(in-package #:ethereum-lisp.test)

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

