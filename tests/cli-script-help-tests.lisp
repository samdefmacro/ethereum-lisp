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

