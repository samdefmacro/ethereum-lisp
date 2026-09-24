(in-package #:ethereum-lisp.evm.internal)

(defun memory-word-count (size)
  (ceiling size 32))

(defun aligned-memory-size (size)
  (* 32 (memory-word-count size)))

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
                     (make-array new-capacity
                                 :element-type '(unsigned-byte 8)
                                 :initial-element 0)))
              (replace new-backing memory)
              (make-array logical-size
                          :element-type '(unsigned-byte 8)
                          :displaced-to new-backing))))))

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
