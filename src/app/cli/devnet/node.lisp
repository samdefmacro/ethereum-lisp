(in-package #:ethereum-lisp.cli)

(defun make-devnet-node
    (&key
       genesis-path
       genesis-json
       genesis-preset
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
       (db-engine :file)
       pid-file-path
       network-id
       ;; Inbound peering. P2P-PORT NIL means no listener: a devnet that binds a
       ;; fixed port by default is a devnet that collides with the next one.
       ;; P2P-HOST is not a CLI flag, so a test can force loopback.
       (p2p-host "0.0.0.0")
       p2p-port
       max-peers
       netrestrict
       nat-policy
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
       miner-gas-limit
       peers
       bootnodes
       node-key
       (public-allowed-method-p #'engine-rpc-public-method-p)
       (telemetry-sink ethereum-lisp.telemetry:*telemetry-sink*)
       ;; --metrics counts every telemetry event by name. Counting what the node
       ;; already emits means the metrics cannot drift from what it actually
       ;; does, which a parallel set of hand-placed counters eventually would.
       metrics
       ;; Where to publish those counts. Ignored unless METRICS is on.
       metrics-host
       metrics-port
       ws-enabled-p
       ws-host
       ws-port
       ws-origins
       ws-rpc-prefix)
  (unless (or (and genesis-path (stringp genesis-path))
              (and genesis-json (stringp genesis-json))
              genesis-preset)
    (error "Devnet node requires a genesis JSON path, source, or preset"))
  (unless (functionp public-allowed-method-p)
    (error "Devnet public RPC method filter must be a function"))
  (when (and database-path
             txpool-journal-path
             (devnet-cli-same-output-path-p
              database-path txpool-journal-path))
    (error
     "--database and --txpool.journal must name different files: ~A"
     database-path))
  (let* ((telemetry-sink
           (if metrics
               (make-counting-telemetry-sink :delegate telemetry-sink)
               telemetry-sink))
         ;; The admin RPC backend must exist before the public service is built,
         ;; but it reads the node, which is built last. The box is filled the
         ;; moment the node exists; nothing reads it before then.
         (node-box (list nil))
         (admin-backend (devnet-node-admin-backend node-box))
         ;; One identity per node, minted once: the peer table's notion of self
         ;; must be the SAME key the workers dial with, or we would fail to
         ;; recognise our own connection.
         (node-key (or node-key (secp256k1-random-private-key)))
         (engine-endpoint-config
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
         (genesis-json (and (null genesis-path) genesis-json))
         (genesis-preset
           (and genesis-preset
                (find-built-in-genesis-preset genesis-preset)))
         (config
           (devnet-cli-apply-merge-overrides
            (cond
              (genesis-preset
               (built-in-genesis-preset-config genesis-preset))
              (genesis-json
               (chain-config-from-genesis-json-string genesis-json))
              (t
               (chain-config-from-genesis-json-file genesis-path)))
            :terminal-total-difficulty terminal-total-difficulty
            :terminal-total-difficulty-passed terminal-total-difficulty-passed
            :terminal-total-difficulty-passed-specified-p
            terminal-total-difficulty-passed-specified-p
            :terminal-block-hash terminal-block-hash
            :terminal-block-number terminal-block-number))
         (state
           (cond
             (genesis-preset
              (state-db-from-built-in-genesis-preset genesis-preset))
             (genesis-json
              (state-db-from-genesis-json-string genesis-json))
             (t
              (state-db-from-genesis-json-file genesis-path))))
         (genesis-block
           (cond
             (genesis-preset
              (built-in-genesis-block
               genesis-preset :state-root (state-db-root state)))
             (genesis-json
              (genesis-block-from-state-genesis-json-string
               genesis-json
               :config config))
             (t
              (genesis-block-from-state-genesis-json-file
               genesis-path
               :config config))))
         (persistence-state
           (make-devnet-persistence-state
            :chain-id (chain-config-chain-id config)
            :genesis-hash (block-hash genesis-block)
            :authority-id (devnet-cli-new-persistence-authority-id)))
         (effective-network-id (or network-id (chain-config-chain-id config)))
         (initial-store (make-engine-payload-memory-store))
         ;; The blocking guard and its give-up-instead companion share one
         ;; mutex, so they have to be taken from one call.
         (store-guard-pair (multiple-value-list (make-devnet-store-guard-function)))
         (store-guard-function (first store-guard-pair))
         (store-guard-try-function (second store-guard-pair))
         (new-payload-persistence-function
           (devnet-cli-new-payload-persistence-function database-path db-engine))
         (forkchoice-persistence-function
           (devnet-cli-forkchoice-persistence-function
            database-path persistence-state db-engine))
         (store
           (progn
             (chain-store-put-block
              initial-store genesis-block :state-available-p t)
             (commit-state-db-to-chain-store
              initial-store (block-hash genesis-block) state)
             (devnet-cli-import-persistent-state
              initial-store
              database-path
              txpool-journal-path
              config
              genesis-block
              persistence-state
              db-engine)))
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
            :gas-limit-target miner-gas-limit
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
            :gas-limit-target miner-gas-limit
            :request-guard-function store-guard-function
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
            :admin-backend admin-backend
            :telemetry-sink telemetry-sink)))
    (setf (first node-box)
          (%make-devnet-node
       :genesis-path
       (or genesis-path
           (and genesis-preset
                (format nil "builtin:~(~A~)"
                        (built-in-genesis-preset-name genesis-preset))))
       :store store
       :config config
       :genesis-block genesis-block
       :service service
       :public-service public-service
       :telemetry-sink telemetry-sink
       :jwt-secret-path jwt-secret-path
       :log-path log-path
       :database-path database-path
       :db-engine db-engine
       :pid-file-path pid-file-path
       :network-id effective-network-id
       :public-api-modules (and public-api-modules
                                (copy-list public-api-modules))
       :engine-endpoint-config engine-endpoint-config
       :public-endpoint-config public-endpoint-config
       :txpool-policy txpool-policy
       :dev-mode-p dev-mode-p
       :coinbase coinbase
       :store-guard-function store-guard-function
       :store-guard-try-function store-guard-try-function
       :persistence-state persistence-state
       :canonical-transition-persistence-function
       forkchoice-persistence-function
       :txpool-journal-path txpool-journal-path
       :txpool-rejournal-seconds txpool-rejournal-seconds
       :dev-period-seconds dev-period-seconds
       :miner-gas-limit miner-gas-limit
       :peers (and peers (copy-list peers))
       :bootnodes (and bootnodes (copy-list bootnodes))
       ;; One stable node identity per node, shared by the discovery and peer-sync
       ;; workers; a fresh key when none is configured.
       :node-key node-key
       ;; Every peer we might dial, with its cooldown and failure history.
       :dial-registry (make-devnet-dial-registry)
       :dial-guard-function (make-devnet-store-guard-function)
       :p2p-host p2p-host
       :p2p-port p2p-port
       :nat-policy nat-policy
       :peer-table
       (make-devnet-peer-table
        :self-id-hex (node-id-to-hex (node-id-from-private-key node-key))
        :max-peers (or max-peers +devnet-default-max-peers+)
        :netrestrict netrestrict)
     :discovery-table
     (make-discv4-node-table (node-id-from-private-key node-key))
     :metrics-host metrics-host
     :metrics-port metrics-port
     :ws-enabled-p ws-enabled-p
     :ws-host ws-host
     :ws-port ws-port
     :ws-origins (and ws-origins (copy-list ws-origins))
     :ws-rpc-prefix ws-rpc-prefix))
    ;; Seed the operator's --peer values as static candidates. They are already
    ;; validated at parse time; ignore-errors is for a peer supplied
    ;; programmatically by a test, which must not break node construction.
    (let ((node (first node-box)))
      (dolist (enode (devnet-node-peers node))
        (ignore-errors
         (devnet-dial-registry-put-static
          (devnet-node-dial-registry node)
          (node-id-to-hex (nth-value 0 (parse-enode-url enode)))
          enode)))
      node)))

(defun devnet-cli-loopback-host-p (host)
  "True when HOST is a loopback bind address, so an unauthenticated Engine
endpoint bound to it is reachable only from this machine.

0.0.0.0 and :: bind every interface and are therefore NOT loopback. Any hostname
other than \"localhost\" is treated as non-loopback: we do not resolve names, and
a name that happens to resolve to loopback still deserves an explicit secret."
  (and (stringp host)
       (let ((name (string-trim "[]" host)))
         (or (string-equal name "localhost")
             (string-equal name "::1")
             (and (>= (length name) 4)
                  (string= "127." name :end2 4))))))

(defun devnet-cli-require-engine-authentication (node)
  "Refuse to serve the Engine (authrpc) API unauthenticated on a non-loopback
address.

The HTTP handler only checks the JWT bearer token inside (when jwt-secret ...),
so with no secret every Engine request -- forkchoice, payload submission -- is
accepted. That is acceptable on loopback, where the endpoint is reachable only
from this machine and an `init`-derived --datadir secret still satisfies the
check, but binding a routable host with no secret hands chain control to anyone
who can reach the port. Fail startup with a clear message instead of serving it."
  (let ((host (devnet-endpoint-config-host
               (devnet-node-engine-endpoint-config node))))
    (when (and (not (devnet-cli-loopback-host-p host))
               (null (devnet-node-jwt-secret-path node)))
      (error
       "Engine (authrpc) endpoint binds non-loopback host ~A without a JWT secret; refusing to serve the Engine API unauthenticated. Provide --authrpc.jwtsecret PATH (or --jwt-secret PATH), use a --datadir whose JWT secret was initialised, or bind the Engine endpoint to a loopback address."
       host))))

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
