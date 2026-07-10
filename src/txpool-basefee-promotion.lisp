(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-promote-basefee-transactions
    (store &key expected-chain-id account-slot-limit global-slot-limit
                local-transaction-predicate)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (and header (block-header-base-fee-per-gas header)))
         (promoted-transactions nil))
    (if (and head
             (chain-store-state-available-p store (block-hash head)))
        (dolist (sender
                 (engine-payload-store-indexed-senders
                  (engine-payload-store-basefee-sender-index store)))
          (loop for next-nonce =
                  (engine-payload-store-pending-contiguous-nonce
                   store
                   sender
                   (chain-store-account-nonce
                    store
                    (block-hash head)
                    sender)
                   :expected-chain-id expected-chain-id)
                for transaction =
                  (engine-payload-store-indexed-sender-nonce-transaction
                   (engine-payload-store-basefee-sender-index store)
                   sender
                   next-nonce)
                while transaction
                do (cond
                     ((null (transaction-sender
                             transaction
                             :expected-chain-id expected-chain-id))
                      (engine-pending-txpool-remove-basefee-transaction
                       (engine-payload-store-txpool store)
                       (transaction-hash transaction)))
                     ((engine-payload-store-basefee-promotable-transaction-p
                       store transaction base-fee
                       :expected-chain-id expected-chain-id)
                      (engine-pending-txpool-remove-basefee-transaction
                       (engine-payload-store-txpool store)
                       (transaction-hash transaction))
                      (case
                          (engine-payload-store-promote-transaction-to-pending
                           store
                           transaction
                           :account-slot-limit account-slot-limit
                           :global-slot-limit global-slot-limit
                           :local-transaction-predicate
                           local-transaction-predicate)
                        (:promoted
                         (push transaction promoted-transactions))
                        (:slot-limit
                         (engine-payload-store-put-basefee-transaction
                          store transaction)
                         (return))))
                     (t
                      (return)))))
        (loop for transaction =
                (find-if
                 (lambda (transaction)
                   (or (null (transaction-sender
                              transaction
                              :expected-chain-id expected-chain-id))
                       (engine-payload-store-basefee-promotable-transaction-p
                        store transaction base-fee
                        :expected-chain-id expected-chain-id)))
                 (engine-payload-store-basefee-transactions store))
              while transaction
              do (if (null (transaction-sender
                            transaction
                            :expected-chain-id expected-chain-id))
                     (engine-pending-txpool-remove-basefee-transaction
                      (engine-payload-store-txpool store)
                      (transaction-hash transaction))
                     (progn
                       (engine-pending-txpool-remove-basefee-transaction
                        (engine-payload-store-txpool store)
                        (transaction-hash transaction))
                       (case
                           (engine-payload-store-promote-transaction-to-pending
                            store
                            transaction
                            :account-slot-limit account-slot-limit
                            :global-slot-limit global-slot-limit
                            :local-transaction-predicate
                            local-transaction-predicate)
                         (:promoted
                          (push transaction promoted-transactions))
                         (:slot-limit
                          (engine-payload-store-put-basefee-transaction
                           store transaction)
                          (return)))))))
    (nreverse promoted-transactions)))

(defun engine-payload-store-promote-basefee-and-queued-transactions
    (store &key expected-chain-id account-slot-limit global-slot-limit
                local-transaction-predicate)
  (let ((basefee-promoted
          (engine-payload-store-promote-basefee-transactions
           store
           :expected-chain-id expected-chain-id
           :account-slot-limit account-slot-limit
           :global-slot-limit global-slot-limit
           :local-transaction-predicate local-transaction-predicate))
        (queued-promoted nil)
        (seen-senders (make-hash-table :test 'equal)))
    (dolist (transaction basefee-promoted)
      (let ((sender (transaction-sender
                     transaction
                     :expected-chain-id expected-chain-id)))
        (when sender
          (let ((sender-key (address-to-hex sender)))
            (unless (gethash sender-key seen-senders)
              (setf (gethash sender-key seen-senders) t)
              (setf queued-promoted
                    (nconc queued-promoted
                           (engine-payload-store-promote-queued-transactions
                            store
                            :sender sender
                            :expected-chain-id expected-chain-id
                            :account-slot-limit account-slot-limit
                            :global-slot-limit global-slot-limit
                            :local-transaction-predicate
                            local-transaction-predicate))))))))
    (values basefee-promoted queued-promoted)))
