(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-suite-report-p (report)
  (string= "devnet-listener-boundary-suite"
           (or (devnet-smoke-gate-field report "mode") "")))

(defun devnet-smoke-gate-engine-only-report-p (report)
  (string= "devnet-engine-only-serve"
           (or (devnet-smoke-gate-field report "mode") "")))

