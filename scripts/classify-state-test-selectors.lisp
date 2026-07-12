(defparameter *ethereum-lisp-state-classifier-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)

(defconstant +state-classifier-script-json-flag+ "--json")
(defconstant +state-classifier-script-help-flag+ "--help")
(defconstant +state-classifier-script-root-option+ "--root")
(defconstant +state-classifier-script-prefix-option+ "--prefix")
(defconstant +state-classifier-script-limit-option+ "--limit")
(defconstant +state-classifier-script-include-pinned-flag+ "--include-pinned")
(defconstant +state-classifier-script-failures-only-flag+ "--failures-only")
(defconstant +state-classifier-script-eest-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")
(defparameter *state-classifier-script-value-options*
  (list +state-classifier-script-root-option+
        +state-classifier-script-prefix-option+
        +state-classifier-script-limit-option+))
(defparameter *state-classifier-script-boolean-options*
  (list +state-classifier-script-json-flag+
        +state-classifier-script-help-flag+
        +state-classifier-script-include-pinned-flag+
        +state-classifier-script-failures-only-flag+))

(defun state-classifier-script-parse-boolean-assignment (option value)
  (let ((normalized (and (stringp value) (string-downcase value))))
    (cond
      ((member normalized '("true" "1") :test #'string=) t)
      ((member normalized '("false" "0") :test #'string=) nil)
      (t (error "~A boolean value must be true or false" option)))))

(defun state-classifier-script-normalize-option-args (args)
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
                (member option
                        *state-classifier-script-value-options*
                        :test #'string=))
           (list option value))
          ((and equals-position
                (member option
                        *state-classifier-script-boolean-options*
                        :test #'string=))
           (if (state-classifier-script-parse-boolean-assignment option value)
               (list option)
               '()))
          (t
           (list arg)))))

(defun state-classifier-script-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    (state-classifier-script-normalize-option-args args))
  #-sbcl nil)

(defun state-classifier-script-help-p (args)
  (member +state-classifier-script-help-flag+ args :test #'string=))

(defun state-classifier-script-print-help ()
  (format t "~&Usage: sbcl --script scripts/classify-state-test-selectors.lisp -- [options]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --root PATH          EEST fixture suite root.~%")
  (format t "  --prefix PREFIX      Only classify selectors whose names start with PREFIX.~%")
  (format t "  --limit NUMBER       Classify at most NUMBER candidate selectors.~%")
  (format t "  --include-pinned     Include already pinned selectors in the candidate set.~%")
  (format t "  --failures-only      Keep full counts but print only non-passing results.~%")
  (format t "  --json               Print machine-readable JSON output.~%")
  (format t "  --help               Print this help.~%")
  (format t "~%")
  (format t "Classifications: passing, known-implementation-drift, ~
out-of-scope-fork-feature, implementation-bug-candidate, ~
fixture-harness-error.~%")
  (format t "Without --root, ~A is used when set.~%"
          +state-classifier-script-eest-root-env+))

#+sbcl
(when (state-classifier-script-help-p
       (state-classifier-script-arguments))
  (state-classifier-script-print-help)
  (sb-ext:exit :code 0))

(defun state-classifier-script-json-p (args)
  (member +state-classifier-script-json-flag+ args :test #'string=))

(defun state-classifier-script-include-pinned-p (args)
  (member +state-classifier-script-include-pinned-flag+ args :test #'string=))

(defun state-classifier-script-failures-only-p (args)
  (member +state-classifier-script-failures-only-flag+ args :test #'string=))

(defun state-classifier-script-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun state-classifier-script-blank-string-p (value)
  (or (null value)
      (zerop (length
              (string-trim '(#\Space #\Tab #\Newline #\Return) value)))))

(defun state-classifier-script-set-single-value (current option value)
  (when current
    (error "Only one ~A option is supported" option))
  value)

(defun state-classifier-script-parse-limit (value)
  (handler-case
      (let ((limit (parse-integer value :junk-allowed nil)))
        (unless (plusp limit)
          (error "~A requires a positive integer"
                 +state-classifier-script-limit-option+))
        limit)
    (error ()
      (error "~A requires a positive integer, got ~A"
             +state-classifier-script-limit-option+
             value))))

(defun state-classifier-script-options (args)
  (let ((root nil)
        (prefix nil)
        (limit nil))
    (loop while args
          for arg = (pop args)
          do
      (cond
        ((or (string= arg +state-classifier-script-json-flag+)
             (string= arg +state-classifier-script-help-flag+)
             (string= arg +state-classifier-script-include-pinned-flag+)
             (string= arg +state-classifier-script-failures-only-flag+)))
        ((or (string= arg +state-classifier-script-root-option+)
             (string= arg +state-classifier-script-prefix-option+)
             (string= arg +state-classifier-script-limit-option+))
         (unless args
           (error "~A requires a value" arg))
         (let ((value (pop args)))
           (when (state-classifier-script-option-like-p value)
             (error "~A requires a value, got option ~A" arg value))
           (cond
             ((string= arg +state-classifier-script-root-option+)
              (setf root
                    (state-classifier-script-set-single-value
                     root arg value)))
             ((string= arg +state-classifier-script-prefix-option+)
              (setf prefix
                    (state-classifier-script-set-single-value
                     prefix arg value)))
             (t
              (setf limit
                    (state-classifier-script-set-single-value
                     limit
                     arg
                     (state-classifier-script-parse-limit value)))))))
        ((state-classifier-script-option-like-p arg)
         (error "Unsupported classifier script option ~A" arg))
        (t
         (setf root
               (state-classifier-script-set-single-value
                root
                +state-classifier-script-root-option+
                arg)))))
    (list :root root :prefix prefix :limit limit)))

(defun state-classifier-script-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun state-classifier-script-value (name)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (boundp symbol))
      (error "Fixture value ~A is unavailable" name))
    (symbol-value symbol)))

(defun state-classifier-script-json-encode (object)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) object)))

(defun state-classifier-script-reject-missing-configured-root
    (root-argument)
  (if root-argument
      (unless (probe-file root-argument)
        (error "Configured EEST fixture root from ~A does not exist: ~A"
               +state-classifier-script-root-option+
               root-argument))
      (let ((root (uiop:getenv +state-classifier-script-eest-root-env+)))
        (when (and (not (state-classifier-script-blank-string-p root))
                   (not (probe-file root)))
          (error "Configured EEST fixture root from ~A does not exist: ~A"
                 +state-classifier-script-eest-root-env+
                 root)))))

(defun state-classifier-script-reject-empty-selected-root (root label)
  (when (and root
             (not (state-classifier-script-call
                   "execution-spec-tests-json-paths"
                   root)))
    (error "Configured EEST ~A fixture root contains no JSON files: ~A"
           label
           root)))

(defun state-classifier-script-prefix-p (prefix value)
  (or (state-classifier-script-blank-string-p prefix)
      (and (<= (length prefix) (length value))
           (string= prefix value :end2 (length prefix)))))

(defun state-classifier-script-limit-list (values limit)
  (if (and limit (> (length values) limit))
      (subseq values 0 limit)
      values))

(defun state-classifier-script-selector-key-table (selectors)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (selector selectors table)
      (setf (gethash selector table) t))))

(defun state-classifier-script-candidate-selectors
    (discovered pinned prefix include-pinned-p limit)
  (let ((pinned-table (state-classifier-script-selector-key-table pinned)))
    (state-classifier-script-limit-list
     (remove-if-not
      (lambda (selector)
        (and (state-classifier-script-prefix-p prefix selector)
             (or include-pinned-p
                 (not (gethash selector pinned-table)))))
      discovered)
     limit)))

(defun state-classifier-script-selector-family (selector-name)
  (let ((index (search "/tests/" selector-name)))
    (if index
        (subseq selector-name 0 index)
        selector-name)))

(defun state-classifier-script-error-classification (message)
  (let ((lower (string-downcase message)))
    (cond
      ((or (search "unsupported fork" lower)
           (search "out of phase a" lower)
           (search "cancun" lower)
           (search "prague" lower))
       "out-of-scope-fork-feature")
      ((or (search "not implemented yet" lower)
           (search "is not implemented" lower))
       "known-implementation-drift")
      ((or (search "does not carry" lower)
           (search "fixture helper" lower)
           (search "is unavailable" lower)
           (search "requires an embedded" lower)
           (search "malformed" lower)
           (search "selector count" lower)
           (search "do not match selectors" lower))
       "fixture-harness-error")
      (t
       "implementation-bug-candidate"))))

(defun state-classifier-script-classify-selector (root selector)
  (handler-case
      (progn
        (dolist (case
                 (state-classifier-script-call
                  "load-phase-a-eest-state-test-root-cases"
                  root
                  :expected-names (list selector)))
          (state-classifier-script-call
           "assert-eest-state-test-case"
           case))
        (list (cons "name" selector)
              (cons "family"
                    (state-classifier-script-selector-family selector))
              (cons "classification" "passing")
              (cons "error" nil)))
    (error (condition)
      (let ((message (princ-to-string condition)))
        (list (cons "name" selector)
              (cons "family"
                    (state-classifier-script-selector-family selector))
              (cons "classification"
                    (state-classifier-script-error-classification message))
              (cons "error" message))))))

(defun state-classifier-script-count-classification
    (classification results)
  (count classification
         results
         :key (lambda (result)
                (cdr (assoc "classification" result :test #'string=)))
         :test #'string=))

(defun state-classifier-script-family-summaries (results)
  (let ((families (make-hash-table :test 'equal)))
    (dolist (result results)
      (let* ((family (cdr (assoc "family" result :test #'string=)))
             (classification
               (cdr (assoc "classification" result :test #'string=)))
             (entry (or (gethash family families)
                        (list
                         (cons "family" family)
                         (cons "candidateCount" 0)
                         (cons "passingCount" 0)
                         (cons "knownImplementationDriftCount" 0)
                         (cons "implementationBugCandidateCount" 0)
                         (cons "fixtureHarnessErrorCount" 0)
                         (cons "outOfScopeForkFeatureCount" 0)))))
        (incf (cdr (assoc "candidateCount" entry :test #'string=)))
        (cond
          ((string= classification "passing")
           (incf (cdr (assoc "passingCount" entry :test #'string=))))
          ((string= classification "known-implementation-drift")
           (incf (cdr (assoc "knownImplementationDriftCount"
                             entry
                             :test #'string=))))
          ((string= classification "implementation-bug-candidate")
           (incf (cdr (assoc "implementationBugCandidateCount"
                             entry
                             :test #'string=))))
          ((string= classification "fixture-harness-error")
           (incf (cdr (assoc "fixtureHarnessErrorCount"
                             entry
                             :test #'string=))))
          ((string= classification "out-of-scope-fork-feature")
           (incf (cdr (assoc "outOfScopeForkFeatureCount"
                             entry
                             :test #'string=)))))
        (setf (gethash family families) entry)))
    (sort
     (loop for entry being the hash-values of families
           collect entry)
     #'string<
     :key (lambda (entry)
            (cdr (assoc "family" entry :test #'string=))))))

(defun state-classifier-script-passing-result-p (result)
  (string= "passing"
           (cdr (assoc "classification" result :test #'string=))))

(defun state-classifier-script-report
    (state-root prefix limit include-pinned-p failures-only-p)
  (let* ((discovered
           (state-classifier-script-call
            "discover-phase-a-eest-state-test-selectors"
            state-root))
         (pinned
           (state-classifier-script-value
            "+phase-a-eest-state-test-v5.4.0-case-names+"))
         (candidates
           (state-classifier-script-candidate-selectors
            discovered
            pinned
            prefix
            include-pinned-p
            limit))
         (results
           (mapcar (lambda (selector)
                     (state-classifier-script-classify-selector
                      state-root
                      selector))
                   candidates))
         (reported-results
           (if failures-only-p
               (remove-if #'state-classifier-script-passing-result-p results)
               results)))
    (list
     (cons "root" (namestring state-root))
     (cons "mode" "unpinned-state-test-classification")
     (cons "discoveredCount" (length discovered))
     (cons "pinnedCount" (length pinned))
     (cons "candidateCount" (length candidates))
     (cons "classifiedCount" (length results))
     (cons "passingCount"
           (state-classifier-script-count-classification "passing" results))
     (cons "failingCount"
           (- (length results)
              (state-classifier-script-count-classification
               "passing"
               results)))
     (cons "knownImplementationDriftCount"
           (state-classifier-script-count-classification
            "known-implementation-drift"
            results))
     (cons "implementationBugCandidateCount"
           (state-classifier-script-count-classification
            "implementation-bug-candidate"
            results))
     (cons "fixtureHarnessErrorCount"
           (state-classifier-script-count-classification
            "fixture-harness-error"
            results))
     (cons "outOfScopeForkFeatureCount"
           (state-classifier-script-count-classification
            "out-of-scope-fork-feature"
            results))
     (cons "prefix" (or prefix ""))
     (cons "limit" (or limit :false))
     (cons "includePinned" (if include-pinned-p t :false))
     (cons "failuresOnly" (if failures-only-p t :false))
     (cons "families" (state-classifier-script-family-summaries results))
     (cons "results" (or reported-results (make-array 0))))))

(defun state-classifier-script-report-field (report name)
  (cdr (assoc name report :test #'string=)))

(defun state-classifier-script-print-family-summary (family)
  (format t "family=~A candidates=~D passing=~D knownImplementationDrift=~D implementationBugCandidates=~D fixtureHarnessErrors=~D outOfScopeForkFeature=~D~%"
          (state-classifier-script-report-field family "family")
          (state-classifier-script-report-field family "candidateCount")
          (state-classifier-script-report-field family "passingCount")
          (state-classifier-script-report-field
           family
           "knownImplementationDriftCount")
          (state-classifier-script-report-field
           family
           "implementationBugCandidateCount")
          (state-classifier-script-report-field
           family
           "fixtureHarnessErrorCount")
          (state-classifier-script-report-field
           family
           "outOfScopeForkFeatureCount")))

(defun state-classifier-script-print-result (result)
  (format t "result=~A classification=~A~@[ error=~A~]~%"
          (state-classifier-script-report-field result "name")
          (state-classifier-script-report-field result "classification")
          (state-classifier-script-report-field result "error")))

(defun state-classifier-script-print-text-report (report)
  (dolist (field '("root"
                   "mode"
                   "discoveredCount"
                   "pinnedCount"
                   "candidateCount"
                   "classifiedCount"
                   "passingCount"
                   "failingCount"
                   "knownImplementationDriftCount"
                   "implementationBugCandidateCount"
                   "fixtureHarnessErrorCount"
                   "outOfScopeForkFeatureCount"
                   "prefix"
                   "limit"
                   "includePinned"
                   "failuresOnly"))
    (format t "~A=~A~%"
            field
            (state-classifier-script-report-field report field)))
  (dolist (family (state-classifier-script-report-field report "families"))
    (state-classifier-script-print-family-summary family))
  (dolist (result (state-classifier-script-report-field report "results"))
    (state-classifier-script-print-result result)))

(defun state-classifier-script-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-state-classifier-script-root*))
  (let* ((args (state-classifier-script-arguments))
         (options (state-classifier-script-options args))
         (root-argument (getf options :root))
         (state-root
           (if root-argument
               (state-classifier-script-call
                "execution-spec-tests-state-test-root"
                root-argument)
               (state-classifier-script-call
                "execution-spec-tests-state-test-root"))))
    (state-classifier-script-reject-missing-configured-root root-argument)
    (unless state-root
      (error "No EEST state_tests fixture root found. Pass --root or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (state-classifier-script-reject-empty-selected-root
     state-root
     "state_tests")
    (let ((report
            (state-classifier-script-report
             state-root
             (getf options :prefix)
             (getf options :limit)
             (state-classifier-script-include-pinned-p args)
             (state-classifier-script-failures-only-p args))))
      (if (state-classifier-script-json-p args)
          (format t "~&~A~%"
                  (state-classifier-script-json-encode report))
          (state-classifier-script-print-text-report report)))))

(state-classifier-script-main)
