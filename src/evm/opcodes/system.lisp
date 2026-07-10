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
         (multiple-value-bind (call-gas address-word value
                                       args-offset args-size
                                       return-offset return-size rest)
             (pop7 stack)
           (when (and (evm-context-read-only-p context) (plusp value))
             (fail "CALL with value is not allowed in read-only EVM context"))
           (evm-machine-charge-gas machine
            (memory-regions-expansion-gas
             memory
             (list args-offset args-size)
             (list return-offset return-size)))
           (setf memory
                 (ensure-memory-regions
                  memory
                  (list args-offset args-size)
                  (list return-offset return-size)))
           (let* ((state (evm-context-state context))
                  (callee (word-to-address address-word))
                  (snapshot
                    (capture-execution-snapshot state context))
                  (args (memory-slice memory args-offset args-size))
                  (insufficient-balance-p
                    (and (plusp value)
                         (< (account-balance
                             state
                             (evm-context-address context))
                            value)))
                  (precompile-callee-p
                    (active-precompile-address-p
                     callee
                     (evm-context-chain-rules context))))
             (charge-account-access-gas
              context
              callee
              (lambda (amount) (evm-machine-charge-gas machine amount)))
             (refresh-execution-snapshot-accessed-addresses
              snapshot context)
             (let* ((required-value-gas
                       (call-value-extra-gas state callee value
                                             :new-account-p t))
                    (stipend-discount-p
                      (or insufficient-balance-p
                          precompile-callee-p
                          (and (plusp value)
                               gas-limit
                               (= (+ gas-used required-value-gas)
                                  gas-limit)))))
               (evm-machine-charge-call-value-gas machine
                required-value-gas
                (call-value-extra-gas state callee value
                                      :new-account-p t
                                      :stipend-discount-p
                                      stipend-discount-p)))
             (let ((child-gas-limit
                     (child-call-gas-limit
                      call-gas gas-limit gas-used
                      :stipend (if (plusp value)
                                   +call-stipend+
                                   0))))
               (multiple-value-bind
                     (success child-return-data child-gas-used
                      child-logs child-refund-counter)
                   (execute-message-call-child
                    state context snapshot callee args child-gas-limit
                    :child-address callee
                    :child-caller (evm-context-address context)
                    :child-call-value value
                    :read-only-p (evm-context-read-only-p context)
                    :precompile-address-p precompile-callee-p
                    :value-transfer-from (evm-context-address context)
                    :value-transfer-to callee)
                 (evm-machine-charge-gas machine
                  (if precompile-callee-p
                      child-gas-used
                      (call-child-gas-charge child-gas-used value)))
                 (incf refund-counter child-refund-counter)
                 (setf return-data-buffer child-return-data
                       memory
                       (copy-child-return-data-to-memory
                        memory return-offset return-size
                        child-return-data)
                       logs (prepend-child-logs child-logs logs)
                       stack (stack-push rest success))))))
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
         (multiple-value-bind (call-gas address-word value
                                       args-offset args-size
                                       return-offset return-size rest)
             (pop7 stack)
           (evm-machine-charge-gas machine
            (memory-regions-expansion-gas
             memory
             (list args-offset args-size)
             (list return-offset return-size)))
           (setf memory
                 (ensure-memory-regions
                  memory
                  (list args-offset args-size)
                  (list return-offset return-size)))
           (let* ((state (evm-context-state context))
                  (code-address (word-to-address address-word))
                  (snapshot
                    (capture-execution-snapshot state context))
                  (args (memory-slice memory args-offset args-size))
                  (insufficient-balance-p
                    (and (plusp value)
                         (< (account-balance
                             state
                             (evm-context-address context))
                            value)))
                  (precompile-code-address-p
                    (active-precompile-address-p
                     code-address
                     (evm-context-chain-rules context))))
             (charge-account-access-gas
              context
              code-address
              (lambda (amount) (evm-machine-charge-gas machine amount)))
             (refresh-execution-snapshot-accessed-addresses
              snapshot context)
             (let* ((required-value-gas
                       (call-value-extra-gas state code-address value))
                    (stipend-discount-p
                      (or insufficient-balance-p
                          precompile-code-address-p
                          (and (plusp value)
                               gas-limit
                               (= (+ gas-used required-value-gas)
                                  gas-limit)))))
               (evm-machine-charge-call-value-gas machine
                required-value-gas
                (call-value-extra-gas
                 state code-address value
                 :stipend-discount-p stipend-discount-p)))
             (let ((child-gas-limit
                     (child-call-gas-limit
                      call-gas gas-limit gas-used
                      :stipend (if (plusp value)
                                   +call-stipend+
                                   0))))
               (multiple-value-bind
                     (success child-return-data child-gas-used
                      child-logs child-refund-counter)
                   (execute-message-call-child
                    state context snapshot code-address args
                    child-gas-limit
                    :child-address (evm-context-address context)
                    :child-caller (evm-context-address context)
                    :child-call-value value
                    :read-only-p (evm-context-read-only-p context)
                    :precompile-address-p precompile-code-address-p
                    :balance-check-address
                    (evm-context-address context)
                    :balance-check-value value
                    :balance-check-message
                    "Insufficient balance for CALLCODE value")
                 (evm-machine-charge-gas machine
                  (if precompile-code-address-p
                      child-gas-used
                      (call-child-gas-charge child-gas-used value)))
                 (incf refund-counter child-refund-counter)
                 (setf return-data-buffer child-return-data
                       memory
                       (copy-child-return-data-to-memory
                        memory return-offset return-size
                        child-return-data)
                       logs (prepend-child-logs child-logs logs)
                       stack (stack-push rest success))))))
         (incf pc))
        ((= op #xf4)
         (unless (and context (evm-context-state context))
           (fail "DELEGATECALL requires an EVM context with state"))
         (require-context-fork context #'chain-rules-homestead-p
                               "Homestead" "DELEGATECALL" pc)
         (multiple-value-bind (call-gas address-word
                                        args-offset args-size
                                        return-offset return-size rest)
             (pop6 stack)
           (evm-machine-charge-gas machine
            (memory-regions-expansion-gas
             memory
             (list args-offset args-size)
             (list return-offset return-size)))
           (setf memory
                 (ensure-memory-regions
                  memory
                  (list args-offset args-size)
                  (list return-offset return-size)))
           (let* ((state (evm-context-state context))
                  (code-address (word-to-address address-word))
                  (snapshot
                    (capture-execution-snapshot state context))
                  (args (memory-slice memory args-offset args-size))
                  (precompile-code-address-p
                    (active-precompile-address-p
                     code-address
                     (evm-context-chain-rules context))))
             (charge-account-access-gas
              context
              code-address
              (lambda (amount) (evm-machine-charge-gas machine amount)))
             (refresh-execution-snapshot-accessed-addresses
              snapshot context)
             (let ((child-gas-limit
                     (child-call-gas-limit
                      call-gas gas-limit gas-used)))
               (multiple-value-bind
                     (success child-return-data child-gas-used
                      child-logs child-refund-counter)
                   (execute-message-call-child
                    state context snapshot code-address args
                    child-gas-limit
                    :child-address (evm-context-address context)
                    :child-caller (evm-context-caller context)
                    :child-call-value
                    (evm-context-call-value context)
                    :read-only-p (evm-context-read-only-p context)
                    :precompile-address-p
                    precompile-code-address-p)
                 (evm-machine-charge-gas machine child-gas-used)
                 (incf refund-counter child-refund-counter)
                 (setf return-data-buffer child-return-data
                       memory
                       (copy-child-return-data-to-memory
                        memory return-offset return-size
                        child-return-data)
                       logs (prepend-child-logs child-logs logs)
                       stack (stack-push rest success))))))
         (incf pc))
        ((= op #xfa)
         (unless (and context (evm-context-state context))
           (fail "STATICCALL requires an EVM context with state"))
         (require-context-fork context #'chain-rules-byzantium-p
                               "Byzantium" "STATICCALL" pc)
         (multiple-value-bind (call-gas address-word
                                        args-offset args-size
                                        return-offset return-size rest)
             (pop6 stack)
           (evm-machine-charge-gas machine
            (memory-regions-expansion-gas
             memory
             (list args-offset args-size)
             (list return-offset return-size)))
           (setf memory
                 (ensure-memory-regions
                  memory
                  (list args-offset args-size)
                  (list return-offset return-size)))
           (let* ((state (evm-context-state context))
                  (callee (word-to-address address-word))
                  (snapshot
                    (capture-execution-snapshot state context))
                  (args (memory-slice memory args-offset args-size))
                  (precompile-callee-p
                    (active-precompile-address-p
                     callee
                     (evm-context-chain-rules context))))
             (charge-account-access-gas
              context
              callee
              (lambda (amount) (evm-machine-charge-gas machine amount)))
             (refresh-execution-snapshot-accessed-addresses
              snapshot context)
             (let ((child-gas-limit
                     (child-call-gas-limit
                      call-gas gas-limit gas-used)))
               (multiple-value-bind
                     (success child-return-data child-gas-used
                      child-logs child-refund-counter)
                   (execute-message-call-child
                    state context snapshot callee args child-gas-limit
                    :child-address callee
                    :child-caller (evm-context-address context)
                    :child-call-value 0
                    :read-only-p t
                    :precompile-address-p precompile-callee-p)
                 (declare (ignore child-logs))
                 (evm-machine-charge-gas machine child-gas-used)
                 (incf refund-counter child-refund-counter)
                 (setf return-data-buffer child-return-data
                       memory
                       (copy-child-return-data-to-memory
                        memory return-offset return-size
                        child-return-data)
                       stack (stack-push rest success))))))
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
             (unless (and (evm-context-chain-rules context)
                          (chain-rules-cancun-p
                           (evm-context-chain-rules context)))
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


