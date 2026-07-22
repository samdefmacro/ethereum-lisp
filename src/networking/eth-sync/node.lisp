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

(defun eth-sync-connect-peer
    (host port remote-public-key private-key our-status
     &key (client-id "ethereum-lisp")
          (listen-port 0)
          (capabilities (list (make-devp2p-capability "eth" 68))))
  "Dial HOST:PORT and run the full RLPx, devp2p Hello, and eth Status handshake
as the initiator.

OUR-STATUS is the eth Status to advertise (see eth-build-status). Returns
(VALUES ETH-PEER SOCKET); the caller closes SOCKET when finished."
  (multiple-value-bind (connection socket)
      (eth-sync-open-connection host port private-key remote-public-key)
    (handler-case
        (values (eth-peer-connect
                 connection
                 (make-devp2p-hello :client-id client-id
                                    :capabilities capabilities
                                    :listen-port listen-port
                                    :node-id (node-id-from-private-key private-key))
                 our-status)
                socket)
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))
