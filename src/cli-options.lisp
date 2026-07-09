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
        (help-p nil))
    (loop while args
          for option = (pop args)
          do (cond
               ((string= option "--help")
                (setf help-p t))
               ((string= option "--genesis")
                (multiple-value-setq (genesis-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--host")
                (multiple-value-setq (host args)
                  (devnet-cli-next-value args option))
                (setf default-public-host host))
               ((or (string= option "--engine-host")
                    (string= option "--authrpc.addr"))
                (multiple-value-setq (host args)
                  (devnet-cli-next-value args option)))
               ((string= option "--port")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (devnet-cli-parse-port value option)
                  (setf args rest)))
               ((or (string= option "--engine-port")
                    (string= option "--authrpc.port"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf port (devnet-cli-parse-port value option)
                        args rest)))
               ((or (string= option "--public-host")
                    (string= option "--http.addr"))
                (multiple-value-setq (public-host args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--public-port")
                    (string= option "--http.port"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf public-port (devnet-cli-parse-port value option)
                        args rest)))
               ((or (string= option "--jwt-secret")
                    (string= option "--authrpc.jwtsecret"))
                (multiple-value-setq (jwt-secret-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--authrpc.rpcprefix")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf engine-rpc-prefix
                        (devnet-cli-parse-rpc-prefix value option)
                        args rest)))
               ((string= option "--http.rpcprefix")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf public-rpc-prefix
                        (devnet-cli-parse-rpc-prefix value option)
                        args rest)))
               ((string= option "--database")
                (multiple-value-setq (database-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--datadir")
                (multiple-value-setq (datadir-path args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--networkid")
                    (string= option "--network-id"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf network-id
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--prune-state-before")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf state-prune-before
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--max-connections")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf max-connections
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--override.terminaltotaldifficulty")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf terminal-total-difficulty
                        (devnet-cli-parse-non-negative-quantity value option)
                        args rest)))
               ((string= option "--override.terminaltotaldifficultypassed")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf terminal-total-difficulty-passed enabled-p
                        terminal-total-difficulty-passed-specified-p t
                        args rest)))
               ((string= option "--override.terminalblockhash")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf terminal-block-hash
                        (devnet-cli-parse-hash32 value option)
                        args rest)))
               ((string= option "--override.terminalblocknumber")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf terminal-block-number
                        (devnet-cli-parse-non-negative-quantity value option)
                        args rest)))
               ((string= option "--http")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf public-rpc-enabled-p enabled-p
                        args rest)))
               ((string= option "--http.api")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf http-api-modules
                        (devnet-cli-parse-http-api-list value option))
                  (setf args rest)))
               ((string= option "--http.corsdomain")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf http-cors-origins
                        (devnet-cli-parse-cors-origin-list value)
                        args rest)))
               ((string= option "--authrpc.corsdomain")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf authrpc-cors-origins
                        (devnet-cli-parse-cors-origin-list value)
                        args rest)))
               ((string= option "--authrpc.vhosts")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf engine-vhosts
                        (devnet-cli-parse-vhost-list value)
                        args rest)))
               ((string= option "--http.vhosts")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf http-vhosts
                        (devnet-cli-parse-vhost-list value)
                        args rest)))
               ((string= option "--ready-file")
                (multiple-value-setq (ready-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--log-file")
                (multiple-value-setq (log-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--pid-file")
                (multiple-value-setq (pid-file args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--kzg-verifier-command")
                    (string= option "--kzg.verifier-command"))
                (multiple-value-setq (kzg-verifier-command args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--kzg-verifier-timeout")
                    (string= option "--kzg.verifier-timeout"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf kzg-verifier-timeout-seconds
                        (devnet-cli-parse-positive-integer value option)
                        args rest)))
               ((string= option "--no-serve")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (when enabled-p
                    (setf serve-p nil))
                  (setf args rest)))
               ((string= option "--json")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (when enabled-p
                    (setf summary-format :json))
                  (setf args rest)))
               ((string= option "--dev")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf dev-mode-p enabled-p
                        args rest)))
               ((string= option "--dev.period")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf dev-period-seconds
                        (devnet-cli-parse-duration-seconds value option)
                        args rest)))
               ((string= option "--dev.gaslimit")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf dev-gas-limit
                        (devnet-cli-parse-uint64-quantity value option)
                        args rest)))
               ((string= option "--miner.gaslimit")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf miner-gas-limit
                        (devnet-cli-parse-uint64-quantity value option)
                        args rest)))
               ((or (string= option "--miner.etherbase")
                    (string= option "--etherbase"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf coinbase (devnet-cli-parse-address value option)
                        args rest)))
               ((string= option "--rpc.allow-unprotected-txs")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf allow-unprotected-transactions-p enabled-p
                        args rest)))
               ((string= option "--txpool.locals")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-local-addresses
                        (devnet-cli-parse-address-list value option)
                        args rest)))
               ((string= option "--txpool.nolocals")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf txpool-no-local-exemptions-p enabled-p
                        args rest)))
               ((string= option "--txpool.pricelimit")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-price-limit
                        (devnet-cli-parse-non-negative-quantity value option)
                        args rest)))
               ((string= option "--txpool.pricebump")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-price-bump-percent
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--txpool.accountslots")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-account-slot-limit
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--txpool.globalslots")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-global-slot-limit
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--txpool.accountqueue")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-account-queue-limit
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--txpool.globalqueue")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-global-queue-limit
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--txpool.lifetime")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-lifetime-seconds
                        (devnet-cli-parse-duration-seconds value option)
                        args rest)))
               ((string= option "--txpool.journal")
                (multiple-value-setq (txpool-journal-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--txpool.rejournal")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-rejournal-seconds
                        (devnet-cli-parse-duration-seconds value option)
                        args rest)))
               ((member option *devnet-cli-value-options* :test #'string=)
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (declare (ignore value))
                  (setf args rest)))
               ((member option *devnet-cli-optional-boolean-options*
                        :test #'string=)
                (setf args
                      (devnet-cli-consume-optional-boolean-value
                       args option)))
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
          :help-p help-p)))


(defun devnet-cli-remove-command-token (args command)
  (let* ((args (devnet-cli-normalize-option-args args))
         (position (devnet-cli-command-position args command)))
    (if position
        (loop for arg in args
              for index from 0
              unless (= index position)
                collect arg)
        args)))

(defun devnet-cli-init-command-p (args)
  (devnet-cli-command-position args "init"))
