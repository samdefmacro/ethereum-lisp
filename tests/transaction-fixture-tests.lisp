(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-transaction-fixture-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-transaction-fixture-test-file (relative-path)
  (load (merge-pathnames relative-path
                         *ethereum-lisp-transaction-fixture-tests-root*)))

(dolist (relative-path
         '("tests/transaction-fixture-shape.lisp"
           "tests/transaction-fixture-eest-loader.lisp"
           "tests/transaction-fixture-coverage.lisp"
           "tests/transaction-fixture-replay.lisp"
           "tests/transaction-fixture-suite-tests.lisp"))
  (load-transaction-fixture-test-file relative-path))
