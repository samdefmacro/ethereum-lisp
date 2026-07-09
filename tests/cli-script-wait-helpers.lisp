(in-package #:ethereum-lisp.test)

(defun devnet-cli-wait-for-file (path timeout-seconds)
  (loop repeat (* timeout-seconds 20)
        when (probe-file path)
          return t
        do (sleep 0.05)
        finally (return nil)))

(defun devnet-cli-wait-process-exit (process timeout-seconds)
  (loop repeat (* timeout-seconds 20)
        unless (uiop:process-alive-p process)
          return (uiop:wait-process process)
        do (sleep 0.05)
        finally (return :timeout)))

