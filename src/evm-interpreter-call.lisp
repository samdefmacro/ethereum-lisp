(in-package #:ethereum-lisp.evm)

(defun execute-message-call-child (state
                                   context
                                   snapshot
                                   code-address
                                   args
                                   child-gas-limit
                                   &key
                                   child-address
                                   child-caller
                                   (child-call-value 0)
                                   read-only-p
                                   precompile-address-p
                                   value-transfer-from
                                   value-transfer-to
                                   balance-check-address
                                   (balance-check-value 0)
                                   balance-check-message)
  (let ((success 0)
        (child-return-data (make-byte-vector 0))
        (child-logs '())
        (child-started-p nil)
        (child-gas-used 0)
        (child-refund-counter 0))
    (handler-case
        (progn
          (when (and balance-check-address
                     (< (account-balance state balance-check-address)
                        balance-check-value))
            (fail balance-check-message))
          (when (and value-transfer-from
                     value-transfer-to
                     (plusp child-call-value))
            (transfer-call-value state
                                 value-transfer-from
                                 value-transfer-to
                                 child-call-value))
          (when precompile-address-p
            (setf child-started-p t)
            (ensure-precompile-upfront-gas
             code-address args
             (evm-context-chain-rules context)
             child-gas-limit))
          (multiple-value-bind (precompile-output precompile-gas precompile-p)
              (run-precompile code-address args
                              (evm-context-chain-rules context))
            (if precompile-p
                (progn
                  (setf child-started-p t)
                  (when (> precompile-gas child-gas-limit)
                    (fail "Precompile out of gas"))
                  (setf success 1
                        child-gas-used precompile-gas
                        child-return-data precompile-output))
                (let ((callee-code (evm-resolved-code state code-address)))
                  (if (zerop (length callee-code))
                      (setf success 1)
                      (let* ((child-context
                               (make-child-evm-context
                                context
                                :state state
                                :address child-address
                                :caller child-caller
                                :call-value child-call-value
                                :input args
                                :read-only-p read-only-p))
                             (child-result
                               (progn
                                 (setf child-started-p t)
                                 (execute-bytecode
                                  callee-code
                                  :context child-context
                                  :gas-limit child-gas-limit))))
                        (multiple-value-bind
                              (child-success result-gas result-return-data
                               result-logs result-refund)
                            (apply-child-execution-result
                             state context snapshot child-result)
                          (setf success child-success
                                child-gas-used result-gas
                                child-return-data result-return-data
                                child-logs result-logs)
                          (incf child-refund-counter result-refund))))))))
      (evm-precompile-error (condition)
        (restore-execution-snapshot state context snapshot)
        (setf success 0
              child-return-data (make-byte-vector 0)
              child-logs '()
              child-gas-used
              (failed-precompile-child-gas-used
               condition child-gas-limit)))
      (evm-error ()
        (restore-execution-snapshot state context snapshot)
        (setf success 0
              child-return-data (make-byte-vector 0)
              child-logs '()
              child-gas-used
              (failed-child-execution-gas-used
               child-started-p child-gas-limit child-gas-used))))
    (values success
            child-return-data
            child-gas-used
            child-logs
            child-refund-counter)))
