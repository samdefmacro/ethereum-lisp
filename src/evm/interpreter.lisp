(in-package #:ethereum-lisp.evm)

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
  "Fetch and execute one opcode, enforcing frame-wide step and gas limits."
  (incf (evm-machine-steps machine))
  (when (> (evm-machine-steps machine)
           (evm-machine-max-steps machine))
    (fail "EVM exceeded maximum step count ~D"
          (evm-machine-max-steps machine)))
  (let ((opcode (aref (evm-machine-code machine)
                      (evm-machine-pc machine))))
    (evm-machine-charge-gas machine (opcode-base-gas opcode))
    (execute-opcode machine opcode)))
