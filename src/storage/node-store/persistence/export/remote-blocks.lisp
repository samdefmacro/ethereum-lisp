(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-export-remote-block-to-kv
    (database batch block-key block)
  (declare (ignore block-key))
  (node-store-put-immutable-block-body-record
   database batch :remote-block block "Remote block"
   :allow-missing-committed-p t))

(defun chain-store-remote-block-exportable-p (store block-key block)
  (let ((block-hash (block-hash block)))
    (and (string= block-key (engine-payload-store-key block-hash))
         (not (chain-store-known-block store block-hash))
         ;; Export observes the already-pruned transaction-local cache.  Do not
         ;; call the public invalid getter here: its default clock would run a
         ;; second age-prune while persistence is assembling this batch.
         (not (gethash
               (engine-payload-store-key block-hash)
               (memory-chain-store-invalid-tipsets store))))))

(defun chain-store-populate-remote-block-export-batch
    (store database batch &key authoritative-p (write-current-p t))
  (setf store (chain-store-require-memory-store store))
  (let ((current-keys (make-hash-table :test 'equalp))
        (deleted-keys (make-hash-table :test 'equalp))
        (changed-p nil))
    (when write-current-p
      (maphash
       (lambda (block-key block)
         (if (chain-store-remote-block-exportable-p store block-key block)
             (progn
               (setf (gethash block-key current-keys) t)
               (when (chain-store-export-remote-block-to-kv
                      database batch block-key block)
                 (setf changed-p t)))
             (setf (gethash block-key deleted-keys) t)))
       (memory-chain-store-remote-blocks store)))
    (when authoritative-p
      (dolist (entry (kv-chain-record-entries database :remote-block))
        (let ((key (bytes-to-hex (car entry))))
          (unless (gethash key current-keys)
            (setf (gethash key deleted-keys) t)))))
    (maphash
     (lambda (block-key marker)
       (declare (ignore marker))
       (setf (gethash block-key deleted-keys) t))
     (memory-chain-store-remote-block-durable-deletions store))
    (let ((deleted-identifiers
            (mapcar #'hex-to-bytes
                    (sort
                     (loop for key being the hash-keys of deleted-keys
                           collect key)
                     #'string<))))
      (dolist (identifier deleted-identifiers)
        (when (nth-value
               1 (kv-get-chain-record database :remote-block identifier))
          (kv-batch-delete-chain-record batch :remote-block identifier)
          (setf changed-p t)))
      (values changed-p deleted-identifiers))))

(defun node-store-clear-durable-cache-deletions (table identifiers)
  (dolist (identifier identifiers)
    (chain-store-journal-remhash table (bytes-to-hex identifier)))
  table)

(defun chain-store-export-remote-blocks-to-kv (store database)
  (engine-payload-store-enable-durable-cache-change-tracking store)
  (let ((deleted-identifiers nil))
    (chain-store-apply-export-batch
     store database "remote-block"
     (lambda (current-store current-database batch)
       (multiple-value-bind (changed-p deleted)
           (chain-store-populate-remote-block-export-batch
            current-store current-database batch :authoritative-p t)
         (setf deleted-identifiers deleted)
         (when (node-store-populate-evicted-remote-bal-cleanup-batch
                current-store current-database batch deleted
                :deleted-remote-identifiers deleted)
           (setf changed-p t))
         ;; CHAIN-STORE-APPLY-EXPORT-BATCH reserves its second return value for
         ;; pending trie nodes. Do not leak deletion identifiers into it.
         changed-p)))
    (node-store-clear-durable-cache-deletions
     (memory-chain-store-remote-block-durable-deletions
      (chain-store-require-memory-store store))
     deleted-identifiers)
    database))
