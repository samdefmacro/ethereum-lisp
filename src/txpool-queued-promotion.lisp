(in-package #:ethereum-lisp.core)

(defun engine-payload-store-promote-queued-sender-transactions
    (store sender head base-fee &key expected-chain-id
                                  account-slot-limit
                                  global-slot-limit
                                  local-transaction-predicate)
  (let ((promoted-transactions nil))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (let ((state-nonce
              (chain-store-account-nonce store (block-hash head) sender)))
        (loop for next-nonce =
                (engine-payload-store-pending-contiguous-nonce
                 store sender state-nonce
                 :expected-chain-id expected-chain-id)
              for transaction =
                (engine-payload-store-indexed-sender-nonce-transaction
                 (engine-payload-store-queued-sender-index store)
                 sender
                 next-nonce)
              while transaction
              do (progn
                   (engine-payload-store-remove-queued-transaction
                    store
                    (transaction-hash transaction))
                   (cond
                     ((null (transaction-sender
                             transaction
                             :expected-chain-id expected-chain-id)))
                     ((and base-fee
                           (< (transaction-max-fee-per-gas transaction)
                              base-fee))
                      (engine-payload-store-put-basefee-transaction
                       store transaction)
                      (return))
                     ((engine-payload-store-transaction-funded-p
                       store transaction
                       :expected-chain-id expected-chain-id)
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
                         (engine-payload-store-put-queued-transaction
                          store transaction)
                         (return))))
                     (t
                      (engine-payload-store-put-queued-transaction
                       store transaction)
                      (return)))))))
    (nreverse promoted-transactions)))

(defun engine-payload-store-promote-queued-transactions
    (store &optional sender &key expected-chain-id
                                account-slot-limit
                                global-slot-limit
                                local-transaction-predicate)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (and header (block-header-base-fee-per-gas header)))
         (promoted-transactions nil))
    (dolist (candidate-sender
             (engine-payload-store-queued-promotion-senders store sender))
      (setf promoted-transactions
            (nconc promoted-transactions
                   (engine-payload-store-promote-queued-sender-transactions
                    store candidate-sender head base-fee
                    :expected-chain-id expected-chain-id
                    :account-slot-limit account-slot-limit
                    :global-slot-limit global-slot-limit
                    :local-transaction-predicate
                    local-transaction-predicate))))
    promoted-transactions))
