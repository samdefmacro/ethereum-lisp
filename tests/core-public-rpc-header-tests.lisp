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

