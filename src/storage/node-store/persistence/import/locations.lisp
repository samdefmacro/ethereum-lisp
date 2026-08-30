(in-package #:ethereum-lisp.node-store.persistence)

(defun transaction-location-record-values (record)
  (let ((fields (rlp-list-field (rlp-decode-one record)
                                "Transaction location record")))
    (unless (= (length fields) 3)
      (block-validation-fail
       "Transaction location record must contain 3 fields"))
    (values
     (rlp-hash32-field (first fields) "Transaction location block hash")
     (rlp-uint-field (second fields) "Transaction location index")
     (rlp-uint-field (third fields) "Transaction location log index start"))))

(defun chain-store-expected-log-index-start (receipts index)
  (loop for receipt in receipts
        for receipt-index from 0 below index
        do (unless receipt
             (block-validation-fail
              "KV transaction location references a missing receipt"))
        sum (length (receipt-logs receipt))))

(defun chain-store-transaction-location-from-kv
    (store transaction-identifier location-record
     &key canonical-block-p-function)
  "Decode and fully validate one durable canonical transaction location.

CANONICAL-BLOCK-P-FUNCTION defaults to STORE's current canonical view.  A
direct durable provider may instead validate against the database snapshot:
during forkchoice the in-memory canonical overlay changes before the atomic KV
batch, so the old durable transaction location is valid in that snapshot even
though public lookup must already hide it from the new canonical view."
  (setf store (chain-store-require-memory-store store))
  (let ((transaction-hash (make-hash32 transaction-identifier)))
    (multiple-value-bind (block-hash index log-index-start)
        (transaction-location-record-values location-record)
      (let* ((block (chain-store-known-block store block-hash))
             (transactions (and block (block-transactions block))))
        (unless block
          (block-validation-fail
           "KV transaction location references an unknown block"))
        (unless (if canonical-block-p-function
                    (funcall canonical-block-p-function block)
                    (engine-payload-store-canonical-block-p store block))
          (block-validation-fail
           "KV transaction location references a non-canonical block"))
        (unless (< index (length transactions))
          (block-validation-fail
           "KV transaction location index is outside the block body"))
        (let* ((receipts (block-receipts block))
               (transaction (nth index transactions))
               (receipt (nth index receipts)))
          (unless (hash32= transaction-hash (transaction-hash transaction))
            (block-validation-fail
             "KV transaction location key does not match block transaction"))
          (unless receipt
            (block-validation-fail
             "KV transaction location references a missing receipt"))
          (unless (= log-index-start
                     (chain-store-expected-log-index-start receipts index))
            (block-validation-fail
             "KV transaction location log index is inconsistent"))
          (make-engine-transaction-location
           :block block
           :index index
           :transaction transaction
           :receipt receipt
           :log-index-start log-index-start))))))

(defun chain-store-import-transaction-location-from-kv
    (store transaction-identifier location-record)
  (setf store (chain-store-require-memory-store store))
  (let ((location
          (chain-store-transaction-location-from-kv
           store transaction-identifier location-record)))
    (setf (gethash (bytes-to-hex transaction-identifier)
                   (memory-chain-store-transaction-locations store))
          location)
    location))

(defun chain-store-import-transaction-locations-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :transaction-location))
    (chain-store-import-transaction-location-from-kv
     store (car entry) (cdr entry))))
