(in-package #:ethereum-lisp.core)

(defun eth-rpc-address= (left right)
  (and left
       right
       (bytes= (address-bytes left) (address-bytes right))))

(defun eth-rpc-log-address-match-p (log addresses)
  (and (not (eq addresses :empty-address-set))
       (or (null addresses)
           (some (lambda (address)
                   (eth-rpc-address= (log-entry-address log) address))
                 addresses))))

(defun eth-rpc-log-topics-match-p (log topic-filters)
  (let ((topics (log-entry-topics log)))
    (or (null topic-filters)
        (loop for slot in topic-filters
              for index from 0
              always (and (not (eq slot :empty-topic-set))
                          (< index (length topics))
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
      ((json-empty-array-p value)
       :empty-address-set)
      ((json-array-p value)
       (mapcar (lambda (address)
                 (unless (stringp address)
                   (block-validation-fail
                    "~A address filter entries must be addresses" method))
                 (eth-rpc-address-param address method "address"))
               (json-array-values value)))
      (t
       (block-validation-fail
        "~A address filter must be an address or address array" method)))))

(defun eth-rpc-log-filter-topic (value method)
  (cond
      ((null value) nil)
      ((stringp value)
       (list (eth-rpc-hash-param (list value) method "topic")))
      ((json-empty-array-p value)
       :empty-topic-set)
      ((json-array-p value)
       (mapcar (lambda (topic)
                 (unless (stringp topic)
                   (block-validation-fail
                    "~A topic filter entries must be topics" method))
                 (eth-rpc-hash-param (list topic) method "topic"))
               (json-array-values value)))
    (t
     (block-validation-fail
      "~A topic filter slots must be null, a topic, or topic array" method))))

(defun eth-rpc-log-filter-topics (filter method)
  (let ((topics (genesis-object-field filter "topics")))
    (cond
      ((null topics) nil)
      ((json-array-p topics)
       (mapcar (lambda (topic)
                 (eth-rpc-log-filter-topic topic method))
               (json-array-values topics)))
      (t
       (block-validation-fail
        "~A topics filter must be an array" method)))))

(defun eth-rpc-log-filter-from-pending-p (filter)
  (and (not (genesis-object-field-present-p filter "blockHash"))
       (eth-rpc-pending-block-tag-p
        (genesis-object-field filter "fromBlock"))))

(defun eth-rpc-log-filter-blocks (filter store method)
  (cond
    ((genesis-object-field-present-p filter "blockHash")
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
    ((eth-rpc-log-filter-from-pending-p filter)
     (when (genesis-object-field-present-p filter "toBlock")
       (eth-rpc-block-number-param
        (list (genesis-object-field filter "toBlock"))
        store
        method))
     '())
    (t
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
               collect block)))))

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

(defun engine-pending-transaction-filter-visible-hash-p
    (hash store expected-chain-id)
  (let ((transaction (engine-payload-store-pooled-transaction store hash)))
    (or (null transaction)
        (transaction-sender
         transaction
         :expected-chain-id expected-chain-id))))

(defun engine-pending-transaction-filter-changes
    (pending-filter store expected-chain-id)
  (let ((hashes (engine-pending-transaction-filter-hashes pending-filter)))
    (prog1 (eth-rpc-json-array
            (loop for hash in hashes
                  when (engine-pending-transaction-filter-visible-hash-p
                        hash store expected-chain-id)
                    collect (hash32-to-hex hash)))
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

(defun engine-rpc-handle-eth-get-filter-changes (params store config)
  (let* ((method "eth_getFilterChanges")
         (id (eth-rpc-filter-id-param params method))
         (filter (engine-payload-store-log-filter store id)))
    (cond
      ((typep filter 'engine-log-filter)
       (engine-log-filter-changes filter store method))
      ((typep filter 'engine-block-filter)
       (engine-block-filter-changes filter store))
      ((typep filter 'engine-pending-transaction-filter)
       (engine-pending-transaction-filter-changes
        filter store (chain-config-chain-id config)))
      (t
       (block-validation-fail "~A filter not found" method)))))

(defun engine-rpc-handle-eth-uninstall-filter (params store)
  (let* ((method "eth_uninstallFilter")
         (id (eth-rpc-filter-id-param params method)))
    (if (engine-payload-store-uninstall-log-filter store id)
        t
        :false)))

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
