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

(deftest address-owns-and-protects-its-bytes
  (let* ((source (make-byte-vector 20))
         (address (make-address source)))
    (setf (aref source 19) #xaa)
    (is (= 0 (aref (address-bytes address) 19)))
    (let ((view (address-bytes address)))
      (setf (aref view 19) #xbb)
      (is (= 0 (aref (address-bytes address) 19))))))

(deftest hash32-owns-and-protects-its-bytes
  (let* ((source (make-byte-vector 32))
         (hash (make-hash32 source)))
    (setf (aref source 31) #xaa)
    (is (= 0 (aref (hash32-bytes hash) 31)))
    (let ((view (hash32-bytes hash)))
      (setf (aref view 31) #xbb)
      (is (= 0 (aref (hash32-bytes hash) 31))))))
