(in-package #:ethereum-lisp.test)

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

