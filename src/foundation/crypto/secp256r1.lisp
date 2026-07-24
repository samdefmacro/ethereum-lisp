(in-package #:ethereum-lisp.crypto)

;;;; NIST P-256 (secp256r1) ECDSA verification for the EIP-7951 P256VERIFY
;;;; precompile. The precompile's input validation stays in Lisp so rejection
;;;; is exactly as the spec requires, while the core ECDSA check delegates to
;;;; Ironclad's secp256r1 rather than bespoke curve arithmetic (see keccak.lisp
;;;; for the crypto policy). NIL denotes the point at infinity.

(defun secp256r1-point (x y) (cons x y))
(defun secp256r1-point-x (point) (car point))
(defun secp256r1-point-y (point) (cdr point))

(defun secp256r1-point-on-curve-p (point)
  (and point
       (let ((x (secp256r1-point-x point))
             (y (secp256r1-point-y point)))
         (= (mod (* y y) +secp256r1-p+)
            (mod (+ (* x x x) (* +secp256r1-a+ x) +secp256r1-b+)
                 +secp256r1-p+)))))

(defun secp256r1-ironclad-verify (hash r s qx qy)
  "Core ECDSA P-256 check via Ironclad, given the values already validated."
  (let ((public-key
          (ignore-errors
           (ironclad:make-public-key
            :secp256r1
            :y (concat-bytes (make-array 1 :element-type '(unsigned-byte 8)
                                           :initial-element 4)
                             (integer-to-fixed-bytes qx 32)
                             (integer-to-fixed-bytes qy 32)))))
        (signature
          (ironclad:make-signature :secp256r1
                                   :r (integer-to-fixed-bytes r 32)
                                   :s (integer-to-fixed-bytes s 32))))
    (and public-key
         (ironclad:verify-signature public-key
                                    (integer-to-fixed-bytes hash 32)
                                    signature)
         t)))

(defun secp256r1-verify (hash r s qx qy)
  "Verify an ECDSA P-256 signature per EIP-7951.

HASH, R, S, QX, and QY are non-negative integers. Returns T when the signature
is valid for public key (QX, QY), NIL otherwise. Enforces 0 < r,s < n,
0 <= qx,qy < p, that (qx,qy) is a non-infinity point on the curve, and the
ECDSA recurrence."
  (and (< 0 r +secp256r1-n+)
       (< 0 s +secp256r1-n+)
       (< qx +secp256r1-p+)
       (< qy +secp256r1-p+)
       (not (and (zerop qx) (zerop qy)))
       (secp256r1-point-on-curve-p (secp256r1-point qx qy))
       (secp256r1-ironclad-verify hash r s qx qy)))
