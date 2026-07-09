(in-package #:ethereum-lisp.test)

(deftest state-proof-fixture-shape-validation
  (let ((valid-case
          (list
           (cons "name" "valid-proof-shape")
           (cons "tags" +state-proof-fixture-required-tags+)
           (cons "operations"
                 (list
                  (list (cons "op" "setAccount")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "balance" 1))))
           (cons "request"
                 (list
                  (cons "address"
                        "0x0000000000000000000000000000000000000001")
                  (cons "storageKeys"
                        (list "0x1"))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedProof"
                 (list
                  (cons "address"
                        "0x0000000000000000000000000000000000000001")
                  (cons "accountProof" nil)
                  (cons "balance" "0x0")
                  (cons "codeHash"
                        "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
                  (cons "nonce" "0x0")
                  (cons "storageHash"
                        "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
                  (cons "storageProof"
                        (list
                         (list
                          (cons "key"
                                "0x0000000000000000000000000000000000000000000000000000000000000001")
                          (cons "value" "0x0")
                          (cons "proof" nil)))))))))
    (labels ((replace-field (object field value)
               (cons (cons field value)
                     (remove field object :key #'car :test #'string=))))
      (validate-state-proof-fixture-case-shape valid-case)
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof
                 (replace-field
                  proof
                  "address"
                  "0x0000000000000000000000000000000000000002")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof
                 (replace-field
                  proof
                  "address"
                  "0000000000000000000000000000000000000001")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "address" 42)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (validate-state-proof-fixture-case-shape
         (replace-field valid-case "name" 42)))
      (signals error
        (validate-state-proof-fixture-case-shape
         (replace-field valid-case "expectedRoot" 42)))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "storageProof" nil)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "accountProof" (list "0x8101"))))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "accountProof" (list "0X80"))))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "balance" "0x1")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "balance" "0x00")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "balance" "0X0")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "balance" 42)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof
                 (replace-field
                  proof
                  "codeHash"
                  "0XC5D2460186F7233C927E7DB2DCC703C0E500B653CA82273B7BFAD8045D85A470")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof (replace-field proof "codeHash" 42)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof
                 (replace-field
                  proof
                  "storageHash"
                  "0x2e7827dc2c61c322f13f77e6f25dd18844ccc48426dde70301d2d57d138fced8")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-proof
                 (replace-field
                  proof
                  "storageHash"
                  "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((request (fixture-required-field valid-case "request"))
               (bad-request (replace-field request "address" 42)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "request" bad-request))))
      (signals error
        (let* ((request (fixture-required-field valid-case "request"))
               (bad-request
                 (replace-field
                  request
                  "storageKeys"
                  (list
                   "0x0000000000000000000000000000000000000000000000000000000000000001"
                   "0X0000000000000000000000000000000000000000000000000000000000000001"))))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "request" bad-request))))
      (signals error
        (let* ((request (fixture-required-field valid-case "request"))
               (bad-request
                 (replace-field
                  request
                  "storageKeys"
                  (list
                   "0x100000000000000000000000000000000000000000000000000000000000000000"))))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "request" bad-request))))
      (signals error
        (let* ((request (fixture-required-field valid-case "request"))
               (bad-request (replace-field request "storageKeys" (list 42))))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "request" bad-request))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-storage-proof
                 (list
                  (list
                   (cons "key"
                         "0x0000000000000000000000000000000000000000000000000000000000000002")
                   (cons "value" "0x0")
                   (cons "proof" nil))))
               (bad-proof
                 (replace-field proof "storageProof" bad-storage-proof)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-storage-proof
                 (list
                  (list
                   (cons "key"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "value" "0x0")
                   (cons "proof" nil))
                  (list
                   (cons "key"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "value" "0x0")
                   (cons "proof" nil))))
               (bad-proof
                 (replace-field proof "storageProof" bad-storage-proof)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-storage-proof
                 (list
                  (list
                   (cons "key" 42)
                   (cons "value" "0x0")
                   (cons "proof" nil))))
               (bad-proof
                 (replace-field proof "storageProof" bad-storage-proof)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-storage-proof
                 (list
                  (list
                   (cons "key"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "value" 42)
                   (cons "proof" nil))))
               (bad-proof
                 (replace-field proof "storageProof" bad-storage-proof)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-storage-proof
                 (list
                  (list
                   (cons "key"
                         "0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "value" "0x0")
                   (cons "proof" nil))))
               (bad-proof
                 (replace-field proof "storageProof" bad-storage-proof)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))
      (signals error
        (let* ((proof (fixture-required-field valid-case "expectedProof"))
               (bad-storage-proof
                 (list
                  (list
                   (cons "key"
                         "0x0000000000000000000000000000000000000000000000000000000000000001")
                   (cons "value" "0x00")
                   (cons "proof" nil))))
               (bad-proof
                 (replace-field proof "storageProof" bad-storage-proof)))
          (validate-state-proof-fixture-case-shape
           (replace-field valid-case "expectedProof" bad-proof))))))
  (signals error
    (validate-state-proof-fixture-storage-proof-shape
     (list (cons "key"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "value" "0x0")
           (cons "proof" (list "0x8101")))))
  (signals error
    (validate-state-proof-fixture-storage-proof-shape
     (list (cons "key"
                 "0x0000000000000000000000000000000000000000000000000000000000000001")
           (cons "value" "0x1")
           (cons "proof" nil))))
  (signals error
    (validate-state-proof-fixture-metadata
     (list (cons "format" +state-proof-fixture-format+)
           (cons "source" "seed")
           (cons "source" "duplicate seed")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-proof-fixture-metadata
     (list (cons "format" +state-proof-fixture-format+)
           (cons "source" 42)
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-proof-fixture-case-shape
     (list (cons "name" "unknown-proof-field")
           (cons "tags" (list "geth-shaped-result"))
           (cons "operations" nil)
           (cons "request"
                 (list
                  (cons "address"
                        "0x0000000000000000000000000000000000000001")
                  (cons "storageKeys" nil)))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedProof"
                 (list
                  (cons "address"
                        "0x0000000000000000000000000000000000000001")
                  (cons "accountProof" nil)
                  (cons "balance" "0x0")
                  (cons "codeHash"
                        "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
                  (cons "nonce" "0x0")
                  (cons "storageHash"
                        "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
                  (cons "storageProof" nil)
                  (cons "unexpected" t)))))))
  (let ((+state-proof-fixture-required-case-names+
          '("present" "missing")))
    (signals error
      (validate-state-proof-fixture-required-case-names
       (list (list (cons "name" "present"))))))
  (let ((+state-proof-fixture-required-case-names+
          '("present" "present")))
    (signals error
      (validate-state-proof-fixture-required-case-names
       (list (list (cons "name" "present"))))))

(deftest state-proof-fixture-vectors
  (let* ((fixture (load-handwritten-fixture-file +state-proof-fixture-path+))
         (cases (fixture-object-field fixture "cases")))
    (validate-state-proof-fixture-metadata fixture)
    (validate-state-proof-fixture-cases cases)
    (validate-state-proof-fixture-required-case-names cases)
    (dolist (case cases)
      (let* ((state (run-state-root-fixture-case case))
             (expected-root
               (hash32-from-hex
                (fixture-object-field case "expectedRoot")))
             (expected-proof-object
               (fixture-object-field case "expectedProof"))
             (decoded-expected-proof
               (state-proof-result-from-rpc-object expected-proof-object))
             (proof
               (run-state-proof-fixture-request
                state
                (fixture-object-field case "request"))))
        (is (string= (fixture-object-field case "expectedRoot")
                     (state-db-root-hex state)))
        (is (state-db-verify-proof expected-root decoded-expected-proof))
        (is (equal expected-proof-object
                   (state-proof-result-rpc-object decoded-expected-proof)))
        (is (state-db-verify-proof (state-db-root state) proof))
        (is (equal (fixture-object-field case "expectedProof")
                   (state-proof-result-rpc-object proof)))))))

(deftest state-proof-reference-fixture-vectors
  (let* ((fixture
           (load-handwritten-fixture-file
            +state-proof-reference-fixture-path+))
         (cases (fixture-object-field fixture "cases")))
    (validate-state-proof-reference-fixture-metadata fixture)
    (unless (and (listp cases) cases)
      (error "State proof reference fixture cases must be a non-empty array"))
    (dolist (case cases)
      (validate-state-proof-reference-fixture-case-shape case)
      (let* ((expected-root
               (hash32-from-hex
                (fixture-required-field case "expectedRoot")))
             (decoded-proof
               (state-proof-result-from-rpc-object
                (fixture-required-field case "expectedProof"))))
        (is (state-db-verify-proof expected-root decoded-proof))))))
