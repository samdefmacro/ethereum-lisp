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
                  ;; Tell the peer where to reach us. Dialing while advertising
                  ;; port 0 says "do not dial me back" even when we are listening.
                  :listen-port (or (devnet-node-p2p-port node) 0)))
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
                             :client-id (eth-peer-remote-client-id peer))
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
                                       "eth" (eth-peer-eth-version peer))
              (values peer entry nil))
            (progn
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
             (let ((blocks '()))
               (maphash (lambda (key block)
                          (declare (ignore key))
                          (push block blocks))
                        (ethereum-lisp.chain-store.state:memory-chain-store-remote-blocks
                         (ethereum-lisp.chain-store.state:chain-store-require-memory-store
                          store)))
               blocks)))
          #'<
          :key (lambda (block) (block-header-number (block-header block))))))

(defun devnet-peer-fill-sync-gaps (node peer)
  "Fetch what a buffered block needs in order to execute, and return how many
blocks were imported.

This is the half of consensus-driven sync that was missing: the Engine API
buffered a block it could not execute, and nothing went to fetch the ancestors
that would let it. Each gap is filled by walking back from the buffered block's
PARENT until we reach a block we hold, then executing forward.

A peer that cannot serve the branch is not an error here -- it may simply be on
a different one -- so a failure is logged and the next target tried."
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
                             (devnet-peer-sync-import-block node block)))))
              (when (plusp filled)
                (devnet-peer-manager-log node "peer.sync.gap_filled"
                                         "blocks" filled
                                         "target" (hash32-to-hex
                                                   (block-hash target)))
                (incf imported filled)))
          (error (condition)
            (devnet-peer-manager-log node "peer.sync.gap_failed"
                                     "target" (hash32-to-hex (block-hash target))
                                     "error" condition)))))))

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
           (multiple-value-bind (status head-number chain-context)
               ;; Takes the store guard itself, per read, and releases it before
               ;; any I/O -- which is why it is safe to call here.
               (devnet-peer-sync-status node)
             (let ((socket (eth-sync-dial-socket host port)))
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
                :pending-broadcast (devnet-peer-pending-broadcast node)
                :on-session-start
                (lambda (peer)
                  ;; Catch up to the peer's tip once. Cheap when we are already
                  ;; there: one short header batch and the loop returns.
                  (eth-sync-download-blocks
                   peer
                   (lambda (block) (devnet-peer-sync-import-block node block))
                   :start-number (1+ head-number))
                  ;; Then fill anything the consensus client asked for that we
                  ;; could not execute. Forward download only helps when the
                  ;; missing blocks extend OUR head; a reorged target needs the
                  ;; backwards walk.
                  (devnet-peer-fill-sync-gaps node peer))))))
      (call-with-devnet-peer-table
       node
       (lambda ()
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
                                (error (condition)
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
            (error (condition)
              (funcall error-callback condition)
              (devnet-shutdown-request shutdown-controller))))
        :name "ethereum-lisp-devnet-dial-scheduler")
       (lambda ()
         (call-with-devnet-mutex sessions-lock (lambda () (copy-list sessions))))))))
