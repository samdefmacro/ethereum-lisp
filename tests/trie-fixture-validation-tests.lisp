(in-package #:ethereum-lisp.test)

(deftest trie-fixture-shape-validation-rejects-ambiguous-operations
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "missing-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "valueAscii" "value")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "ambiguous-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" "0x00")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "put-without-value")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" 42)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-hex-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" 42)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "odd-hex-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" "0x0")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "prefixless-hex-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" "00")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "uppercase-hex-key")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyHex" "0X00")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-operation-value")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" 42)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "missing-entry-with-value")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog"))))
           (cons "expectedMissing"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-expected-value")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" 42))))))))

(deftest trie-fixture-metadata-validation-rejects-wrapper-drift
  (signals error
    (validate-trie-fixture-metadata
     (list (cons "format" +trie-vector-fixture-format+)
           (cons "source" "seed")
           (cons "source" "duplicate seed")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-trie-fixture-metadata
     (list (cons "format" +trie-vector-fixture-format+)
           (cons "source" "seed")
           (cons "unexpected" t)
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-trie-fixture-metadata
     (list (cons "format" +trie-vector-fixture-format+)
           (cons "source" "seed")
           (cons 42 t)
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed"))))))
  (signals error
    (validate-trie-fixture-metadata
     (list (cons "format" +trie-vector-fixture-format+)
           (cons "source" "")
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                      (cons "status" "seed"))))))
  (signals error
    (validate-trie-fixture-metadata
     (list (cons "format" +trie-vector-fixture-format+)
           (cons "source" 42)
           (cons "executionSpecTests"
                 (list (cons "release" +phase-a-eest-release+)
                       (cons "tagTarget" +phase-a-eest-tag-target+)
                       (cons "archive" +phase-a-eest-archive+)
                       (cons "status" "seed")))))))

(deftest trie-fixture-shape-validation-rejects-malformed-expected-fields
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-root")
           (cons "expectedRoot" "0x1234")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" 42)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-root")
           (cons "expectedRoot" 42)
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "prefixless-root")
           (cons "expectedRoot"
                 "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "uppercase-root")
           (cons "expectedRoot"
                 "0X56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-shape")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "short")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-shape")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" 42)
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-root-value")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "expectedRootValueAscii" 42)
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-secure")
           (cons "secure" "yes")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "child-reference-on-leaf")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "expectedChildReference" "embedded")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-child-reference")
           (cons "expectedRoot"
                 "0x1da465b71da985f1e07e3ed8dcd9e678546164ef2b17fb5c46c678fd91429de3")
           (cons "expectedShape" "extension")
           (cons "expectedChildReference" 42)
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "do")
                             (cons "valueAscii" "v")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-child-index")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildren" (list 0 16))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-child-reference-index")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildReferences"
                 (list (cons 1 "embedded")))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "malformed-child-reference-index")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildReferences"
                 (list (cons "1x" "embedded")))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-child-reference-kind")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildReferences"
                 (list (cons "1" 42)))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "child-shape-on-leaf")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "expectedRootChildShapes"
                 (list (cons "1" "extension")))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-child-shape")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildShapes"
                 (list (cons "1" 42)))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-child-shape")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildShapes"
                 (list (cons "1" "empty")))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x00")
                             (cons "valueAscii" "left")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "bad-path-nibble")
           (cons "expectedRoot"
                 "0x1da465b71da985f1e07e3ed8dcd9e678546164ef2b17fb5c46c678fd91429de3")
           (cons "expectedShape" "extension")
           (cons "expectedRootPathNibbles" (list 6 16))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "do")
                             (cons "valueAscii" "v")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-child-reference")
           (cons "expectedRoot"
                 "0x83829cd5772fb13b44be68a75883e4b11b08fe037af8999e7848cfcbd022b8b5")
           (cons "expectedShape" "branch")
           (cons "expectedRootChildReferences"
                 (list (cons "1" "embedded")
                       (cons "01" "hashed")))
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyHex" "0x10")
                             (cons "valueAscii" "left"))))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-expected-get-key")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))
                       (list (cons "keyHex" "0x646f67")
                             (cons "valueAscii" "hound")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "conflicting-expected-lookup-key")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedMissing"
                 (list (list (cons "keyHex" "0x646f67"))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "entry-pair-without-value")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedEntryPairs"
                 (list (list (cons "keyAscii" "dog"))))))))

(deftest trie-fixture-shape-validation-rejects-unknown-fields
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "unknown-case-field")
           (cons "unexpected" t)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-case-field")
           (cons 42 t)
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-case-field")
           (cons "name" "duplicate-case-field-shadow")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "unknown-operation-field")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")
                             (cons "valueHex" "0x01")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-operation-field")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")
                             (cons 42 t)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-operation-field")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog")
                             (cons "keyAscii" "cat")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "unknown-get-field")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")
                             (cons "root" t)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-string-get-field")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")
                             (cons 42 t)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "duplicate-get-field")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedGets"
                 (list (list (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy")
                             (cons "valueAscii" "shadow")))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "unknown-missing-field")
           (cons "expectedRoot"
                 "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
           (cons "expectedShape" "empty")
           (cons "operations"
                 (list (list (cons "op" "delete")
                             (cons "keyAscii" "dog"))))
           (cons "expectedMissing"
                 (list (list (cons "keyAscii" "dog")
                             (cons "proof" nil)))))))
  (signals error
    (validate-trie-fixture-case-shape
     (list (cons "name" "non-boolean-exact-proof")
           (cons "expectedRoot"
                 "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "expectedShape" "leaf")
           (cons "operations"
                 (list (list (cons "op" "put")
                             (cons "keyAscii" "dog")
                             (cons "valueAscii" "puppy"))))
           (cons "expectedProofPrefixes"
                 (list (list (cons "keyAscii" "dog")
                             (cons "exactLength" "yes")
                             (cons "nodeRlps"
                                   (list "0xc88320646f67857075707079")))))))))

(deftest trie-fixture-tag-validation-rejects-duplicates
  (signals error
    (validate-trie-fixture-case-tags
     (list (cons "name" "duplicate-tag")
           (cons "tags" (list "leaf-root" "leaf-root")))
     (make-hash-table :test 'equal))))

(deftest trie-fixture-coverage-validation-requires-secure-root-shapes
  (let* ((fixture (parse-json
                   (fixture-file-string +trie-vector-fixture-path+)))
         (cases (fixture-object-field fixture "cases")))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "secure-branch-root"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "secure-extension-root"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "secure-single-leaf"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "secure-delete-last-entry-empty-root"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-secure-account-step-3"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-required-case-names
       (remove-if
        (lambda (case)
          (string= "root-branch-mixed-child-references"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-one-element-proof"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-large-value-branch"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-general-range-iteration"
                   (fixture-object-field case "name")))
        cases)))
    (signals error
      (validate-trie-fixture-case-coverage
       (remove-if
        (lambda (case)
          (string= "geth-empty-value-sequence"
                   (fixture-object-field case "name")))
        cases)))
    (let ((+trie-fixture-required-case-names+
            '("single-leaf" "single-leaf")))
      (signals error
        (validate-trie-fixture-required-case-names cases)))
    (validate-trie-reference-case-requirements
     cases
     +trie-fixture-reference-case-requirements+
     "Seed trie fixture")
    (signals error
      (validate-trie-reference-case-requirements
       cases
       '(("missing-geth-derived-case" . :plain))
       "Seed trie fixture"))
    (signals error
      (validate-trie-reference-case-requirements
       cases
       '(("geth-secure-account-step-3" . :plain))
       "Seed trie fixture"))
    (signals error
      (validate-trie-reference-case-requirements
       cases
       '(("geth-long-leaf-value" . :plain)
         ("geth-long-leaf-value" . :plain))
       "Seed trie fixture"))
    (validate-trie-fixture-entry-pair-reference-cases
     cases
     +trie-fixture-entry-pair-reference-case-names+
     "Seed trie fixture")
    (signals error
      (validate-trie-fixture-entry-pair-reference-cases
       (mapcar (lambda (case)
                 (if (string= "geth-secure-account-step-1"
                              (fixture-object-field case "name"))
                     (remove "expectedEntryPairs"
                             case
                             :key #'car
                             :test #'string=)
                     case))
               cases)
       '("geth-secure-account-step-1")
       "Seed trie fixture"))
    (signals error
      (validate-trie-fixture-entry-pair-reference-cases
       cases
       '("geth-tiny-account-step-1" "geth-tiny-account-step-1")
       "Seed trie fixture"))
    (validate-trie-fixture-account-proof-reference-cases
     cases
     +trie-fixture-account-proof-reference-case-names+
     "Seed trie fixture")
    (signals error
      (validate-trie-fixture-account-proof-reference-cases
       (mapcar (lambda (case)
                 (if (string= "geth-tiny-account-step-1"
                              (fixture-object-field case "name"))
                     (remove "expectedProofPrefixes"
                             case
                             :key #'car
                             :test #'string=)
                     case))
               cases)
       '("geth-tiny-account-step-1")
       "Seed trie fixture"))
    (signals error
      (validate-trie-fixture-account-proof-reference-cases
       cases
       '("geth-secure-account-step-1" "geth-secure-account-step-1")
       "Seed trie fixture"))))

