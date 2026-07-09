(in-package #:ethereum-lisp.crypto)

(defun secp256k1-point (x y)
  (cons x y))

(defun secp256k1-point-x (point)
  (car point))

(defun secp256k1-point-y (point)
  (cdr point))

(defun secp256k1-point-on-curve-p (point)
  (or (null point)
      (let ((x (secp256k1-point-x point))
            (y (secp256k1-point-y point)))
        (= (mod (* y y) +secp256k1-p+)
           (mod (+ (* x x x) 7) +secp256k1-p+)))))

(defun secp256k1-point-negate (point)
  (and point
       (secp256k1-point
        (secp256k1-point-x point)
        (mod (- (secp256k1-point-y point)) +secp256k1-p+))))

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
                                           (* 2 y1)
                                           +secp256k1-p+)))
                         (unless denominator
                           (return-from secp256k1-point-add nil))
                         (mod (* 3 x1 x1 denominator) +secp256k1-p+))
                       (let ((denominator (modular-inverse
                                           (- x2 x1)
                                           +secp256k1-p+)))
                         (unless denominator
                           (return-from secp256k1-point-add nil))
                         (mod (* (- y2 y1) denominator)
                              +secp256k1-p+))))
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

(defun secp256k1-decompress-point (x odd-y-p)
  (when (< x +secp256k1-p+)
    (let* ((alpha (mod (+ (* x x x) 7) +secp256k1-p+))
           (beta (modular-expt alpha
                               (floor (1+ +secp256k1-p+) 4)
                               +secp256k1-p+)))
      (when (= (mod (* beta beta) +secp256k1-p+) alpha)
        (let ((y (if (eql (oddp beta) odd-y-p)
                     beta
                     (- +secp256k1-p+ beta))))
          (secp256k1-point x y))))))

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

(defun secp256k1-private-key-address (private-key)
  "Derive the Ethereum address for a secp256k1 private key scalar."
  (unless (and (integerp private-key)
               (< 0 private-key)
               (< private-key +secp256k1-n+))
    (error "secp256k1 private key must be in [1, n-1]"))
  (let* ((generator (secp256k1-point +secp256k1-gx+ +secp256k1-gy+))
         (public-point (secp256k1-scalar-multiply private-key generator)))
    (secp256k1-public-key-address
     (concat-bytes
      (integer-to-fixed-bytes (secp256k1-point-x public-point) 32)
      (integer-to-fixed-bytes (secp256k1-point-y public-point) 32)))))

(defun secp256k1-recover-public-key (hash v r s)
  "Recover a 64-byte uncompressed secp256k1 public key body from HASH/V/R/S.
Returns NIL when the signature is invalid or unrecoverable."
  (let ((hash (require-sized-byte-vector hash 32 "secp256k1 hash")))
    (when (secp256k1-valid-signature-values-p v r s)
      (let* ((r-point (secp256k1-decompress-point r (= v 1)))
             (generator (secp256k1-point +secp256k1-gx+ +secp256k1-gy+)))
        (when (and r-point
                   (secp256k1-point-on-curve-p r-point)
                   (null (secp256k1-scalar-multiply +secp256k1-n+ r-point)))
          (let* ((r-inverse (modular-inverse r +secp256k1-n+))
                 (message (bytes-to-integer hash))
                 (u1 (mod (* (- message) r-inverse) +secp256k1-n+))
                 (u2 (mod (* s r-inverse) +secp256k1-n+))
                 (public-point
                   (secp256k1-point-add
                    (secp256k1-scalar-multiply u1 generator)
                    (secp256k1-scalar-multiply u2 r-point))))
            (when (secp256k1-point-on-curve-p public-point)
              (concat-bytes
               (integer-to-fixed-bytes (secp256k1-point-x public-point) 32)
               (integer-to-fixed-bytes (secp256k1-point-y public-point)
                                       32)))))))))

(defun secp256k1-recover-address (hash v r s)
  "Recover the Ethereum address for HASH/V/R/S, or NIL if unrecoverable."
  (let ((public-key (secp256k1-recover-public-key hash v r s)))
    (when public-key
      (secp256k1-public-key-address public-key))))
