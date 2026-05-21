(defpackage #:ethereum-lisp.test
  (:use #:cl #:ethereum-lisp)
  (:export
   #:deftest
   #:is
   #:signals
   #:run-all-tests
   #:+execution-spec-tests-fixture-root-env+
   #:*fixture-root-environment-reader*
   #:test-skipped
   #:test-skipped-reason
   #:skip-test
   #:execution-spec-tests-fixture-root
   #:execution-spec-tests-transaction-test-root
   #:execution-spec-tests-trie-test-root
   #:with-execution-spec-tests-fixture-root
   #:with-execution-spec-tests-transaction-test-root
   #:with-execution-spec-tests-trie-test-root))

(in-package #:ethereum-lisp.test)

(defvar *tests* '())

(defconstant +execution-spec-tests-fixture-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")

(defconstant +phase-a-eest-release+ "v5.4.0")
(defconstant +phase-a-eest-tag-target+ "88e9fb8")
(defconstant +phase-a-eest-archive+ "fixtures_stable.tar.gz")

(defparameter +phase-a-eest-source-fields+
  '("release" "tagTarget" "archive" "status"))

(defparameter +execution-spec-tests-transaction-test-subdirs+
  '("fixtures/transaction_tests/"
    "spec-tests/fixtures/transaction_tests/"))

(defparameter +execution-spec-tests-trie-test-subdirs+
  '("fixtures/trie_tests/"
    "spec-tests/fixtures/trie_tests/"))

(defun default-environment-reader (name)
  #+sbcl (sb-ext:posix-getenv name)
  #-sbcl (declare (ignore name))
  #-sbcl nil)

(defvar *fixture-root-environment-reader* #'default-environment-reader)

(define-condition test-skipped (condition)
  ((reason :initarg :reason :reader test-skipped-reason))
  (:report (lambda (condition stream)
             (format stream "~A" (test-skipped-reason condition)))))

(defun skip-test (reason)
  (signal 'test-skipped :reason reason))

(defun blank-string-p (value)
  (or (null value)
      (zerop (length value))
      (every (lambda (char)
               (find char '(#\Space #\Tab #\Newline #\Return)))
             value)))

(defun fixture-object-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun fixture-field-present-p (object name)
  (not (null (assoc name object :test #'string=))))

(defun fixture-required-field (object name)
  (unless (fixture-field-present-p object name)
    (error "Fixture is missing field ~A" name))
  (fixture-object-field object name))

(defun validate-fixture-object-fields (object allowed-fields label)
  (unless (listp object)
    (error "~A must be a JSON object" label))
  (let ((seen-fields (make-hash-table :test 'equal)))
    (dolist (field object)
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
    (unless (blank-string-p value)
      (probe-file value))))

(defun execution-spec-tests-subdirectory (root subdir)
  (probe-file (merge-pathnames subdir (pathname root))))

(defun execution-spec-tests-transaction-test-root (&optional root)
  (let ((base (or root (execution-spec-tests-fixture-root))))
    (when base
      (dolist (subdir +execution-spec-tests-transaction-test-subdirs+)
        (let ((candidate (execution-spec-tests-subdirectory base subdir)))
          (when candidate
            (return candidate)))))))

(defun execution-spec-tests-trie-test-root (&optional root)
  (let ((base (or root (execution-spec-tests-fixture-root))))
    (when base
      (dolist (subdir +execution-spec-tests-trie-test-subdirs+)
        (let ((candidate (execution-spec-tests-subdirectory base subdir)))
          (when candidate
            (return candidate)))))))

(defmacro with-execution-spec-tests-fixture-root ((root) &body body)
  `(let ((,root (execution-spec-tests-fixture-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root to run this test"
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

(defmacro with-execution-spec-tests-trie-test-root ((root) &body body)
  `(let ((,root (execution-spec-tests-trie-test-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root containing trie_tests to run this test"
                +execution-spec-tests-fixture-root-env+)))
     ,@body))

(defmacro deftest (name &body body)
  `(progn
     (pushnew ',name *tests*)
     (defun ,name () ,@body)))

(defmacro is (form)
  `(unless ,form
     (error "Assertion failed: ~S" ',form)))

(defmacro signals (condition-type &body body)
  `(handler-case
       (progn
         ,@body
         (error "Expected condition ~S was not signaled" ',condition-type))
     (,condition-type () t)))

(defun run-all-tests ()
  (let ((passed 0)
        (skipped 0))
    (dolist (test (reverse *tests*))
      (handler-case
          (progn
            (funcall test)
            (incf passed)
            (format t "~&ok ~A" test))
        (test-skipped (condition)
          (incf skipped)
          (format t "~&skip ~A - ~A" test (test-skipped-reason condition)))))
    (format t "~&~D tests passed" passed)
    (when (plusp skipped)
      (format t ", ~D skipped" skipped))
    (format t ".~%")
    t))
