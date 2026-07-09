(in-package #:ethereum-lisp.test)

(deftest devnet-smoke-gate-script-writes-ready-and-log-files
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let* ((artifact-root
           (devnet-cli-temp-directory "ethereum-lisp-devnet-smoke-artifacts"))
         (ready-path
           (merge-pathnames "ready/nested/devnet-ready.json" artifact-root))
         (log-path
           (merge-pathnames "logs/nested/devnet.log" artifact-root))
         (pid-path
           (merge-pathnames "pid/nested/devnet.pid" artifact-root))
         (database-path
           (merge-pathnames "database/nested/devnet-chain.sexp" artifact-root))
         (terminal-block-hash
           "0x4444444444444444444444444444444444444444444444444444444444444444")
         (reference-token
           (format nil "~A-~A" (sb-unix:unix-getpid) (gensym))))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "env"
                    (format nil "ETHEREUM_LISP_GETH_ROOT=/private/tmp/ethereum-lisp-devnet-geth-root-~A/"
                            reference-token)
                    (format nil "ETHEREUM_LISP_NETHERMIND_ROOT=/private/tmp/ethereum-lisp-devnet-nethermind-root-~A/"
                            reference-token)
                    (format nil "ETHEREUM_LISP_RETH_ROOT=/private/tmp/ethereum-lisp-devnet-reth-root-~A/"
                            reference-token)
                    "sbcl"
                    "--script"
                    "scripts/devnet-smoke-gate.lisp"
                    "--"
                    "--json=true"
                    "--all-fixtures=false"
                    (format nil "--ready-file=~A" (namestring ready-path))
                    (format nil "--log-file=~A" (namestring log-path))
                    (format nil "--pid-file=~A" (namestring pid-path))
                    (format nil "--database=~A" (namestring database-path))
                    "--prune-state-before=42"
                    "--override.terminaltotaldifficulty=0x3039"
                    "--override.terminaltotaldifficultypassed=true"
                    (format nil "--override.terminalblockhash=~A"
                            terminal-block-hash)
                    "--override.terminalblocknumber=66")
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (is (search "\"txpoolPendingFilterEmptyChanges\":[]" stdout))
           (when (= 0 status)
             (let* ((report (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (database
                      (make-file-key-value-database database-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (reference-clients
                      (fixture-object-field report "referenceClients"))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records)))
               (is (string= "ok" (fixture-object-field report "status")))
               (is (string= "devnet-listener-boundary"
                            (fixture-object-field report "mode")))
               (phase-a-smoke-gate-assert-execution-spec-tests-source report)
               (is (= 3 (length reference-clients)))
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "geth")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "nethermind")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "reth")
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "geth"
                (format nil "/private/tmp/ethereum-lisp-devnet-geth-root-~A/"
                        reference-token))
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "nethermind"
                (format nil "/private/tmp/ethereum-lisp-devnet-nethermind-root-~A/"
                        reference-token))
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "reth"
                (format nil "/private/tmp/ethereum-lisp-devnet-reth-root-~A/"
                        reference-token))
               (is (string= (namestring ready-path)
                            (fixture-object-field report "readyFile")))
               (is (string= (namestring log-path)
                            (fixture-object-field report "logFile")))
               (is (string= (namestring pid-path)
                            (fixture-object-field report "pidFile")))
               (is (string= "http://127.0.0.1:8551"
                            (fixture-object-field report "engineEndpoint")))
               (is (string= "http://127.0.0.1:8545"
                            (fixture-object-field report "rpcEndpoint")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineUnauthenticatedStatus")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineInvalidAuthStatus")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineDuplicateAuthStatus")))
               (is (= 404
                      (fixture-object-field
                       report
                       "engineRootWrongPathStatus")))
               (devnet-cli-assert-engine-capability-report report)
               (devnet-cli-assert-engine-client-version report)
               (devnet-cli-assert-engine-transition-configuration
                report
                :terminal-total-difficulty "0x3039"
                :terminal-block-hash terminal-block-hash
                :terminal-block-number "0x42")
               (devnet-cli-assert-engine-payload-bodies report)
               (devnet-cli-assert-engine-get-payload-v2 report)
               (is (= -32601
                      (fixture-object-field
                       report
                       "enginePublicNamespaceErrorCode")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicEngineNamespaceErrorCode")))
               (is (= -32700
                      (fixture-object-field
                       report
                       "publicMalformedJsonErrorCode")))
               (is (= 404
                      (fixture-object-field
                       report
                       "publicRootWrongPathStatus")))
               (is (equal '("eth" "net")
                          (fixture-object-field report
                                                "publicApiAllowlist")))
               (is (equal '("eth" "net")
                          (fixture-object-field
                           report
                           "publicApiAllowlistReportedModules")))
               (is (string= "eth,net"
                            (fixture-object-field
                             report
                             "publicApiAllowlistTelemetryModules")))
               (is (= 0
                      (fixture-object-field
                       report
                       "publicApiAllowlistEngineConnections")))
               (is (= 6
                      (fixture-object-field
                       report
                       "publicApiAllowlistPublicConnections")))
               (is (= 6
                      (fixture-object-field
                       report
                       "publicApiAllowlistTotalConnections")))
               (is (string= "0x539"
                            (fixture-object-field
                             report
                             "publicApiAllowlistChainId")))
               (is (string= "7331"
                            (fixture-object-field
                             report
                             "publicApiAllowlistNetworkVersion")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicApiBlockedWeb3ErrorCode")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicApiBlockedTxpoolErrorCode")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicApiBlockedEngineErrorCode")))
               (devnet-cli-assert-public-cors-smoke-report report)
               (devnet-cli-assert-engine-cors-smoke-report report)
               (devnet-cli-assert-http-shaping-smoke-report report)
               (devnet-cli-assert-vhost-smoke-report report)
               (devnet-cli-assert-rpc-prefix-smoke-report report)
               (devnet-cli-assert-connection-contract report 1)
               (is (= (fixture-object-field ready-summary "processId")
                      (devnet-cli-pid-file-process-id pid-path)))
               (is (string= (namestring database-path)
                            (fixture-object-field report "databaseFile")))
               (is (= 42 (fixture-object-field
                          report "databasePruneStateBefore")))
               (is (eq nil
                       (fixture-object-field
                        report "databasePrunedStateAvailable")))
               (is (string= "eth_getBalance state is not available"
                            (fixture-object-field
                             report "databaseRpcPrunedStateError")))
               (let ((errors
                       (fixture-object-field
                        report "databaseRpcPrunedStateErrors")))
                 (is (= 8 (length errors)))
                 (dolist (message (devnet-cli-pruned-state-error-messages))
                   (is (member message errors :test #'string=))))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database
                    :state
                    (hash32-bytes
                     (hash32-from-hex
                      (fixture-object-field report "safeBlockHash")))
                    :missing)
                 (is (eq :missing value))
                 (is (not present-p)))
               (is (string= (fixture-object-field
                              report "txpoolImportBlockNumber")
                            (fixture-object-field report
                                                  "databaseHeadNumber")))
               (is (string= (fixture-object-field report "blockGasLimit")
                            (fixture-object-field report
                                                  "databaseHeadGasLimit")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (fixture-object-field report
                                                  "databaseSafeNumber")))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field report "databaseSafeHash")))
               (is (string= (fixture-object-field
                              report "finalizedBlockNumber")
                            (fixture-object-field
                             report "databaseFinalizedNumber")))
               (is (string= (fixture-object-field report "finalizedBlockHash")
                            (fixture-object-field
                             report "databaseFinalizedHash")))
               (is (string= (fixture-object-field
                              report "txpoolImportBlockNumber")
                            (fixture-object-field
                             report "databaseRpcBlockNumber")))
               (is (string= (fixture-object-field report "checkedBalance")
                            (fixture-object-field
                             report "databaseRpcBalance")))
               (is (string= (fixture-object-field report "checkedNonce")
                            (fixture-object-field report "databaseRpcNonce")))
               (is (string= (fixture-object-field report "checkedCode")
                            (fixture-object-field report "databaseRpcCode")))
               (is (string= (fixture-object-field report "checkedStorage")
                            (fixture-object-field
                             report "databaseRpcStorage")))
               (is (string= (fixture-object-field
                              report "checkedStorageAddress")
                            (fixture-object-field
                             report "databaseRpcProofAddress")))
               (is (string= (fixture-object-field
                              report "checkedProofCodeHash")
                            (fixture-object-field
                             report "databaseRpcProofCodeHash")))
               (is (string= (fixture-object-field report "checkedStorageKey")
                            (fixture-object-field
                             report "databaseRpcProofStorageKey")))
               (is (string= (fixture-object-field
                              report "checkedProofStorageValue")
                            (fixture-object-field
                             report "databaseRpcProofStorageValue")))
               (is (= 1 (fixture-object-field
                         report "databaseRpcProofStorageCount")))
               (is (<= 0 (fixture-object-field
                          report "databaseRpcProofAccountProofCount")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByHashNumber")
                            (fixture-object-field report "blockNumber")))
               (is (stringp
                    (fixture-object-field report "databaseRpcBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberNumber")
                            (fixture-object-field report "blockNumber")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberHash")
                            (fixture-object-field
                             report "databaseRpcBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcTransactionBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcTransactionBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (= (fixture-object-field report "transactionCount")
                      (fixture-object-field
                       report "databaseRpcBlockReceiptsCount")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockReceiptTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcBlockReceiptBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockReceiptBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (= (fixture-object-field report "transactionCount")
                      (fixture-object-field report
                                            "databaseRpcTransactionCount")))
               (devnet-cli-assert-restored-full-block-transactions report)
               (is (= (fixture-object-field report "checkedBalanceCount")
                      (fixture-object-field report
                                            "databaseRpcBalanceCount")))
               (is (= (fixture-object-field report "checkedLogCount")
                      (fixture-object-field report
                                            "databaseRpcLogCount")))
               (devnet-cli-assert-restored-log-filters report)
               (devnet-cli-assert-restored-block-filter report)
               (is (string= (quantity-to-hex
                              (fixture-object-field report "transactionCount"))
                            (fixture-object-field
                             report
                             "databaseRpcBlockTransactionCountByHash")))
               (is (string= (quantity-to-hex
                              (fixture-object-field report "transactionCount"))
                            (fixture-object-field
                             report
                             "databaseRpcBlockTransactionCountByNumber")))
               (is (string= (fixture-object-field report "databaseRpcBalance")
                            (fixture-object-field
                             report "databaseRpcCanonicalHashBalance")))
               (is (string= (fixture-object-field report "databaseRpcBalance")
                            (fixture-object-field
                             report
                             "databaseRpcCanonicalHashRequireBalance")))
               (is (string= (fixture-object-field
                              report
                              "databaseRpcRawTransactionByBlockHashAndIndex")
                            (fixture-object-field
                             report
                             "databaseRpcRawTransactionByBlockNumberAndIndex")))
               (is (string= (fixture-object-field
                              report
                              "databaseRpcRawTransactionByHash")
                            (fixture-object-field
                             report
                             "databaseRpcRawTransactionByBlockHashAndIndex")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexBlockHash")))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexBlockNumber")))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexBlockNumber")))
               (is (string= "0x0"
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexIndex")))
               (is (string= "0x0"
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexIndex")))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field
                             report "databaseRpcSafeBlockHash")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (fixture-object-field
                             report "databaseRpcSafeBlockNumber")))
               (is (string= (fixture-object-field report "finalizedBlockHash")
                            (fixture-object-field
                             report "databaseRpcFinalizedBlockHash")))
               (is (string= (fixture-object-field
                              report "finalizedBlockNumber")
                            (fixture-object-field
                             report "databaseRpcFinalizedBlockNumber")))
               (is (= (fixture-object-field report "checkedSimulationCount")
                      (fixture-object-field report
                                            "databaseRpcSimulationCount")))
               (is (string= "0x"
                            (fixture-object-field
                             report "databaseRpcCallResult")))
               (is (<= 21000
                       (hex-to-quantity
                        (fixture-object-field
                         report "databaseRpcEstimateGas"))))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcAccessListGasUsed")))
               (is (string= (fixture-object-field report "checkedStorage")
                            (fixture-object-field
                             report "databaseRpcPostCallStorage")))
               (is (= (devnet-cli-restored-public-connections report)
                      (fixture-object-field
                       report "databaseRpcPublicConnections")))
               (is (string= (fixture-object-field report "preparedPayloadId")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadId")))
               (is (string= (fixture-object-field
                              report "preparedPayloadParentHash")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadParentHash")))
               (is (string= (fixture-object-field
                              report "preparedPayloadBlockNumber")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadBlockNumber")))
               (is (string= +payload-status-syncing+
                            (fixture-object-field report "remoteBlockStatus")))
               (is (string= (fixture-object-field report "remoteBlockHash")
                            (fixture-object-field
                             report "databaseRemoteBlockHash")))
               (is (string= +payload-status-syncing+
                            (fixture-object-field
                             report "databaseRpcRemoteBlockStatus")))
               (is (string= +payload-status-invalid+
                            (fixture-object-field report
                                                  "invalidTipsetStatus")))
               (is (string= "Timestamp is not greater than parent timestamp"
                            (fixture-object-field
                             report "invalidTipsetValidationError")))
               (is (string= (fixture-object-field
                              report "invalidTipsetBlockHash")
                            (fixture-object-field
                             report "databaseInvalidTipsetBlockHash")))
               (is (string= +payload-status-invalid+
                            (fixture-object-field
                             report "databaseRpcInvalidTipsetStatus")))
               (is (string= "links to previously rejected block"
                            (fixture-object-field
                             report
                             "databaseRpcInvalidTipsetValidationError")))
               (devnet-cli-assert-txpool-subpool-persistence report)
               (devnet-cli-assert-side-reorg-persistence report)
               (is (< 0 (length (kv-chain-record-entries database :block))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :prepared-payload))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :remote-block))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :invalid-tipset))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :txpool))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :canonical-hash))))
               (is (string= "http://127.0.0.1:8551"
                            (fixture-object-field ready-summary
                                                  "engineEndpoint")))
               (is (string= "http://127.0.0.1:8545"
                            (fixture-object-field ready-summary
                                                  "rpcEndpoint")))
               (is (integerp (fixture-object-field ready-summary
                                                    "processId")))
               (is (< 0 (fixture-object-field ready-summary "processId")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (eq t (fixture-object-field ready-summary
                                                "stateAvailable")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (quantity-to-hex
                             (fixture-object-field ready-summary
                                                   "headNumber"))))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field ready-summary
                                                  "headHash")))
               (is (string= (fixture-object-field report "safeBlockGasLimit")
                            (quantity-to-hex
                             (fixture-object-field ready-summary
                                                   "headGasLimit"))))
               (is (string= (namestring database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (when (member (getf log-record :name)
                               '("devnet.ready" "devnet.shutdown")
                               :test #'string=)
                   (let* ((fields (getf log-record :fields))
                          (ready-p (string= "devnet.ready"
                                            (getf log-record :name)))
	                          (expected-head-number
	                            (fixture-object-field
	                             report
	                             (if ready-p
	                                 "safeBlockNumber"
	                                 "txpoolImportBlockNumber")))
	                          (expected-head-hash
	                            (fixture-object-field
	                             report
	                             (if ready-p
	                                 "safeBlockHash"
	                                 "txpoolImportBlockHash")))
                          (expected-head-gas-limit
                            (fixture-object-field
                             report
                             (if ready-p
                                 "safeBlockGasLimit"
                                 "blockGasLimit"))))
                     (is (string= expected-head-number
                                  (cdr (assoc "headNumber" fields
                                              :test #'string=))))
                     (is (string= expected-head-hash
                                  (cdr (assoc "headHash" fields
                                              :test #'string=))))
                     (is (string= expected-head-gas-limit
                                  (cdr (assoc "headGasLimit" fields
                                              :test #'string=))))
                     (is (string= (if ready-p "ready" "shutdown")
                                  (cdr (assoc "lifecyclePhase" fields
                                              :test #'string=))))
                     (is (string= (fixture-object-field report
                                                        "engineEndpoint")
                                  (cdr (assoc "engineEndpoint" fields
                                              :test #'string=))))
                     (is (string= (fixture-object-field report "rpcEndpoint")
                                  (cdr (assoc "rpcEndpoint" fields
                                              :test #'string=))))
                     (is (string= (write-to-string
                                    (fixture-object-field ready-summary
                                                          "processId"))
                                  (cdr (assoc "processId" fields
                                              :test #'string=))))
                     (is (string= "true"
                                  (cdr (assoc "stateAvailable" fields
                                              :test #'string=))))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file database-path)
        (delete-file database-path)))))

