(in-package #:ethereum-lisp.test)

(deftest core-package-is-a-compatibility-facade
  (let ((api (find-package '#:ethereum-lisp))
        (core (find-package '#:ethereum-lisp.core)))
    (is (member api (package-use-list core)))
    (is (= 2 (length (package-use-list core))))
    (is (every (lambda (package)
                 (member package (list (find-package '#:cl) api)))
               (package-use-list core)))
    (do-external-symbols (api-symbol api)
      (multiple-value-bind (core-symbol core-status)
          (find-symbol (symbol-name api-symbol) core)
        (is (eq :external core-status))
        (is (eq api-symbol core-symbol))))
    (do-external-symbols (core-symbol core)
      (multiple-value-bind (api-symbol api-status)
          (find-symbol (symbol-name core-symbol) api)
        (is (eq :external api-status))
        (is (eq api-symbol core-symbol))
        (is (not (eq core (symbol-package core-symbol))))))))

(defparameter *ethereum-lisp-core-tests-root*
  *repository-root*)

(defun load-core-test-file (relative-path)
  (load (merge-pathnames relative-path *ethereum-lisp-core-tests-root*)))

(dolist (relative-path
         '("tests/core-transaction-tests.lisp"
           "tests/core-genesis-tests.lisp"
           "tests/core-block-tests.lisp"
           "tests/core-engine-payload-tests.lisp"
           "tests/core-chain-store-tests.lisp"
           "tests/core-txpool-tests.lisp"
           "tests/core-execution-tests.lisp"
           "tests/core-engine-rpc-tests.lisp"
           "tests/core-public-rpc-tests.lisp"))
  (load-core-test-file relative-path))
