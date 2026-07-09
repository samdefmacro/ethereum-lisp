(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-state-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-state-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-state-tests-root*)))

(dolist (relative-path
         '("tests/state-genesis-validation.lisp"
           "tests/state-proof-basic-tests.lisp"
           "tests/state-proof-layout-tests.lisp"
           "tests/state-mutation-tests.lisp"
           "tests/state-genesis-json-tests.lisp"
           "tests/state-genesis-shape-tests.lisp"
           "tests/state-transaction-execution-tests.lisp"))
  (load-state-test-file relative-path))
