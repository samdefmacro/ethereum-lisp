(in-package #:ethereum-lisp.engine-api)

(defconstant +engine-rpc-error-unknown-payload+ -38001)
(defconstant +engine-rpc-error-invalid-forkchoice-state+ -38002)
(defconstant +engine-rpc-error-invalid-payload-attributes+ -38003)
(defconstant +engine-rpc-error-too-large-request+ -38004)
(defconstant +engine-rpc-error-unsupported-fork+ -38005)

(define-condition engine-rpc-error (error)
  ((code :initarg :code :reader engine-rpc-error-code)
   (message :initarg :message :reader engine-rpc-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (engine-rpc-error-message condition)))))

(defun engine-rpc-fail (code message)
  (error 'engine-rpc-error :code code :message message))
