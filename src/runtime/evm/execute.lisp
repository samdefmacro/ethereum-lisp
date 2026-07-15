(in-package #:ethereum-lisp.evm.internal)

(defun %execute-bytecode-frame (code context gas-limit step-budget)
  (let* ((*evm-step-budget* step-budget)
         (*evm-step-budget-policy-active-p* t)
         (machine (make-evm-machine code context gas-limit step-budget)))
    (loop until (or (evm-machine-halted-p machine)
                    (>= (evm-machine-pc machine)
                        (length (evm-machine-code machine))))
          do (step-evm-machine machine))
    (evm-machine-result machine)))

(defun execute-bytecode
    (code &key context gas-limit (max-steps nil max-steps-supplied-p))
  "Execute CODE in a fresh EVM call frame and return its EVM-RESULT.

Gas-limited frames rely on protocol gas for termination.  Gasless tooling keeps
a 100,000-step safety guard unless MAX-STEPS is supplied explicitly.  A numeric
MAX-STEPS is shared by the full CALL/CREATE execution tree; explicit NIL
disables the diagnostic guard for that tree."
  (check-type max-steps (or null (integer 0 *)))
  (let* ((inherited-policy-active-p
           *evm-step-budget-policy-active-p*)
         (inherited-budget *evm-step-budget*)
         (step-budget
           (cond
             (max-steps-supplied-p
              (and max-steps
                   (make-evm-step-budget :limit max-steps)))
             (inherited-policy-active-p
              inherited-budget)
             ((null gas-limit)
              (make-evm-step-budget
               :limit +default-gasless-evm-max-steps+))
             (t nil)))
         (budget-owner-p
           (and step-budget
                (or (not inherited-policy-active-p)
                    (not (eq step-budget inherited-budget)))))
         (state (and context (evm-context-state context)))
         (snapshot
           (and budget-owner-p
                context
                (capture-root-execution-snapshot state context))))
    (if budget-owner-p
        (handler-case
            (%execute-bytecode-frame code context gas-limit step-budget)
          (evm-step-limit-error (condition)
            (when snapshot
              (restore-root-execution-snapshot state context snapshot))
            (error condition)))
        (%execute-bytecode-frame code context gas-limit step-budget))))
