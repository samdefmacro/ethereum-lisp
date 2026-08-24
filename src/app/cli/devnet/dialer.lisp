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
                   ;; While fewer than sixteen useful SNAP sessions exist, an
                   ;; outbound ETH-only handshake must not consume a slot that
                   ;; discovery can turn into a state source. The peer learns
                   ;; the ordinary :USELESS-PEER refusal and may be retried once
                   ;; the state workload ends.
                   (when (and
                          (eq verdict :accept)
                          (null
                           (ethereum-lisp.eth-sync:eth-peer-snap-version peer))
                          (devnet-snap-quality-shortfall-p registry table))
                     (setf verdict :useless-peer))
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
                             :snap-version
                             (ethereum-lisp.eth-sync:eth-peer-snap-version peer)
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

(defconstant +devnet-snap-heal-stall-interval-seconds+ 300
  "Minimum time without meaningful healer work before stale-target yield.")

(defconstant +devnet-snap-heal-productive-node-interval+ 2048
  "Minimum cumulative processed/fetched work that keeps an old pivot active.")

(defconstant +devnet-snap-heal-source-collapse-interval-seconds+ 300
  "How long a collapsed healer source pool may retain a stale pivot.")

(defconstant +devnet-snap-heal-source-high-water-minimum+ 8
  "Minimum observed healer source count before relative collapse applies.")

(defconstant +devnet-snap-heal-response-window-requests+ 64
  "Minimum request delta used to classify sustained TrieNodes response yield.")

(defconstant +devnet-snap-heal-minimum-fetched-nodes-per-request+ 8
  "Minimum useful average TrieNodes fill before a stale pivot may be yielded.")

(defun devnet-snap-heal-progress-work (progress)
  "Return the monotonic work units relevant to stale-pivot scheduling."
  (+
   (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes progress)
   (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes progress)))

(defun devnet-snap-heal-productive-progress-p (previous-work progress)
  "Whether PROGRESS justifies retaining a stale authorized pivot.

Small partial TrieNodes responses remain useful and durable, but cannot keep a
root which public peers have pruned alive indefinitely.  The threshold matches
the healer's durable node/checkpoint reporting granularity."
  (let ((work (devnet-snap-heal-progress-work progress)))
    (or (null previous-work)
        (< work previous-work)
        (>= (- work previous-work)
            +devnet-snap-heal-productive-node-interval+)
        (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
         progress))))

(defun devnet-snap-heal-source-pool-collapsed-p (current high-water)
  "Whether a formerly useful healer source pool has lost over half its peers.

The relative test avoids churning a stable, intrinsically small public peer
set.  Once a heal has demonstrated enough capacity, however, retaining a root
after most of those peers prune it converts a finite rebase into a slow tail on
one or two exceptional sources."
  (and (integerp current) (not (minusp current))
       (integerp high-water)
       (>= high-water +devnet-snap-heal-source-high-water-minimum+)
       (< (* 2 current) high-water)))

(defun devnet-snap-heal-response-window-efficient-p
    (previous-fetched previous-requests progress)
  "Whether one bounded remote-heal window retained useful serving capacity.

The caller first waits for at least
`+DEVNET-SNAP-HEAL-RESPONSE-WINDOW-REQUESTS+` new requests.  A public peer set
which returns one or two nodes per nominal 1,024-path TrieNodes request is
usually serving the disappearing edge of a pruned root, not useful sustained
progress.  Locally processed/reused nodes are intentionally excluded."
  (let ((fetched
          (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
           progress))
        (requests
          (ethereum-lisp.snap-sync:snap-sync-heal-progress-request-count
           progress)))
    (and (integerp previous-fetched) (not (minusp previous-fetched))
         (integerp previous-requests) (not (minusp previous-requests))
         (>= fetched previous-fetched)
         (>= requests previous-requests)
         (>= (- requests previous-requests)
             +devnet-snap-heal-response-window-requests+)
         (>= (- fetched previous-fetched)
             (* +devnet-snap-heal-minimum-fetched-nodes-per-request+
                (- requests previous-requests))))))

(defun devnet-snap-heal-progress-log-due-p (last-log-at now completed-p)
  "Whether one cumulative healing snapshot should reach operator telemetry."
  (or completed-p
      (null last-log-at)
      (< now last-log-at)
      (>= (- now last-log-at)
          +devnet-snap-heal-progress-log-interval-seconds+)))

(defconstant +devnet-snap-stale-pivot-distance+
  (- (* 2 +devnet-snap-pivot-distance+) 8)
  "How far the CL head may advance beyond an unfinished pivot before it moves.

This is geth's pivot-relative 2*64-8 window.  With the conventional target-64
pivot, it is equivalent to moving after the target advances 64-8 blocks.  The
pivot-relative comparison prevents slot-by-slot restarts without retaining the
old root an extra 64 blocks after public peers have pruned it.")

(defun devnet-node-stale-snap-successor
    (node target-hash pivot-number)
  "Return the newer CL-authorized target hash and number when TARGET is stale.

Peer-advertised heads are deliberately excluded. Forkchoice has one current
sync target; the Engine store retains its known header even while state is
unavailable. Like geth, staleness is measured from the active pivot rather than
its target, avoiding slot-by-slot healer churn without adding another 64-block
retention interval."
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
                     (+ pivot-number +devnet-snap-stale-pivot-distance+))
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
                    (let* ((restart-pin-p
                             (devnet-node-snap-session-resume-p node))
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
                             (and (not restart-pin-p)
                                  latest-number
                                  (> latest-number
                                     (+
                                      (node-store-snap-skeleton-progress-pivot-number
                                       skeleton)
                                      +devnet-snap-stale-pivot-distance+)))))
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

(defun devnet-node-set-snap-dial-demand (node enabled-p)
  "Let the dial scheduler fill SNAP-capable rather than generic peer slots."
  (call-with-devnet-peer-table
   node
   (lambda ()
     (let* ((registry (devnet-node-dial-registry node))
            (enabled-p (not (null enabled-p))))
       (unless (eql enabled-p
                    (devnet-dial-registry-snap-demand-p registry))
         (clrhash
          (devnet-dial-registry-snap-degraded-peer-ids registry)))
       (setf (devnet-dial-registry-snap-demand-p registry) enabled-p)))))

(defun devnet-node-set-snap-peer-degraded
    (node entry response-id degraded-p)
  "Set ENTRY's failure state for one SNAP RESPONSE-ID capability."
  (call-with-devnet-peer-table
   node
   (lambda ()
     (let* ((table
             (devnet-dial-registry-snap-degraded-peer-ids
              (devnet-node-dial-registry node)))
            (id (devnet-peer-entry-id-hex entry))
            (failures (gethash id table)))
       (if degraded-p
           (progn
             (unless (hash-table-p failures)
               (setf failures (make-hash-table :test #'eql)
                     (gethash id table) failures))
             (setf (gethash response-id failures) t))
           (when (hash-table-p failures)
             (remhash response-id failures)
             (when (zerop (hash-table-count failures))
               (remhash id table)))))))
  entry)

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

(defun devnet-peer-apply-adaptive-snap-byte-cap (queue message-id packet)
  "Apply QUEUE's learned account/storage byte cap to one request PACKET."
  (case message-id
    (#.ethereum-lisp.snap:+snap-message-get-account-range+
     (setf (ethereum-lisp.snap:snap-get-account-range-bytes packet)
           (min
            (ethereum-lisp.snap:snap-get-account-range-bytes packet)
            (devnet-peer-request-queue-snap-capacity
             queue ethereum-lisp.snap:+snap-message-account-range+))))
    (#.ethereum-lisp.snap:+snap-message-get-storage-ranges+
     (setf (ethereum-lisp.snap:snap-get-storage-ranges-bytes packet)
           (min
            (ethereum-lisp.snap:snap-get-storage-ranges-bytes packet)
            (devnet-peer-request-queue-snap-capacity
             queue ethereum-lisp.snap:+snap-message-storage-ranges+)))))
  packet)

(defun devnet-peer-bytecode-request (queue hashes byte-limit)
  "Build one ByteCodes request sized in code items for QUEUE's learned rate."
  (let* ((capacity
           (devnet-peer-request-queue-snap-capacity
            queue ethereum-lisp.snap:+snap-message-bytecodes+))
         (count
           (min (length hashes)
                +devnet-snap-max-bytecode-hashes+
                (max 1 capacity)))
         (requested (subseq hashes 0 count)))
    (values
     (ethereum-lisp.snap:make-snap-get-bytecodes
      1 requested (min byte-limit +devnet-snap-max-request-bytes+))
     requested)))

(defun devnet-node-activate-snap-pivot-peer-set-locked (node pivot-hash)
  "Activate PIVOT-HASH while NODE's unavailable-peer lock is held."
  (let ((active (devnet-node-snap-unavailable-pivot-hash node)))
    (unless (and active (hash32= active pivot-hash))
      (setf (devnet-node-snap-unavailable-pivot-hash node)
            (make-hash32 (hash32-bytes pivot-hash)))
      (clrhash (devnet-node-snap-unavailable-peer-ids node))))
  node)

(defun devnet-node-activate-snap-pivot-peer-set (node pivot-hash)
  "Retain explicit peer rejections only while PIVOT-HASH remains active."
  (call-with-devnet-mutex
   (devnet-node-snap-unavailable-peer-lock node)
   (lambda ()
     (devnet-node-activate-snap-pivot-peer-set-locked node pivot-hash))))

(defun devnet-node-note-snap-pivot-unavailable (node pivot-hash entry)
  "Remember that ENTRY explicitly rejected PIVOT-HASH's state."
  (call-with-devnet-mutex
   (devnet-node-snap-unavailable-peer-lock node)
   (lambda ()
     (devnet-node-activate-snap-pivot-peer-set-locked node pivot-hash)
     (setf (gethash (devnet-peer-entry-id-hex entry)
                    (devnet-node-snap-unavailable-peer-ids node))
           t)))
  entry)

(defun devnet-node-snap-pivot-peer-unavailable-p (node pivot-hash entry)
  "Whether ENTRY already rejected the currently active PIVOT-HASH."
  (call-with-devnet-mutex
   (devnet-node-snap-unavailable-peer-lock node)
   (lambda ()
     (let ((active (devnet-node-snap-unavailable-pivot-hash node)))
       (and active
            (hash32= active pivot-hash)
            (gethash (devnet-peer-entry-id-hex entry)
                     (devnet-node-snap-unavailable-peer-ids node)))))))

(defun devnet-peer-queued-snap-source (entry)
  "Build a per-type-pipelined, rate-adaptive SNAP source for ENTRY."
  (let ((peer (devnet-peer-entry-peer entry))
        (queue (devnet-peer-entry-request-queue entry)))
    (flet ((request (message-id packet)
             (devnet-peer-request-queue-submit-snap
              queue peer message-id
              (devnet-peer-apply-adaptive-snap-byte-cap
               queue message-id packet))))
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
       :bytecodes-batch
       (lambda (hashes byte-limit)
         (multiple-value-bind (packet requested)
             (devnet-peer-bytecode-request queue hashes byte-limit)
           (values
            (request ethereum-lisp.snap:+snap-message-get-bytecodes+ packet)
            requested)))
       :trie-nodes
       (lambda (packet)
         (request ethereum-lisp.snap:+snap-message-get-trie-nodes+ packet))))))

#+sbcl
(defstruct (devnet-snap-source-pool
            (:constructor make-devnet-snap-source-pool
                (node &optional pivot-hash)))
  "Independent storage/bytecode scheduler over the node's live SNAP peers."
  node
  ;; Present for production imports and absent in isolated scheduler tests.
  ;; It lets a pooled dependency failure retire the transport that actually
  ;; rejected the state instead of blaming the account-page source.
  pivot-hash
  (lock (sb-thread:make-mutex :name "ethereum-lisp-snap-source-pool"))
  (changed-by-response (make-hash-table))
  (fixed-sources (make-hash-table :test #'eq))
  (reservations (make-hash-table :test #'eq))
  ;; A peer which explicitly lacks this import's state must not be retried when
  ;; the ordinary transport cooldown expires. The pool is pivot/import scoped,
  ;; so this is neither a permanent node ban nor a peer score.
  (unavailable-entries (make-hash-table :test #'eq))
  (failed-entries (make-hash-table :test #'eq)))

(defconstant +devnet-snap-source-pool-failure-cooldown-seconds+ 30
  "How long one failed dependency transport is excluded from pooled work.")

(define-condition devnet-snap-pooled-state-unavailable
    (ethereum-lisp.snap-sync:snap-sync-state-unavailable)
  ()
  (:documentation
   "All pooled dependency candidates are unavailable for the active pivot."))

#+sbcl
(defun devnet-snap-source-pool-reservation-table (pool entry)
  "Return ENTRY's per-response reservation table while POOL is locked."
  (or (gethash entry (devnet-snap-source-pool-reservations pool))
      (setf (gethash entry (devnet-snap-source-pool-reservations pool))
            (make-hash-table))))

#+sbcl
(defun devnet-snap-source-pool-waitqueue (pool response-id)
  "Return RESPONSE-ID's scheduler waitqueue while POOL is locked."
  (or (gethash response-id
               (devnet-snap-source-pool-changed-by-response pool))
      (setf
       (gethash response-id
                (devnet-snap-source-pool-changed-by-response pool))
       (sb-thread:make-waitqueue
        :name "ethereum-lisp-snap-source-pool-response-changed"))))

#+sbcl
(defun devnet-snap-source-pool-register (pool entry source)
  "Register ENTRY's fixed transport SOURCE for pooled dependency requests."
  (sb-thread:with-mutex ((devnet-snap-source-pool-lock pool))
    (setf (gethash entry (devnet-snap-source-pool-fixed-sources pool)) source)
    (maphash
     (lambda (response-id changed)
       (declare (ignore response-id))
       (sb-thread:condition-broadcast changed))
     (devnet-snap-source-pool-changed-by-response pool)))
  source)

#+sbcl
(defun devnet-snap-source-pool-acquire (pool response-id)
  "Reserve the best idle live peer for RESPONSE-ID, waiting when all are busy.

Each peer has one independent slot per response type, matching geth's idle-peer
dispatch. Work waits in the global pool instead of becoming a stale request in
one peer's private queue. Among idle peers, the largest learned delivery
capacity wins and RTT breaks ties, matching geth's capacity-sorted assignment."
  (sb-thread:with-mutex ((devnet-snap-source-pool-lock pool))
    (loop
      (let ((best nil)
            (best-finish nil)
            (best-capacity nil)
            (eligible-p nil))
        (dolist (entry
                  (devnet-node-live-sync-entries
                   (devnet-snap-source-pool-node pool) :snap-only-p t))
          (let ((source
                  (gethash entry
                           (devnet-snap-source-pool-fixed-sources pool))))
            (when (and source
                       (not
                        (gethash
                         entry
                         (devnet-snap-source-pool-unavailable-entries pool)))
                       (<=
                        (gethash
                         entry (devnet-snap-source-pool-failed-entries pool) 0)
                        (get-universal-time)))
              (setf eligible-p t)
              (let* ((reservations
                       (devnet-snap-source-pool-reservation-table pool entry))
                     (load (gethash response-id reservations 0))
                     (queue (devnet-peer-entry-request-queue entry)))
                (when (zerop load)
                  (multiple-value-bind (capacity rtt samples)
                      (if queue
                          (devnet-peer-request-queue-snap-statistics
                           queue response-id)
                          (values 0 nil 0))
                    (let ((finish
                            (if (and (plusp samples) rtt)
                                rtt
                                +devnet-snap-request-target-seconds+)))
                      (when (or (null best)
                                (> capacity best-capacity)
                                (and (= capacity best-capacity)
                                     (< finish best-finish)))
                        (setf best entry
                              best-finish finish
                              best-capacity capacity)))))))))
        (when best
          (let ((reservations
                  (devnet-snap-source-pool-reservation-table pool best)))
            (incf (gethash response-id reservations 0)))
          (return
            (values
             best
             (gethash best
                      (devnet-snap-source-pool-fixed-sources pool)))))
        (unless eligible-p
          (return (values nil nil)))
        (sb-thread:condition-wait
         (devnet-snap-source-pool-waitqueue pool response-id)
         (devnet-snap-source-pool-lock pool))))))

#+sbcl
(defun devnet-snap-source-pool-release-locked (pool entry response-id)
  "Release one dependency reservation while POOL is locked."
  (let* ((reservations
           (devnet-snap-source-pool-reservation-table pool entry))
         (count (gethash response-id reservations 0)))
    (unless (plusp count)
      (error "SNAP source pool reservation underflow"))
    (if (= count 1)
        (remhash response-id reservations)
        (setf (gethash response-id reservations) (1- count)))))

#+sbcl
(defun devnet-snap-source-pool-release (pool entry response-id)
  "Release one dependency reservation for ENTRY and RESPONSE-ID."
  (sb-thread:with-mutex ((devnet-snap-source-pool-lock pool))
    (devnet-snap-source-pool-release-locked pool entry response-id)
    (sb-thread:condition-notify
     (devnet-snap-source-pool-waitqueue pool response-id)))
  t)

#+sbcl
(defun devnet-snap-source-pool-fail-and-release
    (pool entry response-id &key state-unavailable-p)
  "Retire ENTRY for this import or cool it down, then wake global waiters."
  (sb-thread:with-mutex ((devnet-snap-source-pool-lock pool))
    (if state-unavailable-p
        (progn
          (setf (gethash
                 entry (devnet-snap-source-pool-unavailable-entries pool))
                t)
          (when (devnet-snap-source-pool-pivot-hash pool)
            (devnet-node-note-snap-pivot-unavailable
             (devnet-snap-source-pool-node pool)
             (devnet-snap-source-pool-pivot-hash pool)
             entry)))
        (setf
         (gethash entry (devnet-snap-source-pool-failed-entries pool))
         (+ (get-universal-time)
            +devnet-snap-source-pool-failure-cooldown-seconds+)))
    (devnet-snap-source-pool-release-locked pool entry response-id)
    (sb-thread:condition-notify
     (devnet-snap-source-pool-waitqueue pool response-id)))
  (devnet-node-set-snap-peer-degraded
   (devnet-snap-source-pool-node pool) entry response-id t)
  t)

#+sbcl
(defun devnet-snap-source-pool-call
    (pool response-id source-function request label)
  "Run one dependency REQUEST on the best live peer of its response type.

REQUEST may be a packet or a factory called with the reserved peer entry. A
factory may return an assignment token as a second value; it is returned after
the response so ByteCodes can size its hash set from that exact peer's learned
item capacity without racing a second reservation."
  (let ((last-condition nil))
    (loop
      (multiple-value-bind (entry source)
          (devnet-snap-source-pool-acquire pool response-id)
        (unless entry
          (cond
            ((typep
              last-condition
              'ethereum-lisp.snap-sync:snap-sync-state-unavailable)
             ;; The pool already recorded every exact transport that rejected
             ;; the dependency. Do not let the multi-source importer attribute
             ;; the aggregate failure to the unrelated account-page source.
             (error
              'devnet-snap-pooled-state-unavailable
              :request-kind
              (ethereum-lisp.snap-sync:snap-sync-state-unavailable-request-kind
               last-condition)))
            (last-condition (error last-condition))
            (t (error "no live SNAP peer can serve ~A" label))))
        (let ((result nil)
              (request-values nil)
              (succeeded-p nil)
              (transport-condition nil))
          (unwind-protect
               (handler-case
                   (progn
                     (setf request-values
                           (multiple-value-list
                            (if (functionp request)
                                (funcall request entry)
                                (values request))))
                     (setf result
                           (funcall
                            (funcall source-function source)
                            (first request-values))
                           succeeded-p t))
                 (ethereum-lisp.validation:storage-error (condition)
                   ;; Database faults are local and must never be retried as a
                   ;; peer selection problem.
                   (error condition))
                 (serious-condition (condition)
                   (setf transport-condition condition)))
            ;; Install the cooldown before waking waiters so the peer cannot be
            ;; reacquired in the release/failure race.
            (if transport-condition
                (devnet-snap-source-pool-fail-and-release
                 pool entry response-id
                 :state-unavailable-p
                 (typep
                  transport-condition
                  'ethereum-lisp.snap-sync:snap-sync-state-unavailable))
                (progn
                  (devnet-snap-source-pool-release pool entry response-id)
                  (devnet-node-set-snap-peer-degraded
                   (devnet-snap-source-pool-node pool)
                   entry response-id nil))))
          (when succeeded-p
            (return
              (values-list
               (cons result (rest request-values)))))
          (devnet-peer-manager-log
           (devnet-snap-source-pool-node pool)
           "peer.snap.dependency_failed"
           "peer" (devnet-peer-entry-id-hex entry)
           "type" label
           "error" transport-condition)
          (setf last-condition transport-condition))))))

#+sbcl
(defun devnet-snap-source-pool-source (pool entry)
  "Build an account-pinned source whose dependencies use POOL globally."
  (let ((fixed (devnet-peer-queued-snap-source entry)))
    (devnet-snap-source-pool-register pool entry fixed)
    (ethereum-lisp.snap-sync:make-snap-sync-source
     :account-range
     (ethereum-lisp.snap-sync:snap-sync-source-account-range fixed)
     :storage-ranges
     (lambda (packet)
       (devnet-snap-source-pool-call
        pool ethereum-lisp.snap:+snap-message-storage-ranges+
        #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
        packet "storage ranges"))
     :bytecodes
     (lambda (packet)
       (devnet-snap-source-pool-call
        pool ethereum-lisp.snap:+snap-message-bytecodes+
        #'ethereum-lisp.snap-sync:snap-sync-source-bytecodes
        packet "bytecodes"))
     :bytecodes-batch
     (lambda (hashes byte-limit)
       (devnet-snap-source-pool-call
        pool ethereum-lisp.snap:+snap-message-bytecodes+
        #'ethereum-lisp.snap-sync:snap-sync-source-bytecodes
        (lambda (entry)
          (devnet-peer-bytecode-request
           (devnet-peer-entry-request-queue entry) hashes byte-limit))
        "bytecodes"))
     ;; Trie healing already has its own cross-source scheduler and request
     ;; grouping, so retain the fixed source identity for that phase.
     :trie-nodes
     (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes fixed))))

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

The candidate is 64 blocks behind the CL target, matching geth. Falling
forward to the target's parent looks newer but is counterproductive on public
snapshot servers: they generate stable historical layers and frequently cannot
serve target-1. If this root aged out, the caller moves to the newest
CL-authorized target and derives a fresh target-64 pivot instead. State
unavailability is an availability fact, never a peer penalty."
  (unless tail-headers
    (error "Snap pivot selection requires a non-empty target tail"))
  (let* ((live (devnet-node-live-sync-entries node :snap-only-p t))
         (durable-pivot-number (devnet-node-durable-snap-pivot-number node))
         (candidates
           (remove-if
            (lambda (header)
              (and durable-pivot-number
                   (< (block-header-number header) durable-pivot-number)))
            (list (first tail-headers)))))
    (dolist (header candidates
             (eth-sync-multi-peer-fail
              "no snap peer could serve an authorized pivot for target ~A"
              (hash32-to-hex
               (block-header-hash (car (last tail-headers))))))
      (let ((pivot-hash (block-header-hash header)))
        (devnet-node-activate-snap-pivot-peer-set node pivot-hash)
        (let* ((available
                 (remove-if
                  (lambda (entry)
                    (devnet-node-snap-pivot-peer-unavailable-p
                     node pivot-hash entry))
                  live))
               (entries
                 (if (and preferred-entry
                          (member preferred-entry available :test #'eq))
                     (cons preferred-entry
                           (remove preferred-entry available :test #'eq))
                     available)))
          (dolist (entry entries)
            (handler-case
                (progn
                  (ethereum-lisp.snap-sync:snap-sync-probe-state-root
                   (devnet-peer-queued-snap-source entry)
                   (block-header-state-root header))
                  (return-from devnet-node-select-snap-pivot
                    (values
                     entry header (member header tail-headers :test #'eq))))
              (ethereum-lisp.snap-sync:snap-sync-state-unavailable (condition)
                (devnet-node-note-snap-pivot-unavailable
                 node pivot-hash entry)
                (devnet-peer-manager-log
                 node "peer.snap.pivot_unavailable"
                 "peer" (devnet-peer-entry-id-hex entry)
                 "pivot" (block-header-number header)
                 "error" condition))
              (storage-error (condition) (error condition))
              (serious-condition (condition)
                ;; A closed transport is already handled by the session
                ;; supervisor. Do not double-charge it here; a subsequent pass
                ;; will retry with a fresh live-entry snapshot.
                (devnet-peer-manager-log
                 node "peer.snap.pivot_probe_failed"
                 "peer" (devnet-peer-entry-id-hex entry)
                 "pivot" (block-header-number header)
                 "error" condition)))))))))

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
         (source-pool (make-devnet-snap-source-pool node pivot-hash))
         (last-heal-log-at nil)
         (last-heal-progress-at (unix-time))
         (last-heal-progress-work nil)
         (last-heal-target-check-at (unix-time))
         (heal-source-count 0)
         (heal-source-high-water 0)
         (last-heal-source-healthy-at (unix-time))
         (last-heal-efficient-response-at (unix-time))
         (heal-efficiency-fetched nil)
         (heal-efficiency-requests nil)
         (heal-underfilled-response-window-p nil))
    (devnet-node-activate-snap-pivot-peer-set node pivot-hash)
    (labels
        ((ordered-live-entries ()
           (let ((current
                   (remove-if
                    (lambda (entry)
                      (devnet-node-snap-pivot-peer-unavailable-p
                       node pivot-hash entry))
                    (devnet-node-live-sync-entries node :snap-only-p t))))
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
                         (cons
                          (devnet-snap-source-pool-source source-pool entry)
                          entry))))
                 (incf added)))
             (when (plusp added)
               (devnet-peer-manager-log
                node "peer.snap.sources_refreshed"
                "pivot" pivot-number "added" added
                "sources" (length current)))
             (let ((now (unix-time)))
               (setf heal-source-count (length current)
                     heal-source-high-water
                     (max heal-source-high-water heal-source-count))
               (unless (devnet-snap-heal-source-pool-collapsed-p
                        heal-source-count heal-source-high-water)
                 (setf last-heal-source-healthy-at now)))
             (mapcar
              (lambda (entry)
                (car (find entry source-entries :key #'cdr :test #'eq)))
              current)))
         (entry-for-source (source)
           (cdr (assoc source source-entries :test #'eq)))
         (stale-target-p (reason)
           (multiple-value-bind (successor successor-number)
               (devnet-node-stale-snap-successor
                node target-hash pivot-number)
             (when successor
               (devnet-peer-manager-log
                node "peer.snap.target_stale"
                "target" target-number
                "targetHash" (hash32-to-hex target-hash)
                "successor" successor-number
                "successorHash" (hash32-to-hex successor)
                "reason" reason)
               t)))
         (yield-for-stale-target-p ()
           (let ((now (unix-time)))
             ;; Advancing through a durable local/remote batch is productive
             ;; work on a consensus-authorized pivot. Do not repeatedly
             ;; discard its exact DFS frontier merely because the live head
             ;; advances. Tiny partial responses remain durable, but do not
             ;; postpone this escape hatch after public peers have pruned the
             ;; old root; empty responses already retire their source as
             ;; SNAP-SYNC-STATE-UNAVAILABLE. A pool which once demonstrated
             ;; useful width may also yield after over half its sources remain
             ;; absent for the same bounded interval: sparse residual traffic
             ;; must not pin a root after the public serving window collapses.
             ;; A numerically stable pool can fail the same way by returning
             ;; only the disappearing edge of a pruned root.  Classify that
             ;; independently from peer count using bounded request windows.
             (let ((reason
                     (cond
                       ((and
                         (>= now last-heal-progress-at)
                         (>= (- now last-heal-progress-at)
                             +devnet-snap-heal-stall-interval-seconds+))
                        "progress-stalled")
                       ((and
                         (devnet-snap-heal-source-pool-collapsed-p
                          heal-source-count heal-source-high-water)
                         (>= now last-heal-source-healthy-at)
                         (>= (- now last-heal-source-healthy-at)
                             +devnet-snap-heal-source-collapse-interval-seconds+))
                        "source-collapse")
                       ((and
                         heal-underfilled-response-window-p
                         (>= now last-heal-efficient-response-at)
                         (>= (- now last-heal-efficient-response-at)
                             +devnet-snap-heal-source-collapse-interval-seconds+))
                        "response-underfilled"))))
               (when (and
                    reason
                    (or (< now last-heal-target-check-at)
                        (>= (- now last-heal-target-check-at)
                            +devnet-snap-heal-target-check-interval-seconds+)))
                 (setf last-heal-target-check-at now)
                 (stale-target-p reason))))))
      (setf sources (refresh-sources))
      (unless sources
        (eth-sync-multi-peer-fail
         "no live snap peer can import pivot ~A" (hash32-to-hex pivot-hash)))
      (handler-bind
          ((ethereum-lisp.snap-sync:snap-sync-state-unavailable
             (lambda (condition)
               (declare (ignore condition))
               ;; Aggregate exhaustion means that every source in this finite
               ;; generation explicitly refused the authorized state root.
               ;; Keep waiting inside geth's pivot-retention window, but when
               ;; the CL has already authorized a sufficiently newer target,
               ;; yield immediately instead of restarting counters on the same
               ;; publicly pruned root.  Inner per-source handlers run first;
               ;; this sees only the final unhandled availability result.
               (when (stale-target-p "sources-unavailable")
                 (error 'ethereum-lisp.snap-sync:snap-sync-heal-yielded)))))
        (ethereum-lisp.snap-sync:snap-sync-import-state-multi
         database sources
         :pivot-hash pivot-hash :pivot-number pivot-number
         :state-root state-root :target-hash target-hash
         :chain-id (chain-config-chain-id (devnet-node-config node))
       :genesis-hash (block-hash (devnet-node-genesis-block node))
       :authority-id (devnet-persistence-state-authority-id persistence)
       :heal-source-provider #'refresh-sources
       ;; Keep a productive range import on its exact authenticated root.  A
       ;; time-driven rebase poisons the same-root range witness and turns the
       ;; otherwise zero-TrieNodes completion path into a full state-tree walk.
       ;; If every live source actually prunes the root, the import reports
       ;; SNAP-SYNC-STATE-UNAVAILABLE and the next coordinator pass retains the
       ;; durable cursors while selecting a serviceable newer pivot.
       :range-yield-p nil
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
                (queue (devnet-peer-entry-request-queue entry))
                (next
                  (ethereum-lisp.snap-sync:snap-sync-progress-next-origin
                   progress))
                (task
                  (nth task-index
                       (ethereum-lisp.snap-sync:snap-sync-progress-tasks
                        progress))))
           (multiple-value-bind (account-capacity account-rtt account-samples)
               (if queue
                   (devnet-peer-request-queue-snap-statistics
                    queue ethereum-lisp.snap:+snap-message-account-range+)
                   (values nil nil 0))
             (multiple-value-bind (storage-capacity storage-rtt storage-samples)
                 (if queue
                     (devnet-peer-request-queue-snap-statistics
                      queue ethereum-lisp.snap:+snap-message-storage-ranges+)
                     (values nil nil 0))
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
                "accountCap" account-capacity
                "accountRttMs" (and account-rtt (round (* account-rtt 1000)))
                "accountSamples" account-samples
                "storageCap" storage-capacity
                "storageRttMs" (and storage-rtt (round (* storage-rtt 1000)))
                "storageSamples" storage-samples
                "completed"
                (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                 progress))))))
       :on-page-profile
       (lambda (profile source task-index)
         (let ((entry (entry-for-source source)))
           (devnet-peer-manager-log
            node "peer.snap.page_profile"
            "peer" (devnet-peer-entry-id-hex entry)
            "pivot" pivot-number
            "task" task-index
            "accounts"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-account-count
             profile)
            "storageAccounts"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-storage-account-count
             profile)
            "codes"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-code-count profile)
            "accountRequestMs"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-account-request-ms
             profile)
            "proofMs"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-proof-ms profile)
            "storageMs"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-storage-ms profile)
            "codeMs"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-code-ms profile)
            "metadataMs"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-metadata-ms profile)
            "bufferMs"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-buffer-ms profile)
            "totalMs"
            (ethereum-lisp.snap-sync:snap-sync-page-profile-total-ms profile))))
       :on-heal-progress
       (lambda (heal-progress)
         (let* ((now (unix-time))
                (completed-p
                  (ethereum-lisp.snap-sync:snap-sync-heal-progress-completed-p
                   heal-progress))
                (work (devnet-snap-heal-progress-work heal-progress))
                (fetched
                  (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                   heal-progress))
                (requests
                  (ethereum-lisp.snap-sync:snap-sync-heal-progress-request-count
                   heal-progress)))
           (when (devnet-snap-heal-productive-progress-p
                  last-heal-progress-work heal-progress)
             (setf last-heal-progress-at now
                   last-heal-progress-work work))
           (when (or (null heal-efficiency-fetched)
                     (null heal-efficiency-requests)
                     (< fetched heal-efficiency-fetched)
                     (< requests heal-efficiency-requests))
             (setf heal-efficiency-fetched fetched
                   heal-efficiency-requests requests
                   last-heal-efficient-response-at now
                   heal-underfilled-response-window-p nil))
           (when (>= (- requests heal-efficiency-requests)
                     +devnet-snap-heal-response-window-requests+)
             (if (devnet-snap-heal-response-window-efficient-p
                  heal-efficiency-fetched heal-efficiency-requests
                  heal-progress)
                 (setf last-heal-efficient-response-at now
                       heal-underfilled-response-window-p nil)
                 (setf heal-underfilled-response-window-p t))
             (setf heal-efficiency-fetched fetched
                   heal-efficiency-requests requests))
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
              "promotedSubtrees"
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-promoted-subtrees
               heal-progress)
              "skippedSubtrees"
              (ethereum-lisp.snap-sync:snap-sync-heal-progress-skipped-subtrees
               heal-progress)
              "completed" completed-p))))
       :on-source-error
       (lambda (source condition)
         (let ((entry (entry-for-source source)))
           (cond
             ((typep condition 'devnet-snap-pooled-state-unavailable)
              ;; The dependency pool recorded the exact rejecting entries at
              ;; failure time. SOURCE identifies only the account page whose
              ;; dependency job observed aggregate exhaustion.
              (devnet-peer-manager-log
               node "peer.snap.dependencies_unavailable"
               "peer" (devnet-peer-entry-id-hex entry)
               "pivot" pivot-number "error" condition))
             ((typep condition
                     'ethereum-lisp.snap-sync:snap-sync-state-unavailable)
              (devnet-node-note-snap-pivot-unavailable
               node pivot-hash entry)
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
                  (devnet-peer-entry-id-hex entry) -50))))))))))))

(defun devnet-node-snap-sync-pivot-attempt (node target-hash)
  "Download and execute the conventional target-64 pivot for TARGET-HASH."
  (let ((store (devnet-node-store node)))
    (unless (database-engine-payload-store-p store)
      (return-from devnet-node-snap-sync-pivot-attempt nil))
    (multiple-value-bind (resolved-entry target-header initial-pivot tail-headers)
        (devnet-node-resolve-snap-target node target-hash)
      (declare (ignore initial-pivot))
      (multiple-value-bind (entry pivot-header selected-tail-headers)
          (devnet-node-select-snap-pivot
           node resolved-entry tail-headers)
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
              (devnet-node-set-snap-dial-demand node t)
              (let ((state-progress
                      (unwind-protect
                           (devnet-node-snap-import-with-failover
                            node database pivot-header target-hash
                            :preferred-entry entry
                            :target-number target-number)
                        (devnet-node-set-snap-dial-demand node nil))))
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

The conventional 64-block pivot remains pinned while replacement peers arrive.
Peers that explicitly rejected that pivot are skipped on later coordinator
passes. Ordinary target staleness may still move the pivot at geth's bounded
window; finite source exhaustion alone must not churn roots and discard useful
in-flight capacity every second."
  (handler-case
      (handler-case
          (devnet-node-snap-sync-pivot-attempt node target-hash)
        (ethereum-lisp.snap-sync:snap-sync-state-unavailable (condition)
          (devnet-peer-manager-log
           node "peer.snap.pivot_wait"
           "target" (hash32-to-hex target-hash)
           "error" condition)
          :waiting-for-source))
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
                ;; A matching durable Snap session overrides the stale-pivot
                ;; timer for this first real post-restart attempt, even when a
                ;; deploy landed between healer checkpoints. If that source
                ;; generation still cannot serve it, the next pass regains the
                ;; ordinary rebase escape hatch.
                (setf (devnet-node-snap-session-resume-p node) nil)
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
