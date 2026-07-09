(in-package #:ethereum-lisp.core)

(defun transaction-location-record-rlp (location)
  (rlp-encode
   (make-rlp-list
    (hash32-bytes
     (block-hash (engine-transaction-location-block location)))
    (engine-transaction-location-index location)
    (engine-transaction-location-log-index-start location))))

(defun chain-store-export-transaction-location-to-kv
    (batch transaction-key location)
  (kv-batch-put-chain-record
   batch
   :transaction-location
   (hash32-bytes (hash32-from-hex transaction-key))
   (transaction-location-record-rlp location)))

(defun chain-store-populate-transaction-location-export-batch
    (store database batch)
  (let ((canonical-transaction-keys (make-hash-table :test 'equal)))
    (maphash
     (lambda (transaction-key location)
       (when (engine-payload-store-canonical-block-p
              store
              (engine-transaction-location-block location))
         (setf (gethash transaction-key canonical-transaction-keys) t)
         (chain-store-export-transaction-location-to-kv
          batch
          transaction-key
          location)))
     (engine-payload-memory-store-transaction-locations store))
    (dolist (entry (kv-chain-record-entries database :transaction-location))
      (unless (gethash (bytes-to-hex (car entry)) canonical-transaction-keys)
        (kv-batch-delete-chain-record
         batch
         :transaction-location
         (car entry))))))

(defun chain-store-export-transaction-locations-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain transaction location export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-transaction-location-export-batch
       store database batch)
      (kv-apply-batch database batch))))
