(in-package #:ethereum-lisp.cli)

;;;; Inbound peering: the accept loop, one session thread per peer, and getting
;;;; all of them to stop.
;;;;
;;;; Every thread this wave creates is created here, which is what keeps the
;;;; networking and protocol layers free of sb-thread entirely. The peer table
;;;; below is guarded by a mutex of this manager's own — never the node store
;;;; guard. That guard is a single non-recursive mutex serializing the RPC
;;;; services, block import, journaling and export; holding it across socket I/O
;;;; would not merely slow things down, it would hang shutdown, because the
;;;; rejournal and dev-period workers join without a timeout and both wait on it.
;;;;
;;;; SHUTDOWN IS THE HARD PART, and everything here is shaped by it. The accept
;;;; loop uses a readiness-gated accept, so it returns regularly whether or not
;;;; a peer ever arrives. Each session socket is registered as a shutdown
;;;; closeable BEFORE its handshake begins, so a shutdown mid-handshake closes
;;;; the descriptor and the blocked read errors out on its own. And a session's
;;;; cleanup closes its socket and touches nothing else -- no farewell
;;;; Disconnect, no flush -- because IGNORE-ERRORS catches errors, not blocking,
;;;; and a write to a peer that has stopped reading would hang teardown.

(defconstant +devnet-peer-handshake-timeout-seconds+ 5
  "How long an accepted connection has to start its handshake. Our policy. The
RLPx handshake read is otherwise unbounded, so a peer that connects and says
nothing would hold a thread and a descriptor indefinitely.")

(defconstant +devnet-peer-accept-tick-seconds+ 1
  "How long one accept waits before returning to check for shutdown. Our policy.")

(defun devnet-peer-manager-log (node event &rest fields)
  (telemetry-log :info event
                 :fields (loop for (key value) on fields by #'cddr
                               collect (cons key (princ-to-string value)))
                 ;; Taken from the node explicitly: the telemetry sink special
                 ;; is a defvar used as a keyword default, and a LET binding of
                 ;; a special is invisible to a spawned thread.
                 :sink (devnet-node-telemetry-sink node)))

(defun devnet-peer-disconnect-reason (verdict)
  (ecase verdict
    (:self +devp2p-disconnect-self+)
    (:already-connected +devp2p-disconnect-already-connected+)
    (:too-many-peers +devp2p-disconnect-too-many-peers+)))

(defun devnet-peer-session-readable-function (peer)
  "A readiness gate for PEER's connection.

Asks the STREAM before the descriptor: the connection is fully buffered, so a
whole frame can already be sitting in the Lisp buffer while the descriptor
reports nothing to read. A gate that polls only the descriptor would call an
actively-talking peer idle and drop it."
  #-sbcl
  (declare (ignore peer))
  #-sbcl
  (lambda (timeout) (declare (ignore timeout)) t)
  #+sbcl
  (let ((stream (rlpx-connection-stream (eth-peer-connection peer))))
    (lambda (timeout)
      (or (listen stream)
          (and (sb-sys:fd-stream-p stream)
               (sb-sys:wait-until-fd-usable (sb-sys:fd-stream-fd stream)
                                            :input timeout nil))))))

(defun devnet-peer-run-session (node socket shutdown-controller admit-function
                                &key on-session-start reserved-slot-p stop-p
                                     max-actions pending-broadcast)
  "Turn an open SOCKET into a peer session and serve it until it ends.

Runs on its own thread, and is shared by both directions: everything from
registering the shutdown closeable to the four-step teardown is identical
whether we accepted the connection or dialed it. Only two things differ, and
both are injected.

ADMIT-FUNCTION is called with SOCKET and returns (VALUES PEER ENTRY REFUSAL): a
handshaken peer plus the peer-table entry holding its slot, or a REFUSAL keyword
to send back as a devp2p reason. (VALUES NIL NIL NIL) means there is nothing to
do and falls straight through to teardown.

ON-SESSION-START, when given, runs once with the peer before the message pump.
It is the one thing the directions do differently afterwards: a dialed session
downloads the peer's chain to our tip, an accepted one has nothing to do.

PENDING-BROADCAST, when given, returns transactions of ours to push to this
peer; the session loop calls it and sends what it returns.

RESERVED-SLOT-P says whether teardown must release a handshake reservation.
Inbound takes one, because at accept time there is no identity to decide on;
a dial knows who it is calling before it connects and so never reserves."
  #-sbcl
  (declare (ignore node socket shutdown-controller admit-function
                   on-session-start reserved-slot-p stop-p max-actions
                   pending-broadcast))
  #-sbcl
  nil
  #+sbcl
  (let ((table (devnet-node-peer-table node))
        (closeable nil)
        (admitted nil))
    (unwind-protect
         (progn
           ;; Registered BEFORE the handshake: a shutdown while a peer is still
           ;; proving who it is must still close this descriptor.
           (setf closeable
                 (devnet-shutdown-controller-add-closeable
                  shutdown-controller
                  (lambda () (ignore-errors (sb-bsd-sockets:socket-close socket)))))
           (when closeable
             (multiple-value-bind (peer entry refusal)
                 (funcall admit-function socket)
               (setf admitted entry)
               (cond
                 ((and peer entry)
                  (when on-session-start (funcall on-session-start peer))
                  (eth-peer-run-session
                   peer
                   :readable-function (devnet-peer-session-readable-function peer)
                   :stop-p (or stop-p
                               (lambda ()
                                 (devnet-shutdown-requested-p shutdown-controller)))
                   :max-actions max-actions
                   ;; Our own pool reaches this peer through here, as DATA the
                   ;; session loop sends -- never another thread writing to the
                   ;; connection, which would desynchronize its MAC chain.
                   :pending-broadcast pending-broadcast))
                 ((and peer refusal)
                  (eth-sync-reject-connection
                   (eth-peer-connection peer)
                   (devnet-peer-disconnect-reason refusal)))))))
      ;; Close the socket and nothing else. No farewell Disconnect: a peer that
      ;; has stopped reading would block us here, and this runs on the path a
      ;; shutdown is waiting for. The dialer sends its own, gated, from outside.
      (when admitted
        (call-with-devnet-peer-table
         node
         (lambda ()
           (devnet-peer-table-remove table
                                     (devnet-peer-entry-id-hex admitted)))))
      (when reserved-slot-p
        (call-with-devnet-peer-table
         node (lambda () (devnet-peer-table-release-slot table))))
      (devnet-shutdown-controller-remove-closeable shutdown-controller closeable)
      (ignore-errors (sb-bsd-sockets:socket-close socket)))))

(defun devnet-peer-inbound-admit-function (node remote-host remote-port)
  "The admission half of an INBOUND session: bound the handshake, run the
recipient side of it, then take the identity-keyed verdict.

This is phase two of the two-phase admission the peer table documents: the
identity only exists once the handshake has proven it, so this necessarily runs
on the session thread rather than on the accept loop."
  #-sbcl
  (declare (ignore node remote-host remote-port))
  #-sbcl
  (lambda (socket) (declare (ignore socket)) (values nil nil nil))
  #+sbcl
  (lambda (socket)
    (let ((table (devnet-node-peer-table node)))
      ;; Bound the otherwise unbounded handshake read: a peer that connects and
      ;; says nothing must not hold a thread and a descriptor forever.
      (if (not (sb-sys:wait-until-fd-usable
                (sb-bsd-sockets:socket-file-descriptor socket)
                :input +devnet-peer-handshake-timeout-seconds+ nil))
          (values nil nil nil)
          (multiple-value-bind (status head-number chain-context)
              (devnet-peer-sync-status node)
            (declare (ignore head-number))
            (let* ((peer (eth-sync-accept-peer
                          socket (devnet-node-node-key node) status
                          :chain-context chain-context
                          :serve-backend (devnet-peer-serve-backend node)
                          :listen-port (or (devnet-node-p2p-port node) 0)))
                   (id-hex (node-id-to-hex (eth-peer-remote-public-key peer)))
                   (entry nil)
                   (verdict
                     (call-with-devnet-peer-table
                      node
                      (lambda ()
                        (let ((verdict (devnet-peer-table-inbound-verdict
                                        table id-hex)))
                          (when (eq verdict :accept)
                            (setf entry
                                  (devnet-peer-table-admit
                                   table
                                   (make-devnet-peer-entry
                                    :id-hex id-hex
                                    :direction :inbound
                                    :remote-host remote-host
                                    :remote-port remote-port
                                    :socket socket
                                    :thread sb-thread:*current-thread*
                                    :eth-version (eth-peer-eth-version peer)
                                    :client-id (eth-peer-remote-client-id peer))
                                   (unix-time)))
                            (unless entry (setf verdict :already-connected)))
                          verdict)))))
              (if (eq verdict :accept)
                  (progn
                    (devnet-peer-manager-log
                     node "p2p.peer.connected"
                     "id" id-hex "host" remote-host
                     "eth" (eth-peer-eth-version peer))
                    (values peer entry nil))
                  (progn
                    (devnet-peer-manager-log node "p2p.peer.refused"
                                             "id" id-hex "reason" verdict)
                    (values peer nil verdict)))))))))

(defun devnet-start-p2p-listener-thread
    (node listener shutdown-controller error-callback)
  "Start the inbound accept loop, or return NIL when there is no listener.

A transient accept failure is logged and the loop CONTINUES. For a public
listening port, one refused or aborted connection taking peering down would be a
liveness bug -- deliberately unlike the Engine RPC listener, which re-signals.
Only an error escaping the loop itself is fail-stop."
  #-sbcl
  (declare (ignore node listener shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (when listener
    (let ((table (devnet-node-peer-table node))
          (sessions '())
          (sessions-lock (devnet-make-mutex "ethereum-lisp-p2p-sessions")))
      (values
       (sb-thread:make-thread
        (lambda ()
          (handler-case
              (loop
                (when (devnet-shutdown-requested-p shutdown-controller)
                  (return))
                (handler-case
                    (multiple-value-bind (socket remote-host remote-port)
                        (eth-sync-listener-accept
                         listener
                         :timeout-seconds +devnet-peer-accept-tick-seconds+)
                      (when socket
                        (if (eq :reserve
                                (call-with-devnet-peer-table
                                 node
                                 (lambda ()
                                   (let ((verdict (devnet-peer-table-slot-verdict
                                                   table)))
                                     (when (eq verdict :reserve)
                                       (devnet-peer-table-reserve-slot table))
                                     verdict))))
                            ;; Spawn and move on: the handshake must never run
                            ;; on this thread, or one silent peer stops the
                            ;; listener noticing anything, shutdown included.
                            (let ((thread
                                    (sb-thread:make-thread
                                     (lambda ()
                                       ;; A session must NEVER let a condition
                                       ;; escape its thread. Under `sbcl
                                       ;; --script`, which is how the node and
                                       ;; the whole test suite run, the disabled
                                       ;; debugger turns an unhandled condition
                                       ;; in ANY thread into (exit 1) for the
                                       ;; entire process -- so one peer sending
                                       ;; garbage, closing mid-handshake, or
                                       ;; failing the fork-id check would take
                                       ;; the node down. Measured, not assumed.
                                       (handler-case
                                           (devnet-peer-run-session
                                            node socket shutdown-controller
                                            (devnet-peer-inbound-admit-function
                                             node remote-host remote-port)
                                            :reserved-slot-p t
                                            :pending-broadcast
                                            (devnet-peer-pending-broadcast node))
                                         (error (condition)
                                           (devnet-peer-manager-log
                                            node "p2p.peer.session_failed"
                                            "host" remote-host
                                            "error" condition))))
                                     :name "ethereum-lisp-devnet-peer-session")))
                              (call-with-devnet-mutex
                               sessions-lock
                               (lambda ()
                                 (setf sessions
                                       (cons thread
                                             (remove-if-not
                                              #'sb-thread:thread-alive-p
                                              sessions))))))
                            (progn
                              (devnet-peer-manager-log
                               node "p2p.listener.rejected"
                               "host" remote-host "reason" "no-slot")
                              (ignore-errors
                               (sb-bsd-sockets:socket-close socket))))))
                  (error (condition)
                    (devnet-peer-manager-log node "p2p.listener.accept_failed"
                                             "error" condition))))
            (error (condition)
              (funcall error-callback condition)
              (devnet-shutdown-request shutdown-controller))))
        :name "ethereum-lisp-devnet-p2p-listener")
       (lambda ()
         (call-with-devnet-mutex sessions-lock (lambda () (copy-list sessions))))))))

(defun devnet-join-peer-sessions (session-threads-function &key (timeout 5))
  "Join every session thread, bounded, terminating any that will not stop.

Every join here carries a timeout: an unbounded join on a thread blocked in a
socket read is how a shutdown becomes a hang."
  #-sbcl
  (declare (ignore session-threads-function timeout))
  #-sbcl
  nil
  #+sbcl
  (dolist (thread (funcall session-threads-function))
    (when (sb-thread:thread-alive-p thread)
      (when (eq :timeout
                (sb-thread:join-thread thread :timeout timeout
                                              :default :timeout))
        (ignore-errors (sb-thread:terminate-thread thread))
        (ignore-errors
         (sb-thread:join-thread thread :timeout timeout :default :timeout))))))
