(in-package #:ethereum-lisp.evm.internal)

(defun execute-opcode (machine opcode)
  "Dispatch OPCODE to its semantic family."
  (declare (type evm-machine machine) (type (unsigned-byte 8) opcode))
  (cond
    ((<= #x00 opcode #x20)
     (execute-arithmetic-opcode machine opcode))
    ((<= #x30 opcode #x4b)
     (execute-environment-opcode machine opcode))
    ((<= #x50 opcode #x5f)
     (execute-state-memory-opcode machine opcode))
    ((or (<= #x60 opcode #xa4)
         (<= #xe6 opcode #xe8))
     (execute-stack-log-opcode machine opcode))
    ((<= #xf0 opcode #xff)
     (execute-system-opcode machine opcode))
    (t
     (fail "Unsupported EVM opcode 0x~2,'0X at pc ~D"
           opcode
           (evm-machine-pc machine)))))

(declaim (inline step-evm-machine))
(defun step-evm-machine (machine)
  "Fetch and execute one opcode, enforcing tree-wide step and frame gas limits."
  (declare (type evm-machine machine))
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
    (%evm-machine-charge-gas
     machine
     (opcode-base-gas opcode (evm-machine-context machine)))
    (execute-opcode machine opcode)))

;;; The register loop.  STEP-EVM-MACHINE keeps the whole frame in the machine
;;; object, so every instruction reads and writes PC, SP, the stack vector and
;;; three gas counters through it, and reaches its handler through a range
;;; test, a call and a chain of opcode comparisons (SBCL 2.2.9 compiles CASE
;;; to a comparison chain on arm64, not a jump table).  On the Hoodi gas
;;; burner that is about 11 ns an instruction
;;; (docs/evidence/sec5-evm-throughput-2.txt).
;;;
;;; RUN-EVM-MACHINE holds PC, SP, the stack vector and the regular gas left in
;;; local variables and runs the stack, jump and cheap word instructions
;;; inline.  It charges each instruction's base gas before the instruction, as
;;; STEP-EVM-MACHINE does, and fails with the same messages at the same
;;; points.  Every other instruction runs its ordinary handler: the registers
;;; are first stored back into the machine (the regular gas charged since the
;;; last store is added to USED-REGULAR and GAS-USED then), so the handler sees
;;; exactly the frame STEP-EVM-MACHINE would have left it, and they are loaded
;;; again after it returns.  Registers are also stored before any failure and,
;;; through UNWIND-PROTECT, on any other exit while they are live.
;;;
;;; Frames the loop does not run: gasless tooling frames (no gas limit), frames
;;; under a diagnostic step budget, and a regular gas budget above the fixnum
;;; range (EEST uses some).  Those, and the rest of any frame whose regular
;;; gas leaves the fixnum range, take STEP-EVM-MACHINE.

(defun %run-evm-machine-in-registers (machine)
  "Run MACHINE in registers until it halts or its PC leaves the code, and
return T; return NIL, with the machine stored, when STEP-EVM-MACHINE must run
the rest of the frame."
  (declare (type evm-machine machine)
           (optimize speed)
           (sb-ext:muffle-conditions sb-ext:compiler-note))
  (let ((budget (evm-machine-gas-budget machine))
        (context (evm-machine-context machine)))
    (declare (type evm-gas-budget budget))
    (unless (and (evm-machine-gas-limit machine)
                 (null (evm-machine-step-budget machine))
                 (typep (evm-gas-budget-regular budget) 'evm-small-gas))
      (return-from %run-evm-machine-in-registers nil))
    (let* ((code (evm-machine-code machine))
           (code-length (length code))
           (jump-destinations (evm-machine-jump-destinations machine))
           (push0-p (context-fork-enabled-p context #'chain-rules-shanghai-p))
           (pc (evm-machine-pc machine))
           (sp (evm-machine-sp machine))
           (stack (evm-machine-stack machine))
           (gas (evm-gas-budget-regular budget))
           (charged 0)
           (steps 0)
           (registers-p t))
      (declare (type byte-vector code)
               (type simple-bit-vector jump-destinations)
               (type (and fixnum unsigned-byte) code-length pc charged steps)
               (type (integer 0 #.+stack-limit+) sp)
               (type simple-vector stack)
               (type evm-small-gas gas))
      (macrolet
          ((store-registers ()
             `(progn
                (setf (evm-machine-pc machine) pc
                      (evm-machine-sp machine) sp
                      (evm-gas-budget-regular budget) gas)
                (incf (evm-gas-budget-used-regular budget) charged)
                (incf (evm-machine-gas-used machine) charged)
                (incf (evm-machine-steps machine) steps)
                (setf charged 0
                      steps 0
                      registers-p nil)))
           (fail-stored (&rest arguments)
             `(progn (store-registers) (fail ,@arguments)))
           (pop-word ()
             `(progn
                (when (zerop sp)
                  (fail-stored "EVM stack underflow"))
                (decf sp)
                (svref stack sp)))
           (push-word (form)
             `(let ((value ,form))
                (when (>= sp +stack-limit+)
                  (fail-stored "EVM stack overflow"))
                (when (= sp (length stack))
                  (setf (evm-machine-sp machine) sp
                        stack (%grow-evm-stack machine)))
                (setf (svref stack sp) value)
                (incf sp)))
           (word-operation (operation)
             `(let* ((left (pop-word))
                     (right (pop-word)))
                (push-word (,operation left right))
                (incf pc)))
           (jump-to (destination)
             `(let ((destination ,destination))
                (unless (valid-jump-destination-p
                         code destination jump-destinations)
                  (fail-stored "Invalid EVM jump destination ~D"
                               destination))
                (setf pc destination)))
           (out-of-line (&body charge-and-execute)
             ;; Store, run the handler on the machine, and load again; or
             ;; leave the loop when the handler halted the frame or left the
             ;; regular gas outside the fixnum range.
             `(progn
                (store-registers)
                ,@charge-and-execute
                (when (evm-machine-halted-p machine)
                  (return t))
                (setf budget (evm-machine-gas-budget machine))
                (let ((regular (evm-gas-budget-regular budget)))
                  (unless (typep regular 'evm-small-gas)
                    (return nil))
                  (setf pc (evm-machine-pc machine)
                        sp (evm-machine-sp machine)
                        stack (evm-machine-stack machine)
                        gas regular
                        registers-p t)))))
        (unwind-protect
             (loop
               (when (>= pc code-length)
                 (return t))
               (incf steps)
               (let* ((op (aref code pc))
                      (base (svref *opcode-base-gas-table* op)))
                 (if (null base)
                     ;; The fork decides this opcode's base gas.
                     (out-of-line
                      (%evm-machine-charge-gas
                       machine (opcode-base-gas op context))
                      (execute-opcode machine op))
                     (let ((base base))
                       (declare (type evm-small-gas base))
                       (when (> base gas)
                         (fail-stored
                          "EVM out of gas (regular dimension) at pc ~D" pc))
                       (setf gas (- gas base)
                             charged (+ charged base))
                       (cond
                         ((<= #x60 op #x66)
                          (let ((size (- op #x5f)))
                            (push-word
                             (read-small-push-immediate code pc size))
                            (setf pc (+ pc 1 size))))
                         ((<= #x80 op #x8f)
                          (let ((depth (- op #x7f)))
                            (when (< sp depth)
                              (fail-stored "EVM stack underflow on DUP~D" depth))
                            (push-word (svref stack (- sp depth)))
                            (incf pc)))
                         ((<= #x90 op #x9f)
                          (let ((depth (- op #x8f)))
                            (when (< sp (1+ depth))
                              (fail-stored "EVM stack underflow on SWAP~D"
                                           depth))
                            (rotatef (svref stack (- sp 1))
                                     (svref stack (- sp 1 depth)))
                            (incf pc)))
                         ((= op #x5b) (incf pc))
                         ((= op #x57)
                          (let* ((destination (pop-word))
                                 (condition (pop-word)))
                            (if (eql condition 0)
                                (incf pc)
                                (jump-to destination))))
                         ((= op #x56) (jump-to (pop-word)))
                         ((= op #x50) (pop-word) (incf pc))
                         ((and (= op #x5f) push0-p) (push-word 0) (incf pc))
                         ((<= #x67 op #x7f)
                          (let ((size (- op #x5f)))
                            (push-word (read-push-immediate code pc size))
                            (setf pc (+ pc 1 size))))
                         ((= op #x01) (word-operation word-add))
                         ((= op #x03) (word-operation word-sub))
                         ((= op #x10) (word-operation word-lt))
                         ((= op #x11) (word-operation word-gt))
                         ((= op #x14) (word-operation word-eq))
                         ((= op #x15)
                          (push-word (word-iszero (pop-word)))
                          (incf pc))
                         ((= op #x16) (word-operation word-and))
                         ((= op #x17) (word-operation word-or))
                         ((= op #x18) (word-operation word-xor))
                         ((= op #x5a) (push-word gas) (incf pc))
                         ((= op #x58) (push-word pc) (incf pc))
                         (t
                          (out-of-line (execute-opcode machine op))))))))
          (when registers-p
            (store-registers)))))))

(defun run-evm-machine (machine)
  "Execute MACHINE's frame until it halts or its PC leaves the code."
  (declare (type evm-machine machine))
  (unless (%run-evm-machine-in-registers machine)
    (let ((code-length (length (evm-machine-code machine))))
      (loop until (or (evm-machine-halted-p machine)
                      (>= (evm-machine-pc machine) code-length))
            do (step-evm-machine machine)))))
