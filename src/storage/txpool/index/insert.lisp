(in-package #:ethereum-lisp.txpool.index)

(defun engine-pending-txpool-cheapest-transaction
    (transactions &optional sender-key)
  (loop with cheapest = nil
        for transaction being the hash-values of transactions
        when (or (null sender-key)
                 (equalp sender-key
                         (engine-pending-txpool-sender-key transaction)))
          do (when (or (null cheapest)
                       (< (transaction-max-priority-fee-per-gas transaction)
                          (transaction-max-priority-fee-per-gas cheapest)))
               (setf cheapest transaction))
        finally (return cheapest)))

(defun engine-pending-txpool-evict-cheapest-or-fail
    (txpool transactions sender-index transaction failure-message
     &optional sender-key)
  (let ((victim
          (engine-pending-txpool-cheapest-transaction
           transactions sender-key)))
    (unless (and victim
                 (> (transaction-max-priority-fee-per-gas transaction)
                    (transaction-max-priority-fee-per-gas victim)))
      (block-validation-fail failure-message))
    (engine-pending-txpool-unindex-transaction sender-index victim)
    (remhash
     (engine-pending-txpool-hash-key (transaction-hash victim))
     transactions)
    (engine-pending-txpool-clear-admission-time txpool victim)
    (engine-pending-txpool-record-transaction-change txpool victim)
    victim))

(defun engine-pending-txpool-put-pending-transaction
    (txpool transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          account-slot-limit
          global-slot-limit
          admitted-at)
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
            (when (and (null conflict)
                       account-slot-limit
                       (>= (engine-pending-txpool-sender-index-count
                            sender-index
                            transaction)
                           account-slot-limit))
              (engine-pending-txpool-evict-cheapest-or-fail
               txpool transactions sender-index transaction
               "Pending transaction underpriced for full account slots"
               (engine-pending-txpool-sender-key transaction)))
            (when (and (null conflict)
                       global-slot-limit
                       (>= (hash-table-count transactions) global-slot-limit))
              (engine-pending-txpool-evict-cheapest-or-fail
               txpool transactions sender-index transaction
               "Pending transaction underpriced for full global slots"))
            (when conflict
              (unless (engine-pending-txpool-replacement-transaction-p
                       conflict transaction
                       :price-bump-percent price-bump-percent)
                (block-validation-fail
                 "Pending transaction replacement underpriced"))
              (engine-pending-txpool-unindex-pending-transaction
               txpool
               conflict)
              (remhash
               (engine-pending-txpool-hash-key (transaction-hash conflict))
               transactions)
              (engine-pending-txpool-clear-admission-time txpool conflict)
              (engine-pending-txpool-record-transaction-change
               txpool conflict)))
          (engine-pending-txpool-remove-replacement-conflicts
           txpool
           cross-subpool-conflicts)
          (setf (gethash key transactions) transaction)
          (engine-pending-txpool-note-admission-time
           txpool transaction admitted-at)
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
          admitted-at)
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
               (engine-pending-txpool-sender-key transaction)))
            (when (and (null conflict)
                       global-queue-limit
                       (>= (hash-table-count transactions) global-queue-limit))
              (engine-pending-txpool-evict-cheapest-or-fail
               txpool transactions sender-index transaction
               "Queued transaction underpriced for full global queue"))
            (when conflict
              (unless (engine-pending-txpool-replacement-transaction-p
                       conflict transaction
                       :price-bump-percent price-bump-percent)
                (block-validation-fail
                 "Queued transaction replacement underpriced"))
              (engine-pending-txpool-unindex-queued-transaction
               txpool
               conflict)
              (remhash
               (engine-pending-txpool-hash-key (transaction-hash conflict))
               transactions)
              (engine-pending-txpool-clear-admission-time txpool conflict)
              (engine-pending-txpool-record-transaction-change
               txpool conflict)))
          (engine-pending-txpool-remove-replacement-conflicts
           txpool
           cross-subpool-conflicts)
          (setf (gethash key transactions) transaction)
          (engine-pending-txpool-note-admission-time
           txpool transaction admitted-at)
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
          admitted-at)
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
                       replacement-label)))
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
              (remhash
               (engine-pending-txpool-hash-key (transaction-hash conflict))
               transactions)
              (engine-pending-txpool-clear-admission-time txpool conflict)
              (engine-pending-txpool-record-transaction-change
               txpool conflict)))
          (engine-pending-txpool-remove-replacement-conflicts
           txpool
           cross-subpool-conflicts)
          (setf (gethash key transactions) transaction)
          (engine-pending-txpool-note-admission-time
           txpool transaction admitted-at)
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
          admitted-at)
  (engine-pending-txpool-put-flat-transaction
   txpool
   (engine-pending-txpool-basefee-transactions txpool)
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   transaction
   :basefee
   "Basefee"
   :price-bump-percent price-bump-percent
   :global-slot-limit global-slot-limit
   :admitted-at admitted-at))

(defun engine-pending-txpool-put-blob-transaction
    (txpool transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          global-slot-limit
          admitted-at)
  (engine-pending-txpool-put-flat-transaction
   txpool
   (engine-pending-txpool-blob-transactions txpool)
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   transaction
   :blob
   "Blob"
   :price-bump-percent price-bump-percent
   :global-slot-limit global-slot-limit
   :admitted-at admitted-at))
