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

(defun settle-amsterdam-transaction
    (state sender coinbase tx base-fee budget
     &key (status 1) logs (refund-counter 0))
  "Finalize an Amsterdam transaction from its runtime BUDGET after the top
frame's leftover was absorbed: geth v1.17.6 settleGas.  The state gas is the
budget's net state usage, and everything the sender does not get back (the
regular gas left and the reservoir left) is used; the refund and the calldata
floor are then applied by FINALIZE-TRANSACTION-RECEIPT."
  (let ((state-gas (evm-gas-budget-used-state budget))
        (gas-used (- (transaction-gas-limit tx)
                     (evm-gas-budget-regular budget)
                     (evm-gas-budget-state budget))))
    (when (or (minusp state-gas) (< gas-used state-gas))
      (error 'transaction-validation-error
             :message (format nil "Amsterdam transaction settles ~D gas ~
                                   with ~D of it state gas"
                              gas-used state-gas)))
    (finalize-transaction-receipt
     state sender coinbase tx
     (make-receipt :status status
                   :cumulative-gas-used gas-used
                   ;; EIP-8037 tx_regular_gas: the calldata floor bounds the
                   ;; regular dimension even when state gas lifts the total
                   ;; above the floor.
                   :regular-gas-used (max (- gas-used state-gas)
                                          *transaction-floor-gas*)
                   :state-gas-used state-gas
                   :logs logs)
     base-fee
     :refund-counter refund-counter)))

(defun apply-amsterdam-message-call
    (state sender tx coinbase base-fee rules runtime-budget make-context)
  "Run an Amsterdam message call's top frame and settle it, after geth
v1.17.6 executeCall and settleGas.

The frame gets all of RUNTIME-BUDGET (ForwardAll); its leftover, in the
success, revert or halt form, is absorbed back.  A failed frame refills the
recipient's new-account charge when the recipient is still empty, and a
halted one burns the regular gas that refill repaid.  MAKE-CONTEXT builds the
frame's EVM context."
  (let* ((recipient (transaction-to tx))
         (value (transaction-value tx))
         (snapshot (state-db-snapshot state))
         (frame (evm-gas-budget-forward
                 runtime-budget (evm-gas-budget-regular runtime-budget)))
         (outcome :success)
         (logs '())
         (refund-counter 0)
         (context nil))
    (handler-case
        (let ((transfer-log
                (transfer-value state sender recipient value rules))
              (code (execution-resolved-code state recipient rules)))
          (cond
            ((active-precompile-address-p recipient rules)
             (let ((gas-used
                     (nth-value 1 (execute-precompile
                                   recipient (transaction-data tx) rules
                                   (evm-gas-budget-regular frame)))))
               (evm-gas-budget-charge
                frame (make-evm-gas-costs :regular gas-used))))
            ((plusp (length code))
             (setf context (funcall make-context))
             (let ((result (execute-bytecode
                            code
                            :context context
                            :gas-limit (evm-gas-budget-regular frame)
                            :gas-budget frame)))
               (if (eq (evm-result-status result) :reverted)
                   (setf outcome :reverted
                         frame (evm-gas-budget-exit-revert frame))
                   (setf logs (evm-result-logs result)
                         refund-counter (evm-result-refund-counter result))))))
          (when (and transfer-log (eq outcome :success))
            (push transfer-log logs)))
      (evm-error ()
        (setf outcome :halted
              logs '()
              refund-counter 0
              frame (evm-gas-budget-exit-halt frame))))
    (evm-gas-budget-absorb runtime-budget frame)
    (unless (eq outcome :success)
      (state-db-revert-to-snapshot state snapshot)
      (when (and (plusp value)
                 (execution-empty-account-p state recipient))
        (evm-gas-budget-refill-state runtime-budget +new-account-state-gas+))
      (when (eq outcome :halted)
        (evm-gas-budget-drain-regular runtime-budget)))
    (prog1 (settle-amsterdam-transaction
            state sender coinbase tx base-fee runtime-budget
            :status (if (eq outcome :success) 1 0)
            :logs logs
            :refund-counter refund-counter)
      (when (and context (eq outcome :success))
        (finalize-evm-selfdestructs state context)))))

(defun create-message-recipient-before-eip158 (state recipient rules)
  "Before EIP-158 a message call makes an absent RECIPIENT, whatever the value
(go-ethereum v1.17.6 EVM.Call); from EIP-158 a zero-value call to one does
not, and a transfer creates it by crediting it."
  (unless (or (transaction-eip158-active-p rules)
              (state-db-get-account state recipient))
    (state-db-set-account state recipient (make-state-account))))

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
          (when amsterdam-p
            (return-from apply-message
              (if (apply-amsterdam-call-runtime-charges
                   state tx sender coinbase chain-id
                   effective-chain-rules runtime-budget)
                  (apply-amsterdam-message-call
                   state sender tx coinbase base-fee effective-chain-rules
                   runtime-budget
                   (lambda ()
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
                      :block-hashes block-hashes)))
                  (settle-amsterdam-transaction
                   state sender coinbase tx base-fee
                   (evm-gas-budget-exit-halt runtime-budget)
                   :status 0))))
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
                        (progn
                          (create-message-recipient-before-eip158
                           state recipient effective-chain-rules)
                          (transfer-value
                           state sender recipient (transaction-value tx)
                           effective-chain-rules))))
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
                       (progn
                         (create-message-recipient-before-eip158
                          state recipient effective-chain-rules)
                         (transfer-value
                          state sender recipient (transaction-value tx)
                          effective-chain-rules))))
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
