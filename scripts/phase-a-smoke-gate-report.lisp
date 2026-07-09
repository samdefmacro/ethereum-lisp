(defun smoke-gate-report (suite-root pinned-p &key devnet-p drift-map-p)
  (let ((state (smoke-gate-state-summary suite-root (not pinned-p)
                                         :pinned-p pinned-p))
        (transaction
          (smoke-gate-transaction-summary suite-root (not pinned-p)
                                          :pinned-p pinned-p))
        (blockchain (smoke-gate-blockchain-summary suite-root pinned-p))
        (devnet (and devnet-p (smoke-gate-devnet-summary)))
        (devnet-side-reorg
          (and devnet-p (smoke-gate-devnet-side-reorg-summary)))
        (devnet-engine-only
          (and devnet-p (smoke-gate-devnet-engine-only-summary)))
        (drift-map
          (and drift-map-p (smoke-gate-drift-map-summary suite-root))))
    (append
     (list
      (cons "suiteRoot" suite-root)
      (cons "mode" (if pinned-p "pinned-v5.4.0" "in-repo"))
      (cons "status" "ok")
      (cons "executionSpecTests"
            (smoke-gate-execution-spec-tests-source))
      (cons "referenceClients" (smoke-gate-reference-clients))
      (cons "state" state)
      (cons "transaction" transaction)
      (cons "blockchain" blockchain))
     (smoke-gate-report-counts
      state transaction blockchain devnet devnet-side-reorg
      devnet-engine-only)
     (when devnet
       (list (cons "devnet" devnet)))
     (when devnet-side-reorg
       (list (cons "devnetSideReorg" devnet-side-reorg)))
     (when devnet-engine-only
       (list (cons "devnetEngineOnly" devnet-engine-only)))
     (when drift-map
       (list (cons "driftMap" drift-map))))))

(defun smoke-gate-print-text (report)
  (let ((state (smoke-gate-field report "state"))
        (transaction (smoke-gate-field report "transaction"))
        (blockchain (smoke-gate-field report "blockchain"))
        (execution-spec-tests
          (smoke-gate-field report "executionSpecTests"))
        (reference-clients (smoke-gate-field report "referenceClients"))
        (devnet (smoke-gate-field report "devnet"))
        (devnet-side-reorg (smoke-gate-field report "devnetSideReorg"))
        (devnet-engine-only (smoke-gate-field report "devnetEngineOnly"))
        (drift-map (smoke-gate-field report "driftMap")))
    (format t "~&status=~A~%" (smoke-gate-field report "status"))
    (format t "suiteRoot=~A~%" (smoke-gate-field report "suiteRoot"))
    (format t "mode=~A~%" (smoke-gate-field report "mode"))
    (format t "executionSpecTestsRepository=~A~%"
            (smoke-gate-field execution-spec-tests "repository"))
    (format t "executionSpecTestsRelease=~A~%"
            (smoke-gate-field execution-spec-tests "release"))
    (format t "executionSpecTestsTagTarget=~A~%"
            (smoke-gate-field execution-spec-tests "tagTarget"))
    (format t "executionSpecTestsArchive=~A~%"
            (smoke-gate-field execution-spec-tests "archive"))
    (dolist (client reference-clients)
      (format t "referenceClient[~A]=~A"
              (smoke-gate-field client "name")
              (smoke-gate-field client "status"))
      (when (smoke-gate-field client "commit")
        (format t ":~A" (smoke-gate-field client "commit")))
      (format t "~%"))
    (format t "stateStatus=~A~%" (smoke-gate-field state "status"))
    (format t "stateCount=~D~%" (smoke-gate-field state "count"))
    (format t "stateExecuted=~D~%"
            (smoke-gate-field state "executedCount"))
    (format t "transactionStatus=~A~%"
            (smoke-gate-field transaction "status"))
    (format t "transactionCount=~D~%"
            (smoke-gate-field transaction "count"))
    (format t "transactionExecuted=~D~%"
            (smoke-gate-field transaction "executedCount"))
    (format t "blockchainCount=~D~%"
            (smoke-gate-field blockchain "count"))
    (format t "blockchainExecuted=~D~%"
            (smoke-gate-field blockchain "executedCount"))
    (format t "blockchainBlockCount=~D~%"
            (smoke-gate-field blockchain "blockCount"))
    (format t "blockchainKindCounts=~S~%"
            (smoke-gate-field blockchain "kindCounts"))
    (format t "fixtureCaseCount=~D~%"
            (smoke-gate-field report "fixtureCaseCount"))
    (format t "fixtureExecutedCount=~D~%"
            (smoke-gate-field report "fixtureExecutedCount"))
    (format t "totalCaseCount=~D~%"
            (smoke-gate-field report "totalCaseCount"))
    (format t "totalExecutedCount=~D~%"
            (smoke-gate-field report "totalExecutedCount"))
    (when drift-map
      (format t "driftMapStatus=~A~%"
              (smoke-gate-field drift-map "status"))
      (format t "driftMapCandidateCount=~D~%"
              (smoke-gate-field drift-map "candidateCount"))
      (format t "driftMapClassifiedCount=~D~%"
              (smoke-gate-field drift-map "classifiedCount"))
      (format t "driftMapPassingCount=~D~%"
              (smoke-gate-field drift-map "passingCount"))
      (format t "driftMapKnownImplementationDriftCount=~D~%"
              (smoke-gate-field drift-map
                                "knownImplementationDriftCount"))
      (format t "driftMapOutOfScopeForkFeatureCount=~D~%"
              (smoke-gate-field drift-map
                                "outOfScopeForkFeatureCount"))
      (format t "driftMapImplementationBugCandidateCount=~D~%"
              (smoke-gate-field drift-map
                                "implementationBugCandidateCount"))
      (format t "driftMapFixtureHarnessErrorCount=~D~%"
              (smoke-gate-field drift-map "fixtureHarnessErrorCount"))
      (format t "driftMapPhaseAMaterializableClear=~A~%"
              (smoke-gate-field drift-map "phaseAMaterializableClear")))
    (when devnet
      (format t "devnetStatus=~A~%" (smoke-gate-field devnet "status"))
      (format t "devnetCaseCount=~D~%" (smoke-gate-field devnet "caseCount"))
      (format t "devnetReadyCaseCount=~D~%"
              (smoke-gate-field devnet "readyCaseCount"))
      (format t "devnetLogCaseCount=~D~%"
              (smoke-gate-field devnet "logCaseCount"))
      (format t "devnetDatabaseCaseCount=~D~%"
              (smoke-gate-field devnet "databaseCaseCount"))
      (format t "devnetDatabasePruneStateBefore=~A~%"
              (smoke-gate-field devnet "databasePruneStateBefore"))
      (format t "devnetDatabasePrunedStateCaseCount=~D~%"
              (smoke-gate-field devnet "databasePrunedStateCaseCount"))
      (format t "devnetDatabaseRpcPrunedStateErrorCaseCount=~D~%"
              (smoke-gate-field
               devnet "databaseRpcPrunedStateErrorCaseCount"))
      (format t "devnetSuiteSideReorgCaseCount=~D~%"
              (smoke-gate-field devnet "sideReorgCaseCount"))
      (format t "devnetTotalConnections=~D~%"
              (smoke-gate-field devnet "totalConnections")))
    (when devnet-side-reorg
      (format t "devnetSideReorgStatus=~A~%"
              (smoke-gate-field devnet-side-reorg "status"))
      (format t "devnetSideReorgFixtureCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "caseCount"))
      (format t "devnetSideReorgFixtureCases=~S~%"
              (smoke-gate-field devnet-side-reorg "fixtureCases"))
      (format t "devnetSideReorgCaseCount=~D~%"
              (smoke-gate-field
               devnet-side-reorg "sideReorgCaseCount"))
      (format t "devnetSideReorgReadyCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "readyCaseCount"))
      (format t "devnetSideReorgLogCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "logCaseCount"))
      (format t "devnetSideReorgPidCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "pidCaseCount"))
      (format t "devnetSideReorgDatabaseCaseCount=~D~%"
              (smoke-gate-field devnet-side-reorg "databaseCaseCount")))
    (when devnet-engine-only
      (format t "devnetEngineOnlyStatus=~A~%"
              (smoke-gate-field devnet-engine-only "status"))
      (format t "devnetEngineOnlyCaseCount=~D~%"
              (smoke-gate-field devnet-engine-only "caseCount"))
      (format t "devnetEngineOnlyPublicRpcEnabled=~A~%"
              (smoke-gate-field devnet-engine-only "publicRpcEnabled"))
      (format t "devnetEngineOnlyEngineRpcPrefix=~A~%"
              (smoke-gate-field devnet-engine-only "engineRpcPrefix"))
      (format t "devnetEngineOnlyEngineRpcPrefixStatus=~D~%"
              (smoke-gate-field devnet-engine-only
                                "engineRpcPrefixStatus"))
      (format t "devnetEngineOnlyEngineRpcPrefixBlockedStatus=~D~%"
              (smoke-gate-field devnet-engine-only
                                "engineRpcPrefixBlockedStatus"))
      (format t "devnetEngineOnlyEngineCorsOrigins=~S~%"
              (smoke-gate-field devnet-engine-only
                                "engineCorsOrigins"))
      (format t "devnetEngineOnlyEngineCorsHeader=~A~%"
              (smoke-gate-field devnet-engine-only
                                "engineCorsHeader"))
      (format t "devnetEngineOnlyEngineVhosts=~S~%"
              (smoke-gate-field devnet-engine-only "engineVhosts"))
      (format t "devnetEngineOnlyEngineCapabilityCount=~D~%"
              (smoke-gate-field devnet-engine-only "engineCapabilityCount"))
      (format t "devnetEngineOnlyEngineCapabilityHasNewPayloadV1=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineCapabilityHasNewPayloadV1"))
      (format t "devnetEngineOnlyEngineCapabilityHasForkchoiceUpdatedV1=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineCapabilityHasForkchoiceUpdatedV1"))
      (format t "devnetEngineOnlyEngineCapabilityHasGetPayloadV1=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineCapabilityHasGetPayloadV1"))
      (format t "devnetEngineOnlyEngineCapabilityHasNewPayloadV2=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineCapabilityHasNewPayloadV2"))
      (format t "devnetEngineOnlyEngineCapabilityHasForkchoiceUpdatedV2=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineCapabilityHasForkchoiceUpdatedV2"))
      (format t "devnetEngineOnlyEngineCapabilityHasGetPayloadV2=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineCapabilityHasGetPayloadV2"))
      (format t "devnetEngineOnlyEngineCapabilityHasNewPayloadV3=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineCapabilityHasNewPayloadV3"))
      (format t "devnetEngineOnlyEngineCapabilityHasGetBlobsV1=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineCapabilityHasGetBlobsV1"))
      (format t "devnetEngineOnlyEngineCapabilityHasPayloadBodiesV2=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineCapabilityHasPayloadBodiesV2"))
      (format t "devnetEngineOnlyEngineClientVersionCode=~A~%"
              (smoke-gate-field devnet-engine-only
                                "engineClientVersionCode"))
      (format t "devnetEngineOnlyEngineClientVersionName=~A~%"
              (smoke-gate-field devnet-engine-only
                                "engineClientVersionName"))
      (format t "devnetEngineOnlyEngineClientVersionVersion=~A~%"
              (smoke-gate-field devnet-engine-only
                                "engineClientVersionVersion"))
      (format t "devnetEngineOnlyEngineClientVersionCommit=~A~%"
              (smoke-gate-field devnet-engine-only
                                "engineClientVersionCommit"))
      (format t "devnetEngineOnlyEngineTransitionTerminalTotalDifficulty=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineTransitionTerminalTotalDifficulty"))
      (format t "devnetEngineOnlyEngineTransitionTerminalBlockHash=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineTransitionTerminalBlockHash"))
      (format t "devnetEngineOnlyEngineTransitionTerminalBlockNumber=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineTransitionTerminalBlockNumber"))
      (format t "devnetEngineOnlyEngineTransitionMismatchErrorCode=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineTransitionMismatchErrorCode"))
      (format t "devnetEngineOnlyEngineTransitionMismatchErrorMessage=~A~%"
              (smoke-gate-field
               devnet-engine-only "engineTransitionMismatchErrorMessage"))
      (format t "devnetEngineOnlyNewPayloadStatus=~A~%"
              (smoke-gate-field devnet-engine-only
                                "newPayloadStatus"))
      (format t "devnetEngineOnlyLatestValidHash=~A~%"
              (smoke-gate-field devnet-engine-only
                                "latestValidHash"))
      (format t "devnetEngineOnlyForkchoiceStatus=~A~%"
              (smoke-gate-field devnet-engine-only
                                "forkchoiceStatus"))
      (format t "devnetEngineOnlyDatabaseHeadNumber=~A~%"
              (smoke-gate-field devnet-engine-only
                                "databaseHeadNumber"))
      (format t "devnetEngineOnlyDatabaseHeadHash=~A~%"
              (smoke-gate-field devnet-engine-only
                                "databaseHeadHash"))
      (format t "devnetEngineOnlyDatabaseStateAvailable=~A~%"
              (smoke-gate-field devnet-engine-only
                                "databaseStateAvailable"))
      (format t "devnetEngineOnlyConfiguredPublicEndpoint=~A~%"
              (smoke-gate-field devnet-engine-only
                                "configuredPublicEndpoint"))
      (format t "devnetEngineOnlyPublicEndpointConnectable=~A~%"
              (smoke-gate-field devnet-engine-only
                                "publicEndpointConnectable"))
      (format t "devnetEngineOnlyEngineConnections=~D~%"
              (smoke-gate-field devnet-engine-only "engineConnections"))
      (format t "devnetEngineOnlyPublicConnections=~D~%"
              (smoke-gate-field devnet-engine-only "publicConnections"))
      (format t "devnetEngineOnlyTotalConnections=~D~%"
              (smoke-gate-field devnet-engine-only "totalConnections")))))

