(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-fixture-runner-tests-root*
  *repository-root*)

(defun load-fixture-runner-test-file (relative-path)
  (let ((*test-default-layer* :integration)
        (*test-default-module* :fixture-runner))
    (load (merge-pathnames relative-path
                           *ethereum-lisp-fixture-runner-tests-root*))))

(dolist (relative-path
         '("tests/fixture-runner-state-selectors.lisp"
           "tests/fixture-runner-blockchain-selectors.lisp"
           "tests/fixture-runner-root-loading.lisp"
           "tests/fixture-runner-blockchain-materialization.lisp"
           "tests/fixture-runner-suite-tests.lisp"))
  (load-fixture-runner-test-file relative-path))
