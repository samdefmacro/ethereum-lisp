(in-package #:ethereum-lisp.evm.internal)

(defun execute-environment-opcode (machine opcode)
  "Execute call-data, code, account, and block-environment opcodes."
  (declare (type evm-machine machine) (type (unsigned-byte 8) opcode))
  (with-evm-machine-state (machine)
    (let ((op opcode))
      (cond
        ((= op #x30)
         (unless context
           (fail "ADDRESS requires an EVM context"))
         (evm-stack-push machine
                         (address-to-word (evm-context-address context)))
         (incf pc))
        ((= op #x31)
         (unless (and context (evm-context-state context))
           (fail "BALANCE requires an EVM context with state"))
         (let* ((address-word (evm-stack-pop machine))
                (address (word-to-address address-word)))
           (charge-account-access-gas
            context
            address
            (lambda (amount) (evm-machine-charge-gas machine amount)))
           (evm-stack-push machine
                           (account-balance
                            (evm-context-state context)
                            address)))
         (incf pc))
        ((= op #x32)
         (unless context
           (fail "ORIGIN requires an EVM context"))
         (evm-stack-push machine
                         (address-to-word (evm-context-origin context)))
         (incf pc))
        ((= op #x33)
         (unless context
           (fail "CALLER requires an EVM context"))
         (evm-stack-push machine
                         (address-to-word (evm-context-caller context)))
         (incf pc))
        ((= op #x34)
         (unless context
           (fail "CALLVALUE requires an EVM context"))
         (evm-stack-push machine (evm-context-call-value context))
         (incf pc))
        ((= op #x35)
         (unless context
           (fail "CALLDATALOAD requires an EVM context"))
         (let ((offset (evm-stack-pop machine)))
           (evm-stack-push machine
                           (bytes-to-integer
                            (padded-data-slice
                             (evm-context-input context) offset 32))))
         (incf pc))
        ((= op #x36)
         (unless context
           (fail "CALLDATASIZE requires an EVM context"))
         (evm-stack-push machine
                         (length (ensure-byte-vector
                                  (evm-context-input context))))
         (incf pc))
        ((= op #x37)
         (unless context
           (fail "CALLDATACOPY requires an EVM context"))
         (let* ((memory-offset (evm-stack-pop machine))
                (data-offset (evm-stack-pop machine))
                (size (evm-stack-pop machine)))
           (evm-machine-charge-copy-gas machine memory-offset size)
           (setf memory
                 (copy-into-memory
                  memory
                  memory-offset
                  (padded-data-slice
                   (evm-context-input context) data-offset size))))
         (incf pc))
        ((= op #x38)
         (evm-stack-push machine (length code))
         (incf pc))
        ((= op #x39)
         (let* ((memory-offset (evm-stack-pop machine))
                (code-offset (evm-stack-pop machine))
                (size (evm-stack-pop machine)))
           (evm-machine-charge-copy-gas machine memory-offset size)
           (setf memory
                 (copy-into-memory
                  memory
                  memory-offset
                  (padded-data-slice code code-offset size))))
         (incf pc))
        ((= op #x3a)
         (unless context
           (fail "GASPRICE requires an EVM context"))
         (evm-stack-push machine (evm-context-gas-price context))
         (incf pc))
        ((= op #x3b)
         (unless (and context (evm-context-state context))
           (fail "EXTCODESIZE requires an EVM context with state"))
         (let* ((address-word (evm-stack-pop machine))
                (address (word-to-address address-word)))
           (charge-account-access-gas
            context
            address
            (lambda (amount) (evm-machine-charge-gas machine amount)))
           (when (amsterdam-context-p context)
             (evm-machine-charge-gas
              machine +warm-account-access-amsterdam+))
           (evm-stack-push machine
                           (length
                            (state-db-get-code
                             (evm-context-state context)
                             address))))
         (incf pc))
        ((= op #x3c)
         (unless (and context (evm-context-state context))
           (fail "EXTCODECOPY requires an EVM context with state"))
         (let* ((address-word (evm-stack-pop machine))
                (memory-offset (evm-stack-pop machine))
                (code-offset (evm-stack-pop machine))
                (size (evm-stack-pop machine))
                (address (word-to-address address-word)))
           (charge-account-access-gas
            context
            address
            (lambda (amount) (evm-machine-charge-gas machine amount)))
           (when (amsterdam-context-p context)
             (evm-machine-charge-gas
              machine +warm-account-access-amsterdam+))
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
                   size))))
         (incf pc))
        ((= op #x3d)
         (unless context
           (fail "RETURNDATASIZE requires an EVM context"))
         (require-context-fork context #'chain-rules-byzantium-p
                               "Byzantium" "RETURNDATASIZE" pc)
         (evm-stack-push machine (length return-data-buffer))
         (incf pc))
        ((= op #x3e)
         (unless context
           (fail "RETURNDATACOPY requires an EVM context"))
         (require-context-fork context #'chain-rules-byzantium-p
                               "Byzantium" "RETURNDATACOPY" pc)
         (let* ((memory-offset (evm-stack-pop machine))
                (data-offset (evm-stack-pop machine))
                (size (evm-stack-pop machine)))
           (evm-machine-charge-copy-gas machine memory-offset size)
           (setf memory
                 (copy-into-memory
                  memory
                  memory-offset
                  (bounded-data-slice
                   return-data-buffer
                   data-offset
                   size
                   "RETURNDATACOPY"))))
         (incf pc))
        ((= op #x3f)
         (unless (and context (evm-context-state context))
           (fail "EXTCODEHASH requires an EVM context with state"))
         (require-context-fork context
                               #'chain-rules-constantinople-p
                               "Constantinople" "EXTCODEHASH" pc)
         (let* ((address-word (evm-stack-pop machine))
                (address (word-to-address address-word)))
           (charge-account-access-gas
            context
            address
            (lambda (amount) (evm-machine-charge-gas machine amount)))
           (evm-stack-push machine
                           (account-code-hash-word
                            (evm-context-state context)
                            address)))
         (incf pc))
        ((= op #x40)
         (unless context
           (fail "BLOCKHASH requires an EVM context"))
         (let ((number (evm-stack-pop machine)))
           (evm-stack-push machine (blockhash-word context number)))
         (incf pc))
        ((= op #x41)
         (unless context
           (fail "COINBASE requires an EVM context"))
         (evm-stack-push machine
                         (address-to-word (evm-context-coinbase context)))
         (incf pc))
        ((= op #x42)
         (unless context
           (fail "TIMESTAMP requires an EVM context"))
         (evm-stack-push machine (evm-context-timestamp context))
         (incf pc))
        ((= op #x43)
         (unless context
           (fail "NUMBER requires an EVM context"))
         (evm-stack-push machine (evm-context-block-number context))
         (incf pc))
        ((= op #x44)
         (unless context
           (fail "DIFFICULTY/PREVRANDAO requires an EVM context"))
         (evm-stack-push machine
                         (evm-context-difficulty-or-random-word context))
         (incf pc))
        ((= op #x45)
         (unless context
           (fail "GASLIMIT requires an EVM context"))
         (evm-stack-push machine (evm-context-gas-limit context))
         (incf pc))
        ((= op #x46)
         (unless context
           (fail "CHAINID requires an EVM context"))
         (require-context-fork context #'chain-rules-istanbul-p
                               "Istanbul" "CHAINID" pc)
         (evm-stack-push machine (evm-context-chain-id context))
         (incf pc))
        ((= op #x47)
         (unless (and context (evm-context-state context))
           (fail "SELFBALANCE requires an EVM context with state"))
         (require-context-fork context #'chain-rules-istanbul-p
                               "Istanbul" "SELFBALANCE" pc)
         (evm-stack-push machine
                         (account-balance
                          (evm-context-state context)
                          (evm-context-address context)))
         (incf pc))
        ((= op #x48)
         (unless context
           (fail "BASEFEE requires an EVM context"))
         (require-context-fork context #'chain-rules-london-p
                               "London" "BASEFEE" pc)
         (evm-stack-push machine (evm-context-base-fee context))
         (incf pc))
        ((= op #x49)
         (unless context
           (fail "BLOBHASH requires an EVM context"))
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "BLOBHASH" pc)
         (let ((index (evm-stack-pop machine)))
           (evm-stack-push machine (blobhash-word context index)))
         (incf pc))
        ((= op #x4a)
         (unless context
           (fail "BLOBBASEFEE requires an EVM context"))
         (require-context-fork context #'chain-rules-cancun-p
                               "Cancun" "BLOBBASEFEE" pc)
         (evm-stack-push machine (evm-context-blob-base-fee context))
         (incf pc))
        ((= op #x4b)
         (unless context
           (fail "SLOTNUM requires an EVM context"))
         (require-context-fork context #'chain-rules-amsterdam-p
                               "Amsterdam" "SLOTNUM" pc)
         (evm-stack-push machine (evm-context-slot-number context))
         (incf pc))
        (t
         (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))
