(in-package #:ethereum-lisp.test)

(deftest execution-spec-tests-fixture-root-discovers-existing-directory
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (declare (ignore name))
            "tests/")))
    (let ((root (execution-spec-tests-fixture-root)))
      (is root)
      (is (probe-file root)))))

(deftest execution-spec-tests-fixture-root-ignores-empty-or-missing-values
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (declare (ignore name))
            "")))
    (is (null (execution-spec-tests-fixture-root))))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (declare (ignore name))
            "tests/no-such-fixture-root/")))
    (is (null (execution-spec-tests-fixture-root))))
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (declare (ignore name))
            42)))
    (signals error
      (execution-spec-tests-fixture-root))))

(deftest optional-execution-spec-tests-fixtures-skip-cleanly
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (declare (ignore name))
            nil)))
    (signals test-skipped
      (with-execution-spec-tests-fixture-root (root)
        (error "Fixture body should not run when the root is absent: ~S"
               root)))))

(deftest execution-spec-tests-transaction-root-discovers-known-layouts
  (let ((direct-root (probe-file "tests/fixtures/execution-spec-tests-root/"))
        (fixtures-root
          (probe-file "tests/fixtures/execution-spec-tests-root/fixtures/"))
        (geth-root (probe-file "tests/fixtures/geth-spec-tests-root/")))
    (is (execution-spec-tests-transaction-test-root direct-root))
    (is (execution-spec-tests-transaction-test-root fixtures-root))
    (is (execution-spec-tests-transaction-test-root geth-root))))

(deftest execution-spec-tests-suite-roots-accept-directory-strings
  (let ((direct-root "tests/fixtures/execution-spec-tests-root")
        (fixtures-root "tests/fixtures/execution-spec-tests-root/fixtures"))
    (is (execution-spec-tests-transaction-test-root direct-root))
    (is (execution-spec-tests-transaction-test-root fixtures-root))
    (is (execution-spec-tests-blockchain-test-root direct-root))
    (is (execution-spec-tests-blockchain-test-root fixtures-root))
    (is (execution-spec-tests-state-test-root direct-root))
    (is (execution-spec-tests-state-test-root fixtures-root))
    (is (execution-spec-tests-trie-test-root direct-root))
    (is (execution-spec-tests-trie-test-root fixtures-root))))

(deftest execution-spec-tests-transaction-root-ignores-missing-layout
  (is (null (execution-spec-tests-transaction-test-root
             (probe-file "tests/fixtures/execution-spec-tests/")))))

(deftest execution-spec-tests-blockchain-root-discovers-known-layouts
  (let ((direct-root (probe-file "tests/fixtures/execution-spec-tests-root/"))
        (fixtures-root
          (probe-file "tests/fixtures/execution-spec-tests-root/fixtures/"))
        (geth-root (probe-file "tests/fixtures/geth-spec-tests-root/")))
    (is (execution-spec-tests-blockchain-test-root direct-root))
    (is (execution-spec-tests-blockchain-test-root fixtures-root))
    (is (execution-spec-tests-blockchain-test-root geth-root))))

(deftest execution-spec-tests-blockchain-root-prefers-engine-layout
  (let ((direct-root (probe-file "tests/fixtures/execution-spec-tests-root/")))
    (is (search "blockchain_tests_engine"
                (namestring
                 (execution-spec-tests-blockchain-test-root direct-root))))))

(deftest execution-spec-tests-blockchain-root-ignores-missing-layout
  (is (null (execution-spec-tests-blockchain-test-root
             (probe-file "tests/fixtures/execution-spec-tests/")))))

(deftest execution-spec-tests-state-root-discovers-known-layouts
  (let ((direct-root (probe-file "tests/fixtures/execution-spec-tests-root/"))
        (fixtures-root
          (probe-file "tests/fixtures/execution-spec-tests-root/fixtures/")))
    (is (execution-spec-tests-state-test-root direct-root))
    (is (execution-spec-tests-state-test-root fixtures-root))))

(deftest execution-spec-tests-state-root-ignores-missing-layout
  (is (null (execution-spec-tests-state-test-root
             (probe-file "tests/fixtures/execution-spec-tests/")))))

(deftest execution-spec-tests-trie-root-discovers-known-layouts
  (let ((direct-root (probe-file "tests/fixtures/execution-spec-tests-root/"))
        (fixtures-root
          (probe-file "tests/fixtures/execution-spec-tests-root/fixtures/"))
        (geth-root (probe-file "tests/fixtures/geth-spec-tests-root/")))
    (is (execution-spec-tests-trie-test-root direct-root))
    (is (execution-spec-tests-trie-test-root fixtures-root))
    (is (execution-spec-tests-trie-test-root geth-root))))

(deftest execution-spec-tests-trie-root-ignores-missing-layout
  (is (null (execution-spec-tests-trie-test-root
             (probe-file "tests/fixtures/execution-spec-tests/")))))

(deftest optional-execution-spec-tests-trie-fixtures-skip-cleanly
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (declare (ignore name))
            nil)))
    (signals test-skipped
      (with-execution-spec-tests-trie-test-root (root)
        (error "Trie fixture body should not run when the root is absent: ~S"
               root)))))

(deftest optional-execution-spec-tests-state-fixtures-skip-cleanly
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (declare (ignore name))
            nil)))
    (signals test-skipped
      (with-execution-spec-tests-state-test-root (root)
        (error "State fixture body should not run when the root is absent: ~S"
               root)))))

(deftest optional-execution-spec-tests-blockchain-fixtures-skip-cleanly
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (declare (ignore name))
            nil)))
    (signals test-skipped
      (with-execution-spec-tests-blockchain-test-root (root)
        (error "Blockchain fixture body should not run when the root is absent: ~S"
               root)))))

(deftest fixture-format-validation-rejects-non-string-values
  (validate-fixture-format
   (list (cons "format" "ethereum-lisp:test"))
   "ethereum-lisp:test")
  (signals error
    (validate-fixture-format
     (list (cons "format" 42))
     "ethereum-lisp:test")))

(deftest pinned-execution-spec-tests-source-validation
  (flet ((fixture (source)
           (list (cons "executionSpecTests" source))))
    (validate-fixture-pinned-eest-source
     (fixture
      (list (cons "release" +phase-a-eest-release+)
            (cons "tagTarget" +phase-a-eest-tag-target+)
            (cons "archive" +phase-a-eest-archive+)
            (cons "status" "seed"))))
    (signals error
      (validate-fixture-pinned-eest-source
       (fixture
        (list (cons "release" +phase-a-eest-release+)
              (cons "tagTarget" +phase-a-eest-tag-target+)
              (cons "archive" +phase-a-eest-archive+)
              (cons "status" "seed")
              (cons "unexpected" t)))))
    (signals error
      (validate-fixture-pinned-eest-source
       (fixture
        (list (cons "release" +phase-a-eest-release+)
              (cons "tagTarget" +phase-a-eest-tag-target+)
              (cons "archive" +phase-a-eest-archive+)
              (cons "status" "seed")
              (cons 42 t)))))
    (signals error
      (validate-fixture-pinned-eest-source
       (fixture
        (list (cons "release" +phase-a-eest-release+)
              (cons "release" "duplicate release")
              (cons "tagTarget" +phase-a-eest-tag-target+)
              (cons "archive" +phase-a-eest-archive+)
              (cons "status" "seed")))))
    (signals error
      (validate-fixture-pinned-eest-source
       (fixture
        (list (cons "release" 42)
              (cons "tagTarget" +phase-a-eest-tag-target+)
              (cons "archive" +phase-a-eest-archive+)
              (cons "status" "seed")))))
    (signals error
      (validate-fixture-pinned-eest-source
       (fixture
        (list (cons "release" +phase-a-eest-release+)
              (cons "tagTarget" 42)
              (cons "archive" +phase-a-eest-archive+)
              (cons "status" "seed")))))
    (signals error
      (validate-fixture-pinned-eest-source
       (fixture
        (list (cons "release" +phase-a-eest-release+)
              (cons "tagTarget" +phase-a-eest-tag-target+)
              (cons "archive" 42)
              (cons "status" "seed")))))
    (signals error
      (validate-fixture-pinned-eest-source
       (fixture
        (list (cons "release" +phase-a-eest-release+)
              (cons "tagTarget" +phase-a-eest-tag-target+)
              (cons "archive" +phase-a-eest-archive+)
              (cons "status" 42)))))))
