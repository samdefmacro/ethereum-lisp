(in-package #:ethereum-lisp.test)

(deftest hex-byte-roundtrip
  (is (string= "0x0001027fff80" (bytes-to-hex #(0 1 2 127 255 128))))
  (is (bytes= #(222 173 190 239) (hex-to-bytes "0xdeadbeef")))
  (is (bytes= #(222 173 190 239) (hex-to-bytes "DEADBEEF"))))

(deftest hex-quantities
  (is (string= "0x0" (quantity-to-hex 0)))
  (is (string= "0x400" (quantity-to-hex 1024)))
  (is (= 1024 (hex-to-quantity "0x400"))))
