(in-package #:ethereum-lisp.cli)

(defun devnet-node-telemetry-fields
    (node &key engine-endpoint rpc-endpoint lifecycle-phase
            connection-summary (public-rpc-enabled-p t))
  (let ((summary (devnet-node-summary
                  node
                  :engine-endpoint engine-endpoint
                  :rpc-endpoint rpc-endpoint
                  :public-rpc-enabled-p public-rpc-enabled-p)))
    `(("engineEndpoint" . ,(getf summary :engine-endpoint))
      ("rpcEndpoint" . ,(or (getf summary :rpc-endpoint) ""))
      ("publicRpcEnabled" . ,(if (getf summary :public-rpc-enabled-p)
                                 "true"
                                 "false"))
      ("lifecyclePhase" . ,(or lifecycle-phase ""))
      ("engineConnections" . ,(write-to-string
                               (or (getf connection-summary
                                         :engine-connections)
                                   0)))
      ("publicConnections" . ,(write-to-string
                               (or (getf connection-summary
                                         :public-connections)
                                   0)))
      ("totalConnections" . ,(write-to-string
                              (or (getf connection-summary
                                        :total-connections)
                                  0)))
      ("processId" . ,(let ((process-id (getf summary :process-id)))
                         (if process-id
                             (write-to-string process-id)
                             "")))
      ("chainId" . ,(quantity-to-hex (getf summary :chain-id)))
      ("headNumber" . ,(quantity-to-hex (getf summary :head-number)))
      ("headHash" . ,(getf summary :head-hash))
      ("coinbase" . ,(getf summary :coinbase))
      ("allowUnprotectedTransactions" .
       ,(if (getf summary :allow-unprotected-transactions-p)
            "true"
            "false"))
      ("txpoolPriceLimit" .
       ,(if (getf summary :txpool-price-limit)
            (quantity-to-hex (getf summary :txpool-price-limit))
            ""))
      ("txpoolPriceBump" .
       ,(if (getf summary :txpool-price-bump-percent)
            (write-to-string (getf summary :txpool-price-bump-percent))
            ""))
      ("txpoolAccountSlots" .
       ,(if (getf summary :txpool-account-slot-limit)
            (write-to-string (getf summary :txpool-account-slot-limit))
            ""))
      ("txpoolGlobalSlots" .
       ,(if (getf summary :txpool-global-slot-limit)
            (write-to-string (getf summary :txpool-global-slot-limit))
            ""))
      ("txpoolAccountQueue" .
       ,(if (getf summary :txpool-account-queue-limit)
            (write-to-string (getf summary :txpool-account-queue-limit))
            ""))
      ("txpoolGlobalQueue" .
       ,(if (getf summary :txpool-global-queue-limit)
            (write-to-string (getf summary :txpool-global-queue-limit))
            ""))
      ("txpoolLocals" .
       ,(format nil "~{~A~^,~}" (getf summary :txpool-local-addresses)))
      ("txpoolNoLocals" .
       ,(if (getf summary :txpool-no-local-exemptions-p) "true" "false"))
      ("txpoolLifetimeSeconds" .
       ,(if (getf summary :txpool-lifetime-seconds)
            (write-to-string (getf summary :txpool-lifetime-seconds))
            ""))
      ("txpoolJournalPath" . ,(or (getf summary :txpool-journal-path) ""))
      ("txpoolRejournalSeconds" .
       ,(if (getf summary :txpool-rejournal-seconds)
            (write-to-string (getf summary :txpool-rejournal-seconds))
            ""))
      ("devPeriodSeconds" .
       ,(if (getf summary :dev-period-seconds)
            (write-to-string (getf summary :dev-period-seconds))
            ""))
      ("headGasLimit" . ,(if (getf summary :head-gas-limit)
                              (quantity-to-hex
                               (getf summary :head-gas-limit))
                              ""))
      ("safeNumber" . ,(if (getf summary :safe-number)
                            (quantity-to-hex (getf summary :safe-number))
                            ""))
      ("safeHash" . ,(or (getf summary :safe-hash) ""))
      ("finalizedNumber" . ,(if (getf summary :finalized-number)
                                 (quantity-to-hex
                                  (getf summary :finalized-number))
                                 ""))
      ("finalizedHash" . ,(or (getf summary :finalized-hash) ""))
      ("stateAvailable" . ,(if (getf summary :state-available-p)
                                "true"
                                "false"))
      ("authRequired" . ,(if (getf summary :auth-required-p) "true" "false"))
      ("jwtSecretPath" . ,(or (getf summary :jwt-secret-path) ""))
      ("engineRpcPrefix" . ,(getf summary :engine-rpc-prefix))
      ("publicRpcPrefix" . ,(getf summary :public-rpc-prefix))
      ("logPath" . ,(or (getf summary :log-path) ""))
      ("databasePath" . ,(or (getf summary :database-path) ""))
      ("networkId" . ,(quantity-to-hex (getf summary :network-id)))
      ("publicApiModules" .
       ,(if (getf summary :public-api-modules)
            (format nil "~{~A~^,~}" (getf summary :public-api-modules))
            ""))
      ("engineCorsOrigins" .
       ,(if (getf summary :engine-cors-origins)
            (format nil "~{~A~^,~}" (getf summary :engine-cors-origins))
            ""))
      ("publicCorsOrigins" .
       ,(if (getf summary :public-cors-origins)
            (format nil "~{~A~^,~}" (getf summary :public-cors-origins))
            ""))
      ("engineVhosts" .
       ,(if (getf summary :engine-vhosts)
            (format nil "~{~A~^,~}" (getf summary :engine-vhosts))
            ""))
      ("publicVhosts" .
       ,(if (getf summary :public-vhosts)
            (format nil "~{~A~^,~}" (getf summary :public-vhosts))
            ""))
      ("kzgVerifierCommand" .
       ,(or (getf summary :kzg-verifier-command) ""))
      ("kzgVerifierTimeoutSeconds" .
       ,(if (getf summary :kzg-verifier-timeout-seconds)
            (write-to-string (getf summary :kzg-verifier-timeout-seconds))
            ""))
      ("kzgProofVerificationAvailable" .
       ,(if (getf summary :kzg-proof-verification-available-p)
            "true"
            "false"))
      ("pidFilePath" . ,(or (getf summary :pid-file-path) "")))))

(defun devnet-cli-log-event
    (node name &key engine-endpoint rpc-endpoint connection-summary
            (public-rpc-enabled-p t))
  (ethereum-lisp.telemetry:telemetry-log
   :info
   name
   :sink (devnet-node-telemetry-sink node)
   :fields (devnet-node-telemetry-fields
            node
            :engine-endpoint engine-endpoint
            :rpc-endpoint rpc-endpoint
            :public-rpc-enabled-p public-rpc-enabled-p
            :lifecycle-phase
            (cond
              ((string= name "devnet.ready") "ready")
              ((string= name "devnet.shutdown") "shutdown")
              ((string= name "devnet.error") "error")
              ((string= name "init.ready") "ready")
              ((string= name "init.shutdown") "shutdown")
              ((string= name "init.error") "error")
              (t ""))
            :connection-summary connection-summary)))
