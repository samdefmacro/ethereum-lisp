(defparameter *ethereum-lisp-fixture-report-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)

(defvar *fixture-report-run-main-p* t)
(defvar *fixture-report-environment-lookup* #'uiop:getenv)

(load (merge-pathnames "scripts/fixture-root-application.lisp"
                       *ethereum-lisp-fixture-report-root*))

(defconstant +fixture-report-pinned-v5.4.0-flag+ "--pinned-v5.4.0")
(defconstant +fixture-report-json-flag+ "--json")
(defconstant +fixture-report-root-option+ "--root")
(defconstant +fixture-report-help-flag+ "--help")
(defconstant +fixture-report-eest-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")
(defconstant +fixture-report-eest-repository+
  "ethereum/execution-spec-tests")
(defconstant +fixture-report-eest-release+ "v5.4.0")
(defconstant +fixture-report-eest-tag-target+ "88e9fb8")
(defconstant +fixture-report-eest-archive+ "fixtures_stable.tar.gz")

(defun fixture-report-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun fixture-report-pinned-v5.4.0-p (args)
  (member +fixture-report-pinned-v5.4.0-flag+ args :test #'string=))

(defun fixture-report-json-p (args)
  (member +fixture-report-json-flag+ args :test #'string=))

(defun fixture-report-help-p (args)
  (member +fixture-report-help-flag+ args :test #'string=))

(defun fixture-report-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun fixture-report-blank-string-p (value)
  (ethereum-lisp.fixture-root-application:blank-string-p value))

(defun fixture-report-reject-missing-configured-root
    (root-argument &key
       (environment-lookup *fixture-report-environment-lookup*))
  (ethereum-lisp.fixture-root-application:validate-configured-root
   root-argument
   :environment-name +fixture-report-eest-root-env+
   :root-option +fixture-report-root-option+
   :environment-lookup environment-lookup))

(defun fixture-report-set-argument-root (root value)
  (when root
    (error "Only one fixture root argument is supported"))
  value)

(defun fixture-report-argument-root (args)
  (let ((root nil))
    (loop while args
          for arg = (pop args)
          do
      (cond
        ((string= arg +fixture-report-pinned-v5.4.0-flag+))
        ((string= arg +fixture-report-json-flag+))
        ((string= arg +fixture-report-help-flag+))
        ((string= arg +fixture-report-root-option+)
         (unless args
           (error "~A requires a fixture root path"
                  +fixture-report-root-option+))
         (let ((value (pop args)))
           (when (fixture-report-option-like-p value)
             (error "~A requires a fixture root path, got option ~A"
                    +fixture-report-root-option+
                    value))
           (setf root (fixture-report-set-argument-root root value))))
        ((fixture-report-option-like-p arg)
         (error "Unsupported fixture report option ~A" arg))
        (t
         (setf root (fixture-report-set-argument-root root arg)))))
    root))

(defun fixture-report-print-help ()
  (format t "~&Usage: sbcl --script scripts/phase-a-fixture-report.lisp -- [options] [ROOT]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --root PATH        Fixture suite root. Equivalent to positional ROOT.~%")
  (format t "  --pinned-v5.4.0    Validate the pinned EEST v5.4.0 stable archive subset.~%")
  (format t "  --json             Print machine-readable JSON output.~%")
  (format t "  --help             Print this help without loading the test system.~%")
  (format t "~%")
  (format t "Default ROOT: ~A when set; otherwise no external root is assumed.~%"
          +fixture-report-eest-root-env+)
  (format t "Pinned mode requires ROOT or ~A when ROOT is omitted.~%"
          +fixture-report-eest-root-env+)
  (format t "Reference client roots: ETHEREUM_LISP_GETH_ROOT, ~
ETHEREUM_LISP_NETHERMIND_ROOT, ETHEREUM_LISP_RETH_ROOT override ~
references/ checkouts.~%"))

(defun fixture-report-pinned-default-root ()
  (let ((root (funcall *fixture-report-environment-lookup*
                       +fixture-report-eest-root-env+)))
    (when (fixture-report-blank-string-p root)
      (error "Pinned Phase A fixture report requires an EEST fixture root via ~A or ~A"
             +fixture-report-root-option+
             +fixture-report-eest-root-env+))
    (let ((resolved-root (probe-file root)))
      (unless resolved-root
        (error "Pinned Phase A fixture report root from ~A does not exist: ~A"
               +fixture-report-eest-root-env+
               root))
      (namestring resolved-root))))

(defun fixture-report-suite-root-argument (root-argument pinned-p)
  (or root-argument
      (when pinned-p
        (fixture-report-pinned-default-root))))

(defun fixture-report-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun fixture-report-variable (name)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (boundp symbol))
      (error "Fixture variable ~A is unavailable" name))
    (symbol-value symbol)))

(defun fixture-report-reject-empty-selected-root (root label)
  (ethereum-lisp.fixture-root-application:validate-non-empty-root
   root
   label
   (lambda (path)
     (fixture-report-call "execution-spec-tests-json-paths" path))))

(defun fixture-report-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun fixture-report-root-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults *ethereum-lisp-fixture-report-root*))

(defun fixture-report-reference-path (relative-path &optional env-var)
  (let ((override (and env-var
                       (funcall *fixture-report-environment-lookup* env-var))))
    (if (and override (plusp (length override)))
        (uiop:ensure-directory-pathname
         (merge-pathnames override (fixture-report-root-directory)))
        (merge-pathnames relative-path (fixture-report-root-directory)))))

(defun fixture-report-reference-client-object (name env-var relative-path)
  (let ((path (fixture-report-reference-path relative-path env-var)))
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

(defun fixture-report-reference-clients ()
  (list
   (fixture-report-reference-client-object
    "geth" "ETHEREUM_LISP_GETH_ROOT" "references/go-ethereum/")
   (fixture-report-reference-client-object
    "nethermind" "ETHEREUM_LISP_NETHERMIND_ROOT" "references/nethermind/")
   (fixture-report-reference-client-object
    "reth" "ETHEREUM_LISP_RETH_ROOT" "references/reth/")))

(defun fixture-report-execution-spec-tests-source ()
  (list
   (cons "repository" +fixture-report-eest-repository+)
   (cons "release" +fixture-report-eest-release+)
   (cons "tagTarget" +fixture-report-eest-tag-target+)
   (cons "archive" +fixture-report-eest-archive+)))

(defun fixture-report-kind-string (kinds)
  (fixture-report-call
   "phase-a-eest-blockchain-replay-selector-string"
   kinds))

(defun fixture-report-json-encode (object)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) object)))

(defun fixture-report-blockchain-kind-object (kinds)
  (mapcar (lambda (entry)
            (list (cons "name" (car entry))
                  (cons "kind" (cdr entry))))
          kinds))

(defun fixture-report-state-object (state-root state-selectors state-summary)
  (if state-root
      (list
       (cons "status" "ok")
       (cons "root" (namestring state-root))
       (cons "count" (fixture-report-field state-summary "count"))
       (cons "transactionCombinationCount"
             (fixture-report-field state-summary
                                   "transactionCombinationCount"))
       (cons "selectors" state-selectors)
       (cons "selectorString"
             (fixture-report-call
              "phase-a-eest-state-test-selector-string"
              state-selectors)))
      (list
       (cons "status" "missing")
       (cons "root" nil)
       (cons "count" 0)
       (cons "transactionCombinationCount" 0)
       (cons "selectors" nil)
       (cons "selectorString" ""))))

(defun fixture-report-transaction-object
    (transaction-root transaction-selectors transaction-summary)
  (if transaction-root
      (list
       (cons "status" "ok")
       (cons "root" (namestring transaction-root))
       (cons "count" (fixture-report-field transaction-summary "count"))
       (cons "types" (fixture-report-field transaction-summary "types"))
       (cons "signatureVectorCount"
             (or (fixture-report-field transaction-summary "signatureVectorCount")
                 0))
       (cons "accessListVectorCount"
             (or (fixture-report-field transaction-summary "accessListVectorCount")
                 0))
       (cons "contractCreationVectorCount"
             (or (fixture-report-field transaction-summary
                                       "contractCreationVectorCount")
                 0))
       (cons "invalidSummary"
             (fixture-report-field transaction-summary "invalidSummary"))
       (cons "selectors" transaction-selectors)
       (cons "selectorString"
             (or (fixture-report-field transaction-summary "selectorString")
                 (fixture-report-call
                  "phase-a-eest-transaction-test-selector-string"
                  transaction-selectors))))
      (list
       (cons "status" "missing")
       (cons "root" nil)
       (cons "count" 0)
       (cons "types" nil)
       (cons "signatureVectorCount" 0)
       (cons "accessListVectorCount" 0)
       (cons "contractCreationVectorCount" 0)
       (cons "selectors" nil)
       (cons "selectorString" ""))))

(defun fixture-report-report-object
    (suite-root mode state-root state-selectors state-summary
     transaction-root transaction-selectors transaction-summary
     blockchain-root blockchain-kinds blockchain-summary)
  (list
   (cons "suiteRoot" suite-root)
   (cons "mode" mode)
   (cons "executionSpecTests"
         (fixture-report-execution-spec-tests-source))
   (cons "referenceClients" (fixture-report-reference-clients))
   (cons "state" (fixture-report-state-object
                  state-root state-selectors state-summary))
   (cons "transaction" (fixture-report-transaction-object
                        transaction-root
                        transaction-selectors
                        transaction-summary))
   (cons "blockchain"
         (list
          (cons "root" (namestring blockchain-root))
          (cons "count" (fixture-report-field blockchain-summary "count"))
          (cons "blockCount"
                (fixture-report-field blockchain-summary "blockCount"))
          (cons "kindCounts"
                (fixture-report-field blockchain-summary
                                      "materializationKindCounts"))
          (cons "selectors" (fixture-report-blockchain-kind-object
                             blockchain-kinds))
          (cons "selectorString"
                (fixture-report-kind-string blockchain-kinds))))))

(defun fixture-report-print-text (report)
  (let ((state (fixture-report-field report "state"))
        (transaction (fixture-report-field report "transaction"))
        (blockchain (fixture-report-field report "blockchain"))
        (execution-spec-tests
          (fixture-report-field report "executionSpecTests"))
        (reference-clients (fixture-report-field report "referenceClients")))
    (format t "~&suiteRoot=~A~%" (fixture-report-field report "suiteRoot"))
    (format t "mode=~A~%" (fixture-report-field report "mode"))
    (format t "executionSpecTestsRepository=~A~%"
            (fixture-report-field execution-spec-tests "repository"))
    (format t "executionSpecTestsRelease=~A~%"
            (fixture-report-field execution-spec-tests "release"))
    (format t "executionSpecTestsTagTarget=~A~%"
            (fixture-report-field execution-spec-tests "tagTarget"))
    (format t "executionSpecTestsArchive=~A~%"
            (fixture-report-field execution-spec-tests "archive"))
    (dolist (client reference-clients)
      (format t "referenceClient[~A]=~A"
              (fixture-report-field client "name")
              (fixture-report-field client "status"))
      (when (fixture-report-field client "commit")
        (format t ":~A" (fixture-report-field client "commit")))
      (format t "~%"))
    (format t "stateStatus=~A~%" (fixture-report-field state "status"))
    (format t "stateRoot=~A~%" (or (fixture-report-field state "root")
                                   "missing"))
    (format t "stateCount=~D~%" (fixture-report-field state "count"))
    (format t "stateTransactionCombinations=~D~%"
            (fixture-report-field state "transactionCombinationCount"))
    (format t "stateSelectors=~A~%"
            (fixture-report-field state "selectorString"))
    (format t "transactionStatus=~A~%"
            (fixture-report-field transaction "status"))
    (format t "transactionRoot=~A~%"
            (or (fixture-report-field transaction "root") "missing"))
    (format t "transactionCount=~D~%"
            (fixture-report-field transaction "count"))
    (format t "transactionTypes=~S~%"
            (fixture-report-field transaction "types"))
    (format t "transactionSignatureVectors=~D~%"
            (fixture-report-field transaction "signatureVectorCount"))
    (format t "transactionAccessListVectors=~D~%"
            (fixture-report-field transaction "accessListVectorCount"))
    (format t "transactionContractCreationVectors=~D~%"
            (fixture-report-field transaction "contractCreationVectorCount"))
    (format t "transactionSelectors=~A~%"
            (fixture-report-field transaction "selectorString"))
    (format t "blockchainRoot=~A~%"
            (fixture-report-field blockchain "root"))
    (format t "blockchainCount=~D~%"
            (fixture-report-field blockchain "count"))
    (format t "blockchainBlockCount=~D~%"
            (fixture-report-field blockchain "blockCount"))
    (format t "blockchainKindCounts=~S~%"
            (fixture-report-field blockchain "kindCounts"))
    (format t "blockchainSelectors=~A~%"
            (fixture-report-field blockchain "selectorString"))))

(defun fixture-report-main
    (&key
       (args (fixture-report-arguments))
       (environment-lookup #'uiop:getenv)
       (output *standard-output*)
       (error-output *error-output*)
       (load-tests-p t))
  (let ((*fixture-report-environment-lookup* environment-lookup)
        (*standard-output* output)
        (*error-output* error-output))
    (let* ((args args)
         (pinned-p (fixture-report-pinned-v5.4.0-p args))
         (json-p (fixture-report-json-p args))
         (help-p (fixture-report-help-p args)))
    (if help-p
        (fixture-report-print-help)
        (let* ((root-argument (fixture-report-argument-root args))
               (selected-root
                 (fixture-report-suite-root-argument
                  root-argument
                  pinned-p)))
          (fixture-report-reject-missing-configured-root
           selected-root :environment-lookup environment-lookup)
          (when load-tests-p
            (load (merge-pathnames "tests/load-tests.lisp"
                                   *ethereum-lisp-fixture-report-root*)))
          (fixture-report-run selected-root pinned-p json-p))))))

(defun fixture-report-run (selected-root pinned-p json-p)
  (let* ((suite-root (or selected-root "environment"))
         (mode (if pinned-p "pinned-v5.4.0" "discover"))
         (state-root
           (if selected-root
               (fixture-report-call "execution-spec-tests-state-test-root"
                                    selected-root)
               (fixture-report-call
                "execution-spec-tests-state-test-root")))
         (transaction-root
           (if selected-root
               (fixture-report-call "execution-spec-tests-transaction-test-root"
                                    selected-root)
               (fixture-report-call
                "execution-spec-tests-transaction-test-root")))
         (blockchain-root
           (if selected-root
               (fixture-report-call
                "execution-spec-tests-blockchain-test-root"
                selected-root)
               (fixture-report-call
                "execution-spec-tests-blockchain-test-root"))))
    (unless blockchain-root
      (error "No EEST blockchain fixture root found. Pass a root path or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (fixture-report-reject-empty-selected-root state-root "state_tests")
    (fixture-report-reject-empty-selected-root
     transaction-root
     "transaction_tests")
    (fixture-report-reject-empty-selected-root blockchain-root "blockchain")
    (let* ((state-selectors
             (when state-root
               (if pinned-p
                   (fixture-report-variable
                    "+phase-a-eest-state-test-v5.4.0-case-names+")
                   (fixture-report-call
                    "discover-phase-a-eest-state-test-selectors"
                    state-root))))
           (state-cases
             (when state-root
               (fixture-report-call
                "load-eest-state-test-root-cases"
                state-root
                :names state-selectors)))
           (state-summary
             (when state-root
               (fixture-report-call
                "validate-phase-a-eest-state-test-summary"
                state-cases
                :expected-names state-selectors)))
           (transaction-selectors
             (when (and transaction-root (not pinned-p))
               (fixture-report-variable
                "+phase-a-eest-transaction-test-case-names+")))
           (transaction-vectors
             (when (and transaction-root (not pinned-p))
               (fixture-report-call
                "load-phase-a-eest-transaction-test-root-vectors"
                transaction-root)))
           (transaction-invalid-cases
             (when (and transaction-root pinned-p)
               (fixture-report-call
                "load-eest-transaction-test-root-invalid-cases"
                transaction-root)))
           (transaction-summary
             (when transaction-root
               (if pinned-p
                   (let ((summary
                           (fixture-report-call
                            "eest-invalid-transaction-rejection-summary"
                            transaction-invalid-cases)))
                     (list
                      (cons "count" (length transaction-invalid-cases))
                      (cons "types" nil)
                      (cons "signatureVectorCount" 0)
                      (cons "accessListVectorCount" 0)
                      (cons "contractCreationVectorCount" 0)
                      (cons "invalidSummary" summary)
                      (cons "selectorString" "pinned-v5.4.0-invalid")))
                   (fixture-report-call
                    "validate-phase-a-eest-transaction-vector-summary"
                    transaction-vectors))))
           (blockchain-kinds
             (if pinned-p
                 (fixture-report-call
                  "phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds"
                  blockchain-root)
                 (fixture-report-call
                  "discover-phase-a-eest-blockchain-replay-selectors"
                  blockchain-root)))
           (blockchain-cases
             (fixture-report-call
              "load-phase-a-eest-blockchain-replay-cases"
              blockchain-root
              :expected-kinds blockchain-kinds))
           (blockchain-summary
             (fixture-report-call
              "validate-phase-a-eest-blockchain-replay-summary"
              blockchain-cases
              :expected-kinds blockchain-kinds)))
      (when (and state-root (not state-selectors))
        (error "No materializable Phase A state_tests selectors found under ~A"
               state-root))
      (when (and transaction-root (not pinned-p) (not transaction-selectors))
        (error "No Phase A transaction_tests selectors are configured"))
      (unless blockchain-kinds
        (error "No materializable Phase A blockchain selectors found under ~A"
               blockchain-root))
      (let ((report
              (fixture-report-report-object
               suite-root
               mode
               state-root
               state-selectors
               state-summary
               transaction-root
               transaction-selectors
               transaction-summary
               blockchain-root
               blockchain-kinds
               blockchain-summary)))
        (if json-p
            (format t "~&~A~%" (fixture-report-json-encode report))
            (fixture-report-print-text report))
        report))))

(when *fixture-report-run-main-p*
  (fixture-report-main))
