(in-package #:ethereum-lisp.rpc)

(defun rpc-handle-request-string (request-json context)
  (let ((request
          (handler-case
              (parse-json request-json :preserve-types t)
            (data-decoding-error ()
              (return-from rpc-handle-request-string
                (json-rpc-parse-error-response))))))
    (rpc-handle-request-value request context)))

(defun rpc-batch-unrun-response (item)
  "The response for batch ITEM once the batch's response budget is spent.

A call gets geth's -32003 \"response too large\" with its own id and is never
run; a notification gets nothing; a non-object still gets its invalid-request
object, which costs no work."
  (cond
    ((not (json-object-p item)) (json-rpc-invalid-request-response))
    ((json-rpc-notification-p item) nil)
    (t (json-rpc-response
        (json-object-field item "id")
        :error (json-rpc-error-object -32003 "response too large")))))

(defun rpc-handle-batch-json (items context)
  "Run the batch ITEMS in order and return the encoded response array.

Each response is encoded as soon as it exists, so the response budget is
checked BEFORE the next item does any work, not after the whole array has been
built (*RPC-BATCH-RESPONSE-MAX-SIZE*). The response that crosses the limit is
still delivered, as geth delivers it."
  (if (> (length items) *rpc-batch-request-limit*)
      (json-encode (rpc-batch-too-large-response items))
      (let ((encoded '())
            (bytes 0)
            (spent-p nil))
        (dolist (item items)
          (let ((response
                  (cond
                    (spent-p (rpc-batch-unrun-response item))
                    ((json-object-p item) (rpc-handle-request item context))
                    (t (json-rpc-invalid-request-response)))))
            (when response
              (let ((text (json-encode response)))
                (push text encoded)
                (unless spent-p
                  (incf bytes (length text))
                  (when (> bytes *rpc-batch-response-max-size*)
                    (setf spent-p t)))))))
        (if encoded
            (with-output-to-string (out)
              (write-char #\[ out)
              (loop for (text . more) on (nreverse encoded)
                    do (write-string text out)
                       (when more (write-char #\, out)))
              (write-char #\] out))
            ""))))

(defun rpc-handle-request-json (request-json context)
  (let ((request
          (handler-case
              (parse-json request-json :preserve-types t)
            (data-decoding-error ()
              (return-from rpc-handle-request-json
                (json-encode (json-rpc-parse-error-response)))))))
    (if (and (listp request) request (not (json-object-p request)))
        (rpc-handle-batch-json request context)
        (let ((response (rpc-handle-request-value request context)))
          (if response (json-encode response) "")))))

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
