(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-dispatches-devnet-help
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/ethereum-lisp.lisp"
             "--"
             "devnet"
             "--help")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: ethereum-lisp devnet" stdout))
    (is (search "--ready-file PATH" stdout))
    (is (search "--pid-file PATH" stdout))
    (is (search "--authrpc.jwtsecret PATH" stdout))
    (is (search "--http.port PORT" stdout))
    (is (search "--http.api LIST" stdout))
    (is (search "--datadir PATH" stdout))
    (is (search "--networkid ID" stdout))
    (is (search "--mainnet" stdout))
    (is (search "--sepolia" stdout))
    (is (search "--holesky" stdout))
    (is (search "--hoodi" stdout))
    (is (search "--syncmode MODE" stdout))
    (is (search "--ws.api LIST" stdout))
    (is (search "--ws.origins ORIGINS" stdout))
    (is (search "--ws.rpcprefix PATH" stdout))
    (is (search "--graphql" stdout))
    (is (search "--graphql.addr HOST" stdout))
    (is (search "--graphql.port PORT" stdout))
    (is (search "--nodiscover" stdout))
    (is (search "--ipcdisable" stdout))
    (is (search "--ipcapi LIST" stdout))
    (is (search "--verbosity LEVEL" stdout))
    (is (search "--log.file PATH" stdout))
    (is (search "--log.compress" stdout))
    (is (search "--maxpeers N" stdout))
    (is (search "--nat MODE" stdout))
    (is (search "--identity NAME" stdout))
    (is (search "--gcmode MODE" stdout))
    (is (search "--mine" stdout))
    (is (search "--miner.etherbase ADDRESS" stdout))
    (is (search "--metrics" stdout))
    (is (search "--pprof" stdout))
    (is (search "--snapshot" stdout))
    (is (search "--override.terminaltotaldifficulty TTD" stdout))
    (is (search "--override.terminaltotaldifficultypassed" stdout))
    (is (search "--override.terminalblockhash HASH" stdout))
    (is (search "--override.terminalblocknumber NUMBER" stdout))
    (is (search "--allow-insecure-unlock" stdout))
    (is (search "--http.maxclients N" stdout))
    (is (search "--http.readtimeout DURATION" stdout))
    (is (search "--http.writetimeout DURATION" stdout))
    (is (search "--http.idletimeout DURATION" stdout))
    (is (search "--kzg.verifier-command PATH" stdout))
    (is (search "--kzg.verifier-timeout SECONDS" stdout))
    (is (search "--authrpc.vhosts HOSTS" stdout))))

(deftest ethereum-lisp-script-dispatches-top-level-help-and-version
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp"))))
    (labels ((run-script (&rest args)
               (uiop:run-program
                (append (list "sbcl" "--script" script "--") args)
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)))
      (multiple-value-bind (stdout stderr status)
          (run-script)
        (is (= 0 status))
        (is (string= "" stderr))
        (is (search "Usage: ethereum-lisp COMMAND" stdout))
        (is (search "init" stdout))
        (is (search "devnet" stdout))
        (is (search "version" stdout))
        (is (search "ethereum-lisp init --help" stdout))
        (is (search "ethereum-lisp devnet --help" stdout)))
      (multiple-value-bind (stdout stderr status)
          (run-script "--help")
        (is (= 0 status))
        (is (string= "" stderr))
        (is (search "Usage: ethereum-lisp COMMAND" stdout)))
      (multiple-value-bind (stdout stderr status)
          (run-script "init" "--help")
        (is (= 0 status))
        (is (string= "" stderr))
        (is (search "Usage: ethereum-lisp init" stdout)))
      (multiple-value-bind (stdout stderr status)
          (run-script "version")
        (is (= 0 status))
        (is (string= "" stderr))
        (is (string= "ethereum-lisp/0.1.0/0x00000000"
                     (string-trim '(#\Newline #\Return) stdout))))
      (multiple-value-bind (stdout stderr status)
          (run-script "--version")
        (is (= 0 status))
        (is (string= "" stderr))
        (is (string= "ethereum-lisp/0.1.0/0x00000000"
                     (string-trim '(#\Newline #\Return) stdout)))))))

(deftest ethereum-lisp-script-dispatches-init-datadir-and-devnet-json
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (datadir
           (devnet-cli-temp-directory "ethereum-lisp-script-init-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path "ethereum-lisp-script-init-datadir-jwt"
                                 "hex"))
         (config-path
           (merge-pathnames "geth.toml" datadir))
         (ready-path
           (merge-pathnames "runner/ready.json" datadir))
         (log-path
           (merge-pathnames "runner/devnet.log" datadir))
         (pid-path
           (merge-pathnames "runner/devnet.pid" datadir)))
    (labels ((run-script (&rest args)
               (uiop:run-program
                (append (list "sbcl" "--script" script "--") args)
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)))
      (unwind-protect
           (progn
             (devnet-cli-write-temp-file explicit-jwt-path
                                         +devnet-cli-jwt-secret+)
             (devnet-cli-write-temp-file config-path
                                         (format nil
                                                 "[Eth]~%NetworkId = 7331~%~
                                                  [Node]~%DataDir = ~S~%~
                                                  JWTSecret = ~S~%"
                                                 (namestring datadir)
                                                 (namestring
                                                  explicit-jwt-path)))
             (multiple-value-bind (stdout stderr status)
                 (run-script "--config" (namestring config-path)
                             "--cache" "128"
                             "--cache.database=64"
                             "--gcmode" "archive"
                             "--state.scheme=hash"
                             "--db.engine=pebble"
                             "--snapshot=false"
                             "--networkid" "7331"
                             "--sepolia=false"
                             "--holesky=false"
                             "--authrpc.addr=127.0.0.1"
                             "--authrpc.port" "0"
                             "--authrpc.rpcprefix=/engine"
                             "--authrpc.vhosts" "engine.runner,localhost"
                             "--authrpc.corsdomain" "https://engine.example"
                             "--http"
                             "--http.addr=127.0.0.1"
                             "--http.port" "0"
                             "--http.rpcprefix=/rpc"
                             "--http.api" "eth,net"
                             "--http.vhosts" "public.runner,localhost"
                             "--http.corsdomain" "https://public.example"
                             "--ws"
                             "--ws.addr=127.0.0.1"
                             "--ws.port" "0"
                             "--ws.rpcprefix=/ws"
                             "--ipcapi=eth,net,web3"
                             "--graphql=false"
                             "--override.terminaltotaldifficulty" "0"
                             "--override.terminaltotaldifficultypassed=false"
                             "--override.terminalblockhash=0x0000000000000000000000000000000000000000000000000000000000000000"
                             "--override.terminalblocknumber" "0"
                             "--ready-file" (namestring ready-path)
                             "--log-file" (namestring log-path)
                             "--pid-file" (namestring pid-path)
                             "--max-connections" "0"
                             "--prune-state-before" "0"
                             "--no-serve"
                             "init"
                             "--json"
                             genesis)
               (is (= 0 status))
               (is (string= "" stderr))
               (let* ((summary (parse-json stdout))
                      (ready-summary
                        (parse-json (devnet-cli-file-string ready-path)))
                      (pid (devnet-cli-pid-file-process-id pid-path))
                      (log-records (devnet-cli-file-forms log-path))
                      (ready-record (first log-records))
                      (shutdown-record (second log-records))
                      (ready-fields (getf ready-record :fields))
                      (shutdown-fields (getf shutdown-record :fields)))
                 (is (= 1337 (fixture-object-field summary "chainId")))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field summary
                                                    "jwtSecretPath")))
                 (is (eq t (fixture-object-field summary "authRequired")))
                 (is (probe-file ready-path))
                 (is (probe-file log-path))
                 (is (probe-file pid-path))
                 (is (= 2 (length log-records)))
                 (is (= pid (fixture-object-field summary "processId")))
                 (is (= pid (fixture-object-field ready-summary
                                                  "processId")))
                 (is (string= genesis
                              (fixture-object-field summary "genesisPath")))
                 (is (string= genesis
                              (fixture-object-field ready-summary
                                                    "genesisPath")))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field ready-summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field ready-summary
                                                    "jwtSecretPath")))
                 (is (eq t (fixture-object-field ready-summary
                                                  "authRequired")))
                 (is (string= (namestring log-path)
                              (fixture-object-field summary "logPath")))
                 (is (string= (namestring log-path)
                              (fixture-object-field ready-summary "logPath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field summary
                                                    "pidFilePath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field ready-summary
                                                    "pidFilePath")))
                 (is (eq :log (getf ready-record :kind)))
                 (is (eq :info (getf ready-record :value)))
                 (is (string= "init.ready" (getf ready-record :name)))
                 (is (string= "ready"
                              (cdr (assoc "lifecyclePhase"
                                          ready-fields
                                          :test #'string=))))
                 (is (string= (write-to-string pid)
                              (cdr (assoc "processId"
                                          ready-fields
                                          :test #'string=))))
                 (is (string= (namestring log-path)
                              (cdr (assoc "logPath"
                                          ready-fields
                                          :test #'string=))))
                 (is (string= (namestring pid-path)
                              (cdr (assoc "pidFilePath"
                                          ready-fields
                                          :test #'string=))))
                 (is (string= (namestring datadir-database-path)
                              (cdr (assoc "databasePath"
                                          ready-fields
                                          :test #'string=))))
                 (is (eq :log (getf shutdown-record :kind)))
                 (is (eq :info (getf shutdown-record :value)))
                 (is (string= "init.shutdown"
                              (getf shutdown-record :name)))
                 (is (string= "shutdown"
                              (cdr (assoc "lifecyclePhase"
                                          shutdown-fields
                                          :test #'string=))))
                 (is (string= (write-to-string pid)
                             (cdr (assoc "processId"
                                          shutdown-fields
                                          :test #'string=))))))
             (is (probe-file datadir-genesis-path))
             (is (probe-file datadir-database-path))
             (is (probe-file datadir-jwt-path))
             (is (string= +devnet-cli-jwt-secret+
                          (string-trim
                           '(#\Space #\Tab #\Newline #\Return)
                           (devnet-cli-file-string datadir-jwt-path))))
             (multiple-value-bind (stdout stderr status)
                 (run-script "--identity" "init"
                             "--config" (namestring config-path)
                             "--hoodi=false"
                             "devnet"
                             "--json"
                             "--no-serve")
               (is (= 0 status))
               (is (string= "" stderr))
               (let ((summary (parse-json stdout)))
                 (is (= 1337 (fixture-object-field summary "chainId")))
                 (is (string= (namestring (truename datadir-genesis-path))
                              (fixture-object-field summary "genesisPath")))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath"))))))
        (when (probe-file datadir-genesis-path)
          (delete-file datadir-genesis-path))
        (when (probe-file datadir-database-path)
          (delete-file datadir-database-path))
        (when (probe-file datadir-jwt-path)
          (delete-file datadir-jwt-path))
        (when (probe-file explicit-jwt-path)
          (delete-file explicit-jwt-path))
        (when (probe-file config-path)
          (delete-file config-path))
        (when (probe-file ready-path)
          (delete-file ready-path))
        (when (probe-file log-path)
          (delete-file log-path))
        (when (probe-file pid-path)
          (delete-file pid-path))))))

(deftest ethereum-lisp-script-dispatches-devnet-no-serve-json
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/ethereum-lisp.lisp"
             "--"
             "devnet"
             "--genesis"
             +devnet-cli-genesis-fixture+
             "--json"
             "--no-serve")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let ((summary (parse-json stdout)))
        (is (string= +devnet-cli-genesis-fixture+
                     (fixture-object-field summary "genesisPath")))
        (is (string= "127.0.0.1:8551"
                     (fixture-object-field summary "engineEndpoint")))
        (is (string= "127.0.0.1:8545"
                     (fixture-object-field summary "rpcEndpoint")))
        (is (eq nil (fixture-object-field summary "authRequired")))
        (is (eq t (fixture-object-field summary "stateAvailable")))))))

(deftest ethereum-lisp-script-serve-mode-boots-initialized-datadir
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (datadir
           (devnet-cli-temp-directory "ethereum-lisp-script-serve-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-serve-datadir-explicit-jwt"
            "hex"))
         (ready-path
           (devnet-cli-temp-path "ethereum-lisp-script-serve-datadir-ready"
                                 "json"))
         (log-path
           (devnet-cli-temp-path "ethereum-lisp-script-serve-datadir" "log"))
         (pid-path
           (devnet-cli-temp-path "ethereum-lisp-script-serve-datadir" "pid"))
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
                                                    "jwtSecretPath")))
                 (is (eq t (fixture-object-field summary
                                                  "authRequired"))))))
           (is (probe-file datadir-genesis-path))
           (is (probe-file datadir-database-path))
           (is (probe-file datadir-jwt-path))
           (is (string= +devnet-cli-jwt-secret+
                        (string-trim
                         '(#\Space #\Tab #\Newline #\Return)
                         (devnet-cli-file-string datadir-jwt-path))))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--datadir"
                        (namestring datadir)
                        "devnet"
                        "--json"
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
                        "2")
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
                      "{\"jsonrpc\":\"2.0\",\"id\":701,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"datadir-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":702,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-body
                      "{\"jsonrpc\":\"2.0\",\"id\":703,\"method\":\"net_version\",\"params\":[]}")
                    (jwt-secret
                      (hex-to-bytes
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (devnet-cli-file-string
                                     datadir-jwt-path))))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    engine-unauthenticated-response
                    engine-response
                    public-response
                    public-net-response)
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
               (handler-case
                   (progn
                     (setf engine-unauthenticated-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request engine-body)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token)))
                     (setf public-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request public-body)))
                     (setf public-net-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                             (devnet-cli-json-rpc-http-request
                              public-net-body))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 401
                      (devnet-cli-http-status engine-unauthenticated-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status public-response)))
               (is (= 200 (devnet-cli-http-status public-net-response)))
               (let* ((engine-json
                        (parse-json (devnet-cli-http-body engine-response)))
                      (public-json
                        (parse-json (devnet-cli-http-body public-response)))
                      (public-net-json
                        (parse-json
                         (devnet-cli-http-body public-net-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result"))))
                 (is (= 701 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 702 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result")))
                 (is (= 703 (fixture-object-field public-net-json "id")))
                 (is (string= "1337"
                              (fixture-object-field public-net-json
                                                    "result"))))
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
                       (is (string= (namestring
                                     (truename datadir-genesis-path))
                                    (fixture-object-field stdout-summary
                                                          "genesisPath")))
                       (is (string= (namestring datadir-database-path)
                                    (fixture-object-field stdout-summary
                                                          "databasePath")))
                       (is (eq t (fixture-object-field stdout-summary
                                                       "authRequired")))
                       (is (string= (namestring datadir-jwt-path)
                                    (fixture-object-field stdout-summary
                                                          "jwtSecretPath")))
                       (is (string= engine-endpoint
                                    (fixture-object-field stdout-summary
                                                          "engineEndpoint")))
                       (is (string= rpc-endpoint
                                    (fixture-object-field stdout-summary
                                                          "rpcEndpoint")))
                       (is shutdown-record)
                       (is (string= "2"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "2"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
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
                  (cons "params" '()))))
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

(deftest ethereum-lisp-script-no-command-datadir-engine-only-serve-mode
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-script-no-command-datadir-engine-only"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-explicit-jwt"
            "hex"))
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 714)
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
             (cons "id" 715)
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
             (cons "id" 716)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x1")
                     (cons "terminalBlockHash"
                           (hash32-to-hex (zero-hash32)))
                     (cons "terminalBlockNumber" "0x0")))))))
         (public-port nil)
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-ready"
            "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only" "pid"))
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
           (setf public-port (devnet-cli-unused-loopback-port))
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
                        "--http=false"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        (write-to-string public-port)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "7")
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
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":713,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"no-command-datadir-engine-only\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    blocked-engine-response
                    unauthenticated-engine-response
                    invalid-auth-engine-response
                    engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
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
               (is (= 401
                      (devnet-cli-http-status
                       unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (let* ((engine-json
                        (parse-json (devnet-cli-http-body engine-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result"))))
                 (is (= 713 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name"))))
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
                 (is (= 714 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 715
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
                 (is (= 716
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
                                (fixture-object-field summary
                                                      "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field summary
                                                            "engineEndpoint")))
                         (is (not (fixture-object-field summary
                                                         "rpcEndpoint")))
                         (is (not (fixture-object-field
                                   summary "publicRpcEnabled")))
                         (is (string= (namestring datadir-database-path)
                                      (fixture-object-field summary
                                                            "databasePath")))
                         (is (eq t (fixture-object-field summary
                                                          "authRequired")))
                         (is (string= "/engine"
                                      (fixture-object-field summary
                                                            "engineRpcPrefix"))))
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

(deftest ethereum-lisp-script-no-command-datadir-engine-only-imports-payload
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
         (init-genesis-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import-genesis"
            "json"))
         (datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-script-no-command-datadir-engine-only-import"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import-explicit-jwt"
            "hex"))
         (public-port nil)
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import-ready"
            "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-datadir-engine-only-import" "pid"))
         (new-payload-body
           (json-encode (engine-fixture-payload-request 741 payload)))
         (forkchoice-body
           (json-encode
            (devnet-cli-engine-forkchoice-v2-request
             742
             (block-hash child-block)
             :safe (block-hash parent-block)
             :finalized (block-hash parent-block))))
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
           (setf public-port (devnet-cli-unused-loopback-port))
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
                        "--http=false"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        (write-to-string public-port)
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
                    (configured-public-endpoint
                      (format nil "http://127.0.0.1:~D" public-port))
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
                    forkchoice-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
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
               (is (= (block-header-number (block-header parent-block))
                      (fixture-object-field ready-summary "headNumber")))
               (is (not (devnet-cli-http-endpoint-connectable-p
                         configured-public-endpoint)))
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
                             :token token))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 401
                      (devnet-cli-http-status
                       unauthenticated-engine-response)))
               (is (= 401
                      (devnet-cli-http-status invalid-auth-engine-response)))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (is (= 200 (devnet-cli-http-status forkchoice-response)))
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
                         "payloadStatus")))
                 (is (= 741 (fixture-object-field new-payload-rpc "id")))
                 (is (= 742 (fixture-object-field forkchoice-rpc "id")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status"))))
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
                         (is (not (fixture-object-field summary
                                                         "rpcEndpoint")))
                         (is (not (fixture-object-field
                                   summary "publicRpcEnabled")))
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
                       (is (string= "0"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
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
                             (is (not (fixture-object-field
                                       restore-summary
                                       "publicRpcEnabled")))
                             (is (not (fixture-object-field
                                       restore-summary
                                       "rpcEndpoint")))
                             (is (string= "/engine"
                                          (fixture-object-field
                                           restore-summary
                                           "engineRpcPrefix")))))))))))))
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

(deftest ethereum-lisp-script-is-cwd-independent-for-runner-artifacts
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script" "pid")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
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
                    "8546"
                    "--ready-file"
                    (namestring ready-path)
                    "--log-file"
                    (namestring log-path)
                    "--pid-file"
                    (namestring pid-path)
                    "--json"
                    "--no-serve")
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((stdout-summary (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records)))
               (dolist (summary (list stdout-summary ready-summary))
                 (is (string= genesis
                              (fixture-object-field summary "genesisPath")))
                 (is (= pid (fixture-object-field summary "processId")))
                 (is (string= "127.0.0.1:0"
                              (fixture-object-field summary
                                                    "engineEndpoint")))
                 (is (string= "127.0.0.1:8546"
                              (fixture-object-field summary "rpcEndpoint")))
                 (is (string= (namestring log-path)
                              (fixture-object-field summary "logPath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field summary "pidFilePath")))
                 (is (eq t
                         (fixture-object-field summary "stateAvailable"))))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (let ((fields (getf log-record :fields)))
                   (is (string= "127.0.0.1:0"
                                (cdr (assoc "engineEndpoint" fields
                                            :test #'string=))))
                   (is (string= "127.0.0.1:8546"
                                (cdr (assoc "rpcEndpoint" fields
                                            :test #'string=))))
                   (is (string= (if (string= "devnet.ready"
                                              (getf log-record :name))
                                     "ready"
                                     "shutdown")
                                (cdr (assoc "lifecyclePhase" fields
                                            :test #'string=))))
                   (is (string= (write-to-string pid)
                                (cdr (assoc "processId" fields
                                            :test #'string=))))
                   (is (string= (namestring log-path)
                                (cdr (assoc "logPath" fields
                                            :test #'string=))))
                   (is (string= (namestring pid-path)
                                (cdr (assoc "pidFilePath" fields
                                            :test #'string=)))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest ethereum-lisp-script-serve-mode-writes-runner-artifacts
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve" "pid")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
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
                    "0"
                    "--ready-file"
                    (namestring ready-path)
                    "--log-file"
                    (namestring log-path)
                    "--pid-file"
                    (namestring pid-path)
                    "--max-connections"
                    "0"
                    "--json")
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (when (and (not (= 0 status))
                      (search "Operation not permitted" stderr))
             (skip-test "Local socket bind is not permitted in this sandbox"))
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((stdout-summary (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records))
                    (engine-endpoint
                      (fixture-object-field stdout-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field stdout-summary "rpcEndpoint")))
               (is (string= genesis
                            (fixture-object-field stdout-summary
                                                  "genesisPath")))
               (is (= pid (fixture-object-field stdout-summary "processId")))
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= engine-endpoint
                            (fixture-object-field ready-summary
                                                  "engineEndpoint")))
               (is (string= rpc-endpoint
                            (fixture-object-field ready-summary
                                                  "rpcEndpoint")))
               (is (not (string= "127.0.0.1:0" engine-endpoint)))
               (is (not (string= "127.0.0.1:0" rpc-endpoint)))
               (is (search "127.0.0.1:" engine-endpoint))
               (is (search "127.0.0.1:" rpc-endpoint))
               (dolist (summary (list stdout-summary ready-summary))
                 (is (string= (namestring log-path)
                              (fixture-object-field summary "logPath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field summary "pidFilePath")))
                 (is (eq t
                         (fixture-object-field summary "stateAvailable"))))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (when (member (getf log-record :name)
                               '("devnet.ready" "devnet.shutdown")
                               :test #'string=)
                   (let ((fields (getf log-record :fields)))
                     (is (string= engine-endpoint
                                  (cdr (assoc "engineEndpoint" fields
                                              :test #'string=))))
                     (is (string= rpc-endpoint
                                  (cdr (assoc "rpcEndpoint" fields
                                              :test #'string=))))
                     (is (string= (if (string= "devnet.ready"
                                                (getf log-record :name))
                                       "ready"
                                       "shutdown")
                                  (cdr (assoc "lifecyclePhase" fields
                                              :test #'string=))))
                     (is (string= "0"
                                  (cdr (assoc "engineConnections" fields
                                              :test #'string=))))
                     (is (string= "0"
                                  (cdr (assoc "publicConnections" fields
                                              :test #'string=))))
                     (is (string= "0"
                                  (cdr (assoc "totalConnections" fields
                                              :test #'string=))))
                     (is (string= (write-to-string pid)
                                  (cdr (assoc "processId" fields
                                              :test #'string=))))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(defun devnet-cli-wait-for-file (path timeout-seconds)
  (loop repeat (* timeout-seconds 20)
        when (probe-file path)
          return t
        do (sleep 0.05)
        finally (return nil)))

(defun devnet-cli-wait-process-exit (process timeout-seconds)
  (loop repeat (* timeout-seconds 20)
        unless (uiop:process-alive-p process)
          return (uiop:wait-process process)
        do (sleep 0.05)
        finally (return :timeout)))

