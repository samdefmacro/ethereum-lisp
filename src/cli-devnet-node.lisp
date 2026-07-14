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
  (let* ((engine-endpoint-config
           (make-devnet-endpoint-config
            :host host :port port :rpc-prefix engine-rpc-prefix
            :cors-origins engine-cors-origins :allowed-hosts engine-vhosts
            :allowed-method-p #'engine-rpc-engine-method-p))
         (public-endpoint-config
           (make-devnet-endpoint-config
            :host public-host :port public-port :rpc-prefix public-rpc-prefix
            :cors-origins public-cors-origins :allowed-hosts public-vhosts
            :allowed-method-p public-allowed-method-p))
         (txpool-policy
           (make-devnet-txpool-policy
            :allow-unprotected-transactions-p
            allow-unprotected-transactions-p
            :price-limit txpool-price-limit
            :price-bump-percent txpool-price-bump-percent
            :account-slot-limit txpool-account-slot-limit
            :global-slot-limit txpool-global-slot-limit
            :account-queue-limit txpool-account-queue-limit
            :global-queue-limit txpool-global-queue-limit
            :local-addresses txpool-local-addresses
            :no-local-exemptions-p txpool-no-local-exemptions-p
            :lifetime-seconds txpool-lifetime-seconds))
         (kzg-config
           (make-devnet-kzg-config
            :command kzg-verifier-command
            :timeout-seconds
            (and kzg-verifier-command
                 (or kzg-verifier-timeout-seconds
                     *kzg-verifier-command-timeout-seconds*))))
         (genesis-json (and (null genesis-path) genesis-json))
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
         (store-guard-function (make-devnet-store-guard-function))
         (new-payload-persistence-function
           (devnet-cli-new-payload-persistence-function database-path))
         (forkchoice-persistence-function
           (devnet-cli-forkchoice-persistence-function database-path))
         (jwt-secret (and jwt-secret-path
                          (devnet-cli-read-jwt-secret jwt-secret-path)))
         (service
           (make-engine-rpc-http-service
            :host (devnet-endpoint-config-host engine-endpoint-config)
            :port (devnet-endpoint-config-port engine-endpoint-config)
            :store store
            :config config
            :network-id effective-network-id
            :coinbase coinbase
            :import-function #'execute-and-commit-engine-payload
            :new-payload-persistence-function
            new-payload-persistence-function
            :forkchoice-persistence-function forkchoice-persistence-function
            :request-guard-function store-guard-function
            :jwt-secret jwt-secret
            :rpc-prefix
            (devnet-endpoint-config-rpc-prefix engine-endpoint-config)
            :allowed-method-p
            (devnet-endpoint-config-allowed-method-p engine-endpoint-config)
            :cors-origins
            (devnet-endpoint-config-cors-origins engine-endpoint-config)
            :allowed-hosts
            (devnet-endpoint-config-allowed-hosts engine-endpoint-config)
            :telemetry-sink telemetry-sink))
         (public-service
           (make-engine-rpc-http-service
            :host (devnet-endpoint-config-host public-endpoint-config)
            :port (devnet-endpoint-config-port public-endpoint-config)
            :store store
            :config config
            :network-id effective-network-id
            :coinbase coinbase
            :import-function #'execute-and-commit-engine-payload
            :new-payload-persistence-function
            new-payload-persistence-function
            :forkchoice-persistence-function forkchoice-persistence-function
            :request-guard-function store-guard-function
            :now-provider #'get-universal-time
            :rpc-prefix
            (devnet-endpoint-config-rpc-prefix public-endpoint-config)
            :allowed-method-p
            (devnet-endpoint-config-allowed-method-p public-endpoint-config)
            :cors-origins
            (devnet-endpoint-config-cors-origins public-endpoint-config)
            :allowed-hosts
            (devnet-endpoint-config-allowed-hosts public-endpoint-config)
            :allow-unprotected-transactions-p
            (devnet-txpool-policy-allow-unprotected-transactions-p
             txpool-policy)
            :txpool-price-limit (devnet-txpool-policy-price-limit txpool-policy)
            :txpool-price-bump-percent
            (devnet-txpool-policy-price-bump-percent txpool-policy)
            :txpool-account-slot-limit
            (devnet-txpool-policy-account-slot-limit txpool-policy)
            :txpool-global-slot-limit
            (devnet-txpool-policy-global-slot-limit txpool-policy)
            :txpool-account-queue-limit
            (devnet-txpool-policy-account-queue-limit txpool-policy)
            :txpool-global-queue-limit
            (devnet-txpool-policy-global-queue-limit txpool-policy)
            :txpool-local-addresses
            (devnet-txpool-policy-local-addresses txpool-policy)
            :txpool-no-local-exemptions-p
            (devnet-txpool-policy-no-local-exemptions-p txpool-policy)
            :txpool-lifetime-seconds
            (devnet-txpool-policy-lifetime-seconds txpool-policy)
            :telemetry-sink telemetry-sink)))
    (chain-store-put-block store genesis-block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis-block) state)
    (devnet-cli-import-persistent-state
     store database-path txpool-journal-path config genesis-block)
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
     :engine-endpoint-config engine-endpoint-config
     :public-endpoint-config public-endpoint-config
     :txpool-policy txpool-policy
     :kzg-config kzg-config
     :dev-mode-p dev-mode-p
     :coinbase coinbase
     :store-guard-function store-guard-function
     :txpool-journal-path txpool-journal-path
     :txpool-rejournal-seconds txpool-rejournal-seconds
     :dev-period-seconds dev-period-seconds)))

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
