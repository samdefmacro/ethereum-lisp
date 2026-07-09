(in-package #:ethereum-lisp.cli)

;;;; CLI telemetry sink selection and error logging.

(defun devnet-cli-error-log-file (args)
  (when (and args (string= "devnet" (first args)))
    (setf args (rest args)))
  (setf args (devnet-cli-normalize-option-args args))
  (loop while args
        for option = (pop args)
        do (cond
             ((string= option "--log-file")
              (when (and args
                         (not (devnet-cli-option-token-p (first args))))
                (return (first args))))
             ((member option *devnet-cli-value-options* :test #'string=)
              (when (and args
                         (not (devnet-cli-option-token-p (first args))))
                (pop args)))
             ((member option
                      *devnet-cli-optional-boolean-options*
                      :test #'string=)
              (when (and args
                         (not (devnet-cli-option-token-p (first args)))
                         (devnet-cli-boolean-token-p (first args)))
                (pop args))))))

(defun devnet-cli-log-error-event (args condition)
  (let ((log-file (devnet-cli-error-log-file args)))
    (when log-file
      (devnet-cli-ensure-path-parent-directory log-file)
      (with-open-file (stream log-file
                              :direction :output
                              :if-exists :append
                              :if-does-not-exist :create)
        (ethereum-lisp.telemetry:telemetry-log
         :error
         (if (devnet-cli-init-command-p args) "init.error" "devnet.error")
         :sink (ethereum-lisp.telemetry:make-stream-telemetry-sink
                :stream stream)
         :fields `(("lifecyclePhase" . "error")
                   ("exitCode" . "1")
                   ("processId" . ,(let ((process-id (devnet-process-id)))
                                      (if process-id
                                          (write-to-string process-id)
                                          "")))
                   ("errorMessage" . ,(princ-to-string condition))
                   ("logPath" . ,log-file)))))))

(defun call-with-devnet-cli-telemetry-sink (options output-stream thunk)
  (let ((log-file (getf options :log-file)))
    (if log-file
        (with-open-file (stream (devnet-cli-ensure-path-parent-directory
                                 log-file)
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (funcall thunk
                   (ethereum-lisp.telemetry:make-stream-telemetry-sink
                    :stream stream)))
        (funcall thunk
                 (ethereum-lisp.telemetry:make-stream-telemetry-sink
                  :stream output-stream)))))
