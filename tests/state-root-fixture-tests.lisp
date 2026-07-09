(in-package #:ethereum-lisp.test)

(deftest state-root-fixture-shape-validation
  (let ((valid-case
          (list
           (cons "name" "valid-shape")
           (cons "tags" (list "account-root" "storage-root" "code-root"))
           (cons "operations"
                 (list
                  (list (cons "op" "setAccount")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "nonce" 1)
                        (cons "balance" 2))
                  (list (cons "op" "setStorage")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "slot"
                              "0x0000000000000000000000000000000000000000000000000000000000000001")
                        (cons "value" 3))
                  (list (cons "op" "setCode")
                        (cons "address"
                              "0x0000000000000000000000000000000000000001")
                        (cons "code" "0x6001"))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
    (validate-state-root-fixture-case-shape valid-case))
  (signals error
    (validate-state-root-fixture-metadata
     (list (cons "format" +state-root-fixture-format+)
           (cons "source" "seed")
           (cons "source" "duplicate seed")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-root-fixture-metadata
     (list (cons "format" +state-root-fixture-format+)
           (cons "source" "seed")
           (cons "unexpected" t)
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-root-fixture-metadata
     (list (cons "format" +state-root-fixture-format+)
           (cons "source" "seed")
           (cons 42 t)
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-root-fixture-metadata
     (list (cons "format" +state-root-fixture-format+)
           (cons "source" "")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-root-fixture-metadata
     (list (cons "format" +state-root-fixture-format+)
           (cons "source" 42)
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" 42)
           (cons "tags" (list "account-root"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "non-string-expected-root")
           (cons "tags" (list "account-root"))
           (cons "operations" nil)
           (cons "expectedRoot" 42))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "prefixless-expected-root")
           (cons "tags" (list "account-root"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "uppercase-expected-root")
           (cons "tags" (list "account-root"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0X56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "unknown-case-field")
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "root" "unexpected"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "non-string-case-field")
           (cons 42 t)
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-case-field")
           (cons "name" "duplicate-case-field-shadow")
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "prefixless-operation-address")
           (cons "tags" (list "account-root"))
           (cons "operations"
                 (list (list (cons "op" "setAccount")
                             (cons "address"
                                   "00000000000000000000000000000000000000aa")
                             (cons "balance" 1))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "uppercase-storage-slot")
           (cons "tags" (list "storage-root"))
           (cons "operations"
                 (list (list (cons "op" "setStorage")
                             (cons "address"
                                   "0x00000000000000000000000000000000000000aa")
                             (cons "slot"
                                   "0X00000000000000000000000000000000000000000000000000000000000000AA")
                             (cons "value" 1))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "prefixless-code")
           (cons "tags" (list "code-root"))
           (cons "operations"
                 (list (list (cons "op" "setCode")
                             (cons "address"
                                   "0x00000000000000000000000000000000000000aa")
                             (cons "code" "6001"))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "unknown-operation-field")
           (cons "tags" (list "account-root"))
           (cons "operations"
                 (list (list (cons "op" "setAccount")
                             (cons "address"
                                   "0x00000000000000000000000000000000000000aa")
                             (cons "balance" 1)
                             (cons "storage" nil))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "non-string-operation-field")
           (cons "tags" (list "account-root"))
           (cons "operations"
                 (list (list (cons "op" "setAccount")
                             (cons "address"
                                   "0x00000000000000000000000000000000000000AA")
                             (cons "balance" 1)
                             (cons 42 t))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-operation-field")
           (cons "tags" (list "account-root"))
           (cons "operations"
                 (list (list (cons "op" "setAccount")
                             (cons "address"
                                   "0x00000000000000000000000000000000000000aa")
                             (cons "balance" 1)
                             (cons "balance" 2))))
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "bad-storage-root-shape")
           (cons "tags" (list "storage-root-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedStorageRoots"
                 (list (list (cons "address"
                                   "0x00000000000000000000000000000000000000AA")
                             (cons "root" "0x01")))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "non-string-storage-root-field")
           (cons "tags" (list "storage-root-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedStorageRoots"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root"
                                   "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
                             (cons 42 t)))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-storage-root-field")
           (cons "tags" (list "storage-root-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedStorageRoots"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root"
                                   "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
                             (cons "root"
                                   "0x23cc0c47d1238030e9c1ec18013dcb17024d3d42729567adbb6406a64d3007f3")))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-storage-root-address")
           (cons "tags" (list "storage-root-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedStorageRoots"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root"
                                   "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))
                       (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root"
                                   "0x23cc0c47d1238030e9c1ec18013dcb17024d3d42729567adbb6406a64d3007f3")))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-storage-root-address-alias")
           (cons "tags" (list "storage-root-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedStorageRoots"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root"
                                   "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))
                       (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "root"
                                   "0x23cc0c47d1238030e9c1ec18013dcb17024d3d42729567adbb6406a64d3007f3")))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "unknown-account-field")
           (cons "tags" (list "account-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedAccounts"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 1)
                             (cons "storage" nil)))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "non-string-account-field")
           (cons "tags" (list "account-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedAccounts"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 1)
                             (cons 42 t)))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-account-field")
           (cons "tags" (list "account-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedAccounts"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 1)
                             (cons "balance" 2)))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-account-address")
           (cons "tags" (list "account-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedAccounts"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 1))
                       (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "balance" 2)))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-account-address-alias")
           (cons "tags" (list "account-projection"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedAccounts"
                 (list (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "nonce" 0)
                             (cons "balance" 1))
                       (list (cons "address"
                                   "0x0000000000000000000000000000000000000001")
                             (cons "nonce" 0)
                             (cons "balance" 2)))))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "unknown-tag")
           (cons "tags" (list "unknown"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-case-shape
     (list (cons "name" "duplicate-tag")
           (cons "tags" (list "account-root" "account-root"))
           (cons "operations" nil)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (validate-state-root-fixture-cases
     (list
      (list (cons "name" "duplicate")
            (cons "tags" +state-root-fixture-required-tags+)
            (cons "operations" nil)
            (cons "expectedRoot"
                  "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))
      (list (cons "name" "duplicate")
            (cons "tags" +state-root-fixture-required-tags+)
            (cons "operations" nil)
            (cons "expectedRoot"
                  "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")))))
  (signals error
    (validate-state-root-fixture-cases
     (list
      (list (cons "name" "missing-required-coverage")
            (cons "tags" (list "empty-state-root"))
            (cons "operations" nil)
            (cons "expectedRoot"
                  "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")))))
  (let ((+state-root-fixture-required-case-names+ '("present" "missing")))
    (signals error
      (validate-state-root-fixture-required-case-names
       (list (list (cons "name" "present"))))))
  (let ((+state-root-fixture-required-case-names+ '("present" "present")))
    (signals error
      (validate-state-root-fixture-required-case-names
       (list (list (cons "name" "present"))))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setAccount")
           (cons "address" "0x01")
           (cons "balance" 1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" 42)
           (cons "address" "0x0000000000000000000000000000000000000001"))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setAccount")
           (cons "address" 42)
           (cons "balance" 1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setStorage")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "slot" "0x01")
           (cons "value" 1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setStorage")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "slot"
                 "0x0000000000000000000000000000000000000000000000000000000000000001"))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setAccount")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "balance" -1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "clearAccount")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "balance" 0))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "setCode")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "code" "0x0"))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "transferValue")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "amount" 1))))
  (signals error
    (validate-state-root-fixture-operation-shape
     (list (cons "op" "transferValue")
           (cons "address" "0x0000000000000000000000000000000000000001")
           (cons "recipient" "0x0000000000000000000000000000000000000002")
           (cons "amount" -1)))))

(deftest state-root-fixture-vectors
  (let* ((fixture (load-handwritten-fixture-file +state-root-fixture-path+))
         (cases (fixture-object-field fixture "cases")))
    (validate-state-root-fixture-metadata fixture)
    (validate-state-root-fixture-cases cases)
    (validate-state-root-fixture-required-case-names cases)
    (dolist (case cases)
      (let ((state (run-state-root-fixture-case case)))
        (is (string= (fixture-object-field case "expectedRoot")
                     (state-db-root-hex state)))
        (assert-state-root-fixture-final-operation-state state case)
        (assert-state-root-fixture-storage-roots state case)
        (assert-state-root-fixture-storage-tries state case)
        (assert-state-root-fixture-accounts state case)
        (assert-state-root-fixture-account-ranges state case)
        (assert-state-root-fixture-storage-ranges state case)
        (assert-state-root-fixture-state-trie state case)))))

