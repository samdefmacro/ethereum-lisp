(in-package #:ethereum-lisp.core)

(defun engine-pending-txpool-sender (transaction)
  (or (transaction-sender transaction)
      (block-validation-fail
       "Txpool transaction sender recovery failed")))

(defun engine-pending-txpool-sender-key (transaction)
  (address-to-hex (engine-pending-txpool-sender transaction)))

(defun engine-pending-txpool-nonce-key (transaction)
  (write-to-string (transaction-nonce transaction) :base 10))

(defun engine-pending-txpool-hash-key (hash)
  (engine-payload-store-key hash))

(defun engine-pending-txpool-transaction-hash-key (transaction)
  (engine-pending-txpool-hash-key (transaction-hash transaction)))

(defun engine-pending-txpool-note-admission-time
    (txpool transaction admitted-at)
  (when admitted-at
    (setf (gethash (engine-pending-txpool-transaction-hash-key transaction)
                   (engine-pending-txpool-transaction-admitted-at txpool))
          admitted-at))
  transaction)

(defun engine-pending-txpool-clear-admission-time
    (txpool transaction-or-hash)
  (remhash (engine-pending-txpool-hash-key
            (if (hash32-p transaction-or-hash)
                transaction-or-hash
                (transaction-hash transaction-or-hash)))
           (engine-pending-txpool-transaction-admitted-at txpool)))

(defun engine-pending-txpool-admission-time (txpool transaction)
  (gethash (engine-pending-txpool-transaction-hash-key transaction)
           (engine-pending-txpool-transaction-admitted-at txpool)))

(defun engine-pending-txpool-indexed-conflict
    (sender-index transaction)
  (let* ((sender (engine-pending-txpool-sender-key transaction))
         (nonce (engine-pending-txpool-nonce-key transaction))
         (sender-transactions (gethash sender sender-index)))
    (and sender-transactions
         (gethash nonce sender-transactions))))

(defun engine-pending-txpool-index-transaction
    (sender-index transaction)
  (let* ((sender (engine-pending-txpool-sender-key transaction))
         (nonce (engine-pending-txpool-nonce-key transaction))
         (sender-transactions
           (or (gethash sender sender-index)
               (setf (gethash sender sender-index)
                     (make-hash-table :test 'equal)))))
    (setf (gethash nonce sender-transactions) transaction)))

(defun engine-pending-txpool-unindex-transaction
    (sender-index transaction)
  (when transaction
    (let* ((sender (engine-pending-txpool-sender-key transaction))
           (nonce (engine-pending-txpool-nonce-key transaction))
           (sender-transactions (gethash sender sender-index))
           (indexed-transaction
             (and sender-transactions
                  (gethash nonce sender-transactions))))
      (when (and indexed-transaction
                 (hash32= (transaction-hash indexed-transaction)
                          (transaction-hash transaction)))
        (remhash nonce sender-transactions)
        (when (zerop (hash-table-count sender-transactions))
          (remhash sender sender-index))))))

(defun engine-pending-txpool-sender-index-count (sender-index transaction)
  (let ((sender-transactions
          (gethash (engine-pending-txpool-sender-key transaction)
                   sender-index)))
    (if sender-transactions
        (hash-table-count sender-transactions)
        0)))

(defun engine-pending-txpool-remove-indexed-transaction
    (txpool transactions sender-index hash)
  (let* ((key (engine-pending-txpool-hash-key hash))
         (transaction (gethash key transactions)))
    (when transaction
      (engine-pending-txpool-unindex-transaction
       sender-index
       transaction)
      (engine-pending-txpool-clear-admission-time txpool hash)
      (remhash key transactions))
    transaction))

(defun engine-payload-store-pending-sender-key (transaction)
  (engine-pending-txpool-sender-key transaction))

(defun engine-payload-store-pending-nonce-key (transaction)
  (engine-pending-txpool-nonce-key transaction))

(defun engine-pending-txpool-pending-conflict (txpool transaction)
  (engine-pending-txpool-indexed-conflict
   (engine-pending-txpool-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-queued-conflict (txpool transaction)
  (engine-pending-txpool-indexed-conflict
   (engine-pending-txpool-queued-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-basefee-conflict (txpool transaction)
  (engine-pending-txpool-indexed-conflict
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-blob-conflict (txpool transaction)
  (engine-pending-txpool-indexed-conflict
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-index-pending-transaction
    (txpool transaction)
  (engine-pending-txpool-index-transaction
   (engine-pending-txpool-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-index-queued-transaction
    (txpool transaction)
  (engine-pending-txpool-index-transaction
   (engine-pending-txpool-queued-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-index-basefee-transaction
    (txpool transaction)
  (engine-pending-txpool-index-transaction
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-index-blob-transaction
    (txpool transaction)
  (engine-pending-txpool-index-transaction
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-unindex-pending-transaction
    (txpool transaction)
  (engine-pending-txpool-unindex-transaction
   (engine-pending-txpool-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-unindex-queued-transaction
    (txpool transaction)
  (engine-pending-txpool-unindex-transaction
   (engine-pending-txpool-queued-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-unindex-basefee-transaction
    (txpool transaction)
  (engine-pending-txpool-unindex-transaction
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-unindex-blob-transaction
    (txpool transaction)
  (engine-pending-txpool-unindex-transaction
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   transaction))

(defun engine-pending-txpool-remove-pending-transaction (txpool hash)
  (engine-pending-txpool-remove-indexed-transaction
   txpool
   (engine-pending-txpool-transactions txpool)
   (engine-pending-txpool-transactions-by-sender txpool)
   hash))

(defun engine-pending-txpool-remove-queued-transaction (txpool hash)
  (engine-pending-txpool-remove-indexed-transaction
   txpool
   (engine-pending-txpool-queued-transactions txpool)
   (engine-pending-txpool-queued-transactions-by-sender txpool)
   hash))

(defun engine-pending-txpool-remove-basefee-transaction (txpool hash)
  (engine-pending-txpool-remove-indexed-transaction
   txpool
   (engine-pending-txpool-basefee-transactions txpool)
   (engine-pending-txpool-basefee-transactions-by-sender txpool)
   hash))

(defun engine-pending-txpool-remove-blob-transaction (txpool hash)
  (engine-pending-txpool-remove-indexed-transaction
   txpool
   (engine-pending-txpool-blob-transactions txpool)
   (engine-pending-txpool-blob-transactions-by-sender txpool)
   hash))

(defun engine-pending-txpool-remove-pending-conflict (txpool transaction)
  (when (transaction-sender transaction)
    (let ((conflict
            (engine-pending-txpool-pending-conflict txpool transaction)))
      (when conflict
        (engine-pending-txpool-remove-pending-transaction
         txpool
         (transaction-hash conflict))))))

(defun engine-pending-txpool-remove-queued-conflict (txpool transaction)
  (when (transaction-sender transaction)
    (let ((conflict
            (engine-pending-txpool-queued-conflict txpool transaction)))
      (when conflict
        (engine-pending-txpool-remove-queued-transaction
         txpool
         (transaction-hash conflict))))))

(defun engine-pending-txpool-remove-included-transaction
    (txpool transaction)
  (let ((hash (transaction-hash transaction)))
    (engine-pending-txpool-remove-pending-transaction txpool hash)
    (engine-pending-txpool-remove-queued-transaction txpool hash)
    (engine-pending-txpool-remove-basefee-transaction txpool hash)
    (engine-pending-txpool-remove-blob-transaction txpool hash))
  (when (transaction-sender transaction)
    (engine-pending-txpool-remove-pending-conflict txpool transaction)
    (engine-pending-txpool-remove-queued-conflict txpool transaction)
    (let ((basefee-conflict
            (engine-pending-txpool-basefee-conflict txpool transaction)))
      (when basefee-conflict
        (engine-pending-txpool-remove-basefee-transaction
         txpool
         (transaction-hash basefee-conflict))))
    (let ((blob-conflict
            (engine-pending-txpool-blob-conflict txpool transaction)))
      (when blob-conflict
        (engine-pending-txpool-remove-blob-transaction
         txpool
         (transaction-hash blob-conflict)))))
  transaction)

(defun engine-pending-txpool-cross-subpool-conflicts
    (txpool transaction target)
  (let ((conflicts nil))
    (unless (eq target :pending)
      (let ((conflict
              (engine-pending-txpool-pending-conflict
               txpool
               transaction)))
        (when conflict
          (push (list "Pending"
                      conflict
                      #'engine-pending-txpool-remove-pending-transaction)
                conflicts))))
    (unless (eq target :queued)
      (let ((conflict
              (engine-pending-txpool-queued-conflict
               txpool
               transaction)))
        (when conflict
          (push (list "Queued"
                      conflict
                      #'engine-pending-txpool-remove-queued-transaction)
                conflicts))))
    (unless (eq target :basefee)
      (let ((conflict
              (engine-pending-txpool-basefee-conflict
               txpool
               transaction)))
        (when conflict
          (push (list "Basefee"
                      conflict
                      #'engine-pending-txpool-remove-basefee-transaction)
                conflicts))))
    (unless (eq target :blob)
      (let ((conflict
              (engine-pending-txpool-blob-conflict
               txpool
               transaction)))
        (when conflict
          (push (list "Blob"
                      conflict
                      #'engine-pending-txpool-remove-blob-transaction)
                conflicts))))
    (nreverse conflicts)))

(defun engine-pending-txpool-validate-replacement-conflicts
    (conflicts transaction &key
                           (price-bump-percent
                            +txpool-replacement-price-bump-percent+))
  (dolist (conflict-entry conflicts)
    (destructuring-bind (label conflict remove-function) conflict-entry
      (declare (ignore remove-function))
      (unless (engine-pending-txpool-replacement-transaction-p
               conflict
               transaction
               :price-bump-percent price-bump-percent)
        (block-validation-fail
         "~A transaction replacement underpriced"
         label)))))

(defun engine-pending-txpool-remove-replacement-conflicts
    (txpool conflicts)
  (dolist (conflict-entry conflicts)
    (destructuring-bind (label conflict remove-function) conflict-entry
      (declare (ignore label))
      (funcall remove-function txpool (transaction-hash conflict)))))

(defun engine-pending-txpool-replacement-price-bumped-p
    (old-transaction new-transaction price-function
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (let ((price-bump-percent
          (or price-bump-percent +txpool-replacement-price-bump-percent+))
        (old-price (funcall price-function old-transaction))
        (new-price (funcall price-function new-transaction)))
    (and (> new-price old-price)
         (>= (* new-price 100)
             (* old-price
                (+ 100 price-bump-percent))))))

(defun engine-pending-txpool-replacement-transaction-p
    (old-transaction new-transaction
     &key (price-bump-percent +txpool-replacement-price-bump-percent+))
  (and
   (engine-pending-txpool-replacement-price-bumped-p
    old-transaction
    new-transaction
    #'transaction-max-fee-per-gas
    :price-bump-percent price-bump-percent)
   (engine-pending-txpool-replacement-price-bumped-p
    old-transaction
    new-transaction
    #'transaction-max-priority-fee-per-gas
    :price-bump-percent price-bump-percent)))

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

(defun engine-pending-txpool-pending-transaction (txpool hash)
  (gethash (engine-pending-txpool-hash-key hash)
           (engine-pending-txpool-transactions txpool)))

(defun engine-pending-txpool-queued-transaction (txpool hash)
  (gethash (engine-pending-txpool-hash-key hash)
           (engine-pending-txpool-queued-transactions txpool)))

(defun engine-pending-txpool-basefee-transaction (txpool hash)
  (gethash (engine-pending-txpool-hash-key hash)
           (engine-pending-txpool-basefee-transactions txpool)))

(defun engine-pending-txpool-blob-transaction (txpool hash)
  (gethash (engine-pending-txpool-hash-key hash)
           (engine-pending-txpool-blob-transactions txpool)))

(defun engine-pending-txpool-transaction-list (transactions)
  (sort
   (loop for transaction
           being the hash-values of
             transactions
         collect transaction)
   #'string<
   :key (lambda (transaction)
          (hash32-to-hex (transaction-hash transaction)))))

(defun engine-pending-txpool-pending-transactions (txpool)
  (engine-pending-txpool-transaction-list
   (engine-pending-txpool-transactions txpool)))

(defun engine-pending-txpool-queued-transaction-list (txpool)
  (engine-pending-txpool-transaction-list
   (engine-pending-txpool-queued-transactions txpool)))

(defun engine-pending-txpool-basefee-transaction-list (txpool)
  (engine-pending-txpool-transaction-list
   (engine-pending-txpool-basefee-transactions txpool)))

(defun engine-pending-txpool-blob-transaction-list (txpool)
  (engine-pending-txpool-transaction-list
   (engine-pending-txpool-blob-transactions txpool)))

(defun engine-pending-txpool-pending-count (txpool)
  (hash-table-count (engine-pending-txpool-transactions txpool)))

(defun engine-pending-txpool-queued-count (txpool)
  (hash-table-count (engine-pending-txpool-queued-transactions txpool)))

(defun engine-pending-txpool-basefee-count (txpool)
  (hash-table-count (engine-pending-txpool-basefee-transactions txpool)))

(defun engine-pending-txpool-blob-count (txpool)
  (hash-table-count (engine-pending-txpool-blob-transactions txpool)))

(defun engine-pending-txpool-empty-p (txpool)
  (and (zerop (engine-pending-txpool-pending-count txpool))
       (zerop (engine-pending-txpool-queued-count txpool))
       (zerop (engine-pending-txpool-basefee-count txpool))
       (zerop (engine-pending-txpool-blob-count txpool))))
