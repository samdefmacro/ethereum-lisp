(in-package #:ethereum-lisp.evm.internal)

(defun word (value)
  (mod value +word-modulus+))

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

(defvar *evm-stack-depth-cell* nil
  "Dynamically bound to the current machine's mutable stack-depth cell.")

(defun stack-push (stack value)
  (when (>= (if *evm-stack-depth-cell*
                (car *evm-stack-depth-cell*)
                (length stack))
            +stack-limit+)
    (fail "EVM stack overflow"))
  (when *evm-stack-depth-cell*
    (incf (car *evm-stack-depth-cell*)))
  (cons (word value) stack))

(defun pop1 (stack)
  (if stack
      (progn
        (when *evm-stack-depth-cell*
          (decf (car *evm-stack-depth-cell*)))
        (values (first stack) (rest stack)))
      (fail "EVM stack underflow")))

(defun pop2 (stack)
  (multiple-value-bind (a stack) (pop1 stack)
    (multiple-value-bind (b stack) (pop1 stack)
      (values a b stack))))

(defun pop3 (stack)
  (multiple-value-bind (a stack) (pop1 stack)
    (multiple-value-bind (b stack) (pop1 stack)
      (multiple-value-bind (c stack) (pop1 stack)
        (values a b c stack)))))

(defun pop6 (stack)
  (multiple-value-bind (a stack) (pop1 stack)
    (multiple-value-bind (b stack) (pop1 stack)
      (multiple-value-bind (c stack) (pop1 stack)
        (multiple-value-bind (d stack) (pop1 stack)
          (multiple-value-bind (e stack) (pop1 stack)
            (multiple-value-bind (f stack) (pop1 stack)
              (values a b c d e f stack))))))))

(defun pop7 (stack)
  (multiple-value-bind (a stack) (pop1 stack)
    (multiple-value-bind (b stack) (pop1 stack)
      (multiple-value-bind (c stack) (pop1 stack)
        (multiple-value-bind (d stack) (pop1 stack)
          (multiple-value-bind (e stack) (pop1 stack)
            (multiple-value-bind (f stack) (pop1 stack)
              (multiple-value-bind (g stack) (pop1 stack)
                (values a b c d e f g stack)))))))))

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
