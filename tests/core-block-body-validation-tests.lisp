(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-block-body-validation-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-core-block-body-validation-test-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-core-block-body-validation-tests-root*)))

(dolist (relative-path
         '("tests/core-block-body-root-tests.lisp"
           "tests/core-block-body-access-list-tests.lisp"
           "tests/core-block-body-blob-schedule-tests.lisp"
           "tests/core-block-body-sidecar-kzg-tests.lisp"
           "tests/core-block-body-withdrawal-tests.lisp"
           "tests/core-block-execution-receipt-tests.lisp"
           "tests/core-block-encoding-root-tests.lisp"))
  (load-core-block-body-validation-test-file relative-path))
