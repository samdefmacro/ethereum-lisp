(in-package #:ethereum-lisp.core)

;;;; Public JSON-RPC log and filter dispatch.

(defun engine-rpc-handle-public-filter-method (context)
  (let ((params (public-rpc-dispatch-context-params context))
        (store (public-rpc-dispatch-context-store context))
        (config (public-rpc-dispatch-context-config context)))
    (cond
      ((public-rpc-dispatch-method-p context "eth_getLogs")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-logs params store)))
      ((public-rpc-dispatch-method-p context "eth_newFilter")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-new-filter params store)))
      ((public-rpc-dispatch-method-p context "eth_newBlockFilter")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-new-block-filter params store)))
      ((public-rpc-dispatch-method-p context "eth_newPendingTransactionFilter")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-new-pending-transaction-filter params store)))
      ((public-rpc-dispatch-method-p context "eth_getFilterLogs")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-filter-logs params store)))
      ((public-rpc-dispatch-method-p context "eth_getFilterChanges")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-filter-changes params store config)))
      ((public-rpc-dispatch-method-p context "eth_uninstallFilter")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-uninstall-filter params store))))))
