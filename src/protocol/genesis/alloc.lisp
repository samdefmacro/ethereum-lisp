(in-package #:ethereum-lisp.genesis)

(defun parse-genesis-code (value label)
  (cond
    ((null value) (make-byte-vector 0))
    ((stringp value)
     (handler-case
         (hex-to-bytes value)
       (error ()
         (block-validation-fail "~A must be hex bytecode" label))))
    (t (block-validation-fail "~A must be hex bytecode" label))))

(defun parse-genesis-storage-hash32 (value label)
  (unless (stringp value)
    (block-validation-fail "~A must be hex storage data" label))
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (when (> (length bytes) 32)
          (block-validation-fail "~A must be at most 32 bytes" label))
        (let ((padded (make-byte-vector 32)))
          (replace padded bytes :start1 (- 32 (length bytes)))
          (make-hash32 padded)))
    (error ()
      (block-validation-fail "~A must be valid hex storage data" label))))

(defun parse-genesis-storage-slot (value label)
  (parse-genesis-storage-hash32 value label))

(defun parse-genesis-storage-value (value label)
  (cond
    ((stringp value)
     (bytes-to-integer
      (hash32-bytes (parse-genesis-storage-hash32 value label))))
    (t
     (let ((quantity (parse-json-quantity value label :required-p t)))
       (ensure-uint256 quantity label)))))

(defun parse-genesis-storage (object label)
  (when object
    (loop for (slot . value) in (json-object-entries object label)
          collect (cons (parse-genesis-storage-slot
                         slot (format nil "~A slot" label))
                        (parse-genesis-storage-value
                         value (format nil "~A value" label))))))

(defun genesis-account-from-entry (address-key account-object)
  (unless (and (listp account-object) (every #'consp account-object))
    (block-validation-fail "Genesis alloc account ~A must be an object"
                           address-key))
  (let ((label (format nil "Genesis alloc account ~A" address-key)))
    (make-genesis-account
     :address (parse-genesis-address address-key label)
     :balance (or (parse-genesis-uint256-field
                   account-object "balance"
                   (format nil "~A balance" label))
                  0)
     :nonce (or (parse-genesis-uint256-field
                 account-object "nonce"
                 (format nil "~A nonce" label))
                0)
     :code (parse-genesis-code
            (json-object-field account-object "code")
            (format nil "~A code" label))
     :storage (parse-genesis-storage
               (json-object-field account-object "storage")
               (format nil "~A storage" label)))))

(defun genesis-alloc-from-genesis-object (object)
  (let ((alloc-object (json-object-field object "alloc")))
    (when alloc-object
      (loop for (address-key . account-object)
              in (json-object-entries alloc-object "alloc")
            collect (genesis-account-from-entry address-key account-object)))))
