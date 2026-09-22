(in-package #:ethereum-lisp.test)

;;;; Node-lifetime key-value database handle cache.
;;;;
;;;; Reopening a log-structured database replays the whole file, so the devnet
;;;; keeps one handle per output path for as long as the node runs. These tests
;;;; pin the two properties that make that safe: the cache is off unless a node
;;;; lifetime scopes it, and a cached handle produces byte-identical results to
;;;; the reopen-per-write behaviour it replaces.

(defun devnet-kv-cache-temp-path (name)
  (devnet-cli-temp-path name "kvlog"))

(defun devnet-kv-cache-entries (path)
  "Reopen PATH and drain it into an alist sorted by key, for comparison."
  (let* ((database (make-file-key-value-database path))
         (iterator (kv-iterator database))
         (entries '()))
    (loop
      (multiple-value-bind (key value present-p) (funcall iterator)
        (unless present-p (return))
        (push (cons (bytes-to-hex key) (bytes-to-hex value)) entries)))
    (sort entries #'string< :key #'car)))

(defun devnet-kv-cache-delete-if-exists (path)
  (let ((existing (probe-file path)))
    (when existing (delete-file existing))))

(deftest devnet-kv-cache-is-disabled-outside-a-node-lifetime
  ;; The default must stay open-per-write: anything building databases outside
  ;; a node's lifetime keeps the pre-cache behaviour.
  (let ((path (devnet-kv-cache-temp-path "ethereum-lisp-kv-cache-off")))
    (unwind-protect
         (let ((first (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                       (namestring path)))
               (second (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                        (namestring path))))
           (is (null ethereum-lisp.cli::*devnet-cli-kv-database-cache*))
           (is (not (eq first second))))
      (devnet-kv-cache-delete-if-exists path))))

(deftest devnet-kv-cache-reuses-one-handle-per-path
  (let ((first-path (devnet-kv-cache-temp-path "ethereum-lisp-kv-cache-a"))
        (second-path (devnet-kv-cache-temp-path "ethereum-lisp-kv-cache-b")))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (let ((first (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                          (namestring first-path)))
                  (again (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                          (namestring first-path)))
                  (other (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                          (namestring second-path))))
              (is (eq first again))
              (is (not (eq first other))))))
      (devnet-kv-cache-delete-if-exists first-path)
      (devnet-kv-cache-delete-if-exists second-path))))

(deftest devnet-kv-cache-restores-the-enclosing-scope
  (let ((path (devnet-kv-cache-temp-path "ethereum-lisp-kv-cache-scope")))
    (unwind-protect
         (let ((outer ethereum-lisp.cli::*devnet-cli-kv-database-cache*))
           (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
            (lambda ()
              (is (not (null ethereum-lisp.cli::*devnet-cli-kv-database-cache*)))
              (ethereum-lisp.cli::devnet-cli-make-output-kv-database
               (namestring path))))
           (is (eq outer ethereum-lisp.cli::*devnet-cli-kv-database-cache*))
           ;; A non-local exit must restore it too.
           (ignore-errors
            (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
             (lambda () (error "unwind"))))
           (is (eq outer ethereum-lisp.cli::*devnet-cli-kv-database-cache*)))
      (devnet-kv-cache-delete-if-exists path))))

(deftest devnet-kv-cache-drops-a-poisoned-handle
  ;; A handle that failed mid-append refuses every later write and demands a
  ;; reopen. Before the cache, the next write opened a fresh handle and got
  ;; one; the cache has to reproduce that rather than hand back the corpse.
  (let ((path (devnet-kv-cache-temp-path "ethereum-lisp-kv-cache-poison")))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (let ((poisoned
                    (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                     (namestring path))))
              (kv-put poisoned (ascii-to-bytes "k") (ascii-to-bytes "v"))
              (setf (ethereum-lisp.database::file-key-value-database-write-failed-p
                     poisoned)
                    t)
              (is (ethereum-lisp.database:kv-database-reopen-required-p poisoned))
              (let ((replacement
                      (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                       (namestring path))))
                (is (not (eq poisoned replacement)))
                (is (not (ethereum-lisp.database:kv-database-reopen-required-p
                          replacement)))
                ;; The replacement replayed the log, so the acknowledged write
                ;; survived the poisoning.
                (multiple-value-bind (value present-p)
                    (kv-get replacement (ascii-to-bytes "k"))
                  (is present-p)
                  (is (bytes= (ascii-to-bytes "v") value)))))))
      (devnet-kv-cache-delete-if-exists path))))

(deftest devnet-kv-cache-shares-the-import-handle-with-writers
  ;; The import opens the artifact for reading and the rewrite writes it back;
  ;; both must land on one handle, or the rewrite replays the log again.
  (let ((path (devnet-kv-cache-temp-path "ethereum-lisp-kv-cache-import")))
    (unwind-protect
         (progn
           ;; Give the file real content so the existing-database probe accepts
           ;; it (it returns NIL for a missing or empty artifact).
           (kv-put (make-file-key-value-database path)
                   (ascii-to-bytes "seed")
                   (ascii-to-bytes "value"))
           (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
            (lambda ()
              (let* ((imported
                       (ethereum-lisp.cli::devnet-cli-existing-persistence-database
                        (namestring path)))
                     (writer
                       (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                        (namestring path))))
                (is (not (null imported)))
                ;; EXISTING-PERSISTENCE-DATABASE opens through the truename
                ;; while the writer is handed the configured path; the cache
                ;; key has to see through that.
                (is (eq imported writer))))))
      (devnet-kv-cache-delete-if-exists path))))

(deftest devnet-kv-cache-reread-bypasses-the-cache
  ;; The startup check that the export is restartable must keep replaying the
  ;; log. Answering it from the handle that just wrote would assert nothing
  ;; about the disk, so this bypass is load-bearing, not an optimisation.
  (let ((path (devnet-kv-cache-temp-path "ethereum-lisp-kv-cache-reread")))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (let ((cached (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                           (namestring path))))
              (kv-put cached (ascii-to-bytes "k") (ascii-to-bytes "v"))
              (let ((fresh (ethereum-lisp.cli::devnet-cli-reread-kv-database
                            (namestring path))))
                (is (not (eq cached fresh)))
                ;; It replayed the log rather than sharing the table.
                (multiple-value-bind (value present-p)
                    (kv-get fresh (ascii-to-bytes "k"))
                  (is present-p)
                  (is (bytes= (ascii-to-bytes "v") value))))
              ;; ... and re-reading must not evict or replace the live handle.
              (is (eq cached
                      (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                       (namestring path)))))))
      (devnet-kv-cache-delete-if-exists path))))

(deftest devnet-kv-cache-writes-match-reopen-per-write
  ;; The equivalence that licenses the whole change: a run that holds one
  ;; handle open must leave the same durable contents as a run that reopened
  ;; before every write.
  (let ((cached-path (devnet-kv-cache-temp-path "ethereum-lisp-kv-cache-eq-new"))
        (reopened-path (devnet-kv-cache-temp-path "ethereum-lisp-kv-cache-eq-old")))
    (unwind-protect
         (let ((writes '(("alpha" . "one")
                         ("beta" . "two")
                         ("alpha" . "one-updated")
                         ("gamma" . "three"))))
           ;; Reopen before every write: the pre-cache behaviour.
           (dolist (write writes)
             (kv-put (make-file-key-value-database reopened-path)
                     (ascii-to-bytes (car write))
                     (ascii-to-bytes (cdr write))))
           ;; One cached handle for the whole run.
           (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
            (lambda ()
              (dolist (write writes)
                (kv-put (ethereum-lisp.cli::devnet-cli-make-output-kv-database
                         (namestring cached-path))
                        (ascii-to-bytes (car write))
                        (ascii-to-bytes (cdr write))))))
           (let ((cached (devnet-kv-cache-entries cached-path))
                 (reopened (devnet-kv-cache-entries reopened-path)))
             (is (equal reopened cached))
             ;; Guard against both sides being vacuously empty.
             (is (= 3 (length cached)))))
      (devnet-kv-cache-delete-if-exists cached-path)
      (devnet-kv-cache-delete-if-exists reopened-path))))

#+sbcl
(defun devnet-kv-cache-live-node-worker-names (baseline)
  "Names of live node worker threads that were not already running at BASELINE.

Every worker START-DEVNET-NODE spawns -- listeners, RPC connections, txpool,
payload, dial, sync, discovery, metrics, WebSocket -- is named
ethereum-lisp-devnet-* or ethereum-lisp-rpc-http-*."
  (loop for thread in (sb-thread:list-all-threads)
        for name = (sb-thread:thread-name thread)
        when (and name
                  (sb-thread:thread-alive-p thread)
                  (not (member thread baseline))
                  (or (eql 0 (search "ethereum-lisp-devnet-" name))
                      (eql 0 (search "ethereum-lisp-rpc-http-" name))))
          collect name))

#+sbcl
(deftest devnet-kv-cache-closes-the-node-store-once-after-its-workers-stop
  (:layer :integration :module :cli :requires-local-sockets t
   :estimated-seconds 15d0)
  ;; The ordering the exit-fault fix depends on: the node's RocksDB handle is
  ;; closed exactly once, by the cache scope, only after every worker the
  ;; serving node started has stopped, and never while it is serving. Each
  ;; close is observed through KV-CLOSE together with the node workers still
  ;; alive at that instant.
  ;;
  ;; RED before this change: the scope closed nothing, so CLOSES is empty and
  ;; the handle still answers reads after the scope. The worker probe has its
  ;; own positive control below (it must see workers while the node serves),
  ;; so "no workers at close" cannot pass by the probe seeing nothing at all.
  (let* ((path (merge-pathnames
                (make-pathname
                 :directory
                 `(:relative
                   ,(format nil "ethereum-lisp-kv-cache-close-~A" (gensym))))
                #P"/private/tmp/"))
         (baseline (sb-thread:list-all-threads))
         (original (fdefinition 'ethereum-lisp.database:kv-close))
         (closes '())
         (workers-while-serving nil)
         (server-error nil)
         (store-database nil)
         (outer ethereum-lisp.cli::*devnet-cli-kv-database-cache*))
    (unwind-protect
         (progn
           (setf (fdefinition 'ethereum-lisp.database:kv-close)
                 (lambda (database)
                   (push (list database
                               (devnet-kv-cache-live-node-worker-names
                                baseline))
                         closes)
                   (funcall original database)))
           (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
            (lambda ()
              (let* ((node (ethereum-lisp.cli:make-devnet-node
                            :genesis-json *eth-sync-paris-genesis-json*
                            :database-path path :db-engine :rocksdb
                            :port 0 :public-port 0))
                     (controller
                       (ethereum-lisp.cli::make-devnet-shutdown-controller))
                     (server
                       (sb-thread:make-thread
                        (lambda ()
                          (handler-case
                              (ethereum-lisp.cli:start-devnet-node
                               node :shutdown-controller controller)
                            (serious-condition (condition)
                              (setf server-error condition))))
                        :name "ethereum-lisp-test-node-server")))
                (setf store-database
                      (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
                       (ethereum-lisp.cli::devnet-node-store node)))
                (unwind-protect
                     (setf workers-while-serving
                           (wait-for-test-condition
                            "node workers running" 10
                            (lambda ()
                              (devnet-kv-cache-live-node-worker-names
                               baseline))))
                  (ethereum-lisp.cli:devnet-shutdown-request controller)
                  (sb-thread:join-thread server :timeout 60
                                                :default :timeout))
                ;; Still inside the scope: nothing has been closed yet, and the
                ;; export and shutdown event (the last store users) still work.
                (is (null closes))
                (is (typep store-database
                           'ethereum-lisp.database:rocksdb-key-value-database))
                (kv-get store-database #(0))))))
      (setf (fdefinition 'ethereum-lisp.database:kv-close) original)
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t)))
    (is (null server-error))
    (is (eq outer ethereum-lisp.cli::*devnet-cli-kv-database-cache*))
    ;; Positive control for the worker probe.
    (is (consp workers-while-serving))
    ;; Exactly once for the node's store, and once per distinct handle.
    (is (= 1 (count store-database closes :key #'first)))
    (is (= (length closes)
           (length (remove-duplicates (mapcar #'first closes)))))
    ;; Only after every worker had stopped.
    (is (every (lambda (entry) (null (second entry))) closes))
    ;; And it really is closed: a straggler signals instead of faulting.
    (signals ethereum-lisp.database:rocksdb-database-closed-error
      (kv-get store-database #(0)))))
