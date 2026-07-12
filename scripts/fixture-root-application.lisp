(defpackage #:ethereum-lisp.fixture-root-application
  (:use #:cl)
  (:export
   #:blank-string-p
   #:validate-configured-root
   #:validate-non-empty-root
   #:call-with-validation-result))

(in-package #:ethereum-lisp.fixture-root-application)

(defun blank-string-p (value)
  (or (null value)
      (zerop (length
              (string-trim '(#\Space #\Tab #\Newline #\Return) value)))))

(defun validate-configured-root
    (root-argument
     &key
       (environment-name "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")
       (root-option "--root")
       (environment-lookup #'uiop:getenv)
       (probe #'probe-file))
  "Validate an explicitly configured fixture root without consulting globals.
Returns the configured value, or NIL when neither argv nor the environment
configured a root."
  (let* ((source (if root-argument root-option environment-name))
         (configured
           (or root-argument
               (funcall environment-lookup environment-name))))
    (when (and (not (blank-string-p configured))
               (not (funcall probe configured)))
      (error "Configured EEST fixture root from ~A does not exist: ~A"
             source
             configured))
    configured))

(defun validate-non-empty-root (root label json-paths-reader)
  "Validate a resolved suite root using an injected JSON discovery function."
  (when (and root (not (funcall json-paths-reader root)))
    (error "Configured EEST ~A fixture root contains no JSON files: ~A"
           label
           root))
  root)

(defun call-with-validation-result
    (thunk &key (output *standard-output*) (error-output *error-output*))
  "Run THUNK as an application service and return a process-style status.
The streams are explicit so tests never need to rebind process globals."
  (handler-case
      (progn
        (funcall thunk output error-output)
        0)
    (error (condition)
      (format error-output "~A~%" condition)
      1)))
