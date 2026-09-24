(in-package #:ethereum-lisp.evm.internal)

(defun execute-stack-log-opcode (machine opcode)
  "Execute PUSH, DUP, SWAP, and LOG opcode families."
  (declare (type evm-machine machine) (type (unsigned-byte 8) opcode))
  (with-evm-machine-state (machine)
    (let ((op opcode))
      (cond
        ((<= #x60 op #x7f)
         (let ((size (- op #x5f)))
           (evm-stack-push machine (read-push-immediate code pc size))
           (setf pc (+ pc 1 size))))
        ((<= #x80 op #x8f)
         (let ((depth (- op #x7f)))
           (when (< (evm-machine-sp machine) depth)
             (fail "EVM stack underflow on DUP~D" depth))
           (evm-stack-push-word
            machine
            (svref (evm-machine-stack machine)
                   (evm-stack-index machine (1- depth)))))
         (incf pc))
        ((<= #x90 op #x9f)
         (let ((depth (- op #x8f))
               (stack (evm-machine-stack machine)))
           (when (< (evm-machine-sp machine) (1+ depth))
             (fail "EVM stack underflow on SWAP~D" depth))
           (rotatef (svref stack (evm-stack-index machine 0))
                    (svref stack (evm-stack-index machine depth))))
         (incf pc))
        ((= op #xe6)
         (unless context
           (fail "DUPN requires an EVM context"))
         (require-context-fork context #'chain-rules-amsterdam-p
                               "Amsterdam" "DUPN" pc)
         (let ((immediate (read-opcode-immediate-byte code pc)))
           (when (< 90 immediate 128)
             (fail "Invalid DUPN immediate 0x~2,'0X at pc ~D" immediate pc))
           (let ((depth (decode-eip8024-single immediate)))
             (when (< (evm-machine-sp machine) depth)
               (fail "EVM stack underflow on DUPN depth ~D" depth))
             (evm-stack-push-word
              machine
              (svref (evm-machine-stack machine)
                     (evm-stack-index machine (1- depth))))))
         (incf pc 2))
        ((= op #xe7)
         (unless context
           (fail "SWAPN requires an EVM context"))
         (require-context-fork context #'chain-rules-amsterdam-p
                               "Amsterdam" "SWAPN" pc)
         (let ((immediate (read-opcode-immediate-byte code pc)))
           (when (< 90 immediate 128)
             (fail "Invalid SWAPN immediate 0x~2,'0X at pc ~D" immediate pc))
           (let ((depth (decode-eip8024-single immediate))
                 (stack (evm-machine-stack machine)))
             (when (< (evm-machine-sp machine) (1+ depth))
               (fail "EVM stack underflow on SWAPN depth ~D" depth))
             (rotatef (svref stack (evm-stack-index machine 0))
                      (svref stack (evm-stack-index machine depth)))))
         (incf pc 2))
        ((= op #xe8)
         (unless context
           (fail "EXCHANGE requires an EVM context"))
         (require-context-fork context #'chain-rules-amsterdam-p
                               "Amsterdam" "EXCHANGE" pc)
         (let ((immediate (read-opcode-immediate-byte code pc)))
           (when (< 81 immediate 128)
             (fail "Invalid EXCHANGE immediate 0x~2,'0X at pc ~D"
                   immediate pc))
           (multiple-value-bind (first-depth second-depth)
               (decode-eip8024-pair immediate)
             (let ((required (1+ (max first-depth second-depth)))
                   (stack (evm-machine-stack machine)))
               (when (< (evm-machine-sp machine) required)
                 (fail "EVM stack underflow on EXCHANGE; requires ~D items"
                       required))
               (rotatef (svref stack (evm-stack-index machine first-depth))
                        (svref stack
                               (evm-stack-index machine second-depth))))))
         (incf pc 2))
        ((<= #xa0 op #xa4)
         (unless context
           (fail "LOG requires an EVM context"))
         (when (evm-context-read-only-p context)
           (fail "LOG is not allowed in read-only EVM context"))
         (let* ((topic-count (- op #xa0))
                (memory-offset (evm-stack-pop machine))
                (size (evm-stack-pop machine)))
           (evm-machine-charge-gas machine
            (+ (memory-expansion-gas memory memory-offset size)
               (* topic-count +log-topic-gas+)
               (* size +log-data-gas+)))
           (setf memory
                 (ensure-memory-size memory
                                     (+ memory-offset size)))
           (let ((topics '()))
             (loop repeat topic-count
                   do (push (word-to-hash32 (evm-stack-pop machine)) topics))
             (let ((log
                     (make-log-entry
                      :address (evm-context-address context)
                      :topics (nreverse topics)
                      :data (memory-slice memory memory-offset size))))
               (evm-capture-trace-log log)
               (push log logs))))
         (incf pc))
        (t
         (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))
