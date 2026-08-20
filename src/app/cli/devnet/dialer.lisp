(in-package #:ethereum-lisp.cli)

;;;; Dialing peers, and keeping them.
;;;;
;;;; The outbound counterpart of peer-manager.lisp, and the other of the two
;;;; files where threads live. A dialed connection becomes a long-lived session
;;;; on exactly the same pump an accepted one gets, so keepalives, idle timeouts
;;;; and continuous gossip draining now work in both directions.
;;;;
;;;; TWO LOCKING RULES, and breaking either produces a hang with no diagnostic:
;;;;
;;;; 1. Never hold the peer-table guard across socket I/O. A session's download
;;;;    callback and its serve backend both take the STORE guard, and the
;;;;    rejournal and dev-period workers join unbounded on that guard during
;;;;    shutdown. Holding both in the wrong order deadlocks the shutdown itself.
;;;; 2. Never take the store guard while holding the peer-table guard. No path
;;;;    in the tree does today, and this file must not be the one that starts.

(defconstant +devnet-dial-tick-seconds+ 1
  "How long the scheduler waits between passes. Our policy: also the upper bound
on how long it takes to notice a shutdown request.")

(defconstant +devnet-sync-coordinator-poll-seconds+ 1d0
  "Periodic sync fallback when no peer announcement arrives. Our policy.")

(defconstant +devnet-session-stream-timeout-seconds+ 30
  "How long a single read or write on a peer session may stall before the
session ends. Our policy. It can only fire PART WAY THROUGH a frame, since the
pump's readiness gate sits outside the frame read, and at that point ending the
connection is the only safe answer -- a half-read frame leaves the cipher and
MAC out of step permanently. Comfortably above the worst legitimate gap: a
single response is bounded by the 2 MiB soft serve limit.")

(defun devnet-dial-outbound-admit-function (node candidate host port node-id
                                            status chain-context)
  "The admission half of an OUTBOUND session: run the initiator handshake on an
already-connected socket, then take the peer and dial slots in one step.

No identity check is needed afterwards. The RLPx initiator handshake fixes the
remote key to the one we dialed, and a host holding a different key cannot
produce frames that authenticate."
  (lambda (socket)
    (let* ((table (devnet-node-peer-table node))
           (registry (devnet-node-dial-registry node))
           (id-hex (devnet-dial-candidate-id-hex candidate))
           (peer (eth-sync-connect-peer
                  host port node-id (devnet-node-node-key node) status
                  :socket socket
                  :stream-timeout-seconds +devnet-session-stream-timeout-seconds+
                  :chain-context chain-context
                  :serve-backend (devnet-peer-serve-backend node)
                  :snap-backend (devnet-peer-snap-backend node)
                  ;; Tell the peer where to reach us. Dialing while advertising
                  ;; port 0 says "do not dial me back" even when we are listening.
                  :listen-port (or (devnet-node-p2p-port node) 0)))
           (request-queue (make-devnet-peer-request-queue))
           (entry nil))
      ;; ONE acquisition covering the verdict and both mutations: the mutex is
      ;; not recursive, so this cannot be split into two.
      (let ((verdict
              (call-with-devnet-peer-table
               node
               (lambda ()
                 (let ((verdict (devnet-peer-table-inbound-verdict table id-hex)))
                   (when (eq verdict :accept)
                     (setf entry
                           (devnet-peer-table-admit
                            table
                            (make-devnet-peer-entry
                             :id-hex id-hex
                             :direction :outbound
                             :remote-host host
                             :remote-port port
                             :socket socket
                             :thread sb-thread:*current-thread*
                             :eth-version (eth-peer-eth-version peer)
                             :client-id (eth-peer-remote-client-id peer)
                             :peer peer
                             :request-queue request-queue)
                            (unix-time)))
                     (if entry
                         (devnet-dial-registry-mark-connected registry id-hex
                                                              (unix-time))
                         (setf verdict :already-connected)))
                   verdict)))))
        (if (eq verdict :accept)
            (progn
              (devnet-peer-manager-log node "peer.dial.connected"
                                       "id" id-hex "host" host
                                       "eth" (eth-peer-eth-version peer)
                                       "snap"
                                       (or (ethereum-lisp.eth-sync:eth-peer-snap-version
                                            peer)
                                           0))
              (values peer entry nil))
            (progn
              (devnet-peer-request-queue-close request-queue)
              (devnet-peer-manager-log node "peer.dial.refused"
                                       "id" id-hex "reason" verdict)
              (values peer nil verdict)))))))

(defun devnet-node-sync-targets (node)
  "The buffered blocks whose ancestors we are missing, oldest first.

A consensus client handing us a block we cannot execute is what creates one of
these: the block is kept and the client is told SYNCING, and its PARENT is the
hash we have to reach. Sorting by number means the shallowest gap is filled
first, so a long backfill does not starve a short one."
  (let ((store (devnet-node-store node)))
    (sort (call-with-devnet-node-store-guard
           node
           (lambda ()
             (engine-payload-store-remote-block-list store)))
          #'<
          :key (lambda (block) (block-header-number (block-header block))))))

(defun devnet-node-forkchoice-sync-targets (node)
  "Unknown forkchoice heads to fetch directly, in stable hash order."
  (sort
   (call-with-devnet-node-store-guard
    node
    (lambda ()
      (engine-payload-store-forkchoice-sync-targets
       (devnet-node-store node))))
   #'string<
   :key #'hash32-to-hex))

(defconstant +devnet-snap-pivot-distance+ 64
  "How many blocks after a snap pivot are executed normally before the target.")

(defconstant +devnet-snap-heal-progress-log-interval-seconds+ 30
  "Minimum interval between non-terminal TrieNodes healing progress events.")

(defconstant +devnet-snap-heal-target-check-interval-seconds+ 30
  "Minimum interval between CL-target staleness checks during one heal.")

(defun devnet-snap-heal-progress-log-due-p (last-log-at now completed-p)
  "Whether one cumulative healing snapshot should reach operator telemetry."
  (or completed-p
      (null last-log-at)
      (< now last-log-at)
      (>= (- now last-log-at)
          +devnet-snap-heal-progress-log-interval-seconds+)))

(defconstant +devnet-snap-stale-target-distance+
  (- (* 2 +devnet-snap-pivot-distance+) 8)
  "How far a newer CL target may advance before an unfinished pivot is moved.

This is the same 2*64-8 stale-pivot window used by the pinned geth reference.
It prevents slot-by-slot restarts while still escaping a state root that every
live peer has pruned.")

(defun devnet-node-stale-snap-successor
    (node target-hash target-number)
  "Return the newer CL-authorized target hash and number when TARGET is stale.

Peer-advertised heads are deliberately excluded. Forkchoice has one current
sync target; the Engine store retains its known header even while state is
unavailable. The same 2*64-8 distance as DEVNET-NODE-ACTIVE-SNAP-TARGET avoids
slot-by-slot healer churn."
  (let ((latest-target (first (devnet-node-forkchoice-sync-targets node))))
    (when (and latest-target (not (hash32= latest-target target-hash)))
      (let ((latest-block
              (call-with-devnet-node-store-guard
               node
               (lambda ()
                 (let ((store (devnet-node-store node)))
                   (or (chain-store-known-block store latest-target)
                       (engine-payload-store-remote-block
                        store latest-target)))))))
        (when latest-block
          (let ((latest-number
                  (block-header-number (block-header latest-block))))
            (when (> latest-number
                     (+ target-number +devnet-snap-stale-target-distance+))
              (values latest-target latest-number))))))))

(defun devnet-node-active-snap-target (node latest-target)
  "Keep an unfinished durable Snap session pinned across advancing FCU heads.

LATEST-TARGET is the current in-memory Engine forkchoice target, when one is
available.  Only a durable state-progress record pins an earlier CL-authorized
target.  A skeleton alone is cheap to replace and may name a pivot that all
live peers have already pruned; pinning it forever would prevent public sync
from following newer Engine targets.  Once account-range work has committed,
the matching skeleton and state progress remain pinned until the target is
executable, so normal slot-by-slot FCU updates cannot discard expensive state
work.  If a known newer CL target advances beyond the stale-pivot window, it
may supersede a session that has no resumable healer frontier, just as geth
moves an uncommitted stale pivot.  A bounded, identity-matched heal checkpoint
pins the old target for the first actual Snap attempt after restart; discarding
it immediately would turn a deploy into a full root rescan, while retaining it
after that finite source generation fails would prevent the stale-pivot escape.
The skeleton, state progress, and optional checkpoint are one recovery session
and must agree."
  (let ((store (devnet-node-store node)))
    (if (not (database-engine-payload-store-p store))
        latest-target
        (call-with-devnet-node-store-guard
         node
         (lambda ()
           (let ((database
                   (database-engine-payload-store-database store)))
             (multiple-value-bind (skeleton skeleton-present-p)
               (node-store-read-snap-skeleton-progress
                database)
               (multiple-value-bind (state-progress state-present-p)
                   (ethereum-lisp.snap-sync:snap-sync-read-progress database)
                 (cond
                   ((not state-present-p)
                    latest-target)
                   ((not skeleton-present-p)
                    ;; Older revisions deleted these two records separately.
                    ;; A crash between deletes can leave only the expensive
                    ;; state cursor.  Let the coordinator rebuild the pair in
                    ;; one batch against the latest CL-authorized target.
                    latest-target)
                   ((or
                     (not
                      (hash32=
                       (node-store-snap-skeleton-progress-target-hash skeleton)
                       (ethereum-lisp.snap-sync:snap-sync-progress-target-hash
                        state-progress)))
                     (not
                      (hash32=
                       (node-store-snap-skeleton-progress-pivot-hash skeleton)
                       (ethereum-lisp.snap-sync:snap-sync-progress-pivot-hash
                        state-progress))))
                    ;; Treat an old non-atomic handoff as recoverable.  The
                    ;; session rebase below retains range cursors but publishes
                    ;; neither root until healing proves the latest pivot.
                    (or latest-target
                        (node-store-snap-skeleton-progress-target-hash
                         skeleton)))
                   (t
                    (let* ((checkpoint-present-p
                             (and
                              (devnet-node-snap-checkpoint-resume-p node)
                              (ethereum-lisp.snap-sync:snap-sync-heal-checkpoint-present-p
                               database state-progress)))
                           (target
                             (node-store-snap-skeleton-progress-target-hash
                              skeleton))
                           (latest-block
                             (and latest-target
                                  (or (chain-store-known-block
                                       store latest-target)
                                      (engine-payload-store-remote-block
                                       store latest-target))))
                           (latest-number
                             (and latest-block
                                  (block-header-number
                                   (block-header latest-block))))
                           (stale-p
                             (and (not checkpoint-present-p)
                                  latest-number
                                  (> latest-number
                                     (+
                                      (node-store-snap-skeleton-progress-target-number
                                       skeleton)
                                      +devnet-snap-stale-target-distance+)))))
                      (if (or stale-p
                              (chain-store-state-available-p store target))
                          latest-target
                          target))))))))))))

(defun devnet-peer-entry-sync-source (node entry)
  "Wrap ENTRY's writer queue as one production multi-peer source."
  (let ((peer (devnet-peer-entry-peer entry))
        (queue (devnet-peer-entry-request-queue entry))
        (id (devnet-peer-entry-id-hex entry)))
    (when (and peer queue)
      (flet ((submit (function)
               (devnet-peer-request-queue-submit queue function)))
        (make-eth-sync-peer-source
         peer
         :id id
         :head-number
         (and (>= (eth-peer-eth-version peer) +eth-protocol-version-69+)
              (ethereum-lisp.eth-wire:eth-status-latest-block
               (eth-peer-remote-status peer)))
         :fetch-headers
         (lambda (origin amount)
           (submit
            (lambda ()
              (eth-peer-get-block-headers
               peer :origin-number origin :amount amount))))
         :fetch-bodies
         (lambda (headers)
           (submit
            (lambda ()
              (eth-peer-get-block-bodies
               peer
               (mapcar (lambda (header)
                         (hash32-bytes (block-header-hash header)))
                       headers)))))
         :fetch-receipts
         (lambda (headers)
           (submit
            (lambda ()
              (eth-peer-get-receipts
               peer
               (mapcar (lambda (header)
                         (hash32-bytes (block-header-hash header)))
                       headers)))))
         :penalty
         (lambda (reason score detail)
           (devnet-peer-manager-log
            node "peer.sync.source_penalty"
            "peer" id "reason" reason "score" score "detail" detail)
           (call-with-devnet-peer-table
            node
            (lambda ()
              (devnet-peer-note-score
               (devnet-node-peer-table node) id score))))
         :cancel
         (lambda ()
           (ignore-errors
            ;; Close the owning fd-stream, not only its underlying socket.
            ;; SBCL otherwise leaves an apparently open stream whose next
            ;; LISTEN tries to use a NIL internal buffer, hiding the actual
            ;; downloader failure behind an implementation type error.
            (close
             (rlpx-connection-stream
              (eth-peer-connection peer))
             :abort t))))))))

(defun devnet-node-sync-peer-sources (node)
  "Snapshot live session-backed sources without holding the table during I/O."
  (remove
   nil
   (mapcar
    (lambda (entry) (devnet-peer-entry-sync-source node entry))
    (call-with-devnet-peer-table
     node
     (lambda ()
       (copy-list
        (devnet-peer-table-entries (devnet-node-peer-table node))))))))

(define-condition devnet-snap-target-unavailable (simple-error) ()
  (:documentation
   "The peer does not yet retain the CL-authorized target or its pivot tail.

This is a transient availability result, not evidence of a malformed peer.  A
healthy execution client can legitimately trail the consensus head while it is
importing newly authorized blocks, so retry/failover must not turn this signal
into a permanent peer ban."))

(define-condition devnet-snap-target-malformed (simple-error) ()
  (:documentation
   "The peer returned headers that contradict the requested target or ancestry."))

(defun devnet-node-live-sync-entries (node &key snap-only-p)
  (remove-if-not
   (lambda (entry)
     (and (devnet-peer-entry-peer entry)
          (devnet-peer-entry-request-queue entry)
          (or (not snap-only-p)
              (ethereum-lisp.eth-sync:eth-peer-snap-offset
               (devnet-peer-entry-peer entry)))))
   (call-with-devnet-peer-table
    node
    (lambda ()
      (copy-list
       (devnet-peer-table-entries (devnet-node-peer-table node)))))))

(defun devnet-peer-resolve-snap-target (entry target-hash)
  "Resolve TARGET-HASH and its 64-block pivot on ENTRY's session writer."
  (let* ((peer (devnet-peer-entry-peer entry))
         (queue (devnet-peer-entry-request-queue entry))
         (headers
           (devnet-peer-request-queue-submit
            queue
            (lambda ()
              (eth-peer-get-block-headers
               peer :origin-hash (hash32-bytes target-hash)
                    :amount (1+ +devnet-snap-pivot-distance+)
                    :reverse t)))))
    (unless headers
      (error 'devnet-snap-target-unavailable
             :format-control "peer does not yet have the CL target"
             :format-arguments nil))
    (unless (hash32= target-hash (block-header-hash (first headers)))
      (error 'devnet-snap-target-malformed
             :format-control "peer returned the wrong CL target header"
             :format-arguments nil))
    (unless (= (length headers)
               (min (1+ +devnet-snap-pivot-distance+)
                    (1+ (block-header-number (first headers)))))
      (error 'devnet-snap-target-unavailable
             :format-control "peer does not yet have the complete snap pivot tail"
             :format-arguments nil))
    (loop with expected-hash = target-hash
          with expected-number =
            (block-header-number (first headers))
          for header in headers
          do (unless (and (= expected-number (block-header-number header))
                          (hash32= expected-hash (block-header-hash header)))
               (error 'devnet-snap-target-malformed
                      :format-control
                      "peer returned a non-contiguous snap pivot chain"
                      :format-arguments nil))
             (setf expected-hash (block-header-parent-hash header)
                   expected-number (1- expected-number)))
    (values (first headers) (car (last headers)) (reverse headers))))

(defun devnet-node-resolve-snap-target (node target-hash)
  "Resolve a CL target through the first valid live snap peer, with failover."
  (dolist (entry (devnet-node-live-sync-entries node :snap-only-p t)
                 (eth-sync-multi-peer-fail
                  "no snap peer could resolve consensus target ~A"
                  (hash32-to-hex target-hash)))
    (handler-case
        (multiple-value-bind (target pivot tail)
            (devnet-peer-resolve-snap-target entry target-hash)
          (return (values entry target pivot tail)))
      (devnet-snap-target-unavailable (condition)
        (devnet-peer-manager-log
         node "peer.snap.target_unavailable"
         "peer" (devnet-peer-entry-id-hex entry)
         "error" condition))
      (devnet-snap-target-malformed (condition)
        (devnet-peer-manager-log
         node "peer.snap.target_failed"
         "peer" (devnet-peer-entry-id-hex entry)
         "error" condition)
        (call-with-devnet-peer-table
         node
         (lambda ()
           (devnet-peer-note-score
            (devnet-node-peer-table node)
            (devnet-peer-entry-id-hex entry) -50))))
      (serious-condition (condition)
        ;; Transport closure and request-queue cancellation are availability
        ;; failures. The session supervisor already applies its gradual
        ;; disconnect penalty; charging the resolver too would ban a healthy
        ;; peer after only two target retries.
        (devnet-peer-manager-log
         node "peer.snap.target_failed"
         "peer" (devnet-peer-entry-id-hex entry)
         "error" condition)))))

(defun devnet-peer-queued-snap-source (entry)
  "Build a snap source whose calls execute only on ENTRY's session writer."
  (let ((peer (devnet-peer-entry-peer entry))
        (queue (devnet-peer-entry-request-queue entry)))
    (flet ((request (message-id packet)
             (devnet-peer-request-queue-submit
              queue
              (lambda ()
                (ethereum-lisp.eth-sync:eth-peer-snap-request
                 peer message-id packet)))))
      (ethereum-lisp.snap-sync:make-snap-sync-source
       :account-range
       (lambda (packet)
         (request ethereum-lisp.snap:+snap-message-get-account-range+ packet))
       :storage-ranges
       (lambda (packet)
         (request ethereum-lisp.snap:+snap-message-get-storage-ranges+ packet))
       :bytecodes
       (lambda (packet)
         (request ethereum-lisp.snap:+snap-message-get-bytecodes+ packet))
       :trie-nodes
       (lambda (packet)
         (request ethereum-lisp.snap:+snap-message-get-trie-nodes+ packet))))))

(defun devnet-node-durable-snap-pivot-number (node)
  "Return the highest pivot whose range/skeleton work is already durable."
  (let ((store (devnet-node-store node)))
    (when (database-engine-payload-store-p store)
      (call-with-devnet-node-store-guard
       node
       (lambda ()
         (let ((database (database-engine-payload-store-database store))
               (numbers '()))
           (multiple-value-bind (progress present-p)
               (ethereum-lisp.snap-sync:snap-sync-read-progress database)
             (when present-p
               (push
                (ethereum-lisp.snap-sync:snap-sync-progress-pivot-number
                 progress)
                numbers)))
           (multiple-value-bind (progress present-p)
               (node-store-read-snap-skeleton-progress database)
             (when present-p
               (push
                (node-store-snap-skeleton-progress-pivot-number progress)
                numbers)))
           (and numbers (apply #'max numbers))))))))

(defun devnet-node-select-snap-pivot
    (node preferred-entry tail-headers)
  "Select a serviceable strict-ancestor pivot from a bounded Engine tail.

The conventional candidate is 64 blocks behind the CL target.  A healthy
hash-scheme peer can nevertheless prune that historical snapshot across a
restart while retaining the target and its immediate parent.  Probe the
conventional root first, then fall forward to the target's parent.  Both are
already committed by the same Engine target header; retaining one executable
tail block also keeps the target noncanonical until ordinary forkchoiceUpdated
publishes it.  State unavailability is an availability fact, never a peer
penalty."
  (unless tail-headers
    (error "Snap pivot selection requires a non-empty target tail"))
  (let* ((live (devnet-node-live-sync-entries node :snap-only-p t))
         (entries
           (if (and preferred-entry (member preferred-entry live :test #'eq))
               (cons preferred-entry
                     (remove preferred-entry live :test #'eq))
               live))
         (target-parent
           (if (cdr tail-headers)
               (nth (- (length tail-headers) 2) tail-headers)
               (first tail-headers)))
         (durable-pivot-number (devnet-node-durable-snap-pivot-number node))
         (candidates
           (remove-if
            (lambda (header)
              (and durable-pivot-number
                   (< (block-header-number header) durable-pivot-number)))
            (if (eq (first tail-headers) target-parent)
                (list target-parent)
                (list (first tail-headers) target-parent)))))
    (dolist (header candidates
             (eth-sync-multi-peer-fail
              "no snap peer could serve an authorized pivot for target ~A"
              (hash32-to-hex
               (block-header-hash (car (last tail-headers))))))
      (dolist (entry entries)
        (handler-case
            (progn
              (ethereum-lisp.snap-sync:snap-sync-probe-state-root
               (devnet-peer-queued-snap-source entry)
               (block-header-state-root header))
              (return-from devnet-node-select-snap-pivot
                (values entry header (member header tail-headers :test #'eq))))
          (ethereum-lisp.snap-sync:snap-sync-state-unavailable (condition)
            (devnet-peer-manager-log
             node "peer.snap.pivot_unavailable"
             "peer" (devnet-peer-entry-id-hex entry)
             "pivot" (block-header-number header)
             "error" condition))
          (storage-error (condition) (error condition))
          (serious-condition (condition)
            ;; A closed transport is already handled by the session
            ;; supervisor.  Do not double-charge it here; a subsequent pass
            ;; will retry with a fresh live-entry snapshot.
            (devnet-peer-manager-log
             node "peer.snap.pivot_probe_failed"
             "peer" (devnet-peer-entry-id-hex entry)
             "pivot" (block-header-number header)
             "error" condition)))))))

(defun devnet-node-snap-session-matches-p
    (progress target-hash pivot-hash target-accessor pivot-accessor)
  (and progress
       (hash32= target-hash (funcall target-accessor progress))
       (hash32= pivot-hash (funcall pivot-accessor progress))))

(defun devnet-node-rebase-stale-snap-progress
    (node database target-header pivot-header)
  "Atomically retarget stale skeleton/state metadata to one moving pivot.

Flat range cursors and content-addressed trie nodes survive the transition.
The branch-specific skeleton cursor restarts at the new pivot parent.  Healing
must prove the new state root before either record can authorize publication."
  (let* ((target-hash (block-header-hash target-header))
         (target-number (block-header-number target-header))
         (pivot-hash (block-header-hash pivot-header))
         (pivot-number (block-header-number pivot-header))
         (anchor-number (1- pivot-number))
         (anchor-hash (block-header-parent-hash pivot-header))
         (persistence (devnet-node-persistence-state node))
         (authority-id
           (devnet-persistence-state-authority-id persistence))
         (chain-id (chain-config-chain-id (devnet-node-config node)))
         (genesis-hash (block-hash (devnet-node-genesis-block node))))
    (multiple-value-bind (skeleton skeleton-present-p)
        (node-store-read-snap-skeleton-progress database)
      (multiple-value-bind (state-progress state-present-p)
          (ethereum-lisp.snap-sync:snap-sync-read-progress database)
        (let ((skeleton-matches-p
                (and skeleton-present-p
                     (devnet-node-snap-session-matches-p
                      skeleton target-hash pivot-hash
                      #'node-store-snap-skeleton-progress-target-hash
                      #'node-store-snap-skeleton-progress-pivot-hash)))
              (state-matches-p
                (and state-present-p
                     (devnet-node-snap-session-matches-p
                      state-progress target-hash pivot-hash
                      #'ethereum-lisp.snap-sync:snap-sync-progress-target-hash
                      #'ethereum-lisp.snap-sync:snap-sync-progress-pivot-hash))))
          (cond
            ((or (and (not skeleton-present-p) (not state-present-p))
                 (and skeleton-present-p skeleton-matches-p
                      (or (not state-present-p) state-matches-p)))
             (values skeleton skeleton-present-p))
            (t
             (let* ((replacement
                      (make-node-store-snap-skeleton-progress
                       :authority-id authority-id :chain-id chain-id
                       :genesis-hash genesis-hash
                       :target-number target-number :target-hash target-hash
                       :anchor-number anchor-number :anchor-hash anchor-hash
                       :pivot-number pivot-number :pivot-hash pivot-hash
                       :last-number anchor-number :last-hash anchor-hash))
                    (batch (make-kv-write-batch))
                    (old-pivot
                      (cond
                        (state-present-p
                         (ethereum-lisp.snap-sync:snap-sync-progress-pivot-number
                          state-progress))
                        (skeleton-present-p
                         (node-store-snap-skeleton-progress-pivot-number
                          skeleton)))))
               (when state-present-p
                 (ethereum-lisp.snap-sync:snap-sync-populate-rebased-progress-batch
                  batch state-progress
                  :pivot-hash pivot-hash
                  :pivot-number pivot-number
                  :state-root (block-header-state-root pivot-header)
                  :target-hash target-hash
                  :chain-id chain-id :genesis-hash genesis-hash
                  :authority-id authority-id))
               (node-store-populate-snap-skeleton-rebase-batch
                database batch replacement)
               (kv-apply-batch database batch)
               (devnet-peer-manager-log
                node "peer.snap.pivot_rebased"
                "fromPivot" old-pivot "pivot" pivot-number
                "target" target-number
                "retainedStateProgress" state-present-p)
               (values replacement t)))))))))

(defun devnet-node-snap-import-with-failover
    (node database pivot-header target-hash
     &key preferred-entry
          (target-number (block-header-number pivot-header)))
  "Resume disjoint pivot ranges concurrently across the live snap peers."
  (let* ((persistence (devnet-node-persistence-state node))
         (pivot-hash (block-header-hash pivot-header))
         (pivot-number (block-header-number pivot-header))
         (state-root (block-header-state-root pivot-header))
         (sources nil)
         (source-entries '())
         (last-heal-log-at nil)
         (last-target-check-at (unix-time)))
    (labels
        ((ordered-live-entries ()
           (let ((current
                   (devnet-node-live-sync-entries node :snap-only-p t)))
             (if (and preferred-entry
                      (member preferred-entry current :test #'eq))
                 (cons preferred-entry
                       (remove preferred-entry current :test #'eq))
                 current)))
         (refresh-sources ()
           (let ((current (ordered-live-entries))
                 (added 0))
             (dolist (entry current)
               (unless (find entry source-entries :key #'cdr :test #'eq)
                 (setf source-entries
                       (nconc
                        source-entries
                        (list
                         (cons (devnet-peer-queued-snap-source entry) entry))))
                 (incf added)))
             (when (plusp added)
               (devnet-peer-manager-log
                node "peer.snap.sources_refreshed"
                "pivot" pivot-number "added" added
                "sources" (length current)))
             (mapcar
              (lambda (entry)
                (car (find entry source-entries :key #'cdr :test #'eq)))
              current)))
         (entry-for-source (source)
           (cdr (assoc source source-entries :test #'eq)))
         (yield-for-stale-target-p ()
           (let ((now (unix-time)))
             (when (or (< now last-target-check-at)
                       (>= (- now last-target-check-at)
                           +devnet-snap-heal-target-check-interval-seconds+))
               (setf last-target-check-at now)
               (multiple-value-bind (successor successor-number)
                   (devnet-node-stale-snap-successor
                    node target-hash target-number)
                 (when successor
                   (devnet-peer-manager-log
                    node "peer.snap.target_stale"
                    "target" target-number
                    "targetHash" (hash32-to-hex target-hash)
                    "successor" successor-number
                    "successorHash" (hash32-to-hex successor))
                   t))))))
      (setf sources (refresh-sources))
      (unless sources
        (eth-sync-multi-peer-fail
         "no live snap peer can import pivot ~A" (hash32-to-hex pivot-hash)))
      (ethereum-lisp.snap-sync:snap-sync-import-state-multi
       database sources
       :pivot-hash pivot-hash :pivot-number pivot-number
       :state-root state-root :target-hash target-hash
       :chain-id (chain-config-chain-id (devnet-node-config node))
       :genesis-hash (block-hash (devnet-node-genesis-block node))
       :authority-id (devnet-persistence-state-authority-id persistence)
       :heal-source-provider #'refresh-sources
       :heal-yield-p #'yield-for-stale-target-p
       ;; The multi-source importer invokes this on the coordinator thread only
       ;; after the task's account nodes, code, complete small storage tries,
       ;; and cursor are durable. Byte-capped storage is mandatory work for the
       ;; final content-addressed healing traversal. The task index is an exact
       ;; concurrency/restart witness; NEXT-ORIGIN remains the lowest unfinished
       ;; global cursor.
       :on-progress
       (lambda (progress source task-index)
         (let* ((entry (entry-for-source source))
                (next
                  (ethereum-lisp.snap-sync:snap-sync-progress-next-origin
                   progress))
                (task
                  (nth task-index
                       (ethereum-lisp.snap-sync:snap-sync-progress-tasks
                        progress))))
           (devnet-peer-manager-log
            node "peer.snap.progress"
            "peer" (devnet-peer-entry-id-hex entry)
            "pivot" pivot-number
            "task" task-index
            "taskOrigin"
            (and task
                 (ethereum-lisp.snap-sync:snap-sync-account-task-next-origin
                  task)
                 (bytes-to-hex
                  (ethereum-lisp.snap-sync:snap-sync-account-task-next-origin
                   task)))
            "nextOrigin" (and next (bytes-to-hex next))
            "completed"
            (ethereum-lisp.snap-sync:snap-sync-progress-completed-p progress))))
       :on-heal-progress
       (lambda (heal-progress)
         (let* ((now (unix-time))
                (completed-p
                  (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
                   heal-progress)))
           (when (devnet-snap-heal-progress-log-due-p
                  last-heal-log-at now completed-p)
             (setf last-heal-log-at now)
             (devnet-peer-manager-log
              node "peer.snap.heal_progress"
              "pivot" pivot-number
              "processedNodes"
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
               heal-progress)
              "reusedNodes"
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-reused-nodes
               heal-progress)
              "fetchedNodes"
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
               heal-progress)
              "requests"
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-request-count
               heal-progress)
              "nodeBytes"
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-response-bytes
               heal-progress)
              "completed" completed-p))))
       :on-source-error
       (lambda (source condition)
         (let ((entry (entry-for-source source)))
           (cond
             ((typep condition
                     'ethereum-lisp.snap-sync:snap-sync-state-unavailable)
              (devnet-peer-manager-log
               node "peer.snap.pivot_unavailable"
               "peer" (devnet-peer-entry-id-hex entry)
               "pivot" pivot-number "error" condition))
             ((typep condition 'storage-error)
              ;; The importer re-signals local storage faults after this
              ;; observation; never score a peer for them.
              (devnet-peer-manager-log
               node "peer.snap.storage_failed"
               "peer" (devnet-peer-entry-id-hex entry)
               "error" condition))
             (t
              (devnet-peer-manager-log
               node "peer.snap.import_failed"
               "peer" (devnet-peer-entry-id-hex entry)
               "error" condition)
              (call-with-devnet-peer-table
               node
               (lambda ()
                 (devnet-peer-note-score
                  (devnet-node-peer-table node)
                  (devnet-peer-entry-id-hex entry) -50)))))))))))

(defun devnet-node-snap-sync-pivot-attempt
    (node target-hash fallback-only-p)
  "Download and execute one selected pivot for TARGET-HASH.

When FALLBACK-ONLY-P is true, selection is restricted to the target parent.
This is the bounded recovery path for a conventional pivot whose account probe
succeeded but whose storage ranges were pruned before the full import."
  (let ((store (devnet-node-store node)))
    (unless (database-engine-payload-store-p store)
      (return-from devnet-node-snap-sync-pivot-attempt nil))
    (multiple-value-bind (resolved-entry target-header initial-pivot tail-headers)
        (devnet-node-resolve-snap-target node target-hash)
      (declare (ignore initial-pivot))
      (multiple-value-bind (entry pivot-header selected-tail-headers)
          (devnet-node-select-snap-pivot
           node resolved-entry
           (if fallback-only-p (last tail-headers 2) tail-headers))
        (let* ((tail-headers selected-tail-headers)
               (database (database-engine-payload-store-database store))
             (persistence (devnet-node-persistence-state node))
             (target-number (block-header-number target-header))
             (pivot-number (block-header-number pivot-header))
             (pivot-hash (block-header-hash pivot-header)))
        (multiple-value-bind (head-number head-hash)
            (call-with-devnet-node-store-guard
             node
             (lambda ()
               (let ((number (chain-store-head-number store)))
                 (values number (chain-store-canonical-hash store number)))))
          ;; A short gap is cheaper and safer to execute normally. Equality is
          ;; retained for restart recovery after the pivot was installed but
          ;; before its bounded executable tail completed.
          (when (< pivot-number head-number)
            (return-from devnet-node-snap-sync-pivot-attempt nil))
          (when (and (= pivot-number head-number)
                     (not (hash32= pivot-hash head-hash)))
            (return-from devnet-node-snap-sync-pivot-attempt nil))
          (multiple-value-bind (existing present-p)
              (call-with-devnet-node-store-guard
               node
               (lambda ()
                 (devnet-node-rebase-stale-snap-progress
                  node database target-header pivot-header)))
            ;; If pivot selection lands exactly on an ordinary canonical head,
            ;; the remaining gap is already bounded. Equality denotes snap
            ;; recovery only when its durable skeleton session exists.
            (when (and (= pivot-number head-number) (not present-p))
              (return-from devnet-node-snap-sync-pivot-attempt nil))
            (let* ((anchor-number
                     (if present-p
                         (node-store-snap-skeleton-progress-anchor-number
                          existing)
                         (1- pivot-number)))
                   (anchor-hash
                     (if present-p
                         (node-store-snap-skeleton-progress-anchor-hash existing)
                         (block-header-parent-hash pivot-header)))
                   (last-number
                     (if present-p
                         (node-store-snap-skeleton-progress-last-number existing)
                         anchor-number))
                   (last-hash
                     (if present-p
                         (node-store-snap-skeleton-progress-last-hash existing)
                         anchor-hash)))
              (when (< last-number target-number)
                (eth-sync-download-blocks-multi
                 (devnet-node-sync-peer-sources node)
                 (lambda (block) (declare (ignore block)))
                 :start-number (1+ last-number)
                 :target-number target-number
                 :expected-parent-hash last-hash
                 :expected-target-hash target-hash
                 :request-timeout-seconds 10
                 :import-batch
                 (lambda (blocks)
                   (let ((last (car (last blocks))))
                     (node-store-export-snap-skeleton-batch-to-kv
                      database blocks
                      (make-node-store-snap-skeleton-progress
                       :authority-id
                       (devnet-persistence-state-authority-id persistence)
                       :chain-id
                       (chain-config-chain-id (devnet-node-config node))
                       :genesis-hash
                       (block-hash (devnet-node-genesis-block node))
                       :target-number target-number :target-hash target-hash
                       :anchor-number anchor-number :anchor-hash anchor-hash
                       :pivot-number pivot-number :pivot-hash pivot-hash
                       :last-number
                       (block-header-number (block-header last))
                       :last-hash (block-hash last)))))))
              (let ((state-progress
                      (devnet-node-snap-import-with-failover
                       node database pivot-header target-hash
                       :preferred-entry entry
                       :target-number target-number)))
                (unless (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                         state-progress)
                  (storage-fail
                   "Snap pivot state import returned before completion")))
              ;; This sparse checkpoint continues the authority of the Engine
              ;; target. The durability adapter rechecks completed target-bound
              ;; skeleton and state evidence in the same rollback boundary.
              (when (> pivot-number head-number)
                (let ((persistence-function
                        (devnet-node-canonical-transition-persistence-function
                         node)))
                  (unless persistence-function
                    (storage-fail
                     "Snap pivot requires canonical persistence"))
                  (call-with-devnet-node-store-guard
                   node
                   (lambda ()
                     (ethereum-lisp.block-import:install-forkchoice-sync-pivot
                      store pivot-hash target-hash (devnet-node-config node)
                      :consensus-authorized-p t
                      :durability-function persistence-function)))))
              ;; The direct provider can now execute only the <=64 post-pivot
              ;; blocks. Already executed blocks are skipped after a restart.
              (dolist (header (rest tail-headers))
                (let ((header-hash (block-header-hash header)))
                  (unless
                      (call-with-devnet-node-store-guard
                       node
                       (lambda ()
                         (chain-store-state-available-p store header-hash)))
                    (let ((block
                            (call-with-devnet-node-store-guard
                             node
                             (lambda ()
                               (chain-store-known-block store header-hash)))))
                      (unless block
                        (storage-fail
                         "Snap skeleton block ~A disappeared"
                         (hash32-to-hex header-hash)))
                      (devnet-peer-sync-import-block
                       node block :require-valid-p t)))))
              (devnet-peer-manager-log
               node "peer.snap.target_completed"
               "pivot" pivot-number "target" target-number)
              (- target-number pivot-number)))))))))

(defun devnet-node-snap-sync-target (node target-hash)
  "Download a bounded skeleton, state-sync, and execute one CL target.

The conventional 64-block pivot is attempted first.  A full multi-source
import can discover storage pruning that the cheap account-root probe could not
observe.  In that case retry exactly once at the target parent; if every source
lacks that state too, report a typed peer-availability failure to the continuous
coordinator instead of terminating the node."
  (handler-case
      (handler-case
          (devnet-node-snap-sync-pivot-attempt node target-hash nil)
        (ethereum-lisp.snap-sync:snap-sync-state-unavailable (first-condition)
          (devnet-peer-manager-log
           node "peer.snap.pivot_fallback"
           "target" (hash32-to-hex target-hash)
           "error" first-condition)
          (handler-case
              (devnet-node-snap-sync-pivot-attempt node target-hash t)
            (ethereum-lisp.snap-sync:snap-sync-state-unavailable
                (second-condition)
              (eth-sync-multi-peer-fail
               "all snap peers lack both authorized pivot states for target ~A: ~A"
               (hash32-to-hex target-hash) second-condition)))))
    (ethereum-lisp.snap-sync:snap-sync-heal-yielded ()
      ;; A truthy scheduling result prevents this pass from falling into the
      ;; unbounded forward-gap path. The next pass re-evaluates the newest FCU
      ;; target and atomically rebases the stale SNAP session.
      :stale-target)))

(defun devnet-node-consensus-forward-target (node)
  "Return a numbered full-block target supplied through Engine newPayload.

The peer's advertised head is intentionally not considered. A full remote
candidate exists only because Engine/CL supplied the block and import returned
SYNCING or ACCEPTED, which gives the downloader a consensus-driven bound."
  (call-with-devnet-node-store-guard
   node
   (lambda ()
     (let* ((store (devnet-node-store node))
            (head-number (chain-store-head-number store))
            (head-hash (chain-store-canonical-hash store head-number))
            (target
              (first
               (sort
                (remove-if
                 (lambda (block)
                   (<= (block-header-number (block-header block)) head-number))
                 (engine-payload-store-remote-block-list store))
                #'> :key
                (lambda (block)
                  (block-header-number (block-header block)))))))
       (when target
         (values head-number head-hash
                 (block-header-number (block-header target))
                 (block-hash target)))))))

(defun devnet-node-fill-sync-gaps-with-live-peer (node)
  "Schedule hash-origin gap filling on a live session writer."
  (dolist (entry (devnet-node-live-sync-entries node)
                 (eth-sync-multi-peer-fail
                  "no live peer could fill the consensus sync gap"))
    (handler-case
        (return
          (devnet-peer-request-queue-submit
           (devnet-peer-entry-request-queue entry)
           (lambda ()
             (devnet-peer-fill-sync-gaps
              node (devnet-peer-entry-peer entry)))))
      (eth-sync-backfill-peer-error (condition)
        (devnet-peer-manager-log
         node "peer.sync.gap_peer_failed"
         "peer" (devnet-peer-entry-id-hex entry) "error" condition)))))

(defun devnet-node-multi-sync-pass (node)
  "Run one consensus-bounded multi-peer forward download when work exists."
  (let ((forkchoice-target
          (devnet-node-active-snap-target
           node (first (devnet-node-forkchoice-sync-targets node)))))
    (when forkchoice-target
      (let ((snap-entries
              (devnet-node-live-sync-entries node :snap-only-p t)))
        (return-from devnet-node-multi-sync-pass
          (if snap-entries
              (progn
                ;; A valid durable checkpoint may override the stale-pivot
                ;; timer for this first real post-restart attempt.  If the
                ;; finite source generation still cannot serve it, the next
                ;; pass regains the ordinary rebase escape hatch.
                (setf (devnet-node-snap-checkpoint-resume-p node) nil)
                (or (devnet-node-snap-sync-target node forkchoice-target)
                    (devnet-node-fill-sync-gaps-with-live-peer node)))
              (devnet-node-fill-sync-gaps-with-live-peer node))))))
  (multiple-value-bind (head-number head-hash target-number target-hash)
      (devnet-node-consensus-forward-target node)
    (when target-number
      ;; newPayload makes a candidate available but does not publish CL
      ;; forkchoice authority.  When snap peers are available, do not start a
      ;; multi-million-block forward download during the short newPayload/FCU
      ;; gap: that monopolizes and eventually cancels every session before the
      ;; FCU target can select a bounded pivot.  Small gaps remain eligible for
      ;; ordinary candidate download; large gaps wait for the ensuing FCU.
      (when (and (> (- target-number head-number)
                    +devnet-snap-pivot-distance+)
                 (devnet-node-live-sync-entries node :snap-only-p t))
        (return-from devnet-node-multi-sync-pass nil))
      (let ((sources (devnet-node-sync-peer-sources node)))
        (when sources
          (let ((count
                  (eth-sync-download-blocks-multi
                   sources
                   (lambda (block)
                     (devnet-peer-sync-import-block
                      node block :require-valid-p t))
                   :start-number (1+ head-number)
                   :target-number target-number
                   :expected-parent-hash head-hash
                   :expected-target-hash target-hash
                   :request-timeout-seconds 10)))
            (devnet-peer-manager-log
             node "peer.sync.multi_completed"
             "blocks" count "peers" (length sources)
             "target" (hash32-to-hex target-hash))
            count))))))

(defun devnet-peer-fill-sync-gaps (node peer)
  "Fetch what a buffered block needs in order to execute, and return how many
blocks were imported.

This is the half of consensus-driven sync that was missing: the Engine API
buffered a block it could not execute, and nothing went to fetch the ancestors
that would let it. Each gap is filled by walking back from the buffered block's
PARENT until we reach a block we hold, then executing forward.

A peer-specific backfill refusal is logged and the next target is tried. Local
storage, capability, validation, and unknown program failures propagate to the
session supervisor instead of being misclassified as a peer branch miss."
  (let ((store (devnet-node-store node))
        (imported 0))
    (dolist (target (devnet-node-sync-targets node) imported)
      (let ((parent (hash32-bytes
                     (block-header-parent-hash (block-header target)))))
        (handler-case
            (let ((filled (eth-sync-fill-gap
                           peer parent
                           (lambda (hash)
                             (call-with-devnet-node-store-guard
                              node
                              (lambda ()
                                (and (chain-store-known-block
                                      store (make-hash32 hash))
                                     t))))
                           (lambda (block)
                             (devnet-peer-sync-import-block
                              node block :require-valid-p t)))))
              ;; The reverse walk stops at TARGET's parent.  Re-admit the
              ;; buffered target even when FILLED is zero: another sync path
              ;; may already have supplied its parent since TARGET was first
              ;; buffered.
              (devnet-peer-sync-import-block
               node target :require-valid-p t)
              (devnet-peer-manager-log node "peer.sync.gap_filled"
                                       "blocks" (1+ filled)
                                       "target" (hash32-to-hex
                                                 (block-hash target)))
              (incf imported (1+ filled)))
          (eth-sync-backfill-peer-error (condition)
            (devnet-peer-manager-log node "peer.sync.gap_failed"
                                     "target" (hash32-to-hex (block-hash target))
                                     "error" condition)))))
    (dolist (target (devnet-node-forkchoice-sync-targets node) imported)
      (handler-case
          (let ((filled
                  (eth-sync-fill-gap
                   peer
                   (hash32-bytes target)
                   (lambda (hash)
                     (call-with-devnet-node-store-guard
                      node
                      (lambda ()
                        (and (chain-store-known-block
                              store (make-hash32 hash))
                             t))))
                   (lambda (block)
                     (devnet-peer-sync-import-block
                      node block :require-valid-p t)))))
            (when (plusp filled)
              (devnet-peer-manager-log node "peer.sync.head_filled"
                                       "blocks" filled
                                       "target" (hash32-to-hex target))
              (incf imported filled)))
        (eth-sync-backfill-peer-error (condition)
          (devnet-peer-manager-log node "peer.sync.head_failed"
                                   "target" (hash32-to-hex target)
                                   "error" condition))))))

(defun devnet-peer-dial-session (node candidate shutdown-controller
                                 &key stop-p max-actions)
  "Dial CANDIDATE and hold the session until it ends.

Runs on its own thread. Records the outcome on the dial registry so the peer
becomes eligible again -- immediately for a session that lasted, after a backoff
for one that failed."
  #-sbcl
  (declare (ignore node candidate shutdown-controller stop-p max-actions))
  #-sbcl
  nil
  #+sbcl
  (let ((id-hex (devnet-dial-candidate-id-hex candidate))
        (outcome :failed))
    (unwind-protect
         (multiple-value-bind (node-id host port) (parse-enode-url
                                                   (devnet-dial-candidate-enode
                                                    candidate))
            (multiple-value-bind (status head-number chain-context head-hash)
              ;; Takes the store guard itself, per read, and releases it before
               ;; any I/O -- which is why it is safe to call here.
               (devnet-peer-sync-status node)
             (declare (ignore head-number head-hash))
             (let ((socket (eth-sync-dial-socket host port)))
               ;; Enter the pump immediately after admission.  The node-wide
               ;; coordinator owns every consensus-bounded download, including
               ;; hash backfill fallback.  Running a legacy gap walk here would
               ;; hold the global sync claim while this session still had no
               ;; writer pump, starving snap bootstrap behind 100k-header walks
               ;; for each buffered Engine target.
               (devnet-peer-run-session
                node socket shutdown-controller
                (let ((admit (devnet-dial-outbound-admit-function
                              node candidate host port node-id status
                              chain-context)))
                  (lambda (socket)
                    (multiple-value-bind (peer entry refusal) (funcall admit socket)
                      (setf outcome (cond (entry :disconnected)
                                          (refusal :refused)
                                          (t :failed)))
                      (values peer entry refusal))))
                :reserved-slot-p nil
                :stop-p stop-p
                :max-actions max-actions
                :pending-broadcast (devnet-peer-pending-broadcast node)))))
      (call-with-devnet-peer-table
       node
       (lambda ()
         (when (eq outcome :failed)
           (ignore-errors
            (discv4-table-note-failure
             (devnet-node-discovery-table node)
             (node-id-from-hex id-hex))))
         (devnet-dial-registry-mark-done
          (devnet-node-dial-registry node) id-hex (unix-time)
          :outcome outcome))))))

(defun devnet-dial-scheduler-pass (node)
  "One scheduling pass: refresh the configured peers, forget dead candidates,
and claim the next dials. Returns the claimed candidates.

Everything here happens inside ONE peer-table acquisition, because a verdict and
the claim that follows from it must not be separable. Re-reading the configured
peers each pass rather than capturing them once is what makes admin_addPeer take
effect on a running node."
  (call-with-devnet-peer-table
   node
   (lambda ()
     (let ((registry (devnet-node-dial-registry node))
           (table (devnet-node-peer-table node)))
       (dolist (enode (devnet-node-peers node))
         (ignore-errors
          (devnet-dial-registry-put-static
           registry (node-id-to-hex (nth-value 0 (parse-enode-url enode)))
           enode)))
       ;; A bootnode is both a discovery seed and a fallback peer. Public
       ;; networks can be sparse enough that excluding the seeds themselves
       ;; leaves only stale cross-network neighbors to dial. This is geth's
       ;; fallback-node behavior, not manual static-peer injection.
       (dolist (enode (devnet-node-bootnodes node))
         (ignore-errors
          (devnet-dial-registry-put-bootstrap
           registry (node-id-to-hex (nth-value 0 (parse-enode-url enode)))
           enode)))
       (devnet-dial-registry-expire registry (unix-time))
       (devnet-dial-registry-claim-plan registry table (unix-time))))))

(defun devnet-start-dial-scheduler-thread (node shutdown-controller error-callback)
  "Start the outbound dial scheduler, returning (VALUES THREAD SESSIONS-FUNCTION).

Returns NIL when there is nothing to dial for and no way to be told about one --
no configured peers, no bootnodes, and no listener. That guard keeps every test
that starts a node without peering from paying for a scheduler thread; it is a
property of how the node is configured, not an assumption about the test corpus."
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (when (or (devnet-node-peers node)
            (devnet-node-bootnodes node)
            (devnet-node-p2p-port node))
    (let ((sessions '())
          (sessions-lock (devnet-make-mutex "ethereum-lisp-dial-sessions")))
      (values
       (sb-thread:make-thread
        (lambda ()
          (handler-case
              (loop
                (when (devnet-shutdown-requested-p shutdown-controller)
                  (return))
                (dolist (candidate (devnet-dial-scheduler-pass node))
                  ;; Spawn and move on. The scheduler never dials on its own
                  ;; thread, for the same reason the accept loop never
                  ;; handshakes on its own: one slow peer would stop it
                  ;; noticing anything, shutdown included.
                  (let* ((candidate candidate)
                         (thread
                           (sb-thread:make-thread
                            (lambda ()
                              ;; Mandatory, not defensive: an unhandled
                              ;; condition in ANY thread exits the whole
                              ;; process under `sbcl --script`, and a refused
                              ;; dial is an ordinary event.
                              (handler-case
                                  (devnet-peer-dial-session
                                   node candidate shutdown-controller)
                                (serious-condition (condition)
                                  (devnet-peer-manager-log
                                   node "peer.dial.failed"
                                   "id" (devnet-dial-candidate-id-hex candidate)
                                   "error" condition))))
                            :name "ethereum-lisp-devnet-dial-session")))
                    (call-with-devnet-mutex
                     sessions-lock
                     (lambda ()
                       (setf sessions
                             (cons thread
                                   (remove-if-not #'sb-thread:thread-alive-p
                                                  sessions)))))))
                (loop repeat +devnet-dial-tick-seconds+
                      until (devnet-shutdown-requested-p shutdown-controller)
                      do (sleep 1)))
            (serious-condition (condition)
              (funcall error-callback condition)
              (devnet-shutdown-request shutdown-controller))))
        :name "ethereum-lisp-devnet-dial-scheduler")
       (lambda ()
         (call-with-devnet-mutex sessions-lock (lambda () (copy-list sessions))))))))

(defun devnet-node-sync-coordinator-pass (node)
  "Run one sync pass, containing only finite remote-source exhaustion.

Each pass takes a new live-peer snapshot inside DEVNET-NODE-MULTI-SYNC-PASS.
An exhausted snap snapshot therefore leaves the durable task cursors intact and
returns control to the long-running loop, whose next pass may use replacement
sessions.  Local storage, merge, and unexpected program failures deliberately
escape to the coordinator's outer serious-condition boundary."
  (handler-case
      (call-with-devnet-sync-claim
       node (lambda () (devnet-node-multi-sync-pass node)))
    (eth-sync-multi-peer-error (condition)
      (devnet-peer-manager-log
       node "peer.sync.multi_retry" "error" condition)
      nil)
    (ethereum-lisp.snap-sync:snap-sync-sources-exhausted (condition)
      (devnet-peer-manager-log
       node "peer.snap.sources_retry"
       "phase"
       (ethereum-lisp.snap-sync:snap-sync-sources-exhausted-phase condition)
       "failures"
       (length
        (ethereum-lisp.snap-sync:snap-sync-sources-exhausted-failures
         condition))
       "error" condition)
      nil)))

(defun devnet-start-sync-coordinator-thread
    (node shutdown-controller error-callback
     &key (pass-function #'devnet-node-sync-coordinator-pass)
          (poll-interval-seconds +devnet-sync-coordinator-poll-seconds+))
  "Start the consensus-bounded continuous multi-peer sync coordinator.

Validated peer block/range announcements wake the condition variable; the
periodic timeout remains a fallback for missed network announcements.  Wakeups
carry no target, so PASS-FUNCTION still derives all authority from Engine/CL
state."
  #-sbcl
  (declare (ignore node shutdown-controller error-callback pass-function
                   poll-interval-seconds))
  #-sbcl
  nil
  #+sbcl
  (when (or (devnet-node-peers node)
            (devnet-node-bootnodes node)
            (devnet-node-p2p-port node))
    (unless (functionp pass-function)
      (error "Sync coordinator pass must be a function"))
    (unless (and (realp poll-interval-seconds)
                 (plusp poll-interval-seconds))
      (error "Sync coordinator poll interval must be positive"))
    (let ((wake-token
            (devnet-shutdown-controller-add-closeable
             shutdown-controller
             (lambda () (devnet-node-notify-sync-coordinator node)))))
      (handler-case
          (sb-thread:make-thread
           (lambda ()
             (unwind-protect
                  (handler-case
                      (loop until
                            (devnet-shutdown-requested-p shutdown-controller)
                            do
                               ;; Take the notifier lock before every pass.  A
                               ;; peer update racing this consume either becomes
                               ;; visible to this pass or remains pending for an
                               ;; immediate follow-up pass.
                               (devnet-node-consume-sync-notification node)
                               (funcall pass-function node)
                               (unless
                                   (devnet-shutdown-requested-p
                                    shutdown-controller)
                                 (devnet-node-wait-for-sync-notification
                                  node shutdown-controller
                                  poll-interval-seconds)))
                    (serious-condition (condition)
                      (funcall error-callback condition)
                      (devnet-shutdown-request shutdown-controller)))
               (devnet-shutdown-controller-remove-closeable
                shutdown-controller wake-token)))
           :name "ethereum-lisp-devnet-sync-coordinator")
        (serious-condition (condition)
          (devnet-shutdown-controller-remove-closeable
           shutdown-controller wake-token)
          (error condition))))))
