(in-package #:ethereum-lisp.execution)

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
