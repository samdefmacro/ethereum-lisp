(in-package #:ethereum-lisp.test)

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
