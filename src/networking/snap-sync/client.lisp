(in-package #:ethereum-lisp.snap-sync)

;;;; Verified, resumable snap/1 state import.

(defconstant +snap-sync-progress-version+ 4)
(defconstant +snap-sync-partitioned-progress-version+ 3)
(defconstant +snap-sync-legacy-progress-version+ 2)
(defparameter +snap-sync-progress-identifier+ "snap-state-import")
(defconstant +snap-sync-request-bytes+ (* 512 1024)
  "Geth-aligned upper bound for responsive parallel snap/1 pages.")
(defconstant +snap-sync-storage-request-bytes+ (* 512 1024)
  "Geth-aligned upper bound for responsive parallel StorageRanges pages.")
(defconstant +snap-sync-pivot-probe-bytes+ (* 4 1024))
(defconstant +snap-sync-storage-accounts-per-request+ 512
  "Maximum small storage tries in a 512 KiB geth-style request.")
(defconstant +snap-sync-legacy-account-task-count+ 16
  "Account partition count written by progress versions before oversubscription.")
(defconstant +snap-sync-previous-account-task-count+ 32
  "Account partition count written by the first oversubscribed scheduler.")
(defconstant +snap-sync-account-task-count+ 64
  "Account partitions used by a fresh import.

The session remains the only RLPx writer. It may pipeline one request per snap
response type, while range-proof verification and RocksDB writes happen on the
workers after their response is routed. Sixty-four logical partitions keep a
three-stage per-source pipeline and newly admitted peers busy without changing
the durable page bound.")
(defconstant +snap-sync-range-workers-per-source+ 3
  "Maximum account workers sharing one source's typed request pipeline.

Three workers prevent the AccountRange slot from going idle while one page owns
StorageRanges and a sibling page is queued behind that typed request. Each
worker still retains at most one verified, uncommitted page.")
(defconstant +snap-sync-storage-task-count+ 16
  "Maximum parallel ranges used to finish one byte-capped storage trie.")
(defconstant +snap-sync-heal-paths-per-source+
  +snap-sync-trie-node-lookups-per-request+
  "Maximum healing paths assigned to one source in a concurrent round.")
(defparameter *snap-sync-heal-request-target-paths* 512
  "Target TrieNodes path width while retaining a tail for fast-peer stealing.")
(defconstant +snap-sync-heal-local-reads-per-batch+ 512
  "Maximum local read width before frontier-aware shrinking.")
(defparameter *snap-sync-heal-local-read-workers* 8
  "Maximum concurrent RocksDB MultiGet calls during local trie healing.")
(defparameter *snap-sync-heal-remote-first-p* nil
  "Experimentally prefer peer TrieNodes batches over cold RocksDB reads.

Range import has already made many authenticated nodes durable, but a rebased
final heal still has to prove a different root.  Cloud block storage can make
that content-addressed walk random-I/O bound.  On RocksDB with a live source,
request the authenticated paths from peers and write the hash-verified replies
sequentially instead.  Freshly fetched nodes remain satisfied by the bounded
decoded cache, and loss of every source automatically restores local reads.
Public-peer A/B measurements currently favor the local MultiGet path, so this
remains disabled unless a controlled deployment binds it explicitly.")
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
(defparameter +snap-sync-account-subtree-dependencies-identifier-prefix+
  (ascii-to-bytes "snap-account-subtree-dependencies-v1:")
  "Account-trie completion proofs carrying deferred storage dependencies.")
(defparameter +snap-sync-healed-subtree-value+ #(1)
  "Versioned value for a completely verified content-addressed subtree.")
(defconstant +snap-sync-account-subtree-dependencies-version+ 1)
(defconstant +snap-sync-account-subtree-dependencies-max+ 64
  "Maximum deferred storage roots carried by one account-subtree proof.")
(defparameter *snap-sync-healed-subtree-prefix-nibbles* 4
  "Minimum trie depth at which the healer consumes completion proofs.")
(defparameter *snap-sync-range-subtree-prefix-nibbles* 5
  "Finer trie depth published by range proofs and shallow legacy promotion.

The healer still consumes older four-nibble proofs. Five-nibble proofs retain
reuse inside a coarse bucket changed by a later pivot, while requiring only the
first four levels of concrete nodes to discover the content-addressed roots.")
(defconstant +snap-sync-healed-subtrees-per-batch+ 2048
  "Maximum completed subtree proofs published by one durable write batch.")
(defconstant +snap-sync-healed-subtree-bloom-bits+ (ash 1 27)
  "Fixed 16-MiB negative filter for durable healed-subtree proofs.")
(defconstant +snap-sync-healed-subtree-bloom-hashes+ 4
  "Double-hashed bit probes per healed-subtree proof identifier.")
(defparameter +snap-sync-deferred-storage-identifier-prefix+
  (ascii-to-bytes "snap-deferred-storage-v1:")
  "Prefix for state-root-scoped storage work discovered during range import.")
(defparameter +snap-sync-deferred-storage-plan-prefix+
  (ascii-to-bytes "snap-deferred-storage-plan-v1:")
  "Prefix for the trusted marker that says the deferred work set is complete.")
(defparameter +snap-sync-deferred-storage-value+ #(1)
  "Versioned value shared by deferred storage work and plan markers.")
(defparameter +snap-sync-range-plan-promotion-prefix+
  (ascii-to-bytes "snap-range-plan-promoted-v2:"))
(defparameter +snap-sync-storage-plan-promotion-prefix+
  (ascii-to-bytes "snap-storage-plan-promoted-v2:"))
(defconstant +snap-sync-range-plan-promotion-max-roots+ 64)
(defparameter +snap-sync-storage-task-identifier-prefix+
  (ascii-to-bytes "snap-storage-range-task-v1:")
  "Prefix for restart-safe large-contract StorageRanges cursors.")
(defconstant +snap-sync-storage-task-version+ 1)
(defparameter +snap-sync-rebased-range-witness-domain+
  (ascii-to-bytes "snap-rebased-range-witness-v1:")
  "Domain for a non-root witness that permanently disables range-set plans.")
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
                      response-bytes promoted-subtrees skipped-subtrees
                      completed-p)))
  "One cumulative, observational snapshot of final TrieNodes healing.

PROCESSED-NODES includes decoded inline and hash-addressed trie nodes.
REUSED-NODES counts hash-addressed nodes read from the local database, while
FETCHED-NODES and RESPONSE-BYTES count accepted TrieNodes response blobs.
REQUEST-COUNT includes failover attempts. PROMOTED-SUBTREES counts legacy range
proofs converted into completion records at startup. SKIPPED-SUBTREES counts
such records that stopped traversal below a content-addressed root during the
current healer invocation. These counters are observational and not
consensus-visible."
  (processed-nodes 0)
  (reused-nodes 0)
  (fetched-nodes 0)
  (request-count 0)
  (response-bytes 0)
  (promoted-subtrees 0)
  (skipped-subtrees 0)
  (completed-p nil))

(defun snap-sync-report-heal-progress
    (callback processed-nodes reused-nodes fetched-nodes request-count
     response-bytes promoted-subtrees skipped-subtrees completed-p)
  (when callback
    (funcall
     callback
     (%make-snap-sync-heal-progress
      :processed-nodes processed-nodes
      :reused-nodes reused-nodes
      :fetched-nodes fetched-nodes
      :request-count request-count
      :response-bytes response-bytes
      :promoted-subtrees promoted-subtrees
      :skipped-subtrees skipped-subtrees
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
                       (list 1 +snap-sync-legacy-account-task-count+
                             +snap-sync-previous-account-task-count+
                             +snap-sync-account-task-count+)))
    (error "Snap progress must contain one, ~D, ~D, or ~D account tasks"
           +snap-sync-legacy-account-task-count+
           +snap-sync-previous-account-task-count+
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
      (let* ((value (rlp-decode-one record :max-list-items 128))
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
    (multiple-value-bind (verified-p trie)
        (mpt-verify-range-proof
         storage-root entries nil :start (make-byte-vector 32))
      (declare (ignore verified-p))
      (unless trie
        (error "Complete snap storage group did not reconstruct its trie"))
      (snap-sync-populate-verified-trie-records-batch
       database batch (mpt-dirty-node-records trie)))))

(defun snap-sync-populate-partial-storage-group
    (database batch storage-root slots proof)
  "Verify one byte-capped storage prefix and retain every authenticated node.

The range remains deferred because this response does not prove that the
storage trie is complete.  Persisting its reconstructed interior and compact
edge proof is nevertheless safe: every record is content-addressed and the
range proof authenticates it against STORAGE-ROOT.  Final healing can then
reuse this work instead of downloading the same prefix again."
  (let ((entries (snap-sync-storage-entries slots)))
    (when (null entries)
      (error "Snap peer returned an empty byte-capped storage group"))
    (multiple-value-bind (verified-p trie)
        (mpt-verify-range-proof
         storage-root entries proof :start (make-byte-vector 32))
      (declare (ignore verified-p))
      (unless trie
        (error "Byte-capped snap storage group did not reconstruct its range"))
      (snap-sync-populate-verified-trie-records-batch
       database batch (snap-sync-verified-account-records trie proof)))))

(defun snap-sync-fetch-storage-commitments
    (database source state-root commitments byte-limit)
  "Fetch non-empty storage tries in bounded snap/1 multi-account requests.

Geth returns a prefix of the requested accounts.  All groups preceding a
proof are complete tries and are persisted eagerly.  The final proved group
was byte-capped: its authenticated prefix is persisted too, while the remaining
trie is deferred to the content-addressed TrieNodes healing phase.  Completing
a large storage trie here can outlive a public peer's retained pivot and would
force the otherwise verified account page to be retried from its durable
cursor.  Healing reuses every node already on disk and must still reconstruct
the exact authorized state root before completion."
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
                     (populated-p nil))
                 (loop for commitment in requested
                       for slots in groups
                       repeat complete-count
                       do (snap-sync-populate-complete-storage-group
                           database batch (cdr commitment) slots)
                          (setf populated-p t))
                 (when proof
                   (snap-sync-populate-partial-storage-group
                    database batch
                    (cdr (nth (1- received) requested))
                    (nth (1- received) groups)
                    proof)
                   (setf populated-p t))
                 (when populated-p
                   ;; These authenticated, content-addressed nodes do not
                   ;; publish the account cursor. Buffer their atomic WAL
                   ;; records; SNAP-SYNC-COMMIT-ACCOUNT-PAGE follows only after
                   ;; every dependency is verified, and its synchronous batch
                   ;; durably flushes this complete prefix before exposing the
                   ;; cursor. A crash before that seam simply retries the page.
                   (kv-apply-batch-buffered database batch)))
                 ;; A proof marks the last returned group as byte-capped.  Its
                 ;; verified prefix is durable, but do not fully paginate that
                 ;; potentially enormous storage trie inside the account-page
                 ;; transaction. Its root remains in the verified account value
                 ;; and therefore becomes mandatory work for
                 ;; SNAP-SYNC-HEAL-STATE.
                 ;; Preserve that exact dependency with the verified account
                 ;; page.  Once every account range is durable, final healing
                 ;; can start from this bounded set instead of rediscovering it
                 ;; by traversing the already reconstructed account trie.
                 (when proof
                   (push (nth (1- received) requested) deferred))
                 (setf remaining (nthcdr received remaining))))
    (nreverse deferred)))

(defun snap-sync-page-code-hashes (entries)
  (let ((seen (make-hash-table :test #'equalp))
        (hashes '()))
    (dolist (entry entries (nreverse hashes))
      (let* ((account (decode-state-account-rlp (cdr entry)))
             (hash (state-account-code-hash account))
             (bytes (hash32-bytes hash)))
        (unless (or (hash32= hash +empty-code-hash+)
                    (nth-value 1 (gethash bytes seen)))
          (setf (gethash bytes seen) t)
          (push bytes hashes))))))

(defun snap-sync-page-storage-commitments (entries)
  (loop for entry in entries
        for account = (decode-state-account-rlp (cdr entry))
        for root = (state-account-storage-root account)
        unless (hash32= root +empty-trie-hash+)
          collect (cons (car entry) root)))

(defun snap-sync-fetch-codes (source hashes byte-limit)
  (let ((remaining (mapcar #'copy-seq hashes))
        (pending (make-hash-table :test #'equalp))
        (codes '()))
    (dolist (hash remaining)
      (setf (gethash hash pending) t))
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
                   (unless (nth-value 1 (gethash hash pending))
                     (error "Snap peer returned unrequested bytecode"))
                   (push (cons hash (copy-seq code)) codes)
                   (remhash hash pending)))
               (setf remaining
                     (delete-if-not
                      (lambda (hash)
                        (nth-value 1 (gethash hash pending)))
                      remaining))))
    (nreverse codes)))

(defun snap-sync-populate-code-batch (database batch codes)
  "Add hash-verified bytecodes to BATCH without prereading durable storage."
  (declare (ignore database))
  (dolist (entry codes)
    (unless (and (consp entry)
                 (byte-vector-p (car entry))
                 (= 32 (length (car entry)))
                 (byte-vector-p (cdr entry))
                 (bytes= (car entry) (keccak-256 (cdr entry))))
      (error "Snap verified bytecode record is malformed"))
    ;; The response was matched to a requested code hash before this point.
    ;; An unconditional content-addressed put is idempotent for healthy data
    ;; and repairs a corrupt local value without a random read per code blob.
    (kv-batch-put-chain-record batch :code (car entry) (cdr entry)))
  batch)

(defun snap-sync-heal-missing-code-hashes (database hashes)
  "Return distinct missing code hashes in first-seen order using MultiGet."
  (let ((seen (make-hash-table :test #'equalp))
        (unique '())
        (missing '()))
    ;; Account values are peer-derived. Reject malformed commitments before
    ;; they reach either the database key codec or the wire request. EQUALP
    ;; hashes octet vectors by content without quadratic byte comparisons.
    (dolist (hash hashes)
      (unless (and (byte-vector-p hash) (= 32 (length hash)))
        (error "Snap healing code hash must contain exactly 32 bytes"))
      (unless (nth-value 1 (gethash hash seen))
        (setf (gethash hash seen) t)
        (push hash unique)))
    (setf unique (nreverse unique))
    (loop while unique
          for count = (min +kv-get-many-max-keys+ (length unique))
          for identifiers = (coerce (subseq unique 0 count) 'vector)
          do
             (multiple-value-bind (records present)
                 (kv-get-chain-records database :code identifiers)
               (declare (ignore records))
               (loop for hash across identifiers
                     for index from 0
                     unless (= 1 (aref present index))
                       do (push hash missing)))
             (setf unique (nthcdr count unique)))
    (nreverse missing)))

(defun snap-sync-complete-batch (batch progress)
  (kv-batch-put-chain-record
   batch :state-history
   (hash32-bytes (snap-sync-progress-pivot-hash progress))
   (hash32-bytes (snap-sync-progress-state-root progress)))
  (snap-sync-populate-progress-batch batch progress)
  (kv-batch-delete-chain-record
   batch :metadata +snap-sync-heal-checkpoint-identifier+))

(defun snap-sync-completed-progress (progress)
  "Return PROGRESS with its exact authorized state root published complete."
  (snap-sync-make-progress
   :pivot-hash (snap-sync-progress-pivot-hash progress)
   :pivot-number (snap-sync-progress-pivot-number progress)
   :state-root (snap-sync-progress-state-root progress)
   :partial-root (snap-sync-progress-state-root progress)
   :target-hash (snap-sync-progress-target-hash progress)
   :chain-id (snap-sync-progress-chain-id progress)
   :genesis-hash (snap-sync-progress-genesis-hash progress)
   :authority-id (snap-sync-progress-authority-id progress)
   :completed-p t :tasks (snap-sync-progress-tasks progress)))

(defun snap-sync-expand-account-tasks (tasks count)
  "Split TASKS into aligned COUNT partitions without replaying their cursors."
  (snap-sync-validate-account-tasks tasks)
  (loop for (start . limit) in (snap-sync-task-boundaries count)
        for old =
          (find-if
           (lambda (task)
             (and
              (not
               (ethereum-lisp.validation:byte-vector-lexicographic<
                start (snap-sync-account-task-start task)))
              (not
               (ethereum-lisp.validation:byte-vector-lexicographic<
                (snap-sync-account-task-limit task) limit))))
           tasks)
        do (unless old
             (error "Snap task expansion is not aligned with durable ranges"))
        collect
        (cond
          ((snap-sync-account-task-completed-p old)
           (snap-sync-account-task
            :start start :limit limit :completed-p t))
          ((ethereum-lisp.validation:byte-vector-lexicographic<
            limit (snap-sync-account-task-next-origin old))
           (snap-sync-account-task
            :start start :limit limit :completed-p t))
          (t
           (snap-sync-account-task
            :start start :limit limit
            :next-origin
            (if (ethereum-lisp.validation:byte-vector-lexicographic<
                 (snap-sync-account-task-next-origin old) start)
                start
                (snap-sync-account-task-next-origin old)))))))

(defun snap-sync-progress-with-task-count (progress count)
  "Expand resumable account cursors to COUNT disjoint durable tasks."
  (if (or (= count (length (snap-sync-progress-tasks progress)))
          ;; Retain the oldest sixteen-way public layout. The actively measured
          ;; thirty-two-way layout below has aligned boundaries and is expanded
          ;; to sixty-four so more live SNAP sessions can join immediately.
          (and (= count +snap-sync-account-task-count+)
               (= +snap-sync-legacy-account-task-count+
                  (length (snap-sync-progress-tasks progress))))
          ;; A single-source caller can finish a previously partitioned public
          ;; import serially.  Only the multi-source upgrade needs to split a
          ;; legacy one-task cursor.
          (and (= count 1)
               (member
                (length (snap-sync-progress-tasks progress))
                (list +snap-sync-legacy-account-task-count+
                      +snap-sync-previous-account-task-count+
                      +snap-sync-account-task-count+))))
      progress
      (let* ((tasks (snap-sync-progress-tasks progress))
             (replacement
               (cond
                 ((= 1 (length tasks))
                  (snap-sync-make-account-tasks
                   :count count
                   :next-origin (snap-sync-progress-next-origin progress)
                   :completed-p (snap-sync-progress-completed-p progress)))
                 ((and (= count +snap-sync-account-task-count+)
                       (= (length tasks)
                          +snap-sync-previous-account-task-count+))
                  (snap-sync-expand-account-tasks tasks count))
                 (t
                  (error
                   "Persisted snap progress uses an incompatible task layout")))))
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
         :tasks replacement))))

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

(defstruct (snap-sync-page-profile
            (:constructor make-snap-sync-page-profile
                (&key account-count storage-account-count code-count
                      account-request-ms proof-ms storage-ms code-ms metadata-ms
                      buffer-ms total-ms)))
  "Observational wall-clock breakdown for one verified SNAP account page."
  (account-count 0)
  (storage-account-count 0)
  (code-count 0)
  (account-request-ms 0)
  (proof-ms 0)
  (storage-ms 0)
  (code-ms 0)
  (metadata-ms 0)
  (buffer-ms 0)
  (total-ms 0))

(defstruct (snap-sync-page-result
            (:constructor make-snap-sync-page-result
                (&key task-index origin account-records codes deferred-storage
                      healed-subtrees dependency-subtrees next-origin
                      completed-p profile)))
  task-index
  origin
  account-records
  codes
  deferred-storage
  healed-subtrees
  dependency-subtrees
  next-origin
  completed-p
  profile)

(defstruct (snap-sync-storage-page-result
            (:constructor make-snap-sync-storage-page-result
                (&key task-index origin records healed-subtrees next-origin
                      completed-p)))
  task-index
  origin
  records
  healed-subtrees
  next-origin
  completed-p)

(defun snap-sync-elapsed-milliseconds (start end)
  "Return non-negative monotonic milliseconds between internal clock ticks."
  (max 0
       (round
        (* 1000 (- end start))
        internal-time-units-per-second)))

(defun snap-sync-verified-account-records (trie proof)
  "Collect one verified account page's reconstructed and boundary nodes."
  (let ((seen (make-hash-table :test #'equalp))
        (records '()))
    (labels ((add (hash encoded)
               (unless (and (byte-vector-p hash) (= 32 (length hash))
                            (byte-vector-p encoded) (plusp (length encoded)))
                 (error "Snap verified account trie record is malformed"))
               (multiple-value-bind (existing present-p) (gethash hash seen)
                 (when (and present-p (not (bytes= existing encoded)))
                   (error "Snap verified account trie records collide"))
                 (unless present-p
                   (setf (gethash hash seen) encoded)
                   (push (cons hash encoded) records)))))
      (when trie
        (dolist (record (mpt-dirty-node-records trie))
          (add (car record) (cdr record))))
      ;; Boundary proof nodes are decoded and used by MPT-VERIFY-RANGE-PROOF,
      ;; but are clean resolver nodes in its reconstructed trie. Persist their
      ;; raw content too or a later traversal could reach a missing boundary.
      (dolist (encoded proof)
        (add (keccak-256 encoded) encoded)))
    (nreverse records)))

(defun snap-sync-populate-verified-trie-records-batch
    (database batch records)
  "Add state-root-authenticated content-addressed RECORDS to BATCH.

Every caller derives each key from the exact encoded node only after its range
proof has verified.  An unconditional put is therefore idempotent for healthy
state and repairs a corrupt local value.  Avoiding a database probe per node is
essential for SNAP range ingestion, whose write set is much larger than the
wire response.  DATABASE remains in the private signature so callers keep one
uniform persistence interface."
  (declare (ignore database))
  (dolist (record records)
    (unless (and (consp record)
                 (byte-vector-p (car record))
                 (= 32 (length (car record)))
                 (byte-vector-p (cdr record))
                 (plusp (length (cdr record))))
      (error "Snap verified trie record is malformed"))
    (kv-batch-put-chain-record
     batch :trie-node (car record) (cdr record)))
  batch)

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

(defun snap-sync-storage-task-identifier
    (state-root account-hash storage-root task-index)
  (unless (and (integerp task-index)
               (<= 0 task-index)
               (< task-index +snap-sync-storage-task-count+))
    (error "Snap storage range task index is out of bounds"))
  (unless (and (byte-vector-p account-hash) (= 32 (length account-hash)))
    (error "Snap storage range task requires a 32-byte account hash"))
  (concatenate
   'vector +snap-sync-storage-task-identifier-prefix+
   (hash32-bytes state-root) account-hash (hash32-bytes storage-root)
   (vector task-index)))

(defun snap-sync-storage-task-record (task)
  (rlp-encode
   (make-rlp-list
    +snap-sync-storage-task-version+
    (snap-sync-account-task-object task))))

(defun snap-sync-storage-task-from-record (record)
  (handler-case
      (destructuring-bind (version task)
          (snap-sync-rlp-list
           (rlp-decode-one
            record :max-depth 2 :max-list-items 4 :max-total-items 8
            :max-string-bytes 256)
           2 "Snap storage range task")
        (unless (= +snap-sync-storage-task-version+
                   (snap-sync-rlp-uint
                    version "Snap storage range task version"))
          (error "Unsupported snap storage range task version"))
        (snap-sync-account-task-from-object task))
    (rlp-error (condition)
      (error "Invalid snap storage range task RLP: ~A" condition))))

(defun snap-sync-populate-storage-task-batch
    (batch state-root account-hash storage-root task-index task)
  (kv-batch-put-chain-record
   batch :metadata
   (snap-sync-storage-task-identifier
    state-root account-hash storage-root task-index)
   (snap-sync-storage-task-record task))
  batch)

(defun snap-sync-load-or-create-storage-tasks
    (database state-root account-hash storage-root)
  "Load all sixteen durable cursors, or atomically initialize a fresh set."
  (let* ((identifiers
           (coerce
            (loop for index below +snap-sync-storage-task-count+
                  collect
                  (snap-sync-storage-task-identifier
                   state-root account-hash storage-root index))
            'vector)))
    (multiple-value-bind (records present)
        (kv-get-chain-records database :metadata identifiers)
      (let ((present-count (count 1 present)))
        (cond
          ((zerop present-count)
           (let ((tasks
                   (snap-sync-make-account-tasks
                    :count +snap-sync-storage-task-count+))
                 (batch (make-kv-write-batch)))
             (loop for task in tasks
                   for index from 0
                   do (snap-sync-populate-storage-task-batch
                       batch state-root account-hash storage-root index task))
             (kv-apply-batch database batch)
             tasks))
          ((/= present-count +snap-sync-storage-task-count+)
           (ethereum-lisp.validation:storage-fail
            "Persisted snap storage range task set is incomplete"))
          (t
           (loop for record across records
                 collect (snap-sync-storage-task-from-record record))))))))

(defun snap-sync-classify-account-range-subtrees
    (candidates deferred-storage)
  "Split proved account subtrees by their unresolved storage dependencies."
  (let ((dependencies-by-prefix (make-hash-table :test #'equalp))
        (safe-subtrees '())
        (dependency-subtrees '()))
    (dolist (commitment deferred-storage)
      (push commitment
            (gethash
             (snap-sync-account-prefix-bucket (car commitment))
             dependencies-by-prefix)))
    (dolist (candidate candidates)
      (let* ((prefix (car candidate))
             (reference (cdr candidate))
             (dependencies
               (nreverse (gethash prefix dependencies-by-prefix))))
        (cond
          ((null dependencies)
           (push reference safe-subtrees))
          ((<= (length dependencies)
               +snap-sync-account-subtree-dependencies-max+)
           (push (cons reference dependencies) dependency-subtrees)))))
    (values (nreverse safe-subtrees) (nreverse dependency-subtrees))))

(defun snap-sync-buffer-account-page-content
    (database state-root result)
  "Buffer RESULT's verified content before its task cursor is published.

The records and proof metadata are authenticated and content-addressed, hence
safe to write idempotently from the fetching worker.  The coordinator later
publishes the successor cursor with KV-APPLY-BATCH; that synchronous write
flushes this earlier WAL prefix before the cursor becomes durable.  A crash
before that seam can expose no cursor and merely causes the page to be fetched
again."
  (let ((batch (make-kv-write-batch)))
    (snap-sync-populate-verified-trie-records-batch
     database batch (snap-sync-page-result-account-records result))
    (snap-sync-populate-code-batch
     database batch (snap-sync-page-result-codes result))
    (dolist (commitment (snap-sync-page-result-deferred-storage result))
      (snap-sync-populate-deferred-storage-batch
       batch state-root commitment))
    (dolist (reference (snap-sync-page-result-healed-subtrees result))
      (snap-sync-populate-healed-subtree-batch batch reference :account))
    (dolist (entry (snap-sync-page-result-dependency-subtrees result))
      (snap-sync-populate-account-subtree-dependencies-batch
       batch (car entry) (cdr entry)))
    (kv-apply-batch-buffered database batch)
    ;; The coordinator now needs only ordering metadata. Do not retain a large
    ;; page's reconstructed nodes and code while it waits behind other cursors.
    (setf (snap-sync-page-result-account-records result) '()
          (snap-sync-page-result-codes result) '()
          (snap-sync-page-result-deferred-storage result) '()
          (snap-sync-page-result-healed-subtrees result) '()
          (snap-sync-page-result-dependency-subtrees result) '())
    result))

(defun snap-sync-prepare-account-page
    (database source state-root task-index task byte-limit)
  "Fetch and verify one page without advancing authoritative progress."
  (let* ((started-at (get-internal-real-time))
         (origin (snap-sync-account-task-next-origin task))
         (limit (snap-sync-account-task-limit task))
         (request
           (make-snap-get-account-range
            1 (hash32-bytes state-root) origin limit byte-limit))
         (response
           (snap-sync-source-call
            (snap-sync-source-account-range source)
            request "account ranges"))
         (account-response-at (get-internal-real-time))
         (wire-entries (snap-sync-account-entries response))
         (proof (snap-account-range-proof response)))
    (unless (= 1 (snap-account-range-id response))
      (error "Snap account response id mismatch"))
    (when (and (null wire-entries) (null proof))
      (snap-sync-state-unavailable "account-range"))
    ;; Geth's inclusive task limit may produce the first account beyond the
    ;; requested partition.  Verify the complete wire response first, then
    ;; discard that overlap before inserting this task's accounts.
    (multiple-value-bind (verified-p account-trie)
        (if wire-entries
            (mpt-verify-range-proof
             state-root wire-entries proof :start origin)
            (mpt-verify-range-proof
             state-root wire-entries proof :start origin
             :end (snap-sync-increment-hash limit)))
      (declare (ignore verified-p))
      (let* ((account-records
               (snap-sync-verified-account-records account-trie proof))
             (last-wire (and wire-entries (caar (last wire-entries))))
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
                  (snap-sync-increment-hash last-entry)))
           (proof-finished-at (get-internal-real-time))
           (storage-commitments
             (snap-sync-page-storage-commitments entries))
           (deferred-storage
             (snap-sync-fetch-storage-commitments
              database source state-root storage-commitments
              (min byte-limit +snap-sync-storage-request-bytes+)))
           (storage-finished-at (get-internal-real-time))
           (code-hashes (snap-sync-page-code-hashes entries))
           (missing-code-hashes
             (snap-sync-heal-missing-code-hashes database code-hashes))
           (codes
             (if missing-code-hashes
                 (snap-sync-fetch-codes source missing-code-hashes byte-limit)
                 '()))
           (code-finished-at (get-internal-real-time))
           (proved-end (if complete-p limit last-entry))
           (candidates
             (if (and account-trie proved-end)
                 (mpt-proved-range-subtrees
                  account-trie origin proved-end
                  *snap-sync-range-subtree-prefix-nibbles*)
                 '())))
      (when (and (not complete-p) (null next-origin))
        (error "Snap account page did not advance its assigned task"))
      (multiple-value-bind (safe-subtrees dependency-subtrees)
          (snap-sync-classify-account-range-subtrees
           candidates deferred-storage)
        (let* ((metadata-finished-at (get-internal-real-time))
               (profile
                 (make-snap-sync-page-profile
                  :account-count (length entries)
                  :storage-account-count (length storage-commitments)
                  :code-count (length codes)
                  :account-request-ms
                  (snap-sync-elapsed-milliseconds
                   started-at account-response-at)
                  :proof-ms
                  (snap-sync-elapsed-milliseconds
                   account-response-at proof-finished-at)
                  :storage-ms
                  (snap-sync-elapsed-milliseconds
                   proof-finished-at storage-finished-at)
                  :code-ms
                  (snap-sync-elapsed-milliseconds
                   storage-finished-at code-finished-at)
                  :metadata-ms
                  (snap-sync-elapsed-milliseconds
                   code-finished-at metadata-finished-at)))
               (result
                 (make-snap-sync-page-result
                  :task-index task-index
                  :origin (copy-seq origin)
                  :account-records account-records
                  :codes codes
                  :deferred-storage deferred-storage
                  :healed-subtrees safe-subtrees
                  ;; Keep the exact storage gaps beside the authenticated
                  ;; subtree hash so a later pivot can skip the account walk
                  ;; without skipping external dependencies.
                  :dependency-subtrees dependency-subtrees
                  :next-origin next-origin
                  :completed-p complete-p
                  :profile profile)))
          (snap-sync-buffer-account-page-content database state-root result)
          (let ((finished-at (get-internal-real-time)))
            (setf
             (snap-sync-page-profile-buffer-ms profile)
             (snap-sync-elapsed-milliseconds metadata-finished-at finished-at)
             (snap-sync-page-profile-total-ms profile)
             (snap-sync-elapsed-milliseconds started-at finished-at)))
          result))))))

(defun snap-sync-replace-task (tasks index replacement)
  (loop for task in tasks
        for position from 0
        collect (if (= position index)
                    replacement
                    (snap-sync-copy-account-task task))))

(defun snap-sync-commit-account-page (database progress result)
  "Publish RESULT's task cursor after its buffered content is complete."
  (let* ((task-index (snap-sync-page-result-task-index result))
         (task (nth task-index (snap-sync-progress-tasks progress))))
    (unless task
      (error "Snap account result names an unknown task"))
    (unless (and (not (snap-sync-account-task-completed-p task))
                 (bytes= (snap-sync-account-task-next-origin task)
                         (snap-sync-page-result-origin result)))
      (error "Snap account result no longer matches its durable task cursor"))
    (let* ((batch (make-kv-write-batch))
           (previous-root (snap-sync-progress-partial-root progress))
           ;; EMPTY means this is the first page of a fresh import. Once a
           ;; page has independently reconstructed STATE-ROOT, retain that
           ;; value as the same-root range-set witness. Rebase installs a
           ;; distinct poison witness, so later pages cannot publish a plan
           ;; that omits ranges downloaded under the older root.
           (partial-root
             (if (or (hash32= previous-root +empty-trie-hash+)
                     (hash32= previous-root
                              (snap-sync-progress-state-root progress)))
                 (snap-sync-progress-state-root progress)
                 previous-root))
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
      (when (and (snap-sync-tasks-completed-p tasks)
                 (hash32= partial-root
                          (snap-sync-progress-state-root progress)))
        ;; Every buffered range independently reconstructed the same authorized
        ;; root. Publishing this marker with the last cursor makes the
        ;; deferred storage set complete: after restart, absence of a queue
        ;; record means there was no such work.
        (snap-sync-populate-deferred-storage-plan-batch
         batch (snap-sync-progress-state-root progress)))
      ;; This deliberately tiny synchronous batch is the publication seam. It
      ;; flushes all preceding worker WAL writes before exposing the cursor.
      (snap-sync-populate-progress-batch batch next)
      (kv-apply-batch database batch)
      next)))

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
                (&key source start end order response condition)))
  source
  start
  end
  order
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

(defun snap-sync-heal-request-path-sets (missing start end)
  "Encode and sort one MISSING slice with Geth-style storage-path grouping.

Account trie nodes remain independent one-path sets. Storage trie nodes are
sorted by account hash and compact path before all paths for one account share
a single account-hash prefix, avoiding repeated remote account-trie lookups even
when exact DFS work was interleaved. The second value maps response order back
to MISSING, so partial responses retain the caller's durable continuation."
  (let* ((entries
           (loop for index from start below end
                 collect
                 (cons index
                       (snap-sync-heal-work-path-set (aref missing index)))))
         (ordered
           (stable-sort
            entries
            (lambda (left right)
              (let ((left-path (cdr left))
                    (right-path (cdr right)))
                (cond
                  ((ethereum-lisp.validation:byte-vector-lexicographic<
                    (first left-path) (first right-path))
                   t)
                  ((ethereum-lisp.validation:byte-vector-lexicographic<
                    (first right-path) (first left-path))
                   nil)
                  ((< (length left-path) (length right-path)) t)
                  ((> (length left-path) (length right-path)) nil)
                  ((= 1 (length left-path)) nil)
                  (t
                   (ethereum-lisp.validation:byte-vector-lexicographic<
                    (second left-path) (second right-path))))))))
         (path-sets '())
        (storage-account nil)
        (storage-paths '())
        (order (make-array (length ordered))))
    (labels ((flush-storage ()
               (when storage-account
                 (push
                  (cons storage-account (nreverse storage-paths))
                  path-sets)
                 (setf storage-account nil
                       storage-paths nil))))
      (loop for entry in ordered
            for position from 0
            for index = (car entry)
            for work = (aref missing index)
            for path-set = (cdr entry)
            do
               (setf (aref order position) index)
               (if (eq :storage (snap-sync-heal-work-kind work))
                   (let ((account-hash (first path-set))
                         (compact-path (second path-set)))
                     (unless (and storage-account
                                  (bytes= storage-account account-hash))
                       (flush-storage)
                       (setf storage-account account-hash))
                     (push compact-path storage-paths))
                   (progn
                     (flush-storage)
                     (push path-set path-sets))))
      (flush-storage)
      (values (nreverse path-sets) order))))

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
  (let ((range-witness
          (if (hash32= state-root (snap-sync-progress-state-root progress))
              (snap-sync-progress-partial-root progress)
              (let ((candidate
                      (make-hash32
                       (keccak-256
                        (concatenate
                         'vector +snap-sync-rebased-range-witness-domain+
                         (hash32-bytes
                          (snap-sync-progress-state-root progress))
                         (hash32-bytes state-root)
                         (hash32-bytes pivot-hash))))))
                (when (or (hash32= candidate +empty-trie-hash+)
                          (hash32= candidate state-root))
                  (error "Snap rebased range witness collides with a root"))
                candidate))))
    (snap-sync-make-progress
     :pivot-hash pivot-hash :pivot-number pivot-number
     :state-root state-root
     :partial-root range-witness
     :target-hash target-hash
     :chain-id (snap-sync-progress-chain-id progress)
     :genesis-hash (snap-sync-progress-genesis-hash progress)
     :authority-id (snap-sync-progress-authority-id progress)
     :completed-p nil
     :tasks (snap-sync-progress-tasks progress))))

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
      (multiple-value-bind (path-sets order)
          (snap-sync-heal-request-path-sets missing start end)
        (let* ((request
                 (make-snap-get-trie-nodes
                  1 root-bytes path-sets byte-limit))
               (packet
                 (snap-sync-source-call
                  (snap-sync-source-trie-nodes source)
                  request "trie nodes")))
          (unless (= 1 (snap-trie-nodes-id packet))
            (error "Snap trie-node response id mismatch"))
          (when (null (snap-trie-nodes-nodes packet))
            (snap-sync-state-unavailable "trie-nodes"))
          (make-snap-sync-heal-fetch-result
           :source source :start start :end end :order order
           :response packet)))
    (serious-condition (condition)
      (make-snap-sync-heal-fetch-result
       :source source :start start :end end :condition condition))))

#+sbcl
(defun snap-sync-heal-request-round
    (sources missing root-bytes byte-limit)
  "Drain one bounded missing frontier through continuously busy sources.

Each source still owns at most one TrieNodes exchange at a time.  The frontier
is deliberately over-partitioned, however, so a source that answers promptly
claims another disjoint chunk instead of waiting at a global slowest-peer
barrier.  Failed sources stop claiming; their unrequested remainder stays
absent in the caller's exact continuation and is retried after source rotation."
  (unless (and (integerp *snap-sync-heal-request-target-paths*)
               (<= 1 *snap-sync-heal-request-target-paths*
                   +snap-sync-heal-paths-per-source+))
    (error "Snap healing request target must be between 1 and ~D paths"
           +snap-sync-heal-paths-per-source+))
  (let* ((worker-count (min (length sources) (length missing)))
         (chunk-count
           (max
            1
            (min
             (length missing)
             (max
              worker-count
              (ceiling
               (length missing)
               *snap-sync-heal-request-target-paths*)))))
         (chunk-size (ceiling (length missing) chunk-count))
         (next-start (min (length missing) (* worker-count chunk-size)))
         (results '())
         (lock (sb-thread:make-mutex :name "snap-sync-heal-requests"))
         (threads (make-array worker-count :initial-element nil)))
    (when (zerop worker-count)
      (error "Snap healing requires a live source"))
    (labels ((record-result (result)
               (sb-thread:with-mutex (lock)
                 (push result results)))
             (claim-next ()
               (sb-thread:with-mutex (lock)
                 (when (< next-start (length missing))
                   (let ((start next-start))
                     (setf next-start
                           (min (length missing) (+ start chunk-size)))
                     (values start next-start)))))
             (request-chunk (source start end)
               (let ((result
                       (snap-sync-heal-request-chunk
                        source missing start end root-bytes byte-limit)))
                 (record-result result)
                 result))
             (run-worker (index source)
               ;; Give every source one deterministic initial chunk before
               ;; opening the shared tail to work stealing.  This preserves
               ;; peer diversity even when one in-process test source answers
               ;; synchronously, while live fast peers can drain the tail.
               (let* ((start (* index chunk-size))
                      (end (min (length missing) (+ start chunk-size)))
                      (result (request-chunk source start end)))
                 (unless (snap-sync-heal-fetch-result-condition result)
                   (loop
                     (multiple-value-bind (next end) (claim-next)
                       (unless next (return))
                       (when
                           (snap-sync-heal-fetch-result-condition
                            (request-chunk source next end))
                         (return))))))))
      (unwind-protect
           (progn
             (dotimes (index worker-count)
               (let* ((worker-index index)
                      (source (nth index sources)))
                 (if (= worker-count 1)
                     (run-worker worker-index source)
                     (setf
                      (aref threads index)
                      (sb-thread:make-thread
                       (lambda ()
                         (run-worker worker-index source))
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
    (coerce
     (stable-sort results #'< :key #'snap-sync-heal-fetch-result-start)
     'vector)))

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

(defun snap-sync-account-subtree-dependencies-identifier (reference)
  (unless (and (byte-vector-p reference) (= 32 (length reference)))
    (error "Snap account-subtree dependency proof requires a 32-byte hash"))
  (concatenate
   'vector +snap-sync-account-subtree-dependencies-identifier-prefix+
   reference))

(defun snap-sync-account-subtree-dependencies-value (dependencies)
  "Encode one bounded, non-empty account-subtree storage frontier."
  (unless (and (listp dependencies) dependencies
               (<= (length dependencies)
                   +snap-sync-account-subtree-dependencies-max+))
    (error "Snap account-subtree dependency count is out of bounds"))
  (let ((value
          (make-byte-vector (+ 1 (* 64 (length dependencies)))))
        (seen (make-hash-table :test #'equalp)))
    (setf (aref value 0)
          +snap-sync-account-subtree-dependencies-version+)
    (loop for commitment in dependencies
          for offset from 1 by 64
          do
      (unless (and (consp commitment)
                   (byte-vector-p (car commitment))
                   (= 32 (length (car commitment)))
                   (hash32-p (cdr commitment))
                   (not (hash32= (cdr commitment) +empty-trie-hash+)))
        (error "Snap account-subtree dependency is malformed"))
      (let ((identity
              (concatenate
               'vector (car commitment) (hash32-bytes (cdr commitment)))))
        (when (nth-value 1 (gethash identity seen))
          (error "Snap account-subtree dependency is duplicated"))
        (setf (gethash identity seen) t)
        (replace value identity :start1 offset)))
    value))

(defun snap-sync-account-subtree-dependencies-from-value (value)
  "Decode one persisted account-subtree storage frontier or fail closed."
  (unless (and (byte-vector-p value)
               (>= (length value) 65)
               (zerop (mod (1- (length value)) 64))
               (= (aref value 0)
                  +snap-sync-account-subtree-dependencies-version+))
    (ethereum-lisp.validation:storage-fail
     "Persisted snap account-subtree dependency proof is malformed"))
  (let ((count (/ (1- (length value)) 64))
        (seen (make-hash-table :test #'equalp))
        (dependencies '()))
    (when (> count +snap-sync-account-subtree-dependencies-max+)
      (ethereum-lisp.validation:storage-fail
       "Persisted snap account-subtree dependency proof exceeds its bound"))
    (loop for offset from 1 below (length value) by 64
          for account-hash = (subseq value offset (+ offset 32))
          for storage-bytes = (subseq value (+ offset 32) (+ offset 64))
          for storage-root = (make-hash32 storage-bytes)
          do
      (when (hash32= storage-root +empty-trie-hash+)
        (ethereum-lisp.validation:storage-fail
         "Persisted snap account-subtree dependency names an empty trie"))
      (let ((identity
              (concatenate 'vector account-hash storage-bytes)))
        (when (nth-value 1 (gethash identity seen))
          (ethereum-lisp.validation:storage-fail
           "Persisted snap account-subtree dependency is duplicated"))
        (setf (gethash identity seen) t)
        (push (cons account-hash storage-root) dependencies)))
    (nreverse dependencies)))

(defun snap-sync-healed-subtree-bloom-word (reference start)
  "Read one big-endian uint32 from authenticated 32-byte REFERENCE."
  (loop with word = 0
        for index from start below (+ start 4)
        do (setf word (logior (ash word 8) (aref reference index)))
        finally (return word)))

(defun snap-sync-map-healed-subtree-bloom-bits
    (bloom reference kind function)
  (unless (and (typep bloom 'bit-vector)
               (= (length bloom) +snap-sync-healed-subtree-bloom-bits+)
               (byte-vector-p reference) (= 32 (length reference))
               (member kind '(:account :storage :account-dependencies)))
    (error "Snap healed-subtree Bloom input is malformed"))
  (let* ((mask (1- +snap-sync-healed-subtree-bloom-bits+))
         (salt
           (ecase kind
             (:account #x9e3779b9)
             (:storage #x85ebca6b)
             (:account-dependencies #xc2b2ae35)))
         (first
           (logxor salt (snap-sync-healed-subtree-bloom-word reference 0)))
         (step
           (logior 1 (snap-sync-healed-subtree-bloom-word reference 4))))
    (dotimes (index +snap-sync-healed-subtree-bloom-hashes+)
      (funcall function (logand mask (+ first (* index step))))))
  bloom)

(defun snap-sync-add-healed-subtree-bloom (bloom reference kind)
  (snap-sync-map-healed-subtree-bloom-bits
   bloom reference kind (lambda (index) (setf (sbit bloom index) 1))))

(defun snap-sync-healed-subtree-bloom-maybe-p (bloom reference kind)
  "Return false only when REFERENCE is definitely absent from the index."
  (let ((present-p t))
    (snap-sync-map-healed-subtree-bloom-bits
     bloom reference kind
     (lambda (index)
       (when (zerop (sbit bloom index))
         (setf present-p nil))))
    present-p))

(defun snap-sync-index-healed-subtree-prefix
    (database bloom kind identifier-prefix)
  "Sequentially add one durable proof namespace to BLOOM."
  (let ((start (kv-chain-record-key :metadata identifier-prefix))
        (end
          (kv-chain-record-key
           :metadata (snap-sync-byte-prefix-end identifier-prefix)))
        (expected-length (+ (length identifier-prefix) 32)))
    (multiple-value-bind (iterator close-iterator)
        (kv-iterator database :start start :end end)
      (unwind-protect
           (loop
             (multiple-value-bind (key value present-p) (funcall iterator)
               (declare (ignore value))
               (unless present-p (return))
               (let ((identifier
                       (kv-chain-record-key-identifier :metadata key)))
                 ;; A future record with the same textual prefix but a longer
                 ;; schema is outside this version's exact proof namespace.
                 (when (= (length identifier) expected-length)
                   (snap-sync-add-healed-subtree-bloom
                    bloom
                    (subseq identifier (length identifier-prefix))
                    kind)))))
        (funcall close-iterator))))
  bloom)

(defun snap-sync-make-healed-subtree-bloom (database)
  "Index all existing proof keys with sequential reads and bounded memory."
  (let ((bloom
          (make-array +snap-sync-healed-subtree-bloom-bits+
                      :element-type 'bit :initial-element 0)))
    (snap-sync-index-healed-subtree-prefix
     database bloom :account +snap-sync-healed-subtree-identifier-prefix+)
    (snap-sync-index-healed-subtree-prefix
     database bloom :storage
     +snap-sync-healed-storage-subtree-identifier-prefix+)
    (snap-sync-index-healed-subtree-prefix
     database bloom :account-dependencies
     +snap-sync-account-subtree-dependencies-identifier-prefix+)
    bloom))

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

(defun snap-sync-filtered-healed-subtrees-present
    (database references kinds bloom)
  "Use BLOOM negatives to avoid I/O; confirm every positive in RocksDB."
  (unless (= (length references) (length kinds))
    (error "Snap healed-subtree references and kinds differ in length"))
  (let ((result
          (make-array (length references) :element-type 'bit
                                          :initial-element 0))
        (maybe-indices '())
        (maybe-references '())
        (maybe-kinds '()))
    (dotimes (index (length references))
      (when (snap-sync-healed-subtree-bloom-maybe-p
             bloom (aref references index) (aref kinds index))
        (push index maybe-indices)
        (push (aref references index) maybe-references)
        (push (aref kinds index) maybe-kinds)))
    (when maybe-indices
      (let ((indices (coerce (nreverse maybe-indices) 'vector))
            (present
              (snap-sync-healed-subtrees-present
               database
               (coerce (nreverse maybe-references) 'vector)
               (coerce (nreverse maybe-kinds) 'vector))))
        (dotimes (index (length indices))
          (setf (aref result (aref indices index))
                (aref present index)))))
    result))

(defun snap-sync-filtered-healed-subtree-present-p
    (database reference kind bloom)
  "Avoid batch/list allocation for one completion-sentinel proof check."
  (and (snap-sync-healed-subtree-bloom-maybe-p bloom reference kind)
       (snap-sync-healed-subtree-present-p database reference kind)))

(defun snap-sync-filtered-account-subtree-dependencies
    (database references kinds completed bloom)
  "Return dependency lists for incomplete account proof candidates.

Bloom negatives and already complete proofs avoid RocksDB reads. Persisted
values are decoded only after one ordered, bounded metadata MultiGet."
  (unless (and (= (length references) (length kinds))
               (= (length references) (length completed)))
    (error "Snap account-subtree dependency inputs differ in length"))
  (let ((result (make-array (length references) :initial-element nil))
        (maybe-indices '())
        (maybe-identifiers '()))
    (dotimes (index (length references))
      (when (and (eq :account (aref kinds index))
                 (zerop (aref completed index))
                 (snap-sync-healed-subtree-bloom-maybe-p
                  bloom (aref references index) :account-dependencies))
        (push index maybe-indices)
        (push
         (snap-sync-account-subtree-dependencies-identifier
          (aref references index))
         maybe-identifiers)))
    (when maybe-indices
      (let ((indices (coerce (nreverse maybe-indices) 'vector))
            (identifiers (coerce (nreverse maybe-identifiers) 'vector)))
        (multiple-value-bind (values present)
            (snap-sync-heal-chain-record-batch
             database :metadata identifiers)
          (dotimes (index (length indices))
            (when (= 1 (aref present index))
              (setf (aref result (aref indices index))
                    (snap-sync-account-subtree-dependencies-from-value
                     (aref values index))))))))
    result))

(defun snap-sync-populate-healed-subtree-batch
    (batch reference &optional (kind :account))
  (kv-batch-put-chain-record
   batch :metadata (snap-sync-healed-subtree-identifier reference kind)
   +snap-sync-healed-subtree-value+)
  batch)

(defun snap-sync-populate-account-subtree-dependencies-batch
    (batch reference dependencies)
  (kv-batch-put-chain-record
   batch :metadata
   (snap-sync-account-subtree-dependencies-identifier reference)
   (snap-sync-account-subtree-dependencies-value dependencies))
  batch)

(defun snap-sync-range-plan-promotion-identifier (state-root)
  (concatenate
   'vector +snap-sync-range-plan-promotion-prefix+ (hash32-bytes state-root)))

(defun snap-sync-range-plan-promoted-p (database state-root)
  (multiple-value-bind (value present-p)
      (kv-get-chain-record
       database :metadata
       (snap-sync-range-plan-promotion-identifier state-root))
    (when (and present-p
               (not (bytes= value +snap-sync-healed-subtree-value+)))
      (ethereum-lisp.validation:storage-fail
       "Persisted snap range-plan promotion has an unknown version"))
    present-p))

(defun snap-sync-storage-plan-promotion-identifier (storage-root)
  (concatenate
   'vector +snap-sync-storage-plan-promotion-prefix+
   (hash32-bytes storage-root)))

(defun snap-sync-storage-plan-promoted-p (database storage-root)
  (multiple-value-bind (value present-p)
      (kv-get-chain-record
       database :metadata
       (snap-sync-storage-plan-promotion-identifier storage-root))
    (when (and present-p
               (not (bytes= value +snap-sync-healed-subtree-value+)))
      (ethereum-lisp.validation:storage-fail
       "Persisted snap storage-plan promotion has an unknown version"))
    present-p))

(defun snap-sync-deferred-storage-plan-roots (database)
  "Return the bounded set of state roots with complete range-plan markers."
  (let* ((prefix +snap-sync-deferred-storage-plan-prefix+)
         (start (kv-chain-record-key :metadata prefix))
         (end
           (kv-chain-record-key
            :metadata (snap-sync-byte-prefix-end prefix)))
         (expected-length (+ (length prefix) 32))
         (roots '()))
    (multiple-value-bind (iterator close-iterator)
        (kv-iterator database :start start :end end)
      (unwind-protect
           (loop
             (multiple-value-bind (key value present-p) (funcall iterator)
               (unless present-p (return))
               (unless (bytes= value +snap-sync-deferred-storage-value+)
                 (ethereum-lisp.validation:storage-fail
                  "Persisted snap deferred-storage plan has an unknown version"))
               (let ((identifier
                       (kv-chain-record-key-identifier :metadata key)))
                 (unless (= expected-length (length identifier))
                   (ethereum-lisp.validation:storage-fail
                    "Persisted snap deferred-storage plan is malformed"))
                 (push
                  (make-hash32 (subseq identifier (length prefix))) roots)
                 (when (> (length roots)
                          +snap-sync-range-plan-promotion-max-roots+)
                   (ethereum-lisp.validation:storage-fail
                    "Persisted snap range-plan root set exceeds its bound")))))
        (when close-iterator (funcall close-iterator))))
    (nreverse roots)))

(defun snap-sync-storage-range-tasks-completed-p
    (database state-root account-hash storage-root)
  "Check an existing large-storage cursor set without creating missing work."
  (let ((identifiers
          (coerce
           (loop for index below +snap-sync-storage-task-count+
                 collect
                 (snap-sync-storage-task-identifier
                  state-root account-hash storage-root index))
           'vector)))
    (multiple-value-bind (records present)
        (kv-get-chain-records database :metadata identifiers)
      (and (= +snap-sync-storage-task-count+ (count 1 present))
           (loop for record across records
                 always
                   (snap-sync-account-task-completed-p
                    (snap-sync-storage-task-from-record record)))))))

(defun snap-sync-range-plan-fully-durable-p (database state-root)
  "Prove that a range plan's complete account/code/storage set is durable."
  (multiple-value-bind (works trusted-plan-p overflow-p)
      (snap-sync-deferred-storage-works database state-root)
    (and trusted-plan-p
         (not overflow-p)
         (every
          (lambda (work)
            (snap-sync-storage-range-tasks-completed-p
             database state-root
             (snap-sync-heal-work-account-hash work)
             (make-hash32 (snap-sync-heal-work-reference work))))
          works))))

(defun snap-sync-persist-promoted-subtrees
    (database references kind &optional promotion-identifier)
  "Publish reusable subtree proofs, then an optional idempotency marker."
  (let ((remaining references))
    (loop while remaining
          do (let ((batch (make-kv-write-batch)))
               (loop repeat +snap-sync-healed-subtrees-per-batch+
                     while remaining
                     do
                 (snap-sync-populate-healed-subtree-batch
                  batch (pop remaining) kind))
               (kv-apply-batch database batch))))
  (when promotion-identifier
    ;; Publish idempotency only after every independent subtree proof is
    ;; durable. A crash before this batch safely repeats content-addressed
    ;; writes.
    (let ((batch (make-kv-write-batch)))
      (kv-batch-put-chain-record
       batch :metadata promotion-identifier
       +snap-sync-healed-subtree-value+)
      (kv-apply-batch database batch)))
  (length references))

(defun snap-sync-promote-complete-storage-plan
    (database state-root work &optional completed-p)
  "Turn one completed legacy StorageRanges task set into subtree proofs."
  (let ((storage-root
          (make-hash32 (snap-sync-heal-work-reference work))))
    (when (or (snap-sync-storage-plan-promoted-p database storage-root)
              (not
               (or completed-p
                   (snap-sync-storage-range-tasks-completed-p
                    database state-root
                    (snap-sync-heal-work-account-hash work)
                    storage-root))))
      (return-from snap-sync-promote-complete-storage-plan 0))
    (let ((references
            (if (hash32= storage-root +empty-trie-hash+)
                '()
                (mpt-hashed-subtrees-at-prefix-depth
                 (make-persisted-mpt
                  storage-root
                  (lambda (hash) (trie-node-store-get database hash)))
                 *snap-sync-range-subtree-prefix-nibbles*))))
      (snap-sync-persist-promoted-subtrees
       database references :storage
       (snap-sync-storage-plan-promotion-identifier storage-root)))))

(defun snap-sync-account-prefix-bucket (account-hash)
  (let ((nibbles
          (ethereum-lisp.trie.encoding:keybytes-to-nibbles
           account-hash :terminator nil)))
    (copy-seq
     (subseq nibbles 0 *snap-sync-range-subtree-prefix-nibbles*))))

(defun snap-sync-promote-complete-range-plan (database state-root)
  "Turn one trusted range plan into shallow reusable subtree proofs.

The plan already proves every account range and code. Completed large-storage
task sets independently prove their tries and are promoted as storage subtree
proofs.  Account buckets containing an incomplete large-storage dependency are
excluded, while all other buckets can be promoted immediately. Descendants are
never read or revalidated."
  (multiple-value-bind (works trusted-plan-p overflow-p)
      (snap-sync-deferred-storage-works database state-root)
    (unless (and trusted-plan-p (not overflow-p))
      (return-from snap-sync-promote-complete-range-plan 0))
    (let ((complete-works '())
          (incomplete-works '())
          (promoted 0))
      (dolist (work works)
        (if (snap-sync-storage-range-tasks-completed-p
             database state-root
             (snap-sync-heal-work-account-hash work)
             (make-hash32 (snap-sync-heal-work-reference work)))
            (push work complete-works)
            (push work incomplete-works)))
      (dolist (work complete-works)
        (incf promoted
              (snap-sync-promote-complete-storage-plan
               database state-root work t)))
      (unless (snap-sync-range-plan-promoted-p database state-root)
        (let* ((unsafe-buckets (make-hash-table :test #'equalp))
               (prefixed-references
                 (if (hash32= state-root +empty-trie-hash+)
                     '()
                     (mpt-hashed-subtrees-with-prefix-at-depth
                      (make-persisted-mpt
                       state-root
                       (lambda (hash) (trie-node-store-get database hash)))
                      *snap-sync-range-subtree-prefix-nibbles*))))
          (dolist (work incomplete-works)
            (setf
             (gethash
              (snap-sync-account-prefix-bucket
               (snap-sync-heal-work-account-hash work))
              unsafe-buckets)
             t))
          (let ((safe-references
                  (loop for (prefix . reference) in prefixed-references
                        unless (gethash prefix unsafe-buckets)
                          collect reference)))
            (incf
             promoted
             (snap-sync-persist-promoted-subtrees
              database safe-references :account
              ;; Incomplete buckets are retried after their StorageRanges
              ;; cursors finish; do not freeze a partial promotion as final.
              (and (null incomplete-works)
                   (snap-sync-range-plan-promotion-identifier state-root)))))))
      promoted)))

(defun snap-sync-promote-complete-range-plans (database)
  "Backfill shallow subtree proofs for trusted pre-optimization range plans."
  (loop for state-root in (snap-sync-deferred-storage-plan-roots database)
        sum (snap-sync-promote-complete-range-plan database state-root)))

(defun snap-sync-prepare-storage-page
    (source state-root account-hash storage-root task-index task byte-limit)
  "Fetch and authenticate one page of a partitioned large storage trie."
  (let* ((origin (snap-sync-account-task-next-origin task))
         (limit (snap-sync-account-task-limit task))
         (request
           (make-snap-get-storage-ranges
            1 (hash32-bytes state-root) (list (copy-seq account-hash))
            origin limit byte-limit))
         (response
           (snap-sync-source-call
            (snap-sync-source-storage-ranges source)
            request "storage ranges"))
         (groups (snap-storage-ranges-slots response))
         (proof (snap-storage-ranges-proof response)))
    (unless (= 1 (snap-storage-ranges-id response))
      (error "Snap storage response id mismatch"))
    ;; Some snap/1 servers encode an empty proved range as no slot groups,
    ;; while others return one empty group. Both representations are
    ;; unambiguous because large-trie tasks request exactly one account.
    (when (> (length groups) 1)
      (error "Snap peer returned multiple groups for one storage range task"))
    (when (and (null groups) (null proof))
      (snap-sync-state-unavailable "storage-range"))
    (let* ((entries
             (snap-sync-storage-entries (if groups (first groups) '())))
           (last-wire (and entries (caar (last entries)))))
      (multiple-value-bind (verified-p trie)
          (if entries
              (mpt-verify-range-proof
               storage-root entries proof :start origin)
              (mpt-verify-range-proof
               storage-root entries proof :start origin
               :end (snap-sync-increment-hash limit)))
        (declare (ignore verified-p))
        (let* ((completed-p
                 (or (null entries)
                     (null proof)
                     (not
                      (ethereum-lisp.validation:byte-vector-lexicographic<
                       last-wire limit))))
               (next-origin
                 (and (not completed-p) last-wire
                      (snap-sync-increment-hash last-wire)))
               (proved-end (if completed-p limit last-wire))
               (healed-subtrees
                 (if (and trie proved-end)
                     (mapcar
                      #'cdr
                      (mpt-proved-range-subtrees
                       trie origin proved-end
                       *snap-sync-range-subtree-prefix-nibbles*))
                     '())))
          (when (and (not completed-p) (null next-origin))
            (error "Snap storage range page did not advance its task"))
          (make-snap-sync-storage-page-result
           :task-index task-index :origin (copy-seq origin)
           :records (snap-sync-verified-account-records trie proof)
           :healed-subtrees healed-subtrees
           :next-origin next-origin :completed-p completed-p))))))

(defun snap-sync-commit-storage-page
    (database state-root account-hash storage-root tasks result)
  "Atomically install one authenticated storage page and its durable cursor."
  (let* ((task-index (snap-sync-storage-page-result-task-index result))
         (task (nth task-index tasks)))
    (unless task
      (error "Snap storage result names an unknown task"))
    (unless (and (not (snap-sync-account-task-completed-p task))
                 (bytes= (snap-sync-account-task-next-origin task)
                         (snap-sync-storage-page-result-origin result)))
      (error "Snap storage result no longer matches its durable task cursor"))
    (let* ((replacement
             (snap-sync-account-task
              :start (snap-sync-account-task-start task)
              :limit (snap-sync-account-task-limit task)
              :next-origin
              (snap-sync-storage-page-result-next-origin result)
              :completed-p
              (snap-sync-storage-page-result-completed-p result)))
           (next (snap-sync-replace-task tasks task-index replacement))
           (batch (make-kv-write-batch)))
      (snap-sync-populate-verified-trie-records-batch
       database batch (snap-sync-storage-page-result-records result))
      (snap-sync-populate-storage-task-batch
       batch state-root account-hash storage-root task-index replacement)
      ;; Storage leaves have no external state dependencies. Publish these
      ;; range-derived completion proofs in the same batch as their nodes and
      ;; cursor so a crash can never expose a proof ahead of durable content.
      (dolist (reference
               (snap-sync-storage-page-result-healed-subtrees result))
        (snap-sync-populate-healed-subtree-batch
         batch reference :storage))
      (kv-apply-batch database batch)
      next)))

#+sbcl
(defstruct (snap-sync-storage-runtime
            (:constructor make-snap-sync-storage-runtime
                (tasks source-count)))
  (lock (sb-thread:make-mutex :name "snap-sync-storage"))
  (changed (sb-thread:make-waitqueue :name "snap-sync-storage-changed"))
  tasks
  (claims (make-hash-table))
  (events '())
  source-count
  stopped-p)

#+sbcl
(defstruct (snap-sync-storage-worker-event
            (:constructor make-snap-sync-storage-worker-event
                (&key source task-index result condition)))
  source
  task-index
  result
  condition)

#+sbcl
(defun snap-sync-storage-runtime-notify (runtime)
  (sb-thread:condition-broadcast
   (snap-sync-storage-runtime-changed runtime)))

#+sbcl
(defun snap-sync-storage-runtime-claim (runtime source)
  (sb-thread:with-mutex ((snap-sync-storage-runtime-lock runtime))
    (loop
      (when (or (snap-sync-storage-runtime-stopped-p runtime)
                (every #'snap-sync-account-task-completed-p
                       (snap-sync-storage-runtime-tasks runtime)))
        (return (values nil nil)))
      (loop for task in (snap-sync-storage-runtime-tasks runtime)
            for task-index from 0
            unless (or (snap-sync-account-task-completed-p task)
                       (gethash task-index
                                (snap-sync-storage-runtime-claims runtime)))
              do (setf
                  (gethash task-index
                           (snap-sync-storage-runtime-claims runtime))
                  source)
                 (return-from snap-sync-storage-runtime-claim
                   (values task-index (snap-sync-copy-account-task task))))
      (sb-thread:condition-wait
       (snap-sync-storage-runtime-changed runtime)
       (snap-sync-storage-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-storage-runtime-push-event (runtime event)
  (sb-thread:with-mutex ((snap-sync-storage-runtime-lock runtime))
    (setf (snap-sync-storage-runtime-events runtime)
          (nconc (snap-sync-storage-runtime-events runtime) (list event)))
    (snap-sync-storage-runtime-notify runtime)))

#+sbcl
(defun snap-sync-storage-runtime-wait-for-commit
    (runtime task-index source)
  (sb-thread:with-mutex ((snap-sync-storage-runtime-lock runtime))
    (loop while (and
                 (not (snap-sync-storage-runtime-stopped-p runtime))
                 (eq source
                     (gethash task-index
                              (snap-sync-storage-runtime-claims runtime))))
          do (sb-thread:condition-wait
              (snap-sync-storage-runtime-changed runtime)
              (snap-sync-storage-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-storage-worker
    (runtime source state-root account-hash storage-root byte-limit)
  (unwind-protect
       (loop
         (multiple-value-bind (task-index task)
             (snap-sync-storage-runtime-claim runtime source)
           (unless task (return))
           (handler-case
               (let ((result
                       (snap-sync-prepare-storage-page
                        source state-root account-hash storage-root
                        task-index task byte-limit)))
                 (snap-sync-storage-runtime-push-event
                  runtime
                  (make-snap-sync-storage-worker-event
                   :source source :task-index task-index :result result))
                 ;; Bound verified-but-uncommitted data to one page per peer.
                 (snap-sync-storage-runtime-wait-for-commit
                  runtime task-index source))
             (serious-condition (condition)
               (snap-sync-storage-runtime-push-event
                runtime
                (make-snap-sync-storage-worker-event
                 :source source :task-index task-index
                 :condition condition))
               (return)))))
    (sb-thread:with-mutex ((snap-sync-storage-runtime-lock runtime))
      (decf (snap-sync-storage-runtime-source-count runtime))
      (snap-sync-storage-runtime-notify runtime))))

#+sbcl
(defun snap-sync-storage-runtime-next-event (runtime)
  (sb-thread:with-mutex ((snap-sync-storage-runtime-lock runtime))
    (loop
      (when (snap-sync-storage-runtime-events runtime)
        (return (pop (snap-sync-storage-runtime-events runtime))))
      (when (every #'snap-sync-account-task-completed-p
                   (snap-sync-storage-runtime-tasks runtime))
        (return :complete))
      (when (zerop (snap-sync-storage-runtime-source-count runtime))
        (return :exhausted))
      (sb-thread:condition-wait
       (snap-sync-storage-runtime-changed runtime)
       (snap-sync-storage-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-storage-runtime-release
    (runtime task-index source &optional tasks)
  (sb-thread:with-mutex ((snap-sync-storage-runtime-lock runtime))
    (when tasks
      (setf (snap-sync-storage-runtime-tasks runtime) tasks))
    (when (eq source
              (gethash task-index
                       (snap-sync-storage-runtime-claims runtime)))
      (remhash task-index (snap-sync-storage-runtime-claims runtime)))
    (snap-sync-storage-runtime-notify runtime)))

#+sbcl
(defun snap-sync-fill-storage-root
    (database sources state-root account-hash storage-root byte-limit
     &key source-provider on-source-error heal-yield-p)
  "Fill one large storage trie through a restart-safe continuous worker pool.

This is an optimization, not the trust boundary: completed cursors stay durable
and the deferred root remains queued for a final full local traversal. Each
source owns at most one request and verified page at a time, but a fast source
immediately claims another unfinished partition instead of waiting for the
slowest source in a global wave. If every StorageRanges source disappears, the
caller safely falls back to TrieNodes healing with authenticated pages retained."
  (setf sources (remove-duplicates (copy-list sources) :test #'eq))
  (dolist (source sources)
    (unless (snap-sync-source-complete-p source)
      (error "Snap storage range source is incomplete")))
  (when (and source-provider (not (functionp source-provider)))
    (error "Snap storage range source provider must be a function"))
  (let* ((tasks
           (snap-sync-load-or-create-storage-tasks
            database state-root account-hash storage-root))
         (runtime
           (make-snap-sync-storage-runtime tasks (length sources)))
         (threads '()))
    (labels
        ((start-worker (source &optional count-source-p)
           (when count-source-p
             (sb-thread:with-mutex
                 ((snap-sync-storage-runtime-lock runtime))
               (incf (snap-sync-storage-runtime-source-count runtime))
               (snap-sync-storage-runtime-notify runtime)))
           (handler-case
               (let ((worker-source source))
                 (push
                  (sb-thread:make-thread
                   (lambda ()
                     (snap-sync-storage-worker
                      runtime worker-source state-root account-hash storage-root
                      byte-limit))
                   :name "snap-sync-storage-worker")
                  threads))
             (serious-condition (condition)
               (when count-source-p
                 (sb-thread:with-mutex
                     ((snap-sync-storage-runtime-lock runtime))
                   (decf (snap-sync-storage-runtime-source-count runtime))
                   (snap-sync-storage-runtime-notify runtime)))
               (error condition))))
         (active-worker-count ()
           (sb-thread:with-mutex
               ((snap-sync-storage-runtime-lock runtime))
             (snap-sync-storage-runtime-source-count runtime)))
         (refresh-sources ()
           (let ((added 0))
             (when source-provider
               (let ((fresh (funcall source-provider)))
                 (unless (listp fresh)
                   (error "Snap storage range source provider must return a list"))
                 (dolist (source fresh)
                   (unless (snap-sync-source-complete-p source)
                     (error "Snap storage range source provider returned an incomplete source"))
                   (when (and
                          (< (active-worker-count)
                             +snap-sync-storage-task-count+)
                          (not (member source sources :test #'eq)))
                     (setf sources (nconc sources (list source)))
                     (start-worker source t)
                     (incf added)))))
             added)))
      (unwind-protect
           (progn
             (dolist (source sources)
               (start-worker source))
             (refresh-sources)
             (loop
               (let ((event (snap-sync-storage-runtime-next-event runtime)))
                 (case event
                   (:complete (return t))
                   (:exhausted
                    (unless (plusp (refresh-sources))
                      (return nil)))
                   (otherwise
                    (let ((source
                            (snap-sync-storage-worker-event-source event))
                          (task-index
                            (snap-sync-storage-worker-event-task-index event))
                          (condition
                            (snap-sync-storage-worker-event-condition event)))
                      (cond
                        (condition
                         (snap-sync-storage-runtime-release
                          runtime task-index source)
                         (when on-source-error
                           (funcall on-source-error source condition))
                         (when (typep condition
                                      'ethereum-lisp.validation:storage-error)
                           (error condition))
                         (refresh-sources))
                        (t
                         (let* ((current
                                  (sb-thread:with-mutex
                                      ((snap-sync-storage-runtime-lock runtime))
                                    (snap-sync-storage-runtime-tasks runtime)))
                                (next
                                  (snap-sync-commit-storage-page
                                   database state-root account-hash storage-root
                                   current
                                   (snap-sync-storage-worker-event-result event))))
                           (snap-sync-storage-runtime-release
                            runtime task-index source next)
                           (when (and heal-yield-p (funcall heal-yield-p))
                             (error 'snap-sync-heal-yielded))
                           (refresh-sources))))))))))
        (sb-thread:with-mutex ((snap-sync-storage-runtime-lock runtime))
          (setf (snap-sync-storage-runtime-stopped-p runtime) t)
          (snap-sync-storage-runtime-notify runtime))
        (dolist (thread threads)
          (sb-thread:join-thread thread))))))

#-sbcl
(defun snap-sync-fill-storage-root
    (database sources state-root account-hash storage-root byte-limit
     &key source-provider on-source-error heal-yield-p)
  "Portable serial fallback for restart-safe large storage ranges."
  (let ((tasks
          (snap-sync-load-or-create-storage-tasks
           database state-root account-hash storage-root))
        (live (remove-duplicates (copy-list sources) :test #'eq))
        (failed '()))
    (loop
      (when (every #'snap-sync-account-task-completed-p tasks)
        (return t))
      (when source-provider
        (let ((fresh (funcall source-provider)))
          (unless (listp fresh)
            (error "Snap storage range source provider must return a list"))
          (setf live
                (remove-if
                 (lambda (source) (member source failed :test #'eq))
                 (remove-duplicates (append live fresh) :test #'eq)))))
      (dolist (source live)
        (unless (snap-sync-source-complete-p source)
          (error "Snap storage range source is incomplete")))
      (unless live
        (return nil))
      (let* ((source (pop live))
             (task-index
               (position-if-not
                #'snap-sync-account-task-completed-p tasks))
             (task (nth task-index tasks))
             (progress-p nil))
        (handler-case
            (setf
             tasks
             (snap-sync-commit-storage-page
              database state-root account-hash storage-root tasks
              (snap-sync-prepare-storage-page
               source state-root account-hash storage-root task-index task
               byte-limit))
             live (nconc live (list source))
             progress-p t)
          (ethereum-lisp.validation:storage-error (condition)
            (error condition))
          (serious-condition (condition)
            (pushnew source failed :test #'eq)
            (when on-source-error
              (funcall on-source-error source condition))))
        (when (and progress-p heal-yield-p (funcall heal-yield-p))
          (error 'snap-sync-heal-yielded))))))

(defun snap-sync-fill-deferred-storage
    (database sources progress byte-limit
     &key source-provider on-source-error heal-yield-p)
  "Best-effort Geth-style StorageRanges stage before final TrieNodes healing."
  (multiple-value-bind (works trusted-plan-p overflow-p)
      (snap-sync-deferred-storage-works
       database (snap-sync-progress-state-root progress))
    (unless (and trusted-plan-p (not overflow-p))
      (return-from snap-sync-fill-deferred-storage nil))
    (dolist (work works t)
      (unless
          (snap-sync-fill-storage-root
           database sources (snap-sync-progress-state-root progress)
           (snap-sync-heal-work-account-hash work)
           (make-hash32 (snap-sync-heal-work-reference work)) byte-limit
           :source-provider source-provider
           :on-source-error on-source-error
           :heal-yield-p heal-yield-p)
        (return nil)))))

(defun snap-sync-healed-subtree-candidate-p (work)
  "Select trie paths eligible to consume a reusable completion proof."
  (unless (and (integerp *snap-sync-healed-subtree-prefix-nibbles*)
               (<= 1 *snap-sync-healed-subtree-prefix-nibbles* 64))
    (error "Snap healed-subtree prefix depth must be between one and 64"))
  (and (null (snap-sync-heal-work-marker-state work))
       (>= (length (snap-sync-heal-work-path work))
           *snap-sync-healed-subtree-prefix-nibbles*)
       (let ((reference (snap-sync-heal-work-reference work)))
         (and (byte-vector-p reference) (= 32 (length reference))))))

(defun snap-sync-healed-subtree-publication-candidate-p (work)
  "Select the finer boundary at which new completion proofs are published."
  (unless (and (integerp *snap-sync-range-subtree-prefix-nibbles*)
               (<= *snap-sync-healed-subtree-prefix-nibbles*
                   *snap-sync-range-subtree-prefix-nibbles*
                   64))
    (error
     "Snap range subtree depth must be between the lookup depth and 64"))
  (>= (length (snap-sync-heal-work-path work))
      *snap-sync-range-subtree-prefix-nibbles*))

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
  ;; Older deployments may already have a complete authenticated range plan
  ;; but no per-range subtree proofs. Promote it with a shallow walk before the
  ;; Bloom index is built, reducing this rebase to changed/boundary regions.
  (let ((promoted-subtrees
          (snap-sync-promote-complete-range-plans database)))
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
           (healed-subtree-bloom
             (snap-sync-make-healed-subtree-bloom database))
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
           (skipped-subtrees 0)
           (source-round 0)
           (last-checkpoint-processed-nodes processed-nodes))
    (labels
        ((prefer-peer-nodes-p ()
           (and
            *snap-sync-heal-remote-first-p*
            (typep
             database
             'ethereum-lisp.database:rocksdb-key-value-database)))
         (refresh-active-sources ()
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
              request-count response-bytes promoted-subtrees
              skipped-subtrees nil)))
         (read-local-nodes (references &key decoder (disk-p t))
           ;; Preserve the ordered batch contract while satisfying freshly
           ;; fetched hashes from the bounded response cache.  DISK-P may
           ;; deliberately leave other hashes absent so the existing bounded,
           ;; authenticated TrieNodes path fetches them from live peers.
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
             (when (and disk-p uncached-indices)
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
             ;; A failed durable batch unwinds before these negative-filter
             ;; bits become visible to the remainder of the traversal.
             (dolist (entry pending-healed-subtrees)
               (snap-sync-add-healed-subtree-bloom
                healed-subtree-bloom (cdr entry) (car entry)))
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
                 (nth-value
                  1 (gethash identifier pending-healed-subtree-index))
               (unless
                   (snap-sync-filtered-healed-subtree-present-p
                    database reference kind healed-subtree-bloom)
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
                       (let ((cursor 0)
                             (order
                               (snap-sync-heal-fetch-result-order result)))
                         (incf successful-results)
                         (dolist
                             (encoded
                              (snap-trie-nodes-nodes
                               (snap-sync-heal-fetch-result-response result)))
                           (let ((hash (keccak-256 encoded))
                                 (found nil))
                             (loop while (< cursor (length order))
                                   for index = (aref order cursor)
                                   for work = (aref missing index)
                                   for expected =
                                     (snap-sync-heal-work-reference work)
                                   do (incf cursor)
                                      (when (bytes= hash expected)
                                        (setf found index)
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
                 ;; A remote-first round may have skipped durable nodes, so
                 ;; first retire that peer generation and let the next loop
                 ;; perform the ordinary RocksDB batch reads. If those reads
                 ;; also find a genuinely missing node, FETCH-MISSING observes
                 ;; no remaining source and reports the original exhaustion.
                 (setf stack (continuation-stack))
                 (when (snap-sync-heal-checkpoint-frontier-p stack)
                   (persist-checkpoint stack))
                 (when (prefer-peer-nodes-p)
                   (return-from fetch-missing nil))
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
                request-count response-bytes promoted-subtrees
                skipped-subtrees nil)))))
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
                  ;; One local fallback batch remains useful after every peer
                  ;; in a pruned-pivot generation has been retired. A truly
                  ;; absent node reaches FETCH-MISSING and reports exhaustion.
                  (max 1 (length active-sources)))))
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
                                 (snap-sync-filtered-healed-subtrees-present
                                  database candidate-references candidate-kinds
                                  healed-subtree-bloom)
                                 #()))
                           (candidate-dependencies
                             (if candidate-works
                                 (snap-sync-filtered-account-subtree-dependencies
                                  database candidate-references candidate-kinds
                                  candidate-presence healed-subtree-bloom)
                                 #()))
                           (candidate-index 0)
                           (actual-lookups '()))
                      (loop for work across ordered
                            do
                            (if (snap-sync-healed-subtree-candidate-p work)
                                (let ((dependencies
                                        (aref candidate-dependencies
                                              candidate-index)))
                                  (cond
                                    ((= 1
                                        (aref candidate-presence
                                              candidate-index))
                                     (incf skipped-subtrees))
                                    ((and
                                      dependencies
                                      (<= (+ deferred-storage-count
                                             (length dependencies))
                                          +snap-sync-heal-deferred-storage-target+)
                                      (<= (+ (length stack) missing-count
                                             deferred-storage-count
                                             (length dependencies))
                                          +snap-sync-heal-checkpoint-max-works+))
                                     ;; The account trie and its code are
                                     ;; complete. Keep the explicitly listed
                                     ;; storage roots in the ordinary bounded
                                     ;; frontier, then skip the account walk.
                                     (dolist (commitment dependencies)
                                       (defer-storage-reference
                                        (car commitment)
                                        (hash32-bytes (cdr commitment))))
                                     (incf skipped-subtrees))
                                    (t
                                     (push
                                      (snap-sync-make-heal-work
                                       (snap-sync-heal-work-kind work)
                                       (snap-sync-heal-work-account-hash work)
                                       (snap-sync-heal-work-path work)
                                       (snap-sync-heal-work-reference work)
                                       :fetched-p
                                       (snap-sync-heal-work-fetched-p work)
                                       :marker-state
                                       (and
                                        (snap-sync-healed-subtree-publication-candidate-p
                                         work)
                                        :armed))
                                      actual-lookups)))
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
                               :disk-p
                               (not
                                (and
                                 active-sources (prefer-peer-nodes-p)))
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
    (let* ((completed (snap-sync-completed-progress progress))
           (batch (make-kv-write-batch)))
      (snap-sync-complete-batch batch completed)
      (kv-apply-batch database batch)
      (snap-sync-report-heal-progress
       on-heal-progress processed-nodes reused-nodes fetched-nodes
       request-count response-bytes promoted-subtrees skipped-subtrees t)
      completed))))))

(defun snap-sync-fill-storage-then-heal
    (database sources progress byte-limit
     &key source-provider on-source-error on-heal-progress heal-yield-p)
  "Complete range-proved storage, then publish or heal the exact state.

For an unre-based import, every account partition independently authenticated
its records against the same authorized root, persisted code before its cursor,
and atomically published the complete deferred-storage plan with the final
cursor.  When every range-proved storage task is also durable, those independent
proofs already cover the complete state and can publish completion without a
redundant full trie traversal.  Rebased, legacy, oversized, or source-exhausted
plans retain the content-addressed healer as the fail-closed path."
  (unless (snap-sync-tasks-completed-p
           (snap-sync-progress-tasks progress))
    (error "Snap storage completion cannot precede flat-range completion"))
  (let ((storage-completed-p
          (snap-sync-fill-deferred-storage
           database sources progress
           (min byte-limit +snap-sync-storage-request-bytes+)
           :source-provider source-provider
           :on-source-error on-source-error
           :heal-yield-p heal-yield-p)))
    (when (and storage-completed-p
               (hash32=
                (snap-sync-progress-partial-root progress)
                (snap-sync-progress-state-root progress)))
      (let ((completed (snap-sync-completed-progress progress))
            (batch (make-kv-write-batch)))
        ;; The state marker and completed cursor remain one atomic publication;
        ;; a crash before this batch merely repeats already durable proofs.
        (snap-sync-complete-batch batch completed)
        (kv-apply-batch database batch)
        (snap-sync-report-heal-progress
         on-heal-progress 0 0 0 0 0 0 0 t)
        (return-from snap-sync-fill-storage-then-heal completed))))
  (snap-sync-heal-state
   database sources progress byte-limit
   :source-provider source-provider
   :on-source-error on-source-error
   :heal-yield-p heal-yield-p
   :on-heal-progress on-heal-progress))

(defun snap-sync-import-state
    (database source
     &key pivot-hash pivot-number state-root chain-id genesis-hash authority-id
          target-hash
          (byte-limit +snap-sync-request-bytes+) on-progress on-heal-progress
          heal-source-provider range-yield-p heal-yield-p max-pages)
  "Download, verify, and atomically install a CL-authorized pivot state.

Every account-range cursor is committed only after the worker has buffered the
partial trie nodes and bytecodes it names.  Complete small storage tries are
batched eagerly;
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
  (when (and range-yield-p (not (functionp range-yield-p)))
    (error "Snap state import range yield predicate must be a function"))
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
        (snap-sync-fill-storage-then-heal
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
        (when (and range-yield-p (funcall range-yield-p))
          (error 'snap-sync-heal-yielded))
        (when (snap-sync-progress-completed-p progress)
          (return progress))
        (when (snap-sync-tasks-completed-p
               (snap-sync-progress-tasks progress))
          (return
            (snap-sync-fill-storage-then-heal
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
  (failed-sources (make-hash-table :test #'eq))
  (events '())
  source-count
  max-pages
  (pages 0)
  stopped-p)

#+sbcl
(defstruct (snap-sync-multi-event
            (:constructor make-snap-sync-multi-event
                (&key kind source task-index result condition report-p)))
  kind
  source
  task-index
  result
  condition
  report-p)

#+sbcl
(defun snap-sync-multi-notify (runtime)
  (sb-thread:condition-broadcast (snap-sync-multi-runtime-changed runtime)))

#+sbcl
(defun snap-sync-multi-claim-task (runtime source)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (loop
      (cond
        ((or (snap-sync-multi-runtime-stopped-p runtime)
             (gethash source
                      (snap-sync-multi-runtime-failed-sources runtime))
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
                 ;; Each worker has at most one verified but uncommitted page.
                 ;; The fixed per-source bound keeps resident data small while
                 ;; overlapping account I/O with verification, persistence,
                 ;; and a queued storage-heavy sibling page.
                 (snap-sync-multi-wait-for-commit
                  runtime task-index source))
             (serious-condition (condition)
               (let ((report-p nil))
                 (sb-thread:with-mutex
                     ((snap-sync-multi-runtime-lock runtime))
                   (unless (gethash
                            source
                            (snap-sync-multi-runtime-failed-sources runtime))
                     (setf (gethash
                            source
                            (snap-sync-multi-runtime-failed-sources runtime))
                           t
                           report-p t)))
                 (snap-sync-multi-push-event
                  runtime
                  (make-snap-sync-multi-event
                   :kind :error :source source :task-index task-index
                   :condition condition :report-p report-p)))
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
          on-progress on-page-profile on-source-error on-heal-progress
          heal-source-provider range-yield-p heal-yield-p max-pages)
  "Import one pivot through disjoint durable ranges shared across SOURCES.

Sixty-four logical account tasks oversubscribe pinned geth's independent
account/storage schedulers so peer I/O overlaps proof verification and
persistence. At most three workers share each source. Its session remains the
sole RLPx writer while one request per snap response type may be in flight,
matching replies by both type and request id. Workers verify and heal
independent pages concurrently; the caller thread serializes only the progress
batch and callbacks.  ON-PROGRESS receives PROGRESS, SOURCE, and TASK-INDEX
after that task page is durable. ON-PAGE-PROFILE then receives its observational
timing profile, SOURCE, and TASK-INDEX. ON-SOURCE-ERROR receives SOURCE and the
condition after its task has been made retryable by another source.
HEAL-SOURCE-PROVIDER refreshes both the account worker pool and the final
content-addressed traversal. Newly connected sources join the range phase up to
the task concurrency bound; a failed source identity is never started twice in
one import. RANGE-YIELD-P runs only after a verified account page and its
cursor are durable; a true result stops the current pivot without discarding
those cursors. HEAL-YIELD-P is forwarded to final healing."
  (unless (typep database 'key-value-database)
    (error "Snap state import requires a key-value database"))
  (setf sources (remove-duplicates (copy-list sources) :test #'eq))
  (unless sources
    (error "Multi-source snap import requires at least one source"))
  (dolist (source sources)
    (unless (snap-sync-source-complete-p source)
      (error "Multi-source snap import source is incomplete")))
  (when (and heal-source-provider (not (functionp heal-source-provider)))
    (error "Multi-source snap import source provider must be a function"))
  (when (and on-page-profile (not (functionp on-page-profile)))
    (error "Multi-source snap page profile callback must be a function"))
  (when (and range-yield-p (not (functionp range-yield-p)))
    (error "Multi-source snap import range yield predicate must be a function"))
  (setf target-hash (or target-hash pivot-hash))
  (snap-sync-require-hash32 target-hash "Snap consensus target hash")
  (let* ((progress
           (snap-sync-load-progress
            database +snap-sync-account-task-count+
            pivot-hash pivot-number state-root target-hash chain-id
            genesis-hash authority-id))
         (runtime
           (make-snap-sync-multi-runtime progress 0 max-pages))
         (threads '())
         (errors '()))
    (when (snap-sync-progress-completed-p progress)
      (return-from snap-sync-import-state-multi progress))
    (when (snap-sync-tasks-completed-p
           (snap-sync-progress-tasks progress))
      (return-from snap-sync-import-state-multi
        (snap-sync-fill-storage-then-heal
         database sources progress byte-limit
         :source-provider heal-source-provider
         :heal-yield-p heal-yield-p
         :on-source-error on-source-error
         :on-heal-progress on-heal-progress)))
    (labels
        ((start-worker (source)
           (sb-thread:with-mutex
               ((snap-sync-multi-runtime-lock runtime))
             (incf (snap-sync-multi-runtime-source-count runtime))
             (snap-sync-multi-notify runtime))
           (handler-case
               (let ((worker-source source))
                 (push
                  (sb-thread:make-thread
                   (lambda ()
                     (snap-sync-multi-worker
                      runtime database worker-source state-root byte-limit))
                   :name "snap-sync-account-worker")
                  threads))
             (serious-condition (condition)
               (sb-thread:with-mutex
                   ((snap-sync-multi-runtime-lock runtime))
                 (decf (snap-sync-multi-runtime-source-count runtime))
                 (snap-sync-multi-notify runtime))
               (error condition))))
         (active-worker-count ()
           (sb-thread:with-mutex
               ((snap-sync-multi-runtime-lock runtime))
             (snap-sync-multi-runtime-source-count runtime)))
         (start-source-workers (source)
           (let ((started 0))
             (loop repeat +snap-sync-range-workers-per-source+
                   while (< (active-worker-count)
                            (length
                             (snap-sync-progress-tasks
                              (snap-sync-multi-runtime-progress runtime))))
                   do (start-worker source)
                      (incf started))
             started))
         (refresh-range-sources ()
           (let ((added 0))
             (when heal-source-provider
               (let ((fresh (funcall heal-source-provider)))
                 (unless (listp fresh)
                   (error "Multi-source snap import source provider must return a list"))
                 (dolist (source fresh)
                   (unless (snap-sync-source-complete-p source)
                     (error "Multi-source snap import source provider returned an incomplete source"))
                   (when (and
                          (< (active-worker-count)
                             (length
                              (snap-sync-progress-tasks
                               (snap-sync-multi-runtime-progress runtime))))
                          (not (member source sources :test #'eq)))
                     ;; SOURCES is also the permanent identity set for this
                     ;; import. A worker that retired after a timeout or bad
                     ;; response cannot be re-admitted by the live snapshot.
                     (setf sources (nconc sources (list source)))
                     (start-source-workers source)
                     (incf added)))))
             added)))
      (unwind-protect
           (progn
             (dolist (source sources)
               (start-source-workers source))
             (refresh-range-sources)
           (loop
             (let ((event (snap-sync-multi-next-event runtime)))
               (case event
                 (:complete
                  (return (snap-sync-multi-runtime-progress runtime)))
                 (:limited
                  (return (snap-sync-multi-runtime-progress runtime)))
                 (:heal
                  (return
                    (snap-sync-fill-storage-then-heal
                     database sources
                     (snap-sync-multi-runtime-progress runtime)
                     byte-limit :source-provider heal-source-provider
                     :heal-yield-p heal-yield-p
                     :on-source-error on-source-error
                     :on-heal-progress on-heal-progress)))
                 (:exhausted
                  (unless (plusp (refresh-range-sources))
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
                        :account-ranges (nreverse errors))))))
                 (otherwise
                  (let ((source (snap-sync-multi-event-source event))
                        (task-index (snap-sync-multi-event-task-index event)))
                    (ecase (snap-sync-multi-event-kind event)
                      (:error
                       (let ((condition
                               (snap-sync-multi-event-condition event)))
                         (snap-sync-multi-release-claim
                          runtime task-index source)
                         (when (snap-sync-multi-event-report-p event)
                           (push condition errors)
                           (when on-source-error
                             (funcall on-source-error source condition)))
                         (when (typep condition
                                      'ethereum-lisp.validation:storage-error)
                           (error condition))))
                      (:result
                       (handler-case
                           (let* ((result
                                    (snap-sync-multi-event-result event))
                                  (next
                                   (snap-sync-commit-account-page
                                    database
                                    (snap-sync-multi-runtime-progress runtime)
                                    result)))
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
                               (funcall on-progress next source task-index))
                             (when on-page-profile
                               (funcall
                                on-page-profile
                                (snap-sync-page-result-profile result)
                                source task-index))
                             ;; Match geth's moving-pivot behavior at a durable
                             ;; page boundary. Other workers may still own
                             ;; bounded in-flight pages; unwind stops them and
                             ;; their uncommitted results remain retryable.
                             (when (and range-yield-p
                                        (funcall range-yield-p))
                               (error 'snap-sync-heal-yielded))
                             (refresh-range-sources))
                         (serious-condition (condition)
                           ;; A database or merge failure is local and fatal;
                           ;; it must never be misclassified as a bad peer.
                           (error condition)))))))))))
        (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
          (setf (snap-sync-multi-runtime-stopped-p runtime) t)
          (snap-sync-multi-notify runtime))
        (dolist (thread threads)
          (sb-thread:join-thread thread))))))

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
