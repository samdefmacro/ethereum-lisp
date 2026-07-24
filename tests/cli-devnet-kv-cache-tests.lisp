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
