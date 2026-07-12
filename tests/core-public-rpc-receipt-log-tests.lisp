(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-public-rpc-receipt-log-tests-root*
  *repository-root*)

(defun load-core-public-rpc-receipt-log-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-core-public-rpc-receipt-log-tests-root*)))

(dolist (relative-path
         '("tests/core-public-rpc-receipt-tests.lisp"
           "tests/core-public-rpc-log-tests.lisp"
           "tests/core-public-rpc-log-filter-tests.lisp"
           "tests/core-public-rpc-block-filter-tests.lisp"))
  (load-core-public-rpc-receipt-log-test-file relative-path))
