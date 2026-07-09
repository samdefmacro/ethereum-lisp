(in-package #:ethereum-lisp.core)

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
                       global-slot-limit
                       (>= (hash-table-count transactions) global-slot-limit))
              (block-validation-fail
               "Pending transaction exceeds txpool global slot limit"))
            (when (and (null conflict)
                       account-slot-limit
                       (>= (engine-pending-txpool-sender-index-count
                            sender-index
                            transaction)
                           account-slot-limit))
              (block-validation-fail
               "Pending transaction exceeds txpool account slot limit"))
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
              (engine-pending-txpool-clear-admission-time txpool conflict)))
          (engine-pending-txpool-remove-replacement-conflicts
           txpool
           cross-subpool-conflicts)
          (setf (gethash key transactions) transaction)
          (engine-pending-txpool-note-admission-time
           txpool transaction admitted-at)
          (engine-pending-txpool-index-pending-transaction
           txpool
           transaction)
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
                       global-queue-limit
                       (>= (hash-table-count transactions) global-queue-limit))
              (block-validation-fail
               "Queued transaction exceeds txpool global queue limit"))
            (when (and (null conflict)
                       account-queue-limit
                       (>= (engine-pending-txpool-sender-index-count
                            sender-index
                            transaction)
                           account-queue-limit))
              (block-validation-fail
               "Queued transaction exceeds txpool account queue limit"))
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
              (engine-pending-txpool-clear-admission-time txpool conflict)))
          (engine-pending-txpool-remove-replacement-conflicts
           txpool
           cross-subpool-conflicts)
          (setf (gethash key transactions) transaction)
          (engine-pending-txpool-note-admission-time
           txpool transaction admitted-at)
          (engine-pending-txpool-index-queued-transaction
           txpool
           transaction)
          (values transaction t)))))

(defun engine-pending-txpool-put-flat-transaction
    (txpool transactions sender-index transaction target replacement-label
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
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
              (engine-pending-txpool-clear-admission-time txpool conflict)))
          (engine-pending-txpool-remove-replacement-conflicts
           txpool
           cross-subpool-conflicts)
          (setf (gethash key transactions) transaction)
          (engine-pending-txpool-note-admission-time
           txpool transaction admitted-at)
          (engine-pending-txpool-index-transaction
           sender-index
           transaction)
          (values transaction t)))))

(defun engine-pending-txpool-put-basefee-transaction
    (txpool transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          admitted-at)
  (engine-pending-txpool-put-flat-transaction
   txpool
   (engine-pending-txpool-basefee-transactions txpool)
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   transaction
   :basefee
   "Basefee"
   :price-bump-percent price-bump-percent
   :admitted-at admitted-at))

(defun engine-pending-txpool-put-blob-transaction
    (txpool transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+)
          admitted-at)
  (engine-pending-txpool-put-flat-transaction
   txpool
   (engine-pending-txpool-blob-transactions txpool)
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   transaction
   :blob
   "Blob"
   :price-bump-percent price-bump-percent
   :admitted-at admitted-at))
