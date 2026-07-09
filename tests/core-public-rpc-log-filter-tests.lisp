(in-package #:ethereum-lisp.test)

(deftest eth-rpc-log-topic-wildcard-requires-position
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x44)))
           (address
             (make-address (make-byte-vector 20 :initial-element #xaa)))
           (topic-a
             (make-hash32 (make-byte-vector 32 :initial-element #x11)))
           (topic-b
             (make-hash32 (make-byte-vector 32 :initial-element #x22)))
           (transaction
             (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 0))
           (receipt
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address address
                           :topics (list topic-a)
                           :data #(1)))))
           (block
             (make-block
              :header
              (make-block-header :number 1
                                 :gas-limit 30000000
                                 :timestamp 12)
              :transactions (list transaction)
              :receipts (list receipt))))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((first-position-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":96,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x1\","
                 "\"toBlock\":\"0x1\","
                 "\"topics\":[null]}]}")
                store
                config))
             (missing-second-position-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":97,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x1\","
                 "\"toBlock\":\"0x1\","
                 "\"topics\":[null,\"" (hash32-to-hex topic-b) "\"]}]}")
                store
                config))
             (empty-topic-set-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":98,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x1\","
                 "\"toBlock\":\"0x1\","
                 "\"topics\":[[]]}]}")
                store
                config))
             (empty-address-set-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":99,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x1\","
                 "\"toBlock\":\"0x1\","
                 "\"address\":[]}]}")
                store
                config))
             (first-position-logs
               (field first-position-response "result"))
             (missing-second-position-logs
               (field missing-second-position-response "result"))
             (empty-topic-set-logs
               (field empty-topic-set-response "result"))
             (empty-address-set-logs
               (field empty-address-set-response "result")))
        (is (= 1 (length first-position-logs)))
        (is (string= (address-to-hex address)
                     (field (first first-position-logs) "address")))
        (is (null missing-second-position-logs))
        (is (null empty-topic-set-logs))
        (is (null empty-address-set-logs))))))

(deftest eth-rpc-log-filter-defaults-to-latest
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x44)))
           (address
             (make-address (make-byte-vector 20 :initial-element #xaa)))
           (topic
             (make-hash32 (make-byte-vector 32 :initial-element #x11)))
           (tx-1
             (make-legacy-transaction :nonce 0
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 0))
           (tx-2
             (make-legacy-transaction :nonce 1
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 0))
           (tx-3
             (make-legacy-transaction :nonce 2
                                      :gas-price 1
                                      :gas-limit 21000
                                      :to recipient
                                      :value 0))
           (block-1
             (make-block
              :header
              (make-block-header :number 1
                                 :gas-limit 30000000
                                 :timestamp 12)
              :transactions (list tx-1)
              :receipts
              (list
               (make-receipt
                :status 1
                :cumulative-gas-used 21000
                :logs (list (make-log-entry
                             :address address
                             :topics (list topic)
                             :data #(1)))))))
           (block-2
             (make-block
              :header
              (make-block-header :number 2
                                 :gas-limit 30000000
                                 :timestamp 24)
              :transactions (list tx-2)
              :receipts
              (list
               (make-receipt
                :status 1
                :cumulative-gas-used 21000
                :logs (list (make-log-entry
                             :address address
                             :topics (list topic)
                             :data #(2)))))))
           (block-3
             (make-block
              :header
              (make-block-header :number 3
                                 :gas-limit 30000000
                                 :timestamp 36)
              :transactions (list tx-3)
              :receipts
              (list
               (make-receipt
                :status 1
                :cumulative-gas-used 21000
                :logs (list (make-log-entry
                             :address address
                             :topics (list topic)
                             :data #(3))))))))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (engine-payload-store-put-block store block-2 :state-available-p t)
      (let* ((default-logs-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":98,\"method\":\"eth_getLogs\",\"params\":[{}]}"
                store
                config))
             (default-logs
               (field default-logs-response "result"))
             (new-filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"eth_newFilter\",\"params\":[{}]}"
                store
                config))
             (filter-id (field new-filter-response "result"))
             (initial-changes-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":100,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (initial-changes
               (field initial-changes-response "result")))
        (is (= 1 (length default-logs)))
        (is (string= "0x02" (field (first default-logs) "data")))
        (is (string= (quantity-to-hex 2)
                     (field (first default-logs) "blockNumber")))
        (is (null initial-changes))
        (engine-payload-store-put-block store block-3 :state-available-p t)
        (let* ((later-changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":101,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (later-changes
                 (field later-changes-response "result")))
          (is (= 1 (length later-changes)))
          (is (string= "0x03" (field (first later-changes) "data")))
          (is (string= (quantity-to-hex 3)
                       (field (first later-changes) "blockNumber"))))))))

