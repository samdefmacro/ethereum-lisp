(in-package #:ethereum-lisp.execution)

(defun execution-copy-equalp-table (table)
  (let ((copy (make-hash-table :test 'equalp)))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun execution-empty-access-table ()
  (make-hash-table :test 'equalp))

(defun execution-empty-access-tables ()
  (values (execution-empty-access-table)
          (execution-empty-access-table)))

(defun execution-context-access-tables (context)
  (values (execution-copy-equalp-table
           (evm-context-accessed-addresses context))
          (execution-copy-equalp-table
           (evm-context-accessed-storage context))))

(defun execution-failed-call-values
    (gas-used &optional accessed-addresses accessed-storage)
  (multiple-value-bind (empty-addresses empty-storage)
      (unless (and accessed-addresses accessed-storage)
        (execution-empty-access-tables))
    (values :failed
            (make-byte-vector 0)
            gas-used
            (or accessed-addresses empty-addresses)
            (or accessed-storage empty-storage))))

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
          (context-gas-limit 0)
          (block-hashes (make-hash-table :test 'eql)))
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
        (execution-failed-call-values gas-limit)
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
                     :context-gas-limit context-gas-limit
                     :block-hashes block-hashes))
              (let* ((result
                       (execute-bytecode
                        (transaction-data tx)
                        :context context
                        :gas-limit (- gas-limit intrinsic-gas)))
                     (return-data (copy-seq (evm-result-return-data result)))
                     (accessed-addresses nil)
                     (accessed-storage nil))
                (multiple-value-setq (accessed-addresses accessed-storage)
                  (execution-context-access-tables context))
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
                          (execution-failed-call-values
                           gas-limit accessed-addresses accessed-storage)
                          (values (evm-result-status result)
                                  return-data
                                  gas-used
                                  accessed-addresses
                                  accessed-storage))))))
          (evm-error ()
            (execution-failed-call-values gas-limit))))))

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
          (context-gas-limit 0)
          (block-hashes (make-hash-table :test 'eql)))
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
         :context-gas-limit context-gas-limit
         :block-hashes block-hashes)))
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
          (multiple-value-bind (accessed-addresses accessed-storage)
              (execution-empty-access-tables)
            (values :successful
                    (make-byte-vector 0)
                    intrinsic-gas
                    accessed-addresses
                    accessed-storage))
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
                       :context-gas-limit context-gas-limit
                       :block-hashes block-hashes)))
                (let ((result
                        (execute-bytecode
                         code
                         :context context
                         :gas-limit (- gas-limit intrinsic-gas))))
                  (multiple-value-bind (accessed-addresses accessed-storage)
                      (execution-context-access-tables context)
                    (values (evm-result-status result)
                            (copy-seq (evm-result-return-data result))
                            (transaction-evm-gas-used
                             tx result effective-chain-rules)
                            accessed-addresses
                            accessed-storage))))
            (evm-error ()
              (execution-failed-call-values gas-limit)))))))
