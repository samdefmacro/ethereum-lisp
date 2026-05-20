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
