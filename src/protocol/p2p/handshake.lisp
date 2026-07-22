(in-package #:ethereum-lisp.p2p)

;;;; RLPx handshake — recipient side (EIP-8 auth).
;;;;
;;;; The initiator opens a TCP connection and sends an auth message; the
;;;; recipient decrypts it, recovers the initiator's ephemeral public key from
;;;; the signature, and derives the session secrets. This file covers that
;;;; recipient path (open + recover + derive), which needs no ECDSA signing.
;;;; Producing an auth or ack message is a separate step.
;;;;
;;;;   auth        = auth-size || enc-auth-body
;;;;   auth-size   = big-endian 16-bit length of enc-auth-body
;;;;   auth-body   = [sig, initiator-pubk, initiator-nonce, auth-vsn, ...]
;;;;   enc-auth-body = ecies.encrypt(recipient-pubk, auth-body, auth-size)
;;;;
;;;; The size prefix is the ECIES authenticated data, so the recipient must feed
;;;; it back as shared data when decrypting.

(defconstant +rlpx-auth-version+ 4)
(defconstant +rlpx-signature-size+ 65)
(defconstant +rlpx-nonce-size+ 32)
(defconstant +rlpx-public-key-size+ 64)

(defstruct (rlpx-auth-message (:constructor %make-rlpx-auth-message))
  signature
  initiator-public-key
  initiator-nonce
  version)

(defun rlpx-decode-auth-body (plaintext)
  "Decode a decrypted auth body into an RLPX-AUTH-MESSAGE.

Per EIP-8, extra trailing list elements are ignored and a version other than 4
is accepted; only the leading four fields are read."
  ;; EIP-8 appends random padding after the RLP list, so trailing bytes past the
  ;; list are expected and ignored.
  (let ((decoded (rlp-decode (ensure-byte-vector plaintext) :allow-trailing t)))
    (unless (rlp-list-p decoded)
      (error "RLPx auth body must be an RLP list"))
    (let ((items (rlp-list-items decoded)))
      (when (< (length items) 4)
        (error "RLPx auth body must have at least four elements"))
      (let ((signature (ensure-byte-vector (first items)))
            (initiator-public-key (ensure-byte-vector (second items)))
            (initiator-nonce (ensure-byte-vector (third items)))
            (version (bytes-to-integer (ensure-byte-vector (fourth items)))))
        (unless (= (length signature) +rlpx-signature-size+)
          (error "RLPx auth signature must be ~D bytes" +rlpx-signature-size+))
        (unless (= (length initiator-public-key) +rlpx-public-key-size+)
          (error "RLPx auth public key must be ~D bytes" +rlpx-public-key-size+))
        (unless (= (length initiator-nonce) +rlpx-nonce-size+)
          (error "RLPx auth nonce must be ~D bytes" +rlpx-nonce-size+))
        (%make-rlpx-auth-message
         :signature signature
         :initiator-public-key initiator-public-key
         :initiator-nonce initiator-nonce
         :version version)))))

(defun rlpx-open-auth (recipient-private-key auth-packet)
  "Decrypt and decode an EIP-8 auth PACKET addressed to RECIPIENT-PRIVATE-KEY.

RECIPIENT-PRIVATE-KEY is a secp256k1 scalar. AUTH-PACKET is the framed message:
a two-byte big-endian size prefix and then the ECIES ciphertext, where the
prefix is the ciphertext's authenticated data."
  (let ((packet (ensure-byte-vector auth-packet)))
    (when (< (length packet) 2)
      (error "RLPx auth packet is too short"))
    (rlpx-decode-auth-body
     (ecies-decrypt recipient-private-key (subseq packet 2)
                    :shared-data (subseq packet 0 2)))))

(defun rlpx-recover-initiator-ephemeral-key (recipient-private-key auth-message)
  "Recover the initiator's 64-byte ephemeral public key from AUTH-MESSAGE.

The auth signature is over the static shared secret XORed with the initiator
nonce, made with the initiator's ephemeral key, so recovering it yields that
ephemeral public key."
  (let* ((static-shared
           (secp256k1-ecdh recipient-private-key
                           (rlpx-auth-message-initiator-public-key auth-message)))
         (nonce (rlpx-auth-message-initiator-nonce auth-message))
         (signature (rlpx-auth-message-signature auth-message))
         (signed (make-byte-vector +rlpx-nonce-size+)))
    (dotimes (i +rlpx-nonce-size+)
      (setf (aref signed i) (logxor (aref static-shared i) (aref nonce i))))
    (let ((ephemeral
            (secp256k1-recover-public-key
             signed
             (aref signature 64)
             (bytes-to-integer (subseq signature 0 32))
             (bytes-to-integer (subseq signature 32 64)))))
      (unless ephemeral
        (error "RLPx auth signature does not recover an ephemeral key"))
      ephemeral)))

(defconstant +rlpx-ack-version+ 4)

(defstruct (rlpx-ack-message (:constructor %make-rlpx-ack-message))
  recipient-ephemeral-public-key
  recipient-nonce
  version)

(defun rlpx-xor-nonce (a b)
  (let ((out (make-byte-vector +rlpx-nonce-size+)))
    (dotimes (i +rlpx-nonce-size+)
      (setf (aref out i) (logxor (aref a i) (aref b i))))
    out))

(defun rlpx-uint16-be (value)
  (let ((out (make-byte-vector 2)))
    (setf (aref out 0) (ldb (byte 8 8) value)
          (aref out 1) (ldb (byte 8 0) value))
    out))

(defun rlpx-seal-message (recipient-public-key body)
  "ECIES-seal BODY to RECIPIENT-PUBLIC-KEY, prefixed by its big-endian size.

The size prefix is the ciphertext length and is also its authenticated data, so
it is computed from the known ECIES overhead before encrypting."
  (let* ((size (+ (length body) +ecies-overhead+))
         (prefix (rlpx-uint16-be size)))
    (concat-bytes prefix
                  (ecies-encrypt recipient-public-key body :shared-data prefix))))

(defun rlpx-create-auth (initiator-private-key initiator-ephemeral-private-key
                         recipient-public-key initiator-nonce)
  "Build an EIP-8 auth packet from the initiator to RECIPIENT-PUBLIC-KEY.

The signature is over the static shared secret XORed with INITIATOR-NONCE, made
with the initiator's ephemeral key, so the recipient can recover that key."
  (let* ((static-shared
           (secp256k1-ecdh initiator-private-key recipient-public-key))
         (nonce (ensure-byte-vector initiator-nonce))
         (signature (secp256k1-sign (rlpx-xor-nonce static-shared nonce)
                                    initiator-ephemeral-private-key))
         (initiator-public-key
           (secp256k1-private-key-public-key initiator-private-key)))
    (rlpx-seal-message
     recipient-public-key
     (rlp-encode (make-rlp-list signature initiator-public-key nonce
                                (integer-to-minimal-bytes +rlpx-auth-version+))))))

(defun rlpx-create-ack (recipient-ephemeral-private-key initiator-public-key
                        recipient-nonce)
  "Build an EIP-8 ack packet from the recipient to INITIATOR-PUBLIC-KEY."
  (rlpx-seal-message
   initiator-public-key
   (rlp-encode
    (make-rlp-list
     (secp256k1-private-key-public-key recipient-ephemeral-private-key)
     (ensure-byte-vector recipient-nonce)
     (integer-to-minimal-bytes +rlpx-ack-version+)))))

(defun rlpx-decode-ack-body (plaintext)
  (let ((decoded (rlp-decode (ensure-byte-vector plaintext) :allow-trailing t)))
    (unless (rlp-list-p decoded)
      (error "RLPx ack body must be an RLP list"))
    (let ((items (rlp-list-items decoded)))
      (when (< (length items) 3)
        (error "RLPx ack body must have at least three elements"))
      (let ((ephemeral (ensure-byte-vector (first items)))
            (nonce (ensure-byte-vector (second items)))
            (version (bytes-to-integer (ensure-byte-vector (third items)))))
        (unless (= (length ephemeral) +rlpx-public-key-size+)
          (error "RLPx ack ephemeral key must be ~D bytes" +rlpx-public-key-size+))
        (unless (= (length nonce) +rlpx-nonce-size+)
          (error "RLPx ack nonce must be ~D bytes" +rlpx-nonce-size+))
        (%make-rlpx-ack-message
         :recipient-ephemeral-public-key ephemeral
         :recipient-nonce nonce
         :version version)))))

(defun rlpx-open-ack (initiator-private-key ack-packet)
  "Decrypt and decode an EIP-8 ack PACKET with the initiator's private key."
  (let ((packet (ensure-byte-vector ack-packet)))
    (when (< (length packet) 2)
      (error "RLPx ack packet is too short"))
    (rlpx-decode-ack-body
     (ecies-decrypt initiator-private-key (subseq packet 2)
                    :shared-data (subseq packet 0 2)))))

(defun rlpx-derive-secrets (ephemeral-key initiator-nonce recipient-nonce)
  "Derive the RLPx session secrets from the EPHEMERAL-KEY ECDH result and nonces.

Returns (VALUES AES-SECRET MAC-SECRET SHARED-SECRET), each 32 bytes, exactly as
the RLPx spec specifies."
  (let* ((ephemeral-key (ensure-byte-vector ephemeral-key))
         (shared-secret (keccak-256 ephemeral-key
                                    (keccak-256 recipient-nonce initiator-nonce)))
         (aes-secret (keccak-256 ephemeral-key shared-secret))
         (mac-secret (keccak-256 ephemeral-key aes-secret)))
    (values aes-secret mac-secret shared-secret)))
