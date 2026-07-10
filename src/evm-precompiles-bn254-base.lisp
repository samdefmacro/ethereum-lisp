(in-package #:ethereum-lisp.evm.internal)

(defun bn254-modular-inverse (value)
  (labels ((egcd (a b)
             (if (zerop b)
                 (values a 1 0)
                 (multiple-value-bind (g x y) (egcd b (mod a b))
                   (values g y (- x (* (floor a b) y)))))))
    (multiple-value-bind (g x ignored)
        (egcd (mod value +bn254-field-prime+) +bn254-field-prime+)
      (declare (ignore ignored))
      (unless (= g 1)
        (fail "BN254 modular inverse does not exist"))
      (mod x +bn254-field-prime+))))

(defun bn254-valid-coordinate-p (value)
  (< value +bn254-field-prime+))

(defun bn254-on-curve-p (x y)
  (= (mod (* y y) +bn254-field-prime+)
     (mod (+ (* x x x) 3) +bn254-field-prime+)))

(defun parse-bn254-g1-point (bytes gas-used)
  (let* ((bytes (padded-data-slice bytes 0 64))
         (x (bytes-to-integer (subseq bytes 0 32)))
         (y (bytes-to-integer (subseq bytes 32 64))))
    (cond
      ((and (zerop x) (zerop y)) nil)
      ((and (bn254-valid-coordinate-p x)
            (bn254-valid-coordinate-p y)
            (bn254-on-curve-p x y))
       (cons x y))
      (t
       (fail-precompile gas-used "Invalid BN254 G1 point")))))

(defun serialize-bn254-g1-point (point)
  (if point
      (concat-bytes (integer-to-fixed-bytes (car point) 32)
                    (integer-to-fixed-bytes (cdr point) 32))
      (make-byte-vector 64)))

(defun bn254-g1-add (left right)
  (cond
    ((null left) right)
    ((null right) left)
    (t
     (let ((x1 (car left))
           (y1 (cdr left))
           (x2 (car right))
           (y2 (cdr right)))
       (cond
         ((and (= x1 x2)
               (zerop (mod (+ y1 y2) +bn254-field-prime+)))
          nil)
         (t
          (let* ((slope
                   (if (= x1 x2)
                       (mod (* 3 x1 x1
                               (bn254-modular-inverse (* 2 y1)))
                            +bn254-field-prime+)
                       (mod (* (- y2 y1)
                               (bn254-modular-inverse (- x2 x1)))
                            +bn254-field-prime+)))
                 (x3 (mod (- (* slope slope) x1 x2)
                          +bn254-field-prime+))
                 (y3 (mod (- (* slope (- x1 x3)) y1)
                          +bn254-field-prime+)))
            (cons x3 y3))))))))

(defun bn254-g1-mul (point scalar)
  (loop with result = nil
        with addend = point
        for k = scalar then (ash k -1)
        while (plusp k)
        do (when (oddp k)
             (setf result (bn254-g1-add result addend)))
           (setf addend (bn254-g1-add addend addend))
        finally (return result)))

(defun run-bn254-add-precompile (input)
  (let* ((left (parse-bn254-g1-point (padded-data-slice input 0 64)
                                     +bn254-add-gas+))
         (right (parse-bn254-g1-point (padded-data-slice input 64 64)
                                      +bn254-add-gas+)))
    (values (serialize-bn254-g1-point (bn254-g1-add left right))
            +bn254-add-gas+)))

(defun run-bn254-mul-precompile (input)
  (let* ((point (parse-bn254-g1-point (padded-data-slice input 0 64)
                                      +bn254-mul-gas+))
         (scalar (bytes-to-integer (padded-data-slice input 64 32))))
    (values (serialize-bn254-g1-point (bn254-g1-mul point scalar))
            +bn254-mul-gas+)))

(defun bn254-pairing-gas (input)
  (+ +bn254-pairing-base-gas+
     (* +bn254-pairing-per-point-gas+
        (floor (length (ensure-byte-vector input)) 192))))

(defun bn254-fp2 (real imaginary)
  (cons (mod real +bn254-field-prime+)
        (mod imaginary +bn254-field-prime+)))

(defun bn254-fp2-add (left right)
  (bn254-fp2 (+ (car left) (car right))
             (+ (cdr left) (cdr right))))

(defun bn254-fp2-sub (left right)
  (bn254-fp2 (- (car left) (car right))
             (- (cdr left) (cdr right))))

(defun bn254-fp2-mul (left right)
  (let ((a (car left))
        (b (cdr left))
        (c (car right))
        (d (cdr right)))
    (bn254-fp2 (- (* a c) (* b d))
               (+ (* a d) (* b c)))))

(defun bn254-fp2-square (value)
  (bn254-fp2-mul value value))

(defun bn254-fp2-neg (value)
  (bn254-fp2 (- (car value)) (- (cdr value))))

(defun bn254-fp2-double (value)
  (bn254-fp2 (+ (car value) (car value))
             (+ (cdr value) (cdr value))))

(defun bn254-fp2-mul-scalar (value scalar)
  (bn254-fp2 (* (car value) scalar)
             (* (cdr value) scalar)))

(defun bn254-fp2-conjugate (value)
  (bn254-fp2 (car value) (- (cdr value))))

(defun bn254-fp2-zero ()
  (bn254-fp2 0 0))

(defun bn254-fp2-one ()
  (bn254-fp2 1 0))

(defun bn254-fp2-zero-p (value)
  (and (zerop (car value)) (zerop (cdr value))))

(defun bn254-fp2-one-p (value)
  (and (= 1 (car value)) (zerop (cdr value))))

(defun bn254-fp2-mul-xi (value)
  "Multiply VALUE by xi = 9 + i in Fp2."
  (let ((real (car value))
        (imaginary (cdr value)))
    (bn254-fp2 (- (* 9 real) imaginary)
               (+ real (* 9 imaginary)))))

(defun bn254-fp2-inverse (value)
  (let* ((real (car value))
         (imaginary (cdr value))
         (denominator
           (mod (+ (* real real) (* imaginary imaginary))
                +bn254-field-prime+)))
    (when (zerop denominator)
      (fail "BN254 Fp2 inverse does not exist"))
    (let ((inverse (bn254-modular-inverse denominator)))
      (bn254-fp2 (* real inverse)
                 (- (* imaginary inverse))))))
