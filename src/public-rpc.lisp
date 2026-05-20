(in-package #:ethereum-lisp.core)

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
    (if (and (stringp value)
             (= 66 (length value)))
        (chain-store-known-block
         store
         (eth-rpc-hash-param params method "block hash"))
        (chain-store-block-by-number
         store
         (eth-rpc-block-number-param params store method)))))

(defun engine-rpc-handle-eth-get-balance (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getBalance params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getBalance" "address"))
         (block (eth-rpc-block-param
                 (list (second params)) store "eth_getBalance")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (quantity-to-hex
       (chain-store-account-balance
        store (block-hash block) address)))))

(defun eth-rpc-pending-account-nonce (store address state-nonce)
  (loop with next-nonce = state-nonce
        for transaction in (engine-payload-store-pending-transactions store)
        for sender = (or (transaction-sender transaction) (zero-address))
        when (bytes= (address-bytes sender) (address-bytes address))
          do (setf next-nonce
                   (max next-nonce (1+ (transaction-nonce transaction))))
        finally (return next-nonce)))

(defun engine-rpc-handle-eth-get-transaction-count (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getTransactionCount params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getTransactionCount" "address"))
         (block-id (second params))
         (block (eth-rpc-block-param
                 (list block-id) store "eth_getTransactionCount")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (let ((state-nonce
              (chain-store-account-nonce
               store (block-hash block) address)))
        (quantity-to-hex
         (if (and (stringp block-id) (string= block-id "pending"))
             (eth-rpc-pending-account-nonce store address state-nonce)
             state-nonce))))))

(defun engine-rpc-handle-eth-get-code (params store)
  (unless (= 2 (length params))
    (block-validation-fail
     "eth_getCode params must contain address and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getCode" "address"))
         (block (eth-rpc-block-param
                 (list (second params)) store "eth_getCode")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (bytes-to-hex
       (chain-store-account-code
        store (block-hash block) address)))))

(defun engine-rpc-handle-eth-get-storage-at (params store)
  (unless (= 3 (length params))
    (block-validation-fail
     "eth_getStorageAt params must contain address, storage key, and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getStorageAt" "address"))
         (slot (eth-rpc-storage-slot-param
                (second params) "eth_getStorageAt"))
         (block (eth-rpc-block-param
                 (list (third params)) store "eth_getStorageAt")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (eth-rpc-uint256-word-hex
       (chain-store-account-storage
        store (block-hash block) address slot)))))

(defun eth-rpc-proof-key-for-address (address)
  (keccak-256 (address-bytes address)))

(defun eth-rpc-proof-key-for-storage-slot (slot)
  (keccak-256 (hash32-bytes slot)))

(defun eth-rpc-storage-trie-from-entries (storage-entries)
  (let ((trie (make-mpt)))
    (dolist (entry storage-entries trie)
      (mpt-put trie
               (eth-rpc-proof-key-for-storage-slot (car entry))
               (rlp-encode (cdr entry))))))

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

(defun eth-rpc-storage-proof-object (trie proof-slot value)
  (let ((slot (eth-rpc-proof-storage-slot-slot proof-slot)))
    (list (cons "key" (eth-rpc-proof-storage-slot-output-key proof-slot))
          (cons "value" (quantity-to-hex value))
          (cons "proof"
                (mapcar #'bytes-to-hex
                        (mpt-get-proof
                         trie
                         (eth-rpc-proof-key-for-storage-slot slot)))))))

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
  (let ((state-trie (make-mpt))
        (target-account nil)
        (target-storage-trie nil)
        (target-storage-values (make-hash-table :test #'equal)))
    (chain-store-for-each-account
     store
     block-hash
     (lambda (account-address balance nonce code storage-entries)
       (let* ((storage-trie
                (eth-rpc-storage-trie-from-entries storage-entries))
              (account
                (make-state-account
                 :nonce nonce
                 :balance balance
                 :storage-root (make-hash32 (mpt-root-hash storage-trie))
                 :code-hash (keccak-256-hash code))))
         (mpt-put state-trie
                  (eth-rpc-proof-key-for-address account-address)
                  (state-account-rlp account))
         (when (bytes= (address-bytes account-address)
                       (address-bytes address))
           (setf target-account account
                 target-storage-trie storage-trie)
           (dolist (entry storage-entries)
             (setf (gethash (hash32-to-hex (car entry))
                            target-storage-values)
                   (cdr entry)))))))
    (unless target-account
      (setf target-account (make-state-account)
            target-storage-trie (make-mpt)))
    (list
     (cons "address" (address-to-hex address))
     (cons "accountProof"
           (mapcar #'bytes-to-hex
                   (mpt-get-proof
                    state-trie
                    (eth-rpc-proof-key-for-address address))))
     (cons "balance" (quantity-to-hex (state-account-balance target-account)))
     (cons "codeHash"
           (hash32-to-hex (state-account-code-hash target-account)))
     (cons "nonce" (quantity-to-hex (state-account-nonce target-account)))
     (cons "storageHash"
           (hash32-to-hex (state-account-storage-root target-account)))
     (cons "storageProof"
           (mapcar
            (lambda (slot)
              (let ((slot-hash (eth-rpc-proof-storage-slot-slot slot)))
                (eth-rpc-storage-proof-object
                 target-storage-trie
                 slot
                 (gethash (hash32-to-hex slot-hash) target-storage-values 0))))
            slots)))))

(defun engine-rpc-handle-eth-get-proof (params store)
  (unless (= 3 (length params))
    (block-validation-fail
     "eth_getProof params must contain address, storage keys, and block id"))
  (let* ((address (eth-rpc-address-param
                   (first params) "eth_getProof" "address"))
         (slots (eth-rpc-proof-storage-slots-param
                 (second params) "eth_getProof"))
         (block (eth-rpc-block-param
                 (list (third params)) store "eth_getProof")))
    (when (and block
               (chain-store-state-available-p
                store (block-hash block)))
      (eth-rpc-build-proof-object store (block-hash block) address slots))))

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
