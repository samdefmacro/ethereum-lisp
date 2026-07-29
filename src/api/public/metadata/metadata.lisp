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
          in '(("admin" . "admin_nodeInfo")
               ("debug" . "debug_getRawHeader")
               ("eth" . "eth_chainId")
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

(defun engine-rpc-handle-net-listening (params &optional admin-backend)
  "Whether this node accepts inbound connections.

Answered from the peering backend rather than hardcoded: a node reporting three
peers from admin_peers and 'not listening' here is worse than one that answers
neither."
  (when params
    (block-validation-fail "net_listening params must be empty"))
  (if (admin-backend-listening admin-backend) t :false))

(defun engine-rpc-handle-net-peer-count (params &optional admin-backend)
  (when params
    (block-validation-fail "net_peerCount params must be empty"))
  (quantity-to-hex (admin-backend-peer-total admin-backend)))

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

(defun engine-rpc-sync-highest-block (store)
  "Return the highest buffered remote block number, or NIL when caught up."
  (let ((highest nil))
    (maphash
     (lambda (key block)
       (declare (ignore key))
       (let ((number (block-header-number (block-header block))))
         (setf highest (if highest (max highest number) number))))
     (memory-chain-store-remote-blocks
      (chain-store-require-memory-store store)))
    highest))

(defun engine-rpc-handle-eth-syncing (params store)
  (when params
    (block-validation-fail "eth_syncing params must be empty"))
  (let ((highest (engine-rpc-sync-highest-block store)))
    (if highest
        (let ((current (chain-store-head-number store)))
          (list (cons "startingBlock" (quantity-to-hex current))
                (cons "currentBlock" (quantity-to-hex current))
                (cons "highestBlock" (quantity-to-hex (max current highest)))))
        :false)))

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
