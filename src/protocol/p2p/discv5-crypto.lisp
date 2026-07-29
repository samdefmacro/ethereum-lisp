(in-package #:ethereum-lisp.discv5)

;;;; Discovery v5.1 cryptographic constructions.
;;;;
;;;; The wire uses AES-128-GCM, HKDF-SHA256 and compressed-point secp256k1
;;;; ECDH. AES block encryption, hashes, signatures and the ECDH X coordinate
;;;; remain backed by the project's mature crypto libraries. The small point
;;;; walk below determines only the shared point's Y parity and checks its X
;;;; coordinate against libsecp256k1 before the result is accepted.

(defconstant +discv5-secp256k1-p+
  #xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f)

(defparameter +discv5-key-agreement-label+
  (map '(simple-array (unsigned-byte 8) (*)) #'char-code
       "discovery v5 key agreement"))

(defparameter +discv5-identity-proof-label+
  (map '(simple-array (unsigned-byte 8) (*)) #'char-code
       "discovery v5 identity proof"))

(defun discv5-fixed-bytes (value size)
  (let ((result (make-byte-vector size)))
    (dotimes (index size result)
      (setf (aref result (- size index 1)) (ldb (byte 8 (* index 8)) value)))))

(defun discv5-modular-inverse (value modulus)
  ;; MODULUS is prime for secp256k1; Fermat avoids importing crypto internals.
  (when (plusp (mod value modulus))
    (labels ((pow (base exponent result)
               (if (zerop exponent)
                   result
                   (pow (mod (* base base) modulus)
                        (ash exponent -1)
                        (if (oddp exponent)
                            (mod (* result base) modulus)
                            result)))))
      (pow (mod value modulus) (- modulus 2) 1))))

(defun discv5-point-add (left right)
  (cond
    ((null left) right)
    ((null right) left)
    (t
     (let ((x1 (car left)) (y1 (cdr left))
           (x2 (car right)) (y2 (cdr right)))
       (if (and (= x1 x2) (zerop (mod (+ y1 y2) +discv5-secp256k1-p+)))
           nil
           (let* ((slope
                    (if (and (= x1 x2) (= y1 y2))
                        (mod (* 3 x1 x1
                                (discv5-modular-inverse
                                 (* 2 y1) +discv5-secp256k1-p+))
                             +discv5-secp256k1-p+)
                        (mod (* (- y2 y1)
                                (discv5-modular-inverse
                                 (- x2 x1) +discv5-secp256k1-p+))
                             +discv5-secp256k1-p+)))
                  (x3 (mod (- (* slope slope) x1 x2)
                           +discv5-secp256k1-p+))
                  (y3 (mod (- (* slope (- x1 x3)) y1)
                           +discv5-secp256k1-p+)))
             (cons x3 y3)))))))

(defun discv5-scalar-multiply (scalar point)
  (loop with result = nil
        with addend = point
        for value = scalar then (ash value -1)
        while (plusp value)
        do (when (oddp value)
             (setf result (discv5-point-add result addend)))
           (setf addend (discv5-point-add addend addend))
        finally (return result)))

(defun discv5-compressed-ecdh (private-key compressed-public-key)
  "Return the 33-byte compressed ECDH point required by discv5.1."
  (let* ((public-key
           (or (secp256k1-decompress-public-key
                (ensure-byte-vector compressed-public-key))
               (error "discv5 ECDH public key is invalid")))
         (ffi-x (secp256k1-ecdh private-key public-key))
         (point (discv5-scalar-multiply
                 private-key
                 (secp256k1-public-key-point public-key))))
    (unless (and point
                 (= (bytes-to-integer ffi-x) (car point)))
      (error "discv5 ECDH point disagrees with libsecp256k1"))
    (concat-bytes
     (make-array 1 :element-type '(unsigned-byte 8)
                   :initial-element (if (oddp (cdr point)) 3 2))
     ffi-x)))

(defun discv5-hkdf-sha256 (input salt info length)
  (let ((prk (hmac-sha256 salt input))
        (previous (make-byte-vector 0))
        (output (make-byte-vector 0)))
    (loop for counter from 1
          while (< (length output) length)
          do (setf previous
                   (hmac-sha256
                    prk
                    (concat-bytes previous info
                                  (make-array 1 :element-type '(unsigned-byte 8)
                                                :initial-element counter)))
                   output (concat-bytes output previous)))
    (subseq output 0 length)))

(defun discv5-derive-session-keys
    (ephemeral-private-key remote-compressed-public-key
     initiator-node-id recipient-node-id challenge-data)
  "Derive and return initiator and recipient AES keys as two values."
  (let* ((info (concat-bytes +discv5-key-agreement-label+
                             (ensure-byte-vector initiator-node-id)
                             (ensure-byte-vector recipient-node-id)))
         (keys (discv5-hkdf-sha256
                (discv5-compressed-ecdh
                 ephemeral-private-key remote-compressed-public-key)
                (ensure-byte-vector challenge-data) info 32)))
    (values (subseq keys 0 16) (subseq keys 16 32))))

(defun discv5-id-signature
    (static-private-key challenge-data ephemeral-public-key destination-node-id)
  "Create the 64-byte v4 identity proof signature for a handshake."
  (subseq
   (secp256k1-sign
    (sha256 +discv5-identity-proof-label+
            (ensure-byte-vector challenge-data)
            (ensure-byte-vector ephemeral-public-key)
            (ensure-byte-vector destination-node-id))
    static-private-key)
   0 64))

(defun discv5-verify-id-signature
    (signature static-public-key challenge-data ephemeral-public-key
     destination-node-id)
  (let ((signature (ensure-byte-vector signature)))
    (and (= 64 (length signature))
         (secp256k1-verify
          (sha256 +discv5-identity-proof-label+
                  (ensure-byte-vector challenge-data)
                  (ensure-byte-vector ephemeral-public-key)
                  (ensure-byte-vector destination-node-id))
          (bytes-to-integer (subseq signature 0 32))
          (bytes-to-integer (subseq signature 32 64))
          static-public-key))))

(defun discv5-gf128-multiply (left right)
  (let ((result 0)
        (value right)
        (reduction (ash #xe1 120)))
    (dotimes (index 128 result)
      (when (logbitp (- 127 index) left)
        (setf result (logxor result value)))
      (setf value (if (oddp value)
                      (logxor (ash value -1) reduction)
                      (ash value -1))))))

(defun discv5-pad16 (bytes)
  (let* ((bytes (ensure-byte-vector bytes))
         (remainder (mod (length bytes) 16)))
    (if (zerop remainder)
        bytes
        (concat-bytes bytes (make-byte-vector (- 16 remainder))))))

(defun discv5-ghash (hash-subkey authenticated-data ciphertext)
  (let* ((authenticated-data (ensure-byte-vector authenticated-data))
         (ciphertext (ensure-byte-vector ciphertext))
         (input (concat-bytes
                 (discv5-pad16 authenticated-data)
                 (discv5-pad16 ciphertext)
                 (discv5-fixed-bytes (* 8 (length authenticated-data)) 8)
                 (discv5-fixed-bytes (* 8 (length ciphertext)) 8)))
         (h (bytes-to-integer hash-subkey))
         (state 0))
    (loop for offset from 0 below (length input) by 16
          do (setf state
                   (discv5-gf128-multiply
                    (logxor state
                            (bytes-to-integer (subseq input offset (+ offset 16))))
                    h)))
    (discv5-fixed-bytes state 16)))

(defun discv5-counter-block (nonce counter)
  (concat-bytes (ensure-byte-vector nonce) (discv5-fixed-bytes counter 4)))

(defun discv5-gcm-crypt (key nonce input)
  (let ((output (make-byte-vector (length input))))
    (loop for offset from 0 below (length input) by 16
          for counter from 2
          for end = (min (length input) (+ offset 16))
          for stream = (aes-encrypt-ecb-block
                        key (discv5-counter-block nonce counter))
          do (loop for index from offset below end
                   do (setf (aref output index)
                            (logxor (aref input index)
                                    (aref stream (- index offset))))))
    output))

(defun discv5-gcm-tag (key nonce authenticated-data ciphertext)
  (let ((encrypted-j0
          (aes-encrypt-ecb-block key (discv5-counter-block nonce 1)))
        (hash-subkey
          (aes-encrypt-ecb-block key (make-byte-vector 16))))
    (map '(simple-array (unsigned-byte 8) (*)) #'logxor
         encrypted-j0
         (discv5-ghash hash-subkey authenticated-data ciphertext))))

(defun discv5-aes-gcm-encrypt (key nonce plaintext authenticated-data)
  "AES-128-GCM encrypt PLAINTEXT and append its 16-byte authentication tag."
  (let ((key (ensure-byte-vector key))
        (nonce (ensure-byte-vector nonce))
        (plaintext (ensure-byte-vector plaintext)))
    (unless (= 16 (length key))
      (error "discv5 AES key must be 16 bytes"))
    (unless (= 12 (length nonce))
      (error "discv5 GCM nonce must be 12 bytes"))
    (let ((ciphertext (discv5-gcm-crypt key nonce plaintext)))
      (concat-bytes ciphertext
                    (discv5-gcm-tag key nonce authenticated-data ciphertext)))))

(defun discv5-aes-gcm-decrypt (key nonce input authenticated-data)
  "Authenticate and decrypt AES-128-GCM INPUT. Signals before releasing
plaintext when the tag is invalid."
  (let ((input (ensure-byte-vector input)))
    (when (< (length input) 16)
      (error "discv5 GCM ciphertext is shorter than its tag"))
    (let* ((end (- (length input) 16))
           (ciphertext (subseq input 0 end))
           (tag (subseq input end))
           (expected (discv5-gcm-tag key nonce authenticated-data ciphertext)))
      (unless (constant-time-bytes= tag expected)
        (error "discv5 GCM authentication failed"))
      (discv5-gcm-crypt key nonce ciphertext))))

(defun discv5-node-id (public-key)
  "Return the v4 ENR/discv5 node ID (Keccak-256 of uncompressed X || Y)."
  (keccak-256 (ensure-byte-vector public-key)))
