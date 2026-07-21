(in-package #:ethereum-lisp.engine-api)

(defconstant +engine-rpc-error-unknown-payload+ -38001)
(defconstant +engine-rpc-error-invalid-forkchoice-state+ -38002)
(defconstant +engine-rpc-error-invalid-payload-attributes+ -38003)
(defconstant +engine-rpc-error-too-large-request+ -38004)
(defconstant +engine-rpc-error-unsupported-fork+ -38005)

;; EIP-1474 reserves 3 for a call that reverted; the revert bytes travel in the
;; error object's data member.
(defconstant +engine-rpc-error-execution-reverted+ 3)

(define-condition engine-rpc-error (error)
  ((code :initarg :code :reader engine-rpc-error-code)
   (message :initarg :message :reader engine-rpc-error-message)
   (data :initarg :data :initform nil :reader engine-rpc-error-data))
  (:report (lambda (condition stream)
             (format stream "~A" (engine-rpc-error-message condition)))))

(defun engine-rpc-fail (code message)
  (error 'engine-rpc-error :code code :message message))

(defun engine-rpc-fail-with-data (code message data)
  "Signal an RPC error carrying a data member alongside CODE and MESSAGE."
  (error 'engine-rpc-error :code code :message message :data data))
