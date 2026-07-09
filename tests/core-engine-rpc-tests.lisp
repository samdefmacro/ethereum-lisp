(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-engine-rpc-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-core-engine-rpc-test-file (relative-path)
  (load (merge-pathnames relative-path
                         *ethereum-lisp-core-engine-rpc-tests-root*)))

(dolist (relative-path
         '("tests/core-engine-rpc-new-payload-tests.lisp"
           "tests/core-engine-rpc-forkchoice-visibility-tests.lisp"
           "tests/core-engine-rpc-payload-preparation-tests.lisp"
           "tests/core-engine-rpc-get-payload-tests.lisp"
           "tests/core-engine-rpc-payload-body-tests.lisp"
           "tests/core-engine-rpc-capability-tests.lisp"))
  (load-core-engine-rpc-test-file relative-path))
