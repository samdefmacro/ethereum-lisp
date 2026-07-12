(in-package #:ethereum-lisp.test)

(deftest phase-a-smoke-gate-script-can-include-devnet-suite
  (:layer :e2e :module :devnet-smoke :launches-processes t
   :requires-local-sockets t)
  #-sbcl
  (skip-test "Phase A smoke gate devnet mode requires SBCL")
  #+sbcl
  (let ((prune-boundary 42))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--json"
               "--devnet")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (when (and (not (= 0 status))
                 (search "Operation not permitted" stderr))
        (skip-test "Local socket bind is not permitted in this sandbox"))
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (reference-clients
                 (fixture-object-field report "referenceClients"))
               (devnet (fixture-object-field report "devnet"))
               (devnet-side-reorg
                 (fixture-object-field report "devnetSideReorg"))
               (devnet-engine-only
                 (fixture-object-field report "devnetEngineOnly"))
               (cases (fixture-object-field devnet "cases")))
        (is (string= "ok" (fixture-object-field report "status")))
        (is (string= "in-repo" (fixture-object-field report "mode")))
        (phase-a-smoke-gate-assert-execution-spec-tests-source report)
        (phase-a-smoke-gate-assert-counts report)
        (phase-a-smoke-gate-assert-in-repo-fixture-counts report)
        (is (= 3 (length reference-clients)))
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "geth")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "nethermind")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "reth")
        (is (string= "ok" (fixture-object-field devnet "status")))
        (is (string= "devnet-listener-boundary-suite"
                     (fixture-object-field devnet "mode")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "caseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "readyCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-files devnet "readyFile"))))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "logCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-files devnet "logFile"))))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "pidCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-files devnet "pidFile"))))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "databaseCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-database-files devnet))))
        (devnet-cli-assert-pruned-state-suite
         devnet cases prune-boundary)
        (is (= 0 (fixture-object-field devnet "sideReorgCaseCount")))
        (is (string= "ok"
                     (fixture-object-field
                      devnet-engine-only "status")))
        (is (string= "devnet-engine-only-serve"
                     (fixture-object-field
                      devnet-engine-only "mode")))
        (is (= 1 (fixture-object-field
                  devnet-engine-only "caseCount")))
        (is (not (fixture-object-field
                  devnet-engine-only "publicRpcEnabled")))
        (is (not (fixture-object-field
                  devnet-engine-only "rpcEndpoint")))
        (is (string= "/engine"
                     (fixture-object-field
                      devnet-engine-only "engineRpcPrefix")))
        (is (= 200 (fixture-object-field
                    devnet-engine-only "engineRpcPrefixStatus")))
        (is (= 404 (fixture-object-field
                    devnet-engine-only
                    "engineRpcPrefixBlockedStatus")))
        (devnet-cli-assert-engine-only-http-shaping-report
         devnet-engine-only)
        (devnet-cli-assert-engine-capability-report
         devnet-engine-only)
        (devnet-cli-assert-engine-client-version
         devnet-engine-only)
        (devnet-cli-assert-engine-transition-configuration
         devnet-engine-only)
        (devnet-cli-assert-engine-only-payload-report
         devnet-engine-only)
        (devnet-cli-assert-engine-only-hidden-payload-bodies-v2-report
         devnet-engine-only)
        (devnet-cli-assert-engine-only-database-report
         devnet-engine-only)
        (is (search "http://127.0.0.1:"
                    (fixture-object-field
                     devnet-engine-only "configuredPublicEndpoint")))
        (is (not (fixture-object-field
                  devnet-engine-only "publicEndpointConnectable")))
        (devnet-cli-assert-engine-only-connection-contract
         devnet-engine-only)
        (let ((side-reorg-cases
                (fixture-object-field devnet-side-reorg "cases")))
          (is (string= "ok"
                       (fixture-object-field devnet-side-reorg "status")))
          (is (string= "devnet-side-reorg-suite"
                       (fixture-object-field devnet-side-reorg "mode")))
          (is (equal +devnet-side-reorg-smoke-case-names+
                     (fixture-object-field
                      devnet-side-reorg "fixtureCases")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field devnet-side-reorg "caseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "sideReorgCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "readyCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "logCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "pidCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "databaseCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (length side-reorg-cases)))
          (dolist (case side-reorg-cases)
            (devnet-cli-assert-side-reorg-persistence case))
          (let ((log-case
                  (find "shanghai-log-contract-call-with-withdrawal"
                        side-reorg-cases
                        :key (lambda (case)
                               (fixture-object-field case "fixtureCase"))
                        :test #'string=)))
            (is log-case)
            (when log-case
              (is (= 1 (fixture-object-field log-case "checkedLogCount")))
              (is (= 1 (fixture-object-field
                        log-case "databaseRpcLogCount")))
              (devnet-cli-assert-restored-log-filters log-case)
              (devnet-cli-assert-restored-block-filter log-case)))
          (let ((two-transfer-case
                  (find "shanghai-two-legacy-transfers-with-withdrawal"
                        side-reorg-cases
                        :key (lambda (case)
                               (fixture-object-field case "fixtureCase"))
                        :test #'string=)))
            (is two-transfer-case)
            (when two-transfer-case
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideReinsertedTransactionCount")))
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideRestoredReinsertedTransactionCount")))
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideHiddenReceiptCount")))
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideRestoredHiddenReceiptCount")))
              (is (= 2 (length
                        (fixture-object-field
                         two-transfer-case
                         "databaseRpcSideReinsertedTransactionHashes")))))))
        (is (= (* 23 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "engineConnections")))
        (is (= (* 54 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "publicConnections")))
        (is (= (* 77 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "totalConnections")))
        (dolist (case cases)
          (devnet-cli-assert-public-readiness case)
          (is (string= (fixture-object-field case "txpoolImportBlockNumber")
                       (fixture-object-field
                        case "databaseRpcBlockNumber")))
          (is (string= (fixture-object-field case "safeBlockNumber")
                       (fixture-object-field
                        case "databaseSafeNumber")))
          (is (string= (fixture-object-field case "safeBlockHash")
                       (fixture-object-field case "databaseSafeHash")))
          (is (string= (fixture-object-field case "finalizedBlockNumber")
                       (fixture-object-field
                        case "databaseFinalizedNumber")))
          (is (string= (fixture-object-field case "finalizedBlockHash")
                       (fixture-object-field
                        case "databaseFinalizedHash")))
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
          (is (string= (fixture-object-field case "checkedStorageAddress")
                       (fixture-object-field
                        case "databaseRpcProofAddress")))
          (is (string= (fixture-object-field case "checkedProofCodeHash")
                       (fixture-object-field
                        case "databaseRpcProofCodeHash")))
          (is (string= (fixture-object-field case "checkedStorageKey")
                       (fixture-object-field
                        case "databaseRpcProofStorageKey")))
          (is (string= (fixture-object-field case "checkedProofStorageValue")
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
          (is (string= (fixture-object-field case "finalizedBlockNumber")
                       (fixture-object-field
                        case "databaseRpcFinalizedBlockNumber")))
          (is (= (fixture-object-field case "checkedSimulationCount")
                 (fixture-object-field case "databaseRpcSimulationCount")))
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
          (devnet-cli-assert-engine-get-payload-v2 case)
          (is (string= +payload-status-syncing+
                       (fixture-object-field case "remoteBlockStatus")))
          (is (string= (fixture-object-field case "remoteBlockHash")
                       (fixture-object-field
                        case "databaseRemoteBlockHash")))
          (is (string= +payload-status-syncing+
                       (fixture-object-field
                        case "databaseRpcRemoteBlockStatus")))
          (is (string= +payload-status-invalid+
                       (fixture-object-field case "invalidTipsetStatus")))
          (is (string= "Timestamp is not greater than parent timestamp"
                       (fixture-object-field
                        case "invalidTipsetValidationError")))
          (is (string= (fixture-object-field case "invalidTipsetBlockHash")
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
          (devnet-cli-assert-side-reorg-persistence case)))))))

(deftest phase-a-smoke-gate-devnet-mode-is-cwd-independent
  (:layer :e2e :module :devnet-smoke :launches-processes t
   :requires-local-sockets t)
  #-sbcl
  (skip-test "Phase A smoke gate cwd-independent devnet mode requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/phase-a-smoke-gate.lisp")))
        (root (namestring
               (truename "tests/fixtures/execution-spec-tests-root/"))))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "sbcl"
               "--script"
               script
               "--"
               "--json"
               "--devnet"
               "--root"
               root)
         :directory #P"/private/tmp/"
         :output :string
         :error-output :string
         :ignore-error-status t)
      (when (and (not (= 0 status))
                 (search "Operation not permitted" stderr))
        (skip-test "Local socket bind is not permitted in this sandbox"))
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (devnet (fixture-object-field report "devnet"))
               (devnet-side-reorg
                 (fixture-object-field report "devnetSideReorg"))
               (devnet-engine-only
                 (fixture-object-field report "devnetEngineOnly")))
          (is (string= "ok" (fixture-object-field report "status")))
          (phase-a-smoke-gate-assert-counts report)
          (is (string= "ok" (fixture-object-field devnet "status")))
          (is (string= "devnet-listener-boundary-suite"
                       (fixture-object-field devnet "mode")))
          (is (= 0 (fixture-object-field
                    devnet "sideReorgCaseCount")))
          (is (string= "ok"
                       (fixture-object-field
                        devnet-side-reorg "status")))
          (is (string= "devnet-side-reorg-suite"
                       (fixture-object-field
                        devnet-side-reorg "mode")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "sideReorgCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "readyCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "logCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "pidCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "databaseCaseCount")))
          (is (string= "ok"
                       (fixture-object-field
                        devnet-engine-only "status")))
          (is (string= "devnet-engine-only-serve"
                       (fixture-object-field
                        devnet-engine-only "mode")))
          (is (= 1 (fixture-object-field
                    devnet-engine-only "caseCount")))
          (is (string= "/engine"
                       (fixture-object-field
                        devnet-engine-only "engineRpcPrefix")))
          (is (= 200 (fixture-object-field
                      devnet-engine-only "engineRpcPrefixStatus")))
          (is (= 404 (fixture-object-field
                      devnet-engine-only
                      "engineRpcPrefixBlockedStatus")))
          (devnet-cli-assert-engine-only-http-shaping-report
           devnet-engine-only)
          (devnet-cli-assert-engine-capability-report
           devnet-engine-only)
          (devnet-cli-assert-engine-client-version
           devnet-engine-only)
          (devnet-cli-assert-engine-transition-configuration
            devnet-engine-only)
          (devnet-cli-assert-engine-only-payload-report
           devnet-engine-only)
          (devnet-cli-assert-engine-only-hidden-payload-bodies-v2-report
           devnet-engine-only)
          (devnet-cli-assert-engine-only-database-report
           devnet-engine-only)
          (is (search "http://127.0.0.1:"
                      (fixture-object-field
                       devnet-engine-only "configuredPublicEndpoint")))
          (is (not (fixture-object-field
                    devnet-engine-only "publicEndpointConnectable")))
          (devnet-cli-assert-engine-only-connection-contract
           devnet-engine-only))))))

(deftest phase-a-smoke-gate-text-output-includes-aggregate-counts
  #-sbcl
  (skip-test "Phase A smoke gate text output test requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "fixtureCaseCount=" stdout))
    (is (search "fixtureExecutedCount=" stdout))
    (is (search "totalCaseCount=" stdout))
    (is (search "totalExecutedCount=" stdout))
    (is (search "blockchainCount=9" stdout))
    (is (search "blockchainExecuted=9" stdout))
    (is (search "(\"engineNewPayloadV2\" . 8)" stdout))
    (is (search "(\"blockRlp\" . 1)" stdout))
    (is (search "fixtureCaseCount=38" stdout))
    (is (search "fixtureExecutedCount=38" stdout))))

(deftest phase-a-smoke-gate-drift-map-fails-on-materializable-gaps
  #-sbcl
  (skip-test "Phase A smoke gate drift map failure requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--drift-map"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Phase A drift map found materializable selector gaps"
                stderr))
    (is (search "implementationBugCandidates=1" stderr))))

(deftest phase-a-smoke-gate-pinned-mode-defaults-to-eest-root-env
  #-sbcl
  (skip-test "Phase A smoke gate pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (devnet-cli-temp-directory
            "ethereum-lisp-pinned-smoke-root"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               (format nil "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                       root-string)
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Phase A smoke gate requires an EEST blockchain root"
                  stderr)))))

(deftest phase-a-smoke-gate-pinned-mode-requires-root
  #-sbcl
  (skip-test "Phase A smoke gate pinned mode requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "env"
             "-u"
             "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
             "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--pinned-v5.4.0"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Pinned Phase A smoke gate requires an EEST fixture root"
                stderr))
    (is (search "--root" stderr))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stderr))
    (is (not (search "do not match pinned selectors" stderr)))))

(deftest phase-a-smoke-gate-pinned-mode-rejects-missing-env-root
  #-sbcl
  (skip-test "Phase A smoke gate pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-pinned-smoke-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               (format nil "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                       root-string)
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Pinned Phase A smoke gate root from" stderr))
      (is (not (search "do not match pinned selectors" stderr))))))
