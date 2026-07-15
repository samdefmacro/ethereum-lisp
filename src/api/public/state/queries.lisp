(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-storage-slot-param-values (value method)
  (handler-case
      (let ((text value))
        (unless (stringp text)
          (block-validation-fail "~A storage key must be a hex string" method))
        (let ((hex (if (and (>= (length text) 2)
                            (char= (char text 0) #\0)
                            (member (char text 1) '(#\x #\X)))
                       (subseq text 2)
                       text)))
          (when (oddp (length hex))
            (setf hex (concatenate 'string "0" hex)))
          (when (> (length hex) 64)
            (block-validation-fail
             "~A storage key must be at most 32 bytes" method))
          (let* ((bytes (hex-to-bytes hex))
                 (padded (make-byte-vector 32)))
            (replace padded bytes :start1 (- 32 (length bytes)))
            (values (make-hash32 padded) (length bytes)))))
    (block-validation-error (condition)
      (error condition))
    (error ()
      (block-validation-fail "~A storage key must be hex bytes" method))))

(defun eth-rpc-storage-slot-param (value method)
  (nth-value 0 (eth-rpc-storage-slot-param-values value method)))

(defun eth-rpc-uint256-word-hex (value)
  (let* ((bytes (integer-to-minimal-bytes
                 (ensure-uint256 value "RPC storage value")))
         (word (make-byte-vector 32)))
    (replace word bytes :start1 (- 32 (length bytes)))
    (bytes-to-hex word)))

(defun eth-rpc-state-block-param (params store method)
  (let ((block (eth-rpc-block-param params store method)))
    (unless block
      (block-validation-fail "~A block is not available" method))
    (unless (chain-store-state-available-p store (block-hash block))
      (block-validation-fail "~A state is not available" method))
    block))

(defun engine-rpc-handle-eth-get-balance (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getBalance params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getBalance" "address"))
         (block (eth-rpc-state-block-param
                 (list (second params)) store "eth_getBalance")))
    (quantity-to-hex
     (chain-store-account-balance
      store (block-hash block) address))))

(defun eth-rpc-pending-account-nonce
    (store address state-nonce &key expected-chain-id)
  (engine-payload-store-pending-contiguous-nonce
   store
   address
   state-nonce
   :expected-chain-id expected-chain-id))

(defun engine-rpc-handle-eth-get-transaction-count (params store config)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getTransactionCount params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getTransactionCount" "address"))
         (block-id (second params))
         (block (eth-rpc-state-block-param
                 (list block-id) store "eth_getTransactionCount")))
    (let ((state-nonce
            (chain-store-account-nonce
             store (block-hash block) address)))
      (quantity-to-hex
       (if (and (stringp block-id) (string= block-id "pending"))
           (eth-rpc-pending-account-nonce
            store
            address
            state-nonce
            :expected-chain-id (chain-config-chain-id config))
           state-nonce)))))

(defun engine-rpc-handle-eth-get-code (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getCode params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getCode" "address"))
         (block (eth-rpc-state-block-param
                 (list (second params)) store "eth_getCode")))
    (bytes-to-hex
     (chain-store-account-code
      store (block-hash block) address))))

(defun engine-rpc-handle-eth-get-storage-at (params store)
  (unless (= 3 (length params))
    (block-validation-fail
     "eth_getStorageAt params must contain address, storage key, and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getStorageAt" "address"))
         (slot (eth-rpc-storage-slot-param
                (second params) "eth_getStorageAt"))
         (block (eth-rpc-state-block-param
                 (list (third params)) store "eth_getStorageAt")))
    (eth-rpc-uint256-word-hex
     (chain-store-account-storage
      store (block-hash block) address slot))))
