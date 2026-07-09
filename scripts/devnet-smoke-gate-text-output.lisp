(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-print-text (report)
  (format t "~&status=~A~%" (devnet-smoke-gate-field report "status"))
  (format t "mode=~A~%" (devnet-smoke-gate-field report "mode"))
  (let ((execution-spec-tests
          (devnet-smoke-gate-field report "executionSpecTests"))
        (reference-clients
          (devnet-smoke-gate-field report "referenceClients")))
    (format t "executionSpecTestsRepository=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "repository"))
    (format t "executionSpecTestsRelease=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "release"))
    (format t "executionSpecTestsTagTarget=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "tagTarget"))
    (format t "executionSpecTestsArchive=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "archive"))
    (dolist (client reference-clients)
      (format t "referenceClient[~A]=~A"
              (devnet-smoke-gate-field client "name")
              (devnet-smoke-gate-field client "status"))
      (when (devnet-smoke-gate-field client "commit")
        (format t ":~A" (devnet-smoke-gate-field client "commit")))
      (format t "~%")))
  (when (devnet-smoke-gate-suite-report-p report)
    (format t "caseCount=~D~%" (devnet-smoke-gate-field report "caseCount"))
    (format t "readyFile=~A~%"
            (devnet-smoke-gate-field report "readyFile"))
    (format t "readyCaseCount=~D~%"
            (devnet-smoke-gate-field report "readyCaseCount"))
    (format t "logFile=~A~%"
            (devnet-smoke-gate-field report "logFile"))
    (format t "logCaseCount=~D~%"
            (devnet-smoke-gate-field report "logCaseCount"))
    (format t "pidFile=~A~%"
            (devnet-smoke-gate-field report "pidFile"))
    (format t "pidCaseCount=~D~%"
            (devnet-smoke-gate-field report "pidCaseCount"))
    (format t "databaseFile=~A~%"
            (devnet-smoke-gate-field report "databaseFile"))
    (format t "databasePruneStateBefore=~A~%"
            (devnet-smoke-gate-field report "databasePruneStateBefore"))
    (format t "databaseCaseCount=~D~%"
            (devnet-smoke-gate-field report "databaseCaseCount"))
    (format t "databasePrunedStateCaseCount=~D~%"
            (devnet-smoke-gate-field report
                                     "databasePrunedStateCaseCount"))
    (format t "databaseRpcPrunedStateErrorCaseCount=~D~%"
            (devnet-smoke-gate-field
             report "databaseRpcPrunedStateErrorCaseCount")))
  (when (devnet-smoke-gate-engine-only-report-p report)
    (format t "publicRpcEnabled=~A~%"
            (devnet-smoke-gate-field report "publicRpcEnabled"))
    (format t "engineEndpoint=~A~%"
            (devnet-smoke-gate-field report "engineEndpoint"))
    (format t "rpcEndpoint=~A~%"
            (devnet-smoke-gate-field report "rpcEndpoint"))
    (format t "hiddenBlobsV1Status=~A~%"
            (devnet-smoke-gate-field report "hiddenBlobsV1Status"))
    (format t "hiddenBlobsV1ErrorCode=~A~%"
            (devnet-smoke-gate-field report "hiddenBlobsV1ErrorCode"))
    (format t "hiddenBlobsV1ErrorMessage=~A~%"
            (devnet-smoke-gate-field report "hiddenBlobsV1ErrorMessage"))
    (format t "hiddenBlobsV2Status=~A~%"
            (devnet-smoke-gate-field report "hiddenBlobsV2Status"))
    (format t "hiddenBlobsV2ErrorCode=~A~%"
            (devnet-smoke-gate-field report "hiddenBlobsV2ErrorCode"))
    (format t "hiddenBlobsV2ErrorMessage=~A~%"
            (devnet-smoke-gate-field report "hiddenBlobsV2ErrorMessage"))
    (format t "readyFile=~A~%"
            (devnet-smoke-gate-field report "readyFile"))
    (format t "logFile=~A~%"
            (devnet-smoke-gate-field report "logFile"))
    (format t "pidFile=~A~%"
            (devnet-smoke-gate-field report "pidFile"))
    (format t "databaseFile=~A~%"
            (devnet-smoke-gate-field report "databaseFile"))
    (format t "databaseHeadNumber=~A~%"
            (devnet-smoke-gate-field report "databaseHeadNumber"))
    (format t "databaseHeadHash=~A~%"
            (devnet-smoke-gate-field report "databaseHeadHash"))
    (format t "databaseStateAvailable=~A~%"
            (devnet-smoke-gate-field report "databaseStateAvailable"))
    (format t "engineConnections=~D~%"
            (devnet-smoke-gate-field report "engineConnections"))
    (format t "publicConnections=~D~%"
            (devnet-smoke-gate-field report "publicConnections"))
    (format t "totalConnections=~D~%"
            (devnet-smoke-gate-field report "totalConnections"))
    (format t "engineCapabilityCount=~D~%"
            (devnet-smoke-gate-field report "engineCapabilityCount"))
    (format t "engineCapabilityHasNewPayloadV1=~A~%"
            (devnet-smoke-gate-field
             report "engineCapabilityHasNewPayloadV1"))
    (format t "engineCapabilityHasForkchoiceUpdatedV1=~A~%"
            (devnet-smoke-gate-field
             report "engineCapabilityHasForkchoiceUpdatedV1"))
    (format t "engineCapabilityHasGetPayloadV1=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasGetPayloadV1"))
    (format t "engineCapabilityHasNewPayloadV2=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasNewPayloadV2"))
    (format t "engineCapabilityHasForkchoiceUpdatedV2=~A~%"
            (devnet-smoke-gate-field
             report "engineCapabilityHasForkchoiceUpdatedV2"))
    (format t "engineCapabilityHasGetPayloadV2=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasGetPayloadV2"))
    (format t "engineCapabilityHasNewPayloadV3=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasNewPayloadV3"))
    (format t "engineCapabilityHasGetBlobsV1=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasGetBlobsV1"))
    (format t "engineCapabilityHasGetBlobsV2=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasGetBlobsV2"))
    (format t "engineCapabilityHasPayloadBodiesV2=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasPayloadBodiesV2"))
    (format t "engineClientVersionCode=~A~%"
            (devnet-smoke-gate-field report "engineClientVersionCode"))
    (format t "engineClientVersionName=~A~%"
            (devnet-smoke-gate-field report "engineClientVersionName"))
    (format t "engineClientVersionVersion=~A~%"
            (devnet-smoke-gate-field report "engineClientVersionVersion"))
    (format t "engineClientVersionCommit=~A~%"
            (devnet-smoke-gate-field report "engineClientVersionCommit"))
    (format t "engineTransitionTerminalTotalDifficulty=~A~%"
            (devnet-smoke-gate-field
             report "engineTransitionTerminalTotalDifficulty"))
    (format t "engineTransitionTerminalBlockHash=~A~%"
            (devnet-smoke-gate-field report "engineTransitionTerminalBlockHash"))
    (format t "engineTransitionTerminalBlockNumber=~A~%"
            (devnet-smoke-gate-field
             report "engineTransitionTerminalBlockNumber"))
    (format t "engineTransitionMismatchErrorCode=~A~%"
            (devnet-smoke-gate-field report "engineTransitionMismatchErrorCode"))
    (format t "engineTransitionMismatchErrorMessage=~A~%"
            (devnet-smoke-gate-field
             report "engineTransitionMismatchErrorMessage"))
    (format t "headNumber=~A~%"
            (devnet-smoke-gate-field report "headNumber"))
    (return-from devnet-smoke-gate-print-text nil))
  (unless (devnet-smoke-gate-suite-report-p report)
    (format t "fixtureCase=~A~%"
            (devnet-smoke-gate-field report "fixtureCase")))
  (format t "engineConnections=~D~%"
          (devnet-smoke-gate-field report "engineConnections"))
  (format t "publicConnections=~D~%"
          (devnet-smoke-gate-field report "publicConnections"))
  (format t "totalConnections=~D~%"
          (devnet-smoke-gate-field report "totalConnections"))
  (let ((connection-contract
          (devnet-smoke-gate-field report "connectionContract")))
    (format t "expectedEngineConnections=~D~%"
            (devnet-smoke-gate-field connection-contract
                                     "expectedEngineConnections"))
    (format t "expectedPublicConnections=~D~%"
            (devnet-smoke-gate-field connection-contract
                                     "expectedPublicConnections"))
    (format t "expectedTotalConnections=~D~%"
            (devnet-smoke-gate-field connection-contract
                                     "expectedTotalConnections")))
  (if (devnet-smoke-gate-suite-report-p report)
      (dolist (case-report (devnet-smoke-gate-field report "cases"))
        (format t "case=~A status=~A blockNumber=~A checkedBalance=~A~%"
                (devnet-smoke-gate-field case-report "fixtureCase")
                (devnet-smoke-gate-field case-report "newPayloadStatus")
                (devnet-smoke-gate-field case-report "blockNumber")
                (devnet-smoke-gate-field case-report "checkedBalance")))
      (progn
        (format t "engineUnauthenticatedStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "engineUnauthenticatedStatus"))
        (format t "engineInvalidAuthStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "engineInvalidAuthStatus"))
        (format t "engineDuplicateAuthStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "engineDuplicateAuthStatus"))
        (format t "engineRootWrongPathStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "engineRootWrongPathStatus"))
        (format t "engineCapabilityCount=~D~%"
                (devnet-smoke-gate-field report "engineCapabilityCount"))
        (format t "engineCapabilityHasNewPayloadV1=~A~%"
                (devnet-smoke-gate-field
                 report "engineCapabilityHasNewPayloadV1"))
        (format t "engineCapabilityHasForkchoiceUpdatedV1=~A~%"
                (devnet-smoke-gate-field
                 report "engineCapabilityHasForkchoiceUpdatedV1"))
        (format t "engineCapabilityHasGetPayloadV1=~A~%"
                (devnet-smoke-gate-field
                 report "engineCapabilityHasGetPayloadV1"))
        (format t "engineClientVersionCode=~A~%"
                (devnet-smoke-gate-field report "engineClientVersionCode"))
        (format t "engineClientVersionName=~A~%"
                (devnet-smoke-gate-field report "engineClientVersionName"))
        (format t "engineClientVersionVersion=~A~%"
                (devnet-smoke-gate-field report "engineClientVersionVersion"))
        (format t "engineClientVersionCommit=~A~%"
                (devnet-smoke-gate-field report "engineClientVersionCommit"))
        (format t "engineTransitionTerminalTotalDifficulty=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionTerminalTotalDifficulty"))
        (format t "engineTransitionTerminalBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionTerminalBlockHash"))
        (format t "engineTransitionTerminalBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionTerminalBlockNumber"))
        (format t "engineTransitionMismatchErrorCode=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionMismatchErrorCode"))
        (format t "engineTransitionMismatchErrorMessage=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionMismatchErrorMessage"))
        (format t "enginePublicNamespaceErrorCode=~A~%"
                (devnet-smoke-gate-field
                 report "enginePublicNamespaceErrorCode"))
        (format t "publicRootWrongPathStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "publicRootWrongPathStatus"))
        (format t "publicClientVersion=~A~%"
                (devnet-smoke-gate-field report "publicClientVersion"))
        (format t "publicNetVersion=~A~%"
                (devnet-smoke-gate-field report "publicNetVersion"))
        (format t "publicNetListening=~A~%"
                (devnet-smoke-gate-field report "publicNetListening"))
        (format t "publicSyncing=~A~%"
                (devnet-smoke-gate-field report "publicSyncing"))
        (format t "publicNetPeerCount=~A~%"
                (devnet-smoke-gate-field report "publicNetPeerCount"))
        (format t "publicAccountCount=~D~%"
                (devnet-smoke-gate-field report "publicAccountCount"))
        (format t "publicCoinbase=~A~%"
                (devnet-smoke-gate-field report "publicCoinbase"))
        (format t "publicMining=~A~%"
                (devnet-smoke-gate-field report "publicMining"))
        (format t "publicHashrate=~A~%"
                (devnet-smoke-gate-field report "publicHashrate"))
        (format t "publicRpcModules=~S~%"
                (devnet-smoke-gate-field report "publicRpcModules"))
        (format t "publicProtocolVersion=~A~%"
                (devnet-smoke-gate-field report "publicProtocolVersion"))
        (format t "publicWeb3Sha3=~A~%"
                (devnet-smoke-gate-field report "publicWeb3Sha3"))
        (format t "publicGasPrice=~A~%"
                (devnet-smoke-gate-field report "publicGasPrice"))
        (format t "publicMaxPriorityFeePerGas=~A~%"
                (devnet-smoke-gate-field
                 report "publicMaxPriorityFeePerGas"))
        (format t "publicBaseFee=~A~%"
                (devnet-smoke-gate-field report "publicBaseFee"))
        (format t "publicBlobBaseFee=~A~%"
                (devnet-smoke-gate-field report "publicBlobBaseFee"))
        (format t "publicFeeHistoryOldestBlock=~A~%"
                (devnet-smoke-gate-field
                 report "publicFeeHistoryOldestBlock"))
        (format t "publicBatchResponseCount=~D~%"
                (devnet-smoke-gate-field
                 report "publicBatchResponseCount"))
        (format t "publicBatchChainId=~A~%"
                (devnet-smoke-gate-field report "publicBatchChainId"))
        (format t "publicBatchNetVersion=~A~%"
                (devnet-smoke-gate-field report "publicBatchNetVersion"))
        (format t "publicBatchClientVersion=~A~%"
                (devnet-smoke-gate-field
                 report "publicBatchClientVersion"))
        (format t "newPayloadStatus=~A~%"
                (devnet-smoke-gate-field report "newPayloadStatus"))
        (format t "latestValidHash=~A~%"
                (devnet-smoke-gate-field report "latestValidHash"))
        (format t "forkchoiceStatus=~A~%"
                (devnet-smoke-gate-field report "forkchoiceStatus"))
        (format t "enginePayloadBodiesByHashCount=~D~%"
                (devnet-smoke-gate-field
                 report "enginePayloadBodiesByHashCount"))
        (format t "enginePayloadBodiesByHashTransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report "enginePayloadBodiesByHashTransactionCount"))
        (format t "enginePayloadBodiesByRangeCount=~D~%"
                (devnet-smoke-gate-field
                 report "enginePayloadBodiesByRangeCount"))
        (format t "enginePayloadBodiesByRangeTransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report "enginePayloadBodiesByRangeTransactionCount"))
        (format t "preparedPayloadId=~A~%"
                (devnet-smoke-gate-field report "preparedPayloadId"))
        (format t "preparedPayloadParentHash=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedPayloadParentHash"))
        (format t "preparedPayloadBlockNumber=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedPayloadBlockNumber"))
        (format t "engineGetPayloadV2ParentHash=~A~%"
                (devnet-smoke-gate-field report
                                         "engineGetPayloadV2ParentHash"))
        (format t "engineGetPayloadV2BlockNumber=~A~%"
                (devnet-smoke-gate-field report
                                         "engineGetPayloadV2BlockNumber"))
        (format t "engineGetPayloadV2TransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TransactionCount"))
        (format t "preparedTxpoolPayloadId=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedTxpoolPayloadId"))
        (format t "engineGetPayloadV2TxpoolTransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolTransactionCount"))
        (format t "engineGetPayloadV2TxpoolSelectedTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolSelectedTransactionHash"))
        (format t "engineGetPayloadV2TxpoolSelectedStillPending=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolSelectedStillPending"))
        (format t "engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued"))
        (format t "engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued"))
        (format t "preparedReplacementTxpoolPayloadId=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedReplacementTxpoolPayloadId"))
        (format t "engineGetPayloadV2TxpoolReplacementTransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolReplacementTransactionCount"))
        (format t "engineGetPayloadV2TxpoolReplacementTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolReplacementTransactionHash"))
        (format t "engineGetPayloadV2TxpoolReplacementStillPending=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolReplacementStillPending"))
        (format t "engineNewPayloadV2TxpoolImportStatus=~A~%"
                (devnet-smoke-gate-field
                 report "engineNewPayloadV2TxpoolImportStatus"))
        (format t "engineForkchoiceUpdatedV2TxpoolImportStatus=~A~%"
                (devnet-smoke-gate-field
                 report "engineForkchoiceUpdatedV2TxpoolImportStatus"))
        (format t "txpoolImportTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportTransactionHash"))
        (format t "txpoolImportReceiptTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportReceiptTransactionHash"))
        (format t "txpoolImportTxpoolStatusPending=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportTxpoolStatusPending"))
        (format t "txpoolImportTxpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportTxpoolStatusQueued"))
        (format t "txpoolImportSelectedStillPending=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportSelectedStillPending"))
        (format t "txpoolImportNonSelectedBasefeeStillQueued=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportNonSelectedBasefeeStillQueued"))
        (format t "txpoolImportNonSelectedQueuedStillQueued=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportNonSelectedQueuedStillQueued"))
        (format t "remoteBlockHash=~A~%"
                (devnet-smoke-gate-field report "remoteBlockHash"))
        (format t "remoteBlockStatus=~A~%"
                (devnet-smoke-gate-field report "remoteBlockStatus"))
        (format t "invalidTipsetBlockHash=~A~%"
                (devnet-smoke-gate-field report "invalidTipsetBlockHash"))
        (format t "invalidTipsetStatus=~A~%"
                (devnet-smoke-gate-field report "invalidTipsetStatus"))
        (format t "invalidTipsetValidationError=~A~%"
                (devnet-smoke-gate-field
                 report "invalidTipsetValidationError"))
        (format t "txpoolPendingTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingTransactionHash"))
        (format t "txpoolReplacementTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolReplacementTransactionHash"))
        (format t "txpoolPendingSender=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingSender"))
        (format t "txpoolPendingNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingNonce"))
        (format t "txpoolPendingSenderNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingSenderNonce"))
        (format t "txpoolPendingInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingInspectSummary"))
        (format t "txpoolPendingFilterId=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingFilterId"))
        (format t "txpoolPendingFilterHash=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingFilterHash"))
        (format t "txpoolPendingFilterUninstallResult=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingFilterUninstallResult"))
        (format t "txpoolPendingFilterMissingErrorCode=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingFilterMissingErrorCode"))
        (format t "txpoolBasefeeTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolBasefeeTransactionHash"))
        (format t "txpoolBasefeeNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolBasefeeNonce"))
        (format t "txpoolBasefeeInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolBasefeeInspectSummary"))
        (format t "txpoolQueuedTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolQueuedTransactionHash"))
        (format t "txpoolQueuedNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolQueuedNonce"))
        (format t "txpoolQueuedInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolQueuedInspectSummary"))
        (format t "txpoolStatusPending=~A~%"
                (devnet-smoke-gate-field report "txpoolStatusPending"))
        (format t "txpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field report "txpoolStatusQueued"))
        (format t "devPeriodSeconds=~A~%"
                (devnet-smoke-gate-field report "devPeriodSeconds"))
        (format t "devPeriodTransactionHash=~A~%"
                (devnet-smoke-gate-field report "devPeriodTransactionHash"))
        (format t "devPeriodBlockNumber=~A~%"
                (devnet-smoke-gate-field report "devPeriodBlockNumber"))
        (format t "devPeriodBlockHash=~A~%"
                (devnet-smoke-gate-field report "devPeriodBlockHash"))
        (format t "devPeriodTxpoolStatusPending=~A~%"
                (devnet-smoke-gate-field
                 report "devPeriodTxpoolStatusPending"))
        (format t "devPeriodTxpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field
                 report "devPeriodTxpoolStatusQueued"))
        (format t "blockNumber=~A~%"
                (devnet-smoke-gate-field report "blockNumber"))
        (format t "blockGasLimit=~A~%"
                (devnet-smoke-gate-field report "blockGasLimit"))
        (format t "safeBlockNumber=~A~%"
                (devnet-smoke-gate-field report "safeBlockNumber"))
        (format t "safeBlockGasLimit=~A~%"
                (devnet-smoke-gate-field report "safeBlockGasLimit"))
        (format t "safeBlockHash=~A~%"
                (devnet-smoke-gate-field report "safeBlockHash"))
        (format t "finalizedBlockNumber=~A~%"
                (devnet-smoke-gate-field report "finalizedBlockNumber"))
        (format t "finalizedBlockHash=~A~%"
                (devnet-smoke-gate-field report "finalizedBlockHash"))
        (format t "checkedBalanceAddress=~A~%"
                (devnet-smoke-gate-field report "checkedBalanceAddress"))
        (format t "checkedBalanceField=~A~%"
                (devnet-smoke-gate-field report "checkedBalanceField"))
        (format t "checkedBalance=~A~%"
                (devnet-smoke-gate-field report "checkedBalance"))
        (format t "checkedCheckpointBalance=~A~%"
                (devnet-smoke-gate-field
                 report "checkedCheckpointBalance"))
        (format t "recipientBalance=~A~%"
                (devnet-smoke-gate-field report "recipientBalance"))
        (format t "checkedNonceAddress=~A~%"
                (devnet-smoke-gate-field report "checkedNonceAddress"))
        (format t "checkedNonce=~A~%"
                (devnet-smoke-gate-field report "checkedNonce"))
        (format t "checkedCodeAddress=~A~%"
                (devnet-smoke-gate-field report "checkedCodeAddress"))
        (format t "checkedCode=~A~%"
                (devnet-smoke-gate-field report "checkedCode"))
        (format t "checkedStorageAddress=~A~%"
                (devnet-smoke-gate-field report "checkedStorageAddress"))
        (format t "checkedStorageKey=~A~%"
                (devnet-smoke-gate-field report "checkedStorageKey"))
        (format t "checkedStorage=~A~%"
                (devnet-smoke-gate-field report "checkedStorage"))
        (format t "checkedProofCodeHash=~A~%"
                (devnet-smoke-gate-field report "checkedProofCodeHash"))
        (format t "checkedProofStorageValue=~A~%"
                (devnet-smoke-gate-field report
                                         "checkedProofStorageValue"))
        (format t "checkedLogCount=~A~%"
                (devnet-smoke-gate-field report "checkedLogCount"))
        (format t "checkedSimulationCount=~A~%"
                (devnet-smoke-gate-field report "checkedSimulationCount"))
        (format t "readyFile=~A~%" (devnet-smoke-gate-field report "readyFile"))
        (format t "logFile=~A~%" (devnet-smoke-gate-field report "logFile"))
        (format t "pidFile=~A~%" (devnet-smoke-gate-field report "pidFile"))
        (format t "databaseFile=~A~%"
                (devnet-smoke-gate-field report "databaseFile"))
        (format t "databasePruneStateBefore=~A~%"
                (devnet-smoke-gate-field
                 report "databasePruneStateBefore"))
        (format t "databasePrunedStateAvailable=~A~%"
                (devnet-smoke-gate-field
                 report "databasePrunedStateAvailable"))
        (format t "databaseHeadNumber=~A~%"
                (devnet-smoke-gate-field report "databaseHeadNumber"))
        (format t "databaseHeadGasLimit=~A~%"
                (devnet-smoke-gate-field report "databaseHeadGasLimit"))
        (format t "databaseRpcBlockNumber=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBlockNumber"))
        (format t "databaseSafeNumber=~A~%"
                (devnet-smoke-gate-field report "databaseSafeNumber"))
        (format t "databaseSafeHash=~A~%"
                (devnet-smoke-gate-field report "databaseSafeHash"))
        (format t "databaseFinalizedNumber=~A~%"
                (devnet-smoke-gate-field report "databaseFinalizedNumber"))
        (format t "databaseFinalizedHash=~A~%"
                (devnet-smoke-gate-field report "databaseFinalizedHash"))
        (format t "databaseRpcBalance=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBalance"))
        (format t "databaseRpcNonce=~A~%"
                (devnet-smoke-gate-field report "databaseRpcNonce"))
        (format t "databaseRpcCode=~A~%"
                (devnet-smoke-gate-field report "databaseRpcCode"))
        (format t "databaseRpcStorage=~A~%"
                (devnet-smoke-gate-field report "databaseRpcStorage"))
        (format t "databaseRpcPreparedPayloadId=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcPreparedPayloadId"))
        (format t "databaseRpcPreparedPayloadParentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPreparedPayloadParentHash"))
        (format t "databaseRpcPreparedPayloadBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPreparedPayloadBlockNumber"))
        (format t "databaseRemoteBlockHash=~A~%"
                (devnet-smoke-gate-field report "databaseRemoteBlockHash"))
        (format t "databaseRpcRemoteBlockStatus=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRemoteBlockStatus"))
        (format t "databaseInvalidTipsetBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseInvalidTipsetBlockHash"))
        (format t "databaseRpcInvalidTipsetStatus=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcInvalidTipsetStatus"))
        (format t "databaseRpcInvalidTipsetValidationError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcInvalidTipsetValidationError"))
        (format t "databaseRpcTxpoolPendingHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHash"))
        (format t "databaseRpcTxpoolSender=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolSender"))
        (format t "databaseRpcTxpoolNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolNonce"))
        (format t "databaseRpcTxpoolInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolInspectSummary"))
        (format t "databaseRpcTxpoolBasefeeHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeHash"))
        (format t "databaseRpcTxpoolBasefeeNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeNonce"))
        (format t "databaseRpcTxpoolBasefeeInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeInspectSummary"))
        (format t "databaseRpcTxpoolQueuedHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedHash"))
        (format t "databaseRpcTxpoolQueuedNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedNonce"))
        (format t "databaseRpcTxpoolQueuedInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedInspectSummary"))
        (format t "databaseRpcTxpoolStatusPending=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolStatusPending"))
        (format t "databaseRpcTxpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolStatusQueued"))
        (format t "databaseRpcTxpoolPendingBlockCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockCount"))
        (format t "databaseRpcTxpoolPendingBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockHash"))
        (format t "databaseRpcTxpoolPendingBlockBaseFee=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockBaseFee"))
        (format t "databaseRpcTxpoolPendingHeaderNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderNumber"))
        (format t "databaseRpcTxpoolPendingHeaderParentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderParentHash"))
        (format t "databaseRpcTxpoolPendingHeaderHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderHash"))
        (format t "databaseRpcTxpoolPendingHeaderNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderNonce"))
        (format t "databaseRpcTxpoolPendingHeaderBaseFee=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderBaseFee"))
        (format t "databaseRpcTxpoolPendingFeeHistoryNextBaseFee=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingFeeHistoryNextBaseFee"))
        (format t "databaseRpcTxpoolPendingSenderNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingSenderNonce"))
        (format t "databaseRpcTxpoolPendingBlockTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockTransactionHash"))
        (format t "databaseRpcTxpoolPendingBlockTransactionBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockTransactionBlockHash"))
        (format t "databaseRpcTxpoolPendingIndexHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingIndexHash"))
        (format t "databaseRpcTxpoolPendingIndexBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingIndexBlockHash"))
        (format t "databaseRpcTxpoolPendingRawByIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingRawByIndex"))
        (format t "databaseRpcTxpoolContentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolContentHash"))
        (format t "databaseRpcTxpoolContentFromHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolContentFromHash"))
        (format t "databaseRpcTxpoolBasefeeContentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeContentHash"))
        (format t "databaseRpcTxpoolBasefeeContentFromHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeContentFromHash"))
        (format t "databaseRpcTxpoolQueuedContentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedContentHash"))
        (format t "databaseRpcTxpoolQueuedContentFromHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedContentFromHash"))
        (format t "databaseRpcTxpoolPublicConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPublicConnections"))
        (format t "databaseRpcProofAddress=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofAddress"))
        (format t "databaseRpcProofCodeHash=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofCodeHash"))
        (format t "databaseRpcProofStorageKey=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofStorageKey"))
        (format t "databaseRpcProofStorageValue=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofStorageValue"))
        (format t "databaseRpcProofStorageCount=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofStorageCount"))
        (format t "databaseRpcProofAccountProofCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcProofAccountProofCount"))
        (format t "databaseRpcReceiptTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcReceiptTransactionHash"))
        (format t "databaseRpcReceiptBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcReceiptBlockNumber"))
        (format t "databaseRpcBlockHash=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBlockHash"))
        (format t "databaseRpcBlockByHashNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByHashNumber"))
        (format t "databaseRpcBlockTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockTransactionHash"))
        (format t "databaseRpcBlockByNumberHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByNumberHash"))
        (format t "databaseRpcBlockByNumberNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByNumberNumber"))
        (format t "databaseRpcBlockByNumberTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByNumberTransactionHash"))
        (format t "databaseRpcFullBlockTransactionCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockTransactionCount"))
        (format t "databaseRpcFullBlockTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockTransactionHash"))
        (format t "databaseRpcFullBlockTransactionIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockTransactionIndex"))
        (format t "databaseRpcFullBlockByNumberTransactionCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockByNumberTransactionCount"))
        (format t "databaseRpcFullBlockByNumberTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockByNumberTransactionHash"))
        (format t "databaseRpcFullBlockByNumberTransactionIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockByNumberTransactionIndex"))
        (format t "databaseRpcTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionHash"))
        (format t "databaseRpcTransactionBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionBlockHash"))
        (format t "databaseRpcTransactionBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionBlockNumber"))
        (format t "databaseRpcBlockReceiptsCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptsCount"))
        (format t "databaseRpcLogCount=~A~%"
                (devnet-smoke-gate-field report "databaseRpcLogCount"))
        (format t "databaseRpcLogFilterCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcLogFilterCount"))
        (format t "databaseRpcLogFilterLogCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcLogFilterLogCount"))
        (format t "databaseRpcLogFilterUninstallCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcLogFilterUninstallCount"))
        (format t "databaseRpcBlockReceiptTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptTransactionHash"))
        (format t "databaseRpcBlockReceiptBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptBlockHash"))
        (format t "databaseRpcBlockReceiptBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptBlockNumber"))
        (format t "databaseRpcBlockTransactionCountByHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockTransactionCountByHash"))
        (format t "databaseRpcBlockTransactionCountByNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockTransactionCountByNumber"))
        (format t "databaseRpcCanonicalHashBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcCanonicalHashBalance"))
        (format t "databaseRpcCanonicalHashRequireBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcCanonicalHashRequireBalance"))
        (format t "databaseRpcRawTransactionByBlockHashAndIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRawTransactionByBlockHashAndIndex"))
        (format t "databaseRpcRawTransactionByHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRawTransactionByHash"))
        (format t "databaseRpcRawTransactionByBlockNumberAndIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRawTransactionByBlockNumberAndIndex"))
        (format t "databaseRpcTransactionByBlockHashAndIndexHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockHashAndIndexHash"))
        (format t "databaseRpcTransactionByBlockHashAndIndexBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockHashAndIndexBlockHash"))
        (format t "databaseRpcTransactionByBlockHashAndIndexBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockHashAndIndexBlockNumber"))
        (format t "databaseRpcTransactionByBlockHashAndIndexIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockHashAndIndexIndex"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockNumberAndIndexHash"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockNumberAndIndexBlockHash"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockNumberAndIndexBlockNumber"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockNumberAndIndexIndex"))
        (format t "databaseRpcSafeBlockHash=~A~%"
                (devnet-smoke-gate-field report "databaseRpcSafeBlockHash"))
        (format t "databaseRpcSafeBlockNumber=~A~%"
                (devnet-smoke-gate-field report "databaseRpcSafeBlockNumber"))
        (format t "databaseRpcFinalizedBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFinalizedBlockHash"))
        (format t "databaseRpcFinalizedBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFinalizedBlockNumber"))
        (format t "databaseRpcCallResult=~A~%"
                (devnet-smoke-gate-field report "databaseRpcCallResult"))
        (format t "databaseRpcFailedCallError=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcFailedCallError"))
        (format t "databaseRpcEstimateGas=~A~%"
                (devnet-smoke-gate-field report "databaseRpcEstimateGas"))
        (format t "databaseRpcAccessListCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcAccessListCount"))
        (format t "databaseRpcAccessListGasUsed=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcAccessListGasUsed"))
        (format t "databaseRpcPostCallStorage=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPostCallStorage"))
        (format t "databaseRpcSimulationCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSimulationCount"))
        (format t "databaseRpcSideBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideBlockHash"))
        (format t "databaseRpcSideForkchoiceStatus=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideForkchoiceStatus"))
        (format t "databaseRpcSideRejectedCheckpointError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRejectedCheckpointError"))
        (format t "databaseRpcSideBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideBlockNumber"))
        (format t "databaseRpcSideLatestBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideLatestBlockHash"))
        (format t "databaseRpcSideTransactionReinserted=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideTransactionReinserted"))
        (format t "databaseRpcSideTransactionByHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideTransactionByHash"))
        (format t "databaseRpcSideRawTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRawTransaction"))
        (format t "databaseRpcSidePendingTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSidePendingTransaction"))
        (format t "databaseRpcSideReceipt=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideReceipt"))
        (format t "databaseRpcSideHiddenReceiptCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideHiddenReceiptCount"))
        (format t "databaseRpcSideChildBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideChildBlockHash"))
        (format t "databaseRpcSideBlockReceiptsCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideBlockReceiptsCount"))
        (format t "databaseRpcSideLogCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideLogCount"))
        (format t "databaseRpcSideRestoredHeadNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredHeadNumber"))
        (format t "databaseRpcSideRestoredHeadHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredHeadHash"))
        (format t "databaseRpcSideRestoredRpcBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcBlockNumber"))
        (format t "databaseRpcSideRestoredRpcLatestBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcLatestBlockHash"))
        (format t "databaseRpcSideRestoredSafeNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredSafeNumber"))
        (format t "databaseRpcSideRestoredSafeHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredSafeHash"))
        (format t "databaseRpcSideRestoredFinalizedNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredFinalizedNumber"))
        (format t "databaseRpcSideRestoredFinalizedHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredFinalizedHash"))
        (format t "databaseRpcSideRestoredRpcSafeNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcSafeNumber"))
        (format t "databaseRpcSideRestoredRpcSafeHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcSafeHash"))
        (format t "databaseRpcSideRestoredRpcFinalizedNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcFinalizedNumber"))
        (format t "databaseRpcSideRestoredRpcFinalizedHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcFinalizedHash"))
        (format t "databaseRpcSideRestoredSafeBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredSafeBalance"))
        (format t "databaseRpcSideRestoredFinalizedBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredFinalizedBalance"))
        (format t "databaseRpcSideRestoredRawTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRawTransaction"))
        (format t "databaseRpcSideRestoredPendingTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredPendingTransaction"))
        (format t "databaseRpcSideRestoredReceipt=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredReceipt"))
        (format t "databaseRpcSideRestoredHiddenReceiptCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredHiddenReceiptCount"))
        (format t "databaseRpcSideRestoredChildBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredChildBlockHash"))
        (format t "databaseRpcSideRestoredChildRequireCanonicalError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredChildRequireCanonicalError"))
        (format t "databaseRpcSideRestoredChildRequireCanonicalErrors=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredChildRequireCanonicalErrors"))
        (format t "databaseRpcSideRestoredBlockReceiptsCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredBlockReceiptsCount"))
        (format t "databaseRpcSideRestoredLogCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredLogCount"))
        (format t "databaseRpcSideRestoredPublicConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredPublicConnections"))
        (format t "databaseRpcSideTotalConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideTotalConnections"))
        (format t "databaseRpcSideEngineConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideEngineConnections"))
        (format t "databaseRpcSidePublicConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSidePublicConnections"))
        (format t "databaseRpcPrunedStateError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPrunedStateError"))
        (format t "databaseRpcPrunedStateErrors=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPrunedStateErrors")))))

