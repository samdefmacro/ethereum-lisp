(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-raw-transaction-by-block-and-index
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (tx-1
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 1
                                       :gas-price 7
                                       :gas-limit 21000
                                       :value 3)
              1
              1))
           (tx-2
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 2
                                       :gas-price 9
                                       :gas-limit 21000
                                       :value 4)
              1
              1))
           (wrong-chain-tx
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 3
                                       :gas-price 11
                                       :gas-limit 21000
                                       :value 5)
              1
              2))
           (block
             (make-block
              :header (make-block-header :number 12
                                         :timestamp 120
                                         :gas-limit 30000000)
              :transactions (list tx-1 tx-2 wrong-chain-tx)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (wrong-chain-hash-hex
             (hash32-to-hex (transaction-hash wrong-chain-tx)))
           (config (make-chain-config)))
      (is (transaction-sender tx-1 :expected-chain-id 1))
      (is (transaction-sender tx-2 :expected-chain-id 1))
      (is (transaction-sender wrong-chain-tx :expected-chain-id 2))
      (is (null (transaction-sender wrong-chain-tx :expected-chain-id 1)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":44,\"method\":\"eth_getRawTransactionByBlockNumberAndIndex\",\"params\":[\"0xc\",\"0x1\"]}"
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":45,"
                  "\"method\":\"eth_getRawTransactionByBlockHashAndIndex\","
                  "\"params\":[\"" hash-hex "\",\"0x0\"]}")
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":46,\"method\":\"eth_getRawTransactionByBlockNumberAndIndex\",\"params\":[\"0x63\",\"0x0\"]}"
                 store
                 config)))
             (out-of-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":47,\"method\":\"eth_getRawTransactionByBlockNumberAndIndex\",\"params\":[\"0xc\",\"0x3\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":48,\"method\":\"eth_getRawTransactionByBlockHashAndIndex\",\"params\":[\"0x1234\",\"0x0\"]}"
                 store
                 config)))
             (wrong-chain-number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":49,\"method\":\"eth_getRawTransactionByBlockNumberAndIndex\",\"params\":[\"0xc\",\"0x2\"]}"
                 store
                 config)))
             (wrong-chain-index-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":50,"
                  "\"method\":\"eth_getRawTransactionByBlockHashAndIndex\","
                  "\"params\":[\"" hash-hex "\",\"0x2\"]}")
                 store
                 config)))
             (wrong-chain-hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":51,"
                  "\"method\":\"eth_getRawTransactionByHash\","
                  "\"params\":[\"" wrong-chain-hash-hex "\"]}")
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= (bytes-to-hex (transaction-encoding tx-2))
                     (field number-response "result")))
        (is (string= (bytes-to-hex (transaction-encoding tx-1))
                     (field hash-response "result")))
        (is (null (field missing-response "result")))
        (is (null (field out-of-range-response "result")))
        (is (null (field wrong-chain-number-response "result")))
        (is (null (field wrong-chain-index-response "result")))
        (is (null (field wrong-chain-hash-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-transaction-by-block-and-index
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
              :header (make-block-header :number 13
                                         :timestamp 130
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)
              :transactions (list tx-1 tx-2)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (tx-2-from (transaction-sender tx-2))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":49,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"0xd\",\"0x1\"]}"
                 store
                 config)))
             (number-result (field number-response "result"))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":50,"
                  "\"method\":\"eth_getTransactionByBlockHashAndIndex\","
                  "\"params\":[\"" hash-hex "\",\"0x0\"]}")
                 store
                 config)))
             (hash-result (field hash-response "result"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":51,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"0x63\",\"0x0\"]}"
                 store
                 config)))
             (out-of-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":52,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"0xd\",\"0x2\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":53,\"method\":\"eth_getTransactionByBlockHashAndIndex\",\"params\":[\"0x1234\",\"0x0\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= hash-hex (field number-result "blockHash")))
        (is (string= (quantity-to-hex 13)
                     (field number-result "blockNumber")))
        (is (string= (quantity-to-hex 130)
                     (field number-result "blockTimestamp")))
        (is (string= (address-to-hex tx-2-from)
                     (field number-result "from")))
        (is (string= (quantity-to-hex #x84d0)
                     (field number-result "gas")))
        (is (string= (quantity-to-hex 5)
                     (field number-result "gasPrice")))
        (is (string= (hash32-to-hex (transaction-hash tx-2))
                     (field number-result "hash")))
        (is (string= "0x" (field number-result "input")))
        (is (string= (quantity-to-hex 1)
                     (field number-result "nonce")))
        (is (string= (address-to-hex dynamic-recipient)
                     (field number-result "to")))
        (is (string= (quantity-to-hex 1)
                     (field number-result "transactionIndex")))
        (is (string= (quantity-to-hex 0)
                     (field number-result "value")))
        (is (string= (quantity-to-hex 2)
                     (field number-result "type")))
        (is (string= (quantity-to-hex 1)
                     (field number-result "chainId")))
        (is (string= (quantity-to-hex #x0fa0)
                     (field number-result "maxFeePerGas")))
        (is (string= (quantity-to-hex 0)
                     (field number-result "maxPriorityFeePerGas")))
        (is (string= (quantity-to-hex 1)
                     (field number-result "yParity")))
        (is (string= (quantity-to-hex 1) (field number-result "v")))
        (is (string= (quantity-to-hex #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0)
                     (field number-result "r")))
        (is (string= (quantity-to-hex #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904)
                     (field number-result "s")))
        (is (string= hash-hex (field hash-result "blockHash")))
        (is (string= (hash32-to-hex (transaction-hash tx-1))
                     (field hash-result "hash")))
        (is (string= (quantity-to-hex 0) (field hash-result "type")))
        (is (string= (quantity-to-hex 20000000000)
                     (field hash-result "gasPrice")))
        (is (string= "0x" (field hash-result "input")))
        (is (string= (address-to-hex recipient)
                     (field hash-result "to")))
        (is (string= (quantity-to-hex 0)
                     (field hash-result "transactionIndex")))
        (is (null (field missing-response "result")))
        (is (null (field out-of-range-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

