(unless (find-package '#:ethereum-lisp.fixture-root-application)
  (load (merge-pathnames "fixture-root-application.lisp"
                         (or *load-truename* *default-pathname-defaults*))))

(defpackage #:ethereum-lisp.selector-application
  (:use #:cl)
  (:export #:run-selector-application))

(in-package #:ethereum-lisp.selector-application)

(defconstant +root-env+ "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")

(defun test-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun test-value (name)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (boundp symbol))
      (error "Fixture value ~A is unavailable" name))
    (symbol-value symbol)))

(defun json-encode-report (report)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) report)))

(defun option-like-p (value)
  (and (stringp value) (plusp (length value))
       (char= #\- (char value 0))))

(defun parse-options (kind args)
  (let ((root nil) (json-p nil) (pinned-p nil))
    (loop while args
          for arg = (pop args)
          do (cond
               ((string= arg "--json") (setf json-p t))
               ((string= arg "--pinned-v5.4.0")
                (unless (eq kind :blockchain)
                  (error "Unsupported selector script option ~A" arg))
                (setf pinned-p t))
               ((string= arg "--root")
                (unless args (error "--root requires a fixture root path"))
                (let ((value (pop args)))
                  (when (option-like-p value)
                    (error "--root requires a fixture root path, got option ~A"
                           value))
                  (when root
                    (error "Only one fixture root argument is supported"))
                  (setf root value)))
               ((option-like-p arg)
                (error "Unsupported selector script option ~A" arg))
               (t
                (when root
                  (error "Only one fixture root argument is supported"))
                (setf root arg))))
    (values root json-p pinned-p)))

(defun suite-config (kind)
  (ecase kind
    (:state
     (values "execution-spec-tests-state-test-root" "state_tests"))
    (:transaction
     (values "execution-spec-tests-transaction-test-root" "transaction_tests"))
    (:blockchain
     (values "execution-spec-tests-blockchain-test-root" "blockchain"))))

(defun resolve-suite-root (kind configured-root)
  (multiple-value-bind (root-helper label) (suite-config kind)
    (let ((root (if configured-root
                    (test-call root-helper configured-root)
                    (test-call root-helper))))
      (unless root
        (error "No EEST ~A fixture root found. Pass a root path or set ~A."
               label +root-env+))
      (ethereum-lisp.fixture-root-application:validate-non-empty-root
       root label (lambda (path)
                    (test-call "execution-spec-tests-json-paths" path)))
      root)))

(defun state-report (root)
  (let ((selectors
          (test-call "discover-phase-a-eest-state-test-selectors" root)))
    (unless selectors
      (error "No materializable Phase A state_tests selectors found under ~A"
             root))
    (list
     (cons "root" (namestring root))
     (cons "mode" "discover")
     (cons "count" (length selectors))
     (cons "selectors" selectors)
     (cons "selectorString"
           (test-call "phase-a-eest-state-test-selector-string" selectors)))))

(defun transaction-report (root)
  (let* ((vectors
           (test-call "load-phase-a-eest-transaction-test-root-vectors" root))
         (summary
           (test-call "validate-phase-a-eest-transaction-vector-summary"
                      vectors))
         (selectors
           (test-value "+phase-a-eest-transaction-test-case-names+")))
    (list
     (cons "root" (namestring root))
     (cons "mode" "phase-a")
     (cons "count" (test-call "fixture-object-field" summary "count"))
     (cons "types" (test-call "fixture-object-field" summary "types"))
     (cons "selectors" selectors)
     (cons "selectorString"
           (test-call "phase-a-eest-transaction-test-selector-string"
                      selectors)))))

(defun blockchain-kind-object (selectors)
  (mapcar (lambda (entry)
            (list (cons "name" (car entry)) (cons "kind" (cdr entry))))
          selectors))

(defun blockchain-report (root pinned-p)
  (let ((selectors
          (if pinned-p
              (test-call
               "phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds"
               root)
              (test-call "discover-phase-a-eest-blockchain-replay-selectors"
                         root))))
    (unless selectors
      (error "No materializable Phase A blockchain replay selectors found under ~A"
             root))
    (list
     (cons "root" (namestring root))
     (cons "mode" (if pinned-p "pinned-v5.4.0" "discover"))
     (cons "count" (length selectors))
     (cons "selectors" (blockchain-kind-object selectors))
     (cons "selectorString"
           (test-call "phase-a-eest-blockchain-replay-selector-string"
                      selectors)))))

(defun print-text-report (report output)
  (dolist (field '("root" "mode" "count" "types" "selectorString"))
    (let ((entry (assoc field report :test #'string=)))
      (when entry
        (format output "~A=~A~%" field (cdr entry))))))

(defun run-selector-application
    (kind args
     &key
       (environment-lookup #'uiop:getenv)
       (output *standard-output*)
       (error-output *error-output*)
       (load-tests-p t)
       repository-root)
  (let ((*standard-output* output) (*error-output* error-output))
    (when load-tests-p
      (load (merge-pathnames "tests/load-tests.lisp" repository-root)))
    (multiple-value-bind (root-argument json-p pinned-p)
        (parse-options kind args)
      (let* ((configured-root
               (ethereum-lisp.fixture-root-application:validate-configured-root
                root-argument :environment-name +root-env+
                :root-option "--root"
                :environment-lookup environment-lookup))
             (root (resolve-suite-root kind configured-root))
             (report (ecase kind
                       (:state (state-report root))
                       (:transaction (transaction-report root))
                       (:blockchain (blockchain-report root pinned-p)))))
        (if json-p
            (format output "~&~A~%" (json-encode-report report))
            (print-text-report report output))
        report))))
