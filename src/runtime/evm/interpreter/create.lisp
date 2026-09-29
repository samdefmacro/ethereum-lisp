(in-package #:ethereum-lisp.evm.internal)

(defun execute-create-initcode
    (initcode child-context child-gas-limit child-gas-budget)
  (if child-gas-limit
      (execute-bytecode initcode
                        :context child-context
                        :gas-limit child-gas-limit
                        :gas-budget child-gas-budget)
      (execute-bytecode initcode :context child-context)))

(defun run-created-contract-amsterdam
    (state context creator new-address value initcode child-budget
     operation-name)
  "Deploy INITCODE at NEW-ADDRESS on CHILD-BUDGET, after geth v1.17.6
EVM.create and initNewContract under Amsterdam, and return (VALUES
SUCCESS-ADDRESS RETURN-DATA LOGS REFUND EXIT-BUDGET).  The code size and the
0xEF prefix are checked before the deposit is charged, the deposit's hash cost
before its state cost, and any failure but a revert halts the child."
  (let ((snapshot (capture-execution-snapshot state context))
        (logs '()))
    (handler-case
        (progn
          (let ((transfer-log
                  (transfer-call-value
                   state creator new-address value
                   (evm-context-chain-rules context)
                   :trace-p nil)))
            (when transfer-log
              (setf logs (list transfer-log))))
          (let ((created-account (account-or-empty state new-address)))
            (put-account-values
             state new-address 1
             (state-account-balance created-account)
             (state-account-code-hash created-account)))
          (mark-created-account context new-address)
          (let ((result
                  (execute-create-initcode
                   initcode
                   (make-child-evm-context
                    context
                    :state state
                    :address new-address
                    :caller creator
                    :call-value value
                    :input (make-byte-vector 0))
                   (evm-gas-budget-regular child-budget)
                   child-budget)))
            (if (eq (evm-result-status result) :reverted)
                (progn
                  (restore-execution-snapshot state context snapshot)
                  (values 0 (evm-result-return-data result) '() 0
                          (evm-gas-budget-exit-revert child-budget)))
                (let ((code (evm-result-return-data result)))
                  (when (invalid-created-runtime-code-p
                         code (evm-context-chain-rules context))
                    (fail "~A produced invalid runtime code" operation-name))
                  (unless (and (evm-gas-budget-charge-regular
                                child-budget
                                (* +keccak256-word-gas+
                                   (ceiling (length code) 32)))
                               (evm-gas-budget-charge-state
                                child-budget
                                (* +cost-per-state-byte+ (length code))))
                    (fail "~A code deposit out of gas" operation-name))
                  (state-db-set-code state new-address code)
                  (values (address-to-word new-address)
                          (make-byte-vector 0)
                          (append logs (evm-result-logs result))
                          (evm-result-refund-counter result)
                          child-budget)))))
      (evm-error ()
        (restore-execution-snapshot state context snapshot)
        (values 0 (make-byte-vector 0) '() 0
                (evm-gas-budget-exit-halt child-budget))))))

(defun execute-contract-creation-amsterdam
    (state context creator new-address value initcode machine operation-name)
  "CREATE and CREATE2 under Amsterdam, after geth v1.17.6 opCreate and
opCreate2: a failed depth, balance or nonce precheck pushes zero and spends
nothing; an empty destination is charged its account creation as state gas in
this frame; then 63/64 of the regular gas left and the whole reservoir go to
the child, whose leftover this frame absorbs.  A failed creation (revert,
halt or address collision) refills the account-creation charge.

Returns the values EXECUTE-CONTRACT-CREATION does, with no gas left for the
caller to charge."
  (let ((trace-log-snapshot (evm-log-tracer-snapshot))
        (creator-account (account-or-empty state creator)))
    (when (and *evm-trace-transfers-p* (plusp value))
      (evm-capture-trace-log
       (make-eth-trace-transfer-log-entry creator new-address value)))
    (when (or (>= (evm-context-depth context) +max-call-depth+)
              (< (state-account-balance creator-account) value)
              (= (state-account-nonce creator-account) +max-account-nonce+))
      (evm-log-tracer-restore trace-log-snapshot)
      (return-from execute-contract-creation-amsterdam
        (values 0 (make-byte-vector 0) 0 '() 0 0)))
    (let ((charged-p nil))
      (when (empty-account-p state new-address)
        (evm-machine-charge-state-gas machine +new-account-state-gas+)
        (setf charged-p t))
      (let* ((forward (child-create-regular-gas-limit
                       (evm-machine-regular-gas-left machine)))
             (child-budget
               (evm-gas-budget-forward (evm-machine-gas-budget machine)
                                       forward)))
        (incf (evm-machine-gas-used machine) forward)
        (increment-account-nonce state creator)
        (mark-account-accessed context new-address)
        (multiple-value-bind
              (success-address return-data logs refund exit-budget)
            (if (contract-address-collision-p state new-address)
                ;; EIP-8037: a collision burns the regular gas and keeps the
                ;; reservoir.
                (values 0 (make-byte-vector 0) '() 0
                        (evm-gas-budget-exit-halt child-budget))
                (run-created-contract-amsterdam
                 state context creator new-address value initcode
                 child-budget operation-name))
          (evm-machine-absorb-child-budget machine exit-budget)
          (when (and charged-p (zerop success-address))
            (evm-machine-refill-state-gas machine +new-account-state-gas+))
          (when (zerop success-address)
            (evm-log-tracer-restore trace-log-snapshot))
          ;; The tracer's FAILURE is not distinguished here: an Amsterdam
          ;; creation frame that fails reports a generic error.
          (values success-address return-data 0 logs refund 0 nil
                  (and *evm-call-tracer*
                       (not (zerop success-address))
                       (state-db-get-code state new-address))))))))

(defun execute-contract-creation (state
                                  context
                                  creator
                                  new-address
                                  value
                                  initcode
                                  machine
                                  operation-name)
  "Run CREATE or CREATE2 (OPERATION-NAME) and return (VALUES SUCCESS-ADDRESS
RETURN-DATA GAS-USED LOGS REFUND STATE-GAS-USED FAILURE DEPLOYED-CODE).

The last two are for the call tracer, which records the creation as a frame of
its own when one is bound (CALL-WITH-EVM-CREATE-TRACE); untraced, this costs
one special-variable read."
  (flet ((create ()
           (if (and (evm-machine-gas-limit machine)
                    (amsterdam-context-p context))
               (execute-contract-creation-amsterdam
                state context creator new-address value initcode machine
                operation-name)
               (%execute-contract-creation
                state context creator new-address value initcode machine
                operation-name))))
    (declare (dynamic-extent #'create))
    (if *evm-call-tracer*
        (call-with-evm-create-trace
         #'create
         :type operation-name
         :from creator
         :to new-address
         :value value
         :gas (if (evm-machine-gas-limit machine)
                  (child-create-regular-gas-limit
                   (evm-machine-regular-gas-left machine)
                   :eip150-p (context-eip150-p context))
                  0)
         :input initcode)
        (create))))

(defun %execute-contract-creation (state
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
                 (evm-machine-regular-gas-left machine)
                 :eip150-p (context-eip150-p context))))
         (child-started-p nil)
         (child-gas-used 0)
         (child-state-gas-used 0)
         (child-logs '())
         (trace-log-snapshot (evm-log-tracer-snapshot))
         (child-refund-counter 0)
         (success-address 0)
         (charged-new-account-state-p nil)
         ;; For the call tracer only (EXECUTE-CONTRACT-CREATION).
         (failure nil)
         (deployed-code nil))
    (when (and *evm-trace-transfers-p* (plusp value))
      (evm-capture-trace-log
       (make-eth-trace-transfer-log-entry creator new-address value)))
    (cond
      ;; Depth, balance, and nonce-overflow failures push 0 and return the
      ;; full child gas to the caller. No nonce increment, no state change.
      ((>= (evm-context-depth context) +max-call-depth+)
       (setf failure "max call depth exceeded"))
      ((< (state-account-balance creator-account) value)
       (setf failure "insufficient balance for transfer"))
      ((= (state-account-nonce creator-account) +max-account-nonce+)
       (setf failure "nonce uint64 overflow"))
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
                     (evm-machine-regular-gas-left machine)
                     :eip150-p (context-eip150-p context)))))
       (if (contract-address-collision-p state new-address)
        (progn
          (setf child-gas-used (or child-gas-limit 0)
                failure "contract address collision")
          (when charged-new-account-state-p
            (evm-machine-refill-state-gas
             machine +new-account-state-gas+)))
        (let ((snapshot (capture-execution-snapshot state context)))
          (handler-case
              (progn
                (let ((transfer-log
                        (transfer-call-value
                         state creator new-address value
                         (evm-context-chain-rules context)
                         :trace-p nil)))
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
                        (setf child-logs '()
                              failure :reverted)
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
                              deployed-code child-return-data
                              child-return-data (make-byte-vector 0))))))
            (evm-error (condition)
              (restore-execution-snapshot state context snapshot)
              (when charged-new-account-state-p
                (evm-machine-refill-state-gas
                 machine +new-account-state-gas+))
              (setf success-address 0
                    failure condition
                    child-return-data (make-byte-vector 0)
                    child-logs '()
                    child-refund-counter 0
                    child-state-gas-used 0
                    child-gas-used
                    (failed-create-child-gas-used
                     child-started-p child-gas-limit child-gas-used))))))))
    (when (zerop success-address)
      (evm-log-tracer-restore trace-log-snapshot))
    (values success-address
            child-return-data
            child-gas-used
            child-logs
            child-refund-counter
            child-state-gas-used
            failure
            deployed-code)))
