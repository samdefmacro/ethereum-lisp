(in-package #:ethereum-lisp.execution)

(defun execution-receipt-post-state (state chain-rules)
  (unless (execution-byzantium-p chain-rules)
    (hash32-bytes (state-db-root state))))

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
          (slot-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0)
          block-access-list-construction
          (block-hashes (make-hash-table)))
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp))
        (receipts '())
        (cumulative-gas 0)
        (cumulative-regular-gas 0)
        (cumulative-state-gas 0))
    (validate-execution-transaction-list-fields transactions
                                                effective-chain-rules
                                                blob-base-fee)
    (loop for tx in transactions
          for block-access-index from 1
          do
      (when block-gas-limit
        (if (execution-amsterdam-p effective-chain-rules)
            (when (or
                   (> (+ cumulative-regular-gas
                         (min +transaction-gas-limit-cap-eip7825+
                              (transaction-gas-limit tx)))
                      block-gas-limit)
                   (> (+ cumulative-state-gas
                         (transaction-gas-limit tx))
                      block-gas-limit))
              (error 'block-validation-error
                     :message "Amsterdam block gas dimension unavailable"))
            (when (> (+ cumulative-gas (transaction-gas-limit tx))
                     block-gas-limit)
              (error 'block-validation-error
                     :message "Block gas limit exceeded"))))
      (let ((receipt
              (call-with-block-access-phase
               block-access-list-construction state block-access-index
               (lambda ()
                 (validate-transaction-sender-code state sender)
                 (apply-message state sender tx
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
        (incf cumulative-gas (receipt-cumulative-gas-used receipt))
        (incf cumulative-regular-gas (receipt-regular-gas-used receipt))
        (incf cumulative-state-gas (receipt-state-gas-used receipt))
        (when (and block-gas-limit
                   (execution-amsterdam-p effective-chain-rules)
                   (or (> cumulative-regular-gas block-gas-limit)
                       (> cumulative-state-gas block-gas-limit)))
          (error 'block-validation-error
                 :message "Amsterdam block gas dimension exceeded"))
        (push (make-receipt :type (transaction-type tx)
                            :post-state
                            (execution-receipt-post-state
                             state effective-chain-rules)
                            :status (receipt-status receipt)
                            :cumulative-gas-used cumulative-gas
                            :regular-gas-used
                            (receipt-regular-gas-used receipt)
                            :state-gas-used
                            (receipt-state-gas-used receipt)
                            :logs (receipt-logs receipt))
              receipts)))
    (values (nreverse receipts) cumulative-gas
            cumulative-regular-gas cumulative-state-gas)))

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
          (slot-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0)
          block-access-list-construction
          (block-hashes (make-hash-table)))
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp))
        (receipts '())
        (cumulative-gas 0)
        (cumulative-regular-gas 0)
        (cumulative-state-gas 0))
    (validate-execution-transaction-list-fields transactions
                                                effective-chain-rules
                                                blob-base-fee)
    (let ((senders (signed-transaction-senders-or-error transactions
                                                        expected-chain-id)))
      ;; Validate every authority before the first transaction mutates state.
      (validate-transaction-senders-code state senders)
      (loop for tx in transactions
            for sender in senders
            for block-access-index from 1
            do
        (when block-gas-limit
          (if (execution-amsterdam-p effective-chain-rules)
              (when (or
                     (> (+ cumulative-regular-gas
                           (min +transaction-gas-limit-cap-eip7825+
                                (transaction-gas-limit tx)))
                        block-gas-limit)
                     (> (+ cumulative-state-gas
                           (transaction-gas-limit tx))
                        block-gas-limit))
                (error 'block-validation-error
                       :message "Amsterdam block gas dimension unavailable"))
              (when (> (+ cumulative-gas (transaction-gas-limit tx))
                       block-gas-limit)
                (error 'block-validation-error
                       :message "Block gas limit exceeded"))))
        (let ((receipt
                (call-with-block-access-phase
                 block-access-list-construction state block-access-index
                 (lambda ()
                   (apply-message
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
                    :slot-number slot-number
                    :prev-randao prev-randao
                    :difficulty difficulty
                    :random-p random-p
                    :context-gas-limit context-gas-limit
                    :block-hashes block-hashes)))))
          (incf cumulative-gas (receipt-cumulative-gas-used receipt))
          (incf cumulative-regular-gas (receipt-regular-gas-used receipt))
          (incf cumulative-state-gas (receipt-state-gas-used receipt))
          (when (and block-gas-limit
                     (execution-amsterdam-p effective-chain-rules)
                     (or (> cumulative-regular-gas block-gas-limit)
                         (> cumulative-state-gas block-gas-limit)))
            (error 'block-validation-error
                   :message "Amsterdam block gas dimension exceeded"))
          (push (make-receipt :type (transaction-type tx)
                              :post-state
                              (execution-receipt-post-state
                               state effective-chain-rules)
                              :status (receipt-status receipt)
                              :cumulative-gas-used cumulative-gas
                              :regular-gas-used
                              (receipt-regular-gas-used receipt)
                              :state-gas-used
                              (receipt-state-gas-used receipt)
                              :logs (receipt-logs receipt))
                receipts))))
    (values (nreverse receipts) cumulative-gas
            cumulative-regular-gas cumulative-state-gas)))

(defun apply-signed-message-selection
    (state candidates
     &key expected-chain-id
          (base-fee 0)
          (blob-base-fee 0)
          chain-rules
          chain-config
          block-gas-limit
          max-blob-gas
          max-transaction-bytes
          stop-predicate
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (slot-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0)
          block-access-list-construction
          (block-hashes (make-hash-table)))
  "Execute CANDIDATES in order, keeping each one that executes, in ONE pass.

The payload builder's transaction applier.  Each candidate is executed at most
once, on top of the candidates already kept.  A candidate that fails -- bad
signature or fields, non-delegation sender code, a nonce, balance or fee error,
no room left in the block's gas, blob gas, or MAX-TRANSACTION-BYTES -- is rolled
back and its sender is skipped for the rest of the pass, since that sender's
later nonces cannot execute either.  This is what geth's commitTransactions does
(miner/worker.go: a failed transaction pops its account).

Every check the import path makes on a transaction list is made here per kept
transaction, against the same state the importer will see, so the kept list
re-executes to the same receipts.  STOP-PREDICATE, called before each
candidate, ends the pass early; what was kept so far is a valid block body.

Returns (VALUES RECEIPTS GAS-USED REGULAR-GAS-USED STATE-GAS-USED KEPT
STOPPED-P), the first four exactly as APPLY-SIGNED-MESSAGE-LIST returns them for
KEPT.  Not for Amsterdam: a rolled-back candidate would leave its accesses in
the block access list under construction."
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp))
        (receipts '())
        (kept '())
        (blocked-senders (make-hash-table :test #'equal))
        (cumulative-gas 0)
        (cumulative-blob-gas 0)
        (cumulative-bytes 0)
        (stopped-p nil))
    (unless max-blob-gas
      (setf max-blob-gas
            (execution-max-blob-gas
             effective-chain-rules chain-config block-number timestamp)))
    (when (execution-amsterdam-p effective-chain-rules)
      (error 'block-validation-error
             :message "Transaction selection does not support Amsterdam"))
    (dolist (tx candidates)
      (when (and stop-predicate (funcall stop-predicate))
        (setf stopped-p t)
        (return))
      (let* ((sender
               (handler-case
                   (signed-transaction-sender-or-error tx expected-chain-id)
                 (transaction-validation-error () nil)))
             (sender-key (and sender (address-to-hex sender))))
        (when (and sender-key (not (gethash sender-key blocked-senders)))
          (let ((blob-gas (transaction-blob-gas-used tx))
                (bytes (length (transaction-encoding tx))))
            (if (or (and block-gas-limit
                         (> (+ cumulative-gas (transaction-gas-limit tx))
                            block-gas-limit))
                    (and max-blob-gas
                         (> (+ cumulative-blob-gas blob-gas) max-blob-gas))
                    (and max-transaction-bytes
                         (> (+ cumulative-bytes bytes) max-transaction-bytes)))
                (setf (gethash sender-key blocked-senders) t)
                (let ((snapshot (state-db-transaction-snapshot state)))
                  (handler-case
                      (let ((receipt
                              (progn
                                (validate-execution-transaction-list-fields
                                 (list tx) effective-chain-rules blob-base-fee)
                                (validate-transaction-sender-code state sender)
                                (call-with-block-access-phase
                                 block-access-list-construction state
                                 (1+ (length kept))
                                 (lambda ()
                                   (apply-message
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
                                    :slot-number slot-number
                                    :prev-randao prev-randao
                                    :difficulty difficulty
                                    :random-p random-p
                                    :context-gas-limit context-gas-limit
                                    :block-hashes block-hashes))))))
                        (incf cumulative-gas
                              (receipt-cumulative-gas-used receipt))
                        (incf cumulative-blob-gas blob-gas)
                        (incf cumulative-bytes bytes)
                        (push tx kept)
                        (push (make-receipt
                               :type (transaction-type tx)
                               :post-state
                               (execution-receipt-post-state
                                state effective-chain-rules)
                               :status (receipt-status receipt)
                               :cumulative-gas-used cumulative-gas
                               :regular-gas-used
                               (receipt-regular-gas-used receipt)
                               :state-gas-used
                               (receipt-state-gas-used receipt)
                               :logs (receipt-logs receipt))
                              receipts))
                    (transaction-validation-error ()
                      (state-db-revert-transaction-snapshot state snapshot)
                      (setf (gethash sender-key blocked-senders) t))
                    (block-validation-error ()
                      (state-db-revert-transaction-snapshot state snapshot)
                      (setf (gethash sender-key blocked-senders) t)))))))))
    (let ((receipts (nreverse receipts)))
      (values receipts
              cumulative-gas
              (loop for receipt in receipts
                    sum (receipt-regular-gas-used receipt))
              (loop for receipt in receipts
                    sum (receipt-state-gas-used receipt))
              (nreverse kept)
              stopped-p))))

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
