(in-package #:ethereum-lisp.evm.internal)

(defun memory-word-count (size)
  (ceiling size 32))

(defun aligned-memory-size (size)
  (* 32 (memory-word-count size)))

;;; Allocation ceiling.  In go-ethereum memory is gas-priced before it exists:
;;; the interpreter charges dynamicGas, memoryGasCost included, and resizes
;;; only after the charge succeeds (v1.17.6 core/vm/interpreter.go Run), so a
;;; region no gas can pay for is ErrOutOfGas / ErrGasUintOverflow, never an
;;; allocation.  Every handler here charges before it resizes too, which bounds
;;; a frame's memory by its gas (MEMORY-SIZE-PAYABLE-WITH-GAS).  A defect that
;;; allocates before charging (a zero-length KECCAK256 at a 2 GB offset, the
;;; pre-d7a28c6c shape) does not halt; it asks the host for the bytes.  A
;;; fixture harness binds *MEMORY-ALLOCATION-CEILING* to the gas-derived bound
;;; so such a defect is a typed refusal instead of a heap exhaustion, and
;;; *MEMORY-ALLOCATION-HEAP-BUDGET* so that memory a vector legitimately pays
;;; for across many frames (hundreds of nested calls holding a megabyte each)
;;; is a typed refusal too, rather than the end of the process.  Both are NIL,
;;; and cost one NIL check where a buffer is allocated, everywhere else.

(defvar *memory-allocation-ceiling* nil
  "NIL, or the most bytes one EVM memory backing vector or copied data buffer
may allocate.  Checked only where a buffer is allocated.")

(defvar *memory-allocation-heap-budget* nil
  "NIL, or the most bytes the Lisp heap may hold once an EVM buffer of at
least +MEMORY-ALLOCATION-HEAP-BUDGET-MIN-BYTES+ is allocated.")

(defconstant +memory-allocation-heap-budget-min-bytes+ (* 64 1024)
  "Smaller buffers skip the heap-budget check: they cannot move the heap by
much, and CALLDATALOAD alone allocates 32 bytes per instruction.")

(define-condition evm-memory-allocation-refused (storage-condition)
  ((requested :initarg :requested
              :reader evm-memory-allocation-refused-requested)
   (ceiling :initarg :ceiling
            :reader evm-memory-allocation-refused-ceiling)
   (reason :initarg :reason :initform :ceiling
           :reader evm-memory-allocation-refused-reason))
  (:report
   (lambda (condition stream)
     (format stream
             "EVM allocation of ~D bytes refused: ~:[the ceiling is~;the ~
              heap would pass its budget of~] ~D bytes"
             (evm-memory-allocation-refused-requested condition)
             (eq :heap-budget (evm-memory-allocation-refused-reason condition))
             (evm-memory-allocation-refused-ceiling condition))))
  (:documentation
   "An EVM buffer above *MEMORY-ALLOCATION-CEILING* (REASON :CEILING), or one
that would take the heap past *MEMORY-ALLOCATION-HEAP-BUDGET* (REASON
:HEAP-BUDGET), was requested.

A STORAGE-CONDITION, not an ERROR: no EVM-ERROR or ERROR handler may turn it
into an exceptional halt, a transaction failure, or an internal-error outcome
that reads like a result."))

(defun %check-memory-allocation (bytes ceiling budget)
  (when (and ceiling (> bytes ceiling))
    (error 'evm-memory-allocation-refused
           :requested bytes :ceiling ceiling :reason :ceiling))
  (when (and budget
             (>= bytes +memory-allocation-heap-budget-min-bytes+)
             (> (+ (sb-kernel:dynamic-usage) bytes) budget))
    ;; Usage counts garbage too; only what a full collection leaves decides.
    (sb-ext:gc :full t)
    (when (> (+ (sb-kernel:dynamic-usage) bytes) budget)
      (error 'evm-memory-allocation-refused
             :requested bytes :ceiling budget :reason :heap-budget))))

(declaim (inline check-memory-allocation))
(defun check-memory-allocation (bytes)
  (let ((ceiling *memory-allocation-ceiling*)
        (budget *memory-allocation-heap-budget*))
    (when (or ceiling budget)
      (%check-memory-allocation bytes ceiling budget))))

(defun memory-size-payable-with-gas (gas)
  "The most memory, in bytes (a whole number of words), one frame can pay for
with GAS: the largest W with 3W + floor(W^2 / 512) <= GAS, times 32.

go-ethereum v1.17.6 core/vm/gas_table.go memoryGasCost prices W words at
W * 3 + W^2 / 512, which is MEMORY-TOTAL-GAS."
  (if (< gas (memory-total-gas 1))
      0
      ;; W^2/512 + 3W = GAS  =>  W = sqrt(768^2 + 512 GAS) - 768, then step to
      ;; the exact integer boundary the floor makes.
      (let ((words (max 0 (- (isqrt (+ (* 768 768) (* 512 gas))) 768))))
        (loop while (> (memory-total-gas words) gas)
              do (decf words))
        (loop while (<= (memory-total-gas (1+ words)) gas)
              do (incf words))
        (* 32 words))))

(defun ensure-memory-size (memory size)
  (if (<= size (length memory))
      memory
      (let* ((logical-size (aligned-memory-size size))
             (displaced-to (array-displacement memory))
             (backing (or displaced-to memory))
             (capacity (array-total-size backing)))
        (if (>= capacity logical-size)
            (make-array logical-size
                        :element-type '(unsigned-byte 8)
                        :displaced-to backing)
            (let* ((new-capacity
                     (max logical-size
                          32
                          (* 2 (max capacity 32))))
                   (new-backing
                     (progn
                       (check-memory-allocation new-capacity)
                       (make-array new-capacity
                                   :element-type '(unsigned-byte 8)
                                   :initial-element 0))))
              (replace new-backing memory)
              (make-array logical-size
                          :element-type '(unsigned-byte 8)
                          :displaced-to new-backing))))))

(defun ensure-memory-region (memory offset size)
  "MEMORY grown to hold the SIZE bytes at OFFSET.

An empty region touches no memory at any offset.  go-ethereum sizes it at zero
(v1.17.6 core/vm/common.go calcMemSize64WithUint) and resizes only for a
positive size (core/vm/interpreter.go), so a zero-length LOG, KECCAK256,
CREATE or CREATE2 changes neither MSIZE nor the price of the next expansion,
and its offset may be any word."
  (if (zerop size)
      memory
      (ensure-memory-size memory (+ offset size))))

(defun memory-total-gas (word-count)
  (+ (* word-count +memory-gas+)
     (floor (* word-count word-count) +memory-quad-divisor+)))

(defun memory-expansion-gas (memory offset size)
  (if (zerop size)
      0
      (let* ((current-words (memory-word-count (length memory)))
             (new-words (memory-word-count (+ offset size))))
        (if (<= new-words current-words)
            0
            (- (memory-total-gas new-words)
               (memory-total-gas current-words))))))

(defun memory-regions-high-water (&rest regions)
  (loop for (offset size) in regions
        maximize (if (zerop size) 0 (+ offset size))))

(defun memory-regions-expansion-gas (memory &rest regions)
  (memory-expansion-gas memory 0
                        (apply #'memory-regions-high-water regions)))

(defun ensure-memory-regions (memory &rest regions)
  (ensure-memory-size memory (apply #'memory-regions-high-water regions)))

(defun memory-slice (memory offset size)
  (if (zerop size)
      (make-byte-vector 0)
      (let ((memory (ensure-memory-size memory (+ offset size))))
        (check-memory-allocation size)
        (subseq memory offset (+ offset size)))))

(defun copy-into-memory (memory memory-offset data)
  (let* ((data (ensure-byte-vector data))
         (size (length data)))
    (if (zerop size)
        memory
        (let ((memory (ensure-memory-size memory (+ memory-offset size))))
          (replace memory data :start1 memory-offset)
          memory))))

(defun copy-memory-region (memory destination source size)
  (if (zerop size)
      memory
      (let* ((memory (ensure-memory-size
                      memory
                      (max (+ destination size) (+ source size))))
             (data (subseq memory source (+ source size))))
        (replace memory data :start1 destination)
        memory)))

(defun padded-data-slice (data offset size)
  (check-memory-allocation size)
  (let* ((data (ensure-byte-vector data))
         (result (make-byte-vector size)))
    (when (< offset (length data))
      (let ((available (min size (- (length data) offset))))
        (replace result data :start1 0 :start2 offset :end2 (+ offset available))))
    result))

(defun call-output-data-slice (data size)
  (let* ((data (ensure-byte-vector data))
         (available (min size (length data))))
    (subseq data 0 available)))

(defun bounded-data-slice (data offset size label)
  (let ((data (ensure-byte-vector data)))
    (when (> (+ offset size) (length data))
      (fail "~A out of bounds" label))
    (subseq data offset (+ offset size))))

;;; MSTORE and MLOAD move one 32-byte big-endian word.  MEMORY is a view
;;; displaced onto a doubling backing vector (ENSURE-MEMORY-SIZE), so the
;;; word is read and written on that simple backing vector, and a word is
;;; split into or assembled from 32-bit pieces, which are fixnums, rather
;;; than one shifted bignum per byte.  A fixnum word (every offset, counter
;;; and small constant) never touches a bignum at all.

(declaim (inline %memory-backing-start))
(defun %memory-backing-start (memory offset)
  "The simple byte vector under MEMORY and the index of OFFSET in it, or NIL
when MEMORY is not the usual displaced byte view."
  (multiple-value-bind (backing base) (array-displacement memory)
    (let ((backing (or backing memory)))
      (when (and (typep backing 'byte-vector)
                 (typep offset '(and fixnum unsigned-byte)))
        (values backing (+ base offset))))))

(defun mstore (memory offset value)
  (let ((memory (ensure-memory-size memory (+ offset 32))))
    (multiple-value-bind (backing start)
        (%memory-backing-start memory offset)
      (cond
        ((null backing)
         (dotimes (i 32)
           (setf (aref memory (+ offset i))
                 (logand #xff (ash value (* -8 (- 31 i)))))))
        ((typep value '(and fixnum unsigned-byte))
         (let ((last (+ start 31)))
           (declare (type byte-vector backing) (type fixnum start last))
           (fill backing 0 :start start :end (+ start 24))
           (dotimes (i 8)
             (setf (aref backing (- last i))
                   (ldb (byte 8 (* 8 i)) value)))))
        (t
         (let ((last (+ start 31)))
           (declare (type byte-vector backing) (type fixnum start last))
           (dotimes (chunk-index 8)
             (let ((chunk (ldb (byte 32 (* 32 chunk-index)) value)))
               (declare (type (unsigned-byte 32) chunk))
               (dotimes (i 4)
                 (setf (aref backing (- last (* 4 chunk-index) i))
                       (ldb (byte 8 (* 8 i)) chunk)))))))))
    memory))

(defun mload (memory offset)
  (let ((memory (ensure-memory-size memory (+ offset 32))))
    (multiple-value-bind (backing start)
        (%memory-backing-start memory offset)
      (if (null backing)
          (loop for i below 32
                for value = (aref memory (+ offset i))
                  then (+ (ash value 8) (aref memory (+ offset i)))
                finally (return (word (or value 0))))
          (locally (declare (type byte-vector backing) (type fixnum start))
            (flet ((chunk (index)
                     ;; The INDEX-th 32-bit piece, most significant first.
                     (let ((at (+ start (* 4 index))))
                       (logior (ash (aref backing at) 24)
                               (ash (aref backing (+ at 1)) 16)
                               (ash (aref backing (+ at 2)) 8)
                               (aref backing (+ at 3))))))
              (if (and (loop for i from start below (+ start 24)
                             always (zerop (aref backing i)))
                       (< (aref backing (+ start 24)) 64))
                  ;; Below 2^62: the word is a fixnum.
                  (logior (ash (chunk 6) 32) (chunk 7))
                  (let ((value 0))
                    (dotimes (index 8 value)
                      (setf value (logior (ash value 32) (chunk index))))))))))))

(defun mstore8 (memory offset value)
  (let ((memory (ensure-memory-size memory (1+ offset))))
    (setf (aref memory offset) (logand value #xff))
    memory))
