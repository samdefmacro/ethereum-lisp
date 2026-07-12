(defparameter *ethereum-lisp-selector-script-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(require :asdf)

(load (merge-pathnames "scripts/fixture-root-application.lisp"
                       *ethereum-lisp-selector-script-root*))

(defconstant +selector-script-json-flag+ "--json")
(defconstant +selector-script-root-option+ "--root")
(defconstant +selector-script-eest-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")

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

(defun selector-script-blank-string-p (value)
  (ethereum-lisp.fixture-root-application:blank-string-p value))

(defun selector-script-reject-missing-configured-root (root-argument)
  (ethereum-lisp.fixture-root-application:validate-configured-root
   root-argument
   :environment-name +selector-script-eest-root-env+
   :root-option +selector-script-root-option+))

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

(defun selector-script-variable (name)
  (let ((symbol (find-symbol (string-upcase name) "ETHEREUM-LISP.TEST")))
    (unless (and symbol (boundp symbol))
      (error "Fixture variable ~A is unavailable" name))
    (symbol-value symbol)))

(defun selector-script-reject-empty-selected-root (root label)
  (ethereum-lisp.fixture-root-application:validate-non-empty-root
   root label
   (lambda (path)
     (selector-script-call "execution-spec-tests-json-paths" path))))

(defun selector-script-main ()
  (load (merge-pathnames "tests/load-tests.lisp"
                         *ethereum-lisp-selector-script-root*))
  (let* ((args (selector-script-arguments))
         (json-p (selector-script-json-p args))
         (root-argument (selector-script-argument-root args))
         (transaction-root
           (if root-argument
               (selector-script-call
                "execution-spec-tests-transaction-test-root"
                root-argument)
               (selector-script-call
                "execution-spec-tests-transaction-test-root"))))
    (selector-script-reject-missing-configured-root root-argument)
    (unless transaction-root
      (error "No EEST transaction_tests fixture root found. Pass a root path or set ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT."))
    (selector-script-reject-empty-selected-root
     transaction-root
     "transaction_tests")
    (let* ((vectors
             (selector-script-call
              "load-phase-a-eest-transaction-test-root-vectors"
              transaction-root))
           (summary
             (selector-script-call
              "validate-phase-a-eest-transaction-vector-summary"
              vectors))
           (selectors
             (selector-script-variable
              "+phase-a-eest-transaction-test-case-names+"))
           (selector-string
             (selector-script-call
              "phase-a-eest-transaction-test-selector-string"
              selectors))
           (count
             (selector-script-call
              "fixture-object-field"
              summary
              "count"))
           (types
             (selector-script-call
              "fixture-object-field"
              summary
              "types")))
      (if json-p
          (format t "~&~A~%"
                  (selector-script-json-encode
                   (list
                    (cons "root" (namestring transaction-root))
                    (cons "mode" "phase-a")
                    (cons "count" count)
                    (cons "types" types)
                    (cons "selectors" selectors)
                    (cons "selectorString" selector-string))))
          (progn
            (format t "~&root=~A~%" transaction-root)
            (format t "mode=phase-a~%")
            (format t "count=~D~%" count)
            (format t "types=~S~%" types)
            (format t "~A~%" selector-string))))))

(selector-script-main)
