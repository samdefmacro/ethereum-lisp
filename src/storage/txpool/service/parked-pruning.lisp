(in-package #:ethereum-lisp.txpool)

(defun engine-payload-store-parked-transaction-priority (entry)
  (ecase (car entry)
    (:queued 0)
    (:basefee 1)
    (:blob 2)))

(defun engine-payload-store-sender-parked-transactions (store sender)
  (sort
   (append
    (loop for transaction in
            (engine-payload-store-indexed-sender-transactions
             (engine-payload-store-queued-sender-index store)
             sender)
          collect (cons :queued transaction))
    (loop for transaction in
            (engine-payload-store-indexed-sender-transactions
             (engine-payload-store-basefee-sender-index store)
             sender)
          collect (cons :basefee transaction))
    (loop for transaction in
            (engine-payload-store-indexed-sender-transactions
             (engine-payload-store-blob-sender-index store)
             sender)
          collect (cons :blob transaction)))
   (lambda (left right)
     (let ((left-nonce (transaction-nonce (cdr left)))
           (right-nonce (transaction-nonce (cdr right))))
       (or (< left-nonce right-nonce)
           (and (= left-nonce right-nonce)
                (< (engine-payload-store-parked-transaction-priority left)
                   (engine-payload-store-parked-transaction-priority
                    right))))))))

(defun engine-payload-store-remove-parked-transaction (store entry)
  (let ((hash (transaction-hash (cdr entry)))
        (txpool (engine-payload-store-txpool store)))
    (ecase (car entry)
      (:queued
       (engine-pending-txpool-remove-queued-transaction txpool hash))
      (:basefee
       (engine-pending-txpool-remove-basefee-transaction txpool hash))
      (:blob
       (engine-pending-txpool-remove-blob-transaction txpool hash)))))

(defun engine-payload-store-prune-overbudget-parked-transactions (store)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (dolist (sender (engine-payload-store-pooled-senders store))
        (let ((remaining-balance
                (chain-store-account-balance
                 store
                 (block-hash head)
                 sender)))
          (dolist (transaction
                   (engine-payload-store-pending-sender-transactions
                    store
                    sender))
            (let ((cost
                    (engine-payload-store-txpool-upfront-cost transaction)))
              (if (<= cost remaining-balance)
                  (decf remaining-balance cost)
                  (setf remaining-balance 0))))
          (dolist (entry
                   (engine-payload-store-sender-parked-transactions
                    store
                    sender))
            (let* ((transaction (cdr entry))
                   (cost
                     (engine-payload-store-txpool-upfront-cost transaction)))
              (if (<= cost remaining-balance)
                  (decf remaining-balance cost)
                  (progn
                    (engine-payload-store-remove-parked-transaction
                     store
                     entry)
                    (push transaction removed-transactions))))))))
    (nreverse removed-transactions)))
