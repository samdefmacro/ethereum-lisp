(in-package #:ethereum-lisp.core)

(defun engine-pending-txpool-indexed-conflict
    (sender-index transaction)
  (let* ((sender (engine-pending-txpool-sender-key transaction))
         (nonce (engine-pending-txpool-nonce-key transaction))
         (sender-transactions (gethash sender sender-index)))
    (and sender-transactions
         (gethash nonce sender-transactions))))

(defun engine-pending-txpool-index-transaction
    (sender-index transaction)
  (let* ((sender (engine-pending-txpool-sender-key transaction))
         (nonce (engine-pending-txpool-nonce-key transaction))
         (sender-transactions
           (or (gethash sender sender-index)
               (setf (gethash sender sender-index)
                     (make-hash-table :test 'equal)))))
    (setf (gethash nonce sender-transactions) transaction)))

(defun engine-pending-txpool-unindex-transaction
    (sender-index transaction)
  (when transaction
    (let* ((sender (engine-pending-txpool-sender-key transaction))
           (nonce (engine-pending-txpool-nonce-key transaction))
           (sender-transactions (gethash sender sender-index))
           (indexed-transaction
             (and sender-transactions
                  (gethash nonce sender-transactions))))
      (when (and indexed-transaction
                 (hash32= (transaction-hash indexed-transaction)
                          (transaction-hash transaction)))
        (remhash nonce sender-transactions)
        (when (zerop (hash-table-count sender-transactions))
          (remhash sender sender-index))))))

(defun engine-pending-txpool-sender-index-count (sender-index transaction)
  (let ((sender-transactions
          (gethash (engine-pending-txpool-sender-key transaction)
                   sender-index)))
    (if sender-transactions
        (hash-table-count sender-transactions)
        0)))

(defun engine-pending-txpool-remove-indexed-transaction
    (txpool transactions sender-index hash)
  (let* ((key (engine-pending-txpool-hash-key hash))
         (transaction (gethash key transactions)))
    (when transaction
      (engine-pending-txpool-unindex-transaction
       sender-index
       transaction)
      (engine-pending-txpool-clear-admission-time txpool hash)
      (remhash key transactions))
    transaction))
