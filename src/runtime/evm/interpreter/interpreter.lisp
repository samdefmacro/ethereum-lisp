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
  (let ((budget (evm-machine-step-budget machine)))
    (when budget
      (incf (evm-step-budget-steps budget))
      (when (> (evm-step-budget-steps budget)
               (evm-step-budget-limit budget))
        (error 'evm-step-limit-error
               :limit (evm-step-budget-limit budget)
               :steps (evm-step-budget-steps budget)
               :pc (evm-machine-pc machine)))
      (let ((deadline (evm-step-budget-deadline budget)))
        (when (and deadline
                   (zerop (mod (evm-step-budget-steps budget)
                               +evm-deadline-check-steps+))
                   (> (get-internal-real-time) deadline))
          (error 'evm-execution-deadline-error
                 :seconds (evm-step-budget-seconds budget))))))
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
;;; %RUN-EVM-MACHINE-IN-REGISTERS holds PC, SP, the stack vector and the
;;; regular gas left in local variables and runs the stack, jump and cheap
;;; word instructions inline.  It charges each one's base gas before it, as
;;; STEP-EVM-MACHINE does, and fails with the same messages at the same
;;; points.  At any other instruction it stores the registers back into the
;;; machine (the regular gas charged since they were loaded is added to
;;; USED-REGULAR and GAS-USED then) and returns, and RUN-EVM-MACHINE runs the
;;; instruction's handler on exactly the frame the step loop would have left
;;; (EXECUTE-OPCODE when the loop charged the base gas, STEP-EVM-MACHINE when
;;; the fork decides it), then enters the register loop again.  Returning
;;; rather than calling the handler from inside the loop keeps the loop's
;;; stack frame off the stack while a CALL runs the next level: every byte
;;; kept live across a CALL is paid 1,024 times over, and the level's budget
;;; is a test (EVM-CALL-LEVEL-CONTROL-STACK-FITS-THE-DEPTH-BUDGET;
;;; docs/evidence/sec5-call-depth-stack.txt).
;;;
;;; The registers are also stored before any failure the loop signals and
;;; when the code runs out.  A host error inside the loop itself (heap
;;; exhaustion growing the stack) leaves the machine behind its registers;
;;; nothing reads a machine a host error abandoned.  There is no
;;; UNWIND-PROTECT: a variable its cleanup reads lives in the stack frame, not
;;; a register, and the burner ran 25% slower that way.
;;;
;;; Frames the loop does not run: gasless tooling frames (no gas limit), frames
;;; under a diagnostic step budget, and a regular gas budget above the fixnum
;;; range (EEST uses some).  Those, and the rest of any frame whose regular
;;; gas leaves the fixnum range, take STEP-EVM-MACHINE alone.

(defun %run-evm-machine-in-registers (machine push0-p)
  "Run MACHINE's inline instructions in registers from its PC.  Return, with
the registers stored, :END when the PC has left the code, :EXECUTE when the
instruction at the PC is charged and needs its handler, or :STEP when it
needs STEP-EVM-MACHINE (its base gas depends on the fork and is not charged).
PUSH0-P says whether the frame's fork has PUSH0."
  (declare (type evm-machine machine)
           (optimize speed)
           (sb-ext:muffle-conditions sb-ext:compiler-note))
  (let* ((code (evm-machine-code machine))
         (code-length (length code))
         (pc (evm-machine-pc machine))
         (sp (evm-machine-sp machine))
         (stack (evm-machine-stack machine))
         (budget (evm-machine-gas-budget machine))
         (gas (evm-gas-budget-regular budget))
         (charged 0))
    (declare (type byte-vector code)
             (type (and fixnum unsigned-byte) code-length pc charged)
             (type (integer 0 #.+stack-limit+) sp)
             (type simple-vector stack)
             (type evm-gas-budget budget)
             (type evm-small-gas gas))
    (macrolet
        ((store-registers ()
           `(progn
              (setf (evm-machine-pc machine) pc
                    (evm-machine-sp machine) sp
                    (evm-gas-budget-regular budget) gas)
              (incf (evm-gas-budget-used-regular budget) charged)
              (incf (evm-machine-gas-used machine) charged)))
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
                       code destination
                       (evm-machine-jump-destinations machine))
                (fail-stored "Invalid EVM jump destination ~D" destination))
              (setf pc destination))))
      (loop
        (when (>= pc code-length)
          (store-registers)
          (return :end))
        (let* ((op (aref code pc))
               (base (svref *opcode-base-gas-table* op)))
          (when (null base)
            ;; The fork decides this opcode's base gas.
            (store-registers)
            (return :step))
          (let ((base base))
            (declare (type evm-small-gas base))
            (when (> base gas)
              (fail-stored "EVM out of gas (regular dimension) at pc ~D" pc))
            (setf gas (- gas base)
                  charged (+ charged base))
            (cond
              ((<= #x60 op #x66)
               (let ((size (- op #x5f)))
                 (push-word (read-small-push-immediate code pc size))
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
                   (fail-stored "EVM stack underflow on SWAP~D" depth))
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
              ((= op #x15) (push-word (word-iszero (pop-word))) (incf pc))
              ((= op #x16) (word-operation word-and))
              ((= op #x17) (word-operation word-or))
              ((= op #x18) (word-operation word-xor))
              ((= op #x5a) (push-word gas) (incf pc))
              ((= op #x58) (push-word pc) (incf pc))
              (t
               ;; Charged; its handler runs outside this frame.
               (store-registers)
               (return :execute)))))))))


(defun %evm-machine-registers-p (machine)
  "Whether %RUN-EVM-MACHINE-IN-REGISTERS may run MACHINE now."
  (declare (type evm-machine machine))
  (and (evm-machine-gas-limit machine)
       (null (evm-machine-step-budget machine))
       (typep (evm-gas-budget-regular (evm-machine-gas-budget machine))
              'evm-small-gas)))

;;; Inlined into %EXECUTE-BYTECODE-FRAME, so a CALL level's stack holds that
;;; one frame and the handler's, as it did with the step loop alone.
(declaim (inline run-evm-machine))
(defun run-evm-machine (machine)
  "Execute MACHINE's frame until it halts or its PC leaves the code."
  (declare (type evm-machine machine))
  ;; Nothing but MACHINE stays live across a step here (every such value is
  ;; a stack slot in every CALL level), so PUSH0-P is asked again per entry.
  (when (%evm-machine-registers-p machine)
    (loop
      (ecase (%run-evm-machine-in-registers
              machine
              (context-fork-enabled-p (evm-machine-context machine)
                                      #'chain-rules-shanghai-p))
        (:end (return-from run-evm-machine))
        (:execute
         (execute-opcode machine (aref (evm-machine-code machine)
                                       (evm-machine-pc machine))))
        (:step (step-evm-machine machine)))
      (when (or (evm-machine-halted-p machine)
                (not (%evm-machine-registers-p machine)))
        (return))))
  (let ((code-length (length (evm-machine-code machine))))
    (loop until (or (evm-machine-halted-p machine)
                    (>= (evm-machine-pc machine) code-length))
          do (step-evm-machine machine))))
