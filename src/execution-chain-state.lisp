(in-package #:ethereum-lisp.execution)

(defun commit-state-db-to-chain-store (store block-hash state)
  (state-db-for-each-account
   state
   (lambda (address account code storage-entries)
     (chain-store-put-account-balance
      store block-hash address (state-account-balance account))
     (chain-store-put-account-nonce
      store block-hash address (state-account-nonce account))
     (chain-store-put-account-code store block-hash address code)
     (dolist (entry storage-entries)
       (chain-store-put-account-storage
        store block-hash address (car entry) (cdr entry)))))
  store)

(defun chain-store-state-db (store block-hash)
  (when (chain-store-state-available-p store block-hash)
    (let ((state (make-state-db)))
      (chain-store-for-each-account
       store
       block-hash
       (lambda (address balance nonce code storage-entries)
         (state-db-set-account
          state address
          (make-state-account :nonce nonce :balance balance))
         (when (plusp (length code))
           (state-db-set-code state address code))
         (dolist (entry storage-entries)
           (state-db-set-storage state address (car entry) (cdr entry)))))
      state)))
