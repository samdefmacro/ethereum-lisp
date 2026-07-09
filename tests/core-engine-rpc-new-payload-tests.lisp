(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-engine-rpc-new-payload-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-core-engine-rpc-new-payload-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-core-engine-rpc-new-payload-tests-root*)))

(dolist (relative-path
         '("tests/core-engine-rpc-new-payload-cache-tests.lisp"
           "tests/core-engine-rpc-dispatch-tests.lisp"
           "tests/core-engine-rpc-new-payload-import-tests.lisp"
           "tests/core-engine-rpc-new-payload-sender-receipt-tests.lisp"
           "tests/core-engine-rpc-new-payload-typed-receipt-tests.lisp"
           "tests/core-engine-rpc-new-payload-v3-blob-tests.lisp"))
  (load-core-engine-rpc-new-payload-test-file relative-path))
