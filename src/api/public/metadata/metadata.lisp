(in-package #:ethereum-lisp.public-api)

(defun engine-rpc-handle-web3-client-version (params)
  (when params
    (block-validation-fail "web3_clientVersion params must be empty"))
  (let ((version (engine-rpc-client-version)))
    (format nil "~A/~A/~A/~A"
            (json-rpc-required-field version "name")
            (json-rpc-required-field version "version")
            (json-rpc-required-field version "code")
            (json-rpc-required-field version "commit"))))

(defun engine-rpc-handle-web3-sha3 (params)
  (unless (= 1 (length params))
    (block-validation-fail "web3_sha3 params must contain exactly one data value"))
  (bytes-to-hex (keccak-256 (json-rpc-bytes (first params) "web3_sha3 data"))))

(defun engine-rpc-handle-rpc-modules (params allowed-method-p)
  (when params
    (block-validation-fail "rpc_modules params must be empty"))
  (loop for (module . probe-method)
          in '(("eth" . "eth_chainId")
               ("net" . "net_version")
               ("rpc" . "rpc_modules")
               ("txpool" . "txpool_status")
               ("web3" . "web3_clientVersion"))
        when (funcall allowed-method-p probe-method)
          collect (cons module "1.0")))

(defun engine-rpc-handle-net-version (params config network-id)
  (when params
    (block-validation-fail "net_version params must be empty"))
  (write-to-string (or network-id (chain-config-chain-id config)) :base 10))

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

(defun engine-rpc-handle-eth-coinbase (params &key coinbase)
  (when params
    (block-validation-fail "eth_coinbase params must be empty"))
  (address-to-hex (or coinbase (zero-address))))

(defun engine-rpc-handle-eth-mining (params)
  (when params
    (block-validation-fail "eth_mining params must be empty"))
  :false)

(defun engine-rpc-handle-eth-hashrate (params)
  (when params
    (block-validation-fail "eth_hashrate params must be empty"))
  (quantity-to-hex 0))
