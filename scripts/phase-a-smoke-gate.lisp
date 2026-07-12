(defparameter *ethereum-lisp-phase-a-smoke-gate-loader-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defvar *smoke-gate-run-main-p* t)

(defun load-phase-a-smoke-gate-file (relative-path)
  (load (merge-pathnames
         relative-path
         *ethereum-lisp-phase-a-smoke-gate-loader-root*)))

(dolist (relative-path
         '("scripts/phase-a-smoke-gate-options.lisp"
           "scripts/phase-a-smoke-gate-runtime.lisp"
           "scripts/phase-a-smoke-gate-fixture-summaries.lisp"
           "scripts/phase-a-smoke-gate-devnet-validation.lisp"
           "scripts/phase-a-smoke-gate-devnet-runner.lisp"
           "scripts/phase-a-smoke-gate-drift.lisp"
           "scripts/phase-a-smoke-gate-report.lisp"
           "scripts/phase-a-smoke-gate-main.lisp"))
  (load-phase-a-smoke-gate-file relative-path))
