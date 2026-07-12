(in-package #:ethereum-lisp.test)

(deftest phase-a-fixture-report-includes-reference-client-pins
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Phase A fixture report script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (run-fixture-report-application
       (list "--json"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"))
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (reference-clients
               (fixture-object-field report "referenceClients")))
        (phase-a-smoke-gate-assert-execution-spec-tests-source report)
        (is (= 3 (length reference-clients)))
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "geth")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "nethermind")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "reth")))))

(deftest phase-a-report-scripts-honor-reference-client-root-env
  (:estimated-seconds 17d0)
  #-sbcl
  (skip-test "Phase A report scripts require SBCL")
  #+sbcl
  (let* ((token (format nil "~A-~A" (sb-unix:unix-getpid) (gensym)))
         (geth-root
           (format nil "/private/tmp/ethereum-lisp-geth-root-~A/" token))
         (nethermind-root
           (format nil "/private/tmp/ethereum-lisp-nethermind-root-~A/"
                   token))
         (reth-root
           (format nil "/private/tmp/ethereum-lisp-reth-root-~A/" token))
         (environment
           (list
            (format nil "ETHEREUM_LISP_GETH_ROOT=~A" geth-root)
            (format nil "ETHEREUM_LISP_NETHERMIND_ROOT=~A"
                    nethermind-root)
            (format nil "ETHEREUM_LISP_RETH_ROOT=~A" reth-root))))
    (labels ((run-report (script &rest extra-args)
               (uiop:run-program
                (append
                 (list "env")
                 environment
                 (list "sbcl" "--script" script "--")
                 extra-args)
                :output :string
                :error-output :string
                :ignore-error-status t))
             (assert-reference-roots (report)
               (let ((reference-clients
                       (fixture-object-field report "referenceClients")))
                 (is (= 3 (length reference-clients)))
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "geth" geth-root)
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "nethermind" nethermind-root)
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "reth" reth-root)
                 (dolist (name '("geth" "nethermind" "reth"))
                   (phase-a-smoke-gate-assert-reference-client
                    reference-clients name)))))
      (multiple-value-bind (stdout stderr status)
          (run-report
           "scripts/phase-a-fixture-report.lisp"
           "--json"
           "--root"
           "tests/fixtures/execution-spec-tests-root/")
        (is (= 0 status))
        (is (string= "" stderr))
        (when (= 0 status)
          (assert-reference-roots (parse-json stdout))))
      (multiple-value-bind (stdout stderr status)
          (run-report
           "scripts/phase-a-smoke-gate.lisp"
           "--json"
           "--root"
           "tests/fixtures/execution-spec-tests-root/")
        (is (= 0 status))
        (is (string= "" stderr))
        (when (= 0 status)
          (assert-reference-roots (parse-json stdout)))))))

(deftest phase-a-fixture-report-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Phase A fixture report script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-fixture-report.lisp"
                stdout))
    (is (search "--root PATH" stdout))
    (is (search "--pinned-v5.4.0" stdout))
    (is (search "--json" stdout))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest phase-a-smoke-gate-help-prints-reference-root-env
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-smoke-gate.lisp"
                stdout))
    (is (search "--root PATH" stdout))
    (is (search "--pinned-v5.4.0" stdout))
    (is (search "--devnet" stdout))
    (is (search "--drift-map" stdout))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest phase-a-smoke-gate-script-accepts-geth-style-option-values
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-phase-a-smoke-equals-root"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (run-smoke-gate-application
         (list
               "--json=true"
               "--devnet=false"
               "--drift-map=false"
               "--pinned-v5.4.0=false"
               (format nil "--root=~A" root-string))
         :environment-lookup (lambda (name) (declare (ignore name)) nil))
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Phase A smoke gate requires an EEST state_tests root under"
                  stderr))
      (is (not (search "Unsupported smoke gate option" stderr))))))

(deftest phase-a-smoke-gate-script-rejects-malformed-boolean-assignment
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (run-smoke-gate-application (list "--devnet=maybe"))
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--devnet boolean value must be true or false" stderr))))

(deftest phase-a-fixture-report-pinned-mode-requires-root
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Phase A fixture report pinned mode requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (run-fixture-report-application
       (list "--pinned-v5.4.0" "--json")
       :environment-lookup (lambda (name) (declare (ignore name)) nil))
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Pinned Phase A fixture report requires an EEST fixture root"
                stderr))
    (is (search "--root" stderr))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stderr))
    (is (not (search "do not match pinned selectors" stderr)))))

(deftest phase-a-fixture-report-pinned-mode-rejects-missing-env-root
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Phase A fixture report pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-pinned-report-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (run-fixture-report-application
         (list "--pinned-v5.4.0" "--json")
         :environment-lookup
         (lambda (name)
           (if (string= name "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")
               root-string
               nil)))
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Pinned Phase A fixture report root from" stderr))
      (is (not (search "do not match pinned selectors" stderr))))))

(deftest phase-a-selector-scripts-accept-root-option
  (:layer :integration :module :fixture-cli :launches-processes nil)
  #-sbcl
  (skip-test "Phase A selector scripts require SBCL")
  #+sbcl
  (labels ((run-selector-script (kind)
             (multiple-value-bind (stdout stderr status)
                 (run-selector-application
                  kind
                  (list "--json"
                        "--root"
                        "tests/fixtures/execution-spec-tests-root/"))
               (is (= 0 status))
               (is (string= "" stderr))
               (when (= 0 status)
                 (let ((report (parse-json stdout)))
                   (is (search "tests/fixtures/execution-spec-tests-root/"
                               (fixture-object-field report "root")))
                   (is (plusp (fixture-object-field report "count"))))))))
    (run-selector-script :state)
    (run-selector-script :transaction)
    (run-selector-script :blockchain)))

(deftest phase-a-fixture-sync-scripts-reject-missing-env-root
  (:layer :unit :module :fixture-cli :launches-processes nil)
  (let* ((env-root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-fixture-sync-env-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (env-root-string (namestring env-root))
         (explicit-root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-fixture-sync-explicit-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (explicit-root-string (namestring explicit-root)))
    (labels ((run-validation (root-argument environment-value)
               (let ((stdout (make-string-output-stream))
                     (stderr (make-string-output-stream)))
                 (let ((status
                         (ethereum-lisp.fixture-root-application:call-with-validation-result
                          (lambda (output error-output)
                            (declare (ignore output error-output))
                            (ethereum-lisp.fixture-root-application:validate-configured-root
                             root-argument
                             :environment-lookup
                             (lambda (name)
                               (declare (ignore name))
                               environment-value)
                             :probe (lambda (path)
                                      (declare (ignore path))
                                      nil)))
                          :output stdout
                          :error-output stderr)))
                   (values (get-output-stream-string stdout)
                           (get-output-stream-string stderr)
                           status)))))
      (multiple-value-bind (stdout stderr status)
          (run-validation nil env-root-string)
        (is (= 1 status))
        (is (string= "" stdout))
        (is (search env-root-string stderr))
        (is (search "Configured EEST fixture root from" stderr))
        (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stderr)))
      (multiple-value-bind (stdout stderr status)
          (run-validation explicit-root-string nil)
        (is (= 1 status))
        (is (string= "" stdout))
        (is (search explicit-root-string stderr))
        (is (search "Configured EEST fixture root from" stderr))
        (is (search "--root" stderr))))))

(deftest phase-a-fixture-sync-scripts-reject-empty-suite-root
  (:layer :unit :module :fixture-cli :launches-processes nil)
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-empty-fixture-sync-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (dolist (label '("state_tests" "transaction_tests" "blockchain"))
      (let ((stdout (make-string-output-stream))
            (stderr (make-string-output-stream)))
        (let ((status
                (ethereum-lisp.fixture-root-application:call-with-validation-result
                 (lambda (output error-output)
                   (declare (ignore output error-output))
                   (ethereum-lisp.fixture-root-application:validate-non-empty-root
                    root-string
                    label
                    (lambda (path)
                      (declare (ignore path))
                      nil)))
                 :output stdout
                 :error-output stderr)))
          (is (= 1 status))
          (is (string= "" (get-output-stream-string stdout)))
          (let ((error-text (get-output-stream-string stderr)))
            (is (search root-string error-text))
            (is (search "contains no JSON files" error-text))
            (is (search "Configured EEST" error-text))))))))

(deftest phase-a-smoke-gate-rejects-empty-suite-root-contract
  (:layer :e2e :module :fixture-cli :launches-processes t)
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-empty-smoke-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (dolist (subdir '("state_tests/"
                      "transaction_tests/"
                      "blockchain_tests_engine/"))
      (ensure-directories-exist (merge-pathnames subdir root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               "-u"
               "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--json"
               "--root"
               root-string)
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "contains no JSON files" stderr))
      (is (search "Configured EEST" stderr)))))
