(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-contract-creation-address (transaction sender)
  (when (and (null (transaction-to transaction)) sender)
    (let* ((hash (keccak-256
                  (rlp-encode
                   (make-rlp-list (address-bytes sender)
                                  (transaction-nonce transaction)))))
           (bytes (make-byte-vector 20)))
      (replace bytes hash :start2 12)
      (make-address bytes))))

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
     (cons "topics" (eth-rpc-json-array
                     (mapcar #'hash32-to-hex
                             (log-entry-topics log))))
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
                 (nth-value 2
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
          (cons "logs" (eth-rpc-json-array logs))
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

(defun engine-rpc-handle-eth-get-transaction-receipt (params store config)
  (let* ((hash (eth-rpc-hash-param
                params "eth_getTransactionReceipt" "transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (when location
      (eth-rpc-receipt-object
       location
       :expected-chain-id (chain-config-chain-id config)))))

(defun engine-rpc-handle-eth-get-block-receipts (params store config)
  (if (eth-rpc-pending-block-id-param-p params "eth_getBlockReceipts")
      nil
      (let ((block (eth-rpc-block-param params store "eth_getBlockReceipts")))
        (eth-rpc-block-receipts-object
         block
         :expected-chain-id (chain-config-chain-id config)))))
