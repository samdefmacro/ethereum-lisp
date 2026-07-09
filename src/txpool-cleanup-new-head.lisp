(in-package #:ethereum-lisp.core)

(defun engine-payload-store-sender-code-invalid-txpool-transaction-p
    (store head transaction &key expected-chain-id)
  (let ((sender (transaction-sender
                 transaction
                 :expected-chain-id expected-chain-id)))
    (and sender
         (not (engine-payload-store-sender-code-admissible-p
               store
               head
               sender)))))

(defun engine-payload-store-remove-sender-code-invalid-txpool-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (flet ((remove-sender-code-invalid
                 (transactions remove-function)
               (dolist (transaction transactions)
                 (when (engine-payload-store-sender-code-invalid-txpool-transaction-p
                        store head transaction
                        :expected-chain-id expected-chain-id)
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-sender-code-invalid
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-sender-code-invalid
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-sender-code-invalid
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-sender-code-invalid
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-over-gas-limit-txpool-transaction-p
    (head transaction)
  (> (transaction-gas-limit transaction)
     (block-header-gas-limit (block-header head))))

(defun engine-payload-store-remove-over-gas-limit-txpool-transactions (store)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when head
      (flet ((remove-over-gas (transactions remove-function)
               (dolist (transaction transactions)
                 (when (engine-payload-store-over-gas-limit-txpool-transaction-p
                        head transaction)
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-over-gas
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-over-gas
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-over-gas
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-over-gas
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-remove-underpriced-blob-txpool-transactions
    (store &key chain-config)
  (let ((blob-base-fee
          (engine-payload-store-current-blob-base-fee
           store
           chain-config))
        (removed-transactions nil))
    (when blob-base-fee
      (dolist (transaction (engine-payload-store-blob-transactions store))
        (handler-case
            (validate-blob-transaction-fee-cap transaction blob-base-fee)
          (block-validation-error ()
            (engine-pending-txpool-remove-blob-transaction
             (engine-payload-store-txpool store)
             (transaction-hash transaction))
            (push transaction removed-transactions)))))
    (nreverse removed-transactions)))

(defun engine-payload-store-remove-invalid-sender-txpool-transactions
    (store &key expected-chain-id)
  (let ((removed-transactions nil))
    (when expected-chain-id
      (flet ((remove-invalid-sender
                 (transactions remove-function)
               (dolist (transaction transactions)
                 (when (null (transaction-sender
                              transaction
                              :expected-chain-id expected-chain-id))
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-invalid-sender
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-invalid-sender
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-invalid-sender
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-invalid-sender
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-chain-config-expected-chain-id
    (expected-chain-id chain-config)
  (or expected-chain-id
      (and chain-config
           (chain-config-chain-id chain-config))))

(defun engine-payload-store-remove-new-head-invalid-txpool-transactions
    (store &key expected-chain-id chain-config)
  (let ((txpool-chain-id
          (engine-payload-store-chain-config-expected-chain-id
           expected-chain-id
           chain-config)))
    (nconc
     (engine-payload-store-remove-invalid-sender-txpool-transactions
      store
      :expected-chain-id txpool-chain-id)
     (engine-payload-store-remove-stale-txpool-transactions
      store
      :expected-chain-id txpool-chain-id)
     (engine-payload-store-remove-over-gas-limit-txpool-transactions store)
     (engine-payload-store-remove-underpriced-blob-txpool-transactions
      store
      :chain-config chain-config)
     (engine-payload-store-remove-sender-code-invalid-txpool-transactions
      store
      :expected-chain-id txpool-chain-id))))
