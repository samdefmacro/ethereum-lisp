(in-package #:ethereum-lisp.txpool.index)

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
