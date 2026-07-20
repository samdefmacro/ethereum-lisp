(in-package #:ethereum-lisp.evm.internal)

(defstruct evm-message-call
  "The semantic differences between CALL-family opcodes.

Memory expansion, access charging, snapshots, child execution, and result
merging are deliberately not configurable; those are shared EVM invariants."
  (requested-gas 0 :type (integer 0 *))
  code-address
  (args-offset 0 :type (integer 0 *))
  (args-size 0 :type (integer 0 *))
  (return-offset 0 :type (integer 0 *))
  (return-size 0 :type (integer 0 *))
  rest-stack
  child-address
  child-caller
  (child-value 0 :type (integer 0 *))
  read-only-p
  charge-value-gas-p
  new-account-p
  value-transfer-from
  value-transfer-to
  balance-check-address
  (balance-check-value 0 :type (integer 0 *))
  balance-check-message
  (merge-logs-p t :type boolean))

(defun execute-evm-message-call (machine call)
  "Execute one CALL-family operation described by CALL and update MACHINE."
  (with-slots (requested-gas code-address args-offset args-size
               return-offset return-size rest-stack child-address
               child-caller child-value read-only-p charge-value-gas-p
               new-account-p value-transfer-from
               value-transfer-to balance-check-address balance-check-value
               balance-check-message merge-logs-p)
      call
    (let* ((context (evm-machine-context machine))
           (state (evm-context-state context))
           (input-region (list args-offset args-size))
           (output-region (list return-offset return-size)))
      (evm-machine-charge-gas
       machine
       (memory-regions-expansion-gas
        (evm-machine-memory machine)
        input-region
        output-region))
      (setf (evm-machine-memory machine)
            (ensure-memory-regions
             (evm-machine-memory machine)
             input-region
             output-region))
      (let* ((snapshot (capture-execution-snapshot state context))
             (args (memory-slice
                    (evm-machine-memory machine)
                    args-offset
                    args-size))
             (precompile-p
               (active-precompile-address-p
                code-address
                (evm-context-chain-rules context))))
        (charge-account-access-gas
         context
         code-address
         (lambda (amount)
           (evm-machine-charge-gas machine amount)))
        ;; EIP-7702 (Prague+): calling a delegated account also accesses and
        ;; warms the delegation target, at the EIP-2929 cold/warm account cost.
        (let ((rules (evm-context-chain-rules context)))
          (when (and rules (chain-rules-prague-p rules))
            (let ((delegation-target
                    (set-code-delegation-target
                     (state-db-get-code state code-address))))
              (when delegation-target
                (evm-machine-charge-gas
                 machine
                 (if (gethash (account-access-key delegation-target)
                              (evm-context-accessed-addresses context))
                     +warm-storage-read-cost-eip2929+
                     +cold-account-access-cost-eip2929+))
                (mark-account-accessed context delegation-target)))))
        ;; Warmth survives a failed child, so the rollback snapshot must include
        ;; the just-accessed code address before child execution starts.
        (refresh-execution-snapshot-accessed-addresses snapshot context)
        (let ((gas-used-for-call-cap (evm-machine-gas-used machine)))
          (when charge-value-gas-p
            (let* ((required-value-gas
                     (call-value-extra-gas
                      state code-address child-value
                      :new-account-p new-account-p))
                   (charged-value-gas
                     (call-value-extra-gas
                      state code-address child-value
                      :new-account-p new-account-p
                      :stipend-discount-p (plusp child-value))))
              (evm-machine-charge-call-value-gas
               machine required-value-gas charged-value-gas)
              ;; EIP-150 caps the requested child gas after deducting the full
              ;; value-transfer cost.  The stipend affects net parent usage,
              ;; but must not increase the gas used to calculate that cap.
              ;; The child receives and may refund the stipend, so the parent
              ;; ultimately spends full-cost - stipend + child-gas-used.
              (setf gas-used-for-call-cap
                    (+ (evm-machine-gas-used machine)
                       (- required-value-gas charged-value-gas)))))
          (let ((child-gas-limit
                  (child-call-gas-limit
                   requested-gas
                   (evm-machine-gas-limit machine)
                   gas-used-for-call-cap
                   :stipend (if (and charge-value-gas-p
                                     (plusp child-value))
                                +call-stipend+
                                0))))
            (multiple-value-bind
                (success child-return-data child-gas-used
                 child-logs child-refund-counter)
                (execute-message-call-child
                 state context snapshot code-address args child-gas-limit
                 :child-address child-address
                 :child-caller child-caller
                 :child-call-value child-value
                 :read-only-p read-only-p
                 :precompile-address-p precompile-p
                 :value-transfer-from value-transfer-from
                 :value-transfer-to value-transfer-to
                 :balance-check-address balance-check-address
                 :balance-check-value balance-check-value
                 :balance-check-message balance-check-message)
              (evm-machine-charge-gas machine child-gas-used)
              (incf (evm-machine-refund-counter machine)
                    child-refund-counter)
              (setf (evm-machine-return-data-buffer machine)
                    child-return-data
                    (evm-machine-memory machine)
                    (copy-child-return-data-to-memory
                     (evm-machine-memory machine)
                     return-offset
                     return-size
                     child-return-data)
                    (evm-machine-stack machine)
                    (stack-push rest-stack success))
              (when merge-logs-p
                (setf (evm-machine-logs machine)
                      (prepend-child-logs
                       child-logs
                       (evm-machine-logs machine)))))))))))

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
  ;; A call at the 1024-deep call/create limit fails: push 0, no value
  ;; transfer, and the full child gas returns to the caller.
  (when (>= (evm-context-depth context) +max-call-depth+)
    (return-from execute-message-call-child
      (values 0 (make-byte-vector 0) 0 '() 0)))
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
            (setf child-started-p t))
          (multiple-value-bind (precompile-output precompile-gas precompile-p)
              (execute-precompile
               code-address args
               (evm-context-chain-rules context)
               child-gas-limit)
            (if precompile-p
                (progn
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
