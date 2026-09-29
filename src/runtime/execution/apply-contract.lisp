(in-package #:ethereum-lisp.execution)

(defun run-amsterdam-creation-frame (state sender tx contract rules frame
                                     make-context)
  "Deploy TX's initcode at CONTRACT on FRAME, after geth v1.17.6 EVM.create
and initNewContract under Amsterdam.  Returns (VALUES OUTCOME FRAME LOGS
REFUND CONTEXT), OUTCOME one of :SUCCESS, :REVERTED and :HALTED and FRAME in
its leftover form.  The caller reverts the state of a failed creation."
  (when (execution-contract-address-collision-p state contract)
    ;; EIP-8037: a collision burns the regular gas and keeps the reservoir.
    (return-from run-amsterdam-creation-frame
      (values :halted (evm-gas-budget-exit-halt frame) '() 0 nil)))
  (handler-case
      (let ((transfer-log
              (transfer-value state sender contract (transaction-value tx)
                              rules))
            (contract-account (execution-account-or-empty state contract)))
        (put-execution-account-values
         state contract 1
         (state-account-balance contract-account)
         (state-account-code-hash contract-account))
        (let* ((context (funcall make-context))
               (result
                 (progn
                   ;; EIP-6780: the new contract counts as created in this
                   ;; transaction, so an initcode SELFDESTRUCT deletes it.
                   (mark-created-account context contract)
                   (execute-bytecode (transaction-data tx)
                                     :context context
                                     :gas-limit (evm-gas-budget-regular frame)
                                     :gas-budget frame))))
          (if (eq (evm-result-status result) :reverted)
              (values :reverted (evm-gas-budget-exit-revert frame) '() 0 nil)
              (let ((code (evm-result-return-data result)))
                (if (and (not (invalid-contract-runtime-code-p code rules))
                         (evm-gas-budget-charge
                          frame
                          (make-evm-gas-costs
                           :regular (* +keccak256-word-gas+
                                       (ceiling (length code) 32))))
                         (evm-gas-budget-charge-state
                          frame (* +cost-per-state-byte+ (length code))))
                    (progn
                      (state-db-set-code state contract code)
                      (values :success frame
                              (if transfer-log
                                  (cons transfer-log (evm-result-logs result))
                                  (evm-result-logs result))
                              (evm-result-refund-counter result)
                              context))
                    (values :halted (evm-gas-budget-exit-halt frame)
                            '() 0 nil))))))
    (evm-error ()
      (values :halted (evm-gas-budget-exit-halt frame) '() 0 nil))))

(defun apply-amsterdam-contract-creation
    (state sender coinbase tx base-fee rules contract runtime-budget
     make-context)
  "Run an Amsterdam creation transaction's top frame and settle it, after
geth v1.17.6 executeCreate and settleGas: an empty destination is charged its
account creation as state gas first (an unaffordable charge halts the
transaction), the frame gets all of the budget, a failed creation refills the
account-creation charge, and a halted one burns the regular gas that refill
repaid."
  (let ((charged-p nil))
    (when (execution-empty-account-p state contract)
      (unless (evm-gas-budget-charge-state runtime-budget
                                           +new-account-state-gas+)
        (return-from apply-amsterdam-contract-creation
          (settle-amsterdam-transaction
           state sender coinbase tx base-fee
           (evm-gas-budget-exit-halt runtime-budget)
           :status 0)))
      (setf charged-p t))
    (let ((snapshot (state-db-snapshot state))
          (frame (evm-gas-budget-forward
                  runtime-budget (evm-gas-budget-regular runtime-budget))))
      (multiple-value-bind (outcome exit logs refund-counter context)
          (run-amsterdam-creation-frame
           state sender tx contract rules frame make-context)
        (evm-gas-budget-absorb runtime-budget exit)
        (unless (eq outcome :success)
          (state-db-revert-to-snapshot state snapshot)
          (when charged-p
            (evm-gas-budget-refill-state runtime-budget
                                         +new-account-state-gas+))
          (when (eq outcome :halted)
            (evm-gas-budget-drain-regular runtime-budget)))
        (prog1 (settle-amsterdam-transaction
                state sender coinbase tx base-fee runtime-budget
                :status (if (eq outcome :success) 1 0)
                :logs logs
                :refund-counter refund-counter)
          (when context
            (finalize-evm-selfdestructs state context)))))))

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
         (*transaction-chain-rules* effective-chain-rules)
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
    (when (execution-amsterdam-p effective-chain-rules)
      (return-from apply-contract-creation
        (apply-amsterdam-contract-creation
         state sender coinbase tx base-fee effective-chain-rules contract
         runtime-budget
         (lambda ()
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
            :block-hashes block-hashes)))))
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
    (let ((snapshot (state-db-snapshot state))
          (transfer-log nil))
      (handler-case
          (if (execution-contract-address-collision-p state contract)
              (progn
               (evm-call-tracer-note-top-level
                :failure "contract address collision")
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
               base-fee))
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
                   (if (chain-rules-eip158-active-p effective-chain-rules)
                       1
                       0)
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
                        (evm-call-tracer-note-top-level
                         :output (evm-result-return-data result)
                         :failure :reverted)
                        (state-db-revert-to-snapshot state snapshot)
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
                               ;; Frontier: a deposit the remaining gas
                               ;; cannot pay leaves the contract without
                               ;; code and charges nothing for it (go-ethereum
                               ;; v1.17.6 EVM.create, ErrCodeStoreOutOfGas
                               ;; before Homestead).
                               (frontier-deposit-out-of-gas-p
                                 (and (not amsterdam-p)
                                      (not (transaction-homestead-active-p
                                            effective-chain-rules))
                                      (> (+ (transaction-evm-gas-used
                                             tx result effective-chain-rules)
                                            (contract-code-deposit-gas
                                             runtime-code))
                                         gas-limit)))
                               (runtime-code
                                 (if frontier-deposit-out-of-gas-p
                                     (make-byte-vector 0)
                                     runtime-code))
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
                                (evm-call-tracer-note-top-level
                                 :failure
                                 (if (invalid-contract-runtime-code-p
                                      runtime-code
                                      (evm-context-chain-rules context))
                                     "invalid code"
                                     "contract creation code storage out of gas"))
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
                                 base-fee))
                              (progn
                                (evm-call-tracer-note-top-level
                                 :output runtime-code)
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
                (evm-error (condition)
          (evm-call-tracer-note-top-level :failure condition)
          (state-db-revert-to-snapshot state snapshot)
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
