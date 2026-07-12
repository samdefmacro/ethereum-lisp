(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-execution-tests-root*
  *repository-root*)

(defun load-execution-test-file (relative-path)
  (load (merge-pathnames relative-path *ethereum-lisp-execution-tests-root*)))

(dolist (relative-path
         '("tests/execution-message-preflight-tests.lisp"
           "tests/execution-block-basic-tests.lisp"
           "tests/execution-fork-preflight-tests.lisp"
           "tests/execution-environment-fee-tests.lisp"
           "tests/execution-access-list-tests.lisp"
           "tests/execution-set-code-tests.lisp"
           "tests/execution-blob-tests.lisp"
           "tests/execution-contract-creation-tests.lisp"
           "tests/execution-revert-refund-tests.lisp"))
  (load-execution-test-file relative-path))
