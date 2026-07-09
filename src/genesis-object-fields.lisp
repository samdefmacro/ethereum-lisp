(in-package #:ethereum-lisp.core)

(defun genesis-key= (key name)
  (cond
    ((stringp key) (string= key name))
    ((symbolp key) (string-equal (symbol-name key) name))
    (t nil)))

(defun genesis-object-field (object name)
  (cond
    ((null object) nil)
    ((and (listp object) (every #'consp object))
     (cdr (find name object
                :key #'car
                :test (lambda (expected key)
                        (genesis-key= key expected)))))
    ((listp object)
     (loop for (key value) on object by #'cddr
           when (genesis-key= key name)
             return value))
    (t nil)))

(defun genesis-object-field-present-p (object name)
  (cond
    ((null object) nil)
    ((and (listp object) (every #'consp object))
     (not (null (find name object
                      :key #'car
                      :test (lambda (expected key)
                              (genesis-key= key expected))))))
    ((listp object)
     (loop for (key value) on object by #'cddr
           when (genesis-key= key name)
             return t))
    (t nil)))

(defun genesis-object-field-any (object names)
  (loop for name in names
        for value = (genesis-object-field object name)
        when value
          return value))

(defun genesis-hex-quantity-string-p (value)
  (and (stringp value)
       (>= (length value) 2)
       (char= (char value 0) #\0)
       (member (char value 1) '(#\x #\X))))

(defun parse-genesis-quantity (value label &key required-p)
  (cond
    ((null value)
     (when required-p
       (block-validation-fail "~A is missing" label))
     nil)
    ((and (integerp value) (not (minusp value))) value)
    ((stringp value)
     (handler-case
         (let ((quantity (if (genesis-hex-quantity-string-p value)
                             (hex-to-quantity value)
                             (parse-integer value :radix 10))))
           (if (and (integerp quantity) (not (minusp quantity)))
               quantity
               (block-validation-fail
                "~A must be a non-negative quantity" label)))
       (error ()
         (block-validation-fail "~A must be a non-negative quantity" label))))
    (t (block-validation-fail "~A must be a non-negative quantity" label))))

(defun parse-genesis-field (object name &key label required-p)
  (parse-genesis-quantity (if (listp name)
                              (genesis-object-field-any object name)
                              (genesis-object-field object name))
                          (or label name)
                          :required-p required-p))

(defun parse-genesis-boolean-field (object name label)
  (unless (genesis-object-field-present-p object name)
    (return-from parse-genesis-boolean-field nil))
  (let ((value (genesis-object-field object name)))
    (cond
      ((eq value t) t)
      ((null value) nil)
      (t (block-validation-fail "~A must be a boolean" label)))))

(defun genesis-object-entries (object label)
  (unless (and (listp object) (every #'consp object))
    (block-validation-fail "~A must be an object" label))
  object)

(defun parse-genesis-uint256-field (object name label &key required-p)
  (let ((value (parse-genesis-field object name
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
                   (genesis-object-field-any object name)
                   (genesis-object-field object name))))
    (cond
      ((null value) default)
      (t (parse-genesis-address value label)))))
