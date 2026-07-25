(in-package #:ethereum-lisp.eth-sync)

;;;; Dialing a peer.
;;;;
;;;; The handshake and download layers work over any binary stream; this opens
;;;; the TCP connection to a peer and runs the initiator side of the handshake
;;;; over it, so a node can reach out to a known enode and start syncing.

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defun eth-sync-socket-stream (socket)
  "A full-duplex binary stream over SOCKET, as the RLPx codecs expect."
  (sb-bsd-sockets:socket-make-stream
   socket :input t :output t
          :element-type '(unsigned-byte 8) :buffering :full))

(defun eth-sync-open-connection (host port private-key remote-public-key)
  "Open a TCP connection to HOST:PORT and run the RLPx initiator handshake.

HOST is a dotted-quad IP string (as carried in an enode). PRIVATE-KEY is our
static secp256k1 key; REMOTE-PUBLIC-KEY is the peer's 64-byte static key.
Returns (VALUES CONNECTION SOCKET); the caller closes SOCKET when finished."
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :stream :protocol :tcp)))
    (handler-case
        (progn
          (sb-bsd-sockets:socket-connect
           socket (sb-bsd-sockets:make-inet-address host) port)
          (values (rlpx-connect-stream (eth-sync-socket-stream socket)
                                       private-key remote-public-key)
                  socket))
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
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

(defun eth-sync-reject-connection (connection reason)
  "Tell a peer we are refusing it, without blocking if it will not read.

The Disconnect goes out uncompressed because it may precede the Hello exchange,
and is gated on the socket being writable: a peer that has stopped reading would
otherwise block us in FORCE-OUTPUT, and IGNORE-ERRORS catches errors, not
blocking. A refusal that cannot be delivered is dropped — the caller closes the
socket either way, and the peer learns the same thing from the close."
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

(defun eth-sync-connect-peer
    (host port remote-public-key private-key our-status
     &key (client-id +eth-sync-client-id+)
          (listen-port 0)
          chain-context
          serve-backend
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
      (eth-sync-open-connection host port private-key remote-public-key)
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
