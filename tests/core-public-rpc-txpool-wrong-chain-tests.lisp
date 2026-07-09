(in-package #:ethereum-lisp.test)

(deftest txpool-queued-transactions-promote-after-canonical-nonce-advance
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
               :nonce 1
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
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":166,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 167 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":168,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (queued-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":169,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field queued-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field queued-status-response "result")
                            "queued")))
        (is (= 0 (length (field queued-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":170,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":171,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":172,"
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
                   "{\"jsonrpc\":\"2.0\",\"id\":173,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field promoted-status-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= (quantity-to-hex 1) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (string= transaction-hash
                       (field (field pending "1") "hash")))
          (is (null (field content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 1 (length filter-hashes)))
          (is (string= transaction-hash (first filter-hashes))))))))

(deftest txpool-promotion-drops-wrong-chain-queued-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (empty-object-p (object)
             (or (null object)
                 (typep object 'ethereum-lisp.core::json-empty-object)))
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
           (wrong-chain-nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              2))
           (nonce-zero-hash
             (hash32-to-hex (transaction-hash nonce-zero)))
           (wrong-chain-hash
             (hash32-to-hex (transaction-hash wrong-chain-nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (wrong-chain-sender
             (transaction-sender wrong-chain-nonce-one :expected-chain-id 2))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (is (null (transaction-sender
                 wrong-chain-nonce-one
                 :expected-chain-id 1)))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (ethereum-lisp.core::engine-payload-store-put-queued-transaction
       store
       wrong-chain-nonce-one)
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-queued-transaction-count
              store)))
      (let ((wrong-chain-pre-cleanup-status-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":187,\"method\":\"txpool_status\",\"params\":[]}"
               store
               config))
            (wrong-chain-pre-cleanup-pending-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":188,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
               store
               config))
            (wrong-chain-pre-cleanup-content-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":189,\"method\":\"txpool_content\",\"params\":[]}"
               store
               config))
            (wrong-chain-pre-cleanup-content-from-response
              (request
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":190,"
                "\"method\":\"txpool_contentFrom\",\"params\":[\""
                (address-to-hex wrong-chain-sender)
                "\"]}")
               store
               config))
            (wrong-chain-pre-cleanup-inspect-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":191,\"method\":\"txpool_inspect\",\"params\":[]}"
               store
               config))
            (wrong-chain-pre-cleanup-lookup-response
              (request
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":192,"
                "\"method\":\"eth_getTransactionByHash\","
                "\"params\":[\"" wrong-chain-hash "\"]}")
               store
               config))
            (wrong-chain-pre-cleanup-raw-response
              (request
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":193,"
                "\"method\":\"eth_getRawTransactionByHash\","
                "\"params\":[\"" wrong-chain-hash "\"]}")
               store
               config)))
        (let ((status (field wrong-chain-pre-cleanup-status-response
                             "result")))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued"))))
        (is (= 0 (length (field wrong-chain-pre-cleanup-pending-response
                                "result"))))
        (dolist (response (list wrong-chain-pre-cleanup-content-response
                                wrong-chain-pre-cleanup-content-from-response
                                wrong-chain-pre-cleanup-inspect-response))
          (let ((result (field response "result")))
            (is (empty-object-p (field result "pending")))
            (is (empty-object-p (field result "queued")))))
        (is (null (field wrong-chain-pre-cleanup-lookup-response "result")))
        (is (null (field wrong-chain-pre-cleanup-raw-response "result"))))
      (let* ((send-response (send-raw nonce-zero 189 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":190,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":191,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (wrong-chain-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":192,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" wrong-chain-hash "\"]}")
                store
                config))
             (wrong-chain-raw-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":193,"
                 "\"method\":\"eth_getRawTransactionByHash\","
                 "\"params\":[\"" wrong-chain-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender))))
        (is (string= nonce-zero-hash (field send-response "result")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= nonce-zero-hash
                     (field (field pending "0") "hash")))
        (is (null (field content "queued")))
        (is (null (field wrong-chain-lookup-response "result")))
        (is (null (field wrong-chain-raw-response "result")))))))

(deftest txpool-pending-nonce-ignores-wrong-chain-pending-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (empty-object-p (object)
             (or (null object)
                 (typep object 'ethereum-lisp.core::json-empty-object)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (send-raw (transaction id store config)
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
               ",\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\""
               (bytes-to-hex (transaction-encoding transaction))
               "\"]}")
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (wrong-chain-nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              2))
           (valid-nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (wrong-chain-hash
             (hash32-to-hex (transaction-hash wrong-chain-nonce-zero)))
           (valid-hash
             (hash32-to-hex (transaction-hash valid-nonce-one)))
           (sender
             (transaction-sender valid-nonce-one :expected-chain-id 1))
           (wrong-chain-sender
             (transaction-sender wrong-chain-nonce-zero :expected-chain-id 2))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (is (bytes= (address-bytes sender)
                  (address-bytes wrong-chain-sender)))
      (is (null (transaction-sender
                 wrong-chain-nonce-zero
                 :expected-chain-id 1)))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (ethereum-lisp.core::engine-payload-store-put-pending-transaction
       store
       wrong-chain-nonce-zero)
      (let* ((pre-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":201,"
                 "\"method\":\"eth_getTransactionCount\",\"params\":[\""
                 (address-to-hex sender) "\",\"pending\"]}")
                store
                config))
             (send-response
               (send-raw valid-nonce-one 202 store config))
             (post-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":203,"
                 "\"method\":\"eth_getTransactionCount\",\"params\":[\""
                 (address-to-hex sender) "\",\"pending\"]}")
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":204,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":205,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex sender) "\"]}")
                store
                config))
             (wrong-chain-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":206,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" wrong-chain-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending (field content "pending"))
             (queued (field content "queued")))
        (is (string= (quantity-to-hex 0)
                     (field pre-count-response "result")))
        (is (string= valid-hash (field send-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field post-count-response "result")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (empty-object-p pending))
        (is (string= valid-hash (field (field queued "1") "hash")))
        (is (null (field wrong-chain-lookup-response "result")))))))

