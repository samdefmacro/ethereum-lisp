(in-package #:ethereum-lisp.test)

(deftest phase-a-fixture-report-includes-reference-client-pins
  #-sbcl
  (skip-test "Phase A fixture report script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--json"
             "--root"
             "tests/fixtures/execution-spec-tests-root/")
       :output :string
       :error-output :string
       :ignore-error-status t)
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
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-phase-a-smoke-equals-root"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               "-u"
               "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--json=true"
               "--devnet=false"
               "--drift-map=false"
               "--pinned-v5.4.0=false"
               (format nil "--root=~A" root-string))
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Phase A smoke gate requires an EEST state_tests root under"
                  stderr))
      (is (not (search "Unsupported smoke gate option" stderr))))))

(deftest phase-a-smoke-gate-script-rejects-malformed-boolean-assignment
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--devnet=maybe")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--devnet boolean value must be true or false" stderr))))

(deftest phase-a-fixture-report-pinned-mode-requires-root
  #-sbcl
  (skip-test "Phase A fixture report pinned mode requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "env"
             "-u"
             "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
             "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--pinned-v5.4.0"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Pinned Phase A fixture report requires an EEST fixture root"
                stderr))
    (is (search "--root" stderr))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stderr))
    (is (not (search "do not match pinned selectors" stderr)))))

(deftest phase-a-fixture-report-pinned-mode-rejects-missing-env-root
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
        (uiop:run-program
         (list "env"
               (format nil "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                       root-string)
               "sbcl"
               "--script"
               "scripts/phase-a-fixture-report.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Pinned Phase A fixture report root from" stderr))
      (is (not (search "do not match pinned selectors" stderr))))))

(deftest phase-a-selector-scripts-accept-root-option
  #-sbcl
  (skip-test "Phase A selector scripts require SBCL")
  #+sbcl
  (labels ((run-selector-script (script)
             (multiple-value-bind (stdout stderr status)
                 (uiop:run-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--json"
                        "--root"
                        "tests/fixtures/execution-spec-tests-root/")
                  :output :string
                  :error-output :string
                  :ignore-error-status t)
               (is (= 0 status))
               (is (string= "" stderr))
               (when (= 0 status)
                 (let ((report (parse-json stdout)))
                   (is (search "tests/fixtures/execution-spec-tests-root/"
                               (fixture-object-field report "root")))
                   (is (plusp (fixture-object-field report "count"))))))))
    (run-selector-script "scripts/list-state-test-selectors.lisp")
    (run-selector-script "scripts/list-transaction-test-selectors.lisp")
    (run-selector-script "scripts/list-blockchain-replay-selectors.lisp")))

(deftest phase-a-fixture-sync-scripts-reject-missing-env-root
  #-sbcl
  (skip-test "Phase A fixture sync scripts require SBCL")
  #+sbcl
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
    (labels ((run-script-with-missing-env-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          (format nil
                                  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                                  env-root-string)
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json")
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search env-root-string stderr))
                 (is (search "Configured EEST fixture root from" stderr))
                 (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                             stderr))))
             (run-script-with-missing-explicit-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          "-u"
                          "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json"
                          "--root"
                          explicit-root-string)
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search explicit-root-string stderr))
                 (is (search "Configured EEST fixture root from" stderr))
                 (is (search "--root" stderr)))))
      (dolist (script
               '("scripts/phase-a-fixture-report.lisp"
                 "scripts/classify-state-test-selectors.lisp"
                 "scripts/classify-transaction-test-selectors.lisp"
                 "scripts/list-state-test-selectors.lisp"
                 "scripts/list-transaction-test-selectors.lisp"
                 "scripts/list-blockchain-replay-selectors.lisp"))
        (run-script-with-missing-env-root script)
        (run-script-with-missing-explicit-root script)))))

(deftest phase-a-fixture-sync-scripts-reject-empty-suite-root
  #-sbcl
  (skip-test "Phase A fixture sync scripts require SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-empty-fixture-sync-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (dolist (subdir '("state_tests/"
                      "transaction_tests/"
                      "blockchain_tests_engine/"))
      (ensure-directories-exist (merge-pathnames subdir root)))
    (labels ((run-script-with-empty-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          "-u"
                          "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                          "sbcl"
                          "--script"
                          script
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
      (dolist (script
               '("scripts/phase-a-fixture-report.lisp"
                 "scripts/phase-a-smoke-gate.lisp"
                 "scripts/classify-state-test-selectors.lisp"
                 "scripts/classify-transaction-test-selectors.lisp"
                 "scripts/list-state-test-selectors.lisp"
                 "scripts/list-transaction-test-selectors.lisp"
                 "scripts/list-blockchain-replay-selectors.lisp"))
        (run-script-with-empty-root script)))))

