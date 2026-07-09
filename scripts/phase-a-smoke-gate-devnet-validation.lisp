(defun smoke-gate-devnet-case-files (report field)
  (loop for case-report in (or (smoke-gate-field report "cases") nil)
        for path = (smoke-gate-field case-report field)
        when (stringp path)
          collect path))

(defun smoke-gate-devnet-require-field (report field expected)
  (let ((actual (smoke-gate-field report field)))
    (unless (equal actual expected)
      (error "Devnet smoke gate ~A must be ~S, got ~S"
             field expected actual))
    actual))

(defun smoke-gate-devnet-require-case-files
    (report field count-field expected-count)
  (let ((files (smoke-gate-devnet-case-files report field))
        (count (smoke-gate-field report count-field)))
    (unless (= expected-count count)
      (error "Devnet smoke gate ~A must be ~D, got ~S"
             count-field expected-count count))
    (unless (= expected-count (length files))
      (error "Devnet smoke gate ~A files must have count ~D, got ~D"
             field expected-count (length files)))
    files))

(defparameter +smoke-gate-devnet-side-reorg-pruned-fields+
  '("databaseRpcSideBlockHash"
    "databaseRpcSideForkchoiceStatus"
    "databaseRpcSideRejectedCheckpointError"
    "databaseRpcSideBlockNumber"
    "databaseRpcSideLatestBlockHash"
    "databaseRpcSideTransactionReinserted"
    "databaseRpcSideTransactionByHash"
    "databaseRpcSideRawTransaction"
    "databaseRpcSidePendingTransaction"
    "databaseRpcSideReinsertedTransactionCount"
    "databaseRpcSideReinsertedTransactionHashes"
    "databaseRpcSideReceipt"
    "databaseRpcSideHiddenReceiptCount"
    "databaseRpcSideChildBlockHash"
    "databaseRpcSideBlockReceiptsCount"
    "databaseRpcSideLogCount"
    "databaseRpcSideRestoredHeadNumber"
    "databaseRpcSideRestoredHeadHash"
    "databaseRpcSideRestoredRpcBlockNumber"
    "databaseRpcSideRestoredRpcLatestBlockHash"
    "databaseRpcSideRestoredSafeNumber"
    "databaseRpcSideRestoredSafeHash"
    "databaseRpcSideRestoredFinalizedNumber"
    "databaseRpcSideRestoredFinalizedHash"
    "databaseRpcSideRestoredRpcSafeNumber"
    "databaseRpcSideRestoredRpcSafeHash"
    "databaseRpcSideRestoredRpcFinalizedNumber"
    "databaseRpcSideRestoredRpcFinalizedHash"
    "databaseRpcSideRestoredSafeBalance"
    "databaseRpcSideRestoredFinalizedBalance"
    "databaseRpcSideRestoredRawTransaction"
    "databaseRpcSideRestoredPendingTransaction"
    "databaseRpcSideRestoredReinsertedTransactionCount"
    "databaseRpcSideRestoredReinsertedTransactionHashes"
    "databaseRpcSideRestoredReceipt"
    "databaseRpcSideRestoredHiddenReceiptCount"
    "databaseRpcSideRestoredChildBlockHash"
    "databaseRpcSideRestoredChildRequireCanonicalError"
    "databaseRpcSideRestoredChildRequireCanonicalErrors"
    "databaseRpcSideRestoredBlockReceiptsCount"
    "databaseRpcSideRestoredLogCount"
    "databaseRpcSideRestoredPublicConnections"
    "databaseRpcSideTotalConnections"
    "databaseRpcSideEngineConnections"
    "databaseRpcSidePublicConnections"))

(defparameter +smoke-gate-devnet-noncanonical-state-errors+
  '("eth_getBalance block hash is not canonical"
    "eth_getTransactionCount block hash is not canonical"
    "eth_getCode block hash is not canonical"
    "eth_getStorageAt block hash is not canonical"
    "eth_getProof block hash is not canonical"
    "eth_call block hash is not canonical"
    "eth_estimateGas block hash is not canonical"
    "eth_createAccessList block hash is not canonical"))

(defun smoke-gate-devnet-case-label (case-report)
  (or (smoke-gate-field case-report "fixtureCase") "<unknown>"))

(defun smoke-gate-devnet-case-require-field
    (case-report field expected)
  (let ((actual (smoke-gate-field case-report field)))
    (unless (equal actual expected)
      (error "Devnet smoke gate case ~A field ~A must be ~S, got ~S"
             (smoke-gate-devnet-case-label case-report)
             field
             expected
             actual))
    actual))

(defun smoke-gate-devnet-case-require-false (case-report field)
  (let ((actual (smoke-gate-field case-report field)))
    (unless (smoke-gate-false-p actual)
      (error "Devnet smoke gate case ~A field ~A must be false/null, got ~S"
             (smoke-gate-devnet-case-label case-report)
             field
             actual))))

(defun smoke-gate-devnet-case-require-not-equal
    (case-report field other-field)
  (let ((actual (smoke-gate-field case-report field))
        (other (smoke-gate-field case-report other-field)))
    (unless (and actual other (not (equal actual other)))
      (error "Devnet smoke gate case ~A fields ~A and ~A must differ, got ~S"
             (smoke-gate-devnet-case-label case-report)
             field
             other-field
             actual))))

(defun smoke-gate-devnet-nested-field (object field)
  (when (listp object)
    (smoke-gate-field object field)))

(defun smoke-gate-hex-quantity (value)
  (unless (and (stringp value)
               (<= 2 (length value))
               (char= #\0 (char value 0))
               (char= #\x (char-downcase (char value 1))))
    (error "Expected JSON-RPC hex quantity, got ~S" value))
  (parse-integer value :start 2 :radix 16))

(defun smoke-gate-devnet-case-require-nested-field
    (case-report object-field nested-field expected)
  (let* ((object (smoke-gate-field case-report object-field))
         (actual (smoke-gate-devnet-nested-field object nested-field)))
    (unless (equal actual expected)
      (error "Devnet smoke gate case ~A field ~A.~A must be ~S, got ~S"
             (smoke-gate-devnet-case-label case-report)
             object-field
             nested-field
             expected
             actual))
    actual))

(defun smoke-gate-devnet-case-require-side-pending-object
    (case-report object-field)
  (smoke-gate-devnet-case-require-nested-field
   case-report
   object-field
   "hash"
   (smoke-gate-field case-report "databaseRpcReceiptTransactionHash"))
  (dolist (field '("blockHash" "blockNumber" "transactionIndex"))
    (smoke-gate-devnet-case-require-nested-field
     case-report object-field field nil)))

(defun smoke-gate-devnet-validate-side-reorg-transaction
    (case-report)
  (if (not (smoke-gate-false-p
            (smoke-gate-field
             case-report "databaseRpcSideTransactionReinserted")))
      (let ((expected-hash
              (smoke-gate-field case-report
                                "databaseRpcReceiptTransactionHash"))
            (expected-count
              (smoke-gate-field case-report
                                "databaseRpcTransactionCount")))
        (smoke-gate-devnet-case-require-side-pending-object
         case-report "databaseRpcSideTransactionByHash")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRawTransaction"
         (smoke-gate-field case-report "databaseRpcRawTransactionByHash"))
        (smoke-gate-devnet-case-require-side-pending-object
         case-report "databaseRpcSidePendingTransaction")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRawTransaction"
         (smoke-gate-field case-report "databaseRpcRawTransactionByHash"))
        (smoke-gate-devnet-case-require-side-pending-object
         case-report "databaseRpcSideRestoredPendingTransaction")
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideReinsertedTransactionCount"
         expected-count)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideRestoredReinsertedTransactionCount"
         expected-count)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideHiddenReceiptCount" expected-count)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideRestoredHiddenReceiptCount"
         expected-count)
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideReinsertedTransactionHashes"
         (smoke-gate-field
          case-report "databaseRpcSideRestoredReinsertedTransactionHashes"))
        (unless (member expected-hash
                        (smoke-gate-field
                         case-report
                         "databaseRpcSideReinsertedTransactionHashes")
                        :test #'string=)
          (error "Devnet smoke gate case ~A reinserted transaction hashes ~S must include ~S"
                 (smoke-gate-devnet-case-label case-report)
                 (smoke-gate-field
                  case-report
                  "databaseRpcSideReinsertedTransactionHashes")
                 expected-hash)))
      (dolist (field '("databaseRpcSideTransactionByHash"
                       "databaseRpcSideRawTransaction"
                       "databaseRpcSidePendingTransaction"
                       "databaseRpcSideReinsertedTransactionCount"
                       "databaseRpcSideReinsertedTransactionHashes"
                       "databaseRpcSideHiddenReceiptCount"
                       "databaseRpcSideRestoredRawTransaction"
                       "databaseRpcSideRestoredPendingTransaction"
                       "databaseRpcSideRestoredReinsertedTransactionCount"
                       "databaseRpcSideRestoredReinsertedTransactionHashes"
                       "databaseRpcSideRestoredHiddenReceiptCount"))
        (smoke-gate-devnet-case-require-false case-report field))))

(defun smoke-gate-devnet-validate-side-reorg-case (case-report)
  (if (smoke-gate-false-p
       (smoke-gate-field case-report "databaseRpcSideBlockHash"))
      (progn
        (dolist (field +smoke-gate-devnet-side-reorg-pruned-fields+)
          (smoke-gate-devnet-case-require-false case-report field))
        0)
      (progn
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideForkchoiceStatus" "VALID")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRejectedCheckpointError"
         "forkchoice safe block is not an ancestor of head")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideBlockNumber"
         (smoke-gate-field case-report "blockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideLatestBlockHash"
         (smoke-gate-field case-report "databaseRpcSideBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredHeadHash"
         (smoke-gate-field case-report "databaseRpcSideBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredHeadNumber"
         (smoke-gate-field case-report "blockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcBlockNumber"
         (smoke-gate-field case-report "blockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcLatestBlockHash"
         (smoke-gate-field case-report "databaseRpcSideBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredSafeNumber"
         (smoke-gate-field case-report "safeBlockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredSafeHash"
         (smoke-gate-field case-report "safeBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredFinalizedNumber"
         (smoke-gate-field case-report "finalizedBlockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredFinalizedHash"
         (smoke-gate-field case-report "finalizedBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcSafeNumber"
         (smoke-gate-field case-report "safeBlockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcSafeHash"
         (smoke-gate-field case-report "safeBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcFinalizedNumber"
         (smoke-gate-field case-report "finalizedBlockNumber"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredRpcFinalizedHash"
         (smoke-gate-field case-report "finalizedBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredSafeBalance"
         (smoke-gate-field case-report "checkedCheckpointBalance"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredFinalizedBalance"
         (smoke-gate-field case-report "checkedCheckpointBalance"))
        (smoke-gate-devnet-case-require-not-equal
         case-report "databaseRpcBlockHash" "databaseRpcSideBlockHash")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideChildBlockHash"
         (smoke-gate-field case-report "databaseRpcBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideBlockReceiptsCount" 0)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideLogCount" 0)
        (smoke-gate-devnet-validate-side-reorg-transaction case-report)
        (smoke-gate-devnet-case-require-false
         case-report "databaseRpcSideReceipt")
        (smoke-gate-devnet-case-require-false
         case-report "databaseRpcSideRestoredReceipt")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredChildBlockHash"
         (smoke-gate-field case-report "databaseRpcBlockHash"))
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredChildRequireCanonicalError"
         "eth_getBalance block hash is not canonical")
        (smoke-gate-devnet-case-require-field
         case-report
         "databaseRpcSideRestoredChildRequireCanonicalErrors"
         +smoke-gate-devnet-noncanonical-state-errors+)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideRestoredBlockReceiptsCount" 0)
        (smoke-gate-devnet-case-require-field
         case-report "databaseRpcSideRestoredLogCount" 0)
        (let* ((transaction-count
                 (smoke-gate-field case-report "databaseRpcTransactionCount"))
               (extra-transaction-count (max 0 (1- transaction-count)))
               (side-public-connections (+ 9 extra-transaction-count))
               (restored-public-connections (+ 20 extra-transaction-count)))
          (smoke-gate-devnet-case-require-field
           case-report "databaseRpcSideEngineConnections" 3)
          (smoke-gate-devnet-case-require-field
           case-report "databaseRpcSidePublicConnections"
           side-public-connections)
          (smoke-gate-devnet-case-require-field
           case-report "databaseRpcSideRestoredPublicConnections"
           restored-public-connections)
          (smoke-gate-devnet-case-require-field
           case-report "databaseRpcSideTotalConnections"
           (+ 3 side-public-connections restored-public-connections)))
        1)))

(defun smoke-gate-validate-devnet-side-reorg-cases
    (report expected-count)
  (let ((cases (smoke-gate-field report "cases"))
        (side-reorg-count 0))
    (unless (and (listp cases) (= expected-count (length cases)))
      (error "Devnet smoke gate cases must have count ~D, got ~S"
             expected-count
             (and (listp cases) (length cases))))
    (dolist (case-report cases side-reorg-count)
      (incf side-reorg-count
            (smoke-gate-devnet-validate-side-reorg-case case-report)))))

(defun smoke-gate-validate-devnet-summary
    (report ready-file log-file pid-file database-file)
  (let ((expected-count
          (length
           (smoke-gate-variable "+engine-newpayload-v2-smoke-case-names+"))))
    (unless (string= "ok" (smoke-gate-field report "status"))
      (error "Devnet smoke gate returned non-ok status: ~S" report))
    (smoke-gate-devnet-require-field report "readyFile" ready-file)
    (smoke-gate-devnet-require-field report "logFile" log-file)
    (smoke-gate-devnet-require-field report "pidFile" pid-file)
    (smoke-gate-devnet-require-field report "databaseFile" database-file)
    (smoke-gate-devnet-require-field
     report
     "databasePruneStateBefore"
     +smoke-gate-devnet-prune-state-before+)
    (smoke-gate-devnet-require-field
     report
     "caseCount"
     expected-count)
    (smoke-gate-devnet-require-case-files
     report "readyFile" "readyCaseCount" expected-count)
    (smoke-gate-devnet-require-case-files
     report "logFile" "logCaseCount" expected-count)
    (smoke-gate-devnet-require-case-files
     report "pidFile" "pidCaseCount" expected-count)
    (smoke-gate-devnet-require-case-files
     report "databaseFile" "databaseCaseCount" expected-count)
    (append
     report
     (list
      (cons "sideReorgCaseCount"
            (smoke-gate-validate-devnet-side-reorg-cases
             report expected-count))))))

(defun smoke-gate-validate-devnet-engine-only-summary
    (report ready-file log-file pid-file database-file)
  (unless (string= "ok" (smoke-gate-field report "status"))
    (error "Devnet Engine-only smoke gate returned non-ok status: ~S"
           report))
  (smoke-gate-devnet-require-field
   report "mode" "devnet-engine-only-serve")
  (smoke-gate-devnet-require-field report "readyFile" ready-file)
  (smoke-gate-devnet-require-field report "logFile" log-file)
  (smoke-gate-devnet-require-field report "pidFile" pid-file)
  (smoke-gate-devnet-require-field report "databaseFile" database-file)
  (smoke-gate-devnet-require-field report "engineConnections" 11)
  (smoke-gate-devnet-require-field report "publicConnections" 0)
  (smoke-gate-devnet-require-field report "totalConnections" 11)
  (smoke-gate-devnet-require-field report "engineRpcPrefix" "/engine")
  (smoke-gate-devnet-require-field report "engineRpcPrefixStatus" 200)
  (smoke-gate-devnet-require-field
   report "engineRpcPrefixBlockedStatus" 404)
  (smoke-gate-devnet-require-field
   report "hiddenPayloadBodiesByRangeV2Status" 200)
  (smoke-gate-devnet-require-field
   report "hiddenPayloadBodiesByRangeV2ErrorCode" -32601)
  (smoke-gate-devnet-require-field
   report "hiddenPayloadBodiesByRangeV2ErrorMessage" "Method not found")
  (smoke-gate-devnet-require-field
   report
   "engineCorsOrigins"
   '("https://engine-runner.example" "https://engine-observer.example"))
  (smoke-gate-devnet-require-field
   report "engineCorsHeader" "https://engine-runner.example")
  (smoke-gate-devnet-require-field
   report "engineCorsVaryHeader" "Origin")
  (smoke-gate-devnet-require-field
   report "engineVhosts" '("engine.runner" "localhost"))
  (unless (plusp (or (smoke-gate-field report "engineCapabilityCount") 0))
    (error "Devnet Engine-only capabilities are missing: ~S" report))
  (dolist (field '("engineCapabilityHasNewPayloadV1"
                   "engineCapabilityHasForkchoiceUpdatedV1"
                   "engineCapabilityHasGetPayloadV1"
                   "engineCapabilityHasNewPayloadV2"
                   "engineCapabilityHasForkchoiceUpdatedV2"
                   "engineCapabilityHasGetPayloadV2"))
    (smoke-gate-devnet-require-field report field t))
  (dolist (field '("engineCapabilityHasNewPayloadV3"
                   "engineCapabilityHasGetBlobsV1"
                   "engineCapabilityHasPayloadBodiesV2"))
    (smoke-gate-devnet-require-field report field nil))
  (smoke-gate-devnet-require-field report "engineClientVersionCode" "CL")
  (smoke-gate-devnet-require-field
   report "engineClientVersionName" "ethereum-lisp")
  (smoke-gate-devnet-require-field report "engineClientVersionVersion" "0.1.0")
  (smoke-gate-devnet-require-field report "engineClientVersionCommit" "0x00000000")
  (smoke-gate-devnet-require-field
   report "engineTransitionTerminalTotalDifficulty" "0x0")
  (smoke-gate-devnet-require-field
   report
   "engineTransitionTerminalBlockHash"
   "0x0000000000000000000000000000000000000000000000000000000000000000")
  (smoke-gate-devnet-require-field
   report "engineTransitionTerminalBlockNumber" "0x0")
  (smoke-gate-devnet-require-field
   report "engineTransitionMismatchErrorCode" -32602)
  (unless (search "terminalTotalDifficulty mismatch"
                  (or (smoke-gate-field
                       report "engineTransitionMismatchErrorMessage")
                      ""))
    (error "Devnet Engine-only transition mismatch message missing: ~S"
           report))
  (smoke-gate-devnet-require-field
   report "fixtureCase" "shanghai-one-transfer-with-withdrawal")
  (smoke-gate-devnet-require-field
   report "newPayloadStatus" "VALID")
  (smoke-gate-devnet-require-field
   report "forkchoiceStatus" "VALID")
  (unless (and (stringp (smoke-gate-field report "latestValidHash"))
               (string= (smoke-gate-field report "latestValidHash")
                        (smoke-gate-field report "forkchoiceHeadHash")))
    (error "Devnet Engine-only latestValidHash/forkchoice head mismatch: ~S"
           report))
  (unless (stringp (smoke-gate-field report "forkchoiceHeadNumber"))
    (error "Devnet Engine-only forkchoice head number missing: ~S" report))
  (unless (= (smoke-gate-hex-quantity
              (smoke-gate-field report "forkchoiceHeadNumber"))
             (smoke-gate-field report "databaseHeadNumber"))
    (error "Devnet Engine-only database head number mismatch: ~S" report))
  (unless (and (stringp (smoke-gate-field report "databaseHeadHash"))
               (string= (smoke-gate-field report "forkchoiceHeadHash")
                        (smoke-gate-field report "databaseHeadHash")))
    (error "Devnet Engine-only database head hash mismatch: ~S" report))
  (smoke-gate-devnet-require-field report "databaseStateAvailable" t)
  (smoke-gate-devnet-require-field report "publicRpcEnabled" nil)
  (smoke-gate-devnet-require-field report "rpcEndpoint" nil)
  (unless (and (stringp (smoke-gate-field report "configuredPublicEndpoint"))
               (smoke-gate-http-endpoint-p
                (smoke-gate-field report "configuredPublicEndpoint")))
    (error "Devnet Engine-only configured public endpoint is not probeable: ~S"
           report))
  (smoke-gate-devnet-require-field
   report "publicEndpointConnectable" nil)
  (let ((contract (smoke-gate-field report "connectionContract")))
    (smoke-gate-devnet-require-field
     contract "expectedEngineConnections" 11)
    (smoke-gate-devnet-require-field
     contract "expectedPublicConnections" 0)
    (smoke-gate-devnet-require-field
     contract "expectedTotalConnections" 11))
  (append report (list (cons "caseCount" 1))))

