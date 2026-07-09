(in-package #:ethereum-lisp.core)

(defun engine-payload-store-txpool (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (engine-payload-memory-store-txpool store))

(defun engine-payload-store-pending-transaction-table (store)
  (engine-pending-txpool-transactions
   (engine-payload-store-txpool store)))

(defun engine-payload-store-pending-sender-index (store)
  (engine-pending-txpool-transactions-by-sender
   (engine-payload-store-txpool store)))

(defun engine-payload-store-queued-transaction-table (store)
  (engine-pending-txpool-queued-transactions
   (engine-payload-store-txpool store)))

(defun engine-payload-store-queued-sender-index (store)
  (engine-pending-txpool-queued-transactions-by-sender
   (engine-payload-store-txpool store)))

(defun engine-payload-store-basefee-transaction-table (store)
  (engine-pending-txpool-basefee-transactions
   (engine-payload-store-txpool store)))

(defun engine-payload-store-basefee-sender-index (store)
  (engine-pending-txpool-basefee-transactions-by-sender
   (engine-payload-store-txpool store)))

(defun engine-payload-store-blob-transaction-table (store)
  (engine-pending-txpool-blob-transactions
   (engine-payload-store-txpool store)))

(defun engine-payload-store-blob-sender-index (store)
  (engine-pending-txpool-blob-transactions-by-sender
   (engine-payload-store-txpool store)))

(defun engine-payload-store-pending-conflict (store transaction)
  (engine-pending-txpool-pending-conflict
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-txpool-conflict-p (store transaction)
  (let ((txpool (engine-payload-store-txpool store)))
    (or (engine-pending-txpool-pending-conflict txpool transaction)
        (engine-pending-txpool-queued-conflict txpool transaction)
        (engine-pending-txpool-basefee-conflict txpool transaction)
        (engine-pending-txpool-blob-conflict txpool transaction))))

(defun engine-payload-store-replacement-price-bumped-p
    (old-transaction new-transaction price-function
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (engine-pending-txpool-replacement-price-bumped-p
   old-transaction
   new-transaction
   price-function
   :price-bump-percent price-bump-percent))

(defun engine-payload-store-replacement-transaction-p
    (old-transaction new-transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (engine-pending-txpool-replacement-transaction-p
   old-transaction
   new-transaction
   :price-bump-percent price-bump-percent))

(defun engine-payload-store-index-pending-transaction (store transaction)
  (engine-pending-txpool-index-pending-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-unindex-pending-transaction (store transaction)
  (engine-pending-txpool-unindex-pending-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-index-queued-transaction (store transaction)
  (engine-pending-txpool-index-queued-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-unindex-queued-transaction (store transaction)
  (engine-pending-txpool-unindex-queued-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-index-basefee-transaction (store transaction)
  (engine-pending-txpool-index-basefee-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-unindex-basefee-transaction (store transaction)
  (engine-pending-txpool-unindex-basefee-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-index-blob-transaction (store transaction)
  (engine-pending-txpool-index-blob-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-unindex-blob-transaction (store transaction)
  (engine-pending-txpool-unindex-blob-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-remove-pending-transaction (store hash)
  (engine-pending-txpool-remove-pending-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-remove-queued-transaction (store hash)
  (engine-pending-txpool-remove-queued-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-remove-pending-conflict (store transaction)
  (engine-pending-txpool-remove-pending-conflict
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-remove-included-transaction
    (store transaction)
  (engine-pending-txpool-remove-included-transaction
   (engine-payload-store-txpool store)
   transaction))

(defun engine-payload-store-put-pending-transaction
    (store transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          account-slot-limit
          global-slot-limit
          admitted-at)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep transaction
                 '(or legacy-transaction
                      access-list-transaction
                      dynamic-fee-transaction
                      blob-transaction
                      set-code-transaction))
    (block-validation-fail "Pending transaction must be a transaction"))
  (when (typep transaction 'blob-transaction)
    (block-validation-fail
     "Pending subpool transaction must not be a blob transaction"))
  (multiple-value-bind (transaction inserted-p)
      (engine-pending-txpool-put-pending-transaction
       (engine-payload-store-txpool store)
       transaction
       :price-bump-percent price-bump-percent
       :account-slot-limit account-slot-limit
       :global-slot-limit global-slot-limit
       :admitted-at admitted-at)
    (when inserted-p
      (engine-payload-store-notify-pending-transaction-filters
       store
       transaction))
    transaction))

(defun engine-payload-store-put-queued-transaction
    (store transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          account-queue-limit
          global-queue-limit
          admitted-at)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep transaction
                 '(or legacy-transaction
                      access-list-transaction
                      dynamic-fee-transaction
                      blob-transaction
                      set-code-transaction))
    (block-validation-fail "Queued transaction must be a transaction"))
  (when (typep transaction 'blob-transaction)
    (block-validation-fail
     "Queued subpool transaction must not be a blob transaction"))
  (multiple-value-bind (transaction inserted-p)
      (engine-pending-txpool-put-queued-transaction
       (engine-payload-store-txpool store)
       transaction
       :price-bump-percent price-bump-percent
       :account-queue-limit account-queue-limit
       :global-queue-limit global-queue-limit
       :admitted-at admitted-at)
    (declare (ignore inserted-p))
    transaction))

(defun engine-payload-store-put-basefee-transaction
    (store transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          admitted-at)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep transaction
                 '(or legacy-transaction
                      access-list-transaction
                      dynamic-fee-transaction
                      blob-transaction
                      set-code-transaction))
    (block-validation-fail "Basefee transaction must be a transaction"))
  (when (typep transaction 'blob-transaction)
    (block-validation-fail
     "Basefee subpool transaction must not be a blob transaction"))
  (multiple-value-bind (transaction inserted-p)
      (engine-pending-txpool-put-basefee-transaction
       (engine-payload-store-txpool store)
       transaction
       :price-bump-percent price-bump-percent
       :admitted-at admitted-at)
    (declare (ignore inserted-p))
    transaction))

(defun engine-payload-store-put-blob-transaction
    (store transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          admitted-at)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep transaction 'blob-transaction)
    (block-validation-fail "Blob subpool transaction must be a blob transaction"))
  (multiple-value-bind (transaction inserted-p)
      (engine-pending-txpool-put-blob-transaction
       (engine-payload-store-txpool store)
       transaction
       :price-bump-percent price-bump-percent
       :admitted-at admitted-at)
    (declare (ignore inserted-p))
    transaction))

(defun engine-payload-store-basefee-promotable-transaction-p
    (store transaction base-fee &key expected-chain-id)
  (and (or (null base-fee)
           (>= (transaction-max-fee-per-gas transaction) base-fee))
       (engine-payload-store-transaction-executable-nonce-p
        store transaction
        :expected-chain-id expected-chain-id)
       (engine-payload-store-transaction-funded-p
        store transaction
        :expected-chain-id expected-chain-id)
       (not (engine-pending-txpool-pending-conflict
             (engine-payload-store-txpool store)
             transaction))
       (not (engine-pending-txpool-queued-conflict
             (engine-payload-store-txpool store)
             transaction))
       (not (engine-pending-txpool-blob-conflict
             (engine-payload-store-txpool store)
             transaction))))

(defun engine-payload-store-indexed-sender-nonce-transaction
    (sender-index sender nonce)
  (let ((sender-transactions
          (gethash (address-to-hex sender) sender-index)))
    (when sender-transactions
      (gethash (write-to-string nonce :base 10) sender-transactions))))

(defun engine-payload-store-indexed-sender-transactions
    (sender-index sender)
  (let ((sender-transactions
          (gethash (address-to-hex sender) sender-index)))
    (when sender-transactions
      (loop for transaction being the hash-values of sender-transactions
            collect transaction))))

(defun engine-payload-store-indexed-sender-transactions-sorted
    (sender-index sender)
  (sort (engine-payload-store-indexed-sender-transactions
         sender-index
         sender)
        #'<
        :key #'transaction-nonce))

(defun engine-payload-store-indexed-senders-into (sender-index senders)
  (loop for sender-key being the hash-keys of sender-index
        do (setf (gethash sender-key senders)
                 (address-from-hex sender-key)))
  senders)

(defun engine-payload-store-pooled-senders (store)
  (let ((senders (make-hash-table :test 'equal)))
    (dolist (sender-index
             (list (engine-payload-store-pending-sender-index store)
                   (engine-payload-store-queued-sender-index store)
                   (engine-payload-store-basefee-sender-index store)
                   (engine-payload-store-blob-sender-index store)))
      (engine-payload-store-indexed-senders-into sender-index senders))
    (loop for sender being the hash-values of senders
          collect sender)))

(defun engine-payload-store-sender-pooled-transactions (store sender)
  (loop for sender-index in
          (list (engine-payload-store-pending-sender-index store)
                (engine-payload-store-queued-sender-index store)
                (engine-payload-store-basefee-sender-index store)
                (engine-payload-store-blob-sender-index store))
        append (engine-payload-store-indexed-sender-transactions
                sender-index
                sender)))

(defun engine-payload-store-indexed-senders (sender-index)
  (loop for sender-key being the hash-keys of sender-index
        collect (address-from-hex sender-key)))

(defun engine-payload-store-pending-contiguous-nonce
    (store sender state-nonce &key expected-chain-id)
  (loop with next-nonce = state-nonce
        for transaction =
          (engine-payload-store-indexed-sender-nonce-transaction
           (engine-payload-store-pending-sender-index store)
           sender
           next-nonce)
        while (and transaction
                   (or (null expected-chain-id)
                       (transaction-sender
                        transaction
                        :expected-chain-id expected-chain-id)))
          do (incf next-nonce)
        finally (return next-nonce)))

(defun engine-payload-store-txpool-upfront-cost (transaction)
  (+ (transaction-value transaction)
     (* (transaction-gas-limit transaction)
        (transaction-max-fee-per-gas transaction))
     (* (transaction-blob-gas-used transaction)
        (if (typep transaction 'blob-transaction)
            (blob-transaction-max-fee-per-blob-gas transaction)
            0))))

(defun engine-payload-store-pending-sender-expenditure
    (store sender transaction)
  (let ((new-cost (engine-payload-store-txpool-upfront-cost transaction))
        (existing-cost 0)
        (replacement-cost nil))
    (dolist (pooled
             (engine-payload-store-indexed-sender-transactions
              (engine-payload-store-pending-sender-index store)
              sender))
      (let ((pooled-cost
              (engine-payload-store-txpool-upfront-cost pooled)))
        (incf existing-cost pooled-cost)
        (when (= (transaction-nonce pooled)
                 (transaction-nonce transaction))
          (setf replacement-cost pooled-cost))))
    (if replacement-cost
        (+ existing-cost (- new-cost replacement-cost))
        (+ existing-cost new-cost))))
(defun engine-payload-store-sender-admission-expenditure
    (store sender transaction)
  (let ((new-cost (engine-payload-store-txpool-upfront-cost transaction))
        (existing-cost 0)
        (replacement-cost nil))
    (dolist (pooled
             (engine-payload-store-sender-pooled-transactions
              store
              sender))
      (let ((pooled-cost
              (engine-payload-store-txpool-upfront-cost pooled)))
        (incf existing-cost pooled-cost)
        (when (= (transaction-nonce pooled)
                 (transaction-nonce transaction))
          (setf replacement-cost pooled-cost))))
    (if replacement-cost
        (+ existing-cost (- new-cost replacement-cost))
        (+ existing-cost new-cost))))
