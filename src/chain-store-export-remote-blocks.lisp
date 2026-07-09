(in-package #:ethereum-lisp.core)

(defun chain-store-export-remote-block-to-kv (batch block-key block)
  (kv-batch-put-chain-record
   batch
   :remote-block
   (hex-to-bytes block-key)
   (block-rlp block)))

(defun chain-store-remote-block-exportable-p (store block-key block)
  (let ((block-hash (block-hash block)))
    (and (string= block-key (engine-payload-store-key block-hash))
         (not (chain-store-known-block store block-hash))
         (not (engine-payload-store-invalid-block store block-hash)))))

(defun chain-store-populate-remote-block-export-batch
    (store database batch)
  (let ((current-block-keys (make-hash-table :test 'equal)))
    (maphash
     (lambda (block-key block)
       (when (chain-store-remote-block-exportable-p store block-key block)
         (setf (gethash block-key current-block-keys) t)
         (chain-store-export-remote-block-to-kv batch block-key block)))
     (engine-payload-memory-store-remote-blocks store))
    (dolist (entry (kv-chain-record-entries database :remote-block))
      (unless (gethash (bytes-to-hex (car entry)) current-block-keys)
        (kv-batch-delete-chain-record
         batch
         :remote-block
         (car entry))))))

(defun chain-store-export-remote-blocks-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain remote-block export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-remote-block-export-batch store database batch)
      (kv-apply-batch database batch))))
