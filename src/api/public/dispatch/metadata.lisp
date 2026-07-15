(in-package #:ethereum-lisp.public-api)

;;;; Public JSON-RPC web3/net/rpc and basic eth metadata dispatch.

(defun engine-rpc-handle-public-metadata-method (context)
  (let ((params (public-rpc-dispatch-context-params context))
        (store (public-rpc-dispatch-context-store context))
        (config (public-rpc-dispatch-context-config context)))
    (cond
      ((public-rpc-dispatch-method-p context "web3_clientVersion")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-web3-client-version params)))
      ((public-rpc-dispatch-method-p context "web3_sha3")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-web3-sha3 params)))
      ((public-rpc-dispatch-method-p context "rpc_modules")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-rpc-modules
         params
         (public-rpc-dispatch-context-allowed-method-p context))))
      ((public-rpc-dispatch-method-p context "net_version")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-net-version
         params
         config
         (public-rpc-dispatch-context-network-id context))))
      ((public-rpc-dispatch-method-p context "net_listening")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-net-listening params)))
      ((public-rpc-dispatch-method-p context "net_peerCount")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-net-peer-count params)))
      ((public-rpc-dispatch-method-p context "eth_chainId")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-chain-id params config)))
      ((public-rpc-dispatch-method-p context "eth_blockNumber")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-block-number params store)))
      ((public-rpc-dispatch-method-p context "eth_protocolVersion")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-protocol-version params)))
      ((public-rpc-dispatch-method-p context "eth_syncing")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-syncing params)))
      ((public-rpc-dispatch-method-p context "eth_accounts")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-accounts params)))
      ((public-rpc-dispatch-method-p context "eth_coinbase")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-coinbase
         params
         :coinbase
         (public-rpc-dispatch-context-coinbase context))))
      ((public-rpc-dispatch-method-p context "eth_mining")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-mining params)))
      ((public-rpc-dispatch-method-p context "eth_hashrate")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-hashrate params)))
      ((public-rpc-dispatch-method-p context "eth_gasPrice")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-gas-price params store)))
      ((public-rpc-dispatch-method-p context "eth_maxPriorityFeePerGas")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-max-priority-fee-per-gas params store)))
      ((public-rpc-dispatch-method-p context "eth_baseFee")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-base-fee params store config)))
      ((public-rpc-dispatch-method-p context "eth_blobBaseFee")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-blob-base-fee params store config)))
      ((public-rpc-dispatch-method-p context "eth_feeHistory")
       (public-rpc-dispatch-response
        context
        (engine-rpc-handle-eth-fee-history params store config))))))
