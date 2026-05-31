(defparameter *ethereum-lisp-fixture-report-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defconstant +fixture-report-pinned-v5.4.0-flag+ "--pinned-v5.4.0")

(defun fixture-report-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun fixture-report-pinned-v5.4.0-p (args)
  (member +fixture-report-pinned-v5.4.0-flag+ args :test #'string=))

(defun fixture-report-argument-root (args)
  (let ((root nil))
    (dolist (arg args)
      (cond
        ((string= arg +fixture-report-pinned-v5.4.0-flag+))
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

(defun fixture-report-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-fixture-report-root*))
  (let* ((args (fixture-report-arguments))
         (pinned-p (fixture-report-pinned-v5.4.0-p args))
         (root-argument (fixture-report-argument-root args))
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
      (format t "~&suiteRoot=~A~%" (or root-argument "environment"))
      (format t "mode=~A~%" (if pinned-p "pinned-v5.4.0" "discover"))
      (format t "stateRoot=~A~%" state-root)
      (format t "stateCount=~D~%"
              (fixture-report-field state-summary "count"))
      (format t "stateTransactionCombinations=~D~%"
              (fixture-report-field state-summary
                                    "transactionCombinationCount"))
      (format t "stateSelectors=~A~%"
              (fixture-report-call
               "phase-a-eest-state-test-selector-string"
               state-selectors))
      (format t "blockchainRoot=~A~%" blockchain-root)
      (format t "blockchainCount=~D~%"
              (fixture-report-field blockchain-summary "count"))
      (format t "blockchainBlockCount=~D~%"
              (fixture-report-field blockchain-summary "blockCount"))
      (format t "blockchainKindCounts=~S~%"
              (fixture-report-field blockchain-summary
                                    "materializationKindCounts"))
      (format t "blockchainSelectors=~A~%"
              (fixture-report-kind-string blockchain-kinds)))))

(fixture-report-main)
