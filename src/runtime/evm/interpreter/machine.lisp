(in-package #:ethereum-lisp.evm.internal)

(defconstant +default-gasless-evm-max-steps+ 100000)

(defstruct evm-step-budget
  "Mutable diagnostic instruction budget shared by an execution tree."
  (limit 0 :type (integer 0 *))
  (steps 0 :type (integer 0 *)))

(defvar *evm-step-budget* nil
  "Dynamically inherited diagnostic budget for nested EVM frames.")

(defvar *evm-step-budget-policy-active-p* nil
  "Whether the enclosing execution tree has selected its budget policy.")

(defstruct (evm-machine (:constructor %make-evm-machine))
  "Mutable state for one EVM call frame.

The interpreter owns control flow; opcode handlers mutate this object.  Keeping
the frame explicit makes gas accounting and rollback state visible instead of
hiding them in one large lexical scope."
  (code (make-byte-vector 0) :type byte-vector)
  (jump-destinations #* :type simple-bit-vector)
  context
  gas-limit
  gas-budget
  step-budget
  ;; PC only ever holds a code offset (a jump target is checked against the
  ;; code length before it is stored) and STEPS counts executed instructions,
  ;; so both are fixnums and their per-instruction updates are word
  ;; arithmetic.
  (pc 0 :type (and fixnum unsigned-byte))
  (steps 0 :type (and fixnum unsigned-byte))
  (gas-used 0 :type (integer 0 *))
  ;; The operand stack: words in STACK[0..SP), the top at SP-1.  The vector
  ;; starts small and doubles up to +STACK-LIMIT+, so a push or pop is an
  ;; index update, not a cons.
  (stack (make-array +initial-evm-stack-capacity+) :type simple-vector)
  (sp 0 :type (integer 0 #.+stack-limit+))
  (memory (make-byte-vector 0) :type (array (unsigned-byte 8) (*)))
  (return-data (make-byte-vector 0) :type byte-vector)
  (return-data-buffer (make-byte-vector 0) :type byte-vector)
  frame-snapshot
  original-storage-values
  cleared-storage-slots
  (logs '() :type list)
  (refund-counter 0 :type integer)
  (status :stopped)
  (halted-p nil :type boolean))

(defun make-evm-machine (code context gas-limit step-budget &optional gas-budget)
  (%make-evm-machine
   :code (ensure-byte-vector code)
   :jump-destinations (jump-destination-bitmap (ensure-byte-vector code))
   :context context
   :gas-limit gas-limit
   :gas-budget
   (or gas-budget
       (make-evm-gas-budget :regular (or gas-limit 0)))
   :step-budget step-budget
   :return-data-buffer
   (if context
       (ensure-byte-vector (evm-context-return-data context))
       (make-byte-vector 0))
   :frame-snapshot (capture-frame-snapshot context)
   :original-storage-values
   (if context
       (evm-context-storage-originals context)
       (make-hash-table :test 'equalp))
   :cleared-storage-slots
   (if context
       (evm-context-storage-clears context)
       (make-hash-table :test 'equalp))))

(defun %grow-evm-stack (machine)
  "Double MACHINE's stack vector (never beyond +STACK-LIMIT+) and return it."
  (declare (type evm-machine machine))
  (let* ((old (evm-machine-stack machine))
         (new (make-array (min +stack-limit+ (* 2 (length old))))))
    (replace new old)
    (setf (evm-machine-stack machine) new)))

(declaim (inline evm-stack-push-word evm-stack-push evm-stack-pop
                 evm-stack-index))

(defun evm-stack-push-word (machine value)
  "Push VALUE, already a word, onto MACHINE's stack."
  (declare (type evm-machine machine))
  (let ((sp (evm-machine-sp machine))
        (stack (evm-machine-stack machine)))
    (when (>= sp +stack-limit+)
      (fail "EVM stack overflow"))
    (when (= sp (length stack))
      (setf stack (%grow-evm-stack machine)))
    (setf (svref stack sp) value
          (evm-machine-sp machine) (1+ sp))
    nil))

(defun evm-stack-push (machine value)
  "Push VALUE reduced modulo 2^256 onto MACHINE's stack."
  (evm-stack-push-word machine (word value)))

(defun evm-stack-pop (machine)
  "Pop and return the top word of MACHINE's stack."
  (declare (type evm-machine machine))
  (let ((sp (evm-machine-sp machine)))
    (when (zerop sp)
      (fail "EVM stack underflow"))
    (let ((top (1- sp)))
      (setf (evm-machine-sp machine) top)
      (svref (evm-machine-stack machine) top))))

(defun evm-stack-index (machine depth)
  "The vector index of the word DEPTH below the top (the top is depth 0)."
  (declare (type evm-machine machine) (type fixnum depth))
  (- (evm-machine-sp machine) 1 depth))

(defun evm-stack-list (machine)
  "MACHINE's stack as a list, top first (the EVM-RESULT-STACK shape)."
  (declare (type evm-machine machine))
  (let ((stack (evm-machine-stack machine)))
    (loop for index from (1- (evm-machine-sp machine)) downto 0
          collect (svref stack index))))

(defun evm-machine-apply-binary (machine function)
  (let* ((left (evm-stack-pop machine))
         (right (evm-stack-pop machine)))
    (evm-stack-push machine (funcall function left right))))

(deftype evm-small-gas ()
  "A gas quantity whose arithmetic compiles to machine words."
  '(and fixnum unsigned-byte))

(declaim (inline %evm-machine-charge-small-gas-p))
(defun %evm-machine-charge-small-gas-p (machine amount)
  "Charge AMOUNT of regular gas when it and every counter it touches are
fixnums, and return T; return NIL, charging nothing, when any is not.

This is EVM-GAS-BUDGET-CHARGE-REGULAR plus the frame's GAS-USED on fixnum
arithmetic: every real gas quantity is a fixnum, so the interpreter's
per-instruction charge never reaches generic arithmetic.  An unaffordable
AMOUNT fails exactly as the general path does."
  (declare (type evm-machine machine))
  (let ((budget (evm-machine-gas-budget machine))
        (gas-used (evm-machine-gas-used machine)))
    (declare (type evm-gas-budget budget))
    (let ((regular (evm-gas-budget-regular budget))
          (used-regular (evm-gas-budget-used-regular budget)))
      (when (and (typep amount 'evm-small-gas)
                 (typep regular 'evm-small-gas)
                 (typep used-regular 'evm-small-gas)
                 (typep gas-used 'evm-small-gas))
        (when (> amount regular)
          (fail "EVM out of gas (regular dimension) at pc ~D"
                (evm-machine-pc machine)))
        (setf (evm-gas-budget-regular budget) (- regular amount)
              (evm-gas-budget-used-regular budget) (+ used-regular amount)
              (evm-machine-gas-used machine) (+ gas-used amount))
        t))))

(declaim (inline %evm-machine-charge-gas))
(defun %evm-machine-charge-gas (machine amount)
  (declare (type evm-machine machine))
  (if (and (evm-machine-gas-limit machine)
           (%evm-machine-charge-small-gas-p machine amount))
      amount
      (evm-machine-charge-gas machine amount)))

(defun evm-machine-charge-gas (machine amount)
  (declare (type evm-machine machine))
  (unless (evm-machine-gas-limit machine)
    (incf (evm-machine-gas-used machine) amount)
    (incf (evm-gas-budget-used-regular
           (evm-machine-gas-budget machine))
          amount)
    (return-from evm-machine-charge-gas amount))
  (unless (evm-gas-budget-charge-regular
           (evm-machine-gas-budget machine) amount)
    (fail "EVM out of gas (regular dimension) at pc ~D"
          (evm-machine-pc machine)))
  (incf (evm-machine-gas-used machine) amount)
  amount)

(defun evm-machine-charge-state-gas (machine amount)
  (unless (evm-gas-budget-charge-state
           (evm-machine-gas-budget machine) amount)
    (fail "EVM out of state gas at pc ~D" (evm-machine-pc machine)))
  (incf (evm-machine-gas-used machine) amount)
  amount)

(defun evm-machine-refill-state-gas (machine amount)
  (evm-gas-budget-refill-state (evm-machine-gas-budget machine) amount)
  (decf (evm-machine-gas-used machine) amount)
  amount)

(defun evm-machine-regular-gas-left (machine)
  (if (evm-machine-gas-limit machine)
      (evm-gas-budget-regular (evm-machine-gas-budget machine))
      0))

(defun evm-machine-charge-call-value-gas (machine required charged)
  ;; The OOG boundary uses the undiscounted cost.  A successful call can still
  ;; receive the value-transfer stipend discount.
  (if (and (evm-machine-gas-limit machine)
           (> required (evm-machine-regular-gas-left machine)))
      (evm-machine-charge-gas machine required)
      (evm-machine-charge-gas machine charged)))

(defun evm-machine-charge-memory-gas (machine offset size)
  (evm-machine-charge-gas
   machine
   (memory-expansion-gas (evm-machine-memory machine) offset size)))

(defun evm-machine-charge-copy-gas (machine offset size)
  (evm-machine-charge-gas
   machine
   (+ (memory-expansion-gas (evm-machine-memory machine) offset size)
      (* +copy-word-gas+ (memory-word-count size)))))

(defun halt-evm-machine (machine status)
  (setf (evm-machine-status machine) status
        (evm-machine-halted-p machine) t))

(defun evm-machine-result (machine)
  (let* ((memory (evm-machine-memory machine))
         (memory-copy (make-byte-vector (length memory))))
    (replace memory-copy memory)
    (make-evm-result
     :status (evm-machine-status machine)
     :stack (evm-stack-list machine)
     :memory memory-copy
     :return-data (evm-machine-return-data machine)
     :logs (nreverse (evm-machine-logs machine))
     :pc (evm-machine-pc machine)
     :gas-used (evm-machine-gas-used machine)
     :regular-gas-used
     (evm-gas-budget-used-regular (evm-machine-gas-budget machine))
     :state-gas-used
     (max 0 (evm-gas-budget-used-state
             (evm-machine-gas-budget machine)))
     :gas-budget (copy-evm-gas-budget (evm-machine-gas-budget machine))
     :refund-counter (evm-machine-refund-counter machine))))

(defmacro with-evm-machine-state ((machine) &body body)
  "Bind the mutable frame fields used by an opcode handler."
  `(with-slots (code jump-destinations context gas-limit gas-budget step-budget
                pc steps gas-used memory
                return-data return-data-buffer frame-snapshot
                original-storage-values cleared-storage-slots logs
                refund-counter status halted-p)
       ,machine
     ,@body))
