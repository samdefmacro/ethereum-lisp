(in-package #:ethereum-lisp.core)

(defparameter +engine-rpc-http-accepted-content-types+
  '("application/json" "application/json-rpc" "application/jsonrequest"))

(defun engine-rpc-http-trim (string)
  (string-trim '(#\Space #\Tab #\Return #\Newline) string))

(defun engine-rpc-http-split-lines (string)
  (loop with start = 0
        for end = (position #\Newline string :start start)
        collect (engine-rpc-http-trim
                 (subseq string start (or end (length string))))
        while end
        do (setf start (1+ end))))

(defun engine-rpc-http-request-target (request-line)
  (let* ((first-space (position #\Space request-line))
         (second-space
           (and first-space
                (position #\Space request-line :start (1+ first-space))))
         (third-space
           (and second-space
                (position #\Space request-line :start (1+ second-space)))))
    (unless (and first-space second-space (not third-space))
      (block-validation-fail "HTTP request line is malformed"))
    (let ((version (subseq request-line (1+ second-space))))
      (unless (string= version "HTTP/1.1")
        (block-validation-fail "HTTP request line is malformed"))
      (values (subseq request-line 0 first-space)
              (subseq request-line (1+ first-space) second-space)))))

(defun engine-rpc-http-target-path (target)
  (if (and (stringp target)
           (plusp (length target))
           (char= #\/ (char target 0)))
      (subseq target 0 (or (position #\? target)
                           (length target)))
      target))

(defun engine-rpc-http-target-allowed-p (target rpc-prefix)
  (let ((path (engine-rpc-http-target-path target)))
    (or (string= path rpc-prefix)
        (and (< (length rpc-prefix) (length path))
             (not (string= rpc-prefix "/"))
             (engine-rpc-string-prefix-p rpc-prefix path)
             (char= #\/ (char path (length rpc-prefix)))))))

(defun engine-rpc-http-headers (lines)
  (loop for line in lines
        unless (string= line "")
          collect
          (let ((colon (position #\: line)))
            (unless colon
              (block-validation-fail "HTTP header is malformed"))
            (let ((name (engine-rpc-http-trim (subseq line 0 colon))))
              (when (string= name "")
                (block-validation-fail "HTTP header is malformed"))
              (cons (string-downcase name)
                    (engine-rpc-http-trim (subseq line (1+ colon))))))))

(defun engine-rpc-http-header (headers name)
  (cdr (assoc (string-downcase name) headers :test #'string=)))

(defun engine-rpc-http-header-values (headers name)
  (loop with normalized = (string-downcase name)
        for (header-name . value) in headers
        when (string= normalized header-name)
          collect value))

(defun engine-rpc-http-single-header (headers name)
  (let ((values (engine-rpc-http-header-values headers name)))
    (when (rest values)
      (block-validation-fail "HTTP ~A header is duplicated" name))
    (first values)))

(defun engine-rpc-http-media-type (content-type)
  (when content-type
    (string-downcase
     (engine-rpc-http-trim
      (subseq content-type
              0
              (or (position #\; content-type)
                  (length content-type)))))))

(defun engine-rpc-http-accepted-content-type-p (content-type)
  (let ((media-type (engine-rpc-http-media-type content-type)))
    (and media-type
         (member media-type
                 +engine-rpc-http-accepted-content-types+
                 :test #'string=))))

(defun engine-rpc-http-decimal-digits-p (string)
  (and (< 0 (length string))
       (every #'digit-char-p string)))

(defun engine-rpc-http-parse-content-length (content-length)
  (let ((content-length (engine-rpc-http-trim content-length)))
    (unless (engine-rpc-http-decimal-digits-p content-length)
      (block-validation-fail "HTTP content length is invalid"))
    (parse-integer content-length :junk-allowed nil)))

(defun engine-rpc-http-header-boundary (request)
  (let ((crlf-boundary
          (search (format nil "~C~C~C~C"
                          #\Return #\Newline #\Return #\Newline)
                  request))
        (lf-boundary (search (format nil "~C~C" #\Newline #\Newline)
                             request)))
    (cond
      (crlf-boundary (values crlf-boundary 4))
      (lf-boundary (values lf-boundary 2))
      (t (block-validation-fail "HTTP request is missing header boundary")))))

(defun engine-rpc-http-body (body headers)
  (let ((content-lengths (engine-rpc-http-header-values headers "content-length")))
    (cond
      ((null content-lengths)
       body)
      ((rest content-lengths)
       (block-validation-fail "HTTP content length is duplicated"))
      (t
        (let ((length
                (engine-rpc-http-parse-content-length
                 (first content-lengths))))
          (unless (<= length (length body))
            (block-validation-fail "HTTP content length is invalid"))
          (subseq body 0 length))))))

(defun engine-rpc-request-methods (request)
  (cond
    ((json-object-p request)
     (let ((method (genesis-object-field request "method")))
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
     (let ((error (genesis-object-field response "error")))
       (when (json-object-p error)
         (let ((code (genesis-object-field error "code")))
           (when (integerp code)
             (list (format nil "~D" code)))))))
    ((listp response)
     (loop for item in response
           append (engine-rpc-response-error-codes item)))
    (t nil)))

(defun engine-rpc-response-payload-statuses (response)
  (labels ((result-status (result)
             (when (json-object-p result)
               (let ((status (genesis-object-field result "status"))
                     (payload-status
                       (genesis-object-field result "payloadStatus")))
                 (cond
                   ((stringp status)
                    (list status))
                   ((json-object-p payload-status)
                    (let ((status
                            (genesis-object-field payload-status "status")))
                      (when (stringp status)
                        (list status))))
                   (t nil))))))
    (cond
      ((json-object-p response)
       (result-status (genesis-object-field response "result")))
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

(defun engine-rpc-http-content-length (headers)
  (let ((content-lengths (engine-rpc-http-header-values headers "content-length")))
    (cond
      ((null content-lengths)
       0)
      ((rest content-lengths)
       (block-validation-fail "HTTP content length is duplicated"))
      (t
       (engine-rpc-http-parse-content-length (first content-lengths))))))

(defun engine-rpc-read-http-request-string (input-stream)
  (let ((lines '()))
    (loop for line = (read-line input-stream nil nil)
          while line
          do (push line lines)
             (when (string= "" (engine-rpc-http-trim line))
               (return)))
    (unless (and lines (string= "" (engine-rpc-http-trim (first lines))))
      (block-validation-fail "HTTP request is missing header boundary"))
    (let* ((lines (nreverse lines))
           (headers (engine-rpc-http-headers (rest lines)))
           (content-length (engine-rpc-http-content-length headers))
           (body (make-string content-length))
           (read-count (read-sequence body input-stream)))
      (unless (= read-count content-length)
        (block-validation-fail "HTTP request body is shorter than content length"))
      (with-output-to-string (request)
        (dolist (line lines)
          (write-string (engine-rpc-http-trim line) request)
          (format request "~C~C" #\Return #\Newline))
        (write-string body request)))))

(defun engine-rpc-http-response-string (status-code reason body
                                        &key
                                          (content-type "application/json")
                                          extra-headers)
  (with-output-to-string (stream)
    (format stream "HTTP/1.1 ~D ~A~C~C" status-code reason
            #\Return #\Newline)
    (when content-type
      (format stream "Content-Type: ~A~C~C" content-type #\Return #\Newline))
    (dolist (header extra-headers)
      (format stream "~A: ~A~C~C"
              (car header)
              (cdr header)
              #\Return #\Newline))
    (format stream "Connection: close~C~C" #\Return #\Newline)
    (format stream "Content-Length: ~D~C~C" (length body) #\Return #\Newline)
    (format stream "~C~C" #\Return #\Newline)
    (write-string body stream)))

(defun engine-rpc-http-error-response
    (status-code reason message &key extra-headers)
  (engine-rpc-http-response-string
   status-code reason message
   :content-type "text/plain"
   :extra-headers extra-headers))

(defun engine-rpc-http-cors-wildcard-p (origins)
  (member "*" origins :test #'string=))

(defun engine-rpc-http-cors-response-headers (headers origins)
  (let ((origin (engine-rpc-http-header headers "origin")))
    (cond
      ((null origins)
       (values nil t))
      ((engine-rpc-http-cors-wildcard-p origins)
       (values
        '(("Access-Control-Allow-Origin" . "*")
          ("Access-Control-Allow-Methods" . "GET, POST, OPTIONS")
          ("Access-Control-Allow-Headers" . "Authorization, Content-Type"))
        t))
      ((and origin (member origin origins :test #'string=))
       (values
        `(("Access-Control-Allow-Origin" . ,origin)
          ("Access-Control-Allow-Methods" . "GET, POST, OPTIONS")
          ("Access-Control-Allow-Headers" . "Authorization, Content-Type")
          ("Vary" . "Origin"))
        t))
      (origin
       (values nil nil))
      (t
       (values
        '(("Access-Control-Allow-Methods" . "GET, POST, OPTIONS")
          ("Access-Control-Allow-Headers" . "Authorization, Content-Type"))
        t)))))

(defun engine-rpc-http-host-wildcard-p (hosts)
  (member "*" hosts :test #'string=))

(defun engine-rpc-http-host-name (host)
  (let* ((host (and host (engine-rpc-http-trim host)))
         (length (and host (length host))))
    (cond
      ((or (null host) (zerop length))
       nil)
      ((and (char= #\[ (char host 0))
            (position #\] host))
       (subseq host 0 (1+ (position #\] host))))
      (t
       (let ((colon (position #\: host :from-end t)))
         (if colon
             (subseq host 0 colon)
             host))))))

(defun engine-rpc-http-host-allowed-p (headers allowed-hosts)
  (or (null allowed-hosts)
      (engine-rpc-http-host-wildcard-p allowed-hosts)
      (let ((host (engine-rpc-http-host-name
                   (engine-rpc-http-header headers "host"))))
        (and host
             (member host allowed-hosts :test #'string-equal)))))
