(in-package #:ethereum-lisp.test)

(deftest phase-a-drift-map-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-drift-map.lisp"
                stdout))
    (is (search "--suite SUITE" stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--state-prefix PREFIX" stdout))
    (is (search "--transaction-prefix PREFIX" stdout))
    (is (search "--blockchain-prefix PREFIX" stdout))
    (is (search "--state-limit NUMBER" stdout))
    (is (search "--transaction-limit NUMBER" stdout))
    (is (search "--blockchain-limit NUMBER" stdout))
    (is (search "--summary-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "out-of-scope-fork-feature" stdout))))

(deftest phase-a-drift-map-script-json-summarizes-suites
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--limit"
             "1"
             "--failures-only"
             "--summary-only"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (overall (fixture-object-field report "overall"))
             (suites (fixture-object-field report "suites")))
        (is (string= "phase-a-drift-map"
                     (fixture-object-field report "mode")))
        (is (eq t (fixture-object-field report "failuresOnly")))
        (is (eq t (fixture-object-field report "summaryOnly")))
        (is (= 3 (length suites)))
        (is (= 3 (fixture-object-field overall "suiteCount")))
        (is (= 3 (fixture-object-field overall "candidateCount")))
        (is (= 3 (fixture-object-field overall "classifiedCount")))
        (is (= 0
               (fixture-object-field
                overall
                "knownImplementationDriftCount")))
        (is (= 0
               (fixture-object-field
                overall
                "fixtureHarnessErrorCount")))
        (is (eq t (fixture-object-field
                   overall
                   "phaseAMaterializableClear")))
        (dolist (suite suites)
          (is (member (fixture-object-field suite "suite")
                      '("state" "transaction" "blockchain")
                      :test #'string=))
          (is (string= "" (fixture-object-field suite "prefix")))
          (is (= 1 (fixture-object-field suite "candidateCount")))
          (is (= 1 (fixture-object-field suite "classifiedCount")))
          (is (= 0 (fixture-object-field
                    suite
                    "knownImplementationDriftCount")))
          (is (fixture-object-field suite "families"))
          (is (null (fixture-object-field suite "results"))))
        (let* ((transaction-suite
                 (find "transaction" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=))
               (transaction-family
                 (first (fixture-object-field transaction-suite "families"))))
          (is (= 1
                 (fixture-object-field transaction-family
                                       "outOfScopeForkFeatureCount")))
          (is (null (fixture-object-field transaction-family
                                          "outOfScopeCount"))))))))

(deftest phase-a-drift-map-script-json-filters-suite
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--suite"
             "transaction"
             "--limit"
             "1"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (overall (fixture-object-field report "overall"))
             (suites (fixture-object-field report "suites"))
             (suite (first suites)))
        (is (string= "transaction" (fixture-object-field report "suite")))
        (is (= 1 (length suites)))
        (is (= 1 (fixture-object-field overall "suiteCount")))
        (is (= 1 (fixture-object-field overall "candidateCount")))
        (is (= 1 (fixture-object-field overall "classifiedCount")))
        (is (string= "transaction"
                     (fixture-object-field suite "suite")))
        (is (= 1 (fixture-object-field suite "candidateCount")))
        (is (= 1 (fixture-object-field suite "classifiedCount")))))))

(deftest phase-a-drift-map-script-accepts-assigned-options
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (let ((root "tests/fixtures/execution-spec-tests-root/"))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "sbcl"
               "--script"
               "scripts/phase-a-drift-map.lisp"
               "--"
               (format nil "--root=~A" root)
               "--limit=1"
               "--state-prefix=london/phase-a-state-sample.json/phase_a_london_access_list"
               "--transaction-prefix=prague/eip7702_set_code_tx/test_empty_authorization_list"
               "--blockchain-prefix=shanghai/phase-a-empty-engine"
               "--failures-only=true"
               "--summary-only=true"
               "--json=1")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (overall (fixture-object-field report "overall"))
               (suites (fixture-object-field report "suites"))
               (state-suite
                 (find "state" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=))
               (transaction-suite
                 (find "transaction" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=))
               (blockchain-suite
                 (find "blockchain" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=)))
          (is (string= "phase-a-drift-map"
                       (fixture-object-field report "mode")))
          (is (string= root (fixture-object-field report "root")))
          (is (eq t (fixture-object-field report "failuresOnly")))
          (is (eq t (fixture-object-field report "summaryOnly")))
          (is (string= "london/phase-a-state-sample.json/phase_a_london_access_list"
                       (fixture-object-field state-suite "prefix")))
          (is (string= "prague/eip7702_set_code_tx/test_empty_authorization_list"
                       (fixture-object-field transaction-suite "prefix")))
          (is (string= "shanghai/phase-a-empty-engine"
                       (fixture-object-field blockchain-suite "prefix")))
          (is (= 3 (fixture-object-field overall "classifiedCount"))))))))

(deftest phase-a-drift-map-script-rejects-malformed-boolean-assignment
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--json=maybe")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--json boolean value must be true or false" stderr))))

(deftest phase-a-drift-map-script-rejects-unknown-suite
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--suite=receipts"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--suite requires state, transaction, or blockchain" stderr))))
