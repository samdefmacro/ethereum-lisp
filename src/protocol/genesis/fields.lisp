(in-package #:ethereum-lisp.genesis)

(defun parse-genesis-boolean-field (object name label)
  (unless (json-object-field-present-p object name)
    (return-from parse-genesis-boolean-field nil))
  (let ((value (json-object-field object name)))
    (cond
      ((eq value t) t)
      ((null value) nil)
      (t (block-validation-fail "~A must be a boolean" label)))))

(defun parse-genesis-uint256-field (object name label &key required-p)
  (let ((value (parse-json-quantity-field object name
                                          :label label
                                          :required-p required-p)))
    (when value
      (ensure-uint256 value label))))

(defun parse-genesis-address (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex address" label))
  (handler-case
      (address-from-hex value)
    (error ()
      (block-validation-fail "~A must be a 20-byte hex address" label))))

(defun parse-genesis-address-field (object name label &key default)
  (let ((value (if (listp name)
                   (json-object-field-any object name)
                   (json-object-field object name))))
    (if (null value)
        default
        (parse-genesis-address value label))))
