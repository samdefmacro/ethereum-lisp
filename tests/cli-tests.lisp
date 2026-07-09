(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-cli-test-file (relative-path)
  (load (merge-pathnames relative-path *ethereum-lisp-cli-tests-root*)))

(dolist (relative-path
         '("tests/cli-test-support.lisp"
           "tests/cli-devnet-tests.lisp"
           "tests/cli-phase-a-script-tests.lisp"
           "tests/cli-script-tests.lisp"
           "tests/cli-serve-mode-tests.lisp"))
  (load-cli-test-file relative-path))
