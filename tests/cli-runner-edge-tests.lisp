(in-package #:ethereum-lisp.test)

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
