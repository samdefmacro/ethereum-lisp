(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-export-invalid-tipset-to-kv
    (database batch tipset-key invalid-block)
  (declare (ignore tipset-key))
  (node-store-put-immutable-block-body-record
   database batch :invalid-tipset invalid-block "Invalid block"
   :allow-missing-committed-p t))

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
    (store database batch &key authoritative-p (write-current-p t))
  (setf store (chain-store-require-memory-store store))
  (let ((current-keys (make-hash-table :test 'equalp))
        (deleted-keys (make-hash-table :test 'equalp))
        (changed-p nil))
    (when write-current-p
      (maphash
       (lambda (tipset-key invalid-block)
         (if (chain-store-invalid-tipset-exportable-p
              store tipset-key invalid-block)
             (progn
               (setf (gethash tipset-key current-keys) t)
               (when (chain-store-export-invalid-tipset-to-kv
                      database batch tipset-key invalid-block)
                 (setf changed-p t)))
             (when (chain-store-invalid-tipset-direct-key-p
                    tipset-key invalid-block)
               (setf (gethash tipset-key deleted-keys) t))))
       (memory-chain-store-invalid-tipsets store)))
    (when authoritative-p
      (dolist (entry (kv-chain-record-entries database :invalid-tipset))
        (let ((key (bytes-to-hex (car entry))))
          (unless (gethash key current-keys)
            (setf (gethash key deleted-keys) t)))))
    (maphash
     (lambda (tipset-key marker)
       (declare (ignore marker))
       (setf (gethash tipset-key deleted-keys) t))
     (memory-chain-store-invalid-tipset-durable-deletions store))
    (let ((deleted-identifiers
            (mapcar #'hex-to-bytes
                    (sort
                     (loop for key being the hash-keys of deleted-keys
                           collect key)
                     #'string<))))
      (dolist (identifier deleted-identifiers)
        (when (nth-value
               1 (kv-get-chain-record database :invalid-tipset identifier))
          (kv-batch-delete-chain-record batch :invalid-tipset identifier)
          (setf changed-p t)))
      (values changed-p deleted-identifiers))))

(defun node-store-populate-evicted-remote-bal-cleanup-batch
    (store database batch identifiers
     &key deleted-remote-identifiers deleted-invalid-identifiers)
  "Delete BAL side data owned only by records removed in this batch.

This incremental cleanup combines the final in-memory owner set with point
reads for non-hydrated durable owners. Records scheduled for deletion in this
same batch are not allowed to masquerade as owners."
  (setf store (chain-store-require-memory-store store))
  (let ((changed-p nil))
    (flet ((scheduled-p (identifier scheduled)
             (find identifier scheduled :test #'bytes=))
           (durable-owner-p (kind identifier)
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database kind identifier)
               (declare (ignore record))
               present-p)))
      (dolist (identifier identifiers)
        (unless
            (let* ((key (bytes-to-hex identifier))
                   (blocks (memory-chain-store-blocks store))
                   (remotes (memory-chain-store-remote-blocks store))
                   (invalids (memory-chain-store-invalid-tipsets store)))
              (or
               ;; Same-batch candidate/invalid/remote writes are already visible
               ;; in memory even though point reads cannot see them yet.
               (gethash key blocks)
               (gethash key remotes)
               (let ((invalid-block (gethash key invalids)))
                 (and invalid-block
                      (chain-store-invalid-tipset-direct-key-p
                       key invalid-block)))
               (durable-owner-p :block identifier)
               (durable-owner-p :staged-block identifier)
               (and (not (scheduled-p identifier deleted-remote-identifiers))
                    (durable-owner-p :remote-block identifier))
               (and (not (scheduled-p identifier deleted-invalid-identifiers))
                    (durable-owner-p :invalid-tipset identifier))))
          (when (durable-owner-p :block-access-list identifier)
            (kv-batch-delete-chain-record
             batch :block-access-list identifier)
            (setf changed-p t)))))
    changed-p))

(defun chain-store-export-invalid-tipsets-to-kv (store database)
  (engine-payload-store-enable-durable-cache-change-tracking store)
  (let ((deleted-identifiers nil))
    (chain-store-apply-export-batch
     store database "invalid-tipset"
     (lambda (current-store current-database batch)
       (multiple-value-bind (changed-p deleted)
           (chain-store-populate-invalid-tipset-export-batch
            current-store current-database batch :authoritative-p t)
         (setf deleted-identifiers deleted)
         (when (node-store-populate-evicted-remote-bal-cleanup-batch
                current-store current-database batch deleted
                :deleted-invalid-identifiers deleted)
           (setf changed-p t))
         ;; CHAIN-STORE-APPLY-EXPORT-BATCH reserves its second return value for
         ;; pending trie nodes. Do not leak deletion identifiers into it.
         changed-p)))
    (node-store-clear-durable-cache-deletions
     (memory-chain-store-invalid-tipset-durable-deletions
      (chain-store-require-memory-store store))
     deleted-identifiers)
    database))
