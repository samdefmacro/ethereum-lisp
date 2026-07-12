(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-phase-a-devnet-smoke-tests-root*
  *repository-root*)

(defun load-cli-phase-a-devnet-smoke-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-cli-phase-a-devnet-smoke-tests-root*)))

(dolist (relative-path
         '("tests/cli-phase-a-devnet-smoke-support-tests.lisp"
           "tests/cli-phase-a-devnet-engine-only-tests.lisp"
           "tests/cli-phase-a-devnet-artifact-tests.lisp"
           "tests/cli-phase-a-devnet-argument-tests.lisp"
           "tests/cli-phase-a-devnet-all-fixtures-tests.lisp"
           "tests/cli-phase-a-devnet-concurrency-tests.lisp"))
  (load-cli-phase-a-devnet-smoke-test-file relative-path))
