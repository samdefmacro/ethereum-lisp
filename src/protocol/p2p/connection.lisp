(in-package #:ethereum-lisp.p2p)

;;;; Running the RLPx protocol over a byte stream.
;;;;
;;;; The handshake and frame codecs are pure byte transforms; this drives them
;;;; over a binary stream (a socket in production, anything octet-valued in a
;;;; test). The initiator sends auth and reads ack; the recipient reads auth and
;;;; sends ack; both derive the session and can then read and write frames.

(defun rlpx-read-exactly (stream count)
  "Read exactly COUNT octets from STREAM or error if it ends first."
  (let ((buffer (make-byte-vector count)))
    (let ((filled (read-sequence buffer stream)))
      (unless (= filled count)
        (error "RLPx stream ended after ~D of ~D bytes" filled count))
      buffer)))

(defun rlpx-read-handshake-packet (stream)
  "Read a size-prefixed handshake packet (2-byte length then that many bytes)."
  (let* ((prefix (rlpx-read-exactly stream 2))
         (size (logior (ash (aref prefix 0) 8) (aref prefix 1))))
    (concat-bytes prefix (rlpx-read-exactly stream size))))

(defun rlpx-write-packet (stream packet)
  (write-sequence (ensure-byte-vector packet) stream)
  (force-output stream))

(defun rlpx-write-frame-to-stream (session code data stream)
  "Frame CODE and DATA with SESSION and write the frame to STREAM."
  (write-sequence (rlpx-write-frame session code data) stream)
  (force-output stream))

(defun rlpx-read-frame-from-stream (session stream)
  "Read one frame from STREAM, returning (VALUES MESSAGE-CODE DATA)."
  (let* ((frame-size
           (rlpx-read-frame-header
            session (rlpx-read-exactly stream (* 2 +rlpx-frame-block+))))
         (body (rlpx-read-exactly stream (rlpx-frame-body-length frame-size))))
    (rlpx-read-frame-body session frame-size body)))

(defstruct (rlpx-connection (:constructor %make-rlpx-connection))
  session
  stream
  remote-public-key)

(defun rlpx-connect-stream
    (stream private-key remote-public-key
     &key (ephemeral-private-key (secp256k1-random-private-key))
          (nonce (secure-random-bytes +rlpx-nonce-size+)))
  "Run the initiator handshake over STREAM and return an RLPX-CONNECTION.

PRIVATE-KEY is our static secp256k1 key; REMOTE-PUBLIC-KEY is the recipient's
64-byte static public key."
  (let ((auth (rlpx-create-auth private-key ephemeral-private-key
                                remote-public-key nonce)))
    (rlpx-write-packet stream auth)
    (let* ((ack-packet (rlpx-read-handshake-packet stream))
           (ack (rlpx-open-ack private-key ack-packet))
           (ephemeral-key
             (secp256k1-ecdh ephemeral-private-key
                             (rlpx-ack-message-recipient-ephemeral-public-key ack)))
           (recipient-nonce (rlpx-ack-message-recipient-nonce ack)))
      (multiple-value-bind (aes-secret mac-secret)
          (rlpx-derive-secrets ephemeral-key nonce recipient-nonce)
        (%make-rlpx-connection
         :session (make-rlpx-initiator-session aes-secret mac-secret
                                               nonce recipient-nonce auth ack-packet)
         :stream stream
         :remote-public-key remote-public-key)))))

(defun rlpx-accept-stream
    (stream private-key
     &key (ephemeral-private-key (secp256k1-random-private-key))
          (nonce (secure-random-bytes +rlpx-nonce-size+)))
  "Run the recipient handshake over STREAM and return an RLPX-CONNECTION.

The connection's remote public key is the initiator's, taken from its auth."
  (let* ((auth-packet (rlpx-read-handshake-packet stream))
         (auth (rlpx-open-auth private-key auth-packet))
         (initiator-ephemeral
           (rlpx-recover-initiator-ephemeral-key private-key auth))
         (initiator-public-key (rlpx-auth-message-initiator-public-key auth))
         (initiator-nonce (rlpx-auth-message-initiator-nonce auth))
         (ack (rlpx-create-ack ephemeral-private-key initiator-public-key nonce)))
    (rlpx-write-packet stream ack)
    (let ((ephemeral-key
            (secp256k1-ecdh ephemeral-private-key initiator-ephemeral)))
      (multiple-value-bind (aes-secret mac-secret)
          (rlpx-derive-secrets ephemeral-key initiator-nonce nonce)
        (%make-rlpx-connection
         :session (make-rlpx-recipient-session aes-secret mac-secret
                                               initiator-nonce nonce
                                               auth-packet ack)
         :stream stream
         :remote-public-key initiator-public-key)))))

(defun rlpx-connection-write-message (connection code payload &key (compressed t))
  "Write a devp2p message over CONNECTION, Snappy-compressing unless told not to."
  (rlpx-write-frame-to-stream
   (rlpx-connection-session connection)
   code
   (if compressed (snappy-compress payload) (ensure-byte-vector payload))
   (rlpx-connection-stream connection))
  (values))

(defun rlpx-connection-read-message (connection &key (compressed t))
  "Read one devp2p message from CONNECTION, returning (VALUES CODE PAYLOAD)."
  (multiple-value-bind (code data)
      (rlpx-read-frame-from-stream (rlpx-connection-session connection)
                                   (rlpx-connection-stream connection))
    (values code (if compressed (snappy-decompress data) data))))
