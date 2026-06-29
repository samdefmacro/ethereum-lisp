(defparameter *ethereum-lisp-drift-map-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)

(defconstant +drift-map-json-flag+ "--json")
(defconstant +drift-map-help-flag+ "--help")
(defconstant +drift-map-root-option+ "--root")
(defconstant +drift-map-limit-option+ "--limit")
(defconstant +drift-map-state-limit-option+ "--state-limit")
(defconstant +drift-map-transaction-limit-option+ "--transaction-limit")
(defconstant +drift-map-blockchain-limit-option+ "--blockchain-limit")
(defconstant +drift-map-failures-only-flag+ "--failures-only")
(defconstant +drift-map-eest-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")

(defun drift-map-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun drift-map-help-p (args)
  (member +drift-map-help-flag+ args :test #'string=))

(defun drift-map-print-help ()
  (format t "~&Usage: sbcl --script scripts/phase-a-drift-map.lisp -- [options]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --root PATH               EEST fixture suite root.~%")
  (format t "  --limit NUMBER            Classify at most NUMBER candidates per suite.~%")
  (format t "  --state-limit NUMBER      Override the state-test candidate limit.~%")
  (format t "  --transaction-limit NUMBER Override the transaction-test candidate limit.~%")
  (format t "  --blockchain-limit NUMBER Override the blockchain replay candidate limit.~%")
  (format t "  --failures-only           Keep counts but include only non-passing result records.~%")
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
(when (drift-map-help-p (drift-map-arguments))
  (drift-map-print-help)
  (sb-ext:exit :code 0))

(defun drift-map-json-p (args)
  (member +drift-map-json-flag+ args :test #'string=))

(defun drift-map-failures-only-p (args)
  (member +drift-map-failures-only-flag+ args :test #'string=))

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

(defun drift-map-options (args)
  (let ((root nil)
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
             (string= arg +drift-map-failures-only-flag+)))
        ((or (string= arg +drift-map-root-option+)
             (string= arg +drift-map-limit-option+)
             (string= arg +drift-map-state-limit-option+)
             (string= arg +drift-map-transaction-limit-option+)
             (string= arg +drift-map-blockchain-limit-option+))
         (unless args
           (error "~A requires a value" arg))
         (let ((value (pop args)))
           (when (drift-map-option-like-p value)
             (error "~A requires a value, got option ~A" arg value))
           (cond
             ((string= arg +drift-map-root-option+)
              (setf root
                    (drift-map-set-single-value root arg value)))
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

(defun drift-map-parse-json (string)
  (apply #'drift-map-call "parse-json" (list string)))

(defun drift-map-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun drift-map-script-path (relative-path)
  (namestring (merge-pathnames relative-path
                               *ethereum-lisp-drift-map-script-root*)))

(defun drift-map-classifier-command
    (script root limit failures-only-p)
  (let ((command
          (list "sbcl"
                "--script"
                (drift-map-script-path script)
                "--"
                "--json")))
    (when root
      (setf command
            (append command
                    (list "--root" root))))
    (when limit
      (setf command
            (append command
                    (list "--limit" (write-to-string limit :base 10)))))
    (when failures-only-p
      (setf command
            (append command
                    (list "--failures-only"))))
    command))

(defun drift-map-run-classifier (suite script root limit failures-only-p)
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (drift-map-classifier-command script root limit failures-only-p)
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (= 0 status)
      (error "~A classifier failed with status ~D: ~A" suite status stderr))
    (when (plusp (length stderr))
      (error "~A classifier wrote unexpected stderr: ~A" suite stderr))
    (drift-map-parse-json stdout)))

(defun drift-map-suite-report (suite report)
  (let ((passing-count
          (drift-map-field report "passingCount"))
        (implementation-bug-count
          (drift-map-field report "implementationBugCandidateCount"))
        (fixture-harness-error-count
          (drift-map-field report "fixtureHarnessErrorCount"))
        (out-of-scope-count
          (drift-map-field report "outOfScopeCount")))
    (list
     (cons "suite" suite)
     (cons "mode" (drift-map-field report "mode"))
     (cons "root" (drift-map-field report "root"))
     (cons "discoveredCount" (drift-map-field report "discoveredCount"))
     (cons "pinnedCount" (drift-map-field report "pinnedCount"))
     (cons "candidateCount" (drift-map-field report "candidateCount"))
     (cons "classifiedCount" (drift-map-field report "classifiedCount"))
     (cons "passingCount" passing-count)
     (cons "knownImplementationDriftCount" 0)
     (cons "outOfScopeForkFeatureCount" out-of-scope-count)
     (cons "implementationBugCandidateCount" implementation-bug-count)
     (cons "fixtureHarnessErrorCount" fixture-harness-error-count)
     (cons "families" (drift-map-field report "families"))
     (cons "results" (drift-map-field report "results")))))

(defun drift-map-sum-field (suites name)
  (loop for suite in suites
        sum (or (drift-map-field suite name) 0)))

(defun drift-map-overall-report (suites)
  (let ((implementation-bug-count
          (drift-map-sum-field suites "implementationBugCandidateCount"))
        (fixture-harness-error-count
          (drift-map-sum-field suites "fixtureHarnessErrorCount")))
    (list
     (cons "suiteCount" (length suites))
     (cons "candidateCount" (drift-map-sum-field suites "candidateCount"))
     (cons "classifiedCount" (drift-map-sum-field suites "classifiedCount"))
     (cons "passingCount" (drift-map-sum-field suites "passingCount"))
     (cons "knownImplementationDriftCount"
           (drift-map-sum-field suites "knownImplementationDriftCount"))
     (cons "outOfScopeForkFeatureCount"
           (drift-map-sum-field suites "outOfScopeForkFeatureCount"))
     (cons "implementationBugCandidateCount" implementation-bug-count)
     (cons "fixtureHarnessErrorCount" fixture-harness-error-count)
     (cons "phaseAMaterializableClear"
           (if (and (zerop implementation-bug-count)
                    (zerop fixture-harness-error-count))
               t
               :false)))))

(defun drift-map-report
    (root state-limit transaction-limit blockchain-limit failures-only-p)
  (let* ((state
           (drift-map-suite-report
            "state"
            (drift-map-run-classifier
             "state"
             "scripts/classify-state-test-selectors.lisp"
             root
             state-limit
             failures-only-p)))
         (transaction
           (drift-map-suite-report
            "transaction"
            (drift-map-run-classifier
             "transaction"
             "scripts/classify-transaction-test-selectors.lisp"
             root
             transaction-limit
             failures-only-p)))
         (blockchain
           (drift-map-suite-report
            "blockchain"
            (drift-map-run-classifier
             "blockchain"
             "scripts/classify-blockchain-replay-selectors.lisp"
             root
             blockchain-limit
             failures-only-p)))
         (suites (list state transaction blockchain)))
    (list
     (cons "mode" "phase-a-drift-map")
     (cons "root" (or root
                      (let ((configured
                              (uiop:getenv +drift-map-eest-root-env+)))
                        (if (drift-map-blank-string-p configured)
                            :false
                            configured))))
     (cons "failuresOnly" (if failures-only-p t :false))
     (cons "overall" (drift-map-overall-report suites))
     (cons "suites" suites))))

(defun drift-map-print-suite (suite)
  (format t "suite=~A candidates=~D classified=~D passing=~D knownImplementationDrift=~D outOfScopeForkFeature=~D implementationBugCandidates=~D fixtureHarnessErrors=~D~%"
          (drift-map-field suite "suite")
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

(defun drift-map-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-drift-map-script-root*))
  (let* ((args (drift-map-arguments))
         (options (drift-map-options args))
         (root (getf options :root))
         (limit (getf options :limit))
         (report
           (drift-map-report
            root
            (or (getf options :state-limit) limit)
            (or (getf options :transaction-limit) limit)
            (or (getf options :blockchain-limit) limit)
            (drift-map-failures-only-p args))))
    (if (drift-map-json-p args)
        (format t "~&~A~%" (drift-map-json-encode report))
        (drift-map-print-text-report report))))

(drift-map-main)
