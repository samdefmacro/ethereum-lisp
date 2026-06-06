(defparameter *ethereum-lisp-selector-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defconstant +selector-script-json-flag+ "--json")
(defconstant +selector-script-root-option+ "--root")

(defun selector-script-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun selector-script-json-p (args)
  (member +selector-script-json-flag+ args :test #'string=))

(defun selector-script-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun selector-script-set-argument-root (root value)
  (when root
    (error "Only one fixture root argument is supported"))
  value)

(defun selector-script-argument-root (args)
  (let ((root nil))
    (loop while args
          for arg = (pop args)
          do
      (cond
        ((string= arg +selector-script-json-flag+))
        ((string= arg +selector-script-root-option+)
         (unless args
           (error "~A requires a fixture root path"
                  +selector-script-root-option+))
         (let ((value (pop args)))
           (when (selector-script-option-like-p value)
             (error "~A requires a fixture root path, got option ~A"
                    +selector-script-root-option+
                    value))
           (setf root (selector-script-set-argument-root root value))))
        ((selector-script-option-like-p arg)
         (error "Unsupported selector script option ~A" arg))
        (t
         (setf root (selector-script-set-argument-root root arg)))))
    root))

(defun selector-script-call (name &rest args)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (fboundp symbol))
      (error "Fixture helper ~A is unavailable" name))
    (apply (symbol-function symbol) args)))

(defun selector-script-json-encode (object)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) object)))

(defun selector-script-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-selector-script-root*))
  (let* ((args (selector-script-arguments))
         (json-p (selector-script-json-p args))
         (root-argument (selector-script-argument-root args))
         (state-root
           (if root-argument
               (selector-script-call "execution-spec-tests-state-test-root"
                                     root-argument)
               (selector-script-call
                "execution-spec-tests-state-test-root"))))
    (unless state-root
      (error "No EEST state_tests fixture root found. Pass a root path or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (let ((selectors
            (selector-script-call
             "discover-phase-a-eest-state-test-selectors"
             state-root)))
      (unless selectors
        (error "No materializable Phase A state_tests selectors found under ~A"
               state-root))
      (let ((selector-string
              (selector-script-call
               "phase-a-eest-state-test-selector-string"
               selectors)))
        (if json-p
            (format t "~&~A~%"
                    (selector-script-json-encode
                     (list
                      (cons "root" (namestring state-root))
                      (cons "mode" "discover")
                      (cons "count" (length selectors))
                      (cons "selectors" selectors)
                      (cons "selectorString" selector-string))))
            (progn
              (format t "~&root=~A~%" state-root)
              (format t "mode=discover~%")
              (format t "count=~D~%" (length selectors))
              (format t "~A~%" selector-string)))))))

(selector-script-main)
