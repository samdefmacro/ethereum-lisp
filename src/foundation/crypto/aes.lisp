(in-package #:ethereum-lisp.crypto)

;;;; AES, backed by Ironclad.
;;;;
;;;; A thin adapter over Ironclad's :aes cipher (see keccak.lisp for the crypto
;;;; policy). Only the shapes RLPx needs are exposed: whole-message CTR, a
;;;; continuing CTR keystream, and raw single-block ECB. Ironclad's CTR uses the
;;;; full 16-byte IV as a big-endian counter incremented per block, matching Go
;;;; crypto/cipher and the previous in-tree implementation (verified against it,
;;;; including the carry across the low 8 bytes).

(defconstant +aes-block-size+ 16)

(defun aes-cipher (key iv)
  (ironclad:make-cipher :aes :mode :ctr
                        :key (ensure-byte-vector key)
                        :initialization-vector iv))

(defun make-aes-ctr-stream (key &optional iv)
  "Return an AES-CTR stream over KEY starting at the 16-byte IV (default zero).
The returned object is opaque; feed it to AES-CTR-STREAM-APPLY."
  (let ((iv (if iv (ensure-byte-vector iv) (make-byte-vector +aes-block-size+))))
    (unless (= (length iv) +aes-block-size+)
      (error "AES-CTR IV must be ~D bytes" +aes-block-size+))
    (aes-cipher key iv)))

(defun aes-ctr-stream-apply (stream data)
  "XOR DATA against STREAM's continuing keystream, advancing STREAM.

Successive calls share one keystream, so applying it in pieces equals one CTR
pass over the concatenation."
  (let* ((data (ensure-byte-vector data))
         (output (make-byte-vector (length data))))
    (ironclad:encrypt stream data output)
    output))

(defun aes-encrypt-ecb-block (key block)
  "Return the single-block AES encryption of BLOCK under KEY.

The RLPx framing MAC encrypts a 16-byte seed with the MAC key this way; it is
raw ECB on one block, not a general-purpose mode."
  (let ((key (ensure-byte-vector key))
        (block (ensure-byte-vector block)))
    (unless (= (length block) +aes-block-size+)
      (error "AES block must be ~D bytes" +aes-block-size+))
    (let ((cipher (ironclad:make-cipher :aes :mode :ecb :key key))
          (output (make-byte-vector +aes-block-size+)))
      (ironclad:encrypt cipher block output)
      output)))

(defun aes-ctr (key iv data)
  "Encrypt or decrypt DATA under AES-CTR with KEY and the 16-byte IV.

CTR is its own inverse, so one function serves both directions. The counter is
the whole IV incremented as a big-endian integer, matching Go's crypto/cipher."
  (let ((key (ensure-byte-vector key))
        (iv (ensure-byte-vector iv))
        (data (ensure-byte-vector data)))
    (unless (= (length iv) +aes-block-size+)
      (error "AES-CTR IV must be ~D bytes" +aes-block-size+))
    (let ((cipher (aes-cipher key iv))
          (output (make-byte-vector (length data))))
      (ironclad:encrypt cipher data output)
      output)))
