(in-package #:ethereum-lisp.txpool)

(deftype txpool-transaction ()
  '(or legacy-transaction
       access-list-transaction
       dynamic-fee-transaction
       blob-transaction
       set-code-transaction))

(defun validate-store-transaction (store transaction subpool)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Engine payload store must be a memory store"))
  (unless (typep transaction 'txpool-transaction)
    (block-validation-fail "~:(~A~) transaction must be a transaction"
                           subpool))
  (if (eq subpool :blob)
      (unless (typep transaction 'blob-transaction)
        (block-validation-fail
         "Blob subpool transaction must be a blob transaction"))
      (when (typep transaction 'blob-transaction)
        (block-validation-fail
         "~:(~A~) subpool transaction must not be a blob transaction"
         subpool)))
  transaction)

(defun engine-payload-store-insert-transaction
    (store transaction subpool insert-function options
     &key notify-pending-filters-p)
  (validate-store-transaction store transaction subpool)
  (multiple-value-bind (stored-transaction inserted-p)
      (apply insert-function
             (engine-payload-store-txpool store)
             transaction
             options)
    (when (and inserted-p notify-pending-filters-p)
      (engine-payload-store-notify-pending-transaction-filters
       store
       stored-transaction))
    stored-transaction))

(defun engine-payload-store-put-pending-transaction
    (store transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          account-slot-limit
          global-slot-limit
          admitted-at)
  (engine-payload-store-insert-transaction
   store transaction :pending
   #'engine-pending-txpool-put-pending-transaction
   (list :price-bump-percent price-bump-percent
         :account-slot-limit account-slot-limit
         :global-slot-limit global-slot-limit
         :admitted-at admitted-at)
   :notify-pending-filters-p t))

(defun engine-payload-store-put-queued-transaction
    (store transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          account-queue-limit
          global-queue-limit
          admitted-at)
  (engine-payload-store-insert-transaction
   store transaction :queued
   #'engine-pending-txpool-put-queued-transaction
   (list :price-bump-percent price-bump-percent
         :account-queue-limit account-queue-limit
         :global-queue-limit global-queue-limit
         :admitted-at admitted-at)))

(defun engine-payload-store-put-basefee-transaction
    (store transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          admitted-at)
  (engine-payload-store-insert-transaction
   store transaction :basefee
   #'engine-pending-txpool-put-basefee-transaction
   (list :price-bump-percent price-bump-percent
         :admitted-at admitted-at)))

(defun engine-payload-store-put-blob-transaction
    (store transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          admitted-at)
  (engine-payload-store-insert-transaction
   store transaction :blob
   #'engine-pending-txpool-put-blob-transaction
   (list :price-bump-percent price-bump-percent
         :admitted-at admitted-at)))

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
