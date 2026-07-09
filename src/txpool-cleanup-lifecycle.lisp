(in-package #:ethereum-lisp.core)

(defun engine-payload-store-stale-txpool-transaction-p
    (store head transaction &key expected-chain-id)
  (let ((sender (transaction-sender
                 transaction
                 :expected-chain-id expected-chain-id)))
    (and sender
         (chain-store-state-available-p store (block-hash head))
         (< (transaction-nonce transaction)
            (chain-store-account-nonce
             store
             (block-hash head)
             sender)))))

(defun engine-payload-store-remove-stale-txpool-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (flet ((remove-stale (transactions remove-function)
               (dolist (transaction transactions)
                 (when (engine-payload-store-stale-txpool-transaction-p
                        store head transaction
                        :expected-chain-id expected-chain-id)
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-stale
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-stale
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-stale
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-stale
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-expired-txpool-transaction-p
    (store transaction lifetime-seconds now)
  (let ((admitted-at
          (engine-pending-txpool-admission-time
           (engine-payload-store-txpool store)
           transaction)))
    (and admitted-at
         (>= (- now admitted-at) lifetime-seconds))))

(defun engine-payload-store-remove-expired-txpool-queued-view-transactions
    (store lifetime-seconds now &key local-transaction-predicate)
  (let ((removed-transactions nil))
    (when lifetime-seconds
      (unless (and (integerp lifetime-seconds) (not (minusp lifetime-seconds)))
        (block-validation-fail
         "Txpool lifetime must be a non-negative integer"))
      (unless (and (integerp now) (not (minusp now)))
        (block-validation-fail
         "Txpool cleanup time must be a non-negative integer"))
      (flet ((remove-expired (transactions remove-function)
               (dolist (transaction transactions)
                 (when (and (not (and local-transaction-predicate
                                       (funcall local-transaction-predicate
                                                transaction)))
                            (engine-payload-store-expired-txpool-transaction-p
                             store transaction lifetime-seconds now))
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-expired
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-expired
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-expired
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))
