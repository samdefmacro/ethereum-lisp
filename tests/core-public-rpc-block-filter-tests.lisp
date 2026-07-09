(in-package #:ethereum-lisp.test)

(deftest eth-rpc-block-filter
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (block-1
             (make-block
              :header (make-block-header :number 7
                                         :timestamp 70
                                         :gas-limit 30000000)))
           (block-2
             (make-block
              :header (make-block-header :number 8
                                         :timestamp 80
                                         :gas-limit 30000000)))
           (block-3
             (make-block
              :header (make-block-header :number 10
                                         :timestamp 100
                                         :gas-limit 30000000))))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (let* ((new-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":80,\"method\":\"eth_newBlockFilter\"}"
                 store
                 config)))
             (filter-id (field new-filter-response "result"))
             (initial-changes-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":81,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (first-changes-response
               (progn
                 (engine-payload-store-put-block
                  store block-2 :state-available-p t)
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":82,"
                    "\"method\":\"eth_getFilterChanges\","
                    "\"params\":[\"" filter-id "\"]}")
                   store
                   config))))
             (first-changes (field first-changes-response "result"))
             (empty-changes-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":83,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (second-changes-response
               (progn
                 (engine-payload-store-put-block
                  store block-3 :state-available-p t)
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":84,"
                    "\"method\":\"eth_getFilterChanges\","
                    "\"params\":[\"" filter-id "\"]}")
                   store
                   config))))
             (second-changes (field second-changes-response "result"))
             (get-logs-error-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":85,"
                  "\"method\":\"eth_getFilterLogs\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (uninstall-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":86,"
                  "\"method\":\"eth_uninstallFilter\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (missing-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":87,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (invalid-new-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":88,\"method\":\"eth_newBlockFilter\",\"params\":[\"unexpected\"]}"
                 store
                 config))))
        (is (string= (quantity-to-hex 1) filter-id))
        (is (search "\"result\":[]" initial-changes-json))
        (is (= 1 (length first-changes)))
        (is (string= (hash32-to-hex (block-hash block-2))
                     (first first-changes)))
        (is (search "\"result\":[]" empty-changes-json))
        (is (= 1 (length second-changes)))
        (is (string= (hash32-to-hex (block-hash block-3))
                     (first second-changes)))
        (is (= -32602
               (field (field get-logs-error-response "error") "code")))
        (is (eq t (field uninstall-response "result")))
        (is (= -32602
               (field (field missing-changes-response "error") "code")))
        (is (= -32602
               (field (field invalid-new-filter-response "error")
                      "code")))))))

(deftest eth-rpc-block-filter-records-same-height-reorg-heads
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json (engine-rpc-handle-request-json json store config)))
           (forkchoice-json (id head)
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
              ",\"method\":\"engine_forkchoiceUpdatedV1\","
              "\"params\":[{\"headBlockHash\":\"" (hash32-to-hex head)
              "\",\"safeBlockHash\":\"" (hash32-to-hex (zero-hash32))
              "\",\"finalizedBlockHash\":\"" (hash32-to-hex (zero-hash32))
              "\"}]}")))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 2
               :gas-limit 21000
               :to recipient
               :value 3)
              1
              1))
           (transaction-hash-hex
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (genesis
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :gas-limit 30000000
                                 :timestamp 0
                                 :extra-data #(0))))
           (old-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(1))
              :transactions (list transaction)
              :receipts (list (make-receipt :status 1
                                            :cumulative-gas-used 21000))))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(2)))))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (engine-payload-store-put-block
       store old-canonical-child :state-available-p t)
      (let* ((block-filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":89,\"method\":\"eth_newBlockFilter\"}"
                store
                config))
             (pending-filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":90,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (block-filter-id (field block-filter-response "result"))
             (pending-filter-id (field pending-filter-response "result")))
        (engine-payload-store-put-block
         store new-canonical-child :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash new-canonical-child) sender 0)
        (chain-store-put-account-balance
         store (block-hash new-canonical-child) sender 1000000)
        (let* ((forkchoice-response
                 (request (forkchoice-json 91 (block-hash new-canonical-child))
                          store
                          config))
               (block-changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":92,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" block-filter-id "\"]}")
                  store
                  config))
               (empty-block-changes-json
                 (engine-rpc-handle-request-json
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":93,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" block-filter-id "\"]}")
                  store
                  config))
               (pending-changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":94,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" pending-filter-id "\"]}")
                  store
                  config))
               (lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":95,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" transaction-hash-hex "\"]}")
                  store
                  config))
               (payload-status
                 (field (field forkchoice-response "result")
                        "payloadStatus"))
               (block-changes (field block-changes-response "result"))
               (pending-changes (field pending-changes-response "result"))
               (lookup-result (field lookup-response "result")))
          (is (string= +payload-status-valid+
                       (field payload-status "status")))
          (is (= 1 (length block-changes)))
          (is (string= (hash32-to-hex (block-hash new-canonical-child))
                       (first block-changes)))
          (is (search "\"result\":[]" empty-block-changes-json))
          (is (= 1 (length pending-changes)))
          (is (string= transaction-hash-hex (first pending-changes)))
          (is (string= transaction-hash-hex (field lookup-result "hash")))
          (is (null (field lookup-result "blockHash")))
          (is (null (field lookup-result "blockNumber"))))))))

