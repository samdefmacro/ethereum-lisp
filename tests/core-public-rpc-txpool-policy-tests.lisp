(in-package #:ethereum-lisp.test)

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

