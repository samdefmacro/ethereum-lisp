(in-package #:ethereum-lisp.core)

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

(defun chain-store-populate-block-record-export-batch (store batch)
  (maphash
   (lambda (key block)
     (declare (ignore key))
     (chain-store-export-block-record-to-kv batch block))
   (engine-payload-memory-store-blocks store)))

(defun chain-store-export-block-records-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain block record export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-block-record-export-batch store batch)
      (kv-apply-batch database batch))))
