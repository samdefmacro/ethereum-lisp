(in-package #:ethereum-lisp.test)

(deftest public-api-package-boundary
  (let ((api (find-package '#:ethereum-lisp.public-api))
        (json-rpc (find-package '#:ethereum-lisp.json-rpc))
        (state (find-package '#:ethereum-lisp.state))
        (execution (find-package '#:ethereum-lisp.execution))
        (engine-api (find-package '#:ethereum-lisp.engine-api))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list api))))
    (is (member json-rpc (package-use-list api)))
    (is (member state (package-use-list api)))
    (is (member execution (package-use-list api)))
    (is (member engine-api (package-use-list api)))
    (multiple-value-bind (api-symbol api-status)
        (find-symbol "ENGINE-RPC-HANDLE-PUBLIC-METHOD" api)
      (multiple-value-bind (core-symbol core-status)
          (find-symbol "ENGINE-RPC-HANDLE-PUBLIC-METHOD" core)
        (is api-symbol)
        (is (eq :external api-status))
        (is (null core-symbol))
        (is (null core-status))))
    (multiple-value-bind (symbol status)
        (find-symbol "ETH-RPC-TRANSACTION-OBJECT" api)
      (is symbol)
      (is (eq :internal status)))
    (multiple-value-bind (symbol status)
        (find-symbol "ENGINE-RPC-HANDLE-HTTP-REQUEST-STRING" api)
      (is (null symbol))
      (is (null status)))))

(defparameter *ethereum-lisp-core-public-rpc-state-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-core-public-rpc-state-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-core-public-rpc-state-tests-root*)))

(dolist (relative-path
         '("tests/core-public-rpc-chain-tests.lisp"
           "tests/core-public-rpc-account-state-tests.lisp"
           "tests/core-public-rpc-proof-basic-tests.lisp"
           "tests/core-public-rpc-proof-account-trie-tests.lisp"
           "tests/core-public-rpc-proof-code-tests.lisp"
           "tests/core-public-rpc-proof-storage-tests.lisp"))
  (load-core-public-rpc-state-test-file relative-path))
