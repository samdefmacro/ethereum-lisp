(in-package #:ethereum-lisp.core)

;;;; Public JSON-RPC transaction lookup, raw transaction, and admission dispatch.

(defun engine-rpc-handle-public-transaction-method (context)
  (let ((params (public-rpc-dispatch-context-params context))
        (store (public-rpc-dispatch-context-store context))
        (config (public-rpc-dispatch-context-config context)))
    (cond
      ((public-rpc-dispatch-method-p
        context
        "eth_getTransactionByBlockNumberAndIndex")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-transaction-by-block-number-and-index
         params store config)))
      ((public-rpc-dispatch-method-p
        context
        "eth_getTransactionByBlockHashAndIndex")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-transaction-by-block-hash-and-index
         params store config)))
      ((public-rpc-dispatch-method-p context "eth_getTransactionByHash")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-transaction-by-hash
         params store config)))
      ((public-rpc-dispatch-method-p context "eth_getTransactionReceipt")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-transaction-receipt
         params store config)))
      ((public-rpc-dispatch-method-p
        context
        "eth_getRawTransactionByBlockNumberAndIndex")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-raw-transaction-by-block-number-and-index
         params store config)))
      ((public-rpc-dispatch-method-p
        context
        "eth_getRawTransactionByBlockHashAndIndex")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-raw-transaction-by-block-hash-and-index
         params store config)))
      ((public-rpc-dispatch-method-p context "eth_getRawTransactionByHash")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-raw-transaction-by-hash
         params store config)))
      ((public-rpc-dispatch-method-p context "eth_sendRawTransaction")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-send-raw-transaction
         params
         store
         config
         :allow-unprotected-transactions-p
         (public-rpc-dispatch-context-allow-unprotected-transactions-p context)
         :txpool-price-limit
         (public-rpc-dispatch-context-txpool-price-limit context)
         :txpool-price-bump-percent
         (public-rpc-dispatch-context-txpool-price-bump-percent context)
         :txpool-account-slot-limit
         (public-rpc-dispatch-context-txpool-account-slot-limit context)
         :txpool-global-slot-limit
         (public-rpc-dispatch-context-txpool-global-slot-limit context)
         :txpool-account-queue-limit
         (public-rpc-dispatch-context-txpool-account-queue-limit context)
         :txpool-global-queue-limit
         (public-rpc-dispatch-context-txpool-global-queue-limit context)
         :txpool-local-addresses
         (public-rpc-dispatch-context-txpool-local-addresses context)
         :txpool-no-local-exemptions-p
         (public-rpc-dispatch-context-txpool-no-local-exemptions-p context)
         :txpool-now
         (public-rpc-dispatch-context-txpool-now context))))
      ((public-rpc-dispatch-method-p context "eth_pendingTransactions")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-pending-transactions params store config))))))
