(in-package #:ethereum-lisp.test)

(deftest eth-rpc-send-raw-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction (make-legacy-transaction
                         :nonce 9
                         :gas-price 20000000000
                         :gas-limit 21000
                         :to recipient
                         :value 1000000000000000000
                         :v 37
                         :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                         :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (raw-transaction (bytes-to-hex (transaction-encoding transaction)))
           (transaction-hash (hash32-to-hex (transaction-hash transaction)))
           (base-block
             (make-block
              :header (make-block-header :number 14
                                         :timestamp 140
                                         :gas-limit 30000000
                                         :gas-used 30000000
                                         :base-fee-per-gas 1000)))
           (mined-block
             (make-block
              :header (make-block-header :number 15
                                         :timestamp 150
                                         :gas-limit 30000000)
              :transactions (list transaction)))
           (config (make-chain-config :chain-id 1 :london-block 0)))
      (engine-payload-store-put-block store base-block)
      (let* ((new-pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":77,\"method\":\"eth_newPendingTransactionFilter\"}"
                 store
                 config)))
             (pending-filter-id
               (field new-pending-filter-response "result"))
             (initial-pending-filter-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":78,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (send-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":60,"
                  "\"method\":\"eth_sendRawTransaction\","
                  "\"params\":[\"" raw-transaction "\"]}")
                 store
                 config)))
             (pending-filter-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":79,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" pending-filter-id "\"]}")
                 store
                 config)))
             (pending-filter-changes
               (field pending-filter-changes-response "result"))
             (empty-pending-filter-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":80,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (duplicate-pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":89,"
                  "\"method\":\"eth_sendRawTransaction\","
                  "\"params\":[\"" raw-transaction "\"]}")
                 store
                 config)))
             (duplicate-pending-filter-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":90,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (duplicate-pending-status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":91,\"method\":\"txpool_status\",\"params\":[]}"
                 store
                 config)))
             (raw-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":61,"
                  "\"method\":\"eth_getRawTransactionByHash\","
                  "\"params\":[\"" transaction-hash "\"]}")
                 store
                 config)))
             (transaction-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":62,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\"" transaction-hash "\"]}")
                 store
                 config)))
             (pending-block-count-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":92,\"method\":\"eth_getBlockTransactionCountByNumber\",\"params\":[\"pending\"]}"
                 store
                 config)))
             (pending-index-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":93,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"pending\",\"0x0\"]}"
                 store
                 config)))
             (pending-raw-index-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":94,\"method\":\"eth_getRawTransactionByBlockNumberAndIndex\",\"params\":[\"pending\",\"0x0\"]}"
                 store
                 config)))
             (pending-block-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":96,\"method\":\"eth_getBlockByNumber\",\"params\":[\"pending\",false]}"
                 store
                 config)))
             (pending-full-block-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":97,\"method\":\"eth_getBlockByNumber\",\"params\":[\"pending\",true]}"
                 store
                 config)))
             (pending-header-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":98,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"pending\"]}"
                 store
                 config)))
             (pending-out-of-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":95,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"pending\",\"0x1\"]}"
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":65,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                 store
                 config)))
             (txpool-status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":67,\"method\":\"txpool_status\",\"params\":[]}"
                 store
                 config)))
             (txpool-content-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":69,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (txpool-content-response (parse-json txpool-content-json))
             (txpool-content-from-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":71,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex
                  (or (transaction-sender transaction)
                      (zero-address)))
                 "\"]}")
                store
                config))
             (txpool-content-from-response
               (parse-json txpool-content-from-json))
             (txpool-content-from-missing-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":72,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex
                  (make-address
                   (make-byte-vector 20 :initial-element #x99)))
                 "\"]}")
                store
                config))
             (txpool-inspect-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":75,\"method\":\"txpool_inspect\",\"params\":[]}"
                store
                config))
             (txpool-inspect-response (parse-json txpool-inspect-json))
             (invalid-rlp-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":63,\"method\":\"eth_sendRawTransaction\",\"params\":[\"0x01\"]}"
                 store
                 config)))
             (invalid-count-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":64,\"method\":\"eth_sendRawTransaction\",\"params\":[]}"
                 store
                 config)))
             (invalid-pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":66,\"method\":\"eth_pendingTransactions\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-new-pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":81,\"method\":\"eth_newPendingTransactionFilter\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-txpool-status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":68,\"method\":\"txpool_status\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-txpool-content-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"txpool_content\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-txpool-content-from-count-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":73,\"method\":\"txpool_contentFrom\",\"params\":[]}"
                 store
                 config)))
             (invalid-txpool-content-from-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":74,\"method\":\"txpool_contentFrom\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-txpool-inspect-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":76,\"method\":\"txpool_inspect\",\"params\":[\"unexpected\"]}"
                 store
                 config))))
        (is (string= (quantity-to-hex 1) pending-filter-id))
        (is (search "\"result\":[]" initial-pending-filter-json))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 1 (length pending-filter-changes)))
        (is (string= transaction-hash (first pending-filter-changes)))
        (is (search "\"result\":[]" empty-pending-filter-json))
        (is (string= transaction-hash
                     (field duplicate-pending-response "result")))
        (is (search "\"result\":[]" duplicate-pending-filter-json))
        (is (string= (quantity-to-hex 1)
                     (field (field duplicate-pending-status-response "result")
                            "pending")))
        (is (string= raw-transaction (field raw-response "result")))
        (let ((pending-transaction (field transaction-response "result")))
          (is (string= transaction-hash
                       (field pending-transaction "hash")))
          (is (null (field pending-transaction "blockHash")))
          (is (null (field pending-transaction "blockNumber")))
          (is (null (field pending-transaction "blockTimestamp")))
          (is (null (field pending-transaction "transactionIndex")))
          (is (string= (quantity-to-hex 20000000000)
                       (field pending-transaction "gasPrice")))
          (is (string= (quantity-to-hex 1000000000000000000)
                       (field pending-transaction "value"))))
        (is (string= (quantity-to-hex 1)
                     (field pending-block-count-response "result")))
        (let ((pending-index-transaction
                (field pending-index-response "result")))
          (is (string= transaction-hash
                       (field pending-index-transaction "hash")))
          (is (null (field pending-index-transaction "blockHash")))
          (is (null (field pending-index-transaction "blockNumber")))
          (is (null (field pending-index-transaction "transactionIndex"))))
        (is (string= raw-transaction
                     (field pending-raw-index-response "result")))
        (let* ((pending-block (field pending-block-response "result"))
               (transactions (field pending-block "transactions")))
          (is (null (field pending-block "hash")))
          (is (null (field pending-block "nonce")))
          (is (string= (quantity-to-hex 15)
                       (field pending-block "number")))
          (is (string= (hash32-to-hex (block-hash base-block))
                       (field pending-block "parentHash")))
          (is (string= (quantity-to-hex
                        (expected-base-fee-per-gas
                         (block-header base-block)))
                       (field pending-block "baseFeePerGas")))
          (is (= 1 (length transactions)))
          (is (string= transaction-hash (first transactions))))
        (let* ((pending-block (field pending-full-block-response "result"))
               (transactions (field pending-block "transactions"))
               (pending-transaction (first transactions)))
          (is (null (field pending-block "hash")))
          (is (string= (quantity-to-hex 15)
                       (field pending-block "number")))
          (is (string= (hash32-to-hex (block-hash base-block))
                       (field pending-block "parentHash")))
          (is (string= (quantity-to-hex
                        (expected-base-fee-per-gas
                         (block-header base-block)))
                       (field pending-block "baseFeePerGas")))
          (is (= 1 (length transactions)))
          (is (string= transaction-hash
                       (field pending-transaction "hash")))
          (is (null (field pending-transaction "blockHash")))
          (is (null (field pending-transaction "blockNumber")))
          (is (null (field pending-transaction "transactionIndex"))))
        (let ((pending-header (field pending-header-response "result")))
          (is (null (field pending-header "hash")))
          (is (null (field pending-header "nonce")))
          (is (string= (quantity-to-hex 15)
                       (field pending-header "number")))
          (is (string= (hash32-to-hex (block-hash base-block))
                       (field pending-header "parentHash")))
          (is (string= (quantity-to-hex
                        (expected-base-fee-per-gas
                         (block-header base-block)))
                       (field pending-header "baseFeePerGas"))))
        (is (null (field pending-out-of-range-response "result")))
        (let ((pending-transactions (field pending-response "result")))
          (is (= 1 (length pending-transactions)))
          (is (string= transaction-hash
                       (field (first pending-transactions) "hash")))
          (is (null (field (first pending-transactions) "blockHash"))))
        (let ((txpool-status (field txpool-status-response "result")))
          (is (string= (quantity-to-hex 1)
                       (field txpool-status "pending")))
          (is (string= (quantity-to-hex 0)
                       (field txpool-status "queued"))))
        (let* ((txpool-content (field txpool-content-response "result"))
               (pending (field txpool-content "pending"))
               (sender-transactions
                 (field pending
                        (address-to-hex
                         (or (transaction-sender transaction)
                             (zero-address)))))
               (nonce-transaction (field sender-transactions "9")))
          (is (string= transaction-hash
                       (field nonce-transaction "hash")))
          (is (null (field nonce-transaction "blockHash")))
          (is (search "\"queued\":{}" txpool-content-json)))
        (let* ((txpool-content-from
                 (field txpool-content-from-response "result"))
               (pending (field txpool-content-from "pending"))
               (nonce-transaction (field pending "9")))
          (is (string= transaction-hash
                       (field nonce-transaction "hash")))
          (is (search "\"queued\":{}" txpool-content-from-json))
          (is (search "\"pending\":{}" txpool-content-from-missing-json)))
        (let* ((txpool-inspect (field txpool-inspect-response "result"))
               (pending (field txpool-inspect "pending"))
               (sender-transactions
                 (field pending
                        (address-to-hex
                         (or (transaction-sender transaction)
                             (zero-address)))))
               (summary (field sender-transactions "9")))
          (is (string= (format nil "~A: 1000000000000000000 wei + 21000 gas x 20000000000 wei"
                               (address-to-hex recipient))
                       summary))
          (is (search "\"queued\":{}" txpool-inspect-json)))
        (engine-payload-store-put-block store mined-block)
        (let* ((mined-transaction-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":82,"
                    "\"method\":\"eth_getTransactionByHash\","
                    "\"params\":[\"" transaction-hash "\"]}")
                   store
                   config)))
               (post-mined-pending-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":83,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                   store
                   config)))
               (post-mined-status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":84,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config)))
               (resend-mined-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":85,"
                    "\"method\":\"eth_sendRawTransaction\","
                    "\"params\":[\"" raw-transaction "\"]}")
                   store
                   config)))
               (post-resend-pending-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":86,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                   store
                   config)))
               (post-resend-status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":87,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config)))
               (post-resend-filter-json
                 (engine-rpc-handle-request-json
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":88,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" pending-filter-id "\"]}")
                  store
                  config))
               (mined-transaction
                 (field mined-transaction-response "result"))
               (post-mined-status
                 (field post-mined-status-response "result"))
               (post-resend-status
                 (field post-resend-status-response "result")))
          (is (string= transaction-hash
                       (field mined-transaction "hash")))
          (is (string= (hash32-to-hex (block-hash mined-block))
                       (field mined-transaction "blockHash")))
          (is (string= (quantity-to-hex 15)
                       (field mined-transaction "blockNumber")))
          (is (string= (quantity-to-hex 0)
                       (field mined-transaction "transactionIndex")))
          (is (= 0 (length (field post-mined-pending-response "result"))))
          (is (string= (quantity-to-hex 0)
                       (field post-mined-status "pending")))
          (is (string= transaction-hash
                       (field resend-mined-response "result")))
          (is (= 0 (length (field post-resend-pending-response "result"))))
          (is (string= (quantity-to-hex 0)
                       (field post-resend-status "pending")))
          (is (search "\"result\":[]" post-resend-filter-json)))
        (is (= -32602
               (field (field invalid-rlp-response "error") "code")))
        (is (= -32602
               (field (field invalid-count-response "error") "code")))
        (is (= -32602
               (field (field invalid-pending-response "error") "code")))
        (is (= -32602
               (field (field invalid-new-pending-filter-response "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-status-response "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-content-response "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-content-from-count-response
                             "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-content-from-address-response
                             "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-inspect-response "error")
                      "code")))))))

