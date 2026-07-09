(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-serve-mode-serves-engine-and-public-rpc
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-rpc" "jwt"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-rpc-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-rpc" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-rpc" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string +devnet-cli-jwt-secret+ stream))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        genesis
                        "--authrpc.addr"
                        "0.0.0.0"
                        "--engine-port"
                        "0"
                        "--http.addr"
                        "0.0.0.0"
                        "--public-port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "24"
                        "--override.terminaltotaldifficulty"
                        "12345"
                        "--override.terminaltotaldifficultypassed"
                        "true"
                        "--override.terminalblockhash"
                        "0x3333333333333333333333333333333333333333333333333333333333333333"
                        "--override.terminalblocknumber"
                        "66"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (wrong-token
                      (engine-rpc-make-jwt-token
                       (hex-to-bytes
                        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
                       0))
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":501,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"rpc-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (engine-batch-body
                      "[{\"jsonrpc\":\"2.0\",\"id\":513,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"rpc-batch-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]},{\"jsonrpc\":\"2.0\",\"id\":514,\"method\":\"engine_exchangeCapabilities\",\"params\":[[\"engine_newPayloadV1\",\"engine_forkchoiceUpdatedV1\",\"engine_getPayloadV1\",\"engine_newPayloadV2\",\"engine_forkchoiceUpdatedV2\",\"engine_getPayloadV2\",\"engine_getPayloadBodiesByHashV1\",\"engine_getPayloadBodiesByRangeV1\",\"engine_newPayloadV3\",\"engine_getBlobsV1\",\"engine_getPayloadBodiesByHashV2\"]]}]")
                    (engine-notification-body
                      "{\"jsonrpc\":\"2.0\",\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    (engine-transition-body
                      "{\"jsonrpc\":\"2.0\",\"id\":515,\"method\":\"engine_exchangeTransitionConfigurationV1\",\"params\":[{\"terminalTotalDifficulty\":\"0x3039\",\"terminalBlockHash\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"terminalBlockNumber\":\"0x42\"}]}")
                    (engine-transition-mismatch-body
                      "{\"jsonrpc\":\"2.0\",\"id\":530,\"method\":\"engine_exchangeTransitionConfigurationV1\",\"params\":[{\"terminalTotalDifficulty\":\"0x3038\",\"terminalBlockHash\":\"0x3333333333333333333333333333333333333333333333333333333333333333\",\"terminalBlockNumber\":\"0x42\"}]}")
                    (engine-public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":507,\"method\":\"eth_chainId\",\"params\":[]}")
                    (engine-capabilities-body
                      "{\"jsonrpc\":\"2.0\",\"id\":508,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    (engine-wrong-path-body
                      "{\"jsonrpc\":\"2.0\",\"id\":531,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"wrong-path\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":502,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-client-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":503,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-net-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":504,\"method\":\"net_version\",\"params\":[]}")
                    (public-net-listening-body
                      "{\"jsonrpc\":\"2.0\",\"id\":505,\"method\":\"net_listening\",\"params\":[]}")
                    (public-syncing-body
                      "{\"jsonrpc\":\"2.0\",\"id\":506,\"method\":\"eth_syncing\",\"params\":[]}")
                    (public-net-peer-count-body
                      "{\"jsonrpc\":\"2.0\",\"id\":516,\"method\":\"net_peerCount\",\"params\":[]}")
                    (public-accounts-body
                      "{\"jsonrpc\":\"2.0\",\"id\":517,\"method\":\"eth_accounts\",\"params\":[]}")
                    (public-coinbase-body
                      "{\"jsonrpc\":\"2.0\",\"id\":518,\"method\":\"eth_coinbase\",\"params\":[]}")
                    (public-mining-body
                      "{\"jsonrpc\":\"2.0\",\"id\":519,\"method\":\"eth_mining\",\"params\":[]}")
                    (public-hashrate-body
                      "{\"jsonrpc\":\"2.0\",\"id\":520,\"method\":\"eth_hashrate\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":521,\"method\":\"rpc_modules\",\"params\":[]}")
                    (public-protocol-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":522,\"method\":\"eth_protocolVersion\",\"params\":[]}")
                    (public-web3-sha3-body
                      "{\"jsonrpc\":\"2.0\",\"id\":523,\"method\":\"web3_sha3\",\"params\":[\"0x68656c6c6f\"]}")
                    (public-gas-price-body
                      "{\"jsonrpc\":\"2.0\",\"id\":524,\"method\":\"eth_gasPrice\",\"params\":[]}")
                    (public-priority-fee-body
                      "{\"jsonrpc\":\"2.0\",\"id\":525,\"method\":\"eth_maxPriorityFeePerGas\",\"params\":[]}")
                    (public-base-fee-body
                      "{\"jsonrpc\":\"2.0\",\"id\":526,\"method\":\"eth_baseFee\",\"params\":[]}")
                    (public-blob-base-fee-body
                      "{\"jsonrpc\":\"2.0\",\"id\":527,\"method\":\"eth_blobBaseFee\",\"params\":[]}")
                    (public-fee-history-body
                      "{\"jsonrpc\":\"2.0\",\"id\":528,\"method\":\"eth_feeHistory\",\"params\":[\"0x1\",\"latest\",[]]}")
                    (public-batch-body
                      "[{\"jsonrpc\":\"2.0\",\"id\":510,\"method\":\"eth_chainId\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"id\":511,\"method\":\"net_version\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"id\":512,\"method\":\"web3_clientVersion\",\"params\":[]}]")
                    (public-notification-body
                      "{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-mixed-batch-body
                      "[{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"id\":529,\"method\":\"net_version\",\"params\":[]}]")
                    (public-notifications-batch-body
                      "[{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"method\":\"net_version\",\"params\":[]}]")
                    (public-wrong-path-body
                      "{\"jsonrpc\":\"2.0\",\"id\":532,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":509,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    engine-response
                    engine-batch-response
                    engine-notification-response
                    engine-transition-response
                    engine-transition-mismatch-response
                    engine-public-response
                    unauthenticated-engine-response
                    invalid-auth-engine-response
                    duplicate-auth-engine-response
                    engine-wrong-path-response
                    public-response
                    public-client-version-response
                    public-net-version-response
                    public-net-listening-response
                    public-syncing-response
                    public-net-peer-count-response
                    public-accounts-response
                    public-coinbase-response
                    public-mining-response
                    public-hashrate-response
                    public-rpc-modules-response
                    public-protocol-version-response
                    public-web3-sha3-response
                    public-gas-price-response
                    public-priority-fee-response
                    public-base-fee-response
                    public-blob-base-fee-response
                    public-fee-history-response
                    public-batch-response
                    public-notification-response
                    public-mixed-batch-response
                    public-notifications-batch-response
                    public-wrong-path-response
                    public-engine-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (search "127.0.0.1:" engine-endpoint))
               (is (not (search "0.0.0.0" engine-endpoint)))
               (is (search "127.0.0.1:" rpc-endpoint))
               (is (not (search "0.0.0.0" rpc-endpoint)))
               (handler-case
                   (progn
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token)))
                     (setf engine-batch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-batch-body
                             :token token)))
                     (setf engine-notification-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-notification-body
                             :token token)))
                     (setf engine-transition-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-transition-body
                             :token token)))
                     (setf engine-transition-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-transition-mismatch-body
                             :token token)))
                     (setf engine-public-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-public-body
                             :token token)))
                     (setf unauthenticated-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-capabilities-body)))
                     (setf invalid-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-capabilities-body
                             :token wrong-token)))
                     (setf duplicate-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-duplicate-auth-http-request
                             engine-capabilities-body
                             token
                             wrong-token)))
                     (setf engine-wrong-path-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-wrong-path-body
                             :target "/unexpected"
                             :token token)))
                     (setf public-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request public-body)))
                     (setf public-client-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-client-version-body)))
                     (setf public-net-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-version-body)))
                     (setf public-net-listening-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-listening-body)))
                     (setf public-syncing-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-syncing-body)))
                     (setf public-net-peer-count-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-peer-count-body)))
                     (setf public-accounts-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-accounts-body)))
                     (setf public-coinbase-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-coinbase-body)))
                     (setf public-mining-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-mining-body)))
                     (setf public-hashrate-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-hashrate-body)))
                     (setf public-rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-rpc-modules-body)))
                     (setf public-protocol-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-protocol-version-body)))
                     (setf public-web3-sha3-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-web3-sha3-body)))
                     (setf public-gas-price-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-gas-price-body)))
                     (setf public-priority-fee-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-priority-fee-body)))
                     (setf public-base-fee-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-base-fee-body)))
                     (setf public-blob-base-fee-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-blob-base-fee-body)))
                     (setf public-fee-history-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-fee-history-body)))
                     (setf public-batch-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-batch-body)))
                     (setf public-notification-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-notification-body)))
                     (setf public-mixed-batch-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-mixed-batch-body)))
                     (setf public-notifications-batch-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-notifications-batch-body)))
                     (setf public-wrong-path-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-wrong-path-body
                             :target "/unexpected")))
                     (setf public-engine-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-engine-body))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status engine-batch-response)))
               (is (= 200 (devnet-cli-http-status
                            engine-notification-response)))
               (is (= 200 (devnet-cli-http-status engine-transition-response)))
               (is (= 200 (devnet-cli-http-status
                            engine-transition-mismatch-response)))
               (is (= 200 (devnet-cli-http-status engine-public-response)))
               (is (= 401
                      (devnet-cli-http-status unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (is (= 401
                      (devnet-cli-http-status duplicate-auth-engine-response)))
               (is (= 404 (devnet-cli-http-status engine-wrong-path-response)))
               (is (search "not found"
                           (devnet-cli-http-body
                            engine-wrong-path-response)))
               (is (= 200 (devnet-cli-http-status public-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-client-version-response)))
               (is (= 200 (devnet-cli-http-status public-net-version-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-net-listening-response)))
               (is (= 200 (devnet-cli-http-status public-syncing-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-net-peer-count-response)))
               (is (= 200 (devnet-cli-http-status public-accounts-response)))
               (is (= 200 (devnet-cli-http-status public-coinbase-response)))
               (is (= 200 (devnet-cli-http-status public-mining-response)))
               (is (= 200 (devnet-cli-http-status public-hashrate-response)))
               (is (= 200
                      (devnet-cli-http-status public-rpc-modules-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-protocol-version-response)))
               (is (= 200
                      (devnet-cli-http-status public-web3-sha3-response)))
               (is (= 200
                      (devnet-cli-http-status public-gas-price-response)))
               (is (= 200
                      (devnet-cli-http-status public-priority-fee-response)))
               (is (= 200
                      (devnet-cli-http-status public-base-fee-response)))
               (is (= 200
                      (devnet-cli-http-status public-blob-base-fee-response)))
               (is (= 200
                      (devnet-cli-http-status public-fee-history-response)))
               (is (= 200 (devnet-cli-http-status public-batch-response)))
               (is (= 200
                      (devnet-cli-http-status public-notification-response)))
               (is (= 200
                      (devnet-cli-http-status public-mixed-batch-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-notifications-batch-response)))
               (is (= 404 (devnet-cli-http-status public-wrong-path-response)))
               (is (search "not found"
                           (devnet-cli-http-body
                            public-wrong-path-response)))
               (is (= 200 (devnet-cli-http-status public-engine-response)))
               (let* ((engine-json
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-public-json
                        (parse-json
                         (devnet-cli-http-body engine-public-response)))
                      (engine-batch-json
                        (parse-json
                         (devnet-cli-http-body engine-batch-response)))
                      (engine-batch-client-version-json
                        (first engine-batch-json))
                      (engine-batch-capabilities-json
                        (second engine-batch-json))
                      (engine-transition-json
                        (parse-json
                         (devnet-cli-http-body engine-transition-response)))
                      (engine-transition-result
                        (fixture-object-field engine-transition-json
                                              "result"))
                      (engine-transition-mismatch-json
                        (parse-json
                         (devnet-cli-http-body
                          engine-transition-mismatch-response)))
                      (engine-transition-mismatch-error
                        (fixture-object-field engine-transition-mismatch-json
                                              "error"))
                      (public-json
                        (parse-json (devnet-cli-http-body public-response)))
                      (public-client-version-json
                        (parse-json
                         (devnet-cli-http-body
                          public-client-version-response)))
                      (public-net-version-json
                        (parse-json
                         (devnet-cli-http-body public-net-version-response)))
                      (public-net-listening-json
                        (parse-json
                         (devnet-cli-http-body
                          public-net-listening-response)))
                      (public-syncing-json
                        (parse-json
                         (devnet-cli-http-body public-syncing-response)))
                      (public-net-peer-count-json
                        (parse-json
                         (devnet-cli-http-body
                          public-net-peer-count-response)))
                      (public-accounts-json
                        (parse-json
                         (devnet-cli-http-body public-accounts-response)))
                      (public-coinbase-json
                        (parse-json
                         (devnet-cli-http-body public-coinbase-response)))
                      (public-mining-json
                        (parse-json
                         (devnet-cli-http-body public-mining-response)))
                      (public-hashrate-json
                        (parse-json
                         (devnet-cli-http-body public-hashrate-response)))
                      (public-rpc-modules-json
                        (parse-json
                         (devnet-cli-http-body public-rpc-modules-response)))
                      (public-rpc-modules
                        (fixture-object-field public-rpc-modules-json
                                              "result"))
                      (public-protocol-version-json
                        (parse-json
                         (devnet-cli-http-body
                          public-protocol-version-response)))
                      (public-web3-sha3-json
                        (parse-json
                         (devnet-cli-http-body public-web3-sha3-response)))
                      (public-gas-price-json
                        (parse-json
                         (devnet-cli-http-body public-gas-price-response)))
                      (public-priority-fee-json
                        (parse-json
                         (devnet-cli-http-body public-priority-fee-response)))
                      (public-base-fee-json
                        (parse-json
                         (devnet-cli-http-body public-base-fee-response)))
                      (public-blob-base-fee-json
                        (parse-json
                         (devnet-cli-http-body
                          public-blob-base-fee-response)))
                      (public-fee-history-json
                        (parse-json
                         (devnet-cli-http-body public-fee-history-response)))
                      (public-fee-history
                        (fixture-object-field public-fee-history-json
                                              "result"))
                      (public-batch-json
                        (parse-json
                         (devnet-cli-http-body public-batch-response)))
                      (public-batch-chain-id-json
                        (first public-batch-json))
                      (public-batch-net-version-json
                        (second public-batch-json))
                      (public-batch-client-version-json
                        (third public-batch-json))
                      (public-mixed-batch-json
                        (parse-json
                         (devnet-cli-http-body
                          public-mixed-batch-response)))
                      (public-mixed-batch-net-version-json
                        (first public-mixed-batch-json))
                      (public-engine-json
                        (parse-json
                         (devnet-cli-http-body public-engine-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result"))))
                 (is (= 501 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 2 (length engine-batch-json)))
                 (is (= 513
                        (fixture-object-field
                         engine-batch-client-version-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field
                               (first
                                (fixture-object-field
                                 engine-batch-client-version-json "result"))
                               "name")))
                 (is (= 514
                        (fixture-object-field
                         engine-batch-capabilities-json "id")))
                 (devnet-cli-assert-engine-capability-list
                  (fixture-object-field
                   engine-batch-capabilities-json "result"))
                 (is (string= ""
                              (devnet-cli-http-body
                               engine-notification-response)))
                 (is (= 515 (fixture-object-field engine-transition-json "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               engine-transition-result
                               "terminalTotalDifficulty")))
                 (is (string= "0x3333333333333333333333333333333333333333333333333333333333333333"
                              (fixture-object-field
                               engine-transition-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               engine-transition-result
                               "terminalBlockNumber")))
                 (is (= 530
                        (fixture-object-field
                         engine-transition-mismatch-json "id")))
                 (is (= -32602
                        (fixture-object-field
                         engine-transition-mismatch-error "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              engine-transition-mismatch-error "message")))
                 (is (= 507 (fixture-object-field engine-public-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field engine-public-json "error")
                         "code")))
                 (is (= 502 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result")))
                 (is (= 503
                        (fixture-object-field public-client-version-json "id")))
                 (is (search "ethereum-lisp"
                             (fixture-object-field
                              public-client-version-json "result")))
                 (is (= 504 (fixture-object-field public-net-version-json "id")))
                 (is (string= "1337"
                              (fixture-object-field
                               public-net-version-json "result")))
                 (is (= 505
                        (fixture-object-field public-net-listening-json "id")))
                 (is (null (fixture-object-field
                            public-net-listening-json "result")))
                 (is (= 506 (fixture-object-field public-syncing-json "id")))
                 (is (null (fixture-object-field
                            public-syncing-json "result")))
                 (is (= 516
                        (fixture-object-field
                         public-net-peer-count-json "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               public-net-peer-count-json "result")))
                 (is (= 517 (fixture-object-field public-accounts-json "id")))
                 (is (null (fixture-object-field
                            public-accounts-json "result")))
                 (is (= 518 (fixture-object-field public-coinbase-json "id")))
                 (is (string= (address-to-hex (zero-address))
                              (fixture-object-field
                               public-coinbase-json "result")))
                 (is (= 519 (fixture-object-field public-mining-json "id")))
                 (is (null (fixture-object-field public-mining-json "result")))
                 (is (= 520 (fixture-object-field public-hashrate-json "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               public-hashrate-json "result")))
                 (is (= 521
                        (fixture-object-field public-rpc-modules-json "id")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules "eth")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules "net")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules "rpc")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules
                                                    "txpool")))
                 (is (string= "1.0"
                              (fixture-object-field public-rpc-modules
                                                    "web3")))
                 (is (= 522
                        (fixture-object-field
                         public-protocol-version-json "id")))
                 (is (string= (quantity-to-hex
                               ethereum-lisp.core::+eth-protocol-version+)
                              (fixture-object-field
                               public-protocol-version-json "result")))
                 (is (= 523
                        (fixture-object-field public-web3-sha3-json "id")))
                 (is (string= "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
                              (fixture-object-field
                               public-web3-sha3-json "result")))
                 (is (= 524
                        (fixture-object-field public-gas-price-json "id")))
                 (is (string= "0x3b9aca00"
                              (fixture-object-field
                               public-gas-price-json "result")))
                 (is (= 525
                        (fixture-object-field public-priority-fee-json "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               public-priority-fee-json "result")))
                 (is (= 526
                        (fixture-object-field public-base-fee-json "id")))
                 (is (string= "0x342770c0"
                              (fixture-object-field
                               public-base-fee-json "result")))
                 (is (= 527
                        (fixture-object-field public-blob-base-fee-json "id")))
                 (is (null (fixture-object-field
                            public-blob-base-fee-json "result")))
                 (is (= 528
                        (fixture-object-field public-fee-history-json "id")))
                 (is (string= "0x0"
                              (fixture-object-field public-fee-history
                                                    "oldestBlock")))
                 (let ((base-fees
                         (fixture-object-field public-fee-history
                                               "baseFeePerGas"))
                       (gas-ratios
                         (fixture-object-field public-fee-history
                                               "gasUsedRatio")))
                   (is (= 2 (length base-fees)))
                   (is (string= "0x3b9aca00" (first base-fees)))
                   (is (string= "0x342770c0" (second base-fees)))
                   (is (= 1 (length gas-ratios)))
                   (is (= 0 (first gas-ratios))))
                 (is (= 3 (length public-batch-json)))
                 (is (= 510
                        (fixture-object-field
                         public-batch-chain-id-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field
                               public-batch-chain-id-json "result")))
                 (is (= 511
                        (fixture-object-field
                         public-batch-net-version-json "id")))
                 (is (string= "1337"
                              (fixture-object-field
                               public-batch-net-version-json "result")))
                 (is (= 512
                        (fixture-object-field
                         public-batch-client-version-json "id")))
                 (is (search "ethereum-lisp"
                             (fixture-object-field
                              public-batch-client-version-json "result")))
                 (is (string= ""
                              (devnet-cli-http-body
                               public-notification-response)))
                 (is (= 1 (length public-mixed-batch-json)))
                 (is (= 529
                        (fixture-object-field
                         public-mixed-batch-net-version-json "id")))
                 (is (string= "1337"
                              (fixture-object-field
                               public-mixed-batch-net-version-json "result")))
                 (is (string= ""
                              (devnet-cli-http-body
                               public-notifications-batch-response)))
                 (is (= 509 (fixture-object-field public-engine-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field public-engine-json "error")
                         "code"))))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name)))))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (string= engine-endpoint
                                    (fixture-object-field stdout-summary
                                                          "engineEndpoint")))
                       (is (string= rpc-endpoint
                                    (fixture-object-field stdout-summary
                                                          "rpcEndpoint")))
                       (dolist (record (list ready-record shutdown-record))
                         (is record)
                         (let ((fields (getf record :fields)))
                           (is (string= engine-endpoint
                                        (cdr (assoc "engineEndpoint" fields
                                                    :test #'string=))))
                           (is (string= rpc-endpoint
                                        (cdr (assoc "rpcEndpoint" fields
                                                    :test #'string=))))))
                       (let ((shutdown-fields
                               (getf shutdown-record :fields)))
                         (is (string= "10"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "24"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "34"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

