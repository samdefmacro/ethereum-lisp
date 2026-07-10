(in-package #:ethereum-lisp.evm)

(defstruct (evm-machine (:constructor %make-evm-machine))
  "Mutable state for one EVM call frame.

The interpreter owns control flow; opcode handlers mutate this object.  Keeping
the frame explicit makes gas accounting and rollback state visible instead of
hiding them in one large lexical scope."
  (code (make-byte-vector 0) :type byte-vector)
  context
  gas-limit
  (max-steps 100000 :type (integer 0 *))
  (pc 0 :type (integer 0 *))
  (steps 0 :type (integer 0 *))
  (gas-used 0 :type (integer 0 *))
  (stack '() :type list)
  (memory (make-byte-vector 0) :type byte-vector)
  (return-data (make-byte-vector 0) :type byte-vector)
  (return-data-buffer (make-byte-vector 0) :type byte-vector)
  frame-snapshot
  original-storage-values
  cleared-storage-slots
  (logs '() :type list)
  (refund-counter 0 :type integer)
  (status :stopped)
  (halted-p nil :type boolean))

(defun make-evm-machine (code context gas-limit max-steps)
  (%make-evm-machine
   :code (ensure-byte-vector code)
   :context context
   :gas-limit gas-limit
   :max-steps max-steps
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

(defun evm-machine-apply-binary (machine function)
  (multiple-value-bind (left right rest)
      (pop2 (evm-machine-stack machine))
    (setf (evm-machine-stack machine)
          (stack-push rest (funcall function left right)))))

(defun evm-machine-apply-comparison (machine predicate)
  (evm-machine-apply-binary
   machine
   (lambda (left right)
     (if (funcall predicate left right) 1 0))))

(defun evm-machine-charge-gas (machine amount)
  (incf (evm-machine-gas-used machine) amount)
  (when (and (evm-machine-gas-limit machine)
             (> (evm-machine-gas-used machine)
                (evm-machine-gas-limit machine)))
    (fail "EVM out of gas at pc ~D" (evm-machine-pc machine))))

(defun evm-machine-charge-call-value-gas (machine required charged)
  ;; The OOG boundary uses the undiscounted cost.  A successful call can still
  ;; receive the value-transfer stipend discount.
  (if (and (evm-machine-gas-limit machine)
           (> (+ (evm-machine-gas-used machine) required)
              (evm-machine-gas-limit machine)))
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
  (make-evm-result
   :status (evm-machine-status machine)
   :stack (evm-machine-stack machine)
   :memory (evm-machine-memory machine)
   :return-data (evm-machine-return-data machine)
   :logs (nreverse (evm-machine-logs machine))
   :pc (evm-machine-pc machine)
   :gas-used (evm-machine-gas-used machine)
   :refund-counter (evm-machine-refund-counter machine)))

(defmacro with-evm-machine-state ((machine) &body body)
  "Bind the mutable frame fields used by an opcode handler."
  `(with-slots (code context gas-limit max-steps pc steps gas-used stack memory
                return-data return-data-buffer frame-snapshot
                original-storage-values cleared-storage-slots logs
                refund-counter status halted-p)
       ,machine
     ,@body))
