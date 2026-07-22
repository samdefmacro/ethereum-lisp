(in-package #:ethereum-lisp.p2p)

;;;; ECIES as used by the devp2p RLPx handshake.
;;;;
;;;; This is go-ethereum's ECIES_AES128_SHA256 profile: secp256k1 ECDH, a
;;;; NIST SP 800-56 concatenation KDF over SHA-256, AES-128-CTR, and an
;;;; HMAC-SHA-256 tag. A ciphertext is
;;;;
;;;;   0x04 || Rx || Ry  ||  IV || AES-CTR(m)  ||  HMAC-SHA-256 tag
;;;;   \--- ephemeral ---/    \----- em ------/    \----- 32 bytes ----/
;;;;
;;;; where the tag authenticates em concatenated with the optional shared data
;;;; s2. RLPx passes s2 (the frame size prefix under EIP-8) but never s1, so the
;;;; KDF's shared info is always empty here.

(defconstant +ecies-key-len+ 16 "AES-128 key length.")
(defconstant +ecies-hash-len+ 32 "SHA-256 / HMAC-SHA-256 output length.")
(defconstant +ecies-iv-len+ 16 "AES-CTR IV length.")
(defconstant +ecies-public-key-len+ 65 "0x04 || X || Y uncompressed key length.")
(defconstant +ecies-overhead+
  (+ +ecies-public-key-len+ +ecies-iv-len+ +ecies-hash-len+)
  "Bytes an ECIES ciphertext adds to the message.")

(defun ecies-concat-kdf (shared length)
  "The NIST SP 800-56 concatenation KDF over SHA-256.

Produces LENGTH bytes as SHA-256(counter||SHARED) for counter = 1, 2, ...
with an empty shared-info, matching go-ethereum's concatKDF with s1 = nil."
  (let ((shared (ensure-byte-vector shared))
        (blocks '())
        (produced 0))
    (loop for counter from 1
          while (< produced length)
          do (let ((counter-bytes (make-byte-vector 4)))
               (setf (aref counter-bytes 0) (ldb (byte 8 24) counter)
                     (aref counter-bytes 1) (ldb (byte 8 16) counter)
                     (aref counter-bytes 2) (ldb (byte 8 8) counter)
                     (aref counter-bytes 3) (ldb (byte 8 0) counter))
               (push (sha256 counter-bytes shared) blocks)
               (incf produced +ecies-hash-len+)))
    (subseq (apply #'concat-bytes (nreverse blocks)) 0 length)))

(defun ecies-derive-keys (shared-secret)
  "Return (VALUES ENCRYPTION-KEY MAC-KEY) from a 32-byte ECDH SHARED-SECRET."
  (let* ((k (ecies-concat-kdf shared-secret (* 2 +ecies-key-len+)))
         (encryption-key (subseq k 0 +ecies-key-len+))
         ;; The MAC key is the hash of the KDF's second half, not the half
         ;; itself, so a leaked encryption key does not reveal the MAC key.
         (mac-key (sha256 (subseq k +ecies-key-len+ (* 2 +ecies-key-len+)))))
    (values encryption-key mac-key)))

(defun ecies-message-tag (mac-key em shared-data)
  (hmac-sha256 mac-key
               (concat-bytes em (or shared-data (make-byte-vector 0)))))

(defun ecies-encrypt (public-key message
                      &key shared-data
                           (ephemeral-private-key (secp256k1-random-private-key))
                           (iv (secure-random-bytes +ecies-iv-len+)))
  "Encrypt MESSAGE to the 64-byte uncompressed PUBLIC-KEY.

EPHEMERAL-PRIVATE-KEY and IV default to fresh randomness and are parameters only
so a test can pin them. SHARED-DATA is authenticated by the tag but not
encrypted."
  (let* ((message (ensure-byte-vector message))
         (shared-secret (secp256k1-ecdh ephemeral-private-key public-key))
         (ephemeral-public (secp256k1-private-key-public-key ephemeral-private-key)))
    (multiple-value-bind (encryption-key mac-key)
        (ecies-derive-keys shared-secret)
      (let* ((em (concat-bytes iv (aes-ctr encryption-key iv message)))
             (tag (ecies-message-tag mac-key em shared-data)))
        (concat-bytes (concat-bytes #(#x04) ephemeral-public) em tag)))))

(defun ecies-decrypt (private-key ciphertext &key shared-data)
  "Decrypt an ECIES CIPHERTEXT with the secp256k1 PRIVATE-KEY scalar.

Signals an error on any malformed input or a tag that does not authenticate, and
verifies the tag before decrypting."
  (let ((ciphertext (ensure-byte-vector ciphertext)))
    (when (< (length ciphertext) +ecies-overhead+)
      (error "ECIES ciphertext is too short"))
    (unless (= (aref ciphertext 0) #x04)
      (error "ECIES ephemeral key must be uncompressed"))
    (let* ((ephemeral-public (subseq ciphertext 1 +ecies-public-key-len+))
           (em-end (- (length ciphertext) +ecies-hash-len+))
           (em (subseq ciphertext +ecies-public-key-len+ em-end))
           (tag (subseq ciphertext em-end))
           (shared-secret (secp256k1-ecdh private-key ephemeral-public)))
      (multiple-value-bind (encryption-key mac-key)
          (ecies-derive-keys shared-secret)
        (unless (constant-time-bytes=
                 tag (ecies-message-tag mac-key em shared-data))
          (error "ECIES tag does not authenticate the message"))
        (aes-ctr encryption-key
                 (subseq em 0 +ecies-iv-len+)
                 (subseq em +ecies-iv-len+))))))
