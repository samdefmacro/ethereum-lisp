(in-package #:ethereum-lisp.txpool.index)

(defun engine-pending-txpool-copy-transaction (transaction transaction-copies)
  (or (gethash transaction transaction-copies)
      (setf (gethash transaction transaction-copies)
            (transaction-from-encoding (transaction-encoding transaction)))))

(defun engine-pending-txpool-copy-transaction-table
    (table transaction-copies)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key transaction)
               (setf (gethash key copy)
                     (engine-pending-txpool-copy-transaction
                      transaction
                      transaction-copies)))
             table)
    copy))

(defun engine-pending-txpool-copy-metadata-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun engine-pending-txpool-copy-sender-index
    (table transaction-copies)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (sender nonce-table)
               (let ((nonce-copy
                       (make-hash-table :test (hash-table-test nonce-table))))
                 (maphash
                  (lambda (nonce transaction)
                    (setf (gethash nonce nonce-copy)
                          (engine-pending-txpool-copy-transaction
                           transaction
                           transaction-copies)))
                  nonce-table)
                 (setf (gethash sender copy) nonce-copy)))
             table)
    copy))

(defun engine-pending-txpool-copy (txpool)
  (let ((transaction-copies (make-hash-table :test 'eq)))
    (make-engine-pending-txpool
     :transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-transactions txpool)
      transaction-copies)
     :transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-transactions-by-sender txpool)
      transaction-copies)
     :queued-transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-queued-transactions txpool)
      transaction-copies)
     :queued-transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-queued-transactions-by-sender txpool)
      transaction-copies)
     :basefee-transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-basefee-transactions txpool)
      transaction-copies)
     :basefee-transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-basefee-transactions-by-sender txpool)
      transaction-copies)
     :blob-transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-blob-transactions txpool)
      transaction-copies)
     :blob-transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-blob-transactions-by-sender txpool)
      transaction-copies)
     :transaction-admitted-at
     (engine-pending-txpool-copy-metadata-table
      (engine-pending-txpool-transaction-admitted-at txpool)))))
