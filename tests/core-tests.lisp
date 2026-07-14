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

(defun load-core-test-file (relative-path &optional (layer :unit) module)
  (let ((*test-default-layer* layer)
        (*test-default-module* module))
    (load (merge-pathnames relative-path *ethereum-lisp-core-tests-root*))))

(dolist (entry
         '(("tests/core-transaction-tests.lisp" :unit :transaction)
           ("tests/core-genesis-tests.lisp" :unit :genesis)
           ("tests/core-block-tests.lisp" :unit :block)
           ("tests/core-engine-payload-tests.lisp" :unit :engine)
           ("tests/core-chain-store-payload-candidate-export-tests.lisp"
            :unit :persistence)
           ("tests/core-chain-store-tests.lisp" :integration :persistence)
           ("tests/core-txpool-tests.lisp" :unit :txpool)
           ("tests/core-execution-tests.lisp" :unit :execution)
           ("tests/core-engine-rpc-tests.lisp" :unit :engine-rpc)
           ("tests/core-public-rpc-tests.lisp" :unit :public-rpc)))
  (apply #'load-core-test-file entry))
