(in-package #:ethereum-lisp.test)

(defun devnet-cli-wait-for-file (path timeout-seconds)
  (handler-case
      (wait-for-test-condition
       (format nil "file ~A" path)
       timeout-seconds
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
