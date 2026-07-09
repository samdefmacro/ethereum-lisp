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

(deftest txpool-basefee-transactions-promote-after-canonical-head-drop
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
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":159,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 160 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":161,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (queued-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":162,"
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
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":163,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":164,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":165,"
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
                       (field (field pending "0") "hash")))
          (is (null (field content "queued")))
          (is (= 1 (length filter-hashes)))
          (is (string= transaction-hash (first filter-hashes))))))))

(deftest txpool-pending-revalidation-treats-missing-balance-as-zero
  (let* ((store (make-engine-payload-memory-store))
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
         (sender (transaction-sender transaction :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender 0)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     transaction)
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (= 1
           (length
            (ethereum-lisp.core::engine-payload-store-revalidate-pending-transactions
             store))))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (eq transaction
            (ethereum-lisp.core::engine-payload-store-queued-transaction
             store
             (transaction-hash transaction))))))

(deftest txpool-basefee-promotion-drains-newly-contiguous-queued-tail
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
           (queued-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 5
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (basefee-hash
             (hash32-to-hex (transaction-hash basefee-transaction)))
           (queued-hash
             (hash32-to-hex (transaction-hash queued-transaction)))
           (sender (transaction-sender
                    basefee-transaction
                    :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":301,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (basefee-response (send-raw basefee-transaction 302 store config))
             (queued-response (send-raw queued-transaction 303 store config))
             (initial-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":304,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":305,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= basefee-hash (field basefee-response "result")))
        (is (string= queued-hash (field queued-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field initial-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 2)
                     (field (field initial-status-response "result")
                            "queued")))
        (is (= 0 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":306,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":307,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":308,"
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
                   "{\"jsonrpc\":\"2.0\",\"id\":309,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= (quantity-to-hex 2) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (string= basefee-hash
                       (field (field pending "0") "hash")))
          (is (string= queued-hash
                       (field (field pending "1") "hash")))
          (is (null (field content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 2 (length filter-hashes)))
          (is (string= basefee-hash (first filter-hashes)))
          (is (string= queued-hash (second filter-hashes))))))))

(deftest txpool-basefee-promotion-waits-for-contiguous-nonce
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
           (gap-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (gap-hash (hash32-to-hex (transaction-hash gap-transaction)))
           (closing-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (closing-hash
             (hash32-to-hex (transaction-hash closing-transaction)))
           (sender (transaction-sender gap-transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":189,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (gap-response (send-raw gap-transaction 190 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":191,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config)))
        (is (string= gap-hash (field gap-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field queued-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field queued-status-response "result")
                            "queued")))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((after-drop-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":192,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (after-drop-content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":193,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (after-drop-filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":194,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (after-drop-status (field after-drop-status-response "result"))
               (after-drop-content (field after-drop-content-response "result"))
               (after-drop-queued
                 (field (field after-drop-content "queued")
                        (address-to-hex sender))))
          (is (string= (quantity-to-hex 0)
                       (field after-drop-status "pending")))
          (is (string= (quantity-to-hex 1)
                       (field after-drop-status "queued")))
          (is (null (field after-drop-content "pending")))
          (is (string= gap-hash
                       (field (field after-drop-queued "1") "hash")))
          (is (= 0 (length (field after-drop-filter-changes "result")))))
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (let* ((closing-response (send-raw closing-transaction 195 store config))
               (promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":196,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (promoted-content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":197,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":198,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":199,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (promoted-status (field promoted-status-response "result"))
               (promoted-content (field promoted-content-response "result"))
               (pending
                 (field (field promoted-content "pending")
                        (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= closing-hash (field closing-response "result")))
          (is (string= (quantity-to-hex 2)
                       (field promoted-status "pending")))
          (is (string= (quantity-to-hex 0)
                       (field promoted-status "queued")))
          (is (string= closing-hash
                       (field (field pending "0") "hash")))
          (is (string= gap-hash
                       (field (field pending "1") "hash")))
          (is (null (field promoted-content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 2 (length filter-hashes)))
          (is (string= closing-hash (first filter-hashes)))
          (is (string= gap-hash (second filter-hashes))))))))

(deftest engine-payload-store-promotes-basefee-transactions-by-sender-index
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (sender-a-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-a-nonce-one
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-a-nonce-three
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 3
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-b-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            2
            1))
         (sender-a
           (transaction-sender sender-a-nonce-zero :expected-chain-id 1))
         (sender-b
           (transaction-sender sender-b-nonce-zero :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000
                                       :base-fee-per-gas 3))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender-a 0)
    (chain-store-put-account-nonce store (block-hash head-block) sender-b 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender-a 1000000)
    (chain-store-put-account-balance
     store (block-hash head-block) sender-b 1000000)
    (dolist (transaction
             (list sender-a-nonce-three
                   sender-b-nonce-zero
                   sender-a-nonce-one
                   sender-a-nonce-zero))
      (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
       store
       transaction))
    (let ((promoted
            (ethereum-lisp.core::engine-payload-store-promote-basefee-transactions
             store))
          (sender-a-pending
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender-a))
          (sender-b-pending
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender-b)))
      (is (= 3 (length promoted)))
      (is (= 3
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
              store)))
      (is (eq sender-a-nonce-zero (first sender-a-pending)))
      (is (eq sender-a-nonce-one (second sender-a-pending)))
      (is (eq sender-b-nonce-zero (first sender-b-pending)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store
            (transaction-hash sender-a-nonce-three))))
      (is (eq sender-a-nonce-three
              (ethereum-lisp.core::engine-payload-store-pooled-transaction
               store
               (transaction-hash sender-a-nonce-three)))))))

(deftest txpool-queued-promotion-rechecks-pending-balance
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (gap-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 1
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (closing-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 1
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (sender (transaction-sender gap-transaction :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender 21000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     closing-transaction)
    (ethereum-lisp.core::engine-payload-store-put-queued-transaction
     store
     gap-transaction)
    (is (null
         (ethereum-lisp.core::engine-payload-store-promote-queued-transactions
          store
          sender)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (eq closing-transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store
             (transaction-hash closing-transaction))))
    (is (eq gap-transaction
            (ethereum-lisp.core::engine-payload-store-queued-transaction
             store
             (transaction-hash gap-transaction))))))

(deftest txpool-basefee-promotion-rechecks-pending-balance
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (gap-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 4
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (closing-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (sender (transaction-sender gap-transaction :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000
                                       :base-fee-per-gas 3))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender 84000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     closing-transaction)
    (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
     store
     gap-transaction)
    (is (null
         (ethereum-lisp.core::engine-payload-store-promote-basefee-transactions
          store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
            store)))
    (is (eq closing-transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store
             (transaction-hash closing-transaction))))
    (is (eq gap-transaction
            (ethereum-lisp.core::engine-payload-store-basefee-transaction
             store
             (transaction-hash gap-transaction))))))

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

