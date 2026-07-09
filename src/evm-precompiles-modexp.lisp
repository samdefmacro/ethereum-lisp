(in-package #:ethereum-lisp.evm)

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
