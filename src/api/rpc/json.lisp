(in-package #:ethereum-lisp.rpc)

(defun rpc-handle-request-string (request-json context)
  (let ((request
          (handler-case
              (parse-json request-json :preserve-types t)
            (data-decoding-error ()
              (return-from rpc-handle-request-string
                (json-rpc-parse-error-response))))))
    (rpc-handle-request-value request context)))

(defun rpc-handle-request-json (request-json context)
  (let ((response (rpc-handle-request-string request-json context)))
    (if response
        (let ((encoded (json-encode response)))
          (if (> (length encoded) +rpc-batch-response-max-size+)
              (json-encode
               (json-rpc-response
                nil
                :error
                (json-rpc-error-object -32603 "Batch response too large")))
              encoded))
        "")))

(defun engine-rpc-handle-request-string
    (request-json store config &rest options)
  (rpc-handle-request-string
   request-json
   (apply #'make-rpc-context store config options)))

(defun engine-rpc-handle-request-json
    (request-json store config &rest options)
  (rpc-handle-request-json
   request-json
   (apply #'make-rpc-context store config options)))
