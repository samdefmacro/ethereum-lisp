(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-execution-tests-root*
  *repository-root*)

(defun load-core-execution-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-core-execution-tests-root*)))

(dolist (relative-path
         '("tests/core-execution-commit-tests.lisp"
           "tests/core-execution-canonical-reorg-tests.lisp"
           "tests/core-execution-txpool-reinsert-tests.lisp"
           "tests/core-execution-forkchoice-reinsert-tests.lisp"))
  (load-core-execution-test-file relative-path))
