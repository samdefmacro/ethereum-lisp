(in-package #:ethereum-lisp.core)

(defun eth-rpc-pending-block-tag-p (value)
  (and (stringp value) (string= value "pending")))

(defun eth-rpc-head-block-tag-p (value)
  (and (stringp value)
       (or (string= value "latest")
           (string= value "pending")
           (string= value "safe")
           (string= value "finalized"))))

(defun eth-rpc-address-param (value method label)
  (handler-case
      (engine-rpc-address value label)
    (block-validation-error ()
      (block-validation-fail "~A ~A must be an address" method label))))

(defun eth-rpc-hash-param (params method label)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one ~A"
                           method label))
  (engine-rpc-hash32 (first params) label))

(defun eth-rpc-block-object-require-canonical-p (object method)
  (if (json-object-field-present-p object "requireCanonical")
      (let ((value (json-object-field object "requireCanonical")))
        (unless (or (eq value t) (eq value :true)
                    (eq value nil) (eq value :false))
          (block-validation-fail
           "~A requireCanonical must be a boolean"
           method))
        (or (eq value t) (eq value :true)))
      nil))

(defun eth-rpc-block-number-param (params store method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one block number"
                           method))
  (let ((value (first params)))
    (cond
      ((eth-rpc-head-block-tag-p value)
       (chain-store-block-tag-number store value))
      ((and (stringp value) (string= value "earliest")) 0)
      ((and (stringp value)
            (json-hex-quantity-string-p value))
       (parse-json-quantity value "block number" :required-p t))
      (t
       (block-validation-fail
        "~A block number must be latest, pending, safe, finalized, earliest, or a hex quantity"
        method)))))

(defun eth-rpc-block-object-param (object store method)
  (let ((hash-present-p (json-object-field-present-p object "blockHash"))
        (number-present-p (json-object-field-present-p object "blockNumber")))
    (when (or (and hash-present-p number-present-p)
              (and (not hash-present-p) (not number-present-p)))
      (block-validation-fail
       "~A block id object must contain exactly one of blockHash or blockNumber"
       method))
    (if hash-present-p
        (let* ((hash (eth-rpc-hash-param
                      (list (json-object-field object "blockHash"))
                      method
                      "block hash"))
               (block (chain-store-known-block store hash))
               (require-canonical-p
                 (eth-rpc-block-object-require-canonical-p object method)))
          (when (and block require-canonical-p
                     (not (engine-payload-store-canonical-block-p
                           (chain-store-require-memory-store store)
                           block)))
            (block-validation-fail
             "~A block hash is not canonical"
             method))
          block)
        (progn
          (when (json-object-field-present-p object "requireCanonical")
            (block-validation-fail
             "~A requireCanonical requires blockHash"
             method))
          (chain-store-block-by-number
           store
           (eth-rpc-block-number-param
            (list (json-object-field object "blockNumber"))
            store
            method))))))

(defun eth-rpc-block-param (params store method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one block id"
                           method))
  (let ((value (first params)))
    (cond
      ((json-object-p value)
       (eth-rpc-block-object-param value store method))
      ((and (stringp value)
            (= 66 (length value)))
       (chain-store-known-block
        store
        (eth-rpc-hash-param params method "block hash")))
      (t
       (chain-store-block-by-number
        store
        (eth-rpc-block-number-param params store method))))))

(defun eth-rpc-pending-block-id-param-p (params method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one block id"
                           method))
  (let ((value (first params)))
    (cond
      ((eth-rpc-pending-block-tag-p value) t)
      ((json-object-p value)
       (let ((hash-present-p (json-object-field-present-p value "blockHash"))
             (number-present-p
               (json-object-field-present-p value "blockNumber")))
         (when (or (and hash-present-p number-present-p)
                   (and (not hash-present-p) (not number-present-p)))
           (block-validation-fail
            "~A block id object must contain exactly one of blockHash or blockNumber"
            method))
         (when (and number-present-p
                    (json-object-field-present-p value "requireCanonical"))
           (block-validation-fail
            "~A requireCanonical requires blockHash"
            method))
         (and number-present-p
              (eth-rpc-pending-block-tag-p
               (json-object-field value "blockNumber")))))
      (t nil))))
