(in-package #:ethereum-lisp.test)

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
                  (cons "params" #()))))
         (balance-body
           (json-encode (engine-fixture-balance-request 824 recipient)))
         (net-version-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 826)
                  (cons "method" "net_version")
                  (cons "params" #()))))
         (client-version-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 827)
                  (cons "method" "web3_clientVersion")
                  (cons "params" #()))))
         (rpc-modules-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 828)
                  (cons "method" "rpc_modules")
                  (cons "params" #()))))
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
                 (test-launch-program
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

