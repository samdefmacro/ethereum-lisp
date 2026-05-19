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
   #:with-execution-spec-tests-fixture-root))

(in-package #:ethereum-lisp.test)

(defvar *tests* '())

(defconstant +execution-spec-tests-fixture-root-env+
  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT")

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

(defun execution-spec-tests-fixture-root
    (&key (env-var +execution-spec-tests-fixture-root-env+))
  (let ((value (funcall *fixture-root-environment-reader* env-var)))
    (unless (blank-string-p value)
      (probe-file value))))

(defmacro with-execution-spec-tests-fixture-root ((root) &body body)
  `(let ((,root (execution-spec-tests-fixture-root)))
     (unless ,root
       (skip-test
        (format nil
                "Set ~A to an execution-spec-tests fixture root to run this test"
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
