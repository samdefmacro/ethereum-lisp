(in-package #:ethereum-lisp.evm)

(defun execute-arithmetic-opcode (machine opcode)
  "Execute arithmetic, comparison, bitwise, and KECCAK256 opcodes."
  (with-evm-machine-state (machine)
    (let ((op opcode))
      (cond
        ((= op #x00)
         (halt-evm-machine machine :stopped))
        ((= op #x01) (evm-machine-apply-binary machine #'+) (incf pc))
        ((= op #x02) (evm-machine-apply-binary machine #'*) (incf pc))
        ((= op #x03) (evm-machine-apply-binary machine #'-) (incf pc))
        ((= op #x04)
         (evm-machine-apply-binary machine (lambda (a b) (if (zerop b) 0 (floor a b))))
         (incf pc))
        ((= op #x05)
         (evm-machine-apply-binary machine #'signed-divide-word)
         (incf pc))
        ((= op #x06)
         (evm-machine-apply-binary machine (lambda (a b) (if (zerop b) 0 (mod a b))))
         (incf pc))
        ((= op #x07)
         (evm-machine-apply-binary machine #'signed-mod-word)
         (incf pc))
        ((= op #x08)
         (multiple-value-bind (a b modulus rest) (pop3 stack)
           (setf stack
                 (stack-push
                  rest
                  (if (zerop modulus) 0 (mod (+ a b) modulus)))))
         (incf pc))
        ((= op #x09)
         (multiple-value-bind (a b modulus rest) (pop3 stack)
           (setf stack
                 (stack-push
                  rest
                  (if (zerop modulus) 0 (mod (* a b) modulus)))))
         (incf pc))
        ((= op #x0a)
         (multiple-value-bind (base exponent rest) (pop2 stack)
           (evm-machine-charge-gas machine
            (* (exp-byte-gas
                (and context (evm-context-chain-rules context)))
               (exp-byte-count exponent)))
           (setf stack
                 (stack-push rest (modexp-word base exponent))))
         (incf pc))
        ((= op #x0b)
         (evm-machine-apply-binary machine #'signextend-word)
         (incf pc))
        ((= op #x10) (evm-machine-apply-comparison machine #'<) (incf pc))
        ((= op #x11) (evm-machine-apply-comparison machine #'>) (incf pc))
        ((= op #x12)
         (evm-machine-apply-comparison machine (lambda (a b)
                       (< (signed-word a) (signed-word b))))
         (incf pc))
        ((= op #x13)
         (evm-machine-apply-comparison machine (lambda (a b)
                       (> (signed-word a) (signed-word b))))
         (incf pc))
        ((= op #x14) (evm-machine-apply-comparison machine #'=) (incf pc))
        ((= op #x15)
         (multiple-value-bind (a rest) (pop1 stack)
           (setf stack (stack-push rest (if (zerop a) 1 0))))
         (incf pc))
        ((= op #x16) (evm-machine-apply-binary machine #'logand) (incf pc))
        ((= op #x17) (evm-machine-apply-binary machine #'logior) (incf pc))
        ((= op #x18) (evm-machine-apply-binary machine #'logxor) (incf pc))
        ((= op #x19)
         (multiple-value-bind (a rest) (pop1 stack)
           (setf stack (stack-push rest (logxor a (1- +word-modulus+)))))
         (incf pc))
        ((= op #x1a)
         (evm-machine-apply-binary machine #'byte-op)
         (incf pc))
        ((= op #x1b)
         (require-context-fork context
                               #'chain-rules-constantinople-p
                               "Constantinople" "SHL" pc)
         (evm-machine-apply-binary machine (lambda (shift value)
                   (if (>= shift 256) 0 (word (ash value shift)))))
         (incf pc))
        ((= op #x1c)
         (require-context-fork context
                               #'chain-rules-constantinople-p
                               "Constantinople" "SHR" pc)
         (evm-machine-apply-binary machine (lambda (shift value)
                   (if (>= shift 256) 0 (ash value (- shift)))))
         (incf pc))
        ((= op #x1d)
         (require-context-fork context
                               #'chain-rules-constantinople-p
                               "Constantinople" "SAR" pc)
         (evm-machine-apply-binary machine #'arithmetic-shift-right-word)
         (incf pc))
        ((= op #x20)
         (multiple-value-bind (offset size rest) (pop2 stack)
           (evm-machine-charge-gas machine
            (+ (memory-expansion-gas memory offset size)
               (* +keccak256-word-gas+
                  (memory-word-count size))))
           (setf memory (ensure-memory-size memory (+ offset size)))
           (setf stack
                 (stack-push
                  rest
                  (bytes-to-integer
                   (keccak-256 (memory-slice memory offset size))))))
         (incf pc))
        (t
         (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))



