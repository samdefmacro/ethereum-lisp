(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-phase-a-script-tests-root*
  *repository-root*)

(defun load-cli-phase-a-script-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-cli-phase-a-script-tests-root*)))

(dolist (relative-path
         '("tests/cli-phase-a-application-support.lisp"
           "tests/cli-phase-a-script-support-tests.lisp"
           "tests/cli-phase-a-devnet-smoke-tests.lisp"
           "tests/cli-phase-a-report-tests.lisp"
           "tests/cli-phase-a-devnet-suite-tests.lisp"
           "tests/cli-phase-a-classifier-tests.lisp"
           "tests/cli-phase-a-drift-map-tests.lisp"))
  (load-cli-phase-a-script-test-file relative-path))
