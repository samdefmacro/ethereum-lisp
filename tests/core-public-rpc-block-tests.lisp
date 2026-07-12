(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-public-rpc-block-tests-root*
  *repository-root*)

(defun load-core-public-rpc-block-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-core-public-rpc-block-tests-root*)))

(dolist (relative-path
         '("tests/core-public-rpc-header-tests.lisp"
           "tests/core-public-rpc-block-lookup-tests.lisp"
           "tests/core-public-rpc-uncle-tests.lisp"
           "tests/core-public-rpc-transaction-index-tests.lisp"
           "tests/core-public-rpc-transaction-object-tests.lisp"))
  (load-core-public-rpc-block-test-file relative-path))
