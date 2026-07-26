(in-package #:ethereum-lisp.eth-sync)

;;;; Dialing a peer.
;;;;
;;;; The handshake and download layers work over any binary stream; this opens
;;;; the TCP connection to a peer and runs the initiator side of the handshake
;;;; over it, so a node can reach out to a known enode and start syncing.

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defconstant +eth-sync-dial-timeout-seconds+ 15
  "How long a dial may take to complete. Our policy, not a parity claim.")

(defun eth-sync-socket-stream (socket &key timeout)
  "A full-duplex binary stream over SOCKET, as the RLPx codecs expect.

TIMEOUT bounds each individual read and write, so a peer that stalls part way
through a frame ends the session instead of holding the thread forever. It
signals SB-SYS:IO-TIMEOUT, which is an ERROR and so is caught by ordinary
handlers -- unlike SB-SYS:DEADLINE-TIMEOUT, which inherits SERIOUS-CONDITION and
slips past every one of them.

CALL THIS EXACTLY ONCE PER SOCKET. SBCL caches the stream on the socket and
returns the cached one before looking at any keyword, so a second call passing
TIMEOUT silently hands back the first, untimed stream."
  (sb-bsd-sockets:socket-make-stream
   socket :input t :output t
          :element-type '(unsigned-byte 8) :buffering :full
          :timeout timeout))

(defun eth-sync-dial-socket (host port &key (timeout-seconds
                                             +eth-sync-dial-timeout-seconds+))
  "Connect to HOST:PORT within TIMEOUT-SECONDS, returning a connected socket.

A blocking connect takes as long as the kernel wants -- around 75 seconds to a
silent host -- which is far too long to hold a dial thread and far too long for
a shutdown to wait. So the socket is put in non-blocking mode, the connect is
started, and the descriptor is waited on with a bound.

TWO THINGS HERE ARE EASY TO GET WRONG. Writability does NOT mean the connect
succeeded: a REFUSED connect also makes the descriptor ready. The arbiter is
SOCKET-PEERNAME, which succeeds only if the connection actually landed and
otherwise signals. And blocking mode must be restored before the caller builds a
stream, because every read below the RLPx handshake assumes a blocking
descriptor.

This deliberately does not build a stream -- see ETH-SYNC-SOCKET-STREAM on why
building one here would silently disable the caller's read timeout."
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :stream :protocol :tcp)))
    (handler-case
        (progn
          (setf (sb-bsd-sockets:non-blocking-mode socket) t)
          ;; EINPROGRESS is the normal asynchronous path; every other connect
          ;; error is a real failure and propagates to the cleanup below.
          (handler-case
              (sb-bsd-sockets:socket-connect
               socket (sb-bsd-sockets:make-inet-address host) port)
            (sb-bsd-sockets:operation-in-progress () nil))
          (unless (sb-sys:wait-until-fd-usable
                   (sb-bsd-sockets:socket-file-descriptor socket)
                   :output timeout-seconds nil)
            (error "dialing ~A:~D timed out after ~D seconds"
                   host port timeout-seconds))
          (handler-case (sb-bsd-sockets:socket-peername socket)
            (error (condition)
              ;; The descriptor is ready but there is no peer: the connect was
              ;; refused or reset. Reporting the in-progress condition we caught
              ;; above would say "operation in progress" about a connection that
              ;; is definitively over, so name what actually happened.
              (error "dialing ~A:~D did not connect: ~A" host port condition)))
          (setf (sb-bsd-sockets:non-blocking-mode socket) nil)
          socket)
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))

(defun eth-sync-open-connection (host port private-key remote-public-key
                                 &key socket stream-timeout-seconds)
  "Open a TCP connection to HOST:PORT and run the RLPx initiator handshake.

HOST is a dotted-quad IP string (as carried in an enode). PRIVATE-KEY is our
static secp256k1 key; REMOTE-PUBLIC-KEY is the peer's 64-byte static key.
Returns (VALUES CONNECTION SOCKET); the caller closes SOCKET when finished."
  (let* ((supplied socket)
         (socket (or socket
                     (make-instance 'sb-bsd-sockets:inet-socket
                                    :type :stream :protocol :tcp))))
    (handler-case
        (progn
          (unless supplied
            (sb-bsd-sockets:socket-connect
             socket (sb-bsd-sockets:make-inet-address host) port))
          (values (rlpx-connect-stream
                   (eth-sync-socket-stream socket
                                           :timeout stream-timeout-seconds)
                   private-key remote-public-key)
                  socket))
      (error (condition)
        ;; A socket we were handed belongs to the caller, which has its own
        ;; cleanup for it -- the same ownership split ETH-SYNC-ACCEPT-PEER uses.
        (unless supplied
          (ignore-errors (sb-bsd-sockets:socket-close socket)))
        (error condition)))))

(defparameter +eth-sync-client-id+ "ethereum-lisp"
  "How we name ourselves to peers in the devp2p Hello, and to operators in
admin_nodeInfo. One name for the node, in both places.")

(defun eth-sync-make-hello (private-key &key (client-id +eth-sync-client-id+)
                                             (listen-port 0)
                                             (capabilities
                                              (mapcar (lambda (version)
                                                        (make-devp2p-capability
                                                         "eth" version))
                                                      +eth-supported-protocol-versions+)))
  "Our devp2p Hello, for either side of a connection.

LISTEN-PORT is the TCP port we accept inbound connections on; 0 tells the peer
not to dial us back, which is the right answer when we are not listening."
  (make-devp2p-hello :client-id client-id
                     :capabilities capabilities
                     :listen-port listen-port
                     :node-id (node-id-from-private-key private-key)))

(defun eth-sync-accept-peer
    (socket private-key our-status
     &key (client-id +eth-sync-client-id+)
          (listen-port 0)
          chain-context
          serve-backend
          capabilities)
  "Run the recipient side of the RLPx, Hello, and eth Status handshake on an
already-accepted SOCKET, returning the ETH-PEER.

Unlike ETH-SYNC-CONNECT-PEER this does NOT close SOCKET on failure: the caller
accepted it and owns its lifetime, and it usually has cleanup of its own to run
in the same place. The peer's static key is learned from the handshake, so
nothing about the remote identity is known before this returns."
  (let ((connection (rlpx-accept-stream (eth-sync-socket-stream socket)
                                        private-key)))
    (eth-peer-connect connection
                      (apply #'eth-sync-make-hello private-key
                             :client-id client-id
                             :listen-port listen-port
                             (when capabilities (list :capabilities capabilities)))
                      our-status
                      :chain-context chain-context
                      :serve-backend serve-backend)))

(defun eth-sync-send-goodbye (connection reason)
  "Send a devp2p Disconnect for REASON, giving up rather than blocking.

The write is gated on the socket being writable, because a peer that has stopped
reading would otherwise hold us in FORCE-OUTPUT -- and IGNORE-ERRORS catches
errors, not blocking. That distinction is why a farewell on a teardown path has
to be gated rather than merely wrapped. Uncompressed, since this may precede the
Hello exchange."
  #-sbcl
  (declare (ignore connection reason))
  #-sbcl
  nil
  #+sbcl
  (ignore-errors
   (let ((stream (rlpx-connection-stream connection)))
     (when (or (not (sb-sys:fd-stream-p stream))
               (sb-sys:wait-until-fd-usable (sb-sys:fd-stream-fd stream)
                                            :output 1 nil))
       (rlpx-send-disconnect connection reason :compressed nil))))
  t)

(defun eth-sync-reject-connection (connection reason)
  "Tell a peer we are refusing it, without blocking if it will not read.

The Disconnect goes out uncompressed because it may precede the Hello exchange,
and is gated on the socket being writable: a peer that has stopped reading would
otherwise block us in FORCE-OUTPUT, and IGNORE-ERRORS catches errors, not
blocking. A refusal that cannot be delivered is dropped — the caller closes the
socket either way, and the peer learns the same thing from the close."
  (eth-sync-send-goodbye connection reason))

(defun eth-sync-connect-peer
    (host port remote-public-key private-key our-status
     &key (client-id +eth-sync-client-id+)
          (listen-port 0)
          chain-context
          serve-backend
          socket
          stream-timeout-seconds
          (capabilities (mapcar (lambda (version)
                                  (make-devp2p-capability "eth" version))
                                +eth-supported-protocol-versions+)))
  "Dial HOST:PORT and run the full RLPx, devp2p Hello, and eth Status handshake
as the initiator.

OUR-STATUS is the eth Status to advertise (see eth-build-status). CHAIN-CONTEXT,
when supplied, enables the EIP-2124 fork-id check against the peer, and
SERVE-BACKEND lets us answer the peer's own requests over the same connection.
Returns (VALUES ETH-PEER SOCKET); the caller closes SOCKET when finished."
  (multiple-value-bind (connection socket)
      (eth-sync-open-connection host port private-key remote-public-key
                                :socket socket
                                :stream-timeout-seconds stream-timeout-seconds)
    (handler-case
        (values (eth-peer-connect
                 connection
                 (eth-sync-make-hello private-key
                                      :client-id client-id
                                      :listen-port listen-port
                                      :capabilities capabilities)
                 our-status
                 :chain-context chain-context
                 :serve-backend serve-backend)
                socket)
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))
