(in-package #:ethereum-lisp.validation)

(define-condition block-validation-error (error)
  ((message :initarg :message :reader block-validation-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (block-validation-error-message condition)))))

(defun block-validation-fail (control &rest arguments)
  (error 'block-validation-error
         :message (apply #'format nil control arguments)))

(defun ensure-uint256 (value label)
  (unless (ethereum-lisp.types:uint256-p value)
    (error "~A must be a uint256, got ~S" label value))
  value)

(defun optional-bytes (value size label)
  (cond
    ((null value)
     (make-byte-vector 0))
    ((and size (= (length (ensure-byte-vector value)) size))
     (ensure-byte-vector value))
    (size
     (error "~A must be exactly ~D bytes" label size))
    (t
     (ensure-byte-vector value))))
