(in-package #:ethereum-lisp.core)

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
