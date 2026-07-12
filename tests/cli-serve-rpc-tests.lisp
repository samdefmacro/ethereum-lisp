(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-serve-rpc-tests-root*
  *repository-root*)

(defun load-cli-serve-rpc-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-cli-serve-rpc-tests-root*)))

(dolist (relative-path
         '("tests/cli-serve-engine-public-rpc-tests.lisp"
           "tests/cli-serve-public-txpool-tests.lisp"
           "tests/cli-serve-engine-v1-workflow-tests.lisp"))
  (load-cli-serve-rpc-test-file relative-path))
