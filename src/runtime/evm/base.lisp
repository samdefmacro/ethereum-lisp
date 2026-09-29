(in-package #:ethereum-lisp.evm.internal)

(defun word (value)
  ;; Every stack push reduces its value; a non-negative fixnum is already a
  ;; word, and skipping the bignum MOD for it keeps pushes allocation-free.
  ;; A bignum already below 2^256 (a PUSH32 immediate, an MLOAD result) is
  ;; returned as well: MOD would divide and allocate a copy of it.
  (cond ((typep value '(and fixnum unsigned-byte)) value)
        ((and (typep value 'unsigned-byte) (< value +word-modulus+)) value)
        (t (mod value +word-modulus+))))

;;; The cheap word operations.  Both the opcode handlers and the frame's
;;; register loop (interpreter/interpreter.lisp) call these, so each opcode has
;;; one definition.  Stack words are non-negative integers below 2^256, and
;;; most of them in real code (counters, offsets, gas, small constants) are
;;; fixnums: each operation takes a branch that compiles to machine arithmetic
;;; for two fixnums and the generic one otherwise.  Both branches compute the
;;; same word, so every result may be pushed without a further reduction.

(deftype small-word ()
  "A stack word that is a fixnum."
  '(and fixnum unsigned-byte))

(declaim (inline word-add word-sub word-lt word-gt word-eq word-iszero
                 word-and word-or word-xor))

(defun word-add (left right)
  (if (and (typep left 'small-word) (typep right 'small-word))
      (+ left right)
      (word (+ left right))))

(defun word-sub (left right)
  (if (and (typep left 'small-word) (typep right 'small-word)
           (>= left right))
      (- left right)
      (word (- left right))))

(defun word-lt (left right)
  (if (if (and (typep left 'small-word) (typep right 'small-word))
          (< left right)
          (< left right))
      1
      0))

(defun word-gt (left right)
  (if (if (and (typep left 'small-word) (typep right 'small-word))
          (> left right)
          (> left right))
      1
      0))

(defun word-eq (left right)
  (if (if (and (typep left 'small-word) (typep right 'small-word))
          (= left right)
          (= left right))
      1
      0))

(defun word-iszero (value)
  (if (eql value 0) 1 0))

(defun word-and (left right)
  (if (and (typep left 'small-word) (typep right 'small-word))
      (logand left right)
      (logand left right)))

(defun word-or (left right)
  (if (and (typep left 'small-word) (typep right 'small-word))
      (logior left right)
      (logior left right)))

(defun word-xor (left right)
  (if (and (typep left 'small-word) (typep right 'small-word))
      (logxor left right)
      (logxor left right)))

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

Amsterdam execution is NOT yet available: the tests-glamsterdam-devnet@v7.2.1
burn-down (docs/gap-analysis/amsterdam-inventory.md) still fails in EIP-2780,
EIP-7708, EIP-7928, EIP-8037, EIP-8038 and EIP-8246, most of it EIP-8037
state-gas refill accounting in the interpreter.  Until every directory there
passes this must stay NIL.

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
