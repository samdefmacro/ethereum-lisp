(defparameter *ethereum-lisp-selector-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defconstant +selector-script-pinned-v5.4.0-flag+ "--pinned-v5.4.0")
(defconstant +selector-script-json-flag+ "--json")

(defun selector-script-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun selector-script-pinned-v5.4.0-p (args)
  (member +selector-script-pinned-v5.4.0-flag+ args :test #'string=))

(defun selector-script-json-p (args)
  (member +selector-script-json-flag+ args :test #'string=))

(defun selector-script-argument-root (args)
  (let ((root nil))
    (dolist (arg args)
      (cond
        ((string= arg +selector-script-pinned-v5.4.0-flag+))
        ((string= arg +selector-script-json-flag+))
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

(defun selector-script-json-encode (object)
  (let ((symbol (find-symbol "JSON-ENCODE" "ETHEREUM-LISP")))
    (unless (and symbol (fboundp symbol))
      (error "JSON encoder is unavailable"))
    (funcall (symbol-function symbol) object)))

(defun selector-script-blockchain-kind-object (selectors)
  (mapcar (lambda (entry)
            (list (cons "name" (car entry))
                  (cons "kind" (cdr entry))))
          selectors))

(defun selector-script-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-selector-script-root*))
  (let* ((args (selector-script-arguments))
         (pinned-p (selector-script-pinned-v5.4.0-p args))
         (json-p (selector-script-json-p args))
         (root-argument (selector-script-argument-root args))
         (blockchain-root
           (if root-argument
               (selector-script-call "execution-spec-tests-blockchain-test-root"
                                     root-argument)
               (selector-script-call
                "execution-spec-tests-blockchain-test-root"))))
    (unless blockchain-root
      (error "No EEST blockchain fixture root found. Pass a root path or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (let ((selectors
            (if pinned-p
                (selector-script-call
                 "phase-a-eest-blockchain-pinned-v5.4.0-replay-materialization-kinds"
                 blockchain-root)
                (selector-script-call
                 "discover-phase-a-eest-blockchain-replay-selectors"
                 blockchain-root))))
      (unless selectors
        (error "No materializable Phase A blockchain replay selectors found under ~A"
               blockchain-root))
      (let ((mode (if pinned-p "pinned-v5.4.0" "discover"))
            (selector-string
              (selector-script-call
               "phase-a-eest-blockchain-replay-selector-string"
               selectors)))
        (if json-p
            (format t "~&~A~%"
                    (selector-script-json-encode
                     (list
                      (cons "root" (namestring blockchain-root))
                      (cons "mode" mode)
                      (cons "count" (length selectors))
                      (cons "selectors"
                            (selector-script-blockchain-kind-object
                             selectors))
                      (cons "selectorString" selector-string))))
            (progn
              (format t "~&root=~A~%" blockchain-root)
              (format t "mode=~A~%" mode)
              (format t "count=~D~%" (length selectors))
              (format t "~A~%" selector-string)))))))

(selector-script-main)
