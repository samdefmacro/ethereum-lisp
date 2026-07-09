(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-header-by-number
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (beneficiary
             (make-address (make-byte-vector 20 :initial-element #xab)))
           (genesis
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 1
                                         :gas-limit 30000000)
              :withdrawals '()
              :requests '()
              :block-access-list '()))
           (parent-hash (block-hash genesis))
           (header
             (make-block-header
              :parent-hash parent-hash
              :beneficiary beneficiary
              :state-root +empty-trie-hash+
              :difficulty 0
              :number 12
              :gas-limit 30000000
              :gas-used 21000
              :timestamp 123
              :extra-data #(170 187)
              :mix-hash (zero-hash32)
              :nonce (make-byte-vector 8)
              :base-fee-per-gas 7
              :blob-gas-used 0
              :excess-blob-gas 0
              :parent-beacon-root (zero-hash32)
              :slot-number 99))
           (block
             (make-block :header header
                         :withdrawals '()
                         :requests '()
                         :block-access-list '()))
           (config (make-chain-config)))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((latest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"latest\"]}"
                 store
                 config)))
             (latest (field latest-response "result"))
             (earliest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"earliest\"]}"
                 store
                 config)))
             (quantity-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":22,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"0xc\"]}"
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":120,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"pending\"]}"
                 store
                 config)))
             (safe-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":121,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"safe\"]}"
                 store
                 config)))
             (finalized-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":122,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"finalized\"]}"
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":23,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"0x63\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":24,\"method\":\"eth_getHeaderByNumber\",\"params\":[]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error"))
             (safe-error (field safe-response "error"))
             (finalized-error (field finalized-response "error")))
        (is (string= (quantity-to-hex 12) (field latest "number")))
        (is (string= (hash32-to-hex (block-hash block))
                     (field latest "hash")))
        (is (string= (hash32-to-hex parent-hash)
                     (field latest "parentHash")))
        (is (string= (address-to-hex beneficiary)
                     (field latest "miner")))
        (is (string= (quantity-to-hex 30000000)
                     (field latest "gasLimit")))
        (is (string= (quantity-to-hex 21000)
                     (field latest "gasUsed")))
        (is (string= (quantity-to-hex 123)
                     (field latest "timestamp")))
        (is (string= (quantity-to-hex 7)
                     (field latest "baseFeePerGas")))
        (is (string= (quantity-to-hex 0)
                     (field latest "blobGasUsed")))
        (is (string= (quantity-to-hex 0)
                     (field latest "excessBlobGas")))
        (is (string= (hash32-to-hex (zero-hash32))
                     (field latest "parentBeaconBlockRoot")))
        (is (string= (hash32-to-hex (execution-requests-hash '()))
                     (field latest "requestsHash")))
        (is (string= (hash32-to-hex (block-access-list-hash '()))
                     (field latest "balHash")))
        (is (string= (quantity-to-hex 99) (field latest "slotNumber")))
        (is (string= (hash32-to-hex (block-header-transactions-root header))
                     (field latest "transactionsRoot")))
        (is (string= (quantity-to-hex 0)
                     (field (field earliest-response "result")
                            "number")))
        (is (string= (field latest "hash")
                     (field (field quantity-response "result") "hash")))
        (let ((pending (field pending-response "result")))
          (is (string= (quantity-to-hex 13)
                       (field pending "number")))
          (is (string= (field latest "hash")
                       (field pending "parentHash")))
          (is (null (field pending "hash")))
          (is (null (field pending "nonce"))))
        (is (not (field safe-response "result")))
        (is (= -32602 (field safe-error "code")))
        (is (string= "safe block not found"
                     (field safe-error "message")))
        (is (not (field finalized-response "result")))
        (is (= -32602 (field finalized-error "code")))
        (is (string= "finalized block not found"
                     (field finalized-error "message")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-header-by-hash
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (header
             (make-block-header :number 5
                                :timestamp 55
                                :gas-limit 1000000
                                :gas-used 21000
                                :base-fee-per-gas 9))
           (block (make-block :header header))
           (hash (block-hash block))
           (hash-hex (hash32-to-hex hash))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((found-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":25,"
                  "\"method\":\"eth_getHeaderByHash\",\"params\":[\""
                  hash-hex "\"]}")
                 store
                 config)))
             (found (field found-response "result"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":26,"
                  "\"method\":\"eth_getHeaderByHash\",\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\"]}")
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":27,\"method\":\"eth_getHeaderByHash\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= (quantity-to-hex 5) (field found "number")))
        (is (string= hash-hex (field found "hash")))
        (is (string= (quantity-to-hex 55) (field found "timestamp")))
        (is (string= (quantity-to-hex 9) (field found "baseFeePerGas")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

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

(deftest eth-rpc-get-uncle-count
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (ommer-1 (make-block-header :number 10
                                       :timestamp 101))
           (ommer-2 (make-block-header :number 10
                                       :timestamp 102))
           (block
             (make-block
              :header (make-block-header :number 11
                                         :timestamp 110
                                         :gas-limit 30000000)
              :ommers (list ommer-1 ommer-2)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":39,\"method\":\"eth_getUncleCountByBlockNumber\",\"params\":[\"0xb\"]}"
                 store
                 config)))
             (latest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":40,\"method\":\"eth_getUncleCountByBlockNumber\",\"params\":[\"latest\"]}"
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":44,\"method\":\"eth_getUncleCountByBlockNumber\",\"params\":[\"pending\"]}"
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":41,"
                  "\"method\":\"eth_getUncleCountByBlockHash\","
                  "\"params\":[\"" hash-hex "\"]}")
                 store
                 config)))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"eth_getUncleCountByBlockNumber\",\"params\":[\"0x63\"]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":43,\"method\":\"eth_getUncleCountByBlockHash\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= (quantity-to-hex 2)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 2)
                     (field latest-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field pending-response "result")))
        (is (string= (quantity-to-hex 2)
                     (field hash-response "result")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-uncle-by-block-and-index
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (beneficiary
             (make-address (make-byte-vector 20 :initial-element #x99)))
           (ommer-1
             (make-block-header :number 10
                                :timestamp 101
                                :gas-limit 30000000
                                :gas-used 0))
           (ommer-2
             (make-block-header :number 10
                                :timestamp 102
                                :beneficiary beneficiary
                                :gas-limit 30000000
                                :gas-used 21000
                                :base-fee-per-gas 8))
           (block
             (make-block
              :header (make-block-header :number 11
                                         :timestamp 111
                                         :gas-limit 30000000)
              :ommers (list ommer-1 ommer-2)))
           (hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":67,\"method\":\"eth_getUncleByBlockNumberAndIndex\",\"params\":[\"0xb\",\"0x1\"]}"
                 store
                 config)))
             (number-result (field number-response "result"))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":68,"
                  "\"method\":\"eth_getUncleByBlockHashAndIndex\","
                  "\"params\":[\"" hash-hex "\",\"0x0\"]}")
                 store
                 config)))
             (hash-result (field hash-response "result"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":69,\"method\":\"eth_getUncleByBlockNumberAndIndex\",\"params\":[\"0x63\",\"0x0\"]}"
                 store
                 config)))
             (out-of-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"eth_getUncleByBlockNumberAndIndex\",\"params\":[\"0xb\",\"0x2\"]}"
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":73,\"method\":\"eth_getUncleByBlockNumberAndIndex\",\"params\":[\"pending\",\"0x0\"]}"
                 store
                 config)))
             (invalid-hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":71,\"method\":\"eth_getUncleByBlockHashAndIndex\",\"params\":[\"0x1234\",\"0x0\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":72,\"method\":\"eth_getUncleByBlockNumberAndIndex\",\"params\":[\"0xb\"]}"
                 store
                 config)))
             (invalid-hash-error (field invalid-hash-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 10)
                     (field number-result "number")))
        (is (string= (hash32-to-hex (block-header-hash ommer-2))
                     (field number-result "hash")))
        (is (string= (address-to-hex beneficiary)
                     (field number-result "miner")))
        (is (string= (quantity-to-hex 102)
                     (field number-result "timestamp")))
        (is (string= (quantity-to-hex 8)
                     (field number-result "baseFeePerGas")))
        (is (stringp (field number-result "size")))
        (is (null (assoc "transactions" number-result :test #'string=)))
        (is (null (field number-result "uncles")))
        (is (string= (hash32-to-hex (block-header-hash ommer-1))
                     (field hash-result "hash")))
        (is (null (field missing-response "result")))
        (is (null (field out-of-range-response "result")))
        (is (null (field pending-response "result")))
        (is (= -32602 (field invalid-hash-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

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
                 (typep object 'ethereum-lisp.core::json-empty-object))))
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
      (ethereum-lisp.core::engine-payload-store-put-pending-transaction
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

