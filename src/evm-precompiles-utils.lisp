(in-package #:ethereum-lisp.evm.internal)

(defun integer-to-fixed-bytes (value size)
  (let* ((minimal (integer-to-minimal-bytes value))
         (result (make-byte-vector size))
         (copy-size (min size (length minimal))))
    (replace result
             minimal
             :start1 (- size copy-size)
             :start2 (- (length minimal) copy-size))
    result))

(defun u64 (value)
  (logand value +uint64-mask+))

(defun rotr64 (value count)
  (let ((count (mod count 64))
        (value (u64 value)))
    (if (zerop count)
        value
        (u64 (logior (ash value (- count))
                     (ash value (- 64 count)))))))

(defun load-little-endian-u64 (bytes start)
  (loop for i below 8
        sum (ash (aref bytes (+ start i)) (* 8 i))))

(defun store-little-endian-u64 (value bytes start)
  (loop for i below 8
        do (setf (aref bytes (+ start i))
                 (logand #xff (ash value (* -8 i)))))
  bytes)

(defun load-big-endian-u32 (bytes start)
  (loop for i below 4
        sum (ash (aref bytes (+ start i)) (* 8 (- 3 i)))))
