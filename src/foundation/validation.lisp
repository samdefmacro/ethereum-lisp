(in-package #:ethereum-lisp.validation)

(define-condition ethereum-lisp-error (error)
  ((message :initarg :message :reader ethereum-lisp-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (ethereum-lisp-error-message condition)))))

(define-condition data-decoding-error (ethereum-lisp-error) ())
(define-condition invalid-parameters-error (ethereum-lisp-error) ())
(define-condition consensus-validation-error (ethereum-lisp-error) ())
(define-condition configuration-error (ethereum-lisp-error) ())
(define-condition storage-error (ethereum-lisp-error) ())
(define-condition state-unavailable-error (ethereum-lisp-error) ())
(define-condition block-validation-error (ethereum-lisp-error) ())

(defun block-validation-error-message (condition)
  (ethereum-lisp-error-message condition))

(defun fail-with-condition (condition-type control arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun data-decoding-fail (control &rest arguments)
  (fail-with-condition 'data-decoding-error control arguments))

(defun invalid-parameters-fail (control &rest arguments)
  (fail-with-condition 'invalid-parameters-error control arguments))

(defun consensus-validation-fail (control &rest arguments)
  (fail-with-condition 'consensus-validation-error control arguments))

(defun configuration-fail (control &rest arguments)
  (fail-with-condition 'configuration-error control arguments))

(defun storage-fail (control &rest arguments)
  (fail-with-condition 'storage-error control arguments))

(defun state-unavailable-fail (control &rest arguments)
  (fail-with-condition 'state-unavailable-error control arguments))

(defun block-validation-fail (control &rest arguments)
  (fail-with-condition 'block-validation-error control arguments))

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

(defun rlp-uint-field (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "~A must be RLP bytes" label))
  (when (and (plusp (length value))
             (zerop (aref value 0)))
    (block-validation-fail "~A must be canonically encoded" label))
  (bytes-to-integer value))

(defun rlp-bytes-field (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "~A must be RLP bytes" label))
  (copy-seq value))

(defun rlp-list-field (value label)
  (unless (ethereum-lisp.rlp:rlp-list-p value)
    (block-validation-fail "~A must be an RLP list" label))
  (ethereum-lisp.rlp:rlp-list-items value))

(defun rlp-sized-bytes-field (value size label)
  (let ((bytes (rlp-bytes-field value label)))
    (unless (= (length bytes) size)
      (block-validation-fail "~A must be exactly ~D bytes" label size))
    bytes))

(defun rlp-hash32-field (value label)
  (ethereum-lisp.types:make-hash32
   (rlp-sized-bytes-field value 32 label)))

(defun rlp-address-field (value label)
  (ethereum-lisp.types:make-address
   (rlp-sized-bytes-field value 20 label)))

(defun validate-byte-sequence-field (value label &key size)
  (let ((bytes (handler-case
                   (ensure-byte-vector value)
                 (error ()
                   (block-validation-fail "~A must be a byte sequence"
                                          label)))))
    (when (and size (/= size (length bytes)))
      (block-validation-fail "~A must be exactly ~D bytes" label size))
    bytes))

(defun byte-vector-lexicographic< (left right)
  (let ((left (ensure-byte-vector left))
        (right (ensure-byte-vector right)))
    (loop for index below (min (length left) (length right))
          for left-byte = (aref left index)
          for right-byte = (aref right index)
          when (< left-byte right-byte)
            do (return t)
          when (> left-byte right-byte)
            do (return nil)
          finally (return (< (length left) (length right))))))

(defun uint32-value-p (value)
  (and (integerp value)
       (<= 0 value)
       (< value (expt 2 32))))

(defun uint64-value-p (value)
  (and (integerp value)
       (<= 0 value (1- (ash 1 64)))))
