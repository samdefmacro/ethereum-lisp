(in-package #:ethereum-lisp.evm.internal)

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

(defun modexp-iteration-count (exp-len exp-head exp-byte-multiplier)
  (max 1
       (+ (if (> exp-len 32)
              (* (- exp-len 32) exp-byte-multiplier)
              0)
          (let ((bits (integer-length exp-head)))
            (if (plusp bits) (1- bits) 0)))))

(defun modexp-eip198-multiplication-complexity (length)
  (cond
    ((<= length 64)
     (* length length))
    ((<= length 1024)
     (+ (floor (* length length) 4)
        (* 96 length)
        -3072))
    (t
     (+ (floor (* length length) 16)
        (* 480 length)
        -199680))))

(defun modexp-eip2565-multiplication-complexity (length)
  (let ((words (ceiling length 8)))
    (* words words)))

(defun modexp-eip7883-multiplication-complexity (length)
  (if (<= length 32)
      16
      (* +modexp-eip7883-large-length-multiplier+
         (modexp-eip2565-multiplication-complexity length))))

(defun modexp-osaka-p (rules)
  (or (null rules)
      (chain-rules-osaka-p rules)))

(defun modexp-gas (base-len exp-len mod-len exp-head &optional rules)
  (let ((max-len (max base-len mod-len)))
    (cond
      ((modexp-osaka-p rules)
       (max +modexp-eip7883-min-gas+
            (* (modexp-eip7883-multiplication-complexity max-len)
               (modexp-iteration-count
                exp-len exp-head +modexp-eip7883-exp-byte-multiplier+))))
      ((chain-rules-berlin-p rules)
       (max +modexp-eip2565-min-gas+
            (floor
             (* (modexp-eip2565-multiplication-complexity max-len)
                (modexp-iteration-count
                 exp-len exp-head +modexp-eip2565-exp-byte-multiplier+))
             +modexp-eip2565-quad-divisor+)))
      (t
       (floor
        (* (modexp-eip198-multiplication-complexity max-len)
           (modexp-iteration-count
            exp-len exp-head +modexp-eip2565-exp-byte-multiplier+))
        +modexp-eip198-quad-divisor+)))))

(defun validate-modexp-input-lengths (base-len exp-len mod-len rules)
  (when (and (modexp-osaka-p rules)
             (or (> base-len +modexp-osaka-max-input-length+)
                 (> exp-len +modexp-osaka-max-input-length+)
                 (> mod-len +modexp-osaka-max-input-length+)))
    (fail-precompile
     +precompile-consume-all-child-gas+
     "MODEXP input length exceeds the Osaka limit")))

(defun modexp-input-shape (input &optional rules)
  (let* ((input (ensure-byte-vector input))
         (base-len (bytes-to-integer (padded-data-slice input 0 32)))
         (exp-len (bytes-to-integer (padded-data-slice input 32 32)))
         (mod-len (bytes-to-integer (padded-data-slice input 64 32))))
    (validate-modexp-input-lengths base-len exp-len mod-len rules)
    (let* ((body (if (> (length input) 96)
                     (subseq input 96)
                     (make-byte-vector 0)))
           (exp-head-size (if (> exp-len 32) 32 exp-len))
           (exp-head (if (plusp exp-head-size)
                         (bytes-to-integer
                          (padded-data-slice body base-len exp-head-size))
                         0))
           (gas (modexp-gas base-len exp-len mod-len exp-head rules)))
      (values base-len exp-len mod-len body exp-head gas))))

(defun modexp-precompile-required-gas (input &optional rules)
  (multiple-value-bind (base-len exp-len mod-len body exp-head gas)
      (modexp-input-shape input rules)
    (declare (ignore base-len exp-len mod-len body exp-head))
    gas))

(defun run-modexp-precompile (input &optional rules)
  (multiple-value-bind (base-len exp-len mod-len body exp-head gas)
      (modexp-input-shape input rules)
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
