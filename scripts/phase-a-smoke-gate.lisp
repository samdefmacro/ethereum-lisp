(defparameter *ethereum-lisp-smoke-gate-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defconstant +smoke-gate-pinned-v5.4.0-flag+ "--pinned-v5.4.0")
(defconstant +smoke-gate-json-flag+ "--json")
(defconstant +smoke-gate-root-option+ "--root")
(defconstant +smoke-gate-help-flag+ "--help")
(defconstant +smoke-gate-default-root+
  "tests/fixtures/execution-spec-tests-root/")

(defun smoke-gate-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun smoke-gate-pinned-v5.4.0-p (args)
  (member +smoke-gate-pinned-v5.4.0-flag+ args :test #'string=))

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
  (format t "  --json             Print machine-readable JSON output.~%")
  (format t "  --help             Print this help without loading the test system.~%")
  (format t "~%")
  (format t "Default ROOT: ~A~%" +smoke-gate-default-root+))

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

(defun smoke-gate-json-encode (object)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) object)))

(defun smoke-gate-field (object name)
  (cdr (assoc name object :test #'string=)))

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

(defun smoke-gate-report (suite-root pinned-p)
  (let ((state (smoke-gate-state-summary suite-root (not pinned-p)))
        (transaction
          (smoke-gate-transaction-summary suite-root (not pinned-p)))
        (blockchain (smoke-gate-blockchain-summary suite-root pinned-p)))
    (list
     (cons "suiteRoot" suite-root)
     (cons "mode" (if pinned-p "pinned-v5.4.0" "in-repo"))
     (cons "status" "ok")
     (cons "state" state)
     (cons "transaction" transaction)
     (cons "blockchain" blockchain))))

(defun smoke-gate-print-text (report)
  (let ((state (smoke-gate-field report "state"))
        (transaction (smoke-gate-field report "transaction"))
        (blockchain (smoke-gate-field report "blockchain")))
    (format t "~&status=~A~%" (smoke-gate-field report "status"))
    (format t "suiteRoot=~A~%" (smoke-gate-field report "suiteRoot"))
    (format t "mode=~A~%" (smoke-gate-field report "mode"))
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
            (smoke-gate-field blockchain "kindCounts"))))

(defun smoke-gate-main ()
  (let* ((args (smoke-gate-arguments))
         (help-p (smoke-gate-help-p args))
         (pinned-p (smoke-gate-pinned-v5.4.0-p args))
         (json-p (smoke-gate-json-p args))
         (suite-root (or (smoke-gate-argument-root args)
                         +smoke-gate-default-root+)))
    (if help-p
        (smoke-gate-print-help)
        (progn
          (load (merge-pathnames "tests/load-tests.lisp"
                                 *ethereum-lisp-smoke-gate-root*))
          (let ((report (smoke-gate-report suite-root pinned-p)))
            (if json-p
                (format t "~&~A~%" (smoke-gate-json-encode report))
                (smoke-gate-print-text report)))))))

(smoke-gate-main)
