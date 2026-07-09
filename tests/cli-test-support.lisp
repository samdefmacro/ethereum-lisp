(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-test-support-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-cli-test-support-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-cli-test-support-root*)))

(dolist (relative-path
         '("tests/cli-support-basic.lisp"
           "tests/cli-support-engine-reports.lisp"
           "tests/cli-support-public-reports.lisp"
           "tests/cli-support-restored-reports.lisp"
           "tests/cli-support-pruned-reorg-reports.lisp"
           "tests/cli-support-engine-fixtures.lisp"
           "tests/cli-support-http-requests.lisp"
           "tests/cli-support-node-requests.lisp"))
  (load-cli-test-support-file relative-path))
