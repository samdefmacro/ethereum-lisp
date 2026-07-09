(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-public-rpc-txpool-admission-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-core-public-rpc-txpool-admission-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-core-public-rpc-txpool-admission-tests-root*)))

(dolist (relative-path
         '("tests/core-public-rpc-txpool-send-tests.lisp"
           "tests/core-public-rpc-txpool-signature-tests.lisp"
           "tests/core-public-rpc-txpool-policy-tests.lisp"
           "tests/core-public-rpc-txpool-preflight-tests.lisp"
           "tests/core-public-rpc-txpool-limits-tests.lisp"
           "tests/core-public-rpc-txpool-lifetime-tests.lisp"
           "tests/core-public-rpc-txpool-nonce-flow-tests.lisp"
           "tests/core-public-rpc-txpool-blob-tests.lisp"))
  (load-core-public-rpc-txpool-admission-test-file relative-path))
