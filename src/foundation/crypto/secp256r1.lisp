(in-package #:ethereum-lisp.crypto)

;;;; NIST P-256 (secp256r1) affine curve arithmetic and ECDSA verification,
;;;; used by the EIP-7951 P256VERIFY precompile. NIL denotes the point at
;;;; infinity. This mirrors the secp256k1 implementation but uses the short
;;;; Weierstrass a = -3 term in the doubling slope.

(defun secp256r1-point (x y)
  (cons x y))

(defun secp256r1-point-x (point)
  (car point))

(defun secp256r1-point-y (point)
  (cdr point))

(defun secp256r1-point-on-curve-p (point)
  (and point
       (let ((x (secp256r1-point-x point))
             (y (secp256r1-point-y point)))
         (= (mod (* y y) +secp256r1-p+)
            (mod (+ (* x x x) (* +secp256r1-a+ x) +secp256r1-b+)
                 +secp256r1-p+)))))

(defun secp256r1-point-add (a b)
  (cond
    ((null a) b)
    ((null b) a)
    (t
     (let ((x1 (secp256r1-point-x a))
           (y1 (secp256r1-point-y a))
           (x2 (secp256r1-point-x b))
           (y2 (secp256r1-point-y b)))
       (cond
         ((and (= x1 x2) (zerop (mod (+ y1 y2) +secp256r1-p+)))
          nil)
         (t
          (let* ((slope
                   (if (and (= x1 x2) (= y1 y2))
                       (let ((denominator (modular-inverse
                                           (* 2 y1)
                                           +secp256r1-p+)))
                         (unless denominator
                           (return-from secp256r1-point-add nil))
                         (mod (* (+ (* 3 x1 x1) +secp256r1-a+) denominator)
                              +secp256r1-p+))
                       (let ((denominator (modular-inverse
                                           (- x2 x1)
                                           +secp256r1-p+)))
                         (unless denominator
                           (return-from secp256r1-point-add nil))
                         (mod (* (- y2 y1) denominator)
                              +secp256r1-p+))))
                 (x3 (mod (- (* slope slope) x1 x2) +secp256r1-p+))
                 (y3 (mod (- (* slope (- x1 x3)) y1) +secp256r1-p+)))
            (secp256r1-point x3 y3))))))))

(defun secp256r1-scalar-multiply (scalar point)
  (loop with result = nil
        with addend = point
        for n = scalar then (ash n -1)
        while (plusp n)
        do (when (oddp n)
             (setf result (secp256r1-point-add result addend)))
           (setf addend (secp256r1-point-add addend addend))
        finally (return result)))

(defun secp256r1-verify (hash r s qx qy)
  "Verify an ECDSA P-256 signature per EIP-7951.

HASH, R, S, QX, and QY are non-negative integers. Returns T when the signature
is valid for public key (QX, QY), NIL otherwise. Enforces 0 < r,s < n,
0 <= qx,qy < p, that (qx,qy) is a non-infinity point on the curve, and the
ECDSA recurrence R.x mod n == r."
  (and (< 0 r +secp256r1-n+)
       (< 0 s +secp256r1-n+)
       (< qx +secp256r1-p+)
       (< qy +secp256r1-p+)
       (not (and (zerop qx) (zerop qy)))
       (let ((public-point (secp256r1-point qx qy)))
         (and (secp256r1-point-on-curve-p public-point)
              (let ((s-inverse (modular-inverse s +secp256r1-n+)))
                (and s-inverse
                     (let* ((u1 (mod (* hash s-inverse) +secp256r1-n+))
                            (u2 (mod (* r s-inverse) +secp256r1-n+))
                            (result
                              (secp256r1-point-add
                               (secp256r1-scalar-multiply
                                u1
                                (secp256r1-point +secp256r1-gx+
                                                 +secp256r1-gy+))
                               (secp256r1-scalar-multiply u2 public-point))))
                       (and result
                            (= (mod (secp256r1-point-x result) +secp256r1-n+)
                               r)))))))))
