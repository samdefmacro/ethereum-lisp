(defparameter *ethereum-lisp-selector-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun selector-script-argument-root ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    (first args))
  #-sbcl nil)

(defun selector-script-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun selector-script-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-selector-script-root*))
  (let* ((root-argument (selector-script-argument-root))
         (blockchain-root
           (if root-argument
               (selector-script-call "execution-spec-tests-blockchain-test-root"
                                     root-argument)
               (selector-script-call
                "execution-spec-tests-blockchain-test-root"))))
    (unless blockchain-root
      (error "No EEST blockchain fixture root found. Pass a root path or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (let ((selectors
            (selector-script-call
             "discover-phase-a-eest-blockchain-replay-selectors"
             blockchain-root)))
      (unless selectors
        (error "No materializable Phase A blockchain replay selectors found under ~A"
               blockchain-root))
      (format t "~&root=~A~%" blockchain-root)
      (format t "count=~D~%" (length selectors))
      (format t "~A~%"
              (selector-script-call
               "phase-a-eest-blockchain-replay-selector-string"
               selectors)))))

(selector-script-main)
