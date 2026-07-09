(in-package #:ethereum-lisp.execution)

(defun execution-copy-equalp-table (table)
  (let ((copy (make-hash-table :test 'equalp)))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun execute-contract-creation-call
    (state sender tx effective-chain-rules
     &key (base-fee 0)
          (blob-base-fee 0)
          (chain-id 0)
          chain-config
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  (let* ((call-state (state-db-copy state))
         (contract (execution-create-address
                    sender
                    (transaction-nonce tx)))
         (gas-limit (transaction-gas-limit tx))
         (gas-price (call-transaction-effective-gas-price
                     tx :base-fee base-fee))
         (context-base-fee
           (call-transaction-context-base-fee gas-price base-fee))
         (intrinsic-gas (execution-transaction-intrinsic-gas
                         tx effective-chain-rules)))
    (if (execution-contract-address-collision-p call-state contract)
        (values :failed
                (make-byte-vector 0)
                gas-limit
                (make-hash-table :test 'equalp)
                (make-hash-table :test 'equalp))
        (handler-case
            (let ((context nil))
              (transfer-call-value-for-simulation
               call-state sender contract (transaction-value tx))
              (let ((contract-account
                      (execution-account-or-empty call-state contract)))
                (put-execution-account-values
                 call-state
                 contract
                 1
                 (state-account-balance contract-account)
                 (state-account-code-hash contract-account)))
              (setf context
                    (make-message-evm-context
                     call-state sender tx contract (make-byte-vector 0)
                     gas-price
                     :base-fee context-base-fee
                     :blob-base-fee blob-base-fee
                     :chain-id chain-id
                     :chain-rules effective-chain-rules
                     :chain-config chain-config
                     :coinbase coinbase
                     :timestamp timestamp
                     :block-number block-number
                     :prev-randao prev-randao
                     :difficulty difficulty
                     :random-p random-p
                     :context-gas-limit context-gas-limit))
              (let* ((result
                       (execute-bytecode
                        (transaction-data tx)
                        :context context
                        :gas-limit (- gas-limit intrinsic-gas)))
                     (return-data (copy-seq (evm-result-return-data result)))
                     (accessed-addresses
                       (execution-copy-equalp-table
                        (evm-context-accessed-addresses context)))
                     (accessed-storage
                       (execution-copy-equalp-table
                        (evm-context-accessed-storage context))))
                (if (eq (evm-result-status result) :reverted)
                    (values :reverted
                            return-data
                            (transaction-evm-gas-used
                             tx result effective-chain-rules)
                            accessed-addresses
                            accessed-storage)
                    (let ((gas-used
                            (+ (transaction-evm-gas-used
                                tx result effective-chain-rules)
                               (contract-code-deposit-gas return-data))))
                      (if (or (invalid-contract-runtime-code-p
                               return-data
                               (evm-context-chain-rules context))
                              (> gas-used gas-limit))
                          (values :failed
                                  (make-byte-vector 0)
                                  gas-limit
                                  accessed-addresses
                                  accessed-storage)
                          (values (evm-result-status result)
                                  return-data
                                  gas-used
                                  accessed-addresses
                                  accessed-storage))))))
          (evm-error ()
            (values :failed
                    (make-byte-vector 0)
                    gas-limit
                    (make-hash-table :test 'equalp)
                    (make-hash-table :test 'equalp)))))))

(defun execute-message-call
    (state sender tx
     &key (base-fee 0)
          (blob-base-fee 0)
          (chain-id 0)
          chain-rules
          chain-config
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  "Execute a call-style transaction against a copied state DB.

Returns status, return data, gas used, accessed-address table, and
accessed-storage table as multiple values. The caller's state object is never
mutated."
  (let* ((effective-chain-rules
           (execution-chain-rules chain-rules chain-config block-number timestamp))
         (recipient (transaction-to tx)))
    (validate-call-transaction-fields tx effective-chain-rules)
    (unless recipient
      (return-from execute-message-call
        (execute-contract-creation-call
         state sender tx effective-chain-rules
         :base-fee base-fee
         :blob-base-fee blob-base-fee
         :chain-id chain-id
         :chain-config chain-config
         :coinbase coinbase
         :timestamp timestamp
         :block-number block-number
         :prev-randao prev-randao
         :difficulty difficulty
         :random-p random-p
         :context-gas-limit context-gas-limit)))
    (let* ((call-state (state-db-copy state))
           (gas-limit (transaction-gas-limit tx))
           (gas-price (call-transaction-effective-gas-price
                       tx :base-fee base-fee))
           (context-base-fee
             (call-transaction-context-base-fee gas-price base-fee))
           (intrinsic-gas (execution-transaction-intrinsic-gas
                           tx effective-chain-rules))
           (code (execution-resolved-code call-state recipient)))
      (transfer-call-value-for-simulation
       call-state sender recipient (transaction-value tx))
      (if (zerop (length code))
          (values :successful
                  (make-byte-vector 0)
                  intrinsic-gas
                  (make-hash-table :test 'equalp)
                  (make-hash-table :test 'equalp))
          (handler-case
              (let ((context
                      (make-message-evm-context
                       call-state sender tx recipient (transaction-data tx)
                       gas-price
                       :base-fee context-base-fee
                       :blob-base-fee blob-base-fee
                       :chain-id chain-id
                       :chain-rules effective-chain-rules
                       :chain-config chain-config
                       :coinbase coinbase
                       :timestamp timestamp
                       :block-number block-number
                       :prev-randao prev-randao
                       :difficulty difficulty
                       :random-p random-p
                       :context-gas-limit context-gas-limit)))
                (let ((result
                        (execute-bytecode
                         code
                         :context context
                         :gas-limit (- gas-limit intrinsic-gas))))
                (values (evm-result-status result)
                        (copy-seq (evm-result-return-data result))
                        (transaction-evm-gas-used
                         tx result effective-chain-rules)
                        (execution-copy-equalp-table
                         (evm-context-accessed-addresses context))
                        (execution-copy-equalp-table
                         (evm-context-accessed-storage context)))))
            (evm-error ()
              (values :failed
                      (make-byte-vector 0)
                      gas-limit
                      (make-hash-table :test 'equalp)
                      (make-hash-table :test 'equalp))))))))
