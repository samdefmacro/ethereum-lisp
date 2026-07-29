(in-package #:ethereum-lisp.public-api)

(defun engine-rpc-handle-public-method
    (id method params store config
     &key network-id coinbase
          (allowed-method-p #'engine-rpc-any-method-p)
          allow-unprotected-transactions-p
          txpool-price-limit
          txpool-price-bump-percent
          txpool-account-slot-limit
          txpool-global-slot-limit
          txpool-account-queue-limit
          txpool-global-queue-limit
          txpool-local-addresses
          txpool-no-local-exemptions-p
          txpool-lifetime-seconds
          admin-backend
          (txpool-now 0))
  ;; Lifetime cleanup belongs to the node's periodic maintenance worker.  RPC
  ;; traffic must not be required for a private validator node to evict entries.
  (let ((context
          (make-public-rpc-dispatch-context
           id
           method
           params
           store
           config
           :network-id network-id
           :coinbase coinbase
           :allowed-method-p allowed-method-p
           :allow-unprotected-transactions-p
           allow-unprotected-transactions-p
           :txpool-price-limit txpool-price-limit
           :txpool-price-bump-percent txpool-price-bump-percent
           :txpool-account-slot-limit txpool-account-slot-limit
           :txpool-global-slot-limit txpool-global-slot-limit
           :txpool-account-queue-limit txpool-account-queue-limit
           :txpool-global-queue-limit txpool-global-queue-limit
           :txpool-local-addresses txpool-local-addresses
           :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
           :txpool-lifetime-seconds txpool-lifetime-seconds
           :admin-backend admin-backend
           :txpool-now txpool-now)))
    (or
     (engine-rpc-handle-public-metadata-method context)
     (engine-rpc-handle-public-state-method context)
     (engine-rpc-handle-public-block-method context)
     (engine-rpc-handle-public-transaction-method context)
     (engine-rpc-handle-public-filter-method context)
     (engine-rpc-handle-public-txpool-method context)
     (engine-rpc-handle-public-debug-method context)
     (engine-rpc-handle-public-admin-method context))))
