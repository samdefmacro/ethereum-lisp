(in-package #:ethereum-lisp.core)

;;;; Public JSON-RPC call object parsing and transaction synthesis.

(defun eth-rpc-call-object-optional-address (object name method)
  (when (genesis-object-field-present-p object name)
    (eth-rpc-address-param (genesis-object-field object name) method name)))

(defun eth-rpc-call-object-quantity-field (object name method &key default)
  (if (genesis-object-field-present-p object name)
      (parse-genesis-quantity
       (genesis-object-field object name)
       name
       :required-p t)
      default))

(defun eth-rpc-call-object-data (object method)
  (let* ((data-present-p (genesis-object-field-present-p object "data"))
         (input-present-p (genesis-object-field-present-p object "input"))
         (data (when data-present-p
                 (engine-rpc-bytes (genesis-object-field object "data")
                                   (format nil "~A data" method))))
         (input (when input-present-p
                  (engine-rpc-bytes (genesis-object-field object "input")
                                    (format nil "~A input" method)))))
    (or input data (make-byte-vector 0))))

(defun eth-rpc-call-object-access-list-storage-key (value method)
  (handler-case
      (engine-rpc-hash32 value "accessList storage key")
    (block-validation-error ()
      (block-validation-fail
       "~A accessList storage key must be a 32-byte hash"
       method))))

(defun eth-rpc-call-object-access-list-entry (entry method)
  (unless (json-object-p entry)
    (block-validation-fail "~A accessList entry must be an object" method))
  (unless (genesis-object-field-present-p entry "address")
    (block-validation-fail "~A accessList entry address is missing" method))
  (unless (genesis-object-field-present-p entry "storageKeys")
    (block-validation-fail "~A accessList entry storageKeys is missing" method))
  (let ((storage-keys (genesis-object-field entry "storageKeys")))
    (when (json-object-p storage-keys)
      (block-validation-fail
       "~A accessList storageKeys must be an array"
       method))
    (unless (json-array-p storage-keys)
      (block-validation-fail
       "~A accessList storageKeys must be an array"
       method))
    (make-access-list-entry
     :address
     (eth-rpc-address-param
      (genesis-object-field entry "address")
      method
      "accessList address")
     :storage-keys
     (mapcar
      (lambda (storage-key)
        (eth-rpc-call-object-access-list-storage-key storage-key method))
      (json-array-values storage-keys)))))

(defun eth-rpc-call-object-access-list (object method)
  (if (genesis-object-field-present-p object "accessList")
      (let ((access-list (genesis-object-field object "accessList")))
        (when (json-object-p access-list)
          (block-validation-fail
           "~A accessList must be an array"
           method))
        (unless (json-array-p access-list)
          (block-validation-fail
           "~A accessList must be an array"
           method))
        (values
         (mapcar
          (lambda (entry)
            (eth-rpc-call-object-access-list-entry entry method))
          (json-array-values access-list))
         t))
      (values '() nil)))

(defun eth-rpc-call-object-fees (object method)
  (let ((gas-price-present-p
          (genesis-object-field-present-p object "gasPrice"))
        (max-fee-present-p
          (genesis-object-field-present-p object "maxFeePerGas"))
        (max-priority-present-p
          (genesis-object-field-present-p object "maxPriorityFeePerGas")))
    (when (and gas-price-present-p
               (or max-fee-present-p max-priority-present-p))
      (block-validation-fail
       "~A cannot specify gasPrice with maxFeePerGas or maxPriorityFeePerGas"
       method))
    (if (or max-fee-present-p max-priority-present-p)
        (let ((max-fee
                (eth-rpc-call-object-quantity-field
                 object "maxFeePerGas" method :default 0))
              (max-priority
                (eth-rpc-call-object-quantity-field
                 object "maxPriorityFeePerGas" method :default 0)))
          (values :dynamic max-fee max-priority))
        (values :legacy
                (eth-rpc-call-object-quantity-field
                 object "gasPrice" method :default 0)
                0))))

(defun eth-rpc-call-object-chain-id (object method config)
  (let ((chain-id (if config (chain-config-chain-id config) 0)))
    (when (genesis-object-field-present-p object "chainId")
      (let ((supplied
              (eth-rpc-call-object-quantity-field
               object "chainId" method :default chain-id)))
        (unless (= supplied chain-id)
          (block-validation-fail
           "~A chainId does not match configured chain id"
           method))))
    chain-id))

(defun eth-rpc-call-object-transaction
    (object header method config &key gas-limit-override)
  (unless (json-object-p object)
    (block-validation-fail "~A call object must be a JSON object" method))
  (let* ((sender (or (eth-rpc-call-object-optional-address object "from" method)
                     (zero-address)))
         (recipient
           (eth-rpc-call-object-optional-address object "to" method))
         (gas-limit
           (or gas-limit-override
               (eth-rpc-call-object-quantity-field
                object "gas" method
                :default (eth-rpc-call-object-default-gas-limit
                          header method))))
         (value
           (eth-rpc-call-object-quantity-field
            object "value" method :default 0))
         (nonce
           (eth-rpc-call-object-quantity-field
            object "nonce" method :default 0))
         (data (eth-rpc-call-object-data object method))
         (chain-id (eth-rpc-call-object-chain-id object method config)))
    (multiple-value-bind (access-list access-list-present-p)
        (eth-rpc-call-object-access-list object method)
      (multiple-value-bind (fee-style max-fee max-priority-fee)
          (eth-rpc-call-object-fees object method)
        (values
         sender
         (case fee-style
           (:dynamic
            (make-dynamic-fee-transaction
             :chain-id chain-id
             :nonce nonce
             :max-fee-per-gas max-fee
             :max-priority-fee-per-gas max-priority-fee
             :gas-limit gas-limit
             :to recipient
             :value value
             :data data
             :access-list access-list))
           (otherwise
            (if access-list-present-p
                (make-access-list-transaction
                 :chain-id chain-id
                 :nonce nonce
                 :gas-price max-fee
                 :gas-limit gas-limit
                 :to recipient
                 :value value
                 :data data
                 :access-list access-list)
                (make-legacy-transaction :nonce nonce
                                         :gas-price max-fee
                                         :gas-limit gas-limit
                                         :to recipient
                                         :value value
                                         :data data)))))))))
