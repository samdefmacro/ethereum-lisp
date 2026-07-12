(defparameter *ethereum-lisp-drift-map-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defvar *drift-map-script-run-main-p* t)
(defvar *drift-map-classifier-services-loaded-p* nil)

(require :asdf)

(defconstant +drift-map-json-flag+ "--json")
(defconstant +drift-map-help-flag+ "--help")
(defconstant +drift-map-root-option+ "--root")
(defconstant +drift-map-suite-option+ "--suite")
(defconstant +drift-map-prefix-option+ "--prefix")
(defconstant +drift-map-state-prefix-option+ "--state-prefix")
(defconstant +drift-map-transaction-prefix-option+ "--transaction-prefix")
(defconstant +drift-map-blockchain-prefix-option+ "--blockchain-prefix")
(defconstant +drift-map-limit-option+ "--limit")
(defconstant +drift-map-state-limit-option+ "--state-limit")
(defconstant +drift-map-transaction-limit-option+ "--transaction-limit")
(defconstant +drift-map-blockchain-limit-option+ "--blockchain-limit")
(defconstant +drift-map-failures-only-flag+ "--failures-only")
(defconstant +drift-map-summary-only-flag+ "--summary-only")
(defconstant +drift-map-eest-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")
(defparameter *drift-map-value-options*
  (list +drift-map-root-option+
        +drift-map-suite-option+
        +drift-map-prefix-option+
        +drift-map-state-prefix-option+
        +drift-map-transaction-prefix-option+
        +drift-map-blockchain-prefix-option+
        +drift-map-limit-option+
        +drift-map-state-limit-option+
        +drift-map-transaction-limit-option+
        +drift-map-blockchain-limit-option+))
(defparameter *drift-map-boolean-options*
  (list +drift-map-json-flag+
        +drift-map-help-flag+
        +drift-map-failures-only-flag+
        +drift-map-summary-only-flag+))

(defun drift-map-parse-boolean-assignment (option value)
  (let ((normalized (and (stringp value) (string-downcase value))))
    (cond
      ((member normalized '("true" "1") :test #'string=) t)
      ((member normalized '("false" "0") :test #'string=) nil)
      (t (error "~A boolean value must be true or false" option)))))

(defun drift-map-normalize-option-args (args)
  (loop for arg in args
        for equals-position = (and (stringp arg)
                                   (<= 2 (length arg))
                                   (string= "--" arg :end2 2)
                                   (position #\= arg :start 2))
        for option = (and equals-position (subseq arg 0 equals-position))
        for value = (and equals-position (subseq arg (1+ equals-position)))
        append
        (cond
          ((and equals-position
                (member option *drift-map-value-options* :test #'string=))
           (list option value))
          ((and equals-position
                (member option *drift-map-boolean-options* :test #'string=))
           (if (drift-map-parse-boolean-assignment option value)
               (list option)
               '()))
          (t
           (list arg)))))

(defun drift-map-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    (drift-map-normalize-option-args args))
  #-sbcl nil)

(defun drift-map-help-p (args)
  (member +drift-map-help-flag+ args :test #'string=))

(defun drift-map-print-help ()
  (format t "~&Usage: sbcl --script scripts/phase-a-drift-map.lisp -- [options]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --root PATH               EEST fixture suite root.~%")
  (format t "  --suite SUITE             Run one suite: state, transaction, or blockchain.~%")
  (format t "  --prefix PREFIX           Classify only selectors with this prefix in every suite.~%")
  (format t "  --state-prefix PREFIX     Override the state-test selector prefix.~%")
  (format t "  --transaction-prefix PREFIX Override the transaction-test selector prefix.~%")
  (format t "  --blockchain-prefix PREFIX Override the blockchain replay selector prefix.~%")
  (format t "  --limit NUMBER            Classify at most NUMBER candidates per suite.~%")
  (format t "  --state-limit NUMBER      Override the state-test candidate limit.~%")
  (format t "  --transaction-limit NUMBER Override the transaction-test candidate limit.~%")
  (format t "  --blockchain-limit NUMBER Override the blockchain replay candidate limit.~%")
  (format t "  --failures-only           Keep counts but include only non-passing result records.~%")
  (format t "  --summary-only            Keep counts and family summaries but omit result records.~%")
  (format t "  --json                    Print machine-readable JSON output.~%")
  (format t "  --help                    Print this help.~%")
  (format t "~%")
  (format t "Canonical categories: passing, known-implementation-drift, ~
out-of-scope-fork-feature, implementation-bug-candidate.~%")
  (format t "Fixture harness errors are reported separately because they are not ~
implementation drift.~%")
  (format t "Without --root, ~A is used by the child classifiers when set.~%"
          +drift-map-eest-root-env+))

#+sbcl
(when (and *drift-map-script-run-main-p*
           (drift-map-help-p (drift-map-arguments)))
  (drift-map-print-help)
  (sb-ext:exit :code 0))

(defun drift-map-json-p (args)
  (member +drift-map-json-flag+ args :test #'string=))

(defun drift-map-failures-only-p (args)
  (member +drift-map-failures-only-flag+ args :test #'string=))

(defun drift-map-summary-only-p (args)
  (member +drift-map-summary-only-flag+ args :test #'string=))

(defun drift-map-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun drift-map-blank-string-p (value)
  (or (null value)
      (zerop (length
              (string-trim '(#\Space #\Tab #\Newline #\Return) value)))))

(defun drift-map-set-single-value (current option value)
  (when current
    (error "Only one ~A option is supported" option))
  value)

(defun drift-map-parse-limit (option value)
  (handler-case
      (let ((limit (parse-integer value :junk-allowed nil)))
        (unless (plusp limit)
          (error "~A requires a positive integer" option))
        limit)
    (error ()
      (error "~A requires a positive integer, got ~A" option value))))

(defun drift-map-parse-suite (value)
  (unless (member value '("state" "transaction" "blockchain") :test #'string=)
    (error "~A requires state, transaction, or blockchain, got ~A"
           +drift-map-suite-option+
           value))
  value)

(defun drift-map-options (args)
  (let ((root nil)
        (suite nil)
        (prefix nil)
        (state-prefix nil)
        (transaction-prefix nil)
        (blockchain-prefix nil)
        (limit nil)
        (state-limit nil)
        (transaction-limit nil)
        (blockchain-limit nil))
    (loop while args
          for arg = (pop args)
          do
      (cond
        ((or (string= arg +drift-map-json-flag+)
             (string= arg +drift-map-help-flag+)
             (string= arg +drift-map-failures-only-flag+)
             (string= arg +drift-map-summary-only-flag+)))
        ((member arg *drift-map-value-options* :test #'string=)
         (unless args
           (error "~A requires a value" arg))
         (let ((value (pop args)))
           (when (drift-map-option-like-p value)
             (error "~A requires a value, got option ~A" arg value))
           (cond
             ((string= arg +drift-map-root-option+)
              (setf root
                    (drift-map-set-single-value root arg value)))
             ((string= arg +drift-map-suite-option+)
              (setf suite
                    (drift-map-set-single-value
                     suite
                     arg
                     (drift-map-parse-suite value))))
             ((string= arg +drift-map-prefix-option+)
              (setf prefix
                    (drift-map-set-single-value prefix arg value)))
             ((string= arg +drift-map-state-prefix-option+)
              (setf state-prefix
                    (drift-map-set-single-value state-prefix arg value)))
             ((string= arg +drift-map-transaction-prefix-option+)
              (setf transaction-prefix
                    (drift-map-set-single-value transaction-prefix arg value)))
             ((string= arg +drift-map-blockchain-prefix-option+)
              (setf blockchain-prefix
                    (drift-map-set-single-value blockchain-prefix arg value)))
             ((string= arg +drift-map-limit-option+)
              (setf limit
                    (drift-map-set-single-value
                     limit
                     arg
                     (drift-map-parse-limit arg value))))
             ((string= arg +drift-map-state-limit-option+)
              (setf state-limit
                    (drift-map-set-single-value
                     state-limit
                     arg
                     (drift-map-parse-limit arg value))))
             ((string= arg +drift-map-transaction-limit-option+)
              (setf transaction-limit
                    (drift-map-set-single-value
                     transaction-limit
                     arg
                     (drift-map-parse-limit arg value))))
             (t
              (setf blockchain-limit
                    (drift-map-set-single-value
                     blockchain-limit
                     arg
                     (drift-map-parse-limit arg value)))))))
        ((drift-map-option-like-p arg)
         (error "Unsupported drift map option ~A" arg))
        (t
         (setf root
               (drift-map-set-single-value
                root
                +drift-map-root-option+
                arg)))))
    (list :root root
          :suite suite
          :prefix prefix
          :state-prefix state-prefix
          :transaction-prefix transaction-prefix
          :blockchain-prefix blockchain-prefix
          :limit limit
          :state-limit state-limit
          :transaction-limit transaction-limit
          :blockchain-limit blockchain-limit)))

(defun drift-map-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "Helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun drift-map-json-encode (object)
  (apply #'drift-map-call "json-encode" (list object)))

(defun drift-map-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun drift-map-canonical-classification (classification)
  (cond
    ((string= classification "out-of-scope")
     "out-of-scope-fork-feature")
    (t classification)))

(defun drift-map-canonical-result (result)
  (loop for field in result
        collect
        (if (string= (car field) "classification")
            (cons "classification"
                  (drift-map-canonical-classification (cdr field)))
            field)))

(defun drift-map-canonical-family-summary (family)
  (loop for field in family
        collect
        (if (string= (car field) "outOfScopeCount")
            (cons "outOfScopeForkFeatureCount" (cdr field))
            field)))

(defun drift-map-classifier-args (root limit prefix failures-only-p)
  (let ((args (list "--json")))
    (when root
      (setf args (append args (list "--root" root))))
    (when limit
      (setf args
            (append args
                    (list "--limit" (write-to-string limit :base 10)))))
    (unless (drift-map-blank-string-p prefix)
      (setf args (append args (list "--prefix" prefix))))
    (when failures-only-p
      (setf args (append args (list "--failures-only"))))
    args))

(defun drift-map-load-classifier-services ()
  (unless *drift-map-classifier-services-loaded-p*
    (let ((*classifier-script-run-main-p* nil)
          (*transaction-classifier-script-run-main-p* nil)
          (*state-classifier-script-run-main-p* nil))
      (declare (special *classifier-script-run-main-p*
                        *transaction-classifier-script-run-main-p*
                        *state-classifier-script-run-main-p*))
      (dolist (script '("scripts/classify-state-test-selectors.lisp"
                        "scripts/classify-transaction-test-selectors.lisp"
                        "scripts/classify-blockchain-replay-selectors.lisp"))
        (load (merge-pathnames script
                               *ethereum-lisp-drift-map-script-root*))))
    (setf *drift-map-classifier-services-loaded-p* t)))

(defun drift-map-run-classifier
    (suite script root limit prefix failures-only-p environment-lookup)
  (declare (ignore script))
  (drift-map-load-classifier-services)
  (let ((args (drift-map-classifier-args
               root limit prefix failures-only-p))
        (output (make-broadcast-stream)))
    (cond
      ((string= suite "state")
       (state-classifier-script-main
        :args args
        :environment-lookup environment-lookup
        :output output
        :load-tests-p nil))
      ((string= suite "transaction")
       (transaction-classifier-script-main
        :args args
        :environment-lookup environment-lookup
        :output output
        :load-tests-p nil))
      ((string= suite "blockchain")
       (classifier-script-main
        :args args
        :environment-lookup environment-lookup
        :output output
        :load-tests-p nil))
      (t
       (error "Unsupported classifier suite ~A" suite)))))

(defun drift-map-suite-report (suite report summary-only-p)
  (let ((passing-count
          (drift-map-field report "passingCount"))
        (known-implementation-drift-count
          (or (drift-map-field report "knownImplementationDriftCount")
              0))
        (implementation-bug-count
          (drift-map-field report "implementationBugCandidateCount"))
        (fixture-harness-error-count
          (drift-map-field report "fixtureHarnessErrorCount"))
        (out-of-scope-count
          (or (drift-map-field report "outOfScopeForkFeatureCount")
              (drift-map-field report "outOfScopeCount"))))
    (list
     (cons "suite" suite)
     (cons "mode" (drift-map-field report "mode"))
     (cons "root" (drift-map-field report "root"))
     (cons "prefix" (drift-map-field report "prefix"))
     (cons "discoveredCount" (drift-map-field report "discoveredCount"))
     (cons "pinnedCount" (drift-map-field report "pinnedCount"))
     (cons "candidateCount" (drift-map-field report "candidateCount"))
     (cons "classifiedCount" (drift-map-field report "classifiedCount"))
     (cons "passingCount" passing-count)
     (cons "knownImplementationDriftCount"
           known-implementation-drift-count)
     (cons "outOfScopeForkFeatureCount" out-of-scope-count)
     (cons "implementationBugCandidateCount" implementation-bug-count)
     (cons "fixtureHarnessErrorCount" fixture-harness-error-count)
     (cons "families"
           (mapcar #'drift-map-canonical-family-summary
                   (drift-map-field report "families")))
     (cons "results"
           (if summary-only-p
               (make-array 0)
               (mapcar #'drift-map-canonical-result
                       (drift-map-field report "results")))))))

(defun drift-map-sum-field (suites name)
  (loop for suite in suites
        sum (or (drift-map-field suite name) 0)))

(defun drift-map-overall-report (suites)
  (let ((known-implementation-drift-count
          (drift-map-sum-field suites "knownImplementationDriftCount"))
        (implementation-bug-count
          (drift-map-sum-field suites "implementationBugCandidateCount"))
        (fixture-harness-error-count
          (drift-map-sum-field suites "fixtureHarnessErrorCount")))
    (list
     (cons "suiteCount" (length suites))
     (cons "candidateCount" (drift-map-sum-field suites "candidateCount"))
     (cons "classifiedCount" (drift-map-sum-field suites "classifiedCount"))
     (cons "passingCount" (drift-map-sum-field suites "passingCount"))
     (cons "knownImplementationDriftCount"
           known-implementation-drift-count)
     (cons "outOfScopeForkFeatureCount"
           (drift-map-sum-field suites "outOfScopeForkFeatureCount"))
     (cons "implementationBugCandidateCount" implementation-bug-count)
     (cons "fixtureHarnessErrorCount" fixture-harness-error-count)
     (cons "phaseAMaterializableClear"
           (if (and (zerop known-implementation-drift-count)
                    (zerop implementation-bug-count)
                    (zerop fixture-harness-error-count))
               t
               :false)))))

(defun drift-map-report
    (root suite state-limit transaction-limit blockchain-limit
     state-prefix transaction-prefix blockchain-prefix failures-only-p
     summary-only-p &key (environment-lookup #'uiop:getenv))
  (let ((suites
          (loop for (suite-name script limit prefix)
                  in `(("state"
                        "scripts/classify-state-test-selectors.lisp"
                        ,state-limit
                        ,state-prefix)
                       ("transaction"
                        "scripts/classify-transaction-test-selectors.lisp"
                        ,transaction-limit
                        ,transaction-prefix)
                       ("blockchain"
                        "scripts/classify-blockchain-replay-selectors.lisp"
                        ,blockchain-limit
                        ,blockchain-prefix))
                when (or (null suite) (string= suite suite-name))
                  collect
                  (drift-map-suite-report
                   suite-name
                   (drift-map-run-classifier
                    suite-name
                    script
                    root
                    limit
                    prefix
                    failures-only-p
                    environment-lookup)
                   summary-only-p))))
    (list
     (cons "mode" "phase-a-drift-map")
     (cons "root" (or root
                      (let ((configured
                              (funcall environment-lookup
                                       +drift-map-eest-root-env+)))
                        (if (drift-map-blank-string-p configured)
                            :false
                            configured))))
     (cons "failuresOnly" (if failures-only-p t :false))
     (cons "summaryOnly" (if summary-only-p t :false))
     (cons "suite" (or suite :false))
     (cons "overall" (drift-map-overall-report suites))
     (cons "suites" suites))))

(defun drift-map-print-suite (suite)
  (format t "suite=~A prefix=~A candidates=~D classified=~D passing=~D knownImplementationDrift=~D outOfScopeForkFeature=~D implementationBugCandidates=~D fixtureHarnessErrors=~D~%"
          (drift-map-field suite "suite")
          (drift-map-field suite "prefix")
          (drift-map-field suite "candidateCount")
          (drift-map-field suite "classifiedCount")
          (drift-map-field suite "passingCount")
          (drift-map-field suite "knownImplementationDriftCount")
          (drift-map-field suite "outOfScopeForkFeatureCount")
          (drift-map-field suite "implementationBugCandidateCount")
          (drift-map-field suite "fixtureHarnessErrorCount")))

(defun drift-map-print-text-report (report)
  (let ((overall (drift-map-field report "overall")))
    (format t "~&mode=~A~%" (drift-map-field report "mode"))
    (format t "root=~A~%" (drift-map-field report "root"))
    (format t "failuresOnly=~A~%" (drift-map-field report "failuresOnly"))
    (format t "summaryOnly=~A~%" (drift-map-field report "summaryOnly"))
    (format t "candidateCount=~D classifiedCount=~D passing=~D knownImplementationDrift=~D outOfScopeForkFeature=~D implementationBugCandidates=~D fixtureHarnessErrors=~D phaseAMaterializableClear=~A~%"
            (drift-map-field overall "candidateCount")
            (drift-map-field overall "classifiedCount")
            (drift-map-field overall "passingCount")
            (drift-map-field overall "knownImplementationDriftCount")
            (drift-map-field overall "outOfScopeForkFeatureCount")
            (drift-map-field overall "implementationBugCandidateCount")
            (drift-map-field overall "fixtureHarnessErrorCount")
            (drift-map-field overall "phaseAMaterializableClear"))
    (dolist (suite (drift-map-field report "suites"))
      (drift-map-print-suite suite))))

(defun drift-map-main
    (&key
       (args (drift-map-arguments))
       (environment-lookup #'uiop:getenv)
       (output *standard-output*)
       (error-output *error-output*)
       (load-tests-p t))
  (let ((*standard-output* output)
        (*error-output* error-output))
    (when (drift-map-help-p args)
      (drift-map-print-help)
      (return-from drift-map-main :help))
    (let* ((args (drift-map-normalize-option-args args))
         (options (drift-map-options args))
         (root (getf options :root))
         (limit (getf options :limit))
         (prefix (getf options :prefix)))
    (when load-tests-p
      (load (merge-pathnames "tests/load-tests.lisp"
                             *ethereum-lisp-drift-map-script-root*)))
    (let ((report
            (drift-map-report
             root
             (getf options :suite)
             (or (getf options :state-limit) limit)
             (or (getf options :transaction-limit) limit)
             (or (getf options :blockchain-limit) limit)
             (or (getf options :state-prefix) prefix)
             (or (getf options :transaction-prefix) prefix)
             (or (getf options :blockchain-prefix) prefix)
             (drift-map-failures-only-p args)
             (drift-map-summary-only-p args)
             :environment-lookup environment-lookup)))
      (if (drift-map-json-p args)
          (format t "~&~A~%" (drift-map-json-encode report))
          (drift-map-print-text-report report))
      report))))

(when *drift-map-script-run-main-p*
  (drift-map-main))
