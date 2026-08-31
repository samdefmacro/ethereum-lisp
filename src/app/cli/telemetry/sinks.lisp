(in-package #:ethereum-lisp.cli)

;;;; CLI telemetry sink selection and error logging.

(defconstant +devnet-cli-telemetry-flush-batch-size+ 64
  "Events per backing-stream flush for a long-running node.

The Engine API can handle thousands of small requests per minute. Flushing the
Docker or file stream after every request serializes that hot path on logging.
Warnings and errors still flush immediately, and the CLI drains every partial
batch on exit.")

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
              (setf args (devnet-cli-consume-present-value args)))
             ((member option
                      *devnet-cli-optional-boolean-options*
                      :test #'string=)
              (setf args
                    (devnet-cli-consume-present-boolean-token args))))))

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
  (labels ((call-with-sink (stream)
             (let ((sink
                     (ethereum-lisp.telemetry:make-stream-telemetry-sink
                      :stream stream
                      :flush-batch-size
                      +devnet-cli-telemetry-flush-batch-size+)))
               (unwind-protect
                    (funcall thunk sink)
                 (ethereum-lisp.telemetry:flush-stream-telemetry-sink sink)))))
    (let ((log-file (getf options :log-file)))
      (if log-file
          (with-open-file (stream (devnet-cli-ensure-path-parent-directory
                                   log-file)
                                  :direction :output
                                  :if-exists :append
                                  :if-does-not-exist :create)
            (call-with-sink stream))
          (call-with-sink output-stream)))))

(defun devnet-cli-report-ignored-options (options error-stream)
  (declare (ignore error-stream))
  (let ((ignored-options (getf options :ignored-options))
        (log-file (getf options :log-file)))
    (if (and ignored-options log-file)
        (with-open-file (stream (devnet-cli-ensure-path-parent-directory
                                 log-file)
                                :direction :output
                                :if-exists :append
                                :if-does-not-exist :create)
          (dolist (option ignored-options)
            (telemetry-log
             :warning
             "cli.option_ignored"
             :fields (list (cons "option" option)
                           (cons "effect" "ignored"))
             :sink (ethereum-lisp.telemetry:make-stream-telemetry-sink
                    :stream stream))))
        (dolist (option ignored-options)
          (format *error-output*
                  "Warning: ~A is accepted for compatibility and ignored.~%"
                  option)))))
