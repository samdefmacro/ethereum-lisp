(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-devnet-smoke-gate-output-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defun load-devnet-smoke-gate-output-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-devnet-smoke-gate-output-root*)))

(dolist (relative-path
         '("scripts/devnet-smoke-gate-suite-output.lisp"
           "scripts/devnet-smoke-gate-report-kind.lisp"
           "scripts/devnet-smoke-gate-text-output.lisp"))
  (load-devnet-smoke-gate-output-file relative-path))
