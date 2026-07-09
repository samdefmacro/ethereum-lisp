(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-evm-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-evm-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-evm-tests-root*)))

(dolist (relative-path
         '("tests/evm-core-tests.lisp"
           "tests/evm-memory-control-tests.lisp"
           "tests/evm-storage-access-tests.lisp"
           "tests/evm-context-environment-tests.lisp"
           "tests/evm-call-tests.lisp"
           "tests/evm-precompile-tests.lisp"
           "tests/evm-call-family-tests.lisp"
           "tests/evm-create-tests.lisp"))
  (load-evm-test-file relative-path))
