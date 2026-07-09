(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-core-test-file (relative-path)
  (load (merge-pathnames relative-path *ethereum-lisp-core-tests-root*)))

(dolist (relative-path
         '("tests/core-transaction-tests.lisp"
           "tests/core-genesis-tests.lisp"
           "tests/core-block-tests.lisp"
           "tests/core-engine-payload-tests.lisp"
           "tests/core-chain-store-tests.lisp"
           "tests/core-txpool-tests.lisp"
           "tests/core-execution-tests.lisp"
           "tests/core-engine-rpc-tests.lisp"
           "tests/core-public-rpc-tests.lisp"))
  (load-core-test-file relative-path))
