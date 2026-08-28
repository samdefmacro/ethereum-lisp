(in-package #:ethereum-lisp.snap-sync)

;;;; Verified, resumable snap/1 state import.

(defconstant +snap-sync-progress-version+ 5)
(defconstant +snap-sync-previous-progress-version+ 4)
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
(defconstant +snap-sync-code-hashes-per-request+
  (* (floor +snap-sync-request-bytes+ (* 24 1024)) 4)
  "Maximum bytecode hashes in one geth-sized request.

Deployed EVM code is capped at 24 KiB. Geth requests four times the number of
maximum-sized blobs that fit in a 512 KiB response: enough small contracts to
fill the response without repeatedly retransmitting a page's entire remaining
hash set after the peer reaches its soft byte cap.")
(defconstant +snap-sync-code-batch-workers+ 4
  "Maximum geth-sized ByteCodes batches in the isolated per-page fallback.")
(defconstant +snap-sync-global-code-workers+ 32
  "Import-wide ByteCodes assignments, covering every expected idle SNAP peer.")
(defconstant +snap-sync-dependency-workers+ 32
  "Global account-page dependency jobs advanced independently of range peers.")
(defconstant +snap-sync-cursor-batch-pages+ 16
  "Maximum ready account cursors published by one synchronous WAL batch.")
(defconstant +snap-sync-storage-cursor-batch-pages+ 16
  "Maximum verified storage partition cursors in one durable WAL batch.")
(defconstant +snap-sync-storage-result-buffer-pages+
  +snap-sync-storage-cursor-batch-pages+
  "Maximum verified storage pages waiting behind the single RocksDB writer.

One full write batch lets SNAP peers return to network work while the previous
batch commits, without allowing expanded trie records to grow without bound.")
(defconstant +snap-sync-legacy-account-task-count+ 16
  "Account partition count written by progress versions before oversubscription.")
(defconstant +snap-sync-previous-account-task-count+ 32
  "Account partition count written by the first oversubscribed scheduler.")
(defconstant +snap-sync-account-task-count+ 64
  "Account partitions used by a fresh import.

The session remains the only RLPx writer. It may pipeline one request per snap
response type, while range-proof verification and RocksDB writes happen on
workers after their response is routed. Sixty-four logical partitions bound the
global dependency backlog and keep newly admitted account peers busy without
changing the durable page bound.")
(defconstant +snap-sync-account-inflight-pages+ 16
  "Maximum verified account pages retained across the dependency pipeline.

The sixty-four durable partitions are scheduler granularity, not permission to
retain sixty-four decoded 512-KiB responses. A page expands into account trie
records plus storage/code dependency graphs, and slow StorageRanges work can
otherwise promote dozens of those graphs into SBCL's old generation. Sixteen
matches geth's accountConcurrency while the immediate record/closure release
and phase-boundary collection keep the live heap inside the remote budget.")
(defparameter *snap-sync-range-full-gc-pages* nil
  "Optional committed-page interval for an in-phase full collection.

This is deliberately disabled on the supported public-node profile.  The live
Hoodi gate showed that the former thirty-two-page stop-the-world collection
made the consensus client's five-second Engine upcheck expire.  Bounded page
queues limit live range data, while moving-pivot and range-to-healer boundaries
still join every worker, discard unreachable queues, and collect once.")
(defconstant +snap-sync-range-workers-per-source+ 1
  "One AccountRange dispatcher per source, matching geth's idle-peer model.

Verified pages move to the global dependency queue immediately, so the account
dispatcher can claim another partition without waiting for storage or code.")
(defparameter *snap-sync-range-source-refresh-seconds* 1d0
  "Maximum range-phase delay before admitting newly connected SNAP sources.

The coordinator is normally woken by durable account-page events.  One very
large storage root can postpone such an event for minutes, however, while the
global StorageRanges worker count remains fixed at the smaller peer set that
existed when the import began.  A bounded timed wake keeps that dependency
phase aligned with geth's dynamic idle-peer set without polling the transport
on a worker thread.  Tests may bind a shorter interval.")
(defconstant +snap-sync-storage-task-count+ 16
  "Maximum parallel ranges used to finish one byte-capped storage trie.")
(defconstant +snap-sync-storage-slot-width+ 64
  "Pessimistic hash-plus-value bytes used by geth's storage density estimate.")
(defconstant +snap-sync-heal-paths-per-source+
  +snap-sync-trie-node-lookups-per-request+
  "Maximum healing paths assigned to one source in a concurrent round.")
(defparameter *snap-sync-heal-request-target-paths* 512
  "Target TrieNodes path width while retaining a tail for fast-peer stealing.")
(defconstant +snap-sync-heal-write-batch-bytes+ (* 100 1024)
  "Geth's IdealBatchSize threshold for buffered healer trie-node writes.")
(defconstant +snap-sync-heal-request-target-seconds+ 2d0
  "Target wall time used to learn one peer's TrieNodes request capacity.")
(defconstant +snap-sync-heal-peer-capacity-impact+ 0.2d0
  "EWMA impact for one peer's delivered TrieNodes capacity sample.")
(defconstant +snap-sync-heal-peer-rtt-impact+ 0.1d0
  "EWMA impact for one peer's TrieNodes round-trip sample.")
(defconstant +snap-sync-heal-rate-measurement-impact+ 0.005d0
  "Per-node EWMA impact used by geth's TrieNodes processing-rate tracker.")
(defconstant +snap-sync-heal-throttle-increase+ 1.33d0)
(defconstant +snap-sync-heal-throttle-decrease+ 1.25d0)
(defconstant +snap-sync-heal-min-throttle+ 1d0)
(defconstant +snap-sync-heal-max-throttle+
  +snap-sync-trie-node-lookups-per-request+)
(defconstant +snap-sync-heal-local-reads-per-batch+ 4096
  "Maximum local read width before frontier-aware shrinking.

This matches the database MultiGet key-count boundary.  Small durable
frontiers still shrink against worst-case sixteen-way trie expansion, while a
large transient frontier amortizes the eight bounded reader threads across a
full native batch instead of recreating them once per 512 nodes.")
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
(defconstant +snap-sync-heal-checkpoint-version+ 4)
(defparameter +snap-sync-heal-checkpoint-identifier+
  "snap-state-heal-checkpoint")
(defparameter +snap-sync-healed-subtree-identifier-prefix+
  (ascii-to-bytes "snap-healed-subtree-v2:")
  "Domain-separate durable account-subtree proof keys.")
(defparameter +snap-sync-healed-storage-subtree-identifier-prefix+
  (ascii-to-bytes "snap-healed-storage-subtree-v2:")
  "Domain-separate durable storage-subtree proof keys.")
(defparameter +snap-sync-healed-storage-root-identifier-prefix+
  (ascii-to-bytes "snap-healed-storage-root-v2:")
  "Domain-separate fully closed storage-root proof keys.")
(defparameter +snap-sync-account-subtree-dependencies-identifier-prefix+
  (ascii-to-bytes "snap-account-subtree-dependencies-v2:")
  "Account-trie completion proofs carrying deferred storage dependencies.")
(defparameter +snap-sync-healed-subtree-value+ #(1)
  "Versioned value for a completely verified content-addressed subtree.")
(defparameter +snap-sync-incomplete-node-identifier-prefix+
  (ascii-to-bytes "snap-incomplete-trie-node-v1:")
  "Hash-keyed markers for nodes whose descendant closure is not yet durable.")
(defparameter +snap-sync-incomplete-node-value+ #(1)
  "Versioned value for an incomplete content-addressed trie node.")
(defparameter +snap-sync-complete-node-scheme-identifier+
  "snap-complete-trie-node-scheme")
(defparameter +snap-sync-complete-node-scheme-value+ #(2)
  "Marks a trie store whose every incomplete SNAP node follows closure epoch 2.")
(defparameter +snap-sync-legacy-complete-node-scheme-value+ #(1)
  "Recognized but never trusted marker from the pre-closure-safe epoch.")
(defconstant +snap-sync-node-completions-per-batch+ 2048)
(defconstant +snap-sync-account-subtree-dependencies-version+ 1)
(defconstant +snap-sync-account-subtree-dependencies-max+ 64
  "Maximum deferred storage roots carried by one account-subtree proof.")
(defparameter *snap-sync-healed-subtree-prefix-nibbles* 4
  "Minimum trie depth at which the healer consumes completion proofs.")
(defparameter *snap-sync-range-subtree-prefix-nibbles* 4
  "Coarse trie depth published by range proofs and shallow legacy promotion.

Range ingestion publishes the same four-nibble closure boundary that the
healer consumes. This mirrors geth's complete-hash shortcut: an unchanged
bucket is rejected by the in-memory Bloom filter or accepted by one metadata
lookup before any descendant node is read. Older finer proofs remain valid and
are still consumed below a changed coarse bucket.")
(defparameter *snap-sync-range-nested-subtree-prefix-nibbles* 5
  "Nested range-proof depth retained below the public four-nibble boundary.

Publishing both depths keeps the one-lookup fast path for an unchanged coarse
bucket while allowing a later pivot that changes that bucket to reuse its
unchanged children.  A depth-five layer bounds proof metadata to at most sixteen
children per coarse bucket and avoids turning one touched prefix into a full
descendant scan.")
(defconstant +snap-sync-healed-subtrees-per-batch+ 2048
  "Maximum completed subtree proofs published by one durable write batch.")
(defconstant +snap-sync-healed-subtree-bloom-bits+ (ash 1 27)
  "Fixed 16-MiB negative filter for durable healed-subtree proofs.")
(defconstant +snap-sync-healed-subtree-bloom-hashes+ 4
  "Double-hashed bit probes per healed-subtree proof identifier.")
(defparameter +snap-sync-deferred-storage-identifier-prefix+
  (ascii-to-bytes "snap-deferred-storage-v2:")
  "Prefix for state-root-scoped storage work discovered during range import.")
(defparameter +snap-sync-deferred-storage-plan-prefix+
  (ascii-to-bytes "snap-deferred-storage-plan-v2:")
  "Prefix for the trusted marker that says the deferred work set is complete.")
(defparameter +snap-sync-deferred-storage-value+ #(1)
  "Versioned value shared by deferred storage work and plan markers.")
(defparameter +snap-sync-range-plan-promotion-prefix+
  (ascii-to-bytes "snap-range-plan-promoted-v5:"))
(defparameter +snap-sync-storage-plan-promotion-prefix+
  (ascii-to-bytes "snap-storage-plan-promoted-v7:"))
(defconstant +snap-sync-range-plan-promotion-max-roots+ 64)
(defparameter +snap-sync-legacy-storage-task-identifier-prefix+
  (ascii-to-bytes "snap-storage-range-task-v3:")
  "State-root-scoped cursor prefix written before exact-root reuse.")
(defparameter +snap-sync-storage-task-identifier-prefix+
  (ascii-to-bytes "snap-storage-range-task-v4:")
  "Prefix for restart-safe large-contract StorageRanges cursors.

Version four keys progress by account hash and exact storage root, so an
unchanged content-addressed storage trie resumes across a moving state pivot.
Version three added authenticated-prefix seeding but scoped the same exact-root
cursor to one state root, needlessly replaying large contracts after a rebase.")
(defconstant +snap-sync-storage-task-version+ 1)
(defparameter +snap-sync-rebased-range-witness-domain+
  (ascii-to-bytes "snap-rebased-range-witness-v1:")
  "Domain for a non-root witness that permanently disables range-set plans.")
(defconstant +snap-sync-deferred-storage-max-works+ 8192
  "Maximum direct storage frontier loaded into one resumable heal checkpoint.")
(defconstant +snap-sync-heal-checkpoint-frontier-target+ 4096)
(defconstant +snap-sync-heal-checkpoint-max-works+ 8192)
(defconstant +snap-sync-heal-live-frontier-max-works+ (* 128 1024)
  "Maximum in-memory healer work across DFS, deferred, queued, and in-flight work.

The durable checkpoint deliberately remains much smaller. A resumed legal
8,192-work checkpoint must nevertheless have enough transient room to fill the
same 1,024-path per-peer requests as geth instead of degenerating to one remote
round trip per node. This fixed live cap covers all fifty 1,024-path peer
flights plus bounded trie expansion without making peer input unbounded.")
(defparameter *snap-sync-heal-pipeline-refill-work-quantum* 4096
  "Maximum local works examined by one live-pipeline refill.

The remote event loop must return to completed peer responses even when a
mostly local trie would otherwise scan millions of reusable nodes while trying
to fill every vacant remote slot. Four geth-sized request widths retain large
ordered MultiGets without letting local discovery monopolize the coordinator.")
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

(define-condition snap-sync-request-timeout (error) ()
  (:documentation
   "One SNAP request expired without proving the peer session unusable.

Transport adapters specialize this condition with request metadata. Schedulers
must retry its immutable work without retiring the source identity; malformed
frames, socket failures, and validation errors remain ordinary fatal source
conditions."))

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
                (&key account-range storage-ranges bytecodes bytecodes-batch
                      storage-ranges-verified bytecodes-batch-verified
                      trie-node-capacity trie-nodes)))
  account-range
  storage-ranges
  bytecodes
  ;; Optional geth-style assignment callback. It receives the still-missing
  ;; hashes and the response byte ceiling, then returns RESPONSE and the exact
  ;; hash subset selected after reserving an idle peer. Fixed/test sources keep
  ;; using BYTECODES and the protocol-level fallback below.
  bytecodes-batch
  ;; Production pool callbacks execute the supplied response verifier before
  ;; releasing the actual peer reservation. This keeps malformed/pruned peer
  ;; attribution at the transport that answered, rather than the unrelated
  ;; AccountRange source whose page discovered the dependency.
  storage-ranges-verified
  bytecodes-batch-verified
  ;; Optional live TrieNodes item capacity from the transport's shared SNAP
  ;; message-rate tracker. Production sources expose this so the healer uses
  ;; the same peer throughput/timeout controller as every other SNAP message.
  ;; Fixed and isolated test sources may omit it and retain the local fallback.
  trie-node-capacity
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
                      completed-p complete-node-scheme-p tasks)))
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
  complete-node-scheme-p
  tasks)

(defstruct (snap-sync-heal-progress
            (:constructor %make-snap-sync-heal-progress
                (&key processed-nodes reused-nodes fetched-nodes request-count
                      response-bytes promoted-subtrees skipped-subtrees
                      frontier-works deferred-storage-works remote-works
                      known-incomplete-nodes
                      completed-p)))
  "One cumulative, observational snapshot of final TrieNodes healing.

PROCESSED-NODES includes decoded inline and hash-addressed trie nodes.
REUSED-NODES counts hash-addressed nodes read from the local database, while
FETCHED-NODES and RESPONSE-BYTES count accepted TrieNodes response blobs.
REQUEST-COUNT includes failover attempts. PROMOTED-SUBTREES counts legacy range
proofs converted into completion records at startup. SKIPPED-SUBTREES counts
such records that stopped traversal below a content-addressed root during the
current healer invocation. FRONTIER-WORKS is the currently discovered local,
deferred-storage, and remote work; it can grow as decoded nodes reveal children
and therefore is not a remaining-work denominator. KNOWN-INCOMPLETE-NODES is
the conservative durable-marker population and may include content from an
older pivot that the current root never reaches. These counters are
observational and not consensus-visible."
  (processed-nodes 0)
  (reused-nodes 0)
  (fetched-nodes 0)
  (request-count 0)
  (response-bytes 0)
  (promoted-subtrees 0)
  (skipped-subtrees 0)
  (frontier-works 0)
  (deferred-storage-works 0)
  (remote-works 0)
  (known-incomplete-nodes 0)
  (completed-p nil))

(defun snap-sync-report-heal-progress
    (callback processed-nodes reused-nodes fetched-nodes request-count
     response-bytes promoted-subtrees skipped-subtrees frontier-works
     deferred-storage-works remote-works known-incomplete-nodes completed-p)
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
      :frontier-works frontier-works
      :deferred-storage-works deferred-storage-works
      :remote-works remote-works
      :known-incomplete-nodes known-incomplete-nodes
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
          target-hash chain-id genesis-hash authority-id completed-p
          complete-node-scheme-p tasks)
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
     :complete-node-scheme-p (not (null complete-node-scheme-p))
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
    (if (snap-sync-progress-complete-node-scheme-p progress) 1 0)
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

(defun snap-sync-progress-from-v5-items (items)
  (destructuring-bind
      (version pivot-hash pivot-number state-root next-origin partial-root
       target-hash chain-id genesis-hash authority-id completed
       complete-node-scheme task-list)
      items
    (declare (ignore version))
    (let* ((completed-p
             (snap-sync-completion-flag
              completed "Snap completion flag"))
           (complete-node-scheme-p
             (snap-sync-completion-flag
              complete-node-scheme "Snap complete-node scheme flag"))
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
             :complete-node-scheme-p complete-node-scheme-p
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
                         +snap-sync-previous-progress-version+))
           (unless (= 12 (length items))
             (error "Snap sync progress must contain 12 fields"))
           (snap-sync-progress-from-v3-items items))
          ((= version +snap-sync-progress-version+)
           (unless (= 13 (length items))
             (error "Snap sync progress must contain 13 fields"))
           (snap-sync-progress-from-v5-items items))
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

(defun snap-sync-complete-node-scheme-present-p (database)
  (multiple-value-bind (value present-p)
      (kv-get-chain-record
       database :metadata +snap-sync-complete-node-scheme-identifier+)
    (cond
      ((not present-p) nil)
      ((bytes= value +snap-sync-complete-node-scheme-value+) t)
      ;; Epoch one could remove a storage-root negative marker before the
      ;; final healer had proved descendant closure. Keep all trie content,
      ;; but make absence of an old marker mean nothing after an upgrade.
      ((bytes= value +snap-sync-legacy-complete-node-scheme-value+) nil)
      (t
       (ethereum-lisp.validation:storage-fail
        "Persisted snap complete-node scheme marker is malformed")))))

(defun snap-sync-trie-node-store-empty-p (database)
  (multiple-value-bind (iterator close-iterator)
      (kv-iterator
       database
       :start (kv-chain-record-key :trie-node (make-byte-vector 0))
       :end (kv-chain-record-key :code (make-byte-vector 0)))
    (unwind-protect
         (not (nth-value 2 (funcall iterator)))
      (when close-iterator (funcall close-iterator)))))

(defun snap-sync-enable-complete-node-scheme-p (database)
  "Enable geth-like hash presence only for a store born under this contract."
  (cond
    ((snap-sync-complete-node-scheme-present-p database) t)
    ((not (snap-sync-trie-node-store-empty-p database)) nil)
    (t
     (let ((batch (make-kv-write-batch)))
       (kv-batch-put-chain-record
        batch :metadata +snap-sync-complete-node-scheme-identifier+
        +snap-sync-complete-node-scheme-value+)
       (kv-apply-batch database batch))
     t)))

(defun snap-sync-disable-complete-node-scheme (database)
  "Revoke the store contract when resuming progress written by older code."
  (when (snap-sync-complete-node-scheme-present-p database)
    (let ((batch (make-kv-write-batch)))
      (kv-batch-delete-chain-record
       batch :metadata +snap-sync-complete-node-scheme-identifier+)
      (kv-apply-batch database batch))))

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

(defun snap-sync-range-subtree-depths ()
  "Return validated coarse and nested range-proof publication depths."
  (unless (and
           (integerp *snap-sync-range-subtree-prefix-nibbles*)
           (<= 1 *snap-sync-range-subtree-prefix-nibbles* 64)
           (integerp *snap-sync-range-nested-subtree-prefix-nibbles*)
           (<= *snap-sync-range-subtree-prefix-nibbles*
               *snap-sync-range-nested-subtree-prefix-nibbles*
               64))
    (error "Snap range subtree depths must be ordered integers from one to 64"))
  (remove-duplicates
   (list *snap-sync-range-subtree-prefix-nibbles*
         *snap-sync-range-nested-subtree-prefix-nibbles*)))

(defun snap-sync-proved-range-subtrees (trie start end)
  "Return authenticated coarse and nested subtree groups for one proved range."
  (let ((subtrees '())
        (groups '()))
    (dolist (depth (snap-sync-range-subtree-depths))
      (multiple-value-bind (depth-subtrees depth-groups)
          (mpt-proved-range-subtrees trie start end depth)
        (setf subtrees (nconc subtrees depth-subtrees)
              groups (nconc groups depth-groups))))
    (values subtrees groups)))

(defstruct (snap-sync-verified-storage-group
            (:constructor make-snap-sync-verified-storage-group
                (&key commitment entries proof trie partial-p)))
  "One proof-verified StorageRanges group awaiting local materialization."
  commitment
  entries
  proof
  trie
  partial-p)

(defun snap-sync-verify-complete-storage-group (commitment slots)
  "Verify one complete storage group while its answering peer is reserved."
  (let ((entries (snap-sync-storage-entries slots)))
    (when (null entries)
      (error "Snap peer returned an empty group for a non-empty storage root"))
    (multiple-value-bind (verified-p trie)
        (mpt-verify-range-proof
         (cdr commitment) entries nil :start (make-byte-vector 32))
      (declare (ignore verified-p))
      (unless trie
        (error "Complete snap storage group did not reconstruct its trie"))
      (make-snap-sync-verified-storage-group
       :commitment commitment :entries entries :trie trie :partial-p nil))))

(defun snap-sync-verify-partial-storage-group (commitment slots proof)
  "Verify one byte-capped storage prefix while its peer is reserved."
  (let ((entries (snap-sync-storage-entries slots)))
    (when (null entries)
      (error "Snap peer returned an empty byte-capped storage group"))
    (multiple-value-bind (verified-p trie)
        (mpt-verify-range-proof
         (cdr commitment) entries proof :start (make-byte-vector 32))
      (declare (ignore verified-p))
      (unless trie
        (error "Byte-capped snap storage group did not reconstruct its range"))
      (make-snap-sync-verified-storage-group
       :commitment commitment :entries entries :proof proof :trie trie
       :partial-p t))))

(defun snap-sync-populate-verified-storage-group
    (database batch state-root group)
  "Materialize proof-verified GROUP after releasing its answering peer.

A partial range remains deferred because it does not prove that the storage
trie is complete.  Persisting its reconstructed interior and compact edge
proof is nevertheless safe: every record is content-addressed and the range
proof authenticates it against STORAGE-ROOT.  Final healing can then reuse
this work instead of downloading the same prefix again.  A complete group
publishes its authenticated storage root immediately."
  (let* ((commitment (snap-sync-verified-storage-group-commitment group))
         (account-hash (car commitment))
         (storage-root (cdr commitment))
         (entries (snap-sync-verified-storage-group-entries group))
         (proof (snap-sync-verified-storage-group-proof group))
         (trie (snap-sync-verified-storage-group-trie group)))
    (if (snap-sync-verified-storage-group-partial-p group)
        (let* ((last-key (caar (last entries)))
               (records (snap-sync-verified-account-records trie proof))
               (groups
                 (nth-value
                  1
                  (snap-sync-proved-range-subtrees
                   trie (make-byte-vector 32) last-key)))
               (complete-references
                 (loop for group in groups append (third group)))
               (incomplete
                 (snap-sync-incomplete-record-hashes
                  records complete-references)))
          (snap-sync-populate-verified-trie-records-batch
           database batch records)
          (snap-sync-delete-incomplete-records-batch
           batch complete-references)
          (snap-sync-populate-incomplete-records-batch batch incomplete)
          ;; Geth turns this exact nil-bound response into the first large
          ;; storage subtask and continues after its last authenticated slot.
          ;; Persist the same cursor in the content batch. Re-requesting the
          ;; prefix from zero with explicit Origin/Limit is both redundant and
          ;; unavailable on hash-scheme peers which retained the snapshot but no
          ;; longer retain the historical trie proof for that explicit range.
          (snap-sync-seed-storage-tasks-batch
           database batch state-root account-hash storage-root
           (snap-sync-increment-hash last-key) last-key (length entries)))
        (let ((records (mpt-dirty-node-records trie)))
          (snap-sync-populate-verified-trie-records-batch
           database batch records)
          ;; A previous byte-capped attempt may have marked the same content
          ;; as open. This complete root proof supersedes those negatives.
          (snap-sync-delete-incomplete-records-batch
           batch (mapcar #'car records))
          ;; Storage leaves have no external dependencies. Publish the whole
          ;; root as geth's exact hash-presence shortcut.
          (snap-sync-populate-healed-subtree-batch
           batch (hash32-bytes storage-root) :storage-root))))
  batch)

(defun snap-sync-fetch-storage-commitment-request
    (database source state-root requested byte-limit)
  "Fetch, verify, and buffer one bounded StorageRanges request.

Return the number of commitments covered and the byte-capped commitment, if
the final returned group remains open. Keeping response validation inside this
call lets the multi-peer scheduler retire the exact peer that supplied a bad
response before retrying the same immutable request elsewhere."
  (let ((request
          (make-snap-get-storage-ranges
           1 (hash32-bytes state-root)
           (mapcar #'car requested)
           (make-byte-vector 0) (make-byte-vector 0) byte-limit)))
    (labels
        ((verify (response)
           (let* ((groups (snap-storage-ranges-slots response))
                  (proof (snap-storage-ranges-proof response))
                  (received (length groups)))
             (unless (= 1 (snap-storage-ranges-id response))
               (error "Snap storage response id mismatch"))
             (when (and (null groups) (null proof))
               (snap-sync-state-unavailable "storage-range"))
             (when (or (zerop received) (> received (length requested)))
               (error "Snap peer returned an invalid storage group count"))
             (let ((complete-count (if proof (1- received) received))
                   (verified-groups '()))
               (loop for commitment in requested
                     for slots in groups
                     repeat complete-count
                     do (push
                         (snap-sync-verify-complete-storage-group
                          commitment slots)
                         verified-groups))
               (when proof
                 (let ((commitment (nth (1- received) requested)))
                   (push
                    (snap-sync-verify-partial-storage-group
                     commitment (nth (1- received) groups) proof)
                    verified-groups)))
               (values received
                       (and proof (nth (1- received) requested))
                       (nreverse verified-groups))))))
      (multiple-value-bind (received open-commitment verified-groups)
          (if (functionp (snap-sync-source-storage-ranges-verified source))
              (funcall
               (snap-sync-source-storage-ranges-verified source)
               request #'verify)
              (verify
               (snap-sync-source-call
                (snap-sync-source-storage-ranges source)
                request "storage ranges")))
        ;; Keep proof verification inside the exact peer reservation, but match
        ;; geth by returning that peer to the idle StorageRanges pool before
        ;; generating records, subtree metadata, and the WAL batch from the
        ;; already authenticated tries.
        (when verified-groups
          (let ((batch (make-kv-write-batch)))
            (dolist (group verified-groups)
              (snap-sync-populate-verified-storage-group
               database batch state-root group))
            ;; The later synchronous account cursor flushes this prefix before
            ;; exposing progress which depends on it.
            (kv-apply-batch-buffered database batch)))
        (values received open-commitment)))))

(defun snap-sync-fetch-storage-commitments-serial
    (database source state-root commitments byte-limit)
  "Fetch one storage commitment chunk in bounded snap/1 requests.

Geth returns a prefix of the requested accounts.  All groups preceding a
proof are complete tries and are persisted eagerly.  The final proved group
was byte-capped: its authenticated prefix is persisted too and returned as an
open commitment.  The production account-task boundary immediately completes
that commitment through restart-safe partitioned StorageRanges before its
account cursor advances; final healing remains the closure oracle."
  (let ((remaining commitments)
        (deferred '()))
    (loop while remaining
          do (let* ((count
                      (min +snap-sync-storage-accounts-per-request+
                           (length remaining)))
                    (requested (subseq remaining 0 count)))
               (multiple-value-bind (received open-commitment)
                   (snap-sync-fetch-storage-commitment-request
                    database source state-root requested byte-limit)
                 ;; A proof marks the last returned group as byte-capped. Its
                 ;; verified prefix is durable, while final healing completes
                 ;; the exact root after every account range is published.
                 (when open-commitment
                   (push open-commitment deferred))
                 (setf remaining (nthcdr received remaining)))))
    (nreverse deferred)))

(defun snap-sync-fetch-storage-commitments
    (database source state-root commitments byte-limit)
  "Fetch non-empty storage tries in geth-sized multi-account requests.

The importer already has many account pages in flight and the peer pool permits
only one StorageRanges request per peer. Keep each page serial within that
global scheduler: adding child workers only lengthens the typed request queues
and increases timeout pressure without creating another on-wire slot."
  (snap-sync-fetch-storage-commitments-serial
   database source state-root commitments byte-limit))

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

(defun snap-sync-code-hash-batches (hashes)
  "Partition HASHES into geth-sized ByteCodes request batches."
  (loop with remaining = hashes
        while remaining
        for count = (min +snap-sync-code-hashes-per-request+
                         (length remaining))
        collect (subseq remaining 0 count)
        do (setf remaining (nthcdr count remaining))))

(defun snap-sync-fetch-code-request (source hashes byte-limit)
  "Fetch and validate one peer-selected ByteCodes request from HASHES."
  (labels
      ((verify (response requested)
         (unless (and requested
                      (<= (length requested)
                          +snap-sync-code-hashes-per-request+)
                      (every
                       (lambda (hash) (member hash hashes :test #'bytes=))
                       requested))
           (error "Snap bytecode scheduler selected an invalid hash batch"))
         (unless (= 1 (snap-bytecodes-id response))
           (error "Snap bytecode response id mismatch"))
         (let ((requested-pending (make-hash-table :test #'equalp))
               (received (snap-bytecodes-codes response))
               (codes '()))
           (when (null received)
             (snap-sync-state-unavailable "bytecodes"))
           (dolist (hash requested)
             (setf (gethash hash requested-pending) t))
           (dolist (code received)
             (let ((hash (keccak-256 code)))
               (unless (nth-value 1 (gethash hash requested-pending))
                 (error "Snap peer returned unrequested bytecode"))
               (push (cons hash (copy-seq code)) codes)
               (remhash hash requested-pending)))
           (values (nreverse codes) requested))))
    (cond
      ((functionp (snap-sync-source-bytecodes-batch-verified source))
       (funcall
        (snap-sync-source-bytecodes-batch-verified source)
        hashes byte-limit #'verify))
      ((functionp (snap-sync-source-bytecodes-batch source))
       (multiple-value-call #'verify
         (funcall
          (snap-sync-source-bytecodes-batch source) hashes byte-limit)))
      (t
       (let* ((count
                (min +snap-sync-code-hashes-per-request+ (length hashes)))
              (requested (subseq hashes 0 count))
              (request (make-snap-get-bytecodes 1 requested byte-limit)))
         (verify
          (snap-sync-source-call
           (snap-sync-source-bytecodes source) request "bytecodes")
          requested))))))

(defun snap-sync-fetch-code-hash-batch (source hashes byte-limit)
  "Fetch one bounded hash batch, rescheduling each soft-cap tail request."
  (let ((remaining (mapcar #'copy-seq hashes))
        (pending (make-hash-table :test #'equalp))
        (codes '()))
    (dolist (hash remaining)
      (setf (gethash hash pending) t))
    (loop while remaining
          do (multiple-value-bind (received requested)
                 (snap-sync-fetch-code-request source remaining byte-limit)
               (declare (ignore requested))
               (dolist (entry received)
                 (push entry codes)
                 (remhash (car entry) pending))
               (setf remaining
                     (delete-if-not
                      (lambda (hash)
                        (nth-value 1 (gethash hash pending)))
                      remaining))))
    (nreverse codes)))

#+sbcl
(defun snap-sync-fetch-code-batches-concurrently
    (source batches byte-limit)
  "Fetch BATCHES with a bounded worker pool and retain batch result order."
  (let* ((count (length batches))
         (worker-count (min count +snap-sync-code-batch-workers+))
         (results (make-array count :initial-element nil))
         (threads (make-array (1- worker-count) :initial-element nil))
         (next-index 0)
         (condition nil)
         (lock (sb-thread:make-mutex :name "snap-sync-code-batches")))
    (labels ((claim ()
               (sb-thread:with-mutex (lock)
                 (if (or condition (>= next-index count))
                     (values nil nil)
                     (let ((index next-index))
                       (incf next-index)
                       (values index t)))))
             (worker ()
               (loop
                 (multiple-value-bind (index present-p) (claim)
                   (unless present-p (return))
                   (handler-case
                       (setf
                        (aref results index)
                        (snap-sync-fetch-code-hash-batch
                         source (nth index batches) byte-limit))
                     (serious-condition (error)
                       (sb-thread:with-mutex (lock)
                         (unless condition (setf condition error)))
                       (return)))))))
      (unwind-protect
           (progn
             (dotimes (index (length threads))
               (setf
                (aref threads index)
                (sb-thread:make-thread
                 #'worker :name "snap-sync-code-batch-worker")))
             ;; The account worker is one member of the bound rather than an
             ;; idle coordinator thread.
             (worker)
             (loop for index below (length threads)
                   for thread = (aref threads index)
                   do (sb-thread:join-thread thread)
                      (setf (aref threads index) nil)))
        ;; Thread creation can fail after some helpers started. Their network
        ;; exchanges retain the ordinary request deadline, so join all of them
        ;; before the importer releases its source and database lifetime.
        (loop for thread across threads
              when thread
                do (ignore-errors (sb-thread:join-thread thread)))))
    (when condition (error condition))
    (loop for result across results append result)))

(defun snap-sync-fetch-codes (source hashes byte-limit &key parallel-p)
  "Fetch HASHES in bounded geth-sized batches.

Range import may advance four independent batches because its SOURCE is the
global peer pool. Healing leaves PARALLEL-P false: a healing candidate is one
fixed peer whose single ByteCodes slot would only serialize those calls."
  (let ((batches (snap-sync-code-hash-batches hashes)))
    (cond
      ((null batches) '())
      ((or (null (rest batches)) (not parallel-p))
       (loop for batch in batches
             append (snap-sync-fetch-code-hash-batch
                     source batch byte-limit)))
      (t
       #+sbcl
       (snap-sync-fetch-code-batches-concurrently
        source batches byte-limit)
       #-sbcl
       (loop for batch in batches
             append (snap-sync-fetch-code-hash-batch
                     source batch byte-limit))))))

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

(defun snap-sync-elapsed-milliseconds (start end)
  "Return non-negative monotonic milliseconds between internal clock ticks."
  (max 0
       (round
        (* 1000 (- end start))
        internal-time-units-per-second)))

(defun snap-sync-fetch-page-codes (database source code-hashes byte-limit)
  "Return only page bytecodes that are not already durable."
  (let ((missing
          (snap-sync-heal-missing-code-hashes database code-hashes)))
    (if missing
        (snap-sync-fetch-codes source missing byte-limit :parallel-p t)
        '())))

#+sbcl
(defun snap-sync-fetch-page-dependencies
    (database source state-root storage-commitments code-hashes byte-limit
     &key code-fetch-function)
  "Fetch one page's storage and bytecode dependencies concurrently.

The source transport already owns independent typed SNAP request slots. Running
the two dependency families concurrently lets pooled peers fill both slots like
geth's storage and bytecode schedulers. All child work joins before the caller
publishes the account cursor."
  (let ((storage-result '())
        (code-result '())
        (storage-ms 0)
        (code-ms 0)
        (storage-condition nil)
        (code-condition nil)
        (code-thread nil))
    (setf
     code-thread
     (sb-thread:make-thread
      (lambda ()
        (let ((started-at (get-internal-real-time)))
          (handler-case
              (setf code-result
                    (if code-fetch-function
                        (funcall code-fetch-function)
                        (snap-sync-fetch-page-codes
                         database source code-hashes byte-limit)))
            (serious-condition (condition)
              (setf code-condition condition)))
          (setf code-ms
                (snap-sync-elapsed-milliseconds
                 started-at (get-internal-real-time)))))
      :name "snap-sync-page-bytecodes"))
    (let ((started-at (get-internal-real-time)))
      (handler-case
          (setf storage-result
                (snap-sync-fetch-storage-commitments
                 database source state-root storage-commitments
                 (min byte-limit +snap-sync-storage-request-bytes+)))
        (serious-condition (condition)
          (setf storage-condition condition)))
      (setf storage-ms
            (snap-sync-elapsed-milliseconds
             started-at (get-internal-real-time))))
    (sb-thread:join-thread code-thread)
    (when storage-condition (error storage-condition))
    (when code-condition (error code-condition))
    (values storage-result code-result storage-ms code-ms)))

#-sbcl
(defun snap-sync-fetch-page-dependencies
    (database source state-root storage-commitments code-hashes byte-limit
     &key code-fetch-function)
  "Portable sequential fallback for page dependencies."
  (let* ((storage-started-at (get-internal-real-time))
         (storage-result
           (snap-sync-fetch-storage-commitments
            database source state-root storage-commitments
            (min byte-limit +snap-sync-storage-request-bytes+)))
         (storage-ms
           (snap-sync-elapsed-milliseconds
            storage-started-at (get-internal-real-time)))
         (code-started-at (get-internal-real-time))
         (code-result
           (if code-fetch-function
               (funcall code-fetch-function)
               (snap-sync-fetch-page-codes
                database source code-hashes byte-limit)))
         (code-ms
           (snap-sync-elapsed-milliseconds
            code-started-at (get-internal-real-time))))
    (values storage-result code-result storage-ms code-ms)))

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
   :complete-node-scheme-p
   (snap-sync-progress-complete-node-scheme-p progress)
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
         :complete-node-scheme-p
         (snap-sync-progress-complete-node-scheme-p progress)
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
                  (unless
                      (snap-sync-progress-complete-node-scheme-p existing)
                    (snap-sync-disable-complete-node-scheme database))
                  existing)
                (snap-sync-make-progress
                 :pivot-hash pivot-hash :pivot-number pivot-number
                 :state-root state-root :partial-root +empty-trie-hash+
                 :target-hash target-hash :chain-id chain-id
                 :genesis-hash genesis-hash :authority-id authority-id
                 :complete-node-scheme-p
                 (snap-sync-enable-complete-node-scheme-p database)
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
                      trie-record-count incomplete-node-count
                      healed-subtree-count dependency-subtree-count
                      account-request-ms proof-ms storage-ms code-ms metadata-ms
                      buffer-ms total-ms)))
  "Observational wall-clock breakdown for one verified SNAP account page."
  (account-count 0)
  (storage-account-count 0)
  (code-count 0)
  (trie-record-count 0)
  (incomplete-node-count 0)
  (healed-subtree-count 0)
  (dependency-subtree-count 0)
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
                      healed-subtrees dependency-subtrees complete-node-hashes
                      incomplete-node-hashes next-origin
                      completed-p profile)))
  task-index
  origin
  account-records
  codes
  deferred-storage
  healed-subtrees
  dependency-subtrees
  complete-node-hashes
  incomplete-node-hashes
  next-origin
  completed-p
  profile)

(defstruct (snap-sync-account-page-work
            (:constructor make-snap-sync-account-page-work
                (&key task-index origin account-record-hashes storage-commitments
                      code-hashes candidates account-count next-origin
                      completed-p started-at account-response-at
                      proof-finished-at prebuffer-ms)))
  "Verified account range waiting for globally scheduled dependencies."
  task-index
  origin
  account-record-hashes
  storage-commitments
  code-hashes
  candidates
  account-count
  next-origin
  completed-p
  started-at
  account-response-at
  proof-finished-at
  (prebuffer-ms 0))

(defstruct (snap-sync-storage-page-result
            (:constructor make-snap-sync-storage-page-result
                (&key task-index origin records healed-subtrees
                      complete-node-hashes incomplete-node-hashes next-origin
                      completed-p entry-count request-ms proof-ms
                      materialize-ms)))
  task-index
  origin
  records
  healed-subtrees
  complete-node-hashes
  incomplete-node-hashes
  next-origin
  completed-p
  (entry-count 0)
  (request-ms 0)
  (proof-ms 0)
  (materialize-ms 0))

(defstruct (snap-sync-verified-storage-page
            (:constructor make-snap-sync-verified-storage-page
                (&key task-index origin limit entries proof trie started-at
                      response-at proof-finished-at)))
  "One authenticated large-storage page awaiting local trie materialization."
  task-index
  origin
  limit
  entries
  proof
  trie
  started-at
  response-at
  proof-finished-at)

(defstruct (snap-sync-storage-profile
            (:constructor make-snap-sync-storage-profile
                (&key page-count slot-count trie-record-count
                      batch-operation-count logical-batch-bytes
                      completed-task-count request-ms proof-ms materialize-ms
                      batch-build-ms prepare-ms commit-ms writer-idle-ms)))
  "Aggregate wall-clock and logical-write evidence for one storage commit."
  (page-count 0)
  (slot-count 0)
  (trie-record-count 0)
  (batch-operation-count 0)
  (logical-batch-bytes 0)
  (completed-task-count 0)
  (request-ms 0)
  (proof-ms 0)
  (materialize-ms 0)
  (batch-build-ms 0)
  (prepare-ms 0)
  (commit-ms 0)
  (writer-idle-ms 0))

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

(defun snap-sync-incomplete-record-hashes (records complete-references)
  "Return unique RECORD hashes not covered by a proved complete subtree."
  (let ((complete (make-hash-table :test #'equalp))
        (incomplete (make-hash-table :test #'equalp))
        (result '()))
    (dolist (reference complete-references)
      (setf (gethash reference complete) t))
    (dolist (record records (nreverse result))
      (let ((reference (car record)))
        (unless (or (nth-value 1 (gethash reference complete))
                    (nth-value 1 (gethash reference incomplete)))
          (setf (gethash reference incomplete) t)
          (push reference result))))))

(defun snap-sync-incomplete-reference-hashes
    (references complete-references)
  "Return unique REFERENCES not covered by a proved complete subtree."
  (let ((complete (make-hash-table :test #'equalp))
        (incomplete (make-hash-table :test #'equalp))
        (result '()))
    (dolist (reference complete-references)
      (setf (gethash reference complete) t))
    (dolist (reference references (nreverse result))
      (unless (or (nth-value 1 (gethash reference complete))
                  (nth-value 1 (gethash reference incomplete)))
        (setf (gethash reference incomplete) t)
        (push reference result)))))

(defun snap-sync-populate-incomplete-records-batch (batch references)
  "Mark authenticated nodes whose full descendant closure is not yet proved."
  (dolist (reference references batch)
    (snap-sync-populate-incomplete-node-batch batch reference)))

(defun snap-sync-delete-incomplete-records-batch (batch references)
  "Clear stale negative markers for newly proved complete node closures."
  (dolist (reference references batch)
    (snap-sync-delete-incomplete-node-batch batch reference)))

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
  ;; Retain the argument and its validation at every caller seam.  The state
  ;; root authorizes the request, but the returned storage trie is already
  ;; content-addressed by STORAGE-ROOT and its cursor must survive a pivot move.
  (snap-sync-require-hash32 state-root "Snap storage range task state root")
  (concatenate
   'vector +snap-sync-storage-task-identifier-prefix+
   account-hash (hash32-bytes storage-root) (vector task-index)))

(defun snap-sync-legacy-storage-task-identifier
    (state-root account-hash storage-root task-index)
  "Return the version-three key used for an in-place exact-pivot migration."
  (unless (and (integerp task-index)
               (<= 0 task-index)
               (< task-index +snap-sync-storage-task-count+))
    (error "Legacy snap storage range task index is out of bounds"))
  (unless (and (byte-vector-p account-hash) (= 32 (length account-hash)))
    (error "Legacy snap storage range task requires a 32-byte account hash"))
  (concatenate
   'vector +snap-sync-legacy-storage-task-identifier-prefix+
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

(defun snap-sync-legacy-storage-tasks
    (database state-root account-hash storage-root)
  "Load a complete version-three cursor set for STATE-ROOT, or NIL.

A partial legacy set remains corruption.  Callers copy a complete set into the
state-root-independent version-four namespace before exposing it to workers."
  (let ((identifiers
          (coerce
           (loop for index below +snap-sync-storage-task-count+
                 collect
                 (snap-sync-legacy-storage-task-identifier
                  state-root account-hash storage-root index))
           'vector)))
    (multiple-value-bind (records present)
        (kv-get-chain-records database :metadata identifiers)
      (let ((present-count (count 1 present)))
        (cond
          ((zerop present-count) nil)
          ((/= present-count +snap-sync-storage-task-count+)
           (ethereum-lisp.validation:storage-fail
            "Persisted legacy snap storage range task set is incomplete"))
          (t
           (loop for record across records
                 collect (snap-sync-storage-task-from-record record))))))))

(defun snap-sync-populate-storage-task-set-batch
    (batch state-root account-hash storage-root tasks)
  "Copy one validated cursor TASKS set into the current namespace."
  (unless (= +snap-sync-storage-task-count+ (length tasks))
    (error "Snap storage range task set has the wrong size"))
  (loop for task in tasks
        for index from 0
        do (snap-sync-populate-storage-task-batch
            batch state-root account-hash storage-root index task))
  batch)

(defun snap-sync-estimate-remaining-storage-slots (prefix-count last-key)
  "Estimate slots after LAST-KEY exactly like geth v1.17.4.

The estimate assumes uniformly distributed secure storage hashes. NIL retains
the conservative sixteen-way fallback when the prefix is too small to fit the
estimate in an unsigned 64-bit counter or when LAST-KEY is zero."
  (unless (and (integerp prefix-count) (plusp prefix-count))
    (error "Snap storage density estimate requires a positive prefix count"))
  (let ((last (bytes-to-integer (ensure-byte-vector last-key))))
    (when (plusp last)
      (let ((total
              (floor (* (1- (ash 1 256)) prefix-count) last)))
        (when (<= total (1- (ash 1 64)))
          (max 0 (- total prefix-count)))))))

(defun snap-sync-adaptive-storage-task-count (prefix-count last-key)
  "Return geth v1.17.4's density-selected large-storage chunk count."
  (let ((remaining
          (snap-sync-estimate-remaining-storage-slots prefix-count last-key)))
    (if remaining
        (min
         +snap-sync-storage-task-count+
         (1+
          (floor
           remaining
           (* 2
              (floor +snap-sync-storage-request-bytes+
                     +snap-sync-storage-slot-width+)))))
        +snap-sync-storage-task-count+)))

(defun snap-sync-make-seeded-storage-tasks
    (next-origin last-key prefix-count)
  "Build an adaptive large-storage plan in sixteen durable record slots.

The active prefix matches geth v1.17.4 NEW-HASH-RANGE: its first task owns the
already authenticated nil-bound prefix and the remaining hash space is divided
into the density-selected number of chunks. Unused record slots are completed
sentinels, preserving the version-three restart format and fail-closed complete
set checks without issuing redundant network requests."
  (let* ((last-key (ensure-byte-vector last-key))
         (last (bytes-to-integer last-key))
         (space (ash 1 256))
         (maximum (1- space))
         (count
           (snap-sync-adaptive-storage-task-count prefix-count last-key))
         (step (ceiling (- space last) count))
         (tasks
           (loop for index below count
                 for start-value = (if (zerop index)
                                       0
                                       (+ last (* index step)))
                 for limit-value = (min maximum
                                        (1- (+ last (* (1+ index) step))))
                 for start = (snap-sync-integer-to-hash-bytes start-value)
                 for limit = (snap-sync-integer-to-hash-bytes limit-value)
                 collect
                 (cond
                   ((null next-origin)
                    (snap-sync-account-task
                     :start start :limit limit :completed-p t))
                   ((zerop index)
                    (snap-sync-account-task
                     :start start :limit limit :next-origin next-origin))
                   (t
                    (snap-sync-account-task
                     :start start :limit limit :next-origin start)))))
         (sentinel (snap-sync-integer-to-hash-bytes maximum)))
    (nconc
     tasks
     (loop repeat (- +snap-sync-storage-task-count+ count)
           collect
           (snap-sync-account-task
            :start sentinel :limit sentinel :completed-p t)))))

(defun snap-sync-seed-storage-tasks-batch
    (database batch state-root account-hash storage-root
     next-origin last-key prefix-count)
  "Seed a large storage task set after its nil-bound prefix is already durable.

NEXT-ORIGIN is the successor of the last authenticated slot, or NIL when that
prefix reached the end of the hash space. LAST-KEY and PREFIX-COUNT select
geth's adaptive one-to-sixteen chunk plan. Existing complete task sets are never
rewound: a concurrent or restarted worker may already have advanced them beyond
this initial prefix. A partial persisted set is corruption and remains fail
closed."
  (let ((identifiers
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
                   (or
                    (snap-sync-legacy-storage-tasks
                     database state-root account-hash storage-root)
                    (snap-sync-make-seeded-storage-tasks
                     next-origin last-key prefix-count))))
             (snap-sync-populate-storage-task-set-batch
              batch state-root account-hash storage-root tasks)
             tasks))
          ((/= present-count +snap-sync-storage-task-count+)
           (ethereum-lisp.validation:storage-fail
            "Persisted snap storage range task set is incomplete"))
          (t
           (loop for record across records
                 collect (snap-sync-storage-task-from-record record))))))))

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
                   (or
                    (snap-sync-legacy-storage-tasks
                     database state-root account-hash storage-root)
                    (snap-sync-make-account-tasks
                     :count +snap-sync-storage-task-count+)))
                 (batch (make-kv-write-batch)))
             (snap-sync-populate-storage-task-set-batch
              batch state-root account-hash storage-root tasks)
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
  "Split proved account subtrees by their unresolved storage dependencies.

The third value contains every concrete trie-node hash whose descendant trie
closure is proved by the range.  A subtree with a bounded dependency list is
included: its durable dependency proof makes the healer schedule those exact
storage roots before skipping the account walk, so its account-trie records do
not need millions of per-node negative markers. Coarse and nested candidates
are classified independently, so a dependency-heavy coarse bucket can still
publish safe finer children. A subtree whose dependency list is too wide
remains conservative and contributes no complete references."
  (let ((dependencies-by-prefix (make-hash-table :test #'equalp))
        (candidate-depths
          (remove-duplicates
           (mapcar
            (lambda (candidate)
              (length
               (if (and (consp candidate)
                        (consp (cdr candidate))
                        (consp (cddr candidate))
                        (null (cdddr candidate)))
                   (first candidate)
                   (car candidate))))
            candidates)))
        (safe-subtrees '())
        (dependency-subtrees '())
        (complete-references '())
        (complete-reference-set (make-hash-table :test #'equalp)))
    (dolist (commitment deferred-storage)
      (dolist (depth candidate-depths)
        (push commitment
              (gethash
               (snap-sync-account-prefix-bucket (car commitment) depth)
               dependencies-by-prefix))))
    (labels ((record-complete-references (references)
               (dolist (reference references)
                 (unless
                     (nth-value
                      1 (gethash reference complete-reference-set))
                   (setf (gethash reference complete-reference-set) t)
                   (push reference complete-references)))))
      (dolist (candidate candidates)
        (let* ((group-p
                 (and (consp candidate)
                      (consp (cdr candidate))
                      (consp (cddr candidate))
                      (null (cdddr candidate))))
               (prefix (if group-p (first candidate) (car candidate)))
               (reference (if group-p (second candidate) (cdr candidate)))
               (references (and group-p (third candidate)))
               (dependencies
                 (nreverse (gethash prefix dependencies-by-prefix))))
          (cond
            ((null dependencies)
             (push reference safe-subtrees)
             (record-complete-references references))
            ((<= (length dependencies)
                 +snap-sync-account-subtree-dependencies-max+)
             (push (cons reference dependencies) dependency-subtrees)
             ;; The dependency proof is published in the same buffered batch
             ;; as these records. SNAP-SYNC-HEAL-STATE checks that proof before
             ;; the complete-node fast path and schedules every listed storage
             ;; root, preserving external closure without walking this account
             ;; trie.
             (record-complete-references references))))))
    (values (nreverse safe-subtrees) (nreverse dependency-subtrees)
            (nreverse complete-references))))

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
    ;; Range pages overlap at proof boundaries.  A later authenticated page can
    ;; close a node that an earlier page conservatively marked incomplete.
    (snap-sync-delete-incomplete-records-batch
     batch (snap-sync-page-result-complete-node-hashes result))
    (snap-sync-populate-incomplete-records-batch
     batch (snap-sync-page-result-incomplete-node-hashes result))
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
          (snap-sync-page-result-dependency-subtrees result) '()
          (snap-sync-page-result-complete-node-hashes result) '()
          (snap-sync-page-result-incomplete-node-hashes result) '())
    result))

(defun snap-sync-prepare-account-page-range
    (database source state-root task-index task byte-limit)
  "Fetch and verify one account range, without waiting for its dependencies."
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
           (code-hashes (snap-sync-page-code-hashes entries)))
      (when (and (not complete-p) (null next-origin))
        (error "Snap account page did not advance its assigned task"))
      (let* ((proved-end (if complete-p limit last-entry))
             (candidates
               (if (and account-trie proved-end)
                   (nth-value
                    1
                    (snap-sync-proved-range-subtrees
                     account-trie origin proved-end))
                   '())))
        ;; The proof has authenticated these content-addressed records already.
        ;; Buffer them before StorageRanges/ByteCodes work so slow dependencies
        ;; retain only 32-byte references, not the reconstructed trie graph.
        ;; A later synchronous cursor batch flushes this WAL prefix; a crash
        ;; before that seam merely leaves harmless idempotent content behind.
        (let* ((prebuffer-started-at (get-internal-real-time))
               (batch (make-kv-write-batch))
               (account-record-hashes (mapcar #'car account-records)))
          (snap-sync-populate-verified-trie-records-batch
           database batch account-records)
          (kv-apply-batch-buffered database batch)
          (make-snap-sync-account-page-work
           :task-index task-index
           :origin (copy-seq origin)
           :account-record-hashes account-record-hashes
           :storage-commitments storage-commitments
           :code-hashes code-hashes
           :candidates candidates
           :account-count (length entries)
           :next-origin next-origin
           :completed-p complete-p
           :started-at started-at
           :account-response-at account-response-at
           :proof-finished-at proof-finished-at
           :prebuffer-ms
           (snap-sync-elapsed-milliseconds
            prebuffer-started-at (get-internal-real-time)))))))))

(defun snap-sync-complete-account-page
    (database source state-root work byte-limit
     &key code-fetch-function deferred-storage-function)
  "Resolve WORK's storage/code globally, then buffer its verified content."
  (multiple-value-bind (deferred-storage codes storage-ms code-ms)
      (snap-sync-fetch-page-dependencies
       database source state-root
       (snap-sync-account-page-work-storage-commitments work)
       (snap-sync-account-page-work-code-hashes work)
       byte-limit :code-fetch-function code-fetch-function)
    ;; Geth keeps an account task pending while a byte-capped contract is split
    ;; into storage subtasks. Production imports do the same through the global
    ;; dependency workers: a durable account cursor cannot outrun a large
    ;; storage root that the serving pivot may prune on the next cycle.
    (when (and deferred-storage deferred-storage-function)
      (let ((started-at (get-internal-real-time)))
        (setf deferred-storage
              (funcall deferred-storage-function deferred-storage))
        (incf storage-ms
              (snap-sync-elapsed-milliseconds
               started-at (get-internal-real-time)))))
    (let ((dependencies-finished-at (get-internal-real-time)))
      (multiple-value-bind
            (safe-subtrees dependency-subtrees complete-references)
          (snap-sync-classify-account-range-subtrees
           (snap-sync-account-page-work-candidates work) deferred-storage)
        (let* ((metadata-finished-at (get-internal-real-time))
               (started-at (snap-sync-account-page-work-started-at work))
               (account-record-hashes
                 (snap-sync-account-page-work-account-record-hashes work))
               (incomplete-node-hashes
                 (snap-sync-incomplete-reference-hashes
                  account-record-hashes complete-references))
               (profile
                 (make-snap-sync-page-profile
                  :account-count
                  (snap-sync-account-page-work-account-count work)
                  :storage-account-count
                  (length
                   (snap-sync-account-page-work-storage-commitments work))
                  :code-count
                  (length (snap-sync-account-page-work-code-hashes work))
                  :trie-record-count (length account-record-hashes)
                  :incomplete-node-count (length incomplete-node-hashes)
                  :healed-subtree-count (length safe-subtrees)
                  :dependency-subtree-count (length dependency-subtrees)
                  :account-request-ms
                  (snap-sync-elapsed-milliseconds
                   started-at
                   (snap-sync-account-page-work-account-response-at work))
                  :proof-ms
                  (snap-sync-elapsed-milliseconds
                   (snap-sync-account-page-work-account-response-at work)
                   (snap-sync-account-page-work-proof-finished-at work))
                  :storage-ms storage-ms
                  :code-ms code-ms
                  :metadata-ms
                  (snap-sync-elapsed-milliseconds
                   dependencies-finished-at metadata-finished-at)))
               (result
                 (make-snap-sync-page-result
                  :task-index (snap-sync-account-page-work-task-index work)
                  :origin (snap-sync-account-page-work-origin work)
                  ;; Account trie records were buffered immediately after
                  ;; proof verification; only closure metadata remains here.
                  :account-records '()
                  :codes codes
                  :deferred-storage deferred-storage
                  :healed-subtrees safe-subtrees
                  ;; Keep the exact storage gaps beside the authenticated
                  ;; subtree hash so a later pivot can skip the account walk
                  ;; without skipping external dependencies.
                  :dependency-subtrees dependency-subtrees
                  :complete-node-hashes complete-references
                  :incomplete-node-hashes incomplete-node-hashes
                  :next-origin (snap-sync-account-page-work-next-origin work)
                  :completed-p
                  (snap-sync-account-page-work-completed-p work)
                  :profile profile)))
          (snap-sync-buffer-account-page-content database state-root result)
          (let ((finished-at (get-internal-real-time)))
            (setf
             (snap-sync-page-profile-buffer-ms profile)
             (+ (snap-sync-account-page-work-prebuffer-ms work)
                (snap-sync-elapsed-milliseconds
                 metadata-finished-at finished-at))
             (snap-sync-page-profile-total-ms profile)
             (snap-sync-elapsed-milliseconds started-at finished-at)))
          result)))))

(defun snap-sync-prepare-account-page
    (database source state-root task-index task byte-limit)
  "Fetch, verify, and complete one page without advancing durable progress."
  (snap-sync-complete-account-page
   database source state-root
   (snap-sync-prepare-account-page-range
    database source state-root task-index task byte-limit)
   byte-limit
   :deferred-storage-function
   (lambda (commitments)
     (snap-sync-complete-deferred-storage-roots
      database (list source) state-root commitments byte-limit))))

(defun snap-sync-replace-task (tasks index replacement)
  (loop for task in tasks
        for position from 0
        collect (if (= position index)
                    replacement
                    (snap-sync-copy-account-task task))))

(defun snap-sync-account-page-next-progress (progress result)
  "Return PROGRESS advanced by one already buffered account-page RESULT."
  (let* ((task-index (snap-sync-page-result-task-index result))
         (task (nth task-index (snap-sync-progress-tasks progress))))
    (unless task
      (error "Snap account result names an unknown task"))
    (unless (and (not (snap-sync-account-task-completed-p task))
                 (bytes= (snap-sync-account-task-next-origin task)
                         (snap-sync-page-result-origin result)))
      (error "Snap account result no longer matches its durable task cursor"))
    (let* ((previous-root (snap-sync-progress-partial-root progress))
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
              :complete-node-scheme-p
              (snap-sync-progress-complete-node-scheme-p progress)
              ;; Even an equal account-trie root cannot prove that deferred
              ;; byte-capped storage and code dependencies exist locally.
              ;; Only the final content-addressed traversal may install the
              ;; completion/state-history marker.
              :completed-p nil :tasks tasks)))
      next)))

(defun snap-sync-commit-account-pages (database progress results)
  "Publish several ready task cursors through one synchronous WAL seam.

Every RESULT's authenticated content was buffered first. Folding the results
in event order retains the same durable cursor checks, while one final progress
record flushes all of those worker prefixes and removes per-page fsync stalls."
  (unless results
    (error "Snap account cursor batch must contain at least one result"))
  (let ((next progress)
        (snapshots '()))
    (dolist (result results)
      (setf next (snap-sync-account-page-next-progress next result))
      (push next snapshots))
    (let ((batch (make-kv-write-batch)))
      (when (and
             (snap-sync-tasks-completed-p (snap-sync-progress-tasks next))
             (hash32= (snap-sync-progress-partial-root next)
                      (snap-sync-progress-state-root next)))
        ;; Every buffered range independently reconstructed the same authorized
        ;; root. Publishing this marker with the last cursor makes the
        ;; deferred storage set complete: after restart, absence of a queue
        ;; record means there was no such work.
        (snap-sync-populate-deferred-storage-plan-batch
         batch (snap-sync-progress-state-root next)))
      (snap-sync-populate-progress-batch batch next)
      (kv-apply-batch database batch))
    (values next (nreverse snapshots))))

(defun snap-sync-commit-account-page (database progress result)
  "Publish RESULT's task cursor after its buffered content is complete."
  (snap-sync-commit-account-pages database progress (list result)))

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

#+sbcl
(defstruct (snap-sync-heal-pipeline-peer
            (:constructor make-snap-sync-heal-pipeline-peer
                (source capacity rtt)))
  "One independently scheduled TrieNodes source in the healer event loop."
  source
  capacity
  ;; True when CAPACITY came from the source transport's shared SNAP tracker.
  ;; Such peers must not also run the healer's legacy local capacity learner.
  externally-sized-p
  rtt
  job
  thread
  inflight-p
  retired-p)

#+sbcl
(defstruct (snap-sync-heal-pipeline-event
            (:constructor make-snap-sync-heal-pipeline-event
                (peer works result elapsed-seconds)))
  peer
  works
  result
  elapsed-seconds)

#+sbcl
(defstruct (snap-sync-heal-pipeline-runtime
            (:constructor make-snap-sync-heal-pipeline-runtime ()))
  (lock (sb-thread:make-mutex :name "snap-sync-heal-pipeline"))
  (changed (sb-thread:make-waitqueue :name "snap-sync-heal-pipeline-changed"))
  (peers '())
  (pending '())
  (events '())
  (inflight-works 0)
  stopped-p)

(defun snap-sync-heal-reference-p (reference)
  (or (rlp-list-p reference)
      (and (byte-vector-p reference)
           (member (length reference) '(0 32)))))

(defun snap-sync-make-heal-work
    (kind account-hash path reference &key fetched-p marker-state)
  (unless (member kind '(:account :storage))
    (error "Snap heal work has an unknown trie kind"))
  (unless (member marker-state '(nil :armed :inside :complete :node-complete))
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
           (member marker-state '(:armed :complete :node-complete))
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
  (when (member (snap-sync-heal-work-marker-state work)
                '(:complete :node-complete))
    (error "A snap completion marker is not wire work"))
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

(defun snap-sync-heal-request-capacity (throttle)
  "Return the feedback-limited path count assigned to one TrieNodes request."
  (unless (and (realp throttle) (plusp throttle))
    (error "Snap heal throttle must be positive"))
  (max 1
       (min +snap-sync-heal-paths-per-source+
            (floor *snap-sync-heal-request-target-paths* throttle))))

(defun snap-sync-heal-next-throttle (throttle pending processing-rate)
  "Adjust THROTTLE from geth's pending-vs-processing feedback rule."
  (unless (and (realp throttle) (plusp throttle)
               (integerp pending) (not (minusp pending))
               (realp processing-rate) (not (minusp processing-rate)))
    (error "Invalid snap heal throttle feedback"))
  (let ((next
          (if (> pending (* 2 processing-rate))
              (* throttle +snap-sync-heal-throttle-increase+)
              (/ throttle +snap-sync-heal-throttle-decrease+))))
    (max +snap-sync-heal-min-throttle+
         (min +snap-sync-heal-max-throttle+ next))))

(defun snap-sync-heal-processing-rate (old-rate fills elapsed-seconds)
  "Fold FILLS uniformly into the per-node healer processing-rate EWMA."
  (unless (and (realp old-rate) (not (minusp old-rate))
               (integerp fills) (not (minusp fills))
               (realp elapsed-seconds) (plusp elapsed-seconds))
    (error "Invalid snap heal processing-rate sample"))
  (if (zerop fills)
      (float old-rate 1d0)
      (let* ((sample (/ fills (float elapsed-seconds 1d0)))
             (retained
               (expt (- 1d0 +snap-sync-heal-rate-measurement-impact+)
                     fills)))
        (+ (* retained (- old-rate sample)) sample))))

(defun snap-sync-heal-missing-limit
    (stack-count source-count
     &optional (paths-per-source +snap-sync-heal-paths-per-source+))
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
  (unless (and (integerp paths-per-source)
               (<= 1 paths-per-source
                   +snap-sync-heal-paths-per-source+))
    (error "Snap heal per-source path capacity is invalid"))
  (min +snap-sync-heal-live-frontier-max-works+
       (* #+sbcl source-count #-sbcl 1
          paths-per-source)))

(defun snap-sync-heal-local-read-limit
    (stack-count missing-count missing-limit checkpoint-room)
  "Bound one local read batch by progress and worst-case trie expansion.

Each popped external reference can expose at most sixteen children, increasing
the frontier by fifteen works. Stay within the durable checkpoint bound
throughout its normal soft-target region, and use the separate live bound for a
larger resumed frontier so remote batching does not collapse at 8,192 works."
  (unless (and (integerp stack-count) (not (minusp stack-count))
               (integerp missing-count) (not (minusp missing-count))
               (integerp missing-limit) (> missing-limit missing-count)
               (integerp checkpoint-room) (plusp checkpoint-room))
    (error "Invalid snap heal local read limits"))
  (let* ((frontier-limit
           ;; Below the ordinary checkpoint target, retain enough room for the
           ;; next batch's worst-case expansion to stay immediately durable.
           ;; A restored or transiently larger frontier instead drains under
           ;; the separately bounded live limit; applying the checkpoint cap
           ;; there is the one-path/request failure this split prevents.
           (if (<= stack-count
                   +snap-sync-heal-checkpoint-frontier-target+)
               +snap-sync-heal-checkpoint-max-works+
               +snap-sync-heal-live-frontier-max-works+))
         (expansion-room
           (floor (max 0 (- frontier-limit stack-count)) 15)))
    (min +snap-sync-heal-local-reads-per-batch+
         (- missing-limit missing-count)
         checkpoint-room
         (max 1 expansion-room))))

(defun snap-sync-heal-pipeline-refill-work-room (examined)
  "Return the remaining deterministic local-work quantum after EXAMINED."
  (unless (and (integerp examined) (not (minusp examined))
               (integerp *snap-sync-heal-pipeline-refill-work-quantum*)
               (plusp *snap-sync-heal-pipeline-refill-work-quantum*))
    (error "Invalid snap heal pipeline refill work quantum"))
  (max 0 (- *snap-sync-heal-pipeline-refill-work-quantum* examined)))

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
     (:inside 3)
     (:node-complete 4))))

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
           (4 :node-complete)
           (otherwise
            (error "Snap heal work subtree-marker state exceeds four"))))))))

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
        ;; A checkpoint is only a cache of the frontier omitted from its
        ;; persisted trie. Epochs one through three may already have skipped
        ;; work using closure proofs retired by epoch four, so resuming them
        ;; would preserve the omission. Treat them as cache misses and restart
        ;; from the authorized root.
        (unless (= version +snap-sync-heal-checkpoint-version+)
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
     :complete-node-scheme-p
     (snap-sync-progress-complete-node-scheme-p progress)
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
    (sources missing root-bytes byte-limit
     &key (target-paths *snap-sync-heal-request-target-paths*))
  "Drain one bounded missing frontier through continuously busy sources.

Each source still owns at most one TrieNodes exchange at a time.  The frontier
is deliberately over-partitioned, however, so a source that answers promptly
claims another disjoint chunk instead of waiting at a global slowest-peer
barrier.  Failed sources stop claiming; their unrequested remainder stays
absent in the caller's exact continuation and is retried after source rotation."
  (unless (and (integerp target-paths)
               (<= 1 target-paths
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
               target-paths)))))
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
    (sources missing root-bytes byte-limit &key target-paths)
  (declare (ignore target-paths))
  (let ((source (first sources)))
    (unless source
      (error "Snap healing requires a live source"))
    (vector
     (snap-sync-heal-request-chunk
      source missing 0 (length missing) root-bytes byte-limit))))

(defun snap-sync-heal-learn-peer-capacity
    (old-capacity assigned delivered elapsed-seconds)
  "Learn a peer-local TrieNodes path capacity from one completed exchange.

A response which did not fill its assigned path set contracts to the useful
delivered width. A full response scales toward the number the peer could return
inside geth's two-second target. The EWMA avoids request-size oscillation while
the protocol's 1,024-lookup ceiling remains absolute."
  (unless (and (integerp old-capacity)
               (<= 1 old-capacity +snap-sync-heal-paths-per-source+)
               (integerp assigned) (plusp assigned)
               (integerp delivered) (<= 0 delivered assigned)
               (realp elapsed-seconds) (plusp elapsed-seconds))
    (error "Invalid snap healer peer-capacity sample"))
  (let* ((sample
           (if (< delivered assigned)
               (max 1 delivered)
               (max
                1
                (min
                 +snap-sync-heal-paths-per-source+
                 (round
                  (* delivered
                     (/ +snap-sync-heal-request-target-seconds+
                        (float elapsed-seconds 1d0))))))))
         (next
           (round
            (+ (* (- 1d0 +snap-sync-heal-peer-capacity-impact+)
                  old-capacity)
               (* +snap-sync-heal-peer-capacity-impact+ sample)))))
    (max 1 (min +snap-sync-heal-paths-per-source+ next))))

(defun snap-sync-heal-learn-peer-rtt (old-rtt elapsed-seconds)
  "Fold one completed TrieNodes round trip into a peer-local RTT EWMA."
  (unless (and (realp old-rtt) (plusp old-rtt)
               (realp elapsed-seconds) (plusp elapsed-seconds))
    (error "Invalid snap healer peer RTT sample"))
  (+ (* (- 1d0 +snap-sync-heal-peer-rtt-impact+) old-rtt)
     (* +snap-sync-heal-peer-rtt-impact+ elapsed-seconds)))

#+sbcl
(defun snap-sync-heal-pipeline-peer< (left right)
  "Order idle peers by learned capacity, then by learned RTT."
  (let ((left-capacity (snap-sync-heal-pipeline-peer-capacity left))
        (right-capacity (snap-sync-heal-pipeline-peer-capacity right)))
    (if (= left-capacity right-capacity)
        (< (snap-sync-heal-pipeline-peer-rtt left)
           (snap-sync-heal-pipeline-peer-rtt right))
        (> left-capacity right-capacity))))

(defun snap-sync-heal-source-request-capacity (source throttle)
  "Return SOURCE's Geth-shaped TrieNodes assignment, or NIL for fallback.

The source callback exposes the transport's shared message-rate capacity for
TrieNodes at its current timeout. Geth clamps that value to 1,024, divides it
by the local processing throttle, and preserves a one-item probe."
  (unless (and (realp throttle)
               (<= +snap-sync-heal-min-throttle+
                   throttle
                   +snap-sync-heal-max-throttle+))
    (error "Invalid snap healer throttle"))
  (let ((capacity-function
          (snap-sync-source-trie-node-capacity source)))
    (when capacity-function
      (unless (functionp capacity-function)
        (error "Snap TrieNodes capacity provider must be a function"))
      (let ((capacity (funcall capacity-function)))
        (unless (and (integerp capacity)
                     (<= 1 capacity +snap-sync-heal-paths-per-source+))
          (error "Snap TrieNodes capacity must be between 1 and ~D"
                 +snap-sync-heal-paths-per-source+))
        (max 1
             (floor
              (min capacity +snap-sync-heal-paths-per-source+)
              throttle))))))

#+sbcl
(defun snap-sync-heal-pipeline-worker
    (runtime peer root-bytes byte-limit)
  "Execute at most one synchronous exchange for PEER at a time.

Only the coordinator assigns jobs and integrates events. The worker owns the
source call, so a fast peer can accept its next job as soon as its individual
response has been validated instead of waiting for an unrelated slow peer."
  (loop
    (let ((works
            (sb-thread:with-mutex
                ((snap-sync-heal-pipeline-runtime-lock runtime))
              (loop while (and
                           (null (snap-sync-heal-pipeline-peer-job peer))
                           (not
                            (snap-sync-heal-pipeline-runtime-stopped-p runtime)))
                    do (sb-thread:condition-wait
                        (snap-sync-heal-pipeline-runtime-changed runtime)
                        (snap-sync-heal-pipeline-runtime-lock runtime)))
              (when (snap-sync-heal-pipeline-runtime-stopped-p runtime)
                (return-from snap-sync-heal-pipeline-worker nil))
              (prog1
                  (snap-sync-heal-pipeline-peer-job peer)
                (setf (snap-sync-heal-pipeline-peer-job peer) nil)))))
      (let* ((started-at (get-internal-real-time))
             (result
               (snap-sync-heal-request-chunk
                (snap-sync-heal-pipeline-peer-source peer)
                works 0 (length works) root-bytes byte-limit))
             (elapsed
               (max
                1d-6
                (/ (- (get-internal-real-time) started-at)
                   (float internal-time-units-per-second 1d0)))))
        (sb-thread:with-mutex
            ((snap-sync-heal-pipeline-runtime-lock runtime))
          (setf (snap-sync-heal-pipeline-runtime-events runtime)
                (nconc
                 (snap-sync-heal-pipeline-runtime-events runtime)
                 (list
                  (make-snap-sync-heal-pipeline-event
                   peer works result elapsed))))
          (sb-thread:condition-broadcast
           (snap-sync-heal-pipeline-runtime-changed runtime)))))))

#+sbcl
(defun snap-sync-heal-pipeline-add-source
    (runtime source root-bytes byte-limit capacity-table rtt-table)
  "Add SOURCE once and start its long-lived request worker."
  (sb-thread:with-mutex ((snap-sync-heal-pipeline-runtime-lock runtime))
    (unless
        (find source (snap-sync-heal-pipeline-runtime-peers runtime)
              :key #'snap-sync-heal-pipeline-peer-source :test #'eq)
      (let ((peer
              (make-snap-sync-heal-pipeline-peer
               source
               (gethash
                source capacity-table +snap-sync-heal-paths-per-source+)
               (gethash
                source rtt-table +snap-sync-heal-request-target-seconds+))))
        (setf (snap-sync-heal-pipeline-runtime-peers runtime)
              (nconc
               (snap-sync-heal-pipeline-runtime-peers runtime) (list peer))
              (snap-sync-heal-pipeline-peer-thread peer)
              (sb-thread:make-thread
               (lambda ()
                 (snap-sync-heal-pipeline-worker
                  runtime peer root-bytes byte-limit))
               :name "snap-sync-heal-source-worker"))
        (sb-thread:condition-broadcast
         (snap-sync-heal-pipeline-runtime-changed runtime))
        peer))))

#+sbcl
(defun snap-sync-heal-pipeline-enqueue (runtime works)
  "Append exact unprocessed WORKS to the coordinator-owned shared queue."
  (when works
    (sb-thread:with-mutex ((snap-sync-heal-pipeline-runtime-lock runtime))
      (setf (snap-sync-heal-pipeline-runtime-pending runtime)
            (nconc
             (snap-sync-heal-pipeline-runtime-pending runtime)
             (copy-list works)))
      (sb-thread:condition-broadcast
       (snap-sync-heal-pipeline-runtime-changed runtime)))))

#+sbcl
(defun snap-sync-heal-pipeline-outstanding (runtime)
  (sb-thread:with-mutex ((snap-sync-heal-pipeline-runtime-lock runtime))
    (+ (length (snap-sync-heal-pipeline-runtime-pending runtime))
       (snap-sync-heal-pipeline-runtime-inflight-works runtime))))

#+sbcl
(defun snap-sync-heal-pipeline-dispatch
    (runtime &optional assignment-capacity)
  "Assign shared work to every idle peer without a round barrier."
  (sb-thread:with-mutex ((snap-sync-heal-pipeline-runtime-lock runtime))
    (let ((idle
            (remove-if
             (lambda (peer)
               (or (snap-sync-heal-pipeline-peer-retired-p peer)
                   (snap-sync-heal-pipeline-peer-inflight-p peer)))
             (copy-list (snap-sync-heal-pipeline-runtime-peers runtime)))))
      ;; Refresh transport-owned capacities before ordering and assignment.
      ;; A NIL result deliberately retains the local fallback for fixed test
      ;; sources which do not own a SNAP request queue.
      (when assignment-capacity
        (dolist (peer idle)
          (let ((capacity
                  (funcall
                   assignment-capacity
                   (snap-sync-heal-pipeline-peer-source peer))))
            (if capacity
                (progn
                  (unless (and (integerp capacity)
                               (<= 1 capacity
                                   +snap-sync-heal-paths-per-source+))
                    (error "Invalid external TrieNodes assignment capacity"))
                  (setf
                   (snap-sync-heal-pipeline-peer-capacity peer) capacity
                   (snap-sync-heal-pipeline-peer-externally-sized-p peer) t))
                (setf
                 (snap-sync-heal-pipeline-peer-externally-sized-p peer)
                 nil)))))
      (setf idle
            (stable-sort idle #'snap-sync-heal-pipeline-peer<))
      (dolist (peer idle)
        (unless (snap-sync-heal-pipeline-runtime-pending runtime)
          (return))
        (let ((works '()))
          (loop repeat (snap-sync-heal-pipeline-peer-capacity peer)
                while (snap-sync-heal-pipeline-runtime-pending runtime)
                do (push
                    (pop (snap-sync-heal-pipeline-runtime-pending runtime))
                    works))
          (let ((job (coerce (nreverse works) 'vector)))
            (setf (snap-sync-heal-pipeline-peer-job peer) job
                  (snap-sync-heal-pipeline-peer-inflight-p peer) t)
            (incf (snap-sync-heal-pipeline-runtime-inflight-works runtime)
                  (length job)))))
      (sb-thread:condition-broadcast
       (snap-sync-heal-pipeline-runtime-changed runtime)))))

#+sbcl
(defun snap-sync-heal-pipeline-next-event (runtime)
  "Wait for one peer response, returning NIL only at a quiescent scheduler."
  (sb-thread:with-mutex ((snap-sync-heal-pipeline-runtime-lock runtime))
    (loop
      (when (snap-sync-heal-pipeline-runtime-events runtime)
        (return (pop (snap-sync-heal-pipeline-runtime-events runtime))))
      (when (zerop
             (snap-sync-heal-pipeline-runtime-inflight-works runtime))
        (return nil))
      (sb-thread:condition-wait
       (snap-sync-heal-pipeline-runtime-changed runtime)
       (snap-sync-heal-pipeline-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-heal-run-pipeline
    (sources initial-works root-bytes byte-limit capacity-table rtt-table
     handle-result refill refresh-sources
     &optional pause-p assignment-capacity)
  "Run a geth-shaped TrieNodes event loop over a bounded shared frontier.

HANDLE-RESULT receives an individual result and its exact work vector, and
returns retry works, an optional source-retiring condition, and the accepted
node count. REFILL receives remaining frontier room and the current outstanding
work count, and may expose newly discovered missing work immediately. New
sources from REFRESH-SOURCES join without restarting the pipeline. PAUSE-P
receives the exact outstanding work count; when it becomes true, assignment
stops, in-flight responses are integrated, and the exact pending queue is
returned for a durable checkpoint. The return values are any unprocessed works,
the finite generation's source errors, and whether a pause requested the return.
ASSIGNMENT-CAPACITY optionally returns a live, already-throttled item capacity
for one source. When present, it replaces the local peer-capacity learner."
  (let ((runtime (make-snap-sync-heal-pipeline-runtime))
        (errors '())
        (pause-requested-p nil))
    (labels ((add-sources (candidates)
               (dolist (source candidates)
                 (snap-sync-heal-pipeline-add-source
                  runtime source root-bytes byte-limit
                  capacity-table rtt-table)))
             (healthy-peer-count ()
               (sb-thread:with-mutex
                   ((snap-sync-heal-pipeline-runtime-lock runtime))
                 (count-if-not
                  #'snap-sync-heal-pipeline-peer-retired-p
                  (snap-sync-heal-pipeline-runtime-peers runtime))))
             (pending-copy ()
               (sb-thread:with-mutex
                   ((snap-sync-heal-pipeline-runtime-lock runtime))
                 (copy-list
                  (snap-sync-heal-pipeline-runtime-pending runtime))))
             (finish-event (event retry condition delivered)
               (let* ((peer (snap-sync-heal-pipeline-event-peer event))
                      (works (snap-sync-heal-pipeline-event-works event))
                      (elapsed
                        (snap-sync-heal-pipeline-event-elapsed-seconds event)))
                 (sb-thread:with-mutex
                     ((snap-sync-heal-pipeline-runtime-lock runtime))
                   (decf
                    (snap-sync-heal-pipeline-runtime-inflight-works runtime)
                    (length works))
                   (setf (snap-sync-heal-pipeline-peer-inflight-p peer) nil)
                   (when condition
                     (setf (snap-sync-heal-pipeline-peer-retired-p peer) t)
                     (push condition errors))
                   (unless condition
                     (unless
                         (snap-sync-heal-pipeline-peer-externally-sized-p peer)
                       (setf
                        (snap-sync-heal-pipeline-peer-capacity peer)
                        (snap-sync-heal-learn-peer-capacity
                         (snap-sync-heal-pipeline-peer-capacity peer)
                         (length works) delivered elapsed)
                        (gethash
                         (snap-sync-heal-pipeline-peer-source peer)
                         capacity-table)
                        (snap-sync-heal-pipeline-peer-capacity peer)))
                     (setf
                      (snap-sync-heal-pipeline-peer-rtt peer)
                      (snap-sync-heal-learn-peer-rtt
                       (snap-sync-heal-pipeline-peer-rtt peer) elapsed)
                      (gethash
                       (snap-sync-heal-pipeline-peer-source peer)
                       rtt-table)
                      (snap-sync-heal-pipeline-peer-rtt peer)))
                   (when retry
                     (setf (snap-sync-heal-pipeline-runtime-pending runtime)
                           (nconc
                            (snap-sync-heal-pipeline-runtime-pending runtime)
                            (copy-list retry))))
                   (sb-thread:condition-broadcast
                    (snap-sync-heal-pipeline-runtime-changed runtime))))))
      (unwind-protect
           (progn
             (add-sources sources)
             (snap-sync-heal-pipeline-enqueue
              runtime (coerce initial-works 'list))
             (loop
               (let* ((outstanding
                        (snap-sync-heal-pipeline-outstanding runtime))
                      (pausing-p
                        (or
                         pause-requested-p
                         (and pause-p (funcall pause-p outstanding)))))
                 ;; PAUSE-P is an edge-triggered coordinator decision.  Once
                 ;; observed, keep assignment stopped while the responses
                 ;; which were already in flight drain.  Re-evaluating a
                 ;; throttled stale-target predicate after each response can
                 ;; otherwise return NIL transiently and refill the queue.
                 (when pausing-p
                   (setf pause-requested-p t))
                 (unless pausing-p
                   (when refresh-sources
                     (add-sources (funcall refresh-sources)))
                   (let* ((room
                            (max
                             0
                             (- +snap-sync-heal-live-frontier-max-works+
                                outstanding))))
                     (when (plusp room)
                       (snap-sync-heal-pipeline-enqueue
                        runtime (funcall refill room outstanding))))
                   (snap-sync-heal-pipeline-dispatch
                    runtime assignment-capacity))
                 (let ((event (snap-sync-heal-pipeline-next-event runtime)))
                   (cond
                     (event
                      (multiple-value-bind (retry condition delivered)
                          (funcall
                           handle-result
                           (snap-sync-heal-pipeline-event-result event)
                           (snap-sync-heal-pipeline-event-works event))
                        (finish-event
                         event retry condition (or delivered 0))))
                     (pausing-p
                      (return
                        (values
                         (pending-copy) (nreverse errors) t)))
                     ((null (pending-copy))
                      (return (values nil (nreverse errors) nil)))
                     (t
                      ;; Refresh once more at the exact exhaustion seam. If no
                      ;; genuinely new source joins, hand the complete shared
                      ;; queue back to the durable frontier.
                      (when refresh-sources
                        (add-sources (funcall refresh-sources)))
                      (when (zerop (healthy-peer-count))
                        (return
                          (values
                           (pending-copy) (nreverse errors) nil)))))))))
        (sb-thread:with-mutex ((snap-sync-heal-pipeline-runtime-lock runtime))
          (setf (snap-sync-heal-pipeline-runtime-stopped-p runtime) t)
          (sb-thread:condition-broadcast
           (snap-sync-heal-pipeline-runtime-changed runtime)))
        (dolist (peer (snap-sync-heal-pipeline-runtime-peers runtime))
          (let ((thread (snap-sync-heal-pipeline-peer-thread peer)))
            (when thread
              (ignore-errors (sb-thread:join-thread thread)))))))))

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

(defun snap-sync-incomplete-node-identifier (reference)
  (unless (and (byte-vector-p reference) (= 32 (length reference)))
    (error "Snap incomplete-node identifier requires a 32-byte node hash"))
  (concatenate
   'vector +snap-sync-incomplete-node-identifier-prefix+ reference))

(defun snap-sync-populate-incomplete-node-batch (batch reference)
  (kv-batch-put-chain-record
   batch :metadata (snap-sync-incomplete-node-identifier reference)
   +snap-sync-incomplete-node-value+)
  batch)

(defun snap-sync-delete-incomplete-node-batch (batch reference)
  (kv-batch-delete-chain-record
   batch :metadata (snap-sync-incomplete-node-identifier reference))
  batch)

(defun snap-sync-load-incomplete-nodes (database)
  "Load the bounded-by-written-content set that disables complete-node reuse."
  (let* ((prefix +snap-sync-incomplete-node-identifier-prefix+)
         (start (kv-chain-record-key :metadata prefix))
         (end
           (kv-chain-record-key
            :metadata (snap-sync-byte-prefix-end prefix)))
         (expected-length (+ (length prefix) 32))
         (nodes (make-hash-table :test #'equalp)))
    (multiple-value-bind (iterator close-iterator)
        (kv-iterator database :start start :end end)
      (unwind-protect
           (loop
             (multiple-value-bind (key value present-p) (funcall iterator)
               (unless present-p (return))
               (let ((identifier
                       (kv-chain-record-key-identifier :metadata key)))
                 (unless (and (= (length identifier) expected-length)
                              (bytes= value +snap-sync-incomplete-node-value+))
                   (ethereum-lisp.validation:storage-fail
                    "Persisted snap incomplete-node marker is malformed"))
                 (setf
                  (gethash (subseq identifier (length prefix)) nodes) t))))
        (when close-iterator (funcall close-iterator))))
    nodes))

(defun snap-sync-healed-subtree-identifier
    (reference &optional (kind :account))
  (unless (and (byte-vector-p reference) (= 32 (length reference)))
    (error "Snap healed-subtree identifier requires a 32-byte node hash"))
  (concatenate
   'vector
   (ecase kind
     (:account +snap-sync-healed-subtree-identifier-prefix+)
     (:storage +snap-sync-healed-storage-subtree-identifier-prefix+)
     (:storage-root +snap-sync-healed-storage-root-identifier-prefix+))
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
               (member kind
                       '(:account :storage :storage-root
                         :account-dependencies)))
    (error "Snap healed-subtree Bloom input is malformed"))
  (let* ((mask (1- +snap-sync-healed-subtree-bloom-bits+))
         (salt
           (ecase kind
             (:account #x9e3779b9)
             (:storage #x85ebca6b)
             (:storage-root #x27d4eb2f)
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
     database bloom :storage-root
     +snap-sync-healed-storage-root-identifier-prefix+)
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
            (and
             (snap-sync-storage-range-tasks-completed-p
              database state-root
              (snap-sync-heal-work-account-hash work)
              (make-hash32 (snap-sync-heal-work-reference work)))
             ;; Cursor records restored from an older release are range
             ;; coverage evidence. Only a complete response or the final
             ;; closure walk publishes the whole-root proof needed here.
             (snap-sync-healed-subtree-present-p
              database (snap-sync-heal-work-reference work) :storage-root)))
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

(defun snap-sync-retire-legacy-storage-root-proof (database work)
  "Retire unsafe legacy root-shaped proofs without trusting range cursors.

Completed partition cursors prove authenticated key-space coverage, but the
compact edge proofs can still reference nodes that were never materialized.
Only a separately published whole-root closure proof may classify this work as
complete; otherwise the ordinary healer consumes the safe per-page subtree
proofs and repairs the few open boundaries."
  (let ((storage-root
          (make-hash32 (snap-sync-heal-work-reference work))))
    (when (snap-sync-storage-plan-promoted-p database storage-root)
      (return-from snap-sync-retire-legacy-storage-root-proof 0))
    ;; v4 briefly treated completed partition cursors as a full closure proof.
    ;; They only prove authenticated range coverage; the final local healer is
    ;; still the trust boundary. Conservatively retire that root-shaped v1
    ;; subtree proof before publishing the safe shallow references below.
    (let ((batch (make-kv-write-batch)))
      (kv-batch-delete-chain-record
       batch :metadata
       (snap-sync-healed-subtree-identifier
        (hash32-bytes storage-root) :storage))
      (kv-apply-batch database batch))
    0))

(defun snap-sync-account-prefix-bucket
    (account-hash &optional
                    (depth *snap-sync-range-subtree-prefix-nibbles*))
  (unless (and (integerp depth) (<= 1 depth 64))
    (error "Snap account prefix depth must be between one and 64"))
  (let ((nibbles
          (ethereum-lisp.trie.encoding:keybytes-to-nibbles
           account-hash :terminator nil)))
    (copy-seq (subseq nibbles 0 depth))))

(defun snap-sync-promote-complete-range-plan (database state-root)
  "Turn one trusted range plan into shallow reusable subtree proofs.

The plan already proves every account range and code. A large-storage task set
is complete only when its separately published whole-root closure exists;
cursor-only legacy work remains an exact dependency. Account buckets containing
such an incomplete dependency are excluded, while all other buckets can be
promoted immediately. Descendants are never read or revalidated."
  (multiple-value-bind (works trusted-plan-p overflow-p)
      (snap-sync-deferred-storage-works database state-root)
    (unless (and trusted-plan-p (not overflow-p))
      (return-from snap-sync-promote-complete-range-plan 0))
    (let ((incomplete-works '())
          (promoted 0))
      (dolist (work works)
        ;; Retire the short-lived cursor-derived root-shaped namespace even
        ;; when this work correctly remains incomplete.
        (incf promoted
              (snap-sync-retire-legacy-storage-root-proof database work))
        (unless
            (and
             (snap-sync-storage-range-tasks-completed-p
              database state-root
              (snap-sync-heal-work-account-hash work)
              (make-hash32 (snap-sync-heal-work-reference work)))
             (snap-sync-healed-subtree-present-p
              database (snap-sync-heal-work-reference work) :storage-root))
          (push work incomplete-works)))
      (unless (snap-sync-range-plan-promoted-p database state-root)
        (let ((safe-references '()))
          (unless (hash32= state-root +empty-trie-hash+)
            (let ((trie
                    (make-persisted-mpt
                     state-root
                     (lambda (hash)
                       (trie-node-store-get database hash)))))
              (dolist (depth (snap-sync-range-subtree-depths))
                (let ((unsafe-buckets (make-hash-table :test #'equalp)))
                  (dolist (work incomplete-works)
                    (setf
                     (gethash
                      (snap-sync-account-prefix-bucket
                       (snap-sync-heal-work-account-hash work) depth)
                      unsafe-buckets)
                     t))
                  (dolist
                      (entry
                       (mpt-hashed-subtrees-with-prefix-at-depth trie depth))
                    (unless (gethash (car entry) unsafe-buckets)
                      (push (cdr entry) safe-references)))))))
          (setf safe-references
                (remove-duplicates safe-references :test #'equalp))
          (incf
           promoted
           (snap-sync-persist-promoted-subtrees
            database safe-references :account
            ;; Incomplete buckets are retried after their StorageRanges
            ;; cursors finish; do not freeze a partial promotion as final.
            (and (null incomplete-works)
                 (snap-sync-range-plan-promotion-identifier state-root))))))
      promoted)))

(defun snap-sync-promote-complete-range-plans (database)
  "Backfill shallow subtree proofs for trusted pre-optimization range plans."
  (loop for state-root in (snap-sync-deferred-storage-plan-roots database)
        sum (snap-sync-promote-complete-range-plan database state-root)))

(defun snap-sync-materialize-verified-storage-page (verified)
  "Build local records and subtree metadata for authenticated VERIFIED."
  (let* ((materialize-started-at (get-internal-real-time))
         (task-index (snap-sync-verified-storage-page-task-index verified))
         (origin (snap-sync-verified-storage-page-origin verified))
         (limit (snap-sync-verified-storage-page-limit verified))
         (entries (snap-sync-verified-storage-page-entries verified))
         (proof (snap-sync-verified-storage-page-proof verified))
         (trie (snap-sync-verified-storage-page-trie verified))
         (last-wire (and entries (caar (last entries))))
         (completed-p
           (or (null entries)
               (null proof)
               (not
                (ethereum-lisp.validation:byte-vector-lexicographic<
                 last-wire limit))))
         (next-origin
           (and (not completed-p) last-wire
                (snap-sync-increment-hash last-wire)))
         (proved-end (if completed-p limit last-wire))
         (records (snap-sync-verified-account-records trie proof))
         (subtree-values
           (if (and trie proved-end)
               (multiple-value-list
                (snap-sync-proved-range-subtrees trie origin proved-end))
               (list nil nil)))
         (healed-subtrees (mapcar #'cdr (first subtree-values)))
         (complete-references
           (loop for group in (second subtree-values)
                 append (third group))))
    (when (and (not completed-p) (null next-origin))
      (error "Snap storage range page did not advance its task"))
    (make-snap-sync-storage-page-result
     :task-index task-index :origin (copy-seq origin)
     :records records
     :healed-subtrees healed-subtrees
     :complete-node-hashes complete-references
     :incomplete-node-hashes
     (snap-sync-incomplete-record-hashes records complete-references)
     :next-origin next-origin
     :completed-p completed-p
     :entry-count (length entries)
     :request-ms
     (snap-sync-elapsed-milliseconds
      (snap-sync-verified-storage-page-started-at verified)
      (snap-sync-verified-storage-page-response-at verified))
     :proof-ms
     (snap-sync-elapsed-milliseconds
      (snap-sync-verified-storage-page-response-at verified)
      (snap-sync-verified-storage-page-proof-finished-at verified))
     :materialize-ms
     (snap-sync-elapsed-milliseconds
      materialize-started-at (get-internal-real-time)))))

(defun snap-sync-prepare-storage-page
    (source state-root account-hash storage-root task-index task byte-limit)
  "Fetch and authenticate one page of a partitioned large storage trie."
  (let* ((started-at (get-internal-real-time))
         (origin (snap-sync-account-task-next-origin task))
         (limit (snap-sync-account-task-limit task))
         (request
           (make-snap-get-storage-ranges
            1 (hash32-bytes state-root) (list (copy-seq account-hash))
            origin limit byte-limit)))
    (labels
        ((verify (response)
           (let ((response-at (get-internal-real-time))
                 (groups (snap-storage-ranges-slots response))
                 (proof (snap-storage-ranges-proof response)))
             (unless (= 1 (snap-storage-ranges-id response))
               (error "Snap storage response id mismatch"))
             ;; Some snap/1 servers encode an empty proved range as no slot
             ;; groups, while others return one empty group. Both forms are
             ;; unambiguous because a partition requests exactly one account.
             (when (> (length groups) 1)
               (error
                "Snap peer returned multiple groups for one storage range task"))
             (when (and (null groups) (null proof))
               (snap-sync-state-unavailable "storage-range"))
             (let* ((entries
                      (snap-sync-storage-entries
                       (if groups (first groups) '()))))
               (multiple-value-bind (verified-p trie)
                   (if entries
                       (mpt-verify-range-proof
                        storage-root entries proof :start origin)
                       (mpt-verify-range-proof
                        storage-root entries proof :start origin
                        :end (snap-sync-increment-hash limit)))
                 (declare (ignore verified-p))
                 (make-snap-sync-verified-storage-page
                  :task-index task-index :origin (copy-seq origin)
                  :limit (copy-seq limit) :entries entries :proof proof
                  :trie trie :started-at started-at :response-at response-at
                  :proof-finished-at (get-internal-real-time)))))))
      ;; A production source uses the global per-response-type idle-peer pool.
      ;; Keep proof verification inside that reservation so a malformed or
      ;; pruned response retires the exact transport. Return it to the idle
      ;; pool before the already authenticated trie is expanded into records
      ;; and subtree metadata, matching geth's delivery/integration boundary.
      (snap-sync-materialize-verified-storage-page
       (if (functionp (snap-sync-source-storage-ranges-verified source))
           (funcall
            (snap-sync-source-storage-ranges-verified source) request #'verify)
           (verify
            (snap-sync-source-call
             (snap-sync-source-storage-ranges source)
             request "storage ranges")))))))

(defun snap-sync-build-storage-page-batch
    (database state-root account-hash storage-root task result)
  "Build one privately owned authenticated page batch and replacement cursor."
  (unless (and (not (snap-sync-account-task-completed-p task))
               (bytes= (snap-sync-account-task-next-origin task)
                       (snap-sync-storage-page-result-origin result)))
    (error "Snap storage result no longer matches its durable task cursor"))
  (let* ((batch (make-kv-write-batch))
         (replacement
           (snap-sync-account-task
            :start (snap-sync-account-task-start task)
            :limit (snap-sync-account-task-limit task)
            :next-origin
            (snap-sync-storage-page-result-next-origin result)
            :completed-p
            (snap-sync-storage-page-result-completed-p result))))
    (snap-sync-populate-verified-trie-records-batch
     database batch (snap-sync-storage-page-result-records result))
    ;; A partition page may prove closure for nodes retained by an earlier
    ;; byte-capped prefix or an adjacent page. Remove those old negatives in
    ;; the same atomic batch as the proof, records, and cursor.
    (snap-sync-delete-incomplete-records-batch
     batch (snap-sync-storage-page-result-complete-node-hashes result))
    (snap-sync-populate-incomplete-records-batch
     batch (snap-sync-storage-page-result-incomplete-node-hashes result))
    (snap-sync-populate-storage-task-batch
     batch state-root account-hash storage-root
     (snap-sync-storage-page-result-task-index result) replacement)
    ;; Storage leaves have no external state dependencies. Publish these
    ;; range-derived completion proofs in the same batch as their nodes and
    ;; cursor so a crash can never expose a proof ahead of durable content.
    (dolist (reference
             (snap-sync-storage-page-result-healed-subtrees result))
      (snap-sync-populate-healed-subtree-batch batch reference :storage))
    (values batch replacement)))

(defun snap-sync-populate-storage-page-batch
    (database batch state-root account-hash storage-root tasks result)
  "Append one authenticated storage page and cursor to BATCH.

Return the updated durable task vector without applying BATCH.  Callers may
therefore combine independent partition responses in one atomic WAL seam while
retaining the exact cursor/content crash boundary for every response."
  (let* ((task-index (snap-sync-storage-page-result-task-index result))
         (task (nth task-index tasks)))
    (unless task
      (error "Snap storage result names an unknown task"))
    (multiple-value-bind (page-batch replacement)
        (snap-sync-build-storage-page-batch
         database state-root account-hash storage-root task result)
      (kv-batch-append batch page-batch)
      (snap-sync-replace-task tasks task-index replacement))))

(defun snap-sync-commit-storage-page
    (database state-root account-hash storage-root tasks result)
  "Atomically install one authenticated storage page and its durable cursor."
  (let ((batch (make-kv-write-batch)))
    (prog1
        (snap-sync-populate-storage-page-batch
         database batch state-root account-hash storage-root tasks result)
      (kv-apply-batch database batch))))

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

Completed cursors and range-derived subtree proofs stay durable for the final
closure walk. Each source owns at most one request and verified page at a time,
but a fast source
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

(defun snap-sync-complete-deferred-storage-roots
    (database sources state-root commitments byte-limit &key source-provider)
  "Finish COMMITMENTS before their owning account page may advance.

Synchronous and portable callers give each root their current StorageRanges
sources. Production multi-source range import instead uses its fixed global
rotating lane queue, so this fallback does not multiply one all-peer worker set
per account page. Durable partition cursors make any failed page retry resume
rather than replay."
  (dolist (commitment commitments commitments)
    (unless
        (snap-sync-fill-storage-root
         database sources state-root (car commitment) (cdr commitment)
         (min byte-limit +snap-sync-storage-request-bytes+)
         :source-provider source-provider)
      (snap-sync-state-unavailable "storage-range"))))

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
  ;; A miss at the publication depth arms one region and marks its descendants
  ;; :INSIDE. Range ingestion can publish smaller proved subtrees below an open
  ;; boundary bucket, so those descendants must still probe the Bloom filter;
  ;; otherwise the first publication-depth miss masks every finer range proof below it
  ;; and turns a small boundary walk into a full local-trie scan.
  (and (member (snap-sync-heal-work-marker-state work) '(nil :inside))
       (or
        (>= (length (snap-sync-heal-work-path work))
            *snap-sync-healed-subtree-prefix-nibbles*)
        ;; A storage root can consume only the separate proof published after
        ;; full closure validation. Account roots retain the coarse-depth gate
        ;; because their leaves may name storage and code dependencies.
        (and (eq :storage (snap-sync-heal-work-kind work))
             (zerop (length (snap-sync-heal-work-path work)))))
       (let ((reference (snap-sync-heal-work-reference work)))
         (and (byte-vector-p reference) (= 32 (length reference))))))

(defun snap-sync-healed-subtree-proof-kind (work)
  "Use a separate trust namespace for a fully traversed storage root."
  (if (and (eq :storage (snap-sync-heal-work-kind work))
           (zerop (length (snap-sync-heal-work-path work))))
      :storage-root
      (snap-sync-heal-work-kind work)))

(defun snap-sync-healed-subtree-publication-candidate-p (work)
  "Select the finer boundary at which new completion proofs are published."
  (unless (and (integerp *snap-sync-range-subtree-prefix-nibbles*)
               (<= *snap-sync-healed-subtree-prefix-nibbles*
                   *snap-sync-range-subtree-prefix-nibbles*
                   64))
    (error
     "Snap range subtree depth must be between the lookup depth and 64"))
  (or
   (>= (length (snap-sync-heal-work-path work))
       *snap-sync-range-subtree-prefix-nibbles*)
   ;; A root proof is published only by the healer's post-order sentinel after
   ;; the entire storage trie has been traversed and every node is durable.
   (eq :storage-root (snap-sync-healed-subtree-proof-kind work))))

(defun snap-sync-healed-subtree-miss-marker-state (work)
  "Preserve one publication owner while probing finer nested range proofs."
  (cond
    ;; Deferred storage roots can arrive inside an account proof owner, but
    ;; their closure is independent and must own a root post-order sentinel.
    ((eq :storage-root (snap-sync-healed-subtree-proof-kind work)) :armed)
    ((eq :inside (snap-sync-heal-work-marker-state work)) :inside)
    (t
     (and (snap-sync-healed-subtree-publication-candidate-p work)
          :armed))))

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
           (complete-node-scheme-p
             (and
              (snap-sync-progress-complete-node-scheme-p progress)
              (snap-sync-complete-node-scheme-present-p database)))
           (incomplete-nodes
             (if complete-node-scheme-p
                 (snap-sync-load-incomplete-nodes database)
                 (make-hash-table :test #'equalp)))
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
           ;; STACK is a list because DFS order depends on cheap front pushes,
           ;; but LENGTH is linear. The live frontier can hold 131,072 works
           ;; while a due checkpoint deliberately waits for it to shrink below
           ;; 8,192. Keep the exact count alongside the list so every inner-loop
           ;; frontier bound remains O(1) during that interval.
           (stack-count (length stack))
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
           ;; Response nodes remain in this bounded decoded cache while their
           ;; writes accumulate to geth's 100-KiB batch threshold. No durable
           ;; frontier or subtree proof crosses that pending write prefix.
           (fetched-node-cache (make-hash-table :test #'equalp))
           (pending-fetched-batch (make-kv-write-batch))
           (pending-fetched-bytes 0)
           (pending-fetched-count 0)
           (pending-node-completion-batch (make-kv-write-batch))
           (pending-node-completion-count 0)
           ;; The local capacity table is retained only for fixed sources that
           ;; do not expose the production request queue's shared SNAP tracker.
           ;; RTT ordering survives safe checkpoint boundaries for both paths.
           (source-capacities (make-hash-table :test #'eq))
           (source-rtts (make-hash-table :test #'eq))
           ;; While the event loop owns work outside STACK, the older durable
           ;; checkpoint stays authoritative. These counters keep the combined
           ;; in-memory frontier inside the same 8,192-work bound.
           (remote-pipeline-active-p nil)
           (remote-work-count 0)
           (remote-pipeline-yield-requested-p nil)
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
           (last-checkpoint-processed-nodes processed-nodes)
           ;; Geth-style feedback state. PENDING counts delivered top-level
           ;; nodes not yet integrated by PROCESS-OBJECT; RATE is nodes/second.
           (healer-pending 0)
           (healer-processing-rate 0d0)
           ;; Geth starts maximally throttled and tunes downward instead of
           ;; instantly filling a cold frontier with remotely discovered work.
           (healer-throttle +snap-sync-heal-max-throttle+)
           (last-throttle-adjusted-at (get-internal-real-time)))
    (labels
        ((stack-push (work)
           (push work stack)
           (incf stack-count)
           work)
         (stack-pop ()
           (unless stack
             (error "Snap healer stack count diverged from its frontier"))
           (decf stack-count)
           (pop stack))
         (prefer-peer-nodes-p ()
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
                         (nconc active-sources (list source)))))))
           (copy-list active-sources))
         (report-local-checkpoint ()
           (when (and on-heal-progress
                      (plusp *snap-sync-heal-progress-node-interval*)
                      (zerop
                       (mod processed-nodes
                            *snap-sync-heal-progress-node-interval*)))
             (snap-sync-report-heal-progress
              on-heal-progress processed-nodes reused-nodes fetched-nodes
              request-count response-bytes promoted-subtrees
              skipped-subtrees
              (+ stack-count deferred-storage-count remote-work-count)
              deferred-storage-count remote-work-count
              (hash-table-count incomplete-nodes) nil)))
         (record-processing-rate (started-at processed-before)
           (let ((fills (- processed-nodes processed-before)))
             (when (plusp fills)
               (setf healer-processing-rate
                     (snap-sync-heal-processing-rate
                      healer-processing-rate fills
                      (max
                       1d-6
                       (/ (- (get-internal-real-time) started-at)
                          (float internal-time-units-per-second 1d0))))))))
         (adjust-healer-throttle ()
           (let ((now (get-internal-real-time)))
             (when (>= (- now last-throttle-adjusted-at)
                       internal-time-units-per-second)
               (setf healer-throttle
                     (snap-sync-heal-next-throttle
                      healer-throttle healer-pending healer-processing-rate)
                     last-throttle-adjusted-at now))))
         (current-request-paths ()
           ;; This is the frontier-fill ceiling, not an individual peer's live
           ;; assignment. Dispatch derives that from the shared SNAP tracker
           ;; divided by HEALER-THROTTLE, matching geth.
           +snap-sync-heal-paths-per-source+)
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
             (stack-push
              (snap-sync-make-heal-work
               kind account-hash path reference
               :marker-state marker-state))))
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
             (stack-push work))
           (setf deferred-storage nil
                 deferred-storage-count 0))
         (flush-fetched-nodes (&optional synchronous-p)
           ;; A buffered RocksDB batch is recoverably ordered before the next
           ;; synchronous checkpoint/proof/completion batch. Memory and file
           ;; test oracles keep their stronger all-or-none apply semantics.
           (when (plusp pending-fetched-count)
             (if synchronous-p
                 (kv-apply-batch database pending-fetched-batch)
                 (kv-apply-batch-buffered database pending-fetched-batch))
             (setf pending-fetched-batch (make-kv-write-batch)
                   pending-fetched-bytes 0
                   pending-fetched-count 0)))
         (flush-codes ()
           (when pending-codes
             (flush-fetched-nodes)
             (unless active-sources
               (snap-sync-heal-signal-source-errors
                (nreverse retired-source-errors)))
             (snap-sync-heal-fetch-codes
              database active-sources (nreverse pending-codes) byte-limit
              on-source-error)
             (setf pending-codes nil
                   pending-code-count 0)
             ;; The durable MultiGet inside SNAP-SYNC-HEAL-FETCH-CODES makes
             ;; it safe to forget this exact in-memory set after each bounded
             ;; batch. A repeated hash in a later part of a large account trie
             ;; is rechecked locally and never fetched again, while the healer
             ;; no longer retains millions of code-hash vectors until exit.
             (clrhash seen-code-hashes)))
         (flush-node-completions (&optional synchronous-p)
           (when (plusp pending-node-completion-count)
             (if synchronous-p
                 (kv-apply-batch database pending-node-completion-batch)
                 (kv-apply-batch-buffered
                  database pending-node-completion-batch))
             (setf pending-node-completion-batch (make-kv-write-batch)
                   pending-node-completion-count 0)))
         (persist-complete-node (work)
           ;; The parent marker is removed only after every child, account
           ;; code, and storage dependency encountered before this DFS
           ;; sentinel is durable. A crash before the buffered delete leaves
           ;; the marker behind and conservatively repeats the walk.
           (let ((reference (snap-sync-heal-work-reference work)))
             (unless (and complete-node-scheme-p
                          (byte-vector-p reference)
                          (= 32 (length reference)))
               (error "Snap node-completion work is not a complete-node hash"))
             (flush-fetched-nodes)
             (flush-codes)
             (snap-sync-delete-incomplete-node-batch
              pending-node-completion-batch reference)
             (remhash reference incomplete-nodes)
             (incf pending-node-completion-count)
             (when (= pending-node-completion-count
                      +snap-sync-node-completions-per-batch+)
               (flush-node-completions))))
         (flush-healed-subtrees ()
           ;; Every dependency encountered before a completion sentinel must
           ;; be durable before its reusable proof becomes visible.  Publish
           ;; many independent content-addressed proofs with one WAL sync;
           ;; losing an unflushed cache hint can only repeat safe traversal.
           (flush-fetched-nodes)
           (flush-codes)
           (flush-node-completions)
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
                  (kind (snap-sync-healed-subtree-proof-kind work))
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
                (<= (+ stack-count deferred-storage-count pending-count
                       remote-work-count)
                    +snap-sync-heal-checkpoint-max-works+)))
         (queue-code-hash (hash)
           ;; Keep an exact set for one bounded batch. FLUSH-CODES clears it
           ;; after the durable MultiGet/fetch/write seam; later duplicates
           ;; pay one local bulk lookup without retaining traversal-wide heap.
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
           (when (snap-sync-heal-work-fetched-p work)
             (when (plusp healer-pending)
               (decf healer-pending)))
           (incf processed-nodes)
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
                (error "Snap healing response has invalid trie node arity"))))
           ;; Report only after this node has exposed every immediate child and
           ;; account dependency. Reporting between POP and expansion would
           ;; transiently understate the discovered frontier.
           (report-local-checkpoint))
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
         (complete-local-node-p (work)
           (let ((reference (snap-sync-heal-work-reference work)))
             (and complete-node-scheme-p
                  (byte-vector-p reference)
                  (= 32 (length reference))
                  (not (nth-value 1 (gethash reference incomplete-nodes))))))
         (decode-local-node (work encoded)
           (if (complete-local-node-p work)
               (let ((reference (snap-sync-heal-work-reference work)))
                 ;; Preserve the existing corrupt-value fail-closed boundary
                 ;; while avoiding RLP decode and descendant expansion.
                 (unless (bytes= reference (keccak-256 encoded))
                   (ethereum-lisp.validation:storage-fail
                    "Persisted complete snap trie node does not match its hash"))
                 :complete-node-reused)
               (decode-encoded
                work encoded
                (not (snap-sync-heal-work-fetched-p work)))))
         (integrate-present-work (work object)
           (unless (snap-sync-heal-work-fetched-p work)
             (incf reused-nodes))
           (if (eq object :complete-node-reused)
               (progn
                 ;; The versioned negative-marker scheme is itself a durable
                 ;; closure proof: absence of this node's incomplete marker
                 ;; means all descendants were completed. Materialize the
                 ;; stronger root namespace after its ordinary proof miss.
                 (when
                     (eq :armed (snap-sync-heal-work-marker-state work))
                   (stack-push
                    (snap-sync-make-heal-work
                     (snap-sync-heal-work-kind work)
                     (snap-sync-heal-work-account-hash work)
                     (snap-sync-heal-work-path work)
                     (snap-sync-heal-work-reference work)
                     :marker-state :complete)))
                 (incf skipped-subtrees))
               (progn
                 (when
                     (eq :armed (snap-sync-heal-work-marker-state work))
                   (stack-push
                    (snap-sync-make-heal-work
                     (snap-sync-heal-work-kind work)
                     (snap-sync-heal-work-account-hash work)
                     (snap-sync-heal-work-path work)
                     (snap-sync-heal-work-reference work)
                     :marker-state :complete)))
                 (let ((reference (snap-sync-heal-work-reference work)))
                   (when (and complete-node-scheme-p
                              (byte-vector-p reference)
                              (= 32 (length reference))
                              (nth-value
                               1 (gethash reference incomplete-nodes)))
                     (stack-push
                      (snap-sync-make-heal-work
                       (snap-sync-heal-work-kind work)
                       (snap-sync-heal-work-account-hash work)
                       (snap-sync-heal-work-path work)
                       reference :marker-state :node-complete))))
                 (process-object work object))))
         (collect-missing (maximum &optional bounded-refill-p)
           "Advance local trie work and return at most MAXIMUM missing hashes.

When BOUNDED-REFILL-P is true, yield after one deterministic local-work quantum
so the live remote pipeline can integrate completed responses before looking
for more missing hashes."
           (when (zerop maximum)
             (return-from collect-missing nil))
           (let* ((pass-started-at (get-internal-real-time))
                  (processed-before processed-nodes)
                  (examined-count 0)
                  (missing '())
                  (missing-count 0)
                  (missing-limit
                    (min
                     maximum
                     (snap-sync-heal-missing-limit
                      (+ stack-count deferred-storage-count
                         remote-work-count)
                      ;; A local fallback remains useful after every peer in a
                      ;; pruned-pivot generation has been retired.
                      (max 1 (length active-sources))
                      +snap-sync-heal-paths-per-source+))))
             (loop while (and stack
                              (< missing-count missing-limit)
                              (or
                               (not bounded-refill-p)
                               (plusp
                                (snap-sync-heal-pipeline-refill-work-room
                                 examined-count)))
                              (< deferred-storage-count
                                 +snap-sync-heal-deferred-storage-target+)
                              (not
                               (checkpoint-blocks-traversal-p missing-count)))
                   do
                   (let* ((checkpoint-room
                            (max
                             1
                             (- +snap-sync-heal-checkpoint-node-interval+
                                (- processed-nodes
                                   last-checkpoint-processed-nodes))))
                          (read-limit
                            (min
                             (snap-sync-heal-local-read-limit
                              (+ stack-count deferred-storage-count
                                 remote-work-count missing-count)
                              missing-count missing-limit checkpoint-room)
                             (if bounded-refill-p
                                 (max
                                  1
                                  (snap-sync-heal-pipeline-refill-work-room
                                   examined-count))
                                 +snap-sync-heal-local-reads-per-batch+)))
                          (lookups '())
                          (lookup-count 0))
                     ;; Inline references are already local values. Once a
                     ;; hash batch begins, preserve its exact ordering until
                     ;; the batched local read resolves every popped work.
                     (loop while (and stack
                                      (< lookup-count read-limit)
                                      (not
                                       (checkpoint-blocks-traversal-p
                                        missing-count)))
                           for work = (stack-pop)
                           for reference =
                             (snap-sync-heal-work-reference work)
                           do (incf examined-count)
                           (cond
                             ((eq :node-complete
                                  (snap-sync-heal-work-marker-state work))
                              (if (or lookups deferred-storage)
                                  (progn
                                    (stack-push work)
                                    (unless lookups
                                      (drain-deferred-storage))
                                    (return))
                                  (persist-complete-node work)))
                             ((eq :complete
                                  (snap-sync-heal-work-marker-state work))
                              (if (or lookups deferred-storage)
                                  (progn
                                    (stack-push work)
                                    (unless lookups
                                      (drain-deferred-storage))
                                    (return))
                                  (persist-healed-subtree work)))
                             ((snap-sync-healed-subtree-candidate-p work)
                              (push work lookups)
                              (incf lookup-count))
                             ((or (rlp-list-p reference)
                                  (zerop (length reference)))
                              (if lookups
                                  (stack-push work)
                                  (when (rlp-list-p reference)
                                    (process-object work reference)))
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
                                     #'snap-sync-healed-subtree-proof-kind
                                     candidate-works))
                              (candidate-presence
                                (if candidate-works
                                    (snap-sync-filtered-healed-subtrees-present
                                     database candidate-references
                                     candidate-kinds healed-subtree-bloom)
                                    #()))
                              (candidate-dependencies
                                (if candidate-works
                                    (snap-sync-filtered-account-subtree-dependencies
                                     database candidate-references
                                     candidate-kinds candidate-presence
                                     healed-subtree-bloom)
                                    #()))
                              (candidate-index 0)
                              (actual-lookups '()))
                         (loop for work across ordered
                               do
                               (if
                                (snap-sync-healed-subtree-candidate-p work)
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
                                      (<= (+ stack-count missing-count
                                             deferred-storage-count
                                             remote-work-count
                                             (length dependencies))
                                          +snap-sync-heal-live-frontier-max-works+))
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
                                       (snap-sync-healed-subtree-miss-marker-state
                                        work))
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
                                   (and active-sources
                                        (prefer-peer-nodes-p)))
                                  :decoder
                                  (lambda (index bytes)
                                    (decode-local-node
                                     (aref ordered index) bytes)))
                               (declare (ignore encoded))
                               (dotimes (index (length ordered))
                                 (let ((work (aref ordered index)))
                                   (if (= 1 (aref present index))
                                       (integrate-present-work
                                        work (aref decoded index))
                                       (progn
                                         (push work missing)
                                         (incf missing-count))))))))))))
             (record-processing-rate pass-started-at processed-before)
             (adjust-healer-throttle)
             (drain-deferred-storage)
             (unless remote-pipeline-active-p
               (flush-healed-subtrees))
             (nreverse missing)))
         (fetch-missing (missing)
           (refresh-active-sources)
           (unless active-sources
             (snap-sync-heal-signal-source-errors
              (reverse retired-source-errors)))
           #+sbcl
           (progn
             (setf remote-pipeline-active-p t
                   remote-work-count (length missing)
                   remote-pipeline-yield-requested-p nil)
             (unwind-protect
                  (labels
                 ((pipeline-checkpoint-due-p (outstanding)
                    (setf remote-work-count outstanding)
                    (let ((stale-p
                            (and heal-yield-p (funcall heal-yield-p))))
                      ;; Carry the edge-triggered stale decision through the
                      ;; durable seam. Re-evaluating a throttled predicate
                      ;; after the pipeline returns can turn the same decision
                      ;; back into NIL and start another remote generation.
                      (when stale-p
                        (setf remote-pipeline-yield-requested-p t))
                      (or
                       ;; A stale-root decision is independent from the normal
                       ;; checkpoint cadence.  Stop assigning new work now;
                       ;; SNAP-SYNC-HEAL-RUN-PIPELINE still drains every
                       ;; in-flight response before returning the pending queue,
                       ;; so the caller reaches the ordinary durable batch seam.
                       ;; Without this check, one-node responses can refill the
                       ;; pipeline forever and postpone HEAL-YIELD-P until the
                       ;; entire remote frontier happens to become quiescent.
                       stale-p
                       (and
                        (checkpoint-due-p)
                        (<= (+ stack-count deferred-storage-count
                               remote-work-count)
                            +snap-sync-heal-checkpoint-max-works+)))))
                  (retire-source (source condition)
                    (when (typep
                           condition
                           'ethereum-lisp.validation:storage-error)
                      (error condition))
                    (push condition retired-source-errors)
                    (pushnew source retired-sources :test #'eq)
                    (setf active-sources
                          (remove source active-sources :test #'eq))
                    (when on-source-error
                      (funcall on-source-error source condition)))
                  (handle-result (result works)
                    (incf request-count)
                    (let ((condition
                            (snap-sync-heal-fetch-result-condition result)))
                      (when condition
                        (when (typep condition 'snap-sync-request-timeout)
                          ;; The transport already expired only this wire id,
                          ;; reset TrieNodes capacity, and retained the live
                          ;; RLPx session.  Preserve that request-local verdict
                          ;; here too: return the immutable work to the shared
                          ;; queue without retiring the peer or consuming the
                          ;; source-error callback.  A delayed response for the
                          ;; expired id is discarded by the session boundary.
                          (return-from handle-result
                            (values (coerce works 'list) nil 0)))
                        (retire-source
                         (snap-sync-heal-fetch-result-source result)
                         condition)
                        (return-from handle-result
                          (values (coerce works 'list) condition 0))))
                    (handler-case
                        (let* ((matched
                                 (make-array (length works)
                                             :initial-element nil))
                               (decoded
                                 (make-array (length works)
                                             :initial-element nil))
                               (order
                                 (snap-sync-heal-fetch-result-order result))
                               (cursor 0)
                               (fills 0)
                               (fetched-bytes 0)
                               (unmatched '()))
                          ;; Validate and decode the entire individual response
                          ;; before any of its content becomes visible.
                          (dolist
                              (encoded
                               (snap-trie-nodes-nodes
                                (snap-sync-heal-fetch-result-response result)))
                            (let ((hash (keccak-256 encoded))
                                  (found nil))
                              (loop while (< cursor (length order))
                                    for index = (aref order cursor)
                                    for work = (aref works index)
                                    for expected =
                                      (snap-sync-heal-work-reference work)
                                    do (incf cursor)
                                       (when (bytes= hash expected)
                                         (setf found index)
                                         (return)))
                              (unless found
                                (error
                                 "Snap peer returned an unrequested healing node"))
                              (setf (aref matched found) encoded
                                    (aref decoded found)
                                    (decode-encoded
                                     (aref works found) encoded nil))
                              (incf fills)
                              (incf fetched-bytes (length encoded))))
                          (dotimes (index (length works))
                            (let ((work (aref works index))
                                  (encoded (aref matched index)))
                              (if encoded
                                  (let ((hash
                                          (snap-sync-heal-work-reference work)))
                                    (kv-batch-put-chain-record
                                     pending-fetched-batch
                                     :trie-node hash encoded)
                                    (when complete-node-scheme-p
                                      (snap-sync-populate-incomplete-node-batch
                                       pending-fetched-batch hash)
                                      (setf (gethash hash incomplete-nodes) t))
                                    (incf pending-fetched-count)
                                    (incf pending-fetched-bytes
                                          (+ (length hash) (length encoded)))
                                    (setf
                                     (gethash hash fetched-node-cache)
                                     (aref decoded index)))
                                  (push work unmatched))))
                          ;; Reinsert only delivered work as fetched. The local
                          ;; frontier limiter processes it from the decoded
                          ;; cache and exposes children while slow peers remain
                          ;; independently in flight.
                          (loop for index downfrom (1- (length works)) to 0
                                when (aref matched index)
                                  do (stack-push
                                      (snap-sync-copy-heal-work
                                       (aref works index) :fetched-p t)))
                          (incf fetched-nodes fills)
                          (incf response-bytes fetched-bytes)
                          (incf healer-pending fills)
                          (when (>= pending-fetched-bytes
                                    +snap-sync-heal-write-batch-bytes+)
                            (flush-fetched-nodes))
                          ;; HANDLE-RESULT runs before FINISH-EVENT retires this
                          ;; job from the pipeline's in-flight count. Delivered
                          ;; work is already back on STACK, while UNMATCHED is
                          ;; about to re-enter the shared remote queue. Compute
                          ;; the post-event remote count explicitly so neither
                          ;; class is omitted or counted twice in this snapshot.
                          (let ((remaining-remote-work-count
                                  (+
                                   (max 0
                                        (- remote-work-count (length works)))
                                   (length unmatched))))
                            (snap-sync-report-heal-progress
                             on-heal-progress processed-nodes reused-nodes
                             fetched-nodes request-count response-bytes
                             promoted-subtrees skipped-subtrees
                             (+ stack-count deferred-storage-count
                                remaining-remote-work-count)
                             deferred-storage-count
                             remaining-remote-work-count
                             (hash-table-count incomplete-nodes) nil))
                          (values (nreverse unmatched) nil fills))
                      (ethereum-lisp.validation:storage-error (condition)
                        (error condition))
                      (serious-condition (condition)
                        (retire-source
                         (snap-sync-heal-fetch-result-source result)
                         condition)
                        (values (coerce works 'list) condition 0))))
                  (refill (room outstanding)
                    (let ((available
                            (min
                             room
                             (max
                              (if stack 1 0)
                              (- +snap-sync-heal-live-frontier-max-works+
                                 outstanding stack-count
                                 deferred-storage-count)))))
                      (if (plusp available)
                          (let ((new-missing
                                  (collect-missing available t)))
                            (setf remote-work-count
                                  (+ outstanding (length new-missing)))
                            new-missing)
                          (progn
                            (setf remote-work-count outstanding)
                            nil)))))
               (multiple-value-bind (remaining errors paused-p)
                   (snap-sync-heal-run-pipeline
                    active-sources missing root-bytes byte-limit
                    source-capacities source-rtts
                    #'handle-result #'refill #'refresh-active-sources
                    #'pipeline-checkpoint-due-p
                    (lambda (source)
                      (snap-sync-heal-source-request-capacity
                       source healer-throttle)))
                 (setf remote-work-count 0)
                 (flush-fetched-nodes)
                 (flush-healed-subtrees)
                 (when (or remaining paused-p)
                   (dolist (work (reverse remaining))
                     (stack-push work))
                   (when (snap-sync-heal-checkpoint-frontier-p stack)
                     (persist-checkpoint stack))
                   (when paused-p
                     (when remote-pipeline-yield-requested-p
                       (error 'snap-sync-heal-yielded))
                     (return-from fetch-missing nil))
                   (when (prefer-peer-nodes-p)
                     (return-from fetch-missing nil))
                   (snap-sync-heal-signal-source-errors
                    (or errors (reverse retired-source-errors))))))
               (setf remote-pipeline-active-p nil
                     remote-work-count 0
                     remote-pipeline-yield-requested-p nil)))
           #-sbcl
           (error "Snap asynchronous healer requires SBCL threads")))
      (loop
        ;; No request worker or uncommitted database batch crosses this seam.
        ;; A coordinator may therefore yield a stale, CL-authorized target and
        ;; atomically rebase its durable progress on the next pass. Content-
        ;; addressed nodes and completed-subtree proofs remain reusable.
        (when (and heal-yield-p (funcall heal-yield-p))
          (error 'snap-sync-heal-yielded))
        (let* ((pass-started-at (get-internal-real-time))
               (processed-before processed-nodes)
               (missing '())
               (missing-count 0)
               (request-paths (current-request-paths))
               (missing-limit
                 (snap-sync-heal-missing-limit
                  (+ stack-count deferred-storage-count)
                  ;; One local fallback batch remains useful after every peer
                  ;; in a pruned-pivot generation has been retired. A truly
                  ;; absent node reaches FETCH-MISSING and reports exhaustion.
                  (max 1 (length active-sources))
                  request-paths)))
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
                          (+ stack-count deferred-storage-count
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
                        for work = (stack-pop)
                        for reference =
                          (snap-sync-heal-work-reference work)
                        do (cond
                             ((eq :node-complete
                                  (snap-sync-heal-work-marker-state work))
                              (if (or lookups deferred-storage)
                                  (progn
                                    (stack-push work)
                                    (unless lookups
                                      (drain-deferred-storage))
                                    (return))
                                  (persist-complete-node work)))
                             ((eq :complete
                                  (snap-sync-heal-work-marker-state work))
                              (if (or lookups deferred-storage)
                                  (progn
                                    (stack-push work)
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
                                  (stack-push work)
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
                                  #'snap-sync-healed-subtree-proof-kind
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
                                      (<= (+ stack-count missing-count
                                             deferred-storage-count
                                             (length dependencies))
                                          +snap-sync-heal-live-frontier-max-works+))
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
                                       (snap-sync-healed-subtree-miss-marker-state
                                        work))
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
                                 (decode-local-node
                                  (aref ordered index) bytes)))
                            (declare (ignore encoded))
                            (dotimes (index (length ordered))
                              (let ((work (aref ordered index)))
                                (if (= 1 (aref present index))
                                    (integrate-present-work
                                     work (aref decoded index))
                                    (progn
                                      (push work missing)
                                      (incf missing-count))))))))))))
          (record-processing-rate pass-started-at processed-before)
          (adjust-healer-throttle)
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
       request-count response-bytes promoted-subtrees skipped-subtrees
       0 0 0 (hash-table-count incomplete-nodes) t)
      completed))))))

(defun snap-sync-release-range-phase-memory ()
  "Reclaim transient flat-range heap before the local healing walk."
  #+sbcl (sb-ext:gc :full t)
  #-sbcl nil)

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
               (snap-sync-range-plan-fully-durable-p
                database (snap-sync-progress-state-root progress))
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
         on-heal-progress 0 0 0 0 0 0 0 0 0 0 0 t)
        (return-from snap-sync-fill-storage-then-heal completed))))
  ;; Range workers and their page/dependency graphs have all joined. A full
  ;; collection at this one phase boundary returns their old-generation pages
  ;; before RocksDB's cache and the local healer compete with the colocated
  ;; consensus client on the supported 16-GiB profile.
  (snap-sync-release-range-phase-memory)
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
partial trie nodes, bytecodes, and storage it names. Complete small storage
tries are batched eagerly; byte-capped large tries immediately enter sixteen
restart-safe StorageRanges partitions and publish safe range-subtree proofs
before the owning account cursor advances. The final content-addressed walk
repairs compact-proof boundaries and publishes whole-root closure before the
completion marker.
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
  (code-inflight (make-hash-table :test #'equalp))
  (code-write-lock
    (sb-thread:make-mutex :name "snap-sync-code-publish"))
  ;; One fixed worker per imported source drains all large-root partitions.
  ;; The shared queue rotates after every claim: an open root keeps priority
  ;; over new small-state discovery, but cannot serialize unrelated account
  ;; tasks behind all sixteen of its partitions. This is the same global
  ;; idle-peer boundary used by geth's assignStorageTasks loop.
  (storage-write-lock
    (sb-thread:make-mutex :name "snap-sync-storage-publish"))
  (storage-sources '())
  (storage-jobs '())
  (storage-results '())
  (storage-worker-count 0)
  (storage-committer-active-p nil)
  (storage-source-errors '())
  storage-fatal-condition
  storage-profile-callback
  (code-jobs '())
  (code-worker-count 0)
  (dependency-jobs '())
  (events '())
  source-count
  max-pages
  (pages 0)
  (last-full-gc-pages 0)
  stopped-p)

#+sbcl
(defstruct (snap-sync-code-task
            (:constructor make-snap-sync-code-task
                (owner source byte-limit pending)))
  "One page's owned hashes scheduled through the global ByteCodes queue."
  owner
  source
  byte-limit
  pending
  condition)

#+sbcl
(defstruct (snap-sync-code-job
            (:constructor make-snap-sync-code-job (task hashes)))
  task
  hashes)

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
(defstruct (snap-sync-global-storage-job
            (:constructor make-snap-sync-global-storage-job
                (account-hash storage-root tasks)))
  "One durable large-root task shared by the import-wide StorageRanges lanes."
  account-hash
  storage-root
  tasks
  (claims (make-hash-table))
  (waiters 1)
  completed-p)

#+sbcl
(defstruct (snap-sync-global-storage-result
            (:constructor make-snap-sync-global-storage-result
                (job task-index source result batch replacement
                     batch-build-ms)))
  "One verified partition response waiting for the durable commit coordinator."
  job
  task-index
  source
  result
  batch
  replacement
  (batch-build-ms 0))

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
        ((>= (hash-table-count (snap-sync-multi-runtime-claims runtime))
             +snap-sync-account-inflight-pages+)
         (sb-thread:condition-wait
          (snap-sync-multi-runtime-changed runtime)
          (snap-sync-multi-runtime-lock runtime)))
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
(defun snap-sync-multi-push-yield (runtime event)
  "Stop the worker generation and publish one non-peer scheduling yield."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (unless (snap-sync-multi-runtime-stopped-p runtime)
      (setf (snap-sync-multi-runtime-stopped-p runtime) t
            (snap-sync-multi-runtime-events runtime)
            (nconc (snap-sync-multi-runtime-events runtime) (list event))))
    (snap-sync-multi-notify runtime)))

#+sbcl
(defun snap-sync-multi-push-dependency (runtime event)
  "Move one verified account range to the independent dependency scheduler."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (setf (snap-sync-multi-runtime-dependency-jobs runtime)
          (nconc
           (snap-sync-multi-runtime-dependency-jobs runtime) (list event)))
    (snap-sync-multi-notify runtime)))

#+sbcl
(defun snap-sync-multi-claim-dependency (runtime)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (loop
      (when (snap-sync-multi-runtime-stopped-p runtime)
        (return nil))
      (when (snap-sync-multi-runtime-dependency-jobs runtime)
        (return (pop (snap-sync-multi-runtime-dependency-jobs runtime))))
      (sb-thread:condition-wait
       (snap-sync-multi-runtime-changed runtime)
       (snap-sync-multi-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-multi-mark-source-failed (runtime source)
  "Mark SOURCE once and return whether its failure should be reported."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (unless (gethash source (snap-sync-multi-runtime-failed-sources runtime))
      (setf (gethash source (snap-sync-multi-runtime-failed-sources runtime)) t)
      (snap-sync-multi-notify runtime)
      t)))

#+sbcl
(defun snap-sync-global-storage-job-matches-p
    (job account-hash storage-root)
  (and
   (bytes= account-hash
           (snap-sync-global-storage-job-account-hash job))
   (hash32= storage-root
            (snap-sync-global-storage-job-storage-root job))))

#+sbcl
(defun snap-sync-multi-claim-storage-page (runtime source)
  "Claim one large-root partition from the rotating global job queue."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (loop
      (when (snap-sync-multi-runtime-stopped-p runtime)
        (return (values nil nil nil)))
      (let* ((jobs (snap-sync-multi-runtime-storage-jobs runtime))
             (count (length jobs)))
        (loop repeat count
              for job = (pop jobs)
              do
                 ;; Rotate after every examination. Successive idle sources
                 ;; therefore visit different roots before returning to a
                 ;; root that still has more of its sixteen chunks available.
                 (setf jobs (nconc jobs (list job)))
                 (unless (snap-sync-global-storage-job-completed-p job)
                   (loop for task in
                           (snap-sync-global-storage-job-tasks job)
                         for task-index from 0
                         unless
                           (or
                            (snap-sync-account-task-completed-p task)
                            (gethash
                             task-index
                             (snap-sync-global-storage-job-claims job)))
                           do
                              (setf
                               (gethash
                                task-index
                                (snap-sync-global-storage-job-claims job))
                               source
                               (snap-sync-multi-runtime-storage-jobs runtime)
                               jobs)
                              (return-from
                                  snap-sync-multi-claim-storage-page
                                (values
                                 job task-index
                                 (snap-sync-copy-account-task task)))))
                 (setf (snap-sync-multi-runtime-storage-jobs runtime) jobs)))
      (sb-thread:condition-wait
       (snap-sync-multi-runtime-changed runtime)
       (snap-sync-multi-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-multi-release-storage-claim
    (runtime job task-index source)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (when (eq source
              (gethash
               task-index (snap-sync-global-storage-job-claims job)))
      (remhash task-index (snap-sync-global-storage-job-claims job)))
    (snap-sync-multi-notify runtime)))

#+sbcl
(defun snap-sync-multi-fail-storage-claim
    (runtime job task-index source condition fatal-p)
  "Release one claim and classify its failure at the scheduler boundary."
  (snap-sync-multi-release-storage-claim
   runtime job task-index source)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (push condition
          (snap-sync-multi-runtime-storage-source-errors runtime))
    (when fatal-p
      (setf (snap-sync-multi-runtime-storage-fatal-condition runtime)
            condition))
    (snap-sync-multi-notify runtime)))

#+sbcl
(defun snap-sync-multi-queue-storage-result
    (runtime job task-index source result batch replacement batch-build-ms)
  "Queue one verified response for the bounded commit pipeline.

Return NIL when the generation stopped before the result could be queued."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (loop
      (when (snap-sync-multi-runtime-storage-fatal-condition runtime)
        (error (snap-sync-multi-runtime-storage-fatal-condition runtime)))
      (when (snap-sync-multi-runtime-stopped-p runtime)
        (return nil))
      (when (< (length (snap-sync-multi-runtime-storage-results runtime))
               +snap-sync-storage-result-buffer-pages+)
        (unless
            (eq source
                (gethash task-index
                         (snap-sync-global-storage-job-claims job)))
          (error "Snap global storage result lost its partition claim"))
        (setf (snap-sync-multi-runtime-storage-results runtime)
              (nconc
               (snap-sync-multi-runtime-storage-results runtime)
               (list
                (make-snap-sync-global-storage-result
                 job task-index source result batch replacement
                 batch-build-ms))))
        (snap-sync-multi-notify runtime)
        (return t))
      (sb-thread:condition-wait
       (snap-sync-multi-runtime-changed runtime)
       (snap-sync-multi-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-multi-storage-result-batch (runtime)
  "Take one bounded verified response batch, or signal a latched fatal error."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (when (snap-sync-multi-runtime-storage-fatal-condition runtime)
      (error (snap-sync-multi-runtime-storage-fatal-condition runtime)))
    (prog1
        (loop repeat +snap-sync-storage-cursor-batch-pages+
              while (snap-sync-multi-runtime-storage-results runtime)
              collect (pop (snap-sync-multi-runtime-storage-results runtime)))
      (snap-sync-multi-notify runtime))))

#+sbcl
(defun snap-sync-multi-wait-storage-result-batch (runtime)
  "Wait for one bounded commit batch, or return NIL when the import stops."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (loop
      (when (snap-sync-multi-runtime-storage-fatal-condition runtime)
        (error (snap-sync-multi-runtime-storage-fatal-condition runtime)))
      (when (snap-sync-multi-runtime-stopped-p runtime)
        (return nil))
      (when (snap-sync-multi-runtime-storage-results runtime)
        (return
          (prog1
              (loop repeat +snap-sync-storage-cursor-batch-pages+
                    while (snap-sync-multi-runtime-storage-results runtime)
                    collect
                    (pop (snap-sync-multi-runtime-storage-results runtime)))
            (snap-sync-multi-notify runtime))))
      (sb-thread:condition-wait
       (snap-sync-multi-runtime-changed runtime)
       (snap-sync-multi-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-multi-commit-storage-results
    (runtime database state-root entries &key (writer-idle-ms 0))
  "Buffer ENTRIES through one atomic WAL batch and release their claims.

The owning account page cannot publish its successor cursor until every
storage job is complete.  Its later synchronous cursor batch therefore flushes
this entire WAL prefix.  A crash before that seam leaves the account cursor
behind and may safely replay any lost storage pages."
  (declare (ignore state-root))
  (let ((batch (make-kv-write-batch))
        (task-updates '())
        (profile nil)
        (prepare-started-at (get-internal-real-time)))
    ;; Claims are immutable from verification until this coordinator releases
    ;; them. Validate the complete batch before constructing any durable state.
    (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
      (dolist (entry entries)
        (let ((job (snap-sync-global-storage-result-job entry))
              (task-index
                (snap-sync-global-storage-result-task-index entry))
              (source (snap-sync-global-storage-result-source entry)))
          (unless
              (eq source
                  (gethash task-index
                           (snap-sync-global-storage-job-claims job)))
            (error "Snap global storage batch lost a partition claim")))))
    (dolist (entry entries)
      (let* ((job (snap-sync-global-storage-result-job entry))
             (task-index
               (snap-sync-global-storage-result-task-index entry))
             (result (snap-sync-global-storage-result-result entry))
             (page-batch (snap-sync-global-storage-result-batch entry))
             (replacement
               (snap-sync-global-storage-result-replacement entry))
             (update (assoc job task-updates :test #'eq))
             (current
               (if update
                   (cdr update)
                   (sb-thread:with-mutex
                       ((snap-sync-multi-runtime-lock runtime))
                     (snap-sync-global-storage-job-tasks job))))
             (task (nth task-index current)))
        (unless task
          (error "Snap global storage batch names an unknown task"))
        (unless
            (= task-index (snap-sync-storage-page-result-task-index result))
          (error "Snap global storage batch task index mismatch"))
        ;; Revalidate the cursor against the latest committed task vector. A
        ;; claim keeps this partition immutable while its worker prepares the
        ;; private page batch, but other partitions may commit meanwhile.
        (unless
            (and
             (not (snap-sync-account-task-completed-p task))
             (bytes= (snap-sync-account-task-next-origin task)
                     (snap-sync-storage-page-result-origin result))
             (equalp
              replacement
              (snap-sync-account-task
               :start (snap-sync-account-task-start task)
               :limit (snap-sync-account-task-limit task)
               :next-origin
               (snap-sync-storage-page-result-next-origin result)
               :completed-p
               (snap-sync-storage-page-result-completed-p result))))
          (error "Snap prepared storage batch no longer matches its task"))
        (kv-batch-append batch page-batch)
        (let ((next
                (snap-sync-replace-task current task-index replacement)))
          (if update
              (setf (cdr update) next)
              (push (cons job next) task-updates)))))
    ;; Keep each response's nodes, proof metadata, and exact storage cursor
    ;; atomic, but do not force an intermediate fsync.  These cursors are only
    ;; prerequisites inside an unfinished account page; the account cursor's
    ;; later synchronous batch flushes this preceding WAL prefix before making
    ;; progress externally durable.  This matches geth's in-memory storage
    ;; subtask progress without giving up our restart-safe cursor format.
    (multiple-value-bind (operation-count logical-bytes)
        (kv-write-batch-statistics batch)
      (let* ((commit-started-at (get-internal-real-time))
             (prepare-ms
               (snap-sync-elapsed-milliseconds
                prepare-started-at commit-started-at)))
        (kv-apply-batch-buffered database batch)
        (setf profile
              (make-snap-sync-storage-profile
               :page-count (length entries)
               :slot-count
               (loop for entry in entries
                     sum
                     (snap-sync-storage-page-result-entry-count
                      (snap-sync-global-storage-result-result entry)))
               :trie-record-count
               (loop for entry in entries
                     sum
                     (length
                      (snap-sync-storage-page-result-records
                       (snap-sync-global-storage-result-result entry))))
               :batch-operation-count operation-count
               :logical-batch-bytes logical-bytes
               :completed-task-count
               (loop for entry in entries
                     count
                     (snap-sync-storage-page-result-completed-p
                      (snap-sync-global-storage-result-result entry)))
               :request-ms
               (loop for entry in entries
                     sum
                     (snap-sync-storage-page-result-request-ms
                      (snap-sync-global-storage-result-result entry)))
               :proof-ms
               (loop for entry in entries
                     sum
                     (snap-sync-storage-page-result-proof-ms
                      (snap-sync-global-storage-result-result entry)))
               :materialize-ms
               (loop for entry in entries
                     sum
                     (snap-sync-storage-page-result-materialize-ms
                      (snap-sync-global-storage-result-result entry)))
               :batch-build-ms
               (loop for entry in entries
                     sum
                     (snap-sync-global-storage-result-batch-build-ms entry))
               :prepare-ms prepare-ms
               :commit-ms
               (snap-sync-elapsed-milliseconds
                commit-started-at (get-internal-real-time))
               :writer-idle-ms writer-idle-ms))))
    (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
      (dolist (update task-updates)
        (setf (snap-sync-global-storage-job-tasks (car update)) (cdr update))
        (when (every #'snap-sync-account-task-completed-p (cdr update))
          (setf (snap-sync-global-storage-job-completed-p (car update)) t)))
      (dolist (entry entries)
        (let ((job (snap-sync-global-storage-result-job entry))
              (task-index
                (snap-sync-global-storage-result-task-index entry))
              (source (snap-sync-global-storage-result-source entry)))
          (unless
              (eq source
                  (gethash task-index
                           (snap-sync-global-storage-job-claims job)))
            (error "Snap committed storage batch lost a partition claim"))
          (remhash task-index (snap-sync-global-storage-job-claims job))))
      (snap-sync-multi-notify runtime))
    (let ((callback
            (snap-sync-multi-runtime-storage-profile-callback runtime)))
      (when callback (funcall callback profile)))
    profile))

#+sbcl
(defun snap-sync-multi-commit-storage-page
    (runtime database state-root job task-index source result
     &optional prepared-batch replacement (batch-build-ms 0))
  "Queue and batch verified page integration like geth's sync event loop."
  (unless prepared-batch
    (let ((started-at (get-internal-real-time)))
      (multiple-value-setq (prepared-batch replacement)
        (snap-sync-build-storage-page-batch
         database state-root
         (snap-sync-global-storage-job-account-hash job)
         (snap-sync-global-storage-job-storage-root job)
         (nth task-index (snap-sync-global-storage-job-tasks job)) result))
      (setf batch-build-ms
            (snap-sync-elapsed-milliseconds
             started-at (get-internal-real-time)))))
  (snap-sync-multi-queue-storage-result
   runtime job task-index source result prepared-batch replacement
   batch-build-ms)
  ;; Any worker may become the single coordinator. The first response often
  ;; forms a one-page batch; responses verified during that write accumulate,
  ;; and the next drain folds up to sixteen cursors into one durable seam.
  (sb-thread:with-mutex
      ((snap-sync-multi-runtime-storage-write-lock runtime))
    (loop
      (let ((entries (snap-sync-multi-storage-result-batch runtime)))
        (unless entries (return))
        (handler-case
            (snap-sync-multi-commit-storage-results
             runtime database state-root entries)
          (serious-condition (condition)
            (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
              (setf (snap-sync-multi-runtime-storage-fatal-condition runtime)
                    condition)
              (snap-sync-multi-notify runtime))
            (error condition)))))))

#+sbcl
(defun snap-sync-multi-storage-commit-worker
    (runtime database state-root)
  "Drain verified pages through the one RocksDB writer.

StorageRanges workers stop at the bounded result queue and immediately return
their peers to request work. This writer preserves the existing atomic batch,
claim-release, and WAL-prefix contracts without making peer availability wait
for RocksDB compaction or a preceding batch write."
  (handler-case
      (loop with idle-started-at = (get-internal-real-time)
        for entries = (snap-sync-multi-wait-storage-result-batch runtime)
        while entries
        for dequeued-at = (get-internal-real-time)
        do (snap-sync-multi-commit-storage-results
            runtime database state-root entries
            :writer-idle-ms
            (snap-sync-elapsed-milliseconds idle-started-at dequeued-at))
           (setf idle-started-at (get-internal-real-time)))
    (serious-condition (condition)
      (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
        (setf (snap-sync-multi-runtime-storage-fatal-condition runtime)
              condition)
        (snap-sync-multi-notify runtime)))))

#+sbcl
(defun snap-sync-multi-storage-worker
    (runtime database source state-root byte-limit)
  "Drain all large storage roots through SOURCE's one import-wide lane."
  (unwind-protect
       (handler-case
           (loop
             (multiple-value-bind (job task-index task)
                 (snap-sync-multi-claim-storage-page runtime source)
               (unless job (return))
               (handler-case
                   (let* ((result
                            (snap-sync-prepare-storage-page
                             source state-root
                             (snap-sync-global-storage-job-account-hash job)
                             (snap-sync-global-storage-job-storage-root job)
                             task-index task byte-limit))
                          (batch-started-at (get-internal-real-time)))
                     ;; Build the page-owned operation list on this source
                     ;; lane. The central writer later validates and moves it
                     ;; into a combined batch without copying hundreds of
                     ;; thousands of key/value operations serially.
                     (multiple-value-bind (prepared-batch replacement)
                         (snap-sync-build-storage-page-batch
                          database state-root
                          (snap-sync-global-storage-job-account-hash job)
                          (snap-sync-global-storage-job-storage-root job)
                          task result)
                       (let ((batch-build-ms
                               (snap-sync-elapsed-milliseconds
                                batch-started-at
                                (get-internal-real-time))))
                         ;; Fetch/proof failures belong to the answering source.
                         ;; Once verification has succeeded, every failure below
                         ;; is local scheduler or persistence state and must never
                         ;; be converted into peer exhaustion.
                         (handler-case
                             (if
                                 (sb-thread:with-mutex
                                     ((snap-sync-multi-runtime-lock runtime))
                                   (snap-sync-multi-runtime-storage-committer-active-p
                                    runtime))
                                 (unless
                                     (snap-sync-multi-queue-storage-result
                                      runtime job task-index source result
                                      prepared-batch replacement batch-build-ms)
                                   (return))
                                 ;; Isolated scheduler tests and embedders that do
                                 ;; not start the production committer retain the
                                 ;; synchronous one-writer contract.
                                 (snap-sync-multi-commit-storage-page
                                  runtime database state-root job task-index
                                  source result prepared-batch replacement
                                  batch-build-ms))
                           (serious-condition (condition)
                             (snap-sync-multi-fail-storage-claim
                              runtime job task-index source condition t)
                             (return))))))
                 (snap-sync-heal-yielded (condition)
                   ;; The pooled transport proved that this CL-authorized
                   ;; pivot has aged out while a large root was in flight.
                   ;; Stop the complete generation without blaming the peer;
                   ;; the coordinator will re-signal this scheduling result.
                   (snap-sync-multi-release-storage-claim
                    runtime job task-index source)
                   (snap-sync-multi-push-yield
                    runtime
                    (make-snap-sync-multi-event
                     :kind :yield :source source :task-index task-index
                     :condition condition))
                   (return))
                 (ethereum-lisp.validation:storage-error (condition)
                   (snap-sync-multi-fail-storage-claim
                    runtime job task-index source condition t)
                   (return))
                 (serious-condition (condition)
                   (snap-sync-multi-fail-storage-claim
                    runtime job task-index source condition nil)
                   ;; Match geth's peer-idle set: a failed source leaves this
                   ;; import-wide response-type pool and its exact task is free
                   ;; for a different lane.
                   (return)))))
         ;; A queue/claim bug happens outside the remote response boundary. It
         ;; is a local fatal condition even when no job claim could be released.
         (serious-condition (condition)
           (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
             (setf (snap-sync-multi-runtime-storage-fatal-condition runtime)
                   condition)
             (snap-sync-multi-notify runtime))))
    (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
      (decf (snap-sync-multi-runtime-storage-worker-count runtime))
      (when (minusp
             (snap-sync-multi-runtime-storage-worker-count runtime))
        (error "Snap global storage worker count underflow"))
      (snap-sync-multi-notify runtime))))

#+sbcl
(defun snap-sync-multi-fill-storage-root
    (runtime database state-root account-hash storage-root)
  "Queue one root and wait while fixed source lanes share all open roots."
  (let* ((job nil)
         (terminal nil))
    (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
      (when (snap-sync-multi-runtime-stopped-p runtime)
        (return-from snap-sync-multi-fill-storage-root nil))
      (setf job
            (find-if
             (lambda (candidate)
               (snap-sync-global-storage-job-matches-p
                candidate account-hash storage-root))
             (snap-sync-multi-runtime-storage-jobs runtime)))
      (if job
          (incf (snap-sync-global-storage-job-waiters job))
          (progn
            ;; Check the import-wide job identity before touching durable
            ;; cursors. Concurrent account pages can depend on the same
            ;; content-addressed root; only its first waiter may load or seed
            ;; the sixteen-record task set.
            (let ((tasks
                    (snap-sync-load-or-create-storage-tasks
                     database state-root account-hash storage-root)))
              (setf job
                    (make-snap-sync-global-storage-job
                     (copy-seq account-hash) storage-root tasks)
                    (snap-sync-global-storage-job-completed-p job)
                    (every #'snap-sync-account-task-completed-p tasks)
                    (snap-sync-multi-runtime-storage-jobs runtime)
                    (nconc
                     (snap-sync-multi-runtime-storage-jobs runtime)
                     (list job)))
              (snap-sync-multi-notify runtime)))))
    (unwind-protect
         (setf terminal
               (sb-thread:with-mutex
                   ((snap-sync-multi-runtime-lock runtime))
                 (loop
                   (cond
                     ((snap-sync-global-storage-job-completed-p job)
                      (return :completed))
                     ((snap-sync-multi-runtime-stopped-p runtime)
                      (return :stopped))
                     ((snap-sync-multi-runtime-storage-fatal-condition runtime)
                      (return
                        (snap-sync-multi-runtime-storage-fatal-condition
                         runtime)))
                     ((zerop
                       (snap-sync-multi-runtime-storage-worker-count runtime))
                      (let ((failures
                              (reverse
                               (copy-list
                                (snap-sync-multi-runtime-storage-source-errors
                                 runtime)))))
                        (return
                          (if (and
                               failures
                               (every
                                (lambda (condition)
                                  (typep condition
                                         'snap-sync-state-unavailable))
                                failures))
                              (make-condition
                               'snap-sync-state-unavailable
                               :request-kind "storage-range")
                              (make-condition
                               'snap-sync-sources-exhausted
                               :phase :storage-ranges
                               :failures failures)))))
                     (t
                      (sb-thread:condition-wait
                       (snap-sync-multi-runtime-changed runtime)
                       (snap-sync-multi-runtime-lock runtime)))))))
      (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
        (decf (snap-sync-global-storage-job-waiters job))
        (when (minusp (snap-sync-global-storage-job-waiters job))
          (error "Snap global storage job waiter count underflow"))
        (when (and
               (zerop (snap-sync-global-storage-job-waiters job))
               (or
                (snap-sync-global-storage-job-completed-p job)
                (snap-sync-multi-runtime-stopped-p runtime)
                (typep terminal 'condition)))
          (setf (snap-sync-multi-runtime-storage-jobs runtime)
                (delete
                 job (snap-sync-multi-runtime-storage-jobs runtime)
                 :test #'eq)))
        (snap-sync-multi-notify runtime)))
    (when (typep terminal 'condition)
      (error terminal))
    (eq terminal :completed)))

#+sbcl
(defun snap-sync-multi-complete-deferred-storage-roots
    (runtime database state-root commitments)
  "Finish COMMITMENTS through the import-wide rotating StorageRanges queue."
  (dolist (commitment commitments commitments)
    (unless
        (snap-sync-multi-fill-storage-root
         runtime database state-root (car commitment) (cdr commitment))
      ;; NIL means the generation stopped while this page still owned an
      ;; unresolved large root. It must never be reinterpreted as an empty
      ;; deferred set: that would publish false account-subtree closure before
      ;; the cursor seam. The typed cancellation is idempotent when another
      ;; storage lane already queued the stale-pivot yield.
      (error 'snap-sync-heal-yielded))))

#+sbcl
(defun snap-sync-multi-worker
    (runtime database source state-root byte-limit)
  (unwind-protect
       (loop
         (multiple-value-bind (task-index task)
             (snap-sync-multi-claim-task runtime source)
           (unless task (return))
           (handler-case
               (let ((work
                       (snap-sync-prepare-account-page-range
                        database source state-root task-index task byte-limit)))
                 (snap-sync-multi-push-dependency
                  runtime
                  (make-snap-sync-multi-event
                   :kind :dependency :source source :task-index task-index
                   :result work)))
             (snap-sync-request-timeout (condition)
               (declare (ignore condition))
               ;; A timed-out request does not prove the RLPx session or peer
               ;; unusable. The transport has already reset this message
               ;; type's capacity and assigned a unique id, so release the
               ;; immutable range and let this same worker retry normally.
               (snap-sync-multi-release-claim runtime task-index source))
             (serious-condition (condition)
               (let ((report-p
                       (snap-sync-multi-mark-source-failed runtime source)))
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
(defun snap-sync-multi-release-code-flight
    (runtime owner hashes)
  "Release OWNER's HASHES and wake pages that can now recheck durable code."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (snap-sync-multi-release-code-flight-locked runtime owner hashes)
    (snap-sync-multi-notify runtime)))

#+sbcl
(defun snap-sync-multi-release-code-flight-locked
    (runtime owner hashes)
  "Release OWNER's HASHES while RUNTIME's lock is already held."
    (dolist (hash hashes)
      ;; A completed batch is published before this release. The owner token
      ;; prevents a late cleanup from removing a flight that another page took
      ;; over after an earlier failure.
      (when (eq owner
                (gethash hash
                         (snap-sync-multi-runtime-code-inflight runtime)))
        (remhash hash (snap-sync-multi-runtime-code-inflight runtime)))))

#+sbcl
(defun snap-sync-multi-claim-code-job (runtime)
  "Claim one globally bounded ByteCodes job, or stop with RUNTIME."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (loop
      (when (snap-sync-multi-runtime-stopped-p runtime)
        (return nil))
      (when (snap-sync-multi-runtime-code-jobs runtime)
        (return (pop (snap-sync-multi-runtime-code-jobs runtime))))
      (sb-thread:condition-wait
       (snap-sync-multi-runtime-changed runtime)
       (snap-sync-multi-runtime-lock runtime)))))

#+sbcl
(defun snap-sync-multi-finish-code-job
    (runtime job &optional condition)
  "Publish JOB completion, releasing its hash flights before waking waiters."
  (let ((task (snap-sync-code-job-task job)))
    (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
      (when (and condition (null (snap-sync-code-task-condition task)))
        (setf (snap-sync-code-task-condition task) condition))
      (snap-sync-multi-release-code-flight-locked
       runtime (snap-sync-code-task-owner task)
       (snap-sync-code-job-hashes job))
      (decf (snap-sync-code-task-pending task))
      (when (minusp (snap-sync-code-task-pending task))
        (error "Snap global ByteCodes task underflow"))
      (snap-sync-multi-notify runtime))))

#+sbcl
(defun snap-sync-multi-code-worker (runtime database)
  "Drain the import-wide ByteCodes queue with one request at a time."
  (loop
    (let ((job (snap-sync-multi-claim-code-job runtime)))
      (unless job (return))
      (let ((task (snap-sync-code-job-task job)))
        (handler-case
            (if (sb-thread:with-mutex
                    ((snap-sync-multi-runtime-lock runtime))
                  (not (null (snap-sync-code-task-condition task))))
                (snap-sync-multi-finish-code-job runtime job)
                (let ((codes
                        (snap-sync-fetch-code-hash-batch
                         (snap-sync-code-task-source task)
                         (snap-sync-code-job-hashes job)
                         (snap-sync-code-task-byte-limit task))))
                  (when codes
                    (let ((batch (make-kv-write-batch)))
                      (snap-sync-populate-code-batch database batch codes)
                      ;; RocksDB already serializes writers internally. Keep an
                      ;; explicit publication seam too so the atomic memory
                      ;; backend used as the crash oracle cannot lose a sibling
                      ;; worker's batch while copying its shadow table.
                      (sb-thread:with-mutex
                          ((snap-sync-multi-runtime-code-write-lock runtime))
                        (kv-apply-batch-buffered database batch))))
                  (snap-sync-multi-finish-code-job runtime job)))
          (serious-condition (condition)
            (snap-sync-multi-finish-code-job runtime job condition)))))))

#+sbcl
(defun snap-sync-multi-schedule-code-batches
    (runtime source owner hashes byte-limit)
  "Queue OWNER's hashes once and wait for the fixed global workers."
  (let* ((batches (snap-sync-code-hash-batches hashes))
         (task
           (make-snap-sync-code-task
            owner source byte-limit (length batches))))
    (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
      (dolist (batch batches)
        (setf (snap-sync-multi-runtime-code-jobs runtime)
              (nconc
               (snap-sync-multi-runtime-code-jobs runtime)
               (list (make-snap-sync-code-job task batch)))))
      (snap-sync-multi-notify runtime)
      (loop while (and (plusp (snap-sync-code-task-pending task))
                       (not (snap-sync-multi-runtime-stopped-p runtime)))
            do (sb-thread:condition-wait
                (snap-sync-multi-runtime-changed runtime)
                (snap-sync-multi-runtime-lock runtime))))
    (when (snap-sync-code-task-condition task)
      (error (snap-sync-code-task-condition task)))
    owner))

#+sbcl
(defun snap-sync-multi-buffer-code-batches
    (runtime database source owner hashes byte-limit)
  "Fetch and publish OWNER's HASHES one geth-sized batch at a time.

Each verified response becomes visible before its flight is released. This
matches geth's response integration and prevents an unrelated slow tail batch
from holding every page that shares an already delivered contract code."
  (let* ((batches (snap-sync-code-hash-batches hashes))
         (count (length batches))
         (worker-count (min count +snap-sync-code-batch-workers+))
         (threads (make-array (1- worker-count) :initial-element nil))
         (next-index 0)
         (condition nil)
         (lock (sb-thread:make-mutex :name "snap-sync-multi-code-batches")))
    (labels ((claim ()
               (sb-thread:with-mutex (lock)
                 (if (or condition (>= next-index count))
                     (values nil nil)
                     (let ((index next-index))
                       (incf next-index)
                       (values index t)))))
             (fetch-and-publish (batch)
               (unwind-protect
                    (let ((codes
                            (snap-sync-fetch-code-hash-batch
                             source batch byte-limit)))
                      (when codes
                        (let ((write-batch (make-kv-write-batch)))
                          (snap-sync-populate-code-batch
                           database write-batch codes)
                          (kv-apply-batch-buffered database write-batch))))
                 (snap-sync-multi-release-code-flight
                  runtime owner batch)))
             (worker ()
               (loop
                 (multiple-value-bind (index present-p) (claim)
                   (unless present-p (return))
                   (handler-case
                       (fetch-and-publish (nth index batches))
                     (serious-condition (error)
                       (sb-thread:with-mutex (lock)
                         (unless condition (setf condition error)))
                       (return)))))))
      (unwind-protect
           (progn
             (dotimes (index (length threads))
               (setf
                (aref threads index)
                (sb-thread:make-thread
                 #'worker :name "snap-sync-multi-code-batch-worker")))
             (worker)
             (loop for index below (length threads)
                   for thread = (aref threads index)
                   do (sb-thread:join-thread thread)
                      (setf (aref threads index) nil)))
        (loop for thread across threads
              when thread
                do (ignore-errors (sb-thread:join-thread thread)))
        ;; This is idempotent for completed batches and releases unclaimed
        ;; batches after either a request or thread-creation failure.
        (snap-sync-multi-release-code-flight runtime owner hashes)))
    (when condition (error condition))
    '()))

#+sbcl
(defun snap-sync-multi-fetch-page-codes
    (runtime database source code-hashes byte-limit)
  "Fetch each missing CODE-HASH once across every pending account page.

Each geth-sized response is hash-verified and buffered before its individual
flights are published complete. A later synchronous account cursor therefore
flushes that earlier WAL prefix before it can make a dependent page durable.
Waiters recheck RocksDB after each wake and take over hashes whose owner failed."
  (loop
    (let ((missing
            (snap-sync-heal-missing-code-hashes database code-hashes)))
      (unless missing (return '()))
      (let ((owned '())
            (owner (list :snap-code-flight-owner)))
        (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
          (when (snap-sync-multi-runtime-stopped-p runtime)
            (return-from snap-sync-multi-fetch-page-codes '()))
          (dolist (hash missing)
            (unless (gethash hash
                             (snap-sync-multi-runtime-code-inflight runtime))
              (setf (gethash
                     hash (snap-sync-multi-runtime-code-inflight runtime))
                    owner)
              (push hash owned)))
          (unless owned
            (sb-thread:condition-wait
             (snap-sync-multi-runtime-changed runtime)
             (snap-sync-multi-runtime-lock runtime))))
        (when owned
          (setf owned (nreverse owned))
          (if (plusp (snap-sync-multi-runtime-code-worker-count runtime))
              (snap-sync-multi-schedule-code-batches
               runtime source owner owned byte-limit)
              ;; Isolated callers and the portable test harness have no import
              ;; worker lifetime. Retain the old bounded helper only there;
              ;; production always enters the fixed global queue above.
              (snap-sync-multi-buffer-code-batches
               runtime database source owner owned byte-limit)))))))

#+sbcl
(defun snap-sync-multi-dependency-worker
    (runtime database state-root byte-limit)
  "Complete globally queued storage/code work without occupying range peers.

Like geth's account-task PEND counter, this worker withholds the account result
until every byte-capped storage subtask has published its durable cursor and
range-derived subtree proofs."
  (loop
    (let ((job (snap-sync-multi-claim-dependency runtime)))
      (unless job (return))
      (let ((source (snap-sync-multi-event-source job))
            (task-index (snap-sync-multi-event-task-index job))
            (work (snap-sync-multi-event-result job)))
        (handler-case
            (snap-sync-multi-push-event
             runtime
             (make-snap-sync-multi-event
              :kind :result :source source :task-index task-index
              :result
              (snap-sync-complete-account-page
               database source state-root work byte-limit
               :code-fetch-function
               (lambda ()
                 (snap-sync-multi-fetch-page-codes
                  runtime database source
                  (snap-sync-account-page-work-code-hashes work)
                  byte-limit))
               :deferred-storage-function
               (lambda (commitments)
                 ;; Every source owns one fixed StorageRanges lane. The global
                 ;; rotating queue gives all sixteen chunks of an open root
                 ;; priority while still allowing other account tasks to use
                 ;; otherwise idle peers, matching geth's assignment loop.
                 (snap-sync-multi-complete-deferred-storage-roots
                  runtime database state-root commitments)))))
          (snap-sync-heal-yielded (condition)
            ;; Pivot movement is a coordinator scheduling result. Do not mark
            ;; the account-page source failed merely because one of its pooled
            ;; dependency transports proved that the old root was pruned.
            (snap-sync-multi-push-yield
             runtime
             (make-snap-sync-multi-event
              :kind :yield :source source :task-index task-index
              :condition condition)))
          (serious-condition (condition)
            (snap-sync-multi-push-event
             runtime
             (make-snap-sync-multi-event
              :kind :error :source source :task-index task-index
              :condition condition
              :report-p
              (snap-sync-multi-mark-source-failed runtime source)))))))))

#+sbcl
(defun snap-sync-multi-next-event (runtime &optional refresh-timeout-seconds)
  "Return the next coordinator event, or :REFRESH after a bounded idle wait."
  (let ((refresh-deadline
          (and refresh-timeout-seconds
               (+ (get-internal-real-time)
                  (ceiling
                   (* refresh-timeout-seconds
                      internal-time-units-per-second))))))
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
        (when (and
               (zerop (snap-sync-multi-runtime-source-count runtime))
               (zerop
                (hash-table-count (snap-sync-multi-runtime-claims runtime))))
          (return :exhausted))
        (if refresh-deadline
            (let ((remaining-ticks
                    (- refresh-deadline (get-internal-real-time))))
              ;; Storage commits and worker claims broadcast CHANGED as well.
              ;; Preserve one absolute deadline across those ordinary wakes;
              ;; restarting a relative timeout here can starve live-peer
              ;; refresh forever under a continuously productive dependency.
              (when (not (plusp remaining-ticks))
                (return :refresh))
              (unless
                  (sb-thread:condition-wait
                   (snap-sync-multi-runtime-changed runtime)
                   (snap-sync-multi-runtime-lock runtime)
                   :timeout
                   (/ remaining-ticks
                      (float internal-time-units-per-second 1d0)))
                (return :refresh)))
            (sb-thread:condition-wait
             (snap-sync-multi-runtime-changed runtime)
             (snap-sync-multi-runtime-lock runtime)))))))

#+sbcl
(defun snap-sync-multi-result-event-batch (runtime first)
  "Take FIRST plus the currently queued contiguous result prefix."
  (let ((events (list first)))
    (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
      (loop while
              (and
               (< (length events) +snap-sync-cursor-batch-pages+)
               (let ((next (first (snap-sync-multi-runtime-events runtime))))
                 (and next
                      (eq :result (snap-sync-multi-event-kind next)))))
            do (setf events
                     (nconc
                      events
                      (list (pop (snap-sync-multi-runtime-events runtime)))))))
    events))

#+sbcl
(defun snap-sync-multi-release-claim (runtime task-index source)
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (when (eq source
              (gethash task-index (snap-sync-multi-runtime-claims runtime)))
      (remhash task-index (snap-sync-multi-runtime-claims runtime)))
    (snap-sync-multi-notify runtime)))

#+sbcl
(defun snap-sync-multi-range-gc-due-p (runtime)
  "Advance an enabled in-phase GC watermark and report whether to collect."
  (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
    (when (and
           (integerp *snap-sync-range-full-gc-pages*)
           (plusp *snap-sync-range-full-gc-pages*)
           (>= (- (snap-sync-multi-runtime-pages runtime)
                  (snap-sync-multi-runtime-last-full-gc-pages runtime))
               *snap-sync-range-full-gc-pages*))
      (setf (snap-sync-multi-runtime-last-full-gc-pages runtime)
            (snap-sync-multi-runtime-pages runtime))
      t)))

#+sbcl
(defun snap-sync-import-state-multi
    (database sources
     &key pivot-hash pivot-number state-root chain-id genesis-hash authority-id
          target-hash (byte-limit +snap-sync-request-bytes+)
          on-progress on-page-profile on-storage-profile on-source-error
          on-heal-progress
          heal-source-provider range-yield-p heal-yield-p max-pages)
  "Import one pivot through disjoint durable ranges shared across SOURCES.

Sixty-four logical account tasks feed independent geth-style account and
dependency schedulers. One range worker per source keeps its AccountRange slot
busy, then hands the verified page to a bounded global storage/code pool instead
of occupying the range peer until those dependencies finish. Each session
remains the sole RLPx writer while one request per snap response type may be in
flight, matching replies by both type and request id. The caller thread
serializes only the account progress batch and its callbacks. ON-PROGRESS
receives PROGRESS, SOURCE, and TASK-INDEX
after that task page is durable. ON-PAGE-PROFILE then receives its observational
timing profile, SOURCE, and TASK-INDEX. The single storage commit coordinator
invokes ON-STORAGE-PROFILE with one aggregate profile after each buffered
large-storage page batch. ON-SOURCE-ERROR
receives SOURCE and the condition after its task has been made retryable.
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
  (when (and on-storage-profile (not (functionp on-storage-profile)))
    (error "Multi-source snap storage profile callback must be a function"))
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
         (dependency-threads '())
         (code-threads '())
         (storage-threads '())
         (storage-commit-thread nil)
         (range-yielded-p nil)
         (errors '()))
    (setf (snap-sync-multi-runtime-storage-profile-callback runtime)
          on-storage-profile)
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
        ((start-code-workers ()
           (setf (snap-sync-multi-runtime-code-worker-count runtime)
                 +snap-sync-global-code-workers+)
           (dotimes (index +snap-sync-global-code-workers+)
             (declare (ignore index))
             (push
              (sb-thread:make-thread
               (lambda ()
                 (snap-sync-multi-code-worker runtime database))
               :name "snap-sync-global-bytecode-worker")
              code-threads)))
         (start-dependency-workers ()
           (dotimes (index +snap-sync-dependency-workers+)
             (declare (ignore index))
             (push
              (sb-thread:make-thread
               (lambda ()
                 (snap-sync-multi-dependency-worker
                  runtime database state-root byte-limit))
               :name "snap-sync-dependency-worker")
              dependency-threads)))
         (start-storage-committer ()
           (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
             (setf
              (snap-sync-multi-runtime-storage-committer-active-p runtime) t)
             (snap-sync-multi-notify runtime))
           (setf
            storage-commit-thread
            (sb-thread:make-thread
             (lambda ()
               (snap-sync-multi-storage-commit-worker
                runtime database state-root))
             :name "snap-sync-global-storage-committer")))
         (start-storage-worker (source)
           (let ((start-p nil))
             (sb-thread:with-mutex
                 ((snap-sync-multi-runtime-lock runtime))
               (unless
                   (member
                    source
                    (snap-sync-multi-runtime-storage-sources runtime)
                    :test #'eq)
                 (setf
                  (snap-sync-multi-runtime-storage-sources runtime)
                  (nconc
                   (snap-sync-multi-runtime-storage-sources runtime)
                   (list source))
                  start-p t)
                 (incf
                  (snap-sync-multi-runtime-storage-worker-count runtime))
                 (snap-sync-multi-notify runtime)))
             (when start-p
               (handler-case
                   (let ((worker-source source))
                     (push
                      (sb-thread:make-thread
                       (lambda ()
                         (snap-sync-multi-storage-worker
                          runtime database worker-source state-root
                          (min byte-limit
                               +snap-sync-storage-request-bytes+)))
                       :name "snap-sync-global-storage-worker")
                      storage-threads))
                 (serious-condition (condition)
                   (sb-thread:with-mutex
                       ((snap-sync-multi-runtime-lock runtime))
                     (decf
                      (snap-sync-multi-runtime-storage-worker-count runtime))
                     (setf (snap-sync-multi-runtime-storage-sources runtime)
                           (delete
                            source
                            (snap-sync-multi-runtime-storage-sources runtime)
                            :test #'eq))
                     (snap-sync-multi-notify runtime))
                   (error condition))))))
         (start-worker (source)
           (start-storage-worker source)
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
             (start-code-workers)
             (start-dependency-workers)
             (start-storage-committer)
             (dolist (source sources)
               (start-source-workers source))
             (refresh-range-sources)
           (loop
             (let ((event
                     (snap-sync-multi-next-event
                      runtime
                      (and heal-source-provider
                           *snap-sync-range-source-refresh-seconds*))))
               (case event
                 (:refresh
                  ;; Account cursor publication is intentionally delayed by
                  ;; unfinished storage dependencies.  Admit peers on this
                  ;; independent wake too, so one large root cannot freeze the
                  ;; initial range/storage dispatcher width for its lifetime.
                  (refresh-range-sources))
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
                      (:yield
                       (error (snap-sync-multi-event-condition event)))
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
                           (let* ((result-events
                                    (snap-sync-multi-result-event-batch
                                     runtime event))
                                  (results
                                    (mapcar
                                     #'snap-sync-multi-event-result
                                     result-events)))
                             (multiple-value-bind (next snapshots)
                                 (snap-sync-commit-account-pages
                                  database
                                  (snap-sync-multi-runtime-progress runtime)
                                  results)
                             (sb-thread:with-mutex
                                 ((snap-sync-multi-runtime-lock runtime))
                               (setf (snap-sync-multi-runtime-progress runtime)
                                     next)
                               (incf
                                (snap-sync-multi-runtime-pages runtime)
                                (length result-events))
                               (dolist (result-event result-events)
                                 (remhash
                                  (snap-sync-multi-event-task-index result-event)
                                  (snap-sync-multi-runtime-claims runtime)))
                               (snap-sync-multi-notify runtime))
                             (loop for result-event in result-events
                                   for result in results
                                   for snapshot in snapshots
                                   do
                                   (when on-progress
                                     (funcall
                                      on-progress snapshot
                                      (snap-sync-multi-event-source result-event)
                                      (snap-sync-multi-event-task-index
                                       result-event)))
                                   (when on-page-profile
                                     (funcall
                                      on-page-profile
                                      (snap-sync-page-result-profile result)
                                      (snap-sync-multi-event-source result-event)
                                      (snap-sync-multi-event-task-index
                                       result-event))))
                             ;; Keep an opt-in emergency watermark behind one
                             ;; exact configuration seam. Production leaves it
                             ;; disabled: Hoodi proved the stop-the-world pause
                             ;; can make the colocated CL miss Engine upchecks.
                             (when (snap-sync-multi-range-gc-due-p runtime)
                               (snap-sync-release-range-phase-memory))
                             ;; Match geth's moving-pivot behavior at a durable
                             ;; cursor batch boundary. Other workers may still
                             ;; own bounded in-flight pages; unwind stops them
                             ;; and their uncommitted results remain retryable.
                             (when (and
                                    range-yield-p
                                    (loop repeat (length result-events)
                                          thereis (funcall range-yield-p)))
                               (setf range-yielded-p t)
                               (error 'snap-sync-heal-yielded))
                             (refresh-range-sources)))
                         (serious-condition (condition)
                           ;; A database or merge failure is local and fatal;
                           ;; it must never be misclassified as a bad peer.
                           (error condition)))))))))))
        (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
          (setf (snap-sync-multi-runtime-stopped-p runtime) t)
          (snap-sync-multi-notify runtime))
        (dolist (thread threads)
          (sb-thread:join-thread thread))
        (dolist (thread dependency-threads)
          (sb-thread:join-thread thread))
        (dolist (thread code-threads)
          (sb-thread:join-thread thread))
        (dolist (thread storage-threads)
          (sb-thread:join-thread thread))
        (when storage-commit-thread
          (sb-thread:join-thread storage-commit-thread)
          (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
            (setf
             (snap-sync-multi-runtime-storage-committer-active-p runtime) nil)
            (snap-sync-multi-notify runtime)))
        ;; A moving-pivot yield is a safe phase boundary: every committed page
        ;; is durable and every worker has joined. Discard any uncommitted page
        ;; graphs left in the stopped scheduler before collecting, otherwise
        ;; successive 12-minute Hoodi pivot windows retain enough old-generation
        ;; data to exhaust a shared 16-GiB EL/CL host before the final healer.
        (when range-yielded-p
          (sb-thread:with-mutex ((snap-sync-multi-runtime-lock runtime))
            (setf (snap-sync-multi-runtime-events runtime) nil
                  (snap-sync-multi-runtime-dependency-jobs runtime) nil
                  (snap-sync-multi-runtime-code-jobs runtime) nil
                  (snap-sync-multi-runtime-storage-jobs runtime) nil
                  (snap-sync-multi-runtime-storage-results runtime) nil)
            (clrhash (snap-sync-multi-runtime-claims runtime))
            (clrhash (snap-sync-multi-runtime-code-inflight runtime)))
          (setf threads nil
                dependency-threads nil
                code-threads nil
                storage-threads nil
                storage-commit-thread nil)
          (snap-sync-release-range-phase-memory))))))

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
