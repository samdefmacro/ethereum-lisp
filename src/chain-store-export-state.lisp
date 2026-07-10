(in-package #:ethereum-lisp.chain-store.persistence)

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
  (chain-store-apply-export-batch
   store database "state record"
   #'chain-store-populate-state-record-export-batch))
