(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-serve-no-command-tests-root*
  *repository-root*)

(defun load-cli-serve-no-command-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-cli-serve-no-command-tests-root*)))

(dolist (relative-path
         '("tests/cli-serve-http-shaping-tests.lisp"
           "tests/cli-serve-http-false-tests.lisp"
           "tests/cli-serve-no-command-split-tests.lisp"
           "tests/cli-serve-no-command-import-payload-tests.lisp"
           "tests/cli-serve-no-command-engine-only-tests.lisp"))
  (load-cli-serve-no-command-test-file relative-path))
