(in-package #:ethereum-lisp.json-rpc)

(defun json-rpc-response (id &key result error)
  (append (list (cons "jsonrpc" "2.0")
                (cons "id" id))
          (if error
              (list (cons "error" error))
              (list (cons "result" result)))))

(defun json-rpc-error-object (code message)
  (list (cons "code" code)
        (cons "message" message)))

(defun json-rpc-invalid-request-response ()
  (json-rpc-response
   nil
   :error
   (json-rpc-error-object -32600 "Invalid Request")))

(defun json-rpc-parse-error-response ()
  (json-rpc-response
   nil
   :error
   (json-rpc-error-object -32700 "Parse error")))

(defun json-rpc-version-valid-p (request)
  (let ((version (json-object-field request "jsonrpc")))
    (and (json-object-field-present-p request "jsonrpc")
         (stringp version)
         (string= "2.0" version))))

(defun json-rpc-notification-p (request)
  (and (json-object-p request)
       (json-rpc-version-valid-p request)
       (not (json-object-field-present-p request "id"))
       (stringp (json-object-field request "method"))))

(defun json-rpc-request-id-valid-p (request)
  (or (not (json-object-field-present-p request "id"))
      (let ((id (json-object-field request "id")))
        (or (null id)
            (stringp id)
            (numberp id)))))

(defun json-rpc-request-valid-p (request)
  (and (json-rpc-version-valid-p request)
       (json-rpc-request-id-valid-p request)
       (json-object-field-present-p request "method")
       (stringp (json-object-field request "method"))
       (or (not (json-object-field-present-p request "params"))
           (json-array-p (json-object-field request "params")))))
