(in-package #:ethereum-lisp.test)

(deftest eth-rpc-chain-id-and-block-number
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1701))
           (block
             (make-block
              :header (make-block-header :number 12
                                         :timestamp 1))))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((responses
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "[{\"jsonrpc\":\"2.0\",\"id\":17,"
                  "\"method\":\"eth_chainId\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":18,"
                  "\"method\":\"eth_blockNumber\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":33,"
                  "\"method\":\"eth_protocolVersion\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":45,"
                  "\"method\":\"net_version\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":52,"
                  "\"method\":\"net_listening\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":53,"
                  "\"method\":\"net_peerCount\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":46,"
                  "\"method\":\"web3_clientVersion\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":49,"
                  "\"method\":\"web3_sha3\","
                  "\"params\":[\"0x68656c6c6f\"]}]")
                 store
                 config))))
        (is (= 8 (length responses)))
        (is (= 17 (field (first responses) "id")))
        (is (string= (quantity-to-hex 1701)
                     (field (first responses) "result")))
        (is (= 18 (field (second responses) "id")))
        (is (string= (quantity-to-hex 12)
                     (field (second responses) "result")))
        (is (= 33 (field (third responses) "id")))
        (is (string= (quantity-to-hex 70)
                     (field (third responses) "result")))
        (is (= 45 (field (fourth responses) "id")))
        (is (string= "1701" (field (fourth responses) "result")))
        (is (= 52 (field (fifth responses) "id")))
        (is (null (field (fifth responses) "result")))
        (is (= 53 (field (sixth responses) "id")))
        (is (string= (quantity-to-hex 0)
                     (field (sixth responses) "result")))
        (is (= 46 (field (seventh responses) "id")))
        (is (string= "ethereum-lisp/0.1.0/CL/0x00000000"
                     (field (seventh responses) "result")))
        (is (= 49 (field (eighth responses) "id")))
        (is (string= "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
                     (field (eighth responses) "result")))))
    (let* ((response-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"net_version\",\"params\":[]}"
              (make-engine-payload-memory-store)
              (make-chain-config :chain-id 1701)
              :network-id 7331))
           (response (parse-json response-json)))
      (is (= 21 (field response "id")))
      (is (string= "7331" (field response "result"))))
    (let* ((response-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"eth_syncing\",\"params\":[]}"
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (response (parse-json response-json)))
      (is (= 20 (field response "id")))
      (is (null (field response "result")))
      (is (search "\"result\":false" response-json)))
    (let* ((response-json
             (engine-rpc-handle-request-json
              (concatenate
               'string
               "[{\"jsonrpc\":\"2.0\",\"id\":22,"
               "\"method\":\"eth_accounts\",\"params\":[]},"
               "{\"jsonrpc\":\"2.0\",\"id\":23,"
               "\"method\":\"eth_coinbase\",\"params\":[]},"
               "{\"jsonrpc\":\"2.0\",\"id\":41,"
               "\"method\":\"eth_mining\",\"params\":[]},"
               "{\"jsonrpc\":\"2.0\",\"id\":42,"
               "\"method\":\"eth_hashrate\",\"params\":[]}]")
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (responses (parse-json response-json)))
      (is (= 4 (length responses)))
      (is (= 22 (field (first responses) "id")))
      (is (null (field (first responses) "result")))
      (is (search "\"result\":[]" response-json))
      (is (= 23 (field (second responses) "id")))
      (is (string= (address-to-hex (zero-address))
                   (field (second responses) "result")))
      (is (= 41 (field (third responses) "id")))
      (is (null (field (third responses) "result")))
      (is (search "\"id\":41,\"result\":false" response-json))
      (is (= 42 (field (fourth responses) "id")))
      (is (string= (quantity-to-hex 0)
                   (field (fourth responses) "result"))))
    (let* ((coinbase
             (address-from-hex "0x00000000000000000000000000000000000000cb"))
           (response-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":24,\"method\":\"eth_coinbase\",\"params\":[]}"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :coinbase coinbase))
           (response (parse-json response-json)))
      (is (= 24 (field response "id")))
      (is (string= (address-to-hex coinbase)
                   (field response "result"))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :london-block 0
                                      :cancun-time 0))
           (parent
             (make-block
              :header (make-block-header
                       :number 29
                       :timestamp 8
                       :gas-limit 200
                       :gas-used 100
                       :base-fee-per-gas 900)))
           (head
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 9
                       :gas-limit 200
                       :gas-used 150
                       :base-fee-per-gas 1000
                       :blob-gas-used 0
                       :excess-blob-gas 0))))
      (engine-payload-store-put-block store parent :state-available-p t)
      (engine-payload-store-put-block store head :state-available-p t)
      (chain-store-update-forkchoice-checkpoints
       store
       (make-forkchoice-state
        :head-block-hash (block-hash head)
        :safe-block-hash (block-hash head)))
      (let* ((responses
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "[{\"jsonrpc\":\"2.0\",\"id\":26,"
                  "\"method\":\"eth_baseFee\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":27,"
                  "\"method\":\"eth_blobBaseFee\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":35,"
                  "\"method\":\"eth_gasPrice\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":36,"
                  "\"method\":\"eth_maxPriorityFeePerGas\",\"params\":[]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":56,"
                  "\"method\":\"eth_feeHistory\","
                  "\"params\":[\"0x2\",\"latest\",[10.5,90]]},"
                  "{\"jsonrpc\":\"2.0\",\"id\":59,"
                  "\"method\":\"eth_feeHistory\","
                  "\"params\":[\"0x1\",\"safe\",[]]}]")
                 store
                 config))))
        (is (= 6 (length responses)))
        (is (= 26 (field (first responses) "id")))
        (is (string= (quantity-to-hex
                      (expected-base-fee-per-gas (block-header head)))
                     (field (first responses) "result")))
        (is (= 27 (field (second responses) "id")))
        (is (string= (quantity-to-hex
                      (block-header-blob-base-fee (block-header head)))
                     (field (second responses) "result")))
        (is (= 35 (field (third responses) "id")))
        (is (string= (quantity-to-hex 1000)
                     (field (third responses) "result")))
        (is (= 36 (field (fourth responses) "id")))
        (is (string= (quantity-to-hex 0)
                     (field (fourth responses) "result")))
        (let* ((fee-history (field (fifth responses) "result"))
               (base-fees (field fee-history "baseFeePerGas"))
               (gas-ratios (field fee-history "gasUsedRatio"))
               (rewards (field fee-history "reward"))
               (blob-base-fees (field fee-history "baseFeePerBlobGas"))
               (blob-ratios (field fee-history "blobGasUsedRatio")))
          (is (= 56 (field (fifth responses) "id")))
          (is (string= (quantity-to-hex 29)
                       (field fee-history "oldestBlock")))
          (is (string= (quantity-to-hex 900) (first base-fees)))
          (is (string= (quantity-to-hex 1000) (second base-fees)))
          (is (string= (quantity-to-hex
                        (expected-base-fee-per-gas (block-header head)))
                       (third base-fees)))
          (is (= 1/2 (first gas-ratios)))
          (is (= 3/4 (second gas-ratios)))
          (is (string= (quantity-to-hex 0)
                       (first (first rewards))))
          (is (string= (quantity-to-hex 0)
                       (second (second rewards))))
          (is (string= (quantity-to-hex 0) (first blob-base-fees)))
          (is (string= (quantity-to-hex
                        (block-header-blob-base-fee (block-header head)))
                       (second blob-base-fees)))
          (is (string= (quantity-to-hex
                        (block-header-blob-base-fee (block-header head)))
                       (third blob-base-fees)))
          (is (= 0 (first blob-ratios)))
          (is (= 0 (second blob-ratios))))
        (let ((safe-fee-history (field (sixth responses) "result")))
          (is (= 59 (field (sixth responses) "id")))
          (is (string= (quantity-to-hex 30)
                       (field safe-fee-history "oldestBlock"))))))
    (let* ((responses
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "[{\"jsonrpc\":\"2.0\",\"id\":37,"
                "\"method\":\"eth_gasPrice\",\"params\":[]},"
                "{\"jsonrpc\":\"2.0\",\"id\":38,"
                "\"method\":\"eth_maxPriorityFeePerGas\",\"params\":[]}]")
               (make-engine-payload-memory-store)
               (make-chain-config)))))
      (is (= 2 (length responses)))
      (is (string= (quantity-to-hex 0)
                   (field (first responses) "result")))
      (is (string= (quantity-to-hex 0)
                   (field (second responses) "result"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":28,\"method\":\"eth_baseFee\",\"params\":[]}"
               (make-engine-payload-memory-store)
               (make-chain-config :london-block 0)))))
      (is (= 28 (field response "id")))
      (is (null (field response "result"))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :london-block nil))
           (block
             (make-block
              :header (make-block-header
                       :number 2
                       :timestamp 5
                       :gas-limit 200
                       :gas-used 100))))
      (engine-payload-store-put-block store block)
      (let ((response
              (parse-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":29,\"method\":\"eth_baseFee\",\"params\":[]}"
                store
                config))))
        (is (= 29 (field response "id")))
        (is (null (field response "result")))))
    (let* ((store (make-engine-payload-memory-store))
           (block
             (make-block
              :header (make-block-header
                       :number 3
                       :timestamp 5
                       :gas-limit 200
                       :gas-used 100))))
      (engine-payload-store-put-block store block)
      (let ((response
              (parse-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"eth_blobBaseFee\",\"params\":[]}"
                store
                (make-chain-config :cancun-time 0)))))
        (is (= 30 (field response "id")))
        (is (null (field response "result")))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":19,\"method\":\"eth_chainId\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"eth_syncing\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":24,\"method\":\"eth_accounts\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":25,\"method\":\"eth_coinbase\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":43,\"method\":\"eth_mining\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":44,\"method\":\"eth_hashrate\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"eth_baseFee\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"eth_blobBaseFee\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":34,\"method\":\"eth_protocolVersion\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":47,\"method\":\"net_version\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":48,\"method\":\"web3_clientVersion\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":54,\"method\":\"net_listening\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":55,\"method\":\"net_peerCount\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":50,\"method\":\"web3_sha3\",\"params\":[]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":51,\"method\":\"web3_sha3\",\"params\":[\"0xzz\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":39,\"method\":\"eth_gasPrice\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":40,\"method\":\"eth_maxPriorityFeePerGas\",\"params\":[\"unexpected\"]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":57,\"method\":\"eth_feeHistory\",\"params\":[\"0x0\",\"latest\",[]]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":58,\"method\":\"eth_feeHistory\",\"params\":[\"0x1\",\"latest\",[90,10]]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))))

(deftest eth-rpc-get-balance
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (empty-address
             (address-from-hex "0x00000000000000000000000000000000000000bb"))
           (state-block
             (make-block
              :header (make-block-header :number 20
                                         :timestamp 200
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 21
                                         :timestamp 210
                                         :gas-limit 30000000)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-balance
       store (block-hash state-block) address 12345)
      (engine-payload-store-put-block store missing-state-block)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":73,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x14\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":74,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\""
                  state-block-hash-hex "\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":75,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x14\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":76,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x15\"]}")
                 store
                 config)))
             (missing-block-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":77,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x63\"]}")
                 store
                 config)))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":78,\"method\":\"eth_getBalance\",\"params\":[\"0x1234\",\"0x14\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":79,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (missing-state-error (field missing-state-response "error"))
             (missing-block-error (field missing-block-response "error"))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 12345)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 12345)
                     (field hash-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getBalance state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field missing-block-error "code")))
        (is (string= "eth_getBalance block is not available"
                     (field missing-block-error "message")))
        (is (= -32602 (field invalid-address-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-transaction-count
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (empty-address
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           (pending-transaction
           (make-legacy-transaction
              :nonce 7
              :gas-price 11
              :gas-limit 21100
              :to empty-address
              :value 13
              :data #(1 2 3)
              :v 27
              :r 1
              :s 2))
           (address
             (or (transaction-sender pending-transaction) (zero-address)))
           (state-block
             (make-block
              :header (make-block-header :number 22
                                         :timestamp 220
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 23
                                         :timestamp 230
                                         :gas-limit 30000000)))
           (raw-pending-transaction
             (bytes-to-hex (transaction-encoding pending-transaction)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-nonce
       store (block-hash state-block) address 7)
      (engine-payload-store-put-account-balance
       store (block-hash state-block) address 1000000)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":80,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x16\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":81,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address) "\",\""
                  state-block-hash-hex "\"]}")
                 store
                 config)))
             (send-pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                 "{\"jsonrpc\":\"2.0\",\"id\":87,"
                  "\"method\":\"eth_sendRawTransaction\","
                  "\"params\":[\"" raw-pending-transaction "\"]}")
                 store
                 config
                 :allow-unprotected-transactions-p t)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":86,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"pending\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":82,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x16\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (progn
                  (engine-payload-store-put-block store missing-state-block)
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":83,"
                    "\"method\":\"eth_getTransactionCount\","
                    "\"params\":[\"" (address-to-hex address) "\",\"0x17\"]}")
                   store
                   config))))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":84,\"method\":\"eth_getTransactionCount\",\"params\":[\"0x1234\",\"0x16\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":85,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (missing-state-error (field missing-state-response "error"))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 7)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 7)
                     (field hash-response "result")))
        (is (string= (hash32-to-hex (transaction-hash pending-transaction))
                     (field send-pending-response "result")))
        (is (string= (quantity-to-hex 8)
                     (field pending-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getTransactionCount state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-address-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-code
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x00000000000000000000000000000000000000ee"))
           (empty-address
             (address-from-hex "0x00000000000000000000000000000000000000ff"))
           (state-block
             (make-block
              :header (make-block-header :number 24
                                         :timestamp 240
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 25
                                         :timestamp 250
                                         :gas-limit 30000000)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-code
       store (block-hash state-block) address #(96 1 96 0))
      (engine-payload-store-put-block store missing-state-block)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":86,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x18\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":87,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\",\""
                  state-block-hash-hex "\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":88,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x18\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":89,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x19\"]}")
                 store
                 config)))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":90,\"method\":\"eth_getCode\",\"params\":[\"0x1234\",\"0x18\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":91,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (missing-state-error (field missing-state-response "error"))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= "0x60016000"
                     (field number-response "result")))
        (is (string= "0x60016000"
                     (field hash-response "result")))
        (is (string= "0x"
                     (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getCode state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-address-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-storage-at
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000101"))
           (empty-address
             (address-from-hex "0x0000000000000000000000000000000000000102"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000007"))
           (state-block
             (make-block
              :header (make-block-header :number 26
                                         :timestamp 260
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 27
                                         :timestamp 270
                                         :gas-limit 30000000)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-storage
       store (block-hash state-block) address slot #x2a)
      (engine-payload-store-put-block store missing-state-block)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":92,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\",\"0x1a\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":93,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"7\",\"" state-block-hash-hex "\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":94,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x7\",\"0x1a\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":95,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\",\"0x1b\"]}")
                 store
                 config)))
             (invalid-slot-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":96,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x"
                  "111111111111111111111111111111111111111111111111111111111111111111"
                  "\",\"0x1a\"]}")
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":97,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\"]}")
                 store
                 config)))
             (missing-state-error (field missing-state-response "error"))
             (invalid-slot-error (field invalid-slot-response "error"))
             (invalid-params-error (field invalid-params-response "error"))
             (expected-word
               "0x000000000000000000000000000000000000000000000000000000000000002a")
             (zero-word
               "0x0000000000000000000000000000000000000000000000000000000000000000"))
        (is (string= expected-word (field number-response "result")))
        (is (string= expected-word (field hash-response "result")))
        (is (string= zero-word (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getStorageAt state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-slot-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-proof
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (json-string-list (values)
             (with-output-to-string (stream)
               (write-char #\[ stream)
               (loop for value in values
                     for first-p = t then nil
                     unless first-p do (write-char #\, stream)
                     do (format stream "\"~A\"" value))
               (write-char #\] stream)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof)))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000103"))
           (empty-address
             (address-from-hex "0x0000000000000000000000000000000000000104"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000007"))
           (missing-slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000008"))
           (state (make-state-db))
           (state-block
             (make-block
              :header (make-block-header :number 28
                                         :timestamp 280
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 29
                                         :timestamp 290
                                         :gas-limit 30000000)))
           (config (make-chain-config)))
      (state-db-set-account state address
                            (make-state-account :nonce 3 :balance 1000))
      (state-db-set-code state address #(96 1 96 0))
      (state-db-set-storage state address slot #x2a)
      (state-db-set-account state address
                            (make-state-account :nonce 3 :balance 1000))
      (setf (block-header-state-root (block-header state-block))
            (state-db-root state))
      (chain-store-put-block store state-block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash state-block) state)
      (engine-payload-store-put-block store missing-state-block)
      (let* ((proof-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":98,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",[\"0x7\",\""
                  (hash32-to-hex missing-slot)
                  "\",\"7\",\""
                  (subseq (hash32-to-hex slot) 2)
                  "\",\"0X7\"],\"0x1c\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":99,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",[\"0x7\"],\"0x1c\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":100,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",[\"0x7\"],\"0x1d\"]}")
                 store
                 config)))
             (invalid-storage-keys-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":101,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\",\"0x1c\"]}")
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":102,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (too-many-storage-keys-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":103,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\","
                  (json-string-list
                   (loop repeat (1+ ethereum-lisp.core::+eth-get-proof-max-storage-keys+)
                         collect "0x0"))
                  ",\"0x1c\"]}")
                 store
                 config)))
             (proof (field proof-response "result"))
             (storage-proofs (field proof "storageProof"))
             (first-storage (first storage-proofs))
             (second-storage (second storage-proofs))
             (third-storage (third storage-proofs))
             (fourth-storage (fourth storage-proofs))
             (fifth-storage (fifth storage-proofs))
             (empty-proof (field empty-account-response "result"))
             (expected-proof
               (state-db-get-proof
                state
                address
                (list slot missing-slot slot slot slot)))
             (missing-state-error (field missing-state-response "error"))
             (invalid-storage-keys-error
               (field invalid-storage-keys-response "error"))
             (invalid-params-error (field invalid-params-response "error"))
             (too-many-storage-keys-error
               (field too-many-storage-keys-response "error")))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1000)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 3)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex (keccak-256-hash #(96 1 96 0)))
                     (field proof "codeHash")))
        (is (listp (field proof "accountProof")))
        (is (every #'stringp (field proof "accountProof")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (= 5 (length storage-proofs)))
        (is (string= (quantity-to-hex 7) (field first-storage "key")))
        (is (string= "0x2a" (field first-storage "value")))
        (is (every #'stringp (field first-storage "proof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof
                     (first (state-proof-result-storage-proofs expected-proof))))
                   (field first-storage "proof")))
        (is (string= (hash32-to-hex missing-slot)
                     (field second-storage "key")))
        (is (string= (quantity-to-hex 0)
                     (field second-storage "value")))
        (is (every #'stringp (field second-storage "proof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof
                     (second (state-proof-result-storage-proofs expected-proof))))
                   (field second-storage "proof")))
        (is (string= (quantity-to-hex 7) (field third-storage "key")))
        (is (string= "0x2a" (field third-storage "value")))
        (is (string= (hash32-to-hex slot) (field fourth-storage "key")))
        (is (string= "0x2a" (field fourth-storage "value")))
        (is (every #'stringp (field fourth-storage "proof")))
        (is (string= (quantity-to-hex 7) (field fifth-storage "key")))
        (is (string= "0x2a" (field fifth-storage "value")))
        (is (string= (address-to-hex empty-address)
                     (field empty-proof "address")))
        (is (string= (quantity-to-hex 0)
                     (field empty-proof "balance")))
        (is (string= (hash32-to-hex +empty-code-hash+)
                     (field empty-proof "codeHash")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getProof state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-storage-keys-error "code")))
        (is (= -32602 (field invalid-params-error "code")))
        (is (= -32602 (field too-many-storage-keys-error "code")))))))

(deftest eth-rpc-get-proof-geth-secure-account-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (address block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 104)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               nil
                               (hash32-to-hex (block-hash block)))))))
    (let* ((store (make-engine-payload-memory-store))
           (state (make-state-db))
           (cases
             '(("0x0194fdc2fa2ffcc041d3ff12045b73c86e4ff95f"
                "0xb79ef856f65f67cf"
                "0x2077ccce0d8fc159")
               ("0xf662a5eee82abdf44a2d0b75fb180daf48a79ee0"
                "0xe242cf3c6a9f4a578bcb9ef2d4a65314768d6d299761ea9e4f"
                "0x64bed6e2edf354c3")
               ("0xb10d394651850fd4a178892ee285ece151145578"
                "0x20efcd6cea84b6925e607be06371"
                "0x1ec678fcc3aea65a"))))
      (add-account state
                   "0x0194fdc2fa2ffcc041d3ff12045b73c86e4ff95f"
                   2339563716805116249
                   13231285807645419471)
      (add-account state
                   "0xf662a5eee82abdf44a2d0b75fb180daf48a79ee0"
                   7259475919510918339
                   1420263156754097894072208833565313120560341020854497370086991)
      (add-account state
                   "0xb10d394651850fd4a178892ee285ece151145578"
                   2217592893536642650
                   668036214256246407260665125299057)
      (let* ((block (commit-state-block store state 30 300))
             (config (make-chain-config)))
        (is (string= "0x65e27b7b7b43826149e6b5674be3ff0f107ff6e988d20c1be165a172eeef399d"
                     (state-db-root-hex state)))
        (dolist (case cases)
          (destructuring-bind (address-hex balance nonce) case
            (let* ((address (address-from-hex address-hex))
                   (response (engine-rpc-handle-request
                              (proof-request address block)
                              store
                              config))
                   (proof (field response "result"))
                   (expected-proof (state-db-get-proof state address nil))
                   (decoded-proof (state-proof-result-from-rpc-object proof)))
              (is (equal (state-proof-result-rpc-object expected-proof)
                         proof))
              (is (string= (address-to-hex address)
                           (field proof "address")))
              (is (string= balance
                           (field proof "balance")))
              (is (string= nonce
                           (field proof "nonce")))
              (is (string= (hash32-to-hex +empty-code-hash+)
                           (field proof "codeHash")))
              (is (string= (hash32-to-hex +empty-trie-hash+)
                           (field proof "storageHash")))
              (is (= 2 (length (field proof "accountProof"))))
              (is (null (field proof "storageProof")))
              (is (state-db-verify-proof (state-db-root state)
                                         decoded-proof)))))))))

(deftest eth-rpc-get-proof-missing-clear-nontrivial-state-tries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (assert-missing-clear-proof (store state block missing)
             (let* ((response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":109,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex missing)
                         "\",[],\"" (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state missing nil)))
               (is (string= (address-to-hex missing)
                            (field proof "address")))
               (is (string= (quantity-to-hex 0)
                            (field proof "balance")))
               (is (string= (quantity-to-hex 0)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (null (field proof "storageProof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof"))))))
    (let* ((store (make-engine-payload-memory-store))
           (missing (address-from-hex
                     "0x00000000000000000000000000000000000002ff"))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-clear-account extension-state missing)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-clear-account branch-extension-state missing)
      (assert-missing-clear-proof
       store
       extension-state
       (commit-state-block store extension-state 33 330)
       missing)
      (assert-missing-clear-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 34 340)
       missing))))

(deftest eth-rpc-get-proof-state-trie-delete-collapse
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (add-code-storage (state address)
             (state-db-set-storage
              state
              address
              (hash32-from-hex
               "0x000000000000000000000000000000000000000000000000000000000000002a")
              42)
             (state-db-set-code state address #(96 1 96 0)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (assert-delete-collapse-proof
               (store state block address expected-root expected-nodes
                expected-balance expected-nonce)
             (let* ((response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":123,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex address)
                         "\",[],\"" (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state address nil))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= expected-root (state-db-root-hex state)))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex expected-nonce)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (null (field proof "storageProof")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (branch-survivor
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (branch-deleted
             (address-from-hex "0x0000000000000000000000000000000000000211"))
           (extension-survivor
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (extension-deleted
             (address-from-hex "0x0000000000000000000000000000000000000225"))
           (branch-extension-deleted
             (address-from-hex "0x0000000000000000000000000000000000000203"))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (add-code-storage branch-state branch-deleted)
      (state-db-clear-account branch-state branch-deleted)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-code-storage extension-state extension-deleted)
      (state-db-clear-account extension-state extension-deleted)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (add-code-storage branch-extension-state branch-extension-deleted)
      (state-db-clear-account branch-extension-state branch-extension-deleted)
      (let ((branch-block (commit-state-block store branch-state 50 500))
            (extension-block (commit-state-block store extension-state 51 510))
            (branch-extension-block
              (commit-state-block store branch-extension-state 52 520)))
        (assert-delete-collapse-proof
         store
         branch-state
         branch-block
         branch-survivor
         "0x18742ec02ab527594bc83d163360c5b677ca92e37b5a0d5673920a895645b8a1"
         1
         100
         1)
        (assert-delete-collapse-proof
         store
         branch-state
         branch-block
         branch-deleted
         "0x18742ec02ab527594bc83d163360c5b677ca92e37b5a0d5673920a895645b8a1"
         1
         0
         0)
        (assert-delete-collapse-proof
         store
         extension-state
         extension-block
         extension-survivor
         "0x006c6cf2120be53e089f44cb328653de92ca2a9a4970a6a9137148b829c47509"
         1
         100
         1)
        (assert-delete-collapse-proof
         store
         extension-state
         extension-block
         extension-deleted
         "0x006c6cf2120be53e089f44cb328653de92ca2a9a4970a6a9137148b829c47509"
         1
         0
         0)
        (assert-delete-collapse-proof
         store
         branch-extension-state
         branch-extension-block
         extension-survivor
         "0x107571af3beeb3b5f3d1b49b593066ac344ab7e98f657ee27670315fcbde6509"
         3
         100
         1)
        (assert-delete-collapse-proof
         store
         branch-extension-state
         branch-extension-block
         branch-extension-deleted
         "0x107571af3beeb3b5f3d1b49b593066ac344ab7e98f657ee27670315fcbde6509"
         1
         0
         0)))))

(deftest eth-rpc-get-proof-balance-add-nontrivial-state-tries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (assert-balance-add-proof
             (store state block target expected-balance expected-nodes)
             (let* ((response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":110,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex target)
                         "\",[],\"" (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state target nil))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= (address-to-hex target)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex 1)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (null (field proof "storageProof")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof))))
           (assert-balance-add-zero-missing-proof
             (store state block target expected-nodes)
             (let* ((storage-key
                      "0x0000000000000000000000000000000000000000000000000000000000000001")
                    (response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":111,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex target)
                         "\",[\"" storage-key "\"],\""
                         (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof
                       state
                       target
                       (list (hash32-from-hex storage-key))))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof))
                    (storage-proof
                      (first (field proof "storageProof"))))
               (is (string= (address-to-hex target)
                            (field proof "address")))
               (is (string= "0x0" (field proof "balance")))
               (is (string= "0x0" (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (string= storage-key (field storage-proof "key")))
               (is (string= "0x0" (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (branch-target
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-target
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (missing-target
             (address-from-hex "0x00000000000000000000000000000000000002ff"))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db))
           (branch-existing-zero-state (make-state-db))
           (extension-existing-zero-state (make-state-db))
           (branch-extension-existing-zero-state (make-state-db))
           (branch-zero-state (make-state-db))
           (extension-zero-state (make-state-db))
           (branch-extension-zero-state (make-state-db)))
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (state-db-add-balance branch-state branch-target 300)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-add-balance extension-state extension-target 300)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-add-balance branch-extension-state extension-target 300)
      (add-account branch-existing-zero-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-existing-zero-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (state-db-add-balance branch-existing-zero-state branch-target 0)
      (add-account extension-existing-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-existing-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-add-balance extension-existing-zero-state extension-target 0)
      (add-account branch-extension-existing-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-existing-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-existing-zero-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-add-balance branch-extension-existing-zero-state
                            extension-target
                            0)
      (add-account branch-zero-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-zero-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (state-db-add-balance branch-zero-state missing-target 0)
      (add-account extension-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-add-balance extension-zero-state missing-target 0)
      (add-account branch-extension-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-zero-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-add-balance branch-extension-zero-state missing-target 0)
      (assert-balance-add-proof
       store
       branch-state
       (commit-state-block store branch-state 35 350)
       branch-target
       400
       2)
      (assert-balance-add-proof
       store
       extension-state
       (commit-state-block store extension-state 36 360)
       extension-target
       400
       3)
      (assert-balance-add-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 37 370)
       extension-target
       400
       4)
      (assert-balance-add-proof
       store
       branch-existing-zero-state
       (commit-state-block store branch-existing-zero-state 38 380)
       branch-target
       100
       2)
      (assert-balance-add-proof
       store
       extension-existing-zero-state
       (commit-state-block store extension-existing-zero-state 39 390)
       extension-target
       100
       3)
      (assert-balance-add-proof
       store
       branch-extension-existing-zero-state
       (commit-state-block store branch-extension-existing-zero-state 40 400)
       extension-target
       100
       4)
      (assert-balance-add-zero-missing-proof
       store
       branch-zero-state
       (commit-state-block store branch-zero-state 41 410)
       missing-target
       2)
      (assert-balance-add-zero-missing-proof
       store
       extension-zero-state
       (commit-state-block store extension-zero-state 42 420)
       missing-target
       1)
      (assert-balance-add-zero-missing-proof
       store
       branch-extension-zero-state
       (commit-state-block store branch-extension-zero-state 43 430)
       missing-target
       2))))

(deftest eth-rpc-get-proof-value-transfer
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address storage-keys block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex storage-keys)
                               (hash32-to-hex (block-hash block))))))
           (assert-transfer-proof
             (store state block address storage-keys expected-root
              expected-balance expected-nonce expected-storage-proof-count
              &key expected-account-proof-count)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 132 address storage-keys block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state address storage-keys))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= expected-root
                            (state-db-root-hex state)))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex expected-nonce)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (when expected-account-proof-count
                 (is (= expected-account-proof-count
                        (length (field proof "accountProof")))))
               (is (= expected-storage-proof-count
                      (length (field proof "storageProof"))))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (sender
             (address-from-hex "0x0000000000000000000000000000000000000301"))
           (recipient
             (address-from-hex "0x0000000000000000000000000000000000000302"))
           (zero-sender
             (address-from-hex "0x0000000000000000000000000000000000000303"))
           (missing-recipient
             (address-from-hex "0x0000000000000000000000000000000000000304"))
           (missing-slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           (branch-sender
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (branch-sibling
             (address-from-hex "0x0000000000000000000000000000000000000211"))
           (branch-recipient
             (address-from-hex "0x0000000000000000000000000000000000000202"))
           (extension-sender
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (extension-recipient
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-sibling
             (address-from-hex "0x0000000000000000000000000000000000000225"))
           (branch-extension-extra
             (address-from-hex "0x0000000000000000000000000000000000000203"))
           (transfer-state (make-state-db))
           (zero-transfer-state (make-state-db))
           (branch-transfer-state (make-state-db))
           (extension-transfer-state (make-state-db))
           (branch-extension-transfer-state (make-state-db)))
      (state-db-set-account
       transfer-state sender (make-state-account :nonce 1 :balance 100))
      (ethereum-lisp.state::state-db-transfer-value
       transfer-state sender recipient 37)
      (state-db-set-account
       zero-transfer-state
       zero-sender
       (make-state-account :nonce 2 :balance 100))
      (ethereum-lisp.state::state-db-transfer-value
       zero-transfer-state zero-sender missing-recipient 0)
      (state-db-set-account
       branch-transfer-state
       branch-sender
       (make-state-account :nonce 1 :balance 100))
      (state-db-set-account
       branch-transfer-state
       branch-sibling
       (make-state-account :nonce 2 :balance 200))
      (ethereum-lisp.state::state-db-transfer-value
       branch-transfer-state branch-sender branch-recipient 37)
      (state-db-set-account
       extension-transfer-state
       extension-sender
       (make-state-account :nonce 1 :balance 100))
      (state-db-set-account
       extension-transfer-state
       extension-sibling
       (make-state-account :nonce 2 :balance 200))
      (ethereum-lisp.state::state-db-transfer-value
       extension-transfer-state extension-sender extension-recipient 37)
      (state-db-set-account
       branch-extension-transfer-state
       extension-sender
       (make-state-account :nonce 1 :balance 100))
      (state-db-set-account
       branch-extension-transfer-state
       extension-sibling
       (make-state-account :nonce 2 :balance 200))
      (state-db-set-account
       branch-extension-transfer-state
       branch-extension-extra
       (make-state-account :nonce 3 :balance 300))
      (ethereum-lisp.state::state-db-transfer-value
       branch-extension-transfer-state
       extension-sender
       extension-recipient
       37)
      (let ((transfer-block
              (commit-state-block store transfer-state 44 440))
            (zero-transfer-block
              (commit-state-block store zero-transfer-state 45 450))
            (branch-transfer-block
              (commit-state-block store branch-transfer-state 46 460))
            (extension-transfer-block
              (commit-state-block store extension-transfer-state 47 470))
            (branch-extension-transfer-block
              (commit-state-block
               store branch-extension-transfer-state 48 480)))
        (assert-transfer-proof
         store
         transfer-state
         transfer-block
         sender
         nil
         "0xeb1be297ad9e87812158dcb9b646fe55dfc2e89526b65cf76bd4fe3b40c68da9"
         63
         1
         0)
        (assert-transfer-proof
         store
         transfer-state
         transfer-block
         recipient
         nil
         "0xeb1be297ad9e87812158dcb9b646fe55dfc2e89526b65cf76bd4fe3b40c68da9"
         37
         0
         0)
        (assert-transfer-proof
         store
         zero-transfer-state
         zero-transfer-block
         missing-recipient
         (list missing-slot)
         "0x600e37f427a9f42ebe6b592ff989ec26a865aa3d89c955bb78dbf53890cbeb41"
         0
         0
         1)
        (assert-transfer-proof
         store
         branch-transfer-state
         branch-transfer-block
         branch-sender
         nil
         "0x4dd8ed5858a2fce6bf433fa35e5cc54821ad964aa7a2dd979ea34336ff8b6544"
         63
         1
         0
         :expected-account-proof-count 3)
        (assert-transfer-proof
         store
         branch-transfer-state
         branch-transfer-block
         branch-recipient
         nil
         "0x4dd8ed5858a2fce6bf433fa35e5cc54821ad964aa7a2dd979ea34336ff8b6544"
         37
         0
         0
         :expected-account-proof-count 3)
        (assert-transfer-proof
         store
         extension-transfer-state
         extension-transfer-block
         extension-sender
         nil
         "0x62d868986c4260fa44341f1c75694a5180bb3caaa21efe07f7bab246f22a2aa2"
         63
         1
         0
         :expected-account-proof-count 4)
        (assert-transfer-proof
         store
         extension-transfer-state
         extension-transfer-block
         extension-recipient
         nil
         "0x62d868986c4260fa44341f1c75694a5180bb3caaa21efe07f7bab246f22a2aa2"
         37
         0
         0
         :expected-account-proof-count 3)
        (assert-transfer-proof
         store
         branch-extension-transfer-state
         branch-extension-transfer-block
         extension-sender
         nil
         "0xc86e674a6e90c03f48bc01ea942843efe0eb52fba078dbff71fa44b8c4651aa5"
         63
         1
         0
         :expected-account-proof-count 4)
        (assert-transfer-proof
         store
         branch-extension-transfer-state
         branch-extension-transfer-block
         extension-recipient
         nil
         "0xc86e674a6e90c03f48bc01ea942843efe0eb52fba078dbff71fa44b8c4651aa5"
         37
         0
         0
         :expected-account-proof-count 3)))))

(deftest eth-rpc-get-proof-zero-storage-writes
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block))))))
           (assert-zero-storage-proof
               (store state block address slot expected-balance
                expected-code-hash)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 118 address slot block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proof (first (field proof "storageProof")))
                    (expected-proof
                      (state-db-get-proof state address (list slot)))
                    (expected-storage-proof
                      (first (state-proof-result-storage-proofs
                              expected-proof)))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (hash32-to-hex expected-code-hash)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (= 1 (length (field proof "storageProof"))))
               (is (string= (hash32-to-hex slot)
                            (field storage-proof "key")))
               (is (string= (quantity-to-hex 0)
                            (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (proof-node-hex-list
                           (state-storage-proof-proof expected-storage-proof))
                          (field storage-proof "proof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (missing-address
             (address-from-hex "0x0000000000000000000000000000000000000402"))
           (funded-address
             (address-from-hex "0x0000000000000000000000000000000000000403"))
           (code-address
             (address-from-hex "0x0000000000000000000000000000000000000404"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           (code #(96 1 96 0))
           (missing-state (make-state-db))
           (funded-state (make-state-db))
           (code-state (make-state-db)))
      (state-db-set-storage missing-state missing-address slot 0)
      (state-db-set-account funded-state funded-address
                            (make-state-account :balance 1))
      (state-db-set-storage funded-state funded-address slot 0)
      (state-db-set-code code-state code-address code)
      (state-db-set-storage code-state code-address slot 0)
      (assert-zero-storage-proof
       store
       missing-state
       (commit-state-block store missing-state 38 380)
       missing-address
       slot
       0
       +empty-code-hash+)
      (assert-zero-storage-proof
       store
       funded-state
       (commit-state-block store funded-state 39 390)
       funded-address
       slot
       1
       +empty-code-hash+)
      (assert-zero-storage-proof
       store
       code-state
       (commit-state-block store code-state 40 400)
       code-address
       slot
       0
       (keccak-256-hash code)))))

(deftest eth-rpc-get-proof-code-update
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block)))))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000109"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000000b"))
           (first-code #(96 1 96 0))
           (final-code #(96 2 96 3 1))
           (state (make-state-db)))
      (state-db-set-account state address (make-state-account :balance 1))
      (state-db-set-code state address first-code)
      (state-db-set-code state address final-code)
      (let* ((block (commit-state-block store state 53 530))
             (response
               (engine-rpc-handle-request
                (proof-request 124 address slot block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proof (first (field proof "storageProof")))
             (expected-proof
               (state-db-get-proof state address (list slot)))
             (expected-storage-proof
               (first (state-proof-result-storage-proofs expected-proof)))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (string= "0xa71076e81cddb7521d7345f5aa21a0b5781991a366f66861e5faca0a336798ad"
                     (state-db-root-hex state)))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 0)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex (keccak-256-hash final-code))
                     (field proof "codeHash")))
        (is (string= (hash32-to-hex +empty-trie-hash+)
                     (field proof "storageHash")))
        (is (= 1 (length (field proof "storageProof"))))
        (is (string= (hash32-to-hex slot)
                     (field storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field storage-proof "value")))
        (is (null (field storage-proof "proof")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof expected-storage-proof))
                   (field storage-proof "proof")))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-code-update-preserves-storage
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block)))))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x000000000000000000000000000000000000010b"))
           (present-slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000002c"))
           (missing-slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000002d"))
           (first-code #(96 1 96 0))
           (final-code #(96 2 96 3 1))
           (state (make-state-db)))
      (state-db-set-account
       state address (make-state-account :nonce 1 :balance 1000))
      (state-db-set-storage state address present-slot #x2c)
      (state-db-set-code state address first-code)
      (state-db-set-code state address final-code)
      (let* ((block (commit-state-block store state 54 540))
             (slots (list present-slot missing-slot))
             (response
               (engine-rpc-handle-request
                (proof-request 126 address slots block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proofs (field proof "storageProof"))
             (present-storage-proof (first storage-proofs))
             (missing-storage-proof (second storage-proofs))
             (expected-proof (state-db-get-proof state address slots))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (string= "0xc7b8d640084dfe51710f52b73da6975f617c6c4503ec763c1e2a2eeef11b3f01"
                     (state-db-root-hex state)))
        (is (equal (state-proof-result-rpc-object expected-proof)
                   proof))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1000)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 1)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex (keccak-256-hash final-code))
                     (field proof "codeHash")))
        (is (string= "0x39b3b39f4dd43bd60944a54f2478267341aa89516ee9e8b5c9b6272b02cb0f75"
                     (field proof "storageHash")))
        (is (= 2 (length storage-proofs)))
        (is (string= (hash32-to-hex present-slot)
                     (field present-storage-proof "key")))
        (is (string= (quantity-to-hex #x2c)
                     (field present-storage-proof "value")))
        (is (= 1 (length (field present-storage-proof "proof"))))
        (is (string= (hash32-to-hex missing-slot)
                     (field missing-storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field missing-storage-proof "value")))
        (is (= 1 (length (field missing-storage-proof "proof"))))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-code-update-nontrivial-state-tries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (set-updated-code (state address)
             (let ((target (address-from-hex address)))
               (state-db-set-code state target #(96 1 96 0))
               (state-db-set-code state target #(96 2 96 3 1))))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block))))))
           (assert-code-update-proof
               (store state block target slot expected-root expected-nodes)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 125 target slot block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proof (first (field proof "storageProof")))
                    (expected-proof
                      (state-db-get-proof state target (list slot)))
                    (expected-storage-proof
                      (first (state-proof-result-storage-proofs
                              expected-proof)))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= expected-root
                            (state-db-root-hex state)))
               (is (string= (address-to-hex target)
                            (field proof "address")))
               (is (string= (quantity-to-hex 1000)
                            (field proof "balance")))
               (is (string= (quantity-to-hex 1)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex
                             (keccak-256-hash #(96 2 96 3 1)))
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (= 1 (length (field proof "storageProof"))))
               (is (string= (hash32-to-hex slot)
                            (field storage-proof "key")))
               (is (string= (quantity-to-hex 0)
                            (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (proof-node-hex-list
                           (state-storage-proof-proof expected-storage-proof))
                          (field storage-proof "proof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (branch-target
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-target
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000000b"))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 1000)
      (set-updated-code branch-state
                        "0x0000000000000000000000000000000000000201")
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-updated-code extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-updated-code branch-extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (assert-code-update-proof
       store
       branch-state
       (commit-state-block store branch-state 54 540)
       branch-target
       slot
       "0x6ab69fa5095659c9578b4dc266ea51d9e5288674f3a60ba0058189667c74786e"
       2)
      (assert-code-update-proof
       store
       extension-state
       (commit-state-block store extension-state 55 550)
       extension-target
       slot
       "0x258d8cdbcaf278008d357941227e1b102cad65026083bde2621e843cb7c00c85"
       3)
      (assert-code-update-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 56 560)
       extension-target
       slot
       "0xa53fa7b005c9d7d484bc1130c751b0e743bb907657e3d646aa31cc456680f193"
       4))))

(deftest eth-rpc-get-proof-code-deletion
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (set-deleted-code (state address)
             (let ((target (address-from-hex address)))
               (state-db-set-code state target #(96 1 96 0))
               (state-db-set-code state target #())))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block))))))
           (assert-code-deletion-proof
               (store state block address slot expected-balance
                &optional expected-root expected-nodes (expected-nonce 0))
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 119 address slot block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proof (first (field proof "storageProof")))
                    (expected-proof
                      (state-db-get-proof state address (list slot)))
                    (expected-storage-proof
                      (first (state-proof-result-storage-proofs
                              expected-proof)))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (when expected-root
                 (is (string= expected-root
                              (state-db-root-hex state))))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex expected-nonce)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (when expected-nodes
                 (is (= expected-nodes
                        (length (field proof "accountProof")))))
               (is (= 1 (length (field proof "storageProof"))))
               (is (string= (hash32-to-hex slot)
                            (field storage-proof "key")))
               (is (string= (quantity-to-hex 0)
                            (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (proof-node-hex-list
                           (state-storage-proof-proof expected-storage-proof))
                          (field storage-proof "proof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (created-address
             (address-from-hex "0x0000000000000000000000000000000000000105"))
           (funded-address
             (address-from-hex "0x0000000000000000000000000000000000000106"))
           (branch-target
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-target
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000000b"))
           (code #(96 1 96 0))
           (created-state (make-state-db))
           (funded-state (make-state-db))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (state-db-set-code created-state created-address code)
      (state-db-set-code created-state created-address #())
      (state-db-set-account funded-state funded-address
                            (make-state-account :balance 1))
      (state-db-set-code funded-state funded-address code)
      (state-db-set-code funded-state funded-address #())
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 1000)
      (set-deleted-code branch-state
                        "0x0000000000000000000000000000000000000201")
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-deleted-code extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-deleted-code branch-extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (assert-code-deletion-proof
       store
       created-state
       (commit-state-block store created-state 41 410)
       created-address
       slot
       0)
      (assert-code-deletion-proof
       store
       funded-state
       (commit-state-block store funded-state 42 420)
       funded-address
       slot
       1)
      (assert-code-deletion-proof
       store
       branch-state
       (commit-state-block store branch-state 57 570)
       branch-target
       slot
       1000
       "0x582439b37db3e207275bb7dd5391cb2119286e63ac0c7d52f719adbae41e00bb"
       2
       1)
      (assert-code-deletion-proof
       store
       extension-state
       (commit-state-block store extension-state 58 580)
       extension-target
       slot
       1000
       "0x915d94dd285fc0df8a08abcc98035f585db26f42ff322fdbf202b94de5ad2e8e"
       3
       1)
      (assert-code-deletion-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 59 590)
       extension-target
       slot
       1000
       "0x51eb577604090486f0601db492fe0690432903734494bccedfc7d321659b4e7e"
       4
       1))))

(deftest eth-rpc-get-proof-storage-overwrite-final-value
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block))))))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof)))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x000000000000000000000000000000000000030b"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000001c"))
           (missing-slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000001d"))
           (state (make-state-db)))
      (state-db-set-account state address (make-state-account :nonce 1
                                                              :balance 5))
      (state-db-set-storage state address slot 28)
      (state-db-set-storage state address slot 43)
      (let* ((block (commit-state-block store state 46 460))
             (response
               (engine-rpc-handle-request
                (proof-request 121 address (list slot missing-slot) block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proofs (field proof "storageProof"))
             (present-storage-proof (first storage-proofs))
             (missing-storage-proof (second storage-proofs))
             (expected-proof
               (state-db-get-proof state address (list slot missing-slot)))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (equal (state-proof-result-rpc-object expected-proof)
                   proof))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 5)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 1)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex +empty-code-hash+)
                     (field proof "codeHash")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (= 2 (length storage-proofs)))
        (is (string= (hash32-to-hex slot)
                     (field present-storage-proof "key")))
        (is (string= (quantity-to-hex 43)
                     (field present-storage-proof "value")))
        (is (= 1 (length (field present-storage-proof "proof"))))
        (is (string= (hash32-to-hex missing-slot)
                     (field missing-storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field missing-storage-proof "value")))
        (is (= 1 (length (field missing-storage-proof "proof"))))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-storage-overwrite-to-zero
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block))))))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof)))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000104"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000009"))
           (state (make-state-db)))
      (state-db-set-account state address (make-state-account :balance 1))
      (state-db-set-storage state address slot 99)
      (state-db-set-storage state address slot 100)
      (state-db-set-storage state address slot 0)
      (let* ((block (commit-state-block store state 47 470))
             (response
               (engine-rpc-handle-request
                (proof-request 122 address (list slot) block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proofs (field proof "storageProof"))
             (storage-proof (first storage-proofs))
             (expected-proof
               (state-db-get-proof state address (list slot)))
             (expected-storage-proof
               (first (state-proof-result-storage-proofs expected-proof)))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (equal (state-proof-result-rpc-object expected-proof)
                   proof))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 0)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex +empty-code-hash+)
                     (field proof "codeHash")))
        (is (string= (hash32-to-hex +empty-trie-hash+)
                     (field proof "storageHash")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (= 1 (length storage-proofs)))
        (is (string= (hash32-to-hex slot)
                     (field storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field storage-proof "value")))
        (is (null (field storage-proof "proof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof expected-storage-proof))
                   (field storage-proof "proof")))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-storage-trie-update-boundaries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block))))))
           (storage-slot (value)
             (hash32-from-hex
              (format nil
                      "0x~64,'0x"
                      value)))
           (make-update-state (address slots values update-slot update-value)
             (let ((state (make-state-db)))
               (state-db-set-account state address
                                     (make-state-account :balance 1))
               (loop for slot in slots
                     for value in values
                     do (state-db-set-storage state address slot value))
               (state-db-set-storage state address update-slot update-value)
               state))
           (assert-proof-roundtrip
               (store state block address slots expected-values
                expected-node-counts)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 121 address slots block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proofs (field proof "storageProof"))
                    (expected-proof
                      (state-db-get-proof state address slots))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (= (length expected-values)
                      (length storage-proofs)))
               (loop for storage-proof in storage-proofs
                     for slot in slots
                     for expected-value in expected-values
                     for expected-node-count in expected-node-counts
                     do (progn
                          (is (string= (hash32-to-hex slot)
                                       (field storage-proof "key")))
                          (is (string= (quantity-to-hex expected-value)
                                       (field storage-proof "value")))
                          (is (= expected-node-count
                                 (length (field storage-proof "proof"))))))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000401"))
           (slot-1 (storage-slot 1))
           (slot-2 (storage-slot 2))
           (slot-3 (storage-slot 3))
           (slot-e (storage-slot 14))
           (slot-f (storage-slot 15))
           (branch-state
             (make-update-state
              address
              (list slot-1 slot-2)
              '(1 2)
              slot-1
              17))
           (extension-state
             (make-update-state
              address
              (list slot-1 slot-e)
              '(1 14)
              slot-1
              17)))
      (assert-proof-roundtrip
       store
       branch-state
       (commit-state-block store branch-state 48 480)
       address
       (list slot-1 slot-2 slot-3)
       '(17 2 0)
       '(2 2 1))
      (assert-proof-roundtrip
       store
       extension-state
       (commit-state-block store extension-state 49 490)
       address
       (list slot-1 slot-e slot-f)
       '(17 14 0)
       '(3 3 1)))))

(deftest eth-rpc-get-proof-storage-delete-boundaries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block))))))
           (storage-slot (value)
             (hash32-from-hex
              (format nil
                      "0x~64,'0x"
                     value)))
           (make-delete-preservation-state (address slots values delete-slot)
             (let ((state (make-state-db)))
               (state-db-set-account state address
                                     (make-state-account :balance 1))
               (loop for slot in slots
                     for value in values
                     do (state-db-set-storage state address slot value))
               (state-db-set-storage state address delete-slot 0)
               state))
           (assert-proof-roundtrip
               (store state block address slots expected-values
                expected-node-counts)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 120 address slots block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proofs (field proof "storageProof"))
                    (expected-proof
                      (state-db-get-proof state address slots))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (= (length expected-values)
                      (length storage-proofs)))
               (loop for storage-proof in storage-proofs
                     for slot in slots
                     for expected-value in expected-values
                     for expected-node-count in expected-node-counts
                     do (progn
                          (is (string= (hash32-to-hex slot)
                                       (field storage-proof "key")))
                          (is (string= (quantity-to-hex expected-value)
                                       (field storage-proof "value")))
                          (is (= expected-node-count
                                 (length (field storage-proof "proof"))))))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000401"))
           (slot-1 (storage-slot 1))
           (slot-2 (storage-slot 2))
           (slot-3 (storage-slot 3))
           (slot-e (storage-slot 14))
           (slot-f (storage-slot 15))
           (branch-state
             (make-delete-preservation-state
              address
              (list slot-1 slot-2 slot-3)
              '(1 2 3)
              slot-3))
           (extension-state
             (make-delete-preservation-state
              address
              (list slot-1 slot-e slot-f)
              '(1 14 15)
              slot-f))
           (collapse-state
             (make-delete-preservation-state
              address
              (list slot-1 slot-2)
              '(1 2)
              slot-2)))
      (assert-proof-roundtrip
       store
       branch-state
       (commit-state-block store branch-state 43 430)
       address
       (list slot-1 slot-2 slot-3)
       '(1 2 0)
       '(2 2 1))
      (assert-proof-roundtrip
       store
       extension-state
       (commit-state-block store extension-state 44 440)
       address
       (list slot-1 slot-e slot-f)
       '(1 14 0)
       '(3 3 1))
      (assert-proof-roundtrip
       store
       collapse-state
       (commit-state-block store collapse-state 45 450)
       address
       (list slot-1 slot-2)
       '(1 0)
       '(1 1)))))

