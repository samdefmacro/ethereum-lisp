(in-package #:ethereum-lisp.core)

(defun engine-rpc-required-field (object name)
  (unless (genesis-object-field-present-p object name)
    (block-validation-fail "Engine RPC field ~A is missing" name))
  (genesis-object-field object name))

(defun engine-rpc-optional-quantity-field (object name)
  (when (genesis-object-field-present-p object name)
    (parse-genesis-field object name :label name)))

(defun engine-rpc-required-quantity-field (object name)
  (parse-genesis-field object name :label name :required-p t))

(defun engine-rpc-hash32 (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex hash" label))
  (handler-case
      (hash32-from-hex value)
    (error ()
      (block-validation-fail "~A must be a hash32" label))))

(defun engine-rpc-address (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex address" label))
  (handler-case
      (address-from-hex value)
    (error ()
      (block-validation-fail "~A must be an address" label))))

(defun engine-rpc-bytes (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be a hex byte string" label))
  (handler-case
      (hex-to-bytes value)
    (error ()
      (block-validation-fail "~A must be a hex byte string" label))))

(defun engine-rpc-required-hash32-field (object name)
  (engine-rpc-hash32 (engine-rpc-required-field object name) name))

(defun engine-rpc-optional-hash32-value (value label)
  (when value
    (engine-rpc-hash32 value label)))

(defun engine-rpc-required-address-field (object name)
  (engine-rpc-address (engine-rpc-required-field object name) name))

(defun engine-rpc-required-bytes-field (object name)
  (engine-rpc-bytes (engine-rpc-required-field object name) name))

(defun engine-rpc-optional-bytes-field (object name)
  (when (genesis-object-field-present-p object name)
    (engine-rpc-bytes (genesis-object-field object name) name)))

(defun engine-rpc-byte-list (values label)
  (unless (json-array-p values)
    (block-validation-fail "~A must be a list" label))
  (loop for value in (json-array-values values)
        for index from 0
        collect (engine-rpc-bytes value (format nil "~A ~D" label index))))

(defun engine-rpc-hash32-list (values label)
  (unless (json-array-p values)
    (block-validation-fail "~A must be a list" label))
  (loop for value in (json-array-values values)
        for index from 0
        collect (engine-rpc-hash32 value (format nil "~A ~D" label index))))
