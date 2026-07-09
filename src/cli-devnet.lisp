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

(defun devnet-node-prune-state-before (node block-number)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (when block-number
    (chain-store-prune-state-before (devnet-node-store node) block-number)))

(defun devnet-node-rejournal (node)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let ((journal-path (devnet-node-txpool-journal-path node)))
    (when journal-path
      (chain-store-export-txpool-records-to-kv
       (devnet-node-store node)
       (devnet-cli-make-output-kv-database journal-path))
      t)))

(defun make-devnet-rejournal-state
    (node interval-seconds &key (now-function #'get-universal-time))
  (unless (typep node 'devnet-node)
    (error "Devnet rejournal state requires a devnet node"))
  (unless (or (null interval-seconds)
              (and (integerp interval-seconds) (<= 0 interval-seconds)))
    (error "Devnet rejournal interval must be a non-negative integer"))
  (unless (functionp now-function)
    (error "Devnet rejournal clock must be a function"))
  (%make-devnet-rejournal-state
   :node node
   :interval-seconds interval-seconds
   :now-function now-function
   :last-run-time (funcall now-function)))

(defun devnet-rejournal-state-enabled-p (state)
  (let ((node (devnet-rejournal-state-node state))
        (interval-seconds (devnet-rejournal-state-interval-seconds state)))
    (and node
         (devnet-node-txpool-journal-path node)
         interval-seconds
         (plusp interval-seconds))))

(defun devnet-rejournal-state-tick (state)
  (unless (typep state 'devnet-rejournal-state)
    (error "Devnet rejournal tick requires a devnet rejournal state"))
  (when (devnet-rejournal-state-enabled-p state)
    (let* ((now (funcall (devnet-rejournal-state-now-function state)))
           (last-run-time (devnet-rejournal-state-last-run-time state))
           (interval-seconds
             (devnet-rejournal-state-interval-seconds state)))
      (when (>= (- now last-run-time) interval-seconds)
        (setf (devnet-rejournal-state-last-run-time state) now)
        (devnet-node-rejournal (devnet-rejournal-state-node state))))))

(defun devnet-node-pending-mining-transactions (node)
  (let* ((store (devnet-node-store node))
         (expected-chain-id
           (chain-config-chain-id (devnet-node-config node))))
    (engine-payload-store-pending-mining-transactions
     store expected-chain-id)))

(defun devnet-node-seal-pending-block (node &key timestamp)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let* ((store (devnet-node-store node))
         (config (devnet-node-config node))
         (parent (chain-store-latest-block store))
         (pending-transactions
           (devnet-node-pending-mining-transactions node)))
    (when (and parent pending-transactions)
      (let* ((parent-header (block-header parent))
             (parent-hash (block-hash parent))
             (parent-timestamp (block-header-timestamp parent-header))
             (timestamp (max (or timestamp 0) (1+ parent-timestamp)))
             (block-number (1+ (block-header-number parent-header)))
             (gas-limit (block-header-gas-limit parent-header))
             (expected-chain-id (chain-config-chain-id config))
             (transactions
               (engine-select-mining-transactions
                pending-transactions gas-limit expected-chain-id))
             (state (chain-store-state-db store parent-hash))
             (cancun-p (chain-config-cancun-p config block-number timestamp))
             (shanghai-p (chain-config-shanghai-p config block-number
                                                   timestamp))
             (prague-p (chain-config-prague-p config block-number timestamp))
             (amsterdam-p
               (chain-config-amsterdam-p config block-number timestamp))
             (base-fee-per-gas
               (if (block-header-base-fee-per-gas parent-header)
                   (expected-base-fee-per-gas parent-header)
                   0))
             (cancun-header-arguments nil)
             (fork-body-arguments nil))
        (when transactions
          (unless state
            (error "Devnet dev-period parent state is unavailable"))
          (when cancun-p
            (multiple-value-bind (target-blob-gas max-blob-gas
                                  update-fraction)
                (chain-config-blob-schedule config block-number timestamp)
              (setf cancun-header-arguments
                    (list
                     :blob-gas-used 0
                     :excess-blob-gas
                     (expected-excess-blob-gas
                      parent-header
                      :target-blob-gas target-blob-gas
                      :max-blob-gas max-blob-gas
                      :eip7918-p (chain-config-osaka-p config block-number
                                                        timestamp)
                      :update-fraction update-fraction)
                     :parent-beacon-root (zero-hash32)))))
          (when shanghai-p
            (setf fork-body-arguments
                  (append fork-body-arguments (list :withdrawals '()))))
          (when prague-p
            (setf fork-body-arguments
                  (append fork-body-arguments (list :requests '()))))
          (when amsterdam-p
            (setf fork-body-arguments
                  (append fork-body-arguments (list :block-access-list '()))))
          (multiple-value-bind (block receipts)
              (apply
               #'execute-and-commit-signed-block
               store
               state
               transactions
               (append
                (list
                 :expected-chain-id expected-chain-id
                 :header (apply
                          #'make-block-header
                          (append
                           (list
                            :parent-hash parent-hash
                            :beneficiary (devnet-node-coinbase node)
                            :number block-number
                            :gas-limit gas-limit
                            :timestamp timestamp
                            :base-fee-per-gas base-fee-per-gas
                            :mix-hash (zero-hash32))
                           cancun-header-arguments))
                 :chain-config config
                 :state-available-p t)
                fork-body-arguments))
            (declare (ignore receipts))
            block))))))

(defun make-devnet-dev-period-state
    (node interval-seconds &key (now-function #'get-universal-time))
  (unless (typep node 'devnet-node)
    (error "Devnet dev-period state requires a devnet node"))
  (unless (or (null interval-seconds)
              (and (integerp interval-seconds) (<= 0 interval-seconds)))
    (error "Devnet dev-period interval must be a non-negative integer"))
  (unless (functionp now-function)
    (error "Devnet dev-period clock must be a function"))
  (%make-devnet-dev-period-state
   :node node
   :interval-seconds interval-seconds
   :now-function now-function
   :last-run-time (funcall now-function)))

(defun devnet-dev-period-state-enabled-p (state)
  (let ((node (devnet-dev-period-state-node state))
        (interval-seconds (devnet-dev-period-state-interval-seconds state)))
    (and node
         interval-seconds
         (plusp interval-seconds))))

(defun devnet-dev-period-state-tick (state)
  (unless (typep state 'devnet-dev-period-state)
    (error "Devnet dev-period tick requires a devnet dev-period state"))
  (when (devnet-dev-period-state-enabled-p state)
    (let* ((now (funcall (devnet-dev-period-state-now-function state)))
           (last-run-time (devnet-dev-period-state-last-run-time state))
           (interval-seconds
             (devnet-dev-period-state-interval-seconds state)))
      (when (>= (- now last-run-time) interval-seconds)
        (setf (devnet-dev-period-state-last-run-time state) now)
        (devnet-node-seal-pending-block
         (devnet-dev-period-state-node state)
         :timestamp now)))))

(defun devnet-node-export-database (node &key state-prune-before)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (devnet-node-prune-state-before node state-prune-before)
  (let ((database-path (devnet-node-database-path node)))
    (when database-path
      (chain-store-export-to-kv
       (devnet-node-store node)
       (devnet-cli-make-output-kv-database database-path))))
  (devnet-node-rejournal node))

(defun devnet-block-number (block)
  (and block (block-header-number (block-header block))))

(defun devnet-block-hash-hex (block)
  (and block (hash32-to-hex (block-hash block))))

(defun devnet-node-summary
    (node &key engine-endpoint rpc-endpoint (public-rpc-enabled-p t))
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let* ((store (devnet-node-store node))
         (head (chain-store-latest-block store))
         (safe (chain-store-safe-block store))
         (finalized (chain-store-finalized-block store))
         (engine-endpoint
           (or engine-endpoint
                (engine-rpc-http-service-endpoint
                (devnet-node-service node))))
         (rpc-endpoint
           (and public-rpc-enabled-p
                (or rpc-endpoint
                    (engine-rpc-http-service-endpoint
                     (devnet-node-public-service node))))))
    (list :genesis-path (devnet-node-genesis-path node)
          :engine-endpoint engine-endpoint
          :rpc-endpoint rpc-endpoint
          :public-rpc-enabled-p public-rpc-enabled-p
          :engine-rpc-prefix
          (engine-rpc-http-service-rpc-prefix (devnet-node-service node))
          :public-rpc-prefix
          (engine-rpc-http-service-rpc-prefix
           (devnet-node-public-service node))
          :process-id (devnet-process-id)
          :auth-required-p
          (not (null (engine-rpc-http-service-jwt-secret
                      (devnet-node-service node))))
          :jwt-secret-path (devnet-node-jwt-secret-path node)
          :log-path (devnet-node-log-path node)
          :database-path (devnet-node-database-path node)
          :pid-file-path (devnet-node-pid-file-path node)
          :network-id (devnet-node-network-id node)
          :public-api-modules (devnet-node-public-api-modules node)
          :engine-cors-origins (devnet-node-engine-cors-origins node)
          :public-cors-origins (devnet-node-public-cors-origins node)
          :engine-vhosts (devnet-node-engine-vhosts node)
          :public-vhosts (devnet-node-public-vhosts node)
          :dev-mode-p (devnet-node-dev-mode-p node)
          :coinbase (address-to-hex (devnet-node-coinbase node))
          :allow-unprotected-transactions-p
          (devnet-node-allow-unprotected-transactions-p node)
          :txpool-price-limit (devnet-node-txpool-price-limit node)
          :txpool-price-bump-percent
          (devnet-node-txpool-price-bump-percent node)
          :txpool-account-slot-limit
          (devnet-node-txpool-account-slot-limit node)
          :txpool-global-slot-limit
          (devnet-node-txpool-global-slot-limit node)
          :txpool-account-queue-limit
          (devnet-node-txpool-account-queue-limit node)
          :txpool-global-queue-limit
          (devnet-node-txpool-global-queue-limit node)
          :txpool-local-addresses
          (mapcar #'address-to-hex (or (devnet-node-txpool-local-addresses node)
                                       '()))
          :txpool-no-local-exemptions-p
          (devnet-node-txpool-no-local-exemptions-p node)
          :txpool-lifetime-seconds
          (devnet-node-txpool-lifetime-seconds node)
          :txpool-journal-path (devnet-node-txpool-journal-path node)
          :txpool-rejournal-seconds
          (devnet-node-txpool-rejournal-seconds node)
          :dev-period-seconds (devnet-node-dev-period-seconds node)
          :kzg-verifier-command (devnet-node-kzg-verifier-command node)
          :kzg-verifier-timeout-seconds
          (devnet-node-kzg-verifier-timeout-seconds node)
          :kzg-proof-verification-available-p
          (kzg-proof-verification-available-p)
          :chain-id (chain-config-chain-id (devnet-node-config node))
          :head-number (devnet-block-number head)
          :head-hash (devnet-block-hash-hex head)
          :safe-number (devnet-block-number safe)
          :safe-hash (devnet-block-hash-hex safe)
          :finalized-number (devnet-block-number finalized)
          :finalized-hash (devnet-block-hash-hex finalized)
          :head-gas-limit
          (and head
               (block-header-gas-limit (block-header head)))
          :state-available-p
          (and head
               (chain-store-state-available-p store (block-hash head))))))

(defun devnet-node-summary-json-object
    (node &key engine-endpoint rpc-endpoint (public-rpc-enabled-p t))
  (let ((summary (devnet-node-summary
                  node
                  :engine-endpoint engine-endpoint
                  :rpc-endpoint rpc-endpoint
                  :public-rpc-enabled-p public-rpc-enabled-p)))
    `(("genesisPath" . ,(getf summary :genesis-path))
      ("engineEndpoint" . ,(getf summary :engine-endpoint))
      ("rpcEndpoint" . ,(or (getf summary :rpc-endpoint) :false))
      ("publicRpcEnabled" . ,(if (getf summary :public-rpc-enabled-p)
                                 t
                                 :false))
      ("engineRpcPrefix" . ,(getf summary :engine-rpc-prefix))
      ("publicRpcPrefix" . ,(getf summary :public-rpc-prefix))
      ("processId" . ,(or (getf summary :process-id) :false))
      ("authRequired" . ,(if (getf summary :auth-required-p) t :false))
      ("jwtSecretPath" . ,(getf summary :jwt-secret-path))
      ("logPath" . ,(getf summary :log-path))
      ("databasePath" . ,(getf summary :database-path))
      ("pidFilePath" . ,(getf summary :pid-file-path))
      ("devMode" . ,(if (getf summary :dev-mode-p) t :false))
      ("coinbase" . ,(getf summary :coinbase))
      ("allowUnprotectedTransactions" .
       ,(if (getf summary :allow-unprotected-transactions-p) t :false))
      ("txpoolPriceLimit" . ,(or (getf summary :txpool-price-limit) :false))
      ("txpoolPriceBump" .
       ,(or (getf summary :txpool-price-bump-percent) :false))
      ("txpoolAccountSlots" .
       ,(or (getf summary :txpool-account-slot-limit) :false))
      ("txpoolGlobalSlots" .
       ,(or (getf summary :txpool-global-slot-limit) :false))
      ("txpoolAccountQueue" .
       ,(or (getf summary :txpool-account-queue-limit) :false))
      ("txpoolGlobalQueue" .
       ,(or (getf summary :txpool-global-queue-limit) :false))
      ("txpoolLocals" . ,(getf summary :txpool-local-addresses))
      ("txpoolNoLocals" .
       ,(if (getf summary :txpool-no-local-exemptions-p) t :false))
      ("txpoolLifetimeSeconds" .
       ,(or (getf summary :txpool-lifetime-seconds) :false))
      ("txpoolJournalPath" .
       ,(or (getf summary :txpool-journal-path) :false))
      ("txpoolRejournalSeconds" .
       ,(or (getf summary :txpool-rejournal-seconds) :false))
      ("devPeriodSeconds" .
       ,(or (getf summary :dev-period-seconds) :false))
      ("networkId" . ,(getf summary :network-id))
      ("publicApiModules" . ,(getf summary :public-api-modules))
      ("engineCorsOrigins" . ,(getf summary :engine-cors-origins))
      ("publicCorsOrigins" . ,(getf summary :public-cors-origins))
      ("engineVhosts" . ,(getf summary :engine-vhosts))
      ("publicVhosts" . ,(getf summary :public-vhosts))
      ("kzgVerifierCommand" . ,(or (getf summary :kzg-verifier-command)
                                   :false))
      ("kzgVerifierTimeoutSeconds" .
       ,(or (getf summary :kzg-verifier-timeout-seconds) :false))
      ("kzgProofVerificationAvailable" .
       ,(if (getf summary :kzg-proof-verification-available-p) t :false))
      ("chainId" . ,(getf summary :chain-id))
      ("headNumber" . ,(getf summary :head-number))
      ("headHash" . ,(getf summary :head-hash))
      ("headGasLimit" . ,(or (getf summary :head-gas-limit) :false))
      ("safeNumber" . ,(or (getf summary :safe-number) :false))
      ("safeHash" . ,(or (getf summary :safe-hash) :false))
      ("finalizedNumber" . ,(or (getf summary :finalized-number) :false))
      ("finalizedHash" . ,(or (getf summary :finalized-hash) :false))
      ("stateAvailable" . ,(if (getf summary :state-available-p) t :false)))))

(defun devnet-start-rejournal-thread
    (node shutdown-controller error-callback)
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((state
          (make-devnet-rejournal-state
           node
           (devnet-node-txpool-rejournal-seconds node))))
    (when (devnet-rejournal-state-enabled-p state)
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (loop until (devnet-shutdown-requested-p shutdown-controller)
                   do (sleep 1)
                      (unless (devnet-shutdown-requested-p
                               shutdown-controller)
                        (devnet-rejournal-state-tick state)))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-txpool-rejournal"))))

(defun devnet-start-dev-period-thread
    (node shutdown-controller error-callback)
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((state
          (make-devnet-dev-period-state
           node
           (devnet-node-dev-period-seconds node))))
    (when (devnet-dev-period-state-enabled-p state)
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (loop until (devnet-shutdown-requested-p shutdown-controller)
                   do (sleep 1)
                      (unless (devnet-shutdown-requested-p
                               shutdown-controller)
                        (devnet-dev-period-state-tick state)))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-dev-period"))))

(defun start-devnet-node-listeners
    (node engine-listener public-listener
     &key max-connections stop-p shutdown-controller on-listeners-ready)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (unless (typep engine-listener 'engine-rpc-http-listener)
    (error "Devnet Engine listener must be engine-rpc-http-listener"))
  (when (and public-listener
             (not (typep public-listener 'engine-rpc-http-listener)))
    (error "Devnet public listener must be engine-rpc-http-listener"))
  (when (and stop-p (not (functionp stop-p)))
    (error "Devnet stop predicate must be a function"))
  (when (and shutdown-controller
             (not (typep shutdown-controller 'devnet-shutdown-controller)))
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (when (and on-listeners-ready (not (functionp on-listeners-ready)))
    (error "Devnet listener-ready callback must be a function"))
  #-sbcl
  (declare (ignore node engine-listener public-listener max-connections stop-p
                   shutdown-controller on-listeners-ready))
  #-sbcl
  (error "Devnet split listener serving requires SBCL threads")
  #+sbcl
  (let* ((shutdown-controller
           (or shutdown-controller (make-devnet-shutdown-controller)))
         (stop-requested-p
           (lambda ()
             (or (devnet-shutdown-requested-p shutdown-controller)
                 (and stop-p (funcall stop-p)))))
         (engine-count nil)
         (engine-error nil)
         (public-count nil)
         (public-error nil)
         (rejournal-error nil)
         (rejournal-thread nil)
         (dev-period-error nil)
         (dev-period-thread nil))
    (devnet-shutdown-controller-register-listeners
     shutdown-controller engine-listener public-listener)
    (handler-case
        (when on-listeners-ready
          (funcall on-listeners-ready engine-listener public-listener))
      (error (condition)
        (devnet-shutdown-request shutdown-controller)
        (error condition)))
    (setf rejournal-thread
          (devnet-start-rejournal-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf rejournal-error condition))))
    (setf dev-period-thread
          (devnet-start-dev-period-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf dev-period-error condition))))
    (let ((result nil))
      (unwind-protect
           (setf result
                 (if public-listener
                     (let ((engine-thread
                             (sb-thread:make-thread
                              (lambda ()
                                (handler-case
                                    (setf engine-count
                                          (engine-rpc-http-service-serve-listener
                                           (devnet-node-service node)
                                           engine-listener
                                           :max-connections max-connections
                                           :stop-p stop-requested-p))
                                  (error (condition)
                                    (setf engine-error condition)
                                    (devnet-shutdown-request
                                     shutdown-controller))))
                              :name "ethereum-lisp-devnet-engine-rpc")))
                       (handler-case
                           (setf public-count
                                 (engine-rpc-http-service-serve-listener
                                  (devnet-node-public-service node)
                                  public-listener
                                  :max-connections max-connections
                                  :stop-p stop-requested-p))
                         (error (condition)
                           (setf public-error condition)
                           (devnet-shutdown-request shutdown-controller)))
                       (when public-count
                         (devnet-shutdown-request shutdown-controller))
                       (sb-thread:join-thread engine-thread)
                       (cond
                         (public-error (error public-error))
                         (engine-error (error engine-error))
                         (t
                          (list :engine-connections engine-count
                                :public-connections public-count
                                :total-connections
                                (+ engine-count public-count)))))
                     (handler-case
                         (let ((engine-count
                                 (engine-rpc-http-service-serve-listener
                                  (devnet-node-service node)
                                  engine-listener
                                  :max-connections max-connections
                                  :stop-p stop-requested-p)))
                           (devnet-shutdown-request shutdown-controller)
                           (list :engine-connections engine-count
                                 :public-connections 0
                                 :total-connections engine-count))
                       (error (condition)
                         (devnet-shutdown-request shutdown-controller)
                         (error condition)))))
        (when rejournal-thread
          (devnet-shutdown-request shutdown-controller)
          (sb-thread:join-thread rejournal-thread))
        (when dev-period-thread
          (devnet-shutdown-request shutdown-controller)
          (sb-thread:join-thread dev-period-thread)))
      (when rejournal-error
        (error rejournal-error))
      (when dev-period-error
        (error dev-period-error))
      result)))

(defun start-devnet-node
    (node &key max-connections stop-p shutdown-controller
            install-signal-handlers-p signal-stream on-listeners-ready
            (public-rpc-enabled-p t))
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (when (and shutdown-controller
             (not (typep shutdown-controller 'devnet-shutdown-controller)))
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (when (and on-listeners-ready (not (functionp on-listeners-ready)))
    (error "Devnet listener-ready callback must be a function"))
  (let ((shutdown-controller
          (or shutdown-controller (make-devnet-shutdown-controller)))
        (engine-listener nil)
        (public-listener nil)
        (served-p nil))
    (unwind-protect
         (progn
           (setf engine-listener
                 (make-engine-rpc-http-socket-listener
                  (devnet-node-service node)))
           (devnet-shutdown-controller-register-listeners
            shutdown-controller engine-listener nil)
           (when public-rpc-enabled-p
             (setf public-listener
                   (make-engine-rpc-http-socket-listener
                    (devnet-node-public-service node))))
           (devnet-shutdown-controller-register-listeners
            shutdown-controller engine-listener public-listener)
           (prog1
               (flet ((serve ()
                        (start-devnet-node-listeners
                         node
                         engine-listener
                         public-listener
                         :max-connections max-connections
                         :stop-p stop-p
                         :shutdown-controller shutdown-controller
                         :on-listeners-ready on-listeners-ready)))
                 (if install-signal-handlers-p
                     (call-with-devnet-shutdown-signal-handlers
                      shutdown-controller
                      #'serve
                      :stream (or signal-stream *error-output*))
                     (serve)))
             (setf served-p t)))
      (unless served-p
        (devnet-shutdown-request shutdown-controller)))))
