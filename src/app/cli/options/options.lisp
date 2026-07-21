(in-package #:ethereum-lisp.cli)

(defun devnet-cli-options (args)
  (setf args (devnet-cli-remove-command-token args "devnet"))
  (setf args (devnet-cli-normalize-option-args args))
  (setf args (devnet-cli-apply-config-args args))
  (let ((genesis-path nil)
        (host "127.0.0.1")
        (port +engine-rpc-default-http-port+)
        (default-public-host "127.0.0.1")
        (public-host nil)
        (public-port +devnet-default-public-rpc-port+)
        (jwt-secret-path nil)
        (engine-rpc-prefix "/")
        (public-rpc-prefix "/")
        (database-path nil)
        (datadir-path nil)
        (network-id nil)
        (http-api-modules nil)
        (authrpc-cors-origins nil)
        (http-cors-origins nil)
        (engine-vhosts nil)
        (http-vhosts nil)
        (public-rpc-enabled-p t)
        (state-prune-before nil)
        (max-connections nil)
        (terminal-total-difficulty nil)
        (terminal-total-difficulty-passed nil)
        (terminal-total-difficulty-passed-specified-p nil)
        (terminal-block-hash nil)
        (terminal-block-number nil)
        (dev-mode-p nil)
        (dev-period-seconds nil)
        (dev-gas-limit nil)
        (miner-gas-limit nil)
        (coinbase (zero-address))
        (allow-unprotected-transactions-p nil)
        (txpool-price-limit nil)
        (txpool-price-bump-percent nil)
        (txpool-account-slot-limit nil)
        (txpool-global-slot-limit nil)
        (txpool-account-queue-limit nil)
        (txpool-global-queue-limit nil)
        (txpool-local-addresses nil)
        (txpool-no-local-exemptions-p nil)
        (txpool-lifetime-seconds nil)
        (txpool-journal-path nil)
        (txpool-rejournal-seconds nil)
        (serve-p t)
        (summary-format :sexp)
        (ready-file nil)
        (log-file nil)
        (pid-file nil)
        (kzg-verifier-command nil)
        (kzg-verifier-timeout-seconds nil)
        (bls12381-backend-command nil)
        (bls12381-backend-timeout-seconds nil)
        (http-read-timeout-seconds nil)
        (http-write-timeout-seconds nil)
        (help-p nil))
    (labels ((next-value (option)
               (multiple-value-bind (value rest)
                   (devnet-cli-next-value args option)
                 (setf args rest)
                 value))
             (next-parsed-value (option parser)
               (funcall parser (next-value option) option))
             (next-transformed-value (option transformer)
               (funcall transformer (next-value option)))
             (next-optional-boolean (option)
               (multiple-value-bind (enabled-p rest)
                   (devnet-cli-optional-boolean-value args option)
                 (setf args rest)
                 enabled-p))
             (consume-value-option (option)
               (setf args (devnet-cli-consume-value-option args option)))
             (consume-optional-boolean-value (option)
               (setf args
                     (devnet-cli-consume-optional-boolean-value
                      args option))))
      (loop while args
            for option = (pop args)
            do (cond
               ((string= option "--help")
                (setf help-p t))
               ((string= option "--genesis")
                (setf genesis-path (next-value option)))
               ((string= option "--host")
                (setf host (next-value option))
                (setf default-public-host host))
               ((or (string= option "--engine-host")
                    (string= option "--authrpc.addr"))
                (setf host (next-value option)))
               ((string= option "--port")
                (next-parsed-value option #'devnet-cli-parse-port))
               ((or (string= option "--engine-port")
                    (string= option "--authrpc.port"))
                (setf port (next-parsed-value option #'devnet-cli-parse-port)))
               ((or (string= option "--public-host")
                    (string= option "--http.addr"))
                (setf public-host (next-value option)))
               ((or (string= option "--public-port")
                    (string= option "--http.port"))
                (setf public-port (next-parsed-value option #'devnet-cli-parse-port)))
               ((or (string= option "--jwt-secret")
                    (string= option "--authrpc.jwtsecret"))
                (setf jwt-secret-path (next-value option)))
               ((string= option "--authrpc.rpcprefix")
                (setf engine-rpc-prefix
                      (next-parsed-value option #'devnet-cli-parse-rpc-prefix)))
               ((string= option "--http.rpcprefix")
                (setf public-rpc-prefix
                      (next-parsed-value option #'devnet-cli-parse-rpc-prefix)))
               ((string= option "--database")
                (setf database-path (next-value option)))
               ((string= option "--datadir")
                (setf datadir-path (next-value option)))
               ((or (string= option "--networkid")
                    (string= option "--network-id"))
                (setf network-id
                      (next-parsed-value option #'devnet-cli-parse-non-negative-integer)))
               ((string= option "--prune-state-before")
                (setf state-prune-before
                      (next-parsed-value option #'devnet-cli-parse-non-negative-integer)))
               ((string= option "--max-connections")
                (setf max-connections
                      (next-parsed-value option #'devnet-cli-parse-non-negative-integer)))
               ((string= option "--override.terminaltotaldifficulty")
                (setf terminal-total-difficulty
                      (next-parsed-value option #'devnet-cli-parse-non-negative-quantity)))
               ((string= option "--override.terminaltotaldifficultypassed")
                (setf terminal-total-difficulty-passed
                      (next-optional-boolean option)
                      terminal-total-difficulty-passed-specified-p t))
               ((string= option "--override.terminalblockhash")
                (setf terminal-block-hash
                      (next-parsed-value option #'devnet-cli-parse-hash32)))
               ((string= option "--override.terminalblocknumber")
                (setf terminal-block-number
                      (next-parsed-value option #'devnet-cli-parse-non-negative-quantity)))
               ((string= option "--http")
                (setf public-rpc-enabled-p (next-optional-boolean option)))
               ((string= option "--http.api")
                (setf http-api-modules
                      (next-parsed-value option #'devnet-cli-parse-http-api-list)))
               ((string= option "--http.corsdomain")
                (setf http-cors-origins
                      (next-transformed-value option #'devnet-cli-parse-cors-origin-list)))
               ((string= option "--authrpc.corsdomain")
                (setf authrpc-cors-origins
                      (next-transformed-value option #'devnet-cli-parse-cors-origin-list)))
               ((string= option "--authrpc.vhosts")
                (setf engine-vhosts
                      (next-transformed-value option #'devnet-cli-parse-vhost-list)))
               ((string= option "--http.vhosts")
                (setf http-vhosts
                      (next-transformed-value option #'devnet-cli-parse-vhost-list)))
               ((string= option "--ready-file")
                (setf ready-file (next-value option)))
               ((string= option "--log-file")
                (setf log-file (next-value option)))
               ((string= option "--pid-file")
                (setf pid-file (next-value option)))
               ((or (string= option "--kzg-verifier-command")
                    (string= option "--kzg.verifier-command"))
                (setf kzg-verifier-command (next-value option)))
               ((or (string= option "--kzg-verifier-timeout")
                    (string= option "--kzg.verifier-timeout"))
                (setf kzg-verifier-timeout-seconds
                      (next-parsed-value option #'devnet-cli-parse-positive-integer)))
               ((or (string= option "--bls12381-backend-command")
                    (string= option "--bls12381.backend-command"))
                (setf bls12381-backend-command (next-value option)))
               ((or (string= option "--bls12381-backend-timeout")
                    (string= option "--bls12381.backend-timeout"))
                (setf bls12381-backend-timeout-seconds
                      (next-parsed-value option #'devnet-cli-parse-positive-integer)))
               ((string= option "--http.readtimeout")
                (setf http-read-timeout-seconds
                      (next-parsed-value option #'devnet-cli-parse-duration-seconds)))
               ((string= option "--http.writetimeout")
                (setf http-write-timeout-seconds
                      (next-parsed-value option #'devnet-cli-parse-duration-seconds)))
               ((string= option "--no-serve")
                (let ((enabled-p (next-optional-boolean option)))
                  (when enabled-p
                    (setf serve-p nil))))
               ((string= option "--json")
                (let ((enabled-p (next-optional-boolean option)))
                  (when enabled-p
                    (setf summary-format :json))))
               ((string= option "--dev")
                (setf dev-mode-p (next-optional-boolean option)))
               ((string= option "--dev.period")
                (setf dev-period-seconds
                      (next-parsed-value option #'devnet-cli-parse-duration-seconds)))
               ((string= option "--dev.gaslimit")
                (setf dev-gas-limit
                      (next-parsed-value option #'devnet-cli-parse-uint64-quantity)))
               ((string= option "--miner.gaslimit")
                (setf miner-gas-limit
                      (next-parsed-value option #'devnet-cli-parse-uint64-quantity)))
               ((or (string= option "--miner.etherbase")
                    (string= option "--etherbase"))
                (setf coinbase
                      (next-parsed-value option #'devnet-cli-parse-address)))
               ((string= option "--rpc.allow-unprotected-txs")
                (setf allow-unprotected-transactions-p
                      (next-optional-boolean option)))
               ((string= option "--txpool.locals")
                (setf txpool-local-addresses
                      (next-parsed-value option #'devnet-cli-parse-address-list)))
               ((string= option "--txpool.nolocals")
                (setf txpool-no-local-exemptions-p
                      (next-optional-boolean option)))
               ((string= option "--txpool.pricelimit")
                (setf txpool-price-limit
                      (next-parsed-value option #'devnet-cli-parse-non-negative-quantity)))
               ((string= option "--txpool.pricebump")
                (setf txpool-price-bump-percent
                      (next-parsed-value option #'devnet-cli-parse-non-negative-integer)))
               ((string= option "--txpool.accountslots")
                (setf txpool-account-slot-limit
                      (next-parsed-value option #'devnet-cli-parse-non-negative-integer)))
               ((string= option "--txpool.globalslots")
                (setf txpool-global-slot-limit
                      (next-parsed-value option #'devnet-cli-parse-non-negative-integer)))
               ((string= option "--txpool.accountqueue")
                (setf txpool-account-queue-limit
                      (next-parsed-value option #'devnet-cli-parse-non-negative-integer)))
               ((string= option "--txpool.globalqueue")
                (setf txpool-global-queue-limit
                      (next-parsed-value option #'devnet-cli-parse-non-negative-integer)))
               ((string= option "--txpool.lifetime")
                (setf txpool-lifetime-seconds
                      (next-parsed-value option #'devnet-cli-parse-duration-seconds)))
               ((string= option "--txpool.journal")
                (setf txpool-journal-path (next-value option)))
               ((string= option "--txpool.rejournal")
                (setf txpool-rejournal-seconds
                      (next-parsed-value option #'devnet-cli-parse-duration-seconds)))
               ((member option *devnet-cli-value-options* :test #'string=)
                (consume-value-option option))
               ((member option *devnet-cli-optional-boolean-options*
                        :test #'string=)
                (consume-optional-boolean-value option))
               (t
                (error "Unknown option ~A" option))))
    (list :genesis-path genesis-path
          :host host
          :port port
          :public-host (or public-host default-public-host)
          :public-port public-port
          :jwt-secret-path (or jwt-secret-path
                               (and datadir-path
                                    (devnet-cli-existing-datadir-jwt-secret-path
                                     datadir-path)))
          :engine-rpc-prefix engine-rpc-prefix
          :public-rpc-prefix public-rpc-prefix
          :datadir-path datadir-path
          :database-path (or database-path
                             (and datadir-path
                                  (devnet-cli-datadir-database-path
                                   datadir-path)))
          :network-id network-id
          :http-api-modules http-api-modules
          :authrpc-cors-origins authrpc-cors-origins
          :http-cors-origins http-cors-origins
          :engine-vhosts engine-vhosts
          :http-vhosts http-vhosts
          :public-rpc-enabled-p public-rpc-enabled-p
          :terminal-total-difficulty terminal-total-difficulty
          :terminal-total-difficulty-passed terminal-total-difficulty-passed
          :terminal-total-difficulty-passed-specified-p
          terminal-total-difficulty-passed-specified-p
          :terminal-block-hash terminal-block-hash
          :terminal-block-number terminal-block-number
          :dev-mode-p dev-mode-p
          :dev-period-seconds dev-period-seconds
          :dev-gas-limit dev-gas-limit
          :miner-gas-limit miner-gas-limit
          :coinbase coinbase
          :allow-unprotected-transactions-p allow-unprotected-transactions-p
          :txpool-price-limit txpool-price-limit
          :txpool-price-bump-percent txpool-price-bump-percent
          :txpool-account-slot-limit txpool-account-slot-limit
          :txpool-global-slot-limit txpool-global-slot-limit
          :txpool-account-queue-limit txpool-account-queue-limit
          :txpool-global-queue-limit txpool-global-queue-limit
          :txpool-local-addresses txpool-local-addresses
          :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
          :txpool-lifetime-seconds txpool-lifetime-seconds
          :txpool-journal-path txpool-journal-path
          :txpool-rejournal-seconds txpool-rejournal-seconds
          :state-prune-before state-prune-before
          :max-connections max-connections
          :serve-p serve-p
          :summary-format summary-format
          :ready-file ready-file
          :log-file log-file
          :pid-file pid-file
          :kzg-verifier-command kzg-verifier-command
          :kzg-verifier-timeout-seconds kzg-verifier-timeout-seconds
          :bls12381-backend-command bls12381-backend-command
          :bls12381-backend-timeout-seconds bls12381-backend-timeout-seconds
          :http-read-timeout-seconds http-read-timeout-seconds
          :http-write-timeout-seconds http-write-timeout-seconds
          :help-p help-p))))
