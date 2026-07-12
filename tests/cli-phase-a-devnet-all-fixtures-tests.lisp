(in-package #:ethereum-lisp.test)

(deftest devnet-smoke-gate-script-runs-all-pinned-fixtures
  (:estimated-seconds 80d0)
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let ((ready-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite-ready"
                                "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite"
                                "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite"
                                "pid"))
        (database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite-chain"
                                "sexp"))
        (prune-boundary 42)
        (ready-files nil)
        (log-files nil)
        (pid-files nil)
        (database-files nil))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    "scripts/devnet-smoke-gate.lisp"
                    "--"
                    "--json"
                    "--all-fixtures"
                    "--ready-file" (namestring ready-path)
                    "--log-file" (namestring log-path)
                    "--pid-file" (namestring pid-path)
                    "--database" (namestring database-path)
                    "--prune-state-before"
                    (write-to-string prune-boundary))
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((report (parse-json stdout))
                    (cases (fixture-object-field report "cases"))
                    (reference-clients
                      (fixture-object-field report "referenceClients"))
                    (case-names
                      (mapcar (lambda (case)
                                (fixture-object-field case "fixtureCase"))
                              cases)))
               (setf database-files
                     (devnet-smoke-gate-case-database-files report)
                     ready-files
                     (devnet-smoke-gate-case-files report "readyFile")
                     log-files
                     (devnet-smoke-gate-case-files report "logFile")
                     pid-files
                     (devnet-smoke-gate-case-files report "pidFile"))
               (is (string= "ok" (fixture-object-field report "status")))
               (is (string= "devnet-listener-boundary-suite"
                            (fixture-object-field report "mode")))
               (phase-a-smoke-gate-assert-execution-spec-tests-source report)
               (is (= 3 (length reference-clients)))
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "geth")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "nethermind")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "reth")
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "caseCount")))
               (is (string= (namestring ready-path)
                            (fixture-object-field report "readyFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "readyCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length ready-files)))
               (is (string= (namestring log-path)
                            (fixture-object-field report "logFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "logCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length log-files)))
               (is (string= (namestring pid-path)
                            (fixture-object-field report "pidFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "pidCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length pid-files)))
               (is (string= (namestring database-path)
                            (fixture-object-field report "databaseFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "databaseCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length database-files)))
               (devnet-cli-assert-pruned-state-suite
                report cases prune-boundary)
               (is (= (* 23 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "engineConnections")))
               (is (= (* 54 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "publicConnections")))
               (is (= (* 77 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "totalConnections")))
               (devnet-cli-assert-connection-contract
                report
                (length +engine-newpayload-v2-smoke-case-names+))
               (is (equal +engine-newpayload-v2-smoke-case-names+ case-names))
               (dolist (case cases)
                 (let ((expected-block-number
                         (devnet-cli-engine-fixture-payload-number
                          (fixture-object-field case "fixtureCase"))))
                   (is (string= "ok" (fixture-object-field case "status")))
                   (is (string= +payload-status-valid+
                                (fixture-object-field
                                 case "newPayloadStatus")))
                   (is (string= +payload-status-valid+
                                (fixture-object-field
                                 case "forkchoiceStatus")))
                   (is (= 23 (fixture-object-field case "engineConnections")))
                   (is (= 54 (fixture-object-field case "publicConnections")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineUnauthenticatedStatus")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineInvalidAuthStatus")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineDuplicateAuthStatus")))
                   (is (= 404
                          (fixture-object-field
                           case
                           "engineRootWrongPathStatus")))
                   (devnet-cli-assert-engine-capability-report case)
                   (devnet-cli-assert-engine-client-version case)
                   (devnet-cli-assert-engine-transition-configuration case)
                   (devnet-cli-assert-public-readiness case)
                   (devnet-cli-assert-engine-payload-bodies case)
                   (devnet-cli-assert-engine-get-payload-v2 case)
                   (is (= -32601
                          (fixture-object-field
                           case
                           "enginePublicNamespaceErrorCode")))
                   (is (= -32601
                          (fixture-object-field
                           case
                           "publicEngineNamespaceErrorCode")))
                   (is (= -32700
                          (fixture-object-field
                           case
                           "publicMalformedJsonErrorCode")))
                   (is (= 404
                          (fixture-object-field
                           case
                           "publicRootWrongPathStatus")))
                   (devnet-cli-assert-public-cors-smoke-report case)
                   (devnet-cli-assert-engine-cors-smoke-report case)
                   (devnet-cli-assert-http-shaping-smoke-report case)
                   (devnet-cli-assert-vhost-smoke-report case)
                   (devnet-cli-assert-rpc-prefix-smoke-report case)
                   (is (string= expected-block-number
                                 (fixture-object-field case "blockNumber"))))
                 (is (string= (fixture-object-field
                                case "txpoolImportBlockNumber")
                              (fixture-object-field
                               case "databaseHeadNumber")))
                 (is (string= (fixture-object-field case "blockGasLimit")
                              (fixture-object-field
                               case "databaseHeadGasLimit")))
                 (is (string= (fixture-object-field case "safeBlockNumber")
                              (fixture-object-field
                               case "databaseSafeNumber")))
                 (is (stringp (fixture-object-field
                                case "safeBlockGasLimit")))
                 (is (string= (fixture-object-field case "safeBlockHash")
                              (fixture-object-field
                               case "databaseSafeHash")))
                 (is (string= (fixture-object-field
                                case "finalizedBlockNumber")
                              (fixture-object-field
                               case "databaseFinalizedNumber")))
                 (is (string= (fixture-object-field case "finalizedBlockHash")
                              (fixture-object-field
                               case "databaseFinalizedHash")))
                 (is (string= (fixture-object-field
                                case "txpoolImportBlockNumber")
                              (fixture-object-field
                               case "databaseRpcBlockNumber")))
                 (is (string= (fixture-object-field case "checkedBalance")
                              (fixture-object-field
                               case "databaseRpcBalance")))
                 (is (string= (fixture-object-field case "checkedNonce")
                              (fixture-object-field
                               case "databaseRpcNonce")))
                 (is (string= (fixture-object-field case "checkedCode")
                              (fixture-object-field
                               case "databaseRpcCode")))
                 (is (string= (fixture-object-field case "checkedStorage")
                              (fixture-object-field
                               case "databaseRpcStorage")))
                 (is (string= (fixture-object-field
                                case "checkedStorageAddress")
                              (fixture-object-field
                               case "databaseRpcProofAddress")))
                 (is (string= (fixture-object-field
                                case "checkedProofCodeHash")
                              (fixture-object-field
                               case "databaseRpcProofCodeHash")))
                 (is (string= (fixture-object-field case "checkedStorageKey")
                              (fixture-object-field
                               case "databaseRpcProofStorageKey")))
                 (is (string= (fixture-object-field
                                case "checkedProofStorageValue")
                              (fixture-object-field
                               case "databaseRpcProofStorageValue")))
                 (is (= 1 (fixture-object-field
                           case "databaseRpcProofStorageCount")))
                 (is (<= 0 (fixture-object-field
                            case "databaseRpcProofAccountProofCount")))
                 (is (string= (fixture-object-field
                                case "databaseRpcReceiptBlockNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcReceiptTransactionHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByHashNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (stringp
                      (fixture-object-field case "databaseRpcBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByNumberNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByNumberHash")
                              (fixture-object-field
                               case "databaseRpcBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByNumberTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcTransactionBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcTransactionBlockNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (= (fixture-object-field case "transactionCount")
                        (fixture-object-field
                         case "databaseRpcBlockReceiptsCount")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockReceiptTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcBlockReceiptBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockReceiptBlockNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (= (fixture-object-field case "transactionCount")
                        (fixture-object-field case
                                              "databaseRpcTransactionCount")))
                 (devnet-cli-assert-restored-full-block-transactions case)
                 (is (= (fixture-object-field case "checkedBalanceCount")
                        (fixture-object-field case "databaseRpcBalanceCount")))
                 (is (= (fixture-object-field case "checkedLogCount")
                        (fixture-object-field case "databaseRpcLogCount")))
                 (devnet-cli-assert-restored-log-filters case)
                 (devnet-cli-assert-restored-block-filter case)
                 (is (string= (quantity-to-hex
                                (fixture-object-field case "transactionCount"))
                              (fixture-object-field
                               case
                               "databaseRpcBlockTransactionCountByHash")))
                 (is (string= (quantity-to-hex
                                (fixture-object-field case "transactionCount"))
                              (fixture-object-field
                               case
                               "databaseRpcBlockTransactionCountByNumber")))
                 (is (string= (fixture-object-field case "databaseRpcBalance")
                              (fixture-object-field
                               case "databaseRpcCanonicalHashBalance")))
                 (is (string= (fixture-object-field case "databaseRpcBalance")
                              (fixture-object-field
                               case
                               "databaseRpcCanonicalHashRequireBalance")))
                 (is (string= (fixture-object-field
                                case
                                "databaseRpcRawTransactionByBlockHashAndIndex")
                              (fixture-object-field
                               case
                               "databaseRpcRawTransactionByBlockNumberAndIndex")))
                 (is (string= (fixture-object-field
                                case
                                "databaseRpcRawTransactionByHash")
                              (fixture-object-field
                               case
                               "databaseRpcRawTransactionByBlockHashAndIndex")))
                 (is (string= (fixture-object-field
                                case "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexBlockHash")))
                 (is (string= (fixture-object-field case "blockNumber")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexBlockNumber")))
                 (is (string= (fixture-object-field case "blockNumber")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexBlockNumber")))
                 (is (string= "0x0"
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexIndex")))
                 (is (string= "0x0"
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexIndex")))
                 (is (string= (fixture-object-field case "safeBlockHash")
                              (fixture-object-field
                               case "databaseRpcSafeBlockHash")))
                 (is (string= (fixture-object-field case "safeBlockNumber")
                              (fixture-object-field
                               case "databaseRpcSafeBlockNumber")))
                 (is (string= (fixture-object-field case "finalizedBlockHash")
                              (fixture-object-field
                               case "databaseRpcFinalizedBlockHash")))
                 (is (string= (fixture-object-field
                                case "finalizedBlockNumber")
                              (fixture-object-field
                               case "databaseRpcFinalizedBlockNumber")))
                 (is (= (fixture-object-field case "checkedSimulationCount")
                        (fixture-object-field
                         case "databaseRpcSimulationCount")))
                 (is (string= "0x"
                              (fixture-object-field
                               case "databaseRpcCallResult")))
                 (is (<= 21000
                         (hex-to-quantity
                          (fixture-object-field
                           case "databaseRpcEstimateGas"))))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcAccessListGasUsed")))
                 (is (string= (fixture-object-field case "checkedStorage")
                              (fixture-object-field
                               case "databaseRpcPostCallStorage")))
                 (is (= (devnet-cli-restored-public-connections case)
                        (fixture-object-field
                         case "databaseRpcPublicConnections")))
                 (is (string= (fixture-object-field case "preparedPayloadId")
                              (fixture-object-field
                               case "databaseRpcPreparedPayloadId")))
                 (is (string= (fixture-object-field
                                case "preparedPayloadParentHash")
                              (fixture-object-field
                               case "databaseRpcPreparedPayloadParentHash")))
                 (is (string= (fixture-object-field
                                case "preparedPayloadBlockNumber")
                              (fixture-object-field
                               case "databaseRpcPreparedPayloadBlockNumber")))
                 (is (string= +payload-status-syncing+
                              (fixture-object-field case "remoteBlockStatus")))
                 (is (string= (fixture-object-field case "remoteBlockHash")
                              (fixture-object-field
                               case "databaseRemoteBlockHash")))
                 (is (string= +payload-status-syncing+
                              (fixture-object-field
                               case "databaseRpcRemoteBlockStatus")))
                 (is (string= +payload-status-invalid+
                              (fixture-object-field case
                                                    "invalidTipsetStatus")))
                 (is (string= "Timestamp is not greater than parent timestamp"
                              (fixture-object-field
                               case "invalidTipsetValidationError")))
                 (is (string= (fixture-object-field
                                case "invalidTipsetBlockHash")
                              (fixture-object-field
                               case "databaseInvalidTipsetBlockHash")))
                 (is (string= +payload-status-invalid+
                              (fixture-object-field
                               case "databaseRpcInvalidTipsetStatus")))
                 (is (string= "links to previously rejected block"
                              (fixture-object-field
                               case
                               "databaseRpcInvalidTipsetValidationError")))
                 (devnet-cli-assert-txpool-subpool-persistence case)
                 (devnet-cli-assert-side-reorg-persistence case)
                 (is (probe-file
                      (fixture-object-field case "readyFile")))
                 (is (probe-file
                      (fixture-object-field case "logFile")))
                 (is (probe-file
                      (fixture-object-field case "databaseFile")))))))
      (dolist (path (append ready-files log-files pid-files database-files))
        (when (probe-file path)
          (delete-file path)))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file database-path)
        (delete-file database-path)))))
