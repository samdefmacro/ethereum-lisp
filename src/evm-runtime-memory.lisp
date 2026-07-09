(in-package #:ethereum-lisp.evm)

(defun memory-word-count (size)
  (ceiling size 32))

(defun aligned-memory-size (size)
  (* 32 (memory-word-count size)))

(defun ensure-memory-size (memory size)
  (if (<= size (length memory))
      memory
      (let ((expanded (make-byte-vector (aligned-memory-size size))))
        (replace expanded memory)
        expanded)))

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

(defun mstore (memory offset value)
  (let ((memory (ensure-memory-size memory (+ offset 32))))
    (dotimes (i 32 memory)
      (setf (aref memory (+ offset i))
            (logand #xff (ash value (* -8 (- 31 i))))))))

(defun mload (memory offset)
  (let ((memory (ensure-memory-size memory (+ offset 32))))
    (loop for i below 32
          for value = (aref memory (+ offset i))
            then (+ (ash value 8) (aref memory (+ offset i)))
          finally (return (word (or value 0))))))

(defun mstore8 (memory offset value)
  (let ((memory (ensure-memory-size memory (1+ offset))))
    (setf (aref memory offset) (logand value #xff))
    memory))
