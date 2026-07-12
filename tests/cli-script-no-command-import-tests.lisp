(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-no-command-datadir-imports-payload
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
         (expect (fixture-object-field case "expect"))
         (recipient (fixture-address-field expect "recipient"))
         (block-hash-hex (hash32-to-hex (block-hash child-block)))
         (init-genesis-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import-genesis"
            "json"))
         (datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-script-no-command-datadir-import"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import-explicit-jwt"
            "hex"))
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import-ready"
            "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-import" "pid"))
         (new-payload-body
           (json-encode (engine-fixture-payload-request 731 payload)))
         (forkchoice-body
           (json-encode
            (devnet-cli-engine-forkchoice-v2-request
             732
             (block-hash child-block)
             :safe (block-hash parent-block)
             :finalized (block-hash parent-block))))
         (block-number-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 733)
                  (cons "method" "eth_blockNumber")
                  (cons "params" #()))))
         (balance-body
           (json-encode (engine-fixture-balance-request 734 recipient)))
         (public-syncing-body
           "{\"jsonrpc\":\"2.0\",\"id\":735,\"method\":\"eth_syncing\",\"params\":[]}")
         (public-engine-body
           "{\"jsonrpc\":\"2.0\",\"id\":736,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            init-genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
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
                      (namestring init-genesis-path))
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
                 (test-launch-program
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
                        "4")
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
                    unauthenticated-engine-response
                    invalid-auth-engine-response
                    new-payload-response
                    forkchoice-response
                    block-number-response
                    balance-response
                    public-syncing-response
                    public-engine-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (stringp rpc-endpoint))
               (is (fixture-object-field ready-summary "publicRpcEnabled"))
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
               (is (= (block-header-number (block-header parent-block))
                      (fixture-object-field ready-summary "headNumber")))
               (handler-case
                   (progn
                     (setf unauthenticated-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :target "/engine")))
                     (setf invalid-auth-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :target "/engine"
                             :token wrong-token)))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :target "/engine"
                             :token token)))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :target "/engine"
                             :token token)))
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
               (is (= 401
                      (devnet-cli-http-status
                       unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (dolist (response (list new-payload-response
                                       forkchoice-response
                                       block-number-response
                                       balance-response
                                       public-syncing-response
                                       public-engine-response))
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
                      (public-syncing-rpc
                        (parse-json
                         (devnet-cli-http-body public-syncing-response)))
                      (public-engine-rpc
                        (parse-json
                         (devnet-cli-http-body public-engine-response)))
                      (public-engine-error
                        (fixture-object-field public-engine-rpc "error")))
                 (is (= 731 (fixture-object-field new-payload-rpc "id")))
                 (is (= 732 (fixture-object-field forkchoice-rpc "id")))
                 (is (= 733 (fixture-object-field block-number-rpc "id")))
                 (is (= 734 (fixture-object-field balance-rpc "id")))
                 (is (= 735 (fixture-object-field public-syncing-rpc "id")))
                 (is (= 736 (fixture-object-field public-engine-rpc "id")))
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
                 (is (not (fixture-object-field public-syncing-rpc
                                                "result")))
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
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (string= engine-endpoint
                                      (fixture-object-field summary
                                                            "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field summary
                                                            "rpcEndpoint")))
                         (is (string= (namestring datadir-database-path)
                                      (fixture-object-field summary
                                                            "databasePath"))))
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
                                                :test #'string=))))
                       (is (probe-file datadir-database-path))
                       (multiple-value-bind
                             (restore-stdout restore-stderr restore-status)
                           (uiop:run-program
                            (list "sbcl"
                                  "--script"
                                  script
                                  "--"
                                  "--datadir"
                                  (namestring datadir)
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
                             (is (string= (namestring datadir-database-path)
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
      (dolist (path (list init-genesis-path
                          datadir-genesis-path
                          datadir-database-path
                          datadir-jwt-path
                          explicit-jwt-path
                          ready-path
                          log-path
                          pid-path))
        (when (probe-file path)
          (delete-file path))))))

