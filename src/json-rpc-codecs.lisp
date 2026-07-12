(in-package #:ethereum-lisp.json-rpc)

(defun json-rpc-required-field (object name)
  (unless (json-object-field-present-p object name)
    (invalid-parameters-fail "JSON-RPC field ~A is missing" name))
  (json-object-field object name))

(defun json-rpc-optional-quantity-field (object name)
  (when (json-object-field-present-p object name)
    (parse-json-quantity-field object name :label name)))

(defun json-rpc-required-quantity-field (object name)
  (parse-json-quantity-field object name :label name :required-p t))

(defun json-rpc-hash32 (value label)
  (unless (stringp value)
    (invalid-parameters-fail "~A must be a hex hash" label))
  (handler-case
      (hash32-from-hex value)
    (error ()
      (invalid-parameters-fail "~A must be a hash32" label))))

(defun json-rpc-address (value label)
  (unless (stringp value)
    (invalid-parameters-fail "~A must be a hex address" label))
  (handler-case
      (address-from-hex value)
    (error ()
      (invalid-parameters-fail "~A must be an address" label))))

(defun json-rpc-bytes (value label)
  (unless (stringp value)
    (invalid-parameters-fail "~A must be a hex byte string" label))
  (handler-case
      (hex-to-bytes value)
    (error ()
      (invalid-parameters-fail "~A must be a hex byte string" label))))

(defun json-rpc-required-hash32-field (object name)
  (json-rpc-hash32 (json-rpc-required-field object name) name))

(defun json-rpc-optional-hash32-value (value label)
  (when value
    (json-rpc-hash32 value label)))

(defun json-rpc-required-address-field (object name)
  (json-rpc-address (json-rpc-required-field object name) name))

(defun json-rpc-required-bytes-field (object name)
  (json-rpc-bytes (json-rpc-required-field object name) name))

(defun json-rpc-optional-bytes-field (object name)
  (when (json-object-field-present-p object name)
    (json-rpc-bytes (json-object-field object name) name)))

(defun json-rpc-byte-list (values label)
  (unless (json-array-p values)
    (invalid-parameters-fail "~A must be a list" label))
  (loop for value in (json-array-values values)
        for index from 0
        collect (json-rpc-bytes value (format nil "~A ~D" label index))))

(defun json-rpc-hash32-list (values label)
  (unless (json-array-p values)
    (invalid-parameters-fail "~A must be a list" label))
  (loop for value in (json-array-values values)
        for index from 0
        collect (json-rpc-hash32 value (format nil "~A ~D" label index))))

(defun json-rpc-required-param
    (params index label &optional (method "JSON-RPC method"))
  (unless (< index (length params))
    (invalid-parameters-fail "~A param ~A is missing" method label))
  (nth index params))

(defun json-rpc-quantity-param (params index label method)
  (parse-json-quantity
   (json-rpc-required-param params index label method)
   label
   :required-p t))
