(in-package #:ethereum-lisp.test)

(deftest devnet-cli-main-json-summary-and-ready-file
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex"))
        (ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (pid-path (devnet-cli-temp-path "ethereum-lisp-devnet" "pid"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file ready-path "stale readiness")
           (devnet-cli-write-temp-file pid-path "0")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-port" "0"
                         "--public-port" "8546"
                         "--jwt-secret" (namestring jwt-path)
                         "--txpool.rejournal" "2m"
                         "--ready-file" (namestring ready-path)
                         "--pid-file" (namestring pid-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path))))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (= 1337 (fixture-object-field summary "chainId")))
               (is (= 0 (fixture-object-field summary "headNumber")))
               (is (null (fixture-object-field summary "safeNumber")))
               (is (null (fixture-object-field summary "safeHash")))
               (is (null (fixture-object-field summary "finalizedNumber")))
               (is (null (fixture-object-field summary "finalizedHash")))
               (is (string= "127.0.0.1:0"
                            (fixture-object-field summary "engineEndpoint")))
               (is (string= "127.0.0.1:8546"
                            (fixture-object-field summary "rpcEndpoint")))
               (is (equal (devnet-cli-current-process-id)
                          (fixture-object-field summary "processId")))
               (is (string= (namestring pid-path)
                            (fixture-object-field summary "pidFilePath")))
               (is (eq t (fixture-object-field summary "authRequired")))
               (is (= 120
                      (fixture-object-field summary "txpoolRejournalSeconds")))
               (is (eq t (fixture-object-field summary "stateAvailable")))
               (is (string= (namestring jwt-path)
                            (fixture-object-field summary "jwtSecretPath"))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-creates-artifact-parent-directories
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-artifact-parents"))
         (ready-path
           (merge-pathnames "ready/nested/devnet-ready.json" root))
         (log-path
           (merge-pathnames "logs/nested/devnet.log" root))
         (pid-path
           (merge-pathnames "pid/nested/devnet.pid" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--ready-file" (namestring ready-path)
                         "--log-file" (namestring log-path)
                         "--pid-file" (namestring pid-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= (namestring log-path)
                            (fixture-object-field summary "logPath")))
               (is (string= (namestring pid-path)
                            (fixture-object-field summary "pidFilePath"))))
             (is (= 2 (length log-records)))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-accepts-explicit-engine-endpoint-options
  (let ((ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-host" "192.0.2.10"
                         "--engine-port" "9551"
                         "--public-host" "192.0.2.11"
                         "--public-port" "9545"
                         "--ready-file" (namestring ready-path)
                         "--log-file" (namestring log-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= "192.0.2.10:9551"
                            (fixture-object-field summary "engineEndpoint")))
               (is (string= "192.0.2.11:9545"
                            (fixture-object-field summary "rpcEndpoint"))))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (string= "192.0.2.10:9551"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "192.0.2.11:9545"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest devnet-cli-main-accepts-geth-style-runner-aliases
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex"))
        (config-path (devnet-cli-temp-path "ethereum-lisp-devnet-geth" "toml"))
        (ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string
             "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
             stream))
           (devnet-cli-write-temp-file
            config-path
            "# geth runner config intentionally empty for alias coverage\n")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         (format nil "--config=~A" (namestring config-path))
                         (format nil "--genesis=~A"
                                 +devnet-cli-genesis-fixture+)
                         "--authrpc.addr=192.0.2.30"
                         "--authrpc.port=9651"
                         (format nil "--authrpc.jwtsecret=~A"
                                 (namestring jwt-path))
                         "--authrpc.rpcprefix=/engine"
                         "--authrpc.vhosts=engine.runner,localhost"
                         "--authrpc.corsdomain=https://engine.runner"
                         "--http=false"
                         "--http.addr=192.0.2.31"
                         "--http.port=9645"
                         "--http.api=eth,net,web3,txpool"
                         "--http.rpcprefix=/rpc"
                         "--http.vhosts=public.runner,localhost"
                         "--http.corsdomain=https://runner.example,*"
                         "--ws=false"
                         "--ws.addr=192.0.2.32"
                         "--ws.port=9646"
                         "--ws.api=eth,net"
                         "--ws.origins=*"
                         "--ws.rpcprefix=/ws"
                         "--ipcapi=eth,net,web3"
                         "--graphql=false"
                         "--graphql.addr=192.0.2.33"
                         "--graphql.port=9647"
                         "--graphql.vhosts=*"
                         "--graphql.corsdomain=*"
                         "--networkid=7331"
                         "--mainnet=false"
                         "--sepolia=false"
                         "--holesky=false"
                         "--hoodi=false"
                         "--goerli=false"
                         "--syncmode=full"
                         "--nodiscover=false"
                         "--ipcdisable=true"
                         "--verbosity=3"
                         "--maxpeers=0"
                         "--nat=none"
                         "--netrestrict=127.0.0.0/8"
                         "--identity=ethereum-lisp-devnet"
                         "--nodekey=/tmp/ethereum-lisp-nodekey"
                         "--nodekeyhex=010203"
                         "--discovery.port=30303"
                         "--discovery.dns="
                         "--ipcpath=/tmp/ethereum-lisp.ipc"
                         "--allow-insecure-unlock=false"
                         (format nil "--ready-file=~A"
                                 (namestring ready-path))
                         (format nil "--log-file=~A"
                                 (namestring log-path))
                         "--json=true"
                         "--no-serve=1")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= "192.0.2.30:9651"
                            (fixture-object-field summary "engineEndpoint")))
               (is (not (fixture-object-field summary "rpcEndpoint")))
               (is (not (fixture-object-field summary "publicRpcEnabled")))
               (is (string= "/engine"
                            (fixture-object-field summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field summary
                                                  "publicRpcPrefix")))
               (is (= 7331 (fixture-object-field summary "networkId")))
               (is (eq t (fixture-object-field summary "authRequired")))
               (is (string= (namestring jwt-path)
                            (fixture-object-field summary "jwtSecretPath")))
               (is (equal '("eth" "net" "web3" "txpool")
                          (fixture-object-field summary
                                                "publicApiModules")))
               (is (equal '("https://engine.runner")
                          (fixture-object-field summary
                                                "engineCorsOrigins")))
               (is (equal '("https://runner.example" "*")
                          (fixture-object-field summary
                                                "publicCorsOrigins")))
               (is (equal '("engine.runner" "localhost")
                          (fixture-object-field summary "engineVhosts")))
               (is (equal '("public.runner" "localhost")
                          (fixture-object-field summary "publicVhosts"))))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (string= "0x1ca3"
                              (cdr (assoc "networkId" fields
                                          :test #'string=))))
                 (is (string= "/engine"
                              (cdr (assoc "engineRpcPrefix" fields
                                          :test #'string=))))
                 (is (string= "/rpc"
                              (cdr (assoc "publicRpcPrefix" fields
                                          :test #'string=))))
                 (is (string= ""
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))
                 (is (string= "false"
                              (cdr (assoc "publicRpcEnabled" fields
                                          :test #'string=))))
                 (is (string= "eth,net,web3,txpool"
                              (cdr (assoc "publicApiModules" fields
                                          :test #'string=))))
                 (is (string= "https://engine.runner"
                              (cdr (assoc "engineCorsOrigins" fields
                                          :test #'string=))))
                 (is (string= "https://runner.example,*"
                              (cdr (assoc "publicCorsOrigins" fields
                                          :test #'string=))))
                 (is (string= "engine.runner,localhost"
                              (cdr (assoc "engineVhosts" fields
                                          :test #'string=))))
                 (is (string= "public.runner,localhost"
                              (cdr (assoc "publicVhosts" fields
                                          :test #'string=))))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file config-path)
        (delete-file config-path)))))

