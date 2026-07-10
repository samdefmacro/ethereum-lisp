(in-package #:ethereum-lisp.evm)

(defun execute-stack-log-opcode (machine opcode)
  "Execute PUSH, DUP, SWAP, and LOG opcode families."
  (with-evm-machine-state (machine)
    (let ((op opcode))
      (cond
        ((<= #x60 op #x7f)
         (let ((size (- op #x5f)))
           (setf stack (stack-push stack (read-push-immediate code pc size))
                 pc (+ pc 1 size))))
        ((<= #x80 op #x8f)
         (let ((depth (- op #x7f)))
           (when (< (length stack) depth)
             (fail "EVM stack underflow on DUP~D" depth))
           (setf stack (stack-push stack (nth (1- depth) stack))))
         (incf pc))
        ((<= #x90 op #x9f)
         (let ((depth (- op #x8f)))
           (when (< (length stack) (1+ depth))
             (fail "EVM stack underflow on SWAP~D" depth))
           (rotatef (first stack) (nth depth stack)))
         (incf pc))
        ((<= #xa0 op #xa4)
         (unless context
           (fail "LOG requires an EVM context"))
         (when (evm-context-read-only-p context)
           (fail "LOG is not allowed in read-only EVM context"))
        (let ((topic-count (- op #xa0)))
           (multiple-value-bind (memory-offset size rest1)
               (pop2 stack)
             (evm-machine-charge-gas machine
              (+ (memory-expansion-gas memory memory-offset size)
                 (* topic-count +log-topic-gas+)
                 (* size +log-data-gas+)))
             (setf memory
                   (ensure-memory-size memory
                                       (+ memory-offset size)))
             (let ((topics '())
                   (rest rest1))
               (dotimes (i topic-count)
                 (multiple-value-bind (topic next-rest) (pop1 rest)
                   (push (word-to-hash32 topic) topics)
                   (setf rest next-rest)))
               (push (make-log-entry
                      :address (evm-context-address context)
                      :topics (nreverse topics)
                      :data (memory-slice memory memory-offset size))
                     logs)
               (setf stack rest))))
         (incf pc))
        (t
         (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D" op pc))))))



