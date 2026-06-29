(defparameter *ethereum-lisp-transaction-classifier-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)

(defconstant +transaction-classifier-script-json-flag+ "--json")
(defconstant +transaction-classifier-script-help-flag+ "--help")
(defconstant +transaction-classifier-script-root-option+ "--root")
(defconstant +transaction-classifier-script-prefix-option+ "--prefix")
(defconstant +transaction-classifier-script-limit-option+ "--limit")
(defconstant +transaction-classifier-script-include-pinned-flag+ "--include-pinned")
(defconstant +transaction-classifier-script-failures-only-flag+ "--failures-only")
(defconstant +transaction-classifier-script-eest-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")

(defun transaction-classifier-script-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun transaction-classifier-script-help-p (args)
  (member +transaction-classifier-script-help-flag+ args :test #'string=))

(defun transaction-classifier-script-print-help ()
  (format t "~&Usage: sbcl --script scripts/classify-transaction-test-selectors.lisp -- [options]~%")
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
  (format t "Classifications: passing, implementation-bug-candidate, ~
fixture-harness-error, out-of-scope.~%")
  (format t "Without --root, ~A is used when set.~%"
          +transaction-classifier-script-eest-root-env+))

#+sbcl
(when (transaction-classifier-script-help-p
       (transaction-classifier-script-arguments))
  (transaction-classifier-script-print-help)
  (sb-ext:exit :code 0))

(defun transaction-classifier-script-json-p (args)
  (member +transaction-classifier-script-json-flag+ args :test #'string=))

(defun transaction-classifier-script-include-pinned-p (args)
  (member +transaction-classifier-script-include-pinned-flag+ args :test #'string=))

(defun transaction-classifier-script-failures-only-p (args)
  (member +transaction-classifier-script-failures-only-flag+ args :test #'string=))

(defun transaction-classifier-script-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun transaction-classifier-script-blank-string-p (value)
  (or (null value)
      (zerop (length
              (string-trim '(#\Space #\Tab #\Newline #\Return) value)))))

(defun transaction-classifier-script-set-single-value (current option value)
  (when current
    (error "Only one ~A option is supported" option))
  value)

(defun transaction-classifier-script-parse-limit (value)
  (handler-case
      (let ((limit (parse-integer value :junk-allowed nil)))
        (unless (plusp limit)
          (error "~A requires a positive integer"
                 +transaction-classifier-script-limit-option+))
        limit)
    (error ()
      (error "~A requires a positive integer, got ~A"
             +transaction-classifier-script-limit-option+
             value))))

(defun transaction-classifier-script-options (args)
  (let ((root nil)
        (prefix nil)
        (limit nil))
    (loop while args
          for arg = (pop args)
          do
      (cond
        ((or (string= arg +transaction-classifier-script-json-flag+)
             (string= arg +transaction-classifier-script-help-flag+)
             (string= arg +transaction-classifier-script-include-pinned-flag+)
             (string= arg +transaction-classifier-script-failures-only-flag+)))
        ((or (string= arg +transaction-classifier-script-root-option+)
             (string= arg +transaction-classifier-script-prefix-option+)
             (string= arg +transaction-classifier-script-limit-option+))
         (unless args
           (error "~A requires a value" arg))
         (let ((value (pop args)))
           (when (transaction-classifier-script-option-like-p value)
             (error "~A requires a value, got option ~A" arg value))
           (cond
             ((string= arg +transaction-classifier-script-root-option+)
              (setf root
                    (transaction-classifier-script-set-single-value
                     root arg value)))
             ((string= arg +transaction-classifier-script-prefix-option+)
              (setf prefix
                    (transaction-classifier-script-set-single-value
                     prefix arg value)))
             (t
              (setf limit
                    (transaction-classifier-script-set-single-value
                     limit
                     arg
                     (transaction-classifier-script-parse-limit value)))))))
        ((transaction-classifier-script-option-like-p arg)
         (error "Unsupported classifier script option ~A" arg))
        (t
         (setf root
               (transaction-classifier-script-set-single-value
                root
                +transaction-classifier-script-root-option+
                arg)))))
    (list :root root :prefix prefix :limit limit)))

(defun transaction-classifier-script-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun transaction-classifier-script-value (name)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (boundp symbol))
      (error "Fixture value ~A is unavailable" name))
    (symbol-value symbol)))

(defun transaction-classifier-script-json-encode (object)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) object)))

(defun transaction-classifier-script-reject-missing-configured-root
    (root-argument)
  (if root-argument
      (unless (probe-file root-argument)
        (error "Configured EEST fixture root from ~A does not exist: ~A"
               +transaction-classifier-script-root-option+
               root-argument))
      (let ((root (uiop:getenv +transaction-classifier-script-eest-root-env+)))
        (when (and (not (transaction-classifier-script-blank-string-p root))
                   (not (probe-file root)))
          (error "Configured EEST fixture root from ~A does not exist: ~A"
                 +transaction-classifier-script-eest-root-env+
                 root)))))

(defun transaction-classifier-script-reject-empty-selected-root (root label)
  (when (and root
             (not (transaction-classifier-script-call
                   "execution-spec-tests-json-paths"
                   root)))
    (error "Configured EEST ~A fixture root contains no JSON files: ~A"
           label
           root)))

(defun transaction-classifier-script-prefix-p (prefix value)
  (or (transaction-classifier-script-blank-string-p prefix)
      (and (<= (length prefix) (length value))
           (string= prefix value :end2 (length prefix)))))

(defun transaction-classifier-script-limit-list (values limit)
  (if (and limit (> (length values) limit))
      (subseq values 0 limit)
      values))

(defun transaction-classifier-script-selector-key-table (selectors)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (selector selectors table)
      (setf (gethash selector table) t))))

(defun transaction-classifier-script-candidate-selectors
    (discovered pinned prefix include-pinned-p limit)
  (let ((pinned-table
          (transaction-classifier-script-selector-key-table pinned)))
    (transaction-classifier-script-limit-list
     (remove-if-not
      (lambda (selector)
        (and (transaction-classifier-script-prefix-p prefix selector)
             (or include-pinned-p
                 (not (gethash selector pinned-table)))))
      discovered)
     limit)))

(defun transaction-classifier-script-selector-family (selector-name)
  (let ((json-index (search ".json" selector-name)))
    (if json-index
        (subseq selector-name 0 (+ json-index (length ".json")))
        selector-name)))

(defun transaction-classifier-script-discovered-selectors
    (transaction-root)
  (mapcar (lambda (case)
            (transaction-classifier-script-call
             "fixture-required-field"
             case
             "name"))
          (transaction-classifier-script-call
           "load-eest-transaction-test-root-cases"
           transaction-root)))

(defun transaction-classifier-script-pinned-selectors ()
  (remove-duplicates
   (append
    (transaction-classifier-script-value
     "+phase-a-eest-transaction-test-case-names+")
    (transaction-classifier-script-value
     "+full-eest-transaction-test-case-names+"))
   :test #'string=))

(defun transaction-classifier-script-out-of-scope-selector-p (selector)
  (let ((lower (string-downcase selector)))
    (or (search "prague/" lower)
        (search "eip7702" lower)
        (search "type_4" lower))))

(defun transaction-classifier-script-error-classification (message)
  (let ((lower (string-downcase message)))
    (cond
      ((or (search "unsupported fork" lower)
           (search "out of phase a" lower)
           (search "cancun" lower)
           (search "prague" lower)
           (search "eip7702" lower)
           (search "type_4" lower)
           (search "set-code" lower)
           (search "blob" lower))
       "out-of-scope")
      ((or (search "does not carry" lower)
           (search "fixture helper" lower)
           (search "is unavailable" lower)
           (search "requires an embedded" lower)
           (search "malformed" lower)
           (search "selector count" lower)
           (search "do not match selectors" lower)
           (search "did not match any loaded case" lower))
       "fixture-harness-error")
      (t
       "implementation-bug-candidate"))))

(defun transaction-classifier-script-result
    (selector classification error-message)
  (list (cons "name" selector)
        (cons "family"
              (transaction-classifier-script-selector-family selector))
        (cons "classification" classification)
        (cons "error" error-message)))

(defun transaction-classifier-script-classify-selector
    (root selector)
  (handler-case
      (if (transaction-classifier-script-out-of-scope-selector-p selector)
          (transaction-classifier-script-result
           selector
           "out-of-scope"
           "Prague/EIP-7702 transaction tests are outside the current Phase A valid-envelope scope")
          (let* ((vectors
                   (transaction-classifier-script-call
                    "load-eest-transaction-test-root-vectors"
                    root
                    :names (list selector)))
                 (count (length vectors)))
            (unless (= 1 count)
              (error "EEST transaction selector ~A loaded ~D materialized vectors"
                     selector
                     count))
            (transaction-classifier-script-result
             selector
             "passing"
             nil)))
    (error (condition)
      (let ((message (princ-to-string condition)))
        (transaction-classifier-script-result
         selector
         (transaction-classifier-script-error-classification message)
         message)))))

(defun transaction-classifier-script-count-classification
    (classification results)
  (count classification
         results
         :key (lambda (result)
                (cdr (assoc "classification" result :test #'string=)))
         :test #'string=))

(defun transaction-classifier-script-family-summaries (results)
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
                         (cons "implementationBugCandidateCount" 0)
                         (cons "fixtureHarnessErrorCount" 0)
                         (cons "outOfScopeCount" 0)))))
        (incf (cdr (assoc "candidateCount" entry :test #'string=)))
        (cond
          ((string= classification "passing")
           (incf (cdr (assoc "passingCount" entry :test #'string=))))
          ((string= classification "implementation-bug-candidate")
           (incf (cdr (assoc "implementationBugCandidateCount"
                             entry
                             :test #'string=))))
          ((string= classification "fixture-harness-error")
           (incf (cdr (assoc "fixtureHarnessErrorCount"
                             entry
                             :test #'string=))))
          ((string= classification "out-of-scope")
           (incf (cdr (assoc "outOfScopeCount" entry :test #'string=)))))
        (setf (gethash family families) entry)))
    (sort
     (loop for entry being the hash-values of families
           collect entry)
     #'string<
     :key (lambda (entry)
            (cdr (assoc "family" entry :test #'string=))))))

(defun transaction-classifier-script-passing-result-p (result)
  (string= "passing"
           (cdr (assoc "classification" result :test #'string=))))

(defun transaction-classifier-script-report
    (transaction-root prefix limit include-pinned-p failures-only-p)
  (let* ((discovered
           (transaction-classifier-script-discovered-selectors
            transaction-root))
         (pinned
           (transaction-classifier-script-pinned-selectors))
         (candidates
           (transaction-classifier-script-candidate-selectors
            discovered
            pinned
            prefix
            include-pinned-p
            limit))
         (results
           (mapcar (lambda (selector)
                     (transaction-classifier-script-classify-selector
                      transaction-root
                      selector))
                   candidates))
         (reported-results
           (if failures-only-p
               (remove-if
                #'transaction-classifier-script-passing-result-p
                results)
               results)))
    (list
     (cons "root" (namestring transaction-root))
     (cons "mode" "unpinned-transaction-test-classification")
     (cons "discoveredCount" (length discovered))
     (cons "pinnedCount" (length pinned))
     (cons "candidateCount" (length candidates))
     (cons "classifiedCount" (length results))
     (cons "passingCount"
           (transaction-classifier-script-count-classification
            "passing"
            results))
     (cons "failingCount"
           (- (length results)
              (transaction-classifier-script-count-classification
               "passing"
               results)))
     (cons "implementationBugCandidateCount"
           (transaction-classifier-script-count-classification
            "implementation-bug-candidate"
            results))
     (cons "fixtureHarnessErrorCount"
           (transaction-classifier-script-count-classification
            "fixture-harness-error"
            results))
     (cons "outOfScopeCount"
           (transaction-classifier-script-count-classification
            "out-of-scope"
            results))
     (cons "prefix" (or prefix ""))
     (cons "limit" (or limit :false))
     (cons "includePinned" (if include-pinned-p t :false))
     (cons "failuresOnly" (if failures-only-p t :false))
     (cons "families"
           (transaction-classifier-script-family-summaries results))
     (cons "results" reported-results))))

(defun transaction-classifier-script-report-field (report name)
  (cdr (assoc name report :test #'string=)))

(defun transaction-classifier-script-print-family-summary (family)
  (format t "family=~A candidates=~D passing=~D implementationBugCandidates=~D fixtureHarnessErrors=~D outOfScope=~D~%"
          (transaction-classifier-script-report-field family "family")
          (transaction-classifier-script-report-field family "candidateCount")
          (transaction-classifier-script-report-field family "passingCount")
          (transaction-classifier-script-report-field
           family
           "implementationBugCandidateCount")
          (transaction-classifier-script-report-field
           family
           "fixtureHarnessErrorCount")
          (transaction-classifier-script-report-field family "outOfScopeCount")))

(defun transaction-classifier-script-print-result (result)
  (format t "result=~A classification=~A~@[ error=~A~]~%"
          (transaction-classifier-script-report-field result "name")
          (transaction-classifier-script-report-field result "classification")
          (transaction-classifier-script-report-field result "error")))

(defun transaction-classifier-script-print-text-report (report)
  (dolist (field '("root"
                   "mode"
                   "discoveredCount"
                   "pinnedCount"
                   "candidateCount"
                   "classifiedCount"
                   "passingCount"
                   "failingCount"
                   "implementationBugCandidateCount"
                   "fixtureHarnessErrorCount"
                   "outOfScopeCount"
                   "prefix"
                   "limit"
                   "includePinned"
                   "failuresOnly"))
    (format t "~A=~A~%"
            field
            (transaction-classifier-script-report-field report field)))
  (dolist (family (transaction-classifier-script-report-field
                   report
                   "families"))
    (transaction-classifier-script-print-family-summary family))
  (dolist (result (transaction-classifier-script-report-field
                   report
                   "results"))
    (transaction-classifier-script-print-result result)))

(defun transaction-classifier-script-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-transaction-classifier-script-root*))
  (let* ((args (transaction-classifier-script-arguments))
         (options (transaction-classifier-script-options args))
         (root-argument (getf options :root))
         (transaction-root
           (if root-argument
               (transaction-classifier-script-call
                "execution-spec-tests-transaction-test-root"
                root-argument)
               (transaction-classifier-script-call
                "execution-spec-tests-transaction-test-root"))))
    (transaction-classifier-script-reject-missing-configured-root
     root-argument)
    (unless transaction-root
      (error "No EEST transaction_tests fixture root found. Pass --root or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (transaction-classifier-script-reject-empty-selected-root
     transaction-root
     "transaction_tests")
    (let ((report
            (transaction-classifier-script-report
             transaction-root
             (getf options :prefix)
             (getf options :limit)
             (transaction-classifier-script-include-pinned-p args)
             (transaction-classifier-script-failures-only-p args))))
      (if (transaction-classifier-script-json-p args)
          (format t "~&~A~%"
                  (transaction-classifier-script-json-encode report))
          (transaction-classifier-script-print-text-report report)))))

(transaction-classifier-script-main)
