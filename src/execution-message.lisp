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
          (context-gas-limit 0))
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
                            :context-gas-limit context-gas-limit))
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
		                               :context-gas-limit context-gas-limit))))

(defun transaction-declared-chain-id (tx)
  (typecase tx
    (legacy-transaction
     (legacy-transaction-chain-id tx))
    (access-list-transaction
     (access-list-transaction-chain-id tx))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-chain-id tx))
    (blob-transaction
     (blob-transaction-chain-id tx))
    (set-code-transaction
     (set-code-transaction-chain-id tx))
    (t 0)))

(defun transaction-context-chain-id (tx expected-chain-id)
  (or expected-chain-id
      (transaction-declared-chain-id tx)
      0))

(defun signed-transaction-sender-or-error (tx expected-chain-id)
  (or (transaction-sender tx :expected-chain-id expected-chain-id)
      (error 'transaction-validation-error
             :message "Invalid transaction signature")))

(defun signed-transaction-senders-or-error (transactions expected-chain-id)
  (mapcar (lambda (tx)
            (signed-transaction-sender-or-error tx expected-chain-id))
          transactions))

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
          (context-gas-limit 0))
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
                   :context-gas-limit context-gas-limit)))

(defun apply-legacy-message (state sender tx)
  "Apply a legacy transaction and execute recipient code when present."
  (apply-message state sender tx))

(defun apply-message-list
    (state sender transactions
     &key (base-fee 0)
          (blob-base-fee 0)
          (chain-id 0)
          chain-rules
          chain-config
          block-gas-limit
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp))
        (receipts '())
        (cumulative-gas 0))
    (validate-execution-transaction-list-fields transactions
                                                effective-chain-rules
                                                blob-base-fee)
    (validate-transaction-sender-code state sender)
    (dolist (tx transactions)
      (when (and block-gas-limit
                 (> (+ cumulative-gas (transaction-gas-limit tx))
                    block-gas-limit))
        (error 'block-validation-error :message "Block gas limit exceeded"))
      (let ((receipt (apply-message state sender tx
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
                                    :context-gas-limit context-gas-limit)))
        (incf cumulative-gas (receipt-cumulative-gas-used receipt))
        (push (make-receipt :status (receipt-status receipt)
                            :cumulative-gas-used cumulative-gas
                            :logs (receipt-logs receipt))
              receipts)))
    (values (nreverse receipts) cumulative-gas)))

(defun apply-signed-message-list
    (state transactions
     &key expected-chain-id
          (base-fee 0)
          (blob-base-fee 0)
          chain-rules
          chain-config
          block-gas-limit
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp))
        (receipts '())
        (cumulative-gas 0))
    (validate-execution-transaction-list-fields transactions
                                                effective-chain-rules
                                                blob-base-fee)
    (let ((senders (signed-transaction-senders-or-error transactions
                                                        expected-chain-id)))
      (validate-transaction-senders-code state senders)
      (loop for tx in transactions
            for sender in senders
            do
        (when (and block-gas-limit
                   (> (+ cumulative-gas (transaction-gas-limit tx))
                      block-gas-limit))
          (error 'block-validation-error :message "Block gas limit exceeded"))
        (let ((receipt (apply-message
                        state sender tx
                        :base-fee base-fee
                        :blob-base-fee blob-base-fee
                        :chain-id (transaction-context-chain-id
                                   tx expected-chain-id)
                        :chain-rules effective-chain-rules
                        :chain-config chain-config
                        :coinbase coinbase
                        :timestamp timestamp
                        :block-number block-number
                        :prev-randao prev-randao
                        :difficulty difficulty
                        :random-p random-p
                        :context-gas-limit context-gas-limit)))
          (incf cumulative-gas (receipt-cumulative-gas-used receipt))
          (push (make-receipt :status (receipt-status receipt)
                              :cumulative-gas-used cumulative-gas
                              :logs (receipt-logs receipt))
                receipts))))
    (values (nreverse receipts) cumulative-gas)))

(defun apply-legacy-message-list (state sender transactions)
  (apply-message-list state sender transactions))

(defun execute-legacy-messages (state sender transactions)
  (multiple-value-bind (receipts gas-used)
      (apply-legacy-message-list state sender transactions)
    (declare (ignore gas-used))
    (make-execution-result
     :receipts receipts
     :state-root (state-db-root state)
     :transactions-root (transaction-list-root transactions)
     :receipts-root (transaction-receipt-list-root transactions receipts))))
(defun execute-signed-messages
    (state transactions &key expected-chain-id chain-rules chain-config)
  (multiple-value-bind (receipts gas-used)
      (apply-signed-message-list state transactions
                                 :expected-chain-id expected-chain-id
                                 :chain-rules chain-rules
                                 :chain-config chain-config)
    (declare (ignore gas-used))
    (make-execution-result
     :receipts receipts
     :state-root (state-db-root state)
     :transactions-root (transaction-list-root transactions)
     :receipts-root (transaction-receipt-list-root transactions receipts))))
