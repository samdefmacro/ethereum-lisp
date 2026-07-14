(in-package #:ethereum-lisp.test)

(defconstant +devnet-cli-minimum-ready-timeout-seconds+ 30)

(defun devnet-cli-wait-for-file (path timeout-seconds)
  ;; A cold SBCL child can spend more than ten seconds loading the system,
  ;; especially when e2e shards run concurrently.  Keep callers free to ask
  ;; for a longer deadline while applying one shared readiness floor so test
  ;; outcomes do not depend on local CPU contention.
  (handler-case
      (wait-for-test-condition
       (format nil "file ~A" path)
       (max timeout-seconds +devnet-cli-minimum-ready-timeout-seconds+)
       (lambda () (probe-file path)))
    (error () nil)))

(defun devnet-cli-wait-process-exit (process timeout-seconds)
  (handler-case
      (progn
        (wait-for-test-condition
         "child process exit"
         timeout-seconds
         (lambda () (not (uiop:process-alive-p process)))
         :diagnostics
         (lambda () (format nil "alive=~A" (uiop:process-alive-p process))))
        (uiop:wait-process process))
    (error () :timeout)))
