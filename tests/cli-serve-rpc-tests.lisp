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

