(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-txpool (store)
  (or (txpool-component store)
      (block-validation-fail "Txpool component is not available")))

(defun engine-payload-store-enable-txpool-database-change-tracking (store)
  (engine-pending-txpool-enable-database-change-tracking
   (engine-payload-store-txpool store))
  store)

(defun engine-payload-store-txpool-database-change-tracking-enabled-p (store)
  (engine-pending-txpool-database-change-tracking-enabled-p
   (engine-payload-store-txpool store)))

(defun engine-payload-store-txpool-database-dirty-transaction-hashes (store)
  (engine-pending-txpool-database-dirty-transaction-hashes
   (engine-payload-store-txpool store)))

(defun engine-payload-store-clear-txpool-database-dirty-transaction-hashes
    (store &optional hashes)
  (engine-pending-txpool-clear-database-dirty-transaction-hashes
   (engine-payload-store-txpool store)
   hashes)
  store)

(defun engine-payload-store-pending-transaction-table (store)
  (engine-pending-txpool-transactions
   (engine-payload-store-txpool store)))

(defun engine-payload-store-pending-sender-index (store)
  (engine-pending-txpool-transactions-by-sender
   (engine-payload-store-txpool store)))

(defun engine-payload-store-queued-transaction-table (store)
  (engine-pending-txpool-queued-transactions
   (engine-payload-store-txpool store)))

(defun engine-payload-store-queued-sender-index (store)
  (engine-pending-txpool-queued-transactions-by-sender
   (engine-payload-store-txpool store)))

(defun engine-payload-store-basefee-transaction-table (store)
  (engine-pending-txpool-basefee-transactions
   (engine-payload-store-txpool store)))

(defun engine-payload-store-basefee-sender-index (store)
  (engine-pending-txpool-basefee-transactions-by-sender
   (engine-payload-store-txpool store)))

(defun engine-payload-store-blob-transaction-table (store)
  (engine-pending-txpool-blob-transactions
   (engine-payload-store-txpool store)))

(defun engine-payload-store-blob-sender-index (store)
  (engine-pending-txpool-blob-transactions-by-sender
   (engine-payload-store-txpool store)))

(defun engine-payload-store-pending-conflict (store transaction)
  (engine-pending-txpool-pending-conflict
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-txpool-conflict-p (store transaction)
  (let ((txpool (engine-payload-store-txpool store)))
    (or (engine-pending-txpool-pending-conflict txpool transaction)
        (engine-pending-txpool-queued-conflict txpool transaction)
        (engine-pending-txpool-basefee-conflict txpool transaction)
        (engine-pending-txpool-blob-conflict txpool transaction))))

(defun engine-payload-store-replacement-price-bumped-p
    (old-transaction new-transaction price-function
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (engine-pending-txpool-replacement-price-bumped-p
   old-transaction
   new-transaction
   price-function
   :price-bump-percent price-bump-percent))

(defun engine-payload-store-replacement-transaction-p
    (old-transaction new-transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (engine-pending-txpool-replacement-transaction-p
   old-transaction
   new-transaction
   :price-bump-percent price-bump-percent))

(defun engine-payload-store-index-pending-transaction (store transaction)
  (engine-pending-txpool-index-pending-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-unindex-pending-transaction (store transaction)
  (engine-pending-txpool-unindex-pending-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-index-queued-transaction (store transaction)
  (engine-pending-txpool-index-queued-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-unindex-queued-transaction (store transaction)
  (engine-pending-txpool-unindex-queued-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-index-basefee-transaction (store transaction)
  (engine-pending-txpool-index-basefee-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-unindex-basefee-transaction (store transaction)
  (engine-pending-txpool-unindex-basefee-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-index-blob-transaction (store transaction)
  (engine-pending-txpool-index-blob-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-unindex-blob-transaction (store transaction)
  (engine-pending-txpool-unindex-blob-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-remove-pending-transaction (store hash)
  (engine-pending-txpool-remove-pending-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-remove-queued-transaction (store hash)
  (engine-pending-txpool-remove-queued-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-remove-pending-conflict (store transaction)
  (engine-pending-txpool-remove-pending-conflict
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-remove-included-transaction (store transaction)
  (engine-pending-txpool-remove-included-transaction
   (engine-payload-store-txpool store)
   transaction))
