(in-package #:ethereum-lisp.evm)

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
