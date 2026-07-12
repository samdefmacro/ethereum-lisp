(in-package #:ethereum-lisp.test)

(let ((*state-classifier-script-run-main-p* nil)
      (*transaction-classifier-script-run-main-p* nil)
      (*classifier-script-run-main-p* nil)
      (*drift-map-script-run-main-p* nil))
  (declare (special *state-classifier-script-run-main-p*
                    *transaction-classifier-script-run-main-p*
                    *classifier-script-run-main-p*
                    *drift-map-script-run-main-p*))
  (dolist (script '("scripts/classify-state-test-selectors.lisp"
                    "scripts/classify-transaction-test-selectors.lisp"
                    "scripts/classify-blockchain-replay-selectors.lisp"
                    "scripts/phase-a-drift-map.lisp"))
    (load (merge-pathnames script *repository-root*))))

(setf *drift-map-classifier-services-loaded-p* t)

(load (merge-pathnames "scripts/selector-application.lisp" *repository-root*))

(let ((*fixture-report-run-main-p* nil)
      (*smoke-gate-run-main-p* nil))
  (declare (special *fixture-report-run-main-p* *smoke-gate-run-main-p*))
  (load (merge-pathnames "scripts/phase-a-fixture-report.lisp"
                         *repository-root*))
  (load (merge-pathnames "scripts/phase-a-smoke-gate.lisp"
                         *repository-root*)))

(defun call-phase-a-application (thunk)
  (let ((stdout (make-string-output-stream))
        (stderr (make-string-output-stream))
        (report nil))
    (let ((status
            (ethereum-lisp.fixture-root-application:call-with-validation-result
             (lambda (output error-output)
               (setf report (funcall thunk output error-output)))
             :output stdout
             :error-output stderr)))
      (values (get-output-stream-string stdout)
              (get-output-stream-string stderr)
              status
              report))))

(defun run-classifier-application (suite args)
  (call-phase-a-application
   (lambda (output error-output)
     (ecase suite
       (:state
        (state-classifier-script-main
         :args args
         :output output
         :error-output error-output
         :load-tests-p nil))
       (:transaction
        (transaction-classifier-script-main
         :args args
         :output output
         :error-output error-output
         :load-tests-p nil))
       (:blockchain
        (classifier-script-main
         :args args
         :output output
         :error-output error-output
         :load-tests-p nil))))))

(defun run-drift-map-application (args)
  (call-phase-a-application
   (lambda (output error-output)
     (drift-map-main
      :args args
      :output output
      :error-output error-output
      :load-tests-p nil))))

(defun run-selector-application (kind args)
  (call-phase-a-application
   (lambda (output error-output)
     (ethereum-lisp.selector-application:run-selector-application
      kind args
      :output output
      :error-output error-output
      :load-tests-p nil
      :repository-root *repository-root*))))

(defun run-fixture-report-application
    (args &key (environment-lookup #'uiop:getenv))
  (call-phase-a-application
   (lambda (output error-output)
     (fixture-report-main
      :args args
      :environment-lookup environment-lookup
      :output output
      :error-output error-output
      :load-tests-p nil))))

(defun run-smoke-gate-application
    (args &key (environment-lookup #'uiop:getenv))
  (call-phase-a-application
   (lambda (output error-output)
     (smoke-gate-main
      :args args
      :environment-lookup environment-lookup
      :output output
      :error-output error-output
      :load-tests-p nil))))
