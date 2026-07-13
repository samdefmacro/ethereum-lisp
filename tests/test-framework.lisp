(defpackage #:ethereum-lisp.test
  (:use #:cl #:ethereum-lisp)
  (:export
   #:deftest
   #:is
   #:signals
   #:list-tests
   #:run-tests
   #:run-all-tests
   #:test-metadata
   #:test-metadata-layer
   #:test-metadata-module
   #:test-metadata-launches-processes-p
   #:test-metadata-requires-local-sockets-p
   #:test-metadata-estimated-seconds
   #:test-result
   #:test-result-name
   #:test-result-layer
   #:test-result-status
   #:test-result-elapsed-seconds
   #:test-result-condition
   #:*last-test-results*
   #:*test-default-layer*
   #:*test-default-module*
   #:*test-default-launches-processes-p*
   #:*test-default-requires-local-sockets-p*
   #:test-run-failed
   #:test-run-failed-failures
   #:test-launch-program
   #:call-with-test-process-scope
   #:wait-for-test-condition
   #:+execution-spec-tests-fixture-root-env+
   #:*fixture-root-environment-reader*
   #:test-skipped
   #:test-skipped-reason
   #:skip-test
   #:execution-spec-tests-fixture-root
   #:execution-spec-tests-blockchain-test-root
   #:execution-spec-tests-transaction-test-root
   #:execution-spec-tests-state-test-root
   #:execution-spec-tests-trie-test-root
   #:execution-spec-tests-json-paths
   #:execution-spec-tests-root-json-paths
   #:execution-spec-tests-root-file-names
   #:execution-spec-tests-root-case-name
   #:execution-spec-tests-source-style-name-p
   #:validate-execution-spec-tests-selector-list
   #:filter-execution-spec-tests-root-cases
   #:with-execution-spec-tests-fixture-root
   #:with-execution-spec-tests-blockchain-test-root
   #:with-execution-spec-tests-transaction-test-root
   #:with-execution-spec-tests-state-test-root
   #:with-execution-spec-tests-trie-test-root
   #:repo-kzg-verifier-command))

(in-package #:ethereum-lisp.test)

(defvar *tests* '())

(defparameter +test-layers+ '(:unit :integration :e2e))

(defvar *test-default-layer* :unit)
(defvar *test-default-module* nil)
(defvar *test-default-launches-processes-p* nil)
(defvar *test-default-requires-local-sockets-p* nil)

(defstruct test-metadata
  (layer :unit :type keyword)
  module
  (launches-processes-p nil :type boolean)
  (requires-local-sockets-p nil :type boolean)
  (estimated-seconds 1d0 :type double-float))

(defstruct test-result
  name
  (layer :unit :type keyword)
  (status :passed :type keyword)
  (elapsed-seconds 0d0 :type double-float)
  condition)

(defvar *test-metadata* (make-hash-table :test #'eq))
(defvar *last-test-results* '())
(defvar *test-owned-processes* nil)

(defparameter *test-process-termination-grace-seconds* 2d0)
(defparameter *test-process-termination-urgent-seconds* 2d0)

(defun normalize-test-layer (layer &key allow-all)
  (let ((normalized
          (etypecase layer
            (keyword layer)
            (symbol (intern (symbol-name layer) :keyword))
            (string (intern (string-upcase layer) :keyword)))))
    (unless (or (member normalized +test-layers+)
                (and allow-all (eq normalized :all)))
      (error "Test layer must be one of ~{~(~A~)~^, ~}~@[ or all~], got ~A"
             +test-layers+
             allow-all
             layer))
    normalized))

(defun register-test
    (name &key layer module
               (launches-processes nil launches-processes-supplied-p)
               (requires-local-sockets nil requires-local-sockets-supplied-p)
               (estimated-seconds 1d0))
  (pushnew name *tests*)
  (setf (gethash name *test-metadata*)
        (make-test-metadata
         :layer (normalize-test-layer (or layer *test-default-layer*))
         :module (or module *test-default-module*)
         :launches-processes-p
         (if launches-processes-supplied-p
             launches-processes
             *test-default-launches-processes-p*)
         :requires-local-sockets-p
         (if requires-local-sockets-supplied-p
             requires-local-sockets
             *test-default-requires-local-sockets-p*)
         :estimated-seconds (coerce estimated-seconds 'double-float)))
  name)

(defun metadata-for-test (test)
  (or (gethash test *test-metadata*)
      (error "Test ~A has no metadata" test)))

(defparameter *repository-root*
  (asdf:system-source-directory '#:ethereum-lisp))

(load (merge-pathnames "scripts/fixture-root-application.lisp"
                       *repository-root*))

(defun repository-relative-pathname (relative)
  (merge-pathnames relative *repository-root*))

(defparameter *repo-kzg-verifier-command*
  (repository-relative-pathname #P"scripts/kzg-verifier.sh"))

(defun repo-kzg-verifier-command ()
  (or (probe-file *repo-kzg-verifier-command*)
      (error "Missing repo KZG verifier command at ~A"
             *repo-kzg-verifier-command*)))

(defparameter +execution-spec-tests-fixture-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")

(defparameter +phase-a-eest-release+ "v5.4.0")
(defparameter +phase-a-eest-tag-target+ "88e9fb8")
(defparameter +phase-a-eest-archive+ "fixtures_stable.tar.gz")

(defparameter +phase-a-eest-source-fields+
  '("release" "tagTarget" "archive" "status"))

(defparameter +execution-spec-tests-transaction-test-subdirs+
  '("transaction_tests/"
    "fixtures/transaction_tests/"
    "spec-tests/fixtures/transaction_tests/"))

(defparameter +execution-spec-tests-state-test-subdirs+
  '("state_tests/"
    "fixtures/state_tests/"
    "spec-tests/fixtures/state_tests/"))

(defparameter +execution-spec-tests-trie-test-subdirs+
  '("trie_tests/"
    "fixtures/trie_tests/"
    "spec-tests/fixtures/trie_tests/"))

(defparameter +execution-spec-tests-blockchain-test-subdirs+
  '("blockchain_tests_engine/"
    "blockchain_tests/"
    "fixtures/blockchain_tests_engine/"
    "fixtures/blockchain_tests/"
    "spec-tests/fixtures/blockchain_tests_engine/"
    "spec-tests/fixtures/blockchain_tests/"))

(defun default-environment-reader (name)
  #+sbcl (sb-ext:posix-getenv name)
  #-sbcl (declare (ignore name))
  #-sbcl nil)

(defvar *fixture-root-environment-reader* #'default-environment-reader)

(define-condition test-skipped (condition)
  ((reason :initarg :reason :reader test-skipped-reason))
  (:report (lambda (condition stream)
             (format stream "~A" (test-skipped-reason condition)))))

(define-condition test-run-failed (error)
  ((failures :initarg :failures :reader test-run-failed-failures))
  (:report
   (lambda (condition stream)
     (format stream "~D test~:P failed"
             (length (test-run-failed-failures condition))))))

(defun skip-test (reason)
  (signal 'test-skipped :reason reason))

(defun blank-string-p (value)
  (or (null value)
      (zerop (length value))
      (every (lambda (char)
               (find char '(#\Space #\Tab #\Newline #\Return)))
             value)))

(defun fixture-object-field (object name)
  (ethereum-lisp.json:json-object-field object name))

(defun fixture-field-present-p (object name)
  (ethereum-lisp.json:json-object-field-present-p object name))

(defun fixture-json-object-p (value)
  (or (null value)
      (ethereum-lisp.json:json-object-p value)))

(defun fixture-required-field (object name)
  (unless (fixture-field-present-p object name)
    (error "Fixture is missing field ~A" name))
  (fixture-object-field object name))

(defun validate-fixture-object-fields (object allowed-fields label)
  (unless (fixture-json-object-p object)
    (error "~A must be a JSON object" label))
  (let ((seen-fields (make-hash-table :test 'equal)))
    (dolist (field (ethereum-lisp.json:json-object-entries object label))
      (let ((name (car field)))
        (unless (stringp name)
          (error "~A field name must be a string" label))
        (when (gethash name seen-fields)
          (error "~A has duplicate field ~A" label name))
        (setf (gethash name seen-fields) t)
        (unless (member name allowed-fields :test #'string=)
          (error "~A has unknown field ~A" label name))))))

(defun fixture-file-string (path)
  (with-open-file (stream path :direction :input)
    (with-output-to-string (out)
      (loop for line = (read-line stream nil nil)
            while line
            do (progn
                 (write-string line out)
                 (terpri out))))))

(defun validate-fixture-format (fixture expected-format)
  (unless (string= expected-format
                   (validate-fixture-required-string-field
                    fixture "format" "Fixture"))
    (error "Fixture format must be ~A" expected-format)))

(defun validate-fixture-required-string-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A.~A must be a string" label field))
    value))

(defun validate-fixture-pinned-eest-source (fixture)
  (let ((source (fixture-required-field fixture "executionSpecTests")))
    (unless (listp source)
      (error "Fixture executionSpecTests must be a JSON object"))
    (validate-fixture-object-fields
     source
     +phase-a-eest-source-fields+
     "Fixture executionSpecTests")
    (unless (string= +phase-a-eest-release+
                     (validate-fixture-required-string-field
                      source "release" "Fixture executionSpecTests"))
      (error "Fixture executionSpecTests.release must be ~A"
             +phase-a-eest-release+))
    (unless (string= +phase-a-eest-tag-target+
                     (validate-fixture-required-string-field
                      source "tagTarget" "Fixture executionSpecTests"))
      (error "Fixture executionSpecTests.tagTarget must be ~A"
             +phase-a-eest-tag-target+))
    (unless (string= +phase-a-eest-archive+
                     (validate-fixture-required-string-field
                      source "archive" "Fixture executionSpecTests"))
      (error "Fixture executionSpecTests.archive must be ~A"
             +phase-a-eest-archive+))
    (when (blank-string-p
           (validate-fixture-required-string-field
            source "status" "Fixture executionSpecTests"))
      (error "Fixture executionSpecTests.status must be present"))))

(defun execution-spec-tests-fixture-root
    (&key (env-var +execution-spec-tests-fixture-root-env+))
  (let ((value (funcall *fixture-root-environment-reader* env-var)))
    (unless (or (null value) (stringp value))
      (error "Execution spec tests fixture root must be a string or nil"))
    (unless (blank-string-p value)
      (probe-file value))))

(defun execution-spec-tests-resolved-root (root)
  (if root
      (progn
        (unless (or (stringp root) (pathnamep root))
          (error "Execution spec tests fixture root must be a string, pathname, or nil"))
        (probe-file root))
      (execution-spec-tests-fixture-root)))

(defun execution-spec-tests-subdirectory (root subdir)
  (probe-file (merge-pathnames subdir (pathname root))))

(defun execution-spec-tests-subdirectory-json-p (root subdir)
  (let ((candidate (execution-spec-tests-subdirectory root subdir)))
    (and candidate
         (not (null (execution-spec-tests-json-paths candidate))))))

(defun execution-spec-tests-first-existing-subdirectory
    (root subdirs &key require-json-p)
  (when root
    (let ((first-existing nil))
      (dolist (subdir subdirs)
        (let ((candidate (execution-spec-tests-subdirectory root subdir)))
          (when candidate
            (unless first-existing
              (setf first-existing candidate))
            (when (or (not require-json-p)
                      (execution-spec-tests-subdirectory-json-p root subdir))
              (return-from execution-spec-tests-first-existing-subdirectory
                candidate)))))
      first-existing)))

(defun execution-spec-tests-json-paths (root)
  (let* ((root-path (pathname root))
         (pattern
           (make-pathname
            :directory (append (pathname-directory root-path)
                               (list :wild-inferiors))
            :name :wild
            :type "json"
            :defaults root-path)))
    (sort (directory pattern) #'string< :key #'namestring)))

(defun execution-spec-tests-root-json-paths (root label)
  (let ((paths (execution-spec-tests-json-paths root)))
    (unless paths
      (error "~A root ~A has no JSON files" label root))
    paths))

(defun execution-spec-tests-root-file-names (root label)
  (mapcar (lambda (path)
            (enough-namestring (truename path) (truename root)))
          (execution-spec-tests-root-json-paths root label)))

(defun execution-spec-tests-root-case-name (root path key singleton-p)
  (let ((relative (enough-namestring (truename path) (truename root))))
    (if singleton-p
        relative
        (format nil "~A/~A" relative key))))

(defun execution-spec-tests-source-style-name-p
    (name &key allow-nested-case-name)
  (and (stringp name)
       (not (blank-string-p name))
       (not (char= (char name 0) #\/))
       (null (search ".." name))
       (null (search "//" name))
       (let* ((json-position (search ".json" name :test #'char-equal))
              (after-json (and json-position (+ json-position 5))))
         (and json-position
              (plusp json-position)
              (not (char= (char name (1- json-position)) #\/))
              (or (= after-json (length name))
                  (and (< after-json (length name))
                       (char= (char name after-json) #\/)
                       (< (1+ after-json) (length name))
                       (not (char= (char name (1+ after-json)) #\/))
                       (or allow-nested-case-name
                           (null (position #\/ name
                                           :start (1+ after-json))))))))))

(defun validate-execution-spec-tests-selector-list
    (names label &key allow-nested-case-name)
  (unless (listp names)
    (error "~A selector list must be a list" label))
  (unless names
    (error "~A selector list must not be empty" label))
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (name names)
      (unless (stringp name)
        (error "~A selector name must be a string" label))
      (when (blank-string-p name)
        (error "~A selector name must be present" label))
      (unless (execution-spec-tests-source-style-name-p
               name
               :allow-nested-case-name allow-nested-case-name)
        (error "~A selector ~A must be a source-style JSON case name"
               label name))
      (when (gethash name seen)
        (error "~A selector list has duplicate name ~A" label name))
      (setf (gethash name seen) t))))

(defun filter-execution-spec-tests-root-cases
    (cases names label &key (selector-order-p t))
  (let ((case-index (make-hash-table :test 'equal)))
    (dolist (case cases)
      (let ((name (fixture-required-field case "name")))
        (when (gethash name case-index)
          (error "~A root has duplicate case name ~A" label name))
        (setf (gethash name case-index) case)))
    (if names
        (if selector-order-p
            (mapcar
             (lambda (name)
               (or (gethash name case-index)
                   (error "~A selector ~A did not match any loaded case"
                          label name)))
             names)
            (let ((selected nil)
                  (seen (make-hash-table :test 'equal)))
              (dolist (case cases)
                (let ((name (fixture-required-field case "name")))
                  (when (member name names :test #'string=)
                    (push case selected)
                    (setf (gethash name seen) t))))
              (dolist (name names)
                (unless (gethash name seen)
                  (error "~A selector ~A did not match any loaded case"
                         label name)))
              (nreverse selected)))
        cases)))

(defun execution-spec-tests-blockchain-test-root (&optional root)
  (let ((base (execution-spec-tests-resolved-root root)))
    (execution-spec-tests-first-existing-subdirectory
     base
     +execution-spec-tests-blockchain-test-subdirs+
     :require-json-p t)))

(defun execution-spec-tests-transaction-test-root (&optional root)
  (let ((base (execution-spec-tests-resolved-root root)))
    (execution-spec-tests-first-existing-subdirectory
     base
     +execution-spec-tests-transaction-test-subdirs+
     :require-json-p t)))

(defun execution-spec-tests-state-test-root (&optional root)
  (let ((base (execution-spec-tests-resolved-root root)))
    (execution-spec-tests-first-existing-subdirectory
     base
     +execution-spec-tests-state-test-subdirs+
     :require-json-p t)))

(defun execution-spec-tests-trie-test-root (&optional root)
  (let ((base (execution-spec-tests-resolved-root root)))
    (execution-spec-tests-first-existing-subdirectory
     base
     +execution-spec-tests-trie-test-subdirs+
     :require-json-p t)))

(defmacro with-execution-spec-tests-fixture-root ((root) &body body)
  `(let ((,root (execution-spec-tests-fixture-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro with-execution-spec-tests-blockchain-test-root ((root) &body body)
  `(let ((,root (execution-spec-tests-blockchain-test-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root containing blockchain_tests_engine or blockchain_tests to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro with-execution-spec-tests-transaction-test-root ((root) &body body)
  `(let ((,root (execution-spec-tests-transaction-test-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root containing transaction_tests to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro with-execution-spec-tests-state-test-root ((root) &body body)
  `(let ((,root (execution-spec-tests-state-test-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root containing state_tests to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro with-execution-spec-tests-trie-test-root ((root) &body body)
  `(let ((,root (execution-spec-tests-trie-test-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root containing trie_tests to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun split-deftest-options (body)
    (let ((candidate (first body)))
      (if (and (consp candidate)
               (keywordp (first candidate)))
          (progn
            (unless (evenp (length candidate))
              (error "deftest metadata must be a property list: ~S" candidate))
            (loop for tail on candidate by #'cddr
                  for key = (first tail)
                  do (unless (member key
                                     '(:layer :module :launches-processes
                                       :requires-local-sockets
                                       :estimated-seconds))
                       (error "Unsupported deftest metadata key ~S" key)))
            (values candidate (rest body)))
          (values nil body)))))

(defmacro deftest (name &body body)
  (multiple-value-bind (options forms)
      (split-deftest-options body)
    `(progn
       (register-test ',name ,@options)
       (defun ,name () ,@forms))))

(defmacro is (form)
  `(unless ,form
     (error "Assertion failed: ~S" ',form)))

(defmacro signals (condition-type &body body)
  `(handler-case
       (progn
         ,@body
         (error "Expected condition ~S was not signaled" ',condition-type))
     (,condition-type () t)))

(defun test-filter-list (filters)
  (cond
    ((null filters) nil)
    ((stringp filters) (list filters))
    ((and (listp filters) (every #'stringp filters)) filters)
    (t (error "Test filters must be a string or a list of strings"))))

(defun test-name-matches-filter-p (test filter)
  (search filter (symbol-name test) :test #'char-equal))

(defun test-layer-filter-list (layers)
  (cond
    ((null layers) nil)
    ((or (stringp layers) (symbolp layers))
     (let ((layer (normalize-test-layer layers :allow-all t)))
       (unless (eq layer :all) (list layer))))
    ((listp layers)
     (let ((normalized
             (mapcar (lambda (layer)
                       (normalize-test-layer layer :allow-all t))
                     layers)))
       (if (member :all normalized) nil normalized)))
    (t (error "Test layers must be a layer or a list of layers"))))

(defun selected-tests (&key match exclude layer)
  (let ((match-filters (test-filter-list match))
        (exclude-filters (test-filter-list exclude))
        (layers (test-layer-filter-list layer)))
    (remove-if-not
     (lambda (test)
       (and (or (null match-filters)
                (some (lambda (filter)
                        (test-name-matches-filter-p test filter))
                      match-filters))
            (not (some (lambda (filter)
                         (test-name-matches-filter-p test filter))
                       exclude-filters))
            (or (null layers)
                (member (test-metadata-layer (metadata-for-test test))
                        layers))))
     (reverse *tests*))))

(defun list-tests
    (&key match exclude layer verbose (stream *standard-output*))
  (let ((tests (selected-tests :match match :exclude exclude :layer layer)))
    (dolist (test tests)
      (let ((metadata (metadata-for-test test)))
        (if verbose
            (progn
              (format stream "~A [~(~A~)" test (test-metadata-layer metadata))
              (when (test-metadata-module metadata)
                (format stream " module=~A" (test-metadata-module metadata)))
              (when (test-metadata-launches-processes-p metadata)
                (format stream " process"))
              (when (test-metadata-requires-local-sockets-p metadata)
                (format stream " socket"))
              (format stream "]~%"))
            (format stream "~A~%" test))))
    tests))

(defun monotonic-seconds ()
  (/ (get-internal-real-time)
     (coerce internal-time-units-per-second 'double-float)))

(defun balanced-test-shards (tests shard-count)
  "Partition TESTS deterministically using declared duration estimates."
  (let ((buckets (make-array shard-count :initial-element nil))
        (totals (make-array shard-count :initial-element 0d0))
        (positions (make-hash-table :test #'eq)))
    (loop for test in tests for position from 0
          do (setf (gethash test positions) position))
    (dolist (test
             (stable-sort
              (copy-list tests) #'>
              :key (lambda (name)
                     (test-metadata-estimated-seconds
                      (metadata-for-test name)))))
      (let ((target 0))
        (dotimes (index shard-count)
          (when (< (aref totals index) (aref totals target))
            (setf target index)))
        (push test (aref buckets target))
        (incf (aref totals target)
              (test-metadata-estimated-seconds (metadata-for-test test)))))
    (dotimes (index shard-count buckets)
      (setf (aref buckets index)
            (sort (aref buckets index) #'< :key
                  (lambda (test) (gethash test positions)))))))

(defun test-launch-program (command &rest keys)
  "Launch COMMAND and register the child for unconditional per-test cleanup."
  (let ((process (apply #'uiop:launch-program command keys)))
    (when (boundp '*test-owned-processes*)
      (push process *test-owned-processes*))
    process))

(defun wait-test-process-with-timeout (process timeout-seconds)
  "Return the process status and true, or NIL and NIL when TIMEOUT-SECONDS elapses."
  (let ((deadline (+ (monotonic-seconds) timeout-seconds)))
    (loop
      (unless (ignore-errors (uiop:process-alive-p process))
        (return (values (ignore-errors (uiop:wait-process process)) t)))
      (when (>= (monotonic-seconds) deadline)
        (return (values nil nil)))
      (sleep 0.05d0))))

(defun reap-test-process (process)
  "Bounded TERM-then-KILL cleanup for a child launched by a test."
  (when (ignore-errors (uiop:process-alive-p process))
    (ignore-errors (uiop:terminate-process process)))
  (multiple-value-bind (status exited-p)
      (wait-test-process-with-timeout
       process *test-process-termination-grace-seconds*)
    (if exited-p
        status
        (progn
          (ignore-errors (uiop:terminate-process process :urgent t))
          (multiple-value-bind (urgent-status urgent-exited-p)
              (wait-test-process-with-timeout
               process *test-process-termination-urgent-seconds*)
            (declare (ignore urgent-exited-p))
            urgent-status)))))

(defun call-with-test-process-scope (thunk)
  "Run THUNK and reap every child launched through TEST-LAUNCH-PROGRAM."
  (let ((*test-owned-processes* '()))
    (unwind-protect
         (funcall thunk)
      (dolist (process *test-owned-processes*)
        (reap-test-process process)))))

(defun wait-for-test-condition
    (label timeout-seconds predicate
     &key (interval-seconds 0.05d0) diagnostics)
  "Wait for PREDICATE and report LABEL, elapsed time, and diagnostics on timeout."
  (let ((started (monotonic-seconds)))
    (loop
      (let ((value (funcall predicate)))
        (when value (return value)))
      (let ((elapsed (- (monotonic-seconds) started)))
        (when (>= elapsed timeout-seconds)
          (error "Timed out after ~,3Fs waiting for ~A~@[; ~A~]"
                 elapsed label (and diagnostics (funcall diagnostics)))))
      (sleep interval-seconds))))

(defun report-test-timings (results stream slowest slow-threshold)
  (let* ((total (reduce #'+ results
                        :key #'test-result-elapsed-seconds
                        :initial-value 0d0))
         (slow-results
           (stable-sort
            (remove-if (lambda (result)
                         (and slow-threshold
                              (< (test-result-elapsed-seconds result)
                                 slow-threshold)))
                       (copy-list results))
            #'>
            :key #'test-result-elapsed-seconds)))
    (format stream "Execution time: ~,3Fs" total)
    (dolist (layer +test-layers+)
      (let* ((layer-results
               (remove layer results :test-not #'eq :key #'test-result-layer))
             (elapsed
               (reduce #'+ layer-results
                       :key #'test-result-elapsed-seconds
                       :initial-value 0d0)))
        (when layer-results
          (format stream ", ~(~A~)=~,3Fs" layer elapsed))))
    (format stream ".~%")
    (when slow-results
      (let ((shown (if slowest
                       (subseq slow-results 0 (min slowest (length slow-results)))
                       slow-results)))
        (format stream "Slowest tests~@[ (>= ~,3Fs)~]:~%" slow-threshold)
        (dolist (result shown)
          (format stream "  ~,3Fs ~(~A~) ~A [~(~A~)]~%"
                  (test-result-elapsed-seconds result)
                  (test-result-status result)
                  (test-result-name result)
                  (test-result-layer result)))))))

(defun run-tests
    (&key match exclude layer (stream *standard-output*) timing
          (slowest 10) slow-threshold shard-index shard-count)
  (let* ((selected
           (selected-tests :match match :exclude exclude :layer layer))
         (tests
           (if shard-count
               (aref (balanced-test-shards selected shard-count) shard-index)
               selected))
        (passed 0)
        (skipped 0)
        (failures '())
        (results '()))
    (unless (or tests shard-count)
      (error "No tests matched the requested filters"))
    (dolist (test tests)
      (let* ((metadata (metadata-for-test test))
             (started (monotonic-seconds))
             (status :passed)
             (observed-condition nil))
        (handler-case
            (progn
              (call-with-test-process-scope test)
              (incf passed)
              (format stream "~&ok ~A" test))
          (test-skipped (condition)
            (setf status :skipped
                  observed-condition condition)
            (incf skipped)
            (format stream "~&skip ~A - ~A"
                    test
                    (test-skipped-reason condition)))
          (error (condition)
            (setf status :failed
                  observed-condition condition)
            (push (cons test condition) failures)
            (format stream "~&not ok ~A - ~A" test condition)))
        (push (make-test-result
               :name test
               :layer (test-metadata-layer metadata)
               :status status
               :elapsed-seconds (- (monotonic-seconds) started)
               :condition observed-condition)
              results)
      (finish-output stream)
      (finish-output *error-output*)))
    (setf results (nreverse results)
          *last-test-results* results)
    (format stream "~&~D test~:P passed" passed)
    (when (plusp skipped)
      (format stream ", ~D skipped" skipped))
    (when failures
      (format stream ", ~D failed" (length failures)))
    (format stream ".~%")
    (when (or timing slow-threshold)
      (report-test-timings results stream slowest slow-threshold))
    (when failures
      (error 'test-run-failed :failures (nreverse failures)))
    (values t passed skipped results)))

(defun run-all-tests ()
  (run-tests :layer :all))
