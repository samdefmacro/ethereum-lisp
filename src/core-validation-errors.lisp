(in-package #:ethereum-lisp.validation)

(define-condition block-validation-error (error)
  ((message :initarg :message :reader block-validation-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (block-validation-error-message condition)))))

(defun block-validation-fail (control &rest arguments)
  (error 'block-validation-error
         :message (apply #'format nil control arguments)))
