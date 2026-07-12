(in-package #:ethereum-lisp.test)

(deftest blockchain-replay-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-blockchain-replay-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-blockchain-replay-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "--failures-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest blockchain-replay-classifier-script-json-summarizes-families
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (run-classifier-application
       :blockchain
       (list "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "shanghai/phase-a"
             "--limit"
             "2"
             "--json"))
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-blockchain-replay-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (family families)
          (is (= 0 (fixture-object-field
                    family
                    "knownImplementationDriftCount"))))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest blockchain-replay-classifier-script-json-filters-passing-results
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (run-classifier-application
       :blockchain
       (list "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "shanghai/phase-a"
             "--limit"
             "2"
             "--failures-only"
             "--json"))
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (eq t (fixture-object-field report "failuresOnly")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (length results)))
        (is (plusp (length families)))))))

(deftest transaction-test-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Transaction test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-transaction-test-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-transaction-test-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "--failures-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest transaction-test-classifier-script-json-summarizes-families
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Transaction test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (run-classifier-application
       :transaction
       (list "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "phase-a-sample.json"
             "--limit"
             "2"
             "--include-pinned"
             "--json"))
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-transaction-test-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (family families)
          (is (= 0 (fixture-object-field
                    family
                    "knownImplementationDriftCount"))))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest transaction-test-classifier-script-json-classifies-prague-out-of-scope
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Transaction test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (run-classifier-application
       :transaction
       (list "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "prague/eip7702_set_code_tx/test_empty_authorization_list.json"
             "--limit"
             "1"
             "--json"))
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families"))
             (result (first results)))
        (is (string= "unpinned-transaction-test-classification"
                     (fixture-object-field report "mode")))
        (is (= 1 (fixture-object-field report "classifiedCount")))
        (is (= 0 (fixture-object-field report "passingCount")))
        (is (= 1 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 1 (fixture-object-field
                  report
                  "outOfScopeForkFeatureCount")))
        (is (= 1 (length families)))
        (is (string= "out-of-scope-fork-feature"
                     (fixture-object-field result "classification")))
        (is (search "Prague/EIP-7702"
                    (fixture-object-field result "error")))))))

(deftest state-test-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "State test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-state-test-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-state-test-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "--failures-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest state-test-classifier-script-json-summarizes-families
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "State test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (run-classifier-application
       :state
       (list "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "london/phase-a"
             "--limit"
             "2"
             "--json"))
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-state-test-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (family families)
          (is (= 0 (fixture-object-field
                    family
                    "knownImplementationDriftCount"))))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest state-test-classifier-script-json-filters-passing-results
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "State test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (run-classifier-application
       :state
       (list "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "london/phase-a"
             "--limit"
             "2"
             "--failures-only"
             "--json"))
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (eq t (fixture-object-field report "failuresOnly")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (length results)))
        (is (plusp (length families)))))))

(deftest classifier-scripts-accept-assigned-options
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Fixture classifier scripts require SBCL")
  #+sbcl
  (labels ((run-classifier (suite prefix &key include-pinned)
             (let ((args
                     (append
                      (list "--root=tests/fixtures/execution-spec-tests-root/"
                            (format nil "--prefix=~A" prefix)
                            "--limit=1"
                            "--json=true"
                            "--failures-only=false")
                      (when include-pinned
                        (list "--include-pinned=true")))))
               (multiple-value-bind (stdout stderr status)
                   (run-classifier-application suite args)
                 (is (= 0 status))
                 (is (string= "" stderr))
                 (when (= 0 status)
                   (let ((report (parse-json stdout)))
                     (is (= 1 (fixture-object-field report "classifiedCount")))
                     (is (= 1 (fixture-object-field report "candidateCount")))
                     (is (= 1 (fixture-object-field report "passingCount")))
                     (is (= 0 (fixture-object-field report "failingCount")))
                     (is (not (fixture-object-field report "failuresOnly")))
                     (is (string= prefix
                                  (fixture-object-field report "prefix")))
                     report))))))
    (run-classifier
     :blockchain
     "shanghai/phase-a")
    (let ((transaction-report
            (run-classifier
             :transaction
             "phase-a-sample.json"
             :include-pinned t)))
      (is (eq t (fixture-object-field transaction-report "includePinned"))))
    (run-classifier
     :state
     "london/phase-a")))
