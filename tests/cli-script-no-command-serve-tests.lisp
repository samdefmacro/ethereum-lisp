(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-no-command-boots-initialized-datadir
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-script-no-command-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-explicit-jwt"
            "hex"))
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 713)
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
             (cons "id" 714)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x0")
                     (cons "terminalBlockHash"
                           (hash32-to-hex (zero-hash32)))
                     (cons "terminalBlockNumber" "0x0")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 715)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x1")
                     (cons "terminalBlockHash"
                           (hash32-to-hex (zero-hash32)))
                     (cons "terminalBlockNumber" "0x0")))))))
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-ready" "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir" "pid"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file explicit-jwt-path
                                       +devnet-cli-jwt-secret+)
           (multiple-value-bind (init-stdout init-stderr init-status)
               (uiop:run-program
                (list "sbcl"
                      "--script"
                      script
                      "--"
                      "--datadir"
                      (namestring datadir)
                      "--authrpc.jwtsecret"
                      (namestring explicit-jwt-path)
                      "init"
                      "--json"
                      genesis)
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)
             (is (= 0 init-status))
             (is (string= "" init-stderr))
             (when (= 0 init-status)
               (let ((summary (parse-json init-stdout)))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field summary
                                                    "jwtSecretPath"))))))
           (is (probe-file datadir-genesis-path))
           (is (probe-file datadir-database-path))
           (is (probe-file datadir-jwt-path))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--datadir"
                        (namestring datadir)
                        "--json"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.rpcprefix"
                        "/engine"
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
                        "6")
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
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":711,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"no-command-datadir\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":712,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":716,\"method\":\"net_version\",\"params\":[]}")
                    (public-client-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":717,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":718,\"method\":\"rpc_modules\",\"params\":[]}")
                    (public-syncing-body
                      "{\"jsonrpc\":\"2.0\",\"id\":719,\"method\":\"eth_syncing\",\"params\":[]}")
                    (public-engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":720,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    (jwt-secret
                      (hex-to-bytes
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (devnet-cli-file-string
                                     datadir-jwt-path))))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (wrong-token
                      (engine-rpc-make-jwt-token
                       (hex-to-bytes
                        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
                       0))
                    engine-response
                    unauthenticated-engine-response
                    invalid-auth-engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response
                    public-response
                    public-net-version-response
                    public-client-version-response
                    public-rpc-modules-response
                    public-syncing-response
                    public-engine-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= (namestring (truename datadir-genesis-path))
                            (fixture-object-field ready-summary
                                                  "genesisPath")))
               (is (string= (namestring datadir-database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (string= (namestring datadir-jwt-path)
                            (fixture-object-field ready-summary
                                                  "jwtSecretPath")))
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
                             :target "/engine"
                             :token token)))
                     (setf unauthenticated-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine")))
                     (setf invalid-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :token wrong-token)))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :target "/engine"
                             :token token)))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :target "/engine"
                             :token token)))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :target "/engine"
                             :token token)))
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
                             :target "/rpc")))
                     (setf public-syncing-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-syncing-body
                             :target "/rpc")))
                     (setf public-engine-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-engine-body
                             :target "/rpc"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 401
                      (devnet-cli-http-status
                       unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (dolist (response
                        (list capabilities-response
                              transition-configuration-response
                              transition-configuration-mismatch-response
                              public-response
                              public-net-version-response
                              public-client-version-response
                              public-rpc-modules-response
                              public-syncing-response
                              public-engine-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((engine-json
                        (parse-json (devnet-cli-http-body engine-response)))
                      (public-json
                        (parse-json (devnet-cli-http-body public-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result"))))
                 (is (= 711 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 712 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result"))))
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
                         transition-configuration-mismatch-rpc "error"))
                      (public-net-version-rpc
                        (parse-json
                         (devnet-cli-http-body public-net-version-response)))
                      (public-client-version-rpc
                        (parse-json
                         (devnet-cli-http-body
                          public-client-version-response)))
                      (public-rpc-modules-rpc
                        (parse-json
                         (devnet-cli-http-body public-rpc-modules-response)))
                      (public-syncing-rpc
                        (parse-json
                         (devnet-cli-http-body public-syncing-response)))
                      (public-engine-rpc
                        (parse-json
                         (devnet-cli-http-body public-engine-response)))
                      (public-engine-error
                        (fixture-object-field public-engine-rpc "error")))
                 (is (= 713 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 714
                        (fixture-object-field
                         transition-configuration-rpc "id")))
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
                 (is (= 715
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message")))
                 (is (= 716
                        (fixture-object-field public-net-version-rpc "id")))
                 (is (string= "1337"
                              (fixture-object-field
                               public-net-version-rpc "result")))
                 (is (= 717
                        (fixture-object-field
                         public-client-version-rpc "id")))
                 (is (search "ethereum-lisp/"
                             (fixture-object-field
                              public-client-version-rpc "result")))
                 (is (= 718
                        (fixture-object-field public-rpc-modules-rpc "id")))
                 (is (fixture-object-field
                      (fixture-object-field
                       public-rpc-modules-rpc "result")
                      "eth"))
                 (is (= 719
                        (fixture-object-field public-syncing-rpc "id")))
                 (is (not (fixture-object-field public-syncing-rpc
                                                "result")))
                 (is (= 720
                        (fixture-object-field public-engine-rpc "id")))
                 (is (= -32601
                        (fixture-object-field public-engine-error "code"))))
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
                       (is (string= engine-endpoint
                                    (fixture-object-field stdout-summary
                                                          "engineEndpoint")))
                       (is (string= rpc-endpoint
                                    (fixture-object-field stdout-summary
                                                          "rpcEndpoint")))
                       (is (string= (namestring datadir-database-path)
                                    (fixture-object-field stdout-summary
                                                          "databasePath")))
                       (is (eq t (fixture-object-field stdout-summary
                                                       "authRequired")))
                       (is shutdown-record)
                       (is (string= "6"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "6"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "12"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list datadir-genesis-path
                          datadir-database-path
                          datadir-jwt-path
                          explicit-jwt-path
                          ready-path
                          log-path
                          pid-path))
        (when (probe-file path)
          (delete-file path))))))

