(in-package #:ethereum-lisp.test)

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

