(in-package #:ethereum-lisp.public-api)

;;;; Public JSON-RPC debug namespace dispatch.

(defun engine-rpc-handle-public-debug-method (context)
  (let ((params (public-rpc-dispatch-context-params context))
        (store (public-rpc-dispatch-context-store context))
        (config (public-rpc-dispatch-context-config context)))
    (cond
      ((public-rpc-dispatch-method-p context "debug_getRawHeader")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-debug-get-raw-header params store)))
      ((public-rpc-dispatch-method-p context "debug_getRawBlock")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-debug-get-raw-block params store)))
      ((public-rpc-dispatch-method-p context "debug_getRawReceipts")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-debug-get-raw-receipts params store)))
      ((public-rpc-dispatch-method-p context "debug_getRawTransaction")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-debug-get-raw-transaction params store config))))))
