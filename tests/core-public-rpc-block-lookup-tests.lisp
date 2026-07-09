(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-block-by-number-with-transaction-hashes
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (make-legacy-transaction :nonce 1
                                      :gas-price 20000000000
                                      :gas-limit 21000
                                      :to recipient
                                      :value 1000000000000000000
                                      :v 37
                                      :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                                      :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (withdrawal
             (make-withdrawal :index 1
                              :validator-index 2
                              :address recipient
                              :amount 4))
           (ommer (make-block-header :number 7
                                     :timestamp 70))
           (block
             (make-block
              :header (make-block-header :number 8
                                         :timestamp 80
                                         :gas-limit 30000000
                                         :gas-used 21000
                                         :base-fee-per-gas 9)
              :transactions (list transaction)
              :ommers (list ommer)
              :withdrawals (list withdrawal)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":28,\"method\":\"eth_getBlockByNumber\",\"params\":[\"0x8\",false]}"
                 store
                 config)))
             (result (field response "result"))
             (transactions (field result "transactions"))
             (uncles (field result "uncles"))
             (withdrawals (field result "withdrawals"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":29,\"method\":\"eth_getBlockByNumber\",\"params\":[\"0x63\",false]}"
                 store
                 config)))
             (full-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"eth_getBlockByNumber\",\"params\":[\"0x8\",true]}"
                 store
                 config)))
             (full-result (field full-response "result"))
             (full-transactions (field full-result "transactions"))
             (full-transaction (first full-transactions)))
        (is (string= (quantity-to-hex 8) (field result "number")))
        (is (string= (hash32-to-hex (block-hash block))
                     (field result "hash")))
        (is (stringp (field result "size")))
        (is (= 1 (length transactions)))
        (is (string= (hash32-to-hex (transaction-hash transaction))
                     (first transactions)))
        (is (= 1 (length uncles)))
        (is (string= (hash32-to-hex (block-header-hash ommer))
                     (first uncles)))
        (is (= 1 (length withdrawals)))
        (is (string= (quantity-to-hex 1)
                     (field (first withdrawals) "index")))
        (is (null (field missing-response "result")))
        (is (string= (field result "hash")
                     (field full-result "hash")))
        (is (= 1 (length full-transactions)))
        (is (string= (hash32-to-hex (transaction-hash transaction))
                     (field full-transaction "hash")))
        (is (string= (field result "hash")
                     (field full-transaction "blockHash")))
        (is (string= (quantity-to-hex 8)
                     (field full-transaction "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field full-transaction "transactionIndex")))
        (is (string= (address-to-hex recipient)
                     (field full-transaction "to")))
        (is (string= (address-to-hex
                      (transaction-sender transaction))
                     (field full-transaction "from")))
        (is (string= (quantity-to-hex 0)
                     (field full-transaction "type")))))))

(deftest eth-rpc-get-block-by-hash-with-transaction-hashes
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
           (block
             (make-block
              :header (make-block-header :number 9
                                         :timestamp 90
                                         :gas-limit 30000000
                                         :gas-used 21000
                                         :base-fee-per-gas 10)
              :transactions (list transaction)))
           (hash (block-hash block))
           (hash-hex (hash32-to-hex hash))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":31,"
                  "\"method\":\"eth_getBlockByHash\",\"params\":[\""
                  hash-hex "\",false]}")
                 store
                 config)))
             (result (field response "result"))
             (transactions (field result "transactions"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":32,"
                  "\"method\":\"eth_getBlockByHash\",\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\",false]}")
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":33,\"method\":\"eth_getBlockByHash\",\"params\":[\"0x1234\",false]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error"))
             (full-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":54,"
                  "\"method\":\"eth_getBlockByHash\",\"params\":[\""
                  hash-hex "\",true]}")
                 store
                 config)))
             (full-result (field full-response "result"))
             (full-transaction (first (field full-result "transactions"))))
        (is (string= (quantity-to-hex 9) (field result "number")))
        (is (string= hash-hex (field result "hash")))
        (is (= 1 (length transactions)))
        (is (string= (hash32-to-hex (transaction-hash transaction))
                     (first transactions)))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))
        (is (string= hash-hex (field full-transaction "blockHash")))
        (is (string= (hash32-to-hex (transaction-hash transaction))
                     (field full-transaction "hash")))
        (is (string= (quantity-to-hex 9)
                     (field full-transaction "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field full-transaction "transactionIndex")))))))

(deftest eth-rpc-get-block-transaction-count
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (tx-1 (make-legacy-transaction :nonce 1
                                          :gas-price 7
                                          :gas-limit 21000))
           (tx-2 (make-legacy-transaction :nonce 2
                                          :gas-price 8
                                          :gas-limit 21000))
           (block
             (make-block
              :header (make-block-header :number 10
                                         :timestamp 100
                                         :gas-limit 30000000)
              :transactions (list tx-1 tx-2)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":34,\"method\":\"eth_getBlockTransactionCountByNumber\",\"params\":[\"0xa\"]}"
                 store
                 config)))
             (latest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":35,\"method\":\"eth_getBlockTransactionCountByNumber\",\"params\":[\"latest\"]}"
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":36,"
                  "\"method\":\"eth_getBlockTransactionCountByHash\","
                  "\"params\":[\"" hash-hex "\"]}")
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":37,\"method\":\"eth_getBlockTransactionCountByNumber\",\"params\":[\"0x63\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":38,\"method\":\"eth_getBlockTransactionCountByHash\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= (quantity-to-hex 2)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 2)
                     (field latest-response "result")))
        (is (string= (quantity-to-hex 2)
                     (field hash-response "result")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

