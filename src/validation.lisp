(in-package #:ethereum-lisp.validation)

(define-condition block-validation-error (error)
  ((message :initarg :message :reader block-validation-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (block-validation-error-message condition)))))

(defun block-validation-fail (control &rest arguments)
  (error 'block-validation-error
         :message (apply #'format nil control arguments)))

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
