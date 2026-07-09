(in-package #:ethereum-lisp.test)

(deftest transaction-fixture-vector-shape-validation
  (let ((valid-vector
          (list (cons "name" "shape-test")
                (cons "type" "legacy")
                (cons "chainId" 1)
                (cons "txbytes" "0x01")
                (cons "hash"
                      "0x0000000000000000000000000000000000000000000000000000000000000001")
                (cons "sender" "0x0000000000000000000000000000000000000001")
                (cons "result" nil))))
    (validate-transaction-fixture-vector-shape valid-vector))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" 42)
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "name must be a string" (princ-to-string condition)))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "missing-result")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001"))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-type")
           (cons "type" "unknown")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-type")
                   (cons "type" 42)
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "type must be a string" (princ-to-string condition)))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-chain-id")
           (cons "type" "legacy")
           (cons "chainId" -1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "both-raw-and-txbytes")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "raw" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "raw-only")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "raw" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "empty-txbytes")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-txbytes")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" 42)
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "txbytes must be a string" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "bad-txbytes-hex")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x0")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "txbytes must be hex bytes" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "prefixless-txbytes")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "txbytes must be canonical"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "uppercase-txbytes")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0XAB")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "txbytes must be canonical"
                  (princ-to-string condition)))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-hash")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash" "0x01")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "bad-hash-message")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash" "0x01")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "hash must be a 32-byte hex string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-hash")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash" 42)
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "hash must be a string" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "prefixless-hash")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "hash must be canonical" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "uppercase-hash")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0X00000000000000000000000000000000000000000000000000000000000000AB")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "hash must be canonical" (princ-to-string condition)))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-sender")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x01")
           (cons "result" nil))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "bad-sender-message")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x01")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "sender must be an address hex string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-sender")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" 42)
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "sender must be a string" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "prefixless-sender")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "sender must be canonical" (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "uppercase-sender")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0X00000000000000000000000000000000000000AB")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "sender must be canonical" (princ-to-string condition)))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "bad-contract-address")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "contractAddress" "0x01")
           (cons "result" nil))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "non-string-contract-address")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "contractAddress" 42)
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "contractAddress must be a string"
                  (princ-to-string condition)))))
  (is (handler-case
          (progn
            (validate-transaction-fixture-vector-shape
             (list (cons "name" "prefixless-contract-address")
                   (cons "type" "legacy")
                   (cons "chainId" 1)
                   (cons "txbytes" "0x01")
                   (cons "hash"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "sender" "0x0000000000000000000000000000000000000001")
                   (cons "contractAddress"
                         "0000000000000000000000000000000000000001")
                   (cons "result" nil)))
            nil)
        (error (condition)
          (search "contractAddress must be canonical"
                  (princ-to-string condition)))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "unknown-vector-field")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil)
           (cons "unexpectedVectorField" t))))
  (signals error
    (validate-transaction-fixture-vector-shape
     (list (cons "name" "duplicate-vector-field")
           (cons "name" "duplicate-vector-field-shadow")
           (cons "type" "legacy")
           (cons "chainId" 1)
           (cons "txbytes" "0x01")
           (cons "hash"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "sender" "0x0000000000000000000000000000000000000001")
           (cons "result" nil)))))

(deftest transaction-fixture-decoded-envelope-validation
  (let ((vector (list (cons "name" "decoded-shape-test")
                      (cons "type" "dynamic-fee")
                      (cons "chainId" 1))))
    (validate-transaction-fixture-decoded-envelope
     vector
     (make-dynamic-fee-transaction :chain-id 1))
    (signals error
      (validate-transaction-fixture-decoded-envelope
       vector
       (make-access-list-transaction :chain-id 1)))
    (signals error
      (validate-transaction-fixture-decoded-envelope
       vector
       (make-dynamic-fee-transaction :chain-id 2)))))

(deftest transaction-fixture-decoded-vector-validation
  (let ((vector (first (load-transaction-envelope-vectors
                       +transaction-envelope-fixture-path+)))
        (contract-vector
          (find "legacy-contract-creation"
                (load-transaction-envelope-vectors
                 +transaction-envelope-fixture-path+)
                :test #'string=
                :key (lambda (candidate)
                       (fixture-object-field candidate "name")))))
    (labels ((replace-field (field value)
               (cons (cons field value)
                     (remove field vector :key #'car :test #'string=)))
             (replace-contract-field (field value)
               (cons (cons field value)
                     (remove field
                             contract-vector
                             :key #'car
                             :test #'string=))))
      (validate-transaction-fixture-decoded-vector vector)
      (validate-transaction-fixture-decoded-vector contract-vector)
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-field
          "hash"
          "0x0000000000000000000000000000000000000000000000000000000000000000")))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-field "sender"
                        "0x0000000000000000000000000000000000000000")))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-field "contractAddress"
                        "0x0000000000000000000000000000000000000000")))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (remove "contractAddress"
                 contract-vector
                 :key #'car
                 :test #'string=)))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-contract-field
          "contractAddress"
          "0x0000000000000000000000000000000000000000")))
      (signals error
        (validate-transaction-fixture-decoded-vector
         (replace-field
          "signature"
          (list (cons "v" "0x25")
                (cons "yParity" "0x1")
                (cons "r"
                      "0x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276")
                (cons "s"
                      "0x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83")))))
      (let ((message
              (handler-case
                  (progn
                    (validate-transaction-fixture-decoded-vector
                     (replace-field
                      "result"
                      (list (cons "Frontier"
                                  (list (cons "intrinsicGas" "0x5209")))
                            (cons "Berlin"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "London"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "Paris"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "Shanghai"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "Cancun"
                                  (list (cons "intrinsicGas" "0x5208")))
                            (cons "Prague"
                                  (list (cons "intrinsicGas" "0x5208"))))))
                    nil)
                (error (condition)
                  (princ-to-string condition)))))
        (is message)
        (is (search "fork Frontier" message))
        (is (search "0x5209" message))
        (is (search "0x5208" message))))))

