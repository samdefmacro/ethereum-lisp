(in-package #:ethereum-lisp.evm.internal)

(defun execute-create-initcode (initcode child-context child-gas-limit)
  (if child-gas-limit
      (execute-bytecode initcode
                        :context child-context
                        :gas-limit child-gas-limit)
      (execute-bytecode initcode :context child-context)))

(defun execute-contract-creation (state
                                  context
                                  creator
                                  new-address
                                  value
                                  initcode
                                  gas-limit
                                  gas-used
                                  operation-name)
  (let* ((creator-account (account-or-empty state creator))
         (child-return-data (make-byte-vector 0))
         (child-gas-limit (child-create-gas-limit gas-limit gas-used))
         (child-started-p nil)
         (child-gas-used 0)
         (child-logs '())
         (child-refund-counter 0)
         (success-address 0))
    (cond
      ;; Depth, balance, and nonce-overflow failures push 0 and return the
      ;; full child gas to the caller. No nonce increment, no state change.
      ((>= (evm-context-depth context) +max-call-depth+)
       nil)
      ((< (state-account-balance creator-account) value)
       nil)
      ((= (state-account-nonce creator-account) +max-account-nonce+)
       nil)
      (t
       (increment-account-nonce state creator)
       (mark-account-accessed context new-address)
       (if (contract-address-collision-p state new-address)
        (setf child-gas-used (or child-gas-limit 0))
        (let ((snapshot (capture-execution-snapshot state context)))
          (handler-case
              (progn
                (transfer-call-value state creator new-address value)
                (let ((created-account (account-or-empty state new-address)))
                  (put-account-values
                   state
                   new-address
                   1
                   (state-account-balance created-account)
                   (state-account-code-hash created-account)))
                (mark-created-account context new-address)
                (let* ((child-context
                         (make-child-evm-context
                          context
                          :state state
                          :address new-address
                          :caller creator
                          :call-value value
                          :input (make-byte-vector 0)))
                       (child-result
                         (progn
                           (setf child-started-p t)
                           (execute-create-initcode
                            initcode child-context child-gas-limit))))
                  (setf child-gas-used (evm-result-gas-used child-result)
                        child-return-data
                        (evm-result-return-data child-result))
                  (if (eq (evm-result-status child-result) :reverted)
                      (restore-execution-snapshot state context snapshot)
                      (progn
                        (setf child-logs (evm-result-logs child-result))
                        (when (invalid-created-runtime-code-p
                               child-return-data
                               (evm-context-chain-rules context))
                          (fail "~A produced invalid runtime code"
                                operation-name))
                        (let ((deposit-gas
                                (created-code-deposit-gas
                                 child-return-data)))
                          ;; EIP-150 reserves one 64th in the parent.  Runtime
                          ;; code deposit is part of child creation and cannot
                          ;; spend that reserve.
                          (when (and child-gas-limit
                                     (> (+ child-gas-used deposit-gas)
                                        child-gas-limit))
                            (fail "~A code deposit out of gas"
                                  operation-name))
                          (incf child-gas-used deposit-gas))
                        (state-db-set-code state
                                           new-address
                                           child-return-data)
                        (incf child-refund-counter
                              (evm-result-refund-counter child-result))
                        (setf success-address (address-to-word new-address)
                              child-return-data (make-byte-vector 0))))))
            (evm-error ()
              (restore-execution-snapshot state context snapshot)
              (setf success-address 0
                    child-return-data (make-byte-vector 0)
                    child-logs '()
                    child-refund-counter 0
                    child-gas-used
                    (failed-create-child-gas-used
                     child-started-p child-gas-limit child-gas-used))))))))
    (values success-address
            child-return-data
            child-gas-used
            child-logs
            child-refund-counter)))
