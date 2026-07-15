(in-package #:ethereum-lisp.evm.internal)

(defun execute-bytecode (code &key context gas-limit (max-steps 100000))
  "Execute CODE in a fresh EVM call frame and return its EVM-RESULT."
  (let ((machine (make-evm-machine code context gas-limit max-steps)))
    (loop until (or (evm-machine-halted-p machine)
                    (>= (evm-machine-pc machine)
                        (length (evm-machine-code machine))))
          do (step-evm-machine machine))
    (evm-machine-result machine)))
