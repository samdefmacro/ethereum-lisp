(in-package #:ethereum-lisp.p2p)

;;;; The devp2p "p2p" capability: Hello, Disconnect, Ping, Pong.
;;;;
;;;; These are RLP messages carried over the RLPx frame codec as
;;;; frame-data = msg-id || msg-data. The Hello exchange is uncompressed; every
;;;; message after it is Snappy-compressed, so the message read/write layer
;;;; carries a compression flag the caller flips once Hello has been seen.

(defconstant +devp2p-version+ 5)

(defconstant +devp2p-message-hello+ #x00)
(defconstant +devp2p-message-disconnect+ #x01)
(defconstant +devp2p-message-ping+ #x02)
(defconstant +devp2p-message-pong+ #x03)

;; A subset of the EIP-706 disconnect reasons, enough to speak the protocol.
(defconstant +devp2p-disconnect-requested+ #x00)
(defconstant +devp2p-disconnect-tcp-error+ #x01)
(defconstant +devp2p-disconnect-useless-peer+ #x03)
(defconstant +devp2p-disconnect-too-many-peers+ #x04)
(defconstant +devp2p-disconnect-incompatible-version+ #x06)

(defstruct (devp2p-capability
            (:constructor make-devp2p-capability (name version)))
  name
  version)

(defstruct (devp2p-hello
            (:constructor make-devp2p-hello
                (&key (version +devp2p-version+) client-id capabilities
                      (listen-port 0) node-id)))
  version
  client-id
  capabilities
  listen-port
  node-id)

(defun encode-devp2p-hello (hello)
  "RLP-encode a devp2p HELLO message body."
  (rlp-encode
   (make-rlp-list
    (integer-to-minimal-bytes (devp2p-hello-version hello))
    (ascii-to-bytes (devp2p-hello-client-id hello))
    (apply #'make-rlp-list
           (mapcar (lambda (capability)
                     (make-rlp-list
                      (ascii-to-bytes (devp2p-capability-name capability))
                      (integer-to-minimal-bytes
                       (devp2p-capability-version capability))))
                   (devp2p-hello-capabilities hello)))
    (integer-to-minimal-bytes (devp2p-hello-listen-port hello))
    (ensure-byte-vector (devp2p-hello-node-id hello)))))

(defun decode-devp2p-hello (bytes)
  "Decode a devp2p HELLO message body, ignoring any trailing fields."
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (when (< (length items) 5)
      (error "devp2p Hello must have at least five fields"))
    (make-devp2p-hello
     :version (bytes-to-integer (ensure-byte-vector (first items)))
     :client-id (bytes-to-ascii (ensure-byte-vector (second items)))
     :capabilities
     (mapcar (lambda (capability)
               (let ((fields (rlp-list-items capability)))
                 (make-devp2p-capability
                  (bytes-to-ascii (ensure-byte-vector (first fields)))
                  (bytes-to-integer (ensure-byte-vector (second fields))))))
             (rlp-list-items (third items)))
     :listen-port (bytes-to-integer (ensure-byte-vector (fourth items)))
     :node-id (ensure-byte-vector (fifth items)))))

(defun encode-devp2p-disconnect (reason)
  (rlp-encode (make-rlp-list (integer-to-minimal-bytes reason))))

(defun decode-devp2p-disconnect (bytes)
  "Return the disconnect reason, defaulting to 0 for an empty body."
  (let ((items (rlp-list-items
                (rlp-decode (ensure-byte-vector bytes) :allow-trailing t))))
    (if items
        (bytes-to-integer (ensure-byte-vector (first items)))
        +devp2p-disconnect-requested+)))

(defun encode-devp2p-ping ()
  (rlp-encode (make-rlp-list)))

(defun encode-devp2p-pong ()
  (rlp-encode (make-rlp-list)))

(defun rlpx-write-message (session code payload &key (compressed t))
  "Frame a devp2p message. COMPRESSED is NIL only for the Hello exchange."
  (rlpx-write-frame session code
                    (if compressed
                        (snappy-compress payload)
                        (ensure-byte-vector payload))))

(defun rlpx-read-message (session frame &key (compressed t))
  "Read a framed devp2p message, returning (VALUES CODE PAYLOAD)."
  (multiple-value-bind (code data) (rlpx-read-frame session frame)
    (values code (if compressed (snappy-decompress data) data))))
