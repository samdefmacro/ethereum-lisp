(in-package #:ethereum-lisp.test)

(deftest optional-phase-a-eest-trie-test-root-vectors
  (with-execution-spec-tests-trie-test-root (root)
    (dolist (case (load-phase-a-eest-trie-test-root-cases root))
      (assert-eest-trie-test-case-root case))))

(deftest trie-fixture-vectors
  (let* ((fixture (parse-json
                   (fixture-file-string +trie-vector-fixture-path+)))
         (cases (fixture-object-field fixture "cases")))
    (validate-trie-fixture-metadata fixture)
    (validate-trie-fixture-cases cases)
    (validate-trie-fixture-required-case-names cases)
    (dolist (case cases)
      (multiple-value-bind (trie roots)
          (run-trie-fixture-case-with-root-history case)
        (assert-trie-fixture-intermediate-roots roots case)
        (is (string= (fixture-object-field case "expectedRoot")
                     (mpt-root-hex trie)))
        (is (string= (fixture-object-field case "expectedShape")
                     (trie-fixture-root-shape trie)))
        (let ((reference-kind
                (fixture-object-field case "expectedChildReference")))
          (when reference-kind
            (is (string= reference-kind
                         (trie-fixture-extension-child-reference-kind
                          trie)))))
        (let ((children
                (fixture-object-field case "expectedRootChildren")))
          (when children
            (is (equal children
                       (trie-fixture-root-children trie)))))
        (let ((child-references
                (fixture-object-field case "expectedRootChildReferences")))
          (when child-references
            (dolist (expected child-references)
              (is (string=
                   (cdr expected)
                   (trie-fixture-root-child-reference-kind
                    trie
                    (parse-integer (car expected))))))))
        (let ((child-shapes
                (fixture-object-field case "expectedRootChildShapes")))
          (when child-shapes
            (dolist (expected child-shapes)
              (is (string=
                   (cdr expected)
                   (trie-fixture-root-child-shape
                    trie
                    (parse-integer (car expected))))))))
        (let ((path-nibbles
                (fixture-object-field case "expectedRootPathNibbles")))
          (when path-nibbles
            (is (equal path-nibbles
                       (trie-fixture-root-path-nibbles trie)))))
        (let ((branch-value
                (fixture-object-field case "expectedRootValueAscii")))
          (when branch-value
            (is (string= branch-value
                         (trie-fixture-root-value trie)))))
        (let ((branch-value
                (fixture-object-field case "expectedRootValueHex")))
          (when branch-value
            (is (string= branch-value
                         (bytes-to-hex
                          (trie-fixture-root-value-bytes trie))))))
        (assert-trie-fixture-final-operation-lookups trie case)
        (assert-trie-fixture-entry-pair-replay trie case)
        (assert-trie-fixture-entry-ranges trie case)
        (assert-trie-fixture-proof-prefixes trie case)
        (assert-trie-fixture-lookups trie case)))))
