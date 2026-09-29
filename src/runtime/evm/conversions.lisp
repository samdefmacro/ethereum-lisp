(in-package #:ethereum-lisp.evm.internal)

(defun %word-into-bytes (value out)
  "Write the low (LENGTH OUT) bytes of VALUE, a word, big-endian into OUT (a
fresh, zeroed vector whose length is a multiple of four) and return OUT.

A fixnum needs its low eight bytes only; a wider word is taken 32 bits at a
time, which LDB reads out of a bignum without consing, instead of shifting a
bignum copy per byte (every SLOAD and SSTORE key and LOG topic)."
  (declare (type byte-vector out))
  (let ((last (1- (length out))))
    (if (typep value 'small-word)
        (loop for i from 0 below (min 8 (length out))
              do (setf (aref out (- last i)) (ldb (byte 8 (* 8 i)) value)))
        (loop for chunk-index from 0 below (floor (length out) 4)
              do (let ((chunk (ldb (byte 32 (* 32 chunk-index)) value)))
                   (declare (type (unsigned-byte 32) chunk))
                   (dotimes (i 4)
                     (setf (aref out (- last (* 4 chunk-index) i))
                           (ldb (byte 8 (* 8 i)) chunk))))))
    out))

(defun word-to-hash32 (value)
  (make-hash32 (%word-into-bytes value (make-byte-vector 32))))

(defun word-to-address (value)
  (make-address (%word-into-bytes value (make-byte-vector 20))))

(defun address-to-word (address)
  (bytes-to-integer (address-bytes address)))

(defun hash32-to-word (hash)
  (bytes-to-integer (hash32-bytes hash)))

(defun evm-context-difficulty-or-random-word (context)
  (if (evm-context-random-p context)
      (hash32-to-word (or (evm-context-prev-randao context) (zero-hash32)))
      (evm-context-difficulty context)))
