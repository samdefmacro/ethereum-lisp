(in-package #:ethereum-lisp.execution-requests)

(defun validate-execution-request-fields (request)
  (let ((bytes (handler-case
                   (ensure-byte-vector request)
                 (error ()
                   (block-validation-fail
                    "Execution request must be a byte vector")))))
    (when (zerop (length bytes))
      (block-validation-fail "Execution request is missing request type"))
    bytes))

(defun validate-execution-request-list-fields (requests)
  (unless (listp requests)
    (block-validation-fail "Execution requests must be a list"))
  (loop with previous-type = nil
        for request in requests
        for bytes = (validate-execution-request-fields request)
        for request-type = (aref bytes 0)
        do (when (< (length bytes) 2)
             (block-validation-fail
              "Execution request must contain request type and payload"))
           (when (and previous-type
                      (<= request-type previous-type))
             (block-validation-fail
              "Execution requests must be ordered by unique request type"))
           (setf previous-type request-type)
        finally (return t)))

(defun execution-requests-hash (requests)
  (sha256-hash
   (apply #'concat-bytes
          (loop for request in requests
                for bytes = (validate-execution-request-fields request)
                when (> (length bytes) 1)
                  collect (sha256 bytes)))))
