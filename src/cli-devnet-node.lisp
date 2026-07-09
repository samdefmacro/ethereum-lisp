(in-package #:ethereum-lisp.cli)

(defun make-devnet-node
    (&key
       genesis-path
       genesis-json
       dev-mode-p
       (host "127.0.0.1")
       (port +engine-rpc-default-http-port+)
       (public-host host)
       (public-port +devnet-default-public-rpc-port+)
       jwt-secret-path
       (engine-rpc-prefix "/")
       (public-rpc-prefix "/")
       log-path
       database-path
       pid-file-path
       network-id
       public-api-modules
       engine-cors-origins
       public-cors-origins
       engine-vhosts
       public-vhosts
       terminal-total-difficulty
       terminal-total-difficulty-passed
       terminal-total-difficulty-passed-specified-p
       terminal-block-hash
       terminal-block-number
       (coinbase (zero-address))
       allow-unprotected-transactions-p
       txpool-price-limit
       txpool-price-bump-percent
       txpool-account-slot-limit
       txpool-global-slot-limit
       txpool-account-queue-limit
       txpool-global-queue-limit
       txpool-local-addresses
       txpool-no-local-exemptions-p
       txpool-lifetime-seconds
       txpool-journal-path
       txpool-rejournal-seconds
       dev-period-seconds
       kzg-verifier-command
       kzg-verifier-timeout-seconds
       (public-allowed-method-p #'engine-rpc-public-method-p)
       (telemetry-sink ethereum-lisp.telemetry:*telemetry-sink*))
  (unless (or (and genesis-path (stringp genesis-path))
              (and genesis-json (stringp genesis-json)))
    (error "Devnet node requires a genesis JSON path or source"))
  (unless (functionp public-allowed-method-p)
    (error "Devnet public RPC method filter must be a function"))
  (let* ((genesis-json (and (null genesis-path) genesis-json))
         (config
           (devnet-cli-apply-merge-overrides
            (if genesis-json
                (chain-config-from-genesis-json-string genesis-json)
                (chain-config-from-genesis-json-file genesis-path))
            :terminal-total-difficulty terminal-total-difficulty
            :terminal-total-difficulty-passed terminal-total-difficulty-passed
            :terminal-total-difficulty-passed-specified-p
            terminal-total-difficulty-passed-specified-p
            :terminal-block-hash terminal-block-hash
            :terminal-block-number terminal-block-number))
         (state
           (if genesis-json
               (state-db-from-genesis-json-string genesis-json)
               (state-db-from-genesis-json-file genesis-path)))
         (genesis-block
           (if genesis-json
               (genesis-block-from-state-genesis-json-string
                genesis-json
                :config config)
               (genesis-block-from-state-genesis-json-file
                genesis-path
                :config config)))
         (effective-network-id (or network-id (chain-config-chain-id config)))
         (store (make-engine-payload-memory-store))
         (jwt-secret (and jwt-secret-path
                          (devnet-cli-read-jwt-secret jwt-secret-path)))
         (service
           (make-engine-rpc-http-service
            :host host
            :port port
            :store store
            :config config
            :network-id effective-network-id
            :coinbase coinbase
            :jwt-secret jwt-secret
            :rpc-prefix engine-rpc-prefix
            :allowed-method-p #'engine-rpc-engine-method-p
            :cors-origins engine-cors-origins
            :allowed-hosts engine-vhosts
            :telemetry-sink telemetry-sink))
         (public-service
           (make-engine-rpc-http-service
            :host public-host
            :port public-port
            :store store
            :config config
            :network-id effective-network-id
            :coinbase coinbase
            :now-provider #'get-universal-time
            :rpc-prefix public-rpc-prefix
            :allowed-method-p public-allowed-method-p
            :cors-origins public-cors-origins
            :allowed-hosts public-vhosts
            :allow-unprotected-transactions-p
            allow-unprotected-transactions-p
            :txpool-price-limit txpool-price-limit
            :txpool-price-bump-percent txpool-price-bump-percent
            :txpool-account-slot-limit txpool-account-slot-limit
            :txpool-global-slot-limit txpool-global-slot-limit
            :txpool-account-queue-limit txpool-account-queue-limit
            :txpool-global-queue-limit txpool-global-queue-limit
            :txpool-local-addresses txpool-local-addresses
            :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
            :txpool-lifetime-seconds txpool-lifetime-seconds
            :telemetry-sink telemetry-sink)))
    (chain-store-put-block store genesis-block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis-block) state)
    (when database-path
      (let ((existing-database-path (probe-file database-path)))
        (when (and existing-database-path
                   (not (devnet-cli-empty-file-p existing-database-path)))
          (let ((database
                  (ethereum-lisp.database:make-file-key-value-database
                   existing-database-path)))
            (when (devnet-cli-kv-chain-records-present-p database)
              (chain-store-import-from-kv
               store
               database
               :expected-chain-id (chain-config-chain-id config)
               :chain-config config)
              (devnet-cli-validate-imported-genesis
               store genesis-block existing-database-path))))))
    (when txpool-journal-path
      (let ((existing-journal-path (probe-file txpool-journal-path)))
        (when (and existing-journal-path
                   (not (devnet-cli-empty-file-p existing-journal-path)))
          (let ((journal
                  (ethereum-lisp.database:make-file-key-value-database
                   existing-journal-path)))
            (when (devnet-cli-kv-txpool-records-present-p journal)
              (unless (devnet-cli-store-txpool-records-present-p store)
                (chain-store-import-txpool-records-from-kv
                 store
                 journal
                 :expected-chain-id (chain-config-chain-id config)
                 :chain-config config)
                (chain-store-restore-txpool-consistency
                 store
                 :expected-chain-id (chain-config-chain-id config)
                 :chain-config config)))))))
    (%make-devnet-node
     :genesis-path genesis-path
     :store store
     :config config
     :genesis-block genesis-block
     :service service
     :public-service public-service
     :telemetry-sink telemetry-sink
     :jwt-secret-path jwt-secret-path
     :log-path log-path
     :database-path database-path
     :pid-file-path pid-file-path
     :network-id effective-network-id
     :public-api-modules (and public-api-modules
                              (copy-list public-api-modules))
     :engine-cors-origins (and engine-cors-origins
                               (copy-list engine-cors-origins))
     :public-cors-origins (and public-cors-origins
                               (copy-list public-cors-origins))
     :engine-vhosts (and engine-vhosts
                         (copy-list engine-vhosts))
     :public-vhosts (and public-vhosts
                         (copy-list public-vhosts))
     :dev-mode-p dev-mode-p
     :coinbase coinbase
     :allow-unprotected-transactions-p allow-unprotected-transactions-p
     :txpool-price-limit txpool-price-limit
     :txpool-price-bump-percent txpool-price-bump-percent
     :txpool-account-slot-limit txpool-account-slot-limit
     :txpool-global-slot-limit txpool-global-slot-limit
     :txpool-account-queue-limit txpool-account-queue-limit
     :txpool-global-queue-limit txpool-global-queue-limit
     :txpool-local-addresses (and txpool-local-addresses
                                  (copy-list txpool-local-addresses))
     :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
     :txpool-lifetime-seconds txpool-lifetime-seconds
     :txpool-journal-path txpool-journal-path
     :txpool-rejournal-seconds txpool-rejournal-seconds
     :dev-period-seconds dev-period-seconds
     :kzg-verifier-command kzg-verifier-command
     :kzg-verifier-timeout-seconds
     (and kzg-verifier-command
          (or kzg-verifier-timeout-seconds
              *kzg-verifier-command-timeout-seconds*)))))

(defun devnet-cli-apply-merge-overrides
    (config &key terminal-total-difficulty
                  terminal-total-difficulty-passed
                  terminal-total-difficulty-passed-specified-p
                  terminal-block-hash
                  terminal-block-number)
  (unless (typep config 'chain-config)
    (error "Devnet Merge overrides require a chain config"))
  (when terminal-total-difficulty
    (setf (chain-config-terminal-total-difficulty config)
          terminal-total-difficulty))
  (when terminal-total-difficulty-passed-specified-p
    (setf (chain-config-terminal-total-difficulty-passed config)
          terminal-total-difficulty-passed))
  (when terminal-block-hash
    (setf (chain-config-terminal-block-hash config) terminal-block-hash))
  (when terminal-block-number
    (setf (chain-config-terminal-block-number config) terminal-block-number))
  config)
