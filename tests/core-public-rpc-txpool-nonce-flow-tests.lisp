(in-package #:ethereum-lisp.test)

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

