(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-local-transaction-p
    (sender txpool-local-addresses txpool-no-local-exemptions-p)
  (txpool-local-transaction-p
   sender
   (make-txpool-admission-policy
    :local-addresses txpool-local-addresses
    :no-local-exemptions-p txpool-no-local-exemptions-p)))

(defun eth-rpc-local-transaction-predicate
    (config txpool-local-addresses txpool-no-local-exemptions-p)
  (txpool-local-transaction-predicate
   config
   (make-txpool-admission-policy
    :local-addresses txpool-local-addresses
    :no-local-exemptions-p txpool-no-local-exemptions-p)))

(defun eth-rpc-remove-expired-txpool-transactions
    (store config txpool-lifetime-seconds txpool-now
     txpool-local-addresses txpool-no-local-exemptions-p)
  (when txpool-lifetime-seconds
    (engine-payload-store-remove-expired-txpool-queued-view-transactions
     store
     txpool-lifetime-seconds
     txpool-now
     :local-transaction-predicate
     (eth-rpc-local-transaction-predicate
      config txpool-local-addresses txpool-no-local-exemptions-p))))
