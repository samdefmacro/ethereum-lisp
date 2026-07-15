(in-package #:ethereum-lisp.public-api)

;;;; Public JSON-RPC txpool namespace dispatch.

(defun engine-rpc-handle-public-txpool-method (context)
  (let ((params (public-rpc-dispatch-context-params context))
        (store (public-rpc-dispatch-context-store context))
        (config (public-rpc-dispatch-context-config context)))
    (cond
      ((public-rpc-dispatch-method-p context "txpool_status")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-txpool-status params store config)))
      ((public-rpc-dispatch-method-p context "txpool_content")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-txpool-content params store config)))
      ((public-rpc-dispatch-method-p context "txpool_contentFrom")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-txpool-content-from params store config)))
      ((public-rpc-dispatch-method-p context "txpool_inspect")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-txpool-inspect params store config))))))
