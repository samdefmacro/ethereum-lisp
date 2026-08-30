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

(defun engine-rpc-sync-highest-block (store &key (now (unix-time)))
  "Return the highest buffered remote block number, or NIL when caught up."
  (let ((highest nil))
    (dolist (block (engine-payload-store-remote-block-list store :now now))
       (let ((number (block-header-number (block-header block))))
         (setf highest (if highest (max highest number) number))))
    highest))

(defun engine-rpc-handle-eth-syncing (params store &optional admin-backend)
  (when params
    (block-validation-fail "eth_syncing params must be empty"))
  (let ((snapshot-function
          (and admin-backend
               ;; ADMIN-BACKEND is defined later in the public API load order.
               ;; Keep this cross-file accessor call late-bound.
               (locally
                   (declare (notinline admin-backend-syncing))
                 (admin-backend-syncing admin-backend)))))
    (if snapshot-function
        (funcall snapshot-function)
        (let ((highest (engine-rpc-sync-highest-block store))
              (current (chain-store-head-number store)))
          (if (and highest (> highest current))
              (list (cons "startingBlock" (quantity-to-hex current))
                    (cons "currentBlock" (quantity-to-hex current))
                    (cons "highestBlock" (quantity-to-hex highest)))
              :false)))))

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

(defconstant +eth-capabilities-log-retention-blocks+ #x23dbb0)

(defun eth-capabilities-resource (oldest-block &key retention-blocks)
  (append
   (when retention-blocks
     (list
      (cons "deleteStrategy"
            (list (cons "retentionBlocks"
                        (quantity-to-hex retention-blocks))
                  (cons "type" "window")))))
   (list (cons "disabled" :false)
         (cons "oldestBlock" (quantity-to-hex oldest-block)))))

(defun engine-rpc-handle-eth-capabilities (params store)
  "Describe the historical data ranges this node can conservatively serve."
  (when params
    (block-validation-fail "eth_capabilities params must be empty"))
  (let ((head (chain-store-latest-block store)))
    (unless head
      (block-validation-fail "eth_capabilities requires a head block"))
    (let* ((header (block-header head))
           (head-number (block-header-number header))
           (archive-resource (eth-capabilities-resource 0))
           (oldest-log-block
             (max 0 (- head-number
                       +eth-capabilities-log-retention-blocks+))))
      (list
       (cons "blocks" archive-resource)
       (cons "head"
             (list (cons "hash" (hash32-to-hex (block-hash head)))
                   (cons "number" (quantity-to-hex head-number))))
       (cons "logs"
             (eth-capabilities-resource
              oldest-log-block
              :retention-blocks
              +eth-capabilities-log-retention-blocks+))
       (cons "receipts" archive-resource)
       (cons "state" archive-resource)
       (cons "stateproofs" archive-resource)
       (cons "tx" archive-resource)))))

(defparameter +eth-config-precompiles+
  '((1 . "ECREC")
    (2 . "SHA256")
    (3 . "RIPEMD160")
    (4 . "ID")
    (5 . "MODEXP")
    (6 . "BN254_ADD")
    (7 . "BN254_MUL")
    (8 . "BN254_PAIRING")
    (9 . "BLAKE2F")
    (10 . "KZG_POINT_EVALUATION")
    (11 . "BLS12_G1ADD")
    (12 . "BLS12_G1MSM")
    (13 . "BLS12_G2ADD")
    (14 . "BLS12_G2MSM")
    (15 . "BLS12_PAIRING_CHECK")
    (16 . "BLS12_MAP_FP_TO_G1")
    (17 . "BLS12_MAP_FP2_TO_G2")
    (256 . "P256VERIFY")))

(defun eth-config-precompile-active-p
    (number config block-number timestamp)
  (cond
    ((<= number 4) t)
    ((<= 5 number 8)
     (chain-config-byzantium-p config block-number))
    ((= number 9)
     (chain-config-istanbul-p config block-number))
    ((= number 10)
     (chain-config-cancun-p config block-number timestamp))
    ((<= 11 number 17)
     (chain-config-prague-p config block-number timestamp))
    ((= number 256)
     (chain-config-osaka-p config block-number timestamp))))

(defun eth-config-precompiles-object
    (config block-number timestamp)
  (loop for (number . name) in +eth-config-precompiles+
        when (eth-config-precompile-active-p
              number config block-number timestamp)
          collect (cons name (address-to-hex (precompile-address number)))))

(defun eth-config-system-contracts-object
    (config block-number timestamp)
  (when (chain-config-cancun-p config block-number timestamp)
    (append
     (list
      (cons "BEACON_ROOTS_ADDRESS"
            "0x000f3df6d732807ef1319fb7b8bb8522d0beac02"))
     (when (chain-config-prague-p config block-number timestamp)
       (append
        (list
         (cons "CONSOLIDATION_REQUEST_PREDEPLOY_ADDRESS"
               "0x0000bbddc7ce488642fb579f8b00f3a590007251"))
        (when (chain-config-deposit-contract-address config)
          (list
           (cons "DEPOSIT_CONTRACT_ADDRESS"
                 (address-to-hex
                  (chain-config-deposit-contract-address config)))))
        (list
         (cons "HISTORY_STORAGE_ADDRESS"
               "0x0000f90827f1c53a10cb7a02335b175320002935")
         (cons "WITHDRAWAL_REQUEST_PREDEPLOY_ADDRESS"
               "0x00000961ef480eb55e80d19ad83579a64c007002")))))))

(defun eth-config-object
    (config genesis-hash genesis-timestamp block-number activation-time)
  (multiple-value-bind (target-gas max-gas update-fraction)
      (chain-config-blob-schedule config block-number activation-time)
    (let ((fork-id
            (ethereum-lisp.eth-wire:chain-config-eth-fork-id
             config (hash32-bytes genesis-hash) block-number activation-time
             genesis-timestamp)))
      (append
       (list
        (cons "activationTime" activation-time)
        (cons "blobSchedule"
              (list
               (cons "baseFeeUpdateFraction" update-fraction)
               (cons "max" (/ max-gas +blob-gas-per-blob+))
               (cons "target" (/ target-gas +blob-gas-per-blob+))))
        (cons "chainId" (quantity-to-hex (chain-config-chain-id config)))
        (cons
         "forkId"
         (bytes-to-hex
          (ethereum-lisp.eth-wire:eth-fork-id-hash fork-id)))
        (cons "precompiles"
              (eth-config-precompiles-object
               config block-number activation-time)))
       (let ((system-contracts
               (eth-config-system-contracts-object
                config block-number activation-time)))
         (when system-contracts
           (list (cons "systemContracts" system-contracts))))))))

(defun engine-rpc-handle-eth-config (params store config)
  (when params
    (block-validation-fail "eth_config params must be empty"))
  (let* ((genesis (chain-store-block-by-number store 0))
         (head (chain-store-latest-block store)))
    (unless (and genesis head)
      (block-validation-fail "eth_config requires genesis and head blocks"))
    (let* ((genesis-header (block-header genesis))
           (head-header (block-header head))
           (genesis-time (block-header-timestamp genesis-header))
           (head-time (block-header-timestamp head-header))
           (head-number (block-header-number head-header))
           (fork-times
             (cons 0
                   (chain-config-time-fork-schedule config genesis-time)))
           (current-time
             (or (car (last (remove-if (lambda (time) (> time head-time))
                                       fork-times)))
                 0))
           (future-times
             (remove-if-not (lambda (time) (> time head-time)) fork-times))
           (next-time (first future-times))
           (last-time (car (last future-times))))
      (labels ((object (activation-time)
                 (and activation-time
                      (eth-config-object
                       config (block-hash genesis) genesis-time
                       head-number activation-time))))
        (list (cons "current" (object current-time))
              (cons "next" (object next-time))
              (cons "last" (object last-time)))))))
