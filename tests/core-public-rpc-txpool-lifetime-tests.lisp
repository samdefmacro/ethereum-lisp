(in-package #:ethereum-lisp.test)

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

