(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-devnet-tests-root*
  *repository-root*)

(defun load-cli-devnet-test-file (relative-path)
  (load (merge-pathnames relative-path
                         *ethereum-lisp-cli-devnet-tests-root*)))

(dolist (relative-path
         '("tests/cli-devnet-node-tests.lisp"
           "tests/cli-devnet-live-persistence-tests.lisp"
           "tests/cli-devnet-main-tests.lisp"
           "tests/cli-devnet-txpool-period-tests.lisp"
           "tests/cli-devnet-artifact-tests.lisp"
           "tests/cli-devnet-geth-config-tests.lisp"
           "tests/cli-devnet-log-tests.lisp"))
  (load-cli-devnet-test-file relative-path))
