(defparameter *ethereum-lisp-classifier-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)

(defconstant +classifier-script-json-flag+ "--json")
(defconstant +classifier-script-help-flag+ "--help")
(defconstant +classifier-script-root-option+ "--root")
(defconstant +classifier-script-prefix-option+ "--prefix")
(defconstant +classifier-script-limit-option+ "--limit")
(defconstant +classifier-script-include-pinned-flag+ "--include-pinned")
(defconstant +classifier-script-eest-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")

(defun classifier-script-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun classifier-script-help-p (args)
  (member +classifier-script-help-flag+ args :test #'string=))

(defun classifier-script-print-help ()
  (format t "~&Usage: sbcl --script scripts/classify-blockchain-replay-selectors.lisp -- [options]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --root PATH          EEST fixture suite root.~%")
  (format t "  --prefix PREFIX      Only classify selectors whose names start with PREFIX.~%")
  (format t "  --limit NUMBER       Classify at most NUMBER candidate selectors.~%")
  (format t "  --include-pinned     Include already pinned selectors in the candidate set.~%")
  (format t "  --json               Print machine-readable JSON output.~%")
  (format t "  --help               Print this help.~%")
  (format t "~%")
  (format t "Classifications: passing, implementation-bug-candidate, ~
fixture-harness-error, out-of-scope.~%")
  (format t "Without --root, ~A is used when set.~%"
          +classifier-script-eest-root-env+))

#+sbcl
(when (classifier-script-help-p (classifier-script-arguments))
  (classifier-script-print-help)
  (sb-ext:exit :code 0))

(defun classifier-script-json-p (args)
  (member +classifier-script-json-flag+ args :test #'string=))

(defun classifier-script-include-pinned-p (args)
  (member +classifier-script-include-pinned-flag+ args :test #'string=))

(defun classifier-script-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun classifier-script-blank-string-p (value)
  (or (null value)
      (zerop (length
              (string-trim '(#\Space #\Tab #\Newline #\Return) value)))))

(defun classifier-script-set-single-value (current option value)
  (when current
    (error "Only one ~A option is supported" option))
  value)

(defun classifier-script-parse-limit (value)
  (handler-case
      (let ((limit (parse-integer value :junk-allowed nil)))
        (unless (plusp limit)
          (error "~A requires a positive integer"
                 +classifier-script-limit-option+))
        limit)
    (error ()
      (error "~A requires a positive integer, got ~A"
             +classifier-script-limit-option+
             value))))

(defun classifier-script-options (args)
  (let ((root nil)
        (prefix nil)
        (limit nil))
    (loop while args
          for arg = (pop args)
          do
      (cond
        ((or (string= arg +classifier-script-json-flag+)
             (string= arg +classifier-script-help-flag+)
             (string= arg +classifier-script-include-pinned-flag+)))
        ((or (string= arg +classifier-script-root-option+)
             (string= arg +classifier-script-prefix-option+)
             (string= arg +classifier-script-limit-option+))
         (unless args
           (error "~A requires a value" arg))
         (let ((value (pop args)))
           (when (classifier-script-option-like-p value)
             (error "~A requires a value, got option ~A" arg value))
           (cond
             ((string= arg +classifier-script-root-option+)
              (setf root
                    (classifier-script-set-single-value root arg value)))
             ((string= arg +classifier-script-prefix-option+)
              (setf prefix
                    (classifier-script-set-single-value prefix arg value)))
             (t
              (setf limit
                    (classifier-script-set-single-value
                     limit
                     arg
                     (classifier-script-parse-limit value)))))))
        ((classifier-script-option-like-p arg)
         (error "Unsupported classifier script option ~A" arg))
        (t
         (setf root
               (classifier-script-set-single-value
                root
                +classifier-script-root-option+
                arg)))))
    (list :root root :prefix prefix :limit limit)))

(defun classifier-script-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun classifier-script-json-encode (object)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) object)))

(defun classifier-script-reject-missing-configured-root (root-argument)
  (if root-argument
      (unless (probe-file root-argument)
        (error "Configured EEST fixture root from ~A does not exist: ~A"
               +classifier-script-root-option+
               root-argument))
      (let ((root (uiop:getenv +classifier-script-eest-root-env+)))
        (when (and (not (classifier-script-blank-string-p root))
                   (not (probe-file root)))
          (error "Configured EEST fixture root from ~A does not exist: ~A"
                 +classifier-script-eest-root-env+
                 root)))))

(defun classifier-script-reject-empty-selected-root (root label)
  (when (and root
             (not (classifier-script-call "execution-spec-tests-json-paths"
                                          root)))
    (error "Configured EEST ~A fixture root contains no JSON files: ~A"
           label
           root)))

(defun classifier-script-prefix-p (prefix value)
  (or (classifier-script-blank-string-p prefix)
      (and (<= (length prefix) (length value))
           (string= prefix value :end2 (length prefix)))))

(defun classifier-script-limit-list (values limit)
  (if (and limit (> (length values) limit))
      (subseq values 0 limit)
      values))

(defun classifier-script-selector-key-table (selectors)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (selector selectors table)
      (setf (gethash (car selector) table) t))))

(defun classifier-script-candidate-selectors
    (discovered pinned prefix include-pinned-p limit)
  (let ((pinned-table (classifier-script-selector-key-table pinned)))
    (classifier-script-limit-list
     (remove-if-not
      (lambda (selector)
        (and (classifier-script-prefix-p prefix (car selector))
             (or include-pinned-p
                 (not (gethash (car selector) pinned-table)))))
      discovered)
     limit)))

(defun classifier-script-selector-family (selector-name)
  (let ((index (search "/tests/" selector-name)))
    (if index
        (subseq selector-name 0 index)
        selector-name)))

(defun classifier-script-error-classification (message)
  (let ((lower (string-downcase message)))
    (cond
      ((or (search "unsupported fork" lower)
           (search "out of phase a" lower)
           (search "cancun" lower)
           (search "prague" lower))
       "out-of-scope")
      ((or (search "does not carry" lower)
           (search "fixture helper" lower)
           (search "is unavailable" lower)
           (search "requires an embedded" lower)
           (search "malformed" lower))
       "fixture-harness-error")
      (t
       "implementation-bug-candidate"))))

(defun classifier-script-classify-selector (root selector)
  (handler-case
      (let ((cases
              (classifier-script-call
               "load-phase-a-eest-blockchain-replay-cases"
               root
               :expected-kinds (list selector))))
        (dolist (source-case cases)
          (classifier-script-call
           "assert-eest-blockchain-engine-newpayload-v2-replay"
           (classifier-script-call
            "materialize-eest-blockchain-engine-newpayload-v2-case"
            source-case)
           :source-case source-case))
        (list (cons "name" (car selector))
              (cons "family"
                    (classifier-script-selector-family (car selector)))
              (cons "kind" (cdr selector))
              (cons "classification" "passing")
              (cons "error" nil)))
    (error (condition)
      (let ((message (princ-to-string condition)))
        (list (cons "name" (car selector))
              (cons "family"
                    (classifier-script-selector-family (car selector)))
              (cons "kind" (cdr selector))
              (cons "classification"
                    (classifier-script-error-classification message))
              (cons "error" message))))))

(defun classifier-script-count-classification (classification results)
  (count classification
         results
         :key (lambda (result)
                (cdr (assoc "classification" result :test #'string=)))
         :test #'string=))

(defun classifier-script-family-summaries (results)
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

(defun classifier-script-report
    (blockchain-root prefix limit include-pinned-p)
  (let* ((discovered
           (classifier-script-call
            "discover-phase-a-eest-blockchain-replay-selectors"
            blockchain-root))
         (pinned
           (classifier-script-call
            "phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds"
            blockchain-root))
         (candidates
           (classifier-script-candidate-selectors
            discovered
            pinned
            prefix
            include-pinned-p
            limit))
         (results
           (mapcar (lambda (selector)
                     (classifier-script-classify-selector
                      blockchain-root
                      selector))
                   candidates)))
    (list
     (cons "root" (namestring blockchain-root))
     (cons "mode" "unpinned-blockchain-replay-classification")
     (cons "discoveredCount" (length discovered))
     (cons "pinnedCount" (length pinned))
     (cons "candidateCount" (length candidates))
     (cons "classifiedCount" (length results))
     (cons "passingCount"
           (classifier-script-count-classification "passing" results))
     (cons "failingCount"
           (- (length results)
              (classifier-script-count-classification "passing" results)))
     (cons "implementationBugCandidateCount"
           (classifier-script-count-classification
            "implementation-bug-candidate"
            results))
     (cons "fixtureHarnessErrorCount"
           (classifier-script-count-classification
            "fixture-harness-error"
            results))
     (cons "outOfScopeCount"
           (classifier-script-count-classification
            "out-of-scope"
            results))
     (cons "prefix" (or prefix ""))
     (cons "limit" (or limit :false))
     (cons "includePinned" (if include-pinned-p t :false))
     (cons "families" (classifier-script-family-summaries results))
     (cons "results" results))))

(defun classifier-script-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-classifier-script-root*))
  (let* ((args (classifier-script-arguments))
         (options (classifier-script-options args))
         (root-argument (getf options :root))
         (blockchain-root
           (if root-argument
               (classifier-script-call "execution-spec-tests-blockchain-test-root"
                                       root-argument)
               (classifier-script-call
                "execution-spec-tests-blockchain-test-root"))))
    (classifier-script-reject-missing-configured-root root-argument)
    (unless blockchain-root
      (error "No EEST blockchain fixture root found. Pass --root or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (classifier-script-reject-empty-selected-root blockchain-root "blockchain")
    (let ((report
            (classifier-script-report
             blockchain-root
             (getf options :prefix)
             (getf options :limit)
             (classifier-script-include-pinned-p args))))
      (if (classifier-script-json-p args)
          (format t "~&~A~%" (classifier-script-json-encode report))
          (progn
            (format t "~&root=~A~%"
                    (cdr (assoc "root" report :test #'string=)))
            (format t "mode=~A~%"
                    (cdr (assoc "mode" report :test #'string=)))
            (format t "discovered=~D pinned=~D candidates=~D classified=~D passing=~D failing=~D~%"
                    (cdr (assoc "discoveredCount" report :test #'string=))
                    (cdr (assoc "pinnedCount" report :test #'string=))
                    (cdr (assoc "candidateCount" report :test #'string=))
                    (cdr (assoc "classifiedCount" report :test #'string=))
                    (cdr (assoc "passingCount" report :test #'string=))
                    (cdr (assoc "failingCount" report :test #'string=)))
            (format t "implementationBugCandidates=~D fixtureHarnessErrors=~D outOfScope=~D~%"
                    (cdr (assoc "implementationBugCandidateCount"
                                report
                                :test #'string=))
                    (cdr (assoc "fixtureHarnessErrorCount"
                                report
                                :test #'string=))
                    (cdr (assoc "outOfScopeCount" report :test #'string=))))))))

(classifier-script-main)
