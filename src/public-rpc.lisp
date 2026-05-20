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
