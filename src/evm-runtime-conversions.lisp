(in-package #:ethereum-lisp.evm.internal)

(defun word-to-hash32 (value)
  (let ((out (make-byte-vector 32)))
    (dotimes (i 32 (make-hash32 out))
      (setf (aref out (- 31 i))
            (logand #xff (ash value (* -8 i)))))))

(defun word-to-address (value)
  (let ((out (make-byte-vector 20)))
    (dotimes (i 20 (make-address out))
      (setf (aref out (- 19 i))
            (logand #xff (ash value (* -8 i)))))))

(defun address-to-word (address)
  (bytes-to-integer (address-bytes address)))

(defun hash32-to-word (hash)
  (bytes-to-integer (hash32-bytes hash)))

(defun evm-context-difficulty-or-random-word (context)
  (if (evm-context-random-p context)
      (hash32-to-word (or (evm-context-prev-randao context) (zero-hash32)))
      (evm-context-difficulty context)))
