(in-package #:ethereum-lisp.core)

(defun engine-rpc-request-methods (request)
  (cond
    ((json-object-p request)
     (let ((method (json-object-field request "method")))
       (and (stringp method) (list method))))
    ((listp request)
     (loop for item in request
           when (json-object-p item)
             append (engine-rpc-request-methods item)))
    (t nil)))

(defun engine-rpc-method-summary (methods)
  (with-output-to-string (stream)
    (loop for method in methods
          for first-p = t then nil
          do (progn
               (unless first-p
                 (write-char #\, stream))
               (write-string method stream)))))

(defun engine-rpc-http-request-telemetry-fields (request)
  (handler-case
      (multiple-value-bind (boundary boundary-length)
          (engine-rpc-http-header-boundary request)
        (let* ((head (subseq request 0 boundary))
               (body (subseq request (+ boundary boundary-length)))
               (lines (engine-rpc-http-split-lines head)))
          (unless lines
            (return-from engine-rpc-http-request-telemetry-fields nil))
          (multiple-value-bind (http-method target)
              (engine-rpc-http-request-target (first lines))
            (let* ((headers (engine-rpc-http-headers (rest lines)))
                   (body (engine-rpc-http-body body headers))
                   (methods
                     (and (plusp (length body))
                          (engine-rpc-request-methods (parse-json body)))))
              (append
               (list (cons "httpMethod" http-method)
                     (cons "httpTarget" target))
               (when methods
                 (list (cons "rpcMethods"
                             (engine-rpc-method-summary methods)))))))))
    (error () nil)))

(defun engine-rpc-http-response-status-code (response)
  (handler-case
      (parse-integer response :start 9 :end 12 :junk-allowed nil)
    (error () nil)))

(defun engine-rpc-http-response-body (response)
  (handler-case
      (multiple-value-bind (boundary boundary-length)
          (engine-rpc-http-header-boundary response)
        (let* ((head (subseq response 0 boundary))
               (body (subseq response (+ boundary boundary-length)))
               (lines (engine-rpc-http-split-lines head)))
          (engine-rpc-http-body body (engine-rpc-http-headers (rest lines)))))
    (error () nil)))

(defun engine-rpc-telemetry-summary (values)
  (with-output-to-string (stream)
    (loop for value in values
          for first-p = t then nil
          do (progn
               (unless first-p
                 (write-char #\, stream))
               (write-string value stream)))))

(defun engine-rpc-response-error-codes (response)
  (cond
    ((json-object-p response)
     (let ((error (json-object-field response "error")))
       (when (json-object-p error)
         (let ((code (json-object-field error "code")))
           (when (integerp code)
             (list (format nil "~D" code)))))))
    ((listp response)
     (loop for item in response
           append (engine-rpc-response-error-codes item)))
    (t nil)))

(defun engine-rpc-response-payload-statuses (response)
  (labels ((result-status (result)
             (when (json-object-p result)
               (let ((status (json-object-field result "status"))
                     (payload-status
                       (json-object-field result "payloadStatus")))
                 (cond
                   ((stringp status)
                    (list status))
                   ((json-object-p payload-status)
                    (let ((status
                            (json-object-field payload-status "status")))
                      (when (stringp status)
                        (list status))))
                   (t nil))))))
    (cond
      ((json-object-p response)
       (result-status (json-object-field response "result")))
      ((listp response)
       (loop for item in response
             append (engine-rpc-response-payload-statuses item)))
      (t nil))))

(defun engine-rpc-http-response-telemetry-fields (response)
  (handler-case
      (let ((body (engine-rpc-http-response-body response)))
        (when (and body (plusp (length body)))
          (let* ((rpc-response (parse-json body))
                 (error-codes
                   (engine-rpc-response-error-codes rpc-response))
                 (payload-statuses
                   (engine-rpc-response-payload-statuses rpc-response)))
            (append
             (when error-codes
               (list (cons "rpcErrorCode"
                           (engine-rpc-telemetry-summary error-codes))))
             (when payload-statuses
               (list (cons "rpcPayloadStatus"
                           (engine-rpc-telemetry-summary
                            payload-statuses))))))))
    (error () nil)))
