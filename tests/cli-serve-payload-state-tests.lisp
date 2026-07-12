(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-serve-payload-state-tests-root*
  *repository-root*)

(defun load-cli-serve-payload-state-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-cli-serve-payload-state-tests-root*)))

(dolist (relative-path
         '("tests/cli-serve-payload-import-tests.lisp"
           "tests/cli-serve-restored-state-tests.lisp"))
  (load-cli-serve-payload-state-test-file relative-path))
