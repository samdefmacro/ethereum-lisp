(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-transaction-fixture-suite-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-transaction-fixture-suite-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-transaction-fixture-suite-tests-root*)))

(dolist (relative-path
         '("tests/transaction-fixture-result-shape-tests.lisp"
           "tests/transaction-fixture-vector-shape-tests.lisp"
           "tests/transaction-fixture-eest-shape-tests.lisp"
           "tests/transaction-fixture-eest-root-tests.lisp"
           "tests/transaction-fixture-vector-replay-tests.lisp"))
  (load-transaction-fixture-suite-test-file relative-path))
