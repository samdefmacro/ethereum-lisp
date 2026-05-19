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
    (is (null (execution-spec-tests-fixture-root)))))

(deftest optional-execution-spec-tests-fixtures-skip-cleanly
  (let ((*fixture-root-environment-reader*
          (lambda (name)
            (declare (ignore name))
            nil)))
    (signals test-skipped
      (with-execution-spec-tests-fixture-root (root)
        (error "Fixture body should not run when the root is absent: ~S"
               root)))))
