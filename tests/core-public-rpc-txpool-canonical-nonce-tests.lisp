(in-package #:ethereum-lisp.test)

(deftest txpool-canonical-balance-drop-demotes-overbudget-pending-tail
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
           (config (make-chain-config :chain-id 1))
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
           (nonce-zero-hash
             (hash32-to-hex (transaction-hash nonce-zero)))
           (nonce-one-hash
             (hash32-to-hex (transaction-hash nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 42000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":222,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (nonce-zero-response (send-raw nonce-zero 223 store config))
             (nonce-one-response (send-raw nonce-one 224 store config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":225,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= nonce-zero-hash (field nonce-zero-response "result")))
        (is (string= nonce-one-hash (field nonce-one-response "result")))
        (is (= 2 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 21000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":226,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (pending-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":227,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":228,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":229,"
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
                   "{\"jsonrpc\":\"2.0\",\"id\":230,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (pending-transactions (field pending-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (queued
                 (field (field content "queued") (address-to-hex sender))))
          (is (string= (quantity-to-hex 1) (field status "pending")))
          (is (string= (quantity-to-hex 1) (field status "queued")))
          (is (= 1 (length pending-transactions)))
          (is (string= nonce-zero-hash
                       (field (field pending "0") "hash")))
          (is (string= nonce-one-hash
                       (field (field queued "1") "hash")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-response "result")))
          (is (= 0 (length (field filter-changes "result")))))))))

(deftest txpool-stale-pending-transactions-drop-after-canonical-nonce-advance
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
           (config (make-chain-config :chain-id 1))
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
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((send-response (send-raw transaction 181 store config))
             (pending-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":182,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field pending-status-response "result")
                            "pending")))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":183,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (pending-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":184,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":185,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":186,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" transaction-hash "\"]}")
                  store
                  config))
               (raw-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":187,"
                   "\"method\":\"eth_getRawTransactionByHash\","
                   "\"params\":[\"" transaction-hash "\"]}")
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":188,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result")))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (= 0 (length (field pending-response "result"))))
          (is (null (field content "pending")))
          (is (null (field content "queued")))
          (is (null (field lookup-response "result")))
          (is (null (field raw-response "result")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-response "result"))))))))

