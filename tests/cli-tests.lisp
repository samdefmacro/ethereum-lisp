(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-cli-tests-root*
  *repository-root*)

(defun load-cli-test-file
    (relative-path layer &key launches-processes requires-local-sockets)
  (let ((*test-default-layer* layer)
        (*test-default-module* :cli)
        (*test-default-launches-processes-p* launches-processes)
        (*test-default-requires-local-sockets-p* requires-local-sockets))
    (load (merge-pathnames relative-path *ethereum-lisp-cli-tests-root*))))

(dolist (entry
         '(("tests/cli-test-support.lisp" :integration)
           ("tests/cli-devnet-tests.lisp" :integration)
           ("tests/cli-phase-a-script-tests.lisp" :e2e
            :launches-processes t)
           ("tests/cli-script-tests.lisp" :e2e
            :launches-processes t)
           ("tests/cli-serve-mode-tests.lisp" :e2e
            :launches-processes t :requires-local-sockets t)))
  (apply #'load-cli-test-file entry))
