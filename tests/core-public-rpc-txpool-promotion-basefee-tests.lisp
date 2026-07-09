(in-package #:ethereum-lisp.test)

(deftest txpool-canonical-blob-base-fee-rise-removes-underpriced-blobs
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1337
                                    :london-block 0
                                    :cancun-time 0))
         (transaction
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
         (transaction-hash (transaction-hash transaction))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :gas-limit 30000000
                               :timestamp 0
                               :blob-gas-used 0
                               :excess-blob-gas 0
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :timestamp 12
                               :blob-gas-used 0
                               :excess-blob-gas 0
                               :extra-data #(1))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :timestamp 12
                               :blob-gas-used 0
                               :excess-blob-gas (* 64 1024 1024)
                               :extra-data #(2)))))
    (is (typep transaction 'blob-transaction))
    (is (<= (block-header-blob-base-fee (block-header old-canonical-child))
            (blob-transaction-max-fee-per-blob-gas transaction)))
    (is (> (block-header-blob-base-fee (block-header new-canonical-child))
           (blob-transaction-max-fee-per-blob-gas transaction)))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (ethereum-lisp.core::engine-payload-store-put-blob-transaction
     store
     transaction)
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-blob-transaction-count
            store)))
    (is (typep
         (ethereum-lisp.core::engine-payload-store-blob-transaction
          store
          transaction-hash)
         'blob-transaction))
    (chain-store-set-canonical-head
     store
     (block-hash new-canonical-child)
     :chain-config config)
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-blob-transaction-count
            store)))
    (is (null
         (ethereum-lisp.core::engine-payload-store-pooled-transaction
          store
          transaction-hash)))))

(deftest eth-rpc-send-raw-transaction-replaces-basefee-conflict-with-pending
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
           (old-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (new-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 6
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (old-hash (hash32-to-hex (transaction-hash old-transaction)))
           (new-hash (hash32-to-hex (transaction-hash new-transaction)))
           (sender (transaction-sender new-transaction :expected-chain-id 1))
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
                "{\"jsonrpc\":\"2.0\",\"id\":151,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (old-response (send-raw old-transaction 152 store config))
             (new-response (send-raw new-transaction 153 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":154,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":155,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (old-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":156,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" old-hash "\"]}")
                store
                config))
             (new-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":157,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" new-hash "\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":158,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (filter-hashes (field filter-changes "result")))
        (is (string= old-hash (field old-response "result")))
        (is (string= new-hash (field new-response "result")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= new-hash (field (field pending "0") "hash")))
        (is (null (field content "queued")))
        (is (null (field old-lookup-response "result")))
        (is (string= new-hash
                     (field (field new-lookup-response "result") "hash")))
        (is (= 1 (length filter-hashes)))
        (is (string= new-hash (first filter-hashes)))))))

