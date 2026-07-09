(in-package #:ethereum-lisp.test)

(deftest optional-eest-transaction-test-root-vectors
  (with-execution-spec-tests-transaction-test-root (root)
    (let* ((vectors (load-phase-a-eest-transaction-test-root-vectors root))
           (summary (transaction-fixture-vector-summary vectors)))
      (is (< 0 (fixture-object-field summary "count")))
      (is (< 0 (length (fixture-object-field summary "types")))))))

(deftest transaction-envelope-fixture-vectors
  (let ((vectors (load-transaction-envelope-vectors
                  +transaction-envelope-fixture-path+)))
    (is (equal vectors
               (validate-transaction-fixture-required-vector-types
                vectors
                +transaction-envelope-fixture-pinned-valid-vector-types+
                "Transaction fixture pinned valid vectors")))
    (signals error
      (validate-transaction-envelope-vector-coverage
       (remove "eip4844-blob"
               vectors
               :test #'string=
               :key (lambda (candidate)
                      (fixture-object-field candidate "name")))))
    (signals error
      (validate-transaction-fixture-required-vector-types
       vectors
       '(("eip1559-pinned-blockchain-valid" . :blob))
       "Transaction fixture pinned valid vectors"))
    (assert-transaction-fixture-vectors-replay vectors)))
