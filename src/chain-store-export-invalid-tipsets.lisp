(in-package #:ethereum-lisp.chain-store.persistence)

(defun chain-store-export-invalid-tipset-to-kv
    (batch tipset-key invalid-block)
  (kv-batch-put-chain-record
   batch
   :invalid-tipset
   (hex-to-bytes tipset-key)
   (block-rlp invalid-block)))

(defun chain-store-invalid-tipset-direct-key-p
    (tipset-key invalid-block)
  (string= tipset-key
           (engine-payload-store-key (block-hash invalid-block))))

(defun chain-store-invalid-tipset-exportable-p
    (store tipset-key invalid-block)
  (let ((invalid-hash (block-hash invalid-block)))
    (and (chain-store-invalid-tipset-direct-key-p tipset-key invalid-block)
         (not (chain-store-known-block store invalid-hash)))))

(defun chain-store-populate-invalid-tipset-export-batch
    (store database batch)
  (setf store (chain-store-require-memory-store store))
  (let ((current-tipset-keys (make-hash-table :test 'equal)))
    (maphash
     (lambda (tipset-key invalid-block)
       (when (chain-store-invalid-tipset-exportable-p
              store tipset-key invalid-block)
         (setf (gethash tipset-key current-tipset-keys) t)
         (chain-store-export-invalid-tipset-to-kv
          batch tipset-key invalid-block)))
     (memory-chain-store-invalid-tipsets store))
    (dolist (entry (kv-chain-record-entries database :invalid-tipset))
      (unless (gethash (bytes-to-hex (car entry)) current-tipset-keys)
        (kv-batch-delete-chain-record
         batch
         :invalid-tipset
         (car entry))))))

(defun chain-store-export-invalid-tipsets-to-kv (store database)
  (chain-store-apply-export-batch
   store database "invalid-tipset"
   #'chain-store-populate-invalid-tipset-export-batch))
