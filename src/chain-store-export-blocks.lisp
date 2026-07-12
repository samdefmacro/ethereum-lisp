(in-package #:ethereum-lisp.node-store.persistence)

(defun block-receipts-record-rlp (block)
  (let ((transactions (block-transactions block))
        (receipts (block-receipts block)))
    (unless (= (length transactions) (length receipts))
      (block-validation-fail
       "Block receipt record requires one receipt per transaction"))
    (rlp-encode
     (apply #'make-rlp-list
            (loop for transaction in transactions
                  for receipt in receipts
                  collect (transaction-receipt-encoding
                           transaction receipt))))))

(defun chain-store-export-block-record-to-kv (batch block)
  (let ((identifier (hash32-bytes (block-hash block))))
    (kv-batch-put-chain-record batch :block identifier (block-rlp block))
    (kv-batch-put-chain-record
     batch :header identifier (block-header-rlp (block-header block)))
    (kv-batch-put-chain-record
     batch :receipt identifier (block-receipts-record-rlp block))))

(defun chain-store-populate-block-record-export-batch (store database batch)
  (declare (ignore database))
  (setf store (chain-store-require-memory-store store))
  (maphash
   (lambda (key block)
     (declare (ignore key))
     (chain-store-export-block-record-to-kv batch block))
   (memory-chain-store-blocks store)))

(defun chain-store-export-block-records-to-kv (store database)
  (chain-store-apply-export-batch
   store database "block record"
   #'chain-store-populate-block-record-export-batch))
