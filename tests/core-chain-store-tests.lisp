(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-core-chain-store-tests-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-core-chain-store-test-file (relative-path)
  (load (merge-pathnames relative-path
                         *ethereum-lisp-core-chain-store-tests-root*)))

(dolist (relative-path
         '("tests/core-chain-store-basic-tests.lisp"
           "tests/core-chain-store-kv-export-tests.lisp"
           "tests/core-chain-store-txpool-persistence-tests.lisp"
           "tests/core-chain-store-invalid-tipset-tests.lisp"
           "tests/core-chain-store-remote-block-tests.lisp"
           "tests/core-chain-store-blob-sidecar-tests.lisp"
           "tests/core-chain-store-prepared-payload-tests.lisp"
           "tests/core-chain-store-import-validation-tests.lisp"
           "tests/core-chain-store-state-db-tests.lisp"
           "tests/core-chain-store-atomic-commit-tests.lisp"))
  (load-core-chain-store-test-file relative-path))
