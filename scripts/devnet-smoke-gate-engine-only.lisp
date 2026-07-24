(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-devnet-smoke-gate-engine-only-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-devnet-smoke-gate-engine-only-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-devnet-smoke-gate-engine-only-root*)))

(dolist (relative-path
         '("scripts/devnet-smoke-gate-engine-only-serve.lisp"))
  (load-devnet-smoke-gate-engine-only-file relative-path))
