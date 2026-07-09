(in-package #:ethereum-lisp.core)

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

(defun engine-payload-store-promote-queued-sender-transactions
    (store sender head base-fee &key expected-chain-id
                                  account-slot-limit
                                  global-slot-limit
                                  local-transaction-predicate)
  (let ((promoted-transactions nil))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (let ((state-nonce
              (chain-store-account-nonce store (block-hash head) sender)))
        (loop for next-nonce =
                (engine-payload-store-pending-contiguous-nonce
                 store sender state-nonce
                 :expected-chain-id expected-chain-id)
              for transaction =
                (engine-payload-store-indexed-sender-nonce-transaction
                 (engine-payload-store-queued-sender-index store)
                 sender
                 next-nonce)
              while transaction
              do (progn
                   (engine-payload-store-remove-queued-transaction
                    store
                    (transaction-hash transaction))
                   (cond
                     ((null (transaction-sender
                             transaction
                             :expected-chain-id expected-chain-id)))
                     ((and base-fee
                           (< (transaction-max-fee-per-gas transaction)
                              base-fee))
                      (engine-payload-store-put-basefee-transaction
                       store transaction)
                      (return))
                     ((engine-payload-store-transaction-funded-p
                       store transaction
                       :expected-chain-id expected-chain-id)
                      (case
                          (engine-payload-store-promote-transaction-to-pending
                           store
                           transaction
                           :account-slot-limit account-slot-limit
                           :global-slot-limit global-slot-limit
                           :local-transaction-predicate
                           local-transaction-predicate)
                        (:promoted
                         (push transaction promoted-transactions))
                        (:slot-limit
                         (engine-payload-store-put-queued-transaction
                          store transaction)
                         (return))))
                     (t
                      (engine-payload-store-put-queued-transaction
                       store transaction)
                      (return)))))))
    (nreverse promoted-transactions)))

(defun engine-payload-store-promote-queued-transactions
    (store &optional sender &key expected-chain-id
                                account-slot-limit
                                global-slot-limit
                                local-transaction-predicate)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (and header (block-header-base-fee-per-gas header)))
         (promoted-transactions nil))
    (dolist (candidate-sender
             (engine-payload-store-queued-promotion-senders store sender))
      (setf promoted-transactions
            (nconc promoted-transactions
                   (engine-payload-store-promote-queued-sender-transactions
                    store candidate-sender head base-fee
                    :expected-chain-id expected-chain-id
                    :account-slot-limit account-slot-limit
                    :global-slot-limit global-slot-limit
                    :local-transaction-predicate
                    local-transaction-predicate))))
    promoted-transactions))

(defun engine-payload-store-promote-basefee-transactions
    (store &key expected-chain-id account-slot-limit global-slot-limit
                local-transaction-predicate)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (and header (block-header-base-fee-per-gas header)))
         (promoted-transactions nil))
    (if (and head
             (chain-store-state-available-p store (block-hash head)))
        (dolist (sender
                 (engine-payload-store-indexed-senders
                  (engine-payload-store-basefee-sender-index store)))
          (loop for next-nonce =
                  (engine-payload-store-pending-contiguous-nonce
                   store
                   sender
                   (chain-store-account-nonce
                    store
                    (block-hash head)
                    sender)
                   :expected-chain-id expected-chain-id)
                for transaction =
                  (engine-payload-store-indexed-sender-nonce-transaction
                   (engine-payload-store-basefee-sender-index store)
                   sender
                   next-nonce)
                while transaction
                do (cond
                     ((null (transaction-sender
                             transaction
                             :expected-chain-id expected-chain-id))
                      (engine-pending-txpool-remove-basefee-transaction
                       (engine-payload-store-txpool store)
                       (transaction-hash transaction)))
                     ((engine-payload-store-basefee-promotable-transaction-p
                       store transaction base-fee
                       :expected-chain-id expected-chain-id)
                      (engine-pending-txpool-remove-basefee-transaction
                       (engine-payload-store-txpool store)
                       (transaction-hash transaction))
                      (case
                          (engine-payload-store-promote-transaction-to-pending
                           store
                           transaction
                           :account-slot-limit account-slot-limit
                           :global-slot-limit global-slot-limit
                           :local-transaction-predicate
                           local-transaction-predicate)
                        (:promoted
                         (push transaction promoted-transactions))
                        (:slot-limit
                         (engine-payload-store-put-basefee-transaction
                          store transaction)
                         (return))))
                     (t
                      (return)))))
        (loop for transaction =
                (find-if
                 (lambda (transaction)
                   (or (null (transaction-sender
                              transaction
                              :expected-chain-id expected-chain-id))
                       (engine-payload-store-basefee-promotable-transaction-p
                        store transaction base-fee
                        :expected-chain-id expected-chain-id)))
                 (engine-payload-store-basefee-transactions store))
              while transaction
              do (if (null (transaction-sender
                            transaction
                            :expected-chain-id expected-chain-id))
                     (engine-pending-txpool-remove-basefee-transaction
                      (engine-payload-store-txpool store)
                      (transaction-hash transaction))
                     (progn
                       (engine-pending-txpool-remove-basefee-transaction
                        (engine-payload-store-txpool store)
                        (transaction-hash transaction))
                       (case
                           (engine-payload-store-promote-transaction-to-pending
                            store
                            transaction
                            :account-slot-limit account-slot-limit
                            :global-slot-limit global-slot-limit
                            :local-transaction-predicate
                            local-transaction-predicate)
                         (:promoted
                          (push transaction promoted-transactions))
                         (:slot-limit
                          (engine-payload-store-put-basefee-transaction
                           store transaction)
                          (return)))))))
    (nreverse promoted-transactions)))

(defun engine-payload-store-promote-basefee-and-queued-transactions
    (store &key expected-chain-id account-slot-limit global-slot-limit
                local-transaction-predicate)
  (let ((basefee-promoted
          (engine-payload-store-promote-basefee-transactions
           store
           :expected-chain-id expected-chain-id
           :account-slot-limit account-slot-limit
           :global-slot-limit global-slot-limit
           :local-transaction-predicate local-transaction-predicate))
        (queued-promoted nil)
        (seen-senders (make-hash-table :test 'equal)))
    (dolist (transaction basefee-promoted)
      (let ((sender (transaction-sender
                     transaction
                     :expected-chain-id expected-chain-id)))
        (when sender
          (let ((sender-key (address-to-hex sender)))
            (unless (gethash sender-key seen-senders)
              (setf (gethash sender-key seen-senders) t)
              (setf queued-promoted
                    (nconc queued-promoted
                           (engine-payload-store-promote-queued-transactions
                            store
                            sender
                            :expected-chain-id expected-chain-id
                            :account-slot-limit account-slot-limit
                            :global-slot-limit global-slot-limit
                            :local-transaction-predicate
                            local-transaction-predicate))))))))
    (values basefee-promoted queued-promoted)))
