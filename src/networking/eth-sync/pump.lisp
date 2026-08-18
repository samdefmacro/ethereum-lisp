(in-package #:ethereum-lisp.eth-sync)

;;;; The long-lived session loop.
;;;;
;;;; ETH-PEER-SERVE-LOOP answers whatever a peer sends and is the right shape
;;;; for a short exchange. A session that stays open for hours needs more: it has
;;;; to notice a shutdown, keep the connection alive, drop a peer that has gone
;;;; quiet, and periodically do work of its own. None of that can live below a
;;;; blocking read.
;;;;
;;;; So the loop is split. All the timing policy is a pure function --
;;;; ETH-PUMP-NEXT-ACTION, which reads no clock and touches no socket, taking
;;;; every input as an argument -- and the loop around it is short enough to
;;;; read in one go. The point is that the decisions can be tested exhaustively
;;;; without a network, threads, or sleeps.
;;;;
;;;; THREE CONTRACTS a caller must not break:
;;;;
;;;; 1. ONE REQUEST IN FLIGHT PER PEER. ETH-PEER-AWAIT drops a reply whose id
;;;;    does not match the one it is waiting for, without offering it to the
;;;;    handler, so two overlapping requests lose each other's replies. Every
;;;;    request this loop issues is issued from its own top level, one at a time.
;;;;
;;;; 2. THE LOOP IS THE ONLY WRITER ON ITS CONNECTION. RLPX-WRITE-FRAME advances
;;;;    the egress cipher and the running MAC per frame, and nothing locks it. A
;;;;    second thread writing the same connection desynchronizes the MAC chain
;;;;    and the peer drops us for a bogus authentication failure. Outbound work
;;;;    arrives here as DATA, through the PENDING-BROADCAST closure -- never as
;;;;    another thread calling ETH-PEER-SEND.
;;;;
;;;; 3. A PEER THAT STOPS MID-FRAME IS ENDED BY CLOSING THE SOCKET, not by this
;;;;    loop. The readiness gate sits strictly outside RLPX-CONNECTION-READ-
;;;;    MESSAGE, because a frame header read advances the ingress cipher and MAC
;;;;    in place and must be followed by its body; unwinding between the two
;;;;    desynchronizes the connection permanently.

(defconstant +eth-pump-read-tick-seconds+ 0.05d0
  "How long one readiness wait blocks. Our policy: the upper bound on how long
the loop can take to notice a stop request or a queued coordinator job.  Snap
page import can issue hundreds of dependent storage/code requests; a one-second
tick serialized those requests at roughly one per second even when the peer
answered immediately.")

(defconstant +eth-pump-ping-interval-seconds+ 15
  "How often we send a keepalive Ping when the connection is otherwise idle.
Our policy, chosen to sit inside the idle timeout with room to spare.")

(defconstant +eth-pump-idle-timeout-seconds+ 60
  "How long a peer may send nothing at all before we give up on it. Our policy.")

(defconstant +eth-pump-drain-interval-seconds+ 2
  "How often we ask a peer for the transactions it has announced. Our policy.")

(defstruct (eth-pump-policy
            (:constructor make-eth-pump-policy
                (&key (read-tick-seconds +eth-pump-read-tick-seconds+)
                      (ping-interval-seconds +eth-pump-ping-interval-seconds+)
                      (idle-timeout-seconds +eth-pump-idle-timeout-seconds+)
                      (drain-interval-seconds +eth-pump-drain-interval-seconds+))))
  "The timing knobs of a session. All of these are OUR policy, not a protocol
requirement and not a parity claim. An interval of NIL turns that behavior off."
  read-tick-seconds
  ping-interval-seconds
  idle-timeout-seconds
  drain-interval-seconds)

(defstruct (eth-pump-state
            (:constructor make-eth-pump-state (&key (now 0))))
  "When each periodic thing last happened, in the caller's own time base."
  (last-read-at now)
  (last-ping-at now)
  (last-drain-at now))

(defun eth-pump-due-p (interval last-at now)
  (and interval (>= (- now last-at) interval)))

(defun eth-pump-next-action (policy state now &key readable-p stop-p request-p
                                                   drainable-p chain-update-p
                                                   broadcast-p)
  "The one thing a session should do next. Pure: no clock, no socket, no state
mutation.

Returns :STOP, :READ, :REQUEST, :IDLE-TIMEOUT, :PING, :DRAIN,
:CHAIN-UPDATE, :BROADCAST or :WAIT.

The order is the policy. Stopping beats everything, because a shutdown must not
wait on a peer. A queued coordinator request comes next: its synchronous await
loop consumes and serves interleaved peer traffic, while letting socket
readability win here can starve snap healing forever on a talkative peer.
Ordinary reads then outrank periodic jobs and keep readable peers from being
timed out as idle. :WAIT means there is nothing to do but block on the readiness
gate."
  (cond
    (stop-p :stop)
    (request-p :request)
    (readable-p :read)
    ((eth-pump-due-p (eth-pump-policy-idle-timeout-seconds policy)
                     (eth-pump-state-last-read-at state) now)
     :idle-timeout)
    ((eth-pump-due-p (eth-pump-policy-ping-interval-seconds policy)
                     (eth-pump-state-last-ping-at state) now)
     :ping)
    ((and drainable-p
          (eth-pump-due-p (eth-pump-policy-drain-interval-seconds policy)
                          (eth-pump-state-last-drain-at state) now))
     :drain)
    (chain-update-p :chain-update)
    (broadcast-p :broadcast)
    (t :wait)))

(defun eth-peer-run-session
    (peer &key (policy (make-eth-pump-policy))
               state
               (now-function (lambda () (get-universal-time)))
               readable-function
               stop-p
               pending-request
               pending-chain-update
               pending-broadcast
               on-event
               max-actions)
  "Run PEER's session until it ends, returning (VALUES ACTIONS REASON).

REASON is :STOP when STOP-P asked us to finish, :IDLE-TIMEOUT when the peer went
quiet for too long, or :MAX-ACTIONS when the bound was reached.

READABLE-FUNCTION is called with a timeout in seconds and answers whether a
message can be read. It is INJECTED rather than built here so that a test can
pass a pure predicate, and because the real one has to consider more than the
socket: the peer stream is fully buffered, so a whole frame can be sitting in
the Lisp buffer while the file descriptor reports nothing to read. A gate that
polls only the descriptor will call an actively-talking peer idle.

PENDING-BROADCAST, when given, returns a list of transactions to push to this
peer, or NIL. It is a closure returning DATA precisely so that other threads
never write to this connection themselves -- see contract 2 in the file header.

PENDING-REQUEST returns a zero-argument thunk representing one coordinator job.
The thunk runs here, on the sole session thread, and may synchronously request
eth or snap data. PENDING-CHAIN-UPDATE similarly returns a zero-argument thunk
that sends a local canonical-head announcement from this writer.

ON-EVENT, when given, is called with a keyword for each action taken, which is
how a caller observes the session without this file knowing what telemetry is."
  (let* ((now (funcall now-function))
         (state (or state (make-eth-pump-state :now now)))
         (actions 0))
    (loop
      (when (and max-actions (>= actions max-actions))
        (return (values actions :max-actions)))
      (let* ((now (funcall now-function))
             ;; Asked first, and short-circuiting everything else: once we are
             ;; stopping there is no reason to touch the peer's socket at all,
             ;; and every reason not to — it may already be closing.
             (stopping (and stop-p (funcall stop-p) t))
             ;; Take coordinator jobs before polling the socket.  A snap/eth
             ;; request reads its own response on this sole writer and handles
             ;; unrelated messages while waiting, so this preserves wire
             ;; ordering without allowing a continuously readable peer to
             ;; starve the request queue.
             (request (and (not stopping)
                           pending-request (funcall pending-request)))
             (readable
               (and (not stopping) (null request)
                    readable-function
                    (funcall readable-function
                             (eth-pump-policy-read-tick-seconds policy))
                    t))
             (chain-update (and (not stopping) (not readable) (null request)
                                pending-chain-update
                                (funcall pending-chain-update)))
             (broadcast (unless stopping
                          (when pending-broadcast (funcall pending-broadcast))))
             (action (eth-pump-next-action
                      policy state now
                      :readable-p readable
                      :stop-p stopping
                      :request-p (and request t)
                      :drainable-p
                      (or (plusp (eth-peer-announced-block-count peer))
                          (plusp (eth-peer-announced-hash-count peer)))
                      :chain-update-p (and chain-update t)
                      :broadcast-p (and broadcast t))))
        (when on-event (funcall on-event action))
        (case action
          (:stop (return (values actions :stop)))
          (:idle-timeout (return (values actions :idle-timeout)))
          (:request (funcall request))
          (:read
           ;; READ-ONCE, not READ: the base-protocol traffic has to reach this
           ;; loop, or a connection carrying only keepalives never comes back
           ;; here and none of the periodic work below ever runs again.
           (multiple-value-bind (kind id payload) (eth-peer-read-once peer)
             (setf (eth-pump-state-last-read-at state) now)
             (case kind
               (:eth (eth-peer-handle-message peer id payload))
               (:snap
                (unless (eth-peer-serve-snap-message peer id payload)
                  (error "unsolicited snap/1 response id ~D" id)))
               (:base (eth-peer-handle-base-message peer id)))))
          (:ping
           (rlpx-send-ping (eth-peer-connection peer))
           (setf (eth-pump-state-last-ping-at state) now))
          (:drain
           (eth-peer-fetch-announced-block peer)
           (eth-peer-request-announced-transactions peer)
           (setf (eth-pump-state-last-drain-at state) now))
          (:chain-update (funcall chain-update))
          (:broadcast
           ;; Full-push only small transactions; the broadcast marks those
           ;; known, so the second pass announces only the remaining large
           ;; transactions by hash.
           (eth-peer-broadcast-transactions peer broadcast)
           (eth-peer-announce-transactions peer broadcast))
          (:wait nil))
        (incf actions)))))
