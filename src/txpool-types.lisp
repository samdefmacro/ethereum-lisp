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
                       (make-hash-table :test 'equalp)))))
  transactions
  transactions-by-sender
  queued-transactions
  queued-transactions-by-sender
  basefee-transactions
  basefee-transactions-by-sender
  blob-transactions
  blob-transactions-by-sender
  transaction-admitted-at)

(defgeneric txpool-component (store)
  (:documentation "Return STORE's txpool component, or NIL when none exists."))

(defmethod txpool-component ((store t))
  nil)

(defmethod txpool-component ((txpool engine-pending-txpool))
  txpool)
