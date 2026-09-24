(in-package #:ethereum-lisp.txpool.index)

(defun engine-pending-txpool-pending-transaction (txpool hash)
  (gethash (engine-pending-txpool-hash-key hash)
           (engine-pending-txpool-transactions txpool)))

(defun engine-pending-txpool-queued-transaction (txpool hash)
  (gethash (engine-pending-txpool-hash-key hash)
           (engine-pending-txpool-queued-transactions txpool)))

(defun engine-pending-txpool-basefee-transaction (txpool hash)
  (gethash (engine-pending-txpool-hash-key hash)
           (engine-pending-txpool-basefee-transactions txpool)))

(defun engine-pending-txpool-blob-transaction (txpool hash)
  (gethash (engine-pending-txpool-hash-key hash)
           (engine-pending-txpool-blob-transactions txpool)))

(defun engine-pending-txpool-transaction-list (transactions)
  "The transactions of subpool table TRANSACTIONS, in transaction-hash order.

Every subpool table is keyed by the hash's hex (ENGINE-PENDING-TXPOOL-HASH-KEY),
so the order comes from the keys already stored. Sorting by a freshly computed
TRANSACTION-HASH instead re-encoded the transaction twice per comparison: with
a full pool, the five whole-pool passes of one forkchoiceUpdated spent seconds
of CPU here (Hoodi b5161312, fcuCanonicalMs 2.8-3.3 s)."
  (mapcar
   #'cdr
   (sort
    (loop for key being the hash-keys of transactions
            using (hash-value transaction)
          collect (cons key transaction))
    #'string<
    :key #'car)))

(defun engine-pending-txpool-pending-transactions (txpool)
  (engine-pending-txpool-transaction-list
   (engine-pending-txpool-transactions txpool)))

(defun engine-pending-txpool-queued-transaction-list (txpool)
  (engine-pending-txpool-transaction-list
   (engine-pending-txpool-queued-transactions txpool)))

(defun engine-pending-txpool-basefee-transaction-list (txpool)
  (engine-pending-txpool-transaction-list
   (engine-pending-txpool-basefee-transactions txpool)))

(defun engine-pending-txpool-blob-transaction-list (txpool)
  (engine-pending-txpool-transaction-list
   (engine-pending-txpool-blob-transactions txpool)))

(defun engine-pending-txpool-pending-count (txpool)
  (hash-table-count (engine-pending-txpool-transactions txpool)))

(defun engine-pending-txpool-queued-count (txpool)
  (hash-table-count (engine-pending-txpool-queued-transactions txpool)))

(defun engine-pending-txpool-basefee-count (txpool)
  (hash-table-count (engine-pending-txpool-basefee-transactions txpool)))

(defun engine-pending-txpool-blob-count (txpool)
  (hash-table-count (engine-pending-txpool-blob-transactions txpool)))

(defun engine-pending-txpool-empty-p (txpool)
  (and (zerop (engine-pending-txpool-pending-count txpool))
       (zerop (engine-pending-txpool-queued-count txpool))
       (zerop (engine-pending-txpool-basefee-count txpool))
       (zerop (engine-pending-txpool-blob-count txpool))))
