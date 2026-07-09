(in-package #:ethereum-lisp.core)

(defun engine-payload-store-transaction-funded-p
    (store transaction &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (sender (transaction-sender
                 transaction
                 :expected-chain-id expected-chain-id)))
    (or (null head)
        (null sender)
        (not (chain-store-state-available-p store (block-hash head)))
        (let ((block-hash (block-hash head)))
          (>= (chain-store-account-balance store block-hash sender)
              (engine-payload-store-pending-sender-expenditure
               store sender transaction))))))

(defun engine-payload-store-transaction-executable-nonce-p
    (store transaction &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (sender (transaction-sender
                 transaction
                 :expected-chain-id expected-chain-id)))
    (or (null head)
        (not (chain-store-state-available-p store (block-hash head)))
        (and sender
             (= (transaction-nonce transaction)
                (engine-payload-store-pending-contiguous-nonce
                 store
                 sender
                 (chain-store-account-nonce
                  store
                  (block-hash head)
                  sender)
                 :expected-chain-id expected-chain-id))))))

(defun engine-payload-store-queued-promotion-senders (store sender)
  (if sender
      (list sender)
      (loop for sender-key
              being the hash-keys of
                (engine-payload-store-queued-sender-index store)
            collect (address-from-hex sender-key))))

(defun engine-payload-store-pending-slot-limit-error-p (condition)
  (and (typep condition 'block-validation-error)
       (member
        (block-validation-error-message condition)
        '("Pending transaction exceeds txpool global slot limit"
          "Pending transaction exceeds txpool account slot limit")
        :test #'string=)))

(defun engine-payload-store-promotion-local-transaction-p
    (transaction local-transaction-predicate)
  (and local-transaction-predicate
       (funcall local-transaction-predicate transaction)))

(defun engine-payload-store-promote-transaction-to-pending
    (store transaction &key account-slot-limit global-slot-limit
                            local-transaction-predicate)
  (let ((local-transaction-p
          (engine-payload-store-promotion-local-transaction-p
           transaction
           local-transaction-predicate)))
    (handler-case
        (progn
          (engine-payload-store-put-pending-transaction
           store
           transaction
           :account-slot-limit
           (unless local-transaction-p account-slot-limit)
           :global-slot-limit
           (unless local-transaction-p global-slot-limit))
          :promoted)
      (block-validation-error (condition)
        (if (engine-payload-store-pending-slot-limit-error-p condition)
            :slot-limit
            (error condition))))))
