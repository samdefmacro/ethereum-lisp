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

(deftest eth-rpc-call-executes-retained-state-without-commit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           ;; SSTORE slot 1 := 42; MSTORE 0 := 7; RETURN mem[0:32].
           (code #(96 42 96 1 85 96 7 96 0 82 96 32 96 0 243))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 300
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (expected (let ((bytes (make-byte-vector 32)))
                       (setf (aref bytes 31) 7)
                       (bytes-to-hex bytes))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 104)
                      (cons "method" "eth_call")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000))
                                   (cons "data" "0x"))
                             "latest")))
                store
                config))
             (result (field response "result")))
        (is (string= expected result))
        (is (= 0
               (chain-store-account-storage
                store (block-hash block) contract slot)))))))

(deftest eth-rpc-call-default-gas-is-not-block-gas-limited
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (id method params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" params))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :berlin-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cd"))
           ;; SSTORE slot 0 := 1; STOP. This needs more execution gas than the
           ;; block limit leaves after intrinsic gas below.
           (code #(#x60 #x01 #x60 #x00 #x55 #x00))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 22000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (call-object
             (list (cons "to" (address-to-hex contract)))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((call-response
               (request 161 "eth_call" (list call-object "latest")
                        store config))
             (access-list-response
               (request 162 "eth_createAccessList"
                        (list call-object "latest")
                        store config))
             (access-list-result (field access-list-response "result")))
        (is (string= "0x" (field call-response "result")))
        (is (< (block-header-gas-limit (block-header block))
               (hex-to-quantity (field access-list-result "gasUsed"))))
        (is (= 0
               (chain-store-account-storage
                store
                (block-hash block)
                contract
                (zero-hash32))))))))

(deftest eth-rpc-simulates-contract-creation-without-commit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (created-address (sender nonce)
             (make-address
              (subseq
               (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes sender) nonce)))
               12 32)))
           (address-word-hex (address)
             (let ((bytes (make-byte-vector 32)))
               (replace bytes (address-bytes address) :start1 12)
               (bytes-to-hex bytes)))
           (request (id method params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" params))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           ;; MSTORE8 0 := 0; RETURN mem[0:1].
           (initcode #(96 0 96 0 83 96 1 96 0 243))
           ;; ADDRESS; MSTORE 0; RETURN mem[0:32].
           (address-initcode #(#x30 #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           (contract (created-address sender 0))
           (nonce-contract (created-address sender 7))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 300
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (tx (make-legacy-transaction :gas-limit 100000
                                        :to nil
                                        :data initcode))
           (expected-gas
             (+ (transaction-intrinsic-gas tx) 18 200))
           (call-object
             (list (cons "from" (address-to-hex sender))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "data" (bytes-to-hex initcode))))
           (nonce-call-object
             (list (cons "from" (address-to-hex sender))
                   (cons "nonce" (quantity-to-hex 7))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "data" (bytes-to-hex address-initcode)))))
      (state-db-set-account state sender
                            (make-state-account :nonce 0
                                                :balance 1000000))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((call-response
               (request 140 "eth_call" (list call-object "latest")
                        store config))
             (estimate-response
               (request 141 "eth_estimateGas" (list call-object "latest")
                        store config))
             (access-list-response
               (request 142 "eth_createAccessList" (list call-object "latest")
                        store config))
             (code-response
               (request 143 "eth_getCode"
                        (list (address-to-hex contract) "latest")
                        store config))
             (nonce-call-response
               (request 144 "eth_call" (list nonce-call-object "latest")
                        store config))
             (nonce-code-response
               (request 145 "eth_getCode"
                        (list (address-to-hex nonce-contract) "latest")
                        store config))
             (access-list-result (field access-list-response "result")))
        (is (string= "0x00" (field call-response "result")))
        (is (string= (address-word-hex nonce-contract)
                     (field nonce-call-response "result")))
        (is (string= (quantity-to-hex expected-gas)
                     (field estimate-response "result")))
        (is (string= (quantity-to-hex expected-gas)
                     (field access-list-result "gasUsed")))
        (is (string= "0x" (field code-response "result")))
        (is (string= "0x" (field nonce-code-response "result")))))))

(deftest eth-rpc-simulates-call-value-transfer-without-commit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (word-hex (value)
             (bytes-to-hex
              (ethereum-lisp.crypto::integer-to-fixed-bytes value 32)))
           (request (id method params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" params))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (recipient
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (contract
             (make-address
              (subseq
               (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes sender) 0)))
               12 32)))
           ;; CALLER BALANCE; MSTORE 0; RETURN mem[0:32].
           (balance-code #(51 49 96 0 82 96 32 96 0 243))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (call-object
             (list (cons "from" (address-to-hex sender))
                   (cons "to" (address-to-hex recipient))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "value" (quantity-to-hex 42))))
           (create-object
             (list (cons "from" (address-to-hex sender))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "value" (quantity-to-hex 42))
                   (cons "data" (bytes-to-hex balance-code))))
           (overdraft-object
             (list (cons "from" (address-to-hex sender))
                   (cons "to" (address-to-hex recipient))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "value" (quantity-to-hex 1001)))))
      (state-db-set-account state sender
                            (make-state-account :nonce 0
                                                :balance 1000))
      (state-db-set-code state recipient balance-code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((call-response
               (request 144 "eth_call" (list call-object "latest")
                        store config))
             (create-response
               (request 145 "eth_call" (list create-object "latest")
                        store config))
             (sender-balance-response
               (request 146 "eth_getBalance"
                        (list (address-to-hex sender) "latest")
                        store config))
             (recipient-balance-response
               (request 147 "eth_getBalance"
                        (list (address-to-hex recipient) "latest")
                        store config))
             (contract-balance-response
               (request 148 "eth_getBalance"
                        (list (address-to-hex contract) "latest")
                        store config))
             (overdraft-response
               (request 149 "eth_estimateGas"
                        (list overdraft-object "latest")
                        store config)))
        (is (string= (word-hex 958) (field call-response "result")))
        (is (string= (word-hex 958) (field create-response "result")))
        (is (string= (quantity-to-hex 1000)
                     (field sender-balance-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field recipient-balance-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field contract-balance-response "result")))
        (is (= -32602
               (field (field overdraft-response "error") "code")))))))

(deftest eth-rpc-estimate-gas-uses-fork-intrinsic-gas
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 300
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (tx (make-legacy-transaction :gas-limit 100000 :to nil))
           (call-object
             (list (cons "gas" (quantity-to-hex 100000)))))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let ((response
              (engine-rpc-handle-request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 150)
                     (cons "method" "eth_estimateGas")
                     (cons "params" (list call-object "latest")))
               store
               config)))
        (is (string= (quantity-to-hex
                      (transaction-intrinsic-gas tx :eip3860-p nil))
                     (field response "result")))))))

(deftest eth-rpc-call-object-access-list-warms-retained-simulation
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (id params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" "eth_estimateGas")
                    (cons "params" params))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :berlin-block 0
                                      :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (target
             (address-from-hex "0x00000000000000000000000000000000000000bb"))
           ;; PUSH20 target; BALANCE; POP; STOP.
           (code (concat-bytes #(#x73) (address-bytes target)
                               #(#x31 #x50 #x00)))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (access-list
             (list
              (list
               (cons "address" (address-to-hex target))
               (cons "storageKeys" '()))))
           (access-list-transaction
             (make-access-list-transaction
              :chain-id 1
              :gas-limit 100000
              :to contract
              :access-list
              (list (make-access-list-entry :address target))))
           (expected-gas
             (+ (transaction-intrinsic-gas access-list-transaction)
                105))
           (access-list-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex expected-gas))
                   (cons "accessList" access-list)))
           (cold-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex expected-gas)))))
      (state-db-set-code state contract code)
      (state-db-set-account state target (make-state-account :balance 11))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((access-list-response
               (request 152 (list access-list-call "latest") store config))
             (cold-response
               (request 153 (list cold-call "latest") store config))
             (cold-error (field cold-response "error")))
        (is (string= (quantity-to-hex expected-gas)
                     (field access-list-response "result")))
        (is (= -32602 (field cold-error "code")))
        (is (string= "eth_estimateGas execution reverted or exceeded gas cap"
                     (field cold-error "message")))))))

(deftest eth-rpc-call-object-dynamic-fee-uses-effective-gas-price
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (word-hex (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               (bytes-to-hex bytes)))
           (call (id call-object store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" "eth_call")
                    (cons "params" (list call-object "latest")))
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (basefee-contract
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           ;; GASPRICE; MSTORE 0; RETURN 32 bytes.
           (code #(#x3a #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           ;; BASEFEE; MSTORE 0; RETURN 32 bytes.
           (basefee-code #(#x48 #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 10
                       :state-root (state-db-root state))))
           (dynamic-call
             (list (cons "to" (address-to-hex contract))
                   (cons "chainId" (quantity-to-hex 1))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "maxFeePerGas" (quantity-to-hex 11))
                   (cons "maxPriorityFeePerGas" (quantity-to-hex 5))))
           (low-gas-price-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "gasPrice" (quantity-to-hex 7))))
           (priority-only-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "maxPriorityFeePerGas" (quantity-to-hex 5))))
           (zero-price-basefee-call
             (list (cons "to" (address-to-hex basefee-contract))
                   (cons "gas" (quantity-to-hex 100000))))
           (dynamic-basefee-call
             (list (cons "to" (address-to-hex basefee-contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "maxFeePerGas" (quantity-to-hex 11))
                   (cons "maxPriorityFeePerGas" (quantity-to-hex 5))))
           (mixed-call
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "gasPrice" (quantity-to-hex 7))
                   (cons "maxFeePerGas" (quantity-to-hex 11))))
           (wrong-chain-call
             (list (cons "to" (address-to-hex contract))
                   (cons "chainId" (quantity-to-hex 2))
                   (cons "gas" (quantity-to-hex 100000)))))
      (state-db-set-code state contract code)
      (state-db-set-code state basefee-contract basefee-code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((dynamic-response (call 154 dynamic-call store config))
             (low-gas-price-response (call 155 low-gas-price-call store config))
             (priority-only-response (call 156 priority-only-call store config))
             (zero-price-basefee-response
               (call 157 zero-price-basefee-call store config))
             (dynamic-basefee-response
               (call 158 dynamic-basefee-call store config))
             (mixed-response (call 159 mixed-call store config))
             (wrong-chain-response (call 160 wrong-chain-call store config))
             (mixed-error (field mixed-response "error"))
             (wrong-chain-error (field wrong-chain-response "error")))
        (is (string= (word-hex 11) (field dynamic-response "result")))
        (is (string= (word-hex 7) (field low-gas-price-response "result")))
        (is (string= (word-hex 0) (field priority-only-response "result")))
        (is (string= (word-hex 0) (field zero-price-basefee-response "result")))
        (is (string= (word-hex 10) (field dynamic-basefee-response "result")))
        (is (= -32602 (field mixed-error "code")))
        (is (string=
             "eth_call cannot specify gasPrice with maxFeePerGas or maxPriorityFeePerGas"
             (field mixed-error "message")))
        (is (= -32602 (field wrong-chain-error "code")))
        (is (string= "eth_call chainId does not match configured chain id"
                     (field wrong-chain-error "message")))))))

(deftest eth-rpc-call-object-input-precedes-data
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (word-hex (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               (bytes-to-hex bytes))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           ;; CALLDATALOAD 0; MSTORE 0; RETURN 32 bytes.
           (code #(#x60 #x00 #x35 #x60 #x00 #x52 #x60 #x20 #x60 #x00 #xf3))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           (call-object
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000))
                   (cons "data" (word-hex 1))
                   (cons "input" (word-hex 2)))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let ((response
              (engine-rpc-handle-request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 157)
                     (cons "method" "eth_call")
                     (cons "params" (list call-object "latest")))
               store
               config)))
        (is (string= (word-hex 2) (field response "result")))))))

(deftest eth-rpc-call-rejects-non-revert-execution-failure
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state))))
           ;; SSTORE slot 1 := 42; STOP. With only 1000 execution gas after
           ;; intrinsic gas, this fails as out-of-gas rather than REVERT.
           (code #(96 42 96 1 85 0))
           (call-object
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 22000)))))
      (state-db-set-code state contract code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 151)
                      (cons "method" "eth_call")
                      (cons "params" (list call-object "latest")))
                store
                config))
             (error (field response "error")))
        (is (= -32602 (field error "code")))
        (is (string= "eth_call execution failed"
                     (field error "message")))))))

(deftest eth-rpc-state-methods-support-block-identifier-objects
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (word-hex (value)
             (let ((bytes (make-byte-vector 32)))
               (setf (aref bytes 31) value)
               (bytes-to-hex bytes)))
           (state-with-contract (contract balance return-value)
             (let ((state (make-state-db)))
               (state-db-set-account
                state
                contract
                (make-state-account :balance balance))
               (state-db-set-code
                state
                contract
                (vector #x60 return-value #x60 #x00 #x52
                        #x60 #x20 #x60 #x00 #xf3))
               state))
           (state-block (parent number timestamp state)
             (make-block
              :header (make-block-header
                       :parent-hash (and parent (block-hash parent))
                       :number number
                       :timestamp timestamp
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x0000000000000000000000000000000000000e19"))
           (genesis-state (make-state-db))
           (genesis (state-block nil 0 0 genesis-state))
           (canonical-state (state-with-contract contract 11 1))
           (side-state (state-with-contract contract 22 2))
           (canonical-block (state-block genesis 1 12 canonical-state))
           (side-block (state-block genesis 1 24 side-state))
           (side-selector
             (list (cons "blockHash" (hash32-to-hex (block-hash side-block)))))
           (side-canonical-selector
             (list (cons "blockHash" (hash32-to-hex (block-hash side-block)))
                   (cons "requireCanonical" t)))
           (call-object
             (list (cons "to" (address-to-hex contract))
                   (cons "gas" (quantity-to-hex 100000)))))
      (dolist (block (list genesis canonical-block side-block))
        (chain-store-put-block store block :state-available-p t))
      (commit-state-db-to-chain-store store (block-hash genesis) genesis-state)
      (commit-state-db-to-chain-store
       store
       (block-hash canonical-block)
       canonical-state)
      (commit-state-db-to-chain-store store (block-hash side-block) side-state)
      (chain-store-set-canonical-head store (block-hash canonical-block))
      (let* ((latest-balance-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 131)
                      (cons "method" "eth_getBalance")
                      (cons "params" (list (address-to-hex contract) "latest")))
                store
                config))
             (side-balance-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 132)
                      (cons "method" "eth_getBalance")
                      (cons "params"
                            (list (address-to-hex contract) side-selector)))
                store
                config))
             (side-call-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 133)
                      (cons "method" "eth_call")
                      (cons "params" (list call-object side-selector)))
                store
                config))
             (side-require-canonical-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 134)
                      (cons "method" "eth_getBalance")
                      (cons "params"
                            (list (address-to-hex contract)
                                  side-canonical-selector)))
                store
                config))
             (side-require-canonical-error
               (field side-require-canonical-response "error")))
        (is (string= (quantity-to-hex 11)
                     (field latest-balance-response "result")))
        (is (string= (quantity-to-hex 22)
                     (field side-balance-response "result")))
        (is (string= (word-hex 2)
                     (field side-call-response "result")))
        (is (= -32602 (field side-require-canonical-error "code")))
        (is (string= "eth_getBalance block hash is not canonical"
                     (field side-require-canonical-error "message")))))))

(deftest eth-rpc-estimate-gas-binary-searches-retained-state-call
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (hex-quantity-integer (value)
             (parse-integer (subseq value 2) :radix 16)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (reverter
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           ;; SSTORE slot 1 := 42; MSTORE 0 := 7; RETURN mem[0:32].
           (code #(96 42 96 1 85 96 7 96 0 82 96 32 96 0 243))
           (revert-code #(96 0 96 0 253))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 31
                       :timestamp 310
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
      (state-db-set-code state contract code)
      (state-db-set-code state reverter revert-code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((transfer-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 105)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex recipient)))
                             "latest")))
                store
                config))
             (contract-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 106)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000)))
                             "latest")))
                store
                config))
             (revert-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 107)
                      (cons "method" "eth_estimateGas")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex reverter))
                                   (cons "gas" (quantity-to-hex 100000)))
                             "latest")))
                store
                config))
             (contract-estimate
               (hex-quantity-integer (field contract-response "result"))))
        (is (string= (quantity-to-hex 21000)
                     (field transfer-response "result")))
        (is (> contract-estimate 21000))
        (is (<= contract-estimate 100000))
        (is (= -32602
               (field (field revert-response "error") "code")))))))

(deftest eth-rpc-create-access-list-reports-touched-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (entry-for (access-list address)
             (find (address-to-hex address)
                   access-list
                   :test #'string=
                   :key (lambda (entry) (field entry "address")))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (target
             (address-from-hex "0x00000000000000000000000000000000000000bb"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           ;; SLOAD slot 1; BALANCE target; STOP.
           (code (concat-bytes #(#x60 #x01 #x54 #x73)
                               (address-bytes target)
                               #(#x31 #x00)))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 32
                       :timestamp 320
                       :gas-limit 100000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
      (state-db-set-code state contract code)
      (state-db-set-storage state contract slot 7)
      (state-db-set-account state target (make-state-account :balance 11))
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 108)
                      (cons "method" "eth_createAccessList")
                      (cons "params"
                            (list
                             (list (cons "to" (address-to-hex contract))
                                   (cons "gas" (quantity-to-hex 100000)))
                             "latest")))
                store
                config))
             (result (field response "result"))
             (access-list (field result "accessList"))
             (contract-entry (entry-for access-list contract))
             (target-entry (entry-for access-list target)))
        (is (stringp (field result "gasUsed")))
        (is (= 2 (length access-list)))
        (is (string= (hash32-to-hex slot)
                     (first (field contract-entry "storageKeys"))))
        (is (null (field target-entry "storageKeys")))))))

(deftest eth-rpc-simulation-methods-require-retained-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (id method)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" method)
                   (cons "params"
                         (list
                          (list
                           (cons "to"
                                 "0x00000000000000000000000000000000000000cc"))
                          "latest"))))
           (assert-state-error (response method)
             (let ((error (field response "error")))
               (is (= -32602 (field error "code")))
               (is (string= (format nil "~A state is not available" method)
                            (field error "message"))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (block
             (make-block
              :header (make-block-header
                       :number 33
                       :timestamp 330
                       :gas-limit 100000
                       :base-fee-per-gas 0))))
      (engine-payload-store-put-block store block)
      (assert-state-error
       (engine-rpc-handle-request (request 109 "eth_call") store config)
       "eth_call")
      (assert-state-error
       (engine-rpc-handle-request (request 110 "eth_estimateGas") store config)
       "eth_estimateGas")
      (assert-state-error
       (engine-rpc-handle-request
        (request 111 "eth_createAccessList") store config)
       "eth_createAccessList"))))

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

(deftest eth-rpc-send-raw-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction (make-legacy-transaction
                         :nonce 9
                         :gas-price 20000000000
                         :gas-limit 21000
                         :to recipient
                         :value 1000000000000000000
                         :v 37
                         :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
                         :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (raw-transaction (bytes-to-hex (transaction-encoding transaction)))
           (transaction-hash (hash32-to-hex (transaction-hash transaction)))
           (base-block
             (make-block
              :header (make-block-header :number 14
                                         :timestamp 140
                                         :gas-limit 30000000
                                         :gas-used 30000000
                                         :base-fee-per-gas 1000)))
           (mined-block
             (make-block
              :header (make-block-header :number 15
                                         :timestamp 150
                                         :gas-limit 30000000)
              :transactions (list transaction)))
           (config (make-chain-config :chain-id 1 :london-block 0)))
      (engine-payload-store-put-block store base-block)
      (let* ((new-pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":77,\"method\":\"eth_newPendingTransactionFilter\"}"
                 store
                 config)))
             (pending-filter-id
               (field new-pending-filter-response "result"))
             (initial-pending-filter-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":78,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (send-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":60,"
                  "\"method\":\"eth_sendRawTransaction\","
                  "\"params\":[\"" raw-transaction "\"]}")
                 store
                 config)))
             (pending-filter-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":79,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" pending-filter-id "\"]}")
                 store
                 config)))
             (pending-filter-changes
               (field pending-filter-changes-response "result"))
             (empty-pending-filter-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":80,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (duplicate-pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":89,"
                  "\"method\":\"eth_sendRawTransaction\","
                  "\"params\":[\"" raw-transaction "\"]}")
                 store
                 config)))
             (duplicate-pending-filter-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":90,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (duplicate-pending-status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":91,\"method\":\"txpool_status\",\"params\":[]}"
                 store
                 config)))
             (raw-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":61,"
                  "\"method\":\"eth_getRawTransactionByHash\","
                  "\"params\":[\"" transaction-hash "\"]}")
                 store
                 config)))
             (transaction-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":62,"
                  "\"method\":\"eth_getTransactionByHash\","
                  "\"params\":[\"" transaction-hash "\"]}")
                 store
                 config)))
             (pending-block-count-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":92,\"method\":\"eth_getBlockTransactionCountByNumber\",\"params\":[\"pending\"]}"
                 store
                 config)))
             (pending-index-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":93,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"pending\",\"0x0\"]}"
                 store
                 config)))
             (pending-raw-index-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":94,\"method\":\"eth_getRawTransactionByBlockNumberAndIndex\",\"params\":[\"pending\",\"0x0\"]}"
                 store
                 config)))
             (pending-block-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":96,\"method\":\"eth_getBlockByNumber\",\"params\":[\"pending\",false]}"
                 store
                 config)))
             (pending-full-block-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":97,\"method\":\"eth_getBlockByNumber\",\"params\":[\"pending\",true]}"
                 store
                 config)))
             (pending-header-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":98,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"pending\"]}"
                 store
                 config)))
             (pending-out-of-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":95,\"method\":\"eth_getTransactionByBlockNumberAndIndex\",\"params\":[\"pending\",\"0x1\"]}"
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":65,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                 store
                 config)))
             (txpool-status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":67,\"method\":\"txpool_status\",\"params\":[]}"
                 store
                 config)))
             (txpool-content-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":69,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (txpool-content-response (parse-json txpool-content-json))
             (txpool-content-from-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":71,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex
                  (or (transaction-sender transaction)
                      (zero-address)))
                 "\"]}")
                store
                config))
             (txpool-content-from-response
               (parse-json txpool-content-from-json))
             (txpool-content-from-missing-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":72,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex
                  (make-address
                   (make-byte-vector 20 :initial-element #x99)))
                 "\"]}")
                store
                config))
             (txpool-inspect-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":75,\"method\":\"txpool_inspect\",\"params\":[]}"
                store
                config))
             (txpool-inspect-response (parse-json txpool-inspect-json))
             (invalid-rlp-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":63,\"method\":\"eth_sendRawTransaction\",\"params\":[\"0x01\"]}"
                 store
                 config)))
             (invalid-count-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":64,\"method\":\"eth_sendRawTransaction\",\"params\":[]}"
                 store
                 config)))
             (invalid-pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":66,\"method\":\"eth_pendingTransactions\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-new-pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":81,\"method\":\"eth_newPendingTransactionFilter\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-txpool-status-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":68,\"method\":\"txpool_status\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-txpool-content-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"txpool_content\",\"params\":[\"unexpected\"]}"
                 store
                 config)))
             (invalid-txpool-content-from-count-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":73,\"method\":\"txpool_contentFrom\",\"params\":[]}"
                 store
                 config)))
             (invalid-txpool-content-from-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":74,\"method\":\"txpool_contentFrom\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-txpool-inspect-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":76,\"method\":\"txpool_inspect\",\"params\":[\"unexpected\"]}"
                 store
                 config))))
        (is (string= (quantity-to-hex 1) pending-filter-id))
        (is (search "\"result\":[]" initial-pending-filter-json))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 1 (length pending-filter-changes)))
        (is (string= transaction-hash (first pending-filter-changes)))
        (is (search "\"result\":[]" empty-pending-filter-json))
        (is (string= transaction-hash
                     (field duplicate-pending-response "result")))
        (is (search "\"result\":[]" duplicate-pending-filter-json))
        (is (string= (quantity-to-hex 1)
                     (field (field duplicate-pending-status-response "result")
                            "pending")))
        (is (string= raw-transaction (field raw-response "result")))
        (let ((pending-transaction (field transaction-response "result")))
          (is (string= transaction-hash
                       (field pending-transaction "hash")))
          (is (null (field pending-transaction "blockHash")))
          (is (null (field pending-transaction "blockNumber")))
          (is (null (field pending-transaction "blockTimestamp")))
          (is (null (field pending-transaction "transactionIndex")))
          (is (string= (quantity-to-hex 20000000000)
                       (field pending-transaction "gasPrice")))
          (is (string= (quantity-to-hex 1000000000000000000)
                       (field pending-transaction "value"))))
        (is (string= (quantity-to-hex 1)
                     (field pending-block-count-response "result")))
        (let ((pending-index-transaction
                (field pending-index-response "result")))
          (is (string= transaction-hash
                       (field pending-index-transaction "hash")))
          (is (null (field pending-index-transaction "blockHash")))
          (is (null (field pending-index-transaction "blockNumber")))
          (is (null (field pending-index-transaction "transactionIndex"))))
        (is (string= raw-transaction
                     (field pending-raw-index-response "result")))
        (let* ((pending-block (field pending-block-response "result"))
               (transactions (field pending-block "transactions")))
          (is (null (field pending-block "hash")))
          (is (null (field pending-block "nonce")))
          (is (string= (quantity-to-hex 15)
                       (field pending-block "number")))
          (is (string= (hash32-to-hex (block-hash base-block))
                       (field pending-block "parentHash")))
          (is (string= (quantity-to-hex
                        (expected-base-fee-per-gas
                         (block-header base-block)))
                       (field pending-block "baseFeePerGas")))
          (is (= 1 (length transactions)))
          (is (string= transaction-hash (first transactions))))
        (let* ((pending-block (field pending-full-block-response "result"))
               (transactions (field pending-block "transactions"))
               (pending-transaction (first transactions)))
          (is (null (field pending-block "hash")))
          (is (string= (quantity-to-hex 15)
                       (field pending-block "number")))
          (is (string= (hash32-to-hex (block-hash base-block))
                       (field pending-block "parentHash")))
          (is (string= (quantity-to-hex
                        (expected-base-fee-per-gas
                         (block-header base-block)))
                       (field pending-block "baseFeePerGas")))
          (is (= 1 (length transactions)))
          (is (string= transaction-hash
                       (field pending-transaction "hash")))
          (is (null (field pending-transaction "blockHash")))
          (is (null (field pending-transaction "blockNumber")))
          (is (null (field pending-transaction "transactionIndex"))))
        (let ((pending-header (field pending-header-response "result")))
          (is (null (field pending-header "hash")))
          (is (null (field pending-header "nonce")))
          (is (string= (quantity-to-hex 15)
                       (field pending-header "number")))
          (is (string= (hash32-to-hex (block-hash base-block))
                       (field pending-header "parentHash")))
          (is (string= (quantity-to-hex
                        (expected-base-fee-per-gas
                         (block-header base-block)))
                       (field pending-header "baseFeePerGas"))))
        (is (null (field pending-out-of-range-response "result")))
        (let ((pending-transactions (field pending-response "result")))
          (is (= 1 (length pending-transactions)))
          (is (string= transaction-hash
                       (field (first pending-transactions) "hash")))
          (is (null (field (first pending-transactions) "blockHash"))))
        (let ((txpool-status (field txpool-status-response "result")))
          (is (string= (quantity-to-hex 1)
                       (field txpool-status "pending")))
          (is (string= (quantity-to-hex 0)
                       (field txpool-status "queued"))))
        (let* ((txpool-content (field txpool-content-response "result"))
               (pending (field txpool-content "pending"))
               (sender-transactions
                 (field pending
                        (address-to-hex
                         (or (transaction-sender transaction)
                             (zero-address)))))
               (nonce-transaction (field sender-transactions "9")))
          (is (string= transaction-hash
                       (field nonce-transaction "hash")))
          (is (null (field nonce-transaction "blockHash")))
          (is (search "\"queued\":{}" txpool-content-json)))
        (let* ((txpool-content-from
                 (field txpool-content-from-response "result"))
               (pending (field txpool-content-from "pending"))
               (nonce-transaction (field pending "9")))
          (is (string= transaction-hash
                       (field nonce-transaction "hash")))
          (is (search "\"queued\":{}" txpool-content-from-json))
          (is (search "\"pending\":{}" txpool-content-from-missing-json)))
        (let* ((txpool-inspect (field txpool-inspect-response "result"))
               (pending (field txpool-inspect "pending"))
               (sender-transactions
                 (field pending
                        (address-to-hex
                         (or (transaction-sender transaction)
                             (zero-address)))))
               (summary (field sender-transactions "9")))
          (is (string= (format nil "~A: 1000000000000000000 wei + 21000 gas x 20000000000 wei"
                               (address-to-hex recipient))
                       summary))
          (is (search "\"queued\":{}" txpool-inspect-json)))
        (engine-payload-store-put-block store mined-block)
        (let* ((mined-transaction-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":82,"
                    "\"method\":\"eth_getTransactionByHash\","
                    "\"params\":[\"" transaction-hash "\"]}")
                   store
                   config)))
               (post-mined-pending-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":83,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                   store
                   config)))
               (post-mined-status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":84,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config)))
               (resend-mined-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":85,"
                    "\"method\":\"eth_sendRawTransaction\","
                    "\"params\":[\"" raw-transaction "\"]}")
                   store
                   config)))
               (post-resend-pending-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":86,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                   store
                   config)))
               (post-resend-status-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":87,\"method\":\"txpool_status\",\"params\":[]}"
                   store
                   config)))
               (post-resend-filter-json
                 (engine-rpc-handle-request-json
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":88,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" pending-filter-id "\"]}")
                  store
                  config))
               (mined-transaction
                 (field mined-transaction-response "result"))
               (post-mined-status
                 (field post-mined-status-response "result"))
               (post-resend-status
                 (field post-resend-status-response "result")))
          (is (string= transaction-hash
                       (field mined-transaction "hash")))
          (is (string= (hash32-to-hex (block-hash mined-block))
                       (field mined-transaction "blockHash")))
          (is (string= (quantity-to-hex 15)
                       (field mined-transaction "blockNumber")))
          (is (string= (quantity-to-hex 0)
                       (field mined-transaction "transactionIndex")))
          (is (= 0 (length (field post-mined-pending-response "result"))))
          (is (string= (quantity-to-hex 0)
                       (field post-mined-status "pending")))
          (is (string= transaction-hash
                       (field resend-mined-response "result")))
          (is (= 0 (length (field post-resend-pending-response "result"))))
          (is (string= (quantity-to-hex 0)
                       (field post-resend-status "pending")))
          (is (search "\"result\":[]" post-resend-filter-json)))
        (is (= -32602
               (field (field invalid-rlp-response "error") "code")))
        (is (= -32602
               (field (field invalid-count-response "error") "code")))
        (is (= -32602
               (field (field invalid-pending-response "error") "code")))
        (is (= -32602
               (field (field invalid-new-pending-filter-response "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-status-response "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-content-response "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-content-from-count-response
                             "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-content-from-address-response
                             "error")
                      "code")))
        (is (= -32602
               (field (field invalid-txpool-inspect-response "error")
                      "code")))))))

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

(deftest eth-rpc-send-raw-transaction-gates-unprotected-legacy-admission
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config &key allow-unprotected-transactions-p)
             (parse-json
              (engine-rpc-handle-request-json
               json
               store
               config
               :allow-unprotected-transactions-p
               allow-unprotected-transactions-p)))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 3)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 1000000)
               store)))
    (let* ((raw-transaction
             "0xf86103018261a894b94f5374fce5edbc8e2a8697c15331677e6ebf0b0a8255441ba079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798a063ba75f072fb465223d8c651fbbf7ce6dd582ca9c793bcb595dd245b8a28cd17")
           (transaction (transaction-from-encoding
                         (hex-to-bytes raw-transaction)))
           (sender (transaction-sender transaction))
           (transaction-hash (hash32-to-hex
                              (transaction-hash transaction)))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (blocked-store (funded-store sender))
           (allowed-store (funded-store sender))
           (send-json
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":126,"
              "\"method\":\"eth_sendRawTransaction\","
              "\"params\":[\"" raw-transaction "\"]}"))
           (blocked-response (request send-json blocked-store config))
           (allowed-response
             (request send-json
                      allowed-store
                      config
                      :allow-unprotected-transactions-p t))
           (blocked-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":127,\"method\":\"txpool_status\",\"params\":[]}"
              blocked-store
              config))
           (allowed-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":128,\"method\":\"txpool_status\",\"params\":[]}"
              allowed-store
              config))
           (blocked-error (field blocked-response "error")))
      (is (not (legacy-transaction-protected-p transaction)))
      (is (= -32602 (field blocked-error "code")))
      (is (string= "eth_sendRawTransaction unprotected legacy transaction rejected"
                   (field blocked-error "message")))
      (is (string= (quantity-to-hex 0)
                   (field (field blocked-status "result") "pending")))
      (is (string= transaction-hash (field allowed-response "result")))
      (is (string= (quantity-to-hex 1)
                   (field (field allowed-status "result") "pending"))))))

(deftest eth-rpc-send-raw-transaction-enforces-txpool-price-limit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config &key txpool-price-limit)
             (parse-json
              (engine-rpc-handle-request-json
               json
               store
               config
               :txpool-price-limit txpool-price-limit)))
           (send-json (transaction id)
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
              ",\"method\":\"eth_sendRawTransaction\","
              "\"params\":[\""
              (bytes-to-hex (transaction-encoding transaction))
              "\"]}"))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 1000000)
               store)))
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (config (make-chain-config :chain-id 1 :london-block 0))
           (low-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (accepted-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 2
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (sender (transaction-sender low-transaction
                                       :expected-chain-id 1))
           (rejected-store (funded-store sender))
           (accepted-store (funded-store sender))
           (rejected-response
             (request
              (send-json low-transaction 129)
              rejected-store
              config
              :txpool-price-limit 2))
           (accepted-response
             (request
              (send-json accepted-transaction 130)
              accepted-store
              config
              :txpool-price-limit 2))
           (rejected-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":131,\"method\":\"txpool_status\",\"params\":[]}"
              rejected-store
              config))
           (accepted-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":132,\"method\":\"txpool_status\",\"params\":[]}"
              accepted-store
              config))
           (rejected-error (field rejected-response "error")))
      (is (= -32602 (field rejected-error "code")))
      (is (string= "eth_sendRawTransaction gas price below txpool price limit"
                   (field rejected-error "message")))
      (is (string= (quantity-to-hex 0)
                   (field (field rejected-status "result") "pending")))
      (is (string= (hash32-to-hex (transaction-hash accepted-transaction))
                   (field accepted-response "result")))
      (is (string= (quantity-to-hex 1)
                   (field (field accepted-status "result") "pending"))))))

(deftest eth-rpc-send-raw-transaction-enforces-configured-txpool-price-bump
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config &key txpool-price-bump-percent)
             (parse-json
              (engine-rpc-handle-request-json
               json
               store
               config
               :txpool-price-bump-percent txpool-price-bump-percent)))
           (send-json (transaction id)
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
              ",\"method\":\"eth_sendRawTransaction\","
              "\"params\":[\""
              (bytes-to-hex (transaction-encoding transaction))
              "\"]}"))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 10000000)
               store))
           (signed-legacy (gas-price private-key recipient)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price gas-price
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1)))
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (config (make-chain-config :chain-id 1 :london-block 0))
           (base-transaction (signed-legacy 100 private-key recipient))
           (underpriced-transaction (signed-legacy 124 private-key recipient))
           (replacement-transaction (signed-legacy 125 private-key recipient))
           (sender (transaction-sender base-transaction :expected-chain-id 1))
           (rejected-store (funded-store sender))
           (accepted-store (funded-store sender))
           (base-rejected-response
             (request
              (send-json base-transaction 133)
              rejected-store
              config
              :txpool-price-bump-percent 25))
           (base-accepted-response
             (request
              (send-json base-transaction 134)
              accepted-store
              config
              :txpool-price-bump-percent 25))
           (rejected-response
             (request
              (send-json underpriced-transaction 135)
              rejected-store
              config
              :txpool-price-bump-percent 25))
           (accepted-response
             (request
              (send-json replacement-transaction 136)
              accepted-store
              config
              :txpool-price-bump-percent 25))
           (rejected-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":137,\"method\":\"txpool_status\",\"params\":[]}"
              rejected-store
              config))
           (accepted-status
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":138,\"method\":\"txpool_status\",\"params\":[]}"
              accepted-store
              config))
           (rejected-error (field rejected-response "error")))
      (is (string= (hash32-to-hex (transaction-hash base-transaction))
                   (field base-rejected-response "result")))
      (is (string= (hash32-to-hex (transaction-hash base-transaction))
                   (field base-accepted-response "result")))
      (is (= -32602 (field rejected-error "code")))
      (is (string= "Pending transaction replacement underpriced"
                   (field rejected-error "message")))
      (is (string= (hash32-to-hex (transaction-hash replacement-transaction))
                   (field accepted-response "result")))
      (is (string= (quantity-to-hex 1)
                   (field (field rejected-status "result") "pending")))
      (is (string= (quantity-to-hex 1)
                   (field (field accepted-status "result") "pending"))))))

(deftest eth-rpc-send-raw-transaction-applies-basic-admission-preflight
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
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (low-gas-store (make-engine-payload-memory-store))
           (typed-store (make-engine-payload-memory-store))
           (over-gas-store (make-engine-payload-memory-store))
           (nonce-store (make-engine-payload-memory-store))
           (balance-store (make-engine-payload-memory-store))
           (missing-balance-store (make-engine-payload-memory-store))
           (sender-code-store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (low-gas-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0
               :data #(1))
              private-key
              1))
           (unsupported-access-transaction
             (make-access-list-transaction
              :chain-id 1
              :nonce 3
              :gas-price 1
              :gas-limit 25000
              :to (address-from-hex
                   "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b")
              :value 10
              :data (hex-to-bytes "0x5544")
              :y-parity 1
              :r #xc9519f4f2b30335884581971573fadf60c6204f59a911df35ee8a540456b2660
              :s #x32f1e8e2c5dd761f9e4f88f41c8310aeaba26a8bfcdacfedfa12ec3862d37521))
           (over-gas-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 30000001
               :to recipient
               :value 0)
              private-key
              1))
           (sender-code-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (nonce-too-low-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1))
           (insufficient-balance-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 10
               :gas-limit 21000
               :to recipient
               :value 1)
              private-key
              1))
           (sender (transaction-sender sender-code-transaction
                                       :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block nonce-store head-block :state-available-p t)
      (chain-store-put-account-nonce
       nonce-store (block-hash head-block) sender 2)
      (chain-store-put-account-balance
       nonce-store (block-hash head-block) sender 1000000)
      (chain-store-put-block over-gas-store head-block :state-available-p t)
      (chain-store-put-account-nonce
       over-gas-store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       over-gas-store (block-hash head-block) sender 100000000)
      (chain-store-put-block balance-store head-block :state-available-p t)
      (chain-store-put-account-balance
       balance-store (block-hash head-block) sender 100)
      (chain-store-put-block missing-balance-store
                             head-block
                             :state-available-p t)
      (engine-payload-store-put-block sender-code-store head-block)
      (engine-payload-store-put-account-balance
       sender-code-store (block-hash head-block) sender 1000000)
      (engine-payload-store-put-account-code
       sender-code-store (block-hash head-block) sender #(1 2 3))
      (let* ((low-gas-response
               (send-raw low-gas-transaction 112 low-gas-store config))
             (typed-response
               (send-raw unsupported-access-transaction 113 typed-store config))
             (over-gas-response
               (send-raw over-gas-transaction 124 over-gas-store config))
             (nonce-too-low-response
               (send-raw nonce-too-low-transaction 114 nonce-store config))
             (insufficient-balance-response
               (send-raw insufficient-balance-transaction
                         115
                         balance-store
                         config))
             (missing-balance-response
               (send-raw insufficient-balance-transaction
                         122
                         missing-balance-store
                         config))
             (sender-code-response
               (send-raw sender-code-transaction
                         116
                         sender-code-store
                         config))
             (low-gas-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":117,\"method\":\"txpool_status\",\"params\":[]}"
                 low-gas-store
                 config)))
             (typed-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":118,\"method\":\"txpool_status\",\"params\":[]}"
                 typed-store
                 config)))
             (over-gas-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_status\",\"params\":[]}"
                 over-gas-store
                 config)))
             (nonce-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":119,\"method\":\"txpool_status\",\"params\":[]}"
                 nonce-store
                 config)))
             (balance-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":120,\"method\":\"txpool_status\",\"params\":[]}"
                 balance-store
                 config)))
             (missing-balance-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":123,\"method\":\"txpool_status\",\"params\":[]}"
                 missing-balance-store
                 config)))
             (sender-code-status
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":121,\"method\":\"txpool_status\",\"params\":[]}"
                 sender-code-store
                 config))))
        (is (= -32602 (field (field low-gas-response "error") "code")))
        (is (string= "eth_sendRawTransaction gas limit below intrinsic gas"
                     (field (field low-gas-response "error") "message")))
        (is (= -32602 (field (field typed-response "error") "code")))
        (is (string= "Access-list transaction before Berlin"
                     (field (field typed-response "error") "message")))
        (is (= -32602 (field (field over-gas-response "error") "code")))
        (is (string= "eth_sendRawTransaction gas limit exceeds block gas limit"
                     (field (field over-gas-response "error") "message")))
        (is (= -32602
               (field (field nonce-too-low-response "error") "code")))
        (is (string= "eth_sendRawTransaction nonce too low"
                     (field (field nonce-too-low-response "error")
                            "message")))
        (is (= -32602
               (field (field insufficient-balance-response "error")
                      "code")))
        (is (string=
             "eth_sendRawTransaction insufficient sender balance"
             (field (field insufficient-balance-response "error")
                    "message")))
        (is (= -32602
               (field (field missing-balance-response "error")
                      "code")))
        (is (string=
             "eth_sendRawTransaction insufficient sender balance"
             (field (field missing-balance-response "error")
                    "message")))
        (is (= -32602 (field (field sender-code-response "error") "code")))
        (is (string=
             "eth_sendRawTransaction sender has non-delegation code"
             (field (field sender-code-response "error") "message")))
        (dolist (status-response
                 (list low-gas-status
                       typed-status
                       over-gas-status
                       nonce-status
                       balance-status
                       missing-balance-status
                       sender-code-status))
          (is (string= (quantity-to-hex 0)
                       (field (field status-response "result")
                              "pending"))))))))

(deftest eth-rpc-send-raw-transaction-enforces-pending-balance-expenditure
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (first-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender first-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 30000)
      (let* ((first-response (send-raw first-transaction 122 store config))
             (second-response (send-raw second-transaction 123 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":124,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":126,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= first-hash (field first-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= first-hash (field (field pending "0") "hash")))
        (is (null (field pending "1")))
        (is (null (field content "queued")))
        (is (null (field second-lookup-response "result")))))))

(deftest eth-rpc-send-raw-transaction-enforces-pooled-balance-expenditure
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (first-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 2
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender first-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 30000)
      (let* ((first-response (send-raw first-transaction 127 store config))
             (second-response (send-raw second-transaction 128 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":129,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":130,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":131,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= first-hash (field first-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= first-hash (field (field queued "1") "hash")))
        (is (null (field queued "2")))
        (is (null (field second-lookup-response "result")))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (basefee-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (second-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (basefee-hash
             (hash32-to-hex (transaction-hash basefee-transaction)))
           (second-hash (hash32-to-hex (transaction-hash second-transaction)))
           (sender (transaction-sender basefee-transaction
                                       :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 100000)
      (let* ((basefee-response
               (send-raw basefee-transaction 132 store config))
             (second-response (send-raw second-transaction 133 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":134,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":135,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (second-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":136,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (second-error (field second-response "error")))
        (is (string= basefee-hash (field basefee-response "result")))
        (is (= -32602 (field second-error "code")))
        (is (string= "eth_sendRawTransaction insufficient sender balance"
                     (field second-error "message")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= basefee-hash (field (field queued "0") "hash")))
        (is (null (field queued "1")))
        (is (null (field second-lookup-response "result")))))))

(deftest eth-rpc-send-raw-transaction-queues-retained-state-nonce-gaps
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 3
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":122,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 123 store config))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":124,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":125,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":126,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (content-from-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":127,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex sender)
                 "\"]}")
                store
                config))
             (transaction-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":128,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (raw-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":129,"
                 "\"method\":\"eth_getRawTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":131,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":132,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (queued-from
               (field (field (field content-from-response "result") "queued")
                      "3"))
             (pooled-transaction
               (field transaction-response "result")))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= transaction-hash (field (field queued "3") "hash")))
        (is (string= transaction-hash (field queued-from "hash")))
        (is (string= transaction-hash (field pooled-transaction "hash")))
        (is (null (field pooled-transaction "blockHash")))
        (is (string= (bytes-to-hex (transaction-encoding transaction))
                     (field raw-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field transaction-count-response "result")))
        (is (= 0 (length (field filter-changes "result"))))))))

(deftest eth-rpc-send-raw-transaction-enforces-txpool-queue-limits
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw
               (transaction id store config
                &key txpool-account-queue-limit txpool-global-queue-limit)
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
               config
               :txpool-account-queue-limit txpool-account-queue-limit
               :txpool-global-queue-limit txpool-global-queue-limit)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 10000000)
               store))
           (signed-legacy (nonce gas-price private-key recipient)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce nonce
               :gas-price gas-price
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1)))
    (let* ((config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-one (signed-legacy 1 1 1 recipient))
           (nonce-two (signed-legacy 2 1 1 recipient))
           (replacement (signed-legacy 1 2 1 recipient))
           (sender (transaction-sender nonce-one :expected-chain-id 1))
           (global-store (funded-store sender))
           (account-store (funded-store sender))
           (replacement-store (funded-store sender))
           (nonce-two-hash (hash32-to-hex (transaction-hash nonce-two)))
           (replacement-hash (hash32-to-hex (transaction-hash replacement))))
      (let* ((first-response
               (send-raw nonce-one 181 global-store config
                         :txpool-global-queue-limit 1))
             (second-response
               (send-raw nonce-two 182 global-store config
                         :txpool-global-queue-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":183,\"method\":\"txpool_status\",\"params\":[]}"
                global-store
                config))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":184,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" nonce-two-hash "\"]}")
                global-store
                config))
             (error (field second-response "error")))
        (is (string= (hash32-to-hex (transaction-hash nonce-one))
                     (field first-response "result")))
        (is (= -32602 (field error "code")))
        (is (string= "Queued transaction exceeds txpool global queue limit"
                     (field error "message")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued")))
        (is (null (field lookup-response "result"))))
      (let* ((first-response
               (send-raw nonce-one 185 account-store config
                         :txpool-account-queue-limit 1
                         :txpool-global-queue-limit 10))
             (second-response
               (send-raw nonce-two 186 account-store config
                         :txpool-account-queue-limit 1
                         :txpool-global-queue-limit 10))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":187,\"method\":\"txpool_status\",\"params\":[]}"
                account-store
                config))
             (error (field second-response "error")))
        (is (string= (hash32-to-hex (transaction-hash nonce-one))
                     (field first-response "result")))
        (is (= -32602 (field error "code")))
        (is (string= "Queued transaction exceeds txpool account queue limit"
                     (field error "message")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued"))))
      (let* ((first-response
               (send-raw nonce-one 188 replacement-store config
                         :txpool-account-queue-limit 1
                         :txpool-global-queue-limit 1))
             (replacement-response
               (send-raw replacement 189 replacement-store config
                         :txpool-account-queue-limit 1
                         :txpool-global-queue-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":190,\"method\":\"txpool_status\",\"params\":[]}"
                replacement-store
                config)))
        (is (string= (hash32-to-hex (transaction-hash nonce-one))
                     (field first-response "result")))
        (is (string= replacement-hash (field replacement-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued")))))))

(deftest eth-rpc-send-raw-transaction-enforces-txpool-slot-limits
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw
               (transaction id store config
                &key txpool-account-slot-limit txpool-global-slot-limit)
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
               config
               :txpool-account-slot-limit txpool-account-slot-limit
               :txpool-global-slot-limit txpool-global-slot-limit)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (funded-store (&rest senders)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (dolist (sender senders)
                 (chain-store-put-account-nonce
                  store (block-hash head-block) sender 0)
                 (chain-store-put-account-balance
                  store (block-hash head-block) sender 10000000))
               store))
           (signed-legacy (nonce gas-price private-key recipient)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce nonce
               :gas-price gas-price
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1)))
    (let* ((config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (sender-one-nonce-zero (signed-legacy 0 1 1 recipient))
           (sender-one-nonce-one (signed-legacy 1 1 1 recipient))
           (sender-one-replacement (signed-legacy 0 2 1 recipient))
           (sender-two-nonce-zero (signed-legacy 0 1 2 recipient))
           (sender-one (transaction-sender sender-one-nonce-zero
                                           :expected-chain-id 1))
           (sender-two (transaction-sender sender-two-nonce-zero
                                           :expected-chain-id 1))
           (global-store (funded-store sender-one sender-two))
           (account-store (funded-store sender-one))
           (replacement-store (funded-store sender-one))
           (global-promotion-store (funded-store sender-one))
           (account-promotion-store (funded-store sender-one))
           (sender-two-hash (hash32-to-hex
                             (transaction-hash sender-two-nonce-zero)))
           (replacement-hash (hash32-to-hex
                              (transaction-hash sender-one-replacement))))
      (let* ((first-response
               (send-raw sender-one-nonce-zero 241 global-store config
                         :txpool-global-slot-limit 1))
             (second-response
               (send-raw sender-two-nonce-zero 242 global-store config
                         :txpool-global-slot-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":243,\"method\":\"txpool_status\",\"params\":[]}"
                global-store
                config))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":244,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" sender-two-hash "\"]}")
                global-store
                config))
             (error (field second-response "error")))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field first-response "result")))
        (is (= -32602 (field error "code")))
        (is (string= "Pending transaction exceeds txpool global slot limit"
                     (field error "message")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending")))
        (is (null (field lookup-response "result"))))
      (let* ((first-response
               (send-raw sender-one-nonce-zero 245 account-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 10))
             (second-response
               (send-raw sender-one-nonce-one 246 account-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 10))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":247,\"method\":\"txpool_status\",\"params\":[]}"
                account-store
                config))
             (error (field second-response "error")))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field first-response "result")))
        (is (= -32602 (field error "code")))
        (is (string= "Pending transaction exceeds txpool account slot limit"
                     (field error "message")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending"))))
      (let* ((first-response
               (send-raw sender-one-nonce-zero 248 replacement-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 1))
             (replacement-response
               (send-raw sender-one-replacement 249 replacement-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":250,\"method\":\"txpool_status\",\"params\":[]}"
                replacement-store
                config)))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field first-response "result")))
        (is (string= replacement-hash (field replacement-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending"))))
      (let* ((queued-response
               (send-raw sender-one-nonce-one 251 global-promotion-store config
                         :txpool-global-slot-limit 1))
             (pending-response
               (send-raw sender-one-nonce-zero 252 global-promotion-store config
                         :txpool-global-slot-limit 1))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":253,\"method\":\"txpool_status\",\"params\":[]}"
                global-promotion-store
                config)))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-one))
                     (field queued-response "result")))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field pending-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued"))))
      (let* ((queued-response
               (send-raw sender-one-nonce-one 254 account-promotion-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 10))
             (pending-response
               (send-raw sender-one-nonce-zero 255 account-promotion-store config
                         :txpool-account-slot-limit 1
                         :txpool-global-slot-limit 10))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":256,\"method\":\"txpool_status\",\"params\":[]}"
                account-promotion-store
                config)))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-one))
                     (field queued-response "result")))
        (is (string= (hash32-to-hex (transaction-hash sender-one-nonce-zero))
                     (field pending-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "queued")))))))

(deftest eth-rpc-send-raw-transaction-honors-txpool-local-exemptions
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw
               (transaction id store config
                &key txpool-price-limit txpool-account-queue-limit
                  txpool-global-queue-limit txpool-account-slot-limit
                  txpool-global-slot-limit txpool-local-addresses
                  txpool-no-local-exemptions-p)
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
               config
               :txpool-price-limit txpool-price-limit
               :txpool-account-queue-limit txpool-account-queue-limit
               :txpool-global-queue-limit txpool-global-queue-limit
               :txpool-account-slot-limit txpool-account-slot-limit
               :txpool-global-slot-limit txpool-global-slot-limit
               :txpool-local-addresses txpool-local-addresses
               :txpool-no-local-exemptions-p txpool-no-local-exemptions-p)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 10000000)
               store))
           (signed-legacy (nonce gas-price private-key recipient)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce nonce
               :gas-price gas-price
               :gas-limit 21000
               :to recipient
               :value 0)
              private-key
              1)))
    (let* ((config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (pending-transaction (signed-legacy 0 1 1 recipient))
           (queued-transaction (signed-legacy 1 1 1 recipient))
           (sender (transaction-sender pending-transaction
                                       :expected-chain-id 1))
           (local-addresses (list sender))
           (price-rejected-store (funded-store sender))
           (price-local-store (funded-store sender))
           (price-nolocals-store (funded-store sender))
           (queue-local-store (funded-store sender))
           (queue-nolocals-store (funded-store sender))
           (slot-local-store (funded-store sender))
           (slot-nolocals-store (funded-store sender)))
      (let* ((rejected-response
               (send-raw pending-transaction 191 price-rejected-store config
                         :txpool-price-limit 2))
             (local-response
               (send-raw pending-transaction 192 price-local-store config
                         :txpool-price-limit 2
                         :txpool-local-addresses local-addresses))
             (nolocals-response
               (send-raw pending-transaction 193 price-nolocals-store config
                         :txpool-price-limit 2
                         :txpool-local-addresses local-addresses
                         :txpool-no-local-exemptions-p t))
             (local-status
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":194,\"method\":\"txpool_status\",\"params\":[]}"
                price-local-store
                config))
             (rejected-error (field rejected-response "error"))
             (nolocals-error (field nolocals-response "error")))
        (is (= -32602 (field rejected-error "code")))
        (is (string= "eth_sendRawTransaction gas price below txpool price limit"
                     (field rejected-error "message")))
        (is (string= (hash32-to-hex (transaction-hash pending-transaction))
                     (field local-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field local-status "result") "pending")))
        (is (= -32602 (field nolocals-error "code")))
        (is (string= "eth_sendRawTransaction gas price below txpool price limit"
                     (field nolocals-error "message"))))
      (let* ((local-response
               (send-raw queued-transaction 195 queue-local-store config
                         :txpool-account-queue-limit 0
                         :txpool-global-queue-limit 0
                         :txpool-local-addresses local-addresses))
             (nolocals-response
               (send-raw queued-transaction 196 queue-nolocals-store config
                         :txpool-account-queue-limit 0
                         :txpool-global-queue-limit 0
                         :txpool-local-addresses local-addresses
                         :txpool-no-local-exemptions-p t))
             (local-status
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":197,\"method\":\"txpool_status\",\"params\":[]}"
                queue-local-store
                config))
             (nolocals-error (field nolocals-response "error")))
        (is (string= (hash32-to-hex (transaction-hash queued-transaction))
                     (field local-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field local-status "result") "queued")))
        (is (= -32602 (field nolocals-error "code")))
        (is (string= "Queued transaction exceeds txpool global queue limit"
                     (field nolocals-error "message"))))
      (let* ((local-response
               (send-raw pending-transaction 198 slot-local-store config
                         :txpool-account-slot-limit 0
                         :txpool-global-slot-limit 0
                         :txpool-local-addresses local-addresses))
             (nolocals-response
               (send-raw pending-transaction 199 slot-nolocals-store config
                         :txpool-account-slot-limit 0
                         :txpool-global-slot-limit 0
                         :txpool-local-addresses local-addresses
                         :txpool-no-local-exemptions-p t))
             (local-status
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":200,\"method\":\"txpool_status\",\"params\":[]}"
                slot-local-store
                config))
             (nolocals-error (field nolocals-response "error")))
        (is (string= (hash32-to-hex (transaction-hash pending-transaction))
                     (field local-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field local-status "result") "pending")))
        (is (= -32602 (field nolocals-error "code")))
        (is (string= "Pending transaction exceeds txpool global slot limit"
                     (field nolocals-error "message")))))))

(deftest eth-rpc-txpool-lifetime-expires-queued-view-transactions
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config now)
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
               config
               :txpool-lifetime-seconds 5
               :txpool-now now)))
           (request (json store config now)
             (parse-json
              (engine-rpc-handle-request-json
               json store config
               :txpool-lifetime-seconds 5
               :txpool-now now)))
           (funded-store (sender)
             (let* ((store (make-engine-payload-memory-store))
                    (head-block
                      (make-block
                       :header (make-block-header :number 0
                                                  :timestamp 0
                                                  :gas-limit 30000000
                                                  :base-fee-per-gas 0))))
               (chain-store-put-block store head-block :state-available-p t)
               (chain-store-put-account-nonce
                store (block-hash head-block) sender 0)
               (chain-store-put-account-balance
                store (block-hash head-block) sender 10000000)
               store))
           (signed-legacy (nonce gas-price)
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce nonce
               :gas-price gas-price
               :gas-limit 21000
               :to (address-from-hex
                    "0x3535353535353535353535353535353535353535")
               :value 0)
              1
              1)))
    (let* ((config (make-chain-config :chain-id 1 :london-block 0))
           (queued-transaction (signed-legacy 1 1))
           (replacement-transaction (signed-legacy 1 2))
           (pending-transaction (signed-legacy 0 1))
           (sender (transaction-sender queued-transaction
                                       :expected-chain-id 1))
           (queued-store (funded-store sender))
           (pending-store (funded-store sender))
           (replacement-store (funded-store sender))
           (queued-hash (hash32-to-hex (transaction-hash queued-transaction)))
           (replacement-hash
             (hash32-to-hex (transaction-hash replacement-transaction)))
           (pending-hash
             (hash32-to-hex (transaction-hash pending-transaction))))
      (is (string= queued-hash
                   (field (send-raw queued-transaction 301 queued-store
                                    config 10)
                          "result")))
      (let* ((status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":302,\"method\":\"txpool_status\",\"params\":[]}"
                queued-store config 16))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":303,\"method\":\"txpool_content\",\"params\":[]}"
                queued-store config 16))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":304,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" queued-hash "\"]}")
                queued-store config 16)))
        (is (string= (quantity-to-hex 0)
                     (field (field status-response "result") "queued")))
        (is (null (field (field content-response "result") "queued")))
        (is (null (field lookup-response "result"))))
      (is (string= pending-hash
                   (field (send-raw pending-transaction 305 pending-store
                                    config 10)
                          "result")))
      (let ((status-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":306,\"method\":\"txpool_status\",\"params\":[]}"
               pending-store config 16)))
        (is (string= (quantity-to-hex 1)
                     (field (field status-response "result") "pending")))
        (is (string= (quantity-to-hex 0)
                     (field (field status-response "result") "queued"))))
      (is (string= queued-hash
                   (field (send-raw queued-transaction 307 replacement-store
                                    config 10)
                          "result")))
      (is (string= replacement-hash
                   (field (send-raw replacement-transaction 308
                                    replacement-store config 14)
                          "result")))
      (let ((lookup-response
              (request
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":309,"
                "\"method\":\"eth_getTransactionByHash\","
                "\"params\":[\"" replacement-hash "\"]}")
               replacement-store config 16)))
        (is (string= replacement-hash
                     (field (field lookup-response "result") "hash")))))))

(deftest eth-rpc-send-raw-transaction-keeps-contiguous-nonces-pending
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-zero-hash (hash32-to-hex (transaction-hash nonce-zero)))
           (nonce-one-hash (hash32-to-hex (transaction-hash nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":174,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (nonce-zero-response (send-raw nonce-zero 175 store config))
             (nonce-one-response (send-raw nonce-one 176 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":177,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":178,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":179,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":180,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (filter-hashes (field filter-changes "result")))
        (is (string= nonce-zero-hash (field nonce-zero-response "result")))
        (is (string= nonce-one-hash (field nonce-one-response "result")))
        (is (string= (quantity-to-hex 2) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= nonce-zero-hash
                     (field (field pending "0") "hash")))
        (is (string= nonce-one-hash
                     (field (field pending "1") "hash")))
        (is (null (field content "queued")))
        (is (string= (quantity-to-hex 2)
                     (field transaction-count-response "result")))
        (is (= 2 (length filter-hashes)))
        (is (string= nonce-zero-hash (first filter-hashes)))
        (is (string= nonce-one-hash (second filter-hashes)))))))

(deftest eth-rpc-send-raw-transaction-promotes-contiguous-queued-nonces
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-zero-hash (hash32-to-hex (transaction-hash nonce-zero)))
           (nonce-one-hash (hash32-to-hex (transaction-hash nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":142,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (queued-response (send-raw nonce-one 143 store config))
             (queued-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":144,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (pending-response (send-raw nonce-zero 145 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":146,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (pending-transactions-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":147,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":148,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":149,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (promoted-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":150,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (pending-transactions
               (field pending-transactions-response "result"))
             (content (field content-response "result"))
             (pending-sender
               (field (field content "pending") (address-to-hex sender)))
             (promoted-hashes (field promoted-filter-changes "result")))
        (is (string= nonce-one-hash (field queued-response "result")))
        (is (= 0 (length (field queued-filter-changes "result"))))
        (is (string= nonce-zero-hash (field pending-response "result")))
        (is (string= (quantity-to-hex 2) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (= 2 (length pending-transactions)))
        (is (string= nonce-zero-hash
                     (field (field pending-sender "0") "hash")))
        (is (string= nonce-one-hash
                     (field (field pending-sender "1") "hash")))
        (is (null (field content "queued")))
        (is (string= (quantity-to-hex 2)
                     (field transaction-count-response "result")))
        (is (= 2 (length promoted-hashes)))
        (is (string= nonce-zero-hash (first promoted-hashes)))
        (is (string= nonce-one-hash (second promoted-hashes)))))))

(deftest eth-rpc-send-raw-transaction-queues-basefee-ineligible-transactions
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":133,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 134 store config))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":135,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":136,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":137,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (content-from-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":138,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex sender)
                 "\"]}")
                store
                config))
             (transaction-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":139,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (transaction-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":140,"
                 "\"method\":\"eth_getTransactionCount\","
                 "\"params\":[\""
                 (address-to-hex sender)
                 "\",\"pending\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":141,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (queued
               (field (field content "queued") (address-to-hex sender)))
             (queued-from
               (field (field (field content-from-response "result") "queued")
                      "0"))
             (pooled-transaction
               (field transaction-response "result")))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (string= transaction-hash (field (field queued "0") "hash")))
        (is (string= transaction-hash (field queued-from "hash")))
        (is (string= transaction-hash (field pooled-transaction "hash")))
        (is (null (field pooled-transaction "blockHash")))
        (is (string= (quantity-to-hex 0)
                     (field transaction-count-response "result")))
        (is (= 0 (length (field filter-changes "result"))))))))

(deftest eth-rpc-send-raw-transaction-routes-blob-transactions-to-blob-subpool
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0))
           (raw-transaction
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")
           (transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1337))
           (filter-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":167,\"method\":\"eth_newPendingTransactionFilter\"}"
              store
              config))
           (filter-id (field filter-response "result"))
           (send-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":166,"
               "\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\"" raw-transaction "\"]}")
              store
              config))
           (pending-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":168,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
              store
              config))
           (status-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":169,\"method\":\"txpool_status\",\"params\":[]}"
              store
              config))
           (content-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":170,\"method\":\"txpool_content\",\"params\":[]}"
              store
              config))
           (content-from-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":171,"
               "\"method\":\"txpool_contentFrom\",\"params\":[\""
               (address-to-hex sender)
               "\"]}")
              store
              config))
           (inspect-response
             (request
              "{\"jsonrpc\":\"2.0\",\"id\":174,\"method\":\"txpool_inspect\",\"params\":[]}"
              store
              config))
           (lookup-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":172,"
               "\"method\":\"eth_getTransactionByHash\","
               "\"params\":[\"" transaction-hash "\"]}")
              store
              config))
           (filter-changes
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":173,"
               "\"method\":\"eth_getFilterChanges\","
               "\"params\":[\"" filter-id "\"]}")
              store
              config))
           (status (field status-response "result"))
           (content (field content-response "result"))
           (queued (field (field content "queued") (address-to-hex sender)))
           (queued-from
             (field (field (field content-from-response "result") "queued")
                    (write-to-string (transaction-nonce transaction)
                                     :base 10)))
           (inspect-queued
             (field (field (field inspect-response "result") "queued")
                    (address-to-hex sender)))
           (pooled-transaction (field lookup-response "result")))
      (is (typep transaction 'blob-transaction))
      (is (string= transaction-hash (field send-response "result")))
      (is (= 0 (length (field pending-response "result"))))
      (is (string= (quantity-to-hex 0) (field status "pending")))
      (is (string= (quantity-to-hex 1) (field status "queued")))
      (is (null (field content "pending")))
      (is (string= transaction-hash (field (field queued "0") "hash")))
      (is (string= transaction-hash (field queued-from "hash")))
      (is (search (format nil "~A wei"
                          (transaction-value transaction))
                  (field inspect-queued "0")))
      (is (string= transaction-hash (field pooled-transaction "hash")))
      (is (null (field pooled-transaction "blockHash")))
      (is (= 0 (length (field filter-changes "result")))))))

(deftest eth-rpc-send-raw-transaction-rejects-low-blob-fee-cap
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0))
           (raw-transaction
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")
           (transaction
             (transaction-from-encoding (hex-to-bytes raw-transaction)))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (head-block
             (make-block
              :header
              (make-block-header
               :number 1
               :timestamp 12
               :gas-limit 30000000
               :blob-gas-used 0
               :excess-blob-gas (* 64 1024 1024)))))
      (chain-store-put-block store head-block :state-available-p t)
      (let* ((send-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":175,"
                 "\"method\":\"eth_sendRawTransaction\","
                 "\"params\":[\"" raw-transaction "\"]}")
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":176,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":177,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                store
                config))
             (error (field send-response "error"))
             (status (field status-response "result")))
        (is (typep transaction 'blob-transaction))
        (is (> (block-header-blob-base-fee (block-header head-block))
               (blob-transaction-max-fee-per-blob-gas transaction)))
        (is (= -32602 (field error "code")))
        (is (string= "eth_sendRawTransaction: Max fee per blob gas below blob base fee"
                     (field error "message")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (null (field lookup-response "result")))))))

(deftest txpool-canonical-blob-base-fee-rise-removes-underpriced-blobs
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1337
                                    :london-block 0
                                    :cancun-time 0))
         (transaction
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
         (transaction-hash (transaction-hash transaction))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :gas-limit 30000000
                               :timestamp 0
                               :blob-gas-used 0
                               :excess-blob-gas 0
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :timestamp 12
                               :blob-gas-used 0
                               :excess-blob-gas 0
                               :extra-data #(1))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :timestamp 12
                               :blob-gas-used 0
                               :excess-blob-gas (* 64 1024 1024)
                               :extra-data #(2)))))
    (is (typep transaction 'blob-transaction))
    (is (<= (block-header-blob-base-fee (block-header old-canonical-child))
            (blob-transaction-max-fee-per-blob-gas transaction)))
    (is (> (block-header-blob-base-fee (block-header new-canonical-child))
           (blob-transaction-max-fee-per-blob-gas transaction)))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (ethereum-lisp.core::engine-payload-store-put-blob-transaction
     store
     transaction)
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-blob-transaction-count
            store)))
    (is (typep
         (ethereum-lisp.core::engine-payload-store-blob-transaction
          store
          transaction-hash)
         'blob-transaction))
    (chain-store-set-canonical-head
     store
     (block-hash new-canonical-child)
     :chain-config config)
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-blob-transaction-count
            store)))
    (is (null
         (ethereum-lisp.core::engine-payload-store-pooled-transaction
          store
          transaction-hash)))))

(deftest eth-rpc-send-raw-transaction-replaces-basefee-conflict-with-pending
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (old-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (new-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 6
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (old-hash (hash32-to-hex (transaction-hash old-transaction)))
           (new-hash (hash32-to-hex (transaction-hash new-transaction)))
           (sender (transaction-sender new-transaction :expected-chain-id 1))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":151,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (old-response (send-raw old-transaction 152 store config))
             (new-response (send-raw new-transaction 153 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":154,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":155,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (old-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":156,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" old-hash "\"]}")
                store
                config))
             (new-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":157,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" new-hash "\"]}")
                store
                config))
             (filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":158,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender)))
             (filter-hashes (field filter-changes "result")))
        (is (string= old-hash (field old-response "result")))
        (is (string= new-hash (field new-response "result")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= new-hash (field (field pending "0") "hash")))
        (is (null (field content "queued")))
        (is (null (field old-lookup-response "result")))
        (is (string= new-hash
                     (field (field new-lookup-response "result") "hash")))
        (is (= 1 (length filter-hashes)))
        (is (string= new-hash (first filter-hashes)))))))

(deftest txpool-basefee-transactions-promote-after-canonical-head-drop
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":159,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 160 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":161,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (queued-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":162,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field queued-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field queued-status-response "result")
                            "queued")))
        (is (= 0 (length (field queued-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":163,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":164,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":165,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field promoted-status-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= (quantity-to-hex 1) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (string= transaction-hash
                       (field (field pending "0") "hash")))
          (is (null (field content "queued")))
          (is (= 1 (length filter-hashes)))
          (is (string= transaction-hash (first filter-hashes))))))))

(deftest txpool-pending-revalidation-treats-missing-balance-as-zero
  (let* ((store (make-engine-payload-memory-store))
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
         (sender (transaction-sender transaction :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender 0)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     transaction)
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (= 1
           (length
            (ethereum-lisp.core::engine-payload-store-revalidate-pending-transactions
             store))))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (eq transaction
            (ethereum-lisp.core::engine-payload-store-queued-transaction
             store
             (transaction-hash transaction))))))

(deftest txpool-basefee-promotion-drains-newly-contiguous-queued-tail
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (basefee-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (queued-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 5
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (basefee-hash
             (hash32-to-hex (transaction-hash basefee-transaction)))
           (queued-hash
             (hash32-to-hex (transaction-hash queued-transaction)))
           (sender (transaction-sender
                    basefee-transaction
                    :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":301,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (basefee-response (send-raw basefee-transaction 302 store config))
             (queued-response (send-raw queued-transaction 303 store config))
             (initial-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":304,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":305,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= basefee-hash (field basefee-response "result")))
        (is (string= queued-hash (field queued-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field initial-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 2)
                     (field (field initial-status-response "result")
                            "queued")))
        (is (= 0 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":306,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":307,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":308,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":309,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= (quantity-to-hex 2) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (string= basefee-hash
                       (field (field pending "0") "hash")))
          (is (string= queued-hash
                       (field (field pending "1") "hash")))
          (is (null (field content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 2 (length filter-hashes)))
          (is (string= basefee-hash (first filter-hashes)))
          (is (string= queued-hash (second filter-hashes))))))))

(deftest txpool-basefee-promotion-waits-for-contiguous-nonce
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (gap-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (gap-hash (hash32-to-hex (transaction-hash gap-transaction)))
           (closing-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (closing-hash
             (hash32-to-hex (transaction-hash closing-transaction)))
           (sender (transaction-sender gap-transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":189,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (gap-response (send-raw gap-transaction 190 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":191,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config)))
        (is (string= gap-hash (field gap-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field queued-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field queued-status-response "result")
                            "queued")))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((after-drop-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":192,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (after-drop-content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":193,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (after-drop-filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":194,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (after-drop-status (field after-drop-status-response "result"))
               (after-drop-content (field after-drop-content-response "result"))
               (after-drop-queued
                 (field (field after-drop-content "queued")
                        (address-to-hex sender))))
          (is (string= (quantity-to-hex 0)
                       (field after-drop-status "pending")))
          (is (string= (quantity-to-hex 1)
                       (field after-drop-status "queued")))
          (is (null (field after-drop-content "pending")))
          (is (string= gap-hash
                       (field (field after-drop-queued "1") "hash")))
          (is (= 0 (length (field after-drop-filter-changes "result")))))
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (let* ((closing-response (send-raw closing-transaction 195 store config))
               (promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":196,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (promoted-content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":197,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":198,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":199,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (promoted-status (field promoted-status-response "result"))
               (promoted-content (field promoted-content-response "result"))
               (pending
                 (field (field promoted-content "pending")
                        (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= closing-hash (field closing-response "result")))
          (is (string= (quantity-to-hex 2)
                       (field promoted-status "pending")))
          (is (string= (quantity-to-hex 0)
                       (field promoted-status "queued")))
          (is (string= closing-hash
                       (field (field pending "0") "hash")))
          (is (string= gap-hash
                       (field (field pending "1") "hash")))
          (is (null (field promoted-content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 2 (length filter-hashes)))
          (is (string= closing-hash (first filter-hashes)))
          (is (string= gap-hash (second filter-hashes))))))))

(deftest engine-payload-store-promotes-basefee-transactions-by-sender-index
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (sender-a-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-a-nonce-one
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-a-nonce-three
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 3
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-b-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            2
            1))
         (sender-a
           (transaction-sender sender-a-nonce-zero :expected-chain-id 1))
         (sender-b
           (transaction-sender sender-b-nonce-zero :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000
                                       :base-fee-per-gas 3))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender-a 0)
    (chain-store-put-account-nonce store (block-hash head-block) sender-b 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender-a 1000000)
    (chain-store-put-account-balance
     store (block-hash head-block) sender-b 1000000)
    (dolist (transaction
             (list sender-a-nonce-three
                   sender-b-nonce-zero
                   sender-a-nonce-one
                   sender-a-nonce-zero))
      (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
       store
       transaction))
    (let ((promoted
            (ethereum-lisp.core::engine-payload-store-promote-basefee-transactions
             store))
          (sender-a-pending
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender-a))
          (sender-b-pending
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender-b)))
      (is (= 3 (length promoted)))
      (is (= 3
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
              store)))
      (is (eq sender-a-nonce-zero (first sender-a-pending)))
      (is (eq sender-a-nonce-one (second sender-a-pending)))
      (is (eq sender-b-nonce-zero (first sender-b-pending)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store
            (transaction-hash sender-a-nonce-three))))
      (is (eq sender-a-nonce-three
              (ethereum-lisp.core::engine-payload-store-pooled-transaction
               store
               (transaction-hash sender-a-nonce-three)))))))

(deftest txpool-queued-promotion-rechecks-pending-balance
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (gap-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 1
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (closing-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 1
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (sender (transaction-sender gap-transaction :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender 21000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     closing-transaction)
    (ethereum-lisp.core::engine-payload-store-put-queued-transaction
     store
     gap-transaction)
    (is (null
         (ethereum-lisp.core::engine-payload-store-promote-queued-transactions
          store
          sender)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (eq closing-transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store
             (transaction-hash closing-transaction))))
    (is (eq gap-transaction
            (ethereum-lisp.core::engine-payload-store-queued-transaction
             store
             (transaction-hash gap-transaction))))))

(deftest txpool-basefee-promotion-rechecks-pending-balance
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (gap-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 4
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (closing-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (sender (transaction-sender gap-transaction :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000
                                       :base-fee-per-gas 3))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender 84000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     closing-transaction)
    (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
     store
     gap-transaction)
    (is (null
         (ethereum-lisp.core::engine-payload-store-promote-basefee-transactions
          store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
            store)))
    (is (eq closing-transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store
             (transaction-hash closing-transaction))))
    (is (eq gap-transaction
            (ethereum-lisp.core::engine-payload-store-basefee-transaction
             store
             (transaction-hash gap-transaction))))))

(deftest txpool-canonical-basefee-rise-demotes-pending-transaction
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":214,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 215 store config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":216,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (= 1 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":217,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (pending-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":218,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":219,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":220,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":221,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result"))
               (queued
                 (field (field content "queued") (address-to-hex sender))))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 1) (field status "queued")))
          (is (= 0 (length (field pending-response "result"))))
          (is (null (field content "pending")))
          (is (string= transaction-hash
                       (field (field queued "0") "hash")))
          (is (string= (quantity-to-hex 0)
                       (field transaction-count-response "result")))
          (is (= 0 (length (field filter-changes "result")))))))))

(deftest txpool-canonical-gas-limit-drop-removes-overlimit-transactions
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (pending-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 6
               :gas-limit 50000
               :to recipient
               :value 0)
              1
              1))
           (queued-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 2
               :gas-price 6
               :gas-limit 60000
               :to recipient
               :value 0)
              1
              1))
           (basefee-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 3
               :gas-price 4
               :gas-limit 55000
               :to recipient
               :value 0)
              1
              1))
           (pending-hash
             (hash32-to-hex (transaction-hash pending-transaction)))
           (queued-hash
             (hash32-to-hex (transaction-hash queued-transaction)))
           (basefee-hash
             (hash32-to-hex (transaction-hash basefee-transaction)))
           (sender (transaction-sender pending-transaction
                                       :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 100000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000
                                         :base-fee-per-gas 5))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":231,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (queued-response (send-raw queued-transaction 232 store config))
             (basefee-response (send-raw basefee-transaction 233 store config))
             (pending-response (send-raw pending-transaction 234 store config))
             (initial-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":235,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":236,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (initial-status (field initial-status-response "result")))
        (is (string= queued-hash (field queued-response "result")))
        (is (string= basefee-hash (field basefee-response "result")))
        (is (string= pending-hash (field pending-response "result")))
        (is (string= (quantity-to-hex 1) (field initial-status "pending")))
        (is (string= (quantity-to-hex 2) (field initial-status "queued")))
        (is (= 1 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":237,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":238,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (pending-lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":239,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" pending-hash "\"]}")
                  store
                  config))
               (queued-lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":240,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" queued-hash "\"]}")
                  store
                  config))
               (basefee-lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":241,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" basefee-hash "\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":242,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result")))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (null (field content "pending")))
          (is (null (field content "queued")))
          (is (null (field pending-lookup-response "result")))
          (is (null (field queued-lookup-response "result")))
          (is (null (field basefee-lookup-response "result")))
          (is (= 0 (length (field filter-changes "result")))))))))

(deftest txpool-canonical-sender-code-change-removes-transactions
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (pending-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (basefee-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (blob-transaction
           (fixture-sign-blob-transaction
            (make-blob-transaction
             :chain-id 1
             :nonce 3
             :max-priority-fee-per-gas 1
             :max-fee-per-gas 6
             :gas-limit 21000
             :to recipient
             :max-fee-per-blob-gas 1
             :blob-versioned-hashes
             (list (hash32-from-hex
                    "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")))
            1))
         (sender (transaction-sender pending-transaction
                                     :expected-chain-id 1))
         (parent-block
           (make-block
            :header
            (make-block-header :number 0
                               :timestamp 0
                               :gas-limit 30000000
                               :base-fee-per-gas 5)))
         (child-block
           (make-block
            :header
            (make-block-header :parent-hash (block-hash parent-block)
                               :number 1
                               :timestamp 12
                               :gas-limit 30000000
                               :base-fee-per-gas 5))))
    (chain-store-put-block store parent-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash parent-block) sender 1000000000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     pending-transaction)
    (ethereum-lisp.core::engine-payload-store-put-queued-transaction
     store
     queued-transaction)
    (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
     store
     basefee-transaction)
    (ethereum-lisp.core::engine-payload-store-put-blob-transaction
     store
     blob-transaction)
    (chain-store-put-block store child-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash child-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash child-block) sender 1000000000)
    (chain-store-put-account-code
     store (block-hash child-block) sender #(1 2 3))
    (chain-store-set-canonical-head store (block-hash child-block))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-blob-transaction-count
            store)))
    (dolist (transaction (list pending-transaction
                               queued-transaction
                               basefee-transaction
                               blob-transaction))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pooled-transaction
            store
            (transaction-hash transaction)))))))

(deftest txpool-canonical-balance-drop-demotes-overbudget-pending-tail
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (nonce-zero-hash
             (hash32-to-hex (transaction-hash nonce-zero)))
           (nonce-one-hash
             (hash32-to-hex (transaction-hash nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 42000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":222,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (nonce-zero-response (send-raw nonce-zero 223 store config))
             (nonce-one-response (send-raw nonce-one 224 store config))
             (initial-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":225,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= nonce-zero-hash (field nonce-zero-response "result")))
        (is (string= nonce-one-hash (field nonce-one-response "result")))
        (is (= 2 (length (field initial-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 21000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":226,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (pending-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":227,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":228,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":229,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":230,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (pending-transactions (field pending-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (queued
                 (field (field content "queued") (address-to-hex sender))))
          (is (string= (quantity-to-hex 1) (field status "pending")))
          (is (string= (quantity-to-hex 1) (field status "queued")))
          (is (= 1 (length pending-transactions)))
          (is (string= nonce-zero-hash
                       (field (field pending "0") "hash")))
          (is (string= nonce-one-hash
                       (field (field queued "1") "hash")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-response "result")))
          (is (= 0 (length (field filter-changes "result")))))))))

(deftest txpool-stale-pending-transactions-drop-after-canonical-nonce-advance
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
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
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((send-response (send-raw transaction 181 store config))
             (pending-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":182,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (string= (quantity-to-hex 1)
                     (field (field pending-status-response "result")
                            "pending")))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":183,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (pending-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":184,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":185,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (lookup-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":186,"
                   "\"method\":\"eth_getTransactionByHash\","
                   "\"params\":[\"" transaction-hash "\"]}")
                  store
                  config))
               (raw-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":187,"
                   "\"method\":\"eth_getRawTransactionByHash\","
                   "\"params\":[\"" transaction-hash "\"]}")
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":188,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (status (field status-response "result"))
               (content (field content-response "result")))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (= 0 (length (field pending-response "result"))))
          (is (null (field content "pending")))
          (is (null (field content "queued")))
          (is (null (field lookup-response "result")))
          (is (null (field raw-response "result")))
          (is (string= (quantity-to-hex 1)
                       (field transaction-count-response "result"))))))))

(deftest txpool-queued-transactions-promote-after-canonical-nonce-advance
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":166,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (send-response (send-raw transaction 167 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":168,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (queued-filter-changes
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":169,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config)))
        (is (string= transaction-hash (field send-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field queued-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field queued-status-response "result")
                            "queued")))
        (is (= 0 (length (field queued-filter-changes "result"))))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 1)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":170,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":171,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":172,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":173,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (status (field promoted-status-response "result"))
               (content (field content-response "result"))
               (pending
                 (field (field content "pending") (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= (quantity-to-hex 1) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued")))
          (is (string= transaction-hash
                       (field (field pending "1") "hash")))
          (is (null (field content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 1 (length filter-hashes)))
          (is (string= transaction-hash (first filter-hashes))))))))

(deftest txpool-promotion-drops-wrong-chain-queued-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (empty-object-p (object)
             (or (null object)
                 (typep object 'ethereum-lisp.core::json-empty-object)))
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
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (wrong-chain-nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              2))
           (nonce-zero-hash
             (hash32-to-hex (transaction-hash nonce-zero)))
           (wrong-chain-hash
             (hash32-to-hex (transaction-hash wrong-chain-nonce-one)))
           (sender (transaction-sender nonce-zero :expected-chain-id 1))
           (wrong-chain-sender
             (transaction-sender wrong-chain-nonce-one :expected-chain-id 2))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (is (null (transaction-sender
                 wrong-chain-nonce-one
                 :expected-chain-id 1)))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (ethereum-lisp.core::engine-payload-store-put-queued-transaction
       store
       wrong-chain-nonce-one)
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-queued-transaction-count
              store)))
      (let ((wrong-chain-pre-cleanup-status-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":187,\"method\":\"txpool_status\",\"params\":[]}"
               store
               config))
            (wrong-chain-pre-cleanup-pending-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":188,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
               store
               config))
            (wrong-chain-pre-cleanup-content-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":189,\"method\":\"txpool_content\",\"params\":[]}"
               store
               config))
            (wrong-chain-pre-cleanup-content-from-response
              (request
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":190,"
                "\"method\":\"txpool_contentFrom\",\"params\":[\""
                (address-to-hex wrong-chain-sender)
                "\"]}")
               store
               config))
            (wrong-chain-pre-cleanup-inspect-response
              (request
               "{\"jsonrpc\":\"2.0\",\"id\":191,\"method\":\"txpool_inspect\",\"params\":[]}"
               store
               config))
            (wrong-chain-pre-cleanup-lookup-response
              (request
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":192,"
                "\"method\":\"eth_getTransactionByHash\","
                "\"params\":[\"" wrong-chain-hash "\"]}")
               store
               config))
            (wrong-chain-pre-cleanup-raw-response
              (request
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":193,"
                "\"method\":\"eth_getRawTransactionByHash\","
                "\"params\":[\"" wrong-chain-hash "\"]}")
               store
               config)))
        (let ((status (field wrong-chain-pre-cleanup-status-response
                             "result")))
          (is (string= (quantity-to-hex 0) (field status "pending")))
          (is (string= (quantity-to-hex 0) (field status "queued"))))
        (is (= 0 (length (field wrong-chain-pre-cleanup-pending-response
                                "result"))))
        (dolist (response (list wrong-chain-pre-cleanup-content-response
                                wrong-chain-pre-cleanup-content-from-response
                                wrong-chain-pre-cleanup-inspect-response))
          (let ((result (field response "result")))
            (is (empty-object-p (field result "pending")))
            (is (empty-object-p (field result "queued")))))
        (is (null (field wrong-chain-pre-cleanup-lookup-response "result")))
        (is (null (field wrong-chain-pre-cleanup-raw-response "result"))))
      (let* ((send-response (send-raw nonce-zero 189 store config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":190,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":191,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (wrong-chain-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":192,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" wrong-chain-hash "\"]}")
                store
                config))
             (wrong-chain-raw-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":193,"
                 "\"method\":\"eth_getRawTransactionByHash\","
                 "\"params\":[\"" wrong-chain-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending
               (field (field content "pending") (address-to-hex sender))))
        (is (string= nonce-zero-hash (field send-response "result")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))
        (is (string= nonce-zero-hash
                     (field (field pending "0") "hash")))
        (is (null (field content "queued")))
        (is (null (field wrong-chain-lookup-response "result")))
        (is (null (field wrong-chain-raw-response "result")))))))

(deftest txpool-pending-nonce-ignores-wrong-chain-pending-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (empty-object-p (object)
             (or (null object)
                 (typep object 'ethereum-lisp.core::json-empty-object)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (send-raw (transaction id store config)
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
               ",\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\""
               (bytes-to-hex (transaction-encoding transaction))
               "\"]}")
              store
              config)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (wrong-chain-nonce-zero
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              2))
           (valid-nonce-one
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 1
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (wrong-chain-hash
             (hash32-to-hex (transaction-hash wrong-chain-nonce-zero)))
           (valid-hash
             (hash32-to-hex (transaction-hash valid-nonce-one)))
           (sender
             (transaction-sender valid-nonce-one :expected-chain-id 1))
           (wrong-chain-sender
             (transaction-sender wrong-chain-nonce-zero :expected-chain-id 2))
           (head-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000))))
      (is (bytes= (address-bytes sender)
                  (address-bytes wrong-chain-sender)))
      (is (null (transaction-sender
                 wrong-chain-nonce-zero
                 :expected-chain-id 1)))
      (chain-store-put-block store head-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash head-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash head-block) sender 1000000)
      (ethereum-lisp.core::engine-payload-store-put-pending-transaction
       store
       wrong-chain-nonce-zero)
      (let* ((pre-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":201,"
                 "\"method\":\"eth_getTransactionCount\",\"params\":[\""
                 (address-to-hex sender) "\",\"pending\"]}")
                store
                config))
             (send-response
               (send-raw valid-nonce-one 202 store config))
             (post-count-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":203,"
                 "\"method\":\"eth_getTransactionCount\",\"params\":[\""
                 (address-to-hex sender) "\",\"pending\"]}")
                store
                config))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":204,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config))
             (content-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":205,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex sender) "\"]}")
                store
                config))
             (wrong-chain-lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":206,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" wrong-chain-hash "\"]}")
                store
                config))
             (status (field status-response "result"))
             (content (field content-response "result"))
             (pending (field content "pending"))
             (queued (field content "queued")))
        (is (string= (quantity-to-hex 0)
                     (field pre-count-response "result")))
        (is (string= valid-hash (field send-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field post-count-response "result")))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 1) (field status "queued")))
        (is (empty-object-p pending))
        (is (string= valid-hash (field (field queued "1") "hash")))
        (is (null (field wrong-chain-lookup-response "result")))))))

(deftest eth-rpc-get-transaction-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x55)))
           (log-address
             (make-address (make-byte-vector 20 :initial-element #x66)))
           (topic-1 (make-hash32
                     (make-byte-vector 32 :initial-element #x11)))
           (topic-2 (make-hash32
                     (make-byte-vector 32 :initial-element #x22)))
           (tx-1 (fixture-sign-legacy-transaction
                  (make-legacy-transaction
                   :nonce 5
                   :gas-price 8
                   :gas-limit 21000
                   :to recipient
                   :value 7)
                  1
                  1))
           (tx-2 (fixture-sign-legacy-transaction
                  (make-legacy-transaction
                   :nonce 6
                   :gas-price 9
                   :gas-limit 23000
                   :to recipient
                   :value 8)
                  1
                  1))
           (receipt-1
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic-1)
                           :data #(1)))))
           (receipt-2
             (make-receipt
              :status 1
              :cumulative-gas-used 44000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic-2)
                           :data #(2 3)))))
           (block
             (make-block
              :header (make-block-header :number 15
                                         :timestamp 150
                                         :gas-limit 30000000
                                         :base-fee-per-gas 6)
              :transactions (list tx-1 tx-2)
              :receipts (list receipt-1 receipt-2)))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (tx-2-hash-hex (hash32-to-hex (transaction-hash tx-2)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((receipt-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":60,"
                  "\"method\":\"eth_getTransactionReceipt\","
                  "\"params\":[\"" tx-2-hash-hex "\"]}")
                 store
                 config)))
             (receipt-result (field receipt-response "result"))
             (logs (field receipt-result "logs"))
             (log (first logs))
             (removed-entry (assoc "removed" log :test #'string=))
             (topics (field log "topics"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":61,"
                  "\"method\":\"eth_getTransactionReceipt\","
                  "\"params\":[\""
                  (hash32-to-hex (zero-hash32)) "\"]}")
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":62,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"0x1234\"]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (string= tx-2-hash-hex
                     (field receipt-result "transactionHash")))
        (is (string= (quantity-to-hex 1)
                     (field receipt-result "transactionIndex")))
        (is (string= block-hash-hex (field receipt-result "blockHash")))
        (is (string= (quantity-to-hex 15)
                     (field receipt-result "blockNumber")))
        (is (string= (address-to-hex recipient)
                     (field receipt-result "to")))
        (is (string= (quantity-to-hex 44000)
                     (field receipt-result "cumulativeGasUsed")))
        (is (string= (quantity-to-hex 23000)
                     (field receipt-result "gasUsed")))
        (is (null (field receipt-result "contractAddress")))
        (is (= 1 (length logs)))
        (is (string= (address-to-hex log-address)
                     (field log "address")))
        (is (= 1 (length topics)))
        (is (string= (hash32-to-hex topic-2) (first topics)))
        (is (string= "0x0203" (field log "data")))
        (is (string= (quantity-to-hex 1) (field log "logIndex")))
        (is removed-entry)
        (is (null (cdr removed-entry)))
        (is (stringp (field receipt-result "logsBloom")))
        (is (string= (address-to-hex (transaction-sender tx-2))
                     (field receipt-result "from")))
        (is (string= (quantity-to-hex 0)
                     (field receipt-result "type")))
        (is (string= (quantity-to-hex 9)
                     (field receipt-result "effectiveGasPrice")))
        (is (string= (quantity-to-hex 1)
                     (field receipt-result "status")))
        (is (null (field missing-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-block-receipts
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x77)))
           (log-address
             (make-address (make-byte-vector 20 :initial-element #x88)))
           (topic (make-hash32
                   (make-byte-vector 32 :initial-element #x33)))
           (tx-1 (fixture-sign-legacy-transaction
                  (make-legacy-transaction
                   :nonce 7
                   :gas-price 8
                   :gas-limit 21000
                   :to recipient
                   :value 9)
                  1
                  1))
           (tx-2 (fixture-sign-legacy-transaction
                  (make-legacy-transaction
                   :nonce 8
                   :gas-price 9
                   :gas-limit 23000
                   :to recipient
                   :value 10)
                  1
                  1))
           (receipt-1
             (make-receipt :status 1
                           :cumulative-gas-used 21000))
           (receipt-2
             (make-receipt
              :status 1
              :cumulative-gas-used 44000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic)
                           :data #(9)))))
           (block
             (make-block
              :header (make-block-header :number 16
                                         :timestamp 160
                                         :gas-limit 30000000
                                         :base-fee-per-gas 6)
              :transactions (list tx-1 tx-2)
              :receipts (list receipt-1 receipt-2)))
           (block-hash-hex (hash32-to-hex (block-hash block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (let* ((latest-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":63,\"method\":\"eth_getBlockReceipts\",\"params\":[\"latest\"]}"
                 store
                 config)))
             (latest-receipts (field latest-response "result"))
             (first-receipt (first latest-receipts))
             (second-receipt (second latest-receipts))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":64,"
                  "\"method\":\"eth_getBlockReceipts\","
                  "\"params\":[\"" block-hash-hex "\"]}")
                 store
                 config)))
             (hash-receipts (field hash-response "result"))
             (missing-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":65,\"method\":\"eth_getBlockReceipts\",\"params\":[\"0x63\"]}"
                 store
                 config)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":67,\"method\":\"eth_getBlockReceipts\",\"params\":[\"pending\"]}"
                 store
                 config)))
             (pending-object-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":68,\"method\":\"eth_getBlockReceipts\",\"params\":[{\"blockNumber\":\"pending\"}]}"
                 store
                 config)))
             (invalid-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":66,\"method\":\"eth_getBlockReceipts\",\"params\":[]}"
                 store
                 config)))
             (invalid-error (field invalid-response "error")))
        (is (= 2 (length latest-receipts)))
        (is (= 2 (length hash-receipts)))
        (is (string= (hash32-to-hex (transaction-hash tx-1))
                     (field first-receipt "transactionHash")))
        (is (string= (hash32-to-hex (transaction-hash tx-2))
                     (field second-receipt "transactionHash")))
        (is (string= block-hash-hex (field second-receipt "blockHash")))
        (is (string= (quantity-to-hex 16)
                     (field second-receipt "blockNumber")))
        (is (string= (quantity-to-hex 1)
                     (field second-receipt "transactionIndex")))
        (is (string= (quantity-to-hex 23000)
                     (field second-receipt "gasUsed")))
        (is (string= (address-to-hex (transaction-sender tx-2))
                     (field second-receipt "from")))
        (is (= 1 (length (field second-receipt "logs"))))
        (is (string= (quantity-to-hex 0)
                     (field (first (field second-receipt "logs"))
                            "logIndex")))
        (is (string= (field second-receipt "transactionHash")
                     (field (second hash-receipts)
                            "transactionHash")))
        (is (null (field missing-response "result")))
        (is (null (field pending-response "result")))
        (is (null (field pending-object-response "result")))
        (is (= -32602 (field invalid-error "code")))))))

(deftest eth-rpc-get-logs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (make-address (make-byte-vector 20 :initial-element #x44)))
           (address-a
             (make-address (make-byte-vector 20 :initial-element #xaa)))
           (address-b
             (make-address (make-byte-vector 20 :initial-element #xbb)))
           (topic-a (make-hash32
                     (make-byte-vector 32 :initial-element #x11)))
           (topic-b (make-hash32
                     (make-byte-vector 32 :initial-element #x22)))
           (topic-c (make-hash32
                     (make-byte-vector 32 :initial-element #x33)))
           (tx-1 (make-legacy-transaction :nonce 1
                                          :gas-price 8
                                          :gas-limit 21000
                                          :to recipient
                                          :value 1))
           (tx-2 (make-legacy-transaction :nonce 2
                                          :gas-price 9
                                          :gas-limit 22000
                                          :to recipient
                                          :value 2))
           (tx-3 (make-legacy-transaction :nonce 3
                                          :gas-price 10
                                          :gas-limit 23000
                                          :to recipient
                                          :value 3))
           (tx-4 (make-legacy-transaction :nonce 4
                                          :gas-price 11
                                          :gas-limit 24000
                                          :to recipient
                                          :value 4))
           (receipt-1
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address address-a
                           :topics (list topic-a topic-b)
                           :data #(1 2)))))
           (receipt-2
             (make-receipt
              :status 1
              :cumulative-gas-used 43000
              :logs (list (make-log-entry
                           :address address-b
                           :topics (list topic-a topic-c)
                           :data #(3)))))
           (receipt-3
             (make-receipt
              :status 1
              :cumulative-gas-used 23000
              :logs (list (make-log-entry
                           :address address-a
                           :topics (list topic-a topic-c)
                           :data #(4 5)))))
           (receipt-4
             (make-receipt
              :status 1
              :cumulative-gas-used 24000
              :logs (list (make-log-entry
                           :address address-a
                           :topics (list topic-a topic-b)
                           :data #(6)))))
           (block-1
             (make-block
              :header (make-block-header :number 40
                                         :timestamp 400
                                         :gas-limit 30000000)
              :transactions (list tx-1 tx-2)
              :receipts (list receipt-1 receipt-2)))
           (block-2
             (make-block
              :header (make-block-header :number 41
                                         :timestamp 410
                                         :gas-limit 30000000)
              :transactions (list tx-3)
              :receipts (list receipt-3)))
           (block-3
             (make-block
              :header (make-block-header :number 42
                                         :timestamp 420
                                         :gas-limit 30000000)
              :transactions (list tx-4)
              :receipts (list receipt-4)))
           (config (make-chain-config))
           (block-2-hash-hex (hash32-to-hex (block-hash block-2))))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (engine-payload-store-put-block store block-2 :state-available-p t)
      (let* ((range-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":67,"
                  "\"method\":\"eth_getLogs\","
                  "\"params\":[{\"fromBlock\":\"0x28\","
                  "\"toBlock\":\"0x28\","
                  "\"address\":\"" (address-to-hex address-a) "\","
                  "\"topics\":[\"" (hash32-to-hex topic-a) "\"]}]}")
                 store
                 config)))
             (range-logs (field range-response "result"))
             (range-log (first range-logs))
             (range-topics (field range-log "topics"))
             (block-hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":68,"
                  "\"method\":\"eth_getLogs\","
                  "\"params\":[{\"blockHash\":\"" block-2-hash-hex "\","
                  "\"topics\":[null,\"" (hash32-to-hex topic-c) "\"]}]}")
                 store
                 config)))
             (block-hash-logs (field block-hash-response "result"))
             (empty-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":69,"
                 "\"method\":\"eth_getLogs\","
                 "\"params\":[{\"fromBlock\":\"0x28\","
                 "\"toBlock\":\"0x29\","
                 "\"address\":\"" (address-to-hex recipient) "\"}]}")
                store
                config))
             (pending-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":169,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"pending\",\"toBlock\":\"pending\"}]}"
                store
                config))
             (invalid-range-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"0x29\",\"toBlock\":\"0x28\"}]}"
                 store
                 config)))
             (invalid-range-error
               (field invalid-range-response "error"))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":71,\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"0x1234\"}]}"
                 store
                 config)))
             (invalid-address-error
               (field invalid-address-response "error")))
        (is (= 1 (length range-logs)))
        (is (string= (address-to-hex address-a)
                     (field range-log "address")))
        (is (string= "0x0102" (field range-log "data")))
        (is (string= (hash32-to-hex (block-hash block-1))
                     (field range-log "blockHash")))
        (is (string= (quantity-to-hex 40)
                     (field range-log "blockNumber")))
        (is (string= (hash32-to-hex (transaction-hash tx-1))
                     (field range-log "transactionHash")))
        (is (string= (quantity-to-hex 0)
                     (field range-log "transactionIndex")))
        (is (string= (quantity-to-hex 0)
                     (field range-log "logIndex")))
        (is (= 2 (length range-topics)))
        (is (string= (hash32-to-hex topic-a) (first range-topics)))
        (is (string= (hash32-to-hex topic-b) (second range-topics)))
        (is (= 1 (length block-hash-logs)))
        (is (string= block-2-hash-hex
                     (field (first block-hash-logs) "blockHash")))
        (is (string= (quantity-to-hex 41)
                     (field (first block-hash-logs) "blockNumber")))
        (is (search "\"result\":[]" empty-json))
        (is (search "\"result\":[]" pending-json))
        (is (= -32602 (field invalid-range-error "code")))
        (is (= -32602 (field invalid-address-error "code"))))
      (let* ((new-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":72,"
                  "\"method\":\"eth_newFilter\","
                  "\"params\":[{\"fromBlock\":\"0x28\","
                  "\"address\":\"" (address-to-hex address-a) "\","
                  "\"topics\":[\"" (hash32-to-hex topic-a) "\"]}]}")
                 store
                 config)))
             (filter-id (field new-filter-response "result"))
             (pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":172,"
                  "\"method\":\"eth_newFilter\","
                  "\"params\":[{\"fromBlock\":\"pending\","
                  "\"address\":\"" (address-to-hex address-a) "\","
                  "\"topics\":[\"" (hash32-to-hex topic-a) "\"]}]}")
                 store
                 config)))
             (pending-filter-id (field pending-filter-response "result"))
             (pending-filter-logs-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":173,"
                 "\"method\":\"eth_getFilterLogs\","
                 "\"params\":[\"" pending-filter-id "\"]}")
                store
                config))
             (filter-logs-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":73,"
                  "\"method\":\"eth_getFilterLogs\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (filter-logs (field filter-logs-response "result"))
             (first-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":77,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (first-changes (field first-changes-response "result"))
             (second-changes-response
               (progn
                 (engine-payload-store-put-block
                  store block-3 :state-available-p t)
                 (parse-json
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":78,"
                    "\"method\":\"eth_getFilterChanges\","
                    "\"params\":[\"" filter-id "\"]}")
                   store
                   config))))
             (second-changes (field second-changes-response "result"))
             (pending-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":174,"
                  "\"method\":\"eth_getFilterChanges\","
                  "\"params\":[\"" pending-filter-id "\"]}")
                 store
                 config)))
             (pending-changes (field pending-changes-response "result"))
             (empty-changes-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":79,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (uninstall-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":74,"
                  "\"method\":\"eth_uninstallFilter\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (missing-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":75,"
                  "\"method\":\"eth_getFilterLogs\","
                  "\"params\":[\"" filter-id "\"]}")
                 store
                 config)))
             (missing-filter-error (field missing-filter-response "error"))
             (uninstall-missing-json
               (engine-rpc-handle-request-json
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":76,"
                 "\"method\":\"eth_uninstallFilter\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (uninstall-missing-response
               (parse-json uninstall-missing-json)))
        (is (string= (quantity-to-hex 1) filter-id))
        (is (string= (quantity-to-hex 2) pending-filter-id))
        (is (search "\"result\":[]" pending-filter-logs-json))
        (is (= 2 (length filter-logs)))
        (is (string= (quantity-to-hex 40)
                     (field (first filter-logs) "blockNumber")))
        (is (string= (quantity-to-hex 41)
                     (field (second filter-logs) "blockNumber")))
        (is (= 2 (length first-changes)))
        (is (string= (quantity-to-hex 40)
                     (field (first first-changes) "blockNumber")))
        (is (string= (quantity-to-hex 41)
                     (field (second first-changes) "blockNumber")))
        (is (= 1 (length second-changes)))
        (is (string= (quantity-to-hex 42)
                     (field (first second-changes) "blockNumber")))
        (is (= 1 (length pending-changes)))
        (is (string= (quantity-to-hex 42)
                     (field (first pending-changes) "blockNumber")))
        (is (search "\"result\":[]" empty-changes-json))
        (is (eq t (field uninstall-response "result")))
        (is (= -32602 (field missing-filter-error "code")))
        (is (null (field uninstall-missing-response "result")))
        (is (search "\"result\":false" uninstall-missing-json))))))

(deftest eth-rpc-log-filter-records-same-height-reorg-changes
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
           (log-address
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (topic
             (hash32-from-hex
              "0x2222222222222222222222222222222222222222222222222222222222222222"))
           (old-transaction
             (make-legacy-transaction :nonce 0
                                      :gas-price 2
                                      :gas-limit 21000
                                      :to recipient
                                      :value 3))
           (new-transaction
             (make-legacy-transaction :nonce 1
                                      :gas-price 3
                                      :gas-limit 21000
                                      :to recipient
                                      :value 4))
           (old-receipt
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic)
                           :data #(1)))))
           (new-receipt
             (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :address log-address
                           :topics (list topic)
                           :data #(2)))))
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
              :transactions (list old-transaction)
              :receipts (list old-receipt)))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(2))
              :transactions (list new-transaction)
              :receipts (list new-receipt))))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (engine-payload-store-put-block
       store old-canonical-child :state-available-p t)
      (let* ((filter-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":89,"
                 "\"method\":\"eth_newFilter\","
                 "\"params\":[{\"fromBlock\":\"0x0\","
                 "\"address\":\"" (address-to-hex log-address) "\","
                 "\"topics\":[\"" (hash32-to-hex topic) "\"]}]}")
                store
                config))
             (filter-id (field filter-response "result"))
             (future-filter-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":90,"
                 "\"method\":\"eth_newFilter\","
                 "\"params\":[{\"fromBlock\":\"0x2\","
                 "\"address\":\"" (address-to-hex log-address) "\","
                 "\"topics\":[\"" (hash32-to-hex topic) "\"]}]}")
                store
                config))
             (future-filter-id (field future-filter-response "result"))
             (initial-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":91,"
                 "\"method\":\"eth_getFilterChanges\","
                 "\"params\":[\"" filter-id "\"]}")
                store
                config))
             (initial-logs (field initial-response "result")))
        (is (= 1 (length initial-logs)))
        (is (string= "0x01" (field (first initial-logs) "data")))
        (is (null (field (first initial-logs) "removed")))
        (engine-payload-store-put-block
         store new-canonical-child :state-available-p t)
        (let* ((forkchoice-response
                 (request (forkchoice-json 92 (block-hash new-canonical-child))
                          store
                          config))
               (changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":93,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (future-changes-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":94,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" future-filter-id "\"]}")
                  store
                  config))
               (empty-changes-json
                 (engine-rpc-handle-request-json
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":95,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (payload-status
                 (field (field forkchoice-response "result")
                        "payloadStatus"))
               (logs (field changes-response "result"))
               (future-logs (field future-changes-response "result"))
               (removed-log (first logs))
               (added-log (second logs)))
          (is (string= +payload-status-valid+
                       (field payload-status "status")))
          (is (= 2 (length logs)))
          (is (string= "0x01" (field removed-log "data")))
          (is (eq t (field removed-log "removed")))
          (is (string= (hash32-to-hex (block-hash old-canonical-child))
                       (field removed-log "blockHash")))
          (is (string= "0x02" (field added-log "data")))
          (is (null (field added-log "removed")))
          (is (string= (hash32-to-hex (block-hash new-canonical-child))
                       (field added-log "blockHash")))
          (is (null future-logs))
          (is (search "\"result\":[]" empty-changes-json)))))))

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

(deftest engine-rpc-http-post-dispatches-json-rpc
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12))))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":17,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json; charset=utf-8~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (http-response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (rpc-response (parse-json (http-body http-response)))
           (local (first (field rpc-response "result"))))
      (is (= 200 (http-status http-response)))
      (is (search "Connection: close" http-response))
      (is (= 17 (field rpc-response "id")))
      (is (string= "ethereum-lisp" (field local "name"))))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":117,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST /engine/v1?trace=true HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (http-response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)
              :rpc-prefix "/engine"))
           (rpc-response (parse-json (http-body http-response))))
      (is (= 200 (http-status http-response)))
      (is (= 117 (field rpc-response "id"))))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":30,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST /unexpected HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (http-response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 404 (http-status http-response)))
      (is (search "not found" (http-body http-response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST /public HTTP/1.1
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :rpc-prefix "/engine")))
      (is (= 404 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "OPTIONS / HTTP/1.1
Origin: https://runner.example
Access-Control-Request-Method: POST
Access-Control-Request-Headers: Content-Type, Authorization

"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :cors-origins '("*"))))
      (is (= 204 (http-status response)))
      (is (search "Access-Control-Allow-Origin: *" response))
      (is (search "Access-Control-Allow-Methods: GET, POST, OPTIONS"
                  response))
      (is (search "Access-Control-Allow-Headers: Authorization, Content-Type"
                  response)))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":119,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Origin: https://runner.example~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)
              :cors-origins '("https://runner.example"))))
      (is (= 200 (http-status response)))
      (is (search "Access-Control-Allow-Origin: https://runner.example"
                  response))
      (is (search "Vary: Origin" response)))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "OPTIONS / HTTP/1.1
Origin: https://other.example
Access-Control-Request-Method: POST

"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :cors-origins '("https://runner.example"))))
      (is (= 403 (http-status response))))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":120,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: runner.local:8551~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)
              :allowed-hosts '("runner.local")))
           (rpc-response (parse-json (http-body response))))
      (is (= 200 (http-status response)))
      (is (= 120 (field rpc-response "id"))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Host: blocked.local
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :allowed-hosts '("runner.local"))))
      (is (= 403 (http-status response)))
      (is (search "host is not allowed" response)))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :allowed-hosts '("*"))))
      (is (= 200 (http-status response))))
    (let* ((body "{\"jsonrpc\":\"2.0\",\"id\":18,")
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (http-response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (rpc-response (parse-json (http-body http-response)))
           (error (field rpc-response "error")))
      (is (= 200 (http-status http-response)))
      (is (not (field rpc-response "id")))
      (is (= -32700 (field error "code"))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: text/plain

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 415 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "PUT / HTTP/1.1
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 405 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2x

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: -1

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: +2

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2
Content-Length: 2

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
: nope
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.0
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1 trailing
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))))

(deftest engine-rpc-http-validates-jwt-bearer-auth
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12)))
           (request (body &key token)
             (with-output-to-string (stream)
               (format stream "POST / HTTP/1.1~%Host: localhost~%")
               (format stream "Content-Type: application/json~%")
               (when token
                 (format stream "Authorization: Bearer ~A~%" token))
               (format stream "Content-Length: ~D~%~%~A" (length body) body))))
    (let* ((secret (make-byte-vector 32 :initial-element #x42))
           (now 1000)
           (body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":18,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (token (engine-rpc-make-jwt-token secret now))
           (http-response
             (engine-rpc-handle-http-request-string
              (request body :token token)
              (make-engine-payload-memory-store)
              (make-chain-config)
              :jwt-secret secret
              :now now))
           (rpc-response (parse-json (http-body http-response)))
           (local (first (field rpc-response "result"))))
      (is (string=
           "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjEwMDB9.WR0G-_BFmXHetdB5_3grgcntOfG-gyUJd1ALOObOAbM"
           token))
      (is (= 200 (http-status http-response)))
      (is (= 18 (field rpc-response "id")))
      (is (string= "ethereum-lisp" (field local "name")))
      (let ((missing-response
              (engine-rpc-handle-http-request-string
               (request body)
               (make-engine-payload-memory-store)
               (make-chain-config)
               :jwt-secret secret
               :now now)))
        (is (= 401 (http-status missing-response))))
      (let* ((stale-token (engine-rpc-make-jwt-token secret (- now 61)))
             (stale-response
               (engine-rpc-handle-http-request-string
                (request body :token stale-token)
                (make-engine-payload-memory-store)
                (make-chain-config)
                :jwt-secret secret
                :now now)))
        (is (= 401 (http-status stale-response))))
      (let* ((expired-token
               (engine-rpc-make-jwt-token
                secret now :expires-at (1- now)))
             (expired-response
               (engine-rpc-handle-http-request-string
                (request body :token expired-token)
                (make-engine-payload-memory-store)
                (make-chain-config)
                :jwt-secret secret
                :now now)))
        (is (= 401 (http-status expired-response))))
      (let* ((duplicate-request
               (with-output-to-string (stream)
                 (format stream "POST / HTTP/1.1~%Host: localhost~%")
                 (format stream "Content-Type: application/json~%")
                 (format stream "Authorization: Bearer ~A~%" token)
                 (format stream "Authorization: Bearer ~A~%"
                         (engine-rpc-make-jwt-token secret (- now 61)))
                 (format stream "Content-Length: ~D~%~%~A"
                         (length body)
                         body)))
             (duplicate-response
               (engine-rpc-handle-http-request-string
                duplicate-request
                (make-engine-payload-memory-store)
                (make-chain-config)
                :jwt-secret secret
                :now now)))
        (is (= 401 (http-status duplicate-response)))))))

(deftest engine-rpc-http-stream-handles-single-connection
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12))))
    (let* ((secret (make-byte-vector 32 :initial-element #x24))
           (now 2000)
           (token (engine-rpc-make-jwt-token secret now))
           (body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":19,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Authorization: Bearer ~A~%Content-Length: ~D~%~%~A"
                     token
                     (length body)
                     body))
           (input (make-string-input-stream request))
           (output (make-string-output-stream))
           (returned-response
             (engine-rpc-handle-http-stream
              input
              output
              (make-engine-payload-memory-store)
              (make-chain-config)
              :jwt-secret secret
              :now now))
           (written-response (get-output-stream-string output))
           (rpc-response (parse-json (http-body written-response)))
           (local (first (field rpc-response "result"))))
      (is (string= returned-response written-response))
      (is (= 200 (http-status written-response)))
      (is (search "Connection: close" written-response))
      (is (= 19 (field rpc-response "id")))
      (is (string= "ethereum-lisp" (field local "name"))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 4

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2x

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: +2

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2
Content-Length: 2

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
: nope
Content-Type: application/json

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.0
Content-Type: application/json

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1 trailing
Content-Type: application/json

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))))

(deftest engine-rpc-http-request-telemetry-includes-response-outcome
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (request (body)
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body)))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (head-hash
             "0x1111111111111111111111111111111111111111111111111111111111111111")
           (zero-hash
             "0x0000000000000000000000000000000000000000000000000000000000000000")
           (body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":30,"
              "\"method\":\"engine_forkchoiceUpdatedV1\","
              "\"params\":[{\"headBlockHash\":\"" head-hash "\","
              "\"safeBlockHash\":\"" zero-hash "\","
              "\"finalizedBlockHash\":\"" zero-hash "\"},null]}"))
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream))
           (response
             (engine-rpc-handle-http-stream
              input output
              (make-engine-payload-memory-store)
              (make-chain-config)
              :telemetry-sink sink))
           (rpc-response (parse-json (http-body response)))
           (fields
             (ethereum-lisp.telemetry:telemetry-event-fields
              (first (ethereum-lisp.telemetry:telemetry-events sink)))))
      (is (string= +payload-status-syncing+
                   (field (field (field rpc-response "result")
                                 "payloadStatus")
                          "status")))
      (is (string= "/" (field fields "httpTarget")))
      (is (string= +payload-status-syncing+
                   (field fields "rpcPayloadStatus"))))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (body
             "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"engine_missingMethod\",\"params\":[]}")
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input output
       (make-engine-payload-memory-store)
       (make-chain-config)
       :telemetry-sink sink)
      (let ((fields
              (ethereum-lisp.telemetry:telemetry-event-fields
               (first (ethereum-lisp.telemetry:telemetry-events sink)))))
        (is (string= "-32601" (field fields "rpcErrorCode")))))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (body "{\"jsonrpc\":\"2.0\",\"id\":32,")
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input output
       (make-engine-payload-memory-store)
       (make-chain-config)
       :telemetry-sink sink)
      (let ((fields
              (ethereum-lisp.telemetry:telemetry-event-fields
               (first (ethereum-lisp.telemetry:telemetry-events sink)))))
        (is (string= "200" (field fields "status")))
        (is (string= "-32700" (field fields "rpcErrorCode")))
        (is (null (field fields "rpcMethods")))))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (body
             "{\"jsonrpc\":\"2.0\",\"id\":33,\"method\":\"eth_blockNumber\",\"params\":7}")
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input output
       (make-engine-payload-memory-store)
       (make-chain-config)
       :telemetry-sink sink)
      (let ((fields
              (ethereum-lisp.telemetry:telemetry-event-fields
               (first (ethereum-lisp.telemetry:telemetry-events sink)))))
        (is (string= "200" (field fields "status")))
        (is (string= "eth_blockNumber" (field fields "rpcMethods")))
        (is (string= "-32600" (field fields "rpcErrorCode")))))))

(deftest engine-rpc-http-service-wraps-stream-configuration
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12))))
    (let* ((coinbase
             (address-from-hex "0x00000000000000000000000000000000000000cb"))
           (default-service (make-engine-rpc-http-service))
           (secret (make-byte-vector 32 :initial-element #x55))
           (sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (now 3000)
           (service
             (make-engine-rpc-http-service
              :host "127.0.0.1"
              :port 8551
              :jwt-secret secret
              :now-provider (lambda () now)
              :import-function #'execute-and-commit-engine-payload
              :rpc-prefix "/engine"
              :coinbase coinbase
              :telemetry-sink sink)))
      (is (string= "localhost:8551"
                   (engine-rpc-http-service-endpoint default-service)))
      (is (string= "127.0.0.1:8551"
                   (engine-rpc-http-service-endpoint service)))
      (is (null (engine-rpc-http-service-telemetry-sink default-service)))
      (is (eq sink (engine-rpc-http-service-telemetry-sink service)))
      (is (functionp
           (engine-rpc-http-service-import-function default-service)))
      (is (eq #'execute-and-commit-engine-payload
              (engine-rpc-http-service-import-function default-service)))
      (is (string= "/" (engine-rpc-http-service-rpc-prefix default-service)))
      (is (string= "/engine" (engine-rpc-http-service-rpc-prefix service)))
      (is (string= (address-to-hex (zero-address))
                   (address-to-hex
                    (engine-rpc-http-service-coinbase default-service))))
      (is (string= (address-to-hex coinbase)
                   (address-to-hex
                    (engine-rpc-http-service-coinbase service))))
      (is (typep (engine-rpc-http-service-store service)
                 'engine-payload-memory-store))
      (is (typep (engine-rpc-http-service-config service) 'chain-config))
      (is (functionp (engine-rpc-http-service-import-function service)))
      (let* ((body
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":20,"
                "\"method\":\"engine_getClientVersionV1\","
                "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
                "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
             (token (engine-rpc-make-jwt-token secret now))
             (request
               (format nil
                       "POST /engine HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Authorization: Bearer ~A~%Content-Length: ~D~%~%~A"
                       token
                       (length body)
                       body))
             (input (make-string-input-stream request))
             (output (make-string-output-stream))
             (response
               (engine-rpc-http-service-handle-stream
                service input output))
             (rpc-response (parse-json (http-body response)))
             (local (first (field rpc-response "result"))))
        (is (= 200 (http-status response)))
        (is (string= response (get-output-stream-string output)))
        (is (= 20 (field rpc-response "id")))
        (is (string= "ethereum-lisp" (field local "name"))))
      (let ((events (ethereum-lisp.telemetry:telemetry-events sink)))
        (is (= 4 (length events)))
        (is (string= "engine.rpc.http.stream.start"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (first events))))
        (is (string= "engine.rpc.http.request"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (second events))))
        (is (string= "200"
                     (cdr (assoc "status"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (second events))
                                 :test #'string=))))
        (is (string= "engine_getClientVersionV1"
                     (cdr (assoc "rpcMethods"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (second events))
                                 :test #'string=))))
        (is (string= "engine.rpc.http.streams"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (third events))))
        (is (= 1
               (ethereum-lisp.telemetry:telemetry-event-value
                (third events))))
        (is (string= "engine.rpc.http.stream.finish"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (fourth events))))
        (is (string= "127.0.0.1:8551"
                     (cdr (assoc "endpoint"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (first events))
                                 :test #'string=)))))
      (signals block-validation-error
        (make-engine-rpc-http-service :rpc-prefix "engine"))
      (signals block-validation-error
        (make-engine-rpc-http-service :port 70000))
      (signals block-validation-error
        (make-engine-rpc-http-service
         :jwt-secret (make-byte-vector 31 :initial-element 1)))
      (signals block-validation-error
        (make-engine-rpc-http-service :import-function "not a function")))))

(deftest engine-rpc-http-service-serves-listener-connections
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12)))
           (request (id)
             (let ((body
                     (format nil
                             "{\"jsonrpc\":\"2.0\",\"id\":~D,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"TT\",\"name\":\"test\",\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"
                             id)))
               (format nil
                       "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                       (length body)
                       body))))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (service (make-engine-rpc-http-service :telemetry-sink sink))
           (output-a (make-string-output-stream))
           (output-b (make-string-output-stream))
           (closed-connections 0)
           (closed-listener-p nil)
           (connections
             (list
              (make-engine-rpc-http-connection
               :input-stream (make-string-input-stream (request 21))
               :output-stream output-a
               :close-function (lambda () (incf closed-connections)))
              (make-engine-rpc-http-connection
               :input-stream (make-string-input-stream (request 22))
               :output-stream output-b
               :close-function (lambda () (incf closed-connections)))))
           (listener
             (make-engine-rpc-http-listener
              :endpoint (engine-rpc-http-service-endpoint service)
              :accept-function
              (lambda ()
                (when connections
                  (pop connections)))
              :close-function
              (lambda () (setf closed-listener-p t)))))
      (is (string= "localhost:8551"
                   (engine-rpc-http-listener-endpoint listener)))
      (is (= 2 (engine-rpc-http-service-serve-listener
                service listener :max-connections 10)))
      (is (= 2 closed-connections))
      (is closed-listener-p)
      (let* ((response-a (get-output-stream-string output-a))
             (response-b (get-output-stream-string output-b))
             (rpc-a (parse-json (http-body response-a)))
             (rpc-b (parse-json (http-body response-b))))
        (is (= 200 (http-status response-a)))
        (is (= 200 (http-status response-b)))
        (is (= 21 (field rpc-a "id")))
        (is (= 22 (field rpc-b "id"))))
      (let ((events (ethereum-lisp.telemetry:telemetry-events sink)))
        (is (= 11 (length events)))
        (is (string= "engine.rpc.http.listener.start"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (first events))))
        (is (string= "engine.rpc.http.stream.start"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (second events))))
        (is (string= "engine.rpc.http.request"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (third events))))
        (is (string= "200"
                     (cdr (assoc "status"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (third events))
                                 :test #'string=))))
        (is (string= "engine_getClientVersionV1"
                     (cdr (assoc "rpcMethods"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (third events))
                                 :test #'string=))))
        (is (string= "engine.rpc.http.stream.finish"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (fifth events))))
        (is (string= "engine.rpc.http.listener.connections"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (tenth events))))
        (is (= 2
               (ethereum-lisp.telemetry:telemetry-event-value
                (tenth events))))
        (is (string= "engine.rpc.http.listener.finish"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (nth 10 events)))))
      (signals block-validation-error
        (engine-rpc-http-listener-accept
         (make-engine-rpc-http-listener
          :endpoint "localhost:8551"
          :accept-function (lambda () "not-a-connection"))))
      (signals block-validation-error
        (engine-rpc-http-service-serve-listener
         service listener :max-connections -1)))))

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

#+sbcl
(deftest engine-rpc-http-service-serves-local-socket
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12)))
           (endpoint-port (endpoint)
             (parse-integer
              endpoint
              :start (1+ (position #\: endpoint :from-end t))))
           (read-stream-string (stream)
             (with-output-to-string (out)
               (loop for char = (read-char stream nil nil)
                     while char
                     do (write-char char out))))
           (connect-stream (host port)
             (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                                          :type :stream
                                          :protocol :tcp)))
               (sb-bsd-sockets:socket-connect
                socket
                (sb-bsd-sockets:make-inet-address host)
                port)
               (sb-bsd-sockets:socket-make-stream
                socket
                :input t
                :output t
                :element-type 'character
                :external-format :utf-8
                :buffering :none))))
    (let* ((service (make-engine-rpc-http-service
                     :host "127.0.0.1"
                     :port 0))
           (listener
             (handler-case
                 (make-engine-rpc-http-socket-listener service)
               (sb-bsd-sockets:operation-not-permitted-error ()
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))))
           (port (endpoint-port
                  (engine-rpc-http-listener-endpoint listener)))
           (server-thread
             (sb-thread:make-thread
              (lambda ()
                (engine-rpc-http-service-serve-listener
                 service listener :max-connections 1)))))
      (unwind-protect
           (let* ((body
                    (concatenate
                     'string
                     "{\"jsonrpc\":\"2.0\",\"id\":23,"
                     "\"method\":\"engine_getClientVersionV1\","
                     "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
                     "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
                  (request
                    (format nil
                            "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                            (length body)
                            body))
                  (stream (connect-stream "127.0.0.1" port)))
             (unwind-protect
                  (progn
                    (write-string request stream)
                    (finish-output stream)
                    (let* ((response (read-stream-string stream))
                           (rpc-response (parse-json (http-body response)))
                           (local (first (field rpc-response "result"))))
                      (is (= 200 (http-status response)))
                      (is (search "Connection: close" response))
                      (is (= 23 (field rpc-response "id")))
                      (is (string= "ethereum-lisp"
                                   (field local "name")))))
               (close stream))
             (sb-thread:join-thread server-thread))
        (ignore-errors (engine-rpc-http-listener-close listener))))))

(deftest block-body-root-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 3
                                               :to address
                                               :value 4))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (block (make-block :transactions (list transaction)
                            :withdrawals (list withdrawal))))
    (is (validate-block-body-roots block))
    (setf (block-header-transactions-root (block-header block)) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-list-before-derived-fields
  (let ((block (make-block)))
    (setf (block-transactions block) (list "not a transaction"))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-ommer-list-before-root-derivation
  (let ((block (make-block)))
    (setf (block-ommers block) (list "not a header"))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-commitment-fields-before-comparison
  (let* ((block (make-block))
         (header (block-header block)))
    (setf (block-header-ommers-hash header) nil)
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-ommers-hash header) +empty-ommers-hash+
          (block-header-transactions-root header) nil)
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-transactions-root header) +empty-trie-hash+
          (block-header-withdrawals-root header) "not a hash")
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-withdrawals-root header) nil
          (block-header-requests-hash header) "not a hash")
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validation-uses-chain-config-transaction-types
  (let* ((config (make-chain-config :berlin-block 5
                                    :london-block 10
                                    :prague-time 30))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (access-list (make-access-list-transaction :to recipient))
         (dynamic (make-dynamic-fee-transaction :to recipient))
         (set-code (make-set-code-transaction
                    :to recipient
                    :authorization-list
                    (list (make-set-code-authorization
                           :address recipient))))
         (berlin-block
           (make-block :header (make-block-header :number 5 :timestamp 0)
                       :transactions (list access-list)))
         (pre-london-block
           (make-block :header (make-block-header :number 9 :timestamp 0)
                       :transactions (list dynamic)))
         (london-block
           (make-block :header (make-block-header :number 10 :timestamp 0)
                       :transactions (list dynamic)))
         (pre-prague-block
           (make-block :header (make-block-header :number 10 :timestamp 29)
                       :transactions (list set-code)))
         (prague-block
           (make-block :header (make-block-header :number 10 :timestamp 30)
                       :transactions (list set-code))))
    (is (validate-block-body-against-config berlin-block config))
    (signals block-validation-error
      (validate-block-body-against-config pre-london-block config))
    (is (validate-block-body-against-config london-block config))
    (signals block-validation-error
      (validate-block-body-against-config pre-prague-block config))
    (is (validate-block-body-against-config prague-block config))))

(deftest block-body-validates-1559-fee-caps
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (valid (make-dynamic-fee-transaction
                 :to recipient
                 :max-priority-fee-per-gas 1
                 :max-fee-per-gas 5))
         (fee-too-low (make-dynamic-fee-transaction
                       :to recipient
                       :max-priority-fee-per-gas 1
                       :max-fee-per-gas 4))
         (tip-too-high (make-set-code-transaction
                        :to recipient
                        :max-priority-fee-per-gas 6
                        :max-fee-per-gas 5
                        :authorization-list
                        (list (make-set-code-authorization
                               :address recipient)))))
    (is (validate-block-body-roots
         (make-block :header (make-block-header :base-fee-per-gas 5)
                     :transactions (list valid))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header (make-block-header :base-fee-per-gas 5)
                   :transactions (list fee-too-low))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header (make-block-header :base-fee-per-gas 5)
                   :transactions (list tip-too-high))))))

(deftest block-body-validates-access-list-fields-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-address-tx
           (make-access-list-transaction
            :to recipient
            :access-list
            (list (make-access-list-entry :address nil))))
         (bad-slot-tx
           (make-access-list-transaction
            :to recipient
            :access-list
            (list (make-access-list-entry
                   :address recipient
                   :storage-keys (list nil))))))
    (setf (block-transactions block) (list bad-address-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list bad-slot-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-data-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-data-tx
           (make-legacy-transaction :to recipient
                                    :data "not bytes")))
    (setf (block-transactions block) (list bad-data-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-recipient-before-root-derivation
  (let* ((block (make-block))
         (bad-recipient-tx
           (make-legacy-transaction :to #(1 2 3))))
    (setf (block-transactions block) (list bad-recipient-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-transaction-scalars-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-nonce-tx
           (make-legacy-transaction :nonce (ash 1 64)
                                    :to recipient))
         (bad-gas-limit-tx
           (make-legacy-transaction :gas-limit (ash 1 64)
                                    :to recipient))
         (bad-value-tx
           (make-legacy-transaction :value (1+ +uint256-max+)
                                    :to recipient))
         (bad-fee-tx
           (make-dynamic-fee-transaction
            :to recipient
            :max-priority-fee-per-gas 2
            :max-fee-per-gas 1))
         (bad-blob-fee-tx
           (make-blob-transaction
            :to recipient
            :blob-versioned-hashes
            (list (hash32-from-hex
                   "0x0100000000000000000000000000000000000000000000000000000000000000"))
            :max-fee-per-blob-gas (1+ +uint256-max+))))
    (dolist (transaction (list bad-nonce-tx
                               bad-gas-limit-tx
                               bad-value-tx
                               bad-fee-tx
                               bad-blob-fee-tx))
      (setf (block-transactions block) (list transaction))
      (signals block-validation-error
        (validate-block-body-roots block)))))

(deftest block-body-validates-transaction-signature-fields-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (bad-legacy-v-tx
           (make-legacy-transaction :to recipient
                                    :v (1+ +uint256-max+)))
         (bad-typed-chain-tx
           (make-dynamic-fee-transaction :to recipient
                                         :chain-id (1+ +uint256-max+)))
         (bad-typed-y-parity-tx
           (make-dynamic-fee-transaction :to recipient
                                         :y-parity (1+ +uint256-max+)))
         (bad-typed-r-tx
           (make-dynamic-fee-transaction :to recipient
                                         :r (1+ +uint256-max+)))
         (bad-typed-s-tx
           (make-dynamic-fee-transaction :to recipient
                                         :s (1+ +uint256-max+))))
    (dolist (transaction (list bad-legacy-v-tx
                               bad-typed-chain-tx
                               bad-typed-y-parity-tx
                               bad-typed-r-tx
                               bad-typed-s-tx))
      (setf (block-transactions block) (list transaction))
      (signals block-validation-error
        (validate-block-body-roots block)))))

(deftest block-body-validates-set-code-fields-before-root-derivation
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (block (make-block))
         (missing-to-tx
           (make-set-code-transaction
            :to nil
            :authorization-list
            (list (make-set-code-authorization :address recipient))))
         (missing-auth-tx
           (make-set-code-transaction :to recipient))
         (bad-auth-address-tx
           (make-set-code-transaction
            :to recipient
            :authorization-list
            (list (make-set-code-authorization :address nil))))
         (bad-auth-chain-tx
           (make-set-code-transaction
            :to recipient
            :authorization-list
            (list (make-set-code-authorization
                   :chain-id (1+ +uint256-max+)
                   :address recipient)))))
    (setf (block-transactions block) (list missing-to-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list missing-auth-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list bad-auth-address-tx))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-transactions block) (list bad-auth-chain-tx))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-validation-combines-config-header-and-body-checks
  (let* ((config (make-chain-config :london-block 0
                                    :shanghai-time 150
                                    :cancun-time 200
                                    :prague-time 300))
         (parent (make-block-header :number 7
                                    :gas-limit 1024000
                                    :gas-used 512000
                                    :timestamp 198
                                    :base-fee-per-gas 1000))
         (parent-hash (block-header-hash parent))
         (valid-header
           (make-block-header :parent-hash parent-hash
                              :number 8
                              :gas-limit 1024000
                              :gas-used 0
                              :timestamp 300
                              :base-fee-per-gas 1000
                              :blob-gas-used 0
                              :excess-blob-gas 0
                              :parent-beacon-root (zero-hash32)))
         (valid-block
           (make-block :header valid-header
                       :withdrawals '()
                       :requests '()))
         (missing-withdrawals-parent
           (make-block-header :number 7
                              :gas-limit 1024000
                              :gas-used 512000
                              :timestamp 149
                              :base-fee-per-gas 1000))
         (missing-withdrawals-root
           (make-block :header
                       (make-block-header :parent-hash
                                          (block-header-hash
                                           missing-withdrawals-parent)
                                          :number 8
                                          :gas-limit 1024000
                                          :gas-used 0
                                          :timestamp 150
                                          :base-fee-per-gas 1000)))
         (pre-london-parent
           (make-block-header :number 8
                              :gas-limit 1024000
                              :gas-used 512000
                              :timestamp 10))
         (pre-london-header
           (make-block-header :parent-hash
                              (block-header-hash pre-london-parent)
                              :number 9
                              :gas-limit 1024000
                              :gas-used 0
                              :timestamp 11))
         (pre-london-block
           (make-block :header pre-london-header
                       :transactions
                       (list (make-dynamic-fee-transaction
                              :to (address-from-hex
                                   "0x0000000000000000000000000000000000000001"))))))
    (is (validate-block-against-config parent valid-block config))
    (signals block-validation-error
      (validate-block-against-config missing-withdrawals-parent
                                     missing-withdrawals-root config))
    (signals block-validation-error
      (validate-block-against-config pre-london-parent pre-london-block
                                     (make-chain-config :london-block 10)))))

(deftest block-body-validates-execution-requests-hash
  (let* ((block (make-block :requests (list #(#x00 #xbb) #(#x01 #xaa))))
         (header (block-header block)))
    (is (validate-block-body-roots block))
    (is (string= (hash32-to-hex
                  (execution-requests-hash (block-requests block)))
                 (hash32-to-hex (block-header-requests-hash header))))
    (setf (block-header-requests-hash header) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block)))
  (let ((header-without-requests
          (make-block-header :requests-hash
                             (execution-requests-hash (list #(#x01 #xaa))))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header header-without-requests))))
  (let ((pre-prague-block (make-block :requests (list #(#x01 #xaa)))))
    (setf (block-header-requests-hash (block-header pre-prague-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-prague-block))))

(deftest block-body-validates-request-list-before-hash-derivation
  (let ((block (make-block)))
    (setf (block-requests block) "not a request list"
          (block-requests-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-block-access-list-hash
  (let* ((block (make-block :block-access-list '()))
         (header (block-header block)))
    (is (validate-block-body-roots block))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (setf (block-header-block-access-list-hash header) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block)))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (block (make-block :block-access-list (list account))))
    (is (validate-block-body-roots block))
    (is (bytes= (block-access-list-rlp (list account))
                (block-encoded-block-access-list block)))
    (is (string= (hash32-to-hex (block-access-list-hash (list account)))
                 (hash32-to-hex
                  (block-header-block-access-list-hash
                   (block-header block))))))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (encoded (block-access-list-rlp (list account)))
         (block (make-block :block-access-list-rlp encoded)))
    (is (block-block-access-list-present-p block))
    (is (bytes= encoded (block-encoded-block-access-list block)))
    (is (bytes= encoded
                (block-access-list-rlp (block-block-access-list block))))
    (is (string= (hash32-to-hex (block-access-list-rlp-hash encoded))
                 (hash32-to-hex
                  (block-header-block-access-list-hash
                   (block-header block)))))
    (is (validate-block-body-roots block))
    (setf (block-encoded-block-access-list block) (block-access-list-rlp '()))
    (signals block-validation-error
      (validate-block-body-roots block))
    (signals block-validation-error
      (make-block :block-access-list (list account)
                  :block-access-list-rlp encoded)))
  (let ((header-without-body
          (make-block-header :block-access-list-hash
                             (block-access-list-hash '()))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header header-without-body))))
  (let ((pre-amsterdam-block (make-block :block-access-list '())))
    (setf (block-header-block-access-list-hash
           (block-header pre-amsterdam-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-amsterdam-block))))

(deftest block-body-validates-block-access-list-code-change-size
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 0))
         (limit-code (make-byte-vector
                      +block-access-list-amsterdam-max-code-size+))
         (oversized-code (make-byte-vector
                          (1+ +block-access-list-amsterdam-max-code-size+)))
         (limit-account
           (make-block-access-account
            :address address
            :code-changes
            (list (make-block-access-code-change :tx-index 1
                                                 :code limit-code))))
         (oversized-account
           (make-block-access-account
            :address address
            :code-changes
            (list (make-block-access-code-change :tx-index 1
                                                 :code oversized-code))))
         (limit-block
           (make-block :header (make-block-header :timestamp 0)
                       :block-access-list (list limit-account)))
         (oversized-block
           (make-block :header (make-block-header :timestamp 0)
                       :block-access-list (list oversized-account))))
    (is (validate-block-body-against-config limit-block config))
    (signals block-validation-error
      (validate-block-body-against-config oversized-block config))
    (signals block-validation-error
      (validate-block-body-roots
       limit-block
       :block-access-list-max-code-size
       +block-access-list-max-code-size+))))

(deftest block-body-validates-block-access-list-item-gas-limit
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000001"))
         (read-slot (hash32-from-hex
                     "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (write-slot (hash32-from-hex
                      "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (slot-writes (make-block-access-slot-writes
                       :slot write-slot
                       :accesses
                       (list (make-block-access-storage-write
                              :tx-index 0
                              :value-after 7))))
         (account (make-block-access-account
                   :address address
                   :storage-writes (list slot-writes)
                   :storage-reads (list read-slot)))
         (access-list (list account))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 0))
         (limit-block
           (make-block :header (make-block-header
                                :timestamp 0
                                :gas-limit
                                (* 3 +block-access-list-item-gas-cost+))
                       :block-access-list access-list))
         (oversized-block
           (make-block :header (make-block-header
                                :timestamp 0
                                :gas-limit
                                (* 2 +block-access-list-item-gas-cost+))
                       :block-access-list access-list)))
    (is (= 3 (block-access-list-item-count access-list)))
    (is (validate-block-access-list-fields access-list
                                           :max-items 3))
    (signals block-validation-error
      (validate-block-access-list-fields access-list
                                         :max-items 2))
    (is (validate-block-body-against-config limit-block config))
    (signals block-validation-error
      (validate-block-body-against-config oversized-block config))))

(deftest block-body-validates-block-access-list-shape-before-hash
  (let ((block (make-block)))
    (setf (block-block-access-list block) "not a block access list"
          (block-block-access-list-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-blob-gas-used
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (bad-version-hash (hash32-from-hex
                            "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :chain-id 1
                       :nonce 1
                       :max-priority-fee-per-gas 2
                       :max-fee-per-gas 3
                       :gas-limit 21000
                       :to address
                       :max-fee-per-blob-gas 4
                       :blob-versioned-hashes (list blob-hash)))
         (block (make-block :transactions (list transaction))))
    (is (= +blob-gas-per-blob+
           (blob-gas-used (block-transactions block))))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (block-header-blob-gas-used (block-header block))
          +blob-gas-per-blob+)
    (is (validate-block-body-roots block))
    (setf (block-header-blob-gas-used (block-header block))
          (1+ +blob-gas-per-blob+))
    (signals block-validation-error
      (validate-block-body-roots block))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block
        :transactions
        (list (make-blob-transaction :to address
                                     :blob-versioned-hashes '())))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block
        :transactions
        (list (make-blob-transaction
              :to address
              :blob-versioned-hashes (list bad-version-hash))))))))

(deftest blob-gas-limit-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (max-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (too-many-hashes (append max-hashes (list blob-hash)))
         (max-tx (make-blob-transaction :to address
                                        :blob-versioned-hashes max-hashes))
         (too-large-tx (make-blob-transaction
                        :to address
                        :blob-versioned-hashes too-many-hashes))
         (max-block (make-block :transactions (list max-tx)))
         (too-large-header
           (make-block-header :blob-gas-used (* (1+ +max-blobs-per-block+)
                                                +blob-gas-per-blob+)
                              :excess-blob-gas 0)))
    (setf (block-header-blob-gas-used (block-header max-block))
          (* +max-blobs-per-block+ +blob-gas-per-blob+))
    (is (validate-block-body-roots max-block))
    (signals block-validation-error
      (validate-blob-transaction-fields too-large-tx))
    (signals block-validation-error
      (validate-blob-transaction-fields
       (make-blob-transaction :to nil
                              :blob-versioned-hashes (list blob-hash))))
    (signals block-validation-error
      (validate-blob-transaction-fields
       (make-blob-transaction :to address
                              :blob-versioned-hashes (list nil))))
    (signals block-validation-error
      (validate-blob-transaction-fields
       (make-blob-transaction :to address
                              :blob-versioned-hashes (list #(#x01 #x02)))))
    (signals block-validation-error
      (validate-block-blob-gas-fields too-large-header))))

(deftest osaka-block-body-allows-higher-aggregate-blob-limit
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat (- +osaka-max-blobs-per-block+
                                       +max-blobs-per-block+)
                             collect blob-hash))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes three-hashes)))
         (block (make-block :header (make-block-header
                                      :number 1
                                      :timestamp 10
                                      :blob-gas-used
                                      (* +osaka-max-blobs-per-block+
                                         +blob-gas-per-blob+)
                                      :excess-blob-gas 0)
                            :transactions transactions)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest prague-block-body-uses-expanded-blob-schedule
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat (- +osaka-max-blobs-per-block+
                                       +max-blobs-per-block+)
                             collect blob-hash))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :prague-time 10))
         (transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes three-hashes)))
         (block (make-block :header (make-block-header
                                      :number 1
                                      :timestamp 10
                                      :blob-gas-used
                                      (* +osaka-max-blobs-per-block+
                                         +blob-gas-per-blob+)
                                      :excess-blob-gas 0)
                            :transactions transactions)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest bpo-block-body-uses-scheduled-blob-limits
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (three-hashes (loop repeat 3 collect blob-hash))
         (two-hashes (loop repeat 2 collect blob-hash))
         (bpo1-transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes three-hashes)))
         (bpo2-transactions
           (append bpo1-transactions
                   (list (make-blob-transaction
                          :to address
                          :max-fee-per-blob-gas 1
                          :blob-versioned-hashes six-hashes))))
         (bpo3-transactions
           (append (loop repeat 5
                         collect (make-blob-transaction
                                  :to address
                                  :max-fee-per-blob-gas 1
                                  :blob-versioned-hashes six-hashes))
                   (list (make-blob-transaction
                          :to address
                          :max-fee-per-blob-gas 1
                          :blob-versioned-hashes two-hashes))))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :bpo1-time 30
                                    :bpo2-time 40
                                    :bpo3-time 50
                                    :bpo4-time 60))
         (bpo1-block
           (make-block :header (make-block-header
                                :number 1
                                :timestamp 30
                                :blob-gas-used
                                (* +bpo1-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo1-transactions))
         (bpo2-block
           (make-block :header (make-block-header
                                :number 2
                                :timestamp 40
                                :blob-gas-used
                                (* +bpo2-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo2-transactions))
         (bpo3-block
           (make-block :header (make-block-header
                                :number 3
                                :timestamp 50
                                :blob-gas-used
                                (* +bpo3-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo3-transactions))
         (bpo4-block
           (make-block :header (make-block-header
                                :number 4
                                :timestamp 60
                                :blob-gas-used
                                (* +bpo4-max-blobs-per-block+
                                   +blob-gas-per-blob+)
                                :excess-blob-gas 0)
                       :transactions bpo2-transactions)))
    (signals block-validation-error
      (validate-block-body-roots bpo1-block))
    (signals block-validation-error
      (validate-block-body-roots bpo2-block))
    (signals block-validation-error
      (validate-block-body-roots bpo3-block))
    (signals block-validation-error
      (validate-block-body-roots bpo4-block))
    (is (validate-block-body-against-config bpo1-block config))
    (is (validate-block-body-against-config bpo2-block config))
    (is (validate-block-body-against-config bpo3-block config))
    (is (validate-block-body-against-config bpo4-block config))))

(deftest custom-blob-schedule-body-validation-uses-active-entry
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (six-hashes (loop repeat +max-blobs-per-block+
                           collect blob-hash))
         (one-hash (list blob-hash))
         (config (make-chain-config
                  :london-block 0
                  :cancun-time 0
                  :custom-blob-schedule
                  (list (make-blob-schedule-entry :timestamp 20
                                                  :target-blobs 5
                                                  :max-blobs 7
                                                  :update-fraction 424242))))
         (transactions
           (list (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes six-hashes)
                 (make-blob-transaction :to address
                                        :max-fee-per-blob-gas 1
                                        :blob-versioned-hashes one-hash)))
         (block (make-block :header (make-block-header
                                      :number 1
                                      :timestamp 20
                                      :blob-gas-used (* 7 +blob-gas-per-blob+)
                                      :excess-blob-gas 0)
                            :transactions transactions)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest blob-sidecar-field-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proof (make-byte-vector +kzg-proof-size+))
         (versioned-hash (kzg-commitment-to-versioned-hash commitment))
         (transaction (make-blob-transaction
                       :to address
                       :blob-versioned-hashes (list versioned-hash)))
         (sidecar (make-blob-sidecar :blobs (list blob)
                                     :commitments (list commitment)
                                     :proofs (list proof))))
    (is (validate-blob-sidecar-fields sidecar :transaction transaction))
    (is (bytes= (hash32-bytes versioned-hash)
                (hash32-bytes (first (blob-sidecar-versioned-hashes sidecar)))))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       sidecar
       :transaction transaction
       :require-proof-verification t))
    (let ((observed nil))
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (setf observed
                      (list verified-blob verified-commitment verified-proof))
                t)))
        (is (kzg-blob-proof-verification-available-p))
        (is (validate-blob-sidecar-fields
             sidecar
             :transaction transaction
             :require-proof-verification t)))
      (is (bytes= blob (first observed)))
      (is (bytes= commitment (second observed)))
      (is (bytes= proof (third observed))))
    (let ((*kzg-blob-proof-verifier*
            (lambda (verified-blob verified-commitment verified-proof)
              (declare (ignore verified-blob verified-commitment
                               verified-proof))
              nil)))
      (signals block-validation-error
        (validate-blob-sidecar-fields
         sidecar
         :transaction transaction
         :require-proof-verification t)))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list commitment)
                          :proofs '())
       :transaction transaction))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list #())
                          :commitments (list commitment)
                          :proofs (list proof))))
    (let ((invalid-blob (copy-seq blob))
          (called nil))
      (replace invalid-blob
               (ethereum-lisp.crypto::integer-to-fixed-bytes
                ethereum-lisp.core::+kzg-field-modulus+
                32)
               :start1 0)
      (let ((*kzg-blob-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proof)
                (declare (ignore verified-blob verified-commitment
                                 verified-proof))
                (setf called t)
                t)))
        (signals block-validation-error
          (validate-blob-sidecar-fields
           (make-blob-sidecar :blobs (list invalid-blob)
                              :commitments (list commitment)
                              :proofs (list proof))
           :require-proof-verification t)))
      (is (null called)))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list #())
                          :proofs (list proof))))
    (signals block-validation-error
      (validate-blob-sidecar-fields
       (make-blob-sidecar :blobs (list blob)
                          :commitments (list commitment)
                          :proofs (list #()))))
    (let ((other-commitment (copy-seq commitment)))
      (setf (aref other-commitment 0) 1)
      (signals block-validation-error
        (validate-blob-sidecar-fields
         (make-blob-sidecar :blobs (list blob)
                            :commitments (list other-commitment)
                            :proofs (list proof))
         :transaction transaction)))))

(deftest kzg-command-verifier-adapter
  (let* ((suffix (format nil "~A-~A" (get-universal-time) (random 1000000)))
         (script-path
           (merge-pathnames
            (format nil "ethereum-lisp-kzg-verifier-~A.sh" suffix)
            (uiop:temporary-directory)))
         (sleep-script-path
           (merge-pathnames
            (format nil "ethereum-lisp-kzg-verifier-sleep-~A.sh" suffix)
            (uiop:temporary-directory)))
         (log-path
           (merge-pathnames
            (format nil "ethereum-lisp-kzg-verifier-~A.log" suffix)
            (uiop:temporary-directory)))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proof (make-byte-vector +kzg-proof-size+))
         (z (make-byte-vector ethereum-lisp.core::+kzg-field-element-size+))
         (y (make-byte-vector ethereum-lisp.core::+kzg-field-element-size+))
         (old-point-verifier *kzg-point-proof-verifier*)
         (old-blob-verifier *kzg-blob-proof-verifier*))
    (labels ((file-contents (path)
               (with-open-file (stream path :direction :input)
                 (let ((contents (make-string (file-length stream))))
                   (read-sequence contents stream)
                   contents))))
      (unwind-protect
           (progn
             (with-open-file (stream script-path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "#!/bin/sh~%")
               (format stream "log=\"$1\"~%")
               (format stream "verdict=\"$2\"~%")
               (format stream "shift 2~%")
               (format stream "case \"$1\" in~%")
               (format stream "  point) printf 'point %s %s %s %s\\n' \"${#2}\" \"${#3}\" \"${#4}\" \"${#5}\" > \"$log\" ;;~%")
               (format stream "  blob) printf 'blob %s %s %s\\n' \"${#2}\" \"${#3}\" \"${#4}\" > \"$log\" ;;~%")
               (format stream "  *) printf 'unknown\\n' > \"$log\" ;;~%")
               (format stream "esac~%")
               (format stream "if [ \"$verdict\" = accept ]; then echo true; else echo false; fi~%"))
             (with-open-file (stream sleep-script-path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (format stream "#!/bin/sh~%")
               (format stream "sleep 2~%")
               (format stream "echo true~%"))
             (configure-kzg-proof-command-verifiers
              (list "sh" (namestring script-path)
                    (namestring log-path)
                    "accept"))
             (is (kzg-proof-verification-available-p))
             (is (verify-kzg-point-proof commitment z y proof))
             (is (string= (format nil "point 98 66 66 98~%")
                          (file-contents log-path)))
             (is (verify-kzg-blob-proof blob commitment proof))
             (is (string=
                  (format nil "blob ~D 98 98~%"
                          (+ 2 (* 2 +blob-byte-size+)))
                  (file-contents log-path)))
             (configure-kzg-proof-command-verifiers
              (list "sh" (namestring script-path)
                    (namestring log-path)
                    "reject"))
             (signals error
               (verify-kzg-point-proof commitment z y proof))
             (signals error
               (verify-kzg-blob-proof blob commitment proof))
             (let ((ethereum-lisp.core::*kzg-verifier-command-timeout-seconds*
                     0))
               (configure-kzg-proof-command-verifiers
                (list "sh" (namestring sleep-script-path)))
               (signals error
                 (verify-kzg-point-proof commitment z y proof)))
             (signals error
               (make-kzg-point-proof-command-verifier '())))
        (setf *kzg-point-proof-verifier* old-point-verifier
              *kzg-blob-proof-verifier* old-blob-verifier)
        (when (probe-file script-path)
          (delete-file script-path))
        (when (probe-file sleep-script-path)
          (delete-file sleep-script-path))
        (when (probe-file log-path)
          (delete-file log-path))))))

(deftest kzg-go-ethereum-command-verifier-replays-canonical-vectors
  (let ((script (repo-kzg-verifier-command)))
    (let* ((valid-blob
             (let ((blob (make-byte-vector +blob-byte-size+))
                   (field-element
                     (ethereum-lisp.crypto::integer-to-fixed-bytes 2 32)))
               (loop for start below +blob-byte-size+ by 32
                     do (replace blob field-element :start1 start))
               blob))
           (valid-commitment
             (hex-to-bytes
              "0xa572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e"))
           (valid-point-z
             (hex-to-bytes
              "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000"))
           (valid-point-y
             (hex-to-bytes
              "0x0000000000000000000000000000000000000000000000000000000000000002"))
           (valid-proof
             (hex-to-bytes
              "0xc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"))
           (invalid-point-commitment
             (hex-to-bytes
              "0xb49d88afcd7f6c61a8ea69eff5f609d2432b47e7e4cd50b02cdddb4e0c1460517e8df02e4e64dc55e3d8ca192d57193a"))
           (invalid-point-z
             (hex-to-bytes
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           (invalid-point-y
             (hex-to-bytes
              "0x443e7af5274b52214ea6c775908c54519fea957eecd98069165a8b771082fd51"))
           (invalid-point-proof
             (hex-to-bytes
              "0xa7de1e32bb336b85e42ff5028167042188317299333f091dd88675e84a550577bfa564b2f57cd2498e2acf875e0aaa40"))
           (invalid-blob-proof
             (hex-to-bytes
              "0x97f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"))
           (old-point-verifier *kzg-point-proof-verifier*)
           (old-blob-verifier *kzg-blob-proof-verifier*))
      (unwind-protect
           (progn
             ;; Sources: go-eth-kzg v1.5.0 kzg-mainnet
             ;; verify_kzg_proof_case_correct_proof_395cf6d697d1a743,
             ;; verify_kzg_proof_case_incorrect_proof_444b73ff54a19b44,
             ;; verify_blob_kzg_proof_case_correct_proof_a87a4e636e0f58fb,
             ;; verify_blob_kzg_proof_case_incorrect_proof_a87a4e636e0f58fb.
             (configure-kzg-proof-command-verifiers (namestring script))
             (is (verify-kzg-point-proof
                  valid-commitment
                  valid-point-z
                  valid-point-y
                  valid-proof))
             (signals error
               (verify-kzg-point-proof
                invalid-point-commitment
                invalid-point-z
                invalid-point-y
                invalid-point-proof))
             (is (verify-kzg-blob-proof
                  valid-blob
                  valid-commitment
                  valid-proof))
             (signals error
               (verify-kzg-blob-proof
                valid-blob
                valid-commitment
                invalid-blob-proof)))
        (setf *kzg-point-proof-verifier* old-point-verifier
              *kzg-blob-proof-verifier* old-blob-verifier)))))

(deftest blob-sidecar-field-validation-replays-real-kzg-vector
  (let ((script (repo-kzg-verifier-command)))
    (let* ((blob
             (let ((blob (make-byte-vector +blob-byte-size+))
                   (field-element
                     (ethereum-lisp.crypto::integer-to-fixed-bytes 2 32)))
               (loop for start below +blob-byte-size+ by 32
                     do (replace blob field-element :start1 start))
               blob))
           (commitment
             (hex-to-bytes
              "0xa572cbea904d67468808c8eb50a9450c9721db309128012543902d0ac358a62ae28f75bb8f1c7c42c39a8c5529bf0f4e"))
           (valid-proof
             (hex-to-bytes
              "0xc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"))
           (invalid-proof
             (hex-to-bytes
              "0x97f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb"))
           (versioned-hash
             (kzg-commitment-to-versioned-hash commitment))
           (transaction
             (make-blob-transaction
              :to (address-from-hex
                   "0x0000000000000000000000000000000000000001")
              :blob-versioned-hashes (list versioned-hash)))
           (old-point-verifier *kzg-point-proof-verifier*)
           (old-blob-verifier *kzg-blob-proof-verifier*))
      (unwind-protect
           (progn
             (configure-kzg-proof-command-verifiers (namestring script))
             (is (validate-blob-sidecar-fields
                  (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs (list valid-proof))
                  :transaction transaction
                  :require-proof-verification t))
             (signals block-validation-error
               (validate-blob-sidecar-fields
                (make-blob-sidecar
                 :blobs (list blob)
                 :commitments (list commitment)
                 :proofs (list invalid-proof))
                :transaction transaction
                :require-proof-verification t)))
        (setf *kzg-point-proof-verifier* old-point-verifier
              *kzg-blob-proof-verifier* old-blob-verifier)))))

(deftest blob-transaction-fee-cap-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :to address
                       :max-fee-per-blob-gas 1
                       :blob-versioned-hashes (list blob-hash)))
         (overwide-transaction (make-blob-transaction
                                :to address
                                :max-fee-per-blob-gas (1+ +uint256-max+)
                                :blob-versioned-hashes (list blob-hash)))
         (block (make-block :transactions (list transaction)))
         (header (block-header block)))
    (setf (block-header-blob-gas-used header) +blob-gas-per-blob+
          (block-header-excess-blob-gas header) 2314058)
    (is (= 2 (block-header-blob-base-fee header)))
    (signals block-validation-error
      (validate-blob-transaction-fee-cap overwide-transaction 2))
    (signals block-validation-error
      (validate-block-body-roots block))
    (setf (blob-transaction-max-fee-per-blob-gas transaction) 2)
    (setf (block-header-transactions-root header)
          (transaction-list-root (block-transactions block)))
    (is (validate-block-body-roots block)))
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash (hash32-from-hex
                     "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :to address
                       :max-fee-per-blob-gas 1
                       :blob-versioned-hashes (list blob-hash)))
         (config (make-chain-config :london-block 0
                                    :cancun-time 0
                                    :osaka-time 10))
         (block (make-block :transactions (list transaction)))
         (header (block-header block)))
    (setf (block-header-number header) 1
          (block-header-timestamp header) 10
          (block-header-blob-gas-used header) +blob-gas-per-blob+
          (block-header-excess-blob-gas header) 2314058)
    (is (= 1 (block-header-blob-base-fee
              header
              :update-fraction +osaka-blob-base-fee-update-fraction+)))
    (signals block-validation-error
      (validate-block-body-roots block))
    (is (validate-block-body-against-config block config))))

(deftest block-withdrawals-presence-is-distinct-from-empty-list
  (let* ((empty-shanghai-block (make-block :withdrawals '()))
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data empty-shanghai-block)))
         (payload-object (engine-rpc-executable-data-object payload))
         (decoded-payload
           (engine-rpc-executable-data-from-object payload-object))
         (decoded-block (executable-data-to-block-no-hash decoded-payload))
         (header-with-missing-body
           (make-block-header :withdrawals-root (withdrawal-list-root '())))
         (missing-body-block (make-block :header header-with-missing-body))
         (pre-shanghai-block (make-block :withdrawals '())))
    (is (block-withdrawals-present-p empty-shanghai-block))
    (is (executable-data-withdrawals-present-p payload))
    (is (assoc "withdrawals" payload-object :test #'string=))
    (is (null (cdr (assoc "withdrawals" payload-object :test #'string=))))
    (is (executable-data-withdrawals-present-p decoded-payload))
    (is (block-withdrawals-present-p decoded-block))
    (is (null (block-withdrawals decoded-block)))
    (is (validate-block-body-roots empty-shanghai-block))
    (signals block-validation-error
      (validate-block-body-roots missing-body-block))
    (setf (block-header-withdrawals-root (block-header pre-shanghai-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-shanghai-block))))

(deftest block-body-validates-withdrawal-fields
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000001"))
         (withdrawal (make-withdrawal :index 0
                                      :validator-index 42
                                      :address recipient
                                      :amount 1))
         (block (make-block :withdrawals (list withdrawal))))
    (setf (withdrawal-amount withdrawal) (1+ +uint256-max+))
    (signals block-validation-error
      (validate-withdrawal-fields withdrawal))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-withdrawal-list-before-root-derivation
  (let ((block (make-block)))
    (setf (block-withdrawals block) "not a withdrawal list"
          (block-withdrawals-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest post-merge-block-body-rejects-ommers
  (let* ((ommer (make-block-header :beneficiary
                                   (address-from-hex
                                    "0x00000000000000000000000000000000000000dd")
                                   :difficulty 1
                                   :number 7))
         (block (make-block :header (make-block-header :difficulty 0
                                                       :number 8)
                            :ommers (list ommer))))
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-execution-root-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (log (make-log-entry :address address :topics (list topic) :data #(7)))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000
                                :logs (list log)))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (is (= 21000 (receipts-gas-used (list receipt))))
    (is (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-gas-used header) 21001)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-gas-used header) 21000
          (block-header-receipts-root header) (zero-hash32))
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))))

(deftest block-execution-validates-commitment-fields-before-comparison
  (let* ((receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (setf (block-header-logs-bloom header) "not a bloom")
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-logs-bloom header) (make-byte-vector 256)
          (block-header-receipts-root header) nil)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-receipts-root header) (receipt-list-root (list receipt))
          (block-header-state-root header) nil)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) nil))))

(deftest block-execution-validates-receipts-before-derived-fields
  (let* ((state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (good-receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (block (make-block :receipts (list good-receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block "not a receipt list" state-root))
    (signals block-validation-error
      (validate-block-execution-roots block (list "not a receipt") state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt :status 1
                           :cumulative-gas-used (ash 1 64)))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt :post-state "not bytes"
                           :cumulative-gas-used 21000))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry :address nil))))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :topics (list nil)))))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry :data "not bytes"))))
       state-root))))

(deftest block-execution-rejects-pre-byzantium-receipts-by-config
  (let* ((post-state (make-byte-vector 32 :initial-element #x11))
         (receipt (make-receipt :post-state post-state
                                :cumulative-gas-used 21000))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block))
         (pre-byzantium-config (make-chain-config :byzantium-block 100))
         (byzantium-config (make-chain-config :byzantium-block 0)))
    (setf (block-header-number header) 42
          (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root
                                      :chain-config pre-byzantium-config))
    (is (validate-block-execution-roots block (list receipt) state-root
                                        :chain-config byzantium-config))))

(deftest block-execution-validates-receipt-cumulative-gas-order
  (let* ((first-receipt (make-receipt :status 1
                                      :cumulative-gas-used 30000))
         (second-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (receipts (list first-receipt second-receipt))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts receipts))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block receipts state-root)))
  (let* ((first-receipt (make-receipt :status 1
                                      :cumulative-gas-used 21000))
         (second-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (receipts (list first-receipt second-receipt))
         (state-root (hash32-from-hex
                      "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (block (make-block :receipts receipts))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block receipts state-root))))

(deftest bloom-add-and-lookup-log-values
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (log (make-log-entry :address address :topics (list topic)))
         (bloom (receipt-bloom (list log))))
    (is (bloom-contains-p bloom (address-bytes address)))
    (is (bloom-contains-p bloom (hash32-bytes topic)))))

(deftest receipt-rlp-and-root
  (let* ((receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (root (receipt-list-root (list receipt))))
    (is (= 267 (length (receipt-rlp receipt))))
    (is (string= "0xf9010801825208"
                 (subseq (bytes-to-hex (receipt-rlp receipt)) 0 16)))
    (is (hash32-p root))))

(deftest typed-receipt-encoding-and-root
  (let* ((legacy (make-legacy-transaction :gas-price 1))
         (dynamic (make-dynamic-fee-transaction
                   :max-priority-fee-per-gas 1
                   :max-fee-per-gas 2))
         (legacy-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (dynamic-receipt (make-receipt :status 1
                                        :cumulative-gas-used 42000))
         (typed-encoding
           (transaction-receipt-encoding dynamic dynamic-receipt))
         (root
           (transaction-receipt-list-root
            (list legacy dynamic)
            (list legacy-receipt dynamic-receipt))))
    (is (= 2 (transaction-type dynamic)))
    (is (= 2 (aref typed-encoding 0)))
    (is (bytes= (receipt-rlp dynamic-receipt)
                (subseq typed-encoding 1)))
    (is (string= (hash32-to-hex (receipt-list-root
                                 (list legacy-receipt)))
                 (hash32-to-hex
                  (transaction-receipt-list-root
                   (list legacy)
                   (list legacy-receipt)))))
    (is (not (string= (hash32-to-hex
                       (receipt-list-root
                        (list legacy-receipt dynamic-receipt)))
                      (hash32-to-hex root))))
    (signals block-validation-error
      (transaction-receipt-list-root (list legacy) '()))))

(deftest transaction-list-root-empty-and-single
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (hash32-to-hex (transaction-list-root '()))))
  (let ((root (transaction-list-root
               (list (make-legacy-transaction :nonce 1
                                              :gas-price 2
                                              :gas-limit 3
                                              :value 4
                                              :data #(96 0)
                                              :v 27
                                              :r 5
                                              :s 6)))))
    (is (hash32-p root))))

(deftest typed-transaction-encodings
  (let* ((recipient (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (access (list (make-access-list-entry :address recipient
                                               :storage-keys (list slot))))
         (tx1 (make-access-list-transaction :chain-id 1
                                            :nonce 2
                                            :gas-price 3
                                            :gas-limit 4
                                            :to recipient
                                            :value 5
                                            :data #(6)
                                            :access-list access
                                            :y-parity 1
                                            :r 7
                                            :s 8))
         (tx2 (make-dynamic-fee-transaction :chain-id 1
                                            :nonce 2
                                            :max-priority-fee-per-gas 3
                                            :max-fee-per-gas 4
                                            :gas-limit 5
                                            :to recipient
                                            :value 6
                                            :data #(7)
                                            :access-list access
                                            :y-parity 1
                                            :r 8
                                            :s 9))
         (blob-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (tx3 (make-blob-transaction :chain-id 1
                                      :nonce 2
                                      :max-priority-fee-per-gas 3
                                      :max-fee-per-gas 4
                                      :gas-limit 5
                                      :to recipient
                                      :value 6
                                      :data #(7)
                                      :access-list access
                                      :max-fee-per-blob-gas 10
                                      :blob-versioned-hashes (list blob-hash)
                                      :y-parity 1
                                      :r 8
                                      :s 9))
         (authorization
           (make-set-code-authorization :chain-id 1
                                        :address recipient
                                        :nonce 11
                                        :y-parity 1
                                        :r 12
                                        :s 13))
         (tx4 (make-set-code-transaction :chain-id 1
                                          :nonce 2
                                          :max-priority-fee-per-gas 3
                                          :max-fee-per-gas 4
                                          :gas-limit 5
                                          :to recipient
                                          :value 6
                                          :data #(7)
                                          :access-list access
                                          :authorization-list (list authorization)
                                          :y-parity 1
                                          :r 8
                                          :s 9))
         (blob-encoding (blob-transaction-encoding tx3))
         (blob-payload (rlp-decode-one (subseq blob-encoding 1)))
         (blob-items (rlp-list-items blob-payload))
         (blob-hash-items (rlp-list-items (nth 10 blob-items)))
         (set-code-encoding (set-code-transaction-encoding tx4))
         (set-code-payload (rlp-decode-one (subseq set-code-encoding 1)))
         (set-code-items (rlp-list-items set-code-payload))
         (authorization-items
           (rlp-list-items
            (first (rlp-list-items (nth 9 set-code-items))))))
    (is (= 1 (aref (access-list-transaction-encoding tx1) 0)))
    (is (= 2 (aref (dynamic-fee-transaction-encoding tx2) 0)))
    (is (= 3 (aref blob-encoding 0)))
    (is (= 4 (aref set-code-encoding 0)))
    (is (= 14 (length blob-items)))
    (is (= 10 (bytes-to-integer (nth 9 blob-items))))
    (is (= 1 (length blob-hash-items)))
    (is (bytes= (hash32-bytes blob-hash) (first blob-hash-items)))
    (is (= 13 (length set-code-items)))
    (is (= 6 (length authorization-items)))
    (is (= 11 (bytes-to-integer (third authorization-items))))
    (let ((decoded (transaction-from-encoding
                    (access-list-transaction-encoding tx1))))
      (is (typep decoded 'access-list-transaction))
      (is (= 1 (access-list-transaction-chain-id decoded)))
      (is (= 2 (access-list-transaction-nonce decoded)))
      (is (= 3 (access-list-transaction-gas-price decoded)))
      (is (= 4 (access-list-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (access-list-transaction-to decoded))))
      (is (= 5 (access-list-transaction-value decoded)))
      (is (bytes= #(6) (access-list-transaction-data decoded)))
      (is (= 1 (length (access-list-transaction-access-list decoded))))
      (is (bytes= (hash32-bytes slot)
                  (hash32-bytes
                   (first (access-list-entry-storage-keys
                           (first (access-list-transaction-access-list
                                   decoded)))))))
      (is (= 1 (access-list-transaction-y-parity decoded)))
      (is (= 7 (access-list-transaction-r decoded)))
      (is (= 8 (access-list-transaction-s decoded)))
      (is (bytes= (access-list-transaction-encoding tx1)
                  (access-list-transaction-encoding decoded))))
    (signals block-validation-error
      (access-list-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (access-list-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4
                       (make-byte-vector 20)
                       5
                       (make-byte-vector 1 :initial-element 6)
                       (make-rlp-list
                        (make-rlp-list
                         (make-byte-vector 19)
                         (make-rlp-list)))
                       1 7 8))))
    (let ((decoded (transaction-from-encoding
                    (dynamic-fee-transaction-encoding tx2))))
      (is (typep decoded 'dynamic-fee-transaction))
      (is (= 1 (dynamic-fee-transaction-chain-id decoded)))
      (is (= 2 (dynamic-fee-transaction-nonce decoded)))
      (is (= 3 (dynamic-fee-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (dynamic-fee-transaction-max-fee-per-gas decoded)))
      (is (= 5 (dynamic-fee-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (dynamic-fee-transaction-to decoded))))
      (is (= 6 (dynamic-fee-transaction-value decoded)))
      (is (bytes= #(7) (dynamic-fee-transaction-data decoded)))
      (is (= 1 (length (dynamic-fee-transaction-access-list decoded))))
      (is (bytes= (hash32-bytes slot)
                  (hash32-bytes
                   (first (access-list-entry-storage-keys
                           (first (dynamic-fee-transaction-access-list
                                   decoded)))))))
      (is (= 1 (dynamic-fee-transaction-y-parity decoded)))
      (is (= 8 (dynamic-fee-transaction-r decoded)))
      (is (= 9 (dynamic-fee-transaction-s decoded)))
      (is (bytes= (dynamic-fee-transaction-encoding tx2)
                  (dynamic-fee-transaction-encoding decoded))))
    (signals block-validation-error
      (dynamic-fee-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (dynamic-fee-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 20)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list
                        (make-rlp-list
                         (make-byte-vector 20)
                         (make-rlp-list (make-byte-vector 31))))
                       1 8 9))))
    (let ((decoded (transaction-from-encoding
                    (blob-transaction-encoding tx3))))
      (is (typep decoded 'blob-transaction))
      (is (= 1 (blob-transaction-chain-id decoded)))
      (is (= 2 (blob-transaction-nonce decoded)))
      (is (= 3 (blob-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (blob-transaction-max-fee-per-gas decoded)))
      (is (= 5 (blob-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (blob-transaction-to decoded))))
      (is (= 6 (blob-transaction-value decoded)))
      (is (bytes= #(7) (blob-transaction-data decoded)))
      (is (= 1 (length (blob-transaction-access-list decoded))))
      (is (= 10 (blob-transaction-max-fee-per-blob-gas decoded)))
      (is (= 1 (length (blob-transaction-blob-versioned-hashes decoded))))
      (is (bytes= (hash32-bytes blob-hash)
                  (hash32-bytes
                   (first (blob-transaction-blob-versioned-hashes decoded)))))
      (is (= 1 (blob-transaction-y-parity decoded)))
      (is (= 8 (blob-transaction-r decoded)))
      (is (= 9 (blob-transaction-s decoded)))
      (is (bytes= (blob-transaction-encoding tx3)
                  (blob-transaction-encoding decoded))))
    (signals block-validation-error
      (blob-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (blob-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 0)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       10
                       (make-rlp-list (hash32-bytes blob-hash))
                       1 8 9))))
    (signals block-validation-error
      (blob-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (address-bytes recipient)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       10
                       (make-rlp-list (make-byte-vector 31))
                       1 8 9))))
    (let ((decoded (transaction-from-encoding
                    (set-code-transaction-encoding tx4))))
      (is (typep decoded 'set-code-transaction))
      (is (= 1 (set-code-transaction-chain-id decoded)))
      (is (= 2 (set-code-transaction-nonce decoded)))
      (is (= 3 (set-code-transaction-max-priority-fee-per-gas decoded)))
      (is (= 4 (set-code-transaction-max-fee-per-gas decoded)))
      (is (= 5 (set-code-transaction-gas-limit decoded)))
      (is (string= (address-to-hex recipient)
                   (address-to-hex (set-code-transaction-to decoded))))
      (is (= 6 (set-code-transaction-value decoded)))
      (is (bytes= #(7) (set-code-transaction-data decoded)))
      (is (= 1 (length (set-code-transaction-access-list decoded))))
      (is (= 1 (length (set-code-transaction-authorization-list decoded))))
      (let ((decoded-authorization
              (first (set-code-transaction-authorization-list decoded))))
        (is (= 1 (set-code-authorization-chain-id decoded-authorization)))
        (is (string= (address-to-hex recipient)
                     (address-to-hex
                      (set-code-authorization-address
                       decoded-authorization))))
        (is (= 11 (set-code-authorization-nonce decoded-authorization)))
        (is (= 1 (set-code-authorization-y-parity decoded-authorization)))
        (is (= 12 (set-code-authorization-r decoded-authorization)))
        (is (= 13 (set-code-authorization-s decoded-authorization))))
      (is (= 1 (set-code-transaction-y-parity decoded)))
      (is (= 8 (set-code-transaction-r decoded)))
      (is (= 9 (set-code-transaction-s decoded)))
      (is (bytes= (set-code-transaction-encoding tx4)
                  (set-code-transaction-encoding decoded))))
    (signals block-validation-error
      (set-code-transaction-from-rlp (rlp-encode (list 1 2 3))))
    (signals block-validation-error
      (set-code-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (make-byte-vector 0)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       (make-rlp-list
                        (make-rlp-list 1
                                       (address-bytes recipient)
                                       11 1 12 13))
                       1 8 9))))
    (signals block-validation-error
      (set-code-transaction-from-rlp
       (rlp-encode
        (make-rlp-list 1 2 3 4 5
                       (address-bytes recipient)
                       6
                       (make-byte-vector 1 :initial-element 7)
                       (make-rlp-list)
                       (make-rlp-list
                        (make-rlp-list 1
                                       (make-byte-vector 0)
                                       11 1 12 13))
                       1 8 9))))
    (is (hash32-p (transaction-hash tx1)))
    (is (hash32-p (blob-transaction-signing-hash tx3)))
    (is (not (string= (hash32-to-hex (blob-transaction-signing-hash tx3))
                      (hash32-to-hex (blob-transaction-hash tx3)))))
    (is (hash32-p (set-code-authorization-signing-hash authorization)))
    (is (hash32-p (set-code-transaction-signing-hash tx4)))
    (is (not (string= (hash32-to-hex (set-code-transaction-signing-hash tx4))
                      (hash32-to-hex (set-code-transaction-hash tx4)))))
    (is (hash32-p (transaction-list-root (list tx1 tx2 tx3 tx4))))))
