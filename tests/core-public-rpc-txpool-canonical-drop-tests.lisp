(in-package #:ethereum-lisp.test)

(deftest txpool-canonical-basefee-rise-demotes-pending-transaction
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
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":214,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 215 store config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":216,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 1 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":217,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (pending-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":218,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":219,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":220,"
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
                   "{\"jsonrpc\":\"2.0\",\"id\":221,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result"))
               (queued
                 (field (field content "queued") (address-to-hex sender))))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 1) (field status "queued")))
          (is (= 0 (length (field pending-response "result"))))
          (is (null (field content "pending")))
          (is (string= transaction-hash
                       (field (field queued "0") "hash")))
          (is (string= (quantity-to-hex 0)
                       (field transaction-count-response "result")))
          (is (= 0 (length (field filter-changes "result")))))))))

(deftest txpool-canonical-gas-limit-drop-removes-overlimit-transactions
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
           (pending-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 6
               :gas-limit 50000
               :to recipient
               :value 0)
              1
              1))
           (queued-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 2
               :gas-price 6
               :gas-limit 60000
               :to recipient
               :value 0)
              1
              1))
           (basefee-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 3
               :gas-price 4
               :gas-limit 55000
               :to recipient
               :value 0)
              1
              1))
           (pending-hash
             (hash32-to-hex (transaction-hash pending-transaction)))
           (queued-hash
             (hash32-to-hex (transaction-hash queued-transaction)))
           (basefee-hash
             (hash32-to-hex (transaction-hash basefee-transaction)))
           (sender (transaction-sender pending-transaction
                                       :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 100000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":231,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (queued-response (send-raw queued-transaction 232 store config))
             (basefee-response (send-raw basefee-transaction 233 store config))
             (pending-response (send-raw pending-transaction 234 store config))
             (initial-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":235,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":236,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (initial-status (field initial-status-response "result")))
        (is (string= queued-hash (field queued-response "result")))
        (is (string= basefee-hash (field basefee-response "result")))
        (is (string= pending-hash (field pending-response "result")))
        (is (string= (quantity-to-hex 1) (field initial-status "pending")))
        (is (string= (quantity-to-hex 2) (field initial-status "queued")))
        (is (= 1 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":237,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":238,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (pending-lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":239,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" pending-hash "\"]}")
                  store
                  config))
               (queued-lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":240,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" queued-hash "\"]}")
                  store
                  config))
               (basefee-lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":241,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" basefee-hash "\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":242,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result")))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (null (field content "pending")))
          (is (null (field content "queued")))
          (is (null (field pending-lookup-response "result")))
          (is (null (field queued-lookup-response "result")))
          (is (null (field basefee-lookup-response "result")))
          (is (= 0 (length (field filter-changes "result")))))))))

(deftest txpool-canonical-sender-code-change-removes-transactions
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (pending-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (basefee-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (blob-transaction
           (fixture-sign-blob-transaction
            (make-blob-transaction
             :chain-id 1
             :nonce 3
             :max-priority-fee-per-gas 1
             :max-fee-per-gas 6
             :gas-limit 21000
             :to recipient
             :max-fee-per-blob-gas 1
             :blob-versioned-hashes
             (list (hash32-from-hex
                    "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")))
            1))
         (sender (transaction-sender pending-transaction
                                     :expected-chain-id 1))
         (parent-block
           (make-block
            :header
            (make-block-header :number 0
                               :timestamp 0
                               :gas-limit 30000000
                               :base-fee-per-gas 5)))
         (child-block
           (make-block
            :header
            (make-block-header :parent-hash (block-hash parent-block)
                               :number 1
                               :timestamp 12
                               :gas-limit 30000000
                               :base-fee-per-gas 5))))
    (chain-store-put-block store parent-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash parent-block) sender 1000000000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     pending-transaction)
    (ethereum-lisp.core::engine-payload-store-put-queued-transaction
     store
     queued-transaction)
    (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
     store
     basefee-transaction)
    (ethereum-lisp.core::engine-payload-store-put-blob-transaction
     store
     blob-transaction)
    (chain-store-put-block store child-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash child-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash child-block) sender 1000000000)
    (chain-store-put-account-code
     store (block-hash child-block) sender #(1 2 3))
    (chain-store-set-canonical-head store (block-hash child-block))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-blob-transaction-count
            store)))
    (dolist (transaction (list pending-transaction
                               queued-transaction
                               basefee-transaction
                               blob-transaction))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pooled-transaction
            store
            (transaction-hash transaction)))))))

