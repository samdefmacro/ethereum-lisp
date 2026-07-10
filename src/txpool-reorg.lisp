(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-reinsert-displaced-transaction
    (store transaction &key expected-chain-id chain-config)
  (let* ((hash (transaction-hash transaction))
         (head (chain-store-latest-block store))
         (sender (transaction-sender transaction
                                     :expected-chain-id expected-chain-id)))
    (when (and sender
               (not (chain-store-transaction-location store hash))
               (not (engine-payload-store-pooled-transaction store hash))
               (not (engine-payload-store-txpool-conflict-p
                     store transaction))
               (or (null head)
                   (not (engine-payload-store-over-gas-limit-txpool-transaction-p
                         head transaction)))
               (handler-case
                   (engine-payload-store-validate-txpool-blob-fee-cap
                    store
                    transaction
                    :chain-config chain-config)
                 (block-validation-error () nil))
               (engine-payload-store-sender-code-admissible-p
                store head sender)
               (engine-payload-store-transaction-admission-funded-p
                store sender transaction))
      (cond
        ((typep transaction 'blob-transaction)
         (engine-payload-store-put-blob-transaction store transaction))
        ((engine-payload-store-transaction-basefee-ineligible-p
          store transaction)
         (engine-payload-store-put-basefee-transaction store transaction))
        ((not (engine-payload-store-transaction-executable-nonce-p
               store transaction
               :expected-chain-id expected-chain-id))
         (engine-payload-store-put-queued-transaction store transaction))
        (t
         (engine-payload-store-put-pending-transaction store transaction))))))

(defun engine-payload-store-reinsert-displaced-block-transactions
    (store blocks &key expected-chain-id chain-config)
  (let ((seen-transactions (make-hash-table :test 'equal))
        (reinserted-transactions nil))
    (dolist (block (sort (copy-list blocks)
                         #'<
                         :key (lambda (block)
                                (block-header-number
                                 (block-header block)))))
      (dolist (transaction (block-transactions block))
        (let ((key (hash32-to-hex (transaction-hash transaction))))
          (unless (gethash key seen-transactions)
            (setf (gethash key seen-transactions) t)
            (when (engine-payload-store-reinsert-displaced-transaction
                   store transaction
                   :expected-chain-id expected-chain-id
                   :chain-config chain-config)
              (push transaction reinserted-transactions))))))
    (nreverse reinserted-transactions)))
