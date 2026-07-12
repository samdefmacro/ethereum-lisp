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
             --jobs COUNT                      Run e2e tests in bounded worker processes.~%~
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
        (slowest 10)
        (jobs 1)
        (shard-count nil)
        (shard-index nil))
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
               ((string= option "--jobs")
                (multiple-value-bind (value rest)
                    (test-runner-option-value option arguments)
                  (setf jobs (parse-integer value :junk-allowed nil)
                        arguments rest)
                  (unless (plusp jobs)
                    (error "--jobs requires a positive integer"))))
               ((string= option "--shard-count")
                (multiple-value-bind (value rest)
                    (test-runner-option-value option arguments)
                  (setf shard-count (parse-integer value :junk-allowed nil)
                        arguments rest)))
               ((string= option "--shard-index")
                (multiple-value-bind (value rest)
                    (test-runner-option-value option arguments)
                  (setf shard-index (parse-integer value :junk-allowed nil)
                        arguments rest)))
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
            slowest
            jobs
            shard-count
            shard-index)))

(defun test-runner-worker-root (index)
  (merge-pathnames
   (format nil "ethereum-lisp-e2e-worker-~D-~D-~D/"
           #+sbcl (sb-unix:unix-getpid) #-sbcl 0
           (get-universal-time)
           index)
   (uiop:temporary-directory)))

(defun test-runner-worker-command
    (index count matches excludes layers timing-p slow-threshold slowest root)
  (append
   (list "env"
         (format nil "ETHEREUM_LISP_TEST_WORKER_ROOT=~A" (namestring root))
         "sbcl" "--script"
         (namestring (merge-pathnames "tests/run-tests.lisp"
                                      *test-runner-root*)))
   (loop for layer in layers append (list "--layer" layer))
   (loop for match in matches append (list "--match" match))
   (loop for exclude in excludes append (list "--exclude" exclude))
   (list "--shard-count" (write-to-string count)
         "--shard-index" (write-to-string index))
   (when timing-p (list "--timing"))
   (when slow-threshold
     (list "--slow" (write-to-string slow-threshold)))
   (list "--slowest" (write-to-string slowest))))

(defun test-runner-file-string (path)
  (if (probe-file path)
      (uiop:read-file-string path)
      ""))

(defun run-parallel-e2e
    (jobs matches excludes layers timing-p slow-threshold slowest)
  (unless (and (= 1 (length layers))
               (string-equal "e2e" (first layers)))
    (error "--jobs greater than 1 is supported only with --layer e2e"))
  (let ((workers '()))
    (unwind-protect
         (progn
           (dotimes (index jobs)
             (let* ((root (test-runner-worker-root index))
                    (stdout (merge-pathnames "stdout.log" root))
                    (stderr (merge-pathnames "stderr.log" root)))
               (ensure-directories-exist stdout)
               (push
                (list index root stdout stderr
                      (uiop:launch-program
                       (test-runner-worker-command
                        index jobs matches excludes layers timing-p
                        slow-threshold slowest root)
                       :output stdout
                       :error-output stderr))
                workers)))
           (let ((failed nil))
             (dolist (worker (sort workers #'< :key #'first))
               (destructuring-bind (index root stdout stderr process) worker
                 (declare (ignore root))
                 (let ((status (uiop:wait-process process)))
                   (format t "~&worker ~D/~D~%~A" (1+ index) jobs
                           (test-runner-file-string stdout))
                   (let ((error-text (test-runner-file-string stderr)))
                     (when (plusp (length error-text))
                       (format *error-output* "~&worker ~D stderr:~%~A"
                               (1+ index) error-text)))
                   (unless (zerop status) (setf failed t)))))
             (when failed (error "One or more e2e workers failed"))))
      (dolist (worker workers)
        (destructuring-bind (index root stdout stderr process) worker
          (declare (ignore index stdout stderr))
          (when (ignore-errors (uiop:process-alive-p process))
            (ignore-errors (uiop:terminate-process process)))
          (ignore-errors (uiop:wait-process process))
          (when (probe-file root)
            (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)))))))

(handler-case
    (multiple-value-bind
        (matches excludes layers list-only-p verbose-p timing-p
         slow-threshold slowest jobs shard-count shard-index)
        (parse-test-runner-options (uiop:command-line-arguments))
      (cond
        (list-only-p
          (uiop:symbol-call
           '#:ethereum-lisp.test '#:list-tests
           :match matches :exclude excludes :layer layers :verbose verbose-p))
        ((> jobs 1)
         (run-parallel-e2e
          jobs matches excludes layers timing-p slow-threshold slowest))
        (t
          (uiop:symbol-call
           '#:ethereum-lisp.test '#:run-tests
           :match matches :exclude excludes :layer layers
           :timing timing-p :slow-threshold slow-threshold :slowest slowest
           :shard-index shard-index :shard-count shard-count))))
  (error (condition)
    (format *error-output* "Test run failed: ~A~%" condition)
    (uiop:quit 1)))
