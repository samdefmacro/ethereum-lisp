(in-package #:ethereum-lisp.test)

(deftest uint256-bounds
  (is (uint256-p 0))
  (is (uint256-p +uint256-max+))
  (is (not (uint256-p -1)))
  (is (not (uint256-p (expt 2 256)))))

(deftest address-roundtrip
  (let ((address (address-from-hex "0x000000000000000000000000000000000000dead")))
    (is (address-p address))
    (is (string= "0x000000000000000000000000000000000000dead"
                 (address-to-hex address)))))

(deftest hash32-roundtrip
  (let ((hash (hash32-from-hex
               "0x00000000000000000000000000000000000000000000000000000000000000f0")))
    (is (hash32-p hash))
    (is (string= "0x00000000000000000000000000000000000000000000000000000000000000f0"
                 (hash32-to-hex hash)))))

(deftest sized-types-reject-invalid-length
  (signals error (make-address #(1 2 3)))
  (signals error (make-hash32 #(1 2 3))))
