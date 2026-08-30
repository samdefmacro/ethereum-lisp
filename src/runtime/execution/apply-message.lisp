(in-package #:ethereum-lisp.execution)

(defun apply-message
    (state sender tx
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
  "Apply a transaction message and execute recipient code when present."
  (let* ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp))
         (transaction-snapshot (state-db-snapshot state))
         (*transaction-floor-gas*
           (transaction-effective-floor-gas tx effective-chain-rules))
         (*transaction-chain-rules* effective-chain-rules))
    (validate-execution-transaction-fields
     tx effective-chain-rules blob-base-fee)
    (validate-transaction-sender-code state sender)
    (multiple-value-prog1
        (if (transaction-to tx)
        (let* ((recipient (transaction-to tx))
               (gas-limit (transaction-gas-limit tx))
               (gas-price
                 (transaction-effective-gas-price tx :base-fee base-fee))
               (intrinsic-gas
                 (execution-transaction-intrinsic-gas
                  tx effective-chain-rules))
               (runtime-budget
                 (transaction-runtime-gas-budget tx effective-chain-rules))
               (new-account-state-p
                 (and (execution-amsterdam-p effective-chain-rules)
                      (plusp (transaction-value tx))
                      (execution-empty-account-p state recipient))))
          (state-db-touch-account state recipient)
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
              (return-from apply-message
                (finalize-transaction-receipt
                 state sender coinbase tx
                 (make-receipt :status 0
                               :cumulative-gas-used used
                               :regular-gas-used used)
                 base-fee))))
          (let* ((refund-counter
                   (apply-set-code-authorizations state tx chain-id))
                 (code (execution-resolved-code
                        state recipient effective-chain-rules))
                 (precompile-p
                   (active-precompile-address-p
                    recipient effective-chain-rules)))
            (cond
              (precompile-p
               (let* ((snapshot (state-db-snapshot state))
                      (transfer-log
                        (transfer-value
                         state sender recipient (transaction-value tx)
                         effective-chain-rules)))
                 (handler-case
                     (multiple-value-bind
                           (output precompile-gas-used active-p)
                         (execute-precompile
                          recipient
                          (transaction-data tx)
                          effective-chain-rules
                          (- gas-limit intrinsic-gas))
                       (declare (ignore output active-p))
                       (finalize-transaction-receipt
                        state sender coinbase tx
                        (make-receipt
                         :status 1
                         :cumulative-gas-used
                         (+ intrinsic-gas precompile-gas-used
                            (evm-gas-budget-used-state runtime-budget))
                         :regular-gas-used
                         (+ intrinsic-gas precompile-gas-used)
                         :state-gas-used
                         (evm-gas-budget-used-state runtime-budget)
                         :logs (if transfer-log
                                   (list transfer-log)
                                   '()))
                        base-fee
                        :refund-counter refund-counter))
                   (evm-error ()
                     (state-db-revert-to-snapshot state snapshot)
                     (finalize-transaction-receipt
                      state sender coinbase tx
                      (make-receipt :status 0
                                    :cumulative-gas-used
                                    (if (execution-amsterdam-p
                                         effective-chain-rules)
                                        +transaction-gas-limit-cap-eip7825+
                                        gas-limit)
                                    :regular-gas-used
                                    (if (execution-amsterdam-p
                                         effective-chain-rules)
                                        +transaction-gas-limit-cap-eip7825+
                                        gas-limit))
                      base-fee
                      :refund-counter refund-counter)))))
              ((zerop (length code))
               (let ((transfer-log
                       (transfer-value
                        state sender recipient (transaction-value tx)
                        effective-chain-rules)))
                 (finalize-transaction-receipt
                  state sender coinbase tx
                  (make-receipt
                   :status 1
                   :cumulative-gas-used
                   (+ intrinsic-gas
                      (evm-gas-budget-used-state runtime-budget))
                   :regular-gas-used intrinsic-gas
                   :state-gas-used
                   (evm-gas-budget-used-state runtime-budget)
                   :logs (if transfer-log (list transfer-log) '()))
                  base-fee
                  :refund-counter refund-counter)))
              (t
               (let* ((snapshot (state-db-snapshot state))
                      (transfer-log
                        (transfer-value
                         state sender recipient (transaction-value tx)
                         effective-chain-rules)))
                 (handler-case
                     (let* ((context
                              (make-message-evm-context
                               state sender tx recipient (transaction-data tx)
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
                              (execute-bytecode
                               code
                               :context context
                               :gas-limit
                               (evm-gas-budget-regular runtime-budget)
                               :gas-budget runtime-budget)))
                       (if (eq (evm-result-status result) :reverted)
                           (progn
                             (state-db-revert-to-snapshot state snapshot)
                             (finalize-transaction-receipt
                              state sender coinbase tx
                              (make-receipt
                               :status 0
                               :cumulative-gas-used
                               (transaction-evm-gas-used
                                tx result effective-chain-rules)
                               :regular-gas-used
                               (transaction-evm-regular-gas-used
                                tx result effective-chain-rules)
                               :state-gas-used
                               (evm-result-state-gas-used result))
                              base-fee
                              :refund-counter refund-counter))
                           (let ((receipt
                                   (finalize-transaction-receipt
                                    state sender coinbase tx
                                    (make-receipt
                                     :status 1
                                     :cumulative-gas-used
                                     (transaction-evm-gas-used
                                      tx result effective-chain-rules)
                                     :regular-gas-used
                                     (transaction-evm-regular-gas-used
                                      tx result effective-chain-rules)
                                     :state-gas-used
                                     (evm-result-state-gas-used result)
                                     :logs
                                     (if transfer-log
                                         (cons transfer-log
                                               (evm-result-logs result))
                                         (evm-result-logs result)))
                                    base-fee
                                    :refund-counter
                                    (+ refund-counter
                                       (evm-result-refund-counter result)))))
                             (finalize-evm-selfdestructs state context)
                             receipt)))
                   (evm-error ()
                     (state-db-revert-to-snapshot state snapshot)
                     (finalize-transaction-receipt
                      state sender coinbase tx
                      (make-receipt :status 0
                                    :cumulative-gas-used
                                    (if (execution-amsterdam-p
                                         effective-chain-rules)
                                        +transaction-gas-limit-cap-eip7825+
                                        gas-limit)
                                    :regular-gas-used
                                    (if (execution-amsterdam-p
                                         effective-chain-rules)
                                        +transaction-gas-limit-cap-eip7825+
                                        gas-limit))
                      base-fee
                      :refund-counter refund-counter))))))))
            (apply-contract-creation state sender tx
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
      (state-db-finalize-transaction
       state transaction-snapshot
       (or (null effective-chain-rules)
           (chain-rules-eip158-p effective-chain-rules))))))

(defun apply-signed-message
    (state tx
     &key expected-chain-id
          (base-fee 0)
          (blob-base-fee 0)
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
  "Recover the transaction sender from its signature and apply the message."
  (let ((sender (signed-transaction-sender-or-error tx expected-chain-id))
        (chain-id (transaction-context-chain-id tx expected-chain-id)))
    (apply-message state sender tx
                   :base-fee base-fee
                   :blob-base-fee blob-base-fee
                   :chain-id chain-id
                   :chain-rules chain-rules
                   :chain-config chain-config
                   :coinbase coinbase
                   :timestamp timestamp
                   :block-number block-number
                   :slot-number slot-number
                   :prev-randao prev-randao
                   :difficulty difficulty
                   :random-p random-p
                   :context-gas-limit context-gas-limit
                   :block-hashes block-hashes)))

(defun apply-legacy-message (state sender tx)
  "Apply a legacy transaction and execute recipient code when present."
  (apply-message state sender tx))
