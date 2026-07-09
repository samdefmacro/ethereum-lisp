(in-package #:ethereum-lisp.test)

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

