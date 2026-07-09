(in-package #:ethereum-lisp.core)

;;;; Public JSON-RPC block, header, ommer, and receipt dispatch.

(defun engine-rpc-handle-public-block-method (context)
  (let ((params (public-rpc-dispatch-context-params context))
        (store (public-rpc-dispatch-context-store context))
        (config (public-rpc-dispatch-context-config context)))
    (cond
      ((public-rpc-dispatch-method-p context "eth_getHeaderByNumber")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-header-by-number params store config)))
      ((public-rpc-dispatch-method-p context "eth_getHeaderByHash")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-header-by-hash params store)))
      ((public-rpc-dispatch-method-p context "eth_getBlockByNumber")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-block-by-number params store config)))
      ((public-rpc-dispatch-method-p context "eth_getBlockByHash")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-block-by-hash params store config)))
      ((public-rpc-dispatch-method-p
        context
        "eth_getBlockTransactionCountByNumber")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-block-transaction-count-by-number
         params store config)))
      ((public-rpc-dispatch-method-p
        context
        "eth_getBlockTransactionCountByHash")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-block-transaction-count-by-hash
         params store)))
      ((public-rpc-dispatch-method-p context "eth_getUncleCountByBlockNumber")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-uncle-count-by-number params store)))
      ((public-rpc-dispatch-method-p context "eth_getUncleCountByBlockHash")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-uncle-count-by-hash params store)))
      ((public-rpc-dispatch-method-p
        context
        "eth_getUncleByBlockNumberAndIndex")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-uncle-by-block-number-and-index
         params store)))
      ((public-rpc-dispatch-method-p
        context
        "eth_getUncleByBlockHashAndIndex")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-uncle-by-block-hash-and-index
         params store)))
      ((public-rpc-dispatch-method-p context "eth_getBlockReceipts")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-block-receipts params store config))))))
