(in-package #:ethereum-lisp.core)

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
