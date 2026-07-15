(in-package #:ethereum-lisp.cli)

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
