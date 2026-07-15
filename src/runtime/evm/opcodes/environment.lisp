(in-package #:ethereum-lisp.evm.internal)

(defun execute-environment-opcode (machine opcode)
  "Execute call-data, code, account, and block-environment opcodes."
  (with-evm-machine-state (machine)
    (let ((op opcode))
      (cond
        ((= op #x30)
         (unless context
           (fail "ADDRESS requires an EVM context"))
         (setf stack (stack-push stack
                                 (address-to-word
                                  (evm-context-address context))))
         (incf pc))
        ((= op #x31)
         (unless (and context (evm-context-state context))
           (fail "BALANCE requires an EVM context with state"))
         (multiple-value-bind (address-word rest) (pop1 stack)
           (let ((address (word-to-address address-word)))
             (charge-account-access-gas
              context
              address
              (lambda (amount) (evm-machine-charge-gas machine amount)))
             (setf stack
                   (stack-push
                    rest
                    (account-balance
                     (evm-context-state context)
                     address)))))
         (incf pc))
        ((= op #x32)
         (unless context
           (fail "ORIGIN requires an EVM context"))
         (setf stack (stack-push stack
                                 (address-to-word
                                  (evm-context-origin context))))
         (incf pc))
        ((= op #x33)
         (unless context
           (fail "CALLER requires an EVM context"))
         (setf stack (stack-push stack
                                 (address-to-word
                                  (evm-context-caller context))))
         (incf pc))
        ((= op #x34)
         (unless context
           (fail "CALLVALUE requires an EVM context"))
         (setf stack (stack-push stack
                                 (word (evm-context-call-value context))))
         (incf pc))
        ((= op #x35)
         (unless context
           (fail "CALLDATALOAD requires an EVM context"))
         (multiple-value-bind (offset rest) (pop1 stack)
           (setf stack
                 (stack-push
                  rest
                  (bytes-to-integer
                   (padded-data-slice
                    (evm-context-input context) offset 32)))))
         (incf pc))
        ((= op #x36)
         (unless context
           (fail "CALLDATASIZE requires an EVM context"))
         (setf stack (stack-push stack
                                 (length (ensure-byte-vector
                                          (evm-context-input context)))))
         (incf pc))
        ((= op #x37)
         (unless context
           (fail "CALLDATACOPY requires an EVM context"))
         (multiple-value-bind (memory-offset data-offset rest1)
             (pop2 stack)
           (multiple-value-bind (size rest) (pop1 rest1)
             (evm-machine-charge-copy-gas machine memory-offset size)
             (setf memory
                   (copy-into-memory
                    memory
                    memory-offset
                    (padded-data-slice
                     (evm-context-input context) data-offset size))
                   stack rest)))
         (incf pc))
        ((= op #x38)
         (setf stack (stack-push stack (length code)))
         (incf pc))
        ((= op #x39)
         (multiple-value-bind (memory-offset code-offset rest1)
             (pop2 stack)
           (multiple-value-bind (size rest) (pop1 rest1)
             (evm-machine-charge-copy-gas machine memory-offset size)
             (setf memory
                   (copy-into-memory
                    memory
                    memory-offset
                    (padded-data-slice code code-offset size))
                   stack rest)))
         (incf pc))
        ((= op #x3a)
         (unless context
           (fail "GASPRICE requires an EVM context"))
         (setf stack (stack-push stack
                                 (evm-context-gas-price context)))
         (incf pc))
        ((= op #x3b)
         (unless (and context (evm-context-state context))
           (fail "EXTCODESIZE requires an EVM context with state"))
         (multiple-value-bind (address-word rest) (pop1 stack)
           (let ((address (word-to-address address-word)))
             (charge-account-access-gas
              context
              address
              (lambda (amount) (evm-machine-charge-gas machine amount)))
             (setf stack
                   (stack-push
                    rest
                    (length
                     (state-db-get-code
                      (evm-context-state context)
                      address))))))
         (incf pc))
        ((= op #x3c)
         (unless (and context (evm-context-state context))
           (fail "EXTCODECOPY requires an EVM context with state"))
         (multiple-value-bind (address-word memory-offset rest1)
             (pop2 stack)
           (multiple-value-bind (code-offset size rest) (pop2 rest1)
             (let ((address (word-to-address address-word)))
               (charge-account-access-gas
                context
                address
                (lambda (amount) (evm-machine-charge-gas machine amount)))
             (evm-machine-charge-copy-gas machine memory-offset size)
             (setf memory
                   (copy-into-memory
                    memory
                    memory-offset
                    (padded-data-slice
                     (state-db-get-code
                      (evm-context-state context)
                      address)
                     code-offset
                     size))
                   stack rest))))
         (incf pc))
        ((= op #x3d)
         (unless context
           (fail "RETURNDATASIZE requires an EVM context"))
         (require-context-fork context #'chain-rules-byzantium-p
                               "Byzantium" "RETURNDATASIZE" pc)
         (setf stack (stack-push stack (length return-data-buffer)))
         (incf pc))
        ((= op #x3e)
         (unless context
           (fail "RETURNDATACOPY requires an EVM context"))
         (require-context-fork context #'chain-rules-byzantium-p
                               "Byzantium" "RETURNDATACOPY" pc)
         (multiple-value-bind (memory-offset data-offset rest1)
             (pop2 stack)
           (multiple-value-bind (size rest) (pop1 rest1)
             (evm-machine-charge-copy-gas machine memory-offset size)
             (setf memory
                   (copy-into-memory
                    memory
                    memory-offset
                    (bounded-data-slice
                     return-data-buffer
                     data-offset
                     size
                     "RETURNDATACOPY"))
                   stack rest)))
         (incf pc))
        ((= op #x3f)
         (unless (and context (evm-context-state context))
           (fail "EXTCODEHASH requires an EVM context with state"))
         (require-context-fork context
                               #'chain-rules-constantinople-p
                               "Constantinople" "EXTCODEHASH" pc)
         (multiple-value-bind (address-word rest) (pop1 stack)
           (let ((address (word-to-address address-word)))
             (charge-account-access-gas
              context
              address
              (lambda (amount) (evm-machine-charge-gas machine amount)))
             (setf stack
                   (stack-push
                    rest
                    (account-code-hash-word
                     (evm-context-state context)
                     address)))))
         (incf pc))
        ((= op #x40)
         (unless context
           (fail "BLOCKHASH requires an EVM context"))
         (multiple-value-bind (number rest) (pop1 stack)
           (setf stack (stack-push rest
                                   (blockhash-word context number))))
         (incf pc))
        ((= op #x41)
         (unless context
           (fail "COINBASE requires an EVM context"))
         (setf stack (stack-push stack
                                 (address-to-word
                                  (evm-context-coinbase context))))
         (incf pc))
        ((= op #x42)
         (unless context
           (fail "TIMESTAMP requires an EVM context"))
         (setf stack (stack-push stack
                                 (evm-context-timestamp context)))
         (incf pc))
        ((= op #x43)
         (unless context
           (fail "NUMBER requires an EVM context"))
         (setf stack (stack-push stack
                                 (evm-context-block-number context)))
         (incf pc))
        ((= op #x44)
         (unless context
           (fail "DIFFICULTY/PREVRANDAO requires an EVM context"))
         (setf stack (stack-push stack
                                 (evm-context-difficulty-or-random-word
                                  context)))
         (incf pc))
        ((= op #x45)
         (unless context
           (fail "GASLIMIT requires an EVM context"))
         (setf stack (stack-push stack
                                 (evm-context-gas-limit context)))
         (incf pc))
        ((= op #x46)
         (unless context
           (fail "CHAINID requires an EVM context"))
         (require-context-fork context #'chain-rules-istanbul-p
                               "Istanbul" "CHAINID" pc)
         (setf stack (stack-push stack
                                 (evm-context-chain-id context)))
         (incf pc))
        ((= op #x47)
         (unless (and context (evm-context-state context))
           (fail "SELFBALANCE requires an EVM context with state"))
         (require-context-fork context #'chain-rules-istanbul-p
                               "Istanbul" "SELFBALANCE" pc)
         (setf stack
               (stack-push stack
                           (account-balance
                            (evm-context-state context)
                            (evm-context-address context))))
         (incf pc))
        ((= op #x48)
         (unless context
           (fail "BASEFEE requires an EVM context"))
         (require-context-fork context #'chain-rules-london-p
                               "London" "BASEFEE" pc)
         (setf stack (stack-push stack
                                 (evm-context-base-fee context)))
         (incf pc))
        ((= op #x49)
         (unless context
           (fail "BLOBHASH requires an EVM context"))
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "BLOBHASH" pc)
         (multiple-value-bind (index rest) (pop1 stack)
           (setf stack
                 (stack-push rest (blobhash-word context index))))
         (incf pc))
        ((= op #x4a)
         (unless context
           (fail "BLOBBASEFEE requires an EVM context"))
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "BLOBBASEFEE" pc)
         (setf stack
               (stack-push stack
                           (evm-context-blob-base-fee context)))
         (incf pc))
        (t
         (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))


