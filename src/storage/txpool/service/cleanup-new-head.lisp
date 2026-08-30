(in-package #:ethereum-lisp.txpool)

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
  (let ((head (chain-store-latest-block store)))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (engine-payload-store-remove-txpool-transactions-if
       store
       (lambda (transaction)
         (engine-payload-store-sender-code-invalid-txpool-transaction-p
          store head transaction
          :expected-chain-id expected-chain-id))))))

(defun engine-payload-store-over-gas-limit-txpool-transaction-p
    (head transaction)
  (> (transaction-gas-limit transaction)
     (block-header-gas-limit (block-header head))))

(defun engine-payload-store-remove-over-gas-limit-txpool-transactions (store)
  (let ((head (chain-store-latest-block store)))
    (when head
      (engine-payload-store-remove-txpool-transactions-if
       store
       (lambda (transaction)
         (engine-payload-store-over-gas-limit-txpool-transaction-p
          head transaction))))))

(defun engine-payload-store-remove-invalid-sender-txpool-transactions
    (store &key expected-chain-id)
  (when expected-chain-id
    (engine-payload-store-remove-txpool-transactions-if
     store
     (lambda (transaction)
       (null (transaction-sender
              transaction
              :expected-chain-id expected-chain-id))))))

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
     ;; Blob base fee is dynamic.  A transaction that is temporarily below it
     ;; must remain parked so an empty block can lower the fee and make the
     ;; transaction executable again.  Payload construction validates the
     ;; current fee and skips it while it is ineligible; canonical cleanup must
     ;; not turn that temporary condition into permanent eviction.
     (engine-payload-store-remove-sender-code-invalid-txpool-transactions
      store
      :expected-chain-id txpool-chain-id))))
