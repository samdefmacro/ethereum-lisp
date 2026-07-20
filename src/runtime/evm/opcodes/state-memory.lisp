(in-package #:ethereum-lisp.evm.internal)

(defun execute-state-memory-opcode (machine opcode)
  "Execute stack, memory, storage, jump, and transient-storage opcodes."
  (with-evm-machine-state (machine)
    (let ((op opcode))
      (cond
        ((= op #x50)
         (multiple-value-bind (ignored rest) (pop1 stack)
           (declare (ignore ignored))
           (setf stack rest))
         (incf pc))
        ((= op #x56)
         (multiple-value-bind (destination rest) (pop1 stack)
           (unless (valid-jump-destination-p code destination)
             (fail "Invalid EVM jump destination ~D" destination))
           (setf stack rest
                 pc destination)))
        ((= op #x57)
         (multiple-value-bind (destination condition rest) (pop2 stack)
           (setf stack rest)
           (if (zerop condition)
               (incf pc)
               (progn
                 (unless (valid-jump-destination-p code destination)
                   (fail "Invalid EVM jump destination ~D" destination))
                 (setf pc destination)))))
        ((= op #x51)
         (multiple-value-bind (offset rest) (pop1 stack)
           (evm-machine-charge-memory-gas machine offset 32)
           (setf memory (ensure-memory-size memory (+ offset 32))
                 stack (stack-push rest (mload memory offset))))
         (incf pc))
        ((= op #x52)
         (multiple-value-bind (offset value rest) (pop2 stack)
           (evm-machine-charge-memory-gas machine offset 32)
           (setf memory (mstore memory offset value)
                 stack rest))
         (incf pc))
        ((= op #x53)
         (multiple-value-bind (offset value rest) (pop2 stack)
           (evm-machine-charge-memory-gas machine offset 1)
           (setf memory (mstore8 memory offset value)
                 stack rest))
         (incf pc))
        ((= op #x54)
         (unless (and context (evm-context-state context))
           (fail "SLOAD requires an EVM context with state"))
         (multiple-value-bind (slot rest) (pop1 stack)
           (let* ((slot-hash (word-to-hash32 slot))
                  (value (state-db-get-storage
                          (evm-context-state context)
                          (evm-context-address context)
                          slot-hash)))
             (charge-storage-read-access-gas
              context
              (evm-context-address context)
              slot-hash
              (lambda (amount) (evm-machine-charge-gas machine amount)))
             (setf stack (stack-push rest value))))
         (incf pc))
        ((= op #x55)
         (unless (and context (evm-context-state context))
           (fail "SSTORE requires an EVM context with state"))
         (when (evm-context-read-only-p context)
           (fail "SSTORE is not allowed in read-only EVM context"))
         (when (and gas-limit
                    (<= (remaining-gas gas-limit gas-used)
                        +sstore-sentry-gas-eip2200+))
           (fail "SSTORE requires more than the EIP-2200 sentry gas"))
         (multiple-value-bind (slot value rest) (pop2 stack)
           (let* ((slot-hash (word-to-hash32 slot))
                  (refund-key
                    (storage-refund-key
                     (evm-context-address context)
                     slot-hash))
                  (current-value
                    (state-db-get-storage
                     (evm-context-state context)
                     (evm-context-address context)
                     slot-hash)))
             (unless (nth-value 1
                       (gethash refund-key
                                original-storage-values))
               (setf (gethash refund-key original-storage-values)
                     current-value))
             (let ((original-value
                     (gethash refund-key original-storage-values)))
               (evm-machine-charge-gas machine
                (sstore-dynamic-gas
                 (storage-cold-access-surcharge
                  context
                  (evm-context-address context)
                  slot-hash)
                 original-value
                 current-value
                 value))
               (mark-storage-accessed
                context
                (evm-context-address context)
                slot-hash)
               (when (and (not (zerop original-value))
                          (not (zerop current-value))
                          (zerop value))
               (setf (gethash refund-key cleared-storage-slots) t)
               (incf refund-counter
                     +sstore-clears-schedule-refund-eip3529+))
             (when (and (not (zerop original-value))
                        (zerop current-value)
                        (not (zerop value))
                        (gethash refund-key cleared-storage-slots))
               (remhash refund-key cleared-storage-slots)
               (decf refund-counter
                     +sstore-clears-schedule-refund-eip3529+))
             (when (and (/= current-value original-value)
                        (= value original-value))
               (incf refund-counter
                     (if (zerop original-value)
                         +sstore-reset-original-zero-refund-eip3529+
                         +sstore-reset-original-refund-eip3529+))))
             (state-db-set-storage
              (evm-context-state context)
              (evm-context-address context)
              slot-hash
              value)
             (setf stack rest)))
         (incf pc))
        ((= op #x58)
         (setf stack (stack-push stack pc))
         (incf pc))
        ((= op #x59)
         (setf stack (stack-push stack (length memory)))
         (incf pc))
        ((= op #x5a)
         (setf stack (stack-push stack
                                 (remaining-gas gas-limit gas-used)))
         (incf pc))
        ((= op #x5b)
         (incf pc))
        ((= op #x5c)
         (unless context
           (fail "TLOAD requires an EVM context"))
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "TLOAD" pc)
         (multiple-value-bind (slot rest) (pop1 stack)
           (setf stack
                 (stack-push
                  rest
                  (transient-storage-get
                   context
                   (evm-context-address context)
                   (word-to-hash32 slot)))))
         (incf pc))
        ((= op #x5d)
         (unless context
           (fail "TSTORE requires an EVM context"))
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "TSTORE" pc)
         (when (evm-context-read-only-p context)
           (fail "TSTORE is not allowed in read-only EVM context"))
         (multiple-value-bind (slot value rest) (pop2 stack)
           (transient-storage-set
            context
            (evm-context-address context)
            (word-to-hash32 slot)
            value)
           (setf stack rest))
         (incf pc))
        ((= op #x5e)
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "MCOPY" pc)
         (multiple-value-bind (destination source size rest)
             (pop3 stack)
           (evm-machine-charge-gas machine
            (+ (memory-expansion-gas
                memory
                0
                (memory-regions-high-water (list destination size)
                                           (list source size)))
               (* +copy-word-gas+ (memory-word-count size))))
           (setf memory
                 (copy-memory-region memory destination source size)
                 stack rest))
         (incf pc))
        ((= op #x5f)
         (require-context-fork context #'chain-rules-shanghai-p
                               "Shanghai" "PUSH0" pc)
         (setf stack (stack-push stack 0))
         (incf pc))
        (t
         (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))


