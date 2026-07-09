(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-serve-mode-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-cli-serve-mode-test-file (relative-path)
  (load (merge-pathnames relative-path
                         *ethereum-lisp-cli-serve-mode-tests-root*)))

(dolist (relative-path
         '("tests/cli-serve-rpc-tests.lisp"
           "tests/cli-serve-payload-state-tests.lisp"
           "tests/cli-serve-no-command-tests.lisp"
           "tests/cli-runner-edge-tests.lisp"))
  (load-cli-serve-mode-test-file relative-path))
