(in-package #:ethereum-lisp.core)

(defun engine-payload-store-state-available-p
    (store hash)
  (not (null
        (gethash (engine-payload-store-key hash)
                 (engine-payload-memory-store-state-blocks store)))))

(defun chain-store-state-available-p (store hash)
  (engine-payload-store-state-available-p
   (chain-store-require-memory-store store)
   hash))

(defun engine-payload-store-string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun engine-payload-store-remove-prefixed-keys (table prefix)
  (let ((keys '()))
    (maphash
     (lambda (key value)
       (declare (ignore value))
       (when (engine-payload-store-string-prefix-p prefix key)
         (push key keys)))
     table)
    (dolist (key keys)
      (remhash key table))
    (length keys)))

(defun engine-payload-store-prune-state-snapshot (store block-key)
  (let ((prefix (format nil "~A:" block-key)))
    (remhash block-key (engine-payload-memory-store-state-blocks store))
    (+ (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-balances store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-nonces store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-codes store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (engine-payload-memory-store-account-storage store)
        prefix))))

(defun chain-store-prune-state-before (store block-number)
  (let ((store (chain-store-require-memory-store store)))
    (unless (and (integerp block-number) (not (minusp block-number)))
      (block-validation-fail
       "Chain state pruning block number must be a non-negative integer"))
    (let ((block-keys '())
          (head-block-key
            (let ((checkpoint
                    (engine-payload-memory-store-head-checkpoint store)))
              (let ((hash (and checkpoint
                               (chain-store-checkpoint-block-hash
                                checkpoint))))
                (if hash
                    (engine-payload-store-key hash)
                    (gethash
                     (engine-payload-memory-store-head-number store)
                     (engine-payload-memory-store-canonical-hashes
                      store)))))))
      (maphash
       (lambda (block-key state-available-p)
         (when state-available-p
           (let ((block (gethash block-key
                                  (engine-payload-memory-store-blocks store))))
             (when (and block
                        (or (null head-block-key)
                            (not (string= block-key head-block-key)))
                        (< (block-header-number (block-header block))
                           block-number))
               (push block-key block-keys)))))
       (engine-payload-memory-store-state-blocks store))
      (dolist (block-key block-keys)
        (engine-payload-store-prune-state-snapshot store block-key))
      (length block-keys))))
