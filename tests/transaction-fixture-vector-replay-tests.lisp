(in-package #:ethereum-lisp.test)

;; The root here comes from the environment, so it is whatever corpus the caller
;; pinned -- in CI, execution-spec-tests v5.4.0. Selection MUST therefore be by
;; discovery. The phase-a and full loaders select by
;; +phase-a-eest-transaction-test-case-names+, whose every entry names a case in
;; the in-tree tests/fixtures/.../phase-a-sample.json, and their summary
;; validators additionally assert the loaded names EQUAL that list; against any
;; real corpus they fail with "selector ... did not match any loaded case", which
;; is what they did on the first CI run that reached this test. Those pinned
;; lists are exercised against the sample root by
;; EEST-TRANSACTION-TEST-ROOT-VECTOR-LOADING, which passes that root explicitly.
;; This test covers the other half: an arbitrary corpus loads, normalizes, and
;; validates as a vector set. It does not replay them -- see docs/gap-analysis.
(deftest optional-eest-transaction-test-root-vectors
  (with-execution-spec-tests-transaction-test-root (root)
    (let* ((vectors (load-eest-transaction-test-root-vectors root))
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
