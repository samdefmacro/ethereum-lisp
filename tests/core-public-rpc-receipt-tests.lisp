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
        (is (string= (quantity-to-hex 150)
                     (field log "blockTimestamp")))
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

(deftest eth-rpc-blob-receipts-derive-gas-fields-and-preserve-legacy-shape
  (labels ((field-entry (object name)
             (assoc name object :test #'string=))
           (field (object name)
             (cdr (field-entry object name)))
           (receipt-request (store config transaction id)
             (engine-rpc-handle-request-json
              (format nil
                      "{\"jsonrpc\":\"2.0\",\"id\":~D,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"~A\"]}"
                      id (hash32-to-hex (transaction-hash transaction)))
              store config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0))
           (recipient
             (address-from-hex
              "0x0000000000000000000000000000000000000042"))
           (legacy-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 7
                                       :gas-limit 21000
                                       :to recipient)
              1 1337))
           (one-blob-transaction
             (transaction-from-encoding
              (transaction-encoding
               (fixture-sign-blob-transaction
                (make-blob-transaction
                 :chain-id 1337
                 :nonce 1
                 :max-priority-fee-per-gas 1
                 :max-fee-per-gas 100
                 :gas-limit 21000
                 :to recipient
                 :max-fee-per-blob-gas 3
                 :blob-versioned-hashes
                 (list
                  (hash32-from-hex
                   "0x0100000000000000000000000000000000000000000000000000000000000001")))
                1))))
           (two-blob-transaction
             (transaction-from-encoding
              (transaction-encoding
               (fixture-sign-blob-transaction
                (make-blob-transaction
                 :chain-id 1337
                 :nonce 2
                 :max-priority-fee-per-gas 1
                 :max-fee-per-gas 100
                 :gas-limit 21000
                 :to recipient
                 :max-fee-per-blob-gas 3
                 :blob-versioned-hashes
                 (list
                  (hash32-from-hex
                   "0x0100000000000000000000000000000000000000000000000000000000000002")
                  (hash32-from-hex
                   "0x0100000000000000000000000000000000000000000000000000000000000003")))
                1))))
           (legacy-receipt
             (make-receipt :status 1 :cumulative-gas-used 21000))
           ;; Receipts do not carry trusted blob gas fields.  Serialization must
           ;; derive them from each transaction and its containing block header.
           (one-blob-receipt
             (make-receipt :status 1 :cumulative-gas-used 42000))
           (two-blob-receipt
             (make-receipt :status 1 :cumulative-gas-used 63000))
           (block
             (make-block
              :header (make-block-header
                       :number 17
                       :timestamp 170
                       :gas-limit 30000000
                       :base-fee-per-gas 1
                       :blob-gas-used (* 3 +blob-gas-per-blob+)
                       :excess-blob-gas +blob-base-fee-update-fraction+)
              :transactions (list legacy-transaction
                                  one-blob-transaction
                                  two-blob-transaction)
              :receipts (list legacy-receipt
                              one-blob-receipt
                              two-blob-receipt))))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((legacy-result
               (field (parse-json
                       (receipt-request store config legacy-transaction 69))
                      "result"))
             (one-blob-result
               (field (parse-json
                       (receipt-request store config one-blob-transaction 70))
                      "result"))
             (two-blob-result
               (field (parse-json
                       (receipt-request store config two-blob-transaction 71))
                      "result"))
             (block-results
               (field
                (parse-json
                 (engine-rpc-handle-request-json
                  "{\"jsonrpc\":\"2.0\",\"id\":72,\"method\":\"eth_getBlockReceipts\",\"params\":[\"latest\"]}"
                  store config))
                "result"))
             (block-legacy-result (first block-results))
             (block-one-blob-result (second block-results))
             (block-two-blob-result (third block-results)))
        (is (null (field-entry legacy-result "blobGasUsed")))
        (is (null (field-entry legacy-result "blobGasPrice")))
        (is (null (field-entry block-legacy-result "blobGasUsed")))
        (is (null (field-entry block-legacy-result "blobGasPrice")))
        (is (equal "0x20000" (field one-blob-result "blobGasUsed")))
        (is (equal "0x2" (field one-blob-result "blobGasPrice")))
        (is (equal "0x40000" (field two-blob-result "blobGasUsed")))
        (is (equal "0x2" (field two-blob-result "blobGasPrice")))
        (is (equal "0x20000"
                   (field block-one-blob-result "blobGasUsed")))
        (is (equal "0x2" (field block-one-blob-result "blobGasPrice")))
        (is (equal "0x40000"
                   (field block-two-blob-result "blobGasUsed")))
        (is (equal "0x2" (field block-two-blob-result "blobGasPrice")))))))

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
