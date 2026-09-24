(in-package #:ethereum-lisp.txpool.index)

(defun engine-pending-txpool-effective-tip (transaction base-fee)
  "What a block built at BASE-FEE earns per gas from TRANSACTION: the priority
fee, capped by the room its fee cap leaves above the base fee, never negative.
NIL BASE-FEE (a pre-London head) leaves the whole priority fee."
  (let ((cap (transaction-max-fee-per-gas transaction))
        (tip (transaction-max-priority-fee-per-gas transaction)))
    (max 0 (min tip (- cap (or base-fee 0))))))

(defun engine-pending-txpool-cheaper-p (left right base-fee)
  "Whether LEFT ranks below RIGHT for eviction at BASE-FEE: by effective tip,
then fee cap, then tip cap, as go-ethereum v1.17 legacypool priceHeap.cmp
orders its heap once a base fee is known. Comparing the raw tip cap instead
kept a transaction promising a tip its fee cap cannot pay at the child base
fee, and evicted one that pays more."
  (let ((left-tip (engine-pending-txpool-effective-tip left base-fee))
        (right-tip (engine-pending-txpool-effective-tip right base-fee)))
    (cond
      ((/= left-tip right-tip) (< left-tip right-tip))
      ((/= (transaction-max-fee-per-gas left)
           (transaction-max-fee-per-gas right))
       (< (transaction-max-fee-per-gas left)
          (transaction-max-fee-per-gas right)))
      (t
       (< (transaction-max-priority-fee-per-gas left)
          (transaction-max-priority-fee-per-gas right))))))

(defun engine-pending-txpool-cheapest-transaction
    (transactions &key sender-key base-fee)
  (loop with cheapest = nil
        for transaction being the hash-values of transactions
        when (or (null sender-key)
                 (equalp sender-key
                         (engine-pending-txpool-sender-key transaction)))
          do (when (or (null cheapest)
                       (engine-pending-txpool-cheaper-p
                        transaction cheapest base-fee))
               (setf cheapest transaction))
        finally (return cheapest)))

(defun engine-pending-txpool-evict-cheapest-or-fail
    (txpool transactions sender-index transaction failure-message
     &key sender-key base-fee)
  "Evict the cheapest of TRANSACTIONS (of SENDER-KEY's, when given) to make
room for TRANSACTION, which must rank strictly above it at BASE-FEE (the child
block's base fee); otherwise fail with FAILURE-MESSAGE."
  (let ((victim
          (engine-pending-txpool-cheapest-transaction
           transactions :sender-key sender-key :base-fee base-fee)))
    (unless (and victim
                 (engine-pending-txpool-cheaper-p victim transaction base-fee))
      (block-validation-fail failure-message))
    (engine-pending-txpool-unindex-transaction sender-index victim)
    (engine-pending-txpool-journal-remhash
     transactions
     (engine-pending-txpool-hash-key (transaction-hash victim)))
    (engine-pending-txpool-clear-admission-time txpool victim)
    (engine-pending-txpool-forget-transaction-lookups txpool victim)
    (engine-pending-txpool-record-transaction-change txpool victim)
    victim))

(defun engine-pending-txpool-put-pending-transaction
    (txpool transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          account-slot-limit
          global-slot-limit
          admitted-at
          base-fee)
  (let ((key (engine-pending-txpool-hash-key
              (transaction-hash transaction)))
        (transactions (engine-pending-txpool-transactions txpool))
        (sender-index (engine-pending-txpool-transactions-by-sender txpool))
        (cross-subpool-conflicts
          (engine-pending-txpool-cross-subpool-conflicts
           txpool transaction :pending)))
    (if (gethash key transactions)
        (values transaction nil)
        (progn
          (engine-pending-txpool-validate-replacement-conflicts
           cross-subpool-conflicts
           transaction
           :price-bump-percent price-bump-percent)
          (let ((conflict
                  (engine-pending-txpool-pending-conflict
                   txpool
                   transaction)))
            ;; AccountSlots is a fairness guarantee, not a hard per-sender
            ;; ceiling (geth legacypool Config). An account may use spare global
            ;; capacity; equalize an over-guarantee account only once the global
            ;; executable pool is full.
            (when (and (null conflict)
                       account-slot-limit
                       global-slot-limit
                       (>= (hash-table-count transactions) global-slot-limit)
                       (>= (engine-pending-txpool-sender-index-count
                            sender-index
                            transaction)
                           account-slot-limit))
              (engine-pending-txpool-evict-cheapest-or-fail
               txpool transactions sender-index transaction
               "Pending transaction underpriced for full account slots"
               :sender-key (engine-pending-txpool-sender-key transaction)
               :base-fee base-fee))
            (when (and (null conflict)
                       global-slot-limit
                       (>= (hash-table-count transactions) global-slot-limit))
              (engine-pending-txpool-evict-cheapest-or-fail
               txpool transactions sender-index transaction
               "Pending transaction underpriced for full global slots"
               :base-fee base-fee))
            (when conflict
              (unless (engine-pending-txpool-replacement-transaction-p
                       conflict transaction
                       :price-bump-percent price-bump-percent)
                (block-validation-fail
                 "Pending transaction replacement underpriced"))
              (engine-pending-txpool-unindex-pending-transaction
               txpool
               conflict)
              (engine-pending-txpool-journal-remhash
               transactions
               (engine-pending-txpool-hash-key
                (transaction-hash conflict)))
              (engine-pending-txpool-clear-admission-time txpool conflict)
              (engine-pending-txpool-forget-transaction-lookups
               txpool conflict)
              (engine-pending-txpool-record-transaction-change
               txpool conflict)))
          (engine-pending-txpool-remove-replacement-conflicts
           txpool
           cross-subpool-conflicts)
          (engine-pending-txpool-journal-puthash
           transactions key transaction)
          (engine-pending-txpool-note-admission-time
           txpool transaction admitted-at)
          (engine-pending-txpool-note-transaction-lookups txpool transaction)
          (engine-pending-txpool-index-pending-transaction
           txpool
           transaction)
          (engine-pending-txpool-record-transaction-change
           txpool transaction)
          (values transaction t)))))

(defun engine-pending-txpool-put-queued-transaction
    (txpool transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          account-queue-limit
          global-queue-limit
          admitted-at
          base-fee)
  (let ((key (engine-pending-txpool-hash-key
              (transaction-hash transaction)))
        (transactions (engine-pending-txpool-queued-transactions txpool))
        (sender-index (engine-pending-txpool-queued-transactions-by-sender
                       txpool))
        (cross-subpool-conflicts
          (engine-pending-txpool-cross-subpool-conflicts
           txpool transaction :queued)))
    (if (gethash key transactions)
        (values transaction nil)
        (progn
          (engine-pending-txpool-validate-replacement-conflicts
           cross-subpool-conflicts
           transaction
           :price-bump-percent price-bump-percent)
          (let ((conflict
                  (engine-pending-txpool-indexed-conflict
                   sender-index
                   transaction)))
            (when (and (null conflict)
                       account-queue-limit
                       (>= (engine-pending-txpool-sender-index-count
                            sender-index
                            transaction)
                           account-queue-limit))
              (engine-pending-txpool-evict-cheapest-or-fail
               txpool transactions sender-index transaction
               "Queued transaction underpriced for full account queue"
               :sender-key (engine-pending-txpool-sender-key transaction)
               :base-fee base-fee))
            (when (and (null conflict)
                       global-queue-limit
                       (>= (hash-table-count transactions) global-queue-limit))
              (engine-pending-txpool-evict-cheapest-or-fail
               txpool transactions sender-index transaction
               "Queued transaction underpriced for full global queue"
               :base-fee base-fee))
            (when conflict
              (unless (engine-pending-txpool-replacement-transaction-p
                       conflict transaction
                       :price-bump-percent price-bump-percent)
                (block-validation-fail
                 "Queued transaction replacement underpriced"))
              (engine-pending-txpool-unindex-queued-transaction
               txpool
               conflict)
              (engine-pending-txpool-journal-remhash
               transactions
               (engine-pending-txpool-hash-key
                (transaction-hash conflict)))
              (engine-pending-txpool-clear-admission-time txpool conflict)
              (engine-pending-txpool-forget-transaction-lookups
               txpool conflict)
              (engine-pending-txpool-record-transaction-change
               txpool conflict)))
          (engine-pending-txpool-remove-replacement-conflicts
           txpool
           cross-subpool-conflicts)
          (engine-pending-txpool-journal-puthash
           transactions key transaction)
          (engine-pending-txpool-note-admission-time
           txpool transaction admitted-at)
          (engine-pending-txpool-note-transaction-lookups txpool transaction)
          (engine-pending-txpool-index-queued-transaction
           txpool
           transaction)
          (engine-pending-txpool-record-transaction-change
           txpool transaction)
          (values transaction t)))))

(defun engine-pending-txpool-put-flat-transaction
    (txpool transactions sender-index transaction target replacement-label
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          global-slot-limit
          admitted-at
          base-fee)
  (let ((key (engine-pending-txpool-hash-key
              (transaction-hash transaction)))
        (cross-subpool-conflicts
          (engine-pending-txpool-cross-subpool-conflicts
           txpool transaction target)))
    (if (gethash key transactions)
        (values transaction nil)
        (progn
          (engine-pending-txpool-validate-replacement-conflicts
           cross-subpool-conflicts
           transaction
           :price-bump-percent price-bump-percent)
          (let ((conflict
                  (engine-pending-txpool-indexed-conflict
                   sender-index
                   transaction)))
            (when (and (null conflict)
                       global-slot-limit
                       (>= (hash-table-count transactions) global-slot-limit))
              (engine-pending-txpool-evict-cheapest-or-fail
               txpool transactions sender-index transaction
               (format nil
                       "~A transaction underpriced for full subpool"
                       replacement-label)
               :base-fee base-fee))
            (when conflict
              (unless (engine-pending-txpool-replacement-transaction-p
                       conflict transaction
                       :price-bump-percent price-bump-percent)
                (block-validation-fail
                 "~A transaction replacement underpriced"
                 replacement-label))
              (engine-pending-txpool-unindex-transaction
               sender-index
               conflict)
              (engine-pending-txpool-journal-remhash
               transactions
               (engine-pending-txpool-hash-key
                (transaction-hash conflict)))
              (engine-pending-txpool-clear-admission-time txpool conflict)
              (engine-pending-txpool-forget-transaction-lookups
               txpool conflict)
              (engine-pending-txpool-record-transaction-change
               txpool conflict)))
          (engine-pending-txpool-remove-replacement-conflicts
           txpool
           cross-subpool-conflicts)
          (engine-pending-txpool-journal-puthash
           transactions key transaction)
          (engine-pending-txpool-note-admission-time
           txpool transaction admitted-at)
          (engine-pending-txpool-note-transaction-lookups txpool transaction)
          (engine-pending-txpool-index-transaction
           sender-index
           transaction)
          (engine-pending-txpool-record-transaction-change
           txpool transaction)
          (values transaction t)))))

(defun engine-pending-txpool-put-basefee-transaction
    (txpool transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          global-slot-limit
          admitted-at
          base-fee)
  (engine-pending-txpool-put-flat-transaction
   txpool
   (engine-pending-txpool-basefee-transactions txpool)
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   transaction
   :basefee
   "Basefee"
   :price-bump-percent price-bump-percent
   :global-slot-limit global-slot-limit
   :admitted-at admitted-at
   :base-fee base-fee))

(defun engine-pending-txpool-put-blob-transaction
    (txpool transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          global-slot-limit
          admitted-at
          base-fee)
  (engine-pending-txpool-put-flat-transaction
   txpool
   (engine-pending-txpool-blob-transactions txpool)
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   transaction
   :blob
   "Blob"
   :price-bump-percent price-bump-percent
   :global-slot-limit global-slot-limit
   :admitted-at admitted-at
   :base-fee base-fee))
