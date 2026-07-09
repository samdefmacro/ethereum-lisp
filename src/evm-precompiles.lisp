(in-package #:ethereum-lisp.evm)

(defun integer-to-fixed-bytes (value size)
  (let* ((minimal (integer-to-minimal-bytes value))
         (result (make-byte-vector size))
         (copy-size (min size (length minimal))))
    (replace result
             minimal
             :start1 (- size copy-size)
             :start2 (- (length minimal) copy-size))
    result))

(defun u64 (value)
  (logand value +uint64-mask+))

(defun rotr64 (value count)
  (let ((count (mod count 64))
        (value (u64 value)))
    (if (zerop count)
        value
        (u64 (logior (ash value (- count))
                     (ash value (- 64 count)))))))

(defun load-little-endian-u64 (bytes start)
  (loop for i below 8
        sum (ash (aref bytes (+ start i)) (* 8 i))))

(defun store-little-endian-u64 (value bytes start)
  (loop for i below 8
        do (setf (aref bytes (+ start i))
                 (logand #xff (ash value (* -8 i)))))
  bytes)

(defun load-big-endian-u32 (bytes start)
  (loop for i below 4
        sum (ash (aref bytes (+ start i)) (* 8 (- 3 i)))))

(defun modular-expt (base exponent modulus)
  (cond
    ((zerop modulus) 0)
    ((zerop exponent) (mod 1 modulus))
    (t
     (loop with result = 1
           with factor = (mod base modulus)
           for exp = exponent then (ash exp -1)
           while (plusp exp)
           do (when (oddp exp)
                (setf result (mod (* result factor) modulus)))
              (setf factor (mod (* factor factor) modulus))
           finally (return result)))))

(defun modexp-iteration-count (exp-len exp-head)
  (max 1
       (+ (if (> exp-len 32)
              (* (- exp-len 32) +modexp-exp-byte-multiplier+)
              0)
          (let ((bits (integer-length exp-head)))
            (if (plusp bits) (1- bits) 0)))))

(defun modexp-gas (base-len exp-len mod-len exp-head)
  (let* ((max-len (max base-len mod-len))
         (words (ceiling max-len 8))
         (mult-complexity (* words words))
         (iteration-count (modexp-iteration-count exp-len exp-head)))
    (max +modexp-min-gas+
         (floor (* mult-complexity iteration-count)
                +modexp-quad-divisor+))))

(defun modexp-input-shape (input)
  (let* ((base-len (bytes-to-integer (padded-data-slice input 0 32)))
         (exp-len (bytes-to-integer (padded-data-slice input 32 32)))
         (mod-len (bytes-to-integer (padded-data-slice input 64 32)))
         (body (if (> (length input) 96)
                   (subseq input 96)
                   (make-byte-vector 0)))
         (exp-head-size (if (> exp-len 32) 32 exp-len))
         (exp-head (if (plusp exp-head-size)
                       (bytes-to-integer
                        (padded-data-slice body base-len exp-head-size))
                       0))
         (gas (modexp-gas base-len exp-len mod-len exp-head)))
    (values base-len exp-len mod-len body exp-head gas)))

(defun modexp-precompile-required-gas (input)
  (multiple-value-bind (base-len exp-len mod-len body exp-head gas)
      (modexp-input-shape (ensure-byte-vector input))
    (declare (ignore base-len exp-len mod-len body exp-head))
    gas))

(defun run-modexp-precompile (input)
  (multiple-value-bind (base-len exp-len mod-len body exp-head gas)
      (modexp-input-shape input)
    (declare (ignore exp-head))
    (if (and (zerop base-len) (zerop mod-len))
        (values (make-byte-vector 0) gas)
        (let* ((base (bytes-to-integer (padded-data-slice body 0 base-len)))
               (exponent (bytes-to-integer
                          (padded-data-slice body base-len exp-len)))
               (modulus (bytes-to-integer
                         (padded-data-slice body (+ base-len exp-len) mod-len)))
               (value (if (zerop modulus)
                          0
                          (modular-expt base exponent modulus))))
          (values (integer-to-fixed-bytes value mod-len) gas)))))

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

(defun bn254-g2-curve-constant ()
  (let ((inverse-82 (bn254-modular-inverse 82)))
    (bn254-fp2 (* 27 inverse-82)
               (- (* 3 inverse-82)))))

(defun bn254-g2-on-curve-p (x y)
  (let ((left (bn254-fp2-square y))
        (right (bn254-fp2-add
                (bn254-fp2-mul (bn254-fp2-square x) x)
                (bn254-g2-curve-constant))))
    (and (= (car left) (car right))
         (= (cdr left) (cdr right)))))

(defun bn254-g2-add (left right)
  (cond
    ((null left) right)
    ((null right) left)
    (t
     (destructuring-bind (x1 y1) left
       (destructuring-bind (x2 y2) right
         (cond
           ((and (bn254-fp2= x1 x2)
                 (bn254-fp2-negation-p y1 y2))
            nil)
           (t
            (let* ((slope
                     (if (and (bn254-fp2= x1 x2)
                              (bn254-fp2= y1 y2))
                         (bn254-fp2-mul
                          (bn254-fp2-mul (bn254-fp2 3 0)
                                         (bn254-fp2-square x1))
                          (bn254-fp2-inverse
                           (bn254-fp2-mul (bn254-fp2 2 0) y1)))
                         (bn254-fp2-mul
                          (bn254-fp2-sub y2 y1)
                          (bn254-fp2-inverse (bn254-fp2-sub x2 x1)))))
                   (x3 (bn254-fp2-sub
                        (bn254-fp2-sub (bn254-fp2-square slope) x1)
                        x2))
                   (y3 (bn254-fp2-sub
                        (bn254-fp2-mul slope (bn254-fp2-sub x1 x3))
                        y1)))
              (list x3 y3)))))))))

(defun bn254-g2-mul (point scalar)
  (loop with result = nil
        with addend = point
        for k = scalar then (ash k -1)
        while (plusp k)
        do (when (oddp k)
             (setf result (bn254-g2-add result addend)))
           (setf addend (bn254-g2-add addend addend))
        finally (return result)))

(defun bn254-g2-subgroup-p (point)
  (null (bn254-g2-mul point +bn254-curve-order+)))

(defun parse-bn254-g2-pairing-point (bytes gas-used)
  (let ((bytes (padded-data-slice bytes 0 128)))
    (cond
      ((loop for byte across bytes always (zerop byte)) nil)
      (t
       (let ((x-imaginary (bytes-to-integer (subseq bytes 0 32)))
             (x-real (bytes-to-integer (subseq bytes 32 64)))
             (y-imaginary (bytes-to-integer (subseq bytes 64 96)))
             (y-real (bytes-to-integer (subseq bytes 96 128))))
         (unless (and (bn254-valid-coordinate-p x-real)
                      (bn254-valid-coordinate-p x-imaginary)
                      (bn254-valid-coordinate-p y-real)
                      (bn254-valid-coordinate-p y-imaginary))
           (fail-precompile gas-used "Invalid BN254 G2 coordinate"))
         (let ((x (bn254-fp2 x-real x-imaginary))
               (y (bn254-fp2 y-real y-imaginary)))
           (unless (bn254-g2-on-curve-p x y)
             (fail-precompile gas-used "Invalid BN254 G2 point"))
           (let ((point (list x y)))
             (unless (bn254-g2-subgroup-p point)
               (fail-precompile gas-used "Invalid BN254 G2 subgroup"))
             point)))))))

(defun bn254-fp2= (left right)
  (and (= (car left) (car right))
       (= (cdr left) (cdr right))))

(defun bn254-fp2-negation-p (left right)
  (and (zerop (mod (+ (car left) (car right))
                   +bn254-field-prime+))
       (zerop (mod (+ (cdr left) (cdr right))
                   +bn254-field-prime+))))

(defun bn254-fp6 (x y z)
  (list x y z))

(defun bn254-fp6-x (value) (first value))
(defun bn254-fp6-y (value) (second value))
(defun bn254-fp6-z (value) (third value))

(defun bn254-fp6-zero ()
  (bn254-fp6 (bn254-fp2-zero) (bn254-fp2-zero) (bn254-fp2-zero)))

(defun bn254-fp6-one ()
  (bn254-fp6 (bn254-fp2-zero) (bn254-fp2-zero) (bn254-fp2-one)))

(defun bn254-fp6-zero-p (value)
  (and (bn254-fp2-zero-p (bn254-fp6-x value))
       (bn254-fp2-zero-p (bn254-fp6-y value))
       (bn254-fp2-zero-p (bn254-fp6-z value))))

(defun bn254-fp6-one-p (value)
  (and (bn254-fp2-zero-p (bn254-fp6-x value))
       (bn254-fp2-zero-p (bn254-fp6-y value))
       (bn254-fp2-one-p (bn254-fp6-z value))))

(defun bn254-fp6-neg (value)
  (bn254-fp6 (bn254-fp2-neg (bn254-fp6-x value))
             (bn254-fp2-neg (bn254-fp6-y value))
             (bn254-fp2-neg (bn254-fp6-z value))))

(defun bn254-fp6-add (left right)
  (bn254-fp6 (bn254-fp2-add (bn254-fp6-x left) (bn254-fp6-x right))
             (bn254-fp2-add (bn254-fp6-y left) (bn254-fp6-y right))
             (bn254-fp2-add (bn254-fp6-z left) (bn254-fp6-z right))))

(defun bn254-fp6-sub (left right)
  (bn254-fp6 (bn254-fp2-sub (bn254-fp6-x left) (bn254-fp6-x right))
             (bn254-fp2-sub (bn254-fp6-y left) (bn254-fp6-y right))
             (bn254-fp2-sub (bn254-fp6-z left) (bn254-fp6-z right))))

(defun bn254-fp6-double (value)
  (bn254-fp6 (bn254-fp2-double (bn254-fp6-x value))
             (bn254-fp2-double (bn254-fp6-y value))
             (bn254-fp2-double (bn254-fp6-z value))))

(defun bn254-fp6-mul (left right)
  (let* ((v0 (bn254-fp2-mul (bn254-fp6-z left) (bn254-fp6-z right)))
         (v1 (bn254-fp2-mul (bn254-fp6-y left) (bn254-fp6-y right)))
         (v2 (bn254-fp2-mul (bn254-fp6-x left) (bn254-fp6-x right)))
         (tz (bn254-fp2-mul
              (bn254-fp2-add (bn254-fp6-x left) (bn254-fp6-y left))
              (bn254-fp2-add (bn254-fp6-x right) (bn254-fp6-y right))))
         (tz (bn254-fp2-add
              (bn254-fp2-mul-xi (bn254-fp2-sub (bn254-fp2-sub tz v1) v2))
              v0))
         (ty (bn254-fp2-mul
              (bn254-fp2-add (bn254-fp6-y left) (bn254-fp6-z left))
              (bn254-fp2-add (bn254-fp6-y right) (bn254-fp6-z right))))
         (ty (bn254-fp2-add
              (bn254-fp2-sub (bn254-fp2-sub ty v0) v1)
              (bn254-fp2-mul-xi v2)))
         (tx (bn254-fp2-mul
              (bn254-fp2-add (bn254-fp6-x left) (bn254-fp6-z left))
              (bn254-fp2-add (bn254-fp6-x right) (bn254-fp6-z right))))
         (tx (bn254-fp2-sub (bn254-fp2-add (bn254-fp2-sub tx v0) v1) v2)))
    (bn254-fp6 tx ty tz)))

(defun bn254-fp6-square (value)
  (let* ((v0 (bn254-fp2-square (bn254-fp6-z value)))
         (v1 (bn254-fp2-square (bn254-fp6-y value)))
         (v2 (bn254-fp2-square (bn254-fp6-x value)))
         (c0 (bn254-fp2-square
              (bn254-fp2-add (bn254-fp6-x value) (bn254-fp6-y value))))
         (c0 (bn254-fp2-add
              (bn254-fp2-mul-xi (bn254-fp2-sub (bn254-fp2-sub c0 v1) v2))
              v0))
         (c1 (bn254-fp2-square
              (bn254-fp2-add (bn254-fp6-y value) (bn254-fp6-z value))))
         (c1 (bn254-fp2-add
              (bn254-fp2-sub (bn254-fp2-sub c1 v0) v1)
              (bn254-fp2-mul-xi v2)))
         (c2 (bn254-fp2-square
              (bn254-fp2-add (bn254-fp6-x value) (bn254-fp6-z value))))
         (c2 (bn254-fp2-sub (bn254-fp2-add (bn254-fp2-sub c2 v0) v1) v2)))
    (bn254-fp6 c2 c1 c0)))

(defun bn254-fp6-mul-scalar-fp2 (value scalar)
  (bn254-fp6 (bn254-fp2-mul (bn254-fp6-x value) scalar)
             (bn254-fp2-mul (bn254-fp6-y value) scalar)
             (bn254-fp2-mul (bn254-fp6-z value) scalar)))

(defun bn254-fp6-mul-scalar-fp (value scalar)
  (bn254-fp6 (bn254-fp2-mul-scalar (bn254-fp6-x value) scalar)
             (bn254-fp2-mul-scalar (bn254-fp6-y value) scalar)
             (bn254-fp2-mul-scalar (bn254-fp6-z value) scalar)))

(defun bn254-fp6-mul-tau (value)
  (bn254-fp6 (bn254-fp6-y value)
             (bn254-fp6-z value)
             (bn254-fp2-mul-xi (bn254-fp6-x value))))

(defun bn254-fp6-inverse (value)
  (let* ((a (bn254-fp2-sub
             (bn254-fp2-square (bn254-fp6-z value))
             (bn254-fp2-mul-xi
              (bn254-fp2-mul (bn254-fp6-x value) (bn254-fp6-y value)))))
         (b (bn254-fp2-sub
             (bn254-fp2-mul-xi (bn254-fp2-square (bn254-fp6-x value)))
             (bn254-fp2-mul (bn254-fp6-y value) (bn254-fp6-z value))))
         (c (bn254-fp2-sub
             (bn254-fp2-square (bn254-fp6-y value))
             (bn254-fp2-mul (bn254-fp6-x value) (bn254-fp6-z value))))
         (f (bn254-fp2-add
             (bn254-fp2-add
              (bn254-fp2-mul-xi (bn254-fp2-mul c (bn254-fp6-y value)))
              (bn254-fp2-mul a (bn254-fp6-z value)))
             (bn254-fp2-mul-xi (bn254-fp2-mul b (bn254-fp6-x value)))))
         (f-inv (bn254-fp2-inverse f)))
    (bn254-fp6 (bn254-fp2-mul c f-inv)
               (bn254-fp2-mul b f-inv)
               (bn254-fp2-mul a f-inv))))

(defparameter +bn254-xi-to-p-minus-1-over-6+
  (bn254-fp2 8376118865763821496583973867626364092589906065868298776909617916018768340080
             16469823323077808223889137241176536799009286646108169935659301613961712198316))

(defparameter +bn254-xi-to-p-minus-1-over-3+
  (bn254-fp2 21575463638280843010398324269430826099269044274347216827212613867836435027261
             10307601595873709700152284273816112264069230130616436755625194854815875713954))

(defparameter +bn254-xi-to-p-minus-1-over-2+
  (bn254-fp2 2821565182194536844548159561693502659359617185244120367078079554186484126554
             3505843767911556378687030309984248845540243509899259641013678093033130930403))

(defparameter +bn254-xi-to-p-squared-minus-1-over-3+
  21888242871839275220042445260109153167277707414472061641714758635765020556616)

(defparameter +bn254-xi-to-2p-squared-minus-2-over-3+
  2203960485148121921418603742825762020974279258880205651966)

(defparameter +bn254-xi-to-p-squared-minus-1-over-6+
  21888242871839275220042445260109153167277707414472061641714758635765020556617)

(defparameter +bn254-xi-to-2p-minus-2-over-3+
  (bn254-fp2 2581911344467009335267311115468803099551665605076196740867805258568234346338
             19937756971775647987995932169929341994314640652964949448313374472400716661030))

(defun bn254-fp6-frobenius (value)
  (bn254-fp6
   (bn254-fp2-mul
    (bn254-fp2-conjugate (bn254-fp6-x value))
    +bn254-xi-to-2p-minus-2-over-3+)
   (bn254-fp2-mul
    (bn254-fp2-conjugate (bn254-fp6-y value))
    +bn254-xi-to-p-minus-1-over-3+)
   (bn254-fp2-conjugate (bn254-fp6-z value))))

(defun bn254-fp6-frobenius-p2 (value)
  (bn254-fp6
   (bn254-fp2-mul-scalar (bn254-fp6-x value)
                         +bn254-xi-to-2p-squared-minus-2-over-3+)
   (bn254-fp2-mul-scalar (bn254-fp6-y value)
                         +bn254-xi-to-p-squared-minus-1-over-3+)
   (bn254-fp6-z value)))

(defun bn254-fp12 (x y)
  (list x y))

(defun bn254-fp12-x (value) (first value))
(defun bn254-fp12-y (value) (second value))

(defun bn254-fp12-one ()
  (bn254-fp12 (bn254-fp6-zero) (bn254-fp6-one)))

(defun bn254-fp12-one-p (value)
  (and (bn254-fp6-zero-p (bn254-fp12-x value))
       (bn254-fp6-one-p (bn254-fp12-y value))))

(defun bn254-fp12-conjugate (value)
  (bn254-fp12 (bn254-fp6-neg (bn254-fp12-x value))
              (bn254-fp12-y value)))

(defun bn254-fp12-mul (left right)
  (let* ((tx (bn254-fp6-add
              (bn254-fp6-mul (bn254-fp12-x left) (bn254-fp12-y right))
              (bn254-fp6-mul (bn254-fp12-x right) (bn254-fp12-y left))))
         (ty (bn254-fp6-add
              (bn254-fp6-mul (bn254-fp12-y left) (bn254-fp12-y right))
              (bn254-fp6-mul-tau
               (bn254-fp6-mul (bn254-fp12-x left) (bn254-fp12-x right))))))
    (bn254-fp12 tx ty)))

(defun bn254-fp12-mul-scalar-fp6 (value scalar)
  (bn254-fp12 (bn254-fp6-mul (bn254-fp12-x value) scalar)
              (bn254-fp6-mul (bn254-fp12-y value) scalar)))

(defun bn254-fp12-square (value)
  (let* ((v0 (bn254-fp6-mul (bn254-fp12-x value) (bn254-fp12-y value)))
         (tau-term (bn254-fp6-add (bn254-fp6-mul-tau (bn254-fp12-x value))
                                  (bn254-fp12-y value)))
         (ty (bn254-fp6-mul
              (bn254-fp6-add (bn254-fp12-x value) (bn254-fp12-y value))
              tau-term))
         (ty (bn254-fp6-sub
              (bn254-fp6-sub ty v0)
              (bn254-fp6-mul-tau v0))))
    (bn254-fp12 (bn254-fp6-double v0) ty)))

(defun bn254-fp12-inverse (value)
  (let* ((t1 (bn254-fp6-mul-tau
              (bn254-fp6-square (bn254-fp12-x value))))
         (t2 (bn254-fp6-square (bn254-fp12-y value)))
         (inv (bn254-fp6-inverse (bn254-fp6-sub t2 t1))))
    (bn254-fp12-mul-scalar-fp6
     (bn254-fp12 (bn254-fp6-neg (bn254-fp12-x value))
                 (bn254-fp12-y value))
     inv)))

(defun bn254-fp12-exp (value power)
  (loop with result = (bn254-fp12-one)
        for i from (1- (integer-length power)) downto 0
        do (setf result (bn254-fp12-square result))
           (when (logbitp i power)
             (setf result (bn254-fp12-mul result value)))
        finally (return result)))

(defun bn254-fp12-frobenius (value)
  (bn254-fp12
   (bn254-fp6-mul-scalar-fp2
    (bn254-fp6-frobenius (bn254-fp12-x value))
    +bn254-xi-to-p-minus-1-over-6+)
   (bn254-fp6-frobenius (bn254-fp12-y value))))

(defun bn254-fp12-frobenius-p2 (value)
  (bn254-fp12
   (bn254-fp6-mul-scalar-fp
    (bn254-fp6-frobenius-p2 (bn254-fp12-x value))
    +bn254-xi-to-p-squared-minus-1-over-6+)
   (bn254-fp6-frobenius-p2 (bn254-fp12-y value))))

(defun bn254-twist-point (x y z tt)
  (list x y z tt))

(defun bn254-twist-x (point) (first point))
(defun bn254-twist-y (point) (second point))
(defun bn254-twist-z (point) (third point))
(defun bn254-twist-t (point) (fourth point))

(defun bn254-twist-affine (point)
  (destructuring-bind (x y) point
    (bn254-twist-point x y (bn254-fp2-one) (bn254-fp2-one))))

(defun bn254-twist-neg (point)
  (bn254-twist-point (bn254-twist-x point)
                     (bn254-fp2-neg (bn254-twist-y point))
                     (bn254-twist-z point)
                     (bn254-fp2-zero)))

(defun bn254-line-function-add (r p q r2)
  (let* ((b (bn254-fp2-mul (bn254-twist-x p) (bn254-twist-t r)))
         (d (bn254-fp2-square
             (bn254-fp2-add (bn254-twist-y p) (bn254-twist-z r))))
         (d (bn254-fp2-mul
             (bn254-fp2-sub
              (bn254-fp2-sub d r2)
              (bn254-twist-t r))
             (bn254-twist-t r)))
         (h (bn254-fp2-sub b (bn254-twist-x r)))
         (i (bn254-fp2-square h))
         (e (bn254-fp2-double (bn254-fp2-double i)))
         (j (bn254-fp2-mul h e))
         (l1 (bn254-fp2-sub
              (bn254-fp2-sub d (bn254-twist-y r))
              (bn254-twist-y r)))
         (v (bn254-fp2-mul (bn254-twist-x r) e))
         (out-x (bn254-fp2-sub
                 (bn254-fp2-sub
                  (bn254-fp2-sub (bn254-fp2-square l1) j)
                  v)
                 v))
         (out-z (bn254-fp2-sub
                 (bn254-fp2-sub
                  (bn254-fp2-square
                   (bn254-fp2-add (bn254-twist-z r) h))
                  (bn254-twist-t r))
                 i))
         (out-y (bn254-fp2-sub
                 (bn254-fp2-mul l1 (bn254-fp2-sub v out-x))
                 (bn254-fp2-double (bn254-fp2-mul (bn254-twist-y r) j))))
         (out-t (bn254-fp2-square out-z))
         (line-temp (bn254-fp2-square (bn254-fp2-add (bn254-twist-y p) out-z)))
         (line-temp (bn254-fp2-sub (bn254-fp2-sub line-temp r2) out-t))
         (t2 (bn254-fp2-double (bn254-fp2-mul l1 (bn254-twist-x p))))
         (a (bn254-fp2-sub t2 line-temp))
         (c (bn254-fp2-double (bn254-fp2-mul-scalar out-z (cdr q))))
         (line-b (bn254-fp2-double
                  (bn254-fp2-mul-scalar (bn254-fp2-neg l1) (car q)))))
    (values a line-b c (bn254-twist-point out-x out-y out-z out-t))))

(defun bn254-line-function-double (r q)
  (let* ((a0 (bn254-fp2-square (bn254-twist-x r)))
         (b0 (bn254-fp2-square (bn254-twist-y r)))
         (c0 (bn254-fp2-square b0))
         (d (bn254-fp2-square (bn254-fp2-add (bn254-twist-x r) b0)))
         (d (bn254-fp2-double (bn254-fp2-sub (bn254-fp2-sub d a0) c0)))
         (e (bn254-fp2-add (bn254-fp2-double a0) a0))
         (g (bn254-fp2-square e))
         (out-x (bn254-fp2-sub (bn254-fp2-sub g d) d))
         (out-z (bn254-fp2-sub
                 (bn254-fp2-sub
                  (bn254-fp2-square
                   (bn254-fp2-add (bn254-twist-y r) (bn254-twist-z r)))
                  b0)
                 (bn254-twist-t r)))
         (out-y (bn254-fp2-sub
                 (bn254-fp2-mul (bn254-fp2-sub d out-x) e)
                 (bn254-fp2-double
                  (bn254-fp2-double (bn254-fp2-double c0)))))
         (out-t (bn254-fp2-square out-z))
         (line-temp (bn254-fp2-double (bn254-fp2-mul e (bn254-twist-t r))))
         (line-b (bn254-fp2-mul-scalar (bn254-fp2-neg line-temp) (car q)))
         (line-a (bn254-fp2-sub
                  (bn254-fp2-sub
                   (bn254-fp2-square (bn254-fp2-add (bn254-twist-x r) e))
                   a0)
                  g))
         (line-a (bn254-fp2-sub line-a (bn254-fp2-double (bn254-fp2-double b0))))
         (line-c (bn254-fp2-mul-scalar
                  (bn254-fp2-double
                   (bn254-fp2-mul out-z (bn254-twist-t r)))
                  (cdr q))))
    (values line-a line-b line-c
            (bn254-twist-point out-x out-y out-z out-t))))

(defun bn254-fp12-mul-line (value a b c)
  (let* ((a2 (bn254-fp6 (bn254-fp2-zero) a b))
         (a2 (bn254-fp6-mul a2 (bn254-fp12-x value)))
         (t3 (bn254-fp6-mul-scalar-fp2 (bn254-fp12-y value) c))
         (line-temp (bn254-fp2-add b c))
         (t2 (bn254-fp6 (bn254-fp2-zero) a line-temp))
         (x (bn254-fp6-add (bn254-fp12-x value) (bn254-fp12-y value)))
         (x (bn254-fp6-sub (bn254-fp6-sub (bn254-fp6-mul x t2) a2) t3))
         (y (bn254-fp6-add t3 (bn254-fp6-mul-tau a2))))
    (bn254-fp12 x y)))

(defparameter +bn254-six-u-plus-2-naf+
  #(0 0 0 1 0 1 0 -1 0 0 1 -1 0 0 1 0
    0 1 1 0 -1 0 0 1 0 -1 0 0 0 0 1 1
    1 0 0 -1 0 0 1 0 0 0 0 0 -1 0 0 1
    1 0 0 -1 0 0 0 1 1 0 -1 0 0 1 0 1 1))

(defun bn254-miller (g2 g1)
  (let* ((a-affine (bn254-twist-affine g2))
         (minus-a (bn254-twist-neg a-affine))
         (r a-affine)
         (r2 (bn254-fp2-square (bn254-twist-y a-affine)))
         (ret (bn254-fp12-one))
         (last-index (1- (length +bn254-six-u-plus-2-naf+))))
    (loop for i from last-index downto 1
          do (progn
               (multiple-value-bind (a b c next-r)
                   (bn254-line-function-double r g1)
                 (unless (= i last-index)
                   (setf ret (bn254-fp12-square ret)))
                 (setf ret (bn254-fp12-mul-line ret a b c))
                 (setf r next-r))
               (case (aref +bn254-six-u-plus-2-naf+ (1- i))
                 (1
                  (multiple-value-bind (a b c next-r)
                      (bn254-line-function-add r a-affine g1 r2)
                    (setf ret (bn254-fp12-mul-line ret a b c))
                    (setf r next-r)))
                 (-1
                  (multiple-value-bind (a b c next-r)
                      (bn254-line-function-add r minus-a g1 r2)
                    (setf ret (bn254-fp12-mul-line ret a b c))
                    (setf r next-r))))))
    (let* ((q1 (bn254-twist-point
                (bn254-fp2-mul
                 (bn254-fp2-conjugate (bn254-twist-x a-affine))
                 +bn254-xi-to-p-minus-1-over-3+)
                (bn254-fp2-mul
                 (bn254-fp2-conjugate (bn254-twist-y a-affine))
                 +bn254-xi-to-p-minus-1-over-2+)
                (bn254-fp2-one)
                (bn254-fp2-one)))
           (minus-q2 (bn254-twist-point
                      (bn254-fp2-mul-scalar
                       (bn254-twist-x a-affine)
                       +bn254-xi-to-p-squared-minus-1-over-3+)
                      (bn254-twist-y a-affine)
                      (bn254-fp2-one)
                      (bn254-fp2-one))))
      (multiple-value-bind (a b c next-r)
          (bn254-line-function-add r q1 g1 (bn254-fp2-square (bn254-twist-y q1)))
        (setf ret (bn254-fp12-mul-line ret a b c))
        (setf r next-r))
      (multiple-value-bind (a b c next-r)
          (bn254-line-function-add
           r minus-q2 g1 (bn254-fp2-square (bn254-twist-y minus-q2)))
        (declare (ignore next-r))
        (setf ret (bn254-fp12-mul-line ret a b c))))
    ret))

(defun bn254-final-exponentiation (value)
  (let* ((t1 (bn254-fp12-conjugate value))
         (inv (bn254-fp12-inverse value))
         (t1 (bn254-fp12-mul t1 inv))
         (t2 (bn254-fp12-frobenius-p2 t1))
         (t1 (bn254-fp12-mul t1 t2))
         (fp (bn254-fp12-frobenius t1))
         (fp2 (bn254-fp12-frobenius-p2 t1))
         (fp3 (bn254-fp12-frobenius fp2))
         (fu (bn254-fp12-exp t1 4965661367192848881))
         (fu2 (bn254-fp12-exp fu 4965661367192848881))
         (fu3 (bn254-fp12-exp fu2 4965661367192848881))
         (y3 (bn254-fp12-frobenius fu))
         (fu2p (bn254-fp12-frobenius fu2))
         (fu3p (bn254-fp12-frobenius fu3))
         (y2 (bn254-fp12-frobenius-p2 fu2))
         (y0 (bn254-fp12-mul (bn254-fp12-mul fp fp2) fp3))
         (y1 (bn254-fp12-conjugate t1))
         (y5 (bn254-fp12-conjugate fu2))
         (y3 (bn254-fp12-conjugate y3))
         (y4 (bn254-fp12-conjugate (bn254-fp12-mul fu fu2p)))
         (y6 (bn254-fp12-conjugate (bn254-fp12-mul fu3 fu3p)))
         (t0 (bn254-fp12-square y6))
         (t0 (bn254-fp12-mul (bn254-fp12-mul t0 y4) y5))
         (t1 (bn254-fp12-mul (bn254-fp12-mul y3 y5) t0))
         (t0 (bn254-fp12-mul t0 y2))
         (t1 (bn254-fp12-square t1))
         (t1 (bn254-fp12-mul t1 t0))
         (t1 (bn254-fp12-square t1))
         (t0 (bn254-fp12-mul t1 y1))
         (t1 (bn254-fp12-mul t1 y0))
         (t0 (bn254-fp12-square t0)))
    (bn254-fp12-mul t0 t1)))

(defun bn254-optimal-ate-pairing-check (pairs)
  "Return true when the product of all BN254 pairings equals one."
  (let ((acc (bn254-fp12-one)))
    (dolist (pair pairs)
      (destructuring-bind (g1 g2) pair
        (setf acc (bn254-fp12-mul acc (bn254-miller g2 g1)))))
    (bn254-fp12-one-p (bn254-final-exponentiation acc))))

(defun bn254-g1= (left right)
  (and (= (car left) (car right))
       (= (cdr left) (cdr right))))

(defun bn254-g1-negation-p (left right)
  (and (= (car left) (car right))
       (zerop (mod (+ (cdr left) (cdr right))
                   +bn254-field-prime+))))

(defun bn254-g2= (left right)
  (and (bn254-fp2= (first left) (first right))
       (bn254-fp2= (second left) (second right))))

(defun bn254-g2-negation-p (left right)
  (and (bn254-fp2= (first left) (first right))
       (bn254-fp2-negation-p (second left) (second right))))

(defun bn254-pairing-cancel-p (left right)
  (destructuring-bind (left-g1 left-g2) left
    (destructuring-bind (right-g1 right-g2) right
      (or (and (bn254-g2= left-g2 right-g2)
               (bn254-g1-negation-p left-g1 right-g1))
          (and (bn254-g1= left-g1 right-g1)
               (bn254-g2-negation-p left-g2 right-g2))))))

(defun bn254-pairing-cancellation-model-check (pairs)
  "Stopgap BN254 pairing backend covering obvious inverse-pair products.

The real precompile requires an optimal Ate pairing check. This model exists as
an explicit backend boundary so the parsing, gas, and validation shell can be
kept stable while a library-backed pairing implementation is wired in."
  (labels ((remove-one-cancel (remaining)
             (cond
               ((null remaining) nil)
               (t
                (let ((head (first remaining))
                      (tail (rest remaining)))
                  (loop for candidate in tail
                        for index from 0
                        when (bn254-pairing-cancel-p head candidate)
                          do (return
                               (append (subseq tail 0 index)
                                       (subseq tail (1+ index))))
                        finally (return :no-cancel)))))))
    (loop with remaining = pairs
          until (null remaining)
          for next = (remove-one-cancel remaining)
          when (eq next :no-cancel)
            do (return nil)
          do (setf remaining next)
          finally (return t))))

(defvar *bn254-pairing-checker* #'bn254-optimal-ate-pairing-check
  "Callable used for non-zero BN254 pairing products after point validation.")

(defun bn254-pairing-check (pairs)
  (funcall *bn254-pairing-checker* pairs))

(defun true32-byte-vector ()
  (let ((output (make-byte-vector 32)))
    (setf (aref output 31) 1)
    output))

(defun false32-byte-vector ()
  (make-byte-vector 32))

(defun run-bn254-pairing-precompile (input)
  (let ((gas (bn254-pairing-gas input)))
    (cond
      ((not (zerop (mod (length input) 192)))
       (fail-precompile gas "Invalid BN254 pairing input size"))
      ((zerop (length input))
       (values (true32-byte-vector) gas))
      (t
       (let ((pairs
               (loop for offset from 0 below (length input) by 192
                     for g1 = (parse-bn254-g1-point
                               (subseq input offset (+ offset 64))
                               gas)
                     for g2 = (parse-bn254-g2-pairing-point
                               (subseq input (+ offset 64) (+ offset 192))
                               gas)
                     when (and g1 g2)
                       collect (list g1 g2))))
         (values (if (bn254-pairing-check pairs)
                     (true32-byte-vector)
                     (false32-byte-vector))
                 gas))))))

(defun kzg-point-evaluation-return-value ()
  (concat-bytes
   (integer-to-fixed-bytes +bls-field-elements-per-blob+ 32)
   (integer-to-fixed-bytes +bls-field-modulus+ 32)))

(defun run-kzg-point-evaluation-precompile (input)
  (let ((input (ensure-byte-vector input))
        (gas +kzg-point-evaluation-gas+))
    (unless (= (length input) +kzg-point-evaluation-input-size+)
      (fail-precompile gas "Invalid KZG point evaluation input length"))
    (let* ((versioned-hash (subseq input 0 32))
           (z (subseq input 32 64))
           (y (subseq input 64 96))
           (commitment (subseq input 96 144))
           (proof (subseq input 144 192))
           (computed-versioned-hash
             (hash32-bytes (kzg-commitment-to-versioned-hash commitment))))
      (unless (bytes= versioned-hash computed-versioned-hash)
        (fail-precompile gas "Mismatched KZG commitment versioned hash"))
      (handler-case
          (progn
            (verify-kzg-point-proof commitment z y proof)
            (values (kzg-point-evaluation-return-value) gas))
        (error (condition)
          (fail-precompile gas "~A" condition))))))

(defun blake2b-mix (v a b c d x y)
  (setf (aref v a) (u64 (+ (aref v a) (aref v b) x))
        (aref v d) (rotr64 (logxor (aref v d) (aref v a)) 32)
        (aref v c) (u64 (+ (aref v c) (aref v d)))
        (aref v b) (rotr64 (logxor (aref v b) (aref v c)) 24)
        (aref v a) (u64 (+ (aref v a) (aref v b) y))
        (aref v d) (rotr64 (logxor (aref v d) (aref v a)) 16)
        (aref v c) (u64 (+ (aref v c) (aref v d)))
        (aref v b) (rotr64 (logxor (aref v b) (aref v c)) 63)))

(defun run-blake2f-precompile (input)
  (let ((input (ensure-byte-vector input)))
    (unless (= (length input) +blake2f-input-size+)
      (fail-precompile +precompile-consume-all-child-gas+
                       "BLAKE2F invalid input length"))
    (let ((rounds (load-big-endian-u32 input 0))
          (h (make-array 8))
          (m (make-array 16))
          (v (make-array 16))
          (t0 (load-little-endian-u64 input 196))
          (t1 (load-little-endian-u64 input 204))
          (final-p (= (aref input 212) 1)))
      (unless (member (aref input 212) '(0 1) :test #'=)
        (fail-precompile +precompile-consume-all-child-gas+
                         "BLAKE2F invalid final flag"))
      (dotimes (i 8)
        (setf (aref h i) (load-little-endian-u64 input (+ 4 (* i 8)))
              (aref v i) (aref h i)
              (aref v (+ i 8)) (aref +blake2b-iv+ i)))
      (dotimes (i 16)
        (setf (aref m i) (load-little-endian-u64 input (+ 68 (* i 8)))))
      (setf (aref v 12) (logxor (aref v 12) t0)
            (aref v 13) (logxor (aref v 13) t1))
      (when final-p
        (setf (aref v 14) (logxor (aref v 14) +uint64-mask+)))
      (dotimes (round rounds)
        (let ((s (aref +blake2b-sigma+ (mod round 10))))
          (blake2b-mix v 0 4 8 12
                       (aref m (aref s 0)) (aref m (aref s 1)))
          (blake2b-mix v 1 5 9 13
                       (aref m (aref s 2)) (aref m (aref s 3)))
          (blake2b-mix v 2 6 10 14
                       (aref m (aref s 4)) (aref m (aref s 5)))
          (blake2b-mix v 3 7 11 15
                       (aref m (aref s 6)) (aref m (aref s 7)))
          (blake2b-mix v 0 5 10 15
                       (aref m (aref s 8)) (aref m (aref s 9)))
          (blake2b-mix v 1 6 11 12
                       (aref m (aref s 10)) (aref m (aref s 11)))
          (blake2b-mix v 2 7 8 13
                       (aref m (aref s 12)) (aref m (aref s 13)))
          (blake2b-mix v 3 4 9 14
                       (aref m (aref s 14)) (aref m (aref s 15)))))
      (let ((output (make-byte-vector 64)))
        (dotimes (i 8)
          (store-little-endian-u64
           (logxor (aref h i) (aref v i) (aref v (+ i 8)))
           output
           (* i 8)))
        (values output rounds)))))

(defun blake2f-precompile-required-gas (input)
  (let ((input (ensure-byte-vector input)))
    (when (and (= (length input) +blake2f-input-size+)
               (member (aref input 212) '(0 1) :test #'=))
      (load-big-endian-u32 input 0))))

(defun ensure-precompile-upfront-gas (address input rules child-gas-limit)
  (case (address-to-word address)
    (5
     (when (active-precompile-address-number-p 5 rules)
       (let ((required-gas (modexp-precompile-required-gas input)))
         (when (> required-gas child-gas-limit)
           (fail "Precompile out of gas")))))
    (9
     (when (active-precompile-address-number-p 9 rules)
       (let ((required-gas (blake2f-precompile-required-gas input)))
         (when (and required-gas (> required-gas child-gas-limit))
           (fail "Precompile out of gas")))))))

(defun all-zero-bytes-p (bytes start end)
  (loop for i from start below end
        always (zerop (aref bytes i))))

(defun run-ecrecover-precompile (input)
  (let* ((padded (padded-data-slice input 0 128))
         (v-byte (aref padded 63))
         (v (- v-byte 27))
         (r (bytes-to-integer (subseq padded 64 96)))
         (s (bytes-to-integer (subseq padded 96 128))))
    (let ((address
            (and (all-zero-bytes-p padded 32 63)
                 (secp256k1-recover-address (subseq padded 0 32) v r s))))
      (if address
          (let ((output (make-byte-vector 32)))
            (replace output (address-bytes address) :start1 12)
            (values output +ecrecover-gas+))
          (values (make-byte-vector 0) +ecrecover-gas+)))))

(defun precompile-word-count (input)
  (ceiling (length (ensure-byte-vector input)) 32))

(defun run-precompile (address input &optional rules)
  (let ((input (ensure-byte-vector input)))
    (case (address-to-word address)
      (1 (if (active-precompile-address-number-p 1 rules)
             (multiple-value-bind (output gas) (run-ecrecover-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (2 (if (active-precompile-address-number-p 2 rules)
             (values (sha256 input)
                     (+ +sha256-base-gas+
                        (* +sha256-word-gas+ (precompile-word-count input)))
                     t)
             (values nil 0 nil)))
      (3 (if (active-precompile-address-number-p 3 rules)
             (let ((output (make-byte-vector 32)))
               (replace output (ripemd160 input) :start1 12)
               (values output
                       (+ +ripemd160-base-gas+
                          (* +ripemd160-word-gas+
                             (precompile-word-count input)))
                       t))
             (values nil 0 nil)))
      (5 (if (active-precompile-address-number-p 5 rules)
             (multiple-value-bind (output gas) (run-modexp-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (6 (if (active-precompile-address-number-p 6 rules)
             (multiple-value-bind (output gas) (run-bn254-add-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (7 (if (active-precompile-address-number-p 7 rules)
             (multiple-value-bind (output gas) (run-bn254-mul-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (8 (if (active-precompile-address-number-p 8 rules)
             (multiple-value-bind (output gas)
                 (run-bn254-pairing-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (9 (if (active-precompile-address-number-p 9 rules)
             (multiple-value-bind (output gas) (run-blake2f-precompile input)
               (values output gas t))
             (values nil 0 nil)))
      (10 (if (active-precompile-address-number-p 10 rules)
              (multiple-value-bind (output gas)
                  (run-kzg-point-evaluation-precompile input)
                (values output gas t))
              (values nil 0 nil)))
      (4 (if (active-precompile-address-number-p 4 rules)
             (values (subseq input 0)
                     (+ +identity-base-gas+
                        (* +identity-word-gas+ (precompile-word-count input)))
                     t)
             (values nil 0 nil)))
      (otherwise (values nil 0 nil)))))
