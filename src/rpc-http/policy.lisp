(in-package #:ethereum-lisp.rpc-http)

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

(defun engine-rpc-http-response-string (status-code reason body
                                        &key
                                          (content-type "application/json")
                                          extra-headers)
  (with-output-to-string (stream)
    (format stream "HTTP/1.1 ~D ~A~C~C" status-code reason
            #\Return #\Newline)
    (when content-type
      (format stream "Content-Type: ~A~C~C"
              content-type #\Return #\Newline))
    (dolist (header extra-headers)
      (format stream "~A: ~A~C~C"
              (car header)
              (cdr header)
              #\Return #\Newline))
    (format stream "Connection: close~C~C" #\Return #\Newline)
    (format stream "Content-Length: ~D~C~C"
            (length body) #\Return #\Newline)
    (format stream "~C~C" #\Return #\Newline)
    (write-string body stream)))

(defun engine-rpc-http-error-response
    (status-code reason message &key extra-headers)
  (engine-rpc-http-response-string
   status-code reason message
   :content-type "text/plain"
   :extra-headers extra-headers))
