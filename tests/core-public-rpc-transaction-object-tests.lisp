(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-transaction-by-hash
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (dynamic-recipient
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (tx-1 (make-legacy-transaction :nonce 9
                                          :gas-price 20000000000
                                          :gas-limit 21000
                                          :to recipient
                                          :value 1000000000000000000
                                          :v 37
                                          :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                                          :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (tx-2 (make-dynamic-fee-transaction
                  :chain-id 1
                  :nonce 1
                  :max-priority-fee-per-gas 0
                  :max-fee-per-gas #x0fa0
                  :gas-limit #x84d0
                  :to dynamic-recipient
                  :value 0
                  :data #()
                  :y-parity 1
                  :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
                  :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904))
           (block
             (make-block
              :header (make-block-header :number 14
                                         :timestamp 140
                                         :gas-limit 30000000
                                         :base-fee-per-gas 6)
              :transactions (list tx-1 tx-2)))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (tx-2-hash-hex (hash32-to-hex (transaction-hash tx-2)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((transaction-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":55,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\"" tx-2-hash-hex "\"]}")
                 store
                 config)))
             (transaction-result (field transaction-response "result"))
             (raw-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":56,"
                  "\"method\":\"eth_getRawTransactionByHash\","
                  "\"params\":[\"" tx-2-hash-hex "\"]}")
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":57,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\"]}")
                 store
                 config)))
             (missing-raw-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":58,"
                  "\"method\":\"eth_getRawTransactionByHash\","
                  "\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\"]}")
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":59,\"method\":\"eth_getTransactionByHash\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= tx-2-hash-hex (field transaction-result "hash")))
        (is (string= block-hash-hex
                     (field transaction-result "blockHash")))
        (is (string= (quantity-to-hex 14)
                     (field transaction-result "blockNumber")))
        (is (string= (quantity-to-hex 140)
                     (field transaction-result "blockTimestamp")))
        (is (string= (quantity-to-hex 1)
                     (field transaction-result "transactionIndex")))
        (is (string= (quantity-to-hex 6)
                     (field transaction-result "gasPrice")))
        (is (string= (quantity-to-hex 2)
                     (field transaction-result "type")))
        (is (string= (bytes-to-hex (transaction-encoding tx-2))
                     (field raw-response "result")))
        (is (null (field missing-response "result")))
        (is (null (field missing-raw-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-transaction-objects-require-recoverable-sender
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
              :r 0
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (transaction-hash-hex (hash32-to-hex (transaction-hash transaction)))
           (block
             (make-block
              :header (make-block-header :number 16
                                         :timestamp 160
                                         :gas-limit 30000000)
              :transactions (list transaction)
              :receipts (list (make-receipt :status 1
                                            :cumulative-gas-used 21000))))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((by-hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":97,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\"" transaction-hash-hex "\"]}")
                 store
                 config)))
             (by-index-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":98,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"0x10\",\"0x0\"]}"
                 store
                 config)))
             (full-block-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":99,"
                  "\"method\":\"eth_getBlockByHash\","
                  "\"params\":[\"" block-hash-hex "\",true]}")
                 store
                 config)))
             (receipt-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":100,"
                  "\"method\":\"eth_getTransactionReceipt\","
                  "\"params\":[\"" transaction-hash-hex "\"]}")
                 store
                 config)))
             (block-receipts-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":101,\"method\":\"eth_getBlockReceipts\",\"params\":[\"0x10\"]}"
                 store
                 config)))
             (by-hash-error (field by-hash-response "error"))
             (by-index-error (field by-index-response "error"))
             (full-block-error (field full-block-response "error"))
             (receipt-error (field receipt-response "error"))
             (block-receipts-error (field block-receipts-response "error")))
        (is (= -32602 (field by-hash-error "code")))
        (is (= -32602 (field by-index-error "code")))
        (is (= -32602 (field full-block-error "code")))
        (is (= -32602 (field receipt-error "code")))
        (is (= -32602 (field block-receipts-error "code")))))))

(deftest eth-rpc-transaction-objects-enforce-configured-chain-id
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (empty-object-p (object)
             (or (null object)
                 (typep object 'ethereum-lisp.json:json-empty-object))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 100
               :gas-limit 21000
               :to recipient)
              1
              2))
           (sender (transaction-sender transaction :expected-chain-id 2))
           (transaction-hash-hex (hash32-to-hex (transaction-hash transaction)))
           (config (make-chain-config :chain-id 1))
           (pending-filter-response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":101,\"method\":\"eth_newPendingTransactionFilter\"}"
               store
               config)))
           (pending-filter-id (field pending-filter-response "result")))
      (is sender)
      (is (null (transaction-sender transaction :expected-chain-id 1)))
      (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
       store
       transaction)
      (let* ((pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":102,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                 store
                 config)))
             (content-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":103,\"method\":\"txpool_content\",\"params\":[]}"
                 store
                 config)))
             (content-from-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":104,"
                  "\"method\":\"txpool_contentFrom\",\"params\":[\""
                  (address-to-hex sender)
                  "\"]}")
                 store
                 config)))
             (by-hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":105,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\"" transaction-hash-hex "\"]}")
                 store
                 config)))
             (pending-filter-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":106,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" pending-filter-id "\"]}")
                 store
                 config))))
        (is (= 0 (length (field pending-response "result"))))
        (dolist (response (list content-response content-from-response))
          (let ((result (field response "result")))
            (is (empty-object-p (field result "pending")))
            (is (empty-object-p (field result "queued")))))
        (is (= 0 (length (field pending-filter-changes-response "result"))))
        (is (null (field by-hash-response "result")))))))

