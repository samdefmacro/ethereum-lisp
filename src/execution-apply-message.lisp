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
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0)
          (block-hashes (make-hash-table)))
  "Apply a transaction message and execute recipient code when present."
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
  (validate-execution-transaction-fields tx effective-chain-rules blob-base-fee)
  (validate-transaction-sender-code state sender)
  (if (transaction-to tx)
      (let* ((recipient (transaction-to tx))
             (gas-limit (transaction-gas-limit tx))
             (gas-price (transaction-effective-gas-price tx :base-fee base-fee)))
        (charge-sender-upfront state sender tx
                               :base-fee base-fee
                               :blob-base-fee blob-base-fee
                               :chain-rules effective-chain-rules)
        (let* ((refund-counter
                 (apply-set-code-authorizations state tx chain-id))
               (code (execution-resolved-code state recipient)))
        (if (zerop (length code))
            (progn
              (transfer-value state sender recipient
                              (transaction-value tx))
              (finalize-transaction-receipt
               state sender coinbase tx
               (make-receipt :status 1
                                     :cumulative-gas-used
                                     (execution-transaction-intrinsic-gas
                                  tx effective-chain-rules))
               base-fee
               :refund-counter refund-counter))
            (let ((snapshot (state-db-copy state)))
              (transfer-value state sender recipient
                              (transaction-value tx))
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
                            :prev-randao prev-randao
                            :difficulty difficulty
                            :random-p random-p
                            :context-gas-limit context-gas-limit
                            :block-hashes block-hashes))
                         (result (execute-bytecode code
                                                   :context context
                                                           :gas-limit (- gas-limit
                                                                         (execution-transaction-intrinsic-gas
                                                                      tx effective-chain-rules)))))
                    (if (eq (evm-result-status result) :reverted)
                        (progn
                          (state-db-restore state snapshot)
                          (finalize-transaction-receipt
                           state sender coinbase tx
                           (make-receipt :status 0
                                                 :cumulative-gas-used
                                                 (transaction-evm-gas-used
                                              tx result effective-chain-rules))
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
                                  :logs (evm-result-logs result))
                                 base-fee
                                 :refund-counter
                                 (+ refund-counter
                                    (evm-result-refund-counter result)))))
                          (finalize-evm-selfdestructs state context)
                          receipt)))
                (evm-error ()
                  (state-db-restore state snapshot)
                  (finalize-transaction-receipt
                   state sender coinbase tx
                   (make-receipt :status 0
                                 :cumulative-gas-used gas-limit)
                   base-fee
                   :refund-counter refund-counter)))))))
      (apply-contract-creation state sender tx
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
                               :context-gas-limit context-gas-limit
                               :block-hashes block-hashes))))

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
                   :prev-randao prev-randao
                   :difficulty difficulty
                   :random-p random-p
                   :context-gas-limit context-gas-limit
                   :block-hashes block-hashes)))

(defun apply-legacy-message (state sender tx)
  "Apply a legacy transaction and execute recipient code when present."
  (apply-message state sender tx))
