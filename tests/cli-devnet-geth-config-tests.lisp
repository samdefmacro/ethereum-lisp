(in-package #:ethereum-lisp.test)

(deftest devnet-cli-main-applies-geth-config-file-values
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config"))
         (datadir (merge-pathnames "datadir/" root))
         (database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (jwt-path (merge-pathnames "jwt.hex" root))
         (config-path (merge-pathnames "geth.toml" root))
         (journal-path (merge-pathnames "txpool-journal.sexp" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist datadir)
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file
            config-path
            (format nil
                    "[Eth]~%NetworkId = 4242~%~
                     [Eth.TxPool]~%PriceLimit = 7~%PriceBump = 25~%~
                     AccountSlots = 3~%GlobalSlots = 4~%~
                     AccountQueue = 9~%GlobalQueue = 12~%~
                     Lifetime = \"3h0m0s\"~%~
                     Journal = ~S~%~
                     Rejournal = \"45m\"~%~
                     Locals = [\"0x0000000000000000000000000000000000000001\", ~
                     \"0x0000000000000000000000000000000000000002\"]~%~
                     NoLocals = true~%~
                     [Node]~%DataDir = ~S~%~
                     HTTPHost = \"192.0.2.41\"~%HTTPPort = 1945~%~
                     HTTPModules = [\"eth\", \"net\"]~%~
                     HTTPCors = [\"https://public.example\", \"*\"]~%~
                     HTTPVirtualHosts = [\"public.example\", \"localhost\"]~%~
                     HTTPPathPrefix = \"/rpc\"~%~
                     AuthAddr = \"192.0.2.42\"~%AuthPort = 1951~%~
                     AuthVirtualHosts = [\"engine.example\", \"localhost\"]~%~
                     JWTSecret = ~S~%"
                    (namestring journal-path)
                    (namestring datadir)
                    (namestring jwt-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= "192.0.2.42:1951"
                          (fixture-object-field summary "engineEndpoint")))
             (is (string= "192.0.2.41:1945"
                          (fixture-object-field summary "rpcEndpoint")))
             (is (= 4242 (fixture-object-field summary "networkId")))
             (is (= 7 (fixture-object-field summary "txpoolPriceLimit")))
             (is (= 25 (fixture-object-field summary "txpoolPriceBump")))
             (is (= 3 (fixture-object-field summary "txpoolAccountSlots")))
             (is (= 4 (fixture-object-field summary "txpoolGlobalSlots")))
             (is (= 9 (fixture-object-field summary "txpoolAccountQueue")))
             (is (= 12 (fixture-object-field summary "txpoolGlobalQueue")))
             (is (= 10800
                    (fixture-object-field summary "txpoolLifetimeSeconds")))
             (is (string= (namestring journal-path)
                          (fixture-object-field summary
                                                "txpoolJournalPath")))
             (is (= 2700
                    (fixture-object-field summary "txpoolRejournalSeconds")))
             (is (equal '("0x0000000000000000000000000000000000000001"
                          "0x0000000000000000000000000000000000000002")
                        (fixture-object-field summary "txpoolLocals")))
             (is (eq t (fixture-object-field summary "txpoolNoLocals")))
             (is (string= "/rpc"
                          (fixture-object-field summary "publicRpcPrefix")))
             (is (string= (namestring jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (eq t (fixture-object-field summary "authRequired")))
             (is (string= (namestring database-path)
                          (fixture-object-field summary "databasePath")))
             (is (equal '("eth" "net")
                        (fixture-object-field summary "publicApiModules")))
             (is (equal '("https://public.example" "*")
                        (fixture-object-field summary "publicCorsOrigins")))
             (is (equal '("public.example" "localhost")
                        (fixture-object-field summary "publicVhosts")))
             (is (equal '("engine.example" "localhost")
                        (fixture-object-field summary "engineVhosts")))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-explicit-options-override-geth-config-file
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config-override"))
         (jwt-path (merge-pathnames "config-jwt.hex" root))
         (override-jwt-path (merge-pathnames "override-jwt.hex" root))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file
            override-jwt-path
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
           (devnet-cli-write-temp-file
            config-path
            (format nil
                    "[Eth]~%NetworkId = 4242~%~
                     [Eth.TxPool]~%PriceLimit = 7~%PriceBump = 25~%~
                     AccountSlots = 3~%GlobalSlots = 4~%~
                     AccountQueue = 9~%GlobalQueue = 12~%~
                     Lifetime = \"3h0m0s\"~%~
                     Rejournal = \"3h0m0s\"~%~
                     Locals = [\"0x0000000000000000000000000000000000000001\"]~%~
                     NoLocals = true~%~
                     [Node]~%HTTPHost = \"192.0.2.50\"~%HTTPPort = 1950~%~
                     AuthAddr = \"192.0.2.51\"~%AuthPort = 1951~%~
                     JWTSecret = ~S~%"
                    (namestring jwt-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--authrpc.addr" "192.0.2.60"
                         "--authrpc.port" "1960"
                         "--http.addr" "192.0.2.61"
                         "--http.port" "1961"
                         "--networkid" "7331"
                         "--txpool.pricelimit" "11"
                         "--txpool.pricebump" "40"
                         "--txpool.accountslots" "5"
                         "--txpool.globalslots" "6"
                         "--txpool.accountqueue" "10"
                         "--txpool.globalqueue" "20"
                         "--txpool.lifetime" "1h2m3s"
                         "--txpool.rejournal" "10m"
                         "--txpool.locals"
                         "0x0000000000000000000000000000000000000002"
                         "--txpool.nolocals" "false"
                         "--authrpc.jwtsecret" (namestring override-jwt-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= "192.0.2.60:1960"
                          (fixture-object-field summary "engineEndpoint")))
             (is (string= "192.0.2.61:1961"
                          (fixture-object-field summary "rpcEndpoint")))
             (is (= 7331 (fixture-object-field summary "networkId")))
             (is (= 11 (fixture-object-field summary "txpoolPriceLimit")))
             (is (= 40 (fixture-object-field summary "txpoolPriceBump")))
             (is (= 5 (fixture-object-field summary "txpoolAccountSlots")))
             (is (= 6 (fixture-object-field summary "txpoolGlobalSlots")))
             (is (= 10 (fixture-object-field summary "txpoolAccountQueue")))
             (is (= 20 (fixture-object-field summary "txpoolGlobalQueue")))
             (is (= 3723
                    (fixture-object-field summary "txpoolLifetimeSeconds")))
             (is (= 600
                    (fixture-object-field summary "txpoolRejournalSeconds")))
             (is (equal '("0x0000000000000000000000000000000000000002")
                        (fixture-object-field summary "txpoolLocals")))
             (is (eq nil (fixture-object-field summary "txpoolNoLocals")))
             (is (string= (namestring override-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file override-jwt-path)
        (delete-file override-jwt-path))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-applies-geth-miner-config-file-values
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-miner-config"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Eth.Miner]
GasCeil = 34000000
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--dev"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq t (fixture-object-field summary "devMode")))
             (is (= 34000000
                    (fixture-object-field summary "headGasLimit")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-explicit-dev-gaslimit-overrides-geth-miner-config-file
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-miner-config-override"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Eth.Miner]
GasCeil = 34000000
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--dev"
                         "--dev.gaslimit"
                         "35000000"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq t (fixture-object-field summary "devMode")))
             (is (= 35000000
                    (fixture-object-field summary "headGasLimit")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-empty-geth-http-host-disables-public-rpc
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config-http-disabled"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Node]
HTTPHost = \"\"
HTTPPort = 1945
AuthAddr = \"192.0.2.42\"
AuthPort = 1951
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq nil (fixture-object-field summary "publicRpcEnabled")))
             (is (eq nil (fixture-object-field summary "rpcEndpoint")))
             (is (string= "192.0.2.42:1951"
                          (fixture-object-field summary "engineEndpoint")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-explicit-http-reenables-empty-geth-http-host
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config-http-reenabled"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Node]
HTTPHost = \"\"
HTTPPort = 1945
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--http"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq t (fixture-object-field summary "publicRpcEnabled")))
             (is (string= "127.0.0.1:1945"
                          (fixture-object-field summary "rpcEndpoint")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-geth-p2p-port-does-not-override-engine-port
  (labels ((run-summary (args)
             (let ((output (make-string-output-stream))
                   (errors (make-string-output-stream)))
               (is (= 0
                      (ethereum-lisp.cli:main
                       (append (list "devnet"
                                     "--genesis"
                                     +devnet-cli-genesis-fixture+)
                               args
                               (list "--json" "--no-serve"))
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string errors)))
               (parse-json (get-output-stream-string output)))))
    (let ((p2p-after-authrpc
            (run-summary
             (list "--authrpc.port=9651"
                   "--port=30303"
                   "--http.port=9645")))
          (p2p-before-authrpc
            (run-summary
             (list "--port=30303"
                   "--authrpc.port=9652"
                   "--http.port=9646")))
          (p2p-without-authrpc
            (run-summary
             (list "--port=30303"
                   "--http.port=9647"))))
      (is (string= "127.0.0.1:9651"
                   (fixture-object-field p2p-after-authrpc
                                         "engineEndpoint")))
      (is (string= "127.0.0.1:9652"
                   (fixture-object-field p2p-before-authrpc
                                         "engineEndpoint")))
      (is (string= "127.0.0.1:8551"
                   (fixture-object-field p2p-without-authrpc
                                         "engineEndpoint")))
      (is (string= "127.0.0.1:9645"
                   (fixture-object-field p2p-after-authrpc
                                         "rpcEndpoint")))
      (is (string= "127.0.0.1:9646"
                   (fixture-object-field p2p-before-authrpc
                                         "rpcEndpoint")))
      (is (string= "127.0.0.1:9647"
                   (fixture-object-field p2p-without-authrpc
                                         "rpcEndpoint"))))))

(deftest devnet-cli-main-accepts-geth-style-txpool-and-database-flags
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-geth-txpool" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         (format nil "--genesis=~A"
                                 +devnet-cli-genesis-fixture+)
                         "--db.engine=pebble"
                         "--state.scheme=hash"
                         "--datadir.ancient=/tmp/ethereum-lisp-ancient"
                         "--rpc.allow-unprotected-txs=true"
                         "--txpool.locals=0x0000000000000000000000000000000000000001"
                         "--txpool.nolocals=false"
                         (format nil "--txpool.journal=~A"
                                 (namestring journal-path))
                         "--txpool.rejournal=1h"
                         "--txpool.pricelimit=1"
                         "--txpool.pricebump=10"
                         "--txpool.accountslots=16"
                         "--txpool.globalslots=5120"
                         "--txpool.accountqueue=64"
                         "--txpool.globalqueue=1024"
                         "--txpool.lifetime=3h0m0s"
                         "--txpool.blobpool.datacap=2684354560"
                         "--txpool.blobpool.pricebump=100"
                         "--dev=false"
                         "--nousb=true"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= "127.0.0.1:8551"
                          (fixture-object-field summary "engineEndpoint")))
             (is (string= "127.0.0.1:8545"
                          (fixture-object-field summary "rpcEndpoint")))
             (is (eq t (fixture-object-field summary
                                              "allowUnprotectedTransactions")))
             (is (= 1 (fixture-object-field summary "txpoolPriceLimit")))
             (is (= 10 (fixture-object-field summary "txpoolPriceBump")))
             (is (= 16 (fixture-object-field summary "txpoolAccountSlots")))
             (is (= 5120 (fixture-object-field summary "txpoolGlobalSlots")))
             (is (= 64 (fixture-object-field summary "txpoolAccountQueue")))
             (is (= 1024 (fixture-object-field summary "txpoolGlobalQueue")))
             (is (= 10800
                    (fixture-object-field summary "txpoolLifetimeSeconds")))
             (is (= 3600
                    (fixture-object-field summary "txpoolRejournalSeconds")))
             (is (string= (namestring journal-path)
                          (fixture-object-field summary
                                                "txpoolJournalPath")))
             (is (equal '("0x0000000000000000000000000000000000000001")
                        (fixture-object-field summary "txpoolLocals")))
             (is (eq nil (fixture-object-field summary "txpoolNoLocals")))
             (is (eq nil (fixture-object-field summary "authRequired")))))
      (when (probe-file journal-path)
        (delete-file journal-path)))))

(deftest devnet-cli-main-accepts-geth-style-dev-mode-flags
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  (format nil "--genesis=~A" +devnet-cli-genesis-fixture+)
                  "--dev=true"
                  "--dev.period=1"
                  "--dev.gaslimit"
                  "31000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (string= "127.0.0.1:8551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint")))
      (is (= 1
             (fixture-object-field summary "devPeriodSeconds")))
      (is (= #x1c9c380
             (fixture-object-field summary "headGasLimit")))))
  (let ((init-options
          (ethereum-lisp.cli::devnet-cli-init-options
           (list "init"
                 "--dev=true"
                 "--dev.period=1"
                 "--dev.gaslimit"
                 "30000000"
                 "--json=false"))))
    (is (eq :sexp (getf init-options :summary-format)))))

(deftest devnet-cli-main-accepts-geth-style-rpc-limit-flags
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  (format nil "--genesis=~A" +devnet-cli-genesis-fixture+)
                  "--rpc.gascap=50000000"
                  "--rpc.evmtimeout=5s"
                  "--rpc.txfeecap=0"
                  "--rpc.batch-request-limit=1000"
                  "--rpc.batch-response-max-size=25000000"
                  "--http.maxclients=128"
                  "--http.readtimeout=30s"
                  "--http.writetimeout"
                  "30s"
                  "--http.idletimeout=2m"
                  "--override.terminaltotaldifficulty=0"
                  "--override.terminaltotaldifficultypassed=true"
                  "--override.terminalblockhash=0x0000000000000000000000000000000000000000000000000000000000000000"
                  "--override.terminalblocknumber=0"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (string= "127.0.0.1:8551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint"))))))

