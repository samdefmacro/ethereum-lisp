(in-package #:ethereum-lisp.public-api)

;;;; Public JSON-RPC state, call, gas estimation, and access-list dispatch.

(defun engine-rpc-handle-public-state-method (context)
  (let ((params (public-rpc-dispatch-context-params context))
        (store (public-rpc-dispatch-context-store context))
        (config (public-rpc-dispatch-context-config context)))
    (cond
      ((public-rpc-dispatch-method-p context "eth_getBalance")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-balance params store)))
      ((public-rpc-dispatch-method-p context "eth_getTransactionCount")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-transaction-count params store config)))
      ((public-rpc-dispatch-method-p context "eth_getCode")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-code params store)))
      ((public-rpc-dispatch-method-p context "eth_getStorageAt")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-storage-at params store)))
      ((public-rpc-dispatch-method-p context "eth_getProof")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-get-proof params store)))
      ((public-rpc-dispatch-method-p context "eth_call")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-call params store config)))
      ((public-rpc-dispatch-method-p context "eth_estimateGas")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-estimate-gas params store config)))
      ((public-rpc-dispatch-method-p context "eth_createAccessList")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-create-access-list params store config))))))
