(in-package #:ethereum-lisp.chain-store.persistence)

(defun chain-store-apply-export-batch
    (store database record-label populate-batch)
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Chain ~A export target must be a key-value database"
     record-label))
  (let ((batch (make-kv-write-batch)))
    (funcall populate-batch store database batch)
    (kv-apply-batch database batch)))

(defun chain-store-export-checkpoint-to-kv (batch checkpoint)
  (let ((label (and checkpoint
                    (chain-store-checkpoint-label checkpoint)))
        (hash (and checkpoint
                   (chain-store-checkpoint-block-hash checkpoint))))
    (when (and label hash)
      (kv-batch-put-chain-checkpoint batch label (hash32-bytes hash)))))

(defun chain-store-checkpoint-labels-with-hashes (store)
  (setf store (chain-store-require-memory-store store))
  (loop for checkpoint in
          (list (memory-chain-store-head-checkpoint store)
                (memory-chain-store-safe-checkpoint store)
                (memory-chain-store-finalized-checkpoint store))
        for label = (and checkpoint
                         (chain-store-checkpoint-label checkpoint))
        for hash = (and checkpoint
                        (chain-store-checkpoint-block-hash checkpoint))
        when (and label hash)
          collect label))

(defun chain-store-populate-index-export-batch (store database batch)
  (setf store (chain-store-require-memory-store store))
  (dolist (entry (kv-chain-canonical-hashes database))
    (unless (gethash (car entry)
                     (memory-chain-store-canonical-hashes store))
      (kv-batch-delete-chain-canonical-hash batch (car entry))))
  (let ((checkpoint-labels
          (chain-store-checkpoint-labels-with-hashes store)))
    (dolist (entry (kv-chain-checkpoints database))
      (unless (member (car entry) checkpoint-labels)
        (kv-batch-delete-chain-checkpoint batch (car entry)))))
  (maphash
   (lambda (number key)
     (kv-batch-put-chain-canonical-hash
      batch
      number
      (hash32-bytes (hash32-from-hex key))))
   (memory-chain-store-canonical-hashes store))
  (chain-store-export-checkpoint-to-kv
   batch
   (memory-chain-store-head-checkpoint store))
  (chain-store-export-checkpoint-to-kv
   batch
   (memory-chain-store-safe-checkpoint store))
  (chain-store-export-checkpoint-to-kv
   batch
   (memory-chain-store-finalized-checkpoint store)))

(defun chain-store-export-indexes-to-kv (store database)
  (chain-store-apply-export-batch
   store database "index" #'chain-store-populate-index-export-batch))
