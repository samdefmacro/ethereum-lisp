(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-transaction-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x55)))
           (log-address
             (make-address (make-byte-vector 20 :initial-element #x66)))
           (topic-1 (make-hash32
                     (make-byte-vector 32 :initial-element #x11)))
           (topic-2 (make-hash32
                     (make-byte-vector 32 :initial-element #x22)))
           (tx-1 (fixture-sign-legacy-transaction
                  (make-legacy-transaction
                   :nonce 5
                   :gas-price 8
                   :gas-limit 21000
                   :to recipient
                   :value 7)
                  1
                  1))
           (tx-2 (fixture-sign-legacy-transaction
                  (make-legacy-transaction
                   :nonce 6
                   :gas-price 9
                   :gas-limit 23000
                   :to recipient
                   :value 8)
                  1
                  1))
           (receipt-1
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic-1)
                           :data #(1)))))
           (receipt-2
             (make-receipt
              :status 1
              :cumulative-gas-used 44000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic-2)
                           :data #(2 3)))))
           (block
             (make-block
              :header (make-block-header :number 15
                                         :timestamp 150
                                         :gas-limit 30000000
                                         :base-fee-per-gas 6)
              :transactions (list tx-1 tx-2)
              :receipts (list receipt-1 receipt-2)))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (tx-2-hash-hex (hash32-to-hex (transaction-hash tx-2)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((receipt-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":60,"
                  "\"method\":\"eth_getTransactionReceipt\","
                  "\"params\":[\"" tx-2-hash-hex "\"]}")
                 store
                 config)))
             (receipt-result (field receipt-response "result"))
             (logs (field receipt-result "logs"))
             (log (first logs))
             (removed-entry (assoc "removed" log :test #'string=))
             (topics (field log "topics"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":61,"
                  "\"method\":\"eth_getTransactionReceipt\","
                  "\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\"]}")
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":62,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= tx-2-hash-hex
                     (field receipt-result "transactionHash")))
        (is (string= (quantity-to-hex 1)
                     (field receipt-result "transactionIndex")))
        (is (string= block-hash-hex (field receipt-result "blockHash")))
        (is (string= (quantity-to-hex 15)
                     (field receipt-result "blockNumber")))
        (is (string= (address-to-hex recipient)
                     (field receipt-result "to")))
        (is (string= (quantity-to-hex 44000)
                     (field receipt-result "cumulativeGasUsed")))
        (is (string= (quantity-to-hex 23000)
                     (field receipt-result "gasUsed")))
        (is (null (field receipt-result "contractAddress")))
        (is (= 1 (length logs)))
        (is (string= (address-to-hex log-address)
                     (field log "address")))
        (is (= 1 (length topics)))
        (is (string= (hash32-to-hex topic-2) (first topics)))
        (is (string= "0x0203" (field log "data")))
        (is (string= (quantity-to-hex 1) (field log "logIndex")))
        (is removed-entry)
        (is (null (cdr removed-entry)))
        (is (stringp (field receipt-result "logsBloom")))
        (is (string= (address-to-hex (transaction-sender tx-2))
                     (field receipt-result "from")))
        (is (string= (quantity-to-hex 0)
                     (field receipt-result "type")))
        (is (string= (quantity-to-hex 9)
                     (field receipt-result "effectiveGasPrice")))
        (is (string= (quantity-to-hex 1)
                     (field receipt-result "status")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-block-receipts
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x77)))
           (log-address
             (make-address (make-byte-vector 20 :initial-element #x88)))
           (topic (make-hash32
                   (make-byte-vector 32 :initial-element #x33)))
           (tx-1 (fixture-sign-legacy-transaction
                  (make-legacy-transaction
                   :nonce 7
                   :gas-price 8
                   :gas-limit 21000
                   :to recipient
                   :value 9)
                  1
                  1))
           (tx-2 (fixture-sign-legacy-transaction
                  (make-legacy-transaction
                   :nonce 8
                   :gas-price 9
                   :gas-limit 23000
                   :to recipient
                   :value 10)
                  1
                  1))
           (receipt-1
             (make-receipt :status 1
                           :cumulative-gas-used 21000))
           (receipt-2
             (make-receipt
              :status 1
              :cumulative-gas-used 44000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic)
                           :data #(9)))))
           (block
             (make-block
              :header (make-block-header :number 16
                                         :timestamp 160
                                         :gas-limit 30000000
                                         :base-fee-per-gas 6)
              :transactions (list tx-1 tx-2)
              :receipts (list receipt-1 receipt-2)))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((latest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":63,\"method\":\"eth_getBlockReceipts\",\"params\":[\"latest\"]}"
                 store
                 config)))
             (latest-receipts (field latest-response "result"))
             (first-receipt (first latest-receipts))
             (second-receipt (second latest-receipts))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":64,"
                  "\"method\":\"eth_getBlockReceipts\","
                  "\"params\":[\"" block-hash-hex "\"]}")
                 store
                 config)))
             (hash-receipts (field hash-response "result"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":65,\"method\":\"eth_getBlockReceipts\",\"params\":[\"0x63\"]}"
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":67,\"method\":\"eth_getBlockReceipts\",\"params\":[\"pending\"]}"
                 store
                 config)))
             (pending-object-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":68,\"method\":\"eth_getBlockReceipts\",\"params\":[{\"blockNumber\":\"pending\"}]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":66,\"method\":\"eth_getBlockReceipts\",\"params\":[]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (= 2 (length latest-receipts)))
        (is (= 2 (length hash-receipts)))
        (is (string= (hash32-to-hex (transaction-hash tx-1))
                     (field first-receipt "transactionHash")))
        (is (string= (hash32-to-hex (transaction-hash tx-2))
                     (field second-receipt "transactionHash")))
        (is (string= block-hash-hex (field second-receipt "blockHash")))
        (is (string= (quantity-to-hex 16)
                     (field second-receipt "blockNumber")))
        (is (string= (quantity-to-hex 1)
                     (field second-receipt "transactionIndex")))
        (is (string= (quantity-to-hex 23000)
                     (field second-receipt "gasUsed")))
        (is (string= (address-to-hex (transaction-sender tx-2))
                     (field second-receipt "from")))
        (is (= 1 (length (field second-receipt "logs"))))
        (is (string= (quantity-to-hex 0)
                     (field (first (field second-receipt "logs"))
                            "logIndex")))
        (is (string= (field second-receipt "transactionHash")
                     (field (second hash-receipts)
                            "transactionHash")))
        (is (null (field missing-response "result")))
        (is (null (field pending-response "result")))
        (is (null (field pending-object-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-logs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x44)))
           (address-a
             (make-address (make-byte-vector 20 :initial-element #xaa)))
           (address-b
             (make-address (make-byte-vector 20 :initial-element #xbb)))
           (topic-a (make-hash32
                     (make-byte-vector 32 :initial-element #x11)))
           (topic-b (make-hash32
                     (make-byte-vector 32 :initial-element #x22)))
           (topic-c (make-hash32
                     (make-byte-vector 32 :initial-element #x33)))
           (tx-1 (make-legacy-transaction :nonce 1
                                          :gas-price 8
                                          :gas-limit 21000
                                          :to recipient
                                          :value 1))
           (tx-2 (make-legacy-transaction :nonce 2
                                          :gas-price 9
                                          :gas-limit 22000
                                          :to recipient
                                          :value 2))
           (tx-3 (make-legacy-transaction :nonce 3
                                          :gas-price 10
                                          :gas-limit 23000
                                          :to recipient
                                          :value 3))
           (tx-4 (make-legacy-transaction :nonce 4
                                          :gas-price 11
                                          :gas-limit 24000
                                          :to recipient
                                          :value 4))
           (receipt-1
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address address-a
                           :topics (list topic-a topic-b)
                           :data #(1 2)))))
           (receipt-2
             (make-receipt
              :status 1
              :cumulative-gas-used 43000
              :logs (list (make-log-entry
                           :address address-b
                           :topics (list topic-a topic-c)
                           :data #(3)))))
           (receipt-3
             (make-receipt
              :status 1
              :cumulative-gas-used 23000
              :logs (list (make-log-entry
                           :address address-a
                           :topics (list topic-a topic-c)
                           :data #(4 5)))))
           (receipt-4
             (make-receipt
              :status 1
              :cumulative-gas-used 24000
              :logs (list (make-log-entry
                           :address address-a
                           :topics (list topic-a topic-b)
                           :data #(6)))))
           (block-1
             (make-block
              :header (make-block-header :number 40
                                         :timestamp 400
                                         :gas-limit 30000000)
              :transactions (list tx-1 tx-2)
              :receipts (list receipt-1 receipt-2)))
           (block-2
             (make-block
              :header (make-block-header :number 41
                                         :timestamp 410
                                         :gas-limit 30000000)
              :transactions (list tx-3)
              :receipts (list receipt-3)))
           (block-3
             (make-block
              :header (make-block-header :number 42
                                         :timestamp 420
                                         :gas-limit 30000000)
              :transactions (list tx-4)
              :receipts (list receipt-4)))
           (config (make-chain-config))
           (block-2-hash-hex (hash32-to-hex (block-hash block-2))))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (engine-payload-store-put-block store block-2 :state-available-p t)
      (let* ((range-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":67,"
                  "\"method\":\"eth_getLogs\","
                  "\"params\":[{\"fromBlock\":\"0x28\","
                  "\"toBlock\":\"0x28\","
                  "\"address\":\"" (address-to-hex address-a) "\","
                  "\"topics\":[\"" (hash32-to-hex topic-a) "\"]}]}")
                 store
                 config)))
             (range-logs (field range-response "result"))
             (range-log (first range-logs))
             (range-topics (field range-log "topics"))
             (block-hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":68,"
                  "\"method\":\"eth_getLogs\","
                  "\"params\":[{\"blockHash\":\"" block-2-hash-hex "\","
                  "\"topics\":[null,\"" (hash32-to-hex topic-c) "\"]}]}")
                 store
                 config)))
             (block-hash-logs (field block-hash-response "result"))
             (empty-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":69,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x28\","
                 "\"toBlock\":\"0x29\","
                 "\"address\":\"" (address-to-hex recipient) "\"}]}")
                store
                config))
             (pending-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":169,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"pending\",\"toBlock\":\"pending\"}]}"
                store
                config))
             (invalid-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"0x29\",\"toBlock\":\"0x28\"}]}"
                 store
                 config)))
             (invalid-range-error
               (field invalid-range-response "error"))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":71,\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"0x1234\"}]}"
                 store
                 config)))
             (invalid-address-error
               (field invalid-address-response "error")))
        (is (= 1 (length range-logs)))
        (is (string= (address-to-hex address-a)
                     (field range-log "address")))
        (is (string= "0x0102" (field range-log "data")))
        (is (string= (hash32-to-hex (block-hash block-1))
                     (field range-log "blockHash")))
        (is (string= (quantity-to-hex 40)
                     (field range-log "blockNumber")))
        (is (string= (hash32-to-hex (transaction-hash tx-1))
                     (field range-log "transactionHash")))
        (is (string= (quantity-to-hex 0)
                     (field range-log "transactionIndex")))
        (is (string= (quantity-to-hex 0)
                     (field range-log "logIndex")))
        (is (= 2 (length range-topics)))
        (is (string= (hash32-to-hex topic-a) (first range-topics)))
        (is (string= (hash32-to-hex topic-b) (second range-topics)))
        (is (= 1 (length block-hash-logs)))
        (is (string= block-2-hash-hex
                     (field (first block-hash-logs) "blockHash")))
        (is (string= (quantity-to-hex 41)
                     (field (first block-hash-logs) "blockNumber")))
        (is (search "\"result\":[]" empty-json))
        (is (search "\"result\":[]" pending-json))
        (is (= -32602 (field invalid-range-error "code")))
        (is (= -32602 (field invalid-address-error "code"))))
      (let* ((new-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":72,"
                  "\"method\":\"eth_newFilter\","
                  "\"params\":[{\"fromBlock\":\"0x28\","
                  "\"address\":\"" (address-to-hex address-a) "\","
                  "\"topics\":[\"" (hash32-to-hex topic-a) "\"]}]}")
                 store
                 config)))
             (filter-id (field new-filter-response "result"))
             (pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":172,"
                  "\"method\":\"eth_newFilter\","
                  "\"params\":[{\"fromBlock\":\"pending\","
                  "\"address\":\"" (address-to-hex address-a) "\","
                  "\"topics\":[\"" (hash32-to-hex topic-a) "\"]}]}")
                 store
                 config)))
             (pending-filter-id (field pending-filter-response "result"))
             (pending-filter-logs-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":173,"
                 "\"method\":\"eth_getFilterLogs\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (filter-logs-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":73,"
                  "\"method\":\"eth_getFilterLogs\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (filter-logs (field filter-logs-response "result"))
             (first-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":77,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (first-changes (field first-changes-response "result"))
             (second-changes-response
               (progn
                 (engine-payload-store-put-block
                  store block-3 :state-available-p t)
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":78,"
                    "\"method\":\"eth_getFilterChanges\","
                    "\"params\":[\"" filter-id "\"]}")
                   store
                   config))))
             (second-changes (field second-changes-response "result"))
             (pending-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":174,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" pending-filter-id "\"]}")
                 store
                 config)))
             (pending-changes (field pending-changes-response "result"))
             (empty-changes-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":79,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (uninstall-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":74,"
                  "\"method\":\"eth_uninstallFilter\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (missing-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":75,"
                  "\"method\":\"eth_getFilterLogs\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (missing-filter-error (field missing-filter-response "error"))
             (uninstall-missing-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":76,"
                 "\"method\":\"eth_uninstallFilter\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (uninstall-missing-response
               (parse-json uninstall-missing-json)))
        (is (string= (quantity-to-hex 1) filter-id))
        (is (string= (quantity-to-hex 2) pending-filter-id))
        (is (search "\"result\":[]" pending-filter-logs-json))
        (is (= 2 (length filter-logs)))
        (is (string= (quantity-to-hex 40)
                     (field (first filter-logs) "blockNumber")))
        (is (string= (quantity-to-hex 41)
                     (field (second filter-logs) "blockNumber")))
        (is (= 2 (length first-changes)))
        (is (string= (quantity-to-hex 40)
                     (field (first first-changes) "blockNumber")))
        (is (string= (quantity-to-hex 41)
                     (field (second first-changes) "blockNumber")))
        (is (= 1 (length second-changes)))
        (is (string= (quantity-to-hex 42)
                     (field (first second-changes) "blockNumber")))
        (is (= 1 (length pending-changes)))
        (is (string= (quantity-to-hex 42)
                     (field (first pending-changes) "blockNumber")))
        (is (search "\"result\":[]" empty-changes-json))
        (is (eq t (field uninstall-response "result")))
        (is (= -32602 (field missing-filter-error "code")))
        (is (null (field uninstall-missing-response "result")))
        (is (search "\"result\":false" uninstall-missing-json))))))

(deftest eth-rpc-log-filter-records-same-height-reorg-changes
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json (engine-rpc-handle-request-json json store config)))
           (forkchoice-json (id head)
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
              ",\"method\":\"engine_forkchoiceUpdatedV1\","
              "\"params\":[{\"headBlockHash\":\"" (hash32-to-hex head)
              "\",\"safeBlockHash\":\"" (hash32-to-hex (zero-hash32))
              "\",\"finalizedBlockHash\":\"" (hash32-to-hex (zero-hash32))
              "\"}]}")))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (log-address
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (topic
             (hash32-from-hex
              "0x2222222222222222222222222222222222222222222222222222222222222222"))
           (old-transaction
             (make-legacy-transaction :nonce 0
                                      :gas-price 2
                                      :gas-limit 21000
                                      :to recipient
                                      :value 3))
           (new-transaction
             (make-legacy-transaction :nonce 1
                                      :gas-price 3
                                      :gas-limit 21000
                                      :to recipient
                                      :value 4))
           (old-receipt
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic)
                           :data #(1)))))
           (new-receipt
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic)
                           :data #(2)))))
           (genesis
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :gas-limit 30000000
                                 :timestamp 0
                                 :extra-data #(0))))
           (old-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(1))
              :transactions (list old-transaction)
              :receipts (list old-receipt)))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(2))
              :transactions (list new-transaction)
              :receipts (list new-receipt))))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (engine-payload-store-put-block
       store old-canonical-child :state-available-p t)
      (let* ((filter-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":89,"
                 "\"method\":\"eth_newFilter\","
                 "\"params\":[{\"fromBlock\":\"0x0\","
                 "\"address\":\"" (address-to-hex log-address) "\","
                 "\"topics\":[\"" (hash32-to-hex topic) "\"]}]}")
                store
                config))
             (filter-id (field filter-response "result"))
             (future-filter-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":90,"
                 "\"method\":\"eth_newFilter\","
                 "\"params\":[{\"fromBlock\":\"0x2\","
                 "\"address\":\"" (address-to-hex log-address) "\","
                 "\"topics\":[\"" (hash32-to-hex topic) "\"]}]}")
                store
                config))
             (future-filter-id (field future-filter-response "result"))
             (initial-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":91,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (initial-logs (field initial-response "result")))
        (is (= 1 (length initial-logs)))
        (is (string= "0x01" (field (first initial-logs) "data")))
        (is (null (field (first initial-logs) "removed")))
        (engine-payload-store-put-block
         store new-canonical-child :state-available-p t)
        (let* ((forkchoice-response
                 (request (forkchoice-json 92 (block-hash new-canonical-child))
                          store
                          config))
               (changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":93,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (future-changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":94,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" future-filter-id "\"]}")
                  store
                  config))
               (empty-changes-json
                 (engine-rpc-handle-request-json
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":95,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (payload-status
                 (field (field forkchoice-response "result")
                        "payloadStatus"))
               (logs (field changes-response "result"))
               (future-logs (field future-changes-response "result"))
               (removed-log (first logs))
               (added-log (second logs)))
          (is (string= +payload-status-valid+
                       (field payload-status "status")))
          (is (= 2 (length logs)))
          (is (string= "0x01" (field removed-log "data")))
          (is (eq t (field removed-log "removed")))
          (is (string= (hash32-to-hex (block-hash old-canonical-child))
                       (field removed-log "blockHash")))
          (is (string= "0x02" (field added-log "data")))
          (is (null (field added-log "removed")))
          (is (string= (hash32-to-hex (block-hash new-canonical-child))
                       (field added-log "blockHash")))
          (is (null future-logs))
          (is (search "\"result\":[]" empty-changes-json)))))))

(deftest eth-rpc-log-topic-wildcard-requires-position
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x44)))
           (address
             (make-address (make-byte-vector 20 :initial-element #xaa)))
           (topic-a
             (make-hash32 (make-byte-vector 32 :initial-element #x11)))
           (topic-b
             (make-hash32 (make-byte-vector 32 :initial-element #x22)))
           (transaction
             (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 0))
           (receipt
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address address
                           :topics (list topic-a)
                           :data #(1)))))
           (block
             (make-block
              :header
              (make-block-header :number 1
                                 :gas-limit 30000000
                                 :timestamp 12)
              :transactions (list transaction)
              :receipts (list receipt))))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((first-position-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":96,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x1\","
                 "\"toBlock\":\"0x1\","
                 "\"topics\":[null]}]}")
                store
                config))
             (missing-second-position-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":97,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x1\","
                 "\"toBlock\":\"0x1\","
                 "\"topics\":[null,\"" (hash32-to-hex topic-b) "\"]}]}")
                store
                config))
             (empty-topic-set-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":98,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x1\","
                 "\"toBlock\":\"0x1\","
                 "\"topics\":[[]]}]}")
                store
                config))
             (empty-address-set-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":99,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x1\","
                 "\"toBlock\":\"0x1\","
                 "\"address\":[]}]}")
                store
                config))
             (first-position-logs
               (field first-position-response "result"))
             (missing-second-position-logs
               (field missing-second-position-response "result"))
             (empty-topic-set-logs
               (field empty-topic-set-response "result"))
             (empty-address-set-logs
               (field empty-address-set-response "result")))
        (is (= 1 (length first-position-logs)))
        (is (string= (address-to-hex address)
                     (field (first first-position-logs) "address")))
        (is (null missing-second-position-logs))
        (is (null empty-topic-set-logs))
        (is (null empty-address-set-logs))))))

(deftest eth-rpc-log-filter-defaults-to-latest
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x44)))
           (address
             (make-address (make-byte-vector 20 :initial-element #xaa)))
           (topic
             (make-hash32 (make-byte-vector 32 :initial-element #x11)))
           (tx-1
             (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 0))
           (tx-2
             (make-legacy-transaction :nonce 1
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 0))
           (tx-3
             (make-legacy-transaction :nonce 2
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 0))
           (block-1
             (make-block
              :header
              (make-block-header :number 1
                                 :gas-limit 30000000
                                 :timestamp 12)
              :transactions (list tx-1)
              :receipts
              (list
               (make-receipt
                :status 1
                :cumulative-gas-used 21000
                :logs (list (make-log-entry
                             :address address
                             :topics (list topic)
                             :data #(1)))))))
           (block-2
             (make-block
              :header
              (make-block-header :number 2
                                 :gas-limit 30000000
                                 :timestamp 24)
              :transactions (list tx-2)
              :receipts
              (list
               (make-receipt
                :status 1
                :cumulative-gas-used 21000
                :logs (list (make-log-entry
                             :address address
                             :topics (list topic)
                             :data #(2)))))))
           (block-3
             (make-block
              :header
              (make-block-header :number 3
                                 :gas-limit 30000000
                                 :timestamp 36)
              :transactions (list tx-3)
              :receipts
              (list
               (make-receipt
                :status 1
                :cumulative-gas-used 21000
                :logs (list (make-log-entry
                             :address address
                             :topics (list topic)
                             :data #(3))))))))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (engine-payload-store-put-block store block-2 :state-available-p t)
      (let* ((default-logs-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":98,\"method\":\"eth_getLogs\",\"params\":[{}]}"
                store
                config))
             (default-logs
               (field default-logs-response "result"))
             (new-filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"eth_newFilter\",\"params\":[{}]}"
                store
                config))
             (filter-id (field new-filter-response "result"))
             (initial-changes-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":100,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (initial-changes
               (field initial-changes-response "result")))
        (is (= 1 (length default-logs)))
        (is (string= "0x02" (field (first default-logs) "data")))
        (is (string= (quantity-to-hex 2)
                     (field (first default-logs) "blockNumber")))
        (is (null initial-changes))
        (engine-payload-store-put-block store block-3 :state-available-p t)
        (let* ((later-changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":101,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (later-changes
                 (field later-changes-response "result")))
          (is (= 1 (length later-changes)))
          (is (string= "0x03" (field (first later-changes) "data")))
          (is (string= (quantity-to-hex 3)
                       (field (first later-changes) "blockNumber"))))))))

(deftest eth-rpc-block-filter
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (block-1
             (make-block
              :header (make-block-header :number 7
                                         :timestamp 70
                                         :gas-limit 30000000)))
           (block-2
             (make-block
              :header (make-block-header :number 8
                                         :timestamp 80
                                         :gas-limit 30000000)))
           (block-3
             (make-block
              :header (make-block-header :number 10
                                         :timestamp 100
                                         :gas-limit 30000000))))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (let* ((new-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":80,\"method\":\"eth_newBlockFilter\"}"
                 store
                 config)))
             (filter-id (field new-filter-response "result"))
             (initial-changes-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":81,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (first-changes-response
               (progn
                 (engine-payload-store-put-block
                  store block-2 :state-available-p t)
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":82,"
                    "\"method\":\"eth_getFilterChanges\","
                    "\"params\":[\"" filter-id "\"]}")
                   store
                   config))))
             (first-changes (field first-changes-response "result"))
             (empty-changes-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":83,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (second-changes-response
               (progn
                 (engine-payload-store-put-block
                  store block-3 :state-available-p t)
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":84,"
                    "\"method\":\"eth_getFilterChanges\","
                    "\"params\":[\"" filter-id "\"]}")
                   store
                   config))))
             (second-changes (field second-changes-response "result"))
             (get-logs-error-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":85,"
                  "\"method\":\"eth_getFilterLogs\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (uninstall-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":86,"
                  "\"method\":\"eth_uninstallFilter\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (missing-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":87,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (invalid-new-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":88,\"method\":\"eth_newBlockFilter\",\"params\":[\"unexpected\"]}"
                 store
                 config))))
        (is (string= (quantity-to-hex 1) filter-id))
        (is (search "\"result\":[]" initial-changes-json))
        (is (= 1 (length first-changes)))
        (is (string= (hash32-to-hex (block-hash block-2))
                     (first first-changes)))
        (is (search "\"result\":[]" empty-changes-json))
        (is (= 1 (length second-changes)))
        (is (string= (hash32-to-hex (block-hash block-3))
                     (first second-changes)))
        (is (= -32602
               (field (field get-logs-error-response "error") "code")))
        (is (eq t (field uninstall-response "result")))
        (is (= -32602
               (field (field missing-changes-response "error") "code")))
        (is (= -32602
               (field (field invalid-new-filter-response "error")
                      "code")))))))

(deftest eth-rpc-block-filter-records-same-height-reorg-heads
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json (engine-rpc-handle-request-json json store config)))
           (forkchoice-json (id head)
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
              ",\"method\":\"engine_forkchoiceUpdatedV1\","
              "\"params\":[{\"headBlockHash\":\"" (hash32-to-hex head)
              "\",\"safeBlockHash\":\"" (hash32-to-hex (zero-hash32))
              "\",\"finalizedBlockHash\":\"" (hash32-to-hex (zero-hash32))
              "\"}]}")))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 2
               :gas-limit 21000
               :to recipient
               :value 3)
              1
              1))
           (transaction-hash-hex
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (genesis
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :gas-limit 30000000
                                 :timestamp 0
                                 :extra-data #(0))))
           (old-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(1))
              :transactions (list transaction)
              :receipts (list (make-receipt :status 1
                                            :cumulative-gas-used 21000))))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(2)))))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (engine-payload-store-put-block
       store old-canonical-child :state-available-p t)
      (let* ((block-filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":89,\"method\":\"eth_newBlockFilter\"}"
                store
                config))
             (pending-filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":90,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (block-filter-id (field block-filter-response "result"))
             (pending-filter-id (field pending-filter-response "result")))
        (engine-payload-store-put-block
         store new-canonical-child :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash new-canonical-child) sender 0)
        (chain-store-put-account-balance
         store (block-hash new-canonical-child) sender 1000000)
        (let* ((forkchoice-response
                 (request (forkchoice-json 91 (block-hash new-canonical-child))
                          store
                          config))
               (block-changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":92,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" block-filter-id "\"]}")
                  store
                  config))
               (empty-block-changes-json
                 (engine-rpc-handle-request-json
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":93,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" block-filter-id "\"]}")
                  store
                  config))
               (pending-changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":94,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" pending-filter-id "\"]}")
                  store
                  config))
               (lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":95,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" transaction-hash-hex "\"]}")
                  store
                  config))
               (payload-status
                 (field (field forkchoice-response "result")
                        "payloadStatus"))
               (block-changes (field block-changes-response "result"))
               (pending-changes (field pending-changes-response "result"))
               (lookup-result (field lookup-response "result")))
          (is (string= +payload-status-valid+
                       (field payload-status "status")))
          (is (= 1 (length block-changes)))
          (is (string= (hash32-to-hex (block-hash new-canonical-child))
                       (first block-changes)))
          (is (search "\"result\":[]" empty-block-changes-json))
          (is (= 1 (length pending-changes)))
          (is (string= transaction-hash-hex (first pending-changes)))
          (is (string= transaction-hash-hex (field lookup-result "hash")))
          (is (null (field lookup-result "blockHash")))
          (is (null (field lookup-result "blockNumber"))))))))

