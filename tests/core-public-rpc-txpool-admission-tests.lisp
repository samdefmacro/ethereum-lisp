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

(deftest eth-rpc-send-raw-transaction-returns-known-hash-before-admission
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config))))
    (let* ((config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1)))
      (let* ((store (make-engine-payload-memory-store))
             (head-block
               (make-block
                :header (make-block-header :number 0
                                           :timestamp 0
                                           :gas-limit 30000000))))
        (chain-store-put-block store head-block :state-available-p t)
        (chain-store-put-account-nonce store (block-hash head-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash head-block) sender 21000)
        (is (string= transaction-hash
                     (field (send-raw transaction 92 store config)
                            "result")))
        (chain-store-put-account-nonce store (block-hash head-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash head-block) sender 0)
        (let* ((resend-response (send-raw transaction 93 store config))
               (status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":94,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config))))
          (is (string= transaction-hash (field resend-response "result")))
          (is (null (field resend-response "error")))
          (is (string= (quantity-to-hex 1)
                       (field (field status-response "result") "pending")))))
      (let* ((store (make-engine-payload-memory-store))
             (mined-block
               (make-block
                :header (make-block-header :number 0
                                           :timestamp 0
                                           :gas-limit 30000000)
                :transactions (list transaction))))
        (chain-store-put-block store mined-block :state-available-p t)
        (chain-store-put-account-nonce store (block-hash mined-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash mined-block) sender 0)
        (let* ((resend-response (send-raw transaction 95 store config))
               (status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":96,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config))))
          (is (string= transaction-hash (field resend-response "result")))
          (is (null (field resend-response "error")))
          (is (string= (quantity-to-hex 0)
                       (field (field status-response "result") "pending"))))))))

(deftest eth-rpc-send-raw-transaction-requires-recoverable-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (raw-transaction
             (bytes-to-hex (transaction-encoding transaction)))
           (config (make-chain-config :chain-id 2))
           (new-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":92,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (filter-id (field new-filter-response "result"))
           (send-response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":93,"
                "\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\"" raw-transaction "\"]}")
               store
               config)))
           (pending-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":94,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
               store
               config)))
           (status-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":95,\"method\":\"txpool_status\",\"params\":[]}"
               store
               config)))
           (filter-response
             (engine-rpc-handle-request-json
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":96,"
               "\"method\":\"eth_getFilterChanges\","
               "\"params\":[\"" filter-id "\"]}")
              store
              config))
           (send-error (field send-response "error"))
           (status (field status-response "result")))
      (is (= -32602 (field send-error "code")))
      (is (= 0 (length (field pending-response "result"))))
      (is (string= (quantity-to-hex 0) (field status "pending")))
      (is (search "\"result\":[]" filter-response)))))

(deftest eth-rpc-send-raw-transaction-rejects-malformed-signatures
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (bad-y-parity-transaction
             (make-dynamic-fee-transaction
              :chain-id 1
              :nonce 1
              :max-priority-fee-per-gas 0
              :max-fee-per-gas #x0fa0
              :gas-limit #x84d0
              :to recipient
              :value 0
              :y-parity 2
              :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
              :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904))
           (high-s-transaction
             (make-dynamic-fee-transaction
              :chain-id 1
              :nonce 1
              :max-priority-fee-per-gas 0
              :max-fee-per-gas #x0fa0
              :gas-limit #x84d0
              :to recipient
              :value 0
              :y-parity 1
              :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
              :s #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1))
           (config (make-chain-config))
           (new-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":100,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (filter-id (field new-filter-response "result"))
           (bad-y-parity-response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":101,"
                "\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex
                 (transaction-encoding bad-y-parity-transaction))
                "\"]}")
               store
               config)))
           (high-s-response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":102,"
                "\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding high-s-transaction))
                "\"]}")
               store
               config)))
           (pending-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":103,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
               store
               config)))
           (status-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":104,\"method\":\"txpool_status\",\"params\":[]}"
               store
               config)))
           (filter-response
             (engine-rpc-handle-request-json
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":105,"
               "\"method\":\"eth_getFilterChanges\","
               "\"params\":[\"" filter-id "\"]}")
              store
              config))
           (bad-y-parity-error (field bad-y-parity-response "error"))
           (high-s-error (field high-s-response "error"))
           (status (field status-response "result")))
      (is (= -32602 (field bad-y-parity-error "code")))
      (is (= -32602 (field high-s-error "code")))
      (is (= 0 (length (field pending-response "result"))))
      (is (string= (quantity-to-hex 0) (field status "pending")))
      (is (search "\"result\":[]" filter-response)))))

(deftest eth-rpc-send-raw-transaction-rejects-malformed-set-code-authorizations
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
               (bytes-to-hex (transaction-encoding transaction))
               "\"]}")
               store
               config)))
           (first-authorization (transaction)
             (first (set-code-transaction-authorization-list transaction))))
    (let* ((raw-transaction
             "0x04f90126820539800285012a05f2008307a1209471562b71999873db5b286df957af199ec94617f78080c0f8baf85c82053994000000000000000000000000000000000000aaaa0101a07ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461a001b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669f85a8094000000000000000000000000000000000000bbbb8001a05011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98a056c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf6101a0167b0ecfc343a497095c22ee4270d3cc3b971cc3599fc73bbff727e0d2ed432da01c003c72306807492bf1150e39b2f79da23b49a4e83eb6e9209ae30d3572368f")
           (store (make-engine-payload-memory-store))
           (bad-y-parity-transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (high-s-transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (config (make-chain-config :chain-id 1337))
           (new-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":106,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (filter-id (field new-filter-response "result")))
      (setf (set-code-authorization-y-parity
             (first-authorization bad-y-parity-transaction))
            2)
      (setf (set-code-authorization-s
             (first-authorization high-s-transaction))
            #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1)
      (let* ((bad-y-parity-response
               (send-raw bad-y-parity-transaction 107 store config))
             (high-s-response
               (send-raw high-s-transaction 108 store config))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":109,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                 store
                 config)))
             (status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":110,\"method\":\"txpool_status\",\"params\":[]}"
                 store
                 config)))
             (filter-response
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":111,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (bad-y-parity-error (field bad-y-parity-response "error"))
             (high-s-error (field high-s-response "error"))
             (status (field status-response "result")))
        (is (= -32602 (field bad-y-parity-error "code")))
        (is (string= "Authorization signature values are invalid"
                     (field bad-y-parity-error "message")))
        (is (= -32602 (field high-s-error "code")))
        (is (string= "Authorization signature values are invalid"
                     (field high-s-error "message")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (search "\"result\":[]" filter-response))))))

(deftest eth-rpc-send-raw-transaction-gates-unprotected-legacy-admission
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config &key allow-unprotected-transactions-p)
             (parse-json
              (engine-rpc-handle-request-json
               json
               store
               config
               :allow-unprotected-transactions-p
               allow-unprotected-transactions-p)))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 3)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 1000000)
               store)))
    (let* ((raw-transaction
             "0xf86103018261a894b94f5374fce5edbc8e2a8697c15331677e6ebf0b0a8255441ba079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798a063ba75f072fb465223d8c651fbbf7ce6dd582ca9c793bcb595dd245b8a28cd17")
           (transaction (transaction-from-encoding
                         (hex-to-bytes raw-transaction)))
           (sender (transaction-sender transaction))
           (transaction-hash (hash32-to-hex
                              (transaction-hash transaction)))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (blocked-store (funded-store sender))
           (allowed-store (funded-store sender))
           (send-json
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":126,"
              "\"method\":\"eth_sendRawTransaction\","
              "\"params\":[\"" raw-transaction "\"]}"))
           (blocked-response (request send-json blocked-store config))
           (allowed-response
             (request send-json
                      allowed-store
                      config
                      :allow-unprotected-transactions-p t))
           (blocked-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":127,\"method\":\"txpool_status\",\"params\":[]}"
              blocked-store
              config))
           (allowed-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":128,\"method\":\"txpool_status\",\"params\":[]}"
              allowed-store
              config))
           (blocked-error (field blocked-response "error")))
      (is (not (legacy-transaction-protected-p transaction)))
      (is (= -32602 (field blocked-error "code")))
      (is (string= "eth_sendRawTransaction unprotected legacy transaction rejected"
                   (field blocked-error "message")))
      (is (string= (quantity-to-hex 0)
                   (field (field blocked-status "result") "pending")))
      (is (string= transaction-hash (field allowed-response "result")))
      (is (string= (quantity-to-hex 1)
                   (field (field allowed-status "result") "pending"))))))

(deftest eth-rpc-send-raw-transaction-enforces-txpool-price-limit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config &key txpool-price-limit)
             (parse-json
              (engine-rpc-handle-request-json
               json
               store
               config
               :txpool-price-limit txpool-price-limit)))
           (send-json (transaction id)
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
              ",\"method\":\"eth_sendRawTransaction\","
              "\"params\":[\""
              (bytes-to-hex (transaction-encoding transaction))
              "\"]}"))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 1000000)
               store)))
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (config (make-chain-config :chain-id 1 :london-block 0))
           (low-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (accepted-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 2
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (sender (transaction-sender low-transaction
                                       :expected-chain-id 1))
           (rejected-store (funded-store sender))
           (accepted-store (funded-store sender))
           (rejected-response
             (request
              (send-json low-transaction 129)
              rejected-store
              config
              :txpool-price-limit 2))
           (accepted-response
             (request
              (send-json accepted-transaction 130)
              accepted-store
              config
              :txpool-price-limit 2))
           (rejected-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":131,\"method\":\"txpool_status\",\"params\":[]}"
              rejected-store
              config))
           (accepted-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":132,\"method\":\"txpool_status\",\"params\":[]}"
              accepted-store
              config))
           (rejected-error (field rejected-response "error")))
      (is (= -32602 (field rejected-error "code")))
      (is (string= "eth_sendRawTransaction gas price below txpool price limit"
                   (field rejected-error "message")))
      (is (string= (quantity-to-hex 0)
                   (field (field rejected-status "result") "pending")))
      (is (string= (hash32-to-hex (transaction-hash accepted-transaction))
                   (field accepted-response "result")))
      (is (string= (quantity-to-hex 1)
                   (field (field accepted-status "result") "pending"))))))

(deftest eth-rpc-send-raw-transaction-enforces-configured-txpool-price-bump
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config &key txpool-price-bump-percent)
             (parse-json
              (engine-rpc-handle-request-json
               json
               store
               config
               :txpool-price-bump-percent txpool-price-bump-percent)))
           (send-json (transaction id)
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
              ",\"method\":\"eth_sendRawTransaction\","
              "\"params\":[\""
              (bytes-to-hex (transaction-encoding transaction))
              "\"]}"))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 10000000)
               store))
           (signed-legacy (gas-price private-key recipient)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price gas-price
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1)))
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (config (make-chain-config :chain-id 1 :london-block 0))
           (base-transaction (signed-legacy 100 private-key recipient))
           (underpriced-transaction (signed-legacy 124 private-key recipient))
           (replacement-transaction (signed-legacy 125 private-key recipient))
           (sender (transaction-sender base-transaction :expected-chain-id 1))
           (rejected-store (funded-store sender))
           (accepted-store (funded-store sender))
           (base-rejected-response
             (request
              (send-json base-transaction 133)
              rejected-store
              config
              :txpool-price-bump-percent 25))
           (base-accepted-response
             (request
              (send-json base-transaction 134)
              accepted-store
              config
              :txpool-price-bump-percent 25))
           (rejected-response
             (request
              (send-json underpriced-transaction 135)
              rejected-store
              config
              :txpool-price-bump-percent 25))
           (accepted-response
             (request
              (send-json replacement-transaction 136)
              accepted-store
              config
              :txpool-price-bump-percent 25))
           (rejected-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":137,\"method\":\"txpool_status\",\"params\":[]}"
              rejected-store
              config))
           (accepted-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":138,\"method\":\"txpool_status\",\"params\":[]}"
              accepted-store
              config))
           (rejected-error (field rejected-response "error")))
      (is (string= (hash32-to-hex (transaction-hash base-transaction))
                   (field base-rejected-response "result")))
      (is (string= (hash32-to-hex (transaction-hash base-transaction))
                   (field base-accepted-response "result")))
      (is (= -32602 (field rejected-error "code")))
      (is (string= "Pending transaction replacement underpriced"
                   (field rejected-error "message")))
      (is (string= (hash32-to-hex (transaction-hash replacement-transaction))
                   (field accepted-response "result")))
      (is (string= (quantity-to-hex 1)
                   (field (field rejected-status "result") "pending")))
      (is (string= (quantity-to-hex 1)
                   (field (field accepted-status "result") "pending"))))))

(deftest eth-rpc-send-raw-transaction-applies-basic-admission-preflight
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config))))
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (low-gas-store (make-engine-payload-memory-store))
           (typed-store (make-engine-payload-memory-store))
           (over-gas-store (make-engine-payload-memory-store))
           (nonce-store (make-engine-payload-memory-store))
           (balance-store (make-engine-payload-memory-store))
           (missing-balance-store (make-engine-payload-memory-store))
           (sender-code-store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (low-gas-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0
               :data #(1))
              private-key
              1))
           (unsupported-access-transaction
             (make-access-list-transaction
              :chain-id 1
              :nonce 3
              :gas-price 1
              :gas-limit 25000
              :to (address-from-hex
                   "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
              :value 10
              :data (hex-to-bytes "0x5544")
              :y-parity 1
              :r #xc9519f4f2b30335884581971573fadf60c6204f59a911df35ee8a540456b2660
              :s #x32f1e8e2c5dd761f9e4f88f41c8310aeaba26a8bfcdacfedfa12ec3862d37521))
           (over-gas-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 30000001
               :to recipient
               :value 0)
              private-key
              1))
           (sender-code-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (nonce-too-low-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (insufficient-balance-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 10
               :gas-limit 21000
               :to recipient
               :value 1)
              private-key
              1))
           (sender (transaction-sender sender-code-transaction
                                       :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block nonce-store head-block :state-available-p t)
      (chain-store-put-account-nonce
       nonce-store (block-hash head-block) sender 2)
      (chain-store-put-account-balance
       nonce-store (block-hash head-block) sender 1000000)
      (chain-store-put-block over-gas-store head-block :state-available-p t)
      (chain-store-put-account-nonce
       over-gas-store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       over-gas-store (block-hash head-block) sender 100000000)
      (chain-store-put-block balance-store head-block :state-available-p t)
      (chain-store-put-account-balance
       balance-store (block-hash head-block) sender 100)
      (chain-store-put-block missing-balance-store
                             head-block
                             :state-available-p t)
      (engine-payload-store-put-block sender-code-store head-block)
      (engine-payload-store-put-account-balance
       sender-code-store (block-hash head-block) sender 1000000)
      (engine-payload-store-put-account-code
       sender-code-store (block-hash head-block) sender #(1 2 3))
      (let* ((low-gas-response
               (send-raw low-gas-transaction 112 low-gas-store config))
             (typed-response
               (send-raw unsupported-access-transaction 113 typed-store config))
             (over-gas-response
               (send-raw over-gas-transaction 124 over-gas-store config))
             (nonce-too-low-response
               (send-raw nonce-too-low-transaction 114 nonce-store config))
             (insufficient-balance-response
               (send-raw insufficient-balance-transaction
                         115
                         balance-store
                         config))
             (missing-balance-response
               (send-raw insufficient-balance-transaction
                         122
                         missing-balance-store
                         config))
             (sender-code-response
               (send-raw sender-code-transaction
                         116
                         sender-code-store
                         config))
             (low-gas-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":117,\"method\":\"txpool_status\",\"params\":[]}"
                 low-gas-store
                 config)))
             (typed-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":118,\"method\":\"txpool_status\",\"params\":[]}"
                 typed-store
                 config)))
             (over-gas-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_status\",\"params\":[]}"
                 over-gas-store
                 config)))
             (nonce-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":119,\"method\":\"txpool_status\",\"params\":[]}"
                 nonce-store
                 config)))
             (balance-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":120,\"method\":\"txpool_status\",\"params\":[]}"
                 balance-store
                 config)))
             (missing-balance-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":123,\"method\":\"txpool_status\",\"params\":[]}"
                 missing-balance-store
                 config)))
             (sender-code-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":121,\"method\":\"txpool_status\",\"params\":[]}"
                 sender-code-store
                 config))))
        (is (= -32602 (field (field low-gas-response "error") "code")))
        (is (string= "eth_sendRawTransaction gas limit below intrinsic gas"
                     (field (field low-gas-response "error") "message")))
        (is (= -32602 (field (field typed-response "error") "code")))
        (is (string= "Access-list transaction before Berlin"
                     (field (field typed-response "error") "message")))
        (is (= -32602 (field (field over-gas-response "error") "code")))
        (is (string= "eth_sendRawTransaction gas limit exceeds block gas limit"
                     (field (field over-gas-response "error") "message")))
        (is (= -32602
               (field (field nonce-too-low-response "error") "code")))
        (is (string= "eth_sendRawTransaction nonce too low"
                     (field (field nonce-too-low-response "error")
                            "message")))
        (is (= -32602
               (field (field insufficient-balance-response "error")
                      "code")))
        (is (string=
             "eth_sendRawTransaction insufficient sender balance"
             (field (field insufficient-balance-response "error")
                    "message")))
        (is (= -32602
               (field (field missing-balance-response "error")
                      "code")))
        (is (string=
             "eth_sendRawTransaction insufficient sender balance"
             (field (field missing-balance-response "error")
                    "message")))
        (is (= -32602 (field (field sender-code-response "error") "code")))
        (is (string=
             "eth_sendRawTransaction sender has non-delegation code"
             (field (field sender-code-response "error") "message")))
        (dolist (status-response
                 (list low-gas-status
                       typed-status
                       over-gas-status
                       nonce-status
                       balance-status
                       missing-balance-status
                       sender-code-status))
          (is (string= (quantity-to-hex 0)
                       (field (field status-response "result")
                              "pending"))))))))

(deftest eth-rpc-send-raw-transaction-enforces-pending-balance-expenditure
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (first-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender first-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 30000)
      (let* ((first-response (send-raw first-transaction 122 store config))
             (second-response (send-raw second-transaction 123 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":124,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":126,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= first-hash (field first-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= first-hash (field (field pending "0") "hash")))
        (is (null (field pending "1")))
        (is (null (field content "queued")))
        (is (null (field second-lookup-response "result")))))))

(deftest eth-rpc-send-raw-transaction-enforces-pooled-balance-expenditure
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (first-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 2
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender first-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 30000)
      (let* ((first-response (send-raw first-transaction 127 store config))
             (second-response (send-raw second-transaction 128 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":129,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":130,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":131,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= first-hash (field first-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= first-hash (field (field queued "1") "hash")))
        (is (null (field queued "2")))
        (is (null (field second-lookup-response "result")))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (basefee-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (basefee-hash
             (hash32-to-hex (transaction-hash basefee-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender basefee-transaction
                                       :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 100000)
      (let* ((basefee-response
               (send-raw basefee-transaction 132 store config))
             (second-response (send-raw second-transaction 133 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":134,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":135,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":136,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= basefee-hash (field basefee-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= basefee-hash (field (field queued "0") "hash")))
        (is (null (field queued "1")))
        (is (null (field second-lookup-response "result")))))))

(deftest eth-rpc-send-raw-transaction-queues-retained-state-nonce-gaps
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
               (bytes-to-hex (transaction-encoding transaction))
               "\"]}")
               store
               config)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 3
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":122,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 123 store config))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":124,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":126,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (content-from-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":127,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex sender)
                 "\"]}")
                store
                config))
             (transaction-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":128,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (raw-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":129,"
                 "\"method\":\"eth_getRawTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":131,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":132,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (queued-from
               (field (field (field content-from-response "result") "queued")
                      "3"))
             (pooled-transaction
               (field transaction-response "result")))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= transaction-hash (field (field queued "3") "hash")))
        (is (string= transaction-hash (field queued-from "hash")))
        (is (string= transaction-hash (field pooled-transaction "hash")))
        (is (null (field pooled-transaction "blockHash")))
        (is (string= (bytes-to-hex (transaction-encoding transaction))
                     (field raw-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field transaction-count-response "result")))
        (is (= 0 (length (field filter-changes "result"))))))))

(deftest eth-rpc-send-raw-transaction-enforces-txpool-queue-limits
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw
               (transaction id store config
                &key txpool-account-queue-limit txpool-global-queue-limit)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config
               :txpool-account-queue-limit txpool-account-queue-limit
               :txpool-global-queue-limit txpool-global-queue-limit)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 10000000)
               store))
           (signed-legacy (nonce gas-price private-key recipient)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce nonce
               :gas-price gas-price
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1)))
    (let* ((config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-one (signed-legacy 1 1 1 recipient))
           (nonce-two (signed-legacy 2 1 1 recipient))
           (replacement (signed-legacy 1 2 1 recipient))
           (sender (transaction-sender nonce-one :expected-chain-id 1))
           (global-store (funded-store sender))
           (account-store (funded-store sender))
           (replacement-store (funded-store sender))
           (nonce-two-hash (hash32-to-hex (transaction-hash nonce-two)))
           (replacement-hash (hash32-to-hex (transaction-hash replacement))))
      (let* ((first-response
               (send-raw nonce-one 181 global-store config
                         :txpool-global-queue-limit 1))
             (second-response
               (send-raw nonce-two 182 global-store config
                         :txpool-global-queue-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":183,\"method\":\"txpool_status\",\"params\":[]}"
                global-store
                config))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":184,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" nonce-two-hash "\"]}")
                global-store
                config))
             (error (field second-response "error")))
        (is (string= (hash32-to-hex (transaction-hash nonce-one))
                     (field first-response "result")))
        (is (= -32602 (field error "code")))
        (is (string= "Queued transaction exceeds txpool global queue limit"
                     (field error "message")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued")))
        (is (null (field lookup-response "result"))))
      (let* ((first-response
               (send-raw nonce-one 185 account-store config
                         :txpool-account-queue-limit 1
                         :txpool-global-queue-limit 10))
             (second-response
               (send-raw nonce-two 186 account-store config
                         :txpool-account-queue-limit 1
                         :txpool-global-queue-limit 10))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":187,\"method\":\"txpool_status\",\"params\":[]}"
                account-store
                config))
             (error (field second-response "error")))
        (is (string= (hash32-to-hex (transaction-hash nonce-one))
                     (field first-response "result")))
        (is (= -32602 (field error "code")))
        (is (string= "Queued transaction exceeds txpool account queue limit"
                     (field error "message")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued"))))
      (let* ((first-response
               (send-raw nonce-one 188 replacement-store config
                         :txpool-account-queue-limit 1
                         :txpool-global-queue-limit 1))
             (replacement-response
               (send-raw replacement 189 replacement-store config
                         :txpool-account-queue-limit 1
                         :txpool-global-queue-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":190,\"method\":\"txpool_status\",\"params\":[]}"
                replacement-store
                config)))
        (is (string= (hash32-to-hex (transaction-hash nonce-one))
                     (field first-response "result")))
        (is (string= replacement-hash (field replacement-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued")))))))

(deftest eth-rpc-send-raw-transaction-enforces-txpool-slot-limits
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw
               (transaction id store config
                &key txpool-account-slot-limit txpool-global-slot-limit)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config
               :txpool-account-slot-limit txpool-account-slot-limit
               :txpool-global-slot-limit txpool-global-slot-limit)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (funded-store (&rest senders)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (dolist (sender senders)
                 (chain-store-put-account-nonce
                  store (block-hash head-block) sender 0)
                 (chain-store-put-account-balance
                  store (block-hash head-block) sender 10000000))
               store))
           (signed-legacy (nonce gas-price private-key recipient)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce nonce
               :gas-price gas-price
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1)))
    (let* ((config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (sender-one-nonce-zero (signed-legacy 0 1 1 recipient))
           (sender-one-nonce-one (signed-legacy 1 1 1 recipient))
           (sender-one-replacement (signed-legacy 0 2 1 recipient))
           (sender-two-nonce-zero (signed-legacy 0 1 2 recipient))
           (sender-one (transaction-sender sender-one-nonce-zero
                                           :expected-chain-id 1))
           (sender-two (transaction-sender sender-two-nonce-zero
                                           :expected-chain-id 1))
           (global-store (funded-store sender-one sender-two))
           (account-store (funded-store sender-one))
           (replacement-store (funded-store sender-one))
           (global-promotion-store (funded-store sender-one))
           (account-promotion-store (funded-store sender-one))
           (sender-two-hash (hash32-to-hex
                             (transaction-hash sender-two-nonce-zero)))
           (replacement-hash (hash32-to-hex
                              (transaction-hash sender-one-replacement))))
      (let* ((first-response
               (send-raw sender-one-nonce-zero 241 global-store config
                         :txpool-global-slot-limit 1))
             (second-response
               (send-raw sender-two-nonce-zero 242 global-store config
                         :txpool-global-slot-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":243,\"method\":\"txpool_status\",\"params\":[]}"
                global-store
                config))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":244,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" sender-two-hash "\"]}")
                global-store
                config))
             (error (field second-response "error")))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field first-response "result")))
        (is (= -32602 (field error "code")))
        (is (string= "Pending transaction exceeds txpool global slot limit"
                     (field error "message")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending")))
        (is (null (field lookup-response "result"))))
      (let* ((first-response
               (send-raw sender-one-nonce-zero 245 account-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 10))
             (second-response
               (send-raw sender-one-nonce-one 246 account-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 10))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":247,\"method\":\"txpool_status\",\"params\":[]}"
                account-store
                config))
             (error (field second-response "error")))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field first-response "result")))
        (is (= -32602 (field error "code")))
        (is (string= "Pending transaction exceeds txpool account slot limit"
                     (field error "message")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending"))))
      (let* ((first-response
               (send-raw sender-one-nonce-zero 248 replacement-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 1))
             (replacement-response
               (send-raw sender-one-replacement 249 replacement-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":250,\"method\":\"txpool_status\",\"params\":[]}"
                replacement-store
                config)))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field first-response "result")))
        (is (string= replacement-hash (field replacement-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending"))))
      (let* ((queued-response
               (send-raw sender-one-nonce-one 251 global-promotion-store config
                         :txpool-global-slot-limit 1))
             (pending-response
               (send-raw sender-one-nonce-zero 252 global-promotion-store config
                         :txpool-global-slot-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":253,\"method\":\"txpool_status\",\"params\":[]}"
                global-promotion-store
                config)))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-one))
                     (field queued-response "result")))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field pending-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued"))))
      (let* ((queued-response
               (send-raw sender-one-nonce-one 254 account-promotion-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 10))
             (pending-response
               (send-raw sender-one-nonce-zero 255 account-promotion-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 10))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":256,\"method\":\"txpool_status\",\"params\":[]}"
                account-promotion-store
                config)))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-one))
                     (field queued-response "result")))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field pending-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued")))))))

(deftest eth-rpc-send-raw-transaction-honors-txpool-local-exemptions
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw
               (transaction id store config
                &key txpool-price-limit txpool-account-queue-limit
                  txpool-global-queue-limit txpool-account-slot-limit
                  txpool-global-slot-limit txpool-local-addresses
                  txpool-no-local-exemptions-p)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config
               :txpool-price-limit txpool-price-limit
               :txpool-account-queue-limit txpool-account-queue-limit
               :txpool-global-queue-limit txpool-global-queue-limit
               :txpool-account-slot-limit txpool-account-slot-limit
               :txpool-global-slot-limit txpool-global-slot-limit
               :txpool-local-addresses txpool-local-addresses
               :txpool-no-local-exemptions-p txpool-no-local-exemptions-p)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 10000000)
               store))
           (signed-legacy (nonce gas-price private-key recipient)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce nonce
               :gas-price gas-price
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1)))
    (let* ((config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (pending-transaction (signed-legacy 0 1 1 recipient))
           (queued-transaction (signed-legacy 1 1 1 recipient))
           (sender (transaction-sender pending-transaction
                                       :expected-chain-id 1))
           (local-addresses (list sender))
           (price-rejected-store (funded-store sender))
           (price-local-store (funded-store sender))
           (price-nolocals-store (funded-store sender))
           (queue-local-store (funded-store sender))
           (queue-nolocals-store (funded-store sender))
           (slot-local-store (funded-store sender))
           (slot-nolocals-store (funded-store sender)))
      (let* ((rejected-response
               (send-raw pending-transaction 191 price-rejected-store config
                         :txpool-price-limit 2))
             (local-response
               (send-raw pending-transaction 192 price-local-store config
                         :txpool-price-limit 2
                         :txpool-local-addresses local-addresses))
             (nolocals-response
               (send-raw pending-transaction 193 price-nolocals-store config
                         :txpool-price-limit 2
                         :txpool-local-addresses local-addresses
                         :txpool-no-local-exemptions-p t))
             (local-status
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":194,\"method\":\"txpool_status\",\"params\":[]}"
                price-local-store
                config))
             (rejected-error (field rejected-response "error"))
             (nolocals-error (field nolocals-response "error")))
        (is (= -32602 (field rejected-error "code")))
        (is (string= "eth_sendRawTransaction gas price below txpool price limit"
                     (field rejected-error "message")))
        (is (string= (hash32-to-hex (transaction-hash pending-transaction))
                     (field local-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field local-status "result") "pending")))
        (is (= -32602 (field nolocals-error "code")))
        (is (string= "eth_sendRawTransaction gas price below txpool price limit"
                     (field nolocals-error "message"))))
      (let* ((local-response
               (send-raw queued-transaction 195 queue-local-store config
                         :txpool-account-queue-limit 0
                         :txpool-global-queue-limit 0
                         :txpool-local-addresses local-addresses))
             (nolocals-response
               (send-raw queued-transaction 196 queue-nolocals-store config
                         :txpool-account-queue-limit 0
                         :txpool-global-queue-limit 0
                         :txpool-local-addresses local-addresses
                         :txpool-no-local-exemptions-p t))
             (local-status
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":197,\"method\":\"txpool_status\",\"params\":[]}"
                queue-local-store
                config))
             (nolocals-error (field nolocals-response "error")))
        (is (string= (hash32-to-hex (transaction-hash queued-transaction))
                     (field local-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field local-status "result") "queued")))
        (is (= -32602 (field nolocals-error "code")))
        (is (string= "Queued transaction exceeds txpool global queue limit"
                     (field nolocals-error "message"))))
      (let* ((local-response
               (send-raw pending-transaction 198 slot-local-store config
                         :txpool-account-slot-limit 0
                         :txpool-global-slot-limit 0
                         :txpool-local-addresses local-addresses))
             (nolocals-response
               (send-raw pending-transaction 199 slot-nolocals-store config
                         :txpool-account-slot-limit 0
                         :txpool-global-slot-limit 0
                         :txpool-local-addresses local-addresses
                         :txpool-no-local-exemptions-p t))
             (local-status
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":200,\"method\":\"txpool_status\",\"params\":[]}"
                slot-local-store
                config))
             (nolocals-error (field nolocals-response "error")))
        (is (string= (hash32-to-hex (transaction-hash pending-transaction))
                     (field local-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field local-status "result") "pending")))
        (is (= -32602 (field nolocals-error "code")))
        (is (string= "Pending transaction exceeds txpool global slot limit"
                     (field nolocals-error "message")))))))

(deftest eth-rpc-txpool-lifetime-expires-queued-view-transactions
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config now)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config
               :txpool-lifetime-seconds 5
               :txpool-now now)))
           (request (json store config now)
             (parse-json
              (engine-rpc-handle-request-json
               json store config
               :txpool-lifetime-seconds 5
               :txpool-now now)))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 10000000)
               store))
           (signed-legacy (nonce gas-price)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce nonce
               :gas-price gas-price
               :gas-limit 21000
               :to (address-from-hex
                    "0x3535353535353535353535353535353535353535")
               :value 0)
              1
              1)))
    (let* ((config (make-chain-config :chain-id 1 :london-block 0))
           (queued-transaction (signed-legacy 1 1))
           (replacement-transaction (signed-legacy 1 2))
           (pending-transaction (signed-legacy 0 1))
           (sender (transaction-sender queued-transaction
                                       :expected-chain-id 1))
           (queued-store (funded-store sender))
           (pending-store (funded-store sender))
           (replacement-store (funded-store sender))
           (queued-hash (hash32-to-hex (transaction-hash queued-transaction)))
           (replacement-hash
             (hash32-to-hex (transaction-hash replacement-transaction)))
           (pending-hash
             (hash32-to-hex (transaction-hash pending-transaction))))
      (is (string= queued-hash
                   (field (send-raw queued-transaction 301 queued-store
                                    config 10)
                          "result")))
      (let* ((status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":302,\"method\":\"txpool_status\",\"params\":[]}"
                queued-store config 16))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":303,\"method\":\"txpool_content\",\"params\":[]}"
                queued-store config 16))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":304,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" queued-hash "\"]}")
                queued-store config 16)))
        (is (string= (quantity-to-hex 0)
                     (field (field status-response "result") "queued")))
        (is (null (field (field content-response "result") "queued")))
        (is (null (field lookup-response "result"))))
      (is (string= pending-hash
                   (field (send-raw pending-transaction 305 pending-store
                                    config 10)
                          "result")))
      (let ((status-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":306,\"method\":\"txpool_status\",\"params\":[]}"
               pending-store config 16)))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending")))
        (is (string= (quantity-to-hex 0)
                     (field (field status-response "result") "queued"))))
      (is (string= queued-hash
                   (field (send-raw queued-transaction 307 replacement-store
                                    config 10)
                          "result")))
      (is (string= replacement-hash
                   (field (send-raw replacement-transaction 308
                                    replacement-store config 14)
                          "result")))
      (let ((lookup-response
              (request
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":309,"
                "\"method\":\"eth_getTransactionByHash\","
                "\"params\":[\"" replacement-hash "\"]}")
               replacement-store config 16)))
        (is (string= replacement-hash
                     (field (field lookup-response "result") "hash")))))))

(deftest eth-rpc-send-raw-transaction-keeps-contiguous-nonces-pending
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-zero-hash (hash32-to-hex (transaction-hash nonce-zero)))
           (nonce-one-hash (hash32-to-hex (transaction-hash nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":174,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (nonce-zero-response (send-raw nonce-zero 175 store config))
             (nonce-one-response (send-raw nonce-one 176 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":177,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":178,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":179,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":180,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (filter-hashes (field filter-changes "result")))
        (is (string= nonce-zero-hash (field nonce-zero-response "result")))
        (is (string= nonce-one-hash (field nonce-one-response "result")))
        (is (string= (quantity-to-hex 2) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= nonce-zero-hash
                     (field (field pending "0") "hash")))
        (is (string= nonce-one-hash
                     (field (field pending "1") "hash")))
        (is (null (field content "queued")))
        (is (string= (quantity-to-hex 2)
                     (field transaction-count-response "result")))
        (is (= 2 (length filter-hashes)))
        (is (string= nonce-zero-hash (first filter-hashes)))
        (is (string= nonce-one-hash (second filter-hashes)))))))

(deftest eth-rpc-send-raw-transaction-promotes-contiguous-queued-nonces
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-zero-hash (hash32-to-hex (transaction-hash nonce-zero)))
           (nonce-one-hash (hash32-to-hex (transaction-hash nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":142,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (queued-response (send-raw nonce-one 143 store config))
             (queued-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":144,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (pending-response (send-raw nonce-zero 145 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":146,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (pending-transactions-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":147,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":148,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":149,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (promoted-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":150,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (pending-transactions
               (field pending-transactions-response "result"))
             (content (field content-response "result"))
             (pending-sender
               (field (field content "pending") (address-to-hex sender)))
             (promoted-hashes (field promoted-filter-changes "result")))
        (is (string= nonce-one-hash (field queued-response "result")))
        (is (= 0 (length (field queued-filter-changes "result"))))
        (is (string= nonce-zero-hash (field pending-response "result")))
        (is (string= (quantity-to-hex 2) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (= 2 (length pending-transactions)))
        (is (string= nonce-zero-hash
                     (field (field pending-sender "0") "hash")))
        (is (string= nonce-one-hash
                     (field (field pending-sender "1") "hash")))
        (is (null (field content "queued")))
        (is (string= (quantity-to-hex 2)
                     (field transaction-count-response "result")))
        (is (= 2 (length promoted-hashes)))
        (is (string= nonce-zero-hash (first promoted-hashes)))
        (is (string= nonce-one-hash (second promoted-hashes)))))))

(deftest eth-rpc-send-raw-transaction-queues-basefee-ineligible-transactions
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":133,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 134 store config))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":135,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":136,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":137,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (content-from-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":138,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex sender)
                 "\"]}")
                store
                config))
             (transaction-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":139,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":140,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":141,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (queued-from
               (field (field (field content-from-response "result") "queued")
                      "0"))
             (pooled-transaction
               (field transaction-response "result")))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= transaction-hash (field (field queued "0") "hash")))
        (is (string= transaction-hash (field queued-from "hash")))
        (is (string= transaction-hash (field pooled-transaction "hash")))
        (is (null (field pooled-transaction "blockHash")))
        (is (string= (quantity-to-hex 0)
                     (field transaction-count-response "result")))
        (is (= 0 (length (field filter-changes "result"))))))))

(deftest eth-rpc-send-raw-transaction-routes-blob-transactions-to-blob-subpool
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0))
           (raw-transaction
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")
           (transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1337))
           (filter-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":167,\"method\":\"eth_newPendingTransactionFilter\"}"
              store
              config))
           (filter-id (field filter-response "result"))
           (send-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":166,"
               "\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\"" raw-transaction "\"]}")
              store
              config))
           (pending-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":168,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
              store
              config))
           (status-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":169,\"method\":\"txpool_status\",\"params\":[]}"
              store
              config))
           (content-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":170,\"method\":\"txpool_content\",\"params\":[]}"
              store
              config))
           (content-from-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":171,"
               "\"method\":\"txpool_contentFrom\",\"params\":[\""
               (address-to-hex sender)
               "\"]}")
              store
              config))
           (inspect-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":174,\"method\":\"txpool_inspect\",\"params\":[]}"
              store
              config))
           (lookup-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":172,"
               "\"method\":\"eth_getTransactionByHash\","
               "\"params\":[\"" transaction-hash "\"]}")
              store
              config))
           (filter-changes
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":173,"
               "\"method\":\"eth_getFilterChanges\","
               "\"params\":[\"" filter-id "\"]}")
              store
              config))
           (status (field status-response "result"))
           (content (field content-response "result"))
           (queued (field (field content "queued") (address-to-hex sender)))
           (queued-from
             (field (field (field content-from-response "result") "queued")
                    (write-to-string (transaction-nonce transaction)
                                     :base 10)))
           (inspect-queued
             (field (field (field inspect-response "result") "queued")
                    (address-to-hex sender)))
           (pooled-transaction (field lookup-response "result")))
      (is (typep transaction 'blob-transaction))
      (is (string= transaction-hash (field send-response "result")))
      (is (= 0 (length (field pending-response "result"))))
      (is (string= (quantity-to-hex 0) (field status "pending")))
      (is (string= (quantity-to-hex 1) (field status "queued")))
      (is (null (field content "pending")))
      (is (string= transaction-hash (field (field queued "0") "hash")))
      (is (string= transaction-hash (field queued-from "hash")))
      (is (search (format nil "~A wei"
                          (transaction-value transaction))
                  (field inspect-queued "0")))
      (is (string= transaction-hash (field pooled-transaction "hash")))
      (is (null (field pooled-transaction "blockHash")))
      (is (= 0 (length (field filter-changes "result")))))))

(deftest eth-rpc-send-raw-transaction-rejects-low-blob-fee-cap
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0))
           (raw-transaction
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")
           (transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (head-block
             (make-block
              :header
              (make-block-header
               :number 1
               :timestamp 12
               :gas-limit 30000000
               :blob-gas-used 0
               :excess-blob-gas (* 64 1024 1024)))))
      (chain-store-put-block store head-block :state-available-p t)
      (let* ((send-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":175,"
                 "\"method\":\"eth_sendRawTransaction\","
                 "\"params\":[\"" raw-transaction "\"]}")
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":176,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":177,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (error (field send-response "error"))
             (status (field status-response "result")))
        (is (typep transaction 'blob-transaction))
        (is (> (block-header-blob-base-fee (block-header head-block))
               (blob-transaction-max-fee-per-blob-gas transaction)))
        (is (= -32602 (field error "code")))
        (is (string= "eth_sendRawTransaction: Max fee per blob gas below blob base fee"
                     (field error "message")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (null (field lookup-response "result")))))))

