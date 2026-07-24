(in-package #:ethereum-lisp.crypto)

;;;; secp256k1 public API.
;;;;
;;;; The elliptic-curve operations delegate to libsecp256k1 (see
;;;; secp256k1-ffi.lisp). This file keeps the package's existing API and the
;;;; small pure-Lisp pieces that need no curve arithmetic: signature-value
;;;; validation, address derivation, key generation, and compressed-key
;;;; framing. Ethereum uses the 64-byte uncompressed public-key body (X||Y,
;;;; no 0x04 prefix) for address derivation and devp2p identities.

;;; A curve point as a cons, retained because SECP256K1-PUBLIC-KEY-POINT is
;;; part of the public API and returns one.
(defun secp256k1-point (x y) (cons x y))
(defun secp256k1-point-x (point) (car point))
(defun secp256k1-point-y (point) (cdr point))

;;; Affine point addition and double-and-add scalar multiplication. These are
;;; NOT on any production cryptographic path — recovery, signing, verification,
;;; ECDH, and key derivation all go through libsecp256k1 below. They remain as
;;; pure helpers for constructing signature test vectors (computing k*G).
(defun secp256k1-point-add (a b)
  (cond
    ((null a) b)
    ((null b) a)
    (t
     (let ((x1 (secp256k1-point-x a))
           (y1 (secp256k1-point-y a))
           (x2 (secp256k1-point-x b))
           (y2 (secp256k1-point-y b)))
       (cond
         ((and (= x1 x2) (= (mod (+ y1 y2) +secp256k1-p+) 0))
          nil)
         (t
          (let* ((slope
                   (if (and (= x1 x2) (= y1 y2))
                       (let ((denominator (modular-inverse
                                           (* 2 y1) +secp256k1-p+)))
                         (unless denominator
                           (return-from secp256k1-point-add nil))
                         (mod (* 3 x1 x1 denominator) +secp256k1-p+))
                       (let ((denominator (modular-inverse
                                           (- x2 x1) +secp256k1-p+)))
                         (unless denominator
                           (return-from secp256k1-point-add nil))
                         (mod (* (- y2 y1) denominator) +secp256k1-p+))))
                 (x3 (mod (- (* slope slope) x1 x2) +secp256k1-p+))
                 (y3 (mod (- (* slope (- x1 x3)) y1) +secp256k1-p+)))
            (secp256k1-point x3 y3))))))))

(defun secp256k1-scalar-multiply (scalar point)
  (loop with result = nil
        with addend = point
        for n = scalar then (ash n -1)
        while (plusp n)
        do (when (oddp n)
             (setf result (secp256k1-point-add result addend)))
           (setf addend (secp256k1-point-add addend addend))
        finally (return result)))

(defun secp256k1-valid-signature-values-p (v r s &key low-s-p)
  (and (or (= v 0) (= v 1))
       (<= 1 r)
       (< r +secp256k1-n+)
       (<= 1 s)
       (< s +secp256k1-n+)
       (or (not low-s-p)
           (<= s +secp256k1-half-n+))))

(defun secp256k1-public-key-address (public-key)
  (let ((address (make-byte-vector 20))
        (hashed (keccak-256 public-key)))
    (replace address hashed :start2 12)
    (make-address address)))

(defun secp256k1-private-key-public-key (private-key)
  "Return the 64-byte uncompressed public key body for PRIVATE-KEY.

The body omits the 0x04 prefix, which is the form Ethereum uses for both
address derivation and devp2p node identities."
  (unless (and (integerp private-key)
               (< 0 private-key)
               (< private-key +secp256k1-n+))
    (error "secp256k1 private key must be in [1, n-1]"))
  (or (secp256k1-ffi-derive-public-key private-key)
      (error "secp256k1 public key derivation failed")))

(defun secp256k1-sign (hash private-key &key k)
  "Sign the 32-byte HASH with the PRIVATE-KEY scalar.

Returns a 65-byte r || s || v signature, where s is normalised to the lower half
of the curve order and v is the recovery id 0 or 1 — the form Ethereum and RLPx
use. Without K the nonce is RFC 6979 deterministic; K pins it and exists so a
test can fix the signature."
  (unless (and (integerp private-key) (< 0 private-key +secp256k1-n+))
    (error "secp256k1 private key must be in [1, n-1]"))
  (let* ((hash (require-sized-byte-vector hash 32 "secp256k1 hash"))
         (signature
           (secp256k1-ffi-sign hash private-key
                               :pinned-nonce (and k (integer-to-fixed-bytes k 32)))))
    (or signature
        ;; A pinned nonce that yields a degenerate signature is an error, not a
        ;; reason to retry — the caller asked for that specific k.
        (if k
            (error "secp256k1 signing failed for the supplied nonce")
            (error "secp256k1 signing failed")))))

(defun secp256k1-random-private-key ()
  "Return a cryptographically random secp256k1 private key scalar in [1, n-1]."
  (loop for candidate = (mod (bytes-to-integer (secure-random-bytes 32))
                             +secp256k1-n+)
        when (plusp candidate) return candidate))

(defun secp256k1-public-key-point (public-key)
  "Parse a 64-byte uncompressed public key body into a curve point."
  (let ((bytes (require-sized-byte-vector public-key 64 "secp256k1 public key")))
    (unless (secp256k1-ffi-parse-public-key-valid-p bytes)
      (error "secp256k1 public key is not on the curve"))
    (secp256k1-point (bytes-to-integer (subseq bytes 0 32))
                     (bytes-to-integer (subseq bytes 32 64)))))

(defun secp256k1-compress-public-key (public-key)
  "Compress a 64-byte uncompressed public-key body (X || Y) to the 33-byte form:
0x02 or 0x03 (Y parity) followed by X. Node records carry the compressed key."
  (let* ((bytes (require-sized-byte-vector public-key 64 "secp256k1 public key"))
         (y (bytes-to-integer (subseq bytes 32 64))))
    (concat-bytes (make-array 1 :element-type '(unsigned-byte 8)
                                :initial-element (if (oddp y) 3 2))
                  (subseq bytes 0 32))))

(defun secp256k1-decompress-public-key (compressed)
  "Expand a 33-byte compressed public key to the 64-byte X || Y body, or NIL when
it is not a valid point."
  (let ((bytes (require-sized-byte-vector compressed 33 "compressed public key")))
    (when (member (aref bytes 0) '(2 3))
      (secp256k1-ffi-decompress bytes))))

(defun secp256k1-verify (hash r s public-key)
  "Verify an ECDSA signature (R, S) over the 32-byte HASH against the known
64-byte PUBLIC-KEY body. Returns T when the signature is valid. Unlike recovery,
this needs no recovery id, as node records sign with an r||s signature."
  (let ((hash (require-sized-byte-vector hash 32 "secp256k1 hash")))
    (and (< 0 r +secp256k1-n+)
         (< 0 s +secp256k1-n+)
         (secp256k1-ffi-verify hash r s public-key))))

(defun secp256k1-ecdh (private-key public-key)
  "Return the 32-byte ECDH shared secret for PRIVATE-KEY and PUBLIC-KEY.

The secret is the big-endian X coordinate of PRIVATE-KEY times the point named
by the 64-byte uncompressed PUBLIC-KEY body — the agreement devp2p ECIES uses."
  (unless (and (integerp private-key) (< 0 private-key +secp256k1-n+))
    (error "secp256k1 private key must be in [1, n-1]"))
  (or (secp256k1-ffi-ecdh private-key
                          (require-sized-byte-vector public-key 64
                                                     "secp256k1 public key"))
      (error "secp256k1 ECDH produced the point at infinity")))

(defun secp256k1-private-key-address (private-key)
  "Derive the Ethereum address for a secp256k1 private key scalar."
  (secp256k1-public-key-address
   (secp256k1-private-key-public-key private-key)))

(defun secp256k1-recover-public-key (hash v r s)
  "Recover a 64-byte uncompressed secp256k1 public key body from HASH/V/R/S.
Returns NIL when the signature is invalid or unrecoverable."
  (let ((hash (require-sized-byte-vector hash 32 "secp256k1 hash")))
    (when (secp256k1-valid-signature-values-p v r s)
      (secp256k1-ffi-recover hash v r s))))

(defun secp256k1-recover-address (hash v r s)
  "Recover the Ethereum address for HASH/V/R/S, or NIL if unrecoverable."
  (let ((public-key (secp256k1-recover-public-key hash v r s)))
    (when public-key
      (secp256k1-public-key-address public-key))))
