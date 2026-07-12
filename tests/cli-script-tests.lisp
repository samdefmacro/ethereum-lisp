(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-script-tests-root*
  *repository-root*)

(defun load-cli-script-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-cli-script-tests-root*)))

(dolist (relative-path
         '("tests/cli-script-help-tests.lisp"
           "tests/cli-script-devnet-json-tests.lisp"
           "tests/cli-script-serve-tests.lisp"
           "tests/cli-script-no-command-serve-tests.lisp"
           "tests/cli-script-no-command-import-tests.lisp"
           "tests/cli-script-engine-only-tests.lisp"
           "tests/cli-script-runner-artifact-tests.lisp"
           "tests/cli-script-wait-helpers.lisp"))
  (load-cli-script-test-file relative-path))
