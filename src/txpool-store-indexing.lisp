(in-package #:ethereum-lisp.core)

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

(defun engine-payload-store-remove-included-transaction
    (store transaction)
  (engine-pending-txpool-remove-included-transaction
   (engine-payload-store-txpool store)
   transaction))
