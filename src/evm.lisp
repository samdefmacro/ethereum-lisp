(in-package #:ethereum-lisp.evm)

(defun execute-bytecode (code &key context gas-limit (max-steps 100000))
  (let ((code (ensure-byte-vector code))
        (pc 0)
        (steps 0)
        (gas-used 0)
        (stack '())
        (memory (make-byte-vector 0))
        (return-data (make-byte-vector 0))
        (return-data-buffer (if context
                                (ensure-byte-vector
                                 (evm-context-return-data context))
                                (make-byte-vector 0)))
        (frame-transient-snapshot (copy-transient-storage context))
        (frame-storage-clears-snapshot (copy-storage-clears context))
        (frame-accessed-storage-snapshot (copy-accessed-storage context))
        (frame-accessed-addresses-snapshot (copy-accessed-addresses context))
        (frame-selfdestructed-snapshot
          (copy-selfdestructed-addresses context))
        (original-storage-values
          (if context
              (evm-context-storage-originals context)
              (make-hash-table :test 'equalp)))
        (cleared-storage-slots
          (if context
              (evm-context-storage-clears context)
              (make-hash-table :test 'equalp)))
        (logs '())
        (refund-counter 0)
        (status :stopped))
    (labels ((binary (fn)
               (multiple-value-bind (a b rest) (pop2 stack)
                 (setf stack (stack-push rest (funcall fn a b)))))
             (comparison (predicate)
               (binary (lambda (a b) (if (funcall predicate a b) 1 0))))
             (charge-extra-gas (amount)
               (incf gas-used amount)
               (when (and gas-limit (> gas-used gas-limit))
                 (fail "EVM out of gas at pc ~D" pc)))
             (charge-call-value-gas (required charged)
               ;; The OOG boundary uses the undiscounted cost; the successful
               ;; charge may still apply the value-call stipend discount.
               (if (and gas-limit (> (+ gas-used required) gas-limit))
                   (charge-extra-gas required)
                   (charge-extra-gas charged)))
             (charge-memory-gas (offset size)
               (charge-extra-gas
                (memory-expansion-gas memory offset size)))
             (charge-copy-gas (offset size)
               (charge-extra-gas
                (+ (memory-expansion-gas memory offset size)
                   (* +copy-word-gas+ (memory-word-count size))))))
      (loop while (< pc (length code))
            do (let ((op (aref code pc)))
                 (incf steps)
                 (when (> steps max-steps)
                   (fail "EVM exceeded maximum step count ~D" max-steps))
                 (incf gas-used (opcode-base-gas op))
                 (when (and gas-limit (> gas-used gas-limit))
                   (fail "EVM out of gas at pc ~D" pc))
                 (cond
                   ((= op #x00)
                    (setf status :stopped)
                    (return))
                   ((= op #x01) (binary #'+) (incf pc))
                   ((= op #x02) (binary #'*) (incf pc))
                   ((= op #x03) (binary #'-) (incf pc))
                   ((= op #x04)
                    (binary (lambda (a b) (if (zerop b) 0 (floor a b))))
                    (incf pc))
                   ((= op #x05)
                    (binary #'signed-divide-word)
                    (incf pc))
                   ((= op #x06)
                    (binary (lambda (a b) (if (zerop b) 0 (mod a b))))
                    (incf pc))
                   ((= op #x07)
                    (binary #'signed-mod-word)
                    (incf pc))
                   ((= op #x08)
                    (multiple-value-bind (a b modulus rest) (pop3 stack)
                      (setf stack
                            (stack-push
                             rest
                             (if (zerop modulus) 0 (mod (+ a b) modulus)))))
                    (incf pc))
                   ((= op #x09)
                    (multiple-value-bind (a b modulus rest) (pop3 stack)
                      (setf stack
                            (stack-push
                             rest
                             (if (zerop modulus) 0 (mod (* a b) modulus)))))
                    (incf pc))
                   ((= op #x0a)
                    (multiple-value-bind (base exponent rest) (pop2 stack)
                      (charge-extra-gas
                       (* (exp-byte-gas
                           (and context (evm-context-chain-rules context)))
                          (exp-byte-count exponent)))
                      (setf stack
                            (stack-push rest (modexp-word base exponent))))
                    (incf pc))
                   ((= op #x0b)
                    (binary #'signextend-word)
                    (incf pc))
                   ((= op #x10) (comparison #'<) (incf pc))
                   ((= op #x11) (comparison #'>) (incf pc))
                   ((= op #x12)
                    (comparison (lambda (a b)
                                  (< (signed-word a) (signed-word b))))
                    (incf pc))
                   ((= op #x13)
                    (comparison (lambda (a b)
                                  (> (signed-word a) (signed-word b))))
                    (incf pc))
                   ((= op #x14) (comparison #'=) (incf pc))
                   ((= op #x15)
                    (multiple-value-bind (a rest) (pop1 stack)
                      (setf stack (stack-push rest (if (zerop a) 1 0))))
                    (incf pc))
                   ((= op #x16) (binary #'logand) (incf pc))
                   ((= op #x17) (binary #'logior) (incf pc))
                   ((= op #x18) (binary #'logxor) (incf pc))
                   ((= op #x19)
                    (multiple-value-bind (a rest) (pop1 stack)
                      (setf stack (stack-push rest (logxor a (1- +word-modulus+)))))
                    (incf pc))
                   ((= op #x1a)
                    (binary #'byte-op)
                    (incf pc))
                   ((= op #x1b)
                    (require-context-fork context
                                          #'chain-rules-constantinople-p
                                          "Constantinople" "SHL" pc)
                    (binary (lambda (shift value)
                              (if (>= shift 256) 0 (word (ash value shift)))))
                    (incf pc))
                   ((= op #x1c)
                    (require-context-fork context
                                          #'chain-rules-constantinople-p
                                          "Constantinople" "SHR" pc)
                    (binary (lambda (shift value)
                              (if (>= shift 256) 0 (ash value (- shift)))))
                    (incf pc))
                   ((= op #x1d)
                    (require-context-fork context
                                          #'chain-rules-constantinople-p
                                          "Constantinople" "SAR" pc)
                    (binary #'arithmetic-shift-right-word)
                    (incf pc))
                   ((= op #x20)
                    (multiple-value-bind (offset size rest) (pop2 stack)
                      (charge-extra-gas
                       (+ (memory-expansion-gas memory offset size)
                          (* +keccak256-word-gas+
                             (memory-word-count size))))
                      (setf memory (ensure-memory-size memory (+ offset size)))
                      (setf stack
                            (stack-push
                             rest
                             (bytes-to-integer
                              (keccak-256 (memory-slice memory offset size))))))
                    (incf pc))
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
                         #'charge-extra-gas)
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
                        (charge-copy-gas memory-offset size)
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
                        (charge-copy-gas memory-offset size)
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
                         #'charge-extra-gas)
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
                           #'charge-extra-gas)
                        (charge-copy-gas memory-offset size)
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
                        (charge-copy-gas memory-offset size)
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
                         #'charge-extra-gas)
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
                      (charge-memory-gas offset 32)
                      (setf memory (ensure-memory-size memory (+ offset 32))
                            stack (stack-push rest (mload memory offset))))
                    (incf pc))
                   ((= op #x52)
                    (multiple-value-bind (offset value rest) (pop2 stack)
                      (charge-memory-gas offset 32)
                      (setf memory (mstore memory offset value)
                            stack rest))
                    (incf pc))
                   ((= op #x53)
                    (multiple-value-bind (offset value rest) (pop2 stack)
                      (charge-memory-gas offset 1)
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
                         #'charge-extra-gas)
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
                          (charge-extra-gas
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
                      (charge-extra-gas
                       (+ (memory-expansion-gas
                           memory
                           0
                           (max (+ destination size) (+ source size)))
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
                   ((<= #x60 op #x7f)
                    (let ((size (- op #x5f)))
                      (setf stack (stack-push stack (read-push-immediate code pc size))
                            pc (+ pc 1 size))))
                   ((<= #x80 op #x8f)
                    (let ((depth (- op #x7f)))
                      (when (< (length stack) depth)
                        (fail "EVM stack underflow on DUP~D" depth))
                      (setf stack (stack-push stack (nth (1- depth) stack))))
                    (incf pc))
                   ((<= #x90 op #x9f)
                    (let ((depth (- op #x8f)))
                      (when (< (length stack) (1+ depth))
                        (fail "EVM stack underflow on SWAP~D" depth))
                      (rotatef (first stack) (nth depth stack)))
                    (incf pc))
                   ((<= #xa0 op #xa4)
                    (unless context
                      (fail "LOG requires an EVM context"))
                    (when (evm-context-read-only-p context)
                      (fail "LOG is not allowed in read-only EVM context"))
                   (let ((topic-count (- op #xa0)))
                      (multiple-value-bind (memory-offset size rest1)
                          (pop2 stack)
                        (charge-extra-gas
                         (+ (memory-expansion-gas memory memory-offset size)
                            (* topic-count +log-topic-gas+)
                            (* size +log-data-gas+)))
                        (setf memory
                              (ensure-memory-size memory
                                                  (+ memory-offset size)))
                        (let ((topics '())
                              (rest rest1))
                          (dotimes (i topic-count)
                            (multiple-value-bind (topic next-rest) (pop1 rest)
                              (push (word-to-hash32 topic) topics)
                              (setf rest next-rest)))
                          (push (make-log-entry
                                 :address (evm-context-address context)
                                 :topics (nreverse topics)
                                 :data (memory-slice memory memory-offset size))
                                logs)
                          (setf stack rest))))
                    (incf pc))
                   ((= op #xf0)
                    (unless (and context (evm-context-state context))
                      (fail "CREATE requires an EVM context with state"))
                   (when (evm-context-read-only-p context)
                     (fail "CREATE is not allowed in read-only EVM context"))
                    (multiple-value-bind (value offset size rest) (pop3 stack)
                      (charge-extra-gas
                       (create-initcode-extra-gas
                        size
                        :rules (evm-context-chain-rules context)))
                      (charge-memory-gas offset size)
                      (setf memory (ensure-memory-size memory (+ offset size)))
                      (let* ((state (evm-context-state context))
                             (creator (evm-context-address context))
                             (creator-account (account-or-empty state creator))
                             (new-address
                               (create-address creator
                                               (state-account-nonce
                                                creator-account)))
                             (initcode (memory-slice memory offset size))
                             (child-return-data (make-byte-vector 0))
                             (child-gas-limit
                               (child-create-gas-limit gas-limit gas-used))
                             (child-started-p nil)
                             (child-gas-used 0)
                             (child-logs '())
                             (success-address 0))
                        (when (< (state-account-balance creator-account) value)
                          (fail "Insufficient balance for CREATE value"))
                        (increment-account-nonce state creator)
                        (mark-account-accessed context new-address)
                        (if (contract-address-collision-p state new-address)
                            (setf child-gas-used (or child-gas-limit 0))
                            (let ((snapshot
                                    (capture-execution-snapshot
                                     state context)))
                              (handler-case
                                  (progn
                                    (transfer-call-value state creator new-address value)
                                    (let ((created-account
                                            (account-or-empty state new-address)))
                                      (put-account-values
                                       state
                                       new-address
                                       1
                                       (state-account-balance created-account)
                                       (state-account-code-hash created-account)))
                                    (let* ((child-context
                                             (make-child-evm-context
                                              context
                                              :state state
                                              :address new-address
                                              :caller creator
                                              :call-value value
                                              :input (make-byte-vector 0)))
                                           (child-result
                                             (progn
                                               (setf child-started-p t)
                                               (if child-gas-limit
                                                   (execute-bytecode
                                                    initcode
                                                    :context child-context
                                                    :gas-limit child-gas-limit)
                                                   (execute-bytecode
                                                    initcode
                                                    :context child-context)))))
                                      (setf child-gas-used
                                            (evm-result-gas-used child-result))
                                      (setf child-return-data
                                            (evm-result-return-data child-result))
                                      (if (eq (evm-result-status child-result)
                                              :reverted)
                                          (restore-execution-snapshot
                                           state context snapshot)
                                          (progn
                                            (setf child-logs
                                                  (evm-result-logs child-result))
                                            (when (invalid-created-runtime-code-p
                                                   child-return-data
                                                   (evm-context-chain-rules
                                                    context))
                                              (fail "CREATE produced invalid runtime code"))
                                            (incf child-gas-used
                                                  (created-code-deposit-gas
                                                   child-return-data))
                                            (when (and gas-limit
                                                       (> (+ gas-used
                                                             child-gas-used)
                                                          gas-limit))
                                              (fail "CREATE code deposit out of gas"))
                                            (state-db-set-code state
                                                               new-address
                                                               child-return-data)
                                            (incf refund-counter
                                                  (evm-result-refund-counter
                                                   child-result))
                                            (setf success-address
                                                  (address-to-word
                                                   new-address)
                                                  child-return-data
                                                  (make-byte-vector 0))))))
                                (evm-error ()
                                  (restore-execution-snapshot
                                   state context snapshot)
                                  (setf success-address 0
                                        child-return-data
                                        (make-byte-vector 0)
                                        child-logs '()
                                        child-gas-used
                                          (failed-create-child-gas-used
                                           child-started-p child-gas-limit
                                           child-gas-used))))))
                        (charge-extra-gas child-gas-used)
                        (setf return-data-buffer child-return-data
                              logs (prepend-child-logs child-logs logs)
                              stack (stack-push rest success-address))))
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
                        (charge-extra-gas
                         (create-initcode-extra-gas
                          size
                          :create2-p t
                          :rules (evm-context-chain-rules context)))
                        (charge-memory-gas offset size)
                        (setf memory (ensure-memory-size memory (+ offset size)))
                        (let* ((state (evm-context-state context))
                               (creator (evm-context-address context))
                               (creator-account (account-or-empty state creator))
                               (initcode (memory-slice memory offset size))
                               (new-address
                                 (create2-address creator salt initcode))
                               (child-return-data (make-byte-vector 0))
                               (child-gas-limit
                                 (child-create-gas-limit gas-limit gas-used))
                               (child-started-p nil)
                               (child-gas-used 0)
                               (child-logs '())
                               (success-address 0))
                          (when (< (state-account-balance creator-account) value)
                            (fail "Insufficient balance for CREATE2 value"))
                          (increment-account-nonce state creator)
                          (mark-account-accessed context new-address)
                          (if (contract-address-collision-p state new-address)
                              (setf child-gas-used (or child-gas-limit 0))
                              (let ((snapshot
                                      (capture-execution-snapshot
                                       state context)))
                                (handler-case
                                    (progn
                                      (transfer-call-value state creator new-address value)
                                      (let ((created-account
                                              (account-or-empty state new-address)))
                                        (put-account-values
                                         state
                                         new-address
                                         1
                                         (state-account-balance created-account)
                                         (state-account-code-hash created-account)))
                                      (let* ((child-context
                                               (make-child-evm-context
                                                context
                                                :state state
                                                :address new-address
                                                :caller creator
                                                :call-value value
                                                :input (make-byte-vector 0)))
                                             (child-result
                                               (progn
                                                 (setf child-started-p t)
                                                 (if child-gas-limit
                                                     (execute-bytecode
                                                      initcode
                                                      :context child-context
                                                      :gas-limit child-gas-limit)
                                                     (execute-bytecode
                                                      initcode
                                                      :context child-context)))))
                                        (setf child-gas-used
                                              (evm-result-gas-used child-result))
                                        (setf child-return-data
                                              (evm-result-return-data child-result))
                                        (if (eq (evm-result-status child-result)
                                                :reverted)
                                            (restore-execution-snapshot
                                             state context snapshot)
                                            (progn
                                              (setf child-logs
                                                    (evm-result-logs child-result))
                                              (when (invalid-created-runtime-code-p
                                                     child-return-data
                                                     (evm-context-chain-rules
                                                      context))
                                                (fail "CREATE2 produced invalid runtime code"))
                                              (incf child-gas-used
                                                    (created-code-deposit-gas
                                                     child-return-data))
                                              (when (and gas-limit
                                                         (> (+ gas-used
                                                               child-gas-used)
                                                            gas-limit))
                                                (fail "CREATE2 code deposit out of gas"))
                                              (state-db-set-code state
                                                                 new-address
                                                                 child-return-data)
                                              (incf refund-counter
                                                    (evm-result-refund-counter
                                                     child-result))
                                              (setf success-address
                                                    (address-to-word new-address)
                                                    child-return-data
                                                    (make-byte-vector 0))))))
                                  (evm-error ()
                                    (restore-execution-snapshot
                                     state context snapshot)
                                    (setf success-address 0
                                          child-return-data
                                          (make-byte-vector 0)
                                          child-logs '()
                                          child-gas-used
                                          (failed-create-child-gas-used
                                           child-started-p child-gas-limit
                                           child-gas-used))))))
                          (charge-extra-gas child-gas-used)
                          (setf return-data-buffer child-return-data
                                logs (prepend-child-logs child-logs logs)
                                stack (stack-push rest success-address)))))
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
                      (charge-extra-gas
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
                             (success 0)
                             (child-return-data (make-byte-vector 0))
                             (child-logs '())
                             (child-started-p nil)
                             (child-gas-limit 0)
                             (child-gas-used 0)
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
                         #'charge-extra-gas)
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
                          (charge-call-value-gas
                           required-value-gas
                           (call-value-extra-gas state callee value
                                                 :new-account-p t
                                                 :stipend-discount-p
                                                 stipend-discount-p)))
                        (setf child-gas-limit
                              (child-call-gas-limit
                               call-gas gas-limit gas-used
                               :stipend (if (plusp value)
                                            +call-stipend+
                                            0)))
                        (handler-case
                            (progn
                              (when (plusp value)
                                (transfer-call-value
                                 state
                                 (evm-context-address context)
                                 callee
                                 value))
                              (when (active-precompile-address-p
                                     callee
                                     (evm-context-chain-rules context))
                                (setf child-started-p t)
                                (ensure-precompile-upfront-gas
                                 callee args
                                 (evm-context-chain-rules context)
                                 child-gas-limit))
                              (multiple-value-bind
                                    (precompile-output precompile-gas precompile-p)
                                  (run-precompile callee args
                                                  (evm-context-chain-rules context))
                                (if precompile-p
                                    (progn
                                      (setf child-started-p t)
                                      (when (> precompile-gas child-gas-limit)
                                        (fail "Precompile out of gas"))
                                      (setf success 1
                                            child-gas-used precompile-gas
                                            child-return-data precompile-output))
                                    (let ((callee-code
                                            (evm-resolved-code state callee)))
                                      (if (zerop (length callee-code))
                                          (setf success 1)
                                          (let* ((child-context
                                                   (make-child-evm-context
                                                    context
                                                    :state state
                                                    :address callee
                                                    :caller (evm-context-address
                                                             context)
                                                    :call-value value
                                                    :input args
                                                    :read-only-p
                                                    (evm-context-read-only-p
                                                     context)))
                                                  (child-result
                                                   (progn
                                                     (setf child-started-p t)
                                                   (execute-bytecode callee-code
                                                                     :context child-context
                                                                     :gas-limit child-gas-limit))))
                                            (multiple-value-bind
                                                  (child-success result-gas
                                                   result-return-data result-logs
                                                   result-refund)
                                                (apply-child-execution-result
                                                 state context snapshot child-result)
                                              (setf success child-success
                                                    child-gas-used result-gas
                                                    child-return-data
                                                    result-return-data
                                                    child-logs result-logs)
                                              (incf refund-counter
                                                    result-refund))))))))
                          (evm-precompile-error (condition)
                            (restore-execution-snapshot
                             state context snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used
                                  (failed-precompile-child-gas-used
                                   condition child-gas-limit)))
                          (evm-error ()
                            (restore-execution-snapshot
                             state context snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used
                                  (failed-child-execution-gas-used
                                   child-started-p child-gas-limit
                                   child-gas-used))))
                        (charge-extra-gas
                         (if precompile-callee-p
                             child-gas-used
                             (call-child-gas-charge child-gas-used value)))
                        (setf return-data-buffer child-return-data
                              memory
                              (copy-child-return-data-to-memory
                               memory return-offset return-size child-return-data)
                              logs (prepend-child-logs child-logs logs)
                              stack (stack-push rest success))))
                    (incf pc))
                   ((= op #xf3)
                    (multiple-value-bind (offset size rest) (pop2 stack)
                      (charge-memory-gas offset size)
                      (setf return-data (memory-slice memory offset size)
                            stack rest
                            status :returned)
                      (return)))
                   ((= op #xf2)
                    (unless (and context (evm-context-state context))
                      (fail "CALLCODE requires an EVM context with state"))
                    (multiple-value-bind (call-gas address-word value
                                                  args-offset args-size
                                                  return-offset return-size rest)
                        (pop7 stack)
                      (charge-extra-gas
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
                             (success 0)
                             (child-return-data (make-byte-vector 0))
                             (child-logs '())
                             (child-started-p nil)
                             (child-gas-limit 0)
                             (child-gas-used 0)
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
                         #'charge-extra-gas)
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
                          (charge-call-value-gas
                           required-value-gas
                           (call-value-extra-gas
                            state code-address value
                            :stipend-discount-p stipend-discount-p)))
                        (setf child-gas-limit
                              (child-call-gas-limit
                               call-gas gas-limit gas-used
                               :stipend (if (plusp value)
                                            +call-stipend+
                                            0)))
                        (handler-case
                            (progn
                              (when (< (account-balance state
                                                        (evm-context-address context))
                                       value)
                                (fail "Insufficient balance for CALLCODE value"))
                              (when (active-precompile-address-p
                                     code-address
                                     (evm-context-chain-rules context))
                                (setf child-started-p t)
                                (ensure-precompile-upfront-gas
                                 code-address args
                                 (evm-context-chain-rules context)
                                 child-gas-limit))
                              (multiple-value-bind
                                    (precompile-output precompile-gas precompile-p)
                                  (run-precompile code-address args
                                                  (evm-context-chain-rules context))
                                (if precompile-p
                                    (progn
                                      (setf child-started-p t)
                                      (when (> precompile-gas child-gas-limit)
                                        (fail "Precompile out of gas"))
                                      (setf success 1
                                            child-gas-used precompile-gas
                                            child-return-data precompile-output))
                                    (let ((callee-code
                                            (evm-resolved-code state code-address)))
                                      (if (zerop (length callee-code))
                                          (setf success 1)
                                          (let* ((child-context
                                                   (make-child-evm-context
                                                    context
                                                    :state state
                                                    :address (evm-context-address
                                                              context)
                                                    :caller (evm-context-address
                                                             context)
                                                    :call-value value
                                                    :input args
                                                    :read-only-p
                                                    (evm-context-read-only-p
                                                     context)))
                                                  (child-result
                                                   (progn
                                                     (setf child-started-p t)
                                                   (execute-bytecode callee-code
                                                                     :context child-context
                                                                     :gas-limit child-gas-limit))))
                                            (multiple-value-bind
                                                  (child-success result-gas
                                                   result-return-data result-logs
                                                   result-refund)
                                                (apply-child-execution-result
                                                 state context snapshot child-result)
                                              (setf success child-success
                                                    child-gas-used result-gas
                                                    child-return-data
                                                    result-return-data
                                                    child-logs result-logs)
                                              (incf refund-counter
                                                    result-refund))))))))
                          (evm-precompile-error (condition)
                            (restore-execution-snapshot
                             state context snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used
                                  (failed-precompile-child-gas-used
                                   condition child-gas-limit)))
                          (evm-error ()
                            (restore-execution-snapshot
                             state context snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used
                                  (failed-child-execution-gas-used
                                   child-started-p child-gas-limit
                                   child-gas-used))))
                        (charge-extra-gas
                         (if precompile-code-address-p
                             child-gas-used
                             (call-child-gas-charge child-gas-used value)))
                        (setf return-data-buffer child-return-data
                              memory
                              (copy-child-return-data-to-memory
                               memory return-offset return-size child-return-data)
                              logs (prepend-child-logs child-logs logs)
                              stack (stack-push rest success))))
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
                      (charge-extra-gas
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
                             (success 0)
                             (child-return-data (make-byte-vector 0))
                             (child-logs '())
                             (child-started-p nil)
                             (child-gas-limit 0)
                             (child-gas-used 0))
                        (charge-account-access-gas
                         context
                         code-address
                         #'charge-extra-gas)
                        (refresh-execution-snapshot-accessed-addresses
                         snapshot context)
                        (setf child-gas-limit
                              (child-call-gas-limit
                               call-gas gas-limit gas-used))
                        (handler-case
                            (progn
                              (when (active-precompile-address-p
                                     code-address
                                     (evm-context-chain-rules context))
                                (setf child-started-p t)
                                (ensure-precompile-upfront-gas
                                 code-address args
                                 (evm-context-chain-rules context)
                                 child-gas-limit))
                              (multiple-value-bind
                                    (precompile-output precompile-gas precompile-p)
                                  (run-precompile code-address args
                                                  (evm-context-chain-rules context))
                                (if precompile-p
                                    (progn
                                      (setf child-started-p t)
                                      (when (> precompile-gas child-gas-limit)
                                        (fail "Precompile out of gas"))
                                      (setf success 1
                                            child-gas-used precompile-gas
                                            child-return-data precompile-output))
                                    (let ((callee-code
                                            (evm-resolved-code state code-address)))
                                      (if (zerop (length callee-code))
                                          (setf success 1)
                                          (let* ((child-context
                                                   (make-child-evm-context
                                                    context
                                                    :state state
                                                    :address (evm-context-address
                                                              context)
                                                    :caller (evm-context-caller
                                                             context)
                                                    :call-value
                                                    (evm-context-call-value
                                                     context)
                                                    :input args
                                                    :read-only-p
                                                    (evm-context-read-only-p
                                                     context)))
                                                  (child-result
                                                   (progn
                                                     (setf child-started-p t)
                                                     (execute-bytecode
                                                      callee-code
                                                      :context child-context
                                                      :gas-limit child-gas-limit))))
                                            (multiple-value-bind
                                                  (child-success result-gas
                                                   result-return-data result-logs
                                                   result-refund)
                                                (apply-child-execution-result
                                                 state context snapshot child-result)
                                              (setf success child-success
                                                    child-gas-used result-gas
                                                    child-return-data
                                                    result-return-data
                                                    child-logs result-logs)
                                              (incf refund-counter
                                                    result-refund))))))))
                          (evm-precompile-error (condition)
                            (restore-execution-snapshot
                             state context snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used
                                  (failed-precompile-child-gas-used
                                   condition child-gas-limit)))
                          (evm-error ()
                            (restore-execution-snapshot
                             state context snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-logs '()
                                  child-gas-used
                                  (failed-child-execution-gas-used
                                   child-started-p child-gas-limit
                                   child-gas-used))))
                        (charge-extra-gas child-gas-used)
                        (setf return-data-buffer child-return-data
                              memory
                              (copy-child-return-data-to-memory
                               memory return-offset return-size child-return-data)
                              logs (prepend-child-logs child-logs logs)
                              stack (stack-push rest success))))
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
                      (charge-extra-gas
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
                             (success 0)
                             (child-return-data (make-byte-vector 0))
                             (child-started-p nil)
                             (child-gas-limit 0)
                             (child-gas-used 0))
                        (charge-account-access-gas
                         context
                         callee
                         #'charge-extra-gas)
                        (refresh-execution-snapshot-accessed-addresses
                         snapshot context)
                        (setf child-gas-limit
                              (child-call-gas-limit
                               call-gas gas-limit gas-used))
                        (handler-case
                            (progn
                              (when (active-precompile-address-p
                                     callee
                                     (evm-context-chain-rules context))
                                (setf child-started-p t)
                                (ensure-precompile-upfront-gas
                                 callee args
                                 (evm-context-chain-rules context)
                                 child-gas-limit))
                              (multiple-value-bind
                                    (precompile-output precompile-gas precompile-p)
                                  (run-precompile callee args
                                                  (evm-context-chain-rules context))
                                (if precompile-p
                                    (progn
                                      (setf child-started-p t)
                                      (when (> precompile-gas child-gas-limit)
                                        (fail "Precompile out of gas"))
                                      (setf success 1
                                            child-gas-used precompile-gas
                                            child-return-data precompile-output))
                                    (let ((callee-code
                                            (evm-resolved-code state callee)))
                                      (if (zerop (length callee-code))
                                          (setf success 1)
                                          (let* ((child-context
                                                   (make-child-evm-context
                                                    context
                                                    :state state
                                                    :address callee
                                                    :caller (evm-context-address
                                                             context)
                                                    :call-value 0
                                                    :input args
                                                    :read-only-p t))
                                                  (child-result
                                                   (progn
                                                     (setf child-started-p t)
                                                     (execute-bytecode
                                                      callee-code
                                                      :context child-context
                                                      :gas-limit child-gas-limit))))
                                            (multiple-value-bind
                                                  (child-success result-gas
                                                   result-return-data result-logs
                                                   result-refund)
                                                (apply-child-execution-result
                                                 state context snapshot child-result)
                                              (declare (ignore result-logs))
                                              (setf success child-success
                                                    child-gas-used result-gas
                                                    child-return-data
                                                    result-return-data)
                                              (incf refund-counter
                                                    result-refund))))))))
                          (evm-precompile-error (condition)
                            (restore-execution-snapshot
                             state context snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-gas-used
                                  (failed-precompile-child-gas-used
                                   condition child-gas-limit)))
                          (evm-error ()
                            (restore-execution-snapshot
                             state context snapshot)
                            (setf success 0
                                  child-return-data (make-byte-vector 0)
                                  child-gas-used
                                  (failed-child-execution-gas-used
                                   child-started-p child-gas-limit
                                   child-gas-used))))
                        (charge-extra-gas child-gas-used)
                        (setf return-data-buffer child-return-data
                              memory
                              (copy-child-return-data-to-memory
                               memory return-offset return-size child-return-data)
                              stack (stack-push rest success))))
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
                         #'charge-extra-gas)
                        (charge-extra-gas
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
                            status :selfdestructed)
                      (return)))
                   ((= op #xfd)
                    (require-context-fork context #'chain-rules-byzantium-p
                                          "Byzantium" "REVERT" pc)
                    (multiple-value-bind (offset size rest) (pop2 stack)
                      (charge-memory-gas offset size)
                      (restore-transient-storage context
                                                 frame-transient-snapshot)
                      (restore-storage-clears context
                                              frame-storage-clears-snapshot)
                      (restore-accessed-storage context
                                                frame-accessed-storage-snapshot)
                      (restore-accessed-addresses
                       context
                       frame-accessed-addresses-snapshot)
                      (restore-selfdestructed-addresses
                       context
                       frame-selfdestructed-snapshot)
                      (setf return-data (memory-slice memory offset size)
                            stack rest
                            refund-counter 0
                            status :reverted)
                      (return)))
                   (t
                    (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))
    (make-evm-result :status status
                     :stack stack
                     :memory memory
                     :return-data return-data
                     :logs (nreverse logs)
                     :pc pc
                     :gas-used gas-used
                     :refund-counter refund-counter)))
