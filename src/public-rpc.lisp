(in-package #:ethereum-lisp.core)

(defun engine-rpc-handle-public-method
    (id method params store config
     &key network-id coinbase
          (allowed-method-p #'engine-rpc-any-method-p)
          allow-unprotected-transactions-p
          txpool-price-limit
          txpool-price-bump-percent
          txpool-account-slot-limit
          txpool-global-slot-limit
          txpool-account-queue-limit
          txpool-global-queue-limit
          txpool-local-addresses
          txpool-no-local-exemptions-p
          txpool-lifetime-seconds
          (txpool-now 0))
  (eth-rpc-remove-expired-txpool-transactions
   store
   config
   txpool-lifetime-seconds
   txpool-now
   txpool-local-addresses
   txpool-no-local-exemptions-p)
  (cond
    ((string= method "web3_clientVersion")
     (engine-rpc-response
      id :result (engine-rpc-handle-web3-client-version params)))
    ((string= method "web3_sha3")
     (engine-rpc-response
      id :result (engine-rpc-handle-web3-sha3 params)))
    ((string= method "rpc_modules")
     (engine-rpc-response
      id :result (engine-rpc-handle-rpc-modules params allowed-method-p)))
    ((string= method "net_version")
     (engine-rpc-response
      id :result (engine-rpc-handle-net-version params config network-id)))
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
      id :result (engine-rpc-handle-eth-coinbase
                  params
                  :coinbase coinbase)))
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
      id
      :result
      (engine-rpc-handle-eth-get-transaction-count params store config)))
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
      id :result
      (engine-rpc-handle-eth-get-header-by-number params store config)))
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
       params store config)))
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
      id :result (engine-rpc-handle-eth-get-filter-changes
                  params store config)))
    ((string= method "eth_uninstallFilter")
     (engine-rpc-response
      id :result (engine-rpc-handle-eth-uninstall-filter params store)))
    ((string= method "eth_getRawTransactionByBlockNumberAndIndex")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-raw-transaction-by-block-number-and-index
       params store config)))
    ((string= method "eth_getRawTransactionByBlockHashAndIndex")
     (engine-rpc-response
      id
      :result
      (engine-rpc-handle-eth-get-raw-transaction-by-block-hash-and-index
       params store config)))
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
      (engine-rpc-handle-eth-send-raw-transaction
       params
       store
       config
       :allow-unprotected-transactions-p
       allow-unprotected-transactions-p
       :txpool-price-limit
       txpool-price-limit
       :txpool-price-bump-percent
       txpool-price-bump-percent
       :txpool-account-slot-limit
       txpool-account-slot-limit
       :txpool-global-slot-limit
       txpool-global-slot-limit
       :txpool-account-queue-limit
       txpool-account-queue-limit
       :txpool-global-queue-limit
       txpool-global-queue-limit
       :txpool-local-addresses
       txpool-local-addresses
       :txpool-no-local-exemptions-p
       txpool-no-local-exemptions-p
       :txpool-now
       txpool-now)))
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
