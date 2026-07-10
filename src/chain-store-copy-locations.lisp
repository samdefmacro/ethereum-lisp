(in-package #:ethereum-lisp.chain-store)

(defun engine-payload-store-copy-transaction-location (location)
  (cond
    ((typep location 'engine-transaction-location)
     (let* ((index (engine-transaction-location-index location))
            (block-copy
              (engine-payload-store-copy-block
               (engine-transaction-location-block location)))
            (transaction
              (engine-transaction-location-transaction location))
            (receipt (engine-transaction-location-receipt location)))
       (make-engine-transaction-location
        :block block-copy
        :index index
        :transaction (or (nth index (block-transactions block-copy))
                         (and transaction
                              (engine-payload-store-copy-transaction
                               transaction)))
        :receipt (or (nth index (block-receipts block-copy))
                     (engine-payload-store-copy-receipt receipt))
        :log-index-start
        (engine-transaction-location-log-index-start location))))
    (t location)))

(defun engine-payload-store-copy-transaction-location-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-transaction-location value)))
             table)
    copy))
