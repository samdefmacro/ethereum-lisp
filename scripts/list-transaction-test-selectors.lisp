(defparameter *ethereum-lisp-selector-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun selector-script-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun selector-script-argument-root (args)
  (let ((root nil))
    (dolist (arg args)
      (cond
        ((and (plusp (length arg))
              (char= #\- (char arg 0)))
         (error "Unsupported selector script option ~A" arg))
        (root
         (error "Only one fixture root argument is supported"))
        (t
         (setf root arg))))
    root))

(defun selector-script-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun selector-script-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-selector-script-root*))
  (let* ((args (selector-script-arguments))
         (root-argument (selector-script-argument-root args))
         (transaction-root
           (if root-argument
               (selector-script-call
                "execution-spec-tests-transaction-test-root"
                root-argument)
               (selector-script-call
                "execution-spec-tests-transaction-test-root"))))
    (unless transaction-root
      (error "No EEST transaction_tests fixture root found. Pass a root path or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (let* ((vectors
             (selector-script-call
              "load-phase-a-eest-transaction-test-root-vectors"
              transaction-root))
           (summary
             (selector-script-call
              "validate-phase-a-eest-transaction-vector-summary"
              vectors)))
      (format t "~&root=~A~%" transaction-root)
      (format t "mode=phase-a~%")
      (format t "count=~D~%"
              (selector-script-call
               "fixture-object-field"
               summary
               "count"))
      (format t "types=~S~%"
              (selector-script-call
               "fixture-object-field"
               summary
               "types"))
      (format t "~A~%"
              (selector-script-call
               "phase-a-eest-transaction-test-selector-string")))))

(selector-script-main)
