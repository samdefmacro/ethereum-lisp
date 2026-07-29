(in-package #:ethereum-lisp.evm.internal)

(defun execute-create-initcode
    (initcode child-context child-gas-limit child-gas-budget)
  (if child-gas-limit
      (execute-bytecode initcode
                        :context child-context
                        :gas-limit child-gas-limit
                        :gas-budget child-gas-budget)
      (execute-bytecode initcode :context child-context)))

(defun execute-contract-creation (state
                                  context
                                  creator
                                  new-address
                                  value
                                  initcode
                                  machine
                                  operation-name)
  (let* ((creator-account (account-or-empty state creator))
         (child-return-data (make-byte-vector 0))
         (child-gas-limit
           (and (evm-machine-gas-limit machine)
                (child-create-regular-gas-limit
                 (evm-machine-regular-gas-left machine))))
         (child-started-p nil)
         (child-gas-used 0)
         (child-state-gas-used 0)
         (child-logs '())
         (child-refund-counter 0)
         (success-address 0)
         (charged-new-account-state-p nil))
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
       (when (and (amsterdam-context-p context)
                  (empty-account-p state new-address))
         (evm-machine-charge-state-gas machine +new-account-state-gas+)
         (setf charged-new-account-state-p t)
         (setf child-gas-limit
               (and (evm-machine-gas-limit machine)
                    (child-create-regular-gas-limit
                     (evm-machine-regular-gas-left machine)))))
       (if (contract-address-collision-p state new-address)
        (progn
          (setf child-gas-used (or child-gas-limit 0))
          (when charged-new-account-state-p
            (evm-machine-refill-state-gas
             machine +new-account-state-gas+)))
        (let ((snapshot (capture-execution-snapshot state context)))
          (handler-case
              (progn
                (let ((transfer-log
                        (transfer-call-value
                         state creator new-address value
                         (evm-context-chain-rules context))))
                  (when transfer-log
                    (setf child-logs (list transfer-log))))
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
                            initcode child-context child-gas-limit
                            (make-evm-gas-budget
                             :regular (or child-gas-limit 0)
                             :state
                             (evm-gas-budget-state
                              (evm-machine-gas-budget machine)))))))
                  (setf child-gas-used
                        (evm-result-regular-gas-used child-result)
                        child-state-gas-used
                        (evm-result-state-gas-used child-result)
                        child-return-data
                        (evm-result-return-data child-result))
                  (if (eq (evm-result-status child-result) :reverted)
                      (progn
                        (restore-execution-snapshot state context snapshot)
                        (when charged-new-account-state-p
                          (evm-machine-refill-state-gas
                           machine +new-account-state-gas+)))
                      (progn
                        (setf child-logs
                              (append child-logs
                                      (evm-result-logs child-result)))
                        (when (invalid-created-runtime-code-p
                               child-return-data
                               (evm-context-chain-rules context))
                          (fail "~A produced invalid runtime code"
                                operation-name))
                        (let* ((amsterdam-p (amsterdam-context-p context))
                               (deposit-gas
                                 (if amsterdam-p
                                     (* +keccak256-word-gas+
                                        (ceiling
                                         (length child-return-data) 32))
                                     (created-code-deposit-gas
                                      child-return-data)))
                               (deposit-state-gas
                                 (if amsterdam-p
                                     (* +cost-per-state-byte+
                                        (length child-return-data))
                                     0)))
                          ;; EIP-150 reserves one 64th in the parent.  Runtime
                          ;; code deposit is part of child creation and cannot
                          ;; spend that reserve.
                          (when (and child-gas-limit
                                     (> (+ child-gas-used deposit-gas)
                                        child-gas-limit))
                            (fail "~A code deposit out of gas"
                                  operation-name))
                          (incf child-gas-used deposit-gas)
                          (when (plusp deposit-state-gas)
                            (let ((budget
                                    (copy-evm-gas-budget
                                     (evm-result-gas-budget child-result))))
                              (unless (evm-gas-budget-charge
                                       budget
                                       (make-evm-gas-costs
                                        :regular deposit-gas
                                        :state deposit-state-gas))
                                (fail "~A code deposit out of gas"
                                      operation-name))
                              (incf child-state-gas-used
                                    deposit-state-gas))))
                        (state-db-set-code state
                                           new-address
                                           child-return-data)
                        (incf child-refund-counter
                              (evm-result-refund-counter child-result))
                        (setf success-address (address-to-word new-address)
                              child-return-data (make-byte-vector 0))))))
            (evm-error ()
              (restore-execution-snapshot state context snapshot)
              (when charged-new-account-state-p
                (evm-machine-refill-state-gas
                 machine +new-account-state-gas+))
              (setf success-address 0
                    child-return-data (make-byte-vector 0)
                    child-logs '()
                    child-refund-counter 0
                    child-state-gas-used 0
                    child-gas-used
                    (failed-create-child-gas-used
                     child-started-p child-gas-limit child-gas-used))))))))
    (values success-address
            child-return-data
            child-gas-used
            child-logs
            child-refund-counter
            child-state-gas-used)))
