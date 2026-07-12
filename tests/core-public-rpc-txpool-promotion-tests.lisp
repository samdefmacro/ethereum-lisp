(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-public-rpc-txpool-promotion-tests-root*
  *repository-root*)

(defun load-core-public-rpc-txpool-promotion-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-core-public-rpc-txpool-promotion-tests-root*)))

(dolist (relative-path
         '("tests/core-public-rpc-txpool-promotion-basefee-tests.lisp"
           "tests/core-public-rpc-txpool-promotion-contiguous-tests.lisp"
           "tests/core-public-rpc-txpool-promotion-balance-tests.lisp"
           "tests/core-public-rpc-txpool-canonical-drop-tests.lisp"
           "tests/core-public-rpc-txpool-canonical-nonce-tests.lisp"
           "tests/core-public-rpc-txpool-wrong-chain-tests.lisp"))
  (load-core-public-rpc-txpool-promotion-test-file relative-path))
