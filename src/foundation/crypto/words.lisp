(in-package #:ethereum-lisp.crypto)

(defun u32 (value)
  (logand value +uint32-mask+))

(defun u64 (value)
  (logand value +uint64-mask+))

(defun rotl64 (value count)
  (let ((count (mod count 64))
        (value (u64 value)))
    (if (zerop count)
        value
        (u64 (logior (ash value count)
                     (ash value (- count 64)))))))

(defun load-little-endian-u64 (bytes start)
  (loop for i below 8
        sum (ash (aref bytes (+ start i)) (* 8 i))))

(defun store-little-endian-u64 (value bytes start)
  (loop for i below 8
        do (setf (aref bytes (+ start i))
                 (logand #xff (ash value (* -8 i)))))
  bytes)

(defun rotr32 (value count)
  (let ((count (mod count 32))
        (value (u32 value)))
    (if (zerop count)
        value
        (u32 (logior (ash value (- count))
                     (ash value (- 32 count)))))))

(defun rotl32 (value count)
  (let ((count (mod count 32))
        (value (u32 value)))
    (if (zerop count)
        value
        (u32 (logior (ash value count)
                     (ash value (- count 32)))))))

(defun load-big-endian-u32 (bytes start)
  (loop for i below 4
        sum (ash (aref bytes (+ start i)) (* 8 (- 3 i)))))

(defun store-big-endian-u32 (value bytes start)
  (loop for i below 4
        do (setf (aref bytes (+ start i))
                 (logand #xff (ash value (* -8 (- 3 i))))))
  bytes)

(defun load-little-endian-u32 (bytes start)
  (loop for i below 4
        sum (ash (aref bytes (+ start i)) (* 8 i))))

(defun store-little-endian-u32 (value bytes start)
  (loop for i below 4
        do (setf (aref bytes (+ start i))
                 (logand #xff (ash value (* -8 i)))))
  bytes)
