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
                     (if (amsterdam-context-p context)
                         +warm-account-access-amsterdam+
                         +warm-storage-read-cost-eip2929+)
                     (context-cold-account-access-cost context)))
                (mark-account-accessed context delegation-target)))))
        ;; Warmth survives a failed child, so the rollback snapshot must include
        ;; the just-accessed code address before child execution starts.
        (refresh-execution-snapshot-accessed-addresses snapshot context)
        (let ((gas-used-for-call-cap (evm-machine-gas-used machine))
              (regular-gas-left-for-call-cap
                (evm-machine-regular-gas-left machine))
              (charged-new-account-state-p nil))
          (when charge-value-gas-p
            (let* ((amsterdam-p (amsterdam-context-p context))
                   (required-value-gas
                     (if (and amsterdam-p (plusp child-value))
                         +call-value-transfer-amsterdam+
                         (call-value-extra-gas
                          state code-address child-value
                          :new-account-p new-account-p)))
                   (charged-value-gas
                     (if (and amsterdam-p (plusp child-value))
                         (- +call-value-transfer-amsterdam+ +call-stipend+)
                         (call-value-extra-gas
                          state code-address child-value
                          :new-account-p new-account-p
                          :stipend-discount-p (plusp child-value)))))
              (evm-machine-charge-call-value-gas
               machine required-value-gas charged-value-gas)
              ;; EIP-150 caps the requested child gas after deducting the full
              ;; value-transfer cost.  The stipend affects net parent usage,
              ;; but must not increase the gas used to calculate that cap.
              ;; The child receives and may refund the stipend, so the parent
              ;; ultimately spends full-cost - stipend + child-gas-used.
              (decf regular-gas-left-for-call-cap
                    (- required-value-gas charged-value-gas))
              (setf gas-used-for-call-cap
                    (+ (evm-machine-gas-used machine)
                       (- required-value-gas charged-value-gas)))
              (when (and amsterdam-p new-account-p
                         (plusp child-value)
                         (empty-account-p state code-address))
                (evm-machine-charge-state-gas
                 machine +new-account-state-gas+)
                (setf charged-new-account-state-p t))))
          (let ((child-gas-limit
                  (if (amsterdam-context-p context)
                      (+ (if (and charge-value-gas-p
                                  (plusp child-value))
                             +call-stipend+
                             0)
                         (if (evm-machine-gas-limit machine)
                             (min requested-gas
                                  (all-but-one-64th
                                   regular-gas-left-for-call-cap))
                             requested-gas))
                      (child-call-gas-limit
                       requested-gas
                       (evm-machine-gas-limit machine)
                       gas-used-for-call-cap
                       :stipend (if (and charge-value-gas-p
                                         (plusp child-value))
                                    +call-stipend+
                                    0)))))
            (multiple-value-bind
                (success child-return-data child-gas-used
                 child-logs child-refund-counter child-state-gas-used)
                (execute-message-call-child
                 state context snapshot code-address args child-gas-limit
                 :child-state-gas-reservoir
                 (evm-gas-budget-state
                  (evm-machine-gas-budget machine))
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
              (when (plusp child-state-gas-used)
                (evm-machine-charge-state-gas machine child-state-gas-used))
              (when (and charged-new-account-state-p (zerop success))
                (evm-machine-refill-state-gas
                 machine +new-account-state-gas+))
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
                                   (child-state-gas-reservoir 0)
                                   value-transfer-from
                                   value-transfer-to
                                   balance-check-address
                                   (balance-check-value 0)
                                   balance-check-message)
  ;; A call at the 1024-deep call/create limit fails: push 0, no value
  ;; transfer, and the full child gas returns to the caller.
  (when (>= (evm-context-depth context) +max-call-depth+)
    (return-from execute-message-call-child
      (values 0 (make-byte-vector 0) 0 '() 0 0)))
  ;; Every frame of a call trace is one of these, so the tracer needs no hook
  ;; anywhere else. FLET with DYNAMIC-EXTENT rather than a fresh closure: this
  ;; is the hottest path in the EVM, and a heap-allocated closure per call
  ;; would be a real cost paid by every execution to support a feature almost
  ;; none of them use. Stack-allocated, and with the tracer unbound, tracing
  ;; costs one NIL check.
  (flet ((traced-body ()
  (let ((success 0)
        (child-return-data (make-byte-vector 0))
        (child-logs '())
        (child-started-p nil)
        (child-gas-used 0)
        (child-state-gas-used 0)
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
            (let ((transfer-log
                    (transfer-call-value
                     state
                     value-transfer-from
                     value-transfer-to
                     child-call-value
                     (evm-context-chain-rules context))))
              (when transfer-log
                (setf child-logs (list transfer-log)))))
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
                (let ((callee-code
                        (evm-resolved-code
                         state code-address
                         (evm-context-chain-rules context))))
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
                                 :gas-limit child-gas-limit
                                 :gas-budget
                                 (make-evm-gas-budget
                                  :regular child-gas-limit
                                  :state child-state-gas-reservoir)))))
                        (multiple-value-bind
                              (child-success result-gas result-return-data
                               result-logs result-refund result-state-gas)
                            (apply-child-execution-result
                             state context snapshot child-result)
                          (setf success child-success
                                child-gas-used result-gas
                                child-return-data result-return-data
                                child-logs (append child-logs result-logs))
                          (setf child-state-gas-used result-state-gas)
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
            child-refund-counter
            child-state-gas-used))))
    (declare (dynamic-extent #'traced-body))
    ;; STATICCALL is derivable here; DELEGATECALL and CALLCODE are not, because
    ;; what distinguishes them is the caller and address the CALLER chose to
    ;; pass, and by this point those are just arguments. Reporting CALL for them
    ;; is a known limitation, named rather than papered over -- as is CREATE,
    ;; which does not come through this function at all. (CHILD-ADDRESS is NOT
    ;; the create marker it looks like: an ordinary call passes it too.)
    (call-with-evm-call-trace
     #'traced-body
     :type (if read-only-p "STATICCALL" "CALL")
     :from child-caller
     :to code-address
     :value child-call-value
     :gas child-gas-limit
     :input args)))
