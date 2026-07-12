(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-trie-tests-root*
  *repository-root*)

(defun load-trie-test-file (relative-path)
  (load (merge-pathnames relative-path *ethereum-lisp-trie-tests-root*)))

(dolist (relative-path
         '("tests/trie-fixture-schema.lisp"
           "tests/eest-trie-normalization.lisp"
           "tests/eest-trie-execution.lisp"
           "tests/eest-trie-loading.lisp"
           "tests/eest-trie-coverage.lisp"
           "tests/trie-fixture-runtime.lisp"
           "tests/trie-basic-tests.lisp"
           "tests/trie-fixture-validation-tests.lisp"
           "tests/eest-trie-loading-tests.lisp"
           "tests/trie-fixture-vector-tests.lisp"))
  (load-trie-test-file relative-path))
