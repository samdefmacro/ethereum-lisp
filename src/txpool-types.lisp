(in-package #:ethereum-lisp.core)

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
