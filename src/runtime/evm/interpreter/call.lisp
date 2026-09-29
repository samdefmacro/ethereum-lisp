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
  child-address
  child-caller
  (child-value 0 :type (integer 0 *))
  read-only-p
  charge-value-gas-p
  new-account-p
  value-transfer-from
  value-transfer-to
  trace-value-transfer-from
  trace-value-transfer-to
  balance-check-address
  (balance-check-value 0 :type (integer 0 *))
  balance-check-message
  (merge-logs-p t :type boolean)
  ;; The opcode's name, for the call tracer only: the frame label geth's
  ;; callTracer reports (CALL, CALLCODE, DELEGATECALL, STATICCALL).
  (trace-type "CALL" :type string))

(defun execute-evm-message-call (machine call)
  "Execute one CALL-family operation described by CALL and update MACHINE."
  (when (and (evm-machine-gas-limit machine)
             (amsterdam-context-p (evm-machine-context machine)))
    (return-from execute-evm-message-call
      (execute-evm-message-call-amsterdam machine call)))
  (with-slots (requested-gas code-address args-offset args-size
               return-offset return-size child-address child-value
               charge-value-gas-p new-account-p merge-logs-p)
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
             (precompile-contract
               (resolved-precompile-contract
                code-address
                (evm-context-chain-rules context)
                (evm-context-precompile-contracts context))))
        (charge-account-access-gas
         context
         code-address
         (lambda (amount)
           (evm-machine-charge-gas machine amount)))
        (state-db-touch-account state child-address)
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
                          :new-account-p new-account-p
                          :eip158-p (context-eip158-p context))))
                   (charged-value-gas
                     (if (and amsterdam-p (plusp child-value))
                         (- +call-value-transfer-amsterdam+ +call-stipend+)
                         (call-value-extra-gas
                          state code-address child-value
                          :new-account-p new-account-p
                          :eip158-p (context-eip158-p context)
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
                                    0)
                       :eip150-p (context-eip150-p context)))))
            (multiple-value-bind
                (success child-return-data child-gas-used
                 child-logs child-refund-counter child-state-gas-used)
                (execute-message-call-child
                 state context snapshot code-address args child-gas-limit
                 call precompile-contract nil
                 (evm-gas-budget-state (evm-machine-gas-budget machine))
                 (and new-account-p (not (context-eip158-p context))))
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
                     child-return-data))
              (evm-stack-push machine success)
              (when merge-logs-p
                (setf (evm-machine-logs machine)
                      (prepend-child-logs
                       child-logs
                       (evm-machine-logs machine)))))))))))

(defun execute-evm-message-call-amsterdam (machine call)
  "Execute one CALL-family operation under Amsterdam's two-dimensional gas.

go-ethereum v1.17.6 makeCallVariantGasCallEIP8037 (CALL) and
makeCallVariantGasCallEIP7702 (the other three), then opCall: the cold
access, the memory and value charges, the delegation charge, CALL's
new-account state charge, and only then the 63/64 cap on the regular gas
left.  The caller pays the forwarded gas up front and hands the child its
state reservoir; the child's leftover (EVM-GAS-BUDGET-EXIT-REVERT, -HALT) is
absorbed, and CALL's new-account charge is refilled when the child failed and
its target is still empty."
  (with-slots (requested-gas code-address args-offset args-size
               return-offset return-size child-address child-value
               charge-value-gas-p new-account-p merge-logs-p)
      call
    (let* ((context (evm-machine-context machine))
           (state (evm-context-state context))
           (input-region (list args-offset args-size))
           (output-region (list return-offset return-size))
           (value-p (and charge-value-gas-p (plusp child-value)))
           (snapshot (capture-execution-snapshot state context)))
      (flet ((charge (amount)
               (evm-machine-charge-gas machine amount)))
        (charge-account-access-gas context code-address #'charge)
        ;; Every charge that precedes a state read is paid before it, so an
        ;; out-of-gas call records nothing in the block access list.
        (charge (+ (memory-regions-expansion-gas
                    (evm-machine-memory machine) input-region output-region)
                   (if value-p +call-value-transfer-amsterdam+ 0)))
        (setf (evm-machine-memory machine)
              (ensure-memory-regions
               (evm-machine-memory machine) input-region output-region))
        (let ((args (memory-slice (evm-machine-memory machine)
                                  args-offset args-size))
              (precompile-contract
                (resolved-precompile-contract
                 code-address
                 (evm-context-chain-rules context)
                 (evm-context-precompile-contracts context))))
          (state-db-touch-account state child-address)
          (let ((delegation-target
                  (set-code-delegation-target
                   (state-db-get-code state code-address))))
            (when delegation-target
              (charge (if (gethash (account-access-key delegation-target)
                                   (evm-context-accessed-addresses context))
                          +warm-account-access-amsterdam+
                          (context-cold-account-access-cost context)))
              (mark-account-accessed context delegation-target)
              ;; geth recordDelegationAccess: once its charge is paid, the
              ;; target is in the block access list, whether or not the call
              ;; then passes its depth and balance checks.
              (state-db-get-code state delegation-target)))
          ;; Warmth survives a failed child, so the rollback snapshot must
          ;; include the addresses accessed above.
          (refresh-execution-snapshot-accessed-addresses snapshot context)
          (when (and value-p new-account-p
                     (empty-account-p state code-address))
            (evm-machine-charge-state-gas machine +new-account-state-gas+))
          (let* ((call-gas
                   (min requested-gas
                        (all-but-one-64th
                         (evm-machine-regular-gas-left machine))))
                 (child-budget
                   (progn
                     (charge call-gas)
                     (make-evm-gas-budget
                      :regular (+ call-gas (if value-p +call-stipend+ 0))
                      :state (evm-gas-budget-state
                              (evm-machine-gas-budget machine))))))
            (multiple-value-bind
                  (success child-return-data child-gas-used
                   child-logs child-refund-counter child-state-gas-used
                   exit-budget)
                (execute-message-call-child
                 state context snapshot code-address args
                 (evm-gas-budget-regular child-budget)
                 call precompile-contract child-budget 0 nil)
              (declare (ignore child-gas-used child-state-gas-used))
              (evm-machine-absorb-child-budget machine exit-budget)
              (when (and value-p new-account-p (zerop success)
                         (empty-account-p state code-address))
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
                     child-return-data))
              (evm-stack-push machine success)
              (when merge-logs-p
                (setf (evm-machine-logs machine)
                      (prepend-child-logs
                       child-logs
                       (evm-machine-logs machine)))))))))))

;;; A CALL level's control stack.  A CALL that runs bytecode nests the
;;; child's whole frame chain on the caller's, so each level costs the frames
;;; between two %EXECUTE-BYTECODE-FRAMEs, and 1,024 levels of them must fit
;;; the thread that executes the block (docs/evidence/sec5-call-depth-stack.txt,
;;; EVM-CALL-LEVEL-CONTROL-STACK-FITS-THE-DEPTH-BUDGET).  So nothing on the
;;; way down keeps more alive than the child's results need:
;;; EXECUTE-MESSAGE-CALL-CHILD tail-calls the frame function when nothing is
;;; tracing, so its own frame is gone before the child's is pushed, and the
;;; opcode's description travels as the one EVM-MESSAGE-CALL object, read at
;;; its point of use, rather than as a keyword argument per field held in a
;;; frame (or a closure) for the life of the child.

(defun execute-message-call-child (state context snapshot code-address args
                                   child-gas-limit call precompile-contract
                                   child-budget child-state-gas-reservoir
                                   create-callee-p)
  "Run one CALL-family child frame for CALL, an EVM-MESSAGE-CALL, and return
(VALUES SUCCESS RETURN-DATA GAS-USED LOGS REFUND STATE-GAS-USED EXIT-BUDGET
FAILURE).

FAILURE is :REVERTED, the EVM-ERROR that ended the frame, or NIL; only the call
tracer reads it.  The traced frame is labelled the way geth's callTracer does:
CALL's TRACE-TYPE (the opcode), and the executing contract (CONTEXT's address)
as the caller, which for DELEGATECALL is not the child's CALLER.

PRECOMPILE-CONTRACT is the resolved precompile at CODE-ADDRESS, or NIL.

CREATE-CALLEE-P (a CALL before EIP-158) creates the child address as an empty
account when it does not exist, once the depth and balance checks pass, as
go-ethereum v1.17.6 EVM.Call does; a failed frame reverts it with the rest.

With CHILD-BUDGET (Amsterdam), the frame runs on that budget and EXIT-BUDGET
is its leftover for the caller to absorb, as geth's Call returns it: the
budget unchanged when the frame never started (depth or balance), the revert
or halt leftover when it failed, and the budget as the frame left it
otherwise.  CHILD-GAS-LIMIT is then CHILD-BUDGET's regular gas.  Without it,
the child's state-gas reservoir is CHILD-STATE-GAS-RESERVOIR."
  ;; Every frame of a call trace is one of these, so the tracer needs no hook
  ;; anywhere else.  Untraced, this is a tail call and costs one NIL check;
  ;; traced, the stack-allocated closure keeps this frame alive under the
  ;; child, which only a tracing run pays.
  (if (null *evm-call-tracer*)
      (%execute-message-call-child-frame
       state context snapshot code-address args child-gas-limit call
       precompile-contract child-budget child-state-gas-reservoir
       create-callee-p)
      (flet ((traced-frame ()
               (%execute-message-call-child-frame
                state context snapshot code-address args child-gas-limit call
                precompile-contract child-budget child-state-gas-reservoir
                create-callee-p)))
        (declare (dynamic-extent #'traced-frame))
        ;; The label and the caller come from the opcode: geth's callTracer
        ;; reports the executing contract as FROM for all four, the code
        ;; address as TO, the frame's value for CALL, CALLCODE and
        ;; DELEGATECALL (which inherits it), and no value for STATICCALL.
        ;; CREATE and CREATE2 are traced by EXECUTE-CONTRACT-CREATION.
        (call-with-evm-call-trace
         #'traced-frame
         :type (evm-message-call-trace-type call)
         :from (or (evm-context-address context)
                   (evm-message-call-child-caller call))
         :to code-address
         :value (evm-message-call-child-value call)
         :gas child-gas-limit
         :input args))))

(defun %execute-message-call-child-frame (state context snapshot code-address
                                          args child-gas-limit call
                                          precompile-contract child-budget
                                          child-state-gas-reservoir
                                          create-callee-p)
  "The body of EXECUTE-MESSAGE-CALL-CHILD, which documents it."
  (declare (type evm-message-call call))
  (let ((success 0)
        (trace-log-snapshot (evm-log-tracer-snapshot))
        (child-return-data (make-byte-vector 0))
        (child-logs '())
        (child-started-p nil)
        (child-gas-used 0)
        (child-state-gas-used 0)
        (child-refund-counter 0)
        (exit-budget child-budget)
        (failure nil))
    (handler-case
        (let ((child-call-value (evm-message-call-child-value call)))
          (when (and (evm-message-call-trace-value-transfer-from call)
                     (evm-message-call-trace-value-transfer-to call)
                     (plusp child-call-value))
            (evm-capture-trace-log
             (make-eth-trace-transfer-log-entry
              (evm-message-call-trace-value-transfer-from call)
              (evm-message-call-trace-value-transfer-to call)
              child-call-value)))
          ;; Geth enters the frame before rejecting depth or balance, so a
          ;; failed value call consumes a tracer index even though its log is
          ;; discarded on exit.
          (when (>= (evm-context-depth context) +max-call-depth+)
            (fail "Maximum EVM call depth exceeded"))
          (let ((balance-check-address
                  (evm-message-call-balance-check-address call)))
            (when (and balance-check-address
                       (< (account-balance state balance-check-address)
                          (evm-message-call-balance-check-value call)))
              (fail (evm-message-call-balance-check-message call))))
          (when (and create-callee-p
                     (null (state-db-get-account
                            state (evm-message-call-child-address call))))
            (state-db-set-account state (evm-message-call-child-address call)
                                  (make-state-account)))
          (when (and (evm-message-call-value-transfer-from call)
                     (evm-message-call-value-transfer-to call)
                     (plusp child-call-value))
            (let ((transfer-log
                    (transfer-call-value
                     state
                     (evm-message-call-value-transfer-from call)
                     (evm-message-call-value-transfer-to call)
                     child-call-value
                     (evm-context-chain-rules context)
                     :trace-p nil)))
              (when transfer-log
                (setf child-logs (list transfer-log)))))
          (when precompile-contract
            (setf child-started-p t))
          (multiple-value-bind (precompile-output precompile-gas precompile-p)
              (cond
                (precompile-contract
                 (execute-precompile
                  precompile-contract args
                  (evm-context-chain-rules context)
                  child-gas-limit))
                ((evm-context-precompile-contracts context)
                 (values (make-byte-vector 0) 0 nil))
                (t
                 (execute-precompile
                  code-address args
                  (evm-context-chain-rules context)
                  child-gas-limit)))
            (if precompile-p
                (progn
                  (when child-budget
                    (evm-gas-budget-charge-regular child-budget precompile-gas))
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
                                :address (evm-message-call-child-address call)
                                :caller (evm-message-call-child-caller call)
                                :call-value child-call-value
                                :input args
                                :read-only-p
                                (evm-message-call-read-only-p call)))
                             (child-result
                               (progn
                                 (setf child-started-p t)
                                 (execute-bytecode
                                  callee-code
                                  :context child-context
                                  :gas-limit child-gas-limit
                                  :gas-budget
                                  (or child-budget
                                      (make-evm-gas-budget
                                       :regular child-gas-limit
                                       :state child-state-gas-reservoir))))))
                        (multiple-value-bind
                              (child-success result-gas result-return-data
                               result-logs result-refund result-state-gas)
                            (apply-child-execution-result
                             state context snapshot child-result)
                          (when (eq (evm-result-status child-result)
                                    :reverted)
                            (setf failure :reverted)
                            (when child-budget
                              (setf exit-budget
                                    (evm-gas-budget-exit-revert
                                     child-budget))))
                          (setf success child-success
                                child-gas-used result-gas
                                child-return-data result-return-data
                                child-logs
                                (if (= child-success 1)
                                    (append child-logs result-logs)
                                    result-logs))
                          (setf child-state-gas-used result-state-gas)
                          (incf child-refund-counter result-refund))))))))
      (evm-precompile-error (condition)
        (restore-execution-snapshot state context snapshot)
        (when child-budget
          (setf exit-budget (evm-gas-budget-exit-halt child-budget)))
        (setf success 0
              failure condition
              child-return-data (make-byte-vector 0)
              child-logs '()
              child-gas-used
              (failed-precompile-child-gas-used
               condition child-gas-limit)))
      (evm-error (condition)
        (restore-execution-snapshot state context snapshot)
        (when (and child-budget child-started-p)
          (setf exit-budget (evm-gas-budget-exit-halt child-budget)))
        (setf success 0
              failure condition
              child-return-data (make-byte-vector 0)
              child-logs '()
              child-gas-used
              (failed-child-execution-gas-used
               child-started-p child-gas-limit child-gas-used))))
    (when (zerop success)
      (evm-log-tracer-restore trace-log-snapshot))
    (values success
            child-return-data
            child-gas-used
            child-logs
            child-refund-counter
            child-state-gas-used
            exit-budget
            failure)))
