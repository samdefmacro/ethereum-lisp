(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-engine-payload-tests-root*
  *repository-root*)

(defun load-core-engine-payload-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-core-engine-payload-tests-root*)))

(dolist (relative-path
         '("tests/core-engine-payload-mapping-tests.lisp"
           "tests/core-engine-payload-block-tests.lisp"
           "tests/core-engine-payload-status-tests.lisp"
           "tests/core-engine-payload-memory-admission-tests.lisp"
           "tests/core-engine-payload-memory-import-tests.lisp"
           "tests/core-engine-payload-execution-outcome-tests.lisp"))
  (load-core-engine-payload-test-file relative-path))
