(in-package #:ethereum-lisp.txpool.index)

(defconstant +txpool-replacement-price-bump-percent+ 10)

(defstruct (engine-pending-txpool
            (:constructor make-engine-pending-txpool
                (&key (transactions (make-hash-table :test 'equalp))
                      (transactions-by-sender
                       (make-hash-table :test 'equalp))
                      (queued-transactions
                       (make-hash-table :test 'equalp))
                      (queued-transactions-by-sender
                       (make-hash-table :test 'equalp))
                      (basefee-transactions
                       (make-hash-table :test 'equalp))
                      (basefee-transactions-by-sender
                       (make-hash-table :test 'equalp))
                      (blob-transactions
                       (make-hash-table :test 'equalp))
                      (blob-transactions-by-sender
                       (make-hash-table :test 'equalp))
                      (transaction-admitted-at
                       (make-hash-table :test 'equalp))
                      (database-change-tracking-enabled-p nil)
                      (database-dirty-transaction-keys
                       (make-hash-table :test 'equalp)))))
  transactions
  transactions-by-sender
  queued-transactions
  queued-transactions-by-sender
  basefee-transactions
  basefee-transactions-by-sender
  blob-transactions
  blob-transactions-by-sender
  transaction-admitted-at
  database-change-tracking-enabled-p
  database-dirty-transaction-keys)

(defvar *engine-pending-txpool-change-recorder* nil)

(defun engine-pending-txpool-record-transaction-change (txpool transaction)
  (let ((hash (transaction-hash transaction)))
    (when (engine-pending-txpool-database-change-tracking-enabled-p txpool)
      (setf (gethash (hash32-to-hex hash)
                     (engine-pending-txpool-database-dirty-transaction-keys
                      txpool))
            t))
    (when *engine-pending-txpool-change-recorder*
      (funcall *engine-pending-txpool-change-recorder* hash))))

(defun call-with-engine-pending-txpool-change-tracking (recorder thunk)
  (unless (and (functionp recorder) (functionp thunk))
    (block-validation-fail
     "Txpool change tracking requires recorder and thunk functions"))
  (let ((outer-recorder *engine-pending-txpool-change-recorder*))
    (let ((*engine-pending-txpool-change-recorder*
            (lambda (hash)
              (when outer-recorder
                (funcall outer-recorder hash))
              (funcall recorder hash))))
      (funcall thunk))))

(defun engine-pending-txpool-enable-database-change-tracking (txpool)
  (clrhash (engine-pending-txpool-database-dirty-transaction-keys txpool))
  (setf (engine-pending-txpool-database-change-tracking-enabled-p txpool) t)
  txpool)

(defun engine-pending-txpool-database-dirty-transaction-hashes (txpool)
  (mapcar
   #'hash32-from-hex
   (sort
    (loop for key being the hash-keys of
            (engine-pending-txpool-database-dirty-transaction-keys txpool)
          collect key)
    #'string<)))

(defun engine-pending-txpool-clear-database-dirty-transaction-hashes
    (txpool &optional hashes)
  (if hashes
      (dolist (hash hashes)
        (remhash (hash32-to-hex hash)
                 (engine-pending-txpool-database-dirty-transaction-keys
                  txpool)))
      (clrhash
       (engine-pending-txpool-database-dirty-transaction-keys txpool)))
  txpool)

(defgeneric txpool-component (store)
  (:documentation "Return STORE's txpool component, or NIL when none exists."))

(defmethod txpool-component ((store t))
  nil)

(defmethod txpool-component ((txpool engine-pending-txpool))
  txpool)
