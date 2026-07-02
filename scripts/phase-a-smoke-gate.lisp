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
(defconstant +smoke-gate-devnet-prune-state-before+ 42)
(defparameter +smoke-gate-devnet-side-reorg-fixture-cases+
  '("shanghai-one-transfer-with-withdrawal"
    "shanghai-two-legacy-transfers-with-withdrawal"
    "shanghai-log-contract-call-with-withdrawal"))

(defparameter *smoke-gate-boolean-options*
  (list +smoke-gate-pinned-v5.4.0-flag+
        +smoke-gate-devnet-flag+
        +smoke-gate-json-flag+))

(defun smoke-gate-option-token-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (string= "--" value :end2 2)))

(defun smoke-gate-boolean-option-p (arg)
  (member arg *smoke-gate-boolean-options* :test #'string=))

(defun smoke-gate-parse-boolean-assignment (option value)
  (let ((normalized (and (stringp value) (string-downcase value))))
    (cond
      ((member normalized '("true" "1") :test #'string=) t)
      ((member normalized '("false" "0") :test #'string=) nil)
      (t (error "~A boolean value must be true or false" option)))))

(defun smoke-gate-normalize-option-args (args)
  (loop for arg in args
        for separator = (and (smoke-gate-option-token-p arg)
                             (position #\= arg :start 2))
        for option = (and separator (subseq arg 0 separator))
        for value = (and separator (subseq arg (1+ separator)))
        append
        (cond
          ((and separator (string= option +smoke-gate-root-option+))
           (list option value))
          ((and separator (smoke-gate-boolean-option-p option))
           (if (smoke-gate-parse-boolean-assignment option value)
               (list option)
               '()))
          (t
           (list arg)))))

(defun smoke-gate-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    (smoke-gate-normalize-option-args args))
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
          +smoke-gate-eest-root-env+)
  (format t "Reference client roots: ETHEREUM_LISP_GETH_ROOT, ~
ETHEREUM_LISP_NETHERMIND_ROOT, ETHEREUM_LISP_RETH_ROOT override ~
references/ checkouts.~%"))

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

(defun smoke-gate-false-p (value)
  (or (null value) (eq value :false)))

(defun smoke-gate-http-endpoint-p (value)
  (and (stringp value)
       (uiop:string-prefix-p "http://127.0.0.1:" value)))

(defun smoke-gate-root-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults *ethereum-lisp-smoke-gate-root*))

(defun smoke-gate-reference-path (relative-path)
  (merge-pathnames relative-path (smoke-gate-root-directory)))

(defun smoke-gate-reference-client-path (relative-path env-var)
  (let ((override (and env-var (uiop:getenv env-var))))
    (if (and override (plusp (length override)))
        (uiop:ensure-directory-pathname
         (merge-pathnames override (smoke-gate-root-directory)))
        (smoke-gate-reference-path relative-path))))

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

(defun smoke-gate-reference-client-object (name env-var relative-path)
  (let ((path (smoke-gate-reference-client-path relative-path env-var)))
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
   (smoke-gate-reference-client-object
    "geth" "ETHEREUM_LISP_GETH_ROOT" "references/go-ethereum/")
   (smoke-gate-reference-client-object
    "nethermind" "ETHEREUM_LISP_NETHERMIND_ROOT" "references/nethermind/")
   (smoke-gate-reference-client-object
    "reth" "ETHEREUM_LISP_RETH_ROOT" "references/reth/")))

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

(defun smoke-gate-state-summary (suite-root required-p &key pinned-p)
  (let ((root (smoke-gate-call "execution-spec-tests-state-test-root"
                               suite-root)))
    (cond
      (root
       (smoke-gate-reject-empty-selected-root root "state_tests")
       (let* ((selectors
                (if pinned-p
                    (smoke-gate-variable
                     "+phase-a-eest-state-test-v5.4.0-case-names+")
                    (or (smoke-gate-call
                         "phase-a-eest-state-test-env-selectors"
                         root)
                        (smoke-gate-call
                         "discover-phase-a-eest-state-test-selectors"
                         root))))
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

(defun smoke-gate-transaction-summary (suite-root required-p &key pinned-p)
  (let ((root (smoke-gate-call
               "execution-spec-tests-transaction-test-root"
               suite-root)))
    (cond
      ((and root pinned-p)
       (smoke-gate-reject-empty-selected-root root "transaction_tests")
       (let* ((cases
                (smoke-gate-call
                 "load-eest-transaction-test-root-invalid-cases"
                 root))
              (summary
                (smoke-gate-call
                 "eest-invalid-transaction-rejection-summary"
                 cases))
              (count (length cases)))
         (unless (plusp count)
           (error "Pinned EEST transaction_tests invalid-case count must be positive"))
         (list
          (cons "status" "ok")
          (cons "root" (namestring root))
          (cons "count" count)
          (cons "executedCount" count)
          (cons "types" nil)
          (cons "invalidSummary" summary)
          (cons "selectorString" "pinned-v5.4.0-invalid"))))
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

(defun smoke-gate-devnet-require-field (report field expected)
  (let ((actual (smoke-gate-field report field)))
    (unless (equal actual expected)
      (error "Devnet smoke gate ~A must be ~S, got ~S"
             field expected actual))
    actual))

(defun smoke-gate-devnet-require-case-files
    (report field count-field expected-count)
  (let ((files (smoke-gate-devnet-case-files report field))
        (count (smoke-gate-field report count-field)))
    (unless (= expected-count count)
      (error "Devnet smoke gate ~A must be ~D, got ~S"
             count-field expected-count count))
    (unless (= expected-count (length files))
      (error "Devnet smoke gate ~A files must have count ~D, got ~D"
             field expected-count (length files)))
    files))

(defparameter +smoke-gate-devnet-side-reorg-pruned-fields+
  '("databaseRpcSideBlockHash"
    "databaseRpcSideForkchoiceStatus"
    "databaseRpcSideRejectedCheckpointError"
    "databaseRpcSideBlockNumber"
    "databaseRpcSideLatestBlockHash"
    "databaseRpcSideTransactionReinserted"
    "databaseRpcSideTransactionByHash"
    "databaseRpcSideRawTransaction"
    "databaseRpcSidePendingTransaction"
    "databaseRpcSideReinsertedTransactionCount"
    "databaseRpcSideReinsertedTransactionHashes"
    "databaseRpcSideReceipt"
    "databaseRpcSideHiddenReceiptCount"
    "databaseRpcSideChildBlockHash"
    "databaseRpcSideBlockReceiptsCount"
    "databaseRpcSideLogCount"
    "databaseRpcSideRestoredHeadNumber"
    "databaseRpcSideRestoredHeadHash"
    "databaseRpcSideRestoredRpcBlockNumber"
    "databaseRpcSideRestoredRpcLatestBlockHash"
    "databaseRpcSideRestoredSafeNumber"
    "databaseRpcSideRestoredSafeHash"
    "databaseRpcSideRestoredFinalizedNumber"
    "databaseRpcSideRestoredFinalizedHash"
    "databaseRpcSideRestoredRpcSafeNumber"
    "databaseRpcSideRestoredRpcSafeHash"
    "databaseRpcSideRestoredRpcFinalizedNumber"
    "databaseRpcSideRestoredRpcFinalizedHash"
    "databaseRpcSideRestoredSafeBalance"
    "databaseRpcSideRestoredFinalizedBalance"
    "databaseRpcSideRestoredRawTransaction"
    "databaseRpcSideRestoredPendingTransaction"
    "databaseRpcSideRestoredReinsertedTransactionCount"
    "databaseRpcSideRestoredReinsertedTransactionHashes"
    "databaseRpcSideRestoredReceipt"
    "databaseRpcSideRestoredHiddenReceiptCount"
    "databaseRpcSideRestoredChildBlockHash"
    "databaseRpcSideRestoredChildRequireCanonicalError"
    "databaseRpcSideRestoredChildRequireCanonicalErrors"
    "databaseRpcSideRestoredBlockReceiptsCount"
    "databaseRpcSideRestoredLogCount"
    "databaseRpcSideRestoredPublicConnections"
    "databaseRpcSideTotalConnections"
    "databaseRpcSideEngineConnections"
    "databaseRpcSidePublicConnections"))

(defparameter +smoke-gate-devnet-noncanonical-state-errors+
  '("eth_getBalance block hash is not canonical"
    "eth_getTransactionCount block hash is not canonical"
    "eth_getCode block hash is not canonical"
    "eth_getStorageAt block hash is not canonical"
    "eth_getProof block hash is not canonical"
    "eth_call block hash is not canonical"
    "eth_estimateGas block hash is not canonical"
    "eth_createAccessList block hash is not canonical"))

(defun smoke-gate-devnet-case-label (case-report)
  (or (smoke-gate-field case-report "fixtureCase") "<unknown>"))

(defun smoke-gate-devnet-case-require-field
    (case-report field expected)
  (let ((actual (smoke-gate-field case-report field)))
    (unless (equal actual expected)
      (error "Devnet smoke gate case ~A field ~A must be ~S, got ~S"
             (smoke-gate-devnet-case-label case-report)
             field
             expected
             actual))
    actual))

(defun smoke-gate-devnet-case-require-false (case-report field)
  (let ((actual (smoke-gate-field case-report field)))
    (unless (smoke-gate-false-p actual)
      (error "Devnet smoke gate case ~A field ~A must be false/null, got ~S"
             (smoke-gate-devnet-case-label case-report)
             field
             actual))))

(defun smoke-gate-devnet-case-require-not-equal
    (case-report field other-field)
  (let ((actual (smoke-gate-field case-report field))
        (other (smoke-gate-field case-report other-field)))
    (unless (and actual other (not (equal actual other)))
      (error "Devnet smoke gate case ~A fields ~A and ~A must differ, got ~S"
             (smoke-gate-devnet-case-label case-report)
             field
             other-field
             actual))))

(defun smoke-gate-devnet-nested-field (object field)
  (when (listp object)
    (smoke-gate-field object field)))

(defun smoke-gate-devnet-case-require-nested-field
    (case-report object-field nested-field expected)
  (let* ((object (smoke-gate-field case-report object-field))
         (actual (smoke-gate-devnet-nested-field object nested-field)))
    (unless (equal actual expected)
      (error "Devnet smoke gate case ~A field ~A.~A must be ~S, got ~S"
             (smoke-gate-devnet-case-label case-report)
             object-field
             nested-field
             expected
             actual))
    actual))

(defun smoke-gate-devnet-case-require-side-pending-object
    (case-report object-field)
  (smoke-gate-devnet-case-require-nested-field
   case-report
   object-field
   "hash"
   (smoke-gate-field case-report "databaseRpcReceiptTransactionHash"))
  (dolist (field '("blockHash" "blockNumber" "transactionIndex"))
    (smoke-gate-devnet-case-require-nested-field
     case-report object-field field nil)))

(defun smoke-gate-devnet-validate-side-reorg-transaction
    (case-report)
  (if (not (smoke-gate-false-p
            (smoke-gate-field
             case-report "databaseRpcSideTransactionReinserted")))
      (let ((expected-hash
              (smoke-gate-field case-report
                                "databaseRpcReceiptTransactionHash"))
            (expected-count
              (smoke-gate-field case-report
                                "databaseRpcTransactionCount")))
        (smoke-gate-devnet-case-require-side-pending-object
         case-report "databaseRpcSideTransactionByHash")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRawTransaction"
         (smoke-gate-field case-report "databaseRpcRawTransactionByHash"))
        (smoke-gate-devnet-case-require-side-pending-object
         case-report "databaseRpcSidePendingTransaction")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRawTransaction"
         (smoke-gate-field case-report "databaseRpcRawTransactionByHash"))
        (smoke-gate-devnet-case-require-side-pending-object
         case-report "databaseRpcSideRestoredPendingTransaction")
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideReinsertedTransactionCount"
         expected-count)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideRestoredReinsertedTransactionCount"
         expected-count)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideHiddenReceiptCount" expected-count)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideRestoredHiddenReceiptCount"
         expected-count)
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideReinsertedTransactionHashes"
         (smoke-gate-field
          case-report "databaseRpcSideRestoredReinsertedTransactionHashes"))
        (unless (member expected-hash
                        (smoke-gate-field
                         case-report
                         "databaseRpcSideReinsertedTransactionHashes")
                        :test #'string=)
          (error "Devnet smoke gate case ~A reinserted transaction hashes ~S must include ~S"
                 (smoke-gate-devnet-case-label case-report)
                 (smoke-gate-field
                  case-report
                  "databaseRpcSideReinsertedTransactionHashes")
                 expected-hash)))
      (dolist (field '("databaseRpcSideTransactionByHash"
                       "databaseRpcSideRawTransaction"
                       "databaseRpcSidePendingTransaction"
                       "databaseRpcSideReinsertedTransactionCount"
                       "databaseRpcSideReinsertedTransactionHashes"
                       "databaseRpcSideHiddenReceiptCount"
                       "databaseRpcSideRestoredRawTransaction"
                       "databaseRpcSideRestoredPendingTransaction"
                       "databaseRpcSideRestoredReinsertedTransactionCount"
                       "databaseRpcSideRestoredReinsertedTransactionHashes"
                       "databaseRpcSideRestoredHiddenReceiptCount"))
        (smoke-gate-devnet-case-require-false case-report field))))

(defun smoke-gate-devnet-validate-side-reorg-case (case-report)
  (if (smoke-gate-false-p
       (smoke-gate-field case-report "databaseRpcSideBlockHash"))
      (progn
        (dolist (field +smoke-gate-devnet-side-reorg-pruned-fields+)
          (smoke-gate-devnet-case-require-false case-report field))
        0)
      (progn
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideForkchoiceStatus" "VALID")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRejectedCheckpointError"
         "forkchoice safe block is not an ancestor of head")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideBlockNumber"
         (smoke-gate-field case-report "blockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideLatestBlockHash"
         (smoke-gate-field case-report "databaseRpcSideBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredHeadHash"
         (smoke-gate-field case-report "databaseRpcSideBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredHeadNumber"
         (smoke-gate-field case-report "blockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcBlockNumber"
         (smoke-gate-field case-report "blockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcLatestBlockHash"
         (smoke-gate-field case-report "databaseRpcSideBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredSafeNumber"
         (smoke-gate-field case-report "safeBlockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredSafeHash"
         (smoke-gate-field case-report "safeBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredFinalizedNumber"
         (smoke-gate-field case-report "finalizedBlockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredFinalizedHash"
         (smoke-gate-field case-report "finalizedBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcSafeNumber"
         (smoke-gate-field case-report "safeBlockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcSafeHash"
         (smoke-gate-field case-report "safeBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcFinalizedNumber"
         (smoke-gate-field case-report "finalizedBlockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcFinalizedHash"
         (smoke-gate-field case-report "finalizedBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredSafeBalance"
         (smoke-gate-field case-report "checkedCheckpointBalance"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredFinalizedBalance"
         (smoke-gate-field case-report "checkedCheckpointBalance"))
        (smoke-gate-devnet-case-require-not-equal
         case-report "databaseRpcBlockHash" "databaseRpcSideBlockHash")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideChildBlockHash"
         (smoke-gate-field case-report "databaseRpcBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideBlockReceiptsCount" 0)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideLogCount" 0)
        (smoke-gate-devnet-validate-side-reorg-transaction case-report)
        (smoke-gate-devnet-case-require-false
         case-report "databaseRpcSideReceipt")
        (smoke-gate-devnet-case-require-false
         case-report "databaseRpcSideRestoredReceipt")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredChildBlockHash"
         (smoke-gate-field case-report "databaseRpcBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredChildRequireCanonicalError"
         "eth_getBalance block hash is not canonical")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredChildRequireCanonicalErrors"
         +smoke-gate-devnet-noncanonical-state-errors+)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideRestoredBlockReceiptsCount" 0)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideRestoredLogCount" 0)
        (let* ((transaction-count
                 (smoke-gate-field case-report "databaseRpcTransactionCount"))
               (extra-transaction-count (max 0 (1- transaction-count)))
               (side-public-connections (+ 9 extra-transaction-count))
               (restored-public-connections (+ 20 extra-transaction-count)))
          (smoke-gate-devnet-case-require-field
           case-report "databaseRpcSideEngineConnections" 3)
          (smoke-gate-devnet-case-require-field
           case-report "databaseRpcSidePublicConnections"
           side-public-connections)
          (smoke-gate-devnet-case-require-field
           case-report "databaseRpcSideRestoredPublicConnections"
           restored-public-connections)
          (smoke-gate-devnet-case-require-field
           case-report "databaseRpcSideTotalConnections"
           (+ 3 side-public-connections restored-public-connections)))
        1)))

(defun smoke-gate-validate-devnet-side-reorg-cases
    (report expected-count)
  (let ((cases (smoke-gate-field report "cases"))
        (side-reorg-count 0))
    (unless (and (listp cases) (= expected-count (length cases)))
      (error "Devnet smoke gate cases must have count ~D, got ~S"
             expected-count
             (and (listp cases) (length cases))))
    (dolist (case-report cases side-reorg-count)
      (incf side-reorg-count
            (smoke-gate-devnet-validate-side-reorg-case case-report)))))

(defun smoke-gate-validate-devnet-summary
    (report ready-file log-file pid-file database-file)
  (let ((expected-count
          (length
           (smoke-gate-variable "+engine-newpayload-v2-smoke-case-names+"))))
    (unless (string= "ok" (smoke-gate-field report "status"))
      (error "Devnet smoke gate returned non-ok status: ~S" report))
    (smoke-gate-devnet-require-field report "readyFile" ready-file)
    (smoke-gate-devnet-require-field report "logFile" log-file)
    (smoke-gate-devnet-require-field report "pidFile" pid-file)
    (smoke-gate-devnet-require-field report "databaseFile" database-file)
    (smoke-gate-devnet-require-field
     report
     "databasePruneStateBefore"
     +smoke-gate-devnet-prune-state-before+)
    (smoke-gate-devnet-require-field
     report
     "caseCount"
     expected-count)
    (smoke-gate-devnet-require-case-files
     report "readyFile" "readyCaseCount" expected-count)
    (smoke-gate-devnet-require-case-files
     report "logFile" "logCaseCount" expected-count)
    (smoke-gate-devnet-require-case-files
     report "pidFile" "pidCaseCount" expected-count)
    (smoke-gate-devnet-require-case-files
     report "databaseFile" "databaseCaseCount" expected-count)
    (append
     report
     (list
      (cons "sideReorgCaseCount"
            (smoke-gate-validate-devnet-side-reorg-cases
             report expected-count))))))

(defun smoke-gate-validate-devnet-engine-only-summary
    (report ready-file log-file pid-file)
  (unless (string= "ok" (smoke-gate-field report "status"))
    (error "Devnet Engine-only smoke gate returned non-ok status: ~S"
           report))
  (smoke-gate-devnet-require-field
   report "mode" "devnet-engine-only-serve")
  (smoke-gate-devnet-require-field report "readyFile" ready-file)
  (smoke-gate-devnet-require-field report "logFile" log-file)
  (smoke-gate-devnet-require-field report "pidFile" pid-file)
  (smoke-gate-devnet-require-field report "engineConnections" 2)
  (smoke-gate-devnet-require-field report "publicConnections" 0)
  (smoke-gate-devnet-require-field report "totalConnections" 2)
  (smoke-gate-devnet-require-field report "engineRpcPrefix" "/engine")
  (smoke-gate-devnet-require-field report "engineRpcPrefixStatus" 200)
  (smoke-gate-devnet-require-field
   report "engineRpcPrefixBlockedStatus" 404)
  (smoke-gate-devnet-require-field
   report
   "engineCorsOrigins"
   '("https://engine-runner.example" "https://engine-observer.example"))
  (smoke-gate-devnet-require-field
   report "engineCorsHeader" "https://engine-runner.example")
  (smoke-gate-devnet-require-field
   report "engineCorsVaryHeader" "Origin")
  (smoke-gate-devnet-require-field
   report "engineVhosts" '("engine.runner" "localhost"))
  (smoke-gate-devnet-require-field report "publicRpcEnabled" nil)
  (smoke-gate-devnet-require-field report "rpcEndpoint" nil)
  (unless (and (stringp (smoke-gate-field report "configuredPublicEndpoint"))
               (smoke-gate-http-endpoint-p
                (smoke-gate-field report "configuredPublicEndpoint")))
    (error "Devnet Engine-only configured public endpoint is not probeable: ~S"
           report))
  (smoke-gate-devnet-require-field
   report "publicEndpointConnectable" nil)
  (let ((contract (smoke-gate-field report "connectionContract")))
    (smoke-gate-devnet-require-field
     contract "expectedEngineConnections" 2)
    (smoke-gate-devnet-require-field
     contract "expectedPublicConnections" 0)
    (smoke-gate-devnet-require-field
     contract "expectedTotalConnections" 2))
  (append report (list (cons "caseCount" 1))))

(defun smoke-gate-devnet-script-json (arguments)
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (append
        (list "sbcl"
              "--script"
              (namestring
               (smoke-gate-reference-path
                "scripts/devnet-smoke-gate.lisp"))
              "--"
              "--json")
        arguments)
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (= 0 status)
      (error "Devnet smoke gate failed with status ~D: ~A" status stderr))
    (smoke-gate-json-decode stdout)))

(defun smoke-gate-devnet-summary ()
  (let ((ready-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-ready"
                                 "json")))
        (log-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet"
                                 "log")))
        (pid-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet"
                                 "pid")))
        (database-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-chain"
                                 "sexp")))
        (report nil))
    (unwind-protect
         (progn
           (setf report
                 (smoke-gate-devnet-script-json
                  (list
                   "--all-fixtures"
                   "--ready-file"
                   ready-file
                   "--log-file"
                   log-file
                   "--pid-file"
                   pid-file
                   "--database"
                   database-file
                   "--prune-state-before"
                   (write-to-string
                    +smoke-gate-devnet-prune-state-before+))))
           (smoke-gate-validate-devnet-summary
            report
            ready-file
            log-file
            pid-file
            database-file))
      (when report
        (dolist (field '("readyFile" "logFile" "pidFile" "databaseFile"))
          (dolist (path (smoke-gate-devnet-case-files report field))
            (smoke-gate-delete-file-if-present path))))
      (smoke-gate-delete-file-if-present ready-file)
      (smoke-gate-delete-file-if-present log-file)
      (smoke-gate-delete-file-if-present pid-file)
      (smoke-gate-delete-file-if-present database-file))))

(defun smoke-gate-devnet-engine-only-summary ()
  (let ((ready-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-engine-only-ready"
                                 "json")))
        (log-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-engine-only"
                                 "log")))
        (pid-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-devnet-engine-only"
                                 "pid")))
        (report nil))
    (unwind-protect
         (progn
           (setf report
                 (smoke-gate-devnet-script-json
                  (list
                   "--engine-only-serve"
                   "--ready-file"
                   ready-file
                   "--log-file"
                   log-file
                   "--pid-file"
                   pid-file)))
           (smoke-gate-validate-devnet-engine-only-summary
            report
            ready-file
            log-file
            pid-file))
      (smoke-gate-delete-file-if-present ready-file)
      (smoke-gate-delete-file-if-present log-file)
      (smoke-gate-delete-file-if-present pid-file))))

(defun smoke-gate-validate-devnet-side-reorg-case-summary
    (report fixture-case ready-file log-file pid-file database-file)
  (unless (string= "ok" (smoke-gate-field report "status"))
    (error "Devnet side-reorg smoke gate returned non-ok status: ~S"
           report))
  (smoke-gate-devnet-require-field
   report "mode" "devnet-listener-boundary")
  (smoke-gate-devnet-require-field
   report "fixtureCase" fixture-case)
  (smoke-gate-devnet-require-field report "readyFile" ready-file)
  (smoke-gate-devnet-require-field report "logFile" log-file)
  (smoke-gate-devnet-require-field report "pidFile" pid-file)
  (smoke-gate-devnet-require-field report "databaseFile" database-file)
  (smoke-gate-devnet-case-require-false
   report "databasePruneStateBefore")
  (let ((side-reorg-count
          (smoke-gate-devnet-validate-side-reorg-case report)))
    (unless (= 1 side-reorg-count)
      (error "Devnet side-reorg smoke gate must cover one case, got ~D"
             side-reorg-count))
    (append
     report
     (list (cons "readyCaseCount" 1)
           (cons "logCaseCount" 1)
           (cons "pidCaseCount" 1)
           (cons "databaseCaseCount" 1)
           (cons "sideReorgCaseCount" side-reorg-count)))))

(defun smoke-gate-devnet-side-reorg-case-summary (fixture-case)
  (let ((ready-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-side-reorg-ready"
                                 "json")))
        (log-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-side-reorg"
                                 "log")))
        (pid-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-side-reorg"
                                 "pid")))
        (database-file
          (namestring
           (smoke-gate-temp-path "ethereum-lisp-phase-a-side-reorg-chain"
                                 "sexp")))
        (report nil))
    (unwind-protect
         (progn
           (setf report
                 (smoke-gate-devnet-script-json
                  (list
                   "--fixture-case"
                   fixture-case
                   "--ready-file"
                   ready-file
                   "--log-file"
                   log-file
                   "--pid-file"
                   pid-file
                   "--database"
                   database-file)))
           (smoke-gate-validate-devnet-side-reorg-case-summary
            report
            fixture-case
            ready-file
            log-file
            pid-file
            database-file))
      (smoke-gate-delete-file-if-present ready-file)
      (smoke-gate-delete-file-if-present log-file)
      (smoke-gate-delete-file-if-present pid-file)
      (smoke-gate-delete-file-if-present database-file))))

(defun smoke-gate-devnet-side-reorg-summary ()
  (let* ((reports
           (mapcar #'smoke-gate-devnet-side-reorg-case-summary
                   +smoke-gate-devnet-side-reorg-fixture-cases+))
         (case-count (length reports)))
    (list
     (cons "status" "ok")
     (cons "mode" "devnet-side-reorg-suite")
     (cons "caseCount" case-count)
     (cons "fixtureCases" +smoke-gate-devnet-side-reorg-fixture-cases+)
     (cons "cases" reports)
     (cons "readyCaseCount" case-count)
     (cons "logCaseCount" case-count)
     (cons "pidCaseCount" case-count)
     (cons "databaseCaseCount" case-count)
     (cons "sideReorgCaseCount"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report "sideReorgCaseCount"))
                   :initial-value 0))
     (cons "engineConnections"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report "databaseRpcSideEngineConnections"))
                   :initial-value 0))
     (cons "publicConnections"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report "databaseRpcSidePublicConnections"))
                   :initial-value 0))
     (cons "restoredPublicConnections"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report
                           "databaseRpcSideRestoredPublicConnections"))
                   :initial-value 0))
     (cons "totalConnections"
           (reduce #'+ reports
                   :key (lambda (report)
                          (smoke-gate-numeric-field
                           report "databaseRpcSideTotalConnections"))
                   :initial-value 0)))))

(defun smoke-gate-numeric-field (object field)
  (or (smoke-gate-field object field) 0))

(defun smoke-gate-report-counts
    (state transaction blockchain devnet devnet-side-reorg
     devnet-engine-only)
  (let* ((fixture-case-count
           (+ (smoke-gate-numeric-field state "count")
              (smoke-gate-numeric-field transaction "count")
              (smoke-gate-numeric-field blockchain "count")))
         (fixture-executed-count
           (+ (smoke-gate-numeric-field state "executedCount")
              (smoke-gate-numeric-field transaction "executedCount")
              (smoke-gate-numeric-field blockchain "executedCount")))
         (devnet-case-count
           (if devnet (smoke-gate-numeric-field devnet "caseCount") 0))
         (devnet-side-reorg-case-count
           (if devnet-side-reorg
               (smoke-gate-numeric-field
                devnet-side-reorg "sideReorgCaseCount")
               0))
         (devnet-engine-only-case-count
           (if devnet-engine-only
               (smoke-gate-numeric-field devnet-engine-only "caseCount")
               0)))
    (list
     (cons "fixtureCaseCount" fixture-case-count)
     (cons "fixtureExecutedCount" fixture-executed-count)
     (cons "totalCaseCount"
           (+ fixture-case-count
              devnet-case-count
              devnet-side-reorg-case-count
              devnet-engine-only-case-count))
     (cons "totalExecutedCount"
           (+ fixture-executed-count
              devnet-case-count
              devnet-side-reorg-case-count
              devnet-engine-only-case-count)))))

(defun smoke-gate-report (suite-root pinned-p &key devnet-p)
  (let ((state (smoke-gate-state-summary suite-root (not pinned-p)
                                         :pinned-p pinned-p))
        (transaction
          (smoke-gate-transaction-summary suite-root (not pinned-p)
                                          :pinned-p pinned-p))
        (blockchain (smoke-gate-blockchain-summary suite-root pinned-p))
        (devnet (and devnet-p (smoke-gate-devnet-summary)))
        (devnet-side-reorg
          (and devnet-p (smoke-gate-devnet-side-reorg-summary)))
        (devnet-engine-only
          (and devnet-p (smoke-gate-devnet-engine-only-summary))))
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
     (smoke-gate-report-counts
      state transaction blockchain devnet devnet-side-reorg
      devnet-engine-only)
     (when devnet
       (list (cons "devnet" devnet)))
     (when devnet-side-reorg
       (list (cons "devnetSideReorg" devnet-side-reorg)))
     (when devnet-engine-only
       (list (cons "devnetEngineOnly" devnet-engine-only))))))

(defun smoke-gate-print-text (report)
  (let ((state (smoke-gate-field report "state"))
        (transaction (smoke-gate-field report "transaction"))
        (blockchain (smoke-gate-field report "blockchain"))
        (execution-spec-tests
          (smoke-gate-field report "executionSpecTests"))
        (reference-clients (smoke-gate-field report "referenceClients"))
        (devnet (smoke-gate-field report "devnet"))
        (devnet-side-reorg (smoke-gate-field report "devnetSideReorg"))
        (devnet-engine-only (smoke-gate-field report "devnetEngineOnly")))
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
      (format t "devnetDatabasePruneStateBefore=~A~%"
              (smoke-gate-field devnet "databasePruneStateBefore"))
      (format t "devnetDatabasePrunedStateCaseCount=~D~%"
              (smoke-gate-field devnet "databasePrunedStateCaseCount"))
      (format t "devnetDatabaseRpcPrunedStateErrorCaseCount=~D~%"
              (smoke-gate-field
               devnet "databaseRpcPrunedStateErrorCaseCount"))
      (format t "devnetSuiteSideReorgCaseCount=~D~%"
              (smoke-gate-field devnet "sideReorgCaseCount"))
      (format t "devnetTotalConnections=~D~%"
              (smoke-gate-field devnet "totalConnections")))
    (when devnet-side-reorg
      (format t "devnetSideReorgStatus=~A~%"
              (smoke-gate-field devnet-side-reorg "status"))
      (format t "devnetSideReorgFixtureCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "caseCount"))
      (format t "devnetSideReorgFixtureCases=~S~%"
              (smoke-gate-field devnet-side-reorg "fixtureCases"))
      (format t "devnetSideReorgCaseCount=~D~%"
              (smoke-gate-field
               devnet-side-reorg "sideReorgCaseCount"))
      (format t "devnetSideReorgReadyCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "readyCaseCount"))
      (format t "devnetSideReorgLogCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "logCaseCount"))
      (format t "devnetSideReorgPidCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "pidCaseCount"))
      (format t "devnetSideReorgDatabaseCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "databaseCaseCount")))
    (when devnet-engine-only
      (format t "devnetEngineOnlyStatus=~A~%"
              (smoke-gate-field devnet-engine-only "status"))
      (format t "devnetEngineOnlyCaseCount=~D~%"
              (smoke-gate-field devnet-engine-only "caseCount"))
      (format t "devnetEngineOnlyPublicRpcEnabled=~A~%"
              (smoke-gate-field devnet-engine-only "publicRpcEnabled"))
      (format t "devnetEngineOnlyEngineRpcPrefix=~A~%"
              (smoke-gate-field devnet-engine-only "engineRpcPrefix"))
      (format t "devnetEngineOnlyEngineRpcPrefixStatus=~D~%"
              (smoke-gate-field devnet-engine-only
                                "engineRpcPrefixStatus"))
      (format t "devnetEngineOnlyEngineRpcPrefixBlockedStatus=~D~%"
              (smoke-gate-field devnet-engine-only
                                "engineRpcPrefixBlockedStatus"))
      (format t "devnetEngineOnlyEngineCorsOrigins=~S~%"
              (smoke-gate-field devnet-engine-only
                                "engineCorsOrigins"))
      (format t "devnetEngineOnlyEngineCorsHeader=~A~%"
              (smoke-gate-field devnet-engine-only
                                "engineCorsHeader"))
      (format t "devnetEngineOnlyEngineVhosts=~S~%"
              (smoke-gate-field devnet-engine-only "engineVhosts"))
      (format t "devnetEngineOnlyConfiguredPublicEndpoint=~A~%"
              (smoke-gate-field devnet-engine-only
                                "configuredPublicEndpoint"))
      (format t "devnetEngineOnlyPublicEndpointConnectable=~A~%"
              (smoke-gate-field devnet-engine-only
                                "publicEndpointConnectable"))
      (format t "devnetEngineOnlyEngineConnections=~D~%"
              (smoke-gate-field devnet-engine-only "engineConnections"))
      (format t "devnetEngineOnlyPublicConnections=~D~%"
              (smoke-gate-field devnet-engine-only "publicConnections"))
      (format t "devnetEngineOnlyTotalConnections=~D~%"
              (smoke-gate-field devnet-engine-only "totalConnections")))))

(defun smoke-gate-main ()
  (let* ((args (smoke-gate-arguments))
         (help-p (smoke-gate-help-p args)))
    (if help-p
        (smoke-gate-print-help)
        (let* ((pinned-p (smoke-gate-pinned-v5.4.0-p args))
               (devnet-p (smoke-gate-devnet-p args))
               (json-p (smoke-gate-json-p args))
               (root-argument (smoke-gate-argument-root args)))
          (load (merge-pathnames "tests/load-tests.lisp"
                                 *ethereum-lisp-smoke-gate-root*))
          (let* ((suite-root (smoke-gate-suite-root root-argument pinned-p))
                 (report (smoke-gate-report
                          suite-root pinned-p :devnet-p devnet-p)))
            (if json-p
                (format t "~&~A~%" (smoke-gate-json-encode report))
                (smoke-gate-print-text report)))))))

(smoke-gate-main)
