(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-export-remote-block-to-kv (batch block-key block)
  (kv-batch-put-chain-record
   batch
   :remote-block
   (hex-to-bytes block-key)
   (chain-store-block-record-rlp block))
  (chain-store-populate-block-access-list-side-data-batch batch block))

(defun chain-store-remote-block-exportable-p (store block-key block)
  (let ((block-hash (block-hash block)))
    (and (string= block-key (engine-payload-store-key block-hash))
         (not (chain-store-known-block store block-hash))
         (not (engine-payload-store-invalid-block store block-hash)))))

(defun chain-store-populate-remote-block-export-batch
    (store database batch)
  (setf store (chain-store-require-memory-store store))
  (let ((current-block-keys (make-hash-table :test 'equalp)))
    (maphash
     (lambda (block-key block)
       (when (chain-store-remote-block-exportable-p store block-key block)
         (setf (gethash block-key current-block-keys) t)
         (chain-store-export-remote-block-to-kv batch block-key block)))
     (memory-chain-store-remote-blocks store))
    (dolist (entry (kv-chain-record-entries database :remote-block))
      (unless (gethash (bytes-to-hex (car entry)) current-block-keys)
        (kv-batch-delete-chain-record
         batch
         :remote-block
         (car entry))))))

(defun chain-store-export-remote-blocks-to-kv (store database)
  (chain-store-apply-export-batch
   store database "remote-block"
   #'chain-store-populate-remote-block-export-batch))
