(defparameter *test-runner-root*
  (merge-pathnames "../"
                   (or *load-truename* *default-pathname-defaults*)))

(load (merge-pathnames "tests/load-tests.lisp" *test-runner-root*))

(defun test-runner-usage (&optional (stream *standard-output*))
  (format stream
          "Usage: sbcl --script tests/run-tests.lisp [options]~%~
           Options:~%~
             --layer unit|integration|e2e|all  Select a layer; may be repeated.~%~
             --match TEXT                      Include matching test names; may be repeated.~%~
             --exclude TEXT                    Exclude matching test names; may be repeated.~%~
             --timing                          Print layer totals and slowest tests.~%~
             --slow SECONDS                    Report tests at or above a duration.~%~
             --slowest COUNT                   Limit the slowest-test report (default 10).~%~
             --list                            List selected tests without running them.~%~
             --verbose                         Include metadata when listing tests.~%~
           The default layer is unit. Matching is case-insensitive.~%"))

(defun test-runner-option-value (option arguments)
  (unless arguments
    (error "~A requires a value" option))
  (values (first arguments) (rest arguments)))

(defun test-runner-non-negative-real (option value)
  (handler-case
      (let ((*read-eval* nil))
        (multiple-value-bind (number position)
            (read-from-string value nil nil)
          (unless (and (realp number)
                       (not (minusp number))
                       (= position (length value)))
            (error "~A requires a non-negative number" option))
          (coerce number 'double-float)))
    (error ()
      (error "~A requires a non-negative number, got ~A" option value))))

(defun parse-test-runner-options (arguments)
  (let ((matches '())
        (excludes '())
        (layers '())
        (list-only-p nil)
        (verbose-p nil)
        (timing-p nil)
        (slow-threshold nil)
        (slowest 10))
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
               ((string= option "--layer")
                (multiple-value-bind (value rest)
                    (test-runner-option-value option arguments)
                  (push value layers)
                  (setf arguments rest)))
               ((string= option "--timing")
                (setf timing-p t))
               ((string= option "--slow")
                (multiple-value-bind (value rest)
                    (test-runner-option-value option arguments)
                  (setf slow-threshold
                        (test-runner-non-negative-real option value)
                        arguments rest)))
               ((string= option "--slowest")
                (multiple-value-bind (value rest)
                    (test-runner-option-value option arguments)
                  (setf slowest (parse-integer value :junk-allowed nil)
                        arguments rest)
                  (unless (plusp slowest)
                    (error "--slowest requires a positive integer"))))
               ((string= option "--list")
                (setf list-only-p t))
               ((string= option "--verbose")
                (setf verbose-p t))
               ((or (string= option "--help")
                    (string= option "-h"))
                (test-runner-usage)
                (uiop:quit 0))
               (t
                (error "Unknown test runner option ~A" option))))
    (values (nreverse matches)
            (nreverse excludes)
            (or (nreverse layers) '("unit"))
            list-only-p
            verbose-p
            timing-p
            slow-threshold
            slowest)))

(handler-case
    (multiple-value-bind
        (matches excludes layers list-only-p verbose-p timing-p
         slow-threshold slowest)
        (parse-test-runner-options (uiop:command-line-arguments))
      (if list-only-p
          (uiop:symbol-call
           '#:ethereum-lisp.test '#:list-tests
           :match matches :exclude excludes :layer layers :verbose verbose-p)
          (uiop:symbol-call
           '#:ethereum-lisp.test '#:run-tests
           :match matches :exclude excludes :layer layers
           :timing timing-p :slow-threshold slow-threshold :slowest slowest)))
  (error (condition)
    (format *error-output* "Test run failed: ~A~%" condition)
    (uiop:quit 1)))
