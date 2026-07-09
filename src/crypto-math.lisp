(in-package #:ethereum-lisp.crypto)

(defun integer-to-fixed-bytes (value size)
  (let* ((minimal (integer-to-minimal-bytes value))
         (result (make-byte-vector size))
         (copy-size (min size (length minimal))))
    (replace result
             minimal
             :start1 (- size copy-size)
             :start2 (- (length minimal) copy-size))
    result))

(defun modular-inverse (value modulus)
  (labels ((egcd (a b)
             (if (zerop b)
                 (values a 1 0)
                 (multiple-value-bind (g x y) (egcd b (mod a b))
                   (values g y (- x (* y (floor a b))))))))
    (multiple-value-bind (g x ignored) (egcd (mod value modulus) modulus)
      (declare (ignore ignored))
      (and (= g 1) (mod x modulus)))))

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
