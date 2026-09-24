(in-package #:ethereum-lisp.evm.internal)

(defun execute-state-memory-opcode (machine opcode)
  "Execute stack, memory, storage, jump, and transient-storage opcodes."
  (declare (type evm-machine machine) (type (unsigned-byte 8) opcode))
  (with-evm-machine-state (machine)
    (let ((op opcode))
      (cond
        ((= op #x50)
         (evm-stack-pop machine)
         (incf pc))
        ((= op #x56)
         (let ((destination (evm-stack-pop machine)))
           (unless (valid-jump-destination-p
                    code destination jump-destinations)
             (fail "Invalid EVM jump destination ~D" destination))
           (setf pc destination)))
        ((= op #x57)
         (let* ((destination (evm-stack-pop machine))
                (condition (evm-stack-pop machine)))
           (if (zerop condition)
               (incf pc)
               (progn
                 (unless (valid-jump-destination-p
                          code destination jump-destinations)
                   (fail "Invalid EVM jump destination ~D" destination))
                 (setf pc destination)))))
        ((= op #x51)
         (let ((offset (evm-stack-pop machine)))
           (evm-machine-charge-memory-gas machine offset 32)
           (setf memory (ensure-memory-size memory (+ offset 32)))
           (evm-stack-push machine (mload memory offset)))
         (incf pc))
        ((= op #x52)
         (let* ((offset (evm-stack-pop machine))
                (value (evm-stack-pop machine)))
           (evm-machine-charge-memory-gas machine offset 32)
           (setf memory (mstore memory offset value)))
         (incf pc))
        ((= op #x53)
         (let* ((offset (evm-stack-pop machine))
                (value (evm-stack-pop machine)))
           (evm-machine-charge-memory-gas machine offset 1)
           (setf memory (mstore8 memory offset value)))
         (incf pc))
        ((= op #x54)
         (unless (and context (evm-context-state context))
           (fail "SLOAD requires an EVM context with state"))
         (let ((slot (evm-stack-pop machine)))
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
             (evm-stack-push machine value)))
         (incf pc))
        ((= op #x55)
         (unless (and context (evm-context-state context))
           (fail "SSTORE requires an EVM context with state"))
         (when (evm-context-read-only-p context)
           (fail "SSTORE is not allowed in read-only EVM context"))
         (when (and (context-istanbul-p context)
                    gas-limit
                    (<= (evm-gas-budget-regular gas-budget)
                        +sstore-sentry-gas-eip2200+))
           (fail "SSTORE requires more than the EIP-2200 sentry gas"))
         (let* ((slot (evm-stack-pop machine))
                (value (evm-stack-pop machine)))
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
              (if (amsterdam-context-p context)
                  (let ((access-cost
                          (storage-access-cost
                           context
                           (evm-context-address context)
                           slot-hash)))
                    (evm-machine-charge-gas
                     machine
                     (sstore-amsterdam-regular-gas
                      access-cost original-value current-value value))
                    (when (and (zerop original-value)
                               (zerop current-value)
                               (not (zerop value)))
                      (evm-machine-charge-state-gas
                       machine +storage-set-state-gas+))
                    (when (and (zerop original-value)
                               (not (zerop current-value))
                               (zerop value))
                      (evm-machine-refill-state-gas
                       machine +storage-set-state-gas+))
                    (when (and (not (zerop original-value))
                               (not (zerop current-value))
                               (zerop value))
                      (incf refund-counter
                            +storage-clear-refund-amsterdam+))
                    (when (and (not (zerop original-value))
                               (zerop current-value)
                               (not (zerop value)))
                      (decf refund-counter
                            +storage-clear-refund-amsterdam+))
                    (when (and (/= current-value original-value)
                               (= value original-value))
                      (incf refund-counter
                            +storage-write-amsterdam+)))
                  (multiple-value-bind (gas refund-delta)
                      (historical-sstore-gas-and-refund
                       context original-value current-value value
                       (evm-context-address context) slot-hash)
                    (evm-machine-charge-gas machine gas)
                    (incf refund-counter refund-delta)))
              (mark-storage-accessed
               context
               (evm-context-address context)
               slot-hash))
             (state-db-set-storage
              (evm-context-state context)
              (evm-context-address context)
              slot-hash
              value)))
         (incf pc))
        ((= op #x58)
         (evm-stack-push machine pc)
         (incf pc))
        ((= op #x59)
         (evm-stack-push machine (length memory))
         (incf pc))
        ((= op #x5a)
         (evm-stack-push machine
                         (if gas-limit
                             (evm-gas-budget-regular gas-budget)
                             0))
         (incf pc))
        ((= op #x5b)
         (incf pc))
        ((= op #x5c)
         (unless context
           (fail "TLOAD requires an EVM context"))
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "TLOAD" pc)
         (let ((slot (evm-stack-pop machine)))
           (evm-stack-push
            machine
            (transient-storage-get
             context
             (evm-context-address context)
             (word-to-hash32 slot))))
         (incf pc))
        ((= op #x5d)
         (unless context
           (fail "TSTORE requires an EVM context"))
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "TSTORE" pc)
         (when (evm-context-read-only-p context)
           (fail "TSTORE is not allowed in read-only EVM context"))
         (let* ((slot (evm-stack-pop machine))
                (value (evm-stack-pop machine)))
           (transient-storage-set
            context
            (evm-context-address context)
            (word-to-hash32 slot)
            value))
         (incf pc))
        ((= op #x5e)
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "MCOPY" pc)
         (let* ((destination (evm-stack-pop machine))
                (source (evm-stack-pop machine))
                (size (evm-stack-pop machine)))
           (evm-machine-charge-gas machine
            (+ (memory-expansion-gas
                memory
                0
                (memory-regions-high-water (list destination size)
                                           (list source size)))
               (* +copy-word-gas+ (memory-word-count size))))
           (setf memory
                 (copy-memory-region memory destination source size)))
         (incf pc))
        ((= op #x5f)
         (require-context-fork context #'chain-rules-shanghai-p
                               "Shanghai" "PUSH0" pc)
         (evm-stack-push-word machine 0)
         (incf pc))
        (t
         (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))
