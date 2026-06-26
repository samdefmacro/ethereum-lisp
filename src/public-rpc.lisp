(in-package #:ethereum-lisp.core)

(defconstant +eth-rpc-default-call-gas-limit+ (1- (ash 1 64)))

(defun eth-rpc-call-object-default-gas-limit (header method)
  (if (or (string= method "eth_call")
          (string= method "eth_createAccessList"))
      +eth-rpc-default-call-gas-limit+
      (or (and header (block-header-gas-limit header))
          +genesis-gas-limit+)))

(defun engine-rpc-handle-web3-client-version (params)
  (when params
    (block-validation-fail "web3_clientVersion params must be empty"))
  (let ((version (engine-rpc-client-version)))
    (format nil "~A/~A/~A/~A"
            (engine-rpc-required-field version "name")
            (engine-rpc-required-field version "version")
            (engine-rpc-required-field version "code")
            (engine-rpc-required-field version "commit"))))

(defun engine-rpc-handle-web3-sha3 (params)
  (unless (= 1 (length params))
    (block-validation-fail "web3_sha3 params must contain exactly one data value"))
  (bytes-to-hex (keccak-256 (engine-rpc-bytes (first params) "web3_sha3 data"))))

(defun engine-rpc-handle-net-version (params config)
  (when params
    (block-validation-fail "net_version params must be empty"))
  (write-to-string (chain-config-chain-id config) :base 10))

(defun engine-rpc-handle-net-listening (params)
  (when params
    (block-validation-fail "net_listening params must be empty"))
  :false)

(defun engine-rpc-handle-net-peer-count (params)
  (when params
    (block-validation-fail "net_peerCount params must be empty"))
  (quantity-to-hex 0))

(defun engine-rpc-handle-eth-chain-id (params config)
  (when params
    (block-validation-fail "eth_chainId params must be empty"))
  (quantity-to-hex (chain-config-chain-id config)))

(defun engine-rpc-handle-eth-block-number (params store)
  (when params
    (block-validation-fail "eth_blockNumber params must be empty"))
  (quantity-to-hex (chain-store-head-number store)))

(defun engine-rpc-handle-eth-protocol-version (params)
  (when params
    (block-validation-fail "eth_protocolVersion params must be empty"))
  (quantity-to-hex +eth-protocol-version+))

(defun engine-rpc-handle-eth-syncing (params)
  (when params
    (block-validation-fail "eth_syncing params must be empty"))
  :false)

(defun engine-rpc-handle-eth-accounts (params)
  (when params
    (block-validation-fail "eth_accounts params must be empty"))
  (make-array 0))

(defun engine-rpc-handle-eth-coinbase (params)
  (when params
    (block-validation-fail "eth_coinbase params must be empty"))
  (address-to-hex (zero-address)))

(defun engine-rpc-handle-eth-mining (params)
  (when params
    (block-validation-fail "eth_mining params must be empty"))
  :false)

(defun engine-rpc-handle-eth-hashrate (params)
  (when params
    (block-validation-fail "eth_hashrate params must be empty"))
  (quantity-to-hex 0))

(defun engine-rpc-suggest-gas-tip-cap (store)
  (declare (ignore store))
  0)

(defun engine-rpc-handle-eth-max-priority-fee-per-gas (params store)
  (when params
    (block-validation-fail "eth_maxPriorityFeePerGas params must be empty"))
  (quantity-to-hex (engine-rpc-suggest-gas-tip-cap store)))

(defun engine-rpc-handle-eth-gas-price (params store)
  (when params
    (block-validation-fail "eth_gasPrice params must be empty"))
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head)))
         (base-fee (if header
                       (or (block-header-base-fee-per-gas header) 0)
                       0)))
    (quantity-to-hex (+ base-fee
                        (engine-rpc-suggest-gas-tip-cap store)))))

(defun engine-payload-store-head-block (store)
  (chain-store-block-by-number
   store
   (engine-payload-store-head-number store)))

(defun engine-rpc-handle-eth-base-fee (params store config)
  (when params
    (block-validation-fail "eth_baseFee params must be empty"))
  (let ((head (chain-store-latest-block store)))
    (when (and head
               (chain-config-london-p
                config
                (1+ (block-header-number (block-header head)))))
      (quantity-to-hex
       (expected-base-fee-per-gas
        (block-header head)
        :london-parent-p
        (not (null (block-header-base-fee-per-gas (block-header head)))))))))

(defun engine-rpc-handle-eth-blob-base-fee (params store config)
  (when params
    (block-validation-fail "eth_blobBaseFee params must be empty"))
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (when (and header (block-header-excess-blob-gas header))
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (chain-config-blob-schedule
           config
           (block-header-number header)
           (block-header-timestamp header))
        (declare (ignore target-blob-gas max-blob-gas))
        (quantity-to-hex
         (block-header-blob-base-fee
          header :update-fraction update-fraction))))))

(defconstant +eth-rpc-max-fee-history-block-count+ 1024)
(defconstant +eth-rpc-max-fee-history-reward-percentiles+ 100)

(defun eth-rpc-head-block-tag-p (value)
  (and (stringp value)
       (or (string= value "latest")
           (string= value "pending")
           (string= value "safe")
           (string= value "finalized"))))

(defun eth-rpc-fee-history-block-count (params method)
  (let ((count (parse-genesis-quantity
                (engine-rpc-required-param params 0 "block count" method)
                "fee history block count"
                :required-p t)))
    (when (< count 1)
      (block-validation-fail
       "~A block count must be greater than zero" method))
    (min count +eth-rpc-max-fee-history-block-count+)))

(defun eth-rpc-fee-history-newest-block-number (params store method)
  (let ((value (engine-rpc-required-param params 1 "newest block" method)))
    (cond
      ((eth-rpc-head-block-tag-p value)
       (chain-store-block-tag-number store value))
      ((and (stringp value) (string= value "earliest")) 0)
      ((and (stringp value) (genesis-hex-quantity-string-p value))
       (parse-genesis-quantity value "newest block" :required-p t))
      (t
       (block-validation-fail
        "~A newest block must be latest, pending, safe, finalized, earliest, or a hex quantity"
        method)))))

(defun eth-rpc-fee-history-reward-percentiles (params method)
  (let ((percentiles (engine-rpc-required-param
                      params 2 "reward percentiles" method)))
    (unless (listp percentiles)
      (block-validation-fail
       "~A reward percentiles must be an array" method))
    (when (> (length percentiles)
             +eth-rpc-max-fee-history-reward-percentiles+)
      (block-validation-fail
       "~A reward percentiles exceed the query limit" method))
    (loop with previous = nil
          for percentile in percentiles
          do (progn
               (unless (realp percentile)
                 (block-validation-fail
                  "~A reward percentiles must be numbers" method))
               (unless (<= 0 percentile 100)
                 (block-validation-fail
                  "~A reward percentiles must be between 0 and 100" method))
               (when (and previous (<= percentile previous))
                 (block-validation-fail
                  "~A reward percentiles must be strictly increasing" method))
               (setf previous percentile))
          collect percentile)))

(defun eth-rpc-fee-history-blocks (store newest-number block-count method)
  (let* ((effective-count (min block-count (1+ newest-number)))
         (oldest-number (- newest-number effective-count -1))
         (blocks '()))
    (loop for number from oldest-number to newest-number
          for block = (chain-store-block-by-number store number)
          do (unless block
               (block-validation-fail
                "~A requested block is not available" method))
             (push block blocks))
    (values oldest-number (nreverse blocks))))

(defun eth-rpc-fee-history-gas-used-ratio (header)
  (if (plusp (block-header-gas-limit header))
      (/ (block-header-gas-used header)
         (block-header-gas-limit header))
      0))

(defun eth-rpc-fee-history-base-fee (header)
  (quantity-to-hex (or (block-header-base-fee-per-gas header) 0)))

(defun eth-rpc-fee-history-next-base-fee (header config)
  (quantity-to-hex
   (if (chain-config-london-p config (1+ (block-header-number header)))
       (expected-base-fee-per-gas
        header
        :london-parent-p
        (not (null (block-header-base-fee-per-gas header))))
       (or (block-header-base-fee-per-gas header) 0))))

(defun eth-rpc-fee-history-blob-enabled-p (blocks)
  (some (lambda (block)
          (let ((header (block-header block)))
            (or (block-header-blob-gas-used header)
                (block-header-excess-blob-gas header))))
        blocks))

(defun eth-rpc-fee-history-blob-schedule (header config)
  (chain-config-blob-schedule
   config
   (block-header-number header)
   (block-header-timestamp header)))

(defun eth-rpc-fee-history-blob-base-fee (header config)
  (if (block-header-excess-blob-gas header)
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (eth-rpc-fee-history-blob-schedule header config)
        (declare (ignore target-blob-gas max-blob-gas))
        (quantity-to-hex
         (block-header-blob-base-fee
          header :update-fraction update-fraction)))
      (quantity-to-hex 0)))

(defun eth-rpc-fee-history-next-blob-base-fee (header config)
  (if (block-header-excess-blob-gas header)
      (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
          (eth-rpc-fee-history-blob-schedule header config)
        (quantity-to-hex
         (blob-base-fee
          (expected-excess-blob-gas
           header
           :target-blob-gas target-blob-gas
           :max-blob-gas max-blob-gas
           :update-fraction update-fraction)
          :update-fraction update-fraction)))
      (quantity-to-hex 0)))

(defun eth-rpc-fee-history-blob-gas-used-ratio (header config)
  (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
      (eth-rpc-fee-history-blob-schedule header config)
    (declare (ignore target-blob-gas update-fraction))
    (if (plusp max-blob-gas)
        (/ (or (block-header-blob-gas-used header) 0) max-blob-gas)
        0)))

(defun eth-rpc-fee-history-zero-reward (percentiles)
  (loop repeat (length percentiles)
        collect (quantity-to-hex 0)))

(defun engine-rpc-handle-eth-fee-history (params store config)
  (let* ((method "eth_feeHistory")
         (block-count
           (progn
             (unless (= 3 (length params))
               (block-validation-fail
                "~A params must contain block count, newest block, and reward percentiles"
                method))
             (eth-rpc-fee-history-block-count params method)))
         (newest-number
           (eth-rpc-fee-history-newest-block-number params store method))
         (percentiles (eth-rpc-fee-history-reward-percentiles params method)))
    (multiple-value-bind (oldest-number blocks)
        (eth-rpc-fee-history-blocks store newest-number block-count method)
      (let* ((headers (mapcar #'block-header blocks))
             (newest-header (car (last headers)))
             (object
               (list
                (cons "oldestBlock" (quantity-to-hex oldest-number))
                (cons "baseFeePerGas"
                      (append
                       (mapcar #'eth-rpc-fee-history-base-fee headers)
                       (list
                        (eth-rpc-fee-history-next-base-fee
                         newest-header config))))
                (cons "gasUsedRatio"
                      (mapcar #'eth-rpc-fee-history-gas-used-ratio
                              headers)))))
        (when percentiles
          (setf object
                (append object
                        (list
                         (cons "reward"
                               (loop repeat (length blocks)
                                     collect
                                     (eth-rpc-fee-history-zero-reward
                                      percentiles)))))))
        (when (eth-rpc-fee-history-blob-enabled-p blocks)
          (setf object
                (append
                 object
                 (list
                  (cons "baseFeePerBlobGas"
                        (append
                         (mapcar
                          (lambda (header)
                            (eth-rpc-fee-history-blob-base-fee
                             header config))
                          headers)
                         (list
                          (eth-rpc-fee-history-next-blob-base-fee
                           newest-header config))))
                  (cons "blobGasUsedRatio"
                        (mapcar
                         (lambda (header)
                           (eth-rpc-fee-history-blob-gas-used-ratio
                            header config))
                         headers))))))
        object))))

(defun eth-rpc-address-param (value method label)
  (handler-case
      (engine-rpc-address value label)
    (block-validation-error ()
      (block-validation-fail "~A ~A must be an address" method label))))

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
            (genesis-hex-quantity-string-p value))
       (parse-genesis-quantity value "block number" :required-p t))
      (t
       (block-validation-fail
        "~A block number must be latest, pending, safe, finalized, earliest, or a hex quantity"
        method)))))

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

(defun eth-rpc-block-object-require-canonical-p (object method)
  (if (genesis-object-field-present-p object "requireCanonical")
      (let ((value (genesis-object-field object "requireCanonical")))
        (unless (or (eq value t) (eq value :true)
                    (eq value nil) (eq value :false))
          (block-validation-fail
           "~A requireCanonical must be a boolean"
           method))
        (or (eq value t) (eq value :true)))
      nil))

(defun eth-rpc-block-object-param (object store method)
  (let ((hash-present-p (genesis-object-field-present-p object "blockHash"))
        (number-present-p (genesis-object-field-present-p object "blockNumber")))
    (when (or (and hash-present-p number-present-p)
              (and (not hash-present-p) (not number-present-p)))
      (block-validation-fail
       "~A block id object must contain exactly one of blockHash or blockNumber"
       method))
    (if hash-present-p
        (let* ((hash (eth-rpc-hash-param
                      (list (genesis-object-field object "blockHash"))
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
          (when (genesis-object-field-present-p object "requireCanonical")
            (block-validation-fail
             "~A requireCanonical requires blockHash"
             method))
          (chain-store-block-by-number
           store
           (eth-rpc-block-number-param
            (list (genesis-object-field object "blockNumber"))
            store
            method))))))

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

(defun eth-rpc-pending-account-nonce (store address state-nonce)
  (engine-payload-store-pending-contiguous-nonce
   store
   address
   state-nonce))

(defun engine-rpc-handle-eth-get-transaction-count (params store)
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
           (eth-rpc-pending-account-nonce store address state-nonce)
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

(defconstant +eth-get-proof-max-storage-keys+ 1024)

(defstruct (eth-rpc-proof-storage-slot
            (:constructor make-eth-rpc-proof-storage-slot
                (&key slot output-key)))
  slot
  output-key)

(defun eth-rpc-proof-storage-slot-param (value method)
  (multiple-value-bind (slot input-length)
      (eth-rpc-storage-slot-param-values value method)
    (make-eth-rpc-proof-storage-slot
     :slot slot
     :output-key
     (if (= input-length 32)
         (hash32-to-hex slot)
         (quantity-to-hex (bytes-to-integer (hash32-bytes slot)))))))

(defun eth-rpc-state-db-from-chain-store (store block-hash)
  (ethereum-lisp.execution:chain-store-state-db store block-hash))

(defun eth-rpc-proof-node-hex-list (proof)
  (mapcar #'bytes-to-hex proof))

(defun eth-rpc-storage-proof-object-from-state-proof (proof proof-slot)
  (list (cons "key" (eth-rpc-proof-storage-slot-output-key proof-slot))
        (cons "value"
              (quantity-to-hex
               (ethereum-lisp.state:state-storage-proof-value proof)))
        (cons "proof"
              (eth-rpc-proof-node-hex-list
               (ethereum-lisp.state:state-storage-proof-proof proof)))))

(defun eth-rpc-proof-storage-slots-param (value method)
  (unless (listp value)
    (block-validation-fail "~A storage keys must be a list" method))
  (when (> (length value) +eth-get-proof-max-storage-keys+)
    (block-validation-fail
     "~A storage keys must contain at most ~D entries"
     method +eth-get-proof-max-storage-keys+))
  (mapcar (lambda (slot)
            (eth-rpc-proof-storage-slot-param slot method))
          value))

(defun eth-rpc-build-proof-object (store block-hash address slots)
  (let* ((state (eth-rpc-state-db-from-chain-store store block-hash))
         (proof
           (ethereum-lisp.state:state-db-get-proof
            state
            address
            (mapcar #'eth-rpc-proof-storage-slot-slot slots))))
    (list
     (cons "address" (address-to-hex address))
     (cons "accountProof"
           (eth-rpc-proof-node-hex-list
            (ethereum-lisp.state:state-proof-result-account-proof proof)))
     (cons "balance"
           (quantity-to-hex
            (ethereum-lisp.state:state-proof-result-balance proof)))
     (cons "codeHash"
           (hash32-to-hex
            (ethereum-lisp.state:state-proof-result-code-hash proof)))
     (cons "nonce"
           (quantity-to-hex
            (ethereum-lisp.state:state-proof-result-nonce proof)))
     (cons "storageHash"
           (hash32-to-hex
            (ethereum-lisp.state:state-proof-result-storage-root proof)))
     (cons "storageProof"
           (loop for storage-proof in
                 (ethereum-lisp.state:state-proof-result-storage-proofs proof)
                 for slot in slots
                 collect
                 (eth-rpc-storage-proof-object-from-state-proof
                  storage-proof
                  slot))))))

(defun engine-rpc-handle-eth-get-proof (params store)
  (unless (= 3 (length params))
    (block-validation-fail
     "eth_getProof params must contain address, storage keys, and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getProof" "address"))
         (slots (eth-rpc-proof-storage-slots-param
                 (second params) "eth_getProof"))
         (block (eth-rpc-state-block-param
                 (list (third params)) store "eth_getProof")))
    (eth-rpc-build-proof-object store (block-hash block) address slots)))

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
    (unless (listp storage-keys)
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
      storage-keys))))

(defun eth-rpc-call-object-access-list (object method)
  (if (genesis-object-field-present-p object "accessList")
      (let ((access-list (genesis-object-field object "accessList")))
        (when (json-object-p access-list)
          (block-validation-fail
           "~A accessList must be an array"
           method))
        (unless (listp access-list)
          (block-validation-fail
           "~A accessList must be an array"
           method))
        (values
         (mapcar
          (lambda (entry)
            (eth-rpc-call-object-access-list-entry entry method))
          access-list)
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

(defun eth-rpc-simulate-call-object
    (object block store config method &key gas-limit)
  (multiple-value-bind (sender tx)
      (eth-rpc-call-object-transaction
       object (block-header block) method config
       :gas-limit-override gas-limit)
    (handler-case
        (ethereum-lisp.execution:execute-message-call
         (ethereum-lisp.execution:chain-store-state-db
          store (block-hash block))
         sender
         tx
         :base-fee (or (block-header-base-fee-per-gas
                        (block-header block))
                       0)
         :chain-id (if config (chain-config-chain-id config) 0)
         :chain-config config
         :coinbase (or (block-header-beneficiary (block-header block))
                       (zero-address))
         :timestamp (block-header-timestamp (block-header block))
         :block-number (block-header-number (block-header block))
         :prev-randao (or (block-header-mix-hash (block-header block))
                          (zero-hash32))
         :difficulty (block-header-difficulty (block-header block))
         :random-p t
         :context-gas-limit (block-header-gas-limit (block-header block)))
      (ethereum-lisp.state:transaction-validation-error ()
        (block-validation-fail
         "~A transaction is invalid" method)))))

(defun engine-rpc-handle-eth-call (params store config)
  (unless (or (= 1 (length params)) (= 2 (length params)))
    (block-validation-fail
     "eth_call params must contain call object and optional block id"))
  (let* ((block (eth-rpc-state-block-param
                 (list (if (= 2 (length params)) (second params) "latest"))
                 store
                 "eth_call")))
    (multiple-value-bind (status return-data gas-used)
        (eth-rpc-simulate-call-object
         (first params) block store config "eth_call")
      (declare (ignore gas-used))
      (unless (or (eth-rpc-call-status-success-p status)
                  (eq status :reverted))
        (block-validation-fail "eth_call execution failed"))
      (bytes-to-hex return-data))))

(defun eth-rpc-call-status-success-p (status)
  (member status '(:stopped :returned :selfdestructed :successful)))

(defun eth-rpc-call-object-gas-cap (object header method)
  (unless (json-object-p object)
    (block-validation-fail "~A call object must be a JSON object" method))
  (let* ((block-limit (or (and header (block-header-gas-limit header))
                          +genesis-gas-limit+))
         (requested
           (eth-rpc-call-object-quantity-field
            object "gas" method :default block-limit)))
    (min requested block-limit)))

(defun eth-rpc-estimate-gas-success-p
    (object block store config gas-limit)
  (multiple-value-bind (status return-data gas-used)
      (eth-rpc-simulate-call-object
       object block store config "eth_estimateGas" :gas-limit gas-limit)
    (declare (ignore return-data gas-used))
    (eth-rpc-call-status-success-p status)))

(defun eth-rpc-call-intrinsic-gas (tx header config)
  (let ((rules (and config
                    header
                    (chain-config-rules config
                                        (block-header-number header)
                                        (block-header-timestamp header)))))
    (ethereum-lisp.state:transaction-intrinsic-gas
     tx
     :eip3860-p (or (null rules) (chain-rules-shanghai-p rules)))))

(defun engine-rpc-handle-eth-estimate-gas (params store config)
  (unless (or (= 1 (length params)) (= 2 (length params)))
    (block-validation-fail
     "eth_estimateGas params must contain call object and optional block id"))
  (let* ((object (first params))
         (block (eth-rpc-state-block-param
                 (list (if (= 2 (length params)) (second params) "latest"))
                 store
                 "eth_estimateGas")))
    (multiple-value-bind (sender tx)
        (eth-rpc-call-object-transaction
         object (block-header block) "eth_estimateGas" config)
      (declare (ignore sender))
      (let* ((intrinsic-gas
               (eth-rpc-call-intrinsic-gas
                tx (block-header block) config))
             (high
               (eth-rpc-call-object-gas-cap
                object (block-header block) "eth_estimateGas")))
        (when (> intrinsic-gas high)
          (block-validation-fail
           "eth_estimateGas intrinsic gas exceeds gas cap"))
        (unless (eth-rpc-estimate-gas-success-p
                 object block store config high)
          (block-validation-fail
           "eth_estimateGas execution reverted or exceeded gas cap"))
        (loop with low = intrinsic-gas
              while (< low high)
              for mid = (floor (+ low high) 2)
              do (if (eth-rpc-estimate-gas-success-p
                      object block store config mid)
                     (setf high mid)
                     (setf low (1+ mid)))
              finally (return (quantity-to-hex low)))))))

(defun eth-rpc-precompile-access-key-p (key)
  (loop for index from 1 to 10
        thereis (bytes= key (address-bytes
                             (ethereum-lisp.evm:precompile-address index)))))

(defun eth-rpc-implicit-access-key-p (key sender recipient coinbase)
  (or (and sender (bytes= key (address-bytes sender)))
      (and recipient (bytes= key (address-bytes recipient)))
      (and coinbase (bytes= key (address-bytes coinbase)))
      (eth-rpc-precompile-access-key-p key)))

(defun eth-rpc-access-list-groups (accessed-addresses accessed-storage)
  (let ((groups (make-hash-table :test 'equal)))
    (labels ((ensure-group (address-hex)
               (or (gethash address-hex groups)
                   (setf (gethash address-hex groups)
                         (make-hash-table :test 'equal)))))
      (maphash
       (lambda (key value)
         (declare (ignore value))
         (when (= (length key) 52)
           (let* ((address (make-address (subseq key 0 20)))
                  (slot (make-hash32 (subseq key 20 52)))
                  (slots (ensure-group (address-to-hex address))))
             (setf (gethash (hash32-to-hex slot) slots) t))))
       accessed-storage)
      (maphash
       (lambda (key value)
         (declare (ignore value))
         (when (= (length key) 20)
           (ensure-group (address-to-hex (make-address key)))))
       accessed-addresses))
    groups))

(defun eth-rpc-created-access-list-object
    (accessed-addresses accessed-storage sender recipient coinbase)
  (let ((groups (eth-rpc-access-list-groups
                 accessed-addresses accessed-storage)))
    (loop for address-hex being the hash-keys of groups
          using (hash-value slots)
          unless (and (zerop (hash-table-count slots))
                      (eth-rpc-implicit-access-key-p
                       (hex-to-bytes address-hex) sender recipient coinbase))
            collect
            (list
             (cons "address" address-hex)
             (cons "storageKeys"
                   (sort
                    (loop for slot being the hash-keys of slots collect slot)
                    #'string<)))
              into entries
          finally
             (return
               (sort entries
                     #'string<
                     :key (lambda (entry)
                            (cdr (assoc "address" entry :test #'string=))))))))

(defun engine-rpc-handle-eth-create-access-list (params store config)
  (unless (or (= 1 (length params)) (= 2 (length params)))
    (block-validation-fail
     "eth_createAccessList params must contain call object and optional block id"))
  (let* ((object (first params))
         (block (eth-rpc-state-block-param
                 (list (if (= 2 (length params)) (second params) "latest"))
                 store
                 "eth_createAccessList")))
    (multiple-value-bind (sender tx)
        (eth-rpc-call-object-transaction
         object (block-header block) "eth_createAccessList" config)
      (multiple-value-bind
            (status return-data gas-used accessed-addresses accessed-storage)
          (eth-rpc-simulate-call-object
           object block store config "eth_createAccessList")
        (declare (ignore return-data))
        (unless (eth-rpc-call-status-success-p status)
          (block-validation-fail
           "eth_createAccessList execution reverted or exceeded gas cap"))
        (list
         (cons "accessList"
               (eth-rpc-created-access-list-object
                accessed-addresses
                accessed-storage
                sender
                (transaction-to tx)
                (or (block-header-beneficiary (block-header block))
                    (zero-address))))
         (cons "gasUsed" (quantity-to-hex gas-used)))))))

(defun eth-rpc-header-object (header)
  (unless (block-header-p header)
    (block-validation-fail "eth header result must be a block header"))
  (append
   (list
    (cons "number" (quantity-to-hex (block-header-number header)))
    (cons "hash" (hash32-to-hex (block-header-hash header)))
    (cons "parentHash"
          (hash32-to-hex (or (block-header-parent-hash header)
                             (zero-hash32))))
    (cons "nonce"
          (bytes-to-hex (or (block-header-nonce header)
                            (make-byte-vector 8))))
    (cons "mixHash"
          (hash32-to-hex (or (block-header-mix-hash header)
                             (zero-hash32))))
    (cons "sha3Uncles"
          (hash32-to-hex (or (block-header-ommers-hash header)
                             +empty-ommers-hash+)))
    (cons "logsBloom"
          (bytes-to-hex (or (block-header-logs-bloom header)
                            (make-byte-vector 256))))
    (cons "stateRoot"
          (hash32-to-hex (or (block-header-state-root header)
                             +empty-trie-hash+)))
    (cons "miner"
          (address-to-hex (or (block-header-beneficiary header)
                              (zero-address))))
    (cons "difficulty" (quantity-to-hex (block-header-difficulty header)))
    (cons "extraData" (bytes-to-hex (block-header-extra-data header)))
    (cons "gasLimit" (quantity-to-hex (block-header-gas-limit header)))
    (cons "gasUsed" (quantity-to-hex (block-header-gas-used header)))
    (cons "timestamp" (quantity-to-hex (block-header-timestamp header)))
    (cons "transactionsRoot"
          (hash32-to-hex (or (block-header-transactions-root header)
                             +empty-trie-hash+)))
    (cons "receiptsRoot"
          (hash32-to-hex (or (block-header-receipts-root header)
                             +empty-trie-hash+))))
   (when (block-header-base-fee-per-gas header)
     (list (cons "baseFeePerGas"
                 (quantity-to-hex
                  (block-header-base-fee-per-gas header)))))
   (when (block-header-withdrawals-root header)
     (list (cons "withdrawalsRoot"
                 (hash32-to-hex
                  (block-header-withdrawals-root header)))))
   (when (block-header-blob-gas-used header)
     (list (cons "blobGasUsed"
                 (quantity-to-hex (block-header-blob-gas-used header)))))
   (when (block-header-excess-blob-gas header)
     (list (cons "excessBlobGas"
                 (quantity-to-hex
                  (block-header-excess-blob-gas header)))))
   (when (block-header-parent-beacon-root header)
     (list (cons "parentBeaconBlockRoot"
                 (hash32-to-hex
                  (block-header-parent-beacon-root header)))))
   (when (block-header-requests-hash header)
     (list (cons "requestsHash"
                 (hash32-to-hex (block-header-requests-hash header)))))
   (when (block-header-block-access-list-hash header)
     (list (cons "balHash"
                 (hash32-to-hex
                  (block-header-block-access-list-hash header)))))
   (when (block-header-slot-number header)
     (list (cons "slotNumber"
                 (quantity-to-hex (block-header-slot-number header)))))))

(defun engine-rpc-handle-eth-get-header-by-number (params store)
  (let* ((number (eth-rpc-block-number-param
                  params store "eth_getHeaderByNumber"))
         (block (chain-store-block-by-number store number)))
    (when block
      (eth-rpc-header-object (block-header block)))))

(defun eth-rpc-hash-param (params method label)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one ~A"
                           method label))
  (engine-rpc-hash32 (first params) label))

(defun engine-rpc-handle-eth-get-header-by-hash (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getHeaderByHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (when block
      (eth-rpc-header-object (block-header block)))))

(defun eth-rpc-rlp-length-prefix (offset length)
  (if (<= length 55)
      (ensure-byte-vector (list (+ offset length)))
      (let ((length-bytes (integer-to-minimal-bytes length)))
        (concat-bytes
         (ensure-byte-vector (list (+ offset 55 (length length-bytes))))
         length-bytes))))

(defun eth-rpc-encoded-rlp-list (encoded-items)
  (let ((payload (if encoded-items
                     (apply #'concat-bytes encoded-items)
                     (make-byte-vector 0))))
    (concat-bytes (eth-rpc-rlp-length-prefix #xc0 (length payload))
                  payload)))

(defun eth-rpc-block-rlp (block)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  (let ((items
          (list
           (block-header-rlp (block-header block))
           (eth-rpc-encoded-rlp-list
            (mapcar #'transaction-encoding (block-transactions block)))
           (eth-rpc-encoded-rlp-list
            (mapcar #'block-header-rlp (block-ommers block))))))
    (when (block-withdrawals-present-p block)
      (setf items
            (append items
                    (list (eth-rpc-encoded-rlp-list
                           (mapcar #'withdrawal-rlp
                                   (block-withdrawals block)))))))
    (when (block-requests-present-p block)
      (setf items
            (append items
                    (list (eth-rpc-encoded-rlp-list
                           (mapcar #'rlp-encode
                                   (block-requests block)))))))
    (when (block-block-access-list-present-p block)
      (setf items
            (append items
                    (list (or (block-encoded-block-access-list block)
                              (block-access-list-rlp
                               (block-block-access-list block)))))))
    (eth-rpc-encoded-rlp-list items)))

(defun eth-rpc-block-full-transactions-param (params method)
  (unless (= 2 (length params))
    (block-validation-fail
     "~A params must contain block id and full transaction flag" method))
  (let ((full-transactions-p (second params)))
    (unless (or (null full-transactions-p)
                (eq full-transactions-p t))
      (block-validation-fail
       "~A full transaction flag must be a boolean" method))
    full-transactions-p))

(defun eth-rpc-block-transactions-object
    (block full-transactions-p &key expected-chain-id)
  (if full-transactions-p
      (loop for transaction in (block-transactions block)
            for index from 0
            collect (eth-rpc-transaction-object
                     transaction block index
                     :expected-chain-id expected-chain-id))
      (mapcar (lambda (transaction)
                (hash32-to-hex (transaction-hash transaction)))
              (block-transactions block))))

(defun eth-rpc-block-object (block full-transactions-p &key expected-chain-id)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  (append
   (eth-rpc-header-object (block-header block))
   (list
    (cons "size" (quantity-to-hex (length (eth-rpc-block-rlp block))))
    (cons "transactions"
          (eth-rpc-block-transactions-object
           block full-transactions-p
           :expected-chain-id expected-chain-id))
    (cons "uncles"
          (mapcar (lambda (ommer)
                    (hash32-to-hex (block-header-hash ommer)))
                  (block-ommers block))))
   (when (block-withdrawals-present-p block)
     (list
      (cons "withdrawals"
            (mapcar #'engine-rpc-withdrawal-object
                    (block-withdrawals block)))))))

(defun engine-rpc-handle-eth-get-block-by-number (params store config)
  (let* ((full-transactions-p
           (eth-rpc-block-full-transactions-param params "eth_getBlockByNumber"))
         (number (eth-rpc-block-number-param
                  (list (first params)) store "eth_getBlockByNumber"))
         (block (chain-store-block-by-number store number)))
    (when block
      (eth-rpc-block-object
       block full-transactions-p
       :expected-chain-id (chain-config-chain-id config)))))

(defun engine-rpc-handle-eth-get-block-by-hash (params store config)
  (let* ((full-transactions-p
           (eth-rpc-block-full-transactions-param params "eth_getBlockByHash"))
         (hash (eth-rpc-hash-param
                (list (first params)) "eth_getBlockByHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (when block
      (eth-rpc-block-object
       block full-transactions-p
       :expected-chain-id (chain-config-chain-id config)))))

(defun eth-rpc-block-transaction-count (block)
  (when block
    (quantity-to-hex (length (block-transactions block)))))

(defun engine-rpc-handle-eth-get-block-transaction-count-by-number
    (params store)
  (let* ((number (eth-rpc-block-number-param
                  params store
                  "eth_getBlockTransactionCountByNumber"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-block-transaction-count block)))

(defun engine-rpc-handle-eth-get-block-transaction-count-by-hash
    (params store)
  (let* ((hash (eth-rpc-hash-param
                params
                "eth_getBlockTransactionCountByHash"
                "block hash"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-block-transaction-count block)))

(defun eth-rpc-block-ommer-count (block)
  (when block
    (quantity-to-hex (length (block-ommers block)))))

(defun eth-rpc-ommer-object (header)
  (when header
    (let ((block (make-block :header header)))
      (append
       (eth-rpc-header-object header)
       (list
        (cons "size" (quantity-to-hex (length (eth-rpc-block-rlp block))))
        (cons "uncles" '()))))))

(defun eth-rpc-ommer-by-index (block index)
  (when (and block (< index (length (block-ommers block))))
    (eth-rpc-ommer-object (nth index (block-ommers block)))))

(defun engine-rpc-handle-eth-get-uncle-count-by-number (params store)
  (let* ((number (eth-rpc-block-number-param
                  params store "eth_getUncleCountByBlockNumber"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-block-ommer-count block)))

(defun engine-rpc-handle-eth-get-uncle-count-by-hash (params store)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getUncleCountByBlockHash" "block hash"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-block-ommer-count block)))

(defun engine-rpc-handle-eth-get-uncle-by-block-number-and-index
    (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getUncleByBlockNumberAndIndex params must contain block id and uncle index"))
  (let* ((number (eth-rpc-block-number-param
                  (list (first params)) store
                  "eth_getUncleByBlockNumberAndIndex"))
         (index (engine-rpc-quantity-param
                 params 1 "uncle index"
                 "eth_getUncleByBlockNumberAndIndex"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-ommer-by-index block index)))

(defun engine-rpc-handle-eth-get-uncle-by-block-hash-and-index
    (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getUncleByBlockHashAndIndex params must contain block id and uncle index"))
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getUncleByBlockHashAndIndex"
                "block hash"))
         (index (engine-rpc-quantity-param
                 params 1 "uncle index"
                 "eth_getUncleByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-ommer-by-index block index)))

(defun eth-rpc-transaction-index-param (params method)
  (unless (= 2 (length params))
    (block-validation-fail
     "~A params must contain block id and transaction index" method))
  (engine-rpc-quantity-param params 1 "transaction index" method))

(defun eth-rpc-raw-transaction-by-index (block index)
  (when (and block (< index (length (block-transactions block))))
    (bytes-to-hex (transaction-encoding
                   (nth index (block-transactions block))))))

(defun eth-rpc-address-or-null (address)
  (when address
    (address-to-hex address)))

(defun eth-rpc-access-list-entry-object (entry)
  (list
   (cons "address" (address-to-hex (access-list-entry-address entry)))
   (cons "storageKeys"
         (mapcar #'hash32-to-hex
                 (access-list-entry-storage-keys entry)))))

(defun eth-rpc-access-list-object (access-list)
  (mapcar #'eth-rpc-access-list-entry-object access-list))

(defun eth-rpc-set-code-authorization-object (authorization)
  (list
   (cons "chainId"
         (quantity-to-hex
          (set-code-authorization-chain-id authorization)))
   (cons "address"
         (address-to-hex
          (set-code-authorization-address authorization)))
   (cons "nonce"
         (quantity-to-hex
          (set-code-authorization-nonce authorization)))
   (cons "yParity"
         (quantity-to-hex
          (set-code-authorization-y-parity authorization)))
   (cons "r" (quantity-to-hex (set-code-authorization-r authorization)))
   (cons "s" (quantity-to-hex (set-code-authorization-s authorization)))))

(defun eth-rpc-transaction-core-fields (transaction)
  (etypecase transaction
    (legacy-transaction
     (values (legacy-transaction-nonce transaction)
             (legacy-transaction-gas-price transaction)
             (legacy-transaction-gas-limit transaction)
             (legacy-transaction-to transaction)
             (legacy-transaction-value transaction)
             (legacy-transaction-data transaction)
             (legacy-transaction-v transaction)
             (legacy-transaction-r transaction)
             (legacy-transaction-s transaction)))
    (access-list-transaction
     (values (access-list-transaction-nonce transaction)
             (access-list-transaction-gas-price transaction)
             (access-list-transaction-gas-limit transaction)
             (access-list-transaction-to transaction)
             (access-list-transaction-value transaction)
             (access-list-transaction-data transaction)
             (access-list-transaction-y-parity transaction)
             (access-list-transaction-r transaction)
             (access-list-transaction-s transaction)))
    (dynamic-fee-transaction
     (values (dynamic-fee-transaction-nonce transaction)
             (dynamic-fee-transaction-max-fee-per-gas transaction)
             (dynamic-fee-transaction-gas-limit transaction)
             (dynamic-fee-transaction-to transaction)
             (dynamic-fee-transaction-value transaction)
             (dynamic-fee-transaction-data transaction)
             (dynamic-fee-transaction-y-parity transaction)
             (dynamic-fee-transaction-r transaction)
             (dynamic-fee-transaction-s transaction)))
    (blob-transaction
     (values (blob-transaction-nonce transaction)
             (blob-transaction-max-fee-per-gas transaction)
             (blob-transaction-gas-limit transaction)
             (blob-transaction-to transaction)
             (blob-transaction-value transaction)
             (blob-transaction-data transaction)
             (blob-transaction-y-parity transaction)
             (blob-transaction-r transaction)
             (blob-transaction-s transaction)))
    (set-code-transaction
     (values (set-code-transaction-nonce transaction)
             (set-code-transaction-max-fee-per-gas transaction)
             (set-code-transaction-gas-limit transaction)
             (set-code-transaction-to transaction)
             (set-code-transaction-value transaction)
             (set-code-transaction-data transaction)
             (set-code-transaction-y-parity transaction)
             (set-code-transaction-r transaction)
             (set-code-transaction-s transaction)))))

(defun eth-rpc-transaction-gas-price (transaction header)
  (if (or (typep transaction 'legacy-transaction)
          (typep transaction 'access-list-transaction)
          (not header)
          (not (block-header-base-fee-per-gas header)))
      (transaction-max-fee-per-gas transaction)
      (transaction-effective-gas-price
       transaction :base-fee (block-header-base-fee-per-gas header))))

(defun eth-rpc-transaction-sender (transaction &key expected-chain-id)
  (or (transaction-sender transaction
                          :expected-chain-id expected-chain-id)
      (block-validation-fail
       "eth transaction sender recovery failed")))

(defun eth-rpc-transaction-type-fields (transaction)
  (etypecase transaction
    (legacy-transaction
     (let ((chain-id (legacy-transaction-chain-id transaction)))
       (when (and chain-id (plusp chain-id))
         (list (cons "chainId" (quantity-to-hex chain-id))))))
    (access-list-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (access-list-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (access-list-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (access-list-transaction-y-parity transaction)))))
    (dynamic-fee-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (dynamic-fee-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (dynamic-fee-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (dynamic-fee-transaction-y-parity transaction)))
      (cons "maxFeePerGas"
            (quantity-to-hex
             (dynamic-fee-transaction-max-fee-per-gas transaction)))
      (cons "maxPriorityFeePerGas"
            (quantity-to-hex
             (dynamic-fee-transaction-max-priority-fee-per-gas transaction)))))
    (blob-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (blob-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (blob-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (blob-transaction-y-parity transaction)))
      (cons "maxFeePerGas"
            (quantity-to-hex
             (blob-transaction-max-fee-per-gas transaction)))
      (cons "maxPriorityFeePerGas"
            (quantity-to-hex
             (blob-transaction-max-priority-fee-per-gas transaction)))
      (cons "maxFeePerBlobGas"
            (quantity-to-hex
             (blob-transaction-max-fee-per-blob-gas transaction)))
      (cons "blobVersionedHashes"
            (mapcar #'hash32-to-hex
                    (blob-transaction-blob-versioned-hashes
                     transaction)))))
    (set-code-transaction
     (list
      (cons "accessList"
            (eth-rpc-access-list-object
             (set-code-transaction-access-list transaction)))
      (cons "chainId"
            (quantity-to-hex
             (set-code-transaction-chain-id transaction)))
      (cons "yParity"
            (quantity-to-hex
             (set-code-transaction-y-parity transaction)))
      (cons "maxFeePerGas"
            (quantity-to-hex
             (set-code-transaction-max-fee-per-gas transaction)))
      (cons "maxPriorityFeePerGas"
            (quantity-to-hex
             (set-code-transaction-max-priority-fee-per-gas transaction)))
      (cons "authorizationList"
            (mapcar #'eth-rpc-set-code-authorization-object
                    (set-code-transaction-authorization-list
                     transaction)))))))

(defun eth-rpc-transaction-object
    (transaction block index &key expected-chain-id)
  (let ((header (when block
                  (block-header block))))
    (multiple-value-bind (nonce gas-price gas-limit to value data v r s)
        (eth-rpc-transaction-core-fields transaction)
      (append
       (list
        (cons "blockHash" (when block
                            (hash32-to-hex (block-hash block))))
        (cons "blockNumber"
              (when header
                (quantity-to-hex (block-header-number header))))
        (cons "blockTimestamp"
              (when header
                (quantity-to-hex (block-header-timestamp header))))
        (cons "from"
              (address-to-hex
               (eth-rpc-transaction-sender
                transaction
                :expected-chain-id expected-chain-id)))
        (cons "gas" (quantity-to-hex gas-limit))
        (cons "gasPrice"
              (quantity-to-hex
               (eth-rpc-transaction-gas-price transaction header)))
        (cons "hash" (hash32-to-hex (transaction-hash transaction)))
        (cons "input" (bytes-to-hex data))
        (cons "nonce" (quantity-to-hex nonce))
        (cons "to" (eth-rpc-address-or-null to))
        (cons "transactionIndex" (when index
                                   (quantity-to-hex index)))
        (cons "value" (quantity-to-hex value))
        (cons "type" (quantity-to-hex (transaction-type transaction))))
       (eth-rpc-transaction-type-fields transaction)
       (list
        (cons "v" (quantity-to-hex v))
        (cons "r" (quantity-to-hex r))
        (cons "s" (quantity-to-hex s)))))))

(defun eth-rpc-transaction-by-index (block index &key expected-chain-id)
  (when (and block (< index (length (block-transactions block))))
    (eth-rpc-transaction-object
     (nth index (block-transactions block)) block index
     :expected-chain-id expected-chain-id)))

(defun eth-rpc-transaction-from-location (location &key expected-chain-id)
  (when location
    (eth-rpc-transaction-object
     (engine-transaction-location-transaction location)
     (engine-transaction-location-block location)
     (engine-transaction-location-index location)
     :expected-chain-id expected-chain-id)))

(defun eth-rpc-pending-transaction-object (transaction &key expected-chain-id)
  (when transaction
    (eth-rpc-transaction-object
     transaction nil nil
     :expected-chain-id expected-chain-id)))

(defun eth-rpc-json-array (items)
  (if items
      items
      (make-array 0)))

(defun eth-rpc-pending-transaction-objects
    (transactions &key expected-chain-id)
  (eth-rpc-json-array
   (loop for transaction in transactions
         when (transaction-sender
               transaction
               :expected-chain-id expected-chain-id)
           collect (eth-rpc-pending-transaction-object
                    transaction
                    :expected-chain-id expected-chain-id))))

(defun eth-rpc-hash-table-object (table)
  (if (zerop (hash-table-count table))
      +json-empty-object+
      (loop for key in (sort (loop for key being the hash-keys of table
                                   collect key)
                             #'string<)
            collect (cons key (gethash key table)))))

(defun txpool-rpc-nonce-key< (left right)
  (< (parse-integer left :junk-allowed nil)
     (parse-integer right :junk-allowed nil)))

(defun txpool-rpc-indexed-nonce-transactions
    (sender-transactions value-function)
  (let ((entries
          (unless (or (null sender-transactions)
                      (zerop (hash-table-count sender-transactions)))
            (loop for nonce in (sort (loop for nonce being the hash-keys
                                             of sender-transactions
                                           collect nonce)
                                     #'txpool-rpc-nonce-key<)
                  for value = (funcall value-function
                                       (gethash nonce sender-transactions))
                  when value
                    collect (cons nonce value)))))
    (or entries +json-empty-object+)))

(defun txpool-rpc-indexed-nonce-transactions-from-sender-indexes
    (address value-function &rest sender-indexes)
  (let ((sender-key (address-to-hex address))
        (merged-transactions (make-hash-table :test 'equal)))
    (dolist (sender-index sender-indexes)
      (let ((sender-transactions (gethash sender-key sender-index)))
        (when sender-transactions
          (maphash
           (lambda (nonce transaction)
             (setf (gethash nonce merged-transactions) transaction))
           sender-transactions))))
    (txpool-rpc-indexed-nonce-transactions
     merged-transactions
     value-function)))

(defun txpool-rpc-indexed-sender-transactions
    (sender-index value-function)
  (let ((entries
          (unless (zerop (hash-table-count sender-index))
            (loop for sender in (sort (loop for sender being the hash-keys
                                              of sender-index
                                            collect sender)
                                      #'string<)
                  for transactions =
                    (txpool-rpc-indexed-nonce-transactions
                     (gethash sender sender-index)
                     value-function)
                  unless (json-empty-object-p transactions)
                    collect (cons sender transactions)))))
    (or entries +json-empty-object+)))

(defun txpool-rpc-indexed-sender-transactions-from-indexes
    (value-function &rest sender-indexes)
  (let ((merged-senders (make-hash-table :test 'equal)))
    (dolist (sender-index sender-indexes)
      (maphash
       (lambda (sender sender-transactions)
         (let ((merged-transactions
                 (or (gethash sender merged-senders)
                     (setf (gethash sender merged-senders)
                           (make-hash-table :test 'equal)))))
           (maphash
            (lambda (nonce transaction)
              (setf (gethash nonce merged-transactions) transaction))
            sender-transactions)))
       sender-index))
    (txpool-rpc-indexed-sender-transactions
     merged-senders
     value-function)))

(defun txpool-rpc-transaction-summary (transaction &key expected-chain-id)
  (when (transaction-sender
         transaction
         :expected-chain-id expected-chain-id)
    (let ((to (transaction-to transaction)))
      (format nil "~A: ~D wei + ~D gas x ~D wei"
              (if to
                  (address-to-hex to)
                  "contract creation")
              (transaction-value transaction)
              (transaction-gas-limit transaction)
              (transaction-max-fee-per-gas transaction)))))

(defun txpool-rpc-indexed-content-transactions
    (sender-index &key expected-chain-id)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   (lambda (transaction)
     (when (transaction-sender
            transaction
            :expected-chain-id expected-chain-id)
       (eth-rpc-pending-transaction-object
        transaction
        :expected-chain-id expected-chain-id)))))

(defun txpool-rpc-indexed-inspect-transactions
    (sender-index &key expected-chain-id)
  (txpool-rpc-indexed-sender-transactions
   sender-index
   (lambda (transaction)
     (txpool-rpc-transaction-summary
      transaction
      :expected-chain-id expected-chain-id))))

(defun eth-rpc-raw-transaction-from-location (location)
  (when location
    (bytes-to-hex
     (transaction-encoding
      (engine-transaction-location-transaction location)))))

(defun eth-rpc-raw-transaction (transaction)
  (when transaction
    (bytes-to-hex (transaction-encoding transaction))))

(defun eth-rpc-pooled-raw-transaction (transaction expected-chain-id)
  (when (and transaction
             (transaction-sender
              transaction
              :expected-chain-id expected-chain-id))
    (eth-rpc-raw-transaction transaction)))

(defun eth-rpc-contract-creation-address (transaction sender)
  (when (and (null (transaction-to transaction)) sender)
    (let* ((hash (keccak-256
                  (rlp-encode
                   (make-rlp-list (address-bytes sender)
                                  (transaction-nonce transaction)))))
           (bytes (make-byte-vector 20)))
      (replace bytes hash :start2 12)
      (make-address bytes))))

(defun eth-rpc-validate-set-code-authorization-signatures (transaction)
  (validate-set-code-authorization-signatures transaction))

(defun eth-rpc-txpool-admission-head-context (store)
  (let* ((head (chain-store-latest-block store))
         (header (and head (block-header head))))
    (values head
            (if header (block-header-number header) 0)
            (if header (block-header-timestamp header) 0))))

(defun eth-rpc-validate-txpool-sender-code (store head sender)
  (when head
    (let ((code (chain-store-account-code store (block-hash head) sender)))
      (when (and (plusp (length code))
                 (not (set-code-delegation-target code)))
        (block-validation-fail
         "eth_sendRawTransaction sender has non-delegation code"))))
  t)

(defun eth-rpc-txpool-upfront-cost (transaction)
  (engine-payload-store-txpool-upfront-cost transaction))

(defun eth-rpc-txpool-sender-admission-expenditure
    (store sender transaction)
  (engine-payload-store-sender-admission-expenditure
   store sender transaction))

(defun eth-rpc-validate-txpool-sender-state (store head sender transaction)
  (when (and head
             (chain-store-state-available-p store (block-hash head)))
    (let* ((block-hash (block-hash head))
           (state-nonce (chain-store-account-nonce store block-hash sender))
           (state-balance
             (chain-store-account-balance store block-hash sender)))
      (when (< (transaction-nonce transaction) state-nonce)
        (block-validation-fail "eth_sendRawTransaction nonce too low"))
      (when (< state-balance
               (eth-rpc-txpool-sender-admission-expenditure
                store
                sender
                transaction))
        (block-validation-fail
         "eth_sendRawTransaction insufficient sender balance"))))
  t)

(defun eth-rpc-txpool-queued-nonce-gap-p (store sender transaction)
  (multiple-value-bind (head block-number timestamp)
      (eth-rpc-txpool-admission-head-context store)
    (declare (ignore block-number timestamp))
    (and head
         (chain-store-state-available-p store (block-hash head))
         (> (transaction-nonce transaction)
            (engine-payload-store-pending-contiguous-nonce
             store
             sender
             (chain-store-account-nonce
              store
              (block-hash head)
              sender))))))

(defun eth-rpc-txpool-basefee-ineligible-p (store transaction)
  (multiple-value-bind (head block-number timestamp)
      (eth-rpc-txpool-admission-head-context store)
    (declare (ignore block-number timestamp))
    (let* ((header (and head (block-header head)))
           (base-fee (and header
                          (block-header-base-fee-per-gas header))))
      (and base-fee
           (< (transaction-max-fee-per-gas transaction) base-fee)))))

(defun eth-rpc-validate-txpool-admission
    (transaction sender store config)
  (multiple-value-bind (head block-number timestamp)
      (eth-rpc-txpool-admission-head-context store)
    (let ((rules (chain-config-rules config block-number timestamp)))
      (validate-transaction-type-for-config
       transaction config block-number timestamp)
      (validate-transaction-data-field transaction)
      (validate-transaction-recipient-field transaction)
      (validate-transaction-scalar-fields transaction)
      (validate-transaction-signature-fields transaction)
      (validate-access-list-fields transaction)
      (validate-set-code-transaction-fields transaction)
      (when (typep transaction 'blob-transaction)
        (validate-blob-transaction-fields transaction))
      (engine-payload-store-validate-txpool-blob-fee-cap
       store
       transaction
       :chain-config config
       :label "eth_sendRawTransaction")
      (let ((intrinsic-gas
              (ethereum-lisp.state:transaction-intrinsic-gas
               transaction
               :eip3860-p (or (null rules)
                               (chain-rules-shanghai-p rules)))))
        (when (< (transaction-gas-limit transaction) intrinsic-gas)
          (block-validation-fail
           "eth_sendRawTransaction gas limit below intrinsic gas")))
      (when (and head
                 (> (transaction-gas-limit transaction)
                    (block-header-gas-limit (block-header head))))
        (block-validation-fail
         "eth_sendRawTransaction gas limit exceeds block gas limit"))
      (eth-rpc-validate-txpool-sender-state
       store head sender transaction)
      (eth-rpc-validate-txpool-sender-code store head sender)))
  t)

(defun eth-rpc-receipt-gas-used (receipt previous-receipt)
  (- (receipt-cumulative-gas-used receipt)
     (if previous-receipt
         (receipt-cumulative-gas-used previous-receipt)
         0)))

(defun eth-rpc-log-object
    (log block transaction transaction-index log-index &key removed-p)
  (let ((header (block-header block)))
    (list
     (cons "address" (address-to-hex (log-entry-address log)))
     (cons "topics" (mapcar #'hash32-to-hex
                            (log-entry-topics log)))
     (cons "data" (bytes-to-hex (log-entry-data log)))
     (cons "blockHash" (hash32-to-hex (block-hash block)))
     (cons "blockNumber"
           (quantity-to-hex (block-header-number header)))
     (cons "transactionHash"
           (hash32-to-hex (transaction-hash transaction)))
     (cons "transactionIndex" (quantity-to-hex transaction-index))
     (cons "logIndex" (quantity-to-hex log-index))
     (cons "removed" (if removed-p t :false)))))

(defun eth-rpc-receipt-object (location &key expected-chain-id)
  (let* ((receipt (engine-transaction-location-receipt location))
         (block (engine-transaction-location-block location))
         (transaction (engine-transaction-location-transaction location))
         (index (engine-transaction-location-index location)))
    (when receipt
      (let* ((header (block-header block))
             (previous-receipt
               (when (plusp index)
                 (nth (1- index) (block-receipts block))))
             (from (eth-rpc-transaction-sender
                    transaction
                    :expected-chain-id expected-chain-id))
             (logs
               (loop for log in (receipt-logs receipt)
                     for log-index
                       from (engine-transaction-location-log-index-start
                             location)
                     collect (eth-rpc-log-object
                              log block transaction index log-index))))
        (append
         (list
          (cons "transactionHash"
                (hash32-to-hex (transaction-hash transaction)))
          (cons "transactionIndex" (quantity-to-hex index))
          (cons "blockHash" (hash32-to-hex (block-hash block)))
          (cons "blockNumber"
                (quantity-to-hex (block-header-number header)))
          (cons "from" (address-to-hex from))
          (cons "to"
                (eth-rpc-address-or-null
                 (nth-value 3
                            (eth-rpc-transaction-core-fields
                             transaction))))
          (cons "cumulativeGasUsed"
                (quantity-to-hex
                 (receipt-cumulative-gas-used receipt)))
          (cons "gasUsed"
                (quantity-to-hex
                 (eth-rpc-receipt-gas-used receipt previous-receipt)))
          (cons "contractAddress"
                (eth-rpc-address-or-null
                 (eth-rpc-contract-creation-address transaction from)))
          (cons "logs" logs)
          (cons "logsBloom"
                (bytes-to-hex
                 (bloom-bytes
                  (receipt-bloom (receipt-logs receipt)))))
          (cons "type" (quantity-to-hex (transaction-type transaction)))
          (cons "effectiveGasPrice"
                (quantity-to-hex
                 (eth-rpc-transaction-gas-price transaction header))))
         (if (receipt-post-state receipt)
             (list (cons "root"
                         (bytes-to-hex (receipt-post-state receipt))))
             (list (cons "status"
                         (quantity-to-hex (receipt-status receipt))))))))))

(defun eth-rpc-block-receipts-object (block &key expected-chain-id)
  (when (and block
             (= (length (block-transactions block))
                (length (block-receipts block))))
    (loop with log-index-start = 0
          for transaction in (block-transactions block)
          for receipt in (block-receipts block)
          for index from 0
          for location = (make-engine-transaction-location
                          :block block
                          :index index
                          :transaction transaction
                          :receipt receipt
                          :log-index-start log-index-start)
          collect (prog1 (eth-rpc-receipt-object
                          location
                          :expected-chain-id expected-chain-id)
                    (incf log-index-start
                          (length (receipt-logs receipt)))))))

(defun engine-rpc-handle-eth-get-raw-transaction-by-block-number-and-index
    (params store)
  (let* ((number (eth-rpc-block-number-param
                  (list (first params)) store
                  "eth_getRawTransactionByBlockNumberAndIndex"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getRawTransactionByBlockNumberAndIndex"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-raw-transaction-by-index block index)))

(defun engine-rpc-handle-eth-get-raw-transaction-by-block-hash-and-index
    (params store)
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getRawTransactionByBlockHashAndIndex"
                "block hash"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getRawTransactionByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-raw-transaction-by-index block index)))

(defun engine-rpc-handle-eth-get-raw-transaction-by-hash
    (params store config)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getRawTransactionByHash" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (or (eth-rpc-raw-transaction-from-location location)
        (eth-rpc-pooled-raw-transaction
         (engine-payload-store-pooled-transaction store hash)
         (chain-config-chain-id config)))))

(defun engine-rpc-handle-eth-send-raw-transaction (params store config)
  (unless (= 1 (length params))
    (block-validation-fail
     "eth_sendRawTransaction params must contain exactly one transaction"))
  (let* ((raw-bytes
            (engine-rpc-bytes
             (first params)
             "eth_sendRawTransaction transaction"))
         (transaction (transaction-from-encoding raw-bytes))
         (hash (transaction-hash transaction)))
    (validate-set-code-transaction-fields transaction)
    (eth-rpc-validate-set-code-authorization-signatures transaction)
    (let ((sender
            (or (transaction-sender
                 transaction
                 :expected-chain-id (chain-config-chain-id config))
                (block-validation-fail
                 "eth_sendRawTransaction transaction sender recovery failed"))))
      (unless (or (chain-store-transaction-location store hash)
                  (engine-payload-store-pooled-transaction store hash))
        (eth-rpc-validate-txpool-admission transaction sender store config)
        (cond
          ((typep transaction 'blob-transaction)
           (engine-payload-store-put-blob-transaction store transaction))
          ((eth-rpc-txpool-basefee-ineligible-p store transaction)
           (engine-payload-store-put-basefee-transaction store transaction))
          ((eth-rpc-txpool-queued-nonce-gap-p store sender transaction)
           (engine-payload-store-put-queued-transaction store transaction))
          (t
           (engine-payload-store-put-pending-transaction store transaction)
           (engine-payload-store-promote-queued-transactions
            store sender
            :expected-chain-id (chain-config-chain-id config))
           (engine-payload-store-promote-basefee-and-queued-transactions
            store
            :expected-chain-id (chain-config-chain-id config))))))
    (hash32-to-hex hash)))

(defun eth-rpc-txpool-queued-view-transactions (store)
  (append (engine-payload-store-queued-transactions store)
          (engine-payload-store-basefee-transactions store)
          (engine-payload-store-blob-transactions store)))

(defun eth-rpc-txpool-visible-transaction-count
    (transactions expected-chain-id)
  (count-if
   (lambda (transaction)
     (transaction-sender
      transaction
      :expected-chain-id expected-chain-id))
   transactions))

(defun eth-rpc-txpool-pending-view-count (store expected-chain-id)
  (eth-rpc-txpool-visible-transaction-count
   (engine-payload-store-pending-transactions store)
   expected-chain-id))

(defun eth-rpc-txpool-queued-view-count (store expected-chain-id)
  (eth-rpc-txpool-visible-transaction-count
   (eth-rpc-txpool-queued-view-transactions store)
   expected-chain-id))

(defun engine-rpc-handle-eth-pending-transactions (params store config)
  (when params
    (block-validation-fail "eth_pendingTransactions params must be empty"))
  (eth-rpc-pending-transaction-objects
   (engine-payload-store-pending-transactions store)
   :expected-chain-id (chain-config-chain-id config)))

(defun engine-rpc-handle-txpool-status (params store config)
  (when params
    (block-validation-fail "txpool_status params must be empty"))
  (let ((chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (quantity-to-hex
            (eth-rpc-txpool-pending-view-count store chain-id)))
     (cons "queued"
           (quantity-to-hex
            (eth-rpc-txpool-queued-view-count store chain-id))))))

(defun engine-rpc-handle-txpool-content (params store config)
  (when params
    (block-validation-fail "txpool_content params must be empty"))
  (let ((chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (txpool-rpc-indexed-content-transactions
            (engine-payload-store-pending-transactions-by-sender store)
            :expected-chain-id chain-id))
     (cons "queued"
           (txpool-rpc-indexed-sender-transactions-from-indexes
            (lambda (transaction)
              (when (transaction-sender
                     transaction
                     :expected-chain-id chain-id)
                (eth-rpc-pending-transaction-object
                 transaction
                 :expected-chain-id chain-id)))
            (engine-payload-store-queued-sender-index store)
            (engine-payload-store-basefee-sender-index store)
            (engine-payload-store-blob-sender-index store))))))

(defun engine-rpc-handle-txpool-content-from (params store config)
  (unless (= 1 (length params))
    (block-validation-fail
     "txpool_contentFrom params must contain exactly one address"))
  (let ((address (eth-rpc-address-param
                  (first params) "txpool_contentFrom" "address"))
        (chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (txpool-rpc-indexed-nonce-transactions
            (gethash
             (address-to-hex address)
             (engine-payload-store-pending-transactions-by-sender store))
            (lambda (transaction)
              (when (transaction-sender
                     transaction
                     :expected-chain-id chain-id)
                (eth-rpc-pending-transaction-object
                 transaction
                 :expected-chain-id chain-id)))))
     (cons "queued"
           (txpool-rpc-indexed-nonce-transactions-from-sender-indexes
            address
            (lambda (transaction)
              (when (transaction-sender
                     transaction
                     :expected-chain-id chain-id)
                (eth-rpc-pending-transaction-object
                 transaction
                 :expected-chain-id chain-id)))
            (engine-payload-store-queued-sender-index store)
            (engine-payload-store-basefee-sender-index store)
            (engine-payload-store-blob-sender-index store))))))

(defun engine-rpc-handle-txpool-inspect (params store config)
  (when params
    (block-validation-fail "txpool_inspect params must be empty"))
  (let ((chain-id (chain-config-chain-id config)))
    (list
     (cons "pending"
           (txpool-rpc-indexed-inspect-transactions
            (engine-payload-store-pending-transactions-by-sender store)
            :expected-chain-id chain-id))
     (cons "queued"
           (txpool-rpc-indexed-sender-transactions-from-indexes
            (lambda (transaction)
              (txpool-rpc-transaction-summary
               transaction
               :expected-chain-id chain-id))
            (engine-payload-store-queued-sender-index store)
            (engine-payload-store-basefee-sender-index store)
            (engine-payload-store-blob-sender-index store))))))

(defun engine-rpc-handle-eth-get-transaction-by-block-number-and-index
    (params store config)
  (let* ((number (eth-rpc-block-number-param
                  (list (first params)) store
                  "eth_getTransactionByBlockNumberAndIndex"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getTransactionByBlockNumberAndIndex"))
         (block (chain-store-block-by-number store number)))
    (eth-rpc-transaction-by-index
     block index
     :expected-chain-id (chain-config-chain-id config))))

(defun engine-rpc-handle-eth-get-transaction-by-block-hash-and-index
    (params store config)
  (let* ((hash (eth-rpc-hash-param
                (list (first params))
                "eth_getTransactionByBlockHashAndIndex"
                "block hash"))
         (index (eth-rpc-transaction-index-param
                 params "eth_getTransactionByBlockHashAndIndex"))
         (block (chain-store-known-block store hash)))
    (eth-rpc-transaction-by-index
     block index
     :expected-chain-id (chain-config-chain-id config))))

(defun engine-rpc-handle-eth-get-transaction-by-hash (params store config)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getTransactionByHash" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (or (eth-rpc-transaction-from-location
         location
         :expected-chain-id (chain-config-chain-id config))
        (eth-rpc-pending-transaction-object
         (engine-payload-store-pooled-transaction store hash)
         :expected-chain-id (chain-config-chain-id config)))))

(defun engine-rpc-handle-eth-get-transaction-receipt (params store config)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getTransactionReceipt" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (when location
      (eth-rpc-receipt-object
       location
       :expected-chain-id (chain-config-chain-id config)))))

(defun engine-rpc-handle-eth-get-block-receipts (params store config)
  (let ((block (eth-rpc-block-param params store "eth_getBlockReceipts")))
    (eth-rpc-block-receipts-object
     block
     :expected-chain-id (chain-config-chain-id config))))

(defun eth-rpc-address= (left right)
  (and left
       right
       (bytes= (address-bytes left) (address-bytes right))))

(defun eth-rpc-log-address-match-p (log addresses)
  (or (null addresses)
      (some (lambda (address)
              (eth-rpc-address= (log-entry-address log) address))
            addresses)))

(defun eth-rpc-log-topics-match-p (log topic-filters)
  (let ((topics (log-entry-topics log)))
    (or (null topic-filters)
        (loop for slot in topic-filters
              for index from 0
              always (and (< index (length topics))
                          (or (null slot)
                              (some (lambda (topic)
                                      (hash32= (nth index topics) topic))
                                    slot)))))))

(defun eth-rpc-log-filter-object (params method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one filter"
                           method))
  (let ((filter (first params)))
    (unless (or (null filter) (json-object-p filter))
      (block-validation-fail "~A filter must be an object" method))
    filter))

(defun eth-rpc-log-filter-addresses (filter method)
  (let ((value (genesis-object-field filter "address")))
    (cond
      ((null value) nil)
      ((stringp value)
       (list (eth-rpc-address-param value method "address")))
      ((listp value)
       (mapcar (lambda (address)
                 (unless (stringp address)
                   (block-validation-fail
                    "~A address filter entries must be addresses" method))
                 (eth-rpc-address-param address method "address"))
               value))
      (t
       (block-validation-fail
        "~A address filter must be an address or address array" method)))))

(defun eth-rpc-log-filter-topic (value method)
  (cond
    ((null value) nil)
    ((stringp value)
     (list (eth-rpc-hash-param (list value) method "topic")))
    ((listp value)
     (mapcar (lambda (topic)
               (unless (stringp topic)
                 (block-validation-fail
                  "~A topic filter entries must be topics" method))
               (eth-rpc-hash-param (list topic) method "topic"))
             value))
    (t
     (block-validation-fail
      "~A topic filter slots must be null, a topic, or topic array" method))))

(defun eth-rpc-log-filter-topics (filter method)
  (let ((topics (genesis-object-field filter "topics")))
    (cond
      ((null topics) nil)
      ((listp topics)
       (mapcar (lambda (topic)
                 (eth-rpc-log-filter-topic topic method))
               topics))
      (t
       (block-validation-fail
        "~A topics filter must be an array" method)))))

(defun eth-rpc-log-filter-blocks (filter store method)
  (if (genesis-object-field-present-p filter "blockHash")
      (progn
        (when (or (genesis-object-field-present-p filter "fromBlock")
                  (genesis-object-field-present-p filter "toBlock"))
          (block-validation-fail
           "~A blockHash cannot be combined with fromBlock or toBlock"
           method))
        (let ((block-hash (eth-rpc-hash-param
                           (list (genesis-object-field filter "blockHash"))
                           method
                           "block hash")))
          (let ((block (chain-store-known-block store block-hash)))
            (if block
                (list block)
                '()))))
      (let* ((from-number (eth-rpc-block-number-param
                           (list (or (genesis-object-field filter "fromBlock")
                                     "latest"))
                           store
                           method))
             (to-number (eth-rpc-block-number-param
                         (list (or (genesis-object-field filter "toBlock")
                                   "latest"))
                         store
                         method)))
        (when (> from-number to-number)
          (block-validation-fail
           "~A fromBlock must be less than or equal to toBlock" method))
        (loop for number from from-number to to-number
              for block = (chain-store-block-by-number store number)
              when block
                collect block))))

(defun eth-rpc-block-logs-object
    (block addresses topic-filters &key removed-p)
  (when (and block
             (= (length (block-transactions block))
                (length (block-receipts block))))
    (loop with log-index-start = 0
          for transaction in (block-transactions block)
          for receipt in (block-receipts block)
          for transaction-index from 0
          append (loop for log in (receipt-logs receipt)
                       for log-index from log-index-start
                       when (and (eth-rpc-log-address-match-p log addresses)
                                 (eth-rpc-log-topics-match-p
                                  log topic-filters))
                         collect (eth-rpc-log-object
                                  log
                                  block
                                  transaction
                                  transaction-index
                                  log-index
                                  :removed-p removed-p))
          do (incf log-index-start (length (receipt-logs receipt))))))

(defun eth-rpc-filter-logs (filter store method)
  (let* ((addresses (eth-rpc-log-filter-addresses filter method))
         (topic-filters (eth-rpc-log-filter-topics filter method))
         (blocks (eth-rpc-log-filter-blocks filter store method))
         (logs (loop for block in blocks
                     append (eth-rpc-block-logs-object
                             block addresses topic-filters))))
    (eth-rpc-json-array logs)))

(defun eth-rpc-log-filter-change-block-key (change)
  (engine-payload-store-key
   (block-hash (engine-log-filter-change-block change))))

(defun eth-rpc-log-filter-change-in-range-p (change from-number to-number)
  (let ((number
          (block-header-number
           (block-header (engine-log-filter-change-block change)))))
    (<= from-number number to-number)))

(defun eth-rpc-log-filter-change-logs
    (changes criteria method)
  (let ((addresses (eth-rpc-log-filter-addresses criteria method))
        (topic-filters (eth-rpc-log-filter-topics criteria method)))
    (loop for change in changes
          append (eth-rpc-block-logs-object
                  (engine-log-filter-change-block change)
                  addresses
                  topic-filters
                  :removed-p
                  (engine-log-filter-change-removed-p change)))))

(defun eth-rpc-log-filter-range-bounds (filter store method)
  (unless (genesis-object-field-present-p filter "blockHash")
    (values
     (eth-rpc-block-number-param
      (list (or (genesis-object-field filter "fromBlock") "latest"))
      store
      method)
     (eth-rpc-block-number-param
      (list (or (genesis-object-field filter "toBlock") "latest"))
      store
      method))))

(defun eth-rpc-log-filter-with-range (filter from-number to-number)
  (append
   (remove-if (lambda (entry)
                (member (car entry) '("fromBlock" "toBlock" "blockHash")
                        :test #'string=))
              filter)
   (list (cons "fromBlock" (quantity-to-hex from-number))
         (cons "toBlock" (quantity-to-hex to-number)))))

(defun engine-log-filter-changes (log-filter store method)
  (let ((criteria (engine-log-filter-criteria log-filter)))
    (if (genesis-object-field-present-p criteria "blockHash")
        (if (engine-log-filter-block-hash-consumed-p log-filter)
            (eth-rpc-json-array '())
            (prog1 (eth-rpc-filter-logs criteria store method)
              (setf (engine-log-filter-block-hash-consumed-p log-filter) t)))
        (multiple-value-bind (from-number to-number)
            (eth-rpc-log-filter-range-bounds criteria store method)
          (let* ((pending-changes
                   (engine-log-filter-pending-changes log-filter))
                 (changes
                   (remove-if-not
                    (lambda (change)
                      (eth-rpc-log-filter-change-in-range-p
                       change
                       from-number
                       to-number))
                    pending-changes))
                 (change-block-keys (make-hash-table :test 'equal))
                 (cursor (engine-log-filter-last-block-number log-filter))
                 (change-from (if cursor
                                  (max from-number (1+ cursor))
                                  from-number)))
            (dolist (change changes)
              (setf (gethash (eth-rpc-log-filter-change-block-key change)
                             change-block-keys)
                    t))
            (prog1
                (let* ((change-logs
                         (eth-rpc-log-filter-change-logs
                          changes
                          criteria
                          method))
                       (range-logs
                         (if (> change-from to-number)
                             nil
                             (let ((addresses
                                     (eth-rpc-log-filter-addresses
                                      criteria
                                      method))
                                   (topic-filters
                                     (eth-rpc-log-filter-topics
                                      criteria
                                      method)))
                               (loop for number from change-from to to-number
                                     for block =
                                       (chain-store-block-by-number
                                        store
                                        number)
                                     when (and block
                                               (not
                                                (gethash
                                                 (engine-payload-store-key
                                                  (block-hash block))
                                                 change-block-keys)))
                                       append (eth-rpc-block-logs-object
                                               block
                                               addresses
                                               topic-filters))))))
                  (eth-rpc-json-array (append change-logs range-logs)))
              (setf (engine-log-filter-last-block-number log-filter)
                    (max (or cursor 0) to-number)
                    (engine-log-filter-pending-changes log-filter)
                    nil)))))))

(defun engine-block-filter-changes (block-filter store)
  (let* ((cursor (engine-block-filter-last-block-number block-filter))
         (latest (chain-store-head-number store))
         (seen (make-hash-table :test 'equal))
         (hashes nil))
    (dolist (hash (engine-block-filter-hashes block-filter))
      (let ((hash-hex (hash32-to-hex hash)))
        (unless (gethash hash-hex seen)
          (setf (gethash hash-hex seen) t)
          (push hash-hex hashes))))
    (loop for number from (1+ cursor) to latest
          for block = (chain-store-block-by-number store number)
          when block
            do (let ((hash-hex (hash32-to-hex (block-hash block))))
                 (unless (gethash hash-hex seen)
                   (setf (gethash hash-hex seen) t)
                   (push hash-hex hashes))))
    (prog1 (eth-rpc-json-array (nreverse hashes))
      (setf (engine-block-filter-last-block-number block-filter) latest
            (engine-block-filter-hashes block-filter) nil))))

(defun engine-pending-transaction-filter-changes (pending-filter)
  (let ((hashes (engine-pending-transaction-filter-hashes pending-filter)))
    (prog1 (eth-rpc-json-array (mapcar #'hash32-to-hex hashes))
      (setf (engine-pending-transaction-filter-hashes pending-filter) nil))))

(defun engine-rpc-handle-eth-get-logs (params store)
  (let* ((method "eth_getLogs")
         (filter (eth-rpc-log-filter-object params method)))
    (eth-rpc-filter-logs filter store method)))

(defun engine-rpc-handle-eth-new-filter (params store)
  (let* ((method "eth_newFilter")
         (filter (eth-rpc-log-filter-object params method)))
    (eth-rpc-log-filter-addresses filter method)
    (eth-rpc-log-filter-topics filter method)
    (eth-rpc-log-filter-blocks filter store method)
    (quantity-to-hex
     (engine-payload-store-put-log-filter store filter))))

(defun engine-rpc-handle-eth-new-block-filter (params store)
  (when params
    (block-validation-fail "eth_newBlockFilter params must be empty"))
  (quantity-to-hex
   (engine-payload-store-put-block-filter store)))

(defun engine-rpc-handle-eth-new-pending-transaction-filter (params store)
  (when params
    (block-validation-fail
     "eth_newPendingTransactionFilter params must be empty"))
  (quantity-to-hex
   (engine-payload-store-put-pending-transaction-filter store)))

(defun eth-rpc-filter-id-param (params method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one filter id"
                           method))
  (engine-rpc-quantity-param params 0 "filter id" method))

(defun engine-rpc-handle-eth-get-filter-logs (params store)
  (let* ((method "eth_getFilterLogs")
         (id (eth-rpc-filter-id-param params method))
         (log-filter (engine-payload-store-log-filter store id)))
    (unless (typep log-filter 'engine-log-filter)
      (block-validation-fail "~A filter not found" method))
    (eth-rpc-filter-logs
     (engine-log-filter-criteria log-filter) store method)))

(defun engine-rpc-handle-eth-get-filter-changes (params store)
  (let* ((method "eth_getFilterChanges")
         (id (eth-rpc-filter-id-param params method))
         (filter (engine-payload-store-log-filter store id)))
    (cond
      ((typep filter 'engine-log-filter)
       (engine-log-filter-changes filter store method))
      ((typep filter 'engine-block-filter)
       (engine-block-filter-changes filter store))
      ((typep filter 'engine-pending-transaction-filter)
       (engine-pending-transaction-filter-changes filter))
      (t
       (block-validation-fail "~A filter not found" method)))))

(defun engine-rpc-handle-eth-uninstall-filter (params store)
  (let* ((method "eth_uninstallFilter")
         (id (eth-rpc-filter-id-param params method)))
    (if (engine-payload-store-uninstall-log-filter store id)
        t
        :false)))

(defun engine-rpc-handle-public-method (id method params store config)
  (cond
    ((string= method "web3_clientVersion")
     (engine-rpc-response
      id :result (engine-rpc-handle-web3-client-version params)))
    ((string= method "web3_sha3")
     (engine-rpc-response
      id :result (engine-rpc-handle-web3-sha3 params)))
    ((string= method "net_version")
     (engine-rpc-response
      id :result (engine-rpc-handle-net-version params config)))
    ((string= method "net_listening")
     (engine-rpc-response
      id :result (engine-rpc-handle-net-listening params)))
    ((string= method "net_peerCount")
     (engine-rpc-response
      id :result (engine-rpc-handle-net-peer-count params)))
    ((string= method "eth_chainId")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-chain-id params config)))
    ((string= method "eth_blockNumber")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-block-number params store)))
    ((string= method "eth_protocolVersion")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-protocol-version params)))
    ((string= method "eth_syncing")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-syncing params)))
    ((string= method "eth_accounts")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-accounts params)))
    ((string= method "eth_coinbase")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-coinbase params)))
    ((string= method "eth_mining")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-mining params)))
    ((string= method "eth_hashrate")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-hashrate params)))
    ((string= method "eth_gasPrice")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-gas-price params store)))
    ((string= method "eth_maxPriorityFeePerGas")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-max-priority-fee-per-gas params store)))
    ((string= method "eth_baseFee")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-base-fee params store config)))
    ((string= method "eth_blobBaseFee")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-blob-base-fee params store config)))
    ((string= method "eth_feeHistory")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-fee-history params store config)))
    ((string= method "eth_getBalance")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-balance params store)))
    ((string= method "eth_getTransactionCount")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-transaction-count params store)))
    ((string= method "eth_getCode")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-code params store)))
    ((string= method "eth_getStorageAt")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-storage-at params store)))
    ((string= method "eth_getProof")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-proof params store)))
    ((string= method "eth_call")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-call params store config)))
    ((string= method "eth_estimateGas")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-estimate-gas params store config)))
    ((string= method "eth_createAccessList")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-create-access-list params store config)))
    ((string= method "eth_getHeaderByNumber")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-header-by-number params store)))
    ((string= method "eth_getHeaderByHash")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-header-by-hash params store)))
    ((string= method "eth_getBlockByNumber")
     (engine-rpc-response
      id :result
      (engine-rpc-handle-eth-get-block-by-number params store config)))
    ((string= method "eth_getBlockByHash")
     (engine-rpc-response
      id :result
      (engine-rpc-handle-eth-get-block-by-hash params store config)))
    ((string= method "eth_getBlockTransactionCountByNumber")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-block-transaction-count-by-number
       params store)))
    ((string= method "eth_getBlockTransactionCountByHash")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-block-transaction-count-by-hash
       params store)))
    ((string= method "eth_getUncleCountByBlockNumber")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-uncle-count-by-number params store)))
    ((string= method "eth_getUncleCountByBlockHash")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-uncle-count-by-hash params store)))
    ((string= method "eth_getUncleByBlockNumberAndIndex")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-uncle-by-block-number-and-index
       params store)))
    ((string= method "eth_getUncleByBlockHashAndIndex")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-uncle-by-block-hash-and-index
       params store)))
    ((string= method "eth_getTransactionByBlockNumberAndIndex")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-transaction-by-block-number-and-index
       params store config)))
    ((string= method "eth_getTransactionByBlockHashAndIndex")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-transaction-by-block-hash-and-index
       params store config)))
    ((string= method "eth_getTransactionByHash")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-transaction-by-hash params store config)))
    ((string= method "eth_getTransactionReceipt")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-transaction-receipt params store config)))
    ((string= method "eth_getBlockReceipts")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-block-receipts params store config)))
    ((string= method "eth_getLogs")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-logs params store)))
    ((string= method "eth_newFilter")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-new-filter params store)))
    ((string= method "eth_newBlockFilter")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-new-block-filter params store)))
    ((string= method "eth_newPendingTransactionFilter")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-new-pending-transaction-filter params store)))
    ((string= method "eth_getFilterLogs")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-filter-logs params store)))
    ((string= method "eth_getFilterChanges")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-get-filter-changes params store)))
    ((string= method "eth_uninstallFilter")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-uninstall-filter params store)))
    ((string= method "eth_getRawTransactionByBlockNumberAndIndex")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-raw-transaction-by-block-number-and-index
       params store)))
    ((string= method "eth_getRawTransactionByBlockHashAndIndex")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-raw-transaction-by-block-hash-and-index
       params store)))
    ((string= method "eth_getRawTransactionByHash")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-raw-transaction-by-hash
       params store config)))
    ((string= method "eth_sendRawTransaction")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-send-raw-transaction params store config)))
    ((string= method "eth_pendingTransactions")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-pending-transactions params store config)))
    ((string= method "txpool_status")
     (engine-rpc-response
      id :result (engine-rpc-handle-txpool-status params store config)))
    ((string= method "txpool_content")
     (engine-rpc-response
      id :result (engine-rpc-handle-txpool-content params store config)))
    ((string= method "txpool_contentFrom")
     (engine-rpc-response
      id :result (engine-rpc-handle-txpool-content-from params store config)))
    ((string= method "txpool_inspect")
     (engine-rpc-response
      id :result (engine-rpc-handle-txpool-inspect params store config)))))
