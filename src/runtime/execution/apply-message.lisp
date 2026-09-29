(in-package #:ethereum-lisp.execution)

(defun charge-amsterdam-call-recipient
    (state tx sender coinbase chain-id rules budget)
  "Charge BUDGET for the top-level recipient; NIL when it cannot pay.

geth v1.17.6 chargeCallRecipientEIP2780: a value transfer to an EIP-161-empty
recipient pays for the new account as state gas, and a delegated recipient
pays a cold (or, when the target is already in the access list, warm) account
access for its target. Each charge precedes the access it prices."
  (let ((recipient (transaction-to tx)))
    (and (or (not (and (plusp (transaction-value tx))
                       (execution-empty-account-p state recipient)))
             (evm-gas-budget-charge-state budget +new-account-state-gas+))
         (let ((target (set-code-delegation-target
                        (state-db-get-code state recipient))))
           (or (null target)
               (evm-gas-budget-charge
                budget
                (make-evm-gas-costs
                 :regular
                 (if (gethash (execution-account-access-key target)
                              (transaction-accessed-addresses-table
                               tx :sender sender
                                  :destination recipient
                                  :coinbase coinbase
                                  :chain-id chain-id
                                  :chain-rules rules))
                     +warm-account-access-amsterdam+
                     +cold-account-access-amsterdam+))))))))

(defun apply-amsterdam-call-runtime-charges
    (state tx sender coinbase chain-id rules budget)
  "Apply TX's authorizations and the recipient's runtime charges.

Mirrors the Amsterdam half of geth v1.17.6 executeCall before its first frame:
when BUDGET cannot cover a charge the authorizations are rolled back and NIL
is returned, and the caller halts the transaction with its gas spent."
  (let ((snapshot (state-db-snapshot state)))
    (or (and (apply-set-code-authorizations-amsterdam
              state tx chain-id sender budget)
             (charge-amsterdam-call-recipient
              state tx sender coinbase chain-id rules budget))
        (progn
          (state-db-revert-to-snapshot state snapshot)
          nil))))

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
         (*transaction-sender* sender)
         (*transaction-floor-gas*
           (transaction-effective-floor-gas tx effective-chain-rules))
         (*transaction-chain-rules* effective-chain-rules))
    (validate-execution-transaction-fields
     tx effective-chain-rules blob-base-fee)
    (validate-transaction-sender-code state sender)
    (multiple-value-prog1
        (if (transaction-to tx)
        (let* ((recipient (transaction-to tx))
               (gas-price
                 (transaction-effective-gas-price tx :base-fee base-fee))
               (intrinsic-gas
                 (execution-transaction-intrinsic-gas
                  tx effective-chain-rules))
               (runtime-budget
                 (transaction-runtime-gas-budget tx effective-chain-rules))
               (amsterdam-p (execution-amsterdam-p effective-chain-rules)))
          (state-db-touch-account state recipient)
          (charge-sender-upfront state sender tx
                                 :base-fee base-fee
                                 :blob-base-fee blob-base-fee
                                 :chain-rules effective-chain-rules)
          (when (and amsterdam-p
                     (not (apply-amsterdam-call-runtime-charges
                           state tx sender coinbase chain-id
                           effective-chain-rules runtime-budget)))
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
                   (if amsterdam-p
                       0
                       (apply-set-code-authorizations state tx chain-id)))
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
                          ;; The regular gas left after any Amsterdam
                          ;; runtime charges; before Amsterdam this is
                          ;; exactly the gas limit less intrinsic gas.
                          (evm-gas-budget-regular runtime-budget))
                       (declare (ignore output active-p))
                       (finalize-transaction-receipt
                        state sender coinbase tx
                        (make-receipt
                         :status 1
                         :cumulative-gas-used
                         (+ intrinsic-gas precompile-gas-used
                            (evm-gas-budget-used-regular runtime-budget)
                            (evm-gas-budget-used-state runtime-budget))
                         :regular-gas-used
                         (+ intrinsic-gas precompile-gas-used
                            (evm-gas-budget-used-regular runtime-budget))
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
                                    (transaction-exceptional-regular-gas-used
                                     tx effective-chain-rules)
                                    :regular-gas-used
                                    (transaction-exceptional-regular-gas-used
                                     tx effective-chain-rules))
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
                      (evm-gas-budget-used-regular runtime-budget)
                      (evm-gas-budget-used-state runtime-budget))
                   :regular-gas-used
                   (+ intrinsic-gas
                      (evm-gas-budget-used-regular runtime-budget))
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
                                    (transaction-exceptional-regular-gas-used
                                     tx effective-chain-rules)
                                    :regular-gas-used
                                    (transaction-exceptional-regular-gas-used
                                     tx effective-chain-rules))
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
