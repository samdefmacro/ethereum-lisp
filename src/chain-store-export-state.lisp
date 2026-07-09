(in-package #:ethereum-lisp.core)

(defun state-storage-entry-rlp-object (entry)
  (make-rlp-list
   (hash32-bytes (car entry))
   (cdr entry)))

(defun state-account-snapshot-rlp-object
    (address balance nonce code storage-entries)
  (make-rlp-list
   (address-bytes address)
   balance
   nonce
   code
   (apply #'make-rlp-list
          (mapcar #'state-storage-entry-rlp-object storage-entries))))

(defun chain-store-state-record-rlp (store block-hash)
  (let ((accounts '()))
    (chain-store-for-each-account
     store
     block-hash
     (lambda (address balance nonce code storage-entries)
       (push
        (state-account-snapshot-rlp-object
         address balance nonce code storage-entries)
        accounts)))
    (rlp-encode (apply #'make-rlp-list (nreverse accounts)))))

(defun chain-store-export-state-record-to-kv
    (store batch block-key)
  (let ((block-hash (hash32-from-hex block-key)))
    (kv-batch-put-chain-record
     batch
     :state
     (hash32-bytes block-hash)
     (chain-store-state-record-rlp store block-hash))))

(defun chain-store-populate-state-record-export-batch
    (store database batch)
  (dolist (entry (kv-chain-record-entries database :state))
    (unless (gethash (bytes-to-hex (car entry))
                     (engine-payload-memory-store-state-blocks store))
      (kv-batch-delete-chain-record batch :state (car entry))))
  (maphash
   (lambda (block-key state-available-p)
     (when state-available-p
       (chain-store-export-state-record-to-kv store batch block-key)))
   (engine-payload-memory-store-state-blocks store)))

(defun chain-store-export-state-records-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain state record export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-state-record-export-batch store database batch)
      (kv-apply-batch database batch))))
