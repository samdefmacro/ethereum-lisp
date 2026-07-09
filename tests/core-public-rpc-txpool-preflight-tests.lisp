(in-package #:ethereum-lisp.test)

(deftest eth-rpc-send-raw-transaction-applies-basic-admission-preflight
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
               config))))
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (low-gas-store (make-engine-payload-memory-store))
           (typed-store (make-engine-payload-memory-store))
           (over-gas-store (make-engine-payload-memory-store))
           (nonce-store (make-engine-payload-memory-store))
           (balance-store (make-engine-payload-memory-store))
           (missing-balance-store (make-engine-payload-memory-store))
           (sender-code-store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (low-gas-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0
               :data #(1))
              private-key
              1))
           (unsupported-access-transaction
             (make-access-list-transaction
              :chain-id 1
              :nonce 3
              :gas-price 1
              :gas-limit 25000
              :to (address-from-hex
                   "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
              :value 10
              :data (hex-to-bytes "0x5544")
              :y-parity 1
              :r #xc9519f4f2b30335884581971573fadf60c6204f59a911df35ee8a540456b2660
              :s #x32f1e8e2c5dd761f9e4f88f41c8310aeaba26a8bfcdacfedfa12ec3862d37521))
           (over-gas-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 30000001
               :to recipient
               :value 0)
              private-key
              1))
           (sender-code-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (nonce-too-low-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (insufficient-balance-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 10
               :gas-limit 21000
               :to recipient
               :value 1)
              private-key
              1))
           (sender (transaction-sender sender-code-transaction
                                       :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block nonce-store head-block :state-available-p t)
      (chain-store-put-account-nonce
       nonce-store (block-hash head-block) sender 2)
      (chain-store-put-account-balance
       nonce-store (block-hash head-block) sender 1000000)
      (chain-store-put-block over-gas-store head-block :state-available-p t)
      (chain-store-put-account-nonce
       over-gas-store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       over-gas-store (block-hash head-block) sender 100000000)
      (chain-store-put-block balance-store head-block :state-available-p t)
      (chain-store-put-account-balance
       balance-store (block-hash head-block) sender 100)
      (chain-store-put-block missing-balance-store
                             head-block
                             :state-available-p t)
      (engine-payload-store-put-block sender-code-store head-block)
      (engine-payload-store-put-account-balance
       sender-code-store (block-hash head-block) sender 1000000)
      (engine-payload-store-put-account-code
       sender-code-store (block-hash head-block) sender #(1 2 3))
      (let* ((low-gas-response
               (send-raw low-gas-transaction 112 low-gas-store config))
             (typed-response
               (send-raw unsupported-access-transaction 113 typed-store config))
             (over-gas-response
               (send-raw over-gas-transaction 124 over-gas-store config))
             (nonce-too-low-response
               (send-raw nonce-too-low-transaction 114 nonce-store config))
             (insufficient-balance-response
               (send-raw insufficient-balance-transaction
                         115
                         balance-store
                         config))
             (missing-balance-response
               (send-raw insufficient-balance-transaction
                         122
                         missing-balance-store
                         config))
             (sender-code-response
               (send-raw sender-code-transaction
                         116
                         sender-code-store
                         config))
             (low-gas-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":117,\"method\":\"txpool_status\",\"params\":[]}"
                 low-gas-store
                 config)))
             (typed-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":118,\"method\":\"txpool_status\",\"params\":[]}"
                 typed-store
                 config)))
             (over-gas-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_status\",\"params\":[]}"
                 over-gas-store
                 config)))
             (nonce-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":119,\"method\":\"txpool_status\",\"params\":[]}"
                 nonce-store
                 config)))
             (balance-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":120,\"method\":\"txpool_status\",\"params\":[]}"
                 balance-store
                 config)))
             (missing-balance-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":123,\"method\":\"txpool_status\",\"params\":[]}"
                 missing-balance-store
                 config)))
             (sender-code-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":121,\"method\":\"txpool_status\",\"params\":[]}"
                 sender-code-store
                 config))))
        (is (= -32602 (field (field low-gas-response "error") "code")))
        (is (string= "eth_sendRawTransaction gas limit below intrinsic gas"
                     (field (field low-gas-response "error") "message")))
        (is (= -32602 (field (field typed-response "error") "code")))
        (is (string= "Access-list transaction before Berlin"
                     (field (field typed-response "error") "message")))
        (is (= -32602 (field (field over-gas-response "error") "code")))
        (is (string= "eth_sendRawTransaction gas limit exceeds block gas limit"
                     (field (field over-gas-response "error") "message")))
        (is (= -32602
               (field (field nonce-too-low-response "error") "code")))
        (is (string= "eth_sendRawTransaction nonce too low"
                     (field (field nonce-too-low-response "error")
                            "message")))
        (is (= -32602
               (field (field insufficient-balance-response "error")
                      "code")))
        (is (string=
             "eth_sendRawTransaction insufficient sender balance"
             (field (field insufficient-balance-response "error")
                    "message")))
        (is (= -32602
               (field (field missing-balance-response "error")
                      "code")))
        (is (string=
             "eth_sendRawTransaction insufficient sender balance"
             (field (field missing-balance-response "error")
                    "message")))
        (is (= -32602 (field (field sender-code-response "error") "code")))
        (is (string=
             "eth_sendRawTransaction sender has non-delegation code"
             (field (field sender-code-response "error") "message")))
        (dolist (status-response
                 (list low-gas-status
                       typed-status
                       over-gas-status
                       nonce-status
                       balance-status
                       missing-balance-status
                       sender-code-status))
          (is (string= (quantity-to-hex 0)
                       (field (field status-response "result")
                              "pending"))))))))

(deftest eth-rpc-send-raw-transaction-enforces-pending-balance-expenditure
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
           (first-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender first-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 30000)
      (let* ((first-response (send-raw first-transaction 122 store config))
             (second-response (send-raw second-transaction 123 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":124,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":126,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= first-hash (field first-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= first-hash (field (field pending "0") "hash")))
        (is (null (field pending "1")))
        (is (null (field content "queued")))
        (is (null (field second-lookup-response "result")))))))

(deftest eth-rpc-send-raw-transaction-enforces-pooled-balance-expenditure
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
           (first-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 2
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender first-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 30000)
      (let* ((first-response (send-raw first-transaction 127 store config))
             (second-response (send-raw second-transaction 128 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":129,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":130,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":131,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= first-hash (field first-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= first-hash (field (field queued "1") "hash")))
        (is (null (field queued "2")))
        (is (null (field second-lookup-response "result")))))
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
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (basefee-hash
             (hash32-to-hex (transaction-hash basefee-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender basefee-transaction
                                       :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 100000)
      (let* ((basefee-response
               (send-raw basefee-transaction 132 store config))
             (second-response (send-raw second-transaction 133 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":134,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":135,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":136,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= basefee-hash (field basefee-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= basefee-hash (field (field queued "0") "hash")))
        (is (null (field queued "1")))
        (is (null (field second-lookup-response "result")))))))

