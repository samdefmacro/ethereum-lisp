(in-package #:ethereum-lisp.txpool.index)

(defconstant +txpool-replacement-price-bump-percent+ 10)

(defstruct (engine-pending-txpool
            (:constructor make-engine-pending-txpool
                (&key (transactions (make-hash-table :test 'equal))
                      (transactions-by-sender
                       (make-hash-table :test 'equal))
                      (queued-transactions
                       (make-hash-table :test 'equal))
                      (queued-transactions-by-sender
                       (make-hash-table :test 'equal))
                      (basefee-transactions
                       (make-hash-table :test 'equal))
                      (basefee-transactions-by-sender
                       (make-hash-table :test 'equal))
                      (blob-transactions
                       (make-hash-table :test 'equal))
                      (blob-transactions-by-sender
                       (make-hash-table :test 'equal))
                      (transaction-admitted-at
                       (make-hash-table :test 'equal)))))
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
