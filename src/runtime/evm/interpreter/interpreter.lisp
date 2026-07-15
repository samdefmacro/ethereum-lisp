(in-package #:ethereum-lisp.evm.internal)

(defun execute-opcode (machine opcode)
  "Dispatch OPCODE to its semantic family."
  (cond
    ((<= #x00 opcode #x20)
     (execute-arithmetic-opcode machine opcode))
    ((<= #x30 opcode #x4a)
     (execute-environment-opcode machine opcode))
    ((<= #x50 opcode #x5f)
     (execute-state-memory-opcode machine opcode))
    ((<= #x60 opcode #xa4)
     (execute-stack-log-opcode machine opcode))
    ((<= #xf0 opcode #xff)
     (execute-system-opcode machine opcode))
    (t
     (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D"
           opcode
           (evm-machine-pc machine)))))

(defun step-evm-machine (machine)
  "Fetch and execute one opcode, enforcing tree-wide step and frame gas limits."
  (incf (evm-machine-steps machine))
  (let ((budget (evm-machine-step-budget machine)))
    (when budget
      (incf (evm-step-budget-steps budget))
      (when (> (evm-step-budget-steps budget)
               (evm-step-budget-limit budget))
        (error 'evm-step-limit-error
               :limit (evm-step-budget-limit budget)
               :steps (evm-step-budget-steps budget)
               :pc (evm-machine-pc machine)))))
  (let ((opcode (aref (evm-machine-code machine)
                      (evm-machine-pc machine))))
    (evm-machine-charge-gas machine (opcode-base-gas opcode))
    (execute-opcode machine opcode)))
