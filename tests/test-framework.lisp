(defpackage #:ethereum-lisp.test
  (:use #:cl #:ethereum-lisp)
  (:export #:deftest #:is #:signals #:run-all-tests))

(in-package #:ethereum-lisp.test)

(defvar *tests* '())

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
  (let ((passed 0))
    (dolist (test (reverse *tests*))
      (funcall test)
      (incf passed)
      (format t "~&ok ~A" test))
    (format t "~&~D tests passed.~%" passed)
    t))
