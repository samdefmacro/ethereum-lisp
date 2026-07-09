(in-package #:ethereum-lisp.test)

(defun devnet-cli-assert-public-readiness (report)
  (is (search "ethereum-lisp"
              (fixture-object-field report "publicClientVersion")))
  (is (every #'digit-char-p
             (fixture-object-field report "publicNetVersion")))
  (is (null (fixture-object-field report "publicNetListening")))
  (is (null (fixture-object-field report "publicSyncing")))
  (is (string= "0x0" (fixture-object-field report "publicNetPeerCount")))
  (is (= 0 (fixture-object-field report "publicAccountCount")))
  (is (string= (address-to-hex (zero-address))
               (fixture-object-field report "publicCoinbase")))
  (is (null (fixture-object-field report "publicMining")))
  (is (string= "0x0" (fixture-object-field report "publicHashrate")))
  (is (= 3 (fixture-object-field report "publicBatchResponseCount")))
  (is (string= (fixture-object-field report "publicBatchChainId")
               (fixture-object-field report "chainId")))
  (is (string= (fixture-object-field report "publicBatchNetVersion")
               (fixture-object-field report "publicNetVersion")))
  (is (search "ethereum-lisp"
              (fixture-object-field report "publicBatchClientVersion"))))

(defun devnet-cli-assert-engine-payload-bodies (report)
  (is (= 1 (fixture-object-field report "enginePayloadBodiesByHashCount")))
  (is (= 1 (fixture-object-field report "enginePayloadBodiesByRangeCount")))
  (is (integerp
       (fixture-object-field
        report "enginePayloadBodiesByHashTransactionCount")))
  (is (integerp
       (fixture-object-field
        report "enginePayloadBodiesByRangeTransactionCount")))
  (is (= (fixture-object-field
          report "enginePayloadBodiesByHashTransactionCount")
         (fixture-object-field
          report "enginePayloadBodiesByRangeTransactionCount"))))

(defun devnet-cli-assert-engine-get-payload-v2 (report)
  (is (string= (fixture-object-field report "preparedPayloadParentHash")
               (fixture-object-field
                report
                "engineGetPayloadV2ParentHash")))
  (is (string= (fixture-object-field report "preparedPayloadBlockNumber")
               (fixture-object-field
                report
                "engineGetPayloadV2BlockNumber")))
  (is (integerp
       (fixture-object-field
        report
        "engineGetPayloadV2TransactionCount")))
  (is (stringp
       (fixture-object-field report "preparedTxpoolPayloadId")))
  (is (not (string= (fixture-object-field report "preparedPayloadId")
                    (fixture-object-field report "preparedTxpoolPayloadId"))))
  (is (string= (fixture-object-field report "preparedPayloadParentHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolParentHash")))
  (is (string= (fixture-object-field report "preparedPayloadBlockNumber")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolBlockNumber")))
  (is (= 1
         (fixture-object-field
          report
          "engineGetPayloadV2TxpoolTransactionCount")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionRaw")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolSelectedTransactionRaw")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolSelectedTransactionHash")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolSelectedStillPending")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued")))
  (is (stringp
       (fixture-object-field report "preparedReplacementTxpoolPayloadId")))
  (is (not (string= (fixture-object-field report "preparedTxpoolPayloadId")
                    (fixture-object-field
                     report
                     "preparedReplacementTxpoolPayloadId"))))
  (is (string= (fixture-object-field report "preparedPayloadParentHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementParentHash")))
  (is (string= (fixture-object-field report "preparedPayloadBlockNumber")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementBlockNumber")))
  (is (= 1
         (fixture-object-field
          report
          "engineGetPayloadV2TxpoolReplacementTransactionCount")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionRaw")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementTransactionRaw")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementTransactionHash")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementStillPending")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementNonSelectedBasefeeStillQueued")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report
                "engineGetPayloadV2TxpoolReplacementNonSelectedQueuedStillQueued")))
  (is (string= +payload-status-valid+
               (fixture-object-field
                report
                "engineNewPayloadV2TxpoolImportStatus")))
  (is (string= (fixture-object-field report "txpoolImportBlockHash")
               (fixture-object-field
                report
                "engineNewPayloadV2TxpoolImportLatestValidHash")))
  (is (string= +payload-status-valid+
               (fixture-object-field
                report
                "engineForkchoiceUpdatedV2TxpoolImportStatus")))
  (is (string= (fixture-object-field report "preparedPayloadBlockNumber")
               (fixture-object-field report "txpoolImportBlockNumber")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field report "txpoolImportTransactionHash")))
  (is (string= (fixture-object-field report "txpoolImportBlockHash")
               (fixture-object-field
                report
                "txpoolImportTransactionBlockHash")))
  (is (string= (fixture-object-field report "txpoolImportBlockNumber")
               (fixture-object-field
                report
                "txpoolImportTransactionBlockNumber")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field
                report
                "txpoolImportReceiptTransactionHash")))
  (is (string= (fixture-object-field report "txpoolImportBlockHash")
               (fixture-object-field report "txpoolImportReceiptBlockHash")))
  (is (string= (fixture-object-field report "txpoolImportBlockNumber")
               (fixture-object-field
                report
                "txpoolImportReceiptBlockNumber")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionRaw")
               (fixture-object-field report "txpoolImportRawTransaction")))
  (is (= 1
         (fixture-object-field report "txpoolImportBlockTransactionCount")))
  (is (string= (fixture-object-field report "txpoolReplacementTransactionHash")
               (fixture-object-field
                report
                "txpoolImportBlockTransactionHash")))
  (is (string= "0x0"
               (fixture-object-field
                report
                "txpoolImportTxpoolStatusPending")))
  (is (string= "0x2"
               (fixture-object-field
                report
                "txpoolImportTxpoolStatusQueued")))
  (is (not (fixture-object-field report "txpoolImportSelectedStillPending")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report
                "txpoolImportNonSelectedBasefeeStillQueued")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report
                "txpoolImportNonSelectedQueuedStillQueued"))))

(defun devnet-cli-assert-public-cors-smoke-report (report)
  (is (equal '("https://runner.example" "https://observer.example")
             (fixture-object-field report "publicCorsOrigins")))
  (is (equal '("https://runner.example" "https://observer.example")
             (fixture-object-field report "publicCorsReportedOrigins")))
  (is (string= "https://runner.example,https://observer.example"
               (fixture-object-field report "publicCorsTelemetryOrigins")))
  (is (= 204 (fixture-object-field report "publicCorsPreflightStatus")))
  (is (= 200 (fixture-object-field report "publicCorsRpcStatus")))
  (is (= 403 (fixture-object-field report "publicCorsBlockedStatus")))
  (is (= 0 (fixture-object-field report "publicCorsEngineConnections")))
  (is (= 3 (fixture-object-field report "publicCorsPublicConnections")))
  (is (= 3 (fixture-object-field report "publicCorsTotalConnections"))))

(defun devnet-cli-assert-engine-cors-smoke-report (report)
  (is (equal '("https://engine-runner.example"
               "https://engine-observer.example")
             (fixture-object-field report "engineCorsOrigins")))
  (is (equal '("https://engine-runner.example"
               "https://engine-observer.example")
             (fixture-object-field report "engineCorsReportedOrigins")))
  (is (string= "https://engine-runner.example,https://engine-observer.example"
               (fixture-object-field report "engineCorsTelemetryOrigins")))
  (is (= 204 (fixture-object-field report "engineCorsPreflightStatus")))
  (is (= 200 (fixture-object-field report "engineCorsRpcStatus")))
  (is (= 403 (fixture-object-field report "engineCorsBlockedStatus")))
  (is (= 3 (fixture-object-field report "engineCorsEngineConnections")))
  (is (= 0 (fixture-object-field report "engineCorsPublicConnections")))
  (is (= 3 (fixture-object-field report "engineCorsTotalConnections"))))

(defun devnet-cli-assert-http-shaping-smoke-report (report)
  (is (= 405 (fixture-object-field report "engineHttpMethodStatus")))
  (is (= 415 (fixture-object-field report "engineHttpContentTypeStatus")))
  (is (= 405 (fixture-object-field report "publicHttpMethodStatus")))
  (is (= 415 (fixture-object-field report "publicHttpContentTypeStatus")))
  (is (= 2 (fixture-object-field report "httpShapingEngineConnections")))
  (is (= 2 (fixture-object-field report "httpShapingPublicConnections")))
  (is (= 4 (fixture-object-field report "httpShapingTotalConnections"))))

(defun devnet-cli-assert-vhost-smoke-report (report)
  (is (equal '("engine.runner" "localhost")
             (fixture-object-field report "engineVhosts")))
  (is (equal '("public.runner" "localhost")
             (fixture-object-field report "publicVhosts")))
  (is (equal '("engine.runner" "localhost")
             (fixture-object-field report "engineVhostsReported")))
  (is (equal '("public.runner" "localhost")
             (fixture-object-field report "publicVhostsReported")))
  (is (string= "engine.runner,localhost"
               (fixture-object-field report "engineVhostsTelemetry")))
  (is (string= "public.runner,localhost"
               (fixture-object-field report "publicVhostsTelemetry")))
  (is (= 200 (fixture-object-field report "engineVhostAllowedStatus")))
  (is (= 403 (fixture-object-field report "engineVhostBlockedStatus")))
  (is (= 200 (fixture-object-field report "publicVhostAllowedStatus")))
  (is (= 403 (fixture-object-field report "publicVhostBlockedStatus")))
  (is (= 2 (fixture-object-field report "vhostEngineConnections")))
  (is (= 2 (fixture-object-field report "vhostPublicConnections")))
  (is (= 4 (fixture-object-field report "vhostTotalConnections"))))

(defun devnet-cli-assert-rpc-prefix-smoke-report (report)
  (is (string= "/engine"
               (fixture-object-field report "engineRpcPrefix")))
  (is (string= "/rpc"
               (fixture-object-field report "publicRpcPrefix")))
  (is (string= "/engine"
               (fixture-object-field report "engineRpcPrefixReported")))
  (is (string= "/rpc"
               (fixture-object-field report "publicRpcPrefixReported")))
  (is (string= "/engine"
               (fixture-object-field report "engineRpcPrefixTelemetry")))
  (is (string= "/rpc"
               (fixture-object-field report "publicRpcPrefixTelemetry")))
  (is (= 200 (fixture-object-field report "engineRpcPrefixStatus")))
  (is (= 404 (fixture-object-field report "engineRpcPrefixBlockedStatus")))
  (is (= 200 (fixture-object-field report "publicRpcPrefixStatus")))
  (is (= 404 (fixture-object-field report "publicRpcPrefixBlockedStatus")))
  (is (= 2 (fixture-object-field report "rpcPrefixEngineConnections")))
  (is (= 2 (fixture-object-field report "rpcPrefixPublicConnections")))
  (is (= 4 (fixture-object-field report "rpcPrefixTotalConnections"))))

(defun devnet-cli-assert-engine-only-http-shaping-report (report)
  (is (equal '("https://engine-runner.example"
               "https://engine-observer.example")
             (fixture-object-field report "engineCorsOrigins")))
  (is (string= "https://engine-runner.example"
               (fixture-object-field report "engineCorsHeader")))
  (is (string= "Origin"
               (fixture-object-field report "engineCorsVaryHeader")))
  (is (equal '("engine.runner" "localhost")
             (fixture-object-field report "engineVhosts"))))

(defun devnet-cli-assert-engine-only-payload-report (report)
  (is (string= "shanghai-one-transfer-with-withdrawal"
               (fixture-object-field report "fixtureCase")))
  (is (string= +payload-status-valid+
               (fixture-object-field report "newPayloadStatus")))
  (is (string= +payload-status-valid+
               (fixture-object-field report "forkchoiceStatus")))
  (is (string= (fixture-object-field report "latestValidHash")
               (fixture-object-field report "forkchoiceHeadHash")))
  (is (stringp (fixture-object-field report "forkchoiceHeadNumber"))))

(defun devnet-cli-assert-engine-only-hidden-payload-bodies-v2-report (report)
  (is (= 200
         (fixture-object-field report "hiddenBlobsV1Status")))
  (is (= -32601
         (fixture-object-field report "hiddenBlobsV1ErrorCode")))
  (is (string= "Method not found"
               (fixture-object-field report "hiddenBlobsV1ErrorMessage")))
  (is (= 200
         (fixture-object-field report "hiddenBlobsV2Status")))
  (is (= -32601
         (fixture-object-field report "hiddenBlobsV2ErrorCode")))
  (is (string= "Method not found"
               (fixture-object-field report "hiddenBlobsV2ErrorMessage")))
  (is (= 200
         (fixture-object-field report "hiddenPayloadBodiesByRangeV2Status")))
  (is (= -32601
         (fixture-object-field
          report
          "hiddenPayloadBodiesByRangeV2ErrorCode")))
  (is (string= "Method not found"
               (fixture-object-field
                report
                "hiddenPayloadBodiesByRangeV2ErrorMessage")))
  (is (= 200
         (fixture-object-field report "hiddenPayloadBodiesByHashV2Status")))
  (is (= -32601
         (fixture-object-field
          report
          "hiddenPayloadBodiesByHashV2ErrorCode")))
  (is (string= "Method not found"
               (fixture-object-field
                report
                "hiddenPayloadBodiesByHashV2ErrorMessage"))))

(defun devnet-cli-assert-engine-only-database-report (report)
  (is (stringp (fixture-object-field report "databaseFile")))
  (is (= (fixture-quantity-field report "forkchoiceHeadNumber")
         (fixture-object-field report "databaseHeadNumber")))
  (is (string= (fixture-object-field report "forkchoiceHeadHash")
               (fixture-object-field report "databaseHeadHash")))
  (is (fixture-object-field report "databaseStateAvailable")))

