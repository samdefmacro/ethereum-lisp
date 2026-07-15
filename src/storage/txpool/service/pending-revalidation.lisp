(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-pending-revalidation-senders (store)
  (loop for sender-key
          being the hash-keys of
            (engine-payload-store-pending-sender-index store)
        collect (address-from-hex sender-key)))

(defun engine-payload-store-demote-pending-transaction
    (store transaction base-fee)
  (engine-payload-store-remove-pending-transaction
   store
   (transaction-hash transaction))
  (if (and base-fee
           (< (transaction-max-fee-per-gas transaction) base-fee))
      (engine-payload-store-put-basefee-transaction store transaction)
      (engine-payload-store-put-queued-transaction store transaction))
  transaction)

(defun engine-payload-store-revalidate-pending-sender-transactions
    (store sender head base-fee)
  (let* ((block-hash (block-hash head))
         (state-nonce
           (chain-store-account-nonce store block-hash sender))
         (remaining-balance
           (chain-store-account-balance store block-hash sender))
         (next-nonce state-nonce)
         (blocked-p nil)
         (demoted-transactions nil))
    (dolist (transaction
             (engine-payload-store-pending-sender-transactions store sender))
      (cond
        ((< (transaction-nonce transaction) state-nonce)
         (engine-payload-store-remove-pending-transaction
          store
          (transaction-hash transaction)))
        ((or blocked-p
             (/= (transaction-nonce transaction) next-nonce)
             (and base-fee
                  (< (transaction-max-fee-per-gas transaction) base-fee)))
         (engine-payload-store-demote-pending-transaction
          store transaction base-fee)
         (setf blocked-p t)
         (push transaction demoted-transactions))
        ((< remaining-balance
            (engine-payload-store-txpool-upfront-cost transaction))
         (engine-payload-store-demote-pending-transaction
          store transaction base-fee)
         (setf blocked-p t)
         (push transaction demoted-transactions))
        (t
         (decf remaining-balance
               (engine-payload-store-txpool-upfront-cost transaction))
         (incf next-nonce))))
    (nreverse demoted-transactions)))

(defun engine-payload-store-revalidate-pending-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (demoted-transactions nil))
    (engine-payload-store-remove-invalid-sender-txpool-transactions
     store
     :expected-chain-id expected-chain-id)
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (let* ((header (block-header head))
             (base-fee (and header
                            (block-header-base-fee-per-gas header))))
        (dolist (sender
                 (engine-payload-store-pending-revalidation-senders store))
          (setf demoted-transactions
                (nconc
                 demoted-transactions
                 (engine-payload-store-revalidate-pending-sender-transactions
                  store sender head base-fee))))))
    demoted-transactions))
