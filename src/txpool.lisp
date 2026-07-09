(in-package #:ethereum-lisp.core)

(defun engine-pending-txpool-copy-transaction (transaction transaction-copies)
  (or (gethash transaction transaction-copies)
      (setf (gethash transaction transaction-copies)
            (engine-payload-store-copy-transaction transaction))))

(defun engine-pending-txpool-copy-transaction-table
    (table transaction-copies)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key transaction)
               (setf (gethash key copy)
                     (engine-pending-txpool-copy-transaction
                      transaction
                      transaction-copies)))
             table)
    copy))

(defun engine-pending-txpool-copy-metadata-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun engine-payload-store-copy-checkpoint (checkpoint)
  (when checkpoint
    (make-chain-store-checkpoint
     :label (chain-store-checkpoint-label checkpoint)
     :block-hash (chain-store-checkpoint-block-hash checkpoint))))

(defun engine-pending-txpool-copy-sender-index
    (table transaction-copies)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (sender nonce-table)
               (let ((nonce-copy
                       (make-hash-table :test (hash-table-test nonce-table))))
                 (maphash
                  (lambda (nonce transaction)
                    (setf (gethash nonce nonce-copy)
                          (engine-pending-txpool-copy-transaction
                           transaction
                           transaction-copies)))
                  nonce-table)
                 (setf (gethash sender copy) nonce-copy)))
             table)
    copy))

(defun engine-pending-txpool-copy (txpool)
  (let ((transaction-copies (make-hash-table :test 'eq)))
    (make-engine-pending-txpool
     :transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-transactions txpool)
      transaction-copies)
     :transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-transactions-by-sender txpool)
      transaction-copies)
     :queued-transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-queued-transactions txpool)
      transaction-copies)
     :queued-transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-queued-transactions-by-sender txpool)
      transaction-copies)
     :basefee-transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-basefee-transactions txpool)
      transaction-copies)
     :basefee-transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-basefee-transactions-by-sender txpool)
      transaction-copies)
     :blob-transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-blob-transactions txpool)
      transaction-copies)
     :blob-transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-blob-transactions-by-sender txpool)
      transaction-copies)
     :transaction-admitted-at
     (engine-pending-txpool-copy-metadata-table
      (engine-pending-txpool-transaction-admitted-at txpool)))))

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

(defun engine-payload-store-notify-pending-transaction-filters
    (store transaction)
  (loop for filter
          being the hash-values of
            (engine-payload-memory-store-log-filters store)
        when (typep filter 'engine-pending-transaction-filter)
          do (engine-pending-transaction-filter-record-hash
              filter
              (transaction-hash transaction))))

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

(defun engine-payload-store-stale-txpool-transaction-p
    (store head transaction &key expected-chain-id)
  (let ((sender (transaction-sender
                 transaction
                 :expected-chain-id expected-chain-id)))
    (and sender
         (chain-store-state-available-p store (block-hash head))
         (< (transaction-nonce transaction)
            (chain-store-account-nonce
             store
             (block-hash head)
             sender)))))

(defun engine-payload-store-remove-stale-txpool-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (flet ((remove-stale (transactions remove-function)
               (dolist (transaction transactions)
                 (when (engine-payload-store-stale-txpool-transaction-p
                        store head transaction
                        :expected-chain-id expected-chain-id)
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-stale
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-stale
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-stale
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-stale
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-expired-txpool-transaction-p
    (store transaction lifetime-seconds now)
  (let ((admitted-at
          (engine-pending-txpool-admission-time
           (engine-payload-store-txpool store)
           transaction)))
    (and admitted-at
         (>= (- now admitted-at) lifetime-seconds))))

(defun engine-payload-store-remove-expired-txpool-queued-view-transactions
    (store lifetime-seconds now &key local-transaction-predicate)
  (let ((removed-transactions nil))
    (when lifetime-seconds
      (unless (and (integerp lifetime-seconds) (not (minusp lifetime-seconds)))
        (block-validation-fail
         "Txpool lifetime must be a non-negative integer"))
      (unless (and (integerp now) (not (minusp now)))
        (block-validation-fail
         "Txpool cleanup time must be a non-negative integer"))
      (flet ((remove-expired (transactions remove-function)
               (dolist (transaction transactions)
                 (when (and (not (and local-transaction-predicate
                                       (funcall local-transaction-predicate
                                                transaction)))
                            (engine-payload-store-expired-txpool-transaction-p
                             store transaction lifetime-seconds now))
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-expired
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-expired
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-expired
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-sender-code-invalid-txpool-transaction-p
    (store head transaction &key expected-chain-id)
  (let ((sender (transaction-sender
                 transaction
                 :expected-chain-id expected-chain-id)))
    (and sender
         (not (engine-payload-store-sender-code-admissible-p
               store
               head
               sender)))))

(defun engine-payload-store-remove-sender-code-invalid-txpool-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (flet ((remove-sender-code-invalid
                 (transactions remove-function)
               (dolist (transaction transactions)
                 (when (engine-payload-store-sender-code-invalid-txpool-transaction-p
                        store head transaction
                        :expected-chain-id expected-chain-id)
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-sender-code-invalid
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-sender-code-invalid
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-sender-code-invalid
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-sender-code-invalid
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-over-gas-limit-txpool-transaction-p
    (head transaction)
  (> (transaction-gas-limit transaction)
     (block-header-gas-limit (block-header head))))

(defun engine-payload-store-remove-over-gas-limit-txpool-transactions (store)
  (let ((head (chain-store-latest-block store))
        (removed-transactions nil))
    (when head
      (flet ((remove-over-gas (transactions remove-function)
               (dolist (transaction transactions)
                 (when (engine-payload-store-over-gas-limit-txpool-transaction-p
                        head transaction)
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-over-gas
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-over-gas
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-over-gas
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-over-gas
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-remove-underpriced-blob-txpool-transactions
    (store &key chain-config)
  (let ((blob-base-fee
          (engine-payload-store-current-blob-base-fee
           store
           chain-config))
        (removed-transactions nil))
    (when blob-base-fee
      (dolist (transaction (engine-payload-store-blob-transactions store))
        (handler-case
            (validate-blob-transaction-fee-cap transaction blob-base-fee)
          (block-validation-error ()
            (engine-pending-txpool-remove-blob-transaction
             (engine-payload-store-txpool store)
             (transaction-hash transaction))
            (push transaction removed-transactions)))))
    (nreverse removed-transactions)))

(defun engine-payload-store-remove-invalid-sender-txpool-transactions
    (store &key expected-chain-id)
  (let ((removed-transactions nil))
    (when expected-chain-id
      (flet ((remove-invalid-sender
                 (transactions remove-function)
               (dolist (transaction transactions)
                 (when (null (transaction-sender
                              transaction
                              :expected-chain-id expected-chain-id))
                   (funcall remove-function
                            (engine-payload-store-txpool store)
                            (transaction-hash transaction))
                   (push transaction removed-transactions)))))
        (remove-invalid-sender
         (engine-payload-store-pending-transactions store)
         #'engine-pending-txpool-remove-pending-transaction)
        (remove-invalid-sender
         (engine-payload-store-queued-transactions store)
         #'engine-pending-txpool-remove-queued-transaction)
        (remove-invalid-sender
         (engine-payload-store-basefee-transactions store)
         #'engine-pending-txpool-remove-basefee-transaction)
        (remove-invalid-sender
         (engine-payload-store-blob-transactions store)
         #'engine-pending-txpool-remove-blob-transaction)))
    (nreverse removed-transactions)))

(defun engine-payload-store-chain-config-expected-chain-id
    (expected-chain-id chain-config)
  (or expected-chain-id
      (and chain-config
           (chain-config-chain-id chain-config))))

(defun engine-payload-store-remove-new-head-invalid-txpool-transactions
    (store &key expected-chain-id chain-config)
  (let ((txpool-chain-id
          (engine-payload-store-chain-config-expected-chain-id
           expected-chain-id
           chain-config)))
    (nconc
     (engine-payload-store-remove-invalid-sender-txpool-transactions
      store
      :expected-chain-id txpool-chain-id)
     (engine-payload-store-remove-stale-txpool-transactions
      store
      :expected-chain-id txpool-chain-id)
     (engine-payload-store-remove-over-gas-limit-txpool-transactions store)
     (engine-payload-store-remove-underpriced-blob-txpool-transactions
      store
      :chain-config chain-config)
     (engine-payload-store-remove-sender-code-invalid-txpool-transactions
      store
      :expected-chain-id txpool-chain-id))))

(defun engine-payload-store-pending-revalidation-senders (store)
  (loop for sender-key
          being the hash-keys of
            (engine-payload-store-pending-sender-index store)
        collect (address-from-hex sender-key)))

(defun engine-payload-store-pending-sender-transactions
    (store sender)
  (engine-payload-store-indexed-sender-transactions-sorted
   (engine-payload-store-pending-sender-index store)
   sender))

(defun engine-payload-store-demote-pending-transaction
    (store transaction base-fee)
  (engine-payload-store-remove-pending-transaction
   store
   (transaction-hash transaction))
  (if (and base-fee
           (< (transaction-max-fee-per-gas transaction) base-fee))
      (engine-payload-store-put-basefee-transaction store transaction)
      (engine-payload-store-put-queued-transaction store transaction))
  transaction)

(defun engine-payload-store-revalidate-pending-sender-transactions
    (store sender head base-fee)
  (let* ((block-hash (block-hash head))
         (state-nonce
           (chain-store-account-nonce store block-hash sender))
         (remaining-balance
           (chain-store-account-balance store block-hash sender))
         (next-nonce state-nonce)
         (blocked-p nil)
         (demoted-transactions nil))
    (dolist (transaction
             (engine-payload-store-pending-sender-transactions store sender))
      (cond
        ((< (transaction-nonce transaction) state-nonce)
         (engine-payload-store-remove-pending-transaction
          store
          (transaction-hash transaction)))
        ((or blocked-p
             (/= (transaction-nonce transaction) next-nonce)
             (and base-fee
                  (< (transaction-max-fee-per-gas transaction) base-fee)))
         (engine-payload-store-demote-pending-transaction
          store transaction base-fee)
         (setf blocked-p t)
         (push transaction demoted-transactions))
        ((< remaining-balance
            (engine-payload-store-txpool-upfront-cost transaction))
         (engine-payload-store-demote-pending-transaction
          store transaction base-fee)
         (setf blocked-p t)
         (push transaction demoted-transactions))
        (t
         (decf remaining-balance
               (engine-payload-store-txpool-upfront-cost transaction))
         (incf next-nonce))))
    (nreverse demoted-transactions)))

(defun engine-payload-store-revalidate-pending-transactions
    (store &key expected-chain-id)
  (let ((head (chain-store-latest-block store))
        (demoted-transactions nil))
    (engine-payload-store-remove-invalid-sender-txpool-transactions
     store
     :expected-chain-id expected-chain-id)
    (when (and head
               (chain-store-state-available-p store (block-hash head)))
      (let* ((header (block-header head))
             (base-fee (and header
                            (block-header-base-fee-per-gas header))))
        (dolist (sender
                 (engine-payload-store-pending-revalidation-senders store))
          (setf demoted-transactions
                (nconc
                 demoted-transactions
                 (engine-payload-store-revalidate-pending-sender-transactions
                  store sender head base-fee))))))
    demoted-transactions))

(defun engine-payload-store-pending-transaction (store hash)
  (engine-pending-txpool-pending-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-queued-transaction (store hash)
  (engine-pending-txpool-queued-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-basefee-transaction (store hash)
  (engine-pending-txpool-basefee-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-blob-transaction (store hash)
  (engine-pending-txpool-blob-transaction
   (engine-payload-store-txpool store)
   hash))

(defun engine-payload-store-pooled-transaction (store hash)
  (or (engine-payload-store-pending-transaction store hash)
      (engine-payload-store-queued-transaction store hash)
      (engine-payload-store-basefee-transaction store hash)
      (engine-payload-store-blob-transaction store hash)))

(defun engine-payload-store-pending-transactions (store)
  (engine-pending-txpool-pending-transactions
   (engine-payload-store-txpool store)))

(defun engine-mining-transaction< (left right expected-chain-id)
  (let* ((left-sender (transaction-sender left
                                          :expected-chain-id
                                          expected-chain-id))
         (right-sender (transaction-sender right
                                           :expected-chain-id
                                           expected-chain-id))
         (left-sender-key (if left-sender
                              (address-to-hex left-sender)
                              ""))
         (right-sender-key (if right-sender
                               (address-to-hex right-sender)
                               "")))
    (cond
      ((string< left-sender-key right-sender-key) t)
      ((string< right-sender-key left-sender-key) nil)
      ((< (transaction-nonce left) (transaction-nonce right)) t)
      ((< (transaction-nonce right) (transaction-nonce left)) nil)
      (t
       (string< (hash32-to-hex (transaction-hash left))
                (hash32-to-hex (transaction-hash right)))))))

(defun engine-payload-store-pending-mining-transactions
    (store expected-chain-id)
  (sort
   (copy-list
    (remove-if-not
     (lambda (transaction)
       (transaction-sender transaction
                           :expected-chain-id expected-chain-id))
     (engine-payload-store-pending-transactions store)))
   (lambda (left right)
     (engine-mining-transaction< left right expected-chain-id))))

(defun engine-select-mining-transactions
    (transactions gas-limit expected-chain-id)
  (let ((blocked-senders (make-hash-table :test #'equal)))
    (loop with selected = nil
          with gas-used = 0
          for transaction in transactions
          for sender = (transaction-sender
                        transaction
                        :expected-chain-id expected-chain-id)
          for sender-key = (and sender (address-to-hex sender))
          for transaction-gas = (transaction-gas-limit transaction)
          when (and sender-key
                    (not (gethash sender-key blocked-senders)))
            do (if (<= (+ gas-used transaction-gas) gas-limit)
                   (progn
                     (push transaction selected)
                     (incf gas-used transaction-gas))
                   (setf (gethash sender-key blocked-senders) t))
          finally (return (nreverse selected)))))

(defun engine-payload-store-queued-transactions (store)
  (engine-pending-txpool-queued-transaction-list
   (engine-payload-store-txpool store)))

(defun engine-payload-store-basefee-transactions (store)
  (engine-pending-txpool-basefee-transaction-list
   (engine-payload-store-txpool store)))

(defun engine-payload-store-blob-transactions (store)
  (engine-pending-txpool-blob-transaction-list
   (engine-payload-store-txpool store)))

(defun engine-payload-store-pooled-transactions (store)
  (sort
   (append (engine-payload-store-pending-transactions store)
           (engine-payload-store-queued-transactions store)
           (engine-payload-store-basefee-transactions store)
           (engine-payload-store-blob-transactions store))
   #'string<
   :key (lambda (transaction)
          (hash32-to-hex (transaction-hash transaction)))))

(defun engine-payload-store-pending-transactions-by-sender (store)
  (engine-payload-store-pending-sender-index store))

(defun engine-payload-store-pending-transaction-count (store)
  (engine-pending-txpool-pending-count
   (engine-payload-store-txpool store)))

(defun engine-payload-store-queued-transaction-count (store)
  (engine-pending-txpool-queued-count
   (engine-payload-store-txpool store)))

(defun engine-payload-store-basefee-transaction-count (store)
  (engine-pending-txpool-basefee-count
   (engine-payload-store-txpool store)))

(defun engine-payload-store-blob-transaction-count (store)
  (engine-pending-txpool-blob-count
   (engine-payload-store-txpool store)))
