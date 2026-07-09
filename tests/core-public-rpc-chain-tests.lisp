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

