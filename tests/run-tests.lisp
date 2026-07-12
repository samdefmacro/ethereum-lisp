(defparameter *test-runner-root*
  (merge-pathnames "../"
                   (or *load-truename* *default-pathname-defaults*)))

(load (merge-pathnames "tests/load-tests.lisp" *test-runner-root*))

(defun test-runner-usage (&optional (stream *standard-output*))
  (format stream
          "Usage: sbcl --script tests/run-tests.lisp [--match TEXT] [--exclude TEXT] [--list]~%~
           Options may be repeated. Matching is case-insensitive and uses test-name substrings.~%"))

(defun test-runner-option-value (option arguments)
  (unless arguments
    (error "~A requires a value" option))
  (values (first arguments) (rest arguments)))

(defun parse-test-runner-options (arguments)
  (let ((matches '())
        (excludes '())
        (list-only-p nil))
    (when (and arguments (string= "--" (first arguments)))
      (setf arguments (rest arguments)))
    (loop while arguments
          for option = (pop arguments)
          do (cond
               ((string= option "--match")
                (multiple-value-bind (value rest)
                    (test-runner-option-value option arguments)
                  (push value matches)
                  (setf arguments rest)))
               ((string= option "--exclude")
                (multiple-value-bind (value rest)
                    (test-runner-option-value option arguments)
                  (push value excludes)
                  (setf arguments rest)))
               ((string= option "--list")
                (setf list-only-p t))
               ((or (string= option "--help")
                    (string= option "-h"))
                (test-runner-usage)
                (uiop:quit 0))
               (t
                (error "Unknown test runner option ~A" option))))
    (values (nreverse matches) (nreverse excludes) list-only-p)))

(handler-case
    (multiple-value-bind (matches excludes list-only-p)
        (parse-test-runner-options (uiop:command-line-arguments))
      (if list-only-p
          (uiop:symbol-call
           '#:ethereum-lisp.test '#:list-tests
           :match matches :exclude excludes)
          (uiop:symbol-call
           '#:ethereum-lisp.test '#:run-tests
           :match matches :exclude excludes)))
  (error (condition)
    (format *error-output* "Test run failed: ~A~%" condition)
    (uiop:quit 1)))
