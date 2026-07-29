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
                                     (slot-number 0)
                                     (prev-randao (zero-hash32))
                                     (difficulty 0)
                                     (random-p t)
                                     (context-gas-limit 0)
                                     (block-hashes (make-hash-table)))
  (let* ((effective-chain-rules
           (execution-chain-rules chain-rules chain-config block-number timestamp))
         (*transaction-floor-gas*
           (transaction-effective-floor-gas tx effective-chain-rules))
         (intrinsic-gas (execution-transaction-intrinsic-gas
                         tx effective-chain-rules))
         (sender-account (execution-account-or-empty state sender))
         (contract (execution-create-address
                    sender
                    (state-account-nonce sender-account)))
         (gas-limit (transaction-gas-limit tx))
         (gas-price (transaction-effective-gas-price tx :base-fee base-fee))
         (runtime-budget
           (transaction-runtime-gas-budget tx effective-chain-rules))
         (new-account-state-p
           (and (execution-amsterdam-p effective-chain-rules)
                (execution-empty-account-p state contract))))
    (validate-contract-initcode-size tx effective-chain-rules)
    (charge-sender-upfront state sender tx
                           :base-fee base-fee
                           :blob-base-fee blob-base-fee
                           :chain-rules effective-chain-rules)
    (when (and new-account-state-p
               (not (evm-gas-budget-charge-state
                     runtime-budget +new-account-state-gas+)))
      (let ((used
              (transaction-exceptional-regular-gas-used
               tx effective-chain-rules)))
        (return-from apply-contract-creation
          (finalize-transaction-receipt
           state sender coinbase tx
           (make-receipt :status 0
                         :cumulative-gas-used used
                         :regular-gas-used used)
           base-fee))))
    (let ((snapshot (state-db-copy state))
          (transfer-log nil))
      (handler-case
          (if (execution-contract-address-collision-p state contract)
              (finalize-transaction-receipt
               state sender coinbase tx
               (make-receipt
                :status 0
                :cumulative-gas-used
                (transaction-exceptional-regular-gas-used
                 tx effective-chain-rules)
                :regular-gas-used
                (transaction-exceptional-regular-gas-used
                 tx effective-chain-rules))
               base-fee)
              (progn
                (setf transfer-log
                      (transfer-value
                       state sender contract (transaction-value tx)
                       effective-chain-rules))
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
                          :slot-number slot-number
                          :prev-randao prev-randao
                          :difficulty difficulty
                          :random-p random-p
                          :context-gas-limit context-gas-limit
                          :block-hashes block-hashes))
                       (result
                         (progn
                           ;; EIP-6780: the new contract counts as created in
                           ;; this transaction, so an initcode SELFDESTRUCT of
                           ;; it deletes the account.
                           (mark-created-account context contract)
                           (execute-bytecode
                            (transaction-data tx)
                            :context context
                            :gas-limit
                            (evm-gas-budget-regular runtime-budget)
                            :gas-budget runtime-budget))))
                  (if (eq (evm-result-status result) :reverted)
                      (progn
                        (state-db-restore state snapshot)
                        (finalize-transaction-receipt
                         state sender coinbase tx
                         (make-receipt :status 0
                                               :cumulative-gas-used
                                               (transaction-evm-gas-used
                                            tx result effective-chain-rules)
                                               :regular-gas-used
                                               (transaction-evm-regular-gas-used
                                                tx result
                                                effective-chain-rules)
                                               :state-gas-used
                                               (evm-result-state-gas-used result))
                         base-fee))
                      (progn
                        (let* ((runtime-code (evm-result-return-data result))
                               (amsterdam-p
                                 (execution-amsterdam-p
                                  effective-chain-rules))
                               (deposit-regular
                                 (if amsterdam-p
                                     (* +keccak256-word-gas+
                                        (ceiling (length runtime-code) 32))
                                     (contract-code-deposit-gas runtime-code)))
                               (deposit-state
                                 (if amsterdam-p
                                     (* +cost-per-state-byte+
                                        (length runtime-code))
                                     0))
                               (deposit-ok-p
                                 (if amsterdam-p
                                     (evm-gas-budget-charge
                                      runtime-budget
                                      (make-evm-gas-costs
                                       :regular deposit-regular
                                       :state deposit-state))
                                     t))
                               (gas-used
                                 (+ (transaction-evm-gas-used
                                     tx result effective-chain-rules)
                                    deposit-regular deposit-state)))
                          (if (or (invalid-contract-runtime-code-p
                                   runtime-code
                                   (evm-context-chain-rules context))
                                  (not deposit-ok-p)
                                  (> gas-used gas-limit))
                              (progn
                                (state-db-restore state snapshot)
                                (finalize-transaction-receipt
                                 state sender coinbase tx
                                 (make-receipt :status 0
                                               :cumulative-gas-used
                                               (transaction-exceptional-regular-gas-used
                                                tx effective-chain-rules)
                                               :regular-gas-used
                                               (transaction-exceptional-regular-gas-used
                                                tx effective-chain-rules))
                                 base-fee))
                              (progn
                                (state-db-set-code state contract runtime-code)
                                (let ((receipt
                                        (finalize-transaction-receipt
                                         state sender coinbase tx
                                         (make-receipt
                                          :status 1
                                          :cumulative-gas-used gas-used
                                          :regular-gas-used
                                          (+ (transaction-evm-regular-gas-used
                                              tx result
                                              effective-chain-rules)
                                             deposit-regular)
                                          :state-gas-used
                                          (+ (evm-result-state-gas-used result)
                                             deposit-state)
                                          :logs
                                          (if transfer-log
                                              (cons transfer-log
                                                    (evm-result-logs result))
                                              (evm-result-logs result)))
                                         base-fee
                                         :refund-counter
                                         (evm-result-refund-counter result))))
                                  (finalize-evm-selfdestructs state context)
                                  receipt)))))))))
                (evm-error ()
          (state-db-restore state snapshot)
          (finalize-transaction-receipt
           state sender coinbase tx
           (make-receipt
            :status 0
            :cumulative-gas-used
            (transaction-exceptional-regular-gas-used
             tx effective-chain-rules)
            :regular-gas-used
            (transaction-exceptional-regular-gas-used
             tx effective-chain-rules))
           base-fee))))))
