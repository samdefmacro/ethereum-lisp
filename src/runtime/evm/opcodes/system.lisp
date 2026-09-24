(in-package #:ethereum-lisp.evm.internal)

(defun execute-system-opcode (machine opcode)
  "Execute contract creation, calls, returns, reverts, and self-destruction."
  (declare (type evm-machine machine) (type (unsigned-byte 8) opcode))
  (with-evm-machine-state (machine)
    (let ((op opcode))
      (cond
        ((= op #xf0)
         (unless (and context (evm-context-state context))
           (fail "CREATE requires an EVM context with state"))
         (when (evm-context-read-only-p context)
           (fail "CREATE is not allowed in read-only EVM context"))
         (let* ((value (evm-stack-pop machine))
                (offset (evm-stack-pop machine))
                (size (evm-stack-pop machine)))
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
                    child-logs child-refund-counter child-state-gas-used)
                 (execute-contract-creation
                  state context creator new-address value initcode
                  machine "CREATE")
               (evm-machine-charge-gas machine child-gas-used)
               (when (plusp child-state-gas-used)
                 (evm-machine-charge-state-gas
                  machine child-state-gas-used))
               (incf refund-counter child-refund-counter)
               (setf return-data-buffer child-return-data
                     logs (prepend-child-logs child-logs logs))
               (evm-stack-push machine success-address))))
         (incf pc))
        ((= op #xf5)
         (unless (and context (evm-context-state context))
           (fail "CREATE2 requires an EVM context with state"))
         (require-context-fork context
                               #'chain-rules-constantinople-p
                               "Constantinople" "CREATE2" pc)
         (when (evm-context-read-only-p context)
           (fail "CREATE2 is not allowed in read-only EVM context"))
         (let* ((value (evm-stack-pop machine))
                (offset (evm-stack-pop machine))
                (size (evm-stack-pop machine)))
           (let ((salt (evm-stack-pop machine)))
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
                      child-logs child-refund-counter child-state-gas-used)
                   (execute-contract-creation
                    state context creator new-address value initcode
                    machine "CREATE2")
                 (evm-machine-charge-gas machine child-gas-used)
                 (when (plusp child-state-gas-used)
                   (evm-machine-charge-state-gas
                    machine child-state-gas-used))
                 (incf refund-counter child-refund-counter)
                 (setf return-data-buffer child-return-data
                       logs (prepend-child-logs child-logs logs))
                 (evm-stack-push machine success-address)))))
         (incf pc))
        ((= op #xf1)
         (unless (and context (evm-context-state context))
           (fail "CALL requires an EVM context with state"))
         (let* ((requested-gas (evm-stack-pop machine))
                (address-word (evm-stack-pop machine))
                (value (evm-stack-pop machine))
                (args-offset (evm-stack-pop machine))
                (args-size (evm-stack-pop machine))
                (return-offset (evm-stack-pop machine))
                (return-size (evm-stack-pop machine)))
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
               :child-address callee
               :child-caller caller
               :child-value value
               :read-only-p (evm-context-read-only-p context)
               :charge-value-gas-p t
               :new-account-p t
               :value-transfer-from caller
               :value-transfer-to callee
               :trace-value-transfer-from caller
               :trace-value-transfer-to callee))))
         (incf pc))
        ((= op #xf3)
         (let* ((offset (evm-stack-pop machine))
                (size (evm-stack-pop machine)))
           (evm-machine-charge-memory-gas machine offset size)
           (setf return-data (memory-slice memory offset size)
                 status :returned
                 halted-p t)))
        ((= op #xf2)
         (unless (and context (evm-context-state context))
           (fail "CALLCODE requires an EVM context with state"))
         (let* ((requested-gas (evm-stack-pop machine))
                (address-word (evm-stack-pop machine))
                (value (evm-stack-pop machine))
                (args-offset (evm-stack-pop machine))
                (args-size (evm-stack-pop machine))
                (return-offset (evm-stack-pop machine))
                (return-size (evm-stack-pop machine)))
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
               :child-address current-address
               :child-caller current-address
               :child-value value
               :read-only-p (evm-context-read-only-p context)
               :charge-value-gas-p t
               :trace-value-transfer-from current-address
               :trace-value-transfer-to code-address
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
         (let* ((requested-gas (evm-stack-pop machine))
                (address-word (evm-stack-pop machine))
                (args-offset (evm-stack-pop machine))
                (args-size (evm-stack-pop machine))
                (return-offset (evm-stack-pop machine))
                (return-size (evm-stack-pop machine)))
           (execute-evm-message-call
            machine
            (make-evm-message-call
             :requested-gas requested-gas
             :code-address (word-to-address address-word)
             :args-offset args-offset
             :args-size args-size
             :return-offset return-offset
             :return-size return-size
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
         (let* ((requested-gas (evm-stack-pop machine))
                (address-word (evm-stack-pop machine))
                (args-offset (evm-stack-pop machine))
                (args-size (evm-stack-pop machine))
                (return-offset (evm-stack-pop machine))
                (return-size (evm-stack-pop machine)))
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
         (let ((beneficiary-word (evm-stack-pop machine)))
           (let ((beneficiary (word-to-address beneficiary-word)))
             (charge-cold-account-access-gas
              context
              beneficiary
              (lambda (amount) (evm-machine-charge-gas machine amount)))
            (if (and (amsterdam-context-p context)
                     (plusp
                      (account-balance
                       (evm-context-state context)
                       (evm-context-address context)))
                     (empty-account-p
                      (evm-context-state context) beneficiary))
                (progn
                  (evm-machine-charge-gas
                   machine +account-write-amsterdam+)
                  (evm-machine-charge-state-gas
                   machine +new-account-state-gas+))
                (when (and (not (amsterdam-context-p context))
                           (context-eip150-p context))
                  (evm-machine-charge-gas machine
                   (selfdestruct-extra-gas
                    (evm-context-state context)
                    (evm-context-address context)
                    beneficiary
                    :eip158-p (context-eip158-p context)))))
             ;; EIP-6780 (Cancun+): the account is deleted only when it was
             ;; created in this transaction; otherwise SELFDESTRUCT merely
             ;; transfers the balance. Pre-Cancun, deletion always applies.
             (let* ((rules (evm-context-chain-rules context))
                    (address (evm-context-address context))
                    (already-selfdestructed-p
                      (gethash (address-to-hex address)
                               (evm-context-selfdestructed-addresses context)))
                    (created-p
                      (account-created-this-transaction-p context address))
                    (delete-p
                      (or (not (and rules
                                    (chain-rules-cancun-p rules)))
                          created-p))
                    (burn-self-balance-p
                      (and delete-p
                           ;; EIP-8246 removes the post-Cancun balance burn
                           ;; for SELFDESTRUCT when beneficiary is self.
                           (not (and rules
                                     (chain-rules-amsterdam-p rules))))))
               (when (and (not (context-london-p context))
                          (not already-selfdestructed-p))
                 (incf refund-counter +selfdestruct-refund-gas+))
               (let ((transfer-log
                       (selfdestruct-account
                        (evm-context-state context)
                        address
                        beneficiary
                        rules
                        :clear-self-balance-p
                        burn-self-balance-p
                        :burn-log-p
                        (and created-p
                             rules
                             (chain-rules-amsterdam-p rules)
                             (bytes= (address-bytes address)
                                     (address-bytes beneficiary))))))
                 (when transfer-log
                   (push transfer-log logs)))
               (when delete-p
                 (mark-selfdestructed-address
                  context
                  address
                  (if (and created-p
                           rules
                           (chain-rules-amsterdam-p rules)
                           (bytes= (address-bytes address)
                                   (address-bytes beneficiary)))
                      :balance-only
                      t)))))
           (setf status :selfdestructed
                 halted-p t)))
        ((= op #xfd)
         (require-context-fork context #'chain-rules-byzantium-p
                               "Byzantium" "REVERT" pc)
         (let* ((offset (evm-stack-pop machine))
                (size (evm-stack-pop machine)))
           (evm-machine-charge-memory-gas machine offset size)
           (restore-frame-snapshot context frame-snapshot)
           (let ((state-used (max 0 (evm-gas-budget-used-state gas-budget))))
             (when (plusp state-used)
               (evm-machine-refill-state-gas machine state-used)))
           (setf return-data (memory-slice memory offset size)
                 refund-counter 0
                 status :reverted
                 halted-p t)))
        (t
         (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))
