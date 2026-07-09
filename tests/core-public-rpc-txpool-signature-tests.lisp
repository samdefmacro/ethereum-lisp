(in-package #:ethereum-lisp.test)

(deftest eth-rpc-send-raw-transaction-returns-known-hash-before-admission
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
    (let* ((config (make-chain-config))
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
           (transaction-hash (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1)))
      (let* ((store (make-engine-payload-memory-store))
             (head-block
               (make-block
                :header (make-block-header :number 0
                                           :timestamp 0
                                           :gas-limit 30000000))))
        (chain-store-put-block store head-block :state-available-p t)
        (chain-store-put-account-nonce store (block-hash head-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash head-block) sender 21000)
        (is (string= transaction-hash
                     (field (send-raw transaction 92 store config)
                            "result")))
        (chain-store-put-account-nonce store (block-hash head-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash head-block) sender 0)
        (let* ((resend-response (send-raw transaction 93 store config))
               (status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":94,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config))))
          (is (string= transaction-hash (field resend-response "result")))
          (is (null (field resend-response "error")))
          (is (string= (quantity-to-hex 1)
                       (field (field status-response "result") "pending")))))
      (let* ((store (make-engine-payload-memory-store))
             (mined-block
               (make-block
                :header (make-block-header :number 0
                                           :timestamp 0
                                           :gas-limit 30000000)
                :transactions (list transaction))))
        (chain-store-put-block store mined-block :state-available-p t)
        (chain-store-put-account-nonce store (block-hash mined-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash mined-block) sender 0)
        (let* ((resend-response (send-raw transaction 95 store config))
               (status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":96,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config))))
          (is (string= transaction-hash (field resend-response "result")))
          (is (null (field resend-response "error")))
          (is (string= (quantity-to-hex 0)
                       (field (field status-response "result") "pending"))))))))

(deftest eth-rpc-send-raw-transaction-requires-recoverable-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (raw-transaction
             (bytes-to-hex (transaction-encoding transaction)))
           (config (make-chain-config :chain-id 2))
           (new-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":92,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (filter-id (field new-filter-response "result"))
           (send-response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":93,"
                "\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\"" raw-transaction "\"]}")
               store
               config)))
           (pending-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":94,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
               store
               config)))
           (status-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":95,\"method\":\"txpool_status\",\"params\":[]}"
               store
               config)))
           (filter-response
             (engine-rpc-handle-request-json
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":96,"
               "\"method\":\"eth_getFilterChanges\","
               "\"params\":[\"" filter-id "\"]}")
              store
              config))
           (send-error (field send-response "error"))
           (status (field status-response "result")))
      (is (= -32602 (field send-error "code")))
      (is (= 0 (length (field pending-response "result"))))
      (is (string= (quantity-to-hex 0) (field status "pending")))
      (is (search "\"result\":[]" filter-response)))))

(deftest eth-rpc-send-raw-transaction-rejects-malformed-signatures
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (bad-y-parity-transaction
             (make-dynamic-fee-transaction
              :chain-id 1
              :nonce 1
              :max-priority-fee-per-gas 0
              :max-fee-per-gas #x0fa0
              :gas-limit #x84d0
              :to recipient
              :value 0
              :y-parity 2
              :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
              :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904))
           (high-s-transaction
             (make-dynamic-fee-transaction
              :chain-id 1
              :nonce 1
              :max-priority-fee-per-gas 0
              :max-fee-per-gas #x0fa0
              :gas-limit #x84d0
              :to recipient
              :value 0
              :y-parity 1
              :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
              :s #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1))
           (config (make-chain-config))
           (new-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":100,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (filter-id (field new-filter-response "result"))
           (bad-y-parity-response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":101,"
                "\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex
                 (transaction-encoding bad-y-parity-transaction))
                "\"]}")
               store
               config)))
           (high-s-response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":102,"
                "\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding high-s-transaction))
                "\"]}")
               store
               config)))
           (pending-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":103,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
               store
               config)))
           (status-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":104,\"method\":\"txpool_status\",\"params\":[]}"
               store
               config)))
           (filter-response
             (engine-rpc-handle-request-json
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":105,"
               "\"method\":\"eth_getFilterChanges\","
               "\"params\":[\"" filter-id "\"]}")
              store
              config))
           (bad-y-parity-error (field bad-y-parity-response "error"))
           (high-s-error (field high-s-response "error"))
           (status (field status-response "result")))
      (is (= -32602 (field bad-y-parity-error "code")))
      (is (= -32602 (field high-s-error "code")))
      (is (= 0 (length (field pending-response "result"))))
      (is (string= (quantity-to-hex 0) (field status "pending")))
      (is (search "\"result\":[]" filter-response)))))

(deftest eth-rpc-send-raw-transaction-rejects-malformed-set-code-authorizations
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
           (first-authorization (transaction)
             (first (set-code-transaction-authorization-list transaction))))
    (let* ((raw-transaction
             "0x04f90126820539800285012a05f2008307a1209471562b71999873db5b286df957af199ec94617f78080c0f8baf85c82053994000000000000000000000000000000000000aaaa0101a07ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461a001b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669f85a8094000000000000000000000000000000000000bbbb8001a05011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98a056c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf6101a0167b0ecfc343a497095c22ee4270d3cc3b971cc3599fc73bbff727e0d2ed432da01c003c72306807492bf1150e39b2f79da23b49a4e83eb6e9209ae30d3572368f")
           (store (make-engine-payload-memory-store))
           (bad-y-parity-transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (high-s-transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (config (make-chain-config :chain-id 1337))
           (new-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":106,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (filter-id (field new-filter-response "result")))
      (setf (set-code-authorization-y-parity
             (first-authorization bad-y-parity-transaction))
            2)
      (setf (set-code-authorization-s
             (first-authorization high-s-transaction))
            #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1)
      (let* ((bad-y-parity-response
               (send-raw bad-y-parity-transaction 107 store config))
             (high-s-response
               (send-raw high-s-transaction 108 store config))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":109,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                 store
                 config)))
             (status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":110,\"method\":\"txpool_status\",\"params\":[]}"
                 store
                 config)))
             (filter-response
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":111,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (bad-y-parity-error (field bad-y-parity-response "error"))
             (high-s-error (field high-s-response "error"))
             (status (field status-response "result")))
        (is (= -32602 (field bad-y-parity-error "code")))
        (is (string= "Authorization signature values are invalid"
                     (field bad-y-parity-error "message")))
        (is (= -32602 (field high-s-error "code")))
        (is (string= "Authorization signature values are invalid"
                     (field high-s-error "message")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (search "\"result\":[]" filter-response))))))

