(in-package #:ethereum-lisp.evm.internal)

(defun execute-system-opcode (machine opcode)
  "Execute contract creation, calls, returns, reverts, and self-destruction."
  (with-evm-machine-state (machine)
    (let ((op opcode))
      (cond
        ((= op #xf0)
         (unless (and context (evm-context-state context))
           (fail "CREATE requires an EVM context with state"))
         (when (evm-context-read-only-p context)
           (fail "CREATE is not allowed in read-only EVM context"))
         (multiple-value-bind (value offset size rest) (pop3 stack)
           (evm-machine-charge-gas machine
            (create-initcode-extra-gas
             size
             :rules (evm-context-chain-rules context)))
           (evm-machine-charge-memory-gas machine offset size)
           (setf memory (ensure-memory-size memory (+ offset size)))
           (let* ((state (evm-context-state context))
                  (creator (evm-context-address context))
                  (creator-account (account-or-empty state creator))
                  (new-address
                    (create-address creator
                                    (state-account-nonce
                                     creator-account)))
                  (initcode (memory-slice memory offset size)))
             (multiple-value-bind
                   (success-address child-return-data child-gas-used
                    child-logs child-refund-counter)
                 (execute-contract-creation
                  state context creator new-address value initcode
                  gas-limit gas-used "CREATE")
               (evm-machine-charge-gas machine child-gas-used)
               (incf refund-counter child-refund-counter)
               (setf return-data-buffer child-return-data
                     logs (prepend-child-logs child-logs logs)
                     stack (stack-push rest success-address)))))
         (incf pc))
        ((= op #xf5)
         (unless (and context (evm-context-state context))
           (fail "CREATE2 requires an EVM context with state"))
         (require-context-fork context
                               #'chain-rules-constantinople-p
                               "Constantinople" "CREATE2" pc)
         (when (evm-context-read-only-p context)
           (fail "CREATE2 is not allowed in read-only EVM context"))
         (multiple-value-bind (value offset size rest1) (pop3 stack)
           (multiple-value-bind (salt rest) (pop1 rest1)
             (evm-machine-charge-gas machine
              (create-initcode-extra-gas
               size
               :create2-p t
               :rules (evm-context-chain-rules context)))
             (evm-machine-charge-memory-gas machine offset size)
             (setf memory (ensure-memory-size memory (+ offset size)))
             (let* ((state (evm-context-state context))
                    (creator (evm-context-address context))
                    (initcode (memory-slice memory offset size))
                    (new-address
                      (create2-address creator salt initcode)))
               (multiple-value-bind
                     (success-address child-return-data child-gas-used
                      child-logs child-refund-counter)
                   (execute-contract-creation
                    state context creator new-address value initcode
                    gas-limit gas-used "CREATE2")
                 (evm-machine-charge-gas machine child-gas-used)
                 (incf refund-counter child-refund-counter)
                 (setf return-data-buffer child-return-data
                       logs (prepend-child-logs child-logs logs)
                       stack (stack-push rest success-address))))))
         (incf pc))
        ((= op #xf1)
         (unless (and context (evm-context-state context))
           (fail "CALL requires an EVM context with state"))
         (multiple-value-bind (requested-gas address-word value
                               args-offset args-size
                               return-offset return-size rest-stack)
             (pop7 stack)
           (when (and (evm-context-read-only-p context) (plusp value))
             (fail "CALL with value is not allowed in read-only EVM context"))
           (let ((callee (word-to-address address-word))
                 (caller (evm-context-address context)))
             (execute-evm-message-call
              machine
              (make-evm-message-call
               :requested-gas requested-gas
               :code-address callee
               :args-offset args-offset
               :args-size args-size
               :return-offset return-offset
               :return-size return-size
               :rest-stack rest-stack
               :child-address callee
               :child-caller caller
               :child-value value
               :read-only-p (evm-context-read-only-p context)
               :charge-value-gas-p t
               :new-account-p t
               :value-transfer-from caller
               :value-transfer-to callee))))
         (incf pc))
        ((= op #xf3)
         (multiple-value-bind (offset size rest) (pop2 stack)
           (evm-machine-charge-memory-gas machine offset size)
           (setf return-data (memory-slice memory offset size)
                 stack rest
                 status :returned
                 halted-p t)))
        ((= op #xf2)
         (unless (and context (evm-context-state context))
           (fail "CALLCODE requires an EVM context with state"))
         (multiple-value-bind (requested-gas address-word value
                               args-offset args-size
                               return-offset return-size rest-stack)
             (pop7 stack)
           (let ((code-address (word-to-address address-word))
                 (current-address (evm-context-address context)))
             (execute-evm-message-call
              machine
              (make-evm-message-call
               :requested-gas requested-gas
               :code-address code-address
               :args-offset args-offset
               :args-size args-size
               :return-offset return-offset
               :return-size return-size
               :rest-stack rest-stack
               :child-address current-address
               :child-caller current-address
               :child-value value
               :read-only-p (evm-context-read-only-p context)
               :charge-value-gas-p t
               :balance-check-address current-address
               :balance-check-value value
               :balance-check-message
               "Insufficient balance for CALLCODE value"))))
         (incf pc))
        ((= op #xf4)
         (unless (and context (evm-context-state context))
           (fail "DELEGATECALL requires an EVM context with state"))
         (require-context-fork context #'chain-rules-homestead-p
                               "Homestead" "DELEGATECALL" pc)
         (multiple-value-bind (requested-gas address-word
                               args-offset args-size
                               return-offset return-size rest-stack)
             (pop6 stack)
           (execute-evm-message-call
            machine
            (make-evm-message-call
             :requested-gas requested-gas
             :code-address (word-to-address address-word)
             :args-offset args-offset
             :args-size args-size
             :return-offset return-offset
             :return-size return-size
             :rest-stack rest-stack
             :child-address (evm-context-address context)
             :child-caller (evm-context-caller context)
             :child-value (evm-context-call-value context)
             :read-only-p (evm-context-read-only-p context))))
         (incf pc))
        ((= op #xfa)
         (unless (and context (evm-context-state context))
           (fail "STATICCALL requires an EVM context with state"))
         (require-context-fork context #'chain-rules-byzantium-p
                               "Byzantium" "STATICCALL" pc)
         (multiple-value-bind (requested-gas address-word
                               args-offset args-size
                               return-offset return-size rest-stack)
             (pop6 stack)
           (let ((callee (word-to-address address-word)))
             (execute-evm-message-call
              machine
              (make-evm-message-call
               :requested-gas requested-gas
               :code-address callee
               :args-offset args-offset
               :args-size args-size
               :return-offset return-offset
               :return-size return-size
               :rest-stack rest-stack
               :child-address callee
               :child-caller (evm-context-address context)
               :read-only-p t
               :merge-logs-p nil))))
         (incf pc))
        ((= op #xff)
         (unless (and context (evm-context-state context))
           (fail "SELFDESTRUCT requires an EVM context with state"))
         (when (evm-context-read-only-p context)
           (fail "SELFDESTRUCT is not allowed in read-only EVM context"))
         (multiple-value-bind (beneficiary-word rest) (pop1 stack)
           (let ((beneficiary (word-to-address beneficiary-word)))
             (charge-cold-account-access-gas
              context
              beneficiary
              (lambda (amount) (evm-machine-charge-gas machine amount)))
             (evm-machine-charge-gas machine
              (selfdestruct-extra-gas
               (evm-context-state context)
               (evm-context-address context)
               beneficiary))
             (selfdestruct-account
              (evm-context-state context)
              (evm-context-address context)
              beneficiary)
             ;; EIP-6780 (Cancun+): the account is deleted only when it was
             ;; created in this transaction; otherwise SELFDESTRUCT merely
             ;; transfers the balance. Pre-Cancun, deletion always applies.
             (when (or (not (and (evm-context-chain-rules context)
                                 (chain-rules-cancun-p
                                  (evm-context-chain-rules context))))
                       (account-created-this-transaction-p
                        context
                        (evm-context-address context)))
               (mark-selfdestructed-address
                context
                (evm-context-address context))))
           (setf stack rest
                 status :selfdestructed
                 halted-p t)))
        ((= op #xfd)
         (require-context-fork context #'chain-rules-byzantium-p
                               "Byzantium" "REVERT" pc)
         (multiple-value-bind (offset size rest) (pop2 stack)
           (evm-machine-charge-memory-gas machine offset size)
           (restore-frame-snapshot context frame-snapshot)
           (setf return-data (memory-slice memory offset size)
                 stack rest
                 refund-counter 0
                 status :reverted
                 halted-p t)))
        (t
         (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))
