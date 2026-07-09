(in-package #:ethereum-lisp.test)

(defun devnet-cli-http-body (response)
  (let ((boundary (search (format nil "~C~C~C~C"
                                  #\Return #\Newline
                                  #\Return #\Newline)
                          response)))
    (subseq response (+ boundary 4))))

(defun devnet-cli-http-status (response)
  (let* ((line-end (position #\Return response))
         (status-line (subseq response 0 line-end)))
    (parse-integer status-line :start 9 :end 12)))

(defun devnet-cli-json-rpc-http-request
    (body &key token (target "/") (host "localhost") origin)
  (with-output-to-string (stream)
    (format stream "POST ~A HTTP/1.1~%Host: ~A~%" target host)
    (format stream "Content-Type: application/json~%")
    (when origin
      (format stream "Origin: ~A~%" origin))
    (when token
      (format stream "Authorization: Bearer ~A~%" token))
    (format stream "Content-Length: ~D~%~%~A" (length body) body)))

(defun devnet-cli-json-rpc-duplicate-auth-http-request
    (body first-token second-token &key (target "/") (host "localhost")
       origin)
  (with-output-to-string (stream)
    (format stream "POST ~A HTTP/1.1~%Host: ~A~%" target host)
    (format stream "Content-Type: application/json~%")
    (when origin
      (format stream "Origin: ~A~%" origin))
    (format stream "Authorization: Bearer ~A~%" first-token)
    (format stream "Authorization: Bearer ~A~%" second-token)
    (format stream "Content-Length: ~D~%~%~A" (length body) body)))

(defun devnet-cli-options-http-request
    (&key (target "/") (host "localhost") origin
       (request-method "POST") request-headers)
  (with-output-to-string (stream)
    (format stream "~A ~A HTTP/1.1~%Host: ~A~%"
            request-method target host)
    (when origin
      (format stream "Origin: ~A~%" origin))
    (dolist (header request-headers)
      (format stream "~A: ~A~%" (car header) (cdr header)))
    (format stream "Content-Length: 0~%~%")))

