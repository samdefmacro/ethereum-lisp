(in-package #:ethereum-lisp.evm.internal)

(defun remaining-gas (gas-limit gas-used)
  (if gas-limit
      (max 0 (- gas-limit gas-used))
      0))

(defun all-but-one-64th (gas)
  (- gas (floor gas 64)))

(defun child-call-gas-limit (requested gas-limit gas-used &key (stipend 0))
  (+ stipend
     (if gas-limit
         (min requested (all-but-one-64th (remaining-gas gas-limit gas-used)))
         requested)))

(defun child-create-gas-limit (gas-limit gas-used)
  (and gas-limit
       (all-but-one-64th (remaining-gas gas-limit gas-used))))
