(in-package #:ethereum-lisp.execution)

(defun apply-contract-creation (state sender tx
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
  (let* ((effective-chain-rules
           (execution-chain-rules chain-rules chain-config block-number timestamp))
         (intrinsic-gas (execution-transaction-intrinsic-gas
                         tx effective-chain-rules))
         (sender-account (execution-account-or-empty state sender))
         (contract (execution-create-address
                    sender
                    (state-account-nonce sender-account)))
         (gas-limit (transaction-gas-limit tx))
         (gas-price (transaction-effective-gas-price tx :base-fee base-fee)))
    (validate-contract-initcode-size tx effective-chain-rules)
    (charge-sender-upfront state sender tx
                           :base-fee base-fee
                           :blob-base-fee blob-base-fee
                           :chain-rules effective-chain-rules)
    (let ((snapshot (state-db-copy state)))
      (handler-case
          (if (execution-contract-address-collision-p state contract)
              (finalize-transaction-receipt
               state sender coinbase tx
               (make-receipt :status 0 :cumulative-gas-used gas-limit)
               base-fee)
              (progn
                (transfer-value state sender contract
                                (transaction-value tx))
                (let ((contract-account
                        (execution-account-or-empty state contract)))
                  (put-execution-account-values
                   state
                   contract
                   1
                   (state-account-balance contract-account)
                   (state-account-code-hash contract-account)))
                (let* ((context
                         (make-message-evm-context
                          state sender tx contract (make-byte-vector 0)
                          gas-price
                          :base-fee base-fee
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
                       (result
                         (execute-bytecode
                          (transaction-data tx)
                                  :context context
                                  :gas-limit (- gas-limit intrinsic-gas))))
                  (if (eq (evm-result-status result) :reverted)
                      (progn
                        (state-db-restore state snapshot)
                        (finalize-transaction-receipt
                         state sender coinbase tx
                         (make-receipt :status 0
                                               :cumulative-gas-used
                                               (transaction-evm-gas-used
                                            tx result effective-chain-rules))
                         base-fee))
                      (progn
                        (let* ((runtime-code (evm-result-return-data result))
                                       (gas-used (+ (transaction-evm-gas-used
                                                  tx result effective-chain-rules)
                                                    (contract-code-deposit-gas
                                                     runtime-code))))
                          (if (or (invalid-contract-runtime-code-p
                                   runtime-code
                                   (evm-context-chain-rules context))
                                  (> gas-used gas-limit))
                              (progn
                                (state-db-restore state snapshot)
                                (finalize-transaction-receipt
                                 state sender coinbase tx
                                 (make-receipt :status 0
                                               :cumulative-gas-used gas-limit)
                                 base-fee))
                              (progn
                                (state-db-set-code state contract runtime-code)
                                (let ((receipt
                                        (finalize-transaction-receipt
                                         state sender coinbase tx
                                         (make-receipt
                                          :status 1
                                          :cumulative-gas-used gas-used
                                          :logs (evm-result-logs result))
                                         base-fee
                                         :refund-counter
                                         (evm-result-refund-counter result))))
                                  (finalize-evm-selfdestructs state context)
                                  receipt)))))))))
                (evm-error ()
          (state-db-restore state snapshot)
          (finalize-transaction-receipt
           state sender coinbase tx
           (make-receipt :status 0 :cumulative-gas-used gas-limit)
           base-fee))))))
