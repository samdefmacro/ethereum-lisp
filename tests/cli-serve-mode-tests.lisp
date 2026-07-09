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

(deftest ethereum-lisp-script-serve-mode-admits-public-txpool-transactions
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool-genesis" "json"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool" "pid"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-one-transfer-with-withdrawal")))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-with-txpool-account
              case)))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :public-port 0))
                  (config (ethereum-lisp.cli:devnet-node-config node))
                  (script-genesis
                    (ethereum-lisp.cli::devnet-node-genesis-block node))
                  (latest-block-hash-hex
                    (hash32-to-hex (block-hash script-genesis)))
                  (expected-pending-block-number
                    (quantity-to-hex
                     (1+ (block-header-number
                          (block-header script-genesis)))))
                  (sender (devnet-cli-txpool-sender-address))
                  (sender-hex (address-to-hex sender))
                  (pending-transaction
                    (devnet-cli-txpool-transaction
                     config 0 +devnet-cli-txpool-gas-price+))
                  (basefee-transaction
                    (devnet-cli-txpool-transaction
                     config 1 +devnet-cli-txpool-basefee-gas-price+))
                  (queued-transaction
                    (devnet-cli-txpool-transaction
                     config 2 +devnet-cli-txpool-gas-price+))
                  (pending-hash
                    (hash32-to-hex (transaction-hash pending-transaction)))
                  (basefee-hash
                    (hash32-to-hex (transaction-hash basefee-transaction)))
                  (queued-hash
                    (hash32-to-hex (transaction-hash queued-transaction)))
                  (pending-raw
                    (devnet-cli-transaction-raw pending-transaction))
                  (basefee-raw
                    (devnet-cli-transaction-raw basefee-transaction))
                  (queued-raw
                    (devnet-cli-transaction-raw queued-transaction))
                  (pending-nonce
                    (devnet-cli-transaction-nonce-key pending-transaction))
                  (expected-pending-sender-nonce
                    (quantity-to-hex
                     (1+ (transaction-nonce pending-transaction))))
                  (basefee-nonce
                    (devnet-cli-transaction-nonce-key basefee-transaction))
                  (queued-nonce
                    (devnet-cli-transaction-nonce-key queued-transaction))
                  (pending-summary
                    (devnet-cli-transaction-summary pending-transaction))
                  (basefee-summary
                    (devnet-cli-transaction-summary basefee-transaction))
                  (queued-summary
                    (devnet-cli-transaction-summary queued-transaction))
                  (send-pending-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 701)
                           (cons "method" "eth_sendRawTransaction")
                           (cons "params" (list pending-raw)))))
                  (send-basefee-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 702)
                           (cons "method" "eth_sendRawTransaction")
                           (cons "params" (list basefee-raw)))))
                  (send-queued-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 703)
                           (cons "method" "eth_sendRawTransaction")
                           (cons "params" (list queued-raw)))))
                  (raw-pending-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 704)
                           (cons "method" "eth_getRawTransactionByHash")
                           (cons "params" (list pending-hash)))))
                  (raw-basefee-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 705)
                           (cons "method" "eth_getRawTransactionByHash")
                           (cons "params" (list basefee-hash)))))
                  (raw-queued-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 706)
                           (cons "method" "eth_getRawTransactionByHash")
                           (cons "params" (list queued-hash)))))
                  (pending-transactions-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 707)
                           (cons "method" "eth_pendingTransactions")
                           (cons "params" '()))))
                  (new-pending-filter-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 717)
                           (cons "method" "eth_newPendingTransactionFilter")
                           (cons "params" '()))))
                  (pending-block-count-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 711)
                           (cons "method"
                                 "eth_getBlockTransactionCountByNumber")
                           (cons "params" (list "pending")))))
                  (pending-transaction-by-index-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 712)
                           (cons "method"
                                 "eth_getTransactionByBlockNumberAndIndex")
                           (cons "params" (list "pending" "0x0")))))
                  (pending-raw-transaction-by-index-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 713)
                           (cons "method"
                                 "eth_getRawTransactionByBlockNumberAndIndex")
                           (cons "params" (list "pending" "0x0")))))
                  (pending-block-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 714)
                           (cons "method" "eth_getBlockByNumber")
                           (cons "params" (list "pending" t)))))
                  (pending-header-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 715)
                           (cons "method" "eth_getHeaderByNumber")
                           (cons "params" (list "pending")))))
                  (pending-fee-history-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 722)
                           (cons "method" "eth_feeHistory")
                           (cons "params" (list "0x1" "latest" '())))))
                  (pending-sender-nonce-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 723)
                           (cons "method" "eth_getTransactionCount")
                           (cons "params" (list sender-hex "pending")))))
                  (pending-block-receipts-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 724)
                           (cons "method" "eth_getBlockReceipts")
                           (cons "params" (list "pending")))))
                  (pending-uncle-count-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 725)
                           (cons "method" "eth_getUncleCountByBlockNumber")
                           (cons "params" (list "pending")))))
                  (pending-logs-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 726)
                           (cons "method" "eth_getLogs")
                           (cons "params"
                                 (list
                                  (list
                                   (cons "fromBlock" "pending")
                                   (cons "toBlock" "pending")))))))
                  (txpool-status-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 708)
                           (cons "method" "txpool_status")
                           (cons "params" '()))))
                  (txpool-content-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 716)
                           (cons "method" "txpool_content")
                           (cons "params" '()))))
                  (txpool-content-from-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 709)
                           (cons "method" "txpool_contentFrom")
                           (cons "params" (list sender-hex)))))
                  (txpool-inspect-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 710)
                           (cons "method" "txpool_inspect")
                           (cons "params" '())))))
             (setf process
                   (uiop:launch-program
                    (list "sbcl"
                          "--script"
                          script
                          "--"
                          "devnet"
                          "--genesis"
                          (namestring genesis-path)
                          "--engine-port"
                          "0"
                          "--public-port"
                          "0"
                          "--ready-file"
                          (namestring ready-path)
                          "--log-file"
                          (namestring log-path)
                          "--pid-file"
                          (namestring pid-path)
                          "--max-connections"
                          "26"
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
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      send-pending-response
                      send-basefee-response
                      send-queued-response
                      raw-pending-response
                      raw-basefee-response
                      raw-queued-response
                      new-pending-filter-response
                      pending-filter-changes-response
                      empty-pending-filter-changes-response
                      uninstall-pending-filter-response
                      removed-pending-filter-changes-response
                      pending-transactions-response
                      pending-block-count-response
                      pending-transaction-by-index-response
                      pending-raw-transaction-by-index-response
                      pending-block-response
                      pending-header-response
                      pending-fee-history-response
                      pending-sender-nonce-response
                      pending-block-receipts-response
                      pending-uncle-count-response
                      pending-logs-response
                      txpool-status-response
                      txpool-content-response
                      txpool-content-from-response
                      txpool-inspect-response)
                 (is (= pid (fixture-object-field ready-summary "processId")))
                 (handler-case
                     (progn
                       (setf new-pending-filter-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               new-pending-filter-body)))
                       (setf send-pending-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               send-pending-body)))
                       (setf send-basefee-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               send-basefee-body)))
                       (setf send-queued-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               send-queued-body)))
                       (setf raw-pending-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               raw-pending-body)))
                       (setf raw-basefee-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               raw-basefee-body)))
                       (setf raw-queued-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               raw-queued-body)))
                       (let* ((new-pending-filter-rpc
                                (parse-json
                                 (devnet-cli-http-body
                                  new-pending-filter-response)))
                              (pending-filter-id
                                (fixture-object-field
                                 new-pending-filter-rpc "result"))
                              (pending-filter-changes-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 718)
                                  (cons "method" "eth_getFilterChanges")
                                  (cons "params"
                                        (list pending-filter-id)))))
                              (empty-pending-filter-changes-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 719)
                                  (cons "method" "eth_getFilterChanges")
                                  (cons "params"
                                        (list pending-filter-id)))))
                              (uninstall-pending-filter-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 720)
                                  (cons "method" "eth_uninstallFilter")
                                  (cons "params"
                                        (list pending-filter-id)))))
                              (removed-pending-filter-changes-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 721)
                                  (cons "method" "eth_getFilterChanges")
                                  (cons "params"
                                        (list pending-filter-id))))))
                         (setf pending-filter-changes-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 pending-filter-changes-body)))
                         (setf empty-pending-filter-changes-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 empty-pending-filter-changes-body)))
                         (setf uninstall-pending-filter-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 uninstall-pending-filter-body)))
                         (setf removed-pending-filter-changes-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 removed-pending-filter-changes-body))))
                       (setf pending-transactions-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-transactions-body)))
                       (setf pending-block-count-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-block-count-body)))
                       (setf pending-transaction-by-index-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-transaction-by-index-body)))
                       (setf pending-raw-transaction-by-index-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-raw-transaction-by-index-body)))
                       (setf pending-block-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-block-body)))
                       (setf pending-header-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-header-body)))
                       (setf pending-fee-history-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-fee-history-body)))
                       (setf pending-sender-nonce-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-sender-nonce-body)))
                       (setf pending-block-receipts-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-block-receipts-body)))
                       (setf pending-uncle-count-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-uncle-count-body)))
                       (setf pending-logs-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-logs-body)))
                       (setf txpool-status-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-status-body)))
                       (setf txpool-content-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-content-body)))
                       (setf txpool-content-from-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-content-from-body)))
                       (setf txpool-inspect-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-inspect-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (dolist (response
                          (list send-pending-response
                                send-basefee-response
                                send-queued-response
                                raw-pending-response
                                raw-basefee-response
                                raw-queued-response
                                new-pending-filter-response
                                pending-filter-changes-response
                                empty-pending-filter-changes-response
                                uninstall-pending-filter-response
                                removed-pending-filter-changes-response
                                pending-transactions-response
                                pending-block-count-response
                                pending-transaction-by-index-response
                                pending-raw-transaction-by-index-response
                                pending-block-response
                                pending-header-response
                                pending-fee-history-response
                                pending-sender-nonce-response
                                pending-block-receipts-response
                                pending-uncle-count-response
                                pending-logs-response
                                txpool-status-response
                                txpool-content-response
                                txpool-content-from-response
                                txpool-inspect-response))
                   (is (= 200 (devnet-cli-http-status response))))
                 (let* ((send-pending-rpc
                          (parse-json
                           (devnet-cli-http-body send-pending-response)))
                        (send-basefee-rpc
                          (parse-json
                           (devnet-cli-http-body send-basefee-response)))
                        (send-queued-rpc
                          (parse-json
                           (devnet-cli-http-body send-queued-response)))
                        (raw-pending-rpc
                          (parse-json
                           (devnet-cli-http-body raw-pending-response)))
                        (raw-basefee-rpc
                          (parse-json
                           (devnet-cli-http-body raw-basefee-response)))
                        (raw-queued-rpc
                          (parse-json
                           (devnet-cli-http-body raw-queued-response)))
                        (new-pending-filter-rpc
                          (parse-json
                           (devnet-cli-http-body
                            new-pending-filter-response)))
                        (pending-filter-changes-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-filter-changes-response)))
                        (empty-pending-filter-changes-rpc
                          (parse-json
                           (devnet-cli-http-body
                            empty-pending-filter-changes-response)
                           :preserve-empty-arrays t))
                        (uninstall-pending-filter-rpc
                          (parse-json
                           (devnet-cli-http-body
                            uninstall-pending-filter-response)))
                        (removed-pending-filter-changes-rpc
                          (parse-json
                           (devnet-cli-http-body
                            removed-pending-filter-changes-response)))
                        (pending-transactions-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-transactions-response)))
                        (pending-block-count-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-block-count-response)))
                        (pending-transaction-by-index-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-transaction-by-index-response)))
                        (pending-raw-transaction-by-index-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-raw-transaction-by-index-response)))
                        (pending-block-rpc
                          (parse-json
                           (devnet-cli-http-body pending-block-response)))
                        (pending-header-rpc
                          (parse-json
                           (devnet-cli-http-body pending-header-response)))
                        (pending-fee-history-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-fee-history-response)))
                        (pending-sender-nonce-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-sender-nonce-response)))
                        (pending-block-receipts-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-block-receipts-response)))
                        (pending-uncle-count-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-uncle-count-response)))
                        (pending-logs-rpc
                          (parse-json
                           (devnet-cli-http-body pending-logs-response)
                           :preserve-empty-arrays t))
                        (txpool-status-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-status-response)))
                        (txpool-content-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-content-response)))
                        (txpool-content-from-rpc
                          (parse-json
                           (devnet-cli-http-body
                            txpool-content-from-response)))
                        (txpool-inspect-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-inspect-response)))
                        (pending-transactions
                          (fixture-object-field
                           pending-transactions-rpc "result"))
                        (pending-filter-changes
                          (fixture-object-field
                           pending-filter-changes-rpc "result"))
                        (empty-pending-filter-changes
                          (fixture-object-field
                           empty-pending-filter-changes-rpc "result"))
                        (removed-pending-filter-error
                          (fixture-object-field
                           removed-pending-filter-changes-rpc "error"))
                        (pending-object (first pending-transactions))
                        (pending-block-count
                          (fixture-object-field pending-block-count-rpc
                                                "result"))
                        (pending-transaction-by-index
                          (fixture-object-field
                           pending-transaction-by-index-rpc "result"))
                        (pending-raw-transaction-by-index
                          (fixture-object-field
                           pending-raw-transaction-by-index-rpc "result"))
                        (pending-block
                          (fixture-object-field pending-block-rpc "result"))
                        (pending-header
                          (fixture-object-field pending-header-rpc "result"))
                        (pending-fee-history
                          (fixture-object-field pending-fee-history-rpc
                                                "result"))
                        (pending-sender-nonce
                          (fixture-object-field pending-sender-nonce-rpc
                                                "result"))
                        (pending-logs
                          (fixture-object-field pending-logs-rpc "result"))
                        (pending-fee-history-base-fees
                          (fixture-object-field pending-fee-history
                                                "baseFeePerGas"))
                        (pending-fee-history-next-base-fee
                          (second pending-fee-history-base-fees))
                        (pending-block-transactions
                          (fixture-object-field pending-block "transactions"))
                        (pending-block-transaction
                          (first pending-block-transactions))
                        (txpool-status
                          (fixture-object-field txpool-status-rpc "result"))
                        (txpool-content
                          (fixture-object-field txpool-content-rpc "result"))
                        (content-pending
                          (fixture-object-field txpool-content "pending"))
                        (content-queued
                          (fixture-object-field txpool-content "queued"))
                        (content-pending-sender
                          (fixture-object-field content-pending sender-hex))
                        (content-queued-sender
                          (fixture-object-field content-queued sender-hex))
                        (content-pending-transaction
                          (fixture-object-field content-pending-sender
                                                pending-nonce))
                        (content-basefee-transaction
                          (fixture-object-field content-queued-sender
                                                basefee-nonce))
                        (content-queued-transaction
                          (fixture-object-field content-queued-sender
                                                queued-nonce))
                        (txpool-content-from
                          (fixture-object-field
                           txpool-content-from-rpc "result"))
                        (content-from-pending
                          (fixture-object-field txpool-content-from "pending"))
                        (content-from-queued
                          (fixture-object-field txpool-content-from "queued"))
                        (content-from-pending-transaction
                          (fixture-object-field
                           content-from-pending pending-nonce))
                        (content-from-basefee-transaction
                          (fixture-object-field
                           content-from-queued basefee-nonce))
                        (content-from-queued-transaction
                          (fixture-object-field
                           content-from-queued queued-nonce))
                        (txpool-inspect
                          (fixture-object-field txpool-inspect-rpc "result"))
                        (inspect-pending
                          (fixture-object-field txpool-inspect "pending"))
                        (inspect-queued
                          (fixture-object-field txpool-inspect "queued"))
                        (inspect-pending-sender
                          (fixture-object-field inspect-pending sender-hex))
                        (inspect-queued-sender
                          (fixture-object-field inspect-queued sender-hex)))
                   (is (= 701 (fixture-object-field send-pending-rpc "id")))
                   (is (= 702 (fixture-object-field send-basefee-rpc "id")))
                   (is (= 703 (fixture-object-field send-queued-rpc "id")))
                   (is (= 717
                          (fixture-object-field new-pending-filter-rpc "id")))
                   (is (= 718
                          (fixture-object-field pending-filter-changes-rpc
                                                "id")))
                   (is (= 719
                          (fixture-object-field
                           empty-pending-filter-changes-rpc "id")))
                   (is (= 720
                          (fixture-object-field
                           uninstall-pending-filter-rpc "id")))
                   (is (= 721
                          (fixture-object-field
                           removed-pending-filter-changes-rpc "id")))
                   (is (= 711 (fixture-object-field pending-block-count-rpc
                                                    "id")))
                   (is (= 712 (fixture-object-field
                               pending-transaction-by-index-rpc "id")))
                   (is (= 713 (fixture-object-field
                               pending-raw-transaction-by-index-rpc "id")))
                   (is (= 714 (fixture-object-field pending-block-rpc "id")))
                   (is (= 715 (fixture-object-field pending-header-rpc "id")))
                   (is (= 722
                          (fixture-object-field pending-fee-history-rpc "id")))
                   (is (= 723
                          (fixture-object-field pending-sender-nonce-rpc "id")))
                   (is (= 724
                          (fixture-object-field
                           pending-block-receipts-rpc "id")))
                   (is (= 725
                          (fixture-object-field pending-uncle-count-rpc "id")))
                   (is (= 726 (fixture-object-field pending-logs-rpc "id")))
                   (is (= 716 (fixture-object-field txpool-content-rpc "id")))
                   (is (string= pending-hash
                                (fixture-object-field
                                 send-pending-rpc "result")))
                   (is (string= basefee-hash
                                (fixture-object-field
                                 send-basefee-rpc "result")))
                   (is (string= queued-hash
                                (fixture-object-field
                                 send-queued-rpc "result")))
                   (is (string= pending-raw
                                (fixture-object-field
                                 raw-pending-rpc "result")))
                   (is (string= basefee-raw
                                (fixture-object-field
                                 raw-basefee-rpc "result")))
                   (is (string= queued-raw
                                (fixture-object-field
                                 raw-queued-rpc "result")))
                   (is (string= "0x1"
                                (fixture-object-field
                                 new-pending-filter-rpc "result")))
                   (is (= 1 (length pending-filter-changes)))
                   (is (string= pending-hash
                                (first pending-filter-changes)))
                   (is (devnet-cli-empty-json-array-p
                        empty-pending-filter-changes))
                   (is (eq t (fixture-object-field
                              uninstall-pending-filter-rpc "result")))
                   (is (= -32602
                          (fixture-object-field
                           removed-pending-filter-error "code")))
                   (is (= 1 (length pending-transactions)))
                   (is (string= pending-hash
                                (fixture-object-field pending-object "hash")))
                   (is (null (fixture-object-field pending-object
                                                   "blockHash")))
                   (is (null (fixture-object-field pending-object
                                                   "blockNumber")))
                   (is (null (fixture-object-field pending-object
                                                   "transactionIndex")))
                   (is (string= "0x1" pending-block-count))
                   (is (string= pending-hash
                                (fixture-object-field
                                 pending-transaction-by-index "hash")))
                   (is (null (fixture-object-field
                              pending-transaction-by-index "blockHash")))
                   (is (null (fixture-object-field
                              pending-transaction-by-index "blockNumber")))
                   (is (null (fixture-object-field
                              pending-transaction-by-index
                              "transactionIndex")))
                   (is (string= pending-raw pending-raw-transaction-by-index))
                   (is (null (fixture-object-field pending-block "hash")))
                   (is (null (fixture-object-field pending-block "nonce")))
                   (is (string= expected-pending-block-number
                                (fixture-object-field pending-block "number")))
                   (is (string= latest-block-hash-hex
                                (fixture-object-field pending-block
                                                      "parentHash")))
                   (is (= 1 (length pending-block-transactions)))
                   (is (string= pending-hash
                                (fixture-object-field
                                 pending-block-transaction "hash")))
                   (is (null (fixture-object-field pending-block-transaction
                                                   "blockHash")))
                   (is (null (fixture-object-field pending-header "hash")))
                   (is (null (fixture-object-field pending-header "nonce")))
                   (is (string= expected-pending-block-number
                                (fixture-object-field pending-header
                                                      "number")))
                   (is (string= latest-block-hash-hex
                                (fixture-object-field pending-header
                                                      "parentHash")))
                   (is (= 2 (length pending-fee-history-base-fees)))
                   (is (string= pending-fee-history-next-base-fee
                                (fixture-object-field pending-block
                                                      "baseFeePerGas")))
                   (is (string= pending-fee-history-next-base-fee
                                (fixture-object-field pending-header
                                                      "baseFeePerGas")))
                   (is (string= expected-pending-sender-nonce
                                pending-sender-nonce))
                   (is (null (fixture-object-field
                              pending-block-receipts-rpc "result")))
                   (is (string= "0x0"
                                (fixture-object-field
                                 pending-uncle-count-rpc "result")))
                   (is (devnet-cli-empty-json-array-p pending-logs))
                   (is (string= "0x1"
                                (fixture-object-field txpool-status
                                                      "pending")))
                   (is (string= "0x2"
                                (fixture-object-field txpool-status
                                                      "queued")))
                   (is (string= pending-hash
                                (fixture-object-field
                                 content-pending-transaction "hash")))
                   (is (string= basefee-hash
                                (fixture-object-field
                                 content-basefee-transaction "hash")))
                   (is (string= queued-hash
                                (fixture-object-field
                                 content-queued-transaction "hash")))
                   (is (string= pending-hash
                                (fixture-object-field
                                 content-from-pending-transaction "hash")))
                   (is (string= basefee-hash
                                (fixture-object-field
                                 content-from-basefee-transaction "hash")))
                   (is (string= queued-hash
                                (fixture-object-field
                                 content-from-queued-transaction "hash")))
                   (is (string= pending-summary
                                (fixture-object-field inspect-pending-sender
                                                      pending-nonce)))
                   (is (string= basefee-summary
                                (fixture-object-field inspect-queued-sender
                                                      basefee-nonce)))
                   (is (string= queued-summary
                                (fixture-object-field inspect-queued-sender
                                                      queued-nonce))))
                 (let ((status (devnet-cli-wait-process-exit process 30)))
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
                              (shutdown-record
                                (find "devnet.shutdown" log-records
                                      :test #'string=
                                      :key (lambda (record)
                                             (getf record :name))))
                              (shutdown-fields
                                (getf shutdown-record :fields)))
                         (is (= pid
                                (fixture-object-field stdout-summary
                                                      "processId")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field stdout-summary
                                                            "rpcEndpoint")))
                         (is shutdown-record)
                         (is (string= "0"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "26"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "26"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file genesis-path)
        (delete-file genesis-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))

(deftest ethereum-lisp-script-serve-mode-serves-engine-v1-workflow
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1" "jwt"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1-genesis"
                                "json"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1-ready"
                                "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode (devnet-cli-pre-shanghai-genesis-object)))
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string +devnet-cli-jwt-secret+ stream))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :public-port 0))
                  (genesis-block
                    (ethereum-lisp.cli::devnet-node-genesis-block node))
                  (payload-attributes
                    (make-payload-attributes-v1
                     :timestamp
                     (1+ (block-header-timestamp
                          (block-header genesis-block)))
                     :prev-randao (zero-hash32)
                     :suggested-fee-recipient (zero-address)))
                  (child-block
                    (ethereum-lisp.core::engine-build-empty-payload
                     genesis-block
                     payload-attributes))
                  (prepared-block
                    (ethereum-lisp.core::engine-build-empty-payload
                     child-block
                     (make-payload-attributes-v1
                      :timestamp
                      (1+ (block-header-timestamp
                           (block-header child-block)))
                      :prev-randao (zero-hash32)
                      :suggested-fee-recipient (zero-address))))
                  (payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data child-block)))
                  (child-hash (block-hash child-block))
                  (child-hash-hex (hash32-to-hex child-hash))
                  (prepared-block-number
                    (quantity-to-hex
                     (block-header-number (block-header prepared-block))))
                  (prepare-payload-attributes
                    (devnet-cli-payload-attributes-v1 child-block
                                                      (zero-address)))
                  (new-payload-body
                    (json-encode
                     (devnet-cli-engine-new-payload-v1-request 701
                                                               payload)))
                  (forkchoice-body
                    (json-encode
                     (engine-fixture-forkchoice-request
                      702 child-hash
                      :safe (block-hash genesis-block)
                      :finalized (block-hash genesis-block))))
                  (prepare-body
                    (json-encode
                     (devnet-cli-engine-forkchoice-v1-payload-attributes-request
                      703 child-hash prepare-payload-attributes
                      :safe (block-hash genesis-block)
                      :finalized (block-hash genesis-block))))
                  (block-number-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 704)
                           (cons "method" "eth_blockNumber")
                           (cons "params" '()))))
                  (latest-block-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 705)
                           (cons "method" "eth_getBlockByNumber")
                           (cons "params" (list "latest" :false)))))
                  (chain-id-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 706)
                           (cons "method" "eth_chainId")
                           (cons "params" '()))))
                  (net-version-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 707)
                           (cons "method" "net_version")
                           (cons "params" '()))))
                  (client-version-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 708)
                           (cons "method" "web3_clientVersion")
                           (cons "params" '())))))
             (setf process
                   (uiop:launch-program
                    (list "sbcl"
                          "--script"
                          script
                          "--"
                          "devnet"
                          "--genesis"
                          (namestring genesis-path)
                          "--engine-port"
                          "0"
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
                          "5"
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
                        (fixture-object-field ready-summary
                                              "engineEndpoint"))
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                      (token (engine-rpc-make-jwt-token jwt-secret 0))
                      new-payload-response
                      forkchoice-response
                      prepare-response
                      get-payload-v1-response
                      get-payload-v2-response
                      block-number-response
                      latest-block-response
                      chain-id-response
                      net-version-response
                      client-version-response)
                 (is (= pid (fixture-object-field ready-summary
                                                   "processId")))
                 (handler-case
                     (progn
                       (setf new-payload-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               new-payload-body
                               :token token)))
                       (setf forkchoice-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               forkchoice-body
                               :token token)))
                       (setf prepare-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               prepare-body
                               :token token)))
                       (let* ((prepare-json
                                (parse-json
                                 (devnet-cli-http-body prepare-response)))
                              (payload-id
                                (fixture-object-field
                                 (fixture-object-field prepare-json "result")
                                 "payloadId"))
                              (get-payload-v1-body
                                (json-encode
                                 (list (cons "jsonrpc" "2.0")
                                       (cons "id" 709)
                                       (cons "method" "engine_getPayloadV1")
                                       (cons "params" (list payload-id)))))
                              (get-payload-v2-body
                                (json-encode
                                 (list (cons "jsonrpc" "2.0")
                                       (cons "id" 710)
                                       (cons "method" "engine_getPayloadV2")
                                       (cons "params" (list payload-id))))))
                         (setf get-payload-v1-response
                               (devnet-cli-http-endpoint-request
                                engine-endpoint
                                (devnet-cli-json-rpc-http-request
                                 get-payload-v1-body
                                 :token token)))
                         (setf get-payload-v2-response
                               (devnet-cli-http-endpoint-request
                                engine-endpoint
                                (devnet-cli-json-rpc-http-request
                                 get-payload-v2-body
                                 :token token))))
                       (setf block-number-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-number-body)))
                       (setf latest-block-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               latest-block-body)))
                       (setf chain-id-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               chain-id-body)))
                       (setf net-version-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               net-version-body)))
                       (setf client-version-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               client-version-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (is (= 200 (devnet-cli-http-status new-payload-response)))
                 (is (= 200 (devnet-cli-http-status forkchoice-response)))
                 (is (= 200 (devnet-cli-http-status prepare-response)))
                 (is (= 200 (devnet-cli-http-status get-payload-v1-response)))
                 (is (= 200 (devnet-cli-http-status get-payload-v2-response)))
                 (is (= 200 (devnet-cli-http-status block-number-response)))
                 (is (= 200 (devnet-cli-http-status latest-block-response)))
                 (is (= 200 (devnet-cli-http-status chain-id-response)))
                 (is (= 200 (devnet-cli-http-status net-version-response)))
                 (is (= 200 (devnet-cli-http-status
                              client-version-response)))
                 (let* ((new-payload-json
                          (parse-json
                           (devnet-cli-http-body new-payload-response)))
                        (new-payload-result
                          (fixture-object-field new-payload-json "result"))
                        (forkchoice-json
                          (parse-json
                           (devnet-cli-http-body forkchoice-response)))
                        (forkchoice-result
                          (fixture-object-field forkchoice-json "result"))
                        (forkchoice-status
                          (fixture-object-field forkchoice-result
                                                "payloadStatus"))
                        (prepare-json
                          (parse-json
                           (devnet-cli-http-body prepare-response)))
                        (prepare-result
                          (fixture-object-field prepare-json "result"))
                        (prepare-status
                          (fixture-object-field prepare-result
                                                "payloadStatus"))
                        (payload-id
                          (fixture-object-field prepare-result
                                                "payloadId"))
                        (get-payload-v1-json
                          (parse-json
                           (devnet-cli-http-body get-payload-v1-response)))
                        (get-payload-v1-result
                          (fixture-object-field get-payload-v1-json
                                                "result"))
                        (get-payload-v2-json
                          (parse-json
                           (devnet-cli-http-body get-payload-v2-response)))
                        (get-payload-v2-result
                          (fixture-object-field get-payload-v2-json
                                                "result"))
                        (get-payload-v2-payload
                          (fixture-object-field get-payload-v2-result
                                                "executionPayload"))
                        (block-number-json
                          (parse-json
                           (devnet-cli-http-body block-number-response)))
                        (latest-block-json
                          (parse-json
                           (devnet-cli-http-body latest-block-response)))
                        (latest-block
                          (fixture-object-field latest-block-json
                                                "result"))
                        (chain-id-json
                          (parse-json
                           (devnet-cli-http-body chain-id-response)))
                        (net-version-json
                          (parse-json
                           (devnet-cli-http-body net-version-response)))
                        (client-version-json
                          (parse-json
                           (devnet-cli-http-body client-version-response))))
                   (is (= 701 (fixture-object-field new-payload-json "id")))
                   (is (string= "VALID"
                                (fixture-object-field new-payload-result
                                                      "status")))
                   (is (string= child-hash-hex
                                (fixture-object-field new-payload-result
                                                      "latestValidHash")))
                   (is (= 702 (fixture-object-field forkchoice-json "id")))
                   (is (string= "VALID"
                                (fixture-object-field forkchoice-status
                                                      "status")))
                   (is (null (fixture-object-field forkchoice-result
                                                   "payloadId")))
                   (is (= 703 (fixture-object-field prepare-json "id")))
                   (is (string= "VALID"
                                (fixture-object-field prepare-status
                                                      "status")))
                   (is (stringp payload-id))
                   (is (= 18 (length payload-id)))
                   (is (= 709 (fixture-object-field get-payload-v1-json
                                                    "id")))
                   (is (string= child-hash-hex
                                (fixture-object-field get-payload-v1-result
                                                      "parentHash")))
                   (is (string= prepared-block-number
                                (fixture-object-field get-payload-v1-result
                                                      "blockNumber")))
                   (is (= 0 (length (fixture-object-field
                                     get-payload-v1-result
                                     "transactions"))))
                   (is (not (fixture-field-present-p get-payload-v1-result
                                                     "withdrawals")))
                   (is (not (fixture-field-present-p get-payload-v1-result
                                                     "executionPayload")))
                   (is (= 710 (fixture-object-field get-payload-v2-json
                                                    "id")))
                   (is (string= child-hash-hex
                                (fixture-object-field get-payload-v2-payload
                                                      "parentHash")))
                   (is (string= prepared-block-number
                                (fixture-object-field get-payload-v2-payload
                                                      "blockNumber")))
                   (is (string= "0x1"
                                (fixture-object-field block-number-json
                                                      "result")))
                   (is (string= child-hash-hex
                                (fixture-object-field latest-block "hash")))
                   (is (string= "0x1"
                                (fixture-object-field latest-block
                                                      "number")))
                   (is (string= "0x539"
                                (fixture-object-field chain-id-json
                                                      "result")))
                   (is (string= "1337"
                                (fixture-object-field net-version-json
                                                      "result")))
                   (is (search "ethereum-lisp"
                               (fixture-object-field client-version-json
                                                     "result"))))
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
                              (shutdown-record
                                (find "devnet.shutdown" log-records
                                      :test #'string=
                                      :key (lambda (record)
                                             (getf record :name))))
                              (shutdown-fields
                                (getf shutdown-record :fields)))
                         (is (= pid
                                (fixture-object-field stdout-summary
                                                      "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field stdout-summary
                                                            "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field stdout-summary
                                                            "rpcEndpoint")))
                         (is shutdown-record)
                         (is (string= "5"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "5"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "10"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))

(deftest ethereum-lisp-script-serve-mode-imports-payload-and-serves-public-state
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload" "jwt"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload-genesis" "json"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload" "pid"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-log-contract-call-with-withdrawal"))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (side-sibling-block
                  (devnet-cli-engine-fixture-side-sibling-block
                   case parent-block))
                (remote-block (devnet-cli-remote-block child-block))
                (invalid-block (devnet-cli-invalid-child-block child-block))
                (payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
                (side-sibling-payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data side-sibling-block)))
                (remote-payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data remote-block)))
                (invalid-payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data invalid-block)))
                (parent (fixture-object-field case "parent"))
                (payload-case (fixture-object-field case "payload"))
                (expect (fixture-object-field case "expect"))
                (recipient (fixture-address-field expect "recipient"))
                (sender (fixture-address-field expect "sender"))
                (code-address (fixture-address-field expect "codeAddress"))
                (storage-address
                  (fixture-address-field expect "storageAddress"))
                (transaction
                  (first (block-transactions child-block)))
                (block-hash-hex
                  (hash32-to-hex (block-hash child-block)))
                (side-sibling-block-hash-hex
                  (hash32-to-hex (block-hash side-sibling-block)))
                (transaction-hash-hex
                  (hash32-to-hex
                   (transaction-hash transaction)))
                (raw-transaction-hex
                  (devnet-cli-transaction-raw transaction))
                (expected-transaction-count-hex
                  (quantity-to-hex (length (block-transactions child-block))))
                (simulation-call-object
                  (list (cons "from" (address-to-hex sender))
                        (cons "to" (address-to-hex code-address))
                        (cons "gas" "0x186a0")
                        (cons "gasPrice" "0x64")
                        (cons "data" "0x")))
                (prepare-payload-attributes
                  (devnet-cli-payload-attributes-v2
                   child-block
                   (block-header-beneficiary (block-header child-block))))
                (new-payload-body
                  (json-encode (engine-fixture-payload-request 601 payload)))
                (remote-payload-body
                  (json-encode
                   (engine-fixture-payload-request 613 remote-payload)))
                (invalid-payload-body
                  (json-encode
                   (engine-fixture-payload-request 614 invalid-payload)))
                (side-sibling-payload-body
                  (json-encode
                   (engine-fixture-payload-request 647
                                                   side-sibling-payload)))
                (forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    602 (block-hash child-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (side-sibling-forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    648 (block-hash side-sibling-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (payload-bodies-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 609)
                         (cons "method" "engine_getPayloadBodiesByHashV1")
                         (cons "params"
                               (list
                                (list
                                 (hash32-to-hex
                                  (block-hash child-block))))))))
                (payload-bodies-by-range-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 610)
                         (cons "method" "engine_getPayloadBodiesByRangeV1")
                         (cons "params"
                               (list
                                (fixture-object-field payload-case "number")
                                "0x1")))))
                (prepare-payload-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-payload-attributes-request
                    605
                    (block-hash child-block)
                    prepare-payload-attributes
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 603)
                         (cons "method" "eth_blockNumber")
                         (cons "params" '()))))
                (post-status-block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 615)
                         (cons "method" "eth_blockNumber")
                         (cons "params" '()))))
                (balance-body
                  (json-encode (engine-fixture-balance-request
                                604 recipient)))
                (safe-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 622)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list (address-to-hex recipient) "safe")))))
                (finalized-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 623)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list (address-to-hex recipient)
                                     "finalized")))))
                (proof-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 633)
                         (cons "method" "eth_getProof")
                         (cons "params"
                               (list (address-to-hex storage-address)
                                     (list (fixture-object-field expect
                                                                 "storageKey"))
                                     "latest")))))
                (block-hash-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 634)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list
                                (address-to-hex recipient)
                                (list (cons "blockHash" block-hash-hex)))))))
                (require-canonical-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 635)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list
                                (address-to-hex recipient)
                                (list (cons "blockHash" block-hash-hex)
                                      (cons "requireCanonical" t)))))))
                (transaction-count-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 607)
                         (cons "method" "eth_getTransactionCount")
                         (cons "params"
                               (list (address-to-hex sender)
                                     "latest")))))
                (block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 608)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" :false)))))
                (block-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 624)
                         (cons "method" "eth_getBlockByHash")
                         (cons "params" (list block-hash-hex :false)))))
                (full-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 640)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" t)))))
                (full-block-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 641)
                         (cons "method" "eth_getBlockByHash")
                         (cons "params" (list block-hash-hex t)))))
                (block-transaction-count-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 625)
                         (cons "method"
                               "eth_getBlockTransactionCountByHash")
                         (cons "params" (list block-hash-hex)))))
                (block-transaction-count-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 626)
                         (cons "method"
                               "eth_getBlockTransactionCountByNumber")
                         (cons "params"
                               (list (fixture-object-field payload-case
                                                           "number"))))))
                (transaction-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 627)
                         (cons "method" "eth_getTransactionByHash")
                         (cons "params" (list transaction-hash-hex)))))
                (transaction-by-block-hash-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 628)
                         (cons "method"
                               "eth_getTransactionByBlockHashAndIndex")
                         (cons "params" (list block-hash-hex "0x0")))))
                (transaction-by-block-number-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 629)
                         (cons "method"
                               "eth_getTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list (fixture-object-field payload-case
                                                           "number")
                                     "0x0")))))
                (raw-transaction-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 630)
                         (cons "method" "eth_getRawTransactionByHash")
                         (cons "params" (list transaction-hash-hex)))))
                (raw-transaction-by-block-hash-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 631)
                         (cons "method"
                               "eth_getRawTransactionByBlockHashAndIndex")
                         (cons "params" (list block-hash-hex "0x0")))))
                (raw-transaction-by-block-number-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 632)
                         (cons "method"
                               "eth_getRawTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list (fixture-object-field payload-case
                                                           "number")
                                     "0x0")))))
                (safe-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 620)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "safe" :false)))))
                (finalized-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 621)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "finalized" :false)))))
                (post-status-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 616)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" :false)))))
                (code-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 611)
                         (cons "method" "eth_getCode")
                         (cons "params"
                               (list (address-to-hex code-address)
                                     "latest")))))
                (storage-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 612)
                         (cons "method" "eth_getStorageAt")
                         (cons "params"
                               (list (address-to-hex storage-address)
                                     (fixture-object-field expect
                                                           "storageKey")
                                     "latest")))))
                (call-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 636)
                         (cons "method" "eth_call")
                         (cons "params"
                               (list simulation-call-object "latest")))))
                (estimate-gas-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 637)
                         (cons "method" "eth_estimateGas")
                         (cons "params"
                               (list simulation-call-object "latest")))))
                (create-access-list-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 638)
                         (cons "method" "eth_createAccessList")
                         (cons "params"
                               (list simulation-call-object "latest")))))
                (post-call-storage-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 639)
                         (cons "method" "eth_getStorageAt")
                         (cons "params"
                               (list (address-to-hex storage-address)
                                     (fixture-object-field expect
                                                           "storageKey")
                                     "latest")))))
                (receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 617)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex)))))
                (block-receipts-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 618)
                         (cons "method" "eth_getBlockReceipts")
                         (cons "params" (list "latest")))))
                (logs-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 619)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" "latest")
                                 (cons "toBlock" "latest")
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (logs-by-block-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 642)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "blockHash" block-hash-hex)
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (new-log-filter-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 645)
                         (cons "method" "eth_newFilter")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" "latest")
                                 (cons "toBlock" "latest")
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (new-block-filter-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 643)
                         (cons "method" "eth_newBlockFilter")
                         (cons "params" '()))))
                (post-reorg-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 651)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" :false)))))
                (post-reorg-transaction-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 652)
                         (cons "method" "eth_getTransactionByHash")
                         (cons "params" (list transaction-hash-hex)))))
                (post-reorg-receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 653)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex)))))
                (post-reorg-logs-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 654)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" "latest")
                                 (cons "toBlock" "latest")
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (post-reorg-pending-block-count-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 655)
                         (cons "method"
                               "eth_getBlockTransactionCountByNumber")
                         (cons "params" (list "pending")))))
                (post-reorg-pending-transaction-by-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 656)
                         (cons "method"
                               "eth_getTransactionByBlockNumberAndIndex")
                         (cons "params" (list "pending" "0x0")))))
                (post-reorg-pending-raw-transaction-by-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 657)
                         (cons "method"
                               "eth_getRawTransactionByBlockNumberAndIndex")
                         (cons "params" (list "pending" "0x0")))))
                (post-reorg-pending-block-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 658)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "pending" t)))))
                (post-reorg-pending-header-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 659)
                         (cons "method" "eth_getHeaderByNumber")
                         (cons "params" (list "pending")))))
                (post-reorg-pending-sender-nonce-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 660)
                         (cons "method" "eth_getTransactionCount")
                         (cons "params"
                               (list (address-to-hex sender)
                                     "pending"))))))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :public-port 0))
                  (script-genesis
                    (ethereum-lisp.cli::devnet-node-genesis-block node)))
             (is (string= (hash32-to-hex (block-hash parent-block))
                          (hash32-to-hex (block-hash script-genesis))))
             (is (= (fixture-quantity-field payload-case "number")
                    (1+ (block-header-number
                         (block-header script-genesis))))))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        (namestring genesis-path)
                        "--engine-port"
                        "0"
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
                        "50"
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
                    new-block-filter-response
                    new-log-filter-response
                    new-payload-response
                    forkchoice-response
                    payload-bodies-by-hash-response
                    payload-bodies-by-range-response
                    prepare-payload-response
                    get-payload-response
                    remote-payload-response
                    invalid-payload-response
                    side-sibling-payload-response
                    side-sibling-forkchoice-response
                    block-number-response
                    post-status-block-number-response
                    balance-response
                    safe-balance-response
                    finalized-balance-response
                    proof-response
                    block-hash-balance-response
                    require-canonical-balance-response
                    transaction-count-response
                    block-by-number-response
                    block-by-hash-response
                    full-block-by-number-response
                    full-block-by-hash-response
                    block-transaction-count-by-hash-response
                    block-transaction-count-by-number-response
                    transaction-by-hash-response
                    transaction-by-block-hash-and-index-response
                    transaction-by-block-number-and-index-response
                    raw-transaction-by-hash-response
                    raw-transaction-by-block-hash-and-index-response
                    raw-transaction-by-block-number-and-index-response
                    safe-block-by-number-response
                    finalized-block-by-number-response
                    post-status-block-by-number-response
                    code-response
                    storage-response
                    call-response
                    estimate-gas-response
                    create-access-list-response
                    post-call-storage-response
                    receipt-response
                    block-receipts-response
                    logs-response
                    logs-by-block-hash-response
                    block-filter-changes-response
                    log-filter-changes-response
                    post-reorg-block-filter-changes-response
                    post-reorg-log-filter-changes-response
                    post-reorg-block-by-number-response
                    post-reorg-transaction-by-hash-response
                    post-reorg-receipt-response
                    post-reorg-logs-response
                    post-reorg-pending-block-count-response
                    post-reorg-pending-transaction-by-index-response
                    post-reorg-pending-raw-transaction-by-index-response
                    post-reorg-pending-block-response
                    post-reorg-pending-header-response
                    post-reorg-pending-sender-nonce-response
                    block-filter-id
                    log-filter-id)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (handler-case
                   (progn
                     (setf new-block-filter-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-block-filter-body)))
                     (setf new-log-filter-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-log-filter-body)))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token)))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token)))
                     (setf payload-bodies-by-hash-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             payload-bodies-by-hash-body
                             :token token)))
                     (setf payload-bodies-by-range-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             payload-bodies-by-range-body
                             :token token)))
                     (setf prepare-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             prepare-payload-body
                             :token token)))
                     (let* ((prepare-payload-rpc
                              (parse-json
                               (devnet-cli-http-body
                                prepare-payload-response)))
                            (prepare-payload-result
                              (fixture-object-field
                               prepare-payload-rpc "result"))
                            (prepared-payload-id
                              (fixture-object-field
                               prepare-payload-result "payloadId"))
                            (get-payload-body
                              (json-encode
                               (list
                                (cons "jsonrpc" "2.0")
                                (cons "id" 606)
                                (cons "method" "engine_getPayloadV2")
                                (cons "params"
                                      (list prepared-payload-id))))))
                       (setf get-payload-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               get-payload-body
                               :token token))))
                     (setf remote-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             remote-payload-body
                             :token token)))
                     (setf invalid-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             invalid-payload-body
                             :token token)))
                     (setf block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-number-body)))
                     (setf balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             balance-body)))
                     (setf safe-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             safe-balance-body)))
                     (setf finalized-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             finalized-balance-body)))
                     (setf proof-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             proof-body)))
                     (setf block-hash-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-hash-balance-body)))
                     (setf require-canonical-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             require-canonical-balance-body)))
                     (setf transaction-count-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-count-body)))
                     (setf block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-by-number-body)))
                     (setf block-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-by-hash-body)))
                     (setf full-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             full-block-by-number-body)))
                     (setf full-block-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             full-block-by-hash-body)))
                     (setf block-transaction-count-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-transaction-count-by-hash-body)))
                     (setf block-transaction-count-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-transaction-count-by-number-body)))
                     (setf transaction-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-by-hash-body)))
                     (setf transaction-by-block-hash-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-by-block-hash-and-index-body)))
                     (setf transaction-by-block-number-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-by-block-number-and-index-body)))
                     (setf raw-transaction-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             raw-transaction-by-hash-body)))
                     (setf raw-transaction-by-block-hash-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             raw-transaction-by-block-hash-and-index-body)))
                     (setf raw-transaction-by-block-number-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             raw-transaction-by-block-number-and-index-body)))
                     (setf safe-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             safe-block-by-number-body)))
                     (setf finalized-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             finalized-block-by-number-body)))
                     (setf code-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             code-body)))
                     (setf storage-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             storage-body)))
                     (setf call-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             call-body)))
                     (setf estimate-gas-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             estimate-gas-body)))
                     (setf create-access-list-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             create-access-list-body)))
                     (setf post-call-storage-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-call-storage-body)))
                     (setf receipt-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             receipt-body)))
                     (setf block-receipts-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-receipts-body)))
                     (setf logs-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             logs-body)))
                     (setf logs-by-block-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             logs-by-block-hash-body)))
                     (let* ((new-block-filter-rpc
                              (parse-json
                               (devnet-cli-http-body
                                new-block-filter-response))))
                       (setf block-filter-id
                             (fixture-object-field
                              new-block-filter-rpc "result"))
                       (let ((block-filter-changes-body
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 644)
                                 (cons "method" "eth_getFilterChanges")
                                 (cons "params"
                                       (list block-filter-id))))))
                       (setf block-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-filter-changes-body)))))
                     (let* ((new-log-filter-rpc
                              (parse-json
                               (devnet-cli-http-body
                                new-log-filter-response))))
                       (setf log-filter-id
                             (fixture-object-field
                              new-log-filter-rpc "result"))
                       (let ((log-filter-changes-body
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 646)
                                 (cons "method" "eth_getFilterChanges")
                                 (cons "params"
                                       (list log-filter-id))))))
                       (setf log-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               log-filter-changes-body)))))
                     (setf post-status-block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-status-block-number-body)))
                     (setf post-status-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-status-block-by-number-body)))
                     (setf side-sibling-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             side-sibling-payload-body
                             :token token)))
                     (setf side-sibling-forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             side-sibling-forkchoice-body
                             :token token)))
                     (setf post-reorg-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-block-by-number-body)))
                     (setf post-reorg-transaction-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-transaction-by-hash-body)))
                     (setf post-reorg-receipt-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-receipt-body)))
                     (setf post-reorg-logs-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-logs-body)))
                     (setf post-reorg-pending-block-count-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-block-count-body)))
                     (setf post-reorg-pending-transaction-by-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-transaction-by-index-body)))
                     (setf post-reorg-pending-raw-transaction-by-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-raw-transaction-by-index-body)))
                     (setf post-reorg-pending-block-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-block-body)))
                     (setf post-reorg-pending-header-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-header-body)))
                     (setf post-reorg-pending-sender-nonce-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-sender-nonce-body)))
                     (let ((post-reorg-block-filter-changes-body
                             (json-encode
                              (list
                               (cons "jsonrpc" "2.0")
                               (cons "id" 649)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list block-filter-id))))))
                       (setf post-reorg-block-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               post-reorg-block-filter-changes-body))))
                     (let ((post-reorg-log-filter-changes-body
                             (json-encode
                              (list
                               (cons "jsonrpc" "2.0")
                               (cons "id" 650)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list log-filter-id))))))
                       (setf post-reorg-log-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               post-reorg-log-filter-changes-body)))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                               "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status new-block-filter-response)))
               (is (= 200 (devnet-cli-http-status new-log-filter-response)))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (is (= 200 (devnet-cli-http-status forkchoice-response)))
               (is (= 200 (devnet-cli-http-status
                            payload-bodies-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            payload-bodies-by-range-response)))
               (is (= 200 (devnet-cli-http-status prepare-payload-response)))
               (is (= 200 (devnet-cli-http-status get-payload-response)))
               (is (= 200 (devnet-cli-http-status remote-payload-response)))
               (is (= 200 (devnet-cli-http-status invalid-payload-response)))
               (is (= 200 (devnet-cli-http-status
                            side-sibling-payload-response)))
               (is (= 200 (devnet-cli-http-status
                            side-sibling-forkchoice-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-transaction-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-receipt-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-logs-response)))
               (is (= 200 (devnet-cli-http-status block-number-response)))
               (is (= 200 (devnet-cli-http-status
                            post-status-block-number-response)))
               (is (= 200 (devnet-cli-http-status balance-response)))
               (is (= 200 (devnet-cli-http-status safe-balance-response)))
               (is (= 200 (devnet-cli-http-status finalized-balance-response)))
               (is (= 200 (devnet-cli-http-status proof-response)))
               (is (= 200 (devnet-cli-http-status
                            block-hash-balance-response)))
               (is (= 200 (devnet-cli-http-status
                            require-canonical-balance-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-count-response)))
               (is (= 200 (devnet-cli-http-status
                            block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            block-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            full-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            full-block-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            block-transaction-count-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            block-transaction-count-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-by-block-hash-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-by-block-number-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            raw-transaction-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            raw-transaction-by-block-hash-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            raw-transaction-by-block-number-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            safe-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            finalized-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            post-status-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status code-response)))
               (is (= 200 (devnet-cli-http-status storage-response)))
               (is (= 200 (devnet-cli-http-status call-response)))
               (is (= 200 (devnet-cli-http-status estimate-gas-response)))
               (is (= 200 (devnet-cli-http-status
                            create-access-list-response)))
               (is (= 200 (devnet-cli-http-status
                            post-call-storage-response)))
               (is (= 200 (devnet-cli-http-status receipt-response)))
               (is (= 200 (devnet-cli-http-status block-receipts-response)))
               (is (= 200 (devnet-cli-http-status logs-response)))
               (is (= 200 (devnet-cli-http-status
                            logs-by-block-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            block-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            log-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-block-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-log-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-block-count-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-transaction-by-index-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-raw-transaction-by-index-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-block-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-header-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-sender-nonce-response)))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-block-filter-rpc
                        (parse-json
                         (devnet-cli-http-body
                          new-block-filter-response)))
                      (new-log-filter-rpc
                        (parse-json
                         (devnet-cli-http-body
                          new-log-filter-response)))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (payload-bodies-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          payload-bodies-by-hash-response)))
                      (payload-bodies-by-range-rpc
                        (parse-json
                         (devnet-cli-http-body
                          payload-bodies-by-range-response)))
                      (prepare-payload-rpc
                        (parse-json
                         (devnet-cli-http-body prepare-payload-response)))
                      (get-payload-rpc
                        (parse-json
                         (devnet-cli-http-body get-payload-response)))
                      (remote-payload-rpc
                        (parse-json
                         (devnet-cli-http-body remote-payload-response)))
                      (invalid-payload-rpc
                        (parse-json
                         (devnet-cli-http-body invalid-payload-response)))
                      (side-sibling-payload-rpc
                        (parse-json
                         (devnet-cli-http-body
                          side-sibling-payload-response)))
                      (side-sibling-forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body
                          side-sibling-forkchoice-response)))
                      (post-reorg-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-block-by-number-response)))
                      (post-reorg-transaction-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-transaction-by-hash-response)))
                      (post-reorg-receipt-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-receipt-response)))
                      (post-reorg-logs-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-logs-response)))
                      (post-reorg-pending-block-count-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-block-count-response)))
                      (post-reorg-pending-transaction-by-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-transaction-by-index-response)))
                      (post-reorg-pending-raw-transaction-by-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-raw-transaction-by-index-response)))
                      (post-reorg-pending-block-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-block-response)))
                      (post-reorg-pending-header-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-header-response)))
                      (post-reorg-pending-sender-nonce-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-sender-nonce-response)))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (post-status-block-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-status-block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (safe-balance-rpc
                        (parse-json
                         (devnet-cli-http-body safe-balance-response)))
                      (finalized-balance-rpc
                        (parse-json
                         (devnet-cli-http-body finalized-balance-response)))
                      (proof-rpc
                        (parse-json
                         (devnet-cli-http-body proof-response)))
                      (block-hash-balance-rpc
                        (parse-json
                         (devnet-cli-http-body block-hash-balance-response)))
                      (require-canonical-balance-rpc
                        (parse-json
                         (devnet-cli-http-body
                          require-canonical-balance-response)))
                      (transaction-count-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-count-response)))
                      (block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-by-number-response)))
                      (block-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-by-hash-response)))
                      (full-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          full-block-by-number-response)))
                      (full-block-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          full-block-by-hash-response)))
                      (block-transaction-count-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-transaction-count-by-hash-response)))
                      (block-transaction-count-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-transaction-count-by-number-response)))
                      (transaction-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-by-hash-response)))
                      (transaction-by-block-hash-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-by-block-hash-and-index-response)))
                      (transaction-by-block-number-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-by-block-number-and-index-response)))
                      (raw-transaction-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          raw-transaction-by-hash-response)))
                      (raw-transaction-by-block-hash-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          raw-transaction-by-block-hash-and-index-response)))
                      (raw-transaction-by-block-number-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          raw-transaction-by-block-number-and-index-response)))
                      (safe-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          safe-block-by-number-response)))
                      (finalized-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          finalized-block-by-number-response)))
                      (post-status-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-status-block-by-number-response)))
                      (code-rpc
                        (parse-json
                         (devnet-cli-http-body code-response)))
                      (storage-rpc
                        (parse-json
                         (devnet-cli-http-body storage-response)))
                      (call-rpc
                        (parse-json
                         (devnet-cli-http-body call-response)))
                      (estimate-gas-rpc
                        (parse-json
                         (devnet-cli-http-body estimate-gas-response)))
                      (create-access-list-rpc
                        (parse-json
                         (devnet-cli-http-body
                          create-access-list-response)))
                      (post-call-storage-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-call-storage-response)))
                      (receipt-rpc
                        (parse-json
                         (devnet-cli-http-body receipt-response)))
                      (block-receipts-rpc
                        (parse-json
                         (devnet-cli-http-body block-receipts-response)))
                      (logs-rpc
                        (parse-json
                         (devnet-cli-http-body logs-response)))
                      (logs-by-block-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          logs-by-block-hash-response)))
                      (block-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-filter-changes-response)))
                      (block-filter-changes
                        (fixture-object-field block-filter-changes-rpc
                                              "result"))
                      (log-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          log-filter-changes-response)))
                      (log-filter-changes
                        (fixture-object-field log-filter-changes-rpc
                                              "result"))
                      (log-filter-change-log (first log-filter-changes))
                      (post-reorg-block-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-block-filter-changes-response)))
                      (post-reorg-block-filter-changes
                        (fixture-object-field
                         post-reorg-block-filter-changes-rpc
                         "result"))
                      (post-reorg-log-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-log-filter-changes-response)))
                      (post-reorg-log-filter-changes
                        (fixture-object-field
                         post-reorg-log-filter-changes-rpc
                         "result"))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (side-sibling-payload-result
                        (fixture-object-field
                         side-sibling-payload-rpc "result"))
                      (side-sibling-forkchoice-status
                        (fixture-object-field
                         (fixture-object-field
                          side-sibling-forkchoice-rpc "result")
                         "payloadStatus"))
                      (post-reorg-block-by-number-result
                        (fixture-object-field
                         post-reorg-block-by-number-rpc "result"))
                      (post-reorg-transaction-by-hash-result
                        (fixture-object-field
                         post-reorg-transaction-by-hash-rpc "result"))
                      (post-reorg-logs
                        (fixture-object-field post-reorg-logs-rpc "result"))
                      (post-reorg-pending-block-count
                        (fixture-object-field
                         post-reorg-pending-block-count-rpc "result"))
                      (post-reorg-pending-transaction-by-index
                        (fixture-object-field
                         post-reorg-pending-transaction-by-index-rpc
                         "result"))
                      (post-reorg-pending-raw-transaction-by-index
                        (fixture-object-field
                         post-reorg-pending-raw-transaction-by-index-rpc
                         "result"))
                      (post-reorg-pending-block
                        (fixture-object-field
                         post-reorg-pending-block-rpc "result"))
                      (post-reorg-pending-header
                        (fixture-object-field
                         post-reorg-pending-header-rpc "result"))
                      (post-reorg-pending-sender-nonce
                        (fixture-object-field
                         post-reorg-pending-sender-nonce-rpc "result"))
                      (post-reorg-pending-block-transactions
                        (fixture-object-field
                         post-reorg-pending-block "transactions"))
                      (post-reorg-pending-block-transaction
                        (first post-reorg-pending-block-transactions))
                      (payload-bodies-by-hash-result
                        (fixture-object-field
                         payload-bodies-by-hash-rpc "result"))
                      (payload-bodies-by-range-result
                        (fixture-object-field
                         payload-bodies-by-range-rpc "result"))
                      (payload-body-by-hash-transactions
                        (fixture-object-field
                         (first payload-bodies-by-hash-result)
                         "transactions"))
                      (payload-body-by-range-transactions
                        (fixture-object-field
                         (first payload-bodies-by-range-result)
                         "transactions"))
                      (expected-payload-body-transaction-count
                        (length (block-transactions child-block)))
                      (prepare-payload-result
                        (fixture-object-field prepare-payload-rpc "result"))
                      (prepare-payload-status
                        (fixture-object-field
                         prepare-payload-result
                         "payloadStatus"))
                      (prepared-payload-id
                        (fixture-object-field
                         prepare-payload-result "payloadId"))
                      (get-payload-result
                        (fixture-object-field get-payload-rpc "result"))
                      (get-payload-execution-payload
                        (fixture-object-field
                         get-payload-result
                         "executionPayload"))
                      (get-payload-transactions
                        (fixture-object-field
                         get-payload-execution-payload
                         "transactions"))
                      (remote-payload-result
                        (fixture-object-field remote-payload-rpc "result"))
                      (invalid-payload-result
                        (fixture-object-field invalid-payload-rpc "result"))
                      (block-by-number-result
                        (fixture-object-field block-by-number-rpc "result"))
                      (block-by-hash-result
                        (fixture-object-field block-by-hash-rpc "result"))
                      (full-block-by-number-result
                        (fixture-object-field full-block-by-number-rpc
                                              "result"))
                      (full-block-by-hash-result
                        (fixture-object-field full-block-by-hash-rpc
                                              "result"))
                      (full-block-by-number-transactions
                        (fixture-object-field full-block-by-number-result
                                              "transactions"))
                      (full-block-by-hash-transactions
                        (fixture-object-field full-block-by-hash-result
                                              "transactions"))
                      (full-block-by-number-transaction
                        (first full-block-by-number-transactions))
                      (full-block-by-hash-transaction
                        (first full-block-by-hash-transactions))
                      (transaction-by-hash-result
                        (fixture-object-field transaction-by-hash-rpc
                                              "result"))
                      (transaction-by-block-hash-and-index-result
                        (fixture-object-field
                         transaction-by-block-hash-and-index-rpc "result"))
                      (transaction-by-block-number-and-index-result
                        (fixture-object-field
                         transaction-by-block-number-and-index-rpc "result"))
                      (proof-result
                        (fixture-object-field proof-rpc "result"))
                      (proof-storage
                        (first (fixture-object-field proof-result
                                                     "storageProof")))
                      (create-access-list-result
                        (fixture-object-field create-access-list-rpc
                                              "result"))
                      (actual-access-list
                        (fixture-object-field create-access-list-result
                                              "accessList"))
                      (actual-access-list-gas-used
                        (fixture-object-field create-access-list-result
                                              "gasUsed"))
                      (actual-access-list-entry
                        (find (address-to-hex storage-address)
                              actual-access-list
                              :test #'string=
                              :key (lambda (entry)
                                     (fixture-object-field entry "address"))))
                      (actual-access-list-storage-keys
                        (and actual-access-list-entry
                             (fixture-object-field actual-access-list-entry
                                                   "storageKeys")))
                      (safe-block-by-number-result
                        (fixture-object-field safe-block-by-number-rpc
                                              "result"))
                      (finalized-block-by-number-result
                        (fixture-object-field finalized-block-by-number-rpc
                                              "result"))
                      (post-status-block-by-number-result
                        (fixture-object-field post-status-block-by-number-rpc
                                              "result"))
                      (receipt
                        (fixture-object-field receipt-rpc "result"))
                      (receipt-logs
                        (fixture-object-field receipt "logs"))
                      (receipt-log (first receipt-logs))
                      (block-receipts
                        (fixture-object-field block-receipts-rpc "result"))
                      (block-receipt (first block-receipts))
                      (block-receipt-logs
                        (fixture-object-field block-receipt "logs"))
                      (block-receipt-log (first block-receipt-logs))
                      (filtered-logs
                        (fixture-object-field logs-rpc "result"))
                      (filtered-log (first filtered-logs))
                      (block-hash-filtered-logs
                        (fixture-object-field logs-by-block-hash-rpc
                                              "result"))
                      (block-hash-filtered-log
                        (first block-hash-filtered-logs))
                      (expected-prepared-block-number
                        (quantity-to-hex
                         (1+ (block-header-number
                              (block-header child-block)))))
                      (expected-post-reorg-pending-block-number
                        (quantity-to-hex
                         (1+ (block-header-number
                              (block-header side-sibling-block))))))
                 (is (= 601 (fixture-object-field new-payload-rpc "id")))
                 (is (= 602 (fixture-object-field forkchoice-rpc "id")))
                 (is (= 603 (fixture-object-field block-number-rpc "id")))
                 (is (= 604 (fixture-object-field balance-rpc "id")))
                 (is (= 605 (fixture-object-field prepare-payload-rpc "id")))
                 (is (= 606 (fixture-object-field get-payload-rpc "id")))
                 (is (= 607 (fixture-object-field
                              transaction-count-rpc "id")))
                 (is (= 608 (fixture-object-field block-by-number-rpc "id")))
                 (is (= 609 (fixture-object-field
                              payload-bodies-by-hash-rpc "id")))
                 (is (= 610 (fixture-object-field
                              payload-bodies-by-range-rpc "id")))
                 (is (= 611 (fixture-object-field code-rpc "id")))
                 (is (= 612 (fixture-object-field storage-rpc "id")))
                 (is (= 613 (fixture-object-field remote-payload-rpc "id")))
                 (is (= 614 (fixture-object-field invalid-payload-rpc "id")))
                 (is (= 647 (fixture-object-field
                              side-sibling-payload-rpc "id")))
                 (is (= 648 (fixture-object-field
                              side-sibling-forkchoice-rpc "id")))
                 (is (= 651 (fixture-object-field
                              post-reorg-block-by-number-rpc "id")))
                 (is (= 652 (fixture-object-field
                              post-reorg-transaction-by-hash-rpc "id")))
                 (is (= 653 (fixture-object-field
                              post-reorg-receipt-rpc "id")))
                 (is (= 654 (fixture-object-field
                              post-reorg-logs-rpc "id")))
                 (is (= 655 (fixture-object-field
                              post-reorg-pending-block-count-rpc "id")))
                 (is (= 656
                        (fixture-object-field
                         post-reorg-pending-transaction-by-index-rpc "id")))
                 (is (= 657
                        (fixture-object-field
                         post-reorg-pending-raw-transaction-by-index-rpc
                         "id")))
                 (is (= 658 (fixture-object-field
                              post-reorg-pending-block-rpc "id")))
                 (is (= 659 (fixture-object-field
                              post-reorg-pending-header-rpc "id")))
                 (is (= 660 (fixture-object-field
                              post-reorg-pending-sender-nonce-rpc "id")))
                 (is (= 615 (fixture-object-field
                              post-status-block-number-rpc "id")))
                 (is (= 616 (fixture-object-field
                              post-status-block-by-number-rpc "id")))
                 (is (= 617 (fixture-object-field receipt-rpc "id")))
                 (is (= 618 (fixture-object-field block-receipts-rpc "id")))
                 (is (= 619 (fixture-object-field logs-rpc "id")))
                 (is (= 620 (fixture-object-field
                              safe-block-by-number-rpc "id")))
                 (is (= 621 (fixture-object-field
                              finalized-block-by-number-rpc "id")))
                 (is (= 622 (fixture-object-field safe-balance-rpc "id")))
                 (is (= 623 (fixture-object-field finalized-balance-rpc "id")))
                 (is (= 624 (fixture-object-field block-by-hash-rpc "id")))
                 (is (= 625 (fixture-object-field
                              block-transaction-count-by-hash-rpc "id")))
                 (is (= 626 (fixture-object-field
                              block-transaction-count-by-number-rpc "id")))
                 (is (= 627 (fixture-object-field
                              transaction-by-hash-rpc "id")))
                 (is (= 628 (fixture-object-field
                              transaction-by-block-hash-and-index-rpc "id")))
                 (is (= 629 (fixture-object-field
                              transaction-by-block-number-and-index-rpc "id")))
                 (is (= 630 (fixture-object-field
                              raw-transaction-by-hash-rpc "id")))
                 (is (= 631 (fixture-object-field
                              raw-transaction-by-block-hash-and-index-rpc
                              "id")))
                 (is (= 632 (fixture-object-field
                              raw-transaction-by-block-number-and-index-rpc
                              "id")))
                 (is (= 633 (fixture-object-field proof-rpc "id")))
                 (is (= 634 (fixture-object-field
                              block-hash-balance-rpc "id")))
                 (is (= 635 (fixture-object-field
                              require-canonical-balance-rpc "id")))
                 (is (= 636 (fixture-object-field call-rpc "id")))
                 (is (= 637 (fixture-object-field estimate-gas-rpc "id")))
                 (is (= 638 (fixture-object-field create-access-list-rpc "id")))
                 (is (= 639 (fixture-object-field post-call-storage-rpc "id")))
                 (is (= 640 (fixture-object-field
                              full-block-by-number-rpc "id")))
                 (is (= 641 (fixture-object-field
                              full-block-by-hash-rpc "id")))
                 (is (= 642 (fixture-object-field
                              logs-by-block-hash-rpc "id")))
                 (is (= 643 (fixture-object-field
                              new-block-filter-rpc "id")))
                 (is (= 644 (fixture-object-field
                              block-filter-changes-rpc "id")))
                 (is (= 645 (fixture-object-field
                              new-log-filter-rpc "id")))
                 (is (= 646 (fixture-object-field
                              log-filter-changes-rpc "id")))
                 (is (= 649 (fixture-object-field
                              post-reorg-block-filter-changes-rpc "id")))
                 (is (= 650 (fixture-object-field
                              post-reorg-log-filter-changes-rpc "id")))
                 (is (string= "0x1"
                              (fixture-object-field
                               new-block-filter-rpc "result")))
                 (is (string= "0x2"
                              (fixture-object-field
                               new-log-filter-rpc "result")))
                 (is (= 1 (length block-filter-changes)))
                 (is (string= block-hash-hex (first block-filter-changes)))
                 (is (= (length receipt-logs) (length log-filter-changes)))
                 (is (= 1 (length post-reorg-block-filter-changes)))
                 (is (string= side-sibling-block-hash-hex
                              (first post-reorg-block-filter-changes)))
                 (is (= (length receipt-logs)
                        (length post-reorg-log-filter-changes)))
                 (dolist (removed-log post-reorg-log-filter-changes)
                   (is (eq t (fixture-object-field removed-log "removed")))
                   (is (string= (fixture-object-field expect "logAddress")
                                (fixture-object-field removed-log "address")))
                   (is (string= (fixture-object-field expect "logData")
                                (fixture-object-field removed-log "data")))
                   (is (equal (list (fixture-object-field expect "logTopic"))
                              (fixture-object-field removed-log "topics")))
                   (is (string= block-hash-hex
                                (fixture-object-field removed-log
                                                      "blockHash"))))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field
                               side-sibling-payload-result "status")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               side-sibling-payload-result
                               "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field
                               side-sibling-forkchoice-status
                               "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field
                               post-reorg-block-by-number-result
                               "number")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               post-reorg-block-by-number-result
                               "hash")))
                 (is (equal '()
                            (fixture-object-field
                             post-reorg-block-by-number-result
                             "transactions")))
                 (is (string= transaction-hash-hex
                              (fixture-object-field
                               post-reorg-transaction-by-hash-result
                               "hash")))
                 (is (null (fixture-object-field
                            post-reorg-transaction-by-hash-result
                            "blockHash")))
                 (is (null (fixture-object-field
                            post-reorg-transaction-by-hash-result
                            "blockNumber")))
                 (is (null (fixture-object-field
                            post-reorg-transaction-by-hash-result
                            "transactionIndex")))
                 (is (string= "0x1" post-reorg-pending-block-count))
                 (is (string= transaction-hash-hex
                              (fixture-object-field
                               post-reorg-pending-transaction-by-index
                               "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-transaction-by-index
                            "blockHash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-transaction-by-index
                            "blockNumber")))
                 (is (null (fixture-object-field
                            post-reorg-pending-transaction-by-index
                            "transactionIndex")))
                 (is (string= raw-transaction-hex
                              post-reorg-pending-raw-transaction-by-index))
                 (is (null (fixture-object-field
                            post-reorg-pending-block "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block "nonce")))
                 (is (string= expected-post-reorg-pending-block-number
                              (fixture-object-field
                               post-reorg-pending-block "number")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               post-reorg-pending-block "parentHash")))
                 (is (= 1 (length post-reorg-pending-block-transactions)))
                 (is (string= transaction-hash-hex
                              (fixture-object-field
                               post-reorg-pending-block-transaction
                               "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block-transaction
                            "blockHash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block-transaction
                            "blockNumber")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block-transaction
                            "transactionIndex")))
                 (is (null (fixture-object-field
                            post-reorg-pending-header "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-header "nonce")))
                 (is (string= expected-post-reorg-pending-block-number
                              (fixture-object-field
                               post-reorg-pending-header "number")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               post-reorg-pending-header "parentHash")))
                 (is (string= (fixture-object-field expect "senderNonce")
                              post-reorg-pending-sender-nonce))
                 (is (null (fixture-object-field
                            post-reorg-receipt-rpc "result")))
                 (is (null post-reorg-logs))
                 (is (= 1 (length payload-bodies-by-hash-result)))
                 (is (= 1 (length payload-bodies-by-range-result)))
                 (is (= expected-payload-body-transaction-count
                        (length payload-body-by-hash-transactions)))
                 (is (= expected-payload-body-transaction-count
                        (length payload-body-by-range-transactions)))
                 (is (string= +payload-status-valid+
                              (fixture-object-field prepare-payload-status
                                                    "status")))
                 (is (and (stringp prepared-payload-id)
                          (= 18 (length prepared-payload-id))))
                 (is (not (fixture-object-field get-payload-rpc "error")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field
                               get-payload-execution-payload
                               "parentHash")))
                 (is (string= expected-prepared-block-number
                              (fixture-object-field
                               get-payload-execution-payload
                               "blockNumber")))
                 (is (and (listp get-payload-transactions)
                          (null get-payload-transactions)))
                 (is (string= +payload-status-syncing+
                              (fixture-object-field remote-payload-result
                                                    "status")))
                 (is (null (fixture-object-field remote-payload-result
                                                 "latestValidHash")))
                 (is (string= +payload-status-invalid+
                              (fixture-object-field invalid-payload-result
                                                    "status")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field invalid-payload-result
                                                    "latestValidHash")))
                 (is (string= "Timestamp is not greater than parent timestamp"
                              (fixture-object-field invalid-payload-result
                                                    "validationError")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field
                               post-status-block-number-rpc
                               "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc
                                                    "result")))
                 (is (string= "0x0"
                              (fixture-object-field safe-balance-rpc
                                                    "result")))
                 (is (string= "0x0"
                              (fixture-object-field finalized-balance-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field block-hash-balance-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field
                               require-canonical-balance-rpc "result")))
                 (is (string= (fixture-object-field expect "senderNonce")
                              (fixture-object-field transaction-count-rpc
                                                    "result")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-by-number-result
                                                    "number")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field block-by-number-result
                                                    "hash")))
                 (is (equal (list transaction-hash-hex)
                            (fixture-object-field block-by-number-result
                                                  "transactions")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-by-hash-result
                                                    "number")))
                 (is (string= block-hash-hex
                              (fixture-object-field block-by-hash-result
                                                    "hash")))
                 (is (equal (list transaction-hash-hex)
                            (fixture-object-field block-by-hash-result
                                                  "transactions")))
                 (dolist (full-block-result
                          (list full-block-by-number-result
                                full-block-by-hash-result))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field full-block-result
                                                      "number")))
                   (is (string= block-hash-hex
                                (fixture-object-field full-block-result
                                                      "hash"))))
                 (dolist (transactions
                          (list full-block-by-number-transactions
                                full-block-by-hash-transactions))
                   (is (= 1 (length transactions))))
                 (dolist (full-block-transaction
                          (list full-block-by-number-transaction
                                full-block-by-hash-transaction))
                   (is (string= transaction-hash-hex
                                (fixture-object-field full-block-transaction
                                                      "hash")))
                   (is (string= block-hash-hex
                                (fixture-object-field full-block-transaction
                                                      "blockHash")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field full-block-transaction
                                                      "blockNumber")))
                   (is (string= "0x0"
                                (fixture-object-field full-block-transaction
                                                      "transactionIndex"))))
                 (is (string= expected-transaction-count-hex
                              (fixture-object-field
                               block-transaction-count-by-hash-rpc
                               "result")))
                 (is (string= expected-transaction-count-hex
                              (fixture-object-field
                               block-transaction-count-by-number-rpc
                               "result")))
                 (dolist (transaction-result
                          (list transaction-by-hash-result
                                transaction-by-block-hash-and-index-result
                                transaction-by-block-number-and-index-result))
                   (is (string= transaction-hash-hex
                                (fixture-object-field transaction-result
                                                      "hash")))
                   (is (string= block-hash-hex
                                (fixture-object-field transaction-result
                                                      "blockHash")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field transaction-result
                                                      "blockNumber")))
                   (is (string= "0x0"
                                (fixture-object-field transaction-result
                                                      "transactionIndex"))))
                 (is (string= raw-transaction-hex
                              (fixture-object-field raw-transaction-by-hash-rpc
                                                    "result")))
                 (is (string= raw-transaction-hex
                              (fixture-object-field
                               raw-transaction-by-block-hash-and-index-rpc
                               "result")))
                 (is (string= raw-transaction-hex
                              (fixture-object-field
                               raw-transaction-by-block-number-and-index-rpc
                               "result")))
                 (is (string= (address-to-hex storage-address)
                              (fixture-object-field proof-result "address")))
                 (is (listp (fixture-object-field proof-result
                                                  "accountProof")))
                 (is (string= (fixture-object-field expect "storageKey")
                              (fixture-object-field proof-storage "key")))
                 (is (string= (quantity-to-hex
                               (hex-to-quantity
                                (fixture-object-field expect "storageValue")))
                              (fixture-object-field proof-storage "value")))
                 (is (listp (fixture-object-field proof-storage "proof")))
                 (is (string= (fixture-object-field parent "number")
                              (fixture-object-field
                               safe-block-by-number-result
                               "number")))
                 (is (string= (hash32-to-hex (block-hash parent-block))
                              (fixture-object-field
                               safe-block-by-number-result
                               "hash")))
                 (is (string= (fixture-object-field parent "number")
                              (fixture-object-field
                               finalized-block-by-number-result
                               "number")))
                 (is (string= (hash32-to-hex (block-hash parent-block))
                              (fixture-object-field
                               finalized-block-by-number-result
                               "hash")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field
                               post-status-block-by-number-result
                               "number")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field
                               post-status-block-by-number-result
                               "hash")))
                 (is (string= (fixture-object-field expect "code")
                              (fixture-object-field code-rpc "result")))
                 (is (string= (fixture-object-field expect "storageValue")
                              (fixture-object-field storage-rpc "result")))
                 (is (not (fixture-object-field call-rpc "error")))
                 (is (string= "0x"
                              (fixture-object-field call-rpc "result")))
                 (is (<= 21000
                         (hex-to-quantity
                          (fixture-object-field estimate-gas-rpc "result"))))
                 (is (stringp actual-access-list-gas-used))
                 (is actual-access-list-entry)
                 (is (member (fixture-object-field expect "storageKey")
                             actual-access-list-storage-keys
                             :test #'string=))
                 (is (string= (fixture-object-field expect "storageValue")
                              (fixture-object-field post-call-storage-rpc
                                                    "result")))
                 (is (string= transaction-hash-hex
                              (fixture-object-field receipt
                                                    "transactionHash")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field receipt "blockNumber")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field receipt "blockHash")))
                 (is (string= (fixture-object-field expect "receiptType")
                              (fixture-object-field receipt "type")))
                 (is (string= (fixture-object-field expect "receiptStatus")
                              (fixture-object-field receipt "status")))
                 (is (= (hex-to-quantity
                         (fixture-object-field expect "logCount"))
                        (length receipt-logs)))
                 (is (= 1 (length block-receipts)))
                 (is (string= transaction-hash-hex
                              (fixture-object-field block-receipt
                                                    "transactionHash")))
                 (is (= (length receipt-logs) (length block-receipt-logs)))
                 (is (= (length receipt-logs) (length filtered-logs)))
                 (is (= (length receipt-logs)
                        (length block-hash-filtered-logs)))
                 (dolist (log (list receipt-log block-receipt-log
                                    filtered-log block-hash-filtered-log
                                    log-filter-change-log))
                   (is (string= (fixture-object-field expect "logAddress")
                                (fixture-object-field log "address")))
                   (is (string= (fixture-object-field expect "logData")
                                (fixture-object-field log "data")))
                   (is (equal (list (fixture-object-field expect "logTopic"))
                              (fixture-object-field log "topics")))
                   (is (string= transaction-hash-hex
                                (fixture-object-field log "transactionHash")))
                   (is (string= (hash32-to-hex (block-hash child-block))
                                (fixture-object-field log "blockHash")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field log "blockNumber")))
                   (is (string= "0x0"
                                (fixture-object-field log
                                                      "transactionIndex")))
                   (is (string= "0x0"
                                (fixture-object-field log "logIndex"))))
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
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (= (fixture-quantity-field parent "number")
                              (fixture-object-field stdout-summary
                                                    "headNumber")))
                       (is (string= (hash32-to-hex (block-hash parent-block))
                                    (fixture-object-field stdout-summary
                                                          "headHash")))
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= side-sibling-block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "10"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "50"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "60"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest ethereum-lisp-script-serve-mode-restores-imported-database-state
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart" "jwt"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-genesis" "json"))
        (database-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-chain" "sexp"))
        (first-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-restart-first-ready" "json"))
        (first-log-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-first" "log"))
        (first-pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-first" "pid"))
        (second-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-restart-second-ready" "json"))
        (second-log-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-second" "log"))
        (second-pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-second" "pid"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-log-contract-call-with-withdrawal"))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
                (payload-case (fixture-object-field case "payload"))
                (expect (fixture-object-field case "expect"))
                (recipient (fixture-address-field expect "recipient"))
                (transaction (first (block-transactions child-block)))
                (block-hash-hex (hash32-to-hex (block-hash child-block)))
                (transaction-hash-hex
                  (hash32-to-hex (transaction-hash transaction)))
                (new-payload-body
                  (json-encode (engine-fixture-payload-request 801 payload)))
                (forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    802 (block-hash child-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 803)
                         (cons "method" "eth_blockNumber")
                         (cons "params" '()))))
                (balance-body
                  (json-encode (engine-fixture-balance-request
                                804 recipient)))
                (block-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 805)
                         (cons "method" "eth_getBlockByHash")
                         (cons "params" (list block-hash-hex :false)))))
                (receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 806)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex))))))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        (namestring genesis-path)
                        "--database"
                        (namestring database-path)
                        "--engine-port"
                        "0"
                        "--public-port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--ready-file"
                        (namestring first-ready-path)
                        "--log-file"
                        (namestring first-log-path)
                        "--pid-file"
                        (namestring first-pid-path)
                        "--max-connections"
                        "100"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file first-ready-path 10)
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
               (is (probe-file first-ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file first-ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string first-ready-path)))
                    (pid (devnet-cli-pid-file-process-id first-pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    new-payload-response
                    forkchoice-response
                    block-number-response
                    balance-response
                    receipt-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= (namestring database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (handler-case
                   (progn
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token)))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token)))
                     (setf block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-number-body)))
                     (setf balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             balance-body)))
                     (setf receipt-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             receipt-body))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (dolist (response (list new-payload-response
                                       forkchoice-response
                                       block-number-response
                                       balance-response
                                       receipt-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (receipt-rpc
                        (parse-json
                         (devnet-cli-http-body receipt-response)))
                      (receipt
                        (fixture-object-field receipt-rpc "result")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc
                                                    "result")))
                 (is (string= transaction-hash-hex
                              (fixture-object-field receipt
                                                    "transactionHash")))
                 (is (string= block-hash-hex
                              (fixture-object-field receipt
                                                    "blockHash"))))
               (multiple-value-bind (kill-stdout kill-stderr kill-status)
                   (uiop:run-program
                    (list "kill" "-TERM" (write-to-string pid))
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (= 0 kill-status))
                 (is (string= "" kill-stdout))
                 (is (string= "" kill-stderr)))
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
                   (is (search
                        "Devnet shutdown requested; closing RPC listeners."
                        stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records
                              (devnet-cli-file-forms first-log-path))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (= (block-header-number
                               (block-header parent-block))
                              (fixture-object-field stdout-summary
                                                    "headNumber")))
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "2"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "3"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))
             (is (probe-file database-path))
             (setf process
                   (uiop:launch-program
                    (list "sbcl"
                          "--script"
                          script
                          "--"
                          "devnet"
                          "--genesis"
                          (namestring genesis-path)
                          "--database"
                          (namestring database-path)
                          "--engine-port"
                          "0"
                          "--public-port"
                          "0"
                          "--ready-file"
                          (namestring second-ready-path)
                          "--log-file"
                          (namestring second-log-path)
                          "--pid-file"
                          (namestring second-pid-path)
                          "--max-connections"
                          "100"
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :stream
                    :error-output :stream))
             (unless (devnet-cli-wait-for-file second-ready-path 10)
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
                 (is (probe-file second-ready-path))
                 (is (string= "" stdout))
                 (is (string= "" stderr))))
             (when (probe-file second-ready-path)
               (let* ((ready-summary
                        (parse-json
                         (devnet-cli-file-string second-ready-path)))
                      (pid (devnet-cli-pid-file-process-id second-pid-path))
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      block-number-response
                      balance-response
                      block-by-hash-response
                      receipt-response)
                 (is (= pid (fixture-object-field ready-summary
                                                   "processId")))
                 (is (string= (namestring database-path)
                              (fixture-object-field ready-summary
                                                    "databasePath")))
                 (is (= (fixture-quantity-field payload-case "number")
                        (fixture-object-field ready-summary "headNumber")))
                 (is (string= block-hash-hex
                              (fixture-object-field ready-summary
                                                    "headHash")))
                 (handler-case
                     (progn
                       (setf block-number-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-number-body)))
                       (setf balance-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               balance-body)))
                       (setf block-by-hash-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-by-hash-body)))
                       (setf receipt-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               receipt-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (dolist (response (list block-number-response
                                         balance-response
                                         block-by-hash-response
                                         receipt-response))
                   (is (= 200 (devnet-cli-http-status response))))
                 (let* ((block-number-rpc
                          (parse-json
                           (devnet-cli-http-body block-number-response)))
                        (balance-rpc
                          (parse-json
                           (devnet-cli-http-body balance-response)))
                        (block-by-hash-rpc
                          (parse-json
                           (devnet-cli-http-body block-by-hash-response)))
                        (block-by-hash-result
                          (fixture-object-field block-by-hash-rpc "result"))
                        (receipt-rpc
                          (parse-json
                           (devnet-cli-http-body receipt-response)))
                        (receipt
                          (fixture-object-field receipt-rpc "result")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field block-number-rpc
                                                      "result")))
                   (is (string= (fixture-object-field expect
                                                      "recipientBalance")
                                (fixture-object-field balance-rpc
                                                      "result")))
                   (is (string= block-hash-hex
                                (fixture-object-field block-by-hash-result
                                                      "hash")))
                   (is (equal (list transaction-hash-hex)
                              (fixture-object-field block-by-hash-result
                                                    "transactions")))
                   (is (string= transaction-hash-hex
                                (fixture-object-field receipt
                                                      "transactionHash")))
                   (is (string= block-hash-hex
                                (fixture-object-field receipt
                                                      "blockHash"))))
                 (multiple-value-bind (kill-stdout kill-stderr kill-status)
                     (uiop:run-program
                      (list "kill" "-TERM" (write-to-string pid))
                      :output :string
                      :error-output :string
                      :ignore-error-status t)
                   (is (= 0 kill-status))
                   (is (string= "" kill-stdout))
                   (is (string= "" kill-stderr)))
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
                     (is (search
                          "Devnet shutdown requested; closing RPC listeners."
                          stderr))
                     (when (and (numberp status) (= 0 status))
                       (let* ((stdout-summary (parse-json stdout))
                              (log-records
                                (devnet-cli-file-forms second-log-path))
                              (shutdown-record
                                (find "devnet.shutdown" log-records
                                      :test #'string=
                                      :key (lambda (record)
                                             (getf record :name))))
                              (shutdown-fields
                                (getf shutdown-record :fields)))
                         (is (= pid
                                (fixture-object-field stdout-summary
                                                      "processId")))
                         (is (= (fixture-quantity-field payload-case
                                                        "number")
                                (fixture-object-field stdout-summary
                                                      "headNumber")))
                         (is (string= block-hash-hex
                                      (fixture-object-field stdout-summary
                                                            "headHash")))
                         (is shutdown-record)
                         (is (string= (fixture-object-field payload-case
                                                            "number")
                                      (cdr (assoc "headNumber"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= block-hash-hex
                                      (cdr (assoc "headHash"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "0"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "4"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "4"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list jwt-path
                          genesis-path
                          database-path
                          first-ready-path
                          first-log-path
                          first-pid-path
                          second-ready-path
                          second-log-path
                          second-pid-path))
        (when (probe-file path)
          (delete-file path)))))

(deftest ethereum-lisp-script-serve-mode-honors-runner-http-shaping
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-http-shape" "jwt"))
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-http-shape-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-http-shape" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-http-shape" "pid"))
        (coinbase "0x00000000000000000000000000000000000000cb")
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
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--authrpc.corsdomain"
                        "https://engine.runner"
                        "--http.rpcprefix"
                        "/rpc"
                        "--authrpc.vhosts"
                        "engine.runner,localhost"
                        "--http.vhosts"
                        "public.runner,localhost"
                        "--http.corsdomain"
                        "https://runner.example"
                        "--http.api"
                        "eth,net"
                        "--networkid"
                        "4242"
                        "--miner.etherbase"
                        coinbase
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "11"
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
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":601,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"shape-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-chain-body
                      "{\"jsonrpc\":\"2.0\",\"id\":602,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-body
                      "{\"jsonrpc\":\"2.0\",\"id\":603,\"method\":\"net_version\",\"params\":[]}")
                    (public-coinbase-body
                      "{\"jsonrpc\":\"2.0\",\"id\":607,\"method\":\"eth_coinbase\",\"params\":[]}")
                    (public-web3-body
                      "{\"jsonrpc\":\"2.0\",\"id\":604,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":605,\"method\":\"rpc_modules\",\"params\":[]}")
                    (public-txpool-body
                      "{\"jsonrpc\":\"2.0\",\"id\":606,\"method\":\"txpool_status\",\"params\":[]}")
                    engine-prefixed-response
                    engine-preflight-response
                    engine-root-response
                    engine-blocked-host-response
                    engine-unsupported-method-response
                    engine-unsupported-content-type-response
                    public-prefixed-response
                    public-net-response
                    public-coinbase-response
                    public-rpc-modules-response
                    public-blocked-host-response
                    public-root-response
                    public-web3-response
                    public-txpool-response
                    public-preflight-response
                    public-unsupported-method-response
                    public-unsupported-content-type-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (dolist (summary-field
                         '(("engineRpcPrefix" . "/engine")
                           ("publicRpcPrefix" . "/rpc")))
                 (is (string= (cdr summary-field)
                              (fixture-object-field
                               ready-summary
                               (car summary-field)))))
               (is (= 4242 (fixture-object-field ready-summary "networkId")))
               (is (equal '("eth" "net")
                          (fixture-object-field
                           ready-summary "publicApiModules")))
               (is (string= coinbase
                            (fixture-object-field ready-summary "coinbase")))
               (is (equal '("https://engine.runner")
                          (fixture-object-field
                           ready-summary "engineCorsOrigins")))
               (is (equal '("https://runner.example")
                          (fixture-object-field
                           ready-summary "publicCorsOrigins")))
               (is (equal '("engine.runner" "localhost")
                          (fixture-object-field ready-summary
                                                "engineVhosts")))
               (is (equal '("public.runner" "localhost")
                          (fixture-object-field ready-summary
                                                "publicVhosts")))
               (handler-case
                   (progn
                     (setf engine-prefixed-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :host "engine.runner"
                             :origin "https://engine.runner"
                             :token token)))
                     (setf engine-preflight-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-options-http-request
                             :target "/engine"
                             :host "engine.runner"
                             :origin "https://engine.runner"
                             :request-method "OPTIONS"
                             :request-headers
                             '(("Access-Control-Request-Method" . "POST")
                               ("Access-Control-Request-Headers" .
                                "authorization, content-type")))))
                     (setf engine-root-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/"
                             :host "engine.runner"
                             :token token)))
                     (setf engine-blocked-host-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :host "blocked.engine"
                             :token token)))
                     (setf engine-unsupported-method-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (with-output-to-string (stream)
                              (format stream "PUT /engine HTTP/1.1~%")
                              (format stream "Host: engine.runner~%")
                              (format stream "Content-Type: application/json~%")
                              (format stream "Authorization: Bearer ~A~%" token)
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length engine-body)
                                      engine-body))))
                     (setf engine-unsupported-content-type-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (with-output-to-string (stream)
                              (format stream "POST /engine HTTP/1.1~%")
                              (format stream "Host: engine.runner~%")
                              (format stream "Content-Type: text/plain~%")
                              (format stream "Authorization: Bearer ~A~%" token)
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length engine-body)
                                      engine-body))))
                     (setf public-prefixed-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-chain-body
                             :target "/rpc"
                             :host "public.runner"
                             :origin "https://runner.example")))
                     (setf public-net-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-coinbase-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-coinbase-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-rpc-modules-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-blocked-host-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-chain-body
                             :target "/rpc"
                             :host "blocked.public")))
                     (setf public-root-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-chain-body
                             :target "/"
                             :host "public.runner")))
                     (setf public-web3-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-web3-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-txpool-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-txpool-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-preflight-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-options-http-request
                             :target "/rpc"
                             :host "public.runner"
                             :origin "https://runner.example"
                             :request-method "OPTIONS"
                             :request-headers
                             '(("Access-Control-Request-Method" . "POST")
                               ("Access-Control-Request-Headers" .
                                "content-type")))))
                     (setf public-unsupported-method-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (with-output-to-string (stream)
                              (format stream "PUT /rpc HTTP/1.1~%")
                              (format stream "Host: public.runner~%")
                              (format stream "Content-Type: application/json~%")
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length public-chain-body)
                                      public-chain-body))))
                     (setf public-unsupported-content-type-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (with-output-to-string (stream)
                              (format stream "POST /rpc HTTP/1.1~%")
                              (format stream "Host: public.runner~%")
                              (format stream "Content-Type: text/plain~%")
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length public-chain-body)
                                      public-chain-body)))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-prefixed-response)))
               (is (search "Access-Control-Allow-Origin: https://engine.runner"
                           engine-prefixed-response))
               (is (= 204 (devnet-cli-http-status engine-preflight-response)))
               (is (search "Access-Control-Allow-Origin: https://engine.runner"
                           engine-preflight-response))
               (is (= 404 (devnet-cli-http-status engine-root-response)))
               (is (= 403
                      (devnet-cli-http-status
                       engine-blocked-host-response)))
               (is (= 405
                      (devnet-cli-http-status
                       engine-unsupported-method-response)))
               (is (search "method not allowed"
                           (devnet-cli-http-body
                            engine-unsupported-method-response)))
               (is (= 415
                      (devnet-cli-http-status
                       engine-unsupported-content-type-response)))
               (is (search "invalid content type"
                           (devnet-cli-http-body
                            engine-unsupported-content-type-response)))
               (is (= 200 (devnet-cli-http-status public-prefixed-response)))
               (is (search "Access-Control-Allow-Origin: https://runner.example"
                           public-prefixed-response))
               (is (= 200 (devnet-cli-http-status public-net-response)))
               (is (= 200 (devnet-cli-http-status public-coinbase-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-rpc-modules-response)))
               (is (= 403
                      (devnet-cli-http-status
                       public-blocked-host-response)))
               (is (= 404 (devnet-cli-http-status public-root-response)))
               (is (= 200 (devnet-cli-http-status public-web3-response)))
               (is (= 200 (devnet-cli-http-status public-txpool-response)))
               (is (= 204 (devnet-cli-http-status public-preflight-response)))
               (is (= 405
                      (devnet-cli-http-status
                       public-unsupported-method-response)))
               (is (search "method not allowed"
                           (devnet-cli-http-body
                            public-unsupported-method-response)))
               (is (= 415
                      (devnet-cli-http-status
                       public-unsupported-content-type-response)))
               (is (search "invalid content type"
                           (devnet-cli-http-body
                            public-unsupported-content-type-response)))
               (let* ((engine-json
                        (parse-json
                         (devnet-cli-http-body engine-prefixed-response)))
                      (public-json
                        (parse-json
                         (devnet-cli-http-body public-prefixed-response)))
                      (public-net-json
                        (parse-json
                         (devnet-cli-http-body public-net-response)))
                      (public-coinbase-json
                        (parse-json
                         (devnet-cli-http-body public-coinbase-response)))
                      (public-rpc-modules-json
                        (parse-json
                         (devnet-cli-http-body
                          public-rpc-modules-response)))
                      (public-web3-json
                        (parse-json
                         (devnet-cli-http-body public-web3-response)))
                      (public-txpool-json
                        (parse-json
                         (devnet-cli-http-body public-txpool-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result")))
                      (public-modules
                        (fixture-object-field
                         public-rpc-modules-json "result")))
                 (is (= 601 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 602 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result")))
                 (is (= 603 (fixture-object-field public-net-json "id")))
                 (is (string= "4242"
                              (fixture-object-field
                               public-net-json "result")))
                 (is (= 607
                        (fixture-object-field public-coinbase-json "id")))
                 (is (string= coinbase
                              (fixture-object-field
                               public-coinbase-json "result")))
                 (is (= 605
                        (fixture-object-field public-rpc-modules-json "id")))
                 (is (string= "1.0"
                              (fixture-object-field public-modules "eth")))
                 (is (string= "1.0"
                              (fixture-object-field public-modules "net")))
                 (is (string= "1.0"
                              (fixture-object-field public-modules "rpc")))
                 (is (not (fixture-object-field public-modules "txpool")))
                 (is (not (fixture-object-field public-modules "web3")))
                 (is (= 604 (fixture-object-field public-web3-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field public-web3-json "error")
                         "code")))
                 (is (= 606 (fixture-object-field public-txpool-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field public-txpool-json "error")
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
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (string= "/rpc"
                                      (fixture-object-field
                                       summary "publicRpcPrefix")))
                         (is (equal '("eth" "net")
                                    (fixture-object-field
                                     summary "publicApiModules")))
                         (is (string= coinbase
                                      (fixture-object-field
                                       summary "coinbase")))
                         (is (equal '("https://engine.runner")
                                    (fixture-object-field
                                     summary "engineCorsOrigins")))
                         (is (equal '("https://runner.example")
                                    (fixture-object-field
                                     summary "publicCorsOrigins"))))
                       (dolist (record (list ready-record shutdown-record))
                         (is record)
                         (let ((fields (getf record :fields)))
                           (is (string= "/engine"
                                        (cdr (assoc "engineRpcPrefix" fields
                                                    :test #'string=))))
                           (is (string= "/rpc"
                                        (cdr (assoc "publicRpcPrefix" fields
                                                    :test #'string=))))
                           (is (string= "eth,net"
                                        (cdr (assoc "publicApiModules" fields
                                                    :test #'string=))))
                           (is (string= coinbase
                                        (cdr (assoc "coinbase" fields
                                                    :test #'string=))))
                           (is (string= "https://engine.runner"
                                        (cdr (assoc "engineCorsOrigins" fields
                                                    :test #'string=))))
                           (is (string= "https://runner.example"
                                        (cdr (assoc "publicCorsOrigins" fields
                                                    :test #'string=))))
                           (is (string= "engine.runner,localhost"
                                        (cdr (assoc "engineVhosts" fields
                                                    :test #'string=))))
                           (is (string= "public.runner,localhost"
                                        (cdr (assoc "publicVhosts" fields
                                                    :test #'string=))))))
                       (let ((shutdown-fields
                               (getf shutdown-record :fields)))
                         (is (string= "6"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "11"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "17"
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

(deftest ethereum-lisp-script-serve-mode-honors-http-false-engine-only
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (case
          (select-engine-newpayload-v2-fixture-case
           +engine-newpayload-v2-fixture-path+
           "shanghai-one-transfer-with-withdrawal"))
        (parent-block (devnet-cli-engine-fixture-parent-block case))
        (child-block (devnet-cli-engine-fixture-child-block case))
        (payload
          (execution-payload-envelope-execution-payload
           (block-to-executable-data child-block)))
        (payload-case (fixture-object-field case "payload"))
        (block-hash-hex (hash32-to-hex (block-hash child-block)))
        (new-payload-body
          (json-encode (engine-fixture-payload-request 702 payload)))
        (forkchoice-body
          (json-encode
           (devnet-cli-engine-forkchoice-v2-request
            703
            (block-hash child-block)
            :safe (block-hash parent-block)
            :finalized (block-hash parent-block))))
        (capabilities-body
          (json-encode
           (list
            (cons "jsonrpc" "2.0")
            (cons "id" 704)
            (cons "method" "engine_exchangeCapabilities")
            (cons "params"
                  (list
                   (list
                    "engine_newPayloadV1"
                    "engine_forkchoiceUpdatedV1"
                    "engine_getPayloadV1"
                    "engine_newPayloadV2"
                    "engine_forkchoiceUpdatedV2"
                    "engine_getPayloadV2"))))))
        (transition-configuration-body
          (json-encode
           (list
            (cons "jsonrpc" "2.0")
            (cons "id" 705)
            (cons "method" "engine_exchangeTransitionConfigurationV1")
            (cons "params"
                  (list
                   (list
                    (cons "terminalTotalDifficulty" "0x0")
                    (cons "terminalBlockHash" (hash32-to-hex (zero-hash32)))
                    (cons "terminalBlockNumber" "0x0")))))))
        (transition-configuration-mismatch-body
          (json-encode
           (list
            (cons "jsonrpc" "2.0")
            (cons "id" 706)
            (cons "method" "engine_exchangeTransitionConfigurationV1")
            (cons "params"
                  (list
                   (list
                    (cons "terminalTotalDifficulty" "0x1")
                    (cons "terminalBlockHash" (hash32-to-hex (zero-hash32)))
                    (cons "terminalBlockNumber" "0x0")))))))
        (genesis-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-engine-only-genesis" "json"))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-only" "jwt"))
        (public-port nil)
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-engine-only-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-only" "log"))
	        (pid-path
	          (devnet-cli-temp-path "ethereum-lisp-script-engine-only" "pid"))
	        (database-path
	          (devnet-cli-temp-path
	           "ethereum-lisp-script-engine-only-chain" "sexp"))
	        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf public-port (devnet-cli-unused-loopback-port))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        (namestring genesis-path)
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http=false"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        (write-to-string public-port)
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--authrpc.corsdomain"
                        "https://engine.runner"
                        "--authrpc.vhosts"
                        "engine.runner,localhost"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
	                        "--pid-file"
	                        (namestring pid-path)
	                        "--database"
	                        (namestring database-path)
	                        "--max-connections"
	                        "7"
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
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (configured-public-endpoint
                      (format nil "http://127.0.0.1:~D" public-port))
                    (engine-body
                      (concatenate
                       'string
                       "{\"jsonrpc\":\"2.0\",\"id\":701,"
                       "\"method\":\"engine_getClientVersionV1\","
                       "\"params\":[{\"code\":\"runner\","
                       "\"name\":\"engine-only-script\","
                       "\"version\":\"1\",\"commit\":\"0x00000000\"}]}"))
                    blocked-engine-response
                    engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response
                    new-payload-response
                    forkchoice-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (not (devnet-cli-http-endpoint-connectable-p
                         configured-public-endpoint)))
               (handler-case
                   (progn
                     (setf blocked-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :host "engine.runner"
                             :token token)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :host "engine.runner"
                             :origin "https://engine.runner"
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token
                             :host "engine.runner"
                             :target "/engine"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 404 (devnet-cli-http-status blocked-engine-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (is (= 200 (devnet-cli-http-status forkchoice-response)))
               (is (search "Access-Control-Allow-Origin: https://engine.runner"
                           engine-response))
               (let* ((engine-rpc
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-result
                        (first (fixture-object-field engine-rpc "result")))
                      (capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc
                         "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc
                         "error"))
                      (new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus")))
                 (is (= 701 (fixture-object-field engine-rpc "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field engine-result "name")))
                 (is (= 704 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 705 (fixture-object-field
                              transition-configuration-rpc
                              "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= (hash32-to-hex (zero-hash32))
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 706 (fixture-object-field
                              transition-configuration-mismatch-rpc
                              "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status"))))
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
                                           (getf record :name))))
                            (ready-fields (getf ready-record :fields))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (not (fixture-object-field summary
                                                         "rpcEndpoint")))
                         (is (not (fixture-object-field
                                   summary "publicRpcEnabled")))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (equal '("https://engine.runner")
                                    (fixture-object-field
                                     summary "engineCorsOrigins")))
                         (is (equal '("engine.runner" "localhost")
                                    (fixture-object-field
                                     summary "engineVhosts"))))
                       (is ready-record)
                       (is shutdown-record)
                       (dolist (fields (list ready-fields shutdown-fields))
                         (is (string= engine-endpoint
                                      (cdr (assoc "engineEndpoint"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "/engine"
                                      (cdr (assoc "engineRpcPrefix"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "https://engine.runner"
                                      (cdr (assoc "engineCorsOrigins"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "engine.runner,localhost"
                                      (cdr (assoc "engineVhosts"
                                                  fields
                                                  :test #'string=))))
                         (is (string= ""
                                      (cdr (assoc "rpcEndpoint"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "false"
                                      (cdr (assoc "publicRpcEnabled"
                                                  fields
                                                  :test #'string=)))))
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "7"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "0"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "7"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (multiple-value-bind
                             (restore-stdout restore-stderr
                              restore-status)
                           (uiop:run-program
                            (list "sbcl"
	                                  "--script"
	                                  script
	                                  "--"
	                                  "devnet"
	                                  "--genesis"
	                                  (namestring genesis-path)
	                                  "--database"
	                                  (namestring database-path)
	                                  "--http=false"
	                                  "--no-serve"
	                                  "--json")
	                            :directory #P"/private/tmp/"
	                            :output :string
	                            :error-output :string
	                            :ignore-error-status t)
	                         (is (= 0 restore-status))
	                         (is (string= "" restore-stderr))
	                         (when (= 0 restore-status)
	                           (let ((restore-summary
	                                   (parse-json restore-stdout)))
	                             (is (string= (namestring database-path)
	                                          (fixture-object-field
	                                           restore-summary
	                                           "databasePath")))
	                             (is (= (fixture-quantity-field
	                                     payload-case "number")
	                                    (fixture-object-field
	                                     restore-summary "headNumber")))
	                             (is (string= block-hash-hex
	                                          (fixture-object-field
	                                           restore-summary "headHash")))
	                             (is (fixture-object-field
	                                  restore-summary "stateAvailable"))
	                             (is (not (fixture-object-field
	                                       restore-summary
	                                       "publicRpcEnabled")))
	                             (is (not (fixture-object-field
	                                       restore-summary
	                                       "rpcEndpoint")))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
	      (dolist (path (list genesis-path jwt-path ready-path log-path
	                          pid-path database-path))
	        (when (probe-file path)
	          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-split-serve-mode
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (terminal-block-hash
           "0x4444444444444444444444444444444444444444444444444444444444444444")
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 813)
             (cons "method" "engine_exchangeCapabilities")
             (cons "params"
                   (list
                    (list
                     "engine_newPayloadV1"
                     "engine_forkchoiceUpdatedV1"
                     "engine_getPayloadV1"
                     "engine_newPayloadV2"
                     "engine_forkchoiceUpdatedV2"
                     "engine_getPayloadV2"))))))
         (transition-configuration-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 814)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3039")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 815)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3038")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split" "jwt"))
        (config-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split"
                                "toml"))
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-no-command-split-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file config-path
                                       "# runner config placeholder\n")
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--config"
                        (namestring config-path)
                        "--dev"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--override.terminaltotaldifficulty"
                        "0x3039"
                        "--override.terminalblockhash"
                        terminal-block-hash
                        "--override.terminalblocknumber"
                        "66"
                        "--http"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--http.rpcprefix"
                        "/rpc"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "4"
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
                    (engine-body
                      (concatenate
                       'string
                       "{\"jsonrpc\":\"2.0\",\"id\":811,"
                       "\"method\":\"engine_getClientVersionV1\","
                       "\"params\":[{\"code\":\"runner\","
                       "\"name\":\"no-command-split-script\","
                       "\"version\":\"1\",\"commit\":\"0x00000000\"}]}"))
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":812,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":816,\"method\":\"net_version\",\"params\":[]}")
                    (public-client-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":817,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":818,\"method\":\"rpc_modules\",\"params\":[]}")
                    engine-response
                    public-response
                    public-net-version-response
                    public-client-version-response
                    public-rpc-modules-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (stringp rpc-endpoint))
               (is (fixture-object-field ready-summary "publicRpcEnabled"))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field ready-summary
                                                  "publicRpcPrefix")))
               (handler-case
                   (progn
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :target "/engine")))
                     (setf public-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-body
                             :target "/rpc")))
                     (setf public-net-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-version-body
                             :target "/rpc")))
                     (setf public-client-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-client-version-body
                             :target "/rpc")))
                     (setf public-rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-rpc-modules-body
                             :target "/rpc"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (dolist (response (list public-response
                                       public-net-version-response
                                       public-client-version-response
                                       public-rpc-modules-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((engine-rpc
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-result
                        (first (fixture-object-field engine-rpc "result")))
                      (public-rpc
                        (parse-json (devnet-cli-http-body public-response))))
                 (is (= 811 (fixture-object-field engine-rpc "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field engine-result "name")))
                 (is (= 812 (fixture-object-field public-rpc "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-rpc "result"))))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 813 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 814
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= terminal-block-hash
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 815
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
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
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field
                                       summary "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field
                                       summary "rpcEndpoint")))
                         (is (fixture-object-field
                              summary "publicRpcEnabled"))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (string= "/rpc"
                                      (fixture-object-field
                                       summary "publicRpcPrefix"))))
                       (is ready-record)
                       (is shutdown-record)
                       (is (string= engine-endpoint
                                    (cdr (assoc "engineEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= rpc-endpoint
                                    (cdr (assoc "rpcEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "true"
                                    (cdr (assoc "publicRpcEnabled"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "8"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list jwt-path config-path ready-path log-path pid-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-split-imports-payload
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (terminal-block-hash
           "0x5555555555555555555555555555555555555555555555555555555555555555")
         (case
           (select-engine-newpayload-v2-fixture-case
            +engine-newpayload-v2-fixture-path+
            "shanghai-one-transfer-with-withdrawal"))
         (parent-block (devnet-cli-engine-fixture-parent-block case))
         (child-block (devnet-cli-engine-fixture-child-block case))
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data child-block)))
         (payload-case (fixture-object-field case "payload"))
         (expect (fixture-object-field case "expect"))
         (recipient (fixture-address-field expect "recipient"))
         (block-hash-hex (hash32-to-hex (block-hash child-block)))
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 819)
             (cons "method" "engine_exchangeCapabilities")
             (cons "params"
                   (list
                    (list
                     "engine_newPayloadV1"
                     "engine_forkchoiceUpdatedV1"
                     "engine_getPayloadV1"
                     "engine_newPayloadV2"
                     "engine_forkchoiceUpdatedV2"
                     "engine_getPayloadV2"))))))
         (transition-configuration-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 820)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3039")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 825)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3038")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (new-payload-body
           (json-encode (engine-fixture-payload-request 821 payload)))
         (forkchoice-body
           (json-encode
            (devnet-cli-engine-forkchoice-v2-request
             822
             (block-hash child-block)
             :safe (block-hash parent-block)
             :finalized (block-hash parent-block))))
         (block-number-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 823)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (balance-body
           (json-encode (engine-fixture-balance-request 824 recipient)))
         (net-version-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 826)
                  (cons "method" "net_version")
                  (cons "params" '()))))
         (client-version-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 827)
                  (cons "method" "web3_clientVersion")
                  (cons "params" '()))))
         (rpc-modules-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 828)
                  (cons "method" "rpc_modules")
                  (cons "params" '()))))
         (genesis-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import-genesis" "json"))
         (jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "jwt"))
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import-ready" "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "pid"))
         (database-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "db"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--genesis"
                        (namestring genesis-path)
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--override.terminaltotaldifficulty"
                        "0x3039"
                        "--override.terminalblockhash"
                        terminal-block-hash
                        "--override.terminalblocknumber"
                        "66"
                        "--http"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--http.rpcprefix"
                        "/rpc"
                        "--database"
                        (namestring database-path)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "5"
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
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response
                    new-payload-response
                    forkchoice-response
                    block-number-response
                    balance-response
                    net-version-response
                    client-version-response
                    rpc-modules-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (stringp rpc-endpoint))
               (is (fixture-object-field ready-summary "publicRpcEnabled"))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field ready-summary
                                                  "publicRpcPrefix")))
               (is (= (block-header-number (block-header parent-block))
                      (fixture-object-field ready-summary "headNumber")))
               (handler-case
                   (progn
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :target "/engine")))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token
                             :target "/engine")))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token
                             :target "/engine")))
                     (setf block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-number-body
                             :target "/rpc")))
                     (setf balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             balance-body
                             :target "/rpc")))
                     (setf net-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             net-version-body
                             :target "/rpc")))
                     (setf client-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             client-version-body
                             :target "/rpc")))
                     (setf rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             rpc-modules-body
                             :target "/rpc"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (dolist (response (list capabilities-response
                                       transition-configuration-response
                                       transition-configuration-mismatch-response
                                       new-payload-response
                                       forkchoice-response
                                       block-number-response
                                       balance-response
                                       net-version-response
                                       client-version-response
                                       rpc-modules-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 819 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 820
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= terminal-block-hash
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 825
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (net-version-rpc
                        (parse-json
                         (devnet-cli-http-body net-version-response)))
                      (client-version-rpc
                        (parse-json
                         (devnet-cli-http-body client-version-response)))
                      (rpc-modules-rpc
                        (parse-json
                         (devnet-cli-http-body rpc-modules-response))))
                 (is (= 821 (fixture-object-field new-payload-rpc "id")))
                 (is (= 822 (fixture-object-field forkchoice-rpc "id")))
                 (is (= 823 (fixture-object-field block-number-rpc "id")))
                 (is (= 824 (fixture-object-field balance-rpc "id")))
                 (is (= 826 (fixture-object-field net-version-rpc "id")))
                 (is (= 827 (fixture-object-field client-version-rpc "id")))
                 (is (= 828 (fixture-object-field rpc-modules-rpc "id")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc "result")))
                 (is (string= "1"
                              (fixture-object-field net-version-rpc "result")))
                 (is (search "ethereum-lisp/"
                             (fixture-object-field
                              client-version-rpc "result")))
                 (is (fixture-object-field
                      (fixture-object-field rpc-modules-rpc "result")
                      "eth")))
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
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field
                                       summary "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field
                                       summary "rpcEndpoint")))
                         (is (fixture-object-field
                              summary "publicRpcEnabled"))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (string= "/rpc"
                                      (fixture-object-field
                                       summary "publicRpcPrefix")))
                         (is (string= (namestring database-path)
                                      (fixture-object-field
                                       summary "databasePath"))))
                       (is ready-record)
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "10"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (probe-file database-path))
                       (multiple-value-bind
                             (restore-stdout restore-stderr restore-status)
                           (uiop:run-program
                            (list "sbcl"
                                  "--script"
                                  script
                                  "--"
                                  "--genesis"
                                  (namestring genesis-path)
                                  "--database"
                                  (namestring database-path)
                                  "--authrpc.rpcprefix"
                                  "/engine"
                                  "--http"
                                  "--http.rpcprefix"
                                  "/rpc"
                                  "--no-serve"
                                  "--json")
                            :directory #P"/private/tmp/"
                            :output :string
                            :error-output :string
                            :ignore-error-status t)
                         (is (= 0 restore-status))
                         (is (string= "" restore-stderr))
                         (when (= 0 restore-status)
                           (let ((restore-summary
                                   (parse-json restore-stdout)))
                             (is (string= (namestring database-path)
                                          (fixture-object-field
                                           restore-summary
                                           "databasePath")))
                             (is (= (fixture-quantity-field
                                     payload-case "number")
                                    (fixture-object-field
                                     restore-summary "headNumber")))
                             (is (string= block-hash-hex
                                          (fixture-object-field
                                           restore-summary "headHash")))
                             (is (fixture-object-field
                                  restore-summary "stateAvailable"))
                             (is (fixture-object-field
                                  restore-summary "publicRpcEnabled"))
                             (is (string= "/engine"
                                          (fixture-object-field
                                           restore-summary
                                           "engineRpcPrefix")))
                             (is (string= "/rpc"
                                          (fixture-object-field
                                           restore-summary
                                           "publicRpcPrefix")))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list genesis-path jwt-path ready-path log-path pid-path
                          database-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-engine-only-serve-mode
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (terminal-block-hash
           "0x3333333333333333333333333333333333333333333333333333333333333333")
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 802)
             (cons "method" "engine_exchangeCapabilities")
             (cons "params"
                   (list
                    (list
                     "engine_newPayloadV1"
                     "engine_forkchoiceUpdatedV1"
                     "engine_getPayloadV1"
                     "engine_newPayloadV2"
                     "engine_forkchoiceUpdatedV2"
                     "engine_getPayloadV2"))))))
         (transition-configuration-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 803)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3039")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 804)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3038")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command" "jwt"))
        (public-port nil)
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-no-command-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf public-port (devnet-cli-unused-loopback-port))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--dev"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http=false"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        (write-to-string public-port)
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--override.terminaltotaldifficulty"
                        "0x3039"
                        "--override.terminalblockhash"
                        terminal-block-hash
                        "--override.terminalblocknumber"
                        "66"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "5"
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
                    (configured-public-endpoint
                      (format nil "http://127.0.0.1:~D" public-port))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (engine-body
                      (concatenate
                       'string
                       "{\"jsonrpc\":\"2.0\",\"id\":801,"
                       "\"method\":\"engine_getClientVersionV1\","
                       "\"params\":[{\"code\":\"runner\","
                       "\"name\":\"no-command-script\","
                       "\"version\":\"1\",\"commit\":\"0x00000000\"}]}"))
                    blocked-engine-response
                    engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (not (devnet-cli-http-endpoint-connectable-p
                         configured-public-endpoint)))
               (handler-case
                   (progn
                     (setf blocked-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :target "/engine"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 404 (devnet-cli-http-status blocked-engine-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (let* ((engine-rpc
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-result
                        (first (fixture-object-field engine-rpc "result"))))
                 (is (= 801 (fixture-object-field engine-rpc "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field engine-result "name"))))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 802 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 803
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= terminal-block-hash
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 804
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
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
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (not (fixture-object-field summary
                                                         "rpcEndpoint")))
                         (is (not (fixture-object-field
                                   summary "publicRpcEnabled")))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix"))))
                       (is ready-record)
                       (is shutdown-record)
                       (is (string= engine-endpoint
                                    (cdr (assoc "engineEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= ""
                                    (cdr (assoc "rpcEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "false"
                                    (cdr (assoc "publicRpcEnabled"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "0"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list jwt-path ready-path log-path pid-path))
        (when (probe-file path)
          (delete-file path))))))

(defun devnet-cli-assert-script-signal-shutdown
    (signal-name temp-name &key engine-only-p)
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-~A-ready" temp-name)
           "json"))
        (log-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-~A" temp-name)
           "log"))
        (pid-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-~A" temp-name)
           "pid"))
        (process nil))
    (unwind-protect
         (progn
           (setf process
                 (uiop:launch-program
                  (append
                   (list "sbcl"
                         "--script"
                         script
                         "--"
                         "devnet"
                         "--genesis"
                         genesis
                         "--engine-port"
                         "0"
                         "--public-port"
                         "0")
                   (when engine-only-p
                     (list "--http=false"))
                   (list "--ready-file"
                         (namestring ready-path)
                         "--log-file"
                         (namestring log-path)
                         "--pid-file"
                         (namestring pid-path)
                         "--json"))
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
                    (pid (devnet-cli-pid-file-process-id pid-path)))
               (is (= pid (fixture-object-field ready-summary "processId")))
               (multiple-value-bind (kill-stdout kill-stderr kill-status)
                   (uiop:run-program
                    (list "kill"
                          (format nil "-~A" signal-name)
                          (write-to-string pid))
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (= 0 kill-status))
                 (is (string= "" kill-stdout))
                 (is (string= "" kill-stderr)))
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
                   (is (search "Devnet shutdown requested; closing RPC listeners."
                               stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (log-names
                              (mapcar (lambda (record) (getf record :name))
                                      log-records))
                            (engine-endpoint
                              (fixture-object-field stdout-summary
                                                    "engineEndpoint"))
                            (rpc-endpoint
                              (fixture-object-field stdout-summary
                                                    "rpcEndpoint")))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (string= genesis
                                    (fixture-object-field stdout-summary
                                                          "genesisPath")))
                       (is (string= engine-endpoint
                                    (fixture-object-field ready-summary
                                                          "engineEndpoint")))
                       (if engine-only-p
                           (progn
                             (is (not rpc-endpoint))
                             (is (not (fixture-object-field
                                       ready-summary
                                       "rpcEndpoint")))
                             (is (not (fixture-object-field
                                       stdout-summary
                                       "publicRpcEnabled")))
                             (is (not (fixture-object-field
                                       ready-summary
                                       "publicRpcEnabled"))))
                           (progn
                             (is (string= rpc-endpoint
                                          (fixture-object-field ready-summary
                                                                "rpcEndpoint")))
                             (is (fixture-object-field
                                  stdout-summary
                                  "publicRpcEnabled"))
                             (is (fixture-object-field
                                  ready-summary
                                  "publicRpcEnabled"))))
                       (is (not (string= "127.0.0.1:0" engine-endpoint)))
                       (unless engine-only-p
                         (is (not (string= "127.0.0.1:0" rpc-endpoint))))
                       (is (member "devnet.ready" log-names :test #'string=))
                       (is (member "devnet.shutdown" log-names :test #'string=))
                       (dolist (log-record log-records)
                         (when (member (getf log-record :name)
                                       '("devnet.ready" "devnet.shutdown")
                                       :test #'string=)
                           (let ((fields (getf log-record :fields)))
                             (is (string= engine-endpoint
                                          (cdr (assoc "engineEndpoint"
                                                      fields
                                                      :test #'string=))))
                             (if engine-only-p
                                 (progn
                                   (is (string= ""
                                                (cdr (assoc "rpcEndpoint"
                                                            fields
                                                            :test #'string=))))
                                   (is (string= "false"
                                                (cdr (assoc
                                                      "publicRpcEnabled"
                                                      fields
                                                      :test #'string=)))))
                                 (progn
                                   (is (string= rpc-endpoint
                                                (cdr (assoc "rpcEndpoint"
                                                            fields
                                                            :test #'string=))))
                                   (is (string= "true"
                                                (cdr (assoc
                                                      "publicRpcEnabled"
                                                      fields
                                                      :test #'string=))))))
                             (is (string= (if (string= "devnet.ready"
                                                        (getf log-record :name))
                                               "ready"
                                               "shutdown")
                                          (cdr (assoc "lifecyclePhase"
                                                      fields
                                                      :test #'string=))))
                             (is (string= (write-to-string pid)
                                          (cdr (assoc "processId"
                                                      fields
                                                      :test #'string=))))
                             (is (string= "0"
                                          (cdr (assoc "totalConnections"
                                                      fields
                                                      :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))))

(deftest ethereum-lisp-script-serve-mode-handles-sigterm-shutdown
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (devnet-cli-assert-script-signal-shutdown "TERM" "sigterm"))

(deftest ethereum-lisp-script-serve-mode-handles-sigint-shutdown
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (devnet-cli-assert-script-signal-shutdown "INT" "sigint"))

(deftest ethereum-lisp-script-engine-only-serve-mode-handles-sigterm-shutdown
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (devnet-cli-assert-script-signal-shutdown
   "TERM"
   "engine-only-sigterm"
   :engine-only-p t))

(defun devnet-cli-assert-script-error-telemetry
    (args error-substring &key
          (event-name "devnet.error")
          (usage-substring "Usage: ethereum-lisp devnet"))
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-error" "log")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (append (list "sbcl" "--script" script "--")
                      args
                      (list "--log-file" (namestring log-path)))
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 1 status))
           (is (string= "" stdout))
           (is (search error-substring stderr))
           (is (search usage-substring stderr))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields))
                  (process-id
                    (parse-integer
                     (cdr (assoc "processId" fields :test #'string=))
                     :junk-allowed nil)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= event-name (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (plusp process-id))
             (is (not (= (devnet-cli-current-process-id) process-id)))
             (is (search error-substring
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= (namestring log-path)
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest ethereum-lisp-script-records-runner-error-telemetry
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (init-datadir
          (devnet-cli-temp-directory
           "ethereum-lisp-script-init-jwt-error-datadir"))
        (bad-jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-bad-jwt" "hex"))
        (missing-jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-missing-jwt" "hex"))
        (non-executable-kzg-command
          (devnet-cli-temp-path "ethereum-lisp-script-kzg-error" "sh")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file bad-jwt-path "not-hex")
           (devnet-cli-write-temp-file
            non-executable-kzg-command
            "#!/bin/sh\necho true\n")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet" "--json" "--no-serve")
            "--genesis is required")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--public-port"
                  "not-a-port"
                  "--no-serve")
            "--public-port requires an integer value")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--public-port")
            "--public-port requires a value")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--authrpc.jwtsecret"
                  (namestring bad-jwt-path)
                  "--no-serve")
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--authrpc.jwtsecret"
                  (namestring missing-jwt-path)
                  "--no-serve")
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--kzg.verifier-command"
                  (namestring non-executable-kzg-command)
                  "--no-serve")
            "KZG verifier command is not executable")
           (devnet-cli-assert-script-error-telemetry
            (list "init" "--json")
            "init requires a genesis file"
            :event-name "init.error"
            :usage-substring "Usage: ethereum-lisp init")
           (devnet-cli-assert-script-error-telemetry
            (list "init"
                  "--datadir"
                  (namestring init-datadir)
                  "--authrpc.jwtsecret"
                  (namestring bad-jwt-path)
                  "--json"
                  genesis)
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret"
            :event-name "init.error"
            :usage-substring "Usage: ethereum-lisp init")
           (devnet-cli-assert-script-error-telemetry
            (list "init"
                  "--datadir"
                  (namestring init-datadir)
                  "--authrpc.jwtsecret"
                  (namestring missing-jwt-path)
                  "--json"
                  genesis)
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret"
            :event-name "init.error"
            :usage-substring "Usage: ethereum-lisp init"))
      (when (probe-file bad-jwt-path)
        (delete-file bad-jwt-path))
      (when (probe-file missing-jwt-path)
        (delete-file missing-jwt-path))
      (when (probe-file non-executable-kzg-command)
        (delete-file non-executable-kzg-command))
      (when (probe-file init-datadir)
        (ignore-errors
          (uiop:delete-directory-tree init-datadir :validate t))))))

(deftest devnet-cli-rejects-missing-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "devnet" "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (is (search "--genesis is required"
                (get-output-stream-string errors)))))

(deftest devnet-cli-boolean-flag-values-affect-semantic-flags
  (let ((disabled
          (ethereum-lisp.cli::devnet-cli-options
           (list "devnet"
                 "--json=false"
                 "--no-serve=0"
                 "--http=true"
                 "--graphql=0"
                 "--nodiscover=0"
                 "--ipcdisable=1"
                 "--mine=false"
                 "--dev=false"
                 "--metrics=0"
                 "--pprof=false"
                 "--snapshot"
                 "false")))
         (enabled
          (ethereum-lisp.cli::devnet-cli-options
           (list "devnet"
                 "--json=1"
                 "--no-serve=true"
                 "--http=false"
                 "--dev"))))
    (is (eq :sexp (getf disabled :summary-format)))
    (is (getf disabled :serve-p))
    (is (getf disabled :public-rpc-enabled-p))
    (is (not (getf disabled :dev-mode-p)))
    (is (eq :json (getf enabled :summary-format)))
    (is (not (getf enabled :serve-p)))
    (is (not (getf enabled :public-rpc-enabled-p)))
    (is (getf enabled :dev-mode-p))))

(deftest devnet-cli-init-json-boolean-values-affect-summary-format
  (let ((disabled
          (ethereum-lisp.cli::devnet-cli-init-options
           (list "init" "--json=false")))
        (enabled
          (ethereum-lisp.cli::devnet-cli-init-options
           (list "init" "--json" "1"))))
    (is (eq :sexp (getf disabled :summary-format)))
    (is (eq :json (getf enabled :summary-format)))))

(deftest devnet-cli-init-rejects-malformed-json-boolean-before-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "init" "--json=maybe")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (let ((stderr (get-output-stream-string errors)))
      (is (search "--json boolean value must be true or false" stderr))
      (is (search "Usage: ethereum-lisp init" stderr)))))

(deftest devnet-cli-accepts-geth-style-mining-archive-and-metrics-flags
  (let ((config-path
          (devnet-cli-temp-path "ethereum-lisp-geth" "toml")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            config-path
            "# geth runner config intentionally empty for flag coverage\n")
           (let ((options
                   (ethereum-lisp.cli::devnet-cli-options
                    (list "devnet"
                          "--config"
                          (namestring config-path)
                          "--gcmode=archive"
                          "--cache"
                          "256"
                          "--cache.database=64"
                          "--cache.gc"
                          "32"
                          "--cache.trie=160"
                          "--txlookuplimit=0"
                          "--history.transactions"
                          "0"
                          "--bootnodes="
                          "--netrestrict=127.0.0.0/8"
                          "--nodekey=/tmp/ethereum-lisp-nodekey"
                          "--nodekeyhex"
                          "010203"
                          "--discovery.port=30303"
                          "--discovery.dns="
                          "--ipcpath=/tmp/ethereum-lisp.ipc"
                          "--mine=true"
                          "--miner.etherbase"
                          "0x0000000000000000000000000000000000000000"
                          "--etherbase=0x0000000000000000000000000000000000000000"
                          "--miner.gaslimit"
                          "30000000"
                          "--miner.gasprice=0"
                          "--unlock"
                          "0"
                          "--password=/tmp/password"
                          "--allow-insecure-unlock=true"
                          "--metrics=true"
                          "--metrics.addr"
                          "127.0.0.1"
                          "--metrics.port=6060"
                          "--pprof=false"
                          "--pprof.addr"
                          "127.0.0.1"
                          "--pprof.port=6061"
                          "--snapshot=false"
                          "--json"
                          "--no-serve"))))
             (is (eq :json (getf options :summary-format)))
             (is (not (getf options :serve-p)))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-accepts-geth-style-logging-flags
  (let ((options
          (ethereum-lisp.cli::devnet-cli-options
           (list "devnet"
                 "--log.file=/tmp/geth.log"
                 "--log.format"
                 "json"
                 "--log.maxsize=64"
                 "--log.maxbackups"
                 "3"
                 "--log.maxage=7"
                 "--log.compress=false"
                 "--log-file=/tmp/ethereum-lisp-events.jsonl"
                 "--json"
                 "--no-serve"))))
    (is (eq :json (getf options :summary-format)))
    (is (not (getf options :serve-p)))
    (is (string= "/tmp/ethereum-lisp-events.jsonl"
                 (getf options :log-file)))))

(deftest devnet-cli-rejects-malformed-options-before-loading-genesis
  (labels ((run-error (args)
             (let ((output (make-string-output-stream))
                   (errors (make-string-output-stream)))
               (is (= 1
                      (ethereum-lisp.cli:main
                       args
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string output)))
               (get-output-stream-string errors))))
    (is (search "--port requires an integer value"
                (run-error (list "devnet" "--port" "abc" "--no-serve"))))
    (is (search "--port requires an integer value"
                (run-error (list "devnet" "--port=abc" "--no-serve"))))
    (is (search "--port must be between 0 and 65535"
                (run-error (list "devnet" "--port" "70000" "--no-serve"))))
    (is (search "--public-port requires an integer value"
                (run-error (list "devnet"
                                 "--public-port"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--public-port must be between 0 and 65535"
                (run-error (list "devnet"
                                 "--public-port"
                                 "70000"
                                 "--no-serve"))))
    (is (search "--authrpc.rpcprefix requires a path beginning with /"
                (run-error (list "devnet"
                                 "--authrpc.rpcprefix"
                                 "engine"
                                 "--no-serve"))))
    (is (search "--authrpc.rpcprefix requires a path beginning with /"
                (run-error (list "devnet"
                                 "--authrpc.rpcprefix=engine"
                                 "--no-serve"))))
    (is (search "--http boolean value must be true or false"
                (run-error (list "devnet"
                                 "--http=maybe"
                                 "--no-serve"))))
    (is (search "--nodiscover boolean value must be true or false"
                (run-error (list "devnet"
                                 "--nodiscover"
                                 "maybe"
                                 "--no-serve"))))
    (is (search "--ws boolean value must be true or false"
                (run-error (list "devnet"
                                 "--ws=maybe"
                                 "--no-serve"))))
    (is (search "--graphql boolean value must be true or false"
                (run-error (list "devnet"
                                 "--graphql=maybe"
                                 "--no-serve"))))
    (is (search "--allow-insecure-unlock boolean value must be true or false"
                (run-error (list "devnet"
                                 "--allow-insecure-unlock=maybe"
                                 "--no-serve"))))
    (is (search "--mine boolean value must be true or false"
                (run-error (list "devnet"
                                 "--mine=maybe"
                                 "--no-serve"))))
    (is (search "--metrics boolean value must be true or false"
                (run-error (list "devnet"
                                 "--metrics=maybe"
                                 "--no-serve"))))
    (is (search "--pprof boolean value must be true or false"
                (run-error (list "devnet"
                                 "--pprof=maybe"
                                 "--no-serve"))))
    (is (search "--snapshot boolean value must be true or false"
                (run-error (list "devnet"
                                 "--snapshot=maybe"
                                 "--no-serve"))))
    (is (search "--log.compress boolean value must be true or false"
                (run-error (list "devnet"
                                 "--log.compress=maybe"
                                 "--no-serve"))))
    (is (search "--rpc.allow-unprotected-txs boolean value must be true or false"
                (run-error (list "devnet"
                                 "--rpc.allow-unprotected-txs=maybe"
                                 "--no-serve"))))
    (is (search "--override.terminaltotaldifficultypassed boolean value must be true or false"
                (run-error (list "devnet"
                                 "--override.terminaltotaldifficultypassed=maybe"
                                 "--no-serve"))))
    (is (search "--txpool.nolocals boolean value must be true or false"
                (run-error (list "devnet"
                                 "--txpool.nolocals=maybe"
                                 "--no-serve"))))
    (is (search "--txpool.locals requires a value"
                (run-error (list "devnet"
                                 "--txpool.locals"
                                 "--no-serve"))))
    (is (search "--txpool.locals requires at least one 20-byte hex address"
                (run-error (list "devnet"
                                 "--txpool.locals=,"
                                 "--no-serve"))))
    (is (search "--txpool.locals requires a 20-byte hex address"
                (run-error (list "devnet"
                                 "--txpool.locals=not-an-address"
                                 "--no-serve"))))
    (is (search "--dev boolean value must be true or false"
                (run-error (list "devnet"
                                 "--dev=maybe"
                                 "--no-serve"))))
    (is (search "--nousb boolean value must be true or false"
                (run-error (list "devnet"
                                 "--nousb=maybe"
                                 "--no-serve"))))
    (is (search "--http.rpcprefix requires a path beginning with /"
                (run-error (list "devnet"
                                 "--http.rpcprefix"
                                 "rpc"
                                 "--no-serve"))))
    (is (search "--max-connections must be non-negative"
                (run-error (list "devnet"
                                 "--max-connections"
                                 "-1"
                                 "--no-serve"))))
    (is (search "--kzg.verifier-timeout requires an integer value"
                (run-error (list "devnet"
                                 "--kzg.verifier-timeout"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--kzg-verifier-timeout must be positive"
                (run-error (list "devnet"
                                 "--kzg-verifier-timeout"
                                 "0"
                                 "--no-serve"))))
    (is (search "--prune-state-before requires an integer value"
                (run-error (list "devnet"
                                 "--prune-state-before"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--prune-state-before must be non-negative"
                (run-error (list "devnet"
                                 "--prune-state-before"
                                 "-1"
                                 "--no-serve"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis" "--no-serve"))))
    (is (search "--config requires a value"
                (run-error (list "devnet" "--config" "--no-serve"))))
    (is (search "--host requires a value"
                (run-error (list "devnet" "--host" "--no-serve"))))
    (is (search "--engine-host requires a value"
                (run-error (list "devnet" "--engine-host" "--no-serve"))))
    (is (search "--public-host requires a value"
                (run-error (list "devnet" "--public-host" "--no-serve"))))
    (is (search "--port requires a value"
                (run-error (list "devnet" "--port" "--no-serve"))))
    (is (search "--engine-port requires a value"
                (run-error (list "devnet" "--engine-port" "--no-serve"))))
    (is (search "--engine-port must be between 0 and 65535"
                (run-error (list "devnet"
                                 "--engine-port"
                                 "70000"
                                 "--no-serve"))))
    (is (search "--public-port requires a value"
                (run-error (list "devnet" "--public-port" "--no-serve"))))
    (is (search "--authrpc.rpcprefix requires a value"
                (run-error (list "devnet"
                                 "--authrpc.rpcprefix"
                                 "--no-serve"))))
    (is (search "--http.rpcprefix requires a value"
                (run-error (list "devnet"
                                 "--http.rpcprefix"
                                 "--no-serve"))))
    (is (search "--graphql.addr requires a value"
                (run-error (list "devnet"
                                 "--graphql.addr"
                                 "--no-serve"))))
    (is (search "--ws.rpcprefix requires a value"
                (run-error (list "devnet"
                                 "--ws.rpcprefix"
                                 "--no-serve"))))
    (is (search "--ipcapi requires a value"
                (run-error (list "devnet"
                                 "--ipcapi"
                                 "--no-serve"))))
    (is (search "--nodekeyhex requires a value"
                (run-error (list "devnet"
                                 "--nodekeyhex"
                                 "--no-serve"))))
    (is (search "--discovery.port requires a value"
                (run-error (list "devnet"
                                 "--discovery.port"
                                 "--no-serve"))))
    (is (search "--ipcpath requires a value"
                (run-error (list "devnet"
                                 "--ipcpath"
                                 "--no-serve"))))
    (is (search "--log.file requires a value"
                (run-error (list "devnet"
                                 "--log.file"
                                 "--no-serve"))))
    (is (search "--http.maxclients requires a value"
                (run-error (list "devnet"
                                 "--http.maxclients"
                                 "--no-serve"))))
    (is (search "--http.readtimeout requires a value"
                (run-error (list "devnet"
                                 "--http.readtimeout"
                                 "--no-serve"))))
    (is (search "--txpool.pricebump requires a value"
                (run-error (list "devnet"
                                 "--txpool.pricebump"
                                 "--no-serve"))))
    (is (search "--txpool.accountslots requires a value"
                (run-error (list "devnet"
                                 "--txpool.accountslots"
                                 "--no-serve"))))
    (is (search "--txpool.globalslots requires a value"
                (run-error (list "devnet"
                                 "--txpool.globalslots"
                                 "--no-serve"))))
    (is (search "--txpool.accountqueue requires a value"
                (run-error (list "devnet"
                                 "--txpool.accountqueue"
                                 "--no-serve"))))
    (is (search "--txpool.globalqueue requires a value"
                (run-error (list "devnet"
                                 "--txpool.globalqueue"
                                 "--no-serve"))))
    (is (search "--txpool.lifetime requires a value"
                (run-error (list "devnet"
                                 "--txpool.lifetime"
                                 "--no-serve"))))
    (is (search "--txpool.pricelimit requires a non-negative integer or hex quantity"
                (run-error (list "devnet"
                                 "--txpool.pricelimit=abc"
                                 "--no-serve"))))
    (is (search "--txpool.pricebump requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.pricebump=abc"
                                 "--no-serve"))))
    (is (search "--txpool.accountslots requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.accountslots=abc"
                                 "--no-serve"))))
    (is (search "--txpool.globalslots requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.globalslots=abc"
                                 "--no-serve"))))
    (is (search "--txpool.accountqueue requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.accountqueue=abc"
                                 "--no-serve"))))
    (is (search "--txpool.globalqueue requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.globalqueue=abc"
                                 "--no-serve"))))
    (is (search "--txpool.lifetime duration unit must be one of s, m, h, or d"
                (run-error (list "devnet"
                                 "--txpool.lifetime=1fortnight"
                                 "--no-serve"))))
    (is (search "--dev.period requires a value"
                (run-error (list "devnet"
                                 "--dev.period"
                                 "--no-serve"))))
    (is (search "--dev.gaslimit requires a value"
                (run-error (list "devnet"
                                 "--dev.gaslimit"
                                 "--no-serve"))))
    (is (search "--dev.gaslimit requires a non-negative integer or hex quantity"
                (run-error (list "devnet"
                                 "--dev.gaslimit=abc"
                                 "--no-serve"))))
    (is (search "--miner.gaslimit requires a non-negative integer or hex quantity"
                (run-error (list "devnet"
                                 "--miner.gaslimit=abc"
                                 "--no-serve"))))
    (is (search "--miner.etherbase requires a 20-byte hex address"
                (run-error (list "devnet"
                                 "--miner.etherbase=0x1234"
                                 "--no-serve"))))
    (is (search "--sepolia boolean value must be true or false"
                (run-error (list "devnet"
                                 "--sepolia=maybe"
                                 "--no-serve"))))
    (is (search "--etherbase requires a 20-byte hex address"
                (run-error (list "devnet"
                                 "--etherbase=not-address"
                                 "--no-serve"))))
    (is (search "--db.engine requires a value"
                (run-error (list "devnet"
                                 "--db.engine"
                                 "--no-serve"))))
    (is (search "--override.terminaltotaldifficulty requires a value"
                (run-error (list "devnet"
                                 "--override.terminaltotaldifficulty"
                                 "--no-serve"))))
    (is (search "--database requires a value"
                (run-error (list "devnet" "--database"))))
    (is (search "--prune-state-before requires a value"
                (run-error (list "devnet" "--prune-state-before"))))
    (is (search "--log-file requires a value"
                (run-error (list "devnet" "--log-file"))))
    (is (search "--pid-file requires a value"
                (run-error (list "devnet" "--pid-file"))))
    (is (search "Unknown option --wat"
                (run-error (list "devnet" "--wat"))))))
