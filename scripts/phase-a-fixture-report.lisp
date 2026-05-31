(defparameter *ethereum-lisp-fixture-report-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defconstant +fixture-report-pinned-v5.4.0-flag+ "--pinned-v5.4.0")
(defconstant +fixture-report-json-flag+ "--json")

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

(defun fixture-report-argument-root (args)
  (let ((root nil))
    (dolist (arg args)
      (cond
        ((string= arg +fixture-report-pinned-v5.4.0-flag+))
        ((string= arg +fixture-report-json-flag+))
        ((and (plusp (length arg))
              (char= #\- (char arg 0)))
         (error "Unsupported fixture report option ~A" arg))
        (root
         (error "Only one fixture root argument is supported"))
        (t
         (setf root arg))))
    root))

(defun fixture-report-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun fixture-report-field (object name)
  (cdr (assoc name object :test #'string=)))

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

(defun fixture-report-report-object
    (suite-root mode state-root state-selectors state-summary
     blockchain-root blockchain-kinds blockchain-summary)
  (list
   (cons "suiteRoot" suite-root)
   (cons "mode" mode)
   (cons "state"
         (list
          (cons "root" (namestring state-root))
          (cons "count" (fixture-report-field state-summary "count"))
          (cons "transactionCombinationCount"
                (fixture-report-field state-summary
                                      "transactionCombinationCount"))
          (cons "selectors" state-selectors)
          (cons "selectorString"
                (fixture-report-call
                 "phase-a-eest-state-test-selector-string"
                 state-selectors))))
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
        (blockchain (fixture-report-field report "blockchain")))
    (format t "~&suiteRoot=~A~%" (fixture-report-field report "suiteRoot"))
    (format t "mode=~A~%" (fixture-report-field report "mode"))
    (format t "stateRoot=~A~%" (fixture-report-field state "root"))
    (format t "stateCount=~D~%" (fixture-report-field state "count"))
    (format t "stateTransactionCombinations=~D~%"
            (fixture-report-field state "transactionCombinationCount"))
    (format t "stateSelectors=~A~%"
            (fixture-report-field state "selectorString"))
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

(defun fixture-report-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-fixture-report-root*))
  (let* ((args (fixture-report-arguments))
         (pinned-p (fixture-report-pinned-v5.4.0-p args))
         (json-p (fixture-report-json-p args))
         (root-argument (fixture-report-argument-root args))
         (suite-root (or root-argument "environment"))
         (mode (if pinned-p "pinned-v5.4.0" "discover"))
         (state-root
           (if root-argument
               (fixture-report-call "execution-spec-tests-state-test-root"
                                    root-argument)
               (fixture-report-call
                "execution-spec-tests-state-test-root")))
         (blockchain-root
           (if root-argument
               (fixture-report-call
                "execution-spec-tests-blockchain-test-root"
                root-argument)
               (fixture-report-call
                "execution-spec-tests-blockchain-test-root"))))
    (unless state-root
      (error "No EEST state_tests fixture root found. Pass a root path or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (unless blockchain-root
      (error "No EEST blockchain fixture root found. Pass a root path or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (let* ((state-selectors
             (fixture-report-call
              "discover-phase-a-eest-state-test-selectors"
              state-root))
           (state-cases
             (fixture-report-call
              "load-eest-state-test-root-cases"
              state-root
              :names state-selectors))
           (state-summary
             (fixture-report-call
              "validate-phase-a-eest-state-test-summary"
              state-cases
              :expected-names state-selectors))
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
      (unless state-selectors
        (error "No materializable Phase A state_tests selectors found under ~A"
               state-root))
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
               blockchain-root
               blockchain-kinds
               blockchain-summary)))
        (if json-p
            (format t "~&~A~%" (fixture-report-json-encode report))
            (fixture-report-print-text report))))))

(fixture-report-main)
