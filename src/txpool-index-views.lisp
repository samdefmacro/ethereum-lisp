(in-package #:ethereum-lisp.core)

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
  (sort
   (loop for transaction
           being the hash-values of
             transactions
         collect transaction)
   #'string<
   :key (lambda (transaction)
          (hash32-to-hex (transaction-hash transaction)))))

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
