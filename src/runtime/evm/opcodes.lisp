(in-package #:ethereum-lisp.evm.internal)

(defun read-push-immediate (code pc size)
  ;; PUSH1..PUSH7 immediates fit a fixnum: read them with word arithmetic.
  ;; Bytes past the end of the code read as zero either way.
  (when (and (typep code 'byte-vector)
             (typep pc '(and fixnum unsigned-byte))
             (typep size '(integer 0 7)))
    (let ((value 0)
          (end (length code)))
      (declare (type (unsigned-byte 56) value))
      (dotimes (i size)
        (let ((index (+ pc 1 i)))
          (setf value
                (logior (ash value 8)
                        (if (< index end) (aref code index) 0)))))
      (return-from read-push-immediate value)))
  ;; PUSH8..PUSH32: the leading SIZE mod 4 bytes, then one 32-bit piece at a
  ;; time, so a PUSH32 builds eight intermediate integers, not thirty-two.
  (when (and (typep code 'byte-vector)
             (typep pc '(and fixnum unsigned-byte))
             (typep size '(integer 8 32)))
    (let ((end (length code))
          (value 0)
          (index (1+ pc)))
      (declare (type fixnum end index))
      (flet ((next-byte ()
               (prog1 (if (< index end) (aref code index) 0)
                 (incf index))))
        (loop repeat (mod size 4)
              do (setf value (logior (ash value 8) (next-byte))))
        (loop repeat (floor size 4)
              do (let ((piece (logior (ash (next-byte) 24)
                                      (ash (next-byte) 16)
                                      (ash (next-byte) 8)
                                      (next-byte))))
                   (setf value (logior (ash value 32) piece)))))
      (return-from read-push-immediate value)))
  (let ((value 0))
    (dotimes (i size value)
      (let ((index (+ pc 1 i)))
        (setf value
              (+ (ash value 8)
                 (if (< index (length code)) (aref code index) 0)))))))

(defun read-opcode-immediate-byte (code pc)
  (let ((index (1+ pc)))
    (if (< index (length code)) (aref code index) 0)))

(defun decode-eip8024-single (immediate)
  (mod (+ immediate 145) 256))

(defun decode-eip8024-pair (immediate)
  (let* ((encoded (logxor immediate 143))
         (row (floor encoded 16))
         (column (mod encoded 16)))
    (if (< row column)
        (values (1+ row) (1+ column))
        (values (1+ column) (- 29 row)))))

(defun byte-op (index value)
  (if (>= index 32)
      0
      (logand #xff (ash value (* -8 (- 31 index))))))

(defun exp-byte-count (exponent)
  (if (zerop exponent)
      0
      (ceiling (integer-length exponent) 8)))

(defun exp-byte-gas (rules)
  (if (or (null rules) (chain-rules-eip158-p rules))
      +exp-byte-gas-eip160+
      +exp-byte-gas+))

(defun code-position-p (code position)
  (loop with pc = 0
        while (< pc (length code))
        do (let ((op (aref code pc)))
             (when (= pc position)
               (return t))
             (cond
               ((<= #x60 op #x7f)
                (incf pc (+ 1 (- op #x5f))))
               ((<= #xe6 op #xe8)
                (incf pc 2))
               (t
                (incf pc))))
        finally (return nil)))

(defun jump-destination-bitmap (code)
  (let ((bitmap (make-array (length code)
                            :element-type 'bit
                            :initial-element 0)))
    (loop with pc = 0
          while (< pc (length code))
          do (let ((op (aref code pc)))
               (when (= op #x5b)
                 (setf (sbit bitmap pc) 1))
               (cond
                 ((<= #x60 op #x7f)
                  (incf pc (+ 1 (- op #x5f))))
                 ((<= #xe6 op #xe8)
                  (incf pc 2))
                 (t
                  (incf pc)))))
    bitmap))

(defun valid-jump-destination-p (code destination &optional bitmap)
  (when (and (typep code 'byte-vector)
             (typep destination '(and fixnum unsigned-byte))
             (typep bitmap 'simple-bit-vector))
    ;; The interpreter's case: typed code, a fixnum target and the frame's
    ;; JUMPDEST bitmap.  A larger target is past any code, as below.
    (return-from valid-jump-destination-p
      (and (< destination (length code))
           (= (aref code destination) #x5b)
           (= 1 (sbit bitmap destination)))))
  (and (< destination (length code))
       (= (aref code destination) #x5b)
       (if bitmap
           (= 1 (sbit bitmap destination))
           (code-position-p code destination))))

(defun %opcode-base-gas-by-schedule (op &optional context)
  "The base-gas schedule as rules: the reference OPCODE-BASE-GAS reads through
its table for every opcode outside +CONTEXT-DEPENDENT-BASE-GAS-OPCODES+."
  (let ((amsterdam-p
          (and context
               (evm-context-chain-rules context)
               (chain-rules-amsterdam-p
                (evm-context-chain-rules context)))))
  (cond
    ((= op #x00) 0)
    ((member op '(#x01 #x03 #x10 #x11 #x12 #x13 #x14 #x15 #x16 #x17 #x18 #x19
                  #x1a #x1b #x1c #x1d #x35 #x51 #x52 #x53 #x5e)
             :test #'=)
     3)
    ((member op '(#x02 #x04 #x05 #x06 #x07 #x1e) :test #'=) 5)
    ((member op '(#x08 #x09) :test #'=) 8)
    ((= op #x0a) 10)
    ((= op #x0b) 5)
    ((= op #x20) 30)
    ((member op '(#x30 #x32 #x33 #x34 #x36 #x38 #x3a #x3d
                  #x41 #x42 #x43 #x44 #x45 #x46 #x48 #x4b
                  #x4a #x58 #x59 #x5a)
             :test #'=)
     2)
    ((= op #x47) 5)
    ((= op #x49) 3)
    ((= op #x31)
     (cond ((context-berlin-p context) 100)
           ((context-istanbul-p context) 700)
           ((context-eip150-p context) 400)
           (t 20)))
    ((member op '(#x3b #x3c) :test #'=)
     (if (context-berlin-p context)
         100
         (if (context-eip150-p context) 700 20)))
    ((= op #x3f)
     (cond ((context-berlin-p context) 100)
           ((context-istanbul-p context) 700)
           (t 400)))
    ((= op #x3e) 3)
    ((= op #x40) 20)
    ((member op '(#x37 #x39) :test #'=) 3)
    ((= op #x50) 2)
    ((= op #x54) 0)
    ((= op #x55) 0)
    ((= op #x56) 8)
    ((= op #x57) 10)
    ((member op '(#x5c #x5d) :test #'=) 100)
    ((= op #x5b) 1)
    ((= op #x5f) 2)
    ((<= #x60 op #x7f) 3)
    ((<= #x80 op #x9f) 3)
    ((member op '(#xe6 #xe7 #xe8) :test #'=) 3)
    ((<= #xa0 op #xa4) 375)
    ((member op '(#xf0 #xf5) :test #'=)
     (if amsterdam-p +create-access-amsterdam+ 32000))
    ((member op '(#xf1 #xf2 #xf4 #xfa) :test #'=)
     (cond ((context-berlin-p context) 100)
           ((context-eip150-p context) 700)
           (t 40)))
    ((member op '(#xf3 #xfd) :test #'=) 0)
    ((= op #xff) (if (context-eip150-p context) 5000 0))
    (t 0))))

;;; The interpreter charges base gas once per executed instruction, so the
;;; lookup is on the hottest path of block execution.  A CPU profile of a
;;; Hoodi gas-burner loop (docs/evidence/sec5-newpayload-six-second-cpu.txt)
;;; spent 43% of the time in the MEMBER/= chains of the schedule above.  The
;;; opcodes whose base gas depends on the fork (the account-access, call,
;;; create and selfdestruct families) keep reading the schedule with their
;;; context; every other opcode's base gas is fork-independent and is read
;;; from a table computed once from the same schedule.
(defparameter +context-dependent-base-gas-opcodes+
  '(#x31 #x3b #x3c #x3f #xf0 #xf1 #xf2 #xf4 #xf5 #xfa #xff)
  "Opcodes whose base gas the schedule derives from the frame's fork rules.")

(declaim (type (simple-array t (256)) *opcode-base-gas-table*))
(defparameter *opcode-base-gas-table*
  (let ((table (make-array 256 :initial-element nil)))
    (dotimes (op 256 table)
      (unless (member op +context-dependent-base-gas-opcodes+)
        (setf (svref table op) (%opcode-base-gas-by-schedule op nil)))))
  "Base gas per opcode, NIL where the schedule needs the frame's context.")

(declaim (inline opcode-base-gas))
(defun opcode-base-gas (op &optional context)
  (declare (type (unsigned-byte 8) op))
  (or (svref *opcode-base-gas-table* op)
      (%opcode-base-gas-by-schedule op context)))
