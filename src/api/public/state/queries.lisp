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
  (unless (<= 1 (length params) 2)
    (block-validation-fail
     "eth_getBalance params must contain address and optional block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getBalance" "address"))
         (block (eth-rpc-state-block-param
                 (list (if (= 2 (length params))
                           (second params)
                           "latest"))
                 store "eth_getBalance")))
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
  (unless (<= 1 (length params) 2)
    (block-validation-fail
     "eth_getTransactionCount params must contain address and optional block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getTransactionCount" "address"))
         (block-id (if (= 2 (length params)) (second params) "latest"))
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
  (unless (<= 1 (length params) 2)
    (block-validation-fail
     "eth_getCode params must contain address and optional block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getCode" "address"))
         (block (eth-rpc-state-block-param
                 (list (if (= 2 (length params))
                           (second params)
                           "latest"))
                 store "eth_getCode")))
    (bytes-to-hex
     (chain-store-account-code
      store (block-hash block) address))))

(defun engine-rpc-handle-eth-get-storage-at (params store)
  (unless (<= 2 (length params) 3)
    (block-validation-fail
     "eth_getStorageAt params must contain address, storage key, and optional block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getStorageAt" "address"))
         (slot (eth-rpc-storage-slot-param
                (second params) "eth_getStorageAt"))
         (block (eth-rpc-state-block-param
                 (list (if (= 3 (length params))
                           (third params)
                           "latest"))
                 store "eth_getStorageAt")))
    (eth-rpc-uint256-word-hex
     (chain-store-account-storage
      store (block-hash block) address slot))))

(defconstant +eth-rpc-get-storage-values-max-slots+ 1024)

(defun engine-rpc-handle-eth-get-storage-values (params store)
  "Return several storage words for several accounts in one state lookup.

The request and response shapes follow geth's eth_getStorageValues extension:
an address-keyed object whose values are equally ordered arrays of bytes32
words.  The optional block selector defaults to latest."
  (unless (<= 1 (length params) 2)
    (block-validation-fail
     "eth_getStorageValues params must contain requests and optional block id"))
  (let ((requests (first params)))
    (unless (json-object-p requests)
      (block-validation-fail
       "eth_getStorageValues requests must be an object"))
    (let ((parsed-requests '())
          (total-slots 0))
      ;; Parse every address and slot before touching state, matching geth's
      ;; fail-closed handling of malformed request maps.
      (dolist (entry (json-object-entries
                      requests "eth_getStorageValues requests"))
        (let* ((address
                 (eth-rpc-address-param
                  (car entry) "eth_getStorageValues" "request address"))
               (slot-values (cdr entry)))
          (unless (json-array-p slot-values)
            (block-validation-fail
             "eth_getStorageValues storage keys must be an array"))
          (let ((slots
                  (loop for slot in (json-array-values slot-values)
                        collect
                        (json-rpc-hash32
                         slot "eth_getStorageValues storage key"))))
            (incf total-slots (length slots))
            (when (> total-slots +eth-rpc-get-storage-values-max-slots+)
              (block-validation-fail
               "eth_getStorageValues requests too many slots (max 1024)"))
            (push (cons address slots) parsed-requests))))
      (when (zerop total-slots)
        (block-validation-fail "eth_getStorageValues empty request"))
      (let* ((block-id (if (= 2 (length params))
                           (second params)
                           "latest"))
             (block (eth-rpc-state-block-param
                     (list block-id) store "eth_getStorageValues"))
             (block-hash (block-hash block)))
        (loop for (address . slots) in (nreverse parsed-requests)
              collect
              (cons
               (address-to-hex address)
               (eth-rpc-json-array
                (loop for slot in slots
                      collect
                      (eth-rpc-uint256-word-hex
                       (chain-store-account-storage
                        store block-hash address slot))))))))))
