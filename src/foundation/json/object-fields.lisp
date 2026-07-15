(in-package #:ethereum-lisp.json)

(defun json-key= (key name)
  (cond
    ((stringp key) (string= key name))
    ((symbolp key) (string-equal (symbol-name key) name))
    (t nil)))

(defun json-object-field (object name)
  (cond
    ((or (null object) (json-empty-object-p object)) nil)
    ((and (listp object) (every #'consp object))
     (cdr (find name object
                :key #'car
                :test (lambda (expected key)
                        (json-key= key expected)))))
    ((listp object)
     (loop for (key value) on object by #'cddr
           when (json-key= key name)
             return value))
    (t nil)))

(defun json-object-field-present-p (object name)
  (cond
    ((or (null object) (json-empty-object-p object)) nil)
    ((and (listp object) (every #'consp object))
     (not (null (find name object
                      :key #'car
                      :test (lambda (expected key)
                              (json-key= key expected))))))
    ((listp object)
     (loop for (key value) on object by #'cddr
           when (json-key= key name)
             return t))
    (t nil)))

(defun json-object-field-any (object names)
  (loop for name in names
        for value = (json-object-field object name)
        when value
          return value))

(defun json-hex-quantity-string-p (value)
  (and (stringp value)
       (>= (length value) 2)
       (char= (char value 0) #\0)
       (member (char value 1) '(#\x #\X))))

(defun parse-json-quantity (value label &key required-p)
  (cond
    ((or (null value) (json-null-p value))
     (when required-p
       (block-validation-fail "~A is missing" label))
     nil)
    ((and (integerp value) (not (minusp value))) value)
    ((stringp value)
     (handler-case
         (let ((quantity (if (json-hex-quantity-string-p value)
                             (hex-to-quantity value)
                             (parse-integer value :radix 10))))
           (if (and (integerp quantity) (not (minusp quantity)))
               quantity
               (block-validation-fail
                "~A must be a non-negative quantity" label)))
       (error ()
         (block-validation-fail "~A must be a non-negative quantity" label))))
    (t (block-validation-fail "~A must be a non-negative quantity" label))))

(defun parse-json-quantity-field (object name &key label required-p)
  (parse-json-quantity (if (listp name)
                           (json-object-field-any object name)
                           (json-object-field object name))
                       (or label name)
                       :required-p required-p))

(defun json-object-entries (object label)
  (when (json-empty-object-p object)
    (return-from json-object-entries '()))
  (unless (and (listp object) (every #'consp object))
    (block-validation-fail "~A must be an object" label))
  object)
