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

(defun rlpx-write-frame-to-stream
    (session code data stream &key max-frame-size)
  "Frame CODE and DATA, splitting a packet when MAX-FRAME-SIZE requires it."
  (let* ((frame-data
           (concat-bytes
            (rlp-encode (integer-to-minimal-bytes code))
            (ensure-byte-vector data)))
         (length (length frame-data)))
    (when (and max-frame-size (not (plusp max-frame-size)))
      (error "RLPx maximum frame size must be positive"))
    (if (or (null max-frame-size) (<= length max-frame-size))
        (write-sequence (rlpx-write-frame-data session frame-data) stream)
        (loop with context-id = 1
              for start from 0 below length by max-frame-size
              for end = (min length (+ start max-frame-size))
              for first = t then nil
              do (write-sequence
                  (rlpx-write-frame-data
                   session (subseq frame-data start end)
                   :context-id context-id
                   :total-packet-size (and first length))
                  stream))))
  (force-output stream))

(defun rlpx-read-frame-data-from-stream (session stream &key max-frame-size)
  "Read one frame, returning data, capability, context, and total packet size."
  (multiple-value-bind (frame-size capability-id context-id total-packet-size)
      (rlpx-read-frame-header
       session (rlpx-read-exactly stream (* 2 +rlpx-frame-block+)))
    (when (and max-frame-size (> frame-size max-frame-size))
      (error "RLPx frame declares ~D bytes, exceeding the ~D-byte limit"
             frame-size max-frame-size))
    (values
     (rlpx-read-frame-body-data
      session frame-size
      (rlpx-read-exactly stream (rlpx-frame-body-length frame-size)))
     capability-id context-id total-packet-size)))

(defun rlpx-read-frame-from-stream (session stream &key max-frame-size)
  "Read one frame from STREAM, returning (VALUES MESSAGE-CODE DATA).

MAX-FRAME-SIZE, when supplied, is checked after authenticating the header and
before allocating or reading the frame body. Chunked packets must be consumed
through RLPX-CONNECTION-READ-MESSAGE, which reassembles their continuation."
  (multiple-value-bind (frame-data capability-id context-id total-packet-size)
      (rlpx-read-frame-data-from-stream session stream
                                       :max-frame-size max-frame-size)
    (unless (and (zerop capability-id) (zerop context-id)
                 (null total-packet-size))
      (error "RLPx frame belongs to a chunked packet"))
    (multiple-value-bind (code next)
        (rlp-decode frame-data :allow-trailing t :max-list-items 16)
      (values (bytes-to-integer (ensure-byte-vector code))
              (subseq frame-data next)))))

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

(defun rlpx-connection-write-message
    (connection code payload &key (compressed t) max-frame-size)
  "Write a devp2p message over CONNECTION, Snappy-compressing unless told not to."
  (rlpx-write-frame-to-stream
   (rlpx-connection-session connection)
   code
   (if compressed (snappy-compress payload) (ensure-byte-vector payload))
   (rlpx-connection-stream connection)
   :max-frame-size max-frame-size)
  (values))

(defun rlpx-connection-read-message
    (connection &key (compressed t) max-frame-size max-message-size)
  "Read one devp2p message from CONNECTION, returning (VALUES CODE PAYLOAD).

MAX-FRAME-SIZE is enforced before the body allocation. MAX-MESSAGE-SIZE is
enforced after decompression as well, so compression cannot bypass the bound."
  (multiple-value-bind (first-data capability-id context-id total-packet-size)
      (rlpx-read-frame-data-from-stream
       (rlpx-connection-session connection)
       (rlpx-connection-stream connection)
       :max-frame-size max-frame-size)
    (unless (zerop capability-id)
      (error "RLPx capability-id ~D is unsupported" capability-id))
    (let ((frame-data
            (if total-packet-size
                (progn
                  (when (zerop context-id)
                    (error "RLPx chunked packet has context-id zero"))
                  (when (and max-message-size
                             (> total-packet-size (+ max-message-size 64)))
                    (error "RLPx chunked packet declares ~D bytes, exceeding its limit"
                           total-packet-size))
                  (when (> (length first-data) total-packet-size)
                    (error "RLPx first chunk exceeds total packet size"))
                  (let ((packet
                          (make-array total-packet-size
                                      :element-type '(unsigned-byte 8)))
                        (filled (length first-data)))
                    (replace packet first-data)
                    (loop while (< filled total-packet-size)
                          do (multiple-value-bind
                                 (chunk next-capability next-context next-total)
                                 (rlpx-read-frame-data-from-stream
                                  (rlpx-connection-session connection)
                                  (rlpx-connection-stream connection)
                                  :max-frame-size max-frame-size)
                               (unless (and (= next-capability capability-id)
                                            (= next-context context-id)
                                            (null next-total))
                                 (error "RLPx chunk continuation metadata mismatch"))
                               (when (> (+ filled (length chunk))
                                        total-packet-size)
                                 (error "RLPx chunks exceed total packet size"))
                               (replace packet chunk :start1 filled)
                               (incf filled (length chunk))))
                    packet))
                (progn
                  (unless (zerop context-id)
                    (error "RLPx continuation arrived without a first chunk"))
                  first-data))))
      (multiple-value-bind (code next)
          (rlp-decode frame-data :allow-trailing t :max-list-items 16)
        (let* ((data (subseq frame-data next))
               (payload (if compressed (snappy-decompress data) data)))
      (when (and max-message-size (> (length payload) max-message-size))
        (error "devp2p message contains ~D bytes, exceeding the ~D-byte limit"
               (length payload) max-message-size))
          (values (bytes-to-integer (ensure-byte-vector code)) payload))))))
