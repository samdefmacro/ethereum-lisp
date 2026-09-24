(in-package #:ethereum-lisp.evm.internal)

(defun word (value)
  ;; Every stack push reduces its value; a non-negative fixnum is already a
  ;; word, and skipping the bignum MOD for it keeps pushes allocation-free.
  ;; A bignum already below 2^256 (a PUSH32 immediate, an MLOAD result) is
  ;; returned as well: MOD would divide and allocate a copy of it.
  (cond ((typep value '(and fixnum unsigned-byte)) value)
        ((and (typep value 'unsigned-byte) (< value +word-modulus+)) value)
        (t (mod value +word-modulus+))))

(defun fail (control &rest args)
  (error 'evm-error :message (apply #'format nil control args)))

(defun context-fork-enabled-p (context predicate)
  (let ((rules (and context (evm-context-chain-rules context))))
    (or (null rules) (funcall predicate rules))))

(defun require-context-fork (context predicate fork-name opcode pc)
  (unless (context-fork-enabled-p context predicate)
    (fail "~A requires the ~A fork at pc ~D" opcode fork-name pc)))

(defun fail-precompile (gas-used control &rest args)
  (error 'evm-precompile-error
         :message (apply #'format nil control args)
         :gas-used gas-used))

(defun amsterdam-execution-available-p ()
  "Return whether every consensus-critical Amsterdam EVM rule is implemented.

Amsterdam execution is NOT yet available: EIP-2780, EIP-7778, EIP-7976, and
EIP-7981 are unimplemented, the EIP-8037/EIP-8038 system-call gas accounting is
still stale, and EIP-8246 is incomplete.  Until all of those land on the
execution path this must stay NIL.

This is purely a capability boundary the Engine API consults to advertise and
dispatch the Amsterdam payload methods; refusing them is safer than executing a
payload with an older fork's semantics.  It is deliberately decoupled from
CHAIN-RULES-AMSTERDAM-P, which gates execution -- do not conflate the two."
  nil)

(defun modexp-word (base exponent)
  (let ((result 1)
        (base (word base))
        (exponent exponent))
    (loop while (plusp exponent)
          do (when (oddp exponent)
               (setf result (word (* result base))))
             (setf exponent (ash exponent -1)
                   base (word (* base base))))
    result))

(defun signed-word (value)
  (if (>= value (expt 2 255))
      (- value +word-modulus+)
      value))

(defun signed-divide-word (dividend divisor)
  (if (zerop divisor)
      0
      (let* ((a (signed-word dividend))
             (b (signed-word divisor))
             (quotient (floor (abs a) (abs b))))
        (word (if (eql (minusp a) (minusp b))
                  quotient
                  (- quotient))))))

(defun signed-mod-word (dividend divisor)
  (if (zerop divisor)
      0
      (let* ((a (signed-word dividend))
             (b (signed-word divisor))
             (remainder (mod (abs a) (abs b))))
        (word (if (minusp a) (- remainder) remainder)))))

(defun signextend-word (byte-index value)
  (if (>= byte-index 32)
      value
      (let* ((bit-index (+ (* 8 byte-index) 7))
             (sign-bit (ash 1 bit-index))
             (mask (1- (ash 1 (1+ bit-index)))))
        (if (zerop (logand value sign-bit))
            (logand value mask)
            (logior value (logxor mask (1- +word-modulus+)))))))

(defun arithmetic-shift-right-word (shift value)
  (let ((signed (signed-word value)))
    (word (if (>= shift 256)
              (if (minusp signed) -1 0)
              (ash signed (- shift))))))
