(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-public-rpc-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-core-public-rpc-test-file (relative-path)
  (load (merge-pathnames relative-path
                         *ethereum-lisp-core-public-rpc-tests-root*)))

(dolist (relative-path
         '("tests/core-public-rpc-state-tests.lisp"
           "tests/core-public-rpc-simulation-tests.lisp"
           "tests/core-public-rpc-block-tests.lisp"
           "tests/core-public-rpc-txpool-admission-tests.lisp"
           "tests/core-public-rpc-txpool-promotion-tests.lisp"
           "tests/core-public-rpc-receipt-log-tests.lisp"
           "tests/core-http-service-tests.lisp"
           "tests/core-block-body-validation-tests.lisp"))
  (load-core-public-rpc-test-file relative-path))
