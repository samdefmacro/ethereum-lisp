(in-package #:ethereum-lisp.test)

(deftest bytes-roundtrip-integers
  (dolist (value '(0 1 15 127 128 255 256 1024 65535 65536
                   115792089237316195423570985008687907853269984665640564039457584007913129639935))
    (is (= value (bytes-to-integer (integer-to-minimal-bytes value))))))

(deftest bytes-concat-and-compare
  (is (bytes= #(1 2 3 4) (concat-bytes #(1 2) #(3 4))))
  (is (not (bytes= #(1 2 3) #(1 2 4)))))
