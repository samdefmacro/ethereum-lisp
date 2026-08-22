(in-package #:ethereum-lisp.snap-sync)

;;;; Verified, resumable snap/1 state import.

(defconstant +snap-sync-progress-version+ 4)
(defconstant +snap-sync-partitioned-progress-version+ 3)
(defconstant +snap-sync-legacy-progress-version+ 2)
(defparameter +snap-sync-progress-identifier+ "snap-state-import")
(defconstant +snap-sync-request-bytes+ (* 2 1024 1024))
(defconstant +snap-sync-pivot-probe-bytes+ (* 4 1024))
(defconstant +snap-sync-storage-accounts-per-request+ 256)
(defconstant +snap-sync-account-task-count+ 16)
(defconstant +snap-sync-heal-paths-per-source+
  +snap-sync-trie-node-lookups-per-request+
  "Maximum healing paths assigned to one source in a concurrent round.")
(defconstant +snap-sync-heal-local-reads-per-batch+ 512
  "Maximum local read width before frontier-aware shrinking.")
(defparameter *snap-sync-heal-local-read-workers* 4
  "Maximum concurrent RocksDB MultiGet calls during local trie healing.")
(defconstant +snap-sync-heal-parallel-read-minimum+ 128
  "Do not pay worker creation overhead below this local read width.")
(defconstant +snap-sync-heal-deferred-storage-target+ 2048
  "Collect this many account storage roots before descending into them.")
(defconstant +snap-sync-heal-codes-per-request+ 2048)
(defconstant +snap-sync-heal-checkpoint-version+ 2)
(defparameter +snap-sync-heal-checkpoint-identifier+
  "snap-state-heal-checkpoint")
(defparameter +snap-sync-healed-subtree-identifier-prefix+
  (ascii-to-bytes "snap-healed-subtree-v1:")
  "Domain-separate durable account-subtree proof keys.")
(defparameter +snap-sync-healed-storage-subtree-identifier-prefix+
  (ascii-to-bytes "snap-healed-storage-subtree-v1:")
  "Domain-separate durable storage-subtree proof keys.")
(defparameter +snap-sync-healed-subtree-value+ #(1)
  "Versioned value for a completely verified content-addressed subtree.")
(defparameter *snap-sync-healed-subtree-prefix-nibbles* 2
  "Account-trie prefix depth whose completed subtrees survive pivot rebases.")
(defconstant +snap-sync-healed-subtrees-per-batch+ 2048
  "Maximum completed subtree proofs published by one durable write batch.")
(defparameter +snap-sync-deferred-storage-identifier-prefix+
  (ascii-to-bytes "snap-deferred-storage-v1:")
  "Prefix for state-root-scoped storage work discovered during range import.")
(defparameter +snap-sync-deferred-storage-plan-prefix+
  (ascii-to-bytes "snap-deferred-storage-plan-v1:")
  "Prefix for the trusted marker that says the deferred work set is complete.")
(defparameter +snap-sync-deferred-storage-value+ #(1)
  "Versioned value shared by deferred storage work and plan markers.")
(defconstant +snap-sync-deferred-storage-max-works+ 8192
  "Maximum direct storage frontier loaded into one resumable heal checkpoint.")
(defconstant +snap-sync-heal-checkpoint-frontier-target+ 4096)
(defconstant +snap-sync-heal-checkpoint-max-works+ 8192)
(defconstant +snap-sync-heal-checkpoint-max-bytes+ (* 4 1024 1024))
(defconstant +snap-sync-heal-checkpoint-max-items+ (* 128 1024))
(defconstant +snap-sync-heal-checkpoint-node-interval+ (* 128 2048)
  "Local-node interval between durable final-healing frontier checkpoints.")
(defparameter *snap-sync-heal-progress-node-interval* 2048
  "Processed-node interval for progress callbacks during local trie reuse.

Remote fetches and completion report immediately.  This checkpoint prevents a
large content-addressed traversal from appearing stalled while it is reusing
durable nodes and issuing no network request; the CLI still owns wall-clock log
throttling.")

(define-condition snap-sync-state-unavailable (error)
  ((request-kind
    :initarg :request-kind
    :reader snap-sync-state-unavailable-request-kind))
  (:report
   (lambda (condition stream)
     (format stream "Snap peer does not have the requested ~A state"
             (snap-sync-state-unavailable-request-kind condition)))))

(define-condition snap-sync-sources-exhausted (error)
  ((phase
    :initarg :phase
    :reader snap-sync-sources-exhausted-phase)
   (failures
    :initarg :failures
    :reader snap-sync-sources-exhausted-failures))
  (:documentation
   "Every source in one finite live-peer snapshot failed before sync finished.

This is a transient source-set result.  It is distinct from local persistence
and merge failures, which remain fatal and are never wrapped in this type.  A
long-running coordinator may therefore retain durable progress, refresh its
live peer snapshot, and retry without hiding local integrity faults.")
  (:report
   (lambda (condition stream)
     (format stream "All snap ~A sources failed: ~{~A~^; ~}"
             (snap-sync-sources-exhausted-phase condition)
             (mapcar #'princ-to-string
                     (snap-sync-sources-exhausted-failures condition))))))

(define-condition snap-sync-heal-yielded (error) ()
  (:documentation
   "The healer yielded at a safe batch boundary to let its coordinator
re-evaluate consensus-authorized target policy. Durable trie records remain
reusable; callers must not treat this local scheduling result as peer fault or
state completion.")
  (:report
   (lambda (condition stream)
     (declare (ignore condition))
     (write-string "Snap healer yielded for target re-evaluation" stream))))

(defun snap-sync-signal-sources-exhausted (phase failures)
  (unless failures
    (error "Snap workers stopped without source-failure evidence"))
  (error 'snap-sync-sources-exhausted
         :phase phase :failures (copy-list failures)))

(defun snap-sync-state-unavailable (request-kind)
  (error 'snap-sync-state-unavailable :request-kind request-kind))

(defstruct (snap-sync-source
            (:constructor make-snap-sync-source
                (&key account-range storage-ranges bytecodes trie-nodes)))
  account-range
  storage-ranges
  bytecodes
  trie-nodes)

(defstruct (snap-sync-account-task
            (:constructor %make-snap-sync-account-task
                (&key start limit next-origin completed-p)))
  start
  limit
  next-origin
  completed-p)

(defstruct (snap-sync-progress
            (:constructor %make-snap-sync-progress
                (&key pivot-hash pivot-number state-root next-origin
                      partial-root target-hash chain-id genesis-hash authority-id
                      completed-p tasks)))
  pivot-hash
  pivot-number
  state-root
  next-origin
  partial-root
  target-hash
  chain-id
  genesis-hash
  authority-id
  completed-p
  tasks)

(defstruct (snap-sync-heal-progress
            (:constructor %make-snap-sync-heal-progress
                (&key processed-nodes reused-nodes fetched-nodes request-count
                      response-bytes completed-p)))
  "One cumulative, observational snapshot of final TrieNodes healing.

PROCESSED-NODES includes decoded inline and hash-addressed trie nodes.
REUSED-NODES counts hash-addressed nodes read from the local database, while
FETCHED-NODES and RESPONSE-BYTES count accepted TrieNodes response blobs.
REQUEST-COUNT includes failover attempts.  None of these counters is durable or
consensus-visible."
  (processed-nodes 0)
  (reused-nodes 0)
  (fetched-nodes 0)
  (request-count 0)
  (response-bytes 0)
  (completed-p nil))

(defun snap-sync-report-heal-progress
    (callback processed-nodes reused-nodes fetched-nodes request-count
     response-bytes completed-p)
  (when callback
    (funcall
     callback
     (%make-snap-sync-heal-progress
      :processed-nodes processed-nodes
      :reused-nodes reused-nodes
      :fetched-nodes fetched-nodes
      :request-count request-count
      :response-bytes response-bytes
      :completed-p completed-p))))

(defun snap-sync-require-hash32 (value label)
  (unless (hash32-p value)
    (error "~A must be a hash32" label))
  value)

(defun snap-sync-account-task
    (&key start limit next-origin completed-p)
  (dolist (entry (list (cons start "Snap task start")
                       (cons limit "Snap task limit")))
    (unless (= 32 (length (ensure-byte-vector (car entry))))
      (error "~A must contain 32 bytes" (cdr entry))))
  (when next-origin
    (unless (= 32 (length (ensure-byte-vector next-origin)))
      (error "Snap task next origin must contain 32 bytes")))
  (when (and completed-p next-origin)
    (error "A completed snap task cannot retain a next origin"))
  (when (and (not completed-p) (null next-origin))
    (error "An incomplete snap task requires a next origin"))
  (when (ethereum-lisp.validation:byte-vector-lexicographic< limit start)
    (error "Snap task limit precedes its start"))
  (when (and next-origin
             (or (ethereum-lisp.validation:byte-vector-lexicographic<
                  next-origin start)
                 (ethereum-lisp.validation:byte-vector-lexicographic<
                  limit next-origin)))
    (error "Snap task next origin is outside its assigned range"))
  (%make-snap-sync-account-task
   :start (copy-seq start) :limit (copy-seq limit)
   :next-origin (and next-origin (copy-seq next-origin))
   :completed-p (not (null completed-p))))

(defun snap-sync-copy-account-task (task)
  (snap-sync-account-task
   :start (snap-sync-account-task-start task)
   :limit (snap-sync-account-task-limit task)
   :next-origin (snap-sync-account-task-next-origin task)
   :completed-p (snap-sync-account-task-completed-p task)))

(defun snap-sync-integer-to-hash-bytes (value)
  (let* ((minimal (integer-to-minimal-bytes value))
         (result (make-byte-vector 32)))
    (unless (<= (length minimal) 32)
      (error "Snap account task boundary exceeds 256 bits"))
    (replace result minimal :start1 (- 32 (length minimal)))
    result))

(defun snap-sync-task-boundaries (&optional (count +snap-sync-account-task-count+))
  "Return COUNT contiguous inclusive partitions of the 256-bit hash space."
  (unless (and (integerp count) (plusp count)
               (<= count +snap-sync-account-task-count+))
    (error "Snap account task count must be between one and ~D"
           +snap-sync-account-task-count+))
  (let ((space (ash 1 256)))
    (loop for index below count
          for start-integer = (floor (* index space) count)
          for end-integer = (1- (floor (* (1+ index) space) count))
          collect
          (cons (snap-sync-integer-to-hash-bytes start-integer)
                (snap-sync-integer-to-hash-bytes end-integer)))))

(defun snap-sync-make-account-tasks
    (&key (count +snap-sync-account-task-count+) next-origin completed-p)
  (let ((cursor (and next-origin (ensure-byte-vector next-origin))))
    (loop for (start . limit) in (snap-sync-task-boundaries count)
          collect
          (cond
            (completed-p
             (snap-sync-account-task
              :start start :limit limit :completed-p t))
            ((and cursor
                  (ethereum-lisp.validation:byte-vector-lexicographic<
                   limit cursor))
             (snap-sync-account-task
              :start start :limit limit :completed-p t))
            (t
             (snap-sync-account-task
              :start start :limit limit
              :next-origin
              (if (and cursor
                       (ethereum-lisp.validation:byte-vector-lexicographic<
                        start cursor))
                  cursor
                  start)))))))

(defun snap-sync-validate-account-tasks (tasks)
  (unless (and (listp tasks)
               (member (length tasks)
                       (list 1 +snap-sync-account-task-count+)))
    (error "Snap progress must contain one or ~D account tasks"
           +snap-sync-account-task-count+))
  (let ((expected-start (make-byte-vector 32)))
    (dolist (task tasks)
      (unless (snap-sync-account-task-p task)
        (error "Snap progress contains a malformed account task"))
      (unless (bytes= expected-start (snap-sync-account-task-start task))
        (error "Snap account tasks are not contiguous"))
      ;; Reconstruct through the public validating constructor.  This catches
      ;; an out-of-range cursor even for task objects supplied internally.
      (snap-sync-copy-account-task task)
      (setf expected-start
            (snap-sync-increment-hash
             (snap-sync-account-task-limit task))))
    (when expected-start
      (error "Snap account tasks do not cover the complete hash space")))
  tasks)

(defun snap-sync-tasks-next-origin (tasks)
  (loop for task in tasks
        unless (snap-sync-account-task-completed-p task)
          return (copy-seq (snap-sync-account-task-next-origin task))))

(defun snap-sync-tasks-completed-p (tasks)
  (every #'snap-sync-account-task-completed-p tasks))

(defun snap-sync-make-progress
    (&key pivot-hash pivot-number state-root next-origin partial-root
          target-hash chain-id genesis-hash authority-id completed-p tasks)
  (snap-sync-require-hash32 pivot-hash "Snap pivot hash")
  (unless (and (integerp pivot-number) (not (minusp pivot-number)))
    (error "Snap pivot number must be non-negative"))
  (snap-sync-require-hash32 state-root "Snap state root")
  (when next-origin
    (unless (= 32 (length (ensure-byte-vector next-origin)))
      (error "Snap next account origin must contain 32 bytes")))
  (snap-sync-require-hash32 partial-root "Snap partial account root")
  (snap-sync-require-hash32 target-hash "Snap consensus target hash")
  (unless (and (integerp chain-id) (not (minusp chain-id)))
    (error "Snap chain id must be non-negative"))
  (snap-sync-require-hash32 genesis-hash "Snap genesis hash")
  (snap-sync-require-hash32 authority-id "Snap authority id")
  (let* ((tasks
           (or tasks
               (snap-sync-make-account-tasks
                :count 1 :next-origin next-origin
                :completed-p completed-p)))
         (tasks (mapcar #'snap-sync-copy-account-task
                        (snap-sync-validate-account-tasks tasks)))
         (derived-next (snap-sync-tasks-next-origin tasks))
         (derived-completed-p (snap-sync-tasks-completed-p tasks)))
    (when (and next-origin (not (bytes= next-origin derived-next)))
      (error "Snap next origin disagrees with its account tasks"))
    ;; A moving snap/1 pivot may finish all flat account ranges before the
    ;; content-addressed trie has been healed to the latest authorized root.
    ;; COMPLETED-P therefore implies completed ranges, but completed ranges do
    ;; not imply a publishable state until PARTIAL-ROOT equals STATE-ROOT.
    (when (and completed-p (not derived-completed-p))
      (error "Completed snap progress retains an unfinished account task"))
    (when (and completed-p (not (hash32= partial-root state-root)))
      (error "Completed snap progress does not reconstruct its state root"))
    (%make-snap-sync-progress
     :pivot-hash pivot-hash
     :pivot-number pivot-number
     :state-root state-root
     :next-origin derived-next
     :partial-root partial-root
     :target-hash target-hash
     :chain-id chain-id
     :genesis-hash genesis-hash
     :authority-id authority-id
     :completed-p completed-p
     :tasks tasks)))

(defun snap-sync-account-task-object (task)
  (make-rlp-list
   (snap-sync-account-task-start task)
   (snap-sync-account-task-limit task)
   (or (snap-sync-account-task-next-origin task) (make-byte-vector 0))
   (if (snap-sync-account-task-completed-p task) 1 0)))

(defun snap-sync-progress-record (progress)
  (rlp-encode
   (make-rlp-list
    +snap-sync-progress-version+
    (hash32-bytes (snap-sync-progress-pivot-hash progress))
    (snap-sync-progress-pivot-number progress)
    (hash32-bytes (snap-sync-progress-state-root progress))
    (or (snap-sync-progress-next-origin progress) (make-byte-vector 0))
    (hash32-bytes (snap-sync-progress-partial-root progress))
    (hash32-bytes (snap-sync-progress-target-hash progress))
    (snap-sync-progress-chain-id progress)
    (hash32-bytes (snap-sync-progress-genesis-hash progress))
    (hash32-bytes (snap-sync-progress-authority-id progress))
    (if (snap-sync-progress-completed-p progress) 1 0)
    (apply #'make-rlp-list
           (mapcar #'snap-sync-account-task-object
                   (snap-sync-progress-tasks progress))))))

(defun snap-sync-rlp-list (value expected label)
  (unless (rlp-list-p value)
    (error "~A must be an RLP list" label))
  (let ((items (rlp-list-items value)))
    (unless (= expected (length items))
      (error "~A must contain ~D fields" label expected))
    items))

(defun snap-sync-rlp-bytes (value length label &key empty-p)
  (unless (byte-vector-p value)
    (error "~A must be RLP bytes" label))
  (unless (or (and empty-p (zerop (length value)))
              (= length (length value)))
    (error "~A must contain ~D bytes~:[~; or be empty~]"
           label length empty-p))
  value)

(defun snap-sync-rlp-uint (value label)
  (unless (byte-vector-p value)
    (error "~A must be RLP bytes" label))
  (when (and (plusp (length value)) (zerop (aref value 0)))
    (error "~A is not minimally encoded" label))
  (bytes-to-integer value))

(defun snap-sync-completion-flag (value label)
  (let ((flag (snap-sync-rlp-uint value label)))
    (unless (member flag '(0 1))
      (error "~A must be zero or one" label))
    (= flag 1)))

(defun snap-sync-account-task-from-object (value)
  (destructuring-bind (start limit next-origin completed)
      (snap-sync-rlp-list value 4 "Snap account task")
    (let* ((completed-p
             (snap-sync-completion-flag
              completed "Snap task completion flag"))
           (next
             (snap-sync-rlp-bytes
              next-origin 32 "Snap task next origin" :empty-p t)))
      (snap-sync-account-task
       :start (snap-sync-rlp-bytes start 32 "Snap task start")
       :limit (snap-sync-rlp-bytes limit 32 "Snap task limit")
       :next-origin (and (plusp (length next)) next)
       :completed-p completed-p))))

(defun snap-sync-progress-common-fields
    (pivot-hash pivot-number state-root partial-root target-hash chain-id
                genesis-hash authority-id)
  (list
   :pivot-hash
   (make-hash32 (snap-sync-rlp-bytes pivot-hash 32 "Snap pivot hash"))
   :pivot-number (snap-sync-rlp-uint pivot-number "Snap pivot number")
   :state-root
   (make-hash32 (snap-sync-rlp-bytes state-root 32 "Snap state root"))
   :partial-root
   (make-hash32 (snap-sync-rlp-bytes partial-root 32 "Snap partial root"))
   :target-hash
   (make-hash32
    (snap-sync-rlp-bytes target-hash 32 "Snap consensus target hash"))
   :chain-id (snap-sync-rlp-uint chain-id "Snap chain id")
   :genesis-hash
   (make-hash32 (snap-sync-rlp-bytes genesis-hash 32 "Snap genesis hash"))
   :authority-id
   (make-hash32 (snap-sync-rlp-bytes authority-id 32 "Snap authority id"))))

(defun snap-sync-progress-from-v2-items (items)
  (destructuring-bind
      (version pivot-hash pivot-number state-root next-origin partial-root
       target-hash chain-id genesis-hash authority-id completed)
      items
    (declare (ignore version))
    (let* ((completed-p
             (snap-sync-completion-flag
              completed "Snap completion flag"))
           (next
             (snap-sync-rlp-bytes
              next-origin 32 "Snap next origin" :empty-p t)))
      (apply #'snap-sync-make-progress
             :next-origin (and (plusp (length next)) next)
             :completed-p completed-p
             (snap-sync-progress-common-fields
              pivot-hash pivot-number state-root partial-root target-hash
              chain-id genesis-hash authority-id)))))

(defun snap-sync-progress-from-v3-items (items)
  (destructuring-bind
      (version pivot-hash pivot-number state-root next-origin partial-root
       target-hash chain-id genesis-hash authority-id completed task-list)
      items
    (declare (ignore version))
    (let* ((completed-p
             (snap-sync-completion-flag
              completed "Snap completion flag"))
           (stored-next
             (snap-sync-rlp-bytes
              next-origin 32 "Snap next origin" :empty-p t))
           (task-items
             (progn
               (unless (rlp-list-p task-list)
                 (error "Snap account tasks must be an RLP list"))
               (rlp-list-items task-list)))
           (tasks (mapcar #'snap-sync-account-task-from-object task-items)))
      (apply #'snap-sync-make-progress
             :next-origin (and (plusp (length stored-next)) stored-next)
             :completed-p completed-p
             :tasks tasks
             (snap-sync-progress-common-fields
              pivot-hash pivot-number state-root partial-root target-hash
              chain-id genesis-hash authority-id)))))

(defun snap-sync-progress-from-record (record)
  (handler-case
      (let* ((value (rlp-decode-one record :max-list-items 32))
             (items
               (progn
                 (unless (rlp-list-p value)
                   (error "Snap sync progress must be an RLP list"))
                 (rlp-list-items value)))
             (version
               (and items
                    (snap-sync-rlp-uint
                     (first items) "Snap progress version"))))
        (cond
          ((= version +snap-sync-legacy-progress-version+)
           (unless (= 11 (length items))
             (error "Legacy snap sync progress must contain 11 fields"))
           (snap-sync-progress-from-v2-items items))
          ((member version
                   (list +snap-sync-partitioned-progress-version+
                         +snap-sync-progress-version+))
           (unless (= 12 (length items))
             (error "Snap sync progress must contain 12 fields"))
           (snap-sync-progress-from-v3-items items))
          (t
           (error "Unsupported snap sync progress version"))))
    (rlp-error (condition)
      (error "Invalid snap sync progress RLP: ~A" condition))))

(defun snap-sync-read-progress (database)
  (multiple-value-bind (record present-p)
      (kv-get-chain-record database :metadata +snap-sync-progress-identifier+)
    (if present-p
        (values (snap-sync-progress-from-record record) t)
        (values nil nil))))

(defun snap-sync-delete-progress (database)
  "Atomically discard a cursor abandoned by a newer CL-authorized target."
  (multiple-value-bind (progress present-p) (snap-sync-read-progress database)
    (declare (ignore progress))
    (multiple-value-bind (checkpoint checkpoint-present-p)
        (kv-get-chain-record
         database :metadata +snap-sync-heal-checkpoint-identifier+)
      (declare (ignore checkpoint))
      (when (or present-p checkpoint-present-p)
        (let ((batch (make-kv-write-batch)))
          (kv-batch-delete-chain-record
           batch :metadata +snap-sync-progress-identifier+)
          (kv-batch-delete-chain-record
           batch :metadata +snap-sync-heal-checkpoint-identifier+)
          (kv-apply-batch database batch))))
    present-p))

(defun snap-sync-populate-progress-batch (batch progress)
  (kv-batch-put-chain-record
   batch :metadata +snap-sync-progress-identifier+
   (snap-sync-progress-record progress))
  batch)

(defun snap-sync-identical-session-p
    (progress pivot-hash pivot-number state-root target-hash chain-id
              genesis-hash authority-id)
  (and (hash32= pivot-hash (snap-sync-progress-pivot-hash progress))
       (= pivot-number (snap-sync-progress-pivot-number progress))
       (hash32= state-root (snap-sync-progress-state-root progress))
       (hash32= target-hash (snap-sync-progress-target-hash progress))
       (= chain-id (snap-sync-progress-chain-id progress))
       (hash32= genesis-hash (snap-sync-progress-genesis-hash progress))
       (hash32= authority-id (snap-sync-progress-authority-id progress))))

(defun snap-sync-increment-hash (bytes)
  "Return the 32-byte successor of BYTES, or NIL after 0xffff...ffff."
  (let ((result (copy-seq (ensure-byte-vector bytes))))
    (unless (= 32 (length result))
      (error "Snap range cursor must contain 32 bytes"))
    (loop for index downfrom 31 to 0
          for next = (1+ (aref result index))
          do (setf (aref result index) (logand next #xff))
          when (< next 256) do (return-from snap-sync-increment-hash result))
    nil))

(defun snap-sync-account-full-rlp (account-data)
  "Expand snap's slim account body to the full consensus trie value."
  (destructuring-bind (nonce balance storage-root code-hash)
      (snap-sync-rlp-list
       (snap-account-data-body account-data) 4 "Snap account body")
    (snap-sync-rlp-uint nonce "Snap account nonce")
    (snap-sync-rlp-uint balance "Snap account balance")
    (let ((storage-root
            (snap-sync-rlp-bytes
             storage-root 32 "Snap account storage root" :empty-p t))
          (code-hash
            (snap-sync-rlp-bytes
             code-hash 32 "Snap account code hash" :empty-p t)))
      (rlp-encode
       (make-rlp-list
        nonce balance
        (if (zerop (length storage-root))
            (hash32-bytes +empty-trie-hash+)
            storage-root)
        (if (zerop (length code-hash))
            (hash32-bytes +empty-code-hash+)
            code-hash))))))

(defun snap-sync-account-entries (response)
  (mapcar
   (lambda (account)
     (cons (copy-seq (snap-account-data-hash account))
           (snap-sync-account-full-rlp account)))
   (snap-account-range-accounts response)))

(defun snap-sync-storage-entries (slots)
  (mapcar
   (lambda (slot)
     (cons (copy-seq (snap-storage-data-hash slot))
           ;; StorageData.Body is already the exact value committed by the
           ;; storage trie. Re-encoding it adds an RLP string wrapper and
           ;; makes every public snap range reconstruct the wrong root.
           (snap-sync-storage-trie-value
            (snap-storage-data-body slot))))
   slots))

(defun snap-sync-open-partial-trie (database root)
  (if (hash32= root +empty-trie-hash+)
      (make-mpt)
      (make-persisted-mpt
       root (lambda (hash) (trie-node-store-get database hash)))))

(defun snap-sync-source-call (function request label)
  (unless (functionp function)
    (error "Snap source does not implement ~A" label))
  (funcall function request))

(defun snap-sync-populate-complete-storage-group
    (database batch storage-root slots)
  "Verify one complete storage group and add its trie nodes to BATCH."
  (let ((entries (snap-sync-storage-entries slots)))
    (when (null entries)
      (error "Snap peer returned an empty group for a non-empty storage root"))
    (mpt-verify-range-proof
     storage-root entries nil :start (make-byte-vector 32))
    (let ((trie (make-mpt)))
      (dolist (entry entries)
        (mpt-put trie (car entry) (cdr entry)))
      (unless (hash32= storage-root (make-hash32 (mpt-root-hash trie)))
        (error "Complete snap storage group did not reconstruct its root"))
      (mpt-populate-dirty-batch batch trie database))))

(defun snap-sync-fetch-storage-commitments
    (database source state-root commitments byte-limit)
  "Fetch non-empty storage tries in bounded snap/1 multi-account requests.

Geth returns a prefix of the requested accounts.  All groups preceding a
proof are complete tries and are persisted eagerly.  The final proved group
was byte-capped and is deliberately deferred to the content-addressed TrieNodes
healing phase.  Completing a large storage trie here can outlive a public
peer's retained pivot and would force the otherwise verified account page to be
retried from its durable cursor.  Healing reuses every node already on disk and
must still reconstruct the exact authorized state root before completion."
  (let ((remaining commitments)
        (deferred '()))
    (loop while remaining
          do (let* ((count
                      (min +snap-sync-storage-accounts-per-request+
                           (length remaining)))
                    (requested (subseq remaining 0 count))
                    (request
                      (make-snap-get-storage-ranges
                       1 (hash32-bytes state-root)
                       (mapcar #'car requested)
                       (make-byte-vector 0) (make-byte-vector 0) byte-limit))
                    (response
                      (snap-sync-source-call
                       (snap-sync-source-storage-ranges source)
                       request "storage ranges"))
                    (groups (snap-storage-ranges-slots response))
                    (proof (snap-storage-ranges-proof response))
                    (received (length groups)))
               (unless (= 1 (snap-storage-ranges-id response))
                 (error "Snap storage response id mismatch"))
               (when (and (null groups) (null proof))
                 (snap-sync-state-unavailable "storage-range"))
               (when (or (zerop received) (> received count))
                 (error "Snap peer returned an invalid storage group count"))
               (let ((complete-count (if proof (1- received) received))
                     (batch (make-kv-write-batch))
                     (nodes '()))
                 (loop for commitment in requested
                       for slots in groups
                       repeat complete-count
                       do (setf nodes
                                (nconc
                                 nodes
                                 (snap-sync-populate-complete-storage-group
                                  database batch (cdr commitment) slots))))
                 (when nodes
                   (kv-apply-batch database batch)
                   (mpt-mark-nodes-persisted nodes)))
                 ;; A proof marks the last returned group as byte-capped.  Do
                 ;; not restart and fully paginate that potentially enormous
                 ;; storage trie inside the account-page transaction.  Its
                 ;; root remains in the verified account value and therefore
                 ;; becomes mandatory work for SNAP-SYNC-HEAL-STATE.
                 ;; Preserve that exact dependency with the verified account
                 ;; page.  Once every account range is durable, final healing
                 ;; can start from this bounded set instead of rediscovering it
                 ;; by traversing the already reconstructed account trie.
                 (when proof
                   (push (nth (1- received) requested) deferred))
                 (setf remaining (nthcdr received remaining))))
    (nreverse deferred)))

(defun snap-sync-page-code-hashes (entries)
  (remove-duplicates
   (loop for entry in entries
         for account = (decode-state-account-rlp (cdr entry))
         for hash = (state-account-code-hash account)
         unless (hash32= hash +empty-code-hash+)
           collect (hash32-bytes hash))
   :test #'bytes=))

(defun snap-sync-page-storage-commitments (entries)
  (loop for entry in entries
        for account = (decode-state-account-rlp (cdr entry))
        for root = (state-account-storage-root account)
        unless (hash32= root +empty-trie-hash+)
          collect (cons (car entry) root)))

(defun snap-sync-fetch-codes (source hashes byte-limit)
  (let ((remaining (mapcar #'copy-seq hashes))
        (codes '()))
    (loop while remaining
          do (let* ((request
                      (make-snap-get-bytecodes 1 remaining byte-limit))
                    (response
                      (snap-sync-source-call
                       (snap-sync-source-bytecodes source)
                       request "bytecodes"))
                    (received (snap-bytecodes-codes response)))
               (unless (= 1 (snap-bytecodes-id response))
                 (error "Snap bytecode response id mismatch"))
               (when (null received)
                 (error "Snap peer omitted requested bytecode"))
               (dolist (code received)
                 (let ((hash (keccak-256 code)))
                   (unless (find hash remaining :test #'bytes=)
                     (error "Snap peer returned unrequested bytecode"))
                   (push (cons hash (copy-seq code)) codes)
                   (setf remaining (delete hash remaining :test #'bytes=))))))
    (nreverse codes)))

(defun snap-sync-populate-code-batch (database batch codes)
  (dolist (entry codes)
    (multiple-value-bind (existing present-p)
        (kv-get-chain-record database :code (car entry))
      (when (and present-p (not (bytes= existing (cdr entry))))
        (error "Snap bytecode collides with an existing content hash"))
      (unless present-p
        (kv-batch-put-chain-record batch :code (car entry) (cdr entry)))))
  batch)

(defun snap-sync-complete-batch (batch progress)
  (kv-batch-put-chain-record
   batch :state-history
   (hash32-bytes (snap-sync-progress-pivot-hash progress))
   (hash32-bytes (snap-sync-progress-state-root progress)))
  (snap-sync-populate-progress-batch batch progress)
  (kv-batch-delete-chain-record
   batch :metadata +snap-sync-heal-checkpoint-identifier+))

(defun snap-sync-progress-with-task-count (progress count)
  "Split legacy linear progress into COUNT disjoint durable account tasks."
  (if (or (= count (length (snap-sync-progress-tasks progress)))
          ;; A single-source caller can finish a previously partitioned public
          ;; import serially.  Only the multi-source upgrade needs to split a
          ;; legacy one-task cursor.
          (and (= count 1)
               (= +snap-sync-account-task-count+
                  (length (snap-sync-progress-tasks progress)))))
      progress
      (progn
        (unless (= 1 (length (snap-sync-progress-tasks progress)))
          (error "Persisted snap progress uses an incompatible task layout"))
        (snap-sync-make-progress
         :pivot-hash (snap-sync-progress-pivot-hash progress)
         :pivot-number (snap-sync-progress-pivot-number progress)
         :state-root (snap-sync-progress-state-root progress)
         :partial-root (snap-sync-progress-partial-root progress)
         :target-hash (snap-sync-progress-target-hash progress)
         :chain-id (snap-sync-progress-chain-id progress)
         :genesis-hash (snap-sync-progress-genesis-hash progress)
         :authority-id (snap-sync-progress-authority-id progress)
         :completed-p (snap-sync-progress-completed-p progress)
         :tasks
         (snap-sync-make-account-tasks
          :count count
          :next-origin (snap-sync-progress-next-origin progress)
          :completed-p (snap-sync-progress-completed-p progress))))))

(defun snap-sync-load-progress
    (database task-count pivot-hash pivot-number state-root target-hash chain-id
              genesis-hash authority-id)
  (multiple-value-bind (existing present-p)
      (snap-sync-read-progress database)
    (let ((progress
            (if present-p
                (progn
                  (unless (snap-sync-identical-session-p
                           existing pivot-hash pivot-number state-root
                           target-hash chain-id genesis-hash authority-id)
                    (error
                     "Persisted snap sync progress belongs to another pivot or authority"))
                  existing)
                (snap-sync-make-progress
                 :pivot-hash pivot-hash :pivot-number pivot-number
                 :state-root state-root :partial-root +empty-trie-hash+
                 :target-hash target-hash :chain-id chain-id
                 :genesis-hash genesis-hash :authority-id authority-id
                 :completed-p nil
                 :tasks (snap-sync-make-account-tasks :count task-count)))))
      (snap-sync-progress-with-task-count progress task-count))))

(defun snap-sync-source-complete-p (source)
  (and (snap-sync-source-p source)
       (every #'functionp
              (list (snap-sync-source-account-range source)
                    (snap-sync-source-storage-ranges source)
                    (snap-sync-source-bytecodes source)
                    (snap-sync-source-trie-nodes source)))))

(defun snap-sync-key-at-most-p (key limit)
  (not (ethereum-lisp.validation:byte-vector-lexicographic< limit key)))

(defstruct (snap-sync-page-result
            (:constructor make-snap-sync-page-result
                (&key task-index origin entries codes deferred-storage
                      next-origin completed-p)))
  task-index
  origin
  entries
  codes
  deferred-storage
  next-origin
  completed-p)

(defun snap-sync-byte-prefix-end (prefix)
  "Return the exclusive lexicographic end key for non-empty byte PREFIX."
  (let ((bytes (copy-seq (ensure-byte-vector prefix))))
    (loop for index downfrom (1- (length bytes)) to 0
          when (< (aref bytes index) #xff)
            do (incf (aref bytes index))
               (return-from snap-sync-byte-prefix-end
                 (subseq bytes 0 (1+ index))))
    (error "Snap metadata prefix has no finite exclusive end key")))

(defun snap-sync-deferred-storage-root-prefix (state-root)
  (concatenate
   'vector +snap-sync-deferred-storage-identifier-prefix+
   (hash32-bytes state-root)))

(defun snap-sync-deferred-storage-identifier
    (state-root account-hash storage-root)
  (unless (and (byte-vector-p account-hash) (= 32 (length account-hash)))
    (error "Deferred snap storage work requires a 32-byte account hash"))
  (concatenate
   'vector (snap-sync-deferred-storage-root-prefix state-root)
   account-hash (hash32-bytes storage-root)))

(defun snap-sync-deferred-storage-plan-identifier (state-root)
  (concatenate
   'vector +snap-sync-deferred-storage-plan-prefix+
   (hash32-bytes state-root)))

(defun snap-sync-populate-deferred-storage-batch
    (batch state-root commitment)
  (kv-batch-put-chain-record
   batch :metadata
   (snap-sync-deferred-storage-identifier
    state-root (car commitment) (cdr commitment))
   +snap-sync-deferred-storage-value+)
  batch)

(defun snap-sync-populate-deferred-storage-plan-batch (batch state-root)
  (kv-batch-put-chain-record
   batch :metadata
   (snap-sync-deferred-storage-plan-identifier state-root)
   +snap-sync-deferred-storage-value+)
  batch)

(defun snap-sync-deferred-storage-plan-present-p (database state-root)
  (multiple-value-bind (value present-p)
      (kv-get-chain-record
       database :metadata
       (snap-sync-deferred-storage-plan-identifier state-root))
    (when (and present-p
               (not (bytes= value +snap-sync-deferred-storage-value+)))
      (ethereum-lisp.validation:storage-fail
       "Persisted snap deferred-storage plan has an unknown version"))
    present-p))

(defun snap-sync-deferred-storage-works (database state-root)
  "Load a bounded, trusted final-healing frontier for STATE-ROOT.

The plan marker is published only with the final verified account-range page.
Without it, callers must use the legacy full-root traversal.  An oversized
frontier also falls back safely instead of creating an uncheckpointable run."
  (unless (snap-sync-deferred-storage-plan-present-p database state-root)
    (return-from snap-sync-deferred-storage-works (values nil nil nil)))
  (let* ((identifier-prefix
           (snap-sync-deferred-storage-root-prefix state-root))
         (start (kv-chain-record-key :metadata identifier-prefix))
         (end
           (kv-chain-record-key
            :metadata (snap-sync-byte-prefix-end identifier-prefix)))
         (expected-length
           (+ (length identifier-prefix) 32 32))
         (works '())
         (overflow-p nil))
    (multiple-value-bind (iterator close-iterator)
        (kv-iterator database :start start :end end)
      (unwind-protect
           (loop
             (multiple-value-bind (key value present-p)
                 (funcall iterator)
               (unless present-p (return))
               (unless (bytes= value +snap-sync-deferred-storage-value+)
                 (ethereum-lisp.validation:storage-fail
                  "Persisted snap deferred-storage work has an unknown version"))
               (let ((identifier
                       (kv-chain-record-key-identifier :metadata key)))
                 (unless (= expected-length (length identifier))
                   (ethereum-lisp.validation:storage-fail
                    "Persisted snap deferred-storage work is malformed"))
                 (push
                  (snap-sync-make-heal-work
                   :storage
                   (subseq identifier (length identifier-prefix)
                           (+ (length identifier-prefix) 32))
                   (make-byte-vector 0)
                   (subseq identifier (+ (length identifier-prefix) 32)))
                  works)
                 (when (> (length works)
                          +snap-sync-deferred-storage-max-works+)
                   (setf overflow-p t)
                   (return)))))
        (when close-iterator
          (funcall close-iterator))))
    (values (and (not overflow-p) (nreverse works)) t overflow-p)))

(defun snap-sync-prepare-account-page
    (database source state-root task-index task byte-limit)
  "Fetch and verify one page without advancing authoritative progress."
  (let* ((origin (snap-sync-account-task-next-origin task))
         (limit (snap-sync-account-task-limit task))
         (request
           (make-snap-get-account-range
            1 (hash32-bytes state-root) origin limit byte-limit))
         (response
           (snap-sync-source-call
            (snap-sync-source-account-range source)
            request "account ranges"))
         (wire-entries (snap-sync-account-entries response))
         (proof (snap-account-range-proof response)))
    (unless (= 1 (snap-account-range-id response))
      (error "Snap account response id mismatch"))
    (when (and (null wire-entries) (null proof))
      (snap-sync-state-unavailable "account-range"))
    ;; Geth's inclusive task limit may produce the first account beyond the
    ;; requested partition.  Verify the complete wire response first, then
    ;; discard that overlap before inserting this task's accounts.
    (if wire-entries
        (mpt-verify-range-proof state-root wire-entries proof :start origin)
        (mpt-verify-range-proof
         state-root wire-entries proof :start origin
         :end (snap-sync-increment-hash limit)))
    (let* ((last-wire (and wire-entries (caar (last wire-entries))))
           (entries
             (remove-if-not
              (lambda (entry) (snap-sync-key-at-most-p (car entry) limit))
              wire-entries))
           (complete-p
             (or (null wire-entries)
                 (null proof)
                 (not
                  (ethereum-lisp.validation:byte-vector-lexicographic<
                   last-wire limit))))
           (last-entry (and entries (caar (last entries))))
           (next-origin
             (and (not complete-p) last-entry
                  (snap-sync-increment-hash last-entry))))
      (when (and (not complete-p) (null next-origin))
        (error "Snap account page did not advance its assigned task"))
      (let ((deferred-storage
              (snap-sync-fetch-storage-commitments
               database source state-root
               (snap-sync-page-storage-commitments entries) byte-limit))
            (code-hashes (snap-sync-page-code-hashes entries)))
        (make-snap-sync-page-result
         :task-index task-index
         :origin (copy-seq origin)
         :entries entries
         :codes (if code-hashes
                    (snap-sync-fetch-codes source code-hashes byte-limit)
                    '())
         :deferred-storage deferred-storage
         :next-origin next-origin
         :completed-p complete-p)))))

(defun snap-sync-replace-task (tasks index replacement)
  (loop for task in tasks
        for position from 0
        collect (if (= position index)
                    replacement
                    (snap-sync-copy-account-task task))))

(defun snap-sync-commit-account-page (database progress result)
  "Commit RESULT's account nodes, code, task cursor, and global root once."
  (let* ((task-index (snap-sync-page-result-task-index result))
         (task (nth task-index (snap-sync-progress-tasks progress))))
    (unless task
      (error "Snap account result names an unknown task"))
    (unless (and (not (snap-sync-account-task-completed-p task))
                 (bytes= (snap-sync-account-task-next-origin task)
                         (snap-sync-page-result-origin result)))
      (error "Snap account result no longer matches its durable task cursor"))
    (let* ((trie
             (snap-sync-open-partial-trie
              database (snap-sync-progress-partial-root progress)))
           (batch (make-kv-write-batch)))
      (dolist (entry (snap-sync-page-result-entries result))
        (mpt-put trie (car entry) (cdr entry)))
      (let* ((nodes (mpt-populate-dirty-batch batch trie database))
             (partial-root (make-hash32 (mpt-root-hash trie)))
             (replacement
               (snap-sync-account-task
                :start (snap-sync-account-task-start task)
                :limit (snap-sync-account-task-limit task)
                :next-origin (snap-sync-page-result-next-origin result)
                :completed-p (snap-sync-page-result-completed-p result)))
             (tasks
               (snap-sync-replace-task
                (snap-sync-progress-tasks progress) task-index replacement))
             (next
               (snap-sync-make-progress
                :pivot-hash (snap-sync-progress-pivot-hash progress)
                :pivot-number (snap-sync-progress-pivot-number progress)
                :state-root (snap-sync-progress-state-root progress)
                :partial-root partial-root
                :target-hash (snap-sync-progress-target-hash progress)
                :chain-id (snap-sync-progress-chain-id progress)
                :genesis-hash (snap-sync-progress-genesis-hash progress)
                :authority-id (snap-sync-progress-authority-id progress)
                ;; Even an equal account-trie root cannot prove that deferred
                ;; byte-capped storage and code dependencies exist locally.
                ;; Only the final content-addressed traversal may install the
                ;; completion/state-history marker.
                :completed-p nil :tasks tasks)))
        (snap-sync-populate-code-batch
         database batch (snap-sync-page-result-codes result))
        (dolist (commitment
                 (snap-sync-page-result-deferred-storage result))
          (snap-sync-populate-deferred-storage-batch
           batch (snap-sync-progress-state-root progress) commitment))
        (when (and (snap-sync-tasks-completed-p tasks)
                   (hash32= partial-root
                            (snap-sync-progress-state-root progress)))
          ;; Every range proof and the locally rebuilt account trie now commit
          ;; to the authorized root.  Publishing this marker in the same batch
          ;; as the last cursor makes the deferred storage set complete: after
          ;; restart, absence of a queue record means there was no such work.
          (snap-sync-populate-deferred-storage-plan-batch
           batch (snap-sync-progress-state-root progress)))
        (snap-sync-populate-progress-batch batch next)
        (kv-apply-batch database batch)
        (mpt-mark-nodes-persisted nodes)
        next))))

(defun snap-sync-next-unfinished-task (progress &optional claimed)
  (loop for task in (snap-sync-progress-tasks progress)
        for index from 0
        unless (or (snap-sync-account-task-completed-p task)
                   (and claimed (gethash index claimed)))
          return (values index (snap-sync-copy-account-task task))))

(defun snap-sync-probe-state-root (source state-root)
  "Verify that SOURCE can serve a compact account range for STATE-ROOT.

The probe is deliberately small and leaves no durable state behind.  An empty
response without a proof is snap/1's normal indication that the peer has
pruned this root; malformed data still fails range-proof verification.  The
continuous coordinator uses this before choosing which CL-authorized header in
its bounded pivot tail will anchor the resumable import."
  (unless (snap-sync-source-p source)
    (error "Snap state probe requires a snap sync source"))
  (snap-sync-require-hash32 state-root "Snap probe state root")
  (let* ((origin (make-byte-vector 32))
         (request
           (make-snap-get-account-range
            1 (hash32-bytes state-root) origin
            (make-byte-vector 32 :initial-element #xff)
            +snap-sync-pivot-probe-bytes+))
         (response
           (snap-sync-source-call
            (snap-sync-source-account-range source)
            request "account ranges"))
         (entries (snap-sync-account-entries response)))
    (unless (= 1 (snap-account-range-id response))
      (error "Snap account probe response id mismatch"))
    (when (and (null entries)
               (null (snap-account-range-proof response)))
      (snap-sync-state-unavailable "account-range"))
    (mpt-verify-range-proof
     state-root entries (snap-account-range-proof response) :start origin)
    t))

(defstruct (snap-sync-heal-work
            (:constructor make-snap-sync-heal-work
                (&key kind account-hash path reference fetched-p marker-state)))
  kind
  account-hash
  path
  reference
  fetched-p
  marker-state)

(defstruct (snap-sync-heal-checkpoint
            (:constructor make-snap-sync-heal-checkpoint
                (&key pivot-hash pivot-number state-root target-hash chain-id
                      genesis-hash authority-id stack processed-nodes
                      reused-nodes fetched-nodes request-count response-bytes)))
  pivot-hash
  pivot-number
  state-root
  target-hash
  chain-id
  genesis-hash
  authority-id
  stack
  processed-nodes
  reused-nodes
  fetched-nodes
  request-count
  response-bytes)

(defstruct (snap-sync-heal-fetch-result
            (:constructor make-snap-sync-heal-fetch-result
                (&key source start end response condition)))
  source
  start
  end
  response
  condition)

(defun snap-sync-heal-reference-p (reference)
  (or (rlp-list-p reference)
      (and (byte-vector-p reference)
           (member (length reference) '(0 32)))))

(defun snap-sync-make-heal-work
    (kind account-hash path reference &key fetched-p marker-state)
  (unless (member kind '(:account :storage))
    (error "Snap heal work has an unknown trie kind"))
  (unless (member marker-state '(nil :armed :inside :complete))
    (error "Snap heal work has an unknown subtree-marker state"))
  (unless (snap-sync-heal-reference-p reference)
    (error "Snap heal work has a malformed child reference"))
  (when (and (eq kind :storage)
             (not (and (byte-vector-p account-hash)
                       (= 32 (length account-hash)))))
    (error "Snap storage heal work requires a 32-byte account hash"))
  (let ((path (ensure-byte-vector path)))
    (when (> (length path) 64)
      (error "Snap trie heal path exceeds a secure-key trie"))
    (unless (every (lambda (nibble) (<= 0 nibble 15)) path)
      (error "Snap trie heal path contains a non-nibble value"))
    (when (and
           (member marker-state '(:armed :complete))
           (not
            (and
             (byte-vector-p reference)
             (= 32 (length reference))
             (case kind
               (:account (null account-hash))
               (:storage
                (and (byte-vector-p account-hash)
                     (= 32 (length account-hash))))))))
      (error "Snap healed-subtree marker work must name a typed hash node"))
    (when (and
           (eq marker-state :inside)
           (not
            (case kind
              (:account (null account-hash))
              (:storage
               (and (byte-vector-p account-hash)
                    (= 32 (length account-hash)))))))
      (error "Snap healed-subtree descendants changed trie identity"))
    (make-snap-sync-heal-work
     :kind kind
     :account-hash (and account-hash (copy-seq account-hash))
     :path (copy-seq path)
     :reference reference
     :fetched-p (not (null fetched-p))
     :marker-state marker-state)))

(defun snap-sync-copy-heal-work (work &key fetched-p)
  (snap-sync-make-heal-work
   (snap-sync-heal-work-kind work)
   (snap-sync-heal-work-account-hash work)
   (snap-sync-heal-work-path work)
   (snap-sync-heal-work-reference work)
   :fetched-p fetched-p
   :marker-state (snap-sync-heal-work-marker-state work)))

(defun snap-sync-heal-deferred-storage-work (account-hash reference)
  "Construct one storage root for the bounded deferred frontier."
  (snap-sync-make-heal-work
   :storage account-hash (make-byte-vector 0) reference))

(defun snap-sync-heal-work-path-set (work)
  (when (eq :complete (snap-sync-heal-work-marker-state work))
    (error "A healed-subtree completion marker is not wire work"))
  (let ((compact
          (ethereum-lisp.trie.encoding:hex-prefix-encode
           (snap-sync-heal-work-path work) :terminator nil)))
    (if (eq :account (snap-sync-heal-work-kind work))
        (list compact)
        (list (snap-sync-heal-work-account-hash work) compact))))

(defun snap-sync-heal-missing-limit (stack-count source-count)
  "Bound one remote missing-path batch by its concurrent source capacity.

Missing work is popped out of the exact DFS frontier only until the response is
made durable, then reinserted in the same order before any checkpoint can be
published.  Coalescing those already-counted works therefore cannot enlarge the
frontier.  The local-read limiter separately counts pending missing work while
reserving room for trie expansion.  Each source receives no more paths than
pinned geth will look up, while independent sources can fill the bounded durable
frontier concurrently."
  (unless (and (integerp stack-count) (not (minusp stack-count)))
    (error "Snap heal frontier count must be a non-negative integer"))
  (unless (and (integerp source-count) (plusp source-count))
    (error "Snap heal source count must be a positive integer"))
  (min +snap-sync-heal-checkpoint-max-works+
       (* #+sbcl source-count #-sbcl 1
          +snap-sync-heal-paths-per-source+)))

(defun snap-sync-heal-local-read-limit
    (stack-count missing-count missing-limit checkpoint-room)
  "Bound one local read batch by progress and worst-case trie expansion.

Each popped external reference can expose at most sixteen children, increasing
the frontier by fifteen works.  Stay within the hard checkpoint bound
throughout the normal soft-target region while retaining a one-item escape for
an already hard-sized frontier whose next node may reduce it."
  (unless (and (integerp stack-count) (not (minusp stack-count))
               (integerp missing-count) (not (minusp missing-count))
               (integerp missing-limit) (> missing-limit missing-count)
               (integerp checkpoint-room) (plusp checkpoint-room))
    (error "Invalid snap heal local read limits"))
  (let ((expansion-room
          (floor
           (max 0
                (- +snap-sync-heal-checkpoint-max-works+ stack-count))
           15)))
    (min +snap-sync-heal-local-reads-per-batch+
         (- missing-limit missing-count)
         checkpoint-room
         (max 1 expansion-room))))

(defun snap-sync-heal-checkpoint-uint (value label)
  (let ((integer (snap-sync-rlp-uint value label)))
    (unless (<= integer #xffffffffffffffff)
      (error "~A exceeds uint64" label))
    integer))

(defun snap-sync-heal-checkpoint-frontier-p (frontier)
  "Return true when FRONTIER can be represented by one durable checkpoint."
  (and frontier
       (<= (length frontier) +snap-sync-heal-checkpoint-max-works+)))

(defun snap-sync-heal-checkpoint-due-p (processed-nodes
                                         last-checkpoint-processed-nodes)
  (>= (- processed-nodes last-checkpoint-processed-nodes)
      +snap-sync-heal-checkpoint-node-interval+))

(defun snap-sync-heal-work-object (work)
  (make-rlp-list
   (ecase (snap-sync-heal-work-kind work)
     (:account 0)
     (:storage 1))
   (or (snap-sync-heal-work-account-hash work) (make-byte-vector 0))
   (snap-sync-heal-work-path work)
   (snap-sync-heal-work-reference work)
   (if (snap-sync-heal-work-fetched-p work) 1 0)
   (ecase (snap-sync-heal-work-marker-state work)
     ((nil) 0)
     (:armed 1)
     (:complete 2)
     (:inside 3))))

(defun snap-sync-heal-work-from-object (value version)
  (destructuring-bind (kind account-hash path reference fetched &optional marker)
      (snap-sync-rlp-list
       value (if (= version 1) 5 6) "Snap heal checkpoint work")
    (let* ((kind-code
             (snap-sync-heal-checkpoint-uint
              kind "Snap heal work kind"))
           (kind
             (case kind-code
               (0 :account)
               (1 :storage)
               (otherwise (error "Snap heal work kind must be zero or one"))))
           (account
             (snap-sync-rlp-bytes
              account-hash 32 "Snap heal work account hash" :empty-p t))
           (path
             (progn
               (unless (byte-vector-p path)
                 (error "Snap heal work path must be RLP bytes"))
               path)))
      (when (and (eq kind :account) (plusp (length account)))
        (error "Snap account heal work cannot carry an account hash"))
      (snap-sync-make-heal-work
       kind (and (plusp (length account)) account) path reference
       :fetched-p
       (snap-sync-completion-flag fetched "Snap heal work fetched flag")
       :marker-state
       (when marker
         (case
             (snap-sync-heal-checkpoint-uint
              marker "Snap heal work subtree-marker state")
           (0 nil)
           (1 :armed)
           (2 :complete)
           (3 :inside)
           (otherwise
            (error "Snap heal work subtree-marker state exceeds three"))))))))

(defun snap-sync-heal-checkpoint-payload (checkpoint)
  (rlp-encode
   (make-rlp-list
    +snap-sync-heal-checkpoint-version+
    (hash32-bytes (snap-sync-heal-checkpoint-pivot-hash checkpoint))
    (snap-sync-heal-checkpoint-pivot-number checkpoint)
    (hash32-bytes (snap-sync-heal-checkpoint-state-root checkpoint))
    (hash32-bytes (snap-sync-heal-checkpoint-target-hash checkpoint))
    (snap-sync-heal-checkpoint-chain-id checkpoint)
    (hash32-bytes (snap-sync-heal-checkpoint-genesis-hash checkpoint))
    (hash32-bytes (snap-sync-heal-checkpoint-authority-id checkpoint))
    (snap-sync-heal-checkpoint-processed-nodes checkpoint)
    (snap-sync-heal-checkpoint-reused-nodes checkpoint)
    (snap-sync-heal-checkpoint-fetched-nodes checkpoint)
    (snap-sync-heal-checkpoint-request-count checkpoint)
    (snap-sync-heal-checkpoint-response-bytes checkpoint)
    (apply #'make-rlp-list
           (mapcar #'snap-sync-heal-work-object
                   (snap-sync-heal-checkpoint-stack checkpoint))))))

(defun snap-sync-heal-checkpoint-record (checkpoint)
  (let* ((payload (snap-sync-heal-checkpoint-payload checkpoint))
         (record
           (rlp-encode
            (make-rlp-list payload (keccak-256 payload)))))
    (when (> (length record) +snap-sync-heal-checkpoint-max-bytes+)
      (error "Snap heal checkpoint exceeds ~D bytes"
             +snap-sync-heal-checkpoint-max-bytes+))
    record))

(defun snap-sync-heal-checkpoint-from-payload (payload)
  (let* ((value
           (rlp-decode-one
            payload :max-depth 70
            :max-list-items +snap-sync-heal-checkpoint-max-works+
            :max-total-items +snap-sync-heal-checkpoint-max-items+
            :max-string-bytes +snap-sync-heal-checkpoint-max-bytes+))
         (items
           (snap-sync-rlp-list value 14 "Snap heal checkpoint")))
    (destructuring-bind
        (version pivot-hash pivot-number state-root target-hash chain-id
         genesis-hash authority-id processed-nodes reused-nodes fetched-nodes
         request-count response-bytes stack-object)
        items
      (let ((version
              (snap-sync-heal-checkpoint-uint
               version "Snap heal checkpoint version")))
        (unless (member version '(1 2))
          (error "Unsupported snap heal checkpoint version"))
      (unless (rlp-list-p stack-object)
        (error "Snap heal checkpoint stack must be an RLP list"))
      (let ((stack-items (rlp-list-items stack-object)))
        (unless (<= 1 (length stack-items)
                    +snap-sync-heal-checkpoint-max-works+)
          (error "Snap heal checkpoint stack is empty or oversized"))
        (make-snap-sync-heal-checkpoint
         :pivot-hash
         (make-hash32
          (snap-sync-rlp-bytes pivot-hash 32 "Snap heal checkpoint pivot"))
         :pivot-number
         (snap-sync-heal-checkpoint-uint
          pivot-number "Snap heal checkpoint pivot number")
         :state-root
         (make-hash32
          (snap-sync-rlp-bytes state-root 32 "Snap heal checkpoint state root"))
         :target-hash
         (make-hash32
          (snap-sync-rlp-bytes target-hash 32 "Snap heal checkpoint target"))
         :chain-id
         (snap-sync-heal-checkpoint-uint
          chain-id "Snap heal checkpoint chain id")
         :genesis-hash
         (make-hash32
          (snap-sync-rlp-bytes
           genesis-hash 32 "Snap heal checkpoint genesis"))
         :authority-id
         (make-hash32
          (snap-sync-rlp-bytes
           authority-id 32 "Snap heal checkpoint authority"))
         :processed-nodes
         (snap-sync-heal-checkpoint-uint
          processed-nodes "Snap heal checkpoint processed nodes")
         :reused-nodes
         (snap-sync-heal-checkpoint-uint
          reused-nodes "Snap heal checkpoint reused nodes")
         :fetched-nodes
         (snap-sync-heal-checkpoint-uint
          fetched-nodes "Snap heal checkpoint fetched nodes")
         :request-count
         (snap-sync-heal-checkpoint-uint
          request-count "Snap heal checkpoint request count")
         :response-bytes
         (snap-sync-heal-checkpoint-uint
          response-bytes "Snap heal checkpoint response bytes")
         :stack
         (mapcar
          (lambda (work)
            (snap-sync-heal-work-from-object work version))
          stack-items)))))))

(defun snap-sync-heal-checkpoint-from-record (record)
  (unless (and (byte-vector-p record)
               (<= (length record) +snap-sync-heal-checkpoint-max-bytes+))
    (error "Snap heal checkpoint record is malformed or oversized"))
  (destructuring-bind (payload checksum)
      (snap-sync-rlp-list
       (rlp-decode-one
        record :max-depth 2 :max-list-items 2 :max-total-items 3
        :max-string-bytes +snap-sync-heal-checkpoint-max-bytes+)
       2 "Snap heal checkpoint envelope")
    (let ((payload
            (progn
              (unless (byte-vector-p payload)
                (error "Snap heal checkpoint payload must be RLP bytes"))
              payload)))
      (unless (bytes=
               (snap-sync-rlp-bytes
                checksum 32 "Snap heal checkpoint checksum")
               (keccak-256 payload))
        (error "Snap heal checkpoint checksum does not match"))
      (snap-sync-heal-checkpoint-from-payload payload))))

(defun snap-sync-heal-checkpoint-matches-progress-p (checkpoint progress)
  (and (hash32= (snap-sync-heal-checkpoint-pivot-hash checkpoint)
                (snap-sync-progress-pivot-hash progress))
       (= (snap-sync-heal-checkpoint-pivot-number checkpoint)
          (snap-sync-progress-pivot-number progress))
       (hash32= (snap-sync-heal-checkpoint-state-root checkpoint)
                (snap-sync-progress-state-root progress))
       (hash32= (snap-sync-heal-checkpoint-target-hash checkpoint)
                (snap-sync-progress-target-hash progress))
       (= (snap-sync-heal-checkpoint-chain-id checkpoint)
          (snap-sync-progress-chain-id progress))
       (hash32= (snap-sync-heal-checkpoint-genesis-hash checkpoint)
                (snap-sync-progress-genesis-hash progress))
       (hash32= (snap-sync-heal-checkpoint-authority-id checkpoint)
                (snap-sync-progress-authority-id progress))))

(defun snap-sync-read-heal-checkpoint (database progress)
  "Read a matching bounded cache record, treating corruption as cache absence."
  (multiple-value-bind (record present-p)
      (kv-get-chain-record
       database :metadata +snap-sync-heal-checkpoint-identifier+)
    (if (not present-p)
        (values nil nil)
        (let ((checkpoint
                (handler-case
                    (snap-sync-heal-checkpoint-from-record record)
                  (error () nil))))
          (if (and checkpoint
                   (snap-sync-heal-checkpoint-matches-progress-p
                    checkpoint progress))
              (values checkpoint t)
              (values nil nil))))))

(defun snap-sync-heal-checkpoint-present-p (database progress)
  "Return true only for a bounded, valid checkpoint matching PROGRESS.

This is the coordinator-facing restart signal.  Corrupt, oversized, or
identity-mismatched cache records remain indistinguishable from absence, so a
caller cannot pin a stale sync target using untrusted metadata."
  (nth-value 1 (snap-sync-read-heal-checkpoint database progress)))

(defun snap-sync-populate-heal-checkpoint-batch
    (batch progress stack processed-nodes reused-nodes fetched-nodes
     request-count response-bytes)
  (unless (snap-sync-heal-checkpoint-frontier-p stack)
    (error "Snap heal checkpoint frontier is empty or oversized"))
  (kv-batch-put-chain-record
   batch :metadata +snap-sync-heal-checkpoint-identifier+
   (snap-sync-heal-checkpoint-record
    (make-snap-sync-heal-checkpoint
     :pivot-hash (snap-sync-progress-pivot-hash progress)
     :pivot-number (snap-sync-progress-pivot-number progress)
     :state-root (snap-sync-progress-state-root progress)
     :target-hash (snap-sync-progress-target-hash progress)
     :chain-id (snap-sync-progress-chain-id progress)
     :genesis-hash (snap-sync-progress-genesis-hash progress)
     :authority-id (snap-sync-progress-authority-id progress)
     :stack stack :processed-nodes processed-nodes
     :reused-nodes reused-nodes :fetched-nodes fetched-nodes
     :request-count request-count :response-bytes response-bytes)))
  batch)

(defun snap-sync-delete-heal-checkpoint-batch (batch)
  (kv-batch-delete-chain-record
   batch :metadata +snap-sync-heal-checkpoint-identifier+)
  batch)

(defun snap-sync-heal-rebased-progress
    (progress pivot-hash pivot-number state-root target-hash)
  "Retarget unfinished flat ranges while retaining their durable cursors.

The caller must establish CL ancestry/authority before using this operation.
The retained partial trie is never published as STATE-ROOT; completed account
ranges enter the healing phase and only a full content-addressed traversal may
mark the rebased progress complete."
  (snap-sync-require-hash32 pivot-hash "Snap rebased pivot hash")
  (snap-sync-require-hash32 state-root "Snap rebased state root")
  (snap-sync-require-hash32 target-hash "Snap rebased target hash")
  (unless (and (integerp pivot-number)
               (>= pivot-number (snap-sync-progress-pivot-number progress)))
    (error "Snap pivot rebase cannot move backwards"))
  (snap-sync-make-progress
   :pivot-hash pivot-hash :pivot-number pivot-number
   :state-root state-root
   :partial-root (snap-sync-progress-partial-root progress)
   :target-hash target-hash
   :chain-id (snap-sync-progress-chain-id progress)
   :genesis-hash (snap-sync-progress-genesis-hash progress)
   :authority-id (snap-sync-progress-authority-id progress)
   :completed-p nil
   :tasks (snap-sync-progress-tasks progress)))

(defun snap-sync-populate-rebased-progress-batch
    (batch progress
     &key pivot-hash pivot-number state-root target-hash
          chain-id genesis-hash authority-id)
  "Retarget PROGRESS and place its durable record in the caller's KV batch.

This is the coordinator primitive for atomically rebasing snap state together
with its CL-authorized skeleton.  No database mutation occurs until the caller
applies BATCH."
  (unless (snap-sync-progress-p progress)
    (error "Snap progress rebase requires a progress record"))
  (unless (and (= chain-id (snap-sync-progress-chain-id progress))
               (hash32= genesis-hash
                        (snap-sync-progress-genesis-hash progress))
               (hash32= authority-id
                        (snap-sync-progress-authority-id progress)))
    (error "Snap progress rebase persistence identity changed"))
  (let ((rebased
          (snap-sync-heal-rebased-progress
           progress pivot-hash pivot-number state-root target-hash)))
    (snap-sync-populate-progress-batch batch rebased)
    (snap-sync-delete-heal-checkpoint-batch batch)
    rebased))

(defun snap-sync-rebase-progress
    (database &key pivot-hash pivot-number state-root target-hash
                   chain-id genesis-hash authority-id)
  "Durably retarget existing snap/1 progress without replaying flat ranges.

This storage-level operation checks database identity and monotonic pivot
height.  A coordinator that also owns a skeleton record should instead place
the returned record in the same batch as its new skeleton metadata."
  (multiple-value-bind (progress present-p) (snap-sync-read-progress database)
    (unless present-p
      (error "Snap progress cannot be rebased before a range is durable"))
    (let ((batch (make-kv-write-batch)))
      (let ((rebased
              (snap-sync-populate-rebased-progress-batch
               batch progress
               :pivot-hash pivot-hash :pivot-number pivot-number
               :state-root state-root :target-hash target-hash
               :chain-id chain-id :genesis-hash genesis-hash
               :authority-id authority-id)))
        (kv-apply-batch database batch)
        rebased))))

(defun snap-sync-call-with-source-failover
    (sources operation on-source-error)
  (let ((errors '()))
    (dolist (source sources)
      (handler-case
          (return-from snap-sync-call-with-source-failover
            (values (funcall operation source) source))
        (ethereum-lisp.validation:storage-error (condition)
          (error condition))
        (serious-condition (condition)
          (push condition errors)
          (when on-source-error
            (funcall on-source-error source condition)))))
    (cond
      ((and errors
            (every (lambda (condition)
                     (typep condition 'snap-sync-state-unavailable))
                   errors))
       (error (first errors)))
      (errors
       (snap-sync-signal-sources-exhausted :healing (nreverse errors)))
      (t
       (error "Snap healing requires a live source")))))

(defun snap-sync-heal-missing-code-hashes (database hashes)
  (let ((seen (make-hash-table :test #'equalp))
        (missing '()))
    ;; Account values are peer-derived.  Reject malformed code commitments
    ;; before they reach either the database key codec or the wire request.
    ;; EQUALP hashes fixed-width octet vectors by content, keeping this scan
    ;; linear while preserving the first-seen order of distinct hashes.
    (dolist (hash hashes)
      (unless (and (byte-vector-p hash) (= 32 (length hash)))
        (error "Snap healing code hash must contain exactly 32 bytes"))
      (unless (nth-value 1 (gethash hash seen))
        (setf (gethash hash seen) t)
        (unless (nth-value 1 (kv-get-chain-record database :code hash))
          (push hash missing))))
    (nreverse missing)))

(defun snap-sync-heal-fetch-codes
    (database sources hashes byte-limit on-source-error)
  (let ((missing (snap-sync-heal-missing-code-hashes database hashes)))
    (when missing
      (multiple-value-bind (codes source)
          (snap-sync-call-with-source-failover
           sources
           (lambda (candidate)
             (snap-sync-fetch-codes candidate missing byte-limit))
           on-source-error)
        (declare (ignore source))
        (let ((batch (make-kv-write-batch)))
          (snap-sync-populate-code-batch database batch codes)
          (kv-apply-batch database batch))))))

(defun snap-sync-heal-request-chunk
    (source missing start end root-bytes byte-limit)
  (handler-case
      (let* ((request
               (make-snap-get-trie-nodes
                1 root-bytes
                (loop for index from start below end
                      collect
                      (snap-sync-heal-work-path-set
                       (aref missing index)))
                byte-limit))
             (packet
               (snap-sync-source-call
                (snap-sync-source-trie-nodes source)
                request "trie nodes")))
        (unless (= 1 (snap-trie-nodes-id packet))
          (error "Snap trie-node response id mismatch"))
        (when (null (snap-trie-nodes-nodes packet))
          (snap-sync-state-unavailable "trie-nodes"))
        (make-snap-sync-heal-fetch-result
         :source source :start start :end end :response packet))
    (serious-condition (condition)
      (make-snap-sync-heal-fetch-result
       :source source :start start :end end :condition condition))))

#+sbcl
(defun snap-sync-heal-request-round
    (sources missing root-bytes byte-limit)
  "Issue at most one disjoint TrieNodes request on each source concurrently."
  (let* ((worker-count (min (length sources) (length missing)))
         (results (make-array worker-count :initial-element nil))
         (threads (make-array worker-count :initial-element nil)))
    (when (zerop worker-count)
      (error "Snap healing requires a live source"))
    (labels ((run-worker (index source start end)
               (setf (aref results index)
                     (snap-sync-heal-request-chunk
                      source missing start end root-bytes byte-limit))))
      (unwind-protect
           (progn
             (dotimes (index worker-count)
               (let* ((worker-index index)
                      (source (nth index sources))
                      (start (floor (* index (length missing)) worker-count))
                      (end
                        (floor
                         (* (1+ index) (length missing)) worker-count)))
                 (if (= worker-count 1)
                     (run-worker worker-index source start end)
                     (setf
                      (aref threads index)
                      (sb-thread:make-thread
                       (lambda ()
                         (run-worker worker-index source start end))
                       :name "snap-sync-heal-worker")))))
             (when (> worker-count 1)
               (loop for index below worker-count
                     for thread = (aref threads index)
                     do (sb-thread:join-thread thread)
                        (setf (aref threads index) nil))))
        ;; A partial thread-creation failure must not leave request workers
        ;; detached from the coordinator.  Peer exchanges have their own
        ;; bounded deadline, so cleanup remains bounded too.
        (loop for thread across threads
              when thread
                do (ignore-errors (sb-thread:join-thread thread)))))
    results))

#-sbcl
(defun snap-sync-heal-request-round
    (sources missing root-bytes byte-limit)
  (let ((source (first sources)))
    (unless source
      (error "Snap healing requires a live source"))
    (vector
     (snap-sync-heal-request-chunk
      source missing 0 (length missing) root-bytes byte-limit))))

(defun snap-sync-heal-round-sources (sources round)
  "Rotate SOURCES so a retained missing slice reaches another peer next ROUND."
  (let ((count (length sources)))
    (cond
      ((<= count 1) (copy-list sources))
      (t
       (unless (and (integerp round) (not (minusp round)))
         (error "Snap healing source round must be a non-negative integer"))
       (let ((offset (mod round count)))
         (append (subseq sources offset) (subseq sources 0 offset)))))))

#+sbcl
(defun snap-sync-heal-parallel-chain-record-batch
    (database kind identifiers workers decoder)
  "Read IDENTIFIERS of KIND concurrently and optionally decode present values.

DECODER receives the original identifier index and encoded value.  Reads,
validation, and decoding remain partitioned into bounded contiguous slices;
the returned encoded, presence, and decoded vectors retain input order."
  (let* ((identifiers (coerce identifiers 'vector))
         (count (length identifiers))
         (worker-count (min workers count))
         (values-by-worker (make-array worker-count :initial-element nil))
         (present-by-worker (make-array worker-count :initial-element nil))
         (decoded-by-worker (make-array worker-count :initial-element nil))
         (conditions (make-array worker-count :initial-element nil))
         (threads (make-array worker-count :initial-element nil)))
    (labels ((start (index)
               (floor (* index count) worker-count))
             (run-worker (index)
               (handler-case
                   (multiple-value-bind (values present)
                       (kv-get-chain-records
                        database kind
                        (subseq identifiers (start index) (start (1+ index))))
                     (let ((decoded
                             (and decoder
                                  (make-array (length values)
                                              :initial-element nil))))
                       (when decoder
                         (dotimes (offset (length values))
                           (when (= 1 (aref present offset))
                             (setf (aref decoded offset)
                                   (funcall decoder
                                            (+ (start index) offset)
                                            (aref values offset))))))
                       (setf (aref values-by-worker index) values
                             (aref present-by-worker index) present
                             (aref decoded-by-worker index) decoded)))
                 (serious-condition (condition)
                   (setf (aref conditions index) condition)))))
      (unwind-protect
           (progn
             (dotimes (index worker-count)
               (let ((worker-index index))
                 (setf
                  (aref threads index)
                  (sb-thread:make-thread
                   (lambda () (run-worker worker-index))
                   :name "snap-sync-heal-local-read-worker"))))
             (dotimes (index worker-count)
               (sb-thread:join-thread (aref threads index))
               (setf (aref threads index) nil)))
        ;; A partial thread-creation failure must not detach readers from the
        ;; database lifetime owned by the coordinator.
        (loop for thread across threads
              when thread
                do (ignore-errors (sb-thread:join-thread thread))))
      (let ((condition (find-if #'identity conditions)))
        (when condition
          (error condition)))
      (let ((values (make-array count :initial-element nil))
            (present (make-array count :element-type 'bit :initial-element 0))
            (decoded
              (and decoder (make-array count :initial-element nil))))
        (dotimes (index worker-count)
          (replace values (aref values-by-worker index) :start1 (start index))
          (replace present (aref present-by-worker index) :start1 (start index))
          (when decoder
            (replace decoded (aref decoded-by-worker index)
                     :start1 (start index))))
        (values values present decoded)))))

(defun snap-sync-heal-chain-record-batch
    (database kind identifiers &key decoder)
  "Read one ordered, bounded chain-record batch and optionally decode it."
  (unless (and (integerp *snap-sync-heal-local-read-workers*)
               (<= 1 *snap-sync-heal-local-read-workers* 16))
    (error "Snap heal local read workers must be between one and 16"))
  #+sbcl
  (when (and
         (typep database 'ethereum-lisp.database:rocksdb-key-value-database)
         (> *snap-sync-heal-local-read-workers* 1)
         (>= (length identifiers) +snap-sync-heal-parallel-read-minimum+))
    (return-from snap-sync-heal-chain-record-batch
      (snap-sync-heal-parallel-chain-record-batch
       database kind identifiers *snap-sync-heal-local-read-workers* decoder)))
  (multiple-value-bind (values present)
      (kv-get-chain-records database kind identifiers)
    (let ((decoded
            (and decoder (make-array (length values) :initial-element nil))))
      (when decoder
        (dotimes (index (length values))
          (when (= 1 (aref present index))
            (setf (aref decoded index)
                  (funcall decoder index (aref values index))))))
      (values values present decoded))))

(defun snap-sync-heal-local-node-batch (database references &key decoder)
  "Read one ordered, bounded local trie-node batch and optionally decode it."
  (snap-sync-heal-chain-record-batch
   database :trie-node references :decoder decoder))

(defun snap-sync-healed-subtree-identifier
    (reference &optional (kind :account))
  (unless (and (byte-vector-p reference) (= 32 (length reference)))
    (error "Snap healed-subtree identifier requires a 32-byte node hash"))
  (concatenate
   'vector
   (ecase kind
     (:account +snap-sync-healed-subtree-identifier-prefix+)
     (:storage +snap-sync-healed-storage-subtree-identifier-prefix+))
   reference))

(defun snap-sync-healed-subtree-present-p
    (database reference &optional (kind :account))
  "Trust only this client's versioned proof that REFERENCE was fully healed."
  (multiple-value-bind (value present-p)
      (kv-get-chain-record
       database :metadata
       (snap-sync-healed-subtree-identifier reference kind))
    (when (and present-p
               (not (bytes= value +snap-sync-healed-subtree-value+)))
      (ethereum-lisp.validation:storage-fail
       "Persisted snap healed-subtree proof has an unknown version"))
    present-p))

(defun snap-sync-healed-subtrees-present
    (database references &optional kinds)
  "Return ordered presence bits for versioned healed-subtree proofs.

The production RocksDB path batches and partitions metadata reads just like
local trie-node reads.  Unknown proof values remain storage corruption rather
than cache misses."
  (let ((kinds
          (or kinds
              (make-array (length references) :initial-element :account))))
    (unless (= (length references) (length kinds))
      (error "Snap healed-subtree references and kinds differ in length"))
    (let ((identifiers
            (map 'vector #'snap-sync-healed-subtree-identifier
                 references kinds)))
      (multiple-value-bind (values present)
          (snap-sync-heal-chain-record-batch database :metadata identifiers)
        (dotimes (index (length references))
          (when (= 1 (aref present index))
            (unless (bytes= (aref values index)
                            +snap-sync-healed-subtree-value+)
              (ethereum-lisp.validation:storage-fail
               "Persisted snap healed-subtree proof has an unknown version"))))
        present))))

(defun snap-sync-populate-healed-subtree-batch
    (batch reference &optional (kind :account))
  (kv-batch-put-chain-record
   batch :metadata (snap-sync-healed-subtree-identifier reference kind)
   +snap-sync-healed-subtree-value+)
  batch)

(defun snap-sync-healed-subtree-candidate-p (work)
  "Select bounded trie subtrees whose content proof survives pivot changes."
  (unless (and (integerp *snap-sync-healed-subtree-prefix-nibbles*)
               (<= 1 *snap-sync-healed-subtree-prefix-nibbles* 64))
    (error "Snap healed-subtree prefix depth must be between one and 64"))
  (and (null (snap-sync-heal-work-marker-state work))
       (>= (length (snap-sync-heal-work-path work))
           *snap-sync-healed-subtree-prefix-nibbles*)
       (let ((reference (snap-sync-heal-work-reference work)))
         (and (byte-vector-p reference) (= 32 (length reference))))))

(defun snap-sync-heal-signal-source-errors (errors)
  (let ((storage-error
          (find-if
           (lambda (condition)
             (typep condition 'ethereum-lisp.validation:storage-error))
           errors)))
    (cond
      (storage-error (error storage-error))
      ((and errors
            (every
             (lambda (condition)
               (typep condition 'snap-sync-state-unavailable))
             errors))
       (error (first errors)))
      (errors
       (snap-sync-signal-sources-exhausted :healing errors))
      (t
       (error "Snap healing requires a live source")))))

(defun snap-sync-heal-state
    (database sources progress byte-limit
     &key on-source-error on-heal-progress source-provider
          heal-yield-p
          (code-batch-limit +snap-sync-heal-codes-per-request+))
  "Heal a mixed snap/1 flat download to PROGRESS's exact authorized root.

Traversal follows the new root and reuses every content-addressed node already
written by older pivots.  Missing account/storage nodes are requested by their
snap compact paths in bounded batches; response blobs are matched to requested
hashes before persistence.  Code and storage dependencies are completed before
the state-history marker and completed cursor share their final batch.
SOURCE-PROVIDER may return a fresh live-source snapshot before each remote
round; newly observed complete sources join in stable order, while a source
retired by this healing attempt cannot be re-admitted under the same identity.
When HEAL-YIELD-P returns true at a safe batch boundary, signal
SNAP-SYNC-HEAL-YIELDED without publishing completion."
  (unless (and (integerp code-batch-limit)
               (<= 1 code-batch-limit +snap-sync-heal-codes-per-request+))
    (error "Snap healing code batch limit must be between one and ~D"
           +snap-sync-heal-codes-per-request+))
  (when (and source-provider (not (functionp source-provider)))
    (error "Snap healing source provider must be a function"))
  (when (and heal-yield-p (not (functionp heal-yield-p)))
    (error "Snap healing yield predicate must be a function"))
  (unless (snap-sync-tasks-completed-p
           (snap-sync-progress-tasks progress))
    (error "Snap trie healing cannot precede flat-range completion"))
  (multiple-value-bind (checkpoint checkpoint-present-p)
      (snap-sync-read-heal-checkpoint database progress)
    (multiple-value-bind
          (planned-storage planned-storage-present-p planned-storage-overflow-p)
        (if checkpoint-present-p
            (values nil nil nil)
            (snap-sync-deferred-storage-works
             database (snap-sync-progress-state-root progress)))
      (let* ((state-root (snap-sync-progress-state-root progress))
           (root-bytes (hash32-bytes state-root))
           (stack
             (cond
               (checkpoint-present-p
                (copy-list (snap-sync-heal-checkpoint-stack checkpoint)))
               ((and planned-storage-present-p
                     (not planned-storage-overflow-p))
                planned-storage)
               ((hash32= state-root +empty-trie-hash+) nil)
               (t
                (list
                 (snap-sync-make-heal-work
                  :account nil (make-byte-vector 0) root-bytes)))))
           (active-sources (remove-duplicates (copy-list sources) :test #'eq))
           (retired-sources '())
           (retired-source-errors '())
           (pending-codes '())
           (pending-code-count 0)
           (pending-healed-subtrees '())
           (pending-healed-subtree-count 0)
           (pending-healed-subtree-index (make-hash-table :test #'equalp))
           (deferred-storage '())
           (deferred-storage-count 0)
           (seen-code-hashes (make-hash-table :test #'equalp))
           ;; A fetched node is made durable before its work re-enters STACK.
           ;; Keep its verified decoded object until that exact continuation
           ;; consumes it, avoiding an immediate RocksDB reread without
           ;; changing durable frontier or subtree-sentinel ordering.
           (fetched-node-cache (make-hash-table :test #'equalp))
           (processed-nodes
             (if checkpoint-present-p
                 (snap-sync-heal-checkpoint-processed-nodes checkpoint)
                 0))
           (reused-nodes
             (if checkpoint-present-p
                 (snap-sync-heal-checkpoint-reused-nodes checkpoint)
                 0))
           (fetched-nodes
             (if checkpoint-present-p
                 (snap-sync-heal-checkpoint-fetched-nodes checkpoint)
                 0))
           (request-count
             (if checkpoint-present-p
                 (snap-sync-heal-checkpoint-request-count checkpoint)
                 0))
           (response-bytes
             (if checkpoint-present-p
                 (snap-sync-heal-checkpoint-response-bytes checkpoint)
                 0))
           (source-round 0)
           (last-checkpoint-processed-nodes processed-nodes))
    (labels
        ((refresh-active-sources ()
           (when source-provider
             (let ((fresh (funcall source-provider)))
               (unless (listp fresh)
                 (error "Snap healing source provider must return a list"))
               (dolist (source fresh)
                 (unless (snap-sync-source-complete-p source)
                   (error "Snap healing source provider returned an incomplete source"))
                 (unless (or (member source active-sources :test #'eq)
                             (member source retired-sources :test #'eq))
                   ;; Preserve the existing rotation order while allowing
                   ;; sessions admitted after a long heal began to join its
                   ;; next bounded request round.
                   (setf active-sources
                         (nconc active-sources (list source))))))))
         (report-local-checkpoint ()
           (when (and on-heal-progress
                      (plusp *snap-sync-heal-progress-node-interval*)
                      (zerop
                       (mod processed-nodes
                            *snap-sync-heal-progress-node-interval*)))
             (snap-sync-report-heal-progress
              on-heal-progress processed-nodes reused-nodes fetched-nodes
              request-count response-bytes nil)))
         (read-local-nodes (references &key decoder)
           ;; Preserve the ordered batch contract while satisfying freshly
           ;; fetched hashes from the bounded response cache.  All other
           ;; references retain the production database batch path.
           (let* ((count (length references))
                  (encoded (make-array count :initial-element nil))
                  (present (make-array count :element-type 'bit
                                             :initial-element 0))
                  (decoded (make-array count :initial-element nil))
                  (cached-references '())
                  (uncached-indices '())
                  (uncached-references '()))
             (dotimes (index count)
               (let ((reference (aref references index)))
                 (multiple-value-bind (object cached-p)
                     (gethash reference fetched-node-cache)
                   (if cached-p
                       (progn
                         (setf (aref present index) 1
                               (aref decoded index) object)
                         (push reference cached-references))
                       (progn
                         (push index uncached-indices)
                         (push reference uncached-references))))))
             (when uncached-indices
               (let ((indices
                       (coerce (nreverse uncached-indices) 'vector))
                     (references
                       (coerce (nreverse uncached-references) 'vector)))
                 (multiple-value-bind
                       (stored stored-present stored-decoded)
                     (snap-sync-heal-local-node-batch
                      database references
                      :decoder
                      (lambda (index bytes)
                        (funcall decoder (aref indices index) bytes)))
                   (dotimes (index (length indices))
                     (let ((destination (aref indices index)))
                       (setf (aref encoded destination) (aref stored index)
                             (aref present destination)
                             (aref stored-present index)
                             (aref decoded destination)
                             (aref stored-decoded index)))))))
             ;; Duplicate references in the same batch all observe the cache;
             ;; later visits safely fall back to the now-durable database.
             (dolist (reference cached-references)
               (remhash reference fetched-node-cache))
             (values encoded present decoded)))
         (push-reference (kind account-hash path reference &optional marker-state)
           (unless (and (byte-vector-p reference)
                        (zerop (length reference)))
             (push (snap-sync-make-heal-work
                    kind account-hash path reference
                    :marker-state marker-state)
                   stack)))
         (defer-storage-reference (account-hash reference)
           (unless (and (byte-vector-p reference)
                        (zerop (length reference)))
             (push
              (snap-sync-heal-deferred-storage-work account-hash reference)
              deferred-storage)
             (incf deferred-storage-count)))
         (drain-deferred-storage ()
           ;; PUSH preserved DFS work on STACK.  Re-pushing the newest-first
           ;; deferred list leaves the oldest discovered storage root on top,
           ;; while making every root part of the next durable frontier.
           (dolist (work deferred-storage)
             (push work stack))
           (setf deferred-storage nil
                 deferred-storage-count 0))
         (flush-codes ()
           (when pending-codes
             (unless active-sources
               (snap-sync-heal-signal-source-errors
                (nreverse retired-source-errors)))
             (snap-sync-heal-fetch-codes
              database active-sources (nreverse pending-codes) byte-limit
              on-source-error)
             (setf pending-codes nil
                   pending-code-count 0)))
         (flush-healed-subtrees ()
           ;; Every dependency encountered before a completion sentinel must
           ;; be durable before its reusable proof becomes visible.  Publish
           ;; many independent content-addressed proofs with one WAL sync;
           ;; losing an unflushed cache hint can only repeat safe traversal.
           (flush-codes)
           (when pending-healed-subtrees
             (setf pending-healed-subtrees
                   (nreverse pending-healed-subtrees))
             (let ((batch (make-kv-write-batch)))
               (dolist (entry pending-healed-subtrees)
                 (snap-sync-populate-healed-subtree-batch
                  batch (cdr entry) (car entry)))
               (kv-apply-batch database batch))
             (setf pending-healed-subtrees nil
                   pending-healed-subtree-count 0)
             (clrhash pending-healed-subtree-index)))
         (persist-healed-subtree (work)
           ;; Account leaves below this sentinel may have queued code and
           ;; storage dependencies.  Publish the pivot-independent proof only
           ;; after every such dependency is durable; a failure leaves the
           ;; older checkpoint authoritative and merely repeats safe work.
           (let* ((reference (snap-sync-heal-work-reference work))
                  (kind (snap-sync-heal-work-kind work))
                  (identifier
                    (snap-sync-healed-subtree-identifier reference kind)))
             (unless
                 (snap-sync-healed-subtree-present-p
                  database reference kind)
               (unless
                   (nth-value
                    1 (gethash identifier pending-healed-subtree-index))
                 (setf (gethash identifier pending-healed-subtree-index) t)
                 (push (cons kind reference) pending-healed-subtrees)
                 (incf pending-healed-subtree-count)
                 (when (= pending-healed-subtree-count
                          +snap-sync-healed-subtrees-per-batch+)
                   (flush-healed-subtrees))))))
         (populate-checkpoint (batch frontier)
           (snap-sync-populate-heal-checkpoint-batch
            batch progress frontier processed-nodes reused-nodes fetched-nodes
            request-count response-bytes))
         (persist-checkpoint (frontier)
           (flush-healed-subtrees)
           (let ((batch (make-kv-write-batch)))
             (populate-checkpoint batch frontier)
             (kv-apply-batch database batch)
             (setf last-checkpoint-processed-nodes processed-nodes)))
         (checkpoint-due-p ()
           (snap-sync-heal-checkpoint-due-p
            processed-nodes last-checkpoint-processed-nodes))
         (checkpoint-blocks-traversal-p (&optional (pending-count 0))
           ;; A wide local batch may transiently expand the exact DFS frontier
           ;; above the single-record checkpoint cap.  The older checkpoint
           ;; remains authoritative while one-work reads drain that bounded
           ;; excess; stopping here would make the node fail at the first
           ;; checkpoint boundary without producing a resumable record.
           (and (checkpoint-due-p)
                (<= (+ (length stack) deferred-storage-count pending-count)
                    +snap-sync-heal-checkpoint-max-works+)))
         (queue-code-hash (hash)
           ;; Keep one content hash for the whole traversal.  Flushing bounds
           ;; wire work and the pending list without repeating database reads
           ;; for bytecode shared by many accounts.
           (unless (nth-value 1 (gethash hash seen-code-hashes))
             (setf (gethash hash seen-code-hashes) t)
             (push hash pending-codes)
             (incf pending-code-count)
             (when (= pending-code-count code-batch-limit)
               (flush-codes))))
         (queue-account-value (path value)
           (unless (= 64 (length path))
             (error "Snap healed account leaf does not end at 32 bytes"))
           (let* ((account-hash
                    (ethereum-lisp.trie.encoding:nibbles-to-keybytes path))
                  (account (decode-state-account-rlp value))
                  (code-hash (state-account-code-hash account))
                  (storage-root (state-account-storage-root account)))
             (unless (hash32= code-hash +empty-code-hash+)
               (queue-code-hash (hash32-bytes code-hash)))
             (unless (hash32= storage-root +empty-trie-hash+)
               (defer-storage-reference
                account-hash (hash32-bytes storage-root)))))
         (process-value (work path value)
           (unless (byte-vector-p value)
             (error "Snap healed trie leaf value is not bytes"))
           (when (eq :account (snap-sync-heal-work-kind work))
             (queue-account-value path value)))
         (process-object (work object)
           (incf processed-nodes)
           (report-local-checkpoint)
           (unless (rlp-list-p object)
             (error "Snap healing response contains a non-list trie node"))
           (let ((items (rlp-list-items object))
                 (path (snap-sync-heal-work-path work))
                 (kind (snap-sync-heal-work-kind work))
                 (account-hash
                   (snap-sync-heal-work-account-hash work))
                 (child-marker-state
                   (and
                    (member
                     (snap-sync-heal-work-marker-state work)
                     '(:armed :inside))
                    :inside)))
             (case (length items)
               (17
                (let ((remaining items))
                  (dotimes (index 16)
                    (let ((reference (pop remaining)))
                      (push-reference
                       kind account-hash
                       (concatenate 'vector path (vector index)) reference
                       child-marker-state)))
                  (let ((value (first remaining)))
                    (when (and (byte-vector-p value) (plusp (length value)))
                      (process-value work path value)))))
               (2
                (let ((path-field (first items))
                      (reference (second items)))
                  (unless (and (byte-vector-p path-field)
                               (plusp (length path-field)))
                    (error "Snap healed trie short path is malformed"))
                  (multiple-value-bind (segment leaf-p)
                      (ethereum-lisp.trie.encoding:hex-prefix-decode path-field)
                    (let* ((segment
                             (if (and leaf-p
                                      (ethereum-lisp.trie.encoding:has-terminator-p
                                       segment))
                                 (subseq segment 0 (1- (length segment)))
                                 segment))
                           (next-path
                             (concatenate 'vector path segment)))
                      (when (> (length next-path) 64)
                        (error "Snap healed trie path exceeds 32 bytes"))
                      (if leaf-p
                          (process-value work next-path reference)
                          (push-reference
                           kind account-hash next-path reference
                           child-marker-state))))))
               (otherwise
                (error "Snap healing response has invalid trie node arity")))))
         (decode-encoded (work encoded local-p)
           (let ((reference (snap-sync-heal-work-reference work)))
             (when (and (byte-vector-p reference)
                        (= 32 (length reference))
                        (not (bytes= reference (keccak-256 encoded))))
               (if local-p
                   (ethereum-lisp.validation:storage-fail
                    "Persisted snap trie node does not match its hash")
                   (error "Snap peer returned an unrequested trie node"))))
           (handler-case
               (rlp-decode-one encoded :max-list-items 17)
             (rlp-error (condition)
               (if local-p
                   (ethereum-lisp.validation:storage-fail
                    "Persisted snap trie node is malformed: ~A" condition)
                   (error condition)))))
         (fetch-missing (missing)
           (refresh-active-sources)
           (unless active-sources
             (snap-sync-heal-signal-source-errors
              (reverse retired-source-errors)))
           (let* ((round-sources
                    (snap-sync-heal-round-sources
                     active-sources source-round))
                  (results
                    (snap-sync-heal-request-round
                     round-sources missing root-bytes byte-limit))
                  (matched
                    (make-array (length missing) :initial-element nil))
                  (batch (make-kv-write-batch))
                  (fills 0)
                  (fetched-bytes 0)
                  (successful-results 0)
                  (round-errors '()))
             (incf source-round)
             (incf request-count (length results))
             (loop for result across results
                   for condition =
                     (snap-sync-heal-fetch-result-condition result)
                   do
                   (if condition
                       (progn
                         (when (typep
                                condition
                                'ethereum-lisp.validation:storage-error)
                           (error condition))
                         (push condition round-errors)
                         (push condition retired-source-errors)
                         (pushnew
                          (snap-sync-heal-fetch-result-source result)
                          retired-sources :test #'eq)
                         (setf active-sources
                               (remove
                                (snap-sync-heal-fetch-result-source result)
                                active-sources :test #'eq))
                         (when on-source-error
                           (funcall
                            on-source-error
                            (snap-sync-heal-fetch-result-source result)
                            condition)))
                       (let ((cursor
                               (snap-sync-heal-fetch-result-start result))
                             (end (snap-sync-heal-fetch-result-end result)))
                         (incf successful-results)
                         (dolist
                             (encoded
                              (snap-trie-nodes-nodes
                               (snap-sync-heal-fetch-result-response result)))
                           (let ((hash (keccak-256 encoded))
                                 (found nil))
                             (loop while (< cursor end)
                                   for work = (aref missing cursor)
                                   for expected =
                                     (snap-sync-heal-work-reference work)
                                   do (incf cursor)
                                      (when (bytes= hash expected)
                                        (setf found (1- cursor))
                                        (return)))
                             (unless found
                               (error
                                "Snap peer returned an unrequested healing node"))
                           (setf (aref matched found) encoded)
                           (incf fills)
                           (incf fetched-bytes (length encoded))
                           ;; MISSING was produced by the immediately preceding
                           ;; ordered local lookup, so another point read here
                           ;; can only rediscover absence (or the same content-
                           ;; addressed value written by another disjoint
                           ;; slice).  The response hash is the collision and
                           ;; identity check.  Stage it directly, as geth's
                           ;; healer does, instead of turning every fetched
                           ;; node into an extra random RocksDB Get.
                           (kv-batch-put-chain-record
                            batch :trie-node hash encoded))))))
             (labels ((continuation-stack ()
                        (let ((continuation stack))
                          (loop for index downfrom (1- (length missing)) to 0
                                for work = (aref missing index)
                                do (push
                                    (snap-sync-copy-heal-work
                                     work :fetched-p
                                     (not (null (aref matched index))))
                                    continuation))
                          continuation)))
               (when (zerop successful-results)
                 ;; Preserve the exact unprocessed frontier before handing the
                 ;; finite source-generation failure back to the coordinator.
                 (setf stack (continuation-stack))
                 (when (snap-sync-heal-checkpoint-frontier-p stack)
                   (persist-checkpoint stack))
                 (snap-sync-heal-signal-source-errors
                  (nreverse round-errors)))
               ;; Decode every delivered node before publishing any of them.
               ;; A malformed peer response therefore cannot leave an invalid
               ;; trie blob behind.  Keep the verified objects in a bounded
               ;; cache after the durable write so the continuation can retain
               ;; its exact DFS/checkpoint semantics without rereading them.
               (let ((decoded
                       (make-array (length missing) :initial-element nil)))
                 (dotimes (index (length missing))
                   (let ((encoded (aref matched index)))
                     (when encoded
                       (setf (aref decoded index)
                             (decode-encoded
                              (aref missing index) encoded nil)))))
                 (incf fetched-nodes fills)
                 (incf response-bytes fetched-bytes)
                 ;; The same batch that makes response nodes durable publishes
                 ;; a frontier whose FETCHED-P bits keep restart telemetry and
                 ;; completion-sentinel ordering exact.
                 (setf stack (continuation-stack))
                 (let ((checkpointable-p
                         (snap-sync-heal-checkpoint-frontier-p stack)))
                   (when checkpointable-p
                     (populate-checkpoint batch stack))
                   (kv-apply-batch database batch)
                   (when checkpointable-p
                     (setf last-checkpoint-processed-nodes processed-nodes)))
                 ;; Cache only after the durable write succeeds.  A crash or
                 ;; restart simply reads these content-addressed nodes normally.
                 (dotimes (index (length missing))
                   (when (aref matched index)
                     (setf
                      (gethash
                       (snap-sync-heal-work-reference (aref missing index))
                       fetched-node-cache)
                      (aref decoded index)))))
               (snap-sync-report-heal-progress
                on-heal-progress processed-nodes reused-nodes fetched-nodes
                request-count response-bytes nil)))))
      (loop
        ;; No request worker or uncommitted database batch crosses this seam.
        ;; A coordinator may therefore yield a stale, CL-authorized target and
        ;; atomically rebase its durable progress on the next pass. Content-
        ;; addressed nodes and completed-subtree proofs remain reusable.
        (when (and heal-yield-p (funcall heal-yield-p))
          (error 'snap-sync-heal-yielded))
        (let* ((missing '())
               (missing-count 0)
               (missing-limit
                 (snap-sync-heal-missing-limit
                  (+ (length stack) deferred-storage-count)
                  (length active-sources))))
          (loop while (and stack
                           (< missing-count missing-limit)
                           (< deferred-storage-count
                              +snap-sync-heal-deferred-storage-target+)
                           (not (checkpoint-blocks-traversal-p missing-count)))
                do
                (let* ((checkpoint-room
                         (max
                          1
                          (- +snap-sync-heal-checkpoint-node-interval+
                             (- processed-nodes
                                last-checkpoint-processed-nodes))))
                       (read-limit
                         (snap-sync-heal-local-read-limit
                          (+ (length stack) deferred-storage-count
                             missing-count)
                          missing-count missing-limit
                          checkpoint-room))
                       (lookups '())
                       (lookup-count 0))
                  ;; Inline references are already local values. Process them
                  ;; immediately until an external hash batch begins; once it
                  ;; does, stop before the next inline item so a durable
                  ;; checkpoint never skips an unprocessed popped work.
                  (loop while (and stack
                                   (< lookup-count read-limit)
                                   (not
                                    (checkpoint-blocks-traversal-p
                                     missing-count)))
                        for work = (pop stack)
                        for reference =
                          (snap-sync-heal-work-reference work)
                        do (cond
                             ((eq :complete
                                  (snap-sync-heal-work-marker-state work))
                              (if (or lookups deferred-storage)
                                  (progn
                                    (push work stack)
                                    (unless lookups
                                      (drain-deferred-storage))
                                    (return))
                                  (persist-healed-subtree work)))
                             ((snap-sync-healed-subtree-candidate-p work)
                              ;; Resolve pivot-independent completion proofs in
                              ;; one ordered batch below.  Counting the popped
                              ;; work now preserves the frontier/read bound
                              ;; even when the proof lets us skip its subtree.
                              (push work lookups)
                              (incf lookup-count))
                             ((or (rlp-list-p reference)
                                  (zerop (length reference)))
                              (if lookups
                                  (push work stack)
                                  (when (rlp-list-p reference)
                                    (process-object work reference)))
                              ;; PROCESS-OBJECT may grow STACK. Recompute the
                              ;; frontier-aware width before collecting hashes.
                              (return))
                             (t
                              (push work lookups)
                              (incf lookup-count))))
                  (when lookups
                    (let* ((ordered (coerce (nreverse lookups) 'vector))
                           (candidate-works
                             (loop for work across ordered
                                   when
                                     (snap-sync-healed-subtree-candidate-p
                                      work)
                                     collect work))
                           (candidate-references
                             (map 'vector
                                  #'snap-sync-heal-work-reference
                                  candidate-works))
                           (candidate-kinds
                             (map 'vector
                                  #'snap-sync-heal-work-kind
                                  candidate-works))
                           (candidate-presence
                             (if candidate-works
                                 (snap-sync-healed-subtrees-present
                                  database candidate-references candidate-kinds)
                                 #()))
                           (candidate-index 0)
                           (actual-lookups '()))
                      (loop for work across ordered
                            do
                            (if (snap-sync-healed-subtree-candidate-p work)
                                (progn
                                  (unless
                                      (= 1
                                         (aref candidate-presence
                                               candidate-index))
                                    (push
                                     (snap-sync-make-heal-work
                                      (snap-sync-heal-work-kind work)
                                      (snap-sync-heal-work-account-hash work)
                                      (snap-sync-heal-work-path work)
                                      (snap-sync-heal-work-reference work)
                                      :fetched-p
                                      (snap-sync-heal-work-fetched-p work)
                                      :marker-state :armed)
                                     actual-lookups))
                                  (incf candidate-index))
                                (push work actual-lookups)))
                      (setf ordered
                            (coerce (nreverse actual-lookups) 'vector))
                      (when (plusp (length ordered))
                        (let ((references
                                (map 'vector
                                     #'snap-sync-heal-work-reference
                                     ordered)))
                          (multiple-value-bind (encoded present decoded)
                              (read-local-nodes
                               references
                               :decoder
                               (lambda (index bytes)
                                 (let ((work (aref ordered index)))
                                   (decode-encoded
                                    work bytes
                                    (not
                                     (snap-sync-heal-work-fetched-p work))))))
                            (declare (ignore encoded))
                            (dotimes (index (length ordered))
                              (let ((work (aref ordered index)))
                                (if (= 1 (aref present index))
                                    (progn
                                      (unless
                                          (snap-sync-heal-work-fetched-p work)
                                        (incf reused-nodes))
                                      (when
                                          (eq
                                           :armed
                                           (snap-sync-heal-work-marker-state
                                            work))
                                        (push
                                         (snap-sync-make-heal-work
                                          (snap-sync-heal-work-kind work)
                                          (snap-sync-heal-work-account-hash work)
                                          (snap-sync-heal-work-path work)
                                          (snap-sync-heal-work-reference work)
                                          :marker-state :complete)
                                         stack))
                                      (process-object
                                       work (aref decoded index)))
                                    (progn
                                      (push work missing)
                                      (incf missing-count))))))))))))
          (drain-deferred-storage)
          (flush-healed-subtrees)
          (cond
            (missing
             (fetch-missing (coerce (nreverse missing) 'vector)))
            ((and stack
                  (checkpoint-due-p)
                  (snap-sync-heal-checkpoint-frontier-p stack))
             (persist-checkpoint stack)))
          (when (and (null stack) (null missing))
            (return)))))
    (let* ((completed
             (snap-sync-make-progress
              :pivot-hash (snap-sync-progress-pivot-hash progress)
              :pivot-number (snap-sync-progress-pivot-number progress)
              :state-root state-root :partial-root state-root
              :target-hash (snap-sync-progress-target-hash progress)
              :chain-id (snap-sync-progress-chain-id progress)
              :genesis-hash (snap-sync-progress-genesis-hash progress)
              :authority-id (snap-sync-progress-authority-id progress)
              :completed-p t :tasks (snap-sync-progress-tasks progress)))
           (batch (make-kv-write-batch)))
      (snap-sync-complete-batch batch completed)
      (kv-apply-batch database batch)
      (snap-sync-report-heal-progress
       on-heal-progress processed-nodes reused-nodes fetched-nodes
       request-count response-bytes t)
      completed)))))

(defun snap-sync-import-state
    (database source
     &key pivot-hash pivot-number state-root chain-id genesis-hash authority-id
          target-hash
          (byte-limit +snap-sync-request-bytes+) on-progress on-heal-progress
          heal-source-provider heal-yield-p max-pages)
  "Download, verify, and atomically install a CL-authorized pivot state.

Every account-range cursor is committed in the same batch as the partial trie
nodes and bytecodes it names.  Complete small storage tries are batched eagerly;
byte-capped large tries are deferred so a peer's pivot-retention window cannot
starve the account cursor.  A final content-addressed traversal reuses durable
nodes and proves every storage/code dependency before installing the completion
marker.
Returns the completed SNAP-SYNC-PROGRESS, or an incomplete progress when
MAX-PAGES intentionally bounds a test or one scheduling slice."
  (unless (typep database 'key-value-database)
    (error "Snap state import requires a key-value database"))
  (unless (snap-sync-source-complete-p source)
    (error "Snap state import source is incomplete"))
  (setf target-hash (or target-hash pivot-hash))
  (snap-sync-require-hash32 target-hash "Snap consensus target hash")
  (let ((progress
          (snap-sync-load-progress
           database 1 pivot-hash pivot-number state-root target-hash chain-id
           genesis-hash authority-id))
        (pages 0))
    (when (snap-sync-progress-completed-p progress)
      (return-from snap-sync-import-state progress))
    (when (snap-sync-tasks-completed-p
           (snap-sync-progress-tasks progress))
      (return-from snap-sync-import-state
        (snap-sync-heal-state
         database (list source) progress byte-limit
         :source-provider heal-source-provider
         :heal-yield-p heal-yield-p
         :on-heal-progress on-heal-progress)))
    (loop
      (when (and max-pages (>= pages max-pages))
        (return progress))
      (multiple-value-bind (task-index task)
          (snap-sync-next-unfinished-task progress)
        (unless task
          (error "Snap progress is incomplete but has no unfinished task"))
        (setf progress
              (snap-sync-commit-account-page
               database progress
               (snap-sync-prepare-account-page
                database source state-root task-index task byte-limit)))
        (incf pages)
        (when on-progress (funcall on-progress progress))
        (when (snap-sync-progress-completed-p progress)
          (return progress))
        (when (snap-sync-tasks-completed-p
               (snap-sync-progress-tasks progress))
          (return
            (snap-sync-heal-state
             database (list source) progress byte-limit
             :source-provider heal-source-provider
             :heal-yield-p heal-yield-p
             :on-heal-progress on-heal-progress)))))))

#+sbcl
(defstruct (snap-sync-multi-runtime
            (:constructor make-snap-sync-multi-runtime
                (progress source-count max-pages)))
  (lock (sb-thread:make-mutex :name "snap-sync-multi"))
  (changed (sb-thread:make-waitqueue :name "snap-sync-multi-changed"))
  progress
  (claims (make-hash-table))
  (events '())
  source-count
  max-pages
  (pages 0)
  stopped-p)

#+sbcl
(defstruct (snap-sync-multi-event
            (:constructor make-snap-sync-multi-event
                (&key kind source task-index result condition)))
  kind
  source
  task-index
  result
  condition)

#+sbcl
(defun snap-sync-multi-notify (runtime)
  (sb-thread:condition-broadcast (snap-sync-multi-runtime-changed runtime)))

#+sbcl
(defun snap-sync-multi-claim-task (runtime source)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (loop
      (cond
        ((or (snap-sync-multi-runtime-stopped-p runtime)
             (snap-sync-progress-completed-p
              (snap-sync-multi-runtime-progress runtime)))
         (return (values nil nil)))
        ((and (snap-sync-multi-runtime-max-pages runtime)
              (>= (+ (snap-sync-multi-runtime-pages runtime)
                     (hash-table-count
                      (snap-sync-multi-runtime-claims runtime)))
                  (snap-sync-multi-runtime-max-pages runtime)))
         (if (zerop
              (hash-table-count (snap-sync-multi-runtime-claims runtime)))
             (return (values nil nil))
             (sb-thread:condition-wait
              (snap-sync-multi-runtime-changed runtime)
              (snap-sync-multi-runtime-lock runtime))))
        (t
         (multiple-value-bind (index task)
             (snap-sync-next-unfinished-task
              (snap-sync-multi-runtime-progress runtime)
              (snap-sync-multi-runtime-claims runtime))
           (when task
             (setf (gethash index (snap-sync-multi-runtime-claims runtime))
                   source)
             (return (values index task))))
         (sb-thread:condition-wait
          (snap-sync-multi-runtime-changed runtime)
          (snap-sync-multi-runtime-lock runtime)))))))

#+sbcl
(defun snap-sync-multi-push-event (runtime event)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (setf (snap-sync-multi-runtime-events runtime)
          (nconc (snap-sync-multi-runtime-events runtime) (list event)))
    (snap-sync-multi-notify runtime)))

#+sbcl
(defun snap-sync-multi-wait-for-commit (runtime task-index source)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (loop while (and (not (snap-sync-multi-runtime-stopped-p runtime))
                     (eq source
                         (gethash task-index
                                  (snap-sync-multi-runtime-claims runtime))))
          do (sb-thread:condition-wait
              (snap-sync-multi-runtime-changed runtime)
              (snap-sync-multi-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-multi-worker
    (runtime database source state-root byte-limit)
  (unwind-protect
       (loop
         (multiple-value-bind (task-index task)
             (snap-sync-multi-claim-task runtime source)
           (unless task (return))
           (handler-case
               (let ((result
                       (snap-sync-prepare-account-page
                        database source state-root task-index task byte-limit)))
                 (snap-sync-multi-push-event
                  runtime
                  (make-snap-sync-multi-event
                   :kind :result :source source :task-index task-index
                   :result result))
                 ;; One source has at most one verified but uncommitted page.
                 ;; This bounds resident account data by source count rather
                 ;; than by the sixteen logical partitions.
                 (snap-sync-multi-wait-for-commit
                  runtime task-index source))
             (serious-condition (condition)
               (snap-sync-multi-push-event
                runtime
                (make-snap-sync-multi-event
                 :kind :error :source source :task-index task-index
                 :condition condition))
               (return)))))
    (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
      (decf (snap-sync-multi-runtime-source-count runtime))
      (snap-sync-multi-notify runtime))))

#+sbcl
(defun snap-sync-multi-next-event (runtime)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (loop
      (when (snap-sync-multi-runtime-events runtime)
        (return (pop (snap-sync-multi-runtime-events runtime))))
      (when (snap-sync-progress-completed-p
             (snap-sync-multi-runtime-progress runtime))
        (return :complete))
      (when (and (snap-sync-multi-runtime-max-pages runtime)
                 (>= (snap-sync-multi-runtime-pages runtime)
                     (snap-sync-multi-runtime-max-pages runtime))
                 (zerop
                  (hash-table-count
                   (snap-sync-multi-runtime-claims runtime))))
        (return :limited))
      (when (snap-sync-tasks-completed-p
             (snap-sync-progress-tasks
              (snap-sync-multi-runtime-progress runtime)))
        (return :heal))
      (when (zerop (snap-sync-multi-runtime-source-count runtime))
        (return :exhausted))
      (sb-thread:condition-wait
       (snap-sync-multi-runtime-changed runtime)
       (snap-sync-multi-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-multi-release-claim (runtime task-index source)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (when (eq source
              (gethash task-index (snap-sync-multi-runtime-claims runtime)))
      (remhash task-index (snap-sync-multi-runtime-claims runtime)))
    (snap-sync-multi-notify runtime)))

#+sbcl
(defun snap-sync-import-state-multi
    (database sources
     &key pivot-hash pivot-number state-root chain-id genesis-hash authority-id
          target-hash (byte-limit +snap-sync-request-bytes+)
          on-progress on-source-error on-heal-progress heal-source-provider
          heal-yield-p max-pages)
  "Import one pivot through disjoint durable ranges shared across SOURCES.

Sixteen logical account tasks follow pinned geth 38271784.  At most one worker
uses each source, preserving the session's sole-writer rule.  Workers verify and
heal independent pages concurrently; the caller thread serializes MPT merge,
the progress batch, and callbacks.  ON-PROGRESS receives PROGRESS, SOURCE, and
TASK-INDEX after that task page is durable.  ON-SOURCE-ERROR receives SOURCE and
the condition after its task has been made retryable by another source.
HEAL-SOURCE-PROVIDER extends only the final content-addressed traversal with
newly admitted live sources; the durable range-worker snapshot stays finite.
HEAL-YIELD-P is forwarded only to that final traversal."
  (unless (typep database 'key-value-database)
    (error "Snap state import requires a key-value database"))
  (setf sources (remove-duplicates (copy-list sources) :test #'eq))
  (unless sources
    (error "Multi-source snap import requires at least one source"))
  (dolist (source sources)
    (unless (snap-sync-source-complete-p source)
      (error "Multi-source snap import source is incomplete")))
  (setf target-hash (or target-hash pivot-hash))
  (snap-sync-require-hash32 target-hash "Snap consensus target hash")
  (let* ((progress
           (snap-sync-load-progress
            database +snap-sync-account-task-count+
            pivot-hash pivot-number state-root target-hash chain-id
            genesis-hash authority-id))
         (runtime
           (make-snap-sync-multi-runtime progress (length sources) max-pages))
         (threads '())
         (errors '()))
    (when (snap-sync-progress-completed-p progress)
      (return-from snap-sync-import-state-multi progress))
    (when (snap-sync-tasks-completed-p
           (snap-sync-progress-tasks progress))
      (return-from snap-sync-import-state-multi
        (snap-sync-heal-state
         database sources progress byte-limit
         :source-provider heal-source-provider
         :heal-yield-p heal-yield-p
         :on-source-error on-source-error
         :on-heal-progress on-heal-progress)))
    (unwind-protect
         (progn
           (dolist (source sources)
             (let ((worker-source source))
               (push
                (sb-thread:make-thread
                 (lambda ()
                   (snap-sync-multi-worker
                    runtime database worker-source state-root byte-limit))
                 :name "snap-sync-account-worker")
                threads)))
           (loop
             (let ((event (snap-sync-multi-next-event runtime)))
               (case event
                 (:complete
                  (return (snap-sync-multi-runtime-progress runtime)))
                 (:limited
                  (return (snap-sync-multi-runtime-progress runtime)))
                 (:heal
                  (return
                    (snap-sync-heal-state
                     database sources
                     (snap-sync-multi-runtime-progress runtime)
                     byte-limit :source-provider heal-source-provider
                     :heal-yield-p heal-yield-p
                     :on-source-error on-source-error
                     :on-heal-progress on-heal-progress)))
                 (:exhausted
                  (cond
                    ((and errors
                          (every
                           (lambda (condition)
                             (typep condition 'snap-sync-state-unavailable))
                           errors))
                     ;; Preserve the availability taxonomy across fan-out.
                     ;; The CLI can then move or retry the CL-authorized pivot
                     ;; without turning ordinary remote pruning into a fatal
                     ;; local node error.
                     (error (first errors)))
                    (t
                     (snap-sync-signal-sources-exhausted
                      :account-ranges (nreverse errors)))))
                 (otherwise
                  (let ((source (snap-sync-multi-event-source event))
                        (task-index (snap-sync-multi-event-task-index event)))
                    (ecase (snap-sync-multi-event-kind event)
                      (:error
                       (let ((condition
                               (snap-sync-multi-event-condition event)))
                         (push condition errors)
                         (snap-sync-multi-release-claim
                          runtime task-index source)
                         (when on-source-error
                           (funcall on-source-error source condition))
                         (when (typep condition
                                      'ethereum-lisp.validation:storage-error)
                           (error condition))))
                      (:result
                       (handler-case
                           (let ((next
                                   (snap-sync-commit-account-page
                                    database
                                    (snap-sync-multi-runtime-progress runtime)
                                    (snap-sync-multi-event-result event))))
                             (sb-thread:with-mutex
                                 ((snap-sync-multi-runtime-lock runtime))
                               (setf (snap-sync-multi-runtime-progress runtime)
                                     next)
                               (incf (snap-sync-multi-runtime-pages runtime))
                               (remhash
                                task-index
                                (snap-sync-multi-runtime-claims runtime))
                               (snap-sync-multi-notify runtime))
                             (when on-progress
                               (funcall on-progress next source task-index)))
                         (serious-condition (condition)
                           ;; A database or merge failure is local and fatal;
                           ;; it must never be misclassified as a bad peer.
                           (error condition)))))))))))
      (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
        (setf (snap-sync-multi-runtime-stopped-p runtime) t)
        (snap-sync-multi-notify runtime))
      (dolist (thread threads)
        (sb-thread:join-thread thread)))))

#-sbcl
(defun snap-sync-import-state-multi (database sources &rest arguments)
  "Portable fallback: resume the durable cursor serially across SOURCES."
  (let ((errors '()))
    (dolist (source sources)
      (handler-case
          (return (apply #'snap-sync-import-state database source arguments))
        (snap-sync-heal-yielded (condition)
          (error condition))
        (ethereum-lisp.validation:storage-error (condition)
          (error condition))
        (serious-condition (condition)
          (push condition errors))))
    (cond
      ((and errors
            (every (lambda (condition)
                     (typep condition 'snap-sync-state-unavailable))
                   errors))
       (error (first errors)))
      (errors
       (snap-sync-signal-sources-exhausted
        :account-ranges (nreverse errors)))
      (t
       (error "Multi-source snap import requires a source")))))
