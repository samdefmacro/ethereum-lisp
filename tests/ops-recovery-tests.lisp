(in-package #:ethereum-lisp.test)

;;;; Operations: what a node leaves behind when it is killed or stopped mid-work.
;;;;
;;;; Section 10 of docs/gap-analysis/public-testnet-readiness-plan.md asks for
;;;; SIGKILL recovery during active sync, build, reorg and persistence, and for
;;;; SIGTERM deadlines in the phases the earlier stop tests did not reach.
;;;;
;;;; Every SIGKILL test here has the same shape. A child process
;;;; (scripts/ops-crash-worker.lisp) runs one production operation against a
;;;; RocksDB store and publishes its progress to a marker file as it goes. The
;;;; parent waits until the marker shows the operation well under way, SIGKILLs
;;;; the child -- no unwind, no close, the database left open -- and then, in
;;;; this process, reopens the store, checks that what it holds is consistent,
;;;; resumes the operation, and compares the result with a control run of the
;;;; same operation that nobody interrupted.
;;;;
;;;; The RED control of each test is the proof that the kill landed mid-
;;;; operation: the marker counted work before the kill, the marker never says
;;;; the operation finished, and the reopened store holds strictly less than the
;;;; finished operation writes. A kill that landed before the work started or
;;;; after it finished would pass the recovery checks vacuously; those
;;;; assertions are what make it fail instead.

;;; The worker protocol.

(defun ops-recovery-marker-path (workdir)
  (merge-pathnames "marker.sexp" (uiop:ensure-directory-pathname workdir)))

(defun ops-recovery-publish (workdir &rest plist)
  "Atomically replace WORKDIR's marker with PLIST.

Written to a temporary name and renamed over the marker, so the parent never
reads a half-written record: rename(2) replaces the old file in one step."
  (let* ((marker (ops-recovery-marker-path workdir))
         (temporary (merge-pathnames "marker.tmp"
                                     (uiop:ensure-directory-pathname workdir))))
    (with-open-file (out temporary :direction :output :if-exists :supersede
                                   :if-does-not-exist :create)
      (with-standard-io-syntax
        (let ((*print-readably* nil))
          (prin1 plist out)))
      (terpri out)
      (finish-output out))
    (rename-file temporary marker)
    plist))

(defun ops-recovery-read-marker (workdir)
  "The worker's last published plist, or NIL before its first."
  (let ((marker (ops-recovery-marker-path workdir)))
    (when (probe-file marker)
      (ignore-errors
       (with-open-file (in marker)
         (with-standard-io-syntax
           (let ((*read-eval* nil)
                 (*package* (find-package '#:ethereum-lisp.test)))
             (read in nil nil))))))))

(defun ops-recovery-workdir (name)
  (devnet-cli-temp-directory (format nil "ethereum-lisp-ops-~A" name)))

(defun ops-recovery-chain-path (workdir)
  (namestring (merge-pathnames "chain/" (uiop:ensure-directory-pathname workdir))))

(defun ops-recovery-remove-workdir (workdir)
  (uiop:delete-directory-tree (uiop:ensure-directory-pathname workdir)
                              :validate t :if-does-not-exist :ignore))

(defun ops-recovery-worker-log (workdir)
  (let ((path (merge-pathnames "worker.log"
                               (uiop:ensure-directory-pathname workdir))))
    (if (probe-file path)
        (let ((text (devnet-cli-file-string path)))
          (subseq text (max 0 (- (length text) 4000))))
        "")))

#+sbcl
(defun ops-recovery-launch-worker (mode workdir)
  (let ((log (merge-pathnames "worker.log"
                              (uiop:ensure-directory-pathname workdir))))
    (test-launch-program
     (list "sbcl" "--script"
           (namestring (truename "scripts/ops-crash-worker.lisp"))
           mode (namestring workdir))
     :output log :if-output-exists :supersede
     :error-output :output)))

#+sbcl
(defun ops-recovery-wait-for-marker (process workdir label predicate
                                     &key (timeout 120))
  "Wait until the worker's marker satisfies PREDICATE, and return the marker."
  (wait-for-test-condition
   label timeout
   (lambda ()
     (let ((marker (ops-recovery-read-marker workdir)))
       (cond ((and marker (funcall predicate marker)) marker)
             ((getf marker :error)
              (error "Worker failed before ~A: ~A" label (getf marker :error)))
             ((not (ignore-errors (uiop:process-alive-p process)))
              (error "Worker exited before ~A; log:~%~A" label
                     (ops-recovery-worker-log workdir))))))
   :interval-seconds 0.02d0
   :diagnostics (lambda ()
                  (format nil "marker ~S; log:~%~A"
                          (ops-recovery-read-marker workdir)
                          (ops-recovery-worker-log workdir)))))

#+sbcl
(defun ops-recovery-kill-when (process workdir label predicate &key (timeout 120))
  "SIGKILL the worker once its marker satisfies PREDICATE.

Returns the marker read immediately before the kill, the marker left on disk
after it, and the exit status. The kill is SIGKILL, not a stop request: the
child gets no chance to unwind, close RocksDB or finish the batch in hand."
  (let ((before (ops-recovery-wait-for-marker process workdir label predicate
                                              :timeout timeout)))
    (uiop:terminate-process process :urgent t)
    (multiple-value-bind (status exited-p)
        (wait-test-process-with-timeout process 30)
      (unless exited-p
        (error "Worker did not exit after SIGKILL"))
      (values before (ops-recovery-read-marker workdir) status))))

(defun ops-recovery-call-with-overrides (overrides thunk)
  "Call THUNK with each (NAME . FUNCTION) in OVERRIDES installed, then restore."
  (let ((originals (mapcar (lambda (override)
                             (cons (car override) (fdefinition (car override))))
                           overrides)))
    (unwind-protect
         (progn
           (dolist (override overrides)
             (setf (fdefinition (car override)) (cdr override)))
           (funcall thunk))
      (dolist (original originals)
        (setf (fdefinition (car original)) (cdr original))))))

;;; Scenario (a): the SNAP range phase, with a deferred storage plan in flight.

(defmacro with-ops-recovery-snap-settings (&body body)
  "The publication depths and plan bound SNAP-TEST-MID-RANGE-REBASE-ARM uses.

One-nibble depths keep the fixture small while taking the same content-addressed
proof paths as the four-nibble public-network setting."
  `(let ((ethereum-lisp.snap-sync::*snap-sync-deferred-storage-max-works* 8192)
         (ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles* 1)
         (ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles* 1)
         (ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
           2))
     ,@body))

(defun ops-recovery-snap-state ()
  "The 403-account state of the mid-range rebase fixture and its root.

Three accounts own a forty-slot storage trie that a 350-byte StorageRanges limit
caps, so the range phase records deferred-storage work: a storage plan."
  (multiple-value-bind (before before-root) (snap-test-mid-range-rebase-states)
    (values before before-root)))

(defun ops-recovery-snap-import (database state root &key on-progress)
  (with-ops-recovery-snap-settings
    (ethereum-lisp.snap-sync:snap-sync-import-state
     database
     (snap-test-source
      (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
       (make-memory-key-value-database) state))
     :pivot-hash (make-hash32 (snap-test-hash 31)) :pivot-number 100
     :state-root root :target-hash (make-hash32 (snap-test-hash 31))
     :chain-id 560048 :genesis-hash (make-hash32 (snap-test-hash 33))
     :authority-id (make-hash32 (snap-test-hash 34))
     :byte-limit 350 :max-pages 4000 :on-progress on-progress)))

(defun ops-recovery-state-records (state)
  "Every node of STATE's account and storage tries, as (HASH . ENCODED).

A fresh copy's tries are wholly dirty, so this is the complete node set."
  (loop for trie in (state-db-persistence-tries (state-db-copy state))
        append (mpt-dirty-node-records trie)))

(defun ops-recovery-present-records (database records)
  "How many of RECORDS DATABASE holds, byte for byte."
  (count-if (lambda (record)
              (multiple-value-bind (node present-p)
                  (trie-node-store-get database (car record))
                (and present-p (bytes= node (cdr record)))))
            records))

(defun ops-recovery-worker-snap-range (workdir)
  (let ((database (make-rocksdb-key-value-database
                   (ops-recovery-chain-path workdir)))
        (pages 0))
    (multiple-value-bind (state root) (ops-recovery-snap-state)
      (ops-recovery-snap-import
       database state root
       :on-progress
       (lambda (progress)
         (declare (ignore progress))
         (incf pages)
         (ops-recovery-publish
          workdir :pages pages
          :deferred (snap-test-durable-deferred-storage-count database root))
         ;; A page is a few milliseconds here; slowed so the parent's kill
         ;; lands inside the range phase rather than after it.
         (sleep 0.2d0)))
      (ops-recovery-publish workdir :pages pages :done t))
    database))

(defun ops-recovery-snap-resume (path state root)
  "Reopen PATH after a crash, record what it held, then finish the import."
  (let ((database (make-rocksdb-key-value-database path)))
    (unwind-protect
         (multiple-value-bind (progress present-p)
             (ethereum-lisp.snap-sync:snap-sync-read-progress database)
           (let* ((records (ops-recovery-state-records state))
                  (before (list
                           :progress-present present-p
                           :completed-before
                           (and present-p
                                (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                                 progress))
                           :deferred-before
                           (snap-test-durable-deferred-storage-count database root)))
                  (final (ops-recovery-snap-import database state root)))
             (append before
                     (list :completed
                           (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                            final)
                           :installed-root
                           (nth-value 0 (kv-get-chain-record
                                         database :state-history
                                         (hash32-bytes
                                          (make-hash32 (snap-test-hash 31)))))
                           :records (length records)
                           :present (ops-recovery-present-records
                                     database records)))))
      (close-rocksdb-key-value-database database))))

#+sbcl
(deftest ops-sigkill-during-snap-range-phase-with-a-storage-plan-resumes
  (:layer :e2e :module :p2p :launches-processes t :estimated-seconds 60d0)
  ;; Kill -9 the SNAP range phase once the deferred-storage plan holds work
  ;; for at least two byte-capped storage tries and a quarter of the 48 pages
  ;; are committed. The reopened store must resume from its durable cursor and
  ;; install the complete state -- every account and storage node of the
  ;; source -- exactly as an uninterrupted import does.
  (let ((workdir (ops-recovery-workdir "snap-range"))
        (control-path (namestring (ops-recovery-workdir "snap-range-control"))))
    (unwind-protect
         (multiple-value-bind (state root) (ops-recovery-snap-state)
           (let ((control
                   (let ((database (make-rocksdb-key-value-database control-path)))
                     (unwind-protect
                          (let* ((records (ops-recovery-state-records state))
                                 (final (ops-recovery-snap-import
                                         database state root)))
                            (list :completed
                                  (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                                   final)
                                  :present (ops-recovery-present-records
                                            database records)
                                  :records (length records)))
                       (close-rocksdb-key-value-database database))))
                 (process (ops-recovery-launch-worker "snap-range" workdir)))
             (multiple-value-bind (before after status)
                 (ops-recovery-kill-when
                  process workdir "the range phase with a storage plan"
                  (lambda (marker)
                    (and (>= (or (getf marker :pages) 0) 12)
                         (>= (or (getf marker :deferred) 0) 2))))
               (let ((resumed (ops-recovery-snap-resume
                               (ops-recovery-chain-path workdir) state root)))
                 (format t "~&;; snap-range kill at ~S, after ~S, status ~S~%;; resumed ~S~%;; control ~S~%"
                         before after status resumed control)
                 ;; RED control: the kill landed inside the range phase.
                 (is (not (getf after :done)))
                 (is (< (getf after :pages) 48))
                 (is (getf resumed :progress-present))
                 (is (not (getf resumed :completed-before)))
                 (is (plusp (getf resumed :deferred-before)))
                 ;; Recovery: the same complete state as the control run.
                 (is (getf control :completed))
                 (is (= (getf control :records) (getf control :present)))
                 (is (getf resumed :completed))
                 (is (bytes= (hash32-bytes root)
                             (let ((installed (getf resumed :installed-root)))
                               (if (typep installed 'hash32)
                                   (hash32-bytes installed)
                                   installed))))
                 (is (= (getf resumed :records) (getf resumed :present)))))))
      (ops-recovery-remove-workdir workdir)
      (ops-recovery-remove-workdir control-path))))

;;; Scenario (b): the state healer, mid-walk.

(defun ops-recovery-heal-state ()
  "A 4,096-account state, its root, and a healthy source serving it.

With 64 KiB responses its heal is fifteen GetTrieNodes round trips, and the
healer flushes what it fetched in 100 KiB batches from the fifth on."
  (let ((state (make-state-db)))
    (loop for index from 1 to 4096
          do (state-db-set-account
              state (snap-test-address-from-integer index)
              (make-state-account :nonce index :balance (+ 5 index))))
    (values state (state-db-root state)
            (snap-test-source
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              (make-memory-key-value-database) state)))))

(defun ops-recovery-heal-progress (root)
  (ethereum-lisp.snap-sync::snap-sync-make-progress
   :pivot-hash (make-hash32 (snap-test-hash 41))
   :pivot-number 7001 :state-root root
   :partial-root +empty-trie-hash+
   :target-hash (make-hash32 (snap-test-hash 42))
   :chain-id 560048
   :genesis-hash (make-hash32 (snap-test-hash 43))
   :authority-id (make-hash32 (snap-test-hash 44))
   :completed-p nil :complete-node-scheme-p t
   :tasks (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
           :count 1 :completed-p t)))

(defun ops-recovery-heal-prepare (database root)
  "Make DATABASE a fresh epoch-seven store whose range phase is done.

The durable progress names ROOT and has every account task complete, so the
next step of a restarted node is the healer, reading this progress back."
  ;; Runs in the worker too, where there is no test to record an assertion.
  (unless (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
           database)
    (error "A fresh store refused the complete-node scheme"))
  (let ((batch (make-kv-write-batch)))
    (ethereum-lisp.snap-sync::snap-sync-populate-progress-batch
     batch (ops-recovery-heal-progress root))
    (kv-apply-batch database batch)))

(defun ops-recovery-heal (database source &key on-request)
  "Heal DATABASE from its own durable progress through SOURCE."
  (multiple-value-bind (progress present-p)
      (ethereum-lisp.snap-sync:snap-sync-read-progress database)
    (unless present-p
      (error "The healer found no durable SNAP progress"))
    (let ((fetched nil))
      (values
       (ethereum-lisp.snap-sync::snap-sync-heal-state
        database
        (list
         (if on-request
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (ethereum-lisp.snap-sync:snap-sync-source-account-range source)
              :storage-ranges
              (ethereum-lisp.snap-sync:snap-sync-source-storage-ranges source)
              :bytecodes (ethereum-lisp.snap-sync:snap-sync-source-bytecodes source)
              :trie-nodes
              (lambda (request)
                (prog1 (funcall (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                                 source)
                                request)
                  (funcall on-request))))
             source))
        progress (* 64 1024)
        :on-heal-progress
        (lambda (event)
          (when (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p event)
            (setf fetched
                  (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                   event)))))
       fetched))))

(defun ops-recovery-heal-summary (database records)
  (multiple-value-bind (progress present-p)
      (ethereum-lisp.snap-sync:snap-sync-read-progress database)
    (list :completed (and present-p
                          (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                           progress))
          :present (ops-recovery-present-records database records)
          :marked (hash-table-count
                   (ethereum-lisp.snap-sync::snap-sync-load-incomplete-nodes
                    database)))))

(defun ops-recovery-worker-heal (workdir)
  (let ((database (make-rocksdb-key-value-database
                   (ops-recovery-chain-path workdir)))
        (requests 0))
    (multiple-value-bind (state root source) (ops-recovery-heal-state)
      (declare (ignore state))
      (ops-recovery-heal-prepare database root)
      (ops-recovery-heal
       database source
       :on-request
       (lambda ()
         (incf requests)
         (ops-recovery-publish
          workdir :requests requests
          ;; The root is in the first flushed batch: once it reads back, part
          ;; of the walk is durable.
          :root-durable (nth-value 1 (trie-node-store-get
                                      database (hash32-bytes root))))
         ;; Slowed so the kill lands inside the walk; a response here is a
         ;; memory read, a live one is a network round trip.
         (sleep 0.1d0)))
      (ops-recovery-publish workdir :requests requests :done t))
    database))

#+sbcl
(deftest ops-sigkill-during-a-heal-walk-resumes-to-the-same-state
  (:layer :e2e :module :p2p :launches-processes t :estimated-seconds 60d0)
  ;; Kill -9 the healer after six of its fifteen GetTrieNodes responses, once
  ;; its first 100 KiB batch of fetched nodes (the root among them) is durable.
  ;; The reopened store must hold a strict, non-empty part of the trie; the
  ;; healer restarted on it from its durable progress must finish with every
  ;; node present, no incomplete marker left and completion published, the
  ;; same end state as a heal nobody interrupted -- and fetch fewer nodes than
  ;; that heal did, because it keeps what the killed run made durable.
  (let ((workdir (ops-recovery-workdir "heal"))
        (control-path (namestring (ops-recovery-workdir "heal-control"))))
    (unwind-protect
         (multiple-value-bind (state root source) (ops-recovery-heal-state)
           (let* ((records (ops-recovery-state-records state))
                  (control
                    (let ((database (make-rocksdb-key-value-database
                                     control-path)))
                      (unwind-protect
                           (progn
                             (ops-recovery-heal-prepare database root)
                             (let ((fetched (nth-value
                                             1 (ops-recovery-heal database source))))
                               (list* :fetched fetched
                                      (ops-recovery-heal-summary database records))))
                        (close-rocksdb-key-value-database database))))
                  (process (ops-recovery-launch-worker "heal" workdir)))
             (multiple-value-bind (before after status)
                 (ops-recovery-kill-when
                  process workdir "six healer responses and a durable flush"
                  (lambda (marker) (and (>= (or (getf marker :requests) 0) 6)
                                        (getf marker :root-durable))))
               (let* ((database (make-rocksdb-key-value-database
                                 (ops-recovery-chain-path workdir)))
                      (crashed nil)
                      (resumed nil))
                 (unwind-protect
                      (progn
                        (setf crashed (ops-recovery-heal-summary database records))
                        (let ((fetched (nth-value
                                        1 (ops-recovery-heal database source))))
                          (setf resumed
                                (list* :fetched fetched
                                       (ops-recovery-heal-summary database records)))))
                   (close-rocksdb-key-value-database database))
                 (format t "~&;; heal kill at ~S, after ~S, status ~S~%;; crashed ~S~%;; resumed ~S~%;; control ~S of ~D~%"
                         before after status crashed resumed control
                         (length records))
                 ;; RED control: the kill landed inside the walk.
                 (is (not (getf after :done)))
                 (is (not (getf crashed :completed)))
                 (is (plusp (getf crashed :present)))
                 (is (< (getf crashed :present) (length records)))
                 ;; Recovery: the control's end state, reached with less work.
                 (is (getf control :completed))
                 (is (= (length records) (getf control :present)))
                 (is (zerop (getf control :marked)))
                 (is (getf resumed :completed))
                 (is (= (length records) (getf resumed :present)))
                 (is (zerop (getf resumed :marked)))
                 (is (and (getf resumed :fetched) (getf control :fetched)
                          (< (getf resumed :fetched) (getf control :fetched))))))))
      (ops-recovery-remove-workdir workdir)
      (ops-recovery-remove-workdir control-path))))

;;; Scenario (c): the forward batch importer, mid-batch.

(defconstant +ops-recovery-forward-blocks+ 24
  "Blocks in the forward batch. At 150 ms a block and a one-second guard hold,
that is four or five durable holds of five or six blocks each.")

(defun ops-recovery-peer-id ()
  (secp256k1-private-key-public-key
   #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee))

(defun ops-recovery-call-with-rocksdb-node (path thunk &rest node-arguments)
  "Call THUNK with a devnet node over the RocksDB store at PATH, then close it."
  (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
   (lambda ()
     (funcall thunk
              (apply #'ethereum-lisp.cli:make-devnet-node
                     :genesis-json *eth-sync-paris-genesis-json*
                     :database-path path :db-engine :rocksdb
                     :port 0 :public-port 0
                     node-arguments)))))

(defun ops-recovery-forward-blocks (node)
  (eth-sync-produce-empty-blocks
   (ethereum-lisp.cli::devnet-node-genesis-block node)
   (ethereum-lisp.cli::devnet-node-config node)
   +ops-recovery-forward-blocks+))

(defun ops-recovery-durable-prefix (node blocks)
  "How many leading BLOCKS NODE holds with state, and whether any later one is.

A forward batch commits whole holds, so what survives a crash must be a prefix:
the second value is true when a block past the prefix is known anyway -- a hole
that only a partially applied hold could leave."
  (let* ((store (ethereum-lisp.cli::devnet-node-store node))
         (prefix (or (position-if-not
                      (lambda (block)
                        (and (chain-store-known-block store (block-hash block))
                             (chain-store-state-available-p
                              store (block-hash block))))
                      blocks)
                     (length blocks))))
    (values prefix
            (some (lambda (block)
                    (chain-store-known-block store (block-hash block)))
                  (nthcdr prefix blocks)))))

(defun ops-recovery-worker-forward-import (workdir)
  (let ((imported 0)
        (name 'ethereum-lisp.block-import:import-p2p-block-candidate))
    (ops-recovery-call-with-rocksdb-node
     (ops-recovery-chain-path workdir)
     (lambda (node)
       (let ((original (fdefinition name))
             (blocks (ops-recovery-forward-blocks node)))
         (ops-recovery-call-with-overrides
          (list (cons name
                      (lambda (&rest arguments)
                        ;; Slowed so the batch spans several guard holds.
                        (sleep 0.15d0)
                        (multiple-value-prog1 (apply original arguments)
                          (ops-recovery-publish workdir
                                                :executed (incf imported))))))
          (lambda ()
            (ethereum-lisp.cli::devnet-peer-sync-import-batch
             node blocks (ops-recovery-peer-id))))
         (ops-recovery-publish workdir :executed imported :done t))))))

(defun ops-recovery-forward-summary (node blocks)
  (let ((store (ethereum-lisp.cli::devnet-node-store node))
        (genesis (ethereum-lisp.cli::devnet-node-genesis-block node)))
    (multiple-value-bind (prefix hole-p) (ops-recovery-durable-prefix node blocks)
      (multiple-value-bind (start parent)
          (ethereum-lisp.cli::devnet-node-peer-sync-resume-point
           node (ops-recovery-peer-id) 0 (block-hash genesis))
        (list :prefix prefix :hole hole-p :resume-start start
              :resume-parent (and parent (hash32-to-hex parent))
              :head-number (chain-store-head-number store)
              :head-hash (hash32-to-hex
                          (chain-store-canonical-hash
                           store (chain-store-head-number store))))))))

#+sbcl
(deftest ops-sigkill-during-a-forward-batch-import-resumes-from-its-cursor
  (:layer :e2e :module :p2p :launches-processes t :estimated-seconds 60d0)
  ;; Kill -9 the forward batch importer after nine of 24 block executions,
  ;; which is inside its second guard hold. The reopened store must hold a
  ;; whole-hold prefix of the batch with state and nothing beyond it, the
  ;; durable peer cursor must name that prefix's tip, and importing the rest
  ;; from the cursor must reach what an uninterrupted import reaches: every
  ;; block executed, the cursor after the last one, the head untouched (a
  ;; forward import never publishes forkchoice).
  (let ((workdir (ops-recovery-workdir "forward"))
        (control-workdir (ops-recovery-workdir "forward-control")))
    (unwind-protect
         (let ((control
                 (ops-recovery-call-with-rocksdb-node
                  (ops-recovery-chain-path control-workdir)
                  (lambda (node)
                    (let ((blocks (ops-recovery-forward-blocks node)))
                      (ethereum-lisp.cli::devnet-peer-sync-import-batch
                       node blocks (ops-recovery-peer-id))
                      (ops-recovery-forward-summary node blocks)))))
               (process (ops-recovery-launch-worker "forward-import" workdir)))
           (multiple-value-bind (before after status)
               (ops-recovery-kill-when
                process workdir "nine block executions"
                (lambda (marker) (>= (or (getf marker :executed) 0) 9)))
             (let (crashed resumed)
               (ops-recovery-call-with-rocksdb-node
                (ops-recovery-chain-path workdir)
                (lambda (node)
                  (let ((blocks (ops-recovery-forward-blocks node)))
                    (setf crashed (ops-recovery-forward-summary node blocks))
                    (let ((start (getf crashed :resume-start)))
                      (ethereum-lisp.cli::devnet-peer-sync-import-batch
                       node (nthcdr (1- start) blocks) (ops-recovery-peer-id)))
                    (setf resumed (ops-recovery-forward-summary node blocks)))))
               (format t "~&;; forward kill at ~S, after ~S, status ~S~%;; crashed ~S~%;; resumed ~S~%;; control ~S~%"
                       before after status crashed resumed control)
               ;; RED control: the kill landed mid-batch, past the first hold.
               (is (not (getf after :done)))
               (is (< (getf after :executed) +ops-recovery-forward-blocks+))
               (is (plusp (getf crashed :prefix)))
               (is (< (getf crashed :prefix) +ops-recovery-forward-blocks+))
               ;; Consistency of what the crash left: a prefix and its cursor.
               (is (not (getf crashed :hole)))
               (is (= (1+ (getf crashed :prefix)) (getf crashed :resume-start)))
               (is (zerop (getf crashed :head-number)))
               ;; Recovery: the control's end state.
               (is (= +ops-recovery-forward-blocks+ (getf control :prefix)))
               (dolist (key '(:prefix :resume-start :resume-parent
                              :head-number :head-hash))
                 (is (equal (getf control key) (getf resumed key))))
               (is (= +ops-recovery-forward-blocks+ (getf resumed :prefix))))))
      (ops-recovery-remove-workdir workdir)
      (ops-recovery-remove-workdir control-workdir))))

;;; Scenarios (d) and (e): a payload build and a reorg in the real node.
;;;
;;; These run the shipped CLI entry point in the child, Engine API over HTTP
;;; with JWT, exactly as a consensus client drives it. The child only adds a
;;; hook at the step the kill must land in: it announces itself on the marker
;;; and then holds that step open.

(defun ops-recovery-write-node-inputs (workdir)
  (let ((directory (uiop:ensure-directory-pathname workdir)))
    (devnet-cli-write-temp-file (merge-pathnames "genesis.json" directory)
                                *eth-sync-paris-genesis-json*)
    (devnet-cli-write-temp-file (merge-pathnames "jwt.hex" directory)
                                +devnet-cli-jwt-secret+)))

(defun ops-recovery-node-arguments (workdir)
  (let ((directory (uiop:ensure-directory-pathname workdir)))
    (list "devnet"
          "--genesis" (namestring (merge-pathnames "genesis.json" directory))
          "--database" (ops-recovery-chain-path workdir)
          "--db.engine" "rocksdb"
          "--engine-port" "0" "--http=false"
          "--authrpc.jwtsecret" (namestring (merge-pathnames "jwt.hex" directory))
          "--ready-file" (namestring (merge-pathnames "ready.json" directory))
          "--json")))

(defparameter *ops-recovery-hold-seconds* 3600
  "How long the worker's hook holds its step open. A kill test never waits it
out; the SIGTERM tests shorten it to a bounded, realistic stall.")

(defun ops-recovery-hold (workdir phase)
  (ops-recovery-publish workdir :phase phase)
  (sleep *ops-recovery-hold-seconds*)
  (ops-recovery-publish workdir :phase phase :released t))

(defun ops-recovery-worker-node (workdir mode)
  "Run the shipped node with MODE's hook installed; return its exit code."
  (let* ((build 'ethereum-lisp.engine-api:engine-rpc-build-viable-prepared-payload)
         (export 'ethereum-lisp.node-store.persistence:node-store-export-forkchoice-to-kv)
         (real-build (fdefinition build))
         (real-export (fdefinition export))
         (overrides
           (ecase mode
             (:build
              (list (cons build
                          (lambda (&rest arguments)
                            (ops-recovery-hold workdir :build)
                            (apply real-build arguments)))))
             (:reorg
              (list (cons export
                          (lambda (store transition database &rest arguments)
                            (when (ethereum-lisp.canonical-chain:canonical-chain-transition-displaced-blocks
                                   transition)
                              (ops-recovery-hold workdir :reorg))
                            (apply real-export store transition database
                                   arguments))))))))
    (ops-recovery-call-with-overrides
     overrides
     (lambda ()
       (ethereum-lisp.cli:main (ops-recovery-node-arguments workdir))))))

(defun ops-recovery-worker-main (mode workdir)
  "The crash worker's entry point: run MODE under WORKDIR, return an exit code."
  (handler-case
      (progn
        ;; Assigned, not bound: the hold runs on an HTTP connection thread,
        ;; which would not see a LET binding made here.
        (when (search "sigterm" mode)
          (setf *ops-recovery-hold-seconds* 8))
        (cond
          ((string= mode "snap-range") (ops-recovery-worker-snap-range workdir))
          ((string= mode "heal") (ops-recovery-worker-heal workdir))
          ((string= mode "forward-import")
           (ops-recovery-worker-forward-import workdir))
          ((member mode '("build" "sigterm-build") :test #'string=)
           (return-from ops-recovery-worker-main
             (ops-recovery-worker-node workdir :build)))
          ((member mode '("reorg" "sigterm-reorg") :test #'string=)
           (return-from ops-recovery-worker-main
             (ops-recovery-worker-node workdir :reorg)))
          (t (error "Unknown ops crash-worker mode ~S" mode)))
        ;; A finished direct-store mode keeps its handles open and waits for
        ;; the parent, which only ever kills it.
        (loop (sleep 3600)))
    (serious-condition (condition)
      (ignore-errors
       (ops-recovery-publish workdir :error (princ-to-string condition)))
      3)))

;;; The Engine client side, in the parent.

(defun ops-recovery-engine-call (endpoint request)
  "Send REQUEST (an alist) to ENDPOINT with a fresh JWT; return the result."
  (let* ((token (engine-rpc-make-jwt-token
                 (hex-to-bytes +devnet-cli-jwt-secret+) (unix-time)))
         (response (devnet-cli-http-endpoint-request
                    endpoint
                    (devnet-cli-json-rpc-http-request (json-encode request)
                                                      :token token)))
         (object (parse-json (devnet-cli-http-body response))))
    (when (fixture-object-field object "error")
      (error "Engine call ~A failed: ~A"
             (fixture-object-field request "method")
             (json-encode (fixture-object-field object "error"))))
    (fixture-object-field object "result")))

(defun ops-recovery-local-call (node request)
  "Handle REQUEST through NODE's Engine service in this process."
  (let ((response (ethereum-lisp.rpc:rpc-handle-request
                   request
                   (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                    (ethereum-lisp.cli::devnet-node-service node)))))
    (when (fixture-object-field response "error")
      (error "Engine call ~A failed: ~S"
             (fixture-object-field request "method")
             (fixture-object-field response "error")))
    (fixture-object-field response "result")))

(defun ops-recovery-new-payload-request (block)
  (devnet-cli-engine-new-payload-v1-request
   1 (execution-payload-envelope-execution-payload
      (block-to-executable-data block))))

(defun ops-recovery-status-of (result)
  (or (fixture-object-field result "status")
      (fixture-object-field (fixture-object-field result "payloadStatus")
                            "status")))

(defun ops-recovery-fixture-chain ()
  "Genesis, a three-block branch A and a competing three-block branch B."
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (genesis (ethereum-lisp.cli::devnet-node-genesis-block node))
         (config (ethereum-lisp.cli::devnet-node-config node))
         (a (eth-sync-produce-empty-blocks genesis config 3))
         (b (let ((parent genesis))
              (loop for marker from 91 to 93
                    collect (setf parent (devnet-peer-sync-test-alternate-empty-child
                                          parent config marker))))))
    (values genesis a b)))

(defun ops-recovery-attributes-request (head)
  (devnet-cli-engine-forkchoice-v1-payload-attributes-request
   2 (block-hash head)
   (devnet-cli-payload-attributes-v1 head (zero-address))))

(defun ops-recovery-get-payload-request (payload-id)
  (list (cons "jsonrpc" "2.0") (cons "id" 3)
        (cons "method" "engine_getPayloadV1")
        (cons "params" (list payload-id))))

(defun ops-recovery-chain-summary (node)
  "The restarted node's head and whether its canonical chain is whole.

Consistent means: every canonical number from genesis to the head names a
known block whose parent is the previous canonical block, and the head's state
is available."
  (let* ((store (ethereum-lisp.cli::devnet-node-store node))
         (head-number (chain-store-head-number store))
         (consistent
           (loop with parent = nil
                 for number from 0 to head-number
                 for hash = (chain-store-canonical-hash store number)
                 for block = (and hash (chain-store-known-block store hash))
                 always (and block
                             (or (null parent)
                                 (hash32= parent (block-header-parent-hash
                                                  (block-header block)))))
                 do (setf parent hash))))
    (list :head-number head-number
          :head-hash (hash32-to-hex (chain-store-canonical-hash store head-number))
          :consistent consistent
          :head-state (chain-store-state-available-p
                       store (chain-store-canonical-hash store head-number)))))

#+sbcl
(defun ops-recovery-start-node-worker (mode workdir)
  "Launch the shipped node under MODE and return (VALUES PROCESS ENDPOINT)."
  (ops-recovery-write-node-inputs workdir)
  (let* ((process (ops-recovery-launch-worker mode workdir))
         (ready (merge-pathnames "ready.json"
                                 (uiop:ensure-directory-pathname workdir))))
    (unless (devnet-cli-wait-for-file ready 60)
      (error "Node worker ~A never became ready; log:~%~A" mode
             (ops-recovery-worker-log workdir)))
    (values process
            (fixture-object-field (parse-json (devnet-cli-file-string ready))
                                  "engineEndpoint"))))

#+sbcl
(defun ops-recovery-call-in-thread (endpoint request)
  "Send REQUEST from a thread; return a cell (DONE-P . RESULT-OR-CONDITION)."
  (let ((cell (list nil)))
    (sb-thread:make-thread
     (lambda ()
       ;; Contained: this request is expected to die with its server.
       (handler-case
           (setf (cdr cell) (ops-recovery-engine-call endpoint request))
         (serious-condition (condition) (setf (cdr cell) condition)))
       (setf (car cell) t))
     :name "ops-recovery-engine-client")
    cell))

(defun ops-recovery-build-control (path genesis a)
  "An uninterrupted node's payload for the build the killed node never finished."
  (declare (ignore genesis))
  (ops-recovery-call-with-rocksdb-node
   path
   (lambda (node)
     (ops-recovery-local-call node (ops-recovery-new-payload-request (first a)))
     (ops-recovery-local-call node (engine-fixture-forkchoice-request
                                    1 (block-hash (first a))))
     (let* ((payload-id (fixture-object-field
                         (ops-recovery-local-call
                          node (ops-recovery-attributes-request (first a)))
                         "payloadId"))
            (payload (ops-recovery-local-call
                      node (ops-recovery-get-payload-request payload-id))))
       (list :block-hash (fixture-object-field payload "blockHash")
             :chain (ops-recovery-chain-summary node))))))

#+sbcl
(deftest ops-sigkill-during-a-payload-build-restarts-consistent-and-rebuilds
  (:layer :e2e :module :cli :launches-processes t :requires-local-sockets t
   :estimated-seconds 60d0)
  ;; A real node: newPayload(A1), forkchoiceUpdated(A1), then forkchoiceUpdated
  ;; with payload attributes, and kill -9 while that build runs. The reopened
  ;; store must report the head the node had published (A1) over a whole
  ;; canonical chain, and the consensus client's retry of the same
  ;; forkchoiceUpdated and getPayload must produce exactly the payload an
  ;; uninterrupted node builds.
  (let ((workdir (ops-recovery-workdir "build"))
        (control-workdir (ops-recovery-workdir "build-control")))
    (unwind-protect
         (multiple-value-bind (genesis a) (ops-recovery-fixture-chain)
           (let ((control (ops-recovery-build-control
                           (ops-recovery-chain-path control-workdir) genesis a)))
             (multiple-value-bind (process endpoint)
                 (ops-recovery-start-node-worker "build" workdir)
               (is (string= +payload-status-valid+
                            (ops-recovery-status-of
                             (ops-recovery-engine-call
                              endpoint (ops-recovery-new-payload-request
                                        (first a))))))
               (is (string= +payload-status-valid+
                            (ops-recovery-status-of
                             (ops-recovery-engine-call
                              endpoint (engine-fixture-forkchoice-request
                                        1 (block-hash (first a)))))))
               (let ((call (ops-recovery-call-in-thread
                            endpoint (ops-recovery-attributes-request (first a)))))
                 (multiple-value-bind (before after status)
                     (ops-recovery-kill-when
                      process workdir "the payload build"
                      (lambda (marker) (eq :build (getf marker :phase))))
                   (wait-for-test-condition "the build call to end" 10
                                            (lambda () (car call)))
                   (let (restarted rebuilt)
                     (ops-recovery-call-with-rocksdb-node
                      (ops-recovery-chain-path workdir)
                      (lambda (node)
                        (setf restarted (ops-recovery-chain-summary node))
                        (let ((payload-id
                                (fixture-object-field
                                 (ops-recovery-local-call
                                  node (ops-recovery-attributes-request (first a)))
                                 "payloadId")))
                          (setf rebuilt
                                (fixture-object-field
                                 (ops-recovery-local-call
                                  node (ops-recovery-get-payload-request payload-id))
                                 "blockHash")))))
                     (format t "~&;; build kill at ~S, after ~S, status ~S~%;; restarted ~S rebuilt ~A~%;; control ~S~%"
                             before after status restarted rebuilt control)
                     ;; RED control: the kill landed inside the build; the
                     ;; client never got an answer.
                     (is (not (getf after :released)))
                     (is (typep (cdr call) 'condition))
                     ;; Consistency after the crash.
                     (is (getf restarted :consistent))
                     (is (getf restarted :head-state))
                     (is (= 1 (getf restarted :head-number)))
                     (is (string= (hash32-to-hex (block-hash (first a)))
                                  (getf restarted :head-hash)))
                     ;; Recovery: the retried build equals the control's.
                     (is (equal (getf control :chain) restarted))
                     (is (string= (getf control :block-hash) rebuilt))))))))
      (ops-recovery-remove-workdir workdir)
      (ops-recovery-remove-workdir control-workdir))))

(defun ops-recovery-reorg-control (path a b)
  "An uninterrupted node's chain after A, then B, then forkchoiceUpdated(B3)."
  (ops-recovery-call-with-rocksdb-node
   path
   (lambda (node)
     (dolist (block a)
       (ops-recovery-local-call node (ops-recovery-new-payload-request block)))
     (ops-recovery-local-call node (engine-fixture-forkchoice-request
                                    1 (block-hash (car (last a)))))
     (dolist (block b)
       (ops-recovery-local-call node (ops-recovery-new-payload-request block)))
     (ops-recovery-local-call node (engine-fixture-forkchoice-request
                                    1 (block-hash (car (last b)))))
     (ops-recovery-chain-summary node))))

#+sbcl
(defun ops-recovery-drive-to-reorg (endpoint a b)
  "Extend the child's chain with A, add the competing B, and start the reorg.

Returns the thread cell of the reorging forkchoiceUpdated."
  (dolist (block a)
    (is (string= +payload-status-valid+
                 (ops-recovery-status-of
                  (ops-recovery-engine-call
                   endpoint (ops-recovery-new-payload-request block))))))
  (is (string= +payload-status-valid+
               (ops-recovery-status-of
                (ops-recovery-engine-call
                 endpoint (engine-fixture-forkchoice-request
                           1 (block-hash (car (last a))))))))
  (dolist (block b)
    (is (string= +payload-status-valid+
                 (ops-recovery-status-of
                  (ops-recovery-engine-call
                   endpoint (ops-recovery-new-payload-request block))))))
  (ops-recovery-call-in-thread
   endpoint (engine-fixture-forkchoice-request 1 (block-hash (car (last b))))))

#+sbcl
(deftest ops-sigkill-during-a-reorg-restarts-on-one-branch-and-completes-it
  (:layer :e2e :module :cli :launches-processes t :requires-local-sockets t
   :estimated-seconds 60d0)
  ;; A real node follows branch A to A3, receives the competing B1..B3, and is
  ;; told forkchoiceUpdated(B3). The kill lands after the reorg is decided in
  ;; memory and before its canonical rewrite reaches the store. The reopened
  ;; store must be wholly on one branch -- A3, the last head it made durable --
  ;; and the consensus client's replay of B and forkchoiceUpdated(B3) must end
  ;; on the same head as a node that was never killed.
  (let ((workdir (ops-recovery-workdir "reorg"))
        (control-workdir (ops-recovery-workdir "reorg-control")))
    (unwind-protect
         (multiple-value-bind (genesis a b) (ops-recovery-fixture-chain)
           (declare (ignore genesis))
           (let ((control (ops-recovery-reorg-control
                           (ops-recovery-chain-path control-workdir) a b)))
             (multiple-value-bind (process endpoint)
                 (ops-recovery-start-node-worker "reorg" workdir)
               (let ((call (ops-recovery-drive-to-reorg endpoint a b)))
                 (multiple-value-bind (before after status)
                     (ops-recovery-kill-when
                      process workdir "the reorg's canonical rewrite"
                      (lambda (marker) (eq :reorg (getf marker :phase))))
                   (wait-for-test-condition "the reorg call to end" 10
                                            (lambda () (car call)))
                   (let (restarted resumed)
                     (ops-recovery-call-with-rocksdb-node
                      (ops-recovery-chain-path workdir)
                      (lambda (node)
                        (setf restarted (ops-recovery-chain-summary node))
                        (dolist (block b)
                          (ops-recovery-local-call
                           node (ops-recovery-new-payload-request block)))
                        (ops-recovery-local-call
                         node (engine-fixture-forkchoice-request
                               1 (block-hash (car (last b)))))
                        (setf resumed (ops-recovery-chain-summary node))))
                     (format t "~&;; reorg kill at ~S, after ~S, status ~S~%;; restarted ~S~%;; resumed ~S~%;; control ~S~%"
                             before after status restarted resumed control)
                     ;; RED control: the kill landed inside the reorg.
                     (is (not (getf after :released)))
                     (is (typep (cdr call) 'condition))
                     ;; Consistency: whole, and on branch A.
                     (is (getf restarted :consistent))
                     (is (getf restarted :head-state))
                     (is (string= (hash32-to-hex (block-hash (car (last a))))
                                  (getf restarted :head-hash)))
                     ;; Recovery: the control's head, on branch B.
                     (is (string= (hash32-to-hex (block-hash (car (last b))))
                                  (getf control :head-hash)))
                     (is (equal control resumed))))))))
      (ops-recovery-remove-workdir workdir)
      (ops-recovery-remove-workdir control-workdir))))

;;; SIGTERM deadlines for a build and a reorg in flight.

(defconstant +ops-recovery-sigterm-budget-seconds+ 20
  "The stop budget: well inside the Hoodi gate's `docker stop --time 30`.")

(defun ops-recovery-rocksdb-closes (workdir)
  "How many clean closes the store's current RocksDB info LOG records."
  (devnet-shutdown-deadline-rocksdb-closes
   (uiop:ensure-directory-pathname (ops-recovery-chain-path workdir))))

#+sbcl
(defun ops-recovery-sigterm (process workdir phase)
  "Wait for PHASE to be held open, SIGTERM the node, and time its exit.

Returns (VALUES SECONDS STATUS MARKER-AT-SIGNAL)."
  (let ((marker (ops-recovery-wait-for-marker
                 process workdir (format nil "the ~(~A~) hold" phase)
                 (lambda (marker) (eq phase (getf marker :phase))))))
    (let ((started (monotonic-seconds)))
      (uiop:terminate-process process)
      (let ((status (devnet-cli-wait-process-exit
                     process (+ 10 +ops-recovery-sigterm-budget-seconds+))))
        (values (- (monotonic-seconds) started) status marker)))))

#+sbcl
(deftest ops-sigterm-during-a-payload-build-closes-the-store-in-time
  (:layer :e2e :module :cli :launches-processes t :requires-local-sockets t
   :estimated-seconds 60d0)
  ;; SIGTERM arrives while a forkchoiceUpdated build holds the store guard for
  ;; eight seconds -- longer than the five-second in-flight request drain, so
  ;; the connection is abandoned and the shutdown export has to wait for the
  ;; guard. The node must still exit 0 inside the 20 s budget, with RocksDB's
  ;; own LOG recording exactly one clean close.
  (let ((workdir (ops-recovery-workdir "sigterm-build")))
    (unwind-protect
         (multiple-value-bind (genesis a) (ops-recovery-fixture-chain)
           (declare (ignore genesis))
           (multiple-value-bind (process endpoint)
               (ops-recovery-start-node-worker "sigterm-build" workdir)
             (ops-recovery-engine-call endpoint
                                       (ops-recovery-new-payload-request (first a)))
             (ops-recovery-engine-call endpoint (engine-fixture-forkchoice-request
                                                 1 (block-hash (first a))))
             (let ((call (ops-recovery-call-in-thread
                          endpoint (ops-recovery-attributes-request (first a)))))
               (multiple-value-bind (seconds status marker)
                   (ops-recovery-sigterm process workdir :build)
                 (let ((closes (ops-recovery-rocksdb-closes workdir))
                       (after (ops-recovery-read-marker workdir)))
                   (format t "~&;; sigterm-build stop ~,2Fs status ~S closes ~S marker ~S after ~S~%"
                           seconds status closes marker after)
                   (wait-for-test-condition "the build call to end" 10
                                            (lambda () (car call)))
                   ;; RED control: the stop arrived while the build was held.
                   (is (eq :build (getf marker :phase)))
                   (is (not (getf marker :released)))
                   (is (eql 0 status))
                   (is (< seconds +ops-recovery-sigterm-budget-seconds+))
                   (is (eql 1 closes)))))))
      (ops-recovery-remove-workdir workdir))))

#+sbcl
(deftest ops-sigterm-during-a-reorg-closes-the-store-in-time-on-the-new-branch
  (:layer :e2e :module :cli :launches-processes t :requires-local-sockets t
   :estimated-seconds 60d0)
  ;; SIGTERM arrives while a reorging forkchoiceUpdated holds its canonical
  ;; rewrite open for eight seconds. The node must exit 0 inside the budget
  ;; with one clean RocksDB close, and because the stop waits for the store
  ;; guard rather than cutting the rewrite, the store it closed is on the new
  ;; branch.
  (let ((workdir (ops-recovery-workdir "sigterm-reorg")))
    (unwind-protect
         (multiple-value-bind (genesis a b) (ops-recovery-fixture-chain)
           (declare (ignore genesis))
           (multiple-value-bind (process endpoint)
               (ops-recovery-start-node-worker "sigterm-reorg" workdir)
             (let ((call (ops-recovery-drive-to-reorg endpoint a b)))
               (multiple-value-bind (seconds status marker)
                   (ops-recovery-sigterm process workdir :reorg)
                 (let ((closes (ops-recovery-rocksdb-closes workdir))
                       (restarted nil))
                   (wait-for-test-condition "the reorg call to end" 10
                                            (lambda () (car call)))
                   (ops-recovery-call-with-rocksdb-node
                    (ops-recovery-chain-path workdir)
                    (lambda (node)
                      (setf restarted (ops-recovery-chain-summary node))))
                   (format t "~&;; sigterm-reorg stop ~,2Fs status ~S closes ~S marker ~S restarted ~S~%"
                           seconds status closes marker restarted)
                   (is (eq :reorg (getf marker :phase)))
                   (is (not (getf marker :released)))
                   (is (eql 0 status))
                   (is (< seconds +ops-recovery-sigterm-budget-seconds+))
                   (is (eql 1 closes))
                   (is (getf restarted :consistent))
                   (is (string= (hash32-to-hex (block-hash (car (last b))))
                                (getf restarted :head-hash))))))))
      (ops-recovery-remove-workdir workdir))))
