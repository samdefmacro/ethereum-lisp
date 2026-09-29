(in-package #:ethereum-lisp.test)

(deftest bytes-roundtrip-integers
  (dolist (value '(0 1 15 127 128 255 256 1024 65535 65536
                   115792089237316195423570985008687907853269984665640564039457584007913129639935))
    (is (= value (bytes-to-integer (integer-to-minimal-bytes value))))))

(deftest bytes-concat-and-compare
  (is (bytes= #(1 2 3 4) (concat-bytes #(1 2) #(3 4))))
  (is (not (bytes= #(1 2 3) #(1 2 4)))))

(deftest bytes-to-integer-matches-a-byte-by-byte-read
  ;; BYTES-TO-INTEGER reads up to eight bytes one at a time and longer inputs
  ;; seven at a time; every length 0-40, with random, all-0xFF and
  ;; leading-zero contents and list or vector input, must equal the plain
  ;; big-endian read.
  (let ((random-state (sb-ext:seed-random-state 256)))
    (flet ((reference (bytes)
             (let ((value 0))
               (map nil (lambda (byte) (setf value (+ (* value 256) byte)))
                    bytes)
               value)))
      (loop for length from 0 to 40
            do (dolist (bytes (list (let ((v (make-byte-vector length)))
                                      (dotimes (i length v)
                                        (setf (aref v i)
                                              (random 256 random-state))))
                                    (make-byte-vector length
                                                      :initial-element #xff)
                                    (let ((v (make-byte-vector length)))
                                      (when (plusp length)
                                        (setf (aref v (1- length)) 1))
                                      v)))
                 (is (= (reference bytes) (bytes-to-integer bytes)))
                 (is (= (reference bytes)
                        (bytes-to-integer (coerce bytes 'list))))
                 (is (= (reference bytes)
                        (bytes-to-integer (coerce bytes 'simple-vector)))))))))
