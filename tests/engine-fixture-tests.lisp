(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-engine-fixture-tests-root*
  *repository-root*)

(defun load-engine-fixture-test-file (relative-path)
  (let ((*test-default-layer* :integration)
        (*test-default-module* :engine-fixtures))
    (load (merge-pathnames
           relative-path
           *ethereum-lisp-engine-fixture-tests-root*))))

(dolist (relative-path
         '("tests/engine-fixture-schema.lisp"
           "tests/engine-fixture-validation.lisp"
           "tests/engine-fixture-runtime.lisp"
           "tests/eest-blockchain-engine-replay-tests.lisp"
           "tests/engine-fixture-rpc-request-helpers.lisp"
           "tests/engine-fixture-shape-tests.lisp"
           "tests/engine-fixture-receipt-tests.lisp"
           "tests/engine-fixture-canonical-tests.lisp"))
  (load-engine-fixture-test-file relative-path))
