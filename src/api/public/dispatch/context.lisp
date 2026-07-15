(in-package #:ethereum-lisp.public-api)

;;;; Public JSON-RPC dispatch context and response helpers.

(defstruct (public-rpc-dispatch-context
            (:constructor make-public-rpc-dispatch-context
                (id method params store config
                 &key network-id
                      coinbase
                      allowed-method-p
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
                      txpool-now)))
  id
  method
  params
  store
  config
  network-id
  coinbase
  allowed-method-p
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
  txpool-now)

(defun public-rpc-dispatch-method-p (context name)
  (string= (public-rpc-dispatch-context-method context) name))

(defun public-rpc-dispatch-response (context result)
  (json-rpc-response
   (public-rpc-dispatch-context-id context)
   :result result))
