(in-package #:ethereum-lisp.evm.internal)

(defun apply-child-execution-result (state context snapshot child-result)
  (let ((child-gas-used (evm-result-gas-used child-result))
        (child-return-data (evm-result-return-data child-result)))
    (if (eq (evm-result-status child-result) :reverted)
        (progn
          (restore-execution-snapshot state context snapshot)
          (values 0 child-gas-used child-return-data '() 0))
        (values 1
                child-gas-used
                child-return-data
                (evm-result-logs child-result)
                (evm-result-refund-counter child-result)))))

(defun failed-precompile-child-gas-used (condition child-gas-limit)
  ;; A precompile's scheduled gas remains useful on the condition for direct
  ;; callers and diagnostics, but any error returned by the precompile burns
  ;; all gas forwarded to the child call.
  (declare (ignore condition))
  child-gas-limit)

(defun failed-child-execution-gas-used (child-started-p
                                        child-gas-limit
                                        child-gas-used)
  (if child-started-p
      child-gas-limit
      child-gas-used))

(defun failed-create-child-gas-used (child-started-p
                                     child-gas-limit
                                     child-gas-used)
  (if (and child-started-p child-gas-limit)
      child-gas-limit
      child-gas-used))

(defun copy-child-return-data-to-memory (memory
                                         return-offset
                                         return-size
                                         child-return-data)
  (copy-into-memory
   memory
   return-offset
   (call-output-data-slice child-return-data return-size)))

(defun prepend-child-logs (child-logs logs)
  (append (reverse child-logs) logs))
