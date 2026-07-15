(in-package #:ethereum-lisp.txpool.index)

(defun engine-pending-txpool-pending-conflict (txpool transaction)
  (engine-pending-txpool-indexed-conflict
   (engine-pending-txpool-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-queued-conflict (txpool transaction)
  (engine-pending-txpool-indexed-conflict
   (engine-pending-txpool-queued-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-basefee-conflict (txpool transaction)
  (engine-pending-txpool-indexed-conflict
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-blob-conflict (txpool transaction)
  (engine-pending-txpool-indexed-conflict
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-index-pending-transaction
    (txpool transaction)
  (engine-pending-txpool-index-transaction
   (engine-pending-txpool-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-index-queued-transaction
    (txpool transaction)
  (engine-pending-txpool-index-transaction
   (engine-pending-txpool-queued-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-index-basefee-transaction
    (txpool transaction)
  (engine-pending-txpool-index-transaction
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-index-blob-transaction
    (txpool transaction)
  (engine-pending-txpool-index-transaction
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-unindex-pending-transaction
    (txpool transaction)
  (engine-pending-txpool-unindex-transaction
   (engine-pending-txpool-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-unindex-queued-transaction
    (txpool transaction)
  (engine-pending-txpool-unindex-transaction
   (engine-pending-txpool-queued-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-unindex-basefee-transaction
    (txpool transaction)
  (engine-pending-txpool-unindex-transaction
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-unindex-blob-transaction
    (txpool transaction)
  (engine-pending-txpool-unindex-transaction
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-remove-pending-transaction (txpool hash)
  (engine-pending-txpool-remove-indexed-transaction
   txpool
   (engine-pending-txpool-transactions txpool)
   (engine-pending-txpool-transactions-by-sender txpool)
   hash))

(defun engine-pending-txpool-remove-queued-transaction (txpool hash)
  (engine-pending-txpool-remove-indexed-transaction
   txpool
   (engine-pending-txpool-queued-transactions txpool)
   (engine-pending-txpool-queued-transactions-by-sender txpool)
   hash))

(defun engine-pending-txpool-remove-basefee-transaction (txpool hash)
  (engine-pending-txpool-remove-indexed-transaction
   txpool
   (engine-pending-txpool-basefee-transactions txpool)
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   hash))

(defun engine-pending-txpool-remove-blob-transaction (txpool hash)
  (engine-pending-txpool-remove-indexed-transaction
   txpool
   (engine-pending-txpool-blob-transactions txpool)
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   hash))
