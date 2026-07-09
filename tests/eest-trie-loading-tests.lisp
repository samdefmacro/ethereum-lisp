(in-package #:ethereum-lisp.test)

(deftest optional-eest-trie-test-root-discovery
  (with-execution-spec-tests-trie-test-root (root)
    (is (probe-file root))))

(deftest eest-trie-test-root-json-discovery
  (let* ((root (execution-spec-tests-trie-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (paths (eest-trie-test-root-json-paths root)))
    (is (= 3 (length paths)))
    (is (equal '("phase-a-secureTrie.json"
                 "phase-a-trie-multi.json"
                 "phase-a-trie-sample.json")
               (eest-trie-test-root-file-names root)))
    (is (string= (namestring (truename +eest-trie-test-sample-path+))
                 (namestring (truename (third paths)))))
    (is (eest-trie-test-secure-path-p
         (truename +eest-trie-test-secure-sample-path+)))))

(deftest eest-trie-test-root-json-discovery-rejects-empty-roots
  (signals error
    (eest-trie-test-root-json-paths
     (execution-spec-tests-trie-test-root
      "tests/fixtures/geth-spec-tests-root/"))))

(deftest eest-trie-test-file-shape-validation
  (let* ((cases (load-eest-trie-test-file +eest-trie-test-sample-path+))
         (case (first cases))
         (entries (fixture-required-field case "entries"))
         (entry (first entries))
         (delete-entry (second entries))
         (hex-entry (third entries))
         (hex-delete-entry (fourth entries))
         (trie (assert-eest-trie-test-case-root case)))
    (is (= 1 (length cases)))
    (is (string= "phase-a-trie-sample"
                 (fixture-object-field case "name")))
    (is (= 4 (length entries)))
    (is (string= "array"
                 (fixture-object-field case "inputForm")))
    (is (string= "dog"
                 (fixture-object-field entry "key")))
    (is (string= "puppy"
                 (fixture-object-field entry "value")))
    (is (string= "dog"
                 (fixture-object-field delete-entry "key")))
    (is (fixture-object-field delete-entry "delete"))
    (is (string= "0x646f67"
                 (fixture-object-field hex-entry "key")))
    (is (string= "0x7075707079"
                 (fixture-object-field hex-entry "value")))
    (is (bytes= (ascii-to-bytes "dog")
                (eest-trie-test-byte-string
                 (fixture-object-field hex-entry "key")
                 "hex sample key")))
    (is (bytes= (ascii-to-bytes "puppy")
                (eest-trie-test-byte-string
                 (fixture-object-field hex-entry "value")
                 "hex sample value")))
    (is (fixture-object-field hex-delete-entry "delete"))
    (is (string= "empty-value"
                 (fixture-object-field hex-delete-entry "deleteSource")))
    (is (string= "0x"
                 (fixture-object-field hex-delete-entry "deleteSourceValue")))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (fixture-object-field case "root")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (let* ((cases (load-eest-trie-test-file +eest-trie-test-secure-sample-path+))
         (case (first cases))
         (branch-child-branch-case (second cases))
         (branch-child-extension-case (third cases))
         (branch-update-case (fourth cases))
         (delete-case (fifth cases))
         (delete-branch-child-case (sixth cases))
         (delete-branch-child-keeps-branch-case (seventh cases))
         (delete-branch-sibling-case (eighth cases))
         (delete-extension-child-case (ninth cases))
         (duplicate-overwrite-case (nth 9 cases))
         (extension-case (nth 10 cases))
         (extension-update-case (nth 11 cases))
         (insert-case (nth 12 cases))
         (missing-delete-branch-case (nth 13 cases))
         (missing-delete-extension-case (nth 14 cases))
         (object-branch-case (nth 15 cases))
         (object-empty-value-delete-case (nth 16 cases))
         (object-missing-delete-case (nth 17 cases))
         (object-hex-byte-case (nth 18 cases))
         (hex-byte-delete-case (nth 19 cases))
         (geth-secure-account-five-step-case (nth 20 cases))
         (geth-secure-account-step-1-case (nth 21 cases))
         (geth-secure-account-step-2-case (nth 22 cases))
         (geth-secure-account-step-3-case (nth 23 cases))
         (geth-secure-delete-case (nth 24 cases))
         (trie (assert-eest-trie-test-case-root case)))
    (is (= 25 (length cases)))
    (is (string= "phase-a-secure-branch"
                 (fixture-object-field case "name")))
    (is (fixture-object-field case "secure"))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field case "root")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie)))
    (is (string= "phase-a-secure-branch-child-branch"
                 (fixture-object-field branch-child-branch-case "name")))
    (is (fixture-object-field branch-child-branch-case "secure"))
    (is (string= "0x626be931db190ef431bdb5638866b8aa95af9384f3ee1c88c3065ec971a17b88"
                 (fixture-object-field branch-child-branch-case "root")))
    (is (string= "phase-a-secure-branch-child-extension"
                 (fixture-object-field branch-child-extension-case "name")))
    (is (fixture-object-field branch-child-extension-case "secure"))
    (is (string= "0x5f8d3f000e83f459e92adbebecb70ac84fc99fd16ee2e6b5a5b400b7d6e974b4"
                 (fixture-object-field branch-child-extension-case "root")))
    (is (string= "phase-a-secure-branch-update-keeps-branch"
                 (fixture-object-field branch-update-case "name")))
    (is (fixture-object-field branch-update-case "secure"))
    (is (string= "0xf853f5608648461d01d9b7df43a7723db3a35d69c80efb1482f9d5a093038f2d"
                 (fixture-object-field branch-update-case "root")))
    (is (string= "phase-a-secure-extension"
                 (fixture-object-field extension-case "name")))
    (is (string= "0x2c6f6489a6626f2f887d76882467e53e711032408473799352c0c2d192db7f80"
                 (fixture-object-field extension-case "root")))
    (is (string= "phase-a-secure-extension-update-keeps-extension"
                 (fixture-object-field extension-update-case "name")))
    (is (fixture-object-field extension-update-case "secure"))
    (is (string= "0xa2e17a0ab859cc7b48061c3cc6617389e39a5a12791460d6c14047a0d4b89f69"
                 (fixture-object-field extension-update-case "root")))
    (is (string= "phase-a-secure-delete"
                 (fixture-object-field delete-case "name")))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (fixture-object-field delete-case "root")))
    (is (string= "phase-a-secure-delete-branch-child"
                 (fixture-object-field delete-branch-child-case "name")))
    (is (string= "0xc8fb1ca12e912e15bb7db6d06ae4967dd3b59a5903f0306dd797dcaab6afcb3b"
                 (fixture-object-field delete-branch-child-case "root")))
    (is (string= "phase-a-secure-delete-branch-child-keeps-branch"
                 (fixture-object-field delete-branch-child-keeps-branch-case "name")))
    (is (string= "0x1d5d556f96abcc20327918d9209473b0709ff666a2723575202cb03388dc0103"
                 (fixture-object-field delete-branch-child-keeps-branch-case "root")))
    (is (string= "phase-a-secure-delete-branch-sibling-collapses-to-extension"
                 (fixture-object-field delete-branch-sibling-case "name")))
    (is (string= "0x2c6f6489a6626f2f887d76882467e53e711032408473799352c0c2d192db7f80"
                 (fixture-object-field delete-branch-sibling-case "root")))
    (is (string= "phase-a-secure-delete-extension-child"
                 (fixture-object-field delete-extension-child-case "name")))
    (is (string= "0xc0613970ee4545b8b874a3720590eadfc7258e9232a3edd82d6fef1a86db614f"
                 (fixture-object-field delete-extension-child-case "root")))
    (is (string= "phase-a-secure-duplicate-overwrite"
                 (fixture-object-field duplicate-overwrite-case "name")))
    (is (fixture-object-field duplicate-overwrite-case "secure"))
    (is (string= "0x293455756e50fb29ac430e499f8596798349a543f1a1dbba37880701b5a9c8fc"
                 (fixture-object-field duplicate-overwrite-case "root")))
    (is (string= "phase-a-secure-insert"
                 (fixture-object-field insert-case "name")))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field insert-case "root")))
    (is (string= "phase-a-secure-missing-delete-branch"
                 (fixture-object-field missing-delete-branch-case "name")))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field missing-delete-branch-case "root")))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field missing-delete-branch-case "entries")))
    (is (string= "phase-a-secure-missing-delete-extension"
                 (fixture-object-field missing-delete-extension-case "name")))
    (is (string= "0x2c6f6489a6626f2f887d76882467e53e711032408473799352c0c2d192db7f80"
                 (fixture-object-field missing-delete-extension-case "root")))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field missing-delete-extension-case "entries")))
    (is (string= "phase-a-secure-object-form-branch"
                 (fixture-object-field object-branch-case "name")))
    (is (string= "object"
                 (fixture-object-field object-branch-case "inputForm")))
    (is (fixture-object-field object-branch-case "secure"))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field object-branch-case "root")))
    (is (string= "phase-a-secure-object-form-empty-value-delete"
                 (fixture-object-field object-empty-value-delete-case "name")))
    (is (string= "object"
                 (fixture-object-field object-empty-value-delete-case
                                       "inputForm")))
    (is (fixture-object-field object-empty-value-delete-case "secure"))
    (is (find-if (lambda (entry)
                   (and (string= "empty-value"
                                 (fixture-object-field entry "deleteSource"))
                        (string= ""
                                 (fixture-object-field entry
                                                       "deleteSourceValue"))))
                 (fixture-object-field object-empty-value-delete-case
                                       "entries")))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field object-empty-value-delete-case
                                       "root")))
    (is (string= "phase-a-secure-object-form-missing-delete"
                 (fixture-object-field object-missing-delete-case "name")))
    (is (string= "object"
                 (fixture-object-field object-missing-delete-case "inputForm")))
    (is (fixture-object-field object-missing-delete-case "secure"))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field object-missing-delete-case "entries")))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field object-missing-delete-case "root")))
    (is (string= "phase-a-secure-object-form-value-hex-bytes"
                 (fixture-object-field object-hex-byte-case "name")))
    (is (string= "object"
                 (fixture-object-field object-hex-byte-case "inputForm")))
    (is (fixture-object-field object-hex-byte-case "secure"))
    (is (string= "0x71fbc97d2b878e33df7dfb4b690789c4b7fe4eef64dd650928aeba15553b3e94"
                 (fixture-object-field object-hex-byte-case "root")))
    (is (find-if (lambda (entry)
                   (string= "0xdeadbeef"
                            (fixture-object-field entry "value")))
                 (fixture-object-field object-hex-byte-case "entries")))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field object-hex-byte-case "entries")))
    (is (string= "phase-a-secure-value-hex-byte-delete"
                 (fixture-object-field hex-byte-delete-case "name")))
    (is (fixture-object-field hex-byte-delete-case "secure"))
    (is (string= "array"
                 (fixture-object-field hex-byte-delete-case "inputForm")))
    (is (string= "0x51601f67f06338ad14e87799781d9eb786daf72d238e3122434a6d7b71900c7f"
                 (fixture-object-field hex-byte-delete-case "root")))
    (is (find-if (lambda (entry)
                   (string= "0xdeadbeef"
                            (fixture-object-field entry "value")))
                 (fixture-object-field hex-byte-delete-case "entries")))
    (is (find-if (lambda (entry)
                   (fixture-field-present-p entry "delete"))
                 (fixture-object-field hex-byte-delete-case "entries")))
    (is (string= "phase-a-secure-zgeth-account-five-step"
                 (fixture-object-field geth-secure-account-five-step-case
                                       "name")))
    (is (fixture-object-field geth-secure-account-five-step-case "secure"))
    (is (string= "0xbd345e2e22174040b0f17b74fbb3377917362b85a533166784d2bd6278f95865"
                 (fixture-object-field geth-secure-account-five-step-case
                                       "root")))
    (is (string= "phase-a-secure-zgeth-account-step-1"
                 (fixture-object-field geth-secure-account-step-1-case "name")))
    (is (fixture-object-field geth-secure-account-step-1-case "secure"))
    (is (string= "0xc8c796b39027107040d7bae53042070762d888d7ec5e8fa875c95bde2ab3e8a5"
                 (fixture-object-field geth-secure-account-step-1-case "root")))
    (is (string= "phase-a-secure-zgeth-account-step-2"
                 (fixture-object-field geth-secure-account-step-2-case "name")))
    (is (fixture-object-field geth-secure-account-step-2-case "secure"))
    (is (string= "0x95e5d195992feeb1c07e0725456fde075005f3fe3ae2270b0b956004049de80f"
                 (fixture-object-field geth-secure-account-step-2-case "root")))
    (is (string= "phase-a-secure-zgeth-account-step-3"
                 (fixture-object-field geth-secure-account-step-3-case "name")))
    (is (fixture-object-field geth-secure-account-step-3-case "secure"))
    (is (string= "0x65e27b7b7b43826149e6b5674be3ff0f107ff6e988d20c1be165a172eeef399d"
                 (fixture-object-field geth-secure-account-step-3-case "root")))
    (is (string= "phase-a-secure-zgeth-delete-sequence"
                 (fixture-object-field geth-secure-delete-case "name")))
    (is (fixture-object-field geth-secure-delete-case "secure"))
    (is (string= "0x29b235a58c3c25ab83010c327d5932bcf05324b7d6b1185e650798034783ca9d"
                 (fixture-object-field geth-secure-delete-case "root"))))
  (let* ((case (normalize-eest-trie-test-case
                "empty-value-delete"
                (list (cons "in" (list (list "dog" "")))
                      (cons "root"
                            "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
         (entry (first (fixture-required-field case "entries"))))
    (is (string= "array"
                 (fixture-object-field case "inputForm")))
    (is (string= "dog"
                 (fixture-object-field entry "key")))
    (is (fixture-object-field entry "delete"))
    (is (string= ""
                 (fixture-object-field entry "deleteSourceValue"))))
  (let* ((case (normalize-eest-trie-test-case
                "object-form-entry"
                (list (cons "in" (list (cons "dog" "puppy")))
                      (cons "root"
                            "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
         (entry (first (fixture-required-field case "entries")))
         (trie (assert-eest-trie-test-case-root case)))
    (is (string= "object"
                 (fixture-object-field case "inputForm")))
    (is (string= "dog"
                 (fixture-object-field entry "key")))
    (is (string= "puppy"
                 (fixture-object-field entry "value")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (let* ((case (normalize-eest-trie-test-case
                "object-form-null-delete"
                (list (cons "in" (list (cons "cat" nil)
                                       (cons "dog" "puppy")))
                      (cons "root"
                            "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
         (entries (fixture-required-field case "entries"))
         (delete-entry (first entries))
         (put-entry (second entries))
         (trie (assert-eest-trie-test-case-root case)))
    (is (string= "object"
                 (fixture-object-field case "inputForm")))
    (is (string= "cat"
                 (fixture-object-field delete-entry "key")))
    (is (fixture-object-field delete-entry "delete"))
    (is (string= "dog"
                 (fixture-object-field put-entry "key")))
    (is (string= "puppy"
                 (fixture-object-field put-entry "value")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (is (handler-case
          (progn
            (assert-eest-trie-test-case-root
             (normalize-eest-trie-test-case
              "out-missing-final-key"
              (list (cons "in" (list (list "dog" "puppy")))
                    (cons "out" (list (cons "cat" nil)))
                    (cons "root"
                          "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
            nil)
        (error (condition)
          (not (null
                (search "out missing final key"
                        (princ-to-string condition)))))))
  (let* ((case (normalize-eest-trie-test-case
                "secure-entry"
                (list (cons "in" (list (list "dog" "puppy")))
                      (cons "secure" t)
                      (cons "root"
                            "ff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"))))
         (trie (assert-eest-trie-test-case-root case)))
    (is (fixture-object-field case "secure"))
    (is (string= "0xff6bdab74d713ebb4005f8604a2108598e24cd031be3ef2880989457695066bf"
                 (fixture-object-field case "root")))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (fixture-object-field
                (normalize-eest-trie-test-case
                 "uppercase-root"
                 (list (cons "in" nil)
                       (cons "root"
                             "0X56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421")))
                "root")))
  (let* ((case (normalize-eest-trie-test-case
                "uppercase-entry-bytes"
                (list (cons "in" (list (list "0X646F67" "0X7075707079")
                                       (list "0X646F67" "0X")))
                      (cons "root"
                            "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
         (entries (fixture-required-field case "entries"))
         (put-entry (first entries))
         (delete-entry (second entries))
         (trie (assert-eest-trie-test-case-root case)))
    (is (string= "0x646f67"
                 (fixture-object-field put-entry "key")))
    (is (string= "0x7075707079"
                 (fixture-object-field put-entry "value")))
    (is (string= "0x646f67"
                 (fixture-object-field delete-entry "key")))
    (is (fixture-object-field delete-entry "delete"))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (let* ((case (normalize-eest-trie-test-case
                "intermediate-roots"
                (list (cons "in" (list (list "dog" "puppy")
                                       (list "dog" nil)))
                      (cons "intermediateRoots"
                            (list "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"
                                  "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))
                      (cons "root"
                            "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
         (roots (fixture-required-field case "expectedIntermediateRoots"))
         (trie (assert-eest-trie-test-case-root case)))
    (is (= 2 (length roots)))
    (is (string= "0xed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"
                 (first roots)))
    (is (string= (fixture-object-field case "root")
                 (mpt-root-hex trie))))
  (let* ((case (normalize-eest-trie-test-case
                "entry-pairs"
                (list (cons "in" (list (list "b" "two")
                                        (list "a" "one")))
                      (cons "entryPairs"
                            (list
                             (list (cons "key" "a")
                                   (cons "value" "one"))
                             (list (cons "key" "b")
                                   (cons "value" "two"))))
                      (cons "root"
                            "0x381e0a6f9726d283e18de485257e324ae8c36c91bec3fb62c96c6794178c9818"))))
         (entry-pairs (fixture-required-field case "expectedEntryPairs"))
         (trie (assert-eest-trie-test-case-root case)))
    (is (= 2 (length entry-pairs)))
    (is (string= "0x381e0a6f9726d283e18de485257e324ae8c36c91bec3fb62c96c6794178c9818"
                 (mpt-root-hex trie))))
  (let* ((case (normalize-eest-trie-test-case
                "proof-nodes"
                (list (cons "in" (list (list "k" "v")))
                      (cons "proofs"
                            (list
                             (list (cons "key" "k")
                                   (cons "nodeRlps"
                                         (list "0xc482206b76"))
                                   (cons "exactLength" t))
                             (list (cons "key" "a")
                                   (cons "nodeRlps"
                                         (list "0xc482206b76"))
                                   (cons "exactLength" t))))
                      (cons "root"
                            "0x6675ca087d4e4344aa1348e54d5b39e1657b57287eb207107a04ffae79e88215"))))
         (proofs (fixture-required-field case "expectedProofs"))
         (trie (assert-eest-trie-test-case-root case)))
    (is (= 2 (length proofs)))
    (is (fixture-object-field (first proofs) "exactLength"))
    (is (string= "0x6675ca087d4e4344aa1348e54d5b39e1657b57287eb207107a04ffae79e88215"
                 (mpt-root-hex trie))))
  (let* ((case (normalize-eest-trie-test-case
                "explicit-range"
                (list (cons "in" (list (list "apple" "fruit1")
                                       (list "banana" "fruit2")
                                       (list "cherry" "fruit3")))
                      (cons "ranges"
                            (list (list (cons "start" "banana")
                                        (cons "end" "date")
                                        (cons "keys" (list "banana" "cherry")))
                                  (list (cons "start" "banana")
                                        (cons "end" "banana")
                                        (cons "keys" nil))))
                    (cons "root"
                          "1105d1b6b4ba5b18a93daeffa42f4a2409cc9906efd03206f55bd12b9840ea1e"))))
         (ranges (fixture-required-field case "expectedRanges")))
    (is (= 2 (length ranges)))
    (is (string= "banana" (fixture-object-field (first ranges) "start")))
    (assert-eest-trie-test-case-root case))
  (is (handler-case
          (progn
            (assert-eest-trie-test-case-root
             (normalize-eest-trie-test-case
              "wrong-root-message"
              (list (cons "in" (list (list "dog" "puppy")))
                    (cons "root"
                          "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
            nil)
        (error (condition)
          (not (null
                (search "EEST trie test case wrong-root-message root mismatch"
                        (princ-to-string condition)))))))
  (signals error
    (normalize-eest-trie-test-case
     "missing-root"
     (list (cons "in" nil))))
  (signals error
    (normalize-eest-trie-test-case
     42
     (list (cons "in" nil)
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "missing-in"
     (list (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-entry"
     (list (cons "in" (list (list "dog")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-entry-value"
     (list (cons "in" (list (list "dog" 1)))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "duplicate-object-entry"
     (list (cons "in" (list (cons "dog" "puppy")
                            (cons "dog" "hound")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "duplicate-object-entry-normalized"
     (list (cons "in" (list (cons "dog" "puppy")
                            (cons "0x646f67" "hound")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-entry-key-hex"
     (list (cons "in" (list (list "0x0" "puppy")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (is (handler-case
          (progn
            (normalize-eest-trie-test-case
             "bad-entry-key-message"
             (list (cons "in" (list (list "dog" "puppy")
                                    (list "0x0" "puppy")))
                   (cons "root"
                         "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")))
            nil)
        (error (condition)
          (not (null
                (search "EEST trie test case bad-entry-key-message in entry 1 key"
                        (princ-to-string condition)))))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-entry-value-hex"
     (list (cons "in" (list (list "dog" "0x0")))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-range-key"
     (list (cons "in" (list (list "dog" "puppy")))
           (cons "ranges" (list (list (cons "keys" (list 42)))))
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-intermediate-root-count"
     (list (cons "in" (list (list "dog" "puppy")
                            (list "dog" nil)))
           (cons "intermediateRoots"
                 (list "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))
           (cons "root"
                 "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-entry-pair"
     (list (cons "in" (list (list "k" "v")))
           (cons "entryPairs"
                 (list
                  (list (cons "key" "k"))))
           (cons "root"
                 "0x6675ca087d4e4344aa1348e54d5b39e1657b57287eb207107a04ffae79e88215"))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-proof-node"
     (list (cons "in" (list (list "k" "v")))
           (cons "proofs"
                 (list
                  (list (cons "key" "k")
                        (cons "nodeRlps" nil)
                        (cons "exactLength" t))))
           (cons "root"
                 "0x6675ca087d4e4344aa1348e54d5b39e1657b57287eb207107a04ffae79e88215"))))
  (signals error
    (normalize-eest-trie-test-case
     "non-string-root"
     (list (cons "in" nil)
           (cons "root" 1))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-root"
     (list (cons "in" nil)
           (cons "root" "0x1234"))))
  (is (handler-case
          (progn
            (normalize-eest-trie-test-case
             "bad-root-message"
             (list (cons "in" nil)
                   (cons "root" "0x1234")))
            nil)
        (error (condition)
          (not (null
                (search "EEST trie test case bad-root-message root must be a 32-byte hex hash"
                        (princ-to-string condition)))))))
  (signals error
    (normalize-eest-trie-test-case
     "unknown-field"
     (list (cons "in" nil)
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")
           (cons "unexpected" t))))
  (signals error
    (normalize-eest-trie-test-case
     "bad-secure"
     (list (cons "in" nil)
           (cons "secure" "yes")
           (cons "root"
                 "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
  (signals error
    (validate-eest-trie-test-file-case-names nil "inline-empty"))
  (signals error
    (validate-eest-trie-test-file-case-names
     (list "not-a-json-object-field")
     "inline-entry-shape"))
  (signals error
    (validate-eest-trie-test-file-case-names
     (list (cons "duplicate-case"
                 (list (cons "in" nil)
                       (cons "root"
                             "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278")))
           (cons "duplicate-case"
                 (list (cons "in" nil)
                       (cons "root"
                             "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))
     "inline")))

(deftest eest-trie-test-root-case-loading
  (let* ((root (execution-spec-tests-trie-test-root
                "tests/fixtures/execution-spec-tests-root/"))
         (cases (load-eest-trie-test-root-cases root))
         (selected-cases
           (load-phase-a-eest-trie-test-root-cases root))
         (summary (eest-trie-test-case-summary selected-cases)))
    (is (= 87 (length cases)))
    (is (= 86 (length selected-cases)))
    (validate-trie-reference-gates
     selected-cases
     +phase-a-eest-trie-reference-gates+
     "Phase A EEST trie subset")
    (signals error
      (validate-trie-reference-gates
       selected-cases
       '((:name :missing-reference
          :validator validate-trie-reference-case-requirements
          :items (("phase-a-trie-multi.json/missing-geth-case" . :plain))))
       "Phase A EEST trie subset"))
    (signals error
      (validate-trie-reference-gates
       selected-cases
       '((:name :bad-validator
          :validator missing-trie-reference-validator
          :items ("phase-a-trie-multi.json/geth-tiny-account-step-1")))
       "Phase A EEST trie subset"))
    (validate-trie-reference-case-requirements
     selected-cases
     (phase-a-eest-trie-reference-gate-items :case-mode)
     "Phase A EEST trie subset")
    (signals error
      (validate-trie-reference-case-requirements
       selected-cases
       '(("phase-a-trie-multi.json/missing-geth-case" . :plain))
       "Phase A EEST trie subset"))
    (signals error
      (validate-trie-reference-case-requirements
       selected-cases
       '(("phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3" . :plain))
       "Phase A EEST trie subset"))
    (validate-trie-reference-explicit-output-requirements
     selected-cases
     (phase-a-eest-trie-reference-gate-items :explicit-output)
     "Phase A EEST trie subset")
    (signals error
      (validate-trie-reference-explicit-output-requirements
       selected-cases
       '("phase-a-trie-multi.json/missing-geth-case")
       "Phase A EEST trie subset"))
    (signals error
      (validate-trie-reference-explicit-output-requirements
       (mapcar (lambda (case)
                 (if (string= "phase-a-trie-multi.json/geth-tiny-account-step-1"
                              (fixture-object-field case "name"))
                     (remove "expectedOut" case :key #'car :test #'string=)
                     case))
               selected-cases)
       '("phase-a-trie-multi.json/geth-tiny-account-step-1")
       "Phase A EEST trie subset"))
    (validate-trie-reference-intermediate-root-requirements
     selected-cases
     (phase-a-eest-trie-reference-gate-items :intermediate-roots)
     "Phase A EEST trie subset")
    (signals error
      (validate-trie-reference-intermediate-root-requirements
       selected-cases
       '("phase-a-trie-multi.json/missing-geth-case")
       "Phase A EEST trie subset"))
    (signals error
      (validate-trie-reference-intermediate-root-requirements
       (mapcar (lambda (case)
                 (if (string= "phase-a-trie-multi.json/geth-stacktrie-short-branch-growth"
                              (fixture-object-field case "name"))
                     (remove "expectedIntermediateRoots" case :key #'car :test #'string=)
                     case))
               selected-cases)
       '("phase-a-trie-multi.json/geth-stacktrie-short-branch-growth")
       "Phase A EEST trie subset"))
    (validate-trie-reference-entry-pair-requirements
     selected-cases
     (phase-a-eest-trie-reference-gate-items :entry-pairs)
     "Phase A EEST trie subset")
    (signals error
      (validate-trie-reference-entry-pair-requirements
       selected-cases
       '("phase-a-trie-multi.json/missing-geth-case")
       "Phase A EEST trie subset"))
    (signals error
      (validate-trie-reference-entry-pair-requirements
       (mapcar (lambda (case)
                 (if (string= "phase-a-trie-multi.json/geth-tiny-account-step-1"
                              (fixture-object-field case "name"))
                     (remove "expectedEntryPairs" case :key #'car :test #'string=)
                     case))
               selected-cases)
       '("phase-a-trie-multi.json/geth-tiny-account-step-1")
       "Phase A EEST trie subset"))
    (validate-trie-reference-proof-requirements
     selected-cases
     (phase-a-eest-trie-reference-gate-items :proofs)
     "Phase A EEST trie subset")
    (signals error
      (validate-trie-reference-proof-requirements
       selected-cases
       '("phase-a-trie-multi.json/missing-geth-case")
       "Phase A EEST trie subset"))
    (signals error
      (validate-trie-reference-proof-requirements
       (mapcar (lambda (case)
                 (if (string= "phase-a-trie-multi.json/geth-tiny-account-step-1"
                              (fixture-object-field case "name"))
                     (remove "expectedProofs" case :key #'car :test #'string=)
                     case))
               selected-cases)
       '("phase-a-trie-multi.json/geth-tiny-account-step-1")
       "Phase A EEST trie subset"))
    (validate-trie-reference-explicit-range-requirements
     selected-cases
     (phase-a-eest-trie-reference-gate-items :ranges)
     "Phase A EEST trie subset")
    (signals error
      (validate-trie-reference-explicit-range-requirements
       selected-cases
       '("phase-a-trie-multi.json/missing-geth-case")
       "Phase A EEST trie subset"))
    (signals error
      (validate-trie-reference-explicit-range-requirements
       (mapcar (lambda (case)
                 (if (string= "phase-a-trie-multi.json/geth-tiny-account-five-step"
                              (fixture-object-field case "name"))
                     (remove "expectedRanges" case :key #'car :test #'string=)
                     case))
               selected-cases)
       '("phase-a-trie-multi.json/geth-tiny-account-five-step")
       "Phase A EEST trie subset"))
    (let ((case-names
            (mapcar (lambda (case)
                      (fixture-object-field case "name"))
                    cases))
          (selected-names (fixture-object-field summary "names"))
          (roots (fixture-object-field summary "roots")))
      (is (member "phase-a-secureTrie.json/phase-a-secure-branch-update-keeps-branch"
                  case-names
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-extension-update-keeps-extension"
                  case-names
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-branch-update-keeps-branch"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-extension-update-keeps-extension"
                  selected-names
                  :test #'string=))
      (is (member "0xf853f5608648461d01d9b7df43a7723db3a35d69c80efb1482f9d5a093038f2d"
                  roots
                  :test #'string=))
      (is (member "0xa2e17a0ab859cc7b48061c3cc6617389e39a5a12791460d6c14047a0d4b89f69"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-insert-shared-prefix"
                  selected-names
                  :test #'string=))
      (is (member "0x8aad789dff2f538bca5d8ea56e8abe10f4c7ba3a5dea95fea4cd6e7c3a1168d3"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-long-leaf-value"
                  selected-names
                  :test #'string=))
      (is (member "0xd23786fb4a010da3ce639d66d5e904a11dbc02746d1ce25029e53290cabf28ab"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-large-value-branch"
                  selected-names
                  :test #'string=))
      (is (member "0xafebee6cfce72f9d2a7a4f5926ac11f2a79bd75f3a9ae6358a08252ba5dce3be"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-tiny-account-step-3"
                  selected-names
                  :test #'string=))
      (is (member "0x0608c1d1dc3905fa22204c7a0e43644831c3b6d3def0f274be623a948197e64a"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-tiny-account-five-step"
                  selected-names
                  :test #'string=))
      (is (member "0x0bb700122f004e1b0171d08613c19769afe3affc46c0ffefcfa80250637d4509"
                  roots
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3"
                  selected-names
                  :test #'string=))
      (is (member "0x65e27b7b7b43826149e6b5674be3ff0f107ff6e988d20c1be165a172eeef399d"
                  roots
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-zgeth-account-five-step"
                  selected-names
                  :test #'string=))
      (is (member "0xbd345e2e22174040b0f17b74fbb3377917362b85a533166784d2bd6278f95865"
                  roots
                  :test #'string=))
      (is (member "phase-a-secureTrie.json/phase-a-secure-zgeth-delete-sequence"
                  selected-names
                  :test #'string=))
      (is (member "0x29b235a58c3c25ab83010c327d5932bcf05324b7d6b1185e650798034783ca9d"
                  roots
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-delete-sequence"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-empty-value-sequence"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-replication-sequence"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-random-cases-sequence"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-stacktrie-extension-child-boundary"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-stacktrie-short-branch-growth"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-stacktrie-root-branch-extension-child"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-tail-fanout"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-splits-to-root-branch"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-stacktrie-zero-prefix-extension-fanout"
                  selected-names
                  :test #'string=))
      (is (member "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-tail-fanout"
                  selected-names
                  :test #'string=))
      (is (member "0x5991bb8c6514148a29db676a14ac506cd2cd5775ace63c30a4fe457715e9ac84"
                  roots
                  :test #'string=))
      (is (member "0x09c889feaafd53779755259beaa0ff41c32512c8cac45152af46fae7ebdef210"
                  roots
                  :test #'string=))
      (is (member "0x380d56237a963e2c17a7c282142dc0b85d3236cd515d4f0348c787e70a68d24c"
                  roots
                  :test #'string=))
      (is (member "0x962c0fffdeef7612a4f7bff1950d67e3e81c878e48b9ae45b3b374253b050bd8"
                  roots
                  :test #'string=))
      (is (member "0xbee629dd27a40772b2e1a67ec6db270d26acdf8d3b674dfae27866ad6ae1f48b"
                  roots
                  :test #'string=))
      (is (member "0x9e6832db0dca2b5cf81c0e0727bfde6afc39d5de33e5720bccacc183c162104e"
                  roots
                  :test #'string=))
      (is (member "0x4f4e368ab367090d5bc3dbf25f7729f8bd60df84de309b4633a6b69ab66142c0"
                  roots
                  :test #'string=))
      (is (member "0x5f5989b820ff5d76b7d49e77bb64f26602294f6c42a1a3becc669cd9e0dc8ec9"
                  roots
                  :test #'string=))
      (is (member "0x33fc259629187bbe54b92f82f0cd8083b91a12e41a9456b84fc155321e334db7"
                  roots
                  :test #'string=))
      (is (member "0x1164d7299964e74ac40d761f9189b2a3987fae959800d0f7e29d3aaf3eae9e15"
                  roots
                  :test #'string=)))
    (is (fixture-object-field (first cases) "secure"))
    (is (string= "0x8acdeb64a8209f6c7f27168a1767883b15ad7e29ed86bec0e59841bce1dd1268"
                 (fixture-object-field (first cases) "root")))
    (is (string= "phase-a-trie-sample.json"
                 (fixture-object-field (nth 86 cases) "name")))
    (is (string= "phase-a-secureTrie.json/phase-a-secure-branch"
                 (fixture-object-field (first selected-cases) "name")))
    (is (fixture-object-field (first selected-cases) "secure"))
    (is (string= "phase-a-secureTrie.json/phase-a-secure-object-form-value-hex-bytes"
                 (fixture-object-field (nth 18 selected-cases) "name")))
    (is (string= "phase-a-trie-sample.json"
                 (fixture-object-field (nth 85 selected-cases) "name")))
    (is (= 86 (fixture-object-field summary "count")))
    (is (= 8 (fixture-object-field summary "objectFormCaseCount")))
    (is (= 5 (fixture-object-field summary "objectFormDeleteEntryCount")))
    (is (= 2 (fixture-object-field summary "objectFormEmptyValueDeleteEntryCount")))
    (is (= 3 (fixture-object-field summary "objectFormWriteOnlyCaseCount")))
    (is (= 4 (fixture-object-field summary "secureObjectFormCaseCount")))
    (is (= 23 (fixture-object-field summary "objectFormPermutationReplayCount")))
    (is (= 12 (fixture-object-field
               summary
               "secureObjectFormPermutationReplayCount")))
    (is (= 11 (fixture-object-field
               summary
               "plainObjectFormPermutationReplayCount")))
    (is (= 3 (fixture-object-field summary "secureObjectFormDeleteEntryCount")))
    (is (= 1 (fixture-object-field
              summary
              "secureObjectFormEmptyValueDeleteEntryCount")))
    (is (= 1 (fixture-object-field
              summary
              "plainObjectFormEmptyValueDeleteEntryCount")))
    (is (= 25 (fixture-object-field summary "secureCaseCount")))
    (is (= 61 (fixture-object-field summary "plainCaseCount")))
    (is (= 24 (fixture-object-field summary "secureNonEmptyRootCount")))
    (is (= 12 (fixture-object-field summary "secureBranchRootCount")))
    (is (= 4 (fixture-object-field summary "secureExtensionRootCount")))
    (is (= 60 (fixture-object-field summary "plainNonEmptyRootCount")))
    (is (= 32 (fixture-object-field summary "branchRootCount")))
    (is (= 5 (fixture-object-field summary "branchChildBranchCount")))
    (is (= 7 (fixture-object-field summary "branchChildExtensionCount")))
    (is (= 1 (fixture-object-field summary "secureBranchChildBranchCount")))
    (is (= 1 (fixture-object-field summary "secureBranchChildExtensionCount")))
    (is (= 17 (fixture-object-field summary "embeddedBranchChildReferenceCount")))
    (is (= 54 (fixture-object-field summary "hashedBranchChildReferenceCount")))
    (is (= 30 (fixture-object-field summary "secureHashedBranchChildReferenceCount")))
    (is (= 2 (fixture-object-field summary "branchValueRootCount")))
    (is (= 1 (fixture-object-field summary "branchValueZeroChildRootCount")))
    (is (= 1 (fixture-object-field summary "emptyKeyDeleteNonEmptyRootCount")))
    (is (= 10 (fixture-object-field summary "branchChildDeleteValueLeafCount")))
    (is (= 1 (fixture-object-field summary "branchChildDeletePlainLeafCount")))
    (is (= 4 (fixture-object-field summary "branchChildDeletePlainBranchCount")))
    (is (= 2 (fixture-object-field summary "branchChildDeleteSecureBranchCount")))
    (is (= 1 (fixture-object-field summary "extensionDeletePlainLeafCount")))
    (is (= 2 (fixture-object-field summary "extensionDeleteSecureLeafCount")))
    (is (= 6 (fixture-object-field summary "extensionDeletePlainExtensionCount")))
    (is (= 1 (fixture-object-field summary "extensionDeleteSecureExtensionCount")))
    (is (= 8 (fixture-object-field summary "branchDeleteRootCount")))
    (is (= 5 (fixture-object-field summary "overwrittenKeyCaseCount")))
    (is (= 3 (fixture-object-field summary "secureOverwrittenKeyCaseCount")))
    (is (= 1 (fixture-object-field summary "secureBranchOverwriteRootCount")))
    (is (= 1 (fixture-object-field summary "secureExtensionOverwriteRootCount")))
    (is (= 4 (fixture-object-field summary "leafMissingDeleteRootCount")))
    (is (= 2 (fixture-object-field summary "secureBranchMissingDeleteRootCount")))
    (is (= 1 (fixture-object-field summary "secureExtensionMissingDeleteRootCount")))
    (is (= 152 (fixture-object-field summary "hexByteStringEntryCount")))
    (is (= 39 (fixture-object-field summary "hexValueEntryCount")))
    (is (= 15 (fixture-object-field summary "secureHexValueEntryCount")))
    (is (= 24 (fixture-object-field summary "plainHexValueEntryCount")))
    (is (= 2 (fixture-object-field summary "secureObjectFormHexValueEntryCount")))
    (is (= 1 (fixture-object-field summary "plainObjectFormHexValueEntryCount")))
    (is (= 5 (fixture-object-field summary "emptyValueDeleteEntryCount")))
    (is (= 1 (fixture-object-field summary "hexEmptyValueDeleteEntryCount")))
    (is (= 4 (fixture-object-field summary "stringEmptyValueDeleteEntryCount")))
    (is (= 2 (fixture-object-field
              summary
              "objectFormStringEmptyValueDeleteEntryCount")))
    (is (= 32 (fixture-object-field summary "extensionRootCount")))
    (is (= 4 (fixture-object-field summary "embeddedExtensionChildReferenceCount")))
    (is (= 28 (fixture-object-field summary "hashedExtensionChildReferenceCount")))
    (is (= 4 (fixture-object-field summary "secureHashedExtensionChildReferenceCount")))
    (is (= 28 (fixture-object-field summary "nonEmptyDeleteRootCount")))
    (is (= 11 (fixture-object-field summary "secureNonEmptyDeleteRootCount")))
    (is (= 273 (fixture-object-field summary "totalEntryCount")))
    (is (= 204 (fixture-object-field summary "finalEntryPairCount")))
    (is (= 84 (fixture-object-field summary "finalEntryPairReplayCaseCount")))
    (is (= 48 (fixture-object-field summary "secureFinalEntryPairCount")))
    (is (= 156 (fixture-object-field summary "plainFinalEntryPairCount")))
    (is (= 24 (fixture-object-field
                summary
                "secureFinalEntryPairReplayCaseCount")))
    (is (= 60 (fixture-object-field
                summary
                "plainFinalEntryPairReplayCaseCount")))
    (is (= 8 (fixture-object-field summary "explicitEntryPairCaseCount")))
    (is (= 4 (fixture-object-field summary "secureExplicitEntryPairCaseCount")))
    (is (= 4 (fixture-object-field summary "plainExplicitEntryPairCaseCount")))
    (is (= 22 (fixture-object-field summary "explicitEntryPairCount")))
    (is (= 11 (fixture-object-field summary "secureExplicitEntryPairCount")))
    (is (= 11 (fixture-object-field summary "plainExplicitEntryPairCount")))
    (is (= 86 (fixture-object-field summary "entryRangeReplayCaseCount")))
    (is (= 84 (fixture-object-field
               summary
               "nonEmptyEntryRangeReplayCaseCount")))
    (is (= 38 (fixture-object-field
               summary
               "boundedEntryRangeReplayCaseCount")))
    (is (= 24 (fixture-object-field
               summary
               "secureEntryRangeReplayCaseCount")))
    (is (= 60 (fixture-object-field
               summary
                "plainEntryRangeReplayCaseCount")))
    (is (= 2 (fixture-object-field summary "explicitEntryRangeCaseCount")))
    (is (= 1 (fixture-object-field summary "secureExplicitEntryRangeCaseCount")))
    (is (= 1 (fixture-object-field summary "plainExplicitEntryRangeCaseCount")))
    (is (= 10 (fixture-object-field summary "explicitEntryRangeCount")))
    (is (= 21 (fixture-object-field summary "intermediateRootCaseCount")))
    (is (= 21 (fixture-object-field summary "plainIntermediateRootCaseCount")))
    (is (= 69 (fixture-object-field summary "intermediateRootCount")))
    (is (= 17 (fixture-object-field summary "proofNodeCaseCount")))
    (is (= 7 (fixture-object-field summary "secureProofNodeCaseCount")))
    (is (= 10 (fixture-object-field summary "plainProofNodeCaseCount")))
    (is (= 41 (fixture-object-field summary "proofNodeAssertionCount")))
    (is (= 26 (fixture-object-field summary "exactProofNodeAssertionCount")))
    (is (= 237 (fixture-object-field summary "totalWriteEntryCount")))
    (is (= 204 (fixture-object-field summary "proofPresentKeyCount")))
    (is (= 48 (fixture-object-field summary "secureProofPresentKeyCount")))
    (is (= 156 (fixture-object-field summary "plainProofPresentKeyCount")))
    (is (= 34 (fixture-object-field summary "proofMissingKeyCount")))
    (is (= 13 (fixture-object-field summary "secureProofMissingKeyCount")))
    (is (= 21 (fixture-object-field summary "plainProofMissingKeyCount")))
    (is (= 34 (fixture-object-field summary "explicitOutputCaseCount")))
    (is (= 6 (fixture-object-field summary "secureExplicitOutputCaseCount")))
    (is (= 28 (fixture-object-field summary "plainExplicitOutputCaseCount")))
    (is (= 135 (fixture-object-field summary "explicitOutputEntryCount")))
    (is (= 101 (fixture-object-field summary "explicitOutputPresentKeyCount")))
    (is (= 15 (fixture-object-field summary "secureExplicitOutputPresentKeyCount")))
    (is (= 86 (fixture-object-field summary "plainExplicitOutputPresentKeyCount")))
    (is (= 34 (fixture-object-field summary "explicitOutputMissingKeyCount")))
    (is (= 6 (fixture-object-field summary "secureExplicitOutputMissingKeyCount")))
    (is (= 28 (fixture-object-field summary "plainExplicitOutputMissingKeyCount")))
    (is (= 2 (fixture-object-field summary "objectFormExplicitOutputCaseCount")))
    (is (= 1 (fixture-object-field summary "secureObjectFormExplicitOutputCaseCount")))
    (is (= 1 (fixture-object-field summary "plainObjectFormExplicitOutputCaseCount")))
    (is (= 4 (fixture-object-field summary "objectFormExplicitOutputPresentKeyCount")))
    (is (= 2 (fixture-object-field summary "objectFormExplicitOutputMissingKeyCount")))
    (is (= 59 (fixture-object-field summary "secureWriteEntryCount")))
    (is (= 178 (fixture-object-field summary "plainWriteEntryCount")))
    (is (= 36 (fixture-object-field summary "totalDeleteEntryCount")))
    (is (= 13 (fixture-object-field summary "secureDeleteEntryCount")))
    (is (= 23 (fixture-object-field summary "plainDeleteEntryCount")))
    (flet ((remove-selected-name (name)
             (remove-if
              (lambda (case)
                (string= name (fixture-object-field case "name")))
              selected-cases)))
      (signals error
        (validate-phase-a-eest-trie-test-coverage
         (remove-selected-name
          "phase-a-secureTrie.json/phase-a-secure-branch-update-keeps-branch")))
      (signals error
        (validate-phase-a-eest-trie-test-coverage
         (remove-selected-name
          "phase-a-secureTrie.json/phase-a-secure-extension-update-keeps-extension")))
      (signals error
        (validate-phase-a-eest-trie-test-coverage
         (remove (second selected-cases) selected-cases)))
      (signals error
        (validate-phase-a-eest-trie-test-coverage
         (remove (third selected-cases) selected-cases))))
    (is (string= "phase-a-trie-multi.json/alpha"
                 (eest-trie-root-case-name root
                                           (second
                                            (eest-trie-test-root-json-paths
                                             root))
                                           "alpha"
                                           nil)))
    (signals error
      (load-eest-trie-test-root-cases
       root
       :names '("missing-trie.json")))
    (signals error
      (load-eest-trie-test-root-cases
       root
       :names '("phase-a-trie-sample.json" "phase-a-trie-sample.json")))
    (signals error
      (load-eest-trie-test-root-cases
       root
       :names '("")))
    (validate-eest-trie-selector-list
     +phase-a-eest-trie-test-case-names+)
    (signals error
      (validate-eest-trie-selector-list nil))
    (signals error
      (validate-eest-trie-selector-list "phase-a-trie-sample.json"))
    (signals error
      (validate-eest-trie-selector-list '(42)))
    (signals error
      (validate-eest-trie-selector-list '("")))
    (signals error
      (validate-eest-trie-selector-list '("bare-case-name")))
    (signals error
      (validate-eest-trie-selector-list '("../escape.json")))
    (signals error
      (validate-eest-trie-selector-list '("/absolute.json")))
    (signals error
      (validate-eest-trie-selector-list '("dir//case.json")))
    (signals error
      (validate-eest-trie-selector-list '(".json/case")))
    (signals error
      (validate-eest-trie-selector-list '("dir/.json/case")))
    (signals error
      (validate-eest-trie-selector-list '("case.jsonx/name")))
    (signals error
      (validate-eest-trie-selector-list '("case.json/")))
    (signals error
      (validate-eest-trie-selector-list '("case.json//name")))
    (signals error
      (validate-eest-trie-selector-list '("case.json/name/extra")))
    (signals error
      (validate-eest-trie-selector-list
       '("phase-a-trie-sample.json" "phase-a-trie-sample.json")))
    (signals error
      (validate-eest-trie-test-root-case-names
       (append cases (list (first cases)))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (second cases)
        (third cases)
        (fourth cases)
        (sixth cases)
        (seventh cases)
        (eighth cases)
        (ninth cases)
        (tenth cases)
        (nth 10 cases)
        (nth 11 cases)
        (nth 12 cases)
        (nth 13 cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list (first cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (normalize-eest-trie-test-case
         "secure-empty"
         (list (cons "in" nil)
               (cons "secure" t)
               (cons "root"
                     "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")))
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (eighth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (seventh cases)
        (eighth cases)
        (ninth cases)
        (tenth cases)
        (nth 10 cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (sixth cases)
        (eighth cases)
        (ninth cases)
        (tenth cases)
        (nth 10 cases)
        (nth 11 cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (sixth cases)
        (eighth cases)
        (ninth cases)
        (tenth cases)
        (nth 10 cases)
        (nth 11 cases)
        (nth 12 cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (sixth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (sixth cases)
        (seventh cases)
        (eighth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (third cases)
        (fifth cases)
        (seventh cases)
        (eighth cases)
        (tenth cases))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (second cases)
        (normalize-eest-trie-test-case
         "plain-delete-only"
         (list (cons "in" (list (list "dog" nil)))
               (cons "root"
                     "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"))))))
    (signals error
      (validate-phase-a-eest-trie-test-coverage
       (list
        (first cases)
        (normalize-eest-trie-test-case
         "plain-write-only"
         (list (cons "in" (list (list "dog" "puppy")))
               (cons "root"
                     "ed6e08740e4a267eca9d4740f71f573e9aabbcc739b16a2fa6c1baed5ec21278"))))))))

