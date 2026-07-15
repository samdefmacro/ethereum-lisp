(in-package #:ethereum-lisp.json)

(defstruct (json-null
            (:constructor %make-json-null ())))

(defparameter +json-null+ (%make-json-null))
(defparameter +json-false+ :false)

(defun json-false-p (value)
  (eq value +json-false+))

(defstruct (json-empty-object
            (:constructor make-json-empty-object ())))

(defparameter +json-empty-object+ (make-json-empty-object))
