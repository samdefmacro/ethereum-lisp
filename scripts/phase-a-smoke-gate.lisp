(defparameter *ethereum-lisp-smoke-gate-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)

(defconstant +smoke-gate-pinned-v5.4.0-flag+ "--pinned-v5.4.0")
(defconstant +smoke-gate-devnet-flag+ "--devnet")
(defconstant +smoke-gate-json-flag+ "--json")
(defconstant +smoke-gate-root-option+ "--root")
(defconstant +smoke-gate-help-flag+ "--help")
(defconstant +smoke-gate-default-root+
  "tests/fixtures/execution-spec-tests-root/")
(defconstant +smoke-gate-eest-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")
(defconstant +smoke-gate-eest-repository+
  "ethereum/execution-spec-tests")
(defconstant +smoke-gate-eest-release+ "v5.4.0")
(defconstant +smoke-gate-eest-tag-target+ "88e9fb8")
(defconstant +smoke-gate-eest-archive+ "fixtures_stable.tar.gz")

(defun smoke-gate-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun smoke-gate-pinned-v5.4.0-p (args)
  (member +smoke-gate-pinned-v5.4.0-flag+ args :test #'string=))

(defun smoke-gate-devnet-p (args)
  (member +smoke-gate-devnet-flag+ args :test #'string=))

(defun smoke-gate-json-p (args)
  (member +smoke-gate-json-flag+ args :test #'string=))

(defun smoke-gate-help-p (args)
  (member +smoke-gate-help-flag+ args :test #'string=))

(defun smoke-gate-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun smoke-gate-set-argument-root (root value)
  (when root
    (error "Only one fixture root argument is supported"))
  value)

(defun smoke-gate-argument-root (args)
  (let ((root nil))
    (loop while args
          for arg = (pop args)
          do
      (cond
        ((string= arg +smoke-gate-pinned-v5.4.0-flag+))
        ((string= arg +smoke-gate-devnet-flag+))
        ((string= arg +smoke-gate-json-flag+))
        ((string= arg +smoke-gate-help-flag+))
        ((string= arg +smoke-gate-root-option+)
         (unless args
           (error "~A requires a fixture root path" +smoke-gate-root-option+))
         (let ((value (pop args)))
           (when (smoke-gate-option-like-p value)
             (error "~A requires a fixture root path, got option ~A"
                    +smoke-gate-root-option+
                    value))
           (setf root (smoke-gate-set-argument-root root value))))
        ((smoke-gate-option-like-p arg)
         (error "Unsupported smoke gate option ~A" arg))
        (t
         (setf root (smoke-gate-set-argument-root root arg)))))
    root))

(defun smoke-gate-print-help ()
  (format t "~&Usage: sbcl --script scripts/phase-a-smoke-gate.lisp -- [options] [ROOT]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --root PATH        Fixture suite root. Equivalent to positional ROOT.~%")
  (format t "  --pinned-v5.4.0    Validate the pinned EEST v5.4.0 stable archive subset.~%")
  (format t "  --devnet           Also run the devnet listener-boundary all-fixtures gate.~%")
  (format t "  --json             Print machine-readable JSON output.~%")
  (format t "  --help             Print this help without loading the test system.~%")
  (format t "~%")
  (format t "Default ROOT: ~A~%" +smoke-gate-default-root+)
  (format t "Pinned mode requires ROOT or ~A when ROOT is omitted.~%"
          +smoke-gate-eest-root-env+))

(defun smoke-gate-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun smoke-gate-variable (name)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (boundp symbol))
      (error "Fixture variable ~A is unavailable" name))
    (symbol-value symbol)))

(defun smoke-gate-reject-empty-selected-root (root label)
  (when (and root
             (not (smoke-gate-call "execution-spec-tests-json-paths" root)))
    (error "Configured EEST ~A fixture root contains no JSON files: ~A"
           label
           root)))

(defun smoke-gate-pinned-default-root ()
  (let ((root (uiop:getenv +smoke-gate-eest-root-env+)))
    (when (or (null root)
              (zerop (length
                      (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   root))))
      (error "Pinned Phase A smoke gate requires an EEST fixture root via ~A or ~A"
             +smoke-gate-root-option+
             +smoke-gate-eest-root-env+))
    (let ((resolved-root (probe-file root)))
      (unless resolved-root
        (error "Pinned Phase A smoke gate root from ~A does not exist: ~A"
               +smoke-gate-eest-root-env+
               root))
      (namestring resolved-root))))

(defun smoke-gate-suite-root (root-argument pinned-p)
  (or root-argument
      (if pinned-p
          (smoke-gate-pinned-default-root)
          +smoke-gate-default-root+)))

(defun smoke-gate-json-encode (object)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) object)))

(defun smoke-gate-json-decode (string)
  (let ((symbol (find-symbol "PARSE-JSON" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON parser is unavailable"))
    (funcall (symbol-function symbol) string)))

(defun smoke-gate-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun smoke-gate-root-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults *ethereum-lisp-smoke-gate-root*))

(defun smoke-gate-reference-path (relative-path)
  (merge-pathnames relative-path (smoke-gate-root-directory)))

(defun smoke-gate-temp-token ()
  (format nil "~A-~A"
          #+sbcl (sb-unix:unix-getpid)
          #-sbcl "nopid"
          (gensym)))

(defun smoke-gate-temp-path (name type)
  (merge-pathnames
   (make-pathname :name (format nil "~A-~A" name (smoke-gate-temp-token))
                  :type type)
   #P"/private/tmp/"))

(defun smoke-gate-delete-file-if-present (path)
  (when (and path (probe-file path))
    (delete-file path)))

(defun smoke-gate-reference-client-object (name relative-path)
  (let ((path (smoke-gate-reference-path relative-path)))
    (cond
      ((not (probe-file path))
       (list
        (cons "name" name)
        (cons "status" "missing")
        (cons "path" (namestring path))
        (cons "commit" nil)))
      (t
       (multiple-value-bind (stdout stderr status)
           (uiop:run-program
            (list "git" "-C" (namestring path) "rev-parse" "HEAD")
            :output :string
            :error-output :string
            :ignore-error-status t)
         (declare (ignore stderr))
         (if (= 0 status)
             (list
              (cons "name" name)
              (cons "status" "ok")
              (cons "path" (namestring path))
              (cons "commit" (string-trim '(#\Space #\Tab #\Newline #\Return)
                                          stdout)))
             (list
              (cons "name" name)
              (cons "status" "unavailable")
              (cons "path" (namestring path))
              (cons "commit" nil))))))))

(defun smoke-gate-reference-clients ()
  (list
   (smoke-gate-reference-client-object "geth" "references/go-ethereum/")
   (smoke-gate-reference-client-object "nethermind" "references/nethermind/")
   (smoke-gate-reference-client-object "reth" "references/reth/")))

(defun smoke-gate-execution-spec-tests-source ()
  (list
   (cons "repository" +smoke-gate-eest-repository+)
   (cons "release" +smoke-gate-eest-release+)
   (cons "tagTarget" +smoke-gate-eest-tag-target+)
   (cons "archive" +smoke-gate-eest-archive+)))

(defun smoke-gate-kind-count (summary kind)
  (or (smoke-gate-field
       (smoke-gate-field summary "materializationKindCounts")
       kind)
      0))

(defun smoke-gate-require-positive-field (summary field label)
  (let ((value (smoke-gate-field summary field)))
    (unless (and (integerp value) (plusp value))
      (error "~A must be positive, got ~S" label value))
    value))

(defun smoke-gate-execute-state-cases (cases)
  (dolist (case cases)
    (smoke-gate-call "assert-eest-state-test-case" case))
  (length cases))

(defun smoke-gate-execute-transaction-vectors (vectors)
  (smoke-gate-call "assert-transaction-fixture-vectors-replay" vectors)
  (length vectors))

(defun smoke-gate-execute-blockchain-cases (cases)
  (dolist (source-case cases)
    (smoke-gate-call
     "assert-eest-blockchain-engine-newpayload-v2-replay"
     (smoke-gate-call
      "materialize-eest-blockchain-engine-newpayload-v2-case"
      source-case)
     :source-case source-case))
  (length cases))

(defun smoke-gate-state-summary (suite-root required-p)
  (let ((root (smoke-gate-call "execution-spec-tests-state-test-root"
                               suite-root)))
    (cond
      (root
       (smoke-gate-reject-empty-selected-root root "state_tests")
       (let* ((selectors
                (smoke-gate-call
                 "discover-phase-a-eest-state-test-selectors"
                 root))
              (cases
                (smoke-gate-call
                 "load-eest-state-test-root-cases"
                 root
                 :names selectors))
              (summary
                (smoke-gate-call
                 "validate-phase-a-eest-state-test-summary"
                 cases
                 :expected-names selectors))
              (executed (smoke-gate-execute-state-cases cases)))
         (smoke-gate-require-positive-field
          summary "count" "Phase A state_tests count")
         (smoke-gate-require-positive-field
          summary
          "transactionCombinationCount"
          "Phase A state_tests transaction-combination count")
         (list
          (cons "status" "ok")
          (cons "root" (namestring root))
          (cons "count" (smoke-gate-field summary "count"))
          (cons "executedCount" executed)
          (cons "transactionCombinationCount"
                (smoke-gate-field summary "transactionCombinationCount"))
          (cons "selectorString"
                (smoke-gate-call
                 "phase-a-eest-state-test-selector-string"
                 selectors)))))
      (required-p
       (error "Phase A smoke gate requires an EEST state_tests root under ~A"
              suite-root))
      (t
       (list
        (cons "status" "missing")
        (cons "root" nil)
        (cons "count" 0)
        (cons "executedCount" 0)
        (cons "transactionCombinationCount" 0)
        (cons "selectorString" ""))))))

(defun smoke-gate-transaction-summary (suite-root required-p)
  (let ((root (smoke-gate-call
               "execution-spec-tests-transaction-test-root"
               suite-root)))
    (cond
      (root
       (smoke-gate-reject-empty-selected-root root "transaction_tests")
       (let* ((vectors
                (smoke-gate-call
                 "load-phase-a-eest-transaction-test-root-vectors"
                 root))
              (summary
                (smoke-gate-call
                 "validate-phase-a-eest-transaction-vector-summary"
                 vectors))
              (executed
                (smoke-gate-execute-transaction-vectors vectors))
              (selectors
                (smoke-gate-variable
                 "+phase-a-eest-transaction-test-case-names+")))
         (smoke-gate-require-positive-field
          summary "count" "Phase A transaction_tests count")
         (list
          (cons "status" "ok")
          (cons "root" (namestring root))
          (cons "count" (smoke-gate-field summary "count"))
          (cons "executedCount" executed)
          (cons "types" (smoke-gate-field summary "types"))
          (cons "selectorString"
                (smoke-gate-call
                 "phase-a-eest-transaction-test-selector-string"
                 selectors)))))
      (required-p
       (error "Phase A smoke gate requires an EEST transaction_tests root under ~A"
              suite-root))
      (t
       (list
        (cons "status" "missing")
        (cons "root" nil)
        (cons "count" 0)
        (cons "executedCount" 0)
        (cons "types" nil)
        (cons "selectorString" ""))))))

(defun smoke-gate-blockchain-summary (suite-root pinned-p)
  (let ((root (smoke-gate-call
               "execution-spec-tests-blockchain-test-root"
               suite-root)))
    (unless root
      (error "Phase A smoke gate requires an EEST blockchain root under ~A"
             suite-root))
    (smoke-gate-reject-empty-selected-root root "blockchain")
    (let* ((kinds
             (if pinned-p
                 (smoke-gate-call
                  "phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds"
                  root)
                 (smoke-gate-call
                  "discover-phase-a-eest-blockchain-replay-selectors"
                  root)))
           (cases
             (smoke-gate-call
              "load-phase-a-eest-blockchain-replay-cases"
              root
              :expected-kinds kinds))
           (summary
             (smoke-gate-call
              "validate-phase-a-eest-blockchain-replay-summary"
              cases
              :expected-kinds kinds))
           (executed (smoke-gate-execute-blockchain-cases cases)))
      (smoke-gate-require-positive-field
       summary "count" "Phase A blockchain replay count")
      (when (and (not pinned-p)
                 (zerop (smoke-gate-kind-count summary "blockRlp")))
        (error "Phase A in-repo blockchain replay must include blockRlp coverage"))
      (when (zerop (smoke-gate-kind-count summary "engineNewPayloadV2"))
        (error "Phase A blockchain replay must include engineNewPayloadV2 coverage"))
      (list
       (cons "status" "ok")
       (cons "root" (namestring root))
       (cons "count" (smoke-gate-field summary "count"))
       (cons "executedCount" executed)
       (cons "blockCount" (smoke-gate-field summary "blockCount"))
       (cons "kindCounts"
             (smoke-gate-field summary "materializationKindCounts"))
       (cons "selectorString"
             (smoke-gate-call
              "phase-a-eest-blockchain-replay-selector-string"
             kinds))))))

(defun smoke-gate-devnet-case-files (report field)
  (loop for case-report in (or (smoke-gate-field report "cases") nil)
        for path = (smoke-gate-field case-report field)
        when (stringp path)
          collect path))

(defun smoke-gate-devnet-summary ()
  (let ((ready-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-ready"
                                 "json")))
        (log-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet"
                                 "log")))
        (database-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-chain"
                                 "sexp")))
        (report nil))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    (namestring
                     (smoke-gate-reference-path
                      "scripts/devnet-smoke-gate.lisp"))
                    "--"
                    "--json"
                    "--all-fixtures"
                    "--ready-file"
                    ready-file
                    "--log-file"
                    log-file
                    "--database"
                    database-file)
              :output :string
              :error-output :string
              :ignore-error-status t)
           (unless (= 0 status)
             (error "Devnet smoke gate failed with status ~D: ~A"
                    status stderr))
           (setf report (smoke-gate-json-decode stdout))
           (unless (string= "ok" (smoke-gate-field report "status"))
             (error "Devnet smoke gate returned non-ok status: ~S" report))
           report)
      (when report
        (dolist (field '("readyFile" "logFile" "databaseFile"))
          (dolist (path (smoke-gate-devnet-case-files report field))
            (smoke-gate-delete-file-if-present path))))
      (smoke-gate-delete-file-if-present ready-file)
      (smoke-gate-delete-file-if-present log-file)
      (smoke-gate-delete-file-if-present database-file))))

(defun smoke-gate-numeric-field (object field)
  (or (smoke-gate-field object field) 0))

(defun smoke-gate-report-counts (state transaction blockchain devnet)
  (let* ((fixture-case-count
           (+ (smoke-gate-numeric-field state "count")
              (smoke-gate-numeric-field transaction "count")
              (smoke-gate-numeric-field blockchain "count")))
         (fixture-executed-count
           (+ (smoke-gate-numeric-field state "executedCount")
              (smoke-gate-numeric-field transaction "executedCount")
              (smoke-gate-numeric-field blockchain "executedCount")))
         (devnet-case-count
           (if devnet (smoke-gate-numeric-field devnet "caseCount") 0)))
    (list
     (cons "fixtureCaseCount" fixture-case-count)
     (cons "fixtureExecutedCount" fixture-executed-count)
     (cons "totalCaseCount" (+ fixture-case-count devnet-case-count))
     (cons "totalExecutedCount"
           (+ fixture-executed-count devnet-case-count)))))

(defun smoke-gate-report (suite-root pinned-p &key devnet-p)
  (let ((state (smoke-gate-state-summary suite-root (not pinned-p)))
        (transaction
          (smoke-gate-transaction-summary suite-root (not pinned-p)))
        (blockchain (smoke-gate-blockchain-summary suite-root pinned-p))
        (devnet (and devnet-p (smoke-gate-devnet-summary))))
    (append
     (list
      (cons "suiteRoot" suite-root)
      (cons "mode" (if pinned-p "pinned-v5.4.0" "in-repo"))
      (cons "status" "ok")
      (cons "executionSpecTests"
            (smoke-gate-execution-spec-tests-source))
      (cons "referenceClients" (smoke-gate-reference-clients))
      (cons "state" state)
      (cons "transaction" transaction)
      (cons "blockchain" blockchain))
     (smoke-gate-report-counts state transaction blockchain devnet)
     (when devnet
       (list (cons "devnet" devnet))))))

(defun smoke-gate-print-text (report)
  (let ((state (smoke-gate-field report "state"))
        (transaction (smoke-gate-field report "transaction"))
        (blockchain (smoke-gate-field report "blockchain"))
        (execution-spec-tests
          (smoke-gate-field report "executionSpecTests"))
        (reference-clients (smoke-gate-field report "referenceClients"))
        (devnet (smoke-gate-field report "devnet")))
    (format t "~&status=~A~%" (smoke-gate-field report "status"))
    (format t "suiteRoot=~A~%" (smoke-gate-field report "suiteRoot"))
    (format t "mode=~A~%" (smoke-gate-field report "mode"))
    (format t "executionSpecTestsRepository=~A~%"
            (smoke-gate-field execution-spec-tests "repository"))
    (format t "executionSpecTestsRelease=~A~%"
            (smoke-gate-field execution-spec-tests "release"))
    (format t "executionSpecTestsTagTarget=~A~%"
            (smoke-gate-field execution-spec-tests "tagTarget"))
    (format t "executionSpecTestsArchive=~A~%"
            (smoke-gate-field execution-spec-tests "archive"))
    (dolist (client reference-clients)
      (format t "referenceClient[~A]=~A"
              (smoke-gate-field client "name")
              (smoke-gate-field client "status"))
      (when (smoke-gate-field client "commit")
        (format t ":~A" (smoke-gate-field client "commit")))
      (format t "~%"))
    (format t "stateStatus=~A~%" (smoke-gate-field state "status"))
    (format t "stateCount=~D~%" (smoke-gate-field state "count"))
    (format t "stateExecuted=~D~%"
            (smoke-gate-field state "executedCount"))
    (format t "transactionStatus=~A~%"
            (smoke-gate-field transaction "status"))
    (format t "transactionCount=~D~%"
            (smoke-gate-field transaction "count"))
    (format t "transactionExecuted=~D~%"
            (smoke-gate-field transaction "executedCount"))
    (format t "blockchainCount=~D~%"
            (smoke-gate-field blockchain "count"))
    (format t "blockchainExecuted=~D~%"
            (smoke-gate-field blockchain "executedCount"))
    (format t "blockchainBlockCount=~D~%"
            (smoke-gate-field blockchain "blockCount"))
    (format t "blockchainKindCounts=~S~%"
            (smoke-gate-field blockchain "kindCounts"))
    (format t "fixtureCaseCount=~D~%"
            (smoke-gate-field report "fixtureCaseCount"))
    (format t "fixtureExecutedCount=~D~%"
            (smoke-gate-field report "fixtureExecutedCount"))
    (format t "totalCaseCount=~D~%"
            (smoke-gate-field report "totalCaseCount"))
    (format t "totalExecutedCount=~D~%"
            (smoke-gate-field report "totalExecutedCount"))
    (when devnet
      (format t "devnetStatus=~A~%" (smoke-gate-field devnet "status"))
      (format t "devnetCaseCount=~D~%" (smoke-gate-field devnet "caseCount"))
      (format t "devnetReadyCaseCount=~D~%"
              (smoke-gate-field devnet "readyCaseCount"))
      (format t "devnetLogCaseCount=~D~%"
              (smoke-gate-field devnet "logCaseCount"))
      (format t "devnetDatabaseCaseCount=~D~%"
              (smoke-gate-field devnet "databaseCaseCount"))
      (format t "devnetTotalConnections=~D~%"
              (smoke-gate-field devnet "totalConnections")))))

(defun smoke-gate-main ()
  (let* ((args (smoke-gate-arguments))
         (help-p (smoke-gate-help-p args))
         (pinned-p (smoke-gate-pinned-v5.4.0-p args))
         (devnet-p (smoke-gate-devnet-p args))
         (json-p (smoke-gate-json-p args))
         (root-argument (smoke-gate-argument-root args)))
    (if help-p
        (smoke-gate-print-help)
        (progn
          (load (merge-pathnames "tests/load-tests.lisp"
                                 *ethereum-lisp-smoke-gate-root*))
          (let* ((suite-root (smoke-gate-suite-root root-argument pinned-p))
                 (report (smoke-gate-report
                          suite-root pinned-p :devnet-p devnet-p)))
            (if json-p
                (format t "~&~A~%" (smoke-gate-json-encode report))
                (smoke-gate-print-text report)))))))

(smoke-gate-main)
