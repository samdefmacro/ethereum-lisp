(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-state-fixture-tests-root*
  *repository-root*)

(defun load-state-fixture-test-file (relative-path)
  (let ((*test-default-layer* :integration)
        (*test-default-module* :state-fixtures))
    (load (merge-pathnames
           relative-path
           *ethereum-lisp-state-fixture-tests-root*))))

(dolist (relative-path
         '("tests/state-fixture-schema.lisp"
           "tests/state-root-fixture-validation.lisp"
           "tests/state-root-fixture-runtime.lisp"
           "tests/state-proof-fixture-validation.lisp"
           "tests/state-proof-fixture-runtime.lisp"
           "tests/state-root-fixture-tests.lisp"
           "tests/state-proof-fixture-tests.lisp"))
  (load-state-fixture-test-file relative-path))
