(in-package #:ethereum-lisp.test)

;;;; A stop requested while the node is busy must still reach the store close
;;;; inside the supervisor's grace period.
;;;;
;;;; docs/evidence/sec5-sigterm-during-heal.txt records the live observation
;;;; these tests reproduce: a Hoodi node in the middle of a snap heal walk was
;;;; SIGKILLed 30 s after SIGTERM, with its HTTP listeners closed and its store
;;;; never closed.

(defvar *devnet-shutdown-deadline-last-measurement* nil
  "The last reproduction's timings, kept for the evidence record.")

(defun devnet-shutdown-deadline-temp-directory (name)
  (merge-pathnames
   (make-pathname
    :directory `(:relative ,(format nil "ethereum-lisp-~A-~A" name (gensym))))
   #P"/private/tmp/"))

(defun devnet-shutdown-deadline-seconds-since (start)
  (/ (- (get-internal-real-time) start)
     (float internal-time-units-per-second 1d0)))

(defun devnet-shutdown-deadline-rocksdb-closes (directory)
  "How many times RocksDB's info LOG under DIRECTORY records a completed close.

\"Shutdown complete\" is written by DBImpl::CloseHelper and nowhere else, so it
is RocksDB's own record that rocksdb_close ran. Returns NIL without a LOG."
  (let ((log (probe-file (merge-pathnames "LOG" directory))))
    (when log
      (let ((text (with-open-file (stream log :external-format :latin-1)
                    (let ((string (make-string (file-length stream))))
                      (subseq string 0 (read-sequence string stream))))))
        (values
         (loop with start = 0
               for found = (search "Shutdown complete" text :start2 start)
               while found
               count t
               do (setf start (1+ found)))
         (and (search "RocksDB version" text) t))))))

(defun devnet-shutdown-deadline-distinct-trie (depth)
  "Return (VALUES ROOT RECORDS) for a full 16-ary account trie of DEPTH levels.

Every leaf holds a distinct account, so no subtree is shared and the healer's
completion proofs cannot skip any of it: a local walk visits every node once.
Depth four is 69,905 nodes, every one of them present locally."
  (let ((records '())
        (balance 0))
    (labels ((build (level)
               (let ((encoded
                       (if (= level depth)
                           (rlp-encode
                            (make-rlp-list
                             (ethereum-lisp.trie.encoding:hex-prefix-encode
                              (make-array (- 64 depth) :initial-element 7)
                              :terminator t)
                             (state-account-rlp
                              (make-state-account :nonce 1
                                                  :balance (incf balance)))))
                           (rlp-encode
                            (apply #'make-rlp-list
                                   (append
                                    (loop repeat 16 collect (build (1+ level)))
                                    (list (make-byte-vector 0))))))))
                 (let ((hash (keccak-256 encoded)))
                   (push (cons hash encoded) records)
                   hash))))
      (let ((root (build 0)))
        (values root records)))))

(defun devnet-shutdown-deadline-heal-progress (root seed)
  (ethereum-lisp.snap-sync::snap-sync-make-progress
   :pivot-hash (make-hash32 (snap-test-hash seed))
   :pivot-number 6090 :state-root (make-hash32 root)
   :partial-root +empty-trie-hash+
   :target-hash (make-hash32 (snap-test-hash (+ seed 1)))
   :chain-id 560048
   :genesis-hash (make-hash32 (snap-test-hash (+ seed 2)))
   :authority-id (make-hash32 (snap-test-hash (+ seed 3)))
   :completed-p nil :complete-node-scheme-p t
   :tasks
   (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
    :count 1 :completed-p t)))

(defun devnet-shutdown-deadline-local-only-source ()
  "A heal source for a walk that must never leave the local store."
  (flet ((refuse (&rest arguments)
           (declare (ignore arguments))
           (error "Local heal-walk fixture made a peer request")))
    (ethereum-lisp.snap-sync:make-snap-sync-source
     :account-range #'refuse :storage-ranges #'refuse
     :bytecodes #'refuse :trie-nodes #'refuse)))

#+sbcl
(defun devnet-shutdown-deadline-call-with-overrides (overrides thunk)
  "Call THUNK with each (NAME . FUNCTION) in OVERRIDES installed, then restore."
  (let ((originals
          (mapcar (lambda (override)
                    (cons (car override) (fdefinition (car override))))
                  overrides)))
    (unwind-protect
         (progn
           (dolist (override overrides)
             (setf (fdefinition (car override)) (cdr override)))
           (funcall thunk))
      (dolist (original originals)
        (setf (fdefinition (car original)) (cdr original))))))

#+sbcl
(deftest devnet-stop-during-a-local-heal-walk-reaches-the-store-close-in-time
  (:layer :integration :module :cli :requires-local-sockets t
   :estimated-seconds 20d0)
  ;; The Hoodi stop this reproduces: SIGTERM arrived while the sync coordinator
  ;; was inside a heal walk over a store that already held most of the trie.
  ;; Such a walk is one local pass -- it reaches no peer and no pass boundary,
  ;; so neither HEAL-YIELD-P nor a closed peer socket ever interrupts it. The
  ;; coordinator join waited out its 15 s bound and every later join summed on
  ;; top of that, so the supervisor's 30 s grace ran out before the store
  ;; close.
  ;;
  ;; Here the walk runs over the node's own RocksDB store, on the node's own
  ;; coordinator thread, through the shipped shutdown sequence; only the pass
  ;; body and the disk speed are the fixture's. Each local read batch is slowed
  ;; to 50 ms, which makes this 69,905-node walk take about a minute: the
  ;; regime of a 57 GB store whose reads miss the block cache.
  ;;
  ;; RED before the stop observation (see the evidence file): the stop took
  ;; about 15 s (the coordinator join's timeout, then a terminate), and the
  ;; walk never saw it.
  (multiple-value-bind (root records) (devnet-shutdown-deadline-distinct-trie 4)
    (let* ((path (devnet-shutdown-deadline-temp-directory "sigterm-heal"))
           (batch-name
             'ethereum-lisp.snap-sync::snap-sync-heal-local-node-and-incomplete-batch)
           (real-batch (fdefinition batch-name))
           (lock (sb-thread:make-mutex :name "test-sigterm-heal"))
           (batches 0)
           (batches-at-stop nil)
           (heal-outcome nil)
           (heal-condition nil)
           (server-error nil)
           (stop-started nil)
           (stop-to-return nil)
           (stop-to-close nil)
           (log-closes nil)
           (stderr (make-string-output-stream)))
      (unwind-protect
           (devnet-shutdown-deadline-call-with-overrides
            (list
             (cons batch-name
                   (lambda (&rest arguments)
                     (sb-thread:with-mutex (lock) (incf batches))
                     (sleep 0.05d0)
                     (apply real-batch arguments)))
             (cons 'ethereum-lisp.cli::devnet-node-sync-coordinator-pass
                   (lambda (node)
                     (let ((database
                             (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
                              (ethereum-lisp.cli::devnet-node-store node)))
                           (returned-p nil))
                       (unless heal-outcome
                         (setf heal-outcome :started)
                         (unwind-protect
                              (handler-case
                                  (progn
                                    (ethereum-lisp.snap-sync::snap-sync-heal-state
                                     database
                                     (list
                                      (devnet-shutdown-deadline-local-only-source))
                                     (devnet-shutdown-deadline-heal-progress root 70)
                                     (* 2 1024 1024))
                                    (setf returned-p t))
                                (error (condition)
                                  (setf heal-condition condition)))
                           (setf heal-outcome
                                 (if returned-p :completed :unwound))))))))
            (lambda ()
              (let ((*error-output* stderr))
                (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
                 (lambda ()
                   (let* ((node (ethereum-lisp.cli:make-devnet-node
                                 :genesis-json *eth-sync-paris-genesis-json*
                                 :database-path path :db-engine :rocksdb
                                 :port 0 :public-port 0 :p2p-port 0))
                          (database
                            (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
                             (ethereum-lisp.cli::devnet-node-store node)))
                          (controller
                            (ethereum-lisp.cli::make-devnet-shutdown-controller)))
                     (is (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
                          database))
                     (let ((batch (make-kv-write-batch)))
                       (ethereum-lisp.snap-sync::snap-sync-populate-verified-trie-records-batch
                        database batch records)
                       (ethereum-lisp.snap-sync::snap-sync-populate-incomplete-records-batch
                        batch (mapcar #'car records))
                       (kv-apply-batch database batch))
                     (let ((server
                             (sb-thread:make-thread
                              (lambda ()
                                (handler-case
                                    (let ((*error-output* stderr))
                                      (ethereum-lisp.cli:start-devnet-node
                                       node :shutdown-controller controller))
                                  (serious-condition (condition)
                                    (setf server-error condition))))
                              :name "ethereum-lisp-test-node-server")))
                       (unwind-protect
                            ;; Well inside the walk: twenty batches is about a
                            ;; second of a walk that needs close to a minute.
                            (wait-for-test-condition
                             "heal walk under way" 30
                             (lambda ()
                               (sb-thread:with-mutex (lock) (>= batches 20)))
                             :diagnostics
                             (lambda ()
                               (format nil "batches ~D, heal ~S ~@[~A~], server ~@[~A~]"
                                       batches heal-outcome heal-condition
                                       server-error)))
                         (setf batches-at-stop
                               (sb-thread:with-mutex (lock) batches))
                         ;; Exactly what the SIGTERM handler does.
                         (setf stop-started (get-internal-real-time))
                         (ethereum-lisp.cli:devnet-shutdown-request controller)
                         (sb-thread:join-thread server :timeout 90
                                                       :default :timeout)
                         (setf stop-to-return
                               (devnet-shutdown-deadline-seconds-since
                                stop-started)))))))
                (setf stop-to-close
                      (devnet-shutdown-deadline-seconds-since stop-started))
                (setf log-closes
                      (multiple-value-list
                       (devnet-shutdown-deadline-rocksdb-closes path))))))
        (when (probe-file path)
          (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))
      (let ((stderr-text (get-output-stream-string stderr)))
        (setf *devnet-shutdown-deadline-last-measurement*
              (list :stop-to-return stop-to-return :stop-to-close stop-to-close
                    :batches-at-stop batches-at-stop :batches batches
                    :heal-outcome heal-outcome :log-closes log-closes
                    :stderr stderr-text))
        (format t "~&;; stop-to-return ~,2Fs stop-to-close ~,2Fs batches ~D/~D ~
                   outcome ~S~@[ stderr: ~A~]~%"
                stop-to-return stop-to-close batches-at-stop batches
                heal-outcome
                (and (plusp (length stderr-text)) stderr-text))
        (is (null server-error))
        (is (null heal-condition))
        ;; Positive control: the stop really landed mid-walk. The whole walk is
        ;; 944 batches; one that finished before the stop proves nothing.
        (is (and batches-at-stop (>= batches-at-stop 20)))
        (is (< batches 400))
        (is (eq :unwound heal-outcome))
        ;; The walk saw the stop at a batch boundary: the node returned well
        ;; before the coordinator join's own 15 s bound could have fired.
        (is (and stop-to-return (< stop-to-return 5d0)))
        (is (and stop-to-close (< stop-to-close 20d0)))
        ;; RocksDB itself recorded the close: its LOG (positive control: the
        ;; version line this run wrote) carries exactly one "Shutdown complete".
        (is (second log-closes))
        (is (eql 1 (first log-closes)))
        (is (null (search "abandoned" stderr-text)))))))

#+sbcl
(defun devnet-shutdown-deadline-stuck-worker (name release)
  "A worker that ignores the stop AND a terminate until RELEASE holds T.

WITHOUT-INTERRUPTS defers SB-THREAD:TERMINATE-THREAD exactly as a foreign call
does, which is where a live worker would be stuck: inside RocksDB, or in a
blocking socket call no closeable reaches."
  (sb-thread:make-thread
   (lambda ()
     (handler-case
         (sb-sys:without-interrupts
           (loop until (car release) do (sleep 0.02d0)))
       (serious-condition () nil)))
   :name name))

#+sbcl
(deftest devnet-shutdown-joins-share-one-deadline
  (:layer :unit :module :cli :estimated-seconds 4d0)
  ;; Two workers that will not stop, joined one after the other under one
  ;; budget: the second gets only what the first left, so the sequence ends on
  ;; the deadline and the step after the joins (the store close, in the node)
  ;; still runs on time.
  (let ((release (list nil))
        (threads '()))
    (unwind-protect
         (let* ((first (devnet-shutdown-deadline-stuck-worker
                        "test-stuck-first" release))
                (second (devnet-shutdown-deadline-stuck-worker
                         "test-stuck-second" release))
                (stream (make-string-output-stream))
                (closed-at nil))
           (setf threads (list first second))
           ;; Positive control, and the RED shape: the same two joins each with
           ;; a budget of its own -- the per-join bounds this replaces -- add up
           ;; to twice the budget.
           (let ((started (get-internal-real-time)))
             (is (eq :abandoned
                     (ethereum-lisp.cli::devnet-join-worker-by-deadline
                      first (ethereum-lisp.cli::devnet-shutdown-join-deadline 1)
                      "first" :stream stream)))
             (is (eq :abandoned
                     (ethereum-lisp.cli::devnet-join-worker-by-deadline
                      second (ethereum-lisp.cli::devnet-shutdown-join-deadline 1)
                      "second" :stream stream)))
             (is (>= (devnet-shutdown-deadline-seconds-since started) 2d0)))
           ;; Subject: one shared deadline.
           (let* ((started (get-internal-real-time))
                  (deadline
                    (ethereum-lisp.cli::devnet-shutdown-join-deadline 1))
                  (outcomes
                    (list
                     (ethereum-lisp.cli::devnet-join-worker-by-deadline
                      first deadline "first" :stream stream)
                     (ethereum-lisp.cli::devnet-join-worker-by-deadline
                      second deadline "second" :stream stream))))
             (setf closed-at (devnet-shutdown-deadline-seconds-since started))
             (is (equal '(:abandoned :abandoned) outcomes))
             (is (>= closed-at 1d0))
             (is (< closed-at 1.5d0)))
           (let ((text (get-output-stream-string stream)))
             (is (search "abandoned worker first" text))
             (is (search "abandoned worker second" text)))
           ;; The other outcomes, so the abandoned path is not all it can say.
           (is (eq :absent
                   (ethereum-lisp.cli::devnet-join-worker-by-deadline
                    nil (ethereum-lisp.cli::devnet-shutdown-join-deadline 1)
                    "none")))
           (is (eq :joined
                   (ethereum-lisp.cli::devnet-join-worker-by-deadline
                    (sb-thread:make-thread (lambda () 7) :name "test-quick")
                    (ethereum-lisp.cli::devnet-shutdown-join-deadline 1)
                    "quick")))
           (is (eq :terminated
                   (ethereum-lisp.cli::devnet-join-worker-by-deadline
                    (sb-thread:make-thread
                     (lambda () (handler-case (sleep 30) (serious-condition () nil)))
                     :name "test-terminable")
                    (ethereum-lisp.cli::devnet-shutdown-join-deadline 0.2d0)
                    "terminable"))))
      (setf (car release) t)
      (dolist (thread threads)
        (sb-thread:join-thread thread :timeout 5 :default nil)))))

#+sbcl
(deftest devnet-stuck-workers-do-not-keep-the-node-from-its-store-close
  (:layer :integration :module :cli :requires-local-sockets t
   :estimated-seconds 8d0)
  ;; Through the shipped sequence: a real node whose dialer and discovery
  ;; workers ignore both the stop and a terminate. With a 3 s budget the node
  ;; must return on that budget, report both workers abandoned, and still close
  ;; its RocksDB store.
  ;;
  ;; RED on the previous service.lisp: each join had its own 5 s bound and a
  ;; further 5 s after its terminate, so the two workers alone held the node
  ;; for about 20 s.
  (let* ((path (devnet-shutdown-deadline-temp-directory "stuck-workers"))
         (release (list nil))
         (threads '())
         (budget ethereum-lisp.cli::*devnet-shutdown-join-budget-seconds*)
         (server-error nil)
         (stop-started nil)
         (stop-to-return nil)
         (log-closes nil)
         (stderr (make-string-output-stream)))
    (flet ((stuck (name)
             (let ((thread (devnet-shutdown-deadline-stuck-worker name release)))
               (push thread threads)
               thread)))
      (unwind-protect
           (devnet-shutdown-deadline-call-with-overrides
            (list
             (cons 'ethereum-lisp.cli::devnet-start-dial-scheduler-thread
                   (lambda (&rest arguments)
                     (declare (ignore arguments))
                     (values (stuck "ethereum-lisp-devnet-test-stuck-dialer")
                             nil)))
             (cons 'ethereum-lisp.cli::devnet-start-discovery-thread
                   (lambda (&rest arguments)
                     (declare (ignore arguments))
                     (stuck "ethereum-lisp-devnet-test-stuck-discovery"))))
            (lambda ()
              (setf ethereum-lisp.cli::*devnet-shutdown-join-budget-seconds* 3)
              (let ((*error-output* stderr))
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
                                   (let ((*error-output* stderr))
                                     (ethereum-lisp.cli:start-devnet-node
                                      node :shutdown-controller controller))
                                 (serious-condition (condition)
                                   (setf server-error condition))))
                             :name "ethereum-lisp-test-node-server")))
                     (unwind-protect
                          (wait-for-test-condition
                           "stuck workers started" 10
                           (lambda () (= 2 (length threads))))
                       (setf stop-started (get-internal-real-time))
                       (ethereum-lisp.cli:devnet-shutdown-request controller)
                       (sb-thread:join-thread server :timeout 60 :default nil)
                       (setf stop-to-return
                             (devnet-shutdown-deadline-seconds-since
                              stop-started)))))))
              (setf log-closes
                    (multiple-value-list
                     (devnet-shutdown-deadline-rocksdb-closes path)))))
        (setf ethereum-lisp.cli::*devnet-shutdown-join-budget-seconds* budget)
        (setf (car release) t)
        (dolist (thread threads)
          (sb-thread:join-thread thread :timeout 5 :default nil))
        (when (probe-file path)
          (uiop:delete-directory-tree path :validate t
                                           :if-does-not-exist :ignore))))
    (let ((text (get-output-stream-string stderr)))
      (setf *devnet-shutdown-deadline-last-measurement*
            (list :stop-to-return stop-to-return :log-closes log-closes
                  :stderr text))
      (is (null server-error))
      (is (= 2 (length threads)))
      (is (and stop-to-return (>= stop-to-return 3d0)))
      (is (and stop-to-return (< stop-to-return 5d0)))
      (is (search "abandoned worker dialer" text))
      (is (search "abandoned worker discovery" text))
      (is (second log-closes))
      (is (eql 1 (first log-closes))))))
