(in-package #:ethereum-lisp.test)

(defun devnet-cli-assert-side-reorg-persistence (report)
  (when (fixture-object-field report "databaseFile")
    (if (fixture-object-field report "databasePruneStateBefore")
        (dolist (field '("databaseRpcSideBlockHash"
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
          (is (eq nil (fixture-object-field report field))))
        (progn
          (is (string= "VALID"
                       (fixture-object-field
                        report "databaseRpcSideForkchoiceStatus")))
          (is (string= "forkchoice safe block is not an ancestor of head"
                       (fixture-object-field
                        report "databaseRpcSideRejectedCheckpointError")))
          (is (string= (fixture-object-field report "blockNumber")
                       (fixture-object-field
                        report "databaseRpcSideBlockNumber")))
          (is (string= (fixture-object-field report "databaseRpcSideBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideLatestBlockHash")))
          (is (string= (fixture-object-field report "databaseRpcSideBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredHeadHash")))
          (is (string= (fixture-object-field report "blockNumber")
                       (fixture-object-field
                        report "databaseRpcSideRestoredHeadNumber")))
          (is (string= (fixture-object-field report "blockNumber")
                       (fixture-object-field
                        report "databaseRpcSideRestoredRpcBlockNumber")))
          (is (string= (fixture-object-field report "databaseRpcSideBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredRpcLatestBlockHash")))
          (is (string= (fixture-object-field report "safeBlockNumber")
                       (fixture-object-field
                        report "databaseRpcSideRestoredSafeNumber")))
          (is (string= (fixture-object-field report "safeBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredSafeHash")))
          (is (string= (fixture-object-field report "finalizedBlockNumber")
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredFinalizedNumber")))
          (is (string= (fixture-object-field report "finalizedBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredFinalizedHash")))
          (is (string= (fixture-object-field report "safeBlockNumber")
                       (fixture-object-field
                        report "databaseRpcSideRestoredRpcSafeNumber")))
          (is (string= (fixture-object-field report "safeBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredRpcSafeHash")))
          (is (string= (fixture-object-field report "finalizedBlockNumber")
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredRpcFinalizedNumber")))
          (is (string= (fixture-object-field report "finalizedBlockHash")
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredRpcFinalizedHash")))
          (is (string= (fixture-object-field
                        report "checkedCheckpointBalance")
                       (fixture-object-field
                        report "databaseRpcSideRestoredSafeBalance")))
          (is (string= (fixture-object-field
                        report "checkedCheckpointBalance")
                       (fixture-object-field
                        report "databaseRpcSideRestoredFinalizedBalance")))
          (is (not (string= (fixture-object-field
                             report "databaseRpcBlockHash")
                            (fixture-object-field
                             report "databaseRpcSideBlockHash"))))
          (is (string= (fixture-object-field report "databaseRpcBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideChildBlockHash")))
          (is (= 0
                 (fixture-object-field
                  report "databaseRpcSideBlockReceiptsCount")))
          (is (= 0
                 (fixture-object-field report "databaseRpcSideLogCount")))
          (if (fixture-object-field report
                                    "databaseRpcSideTransactionReinserted")
              (progn
                (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                             (fixture-object-field
                              (fixture-object-field
                               report "databaseRpcSideTransactionByHash")
                              "hash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSideTransactionByHash")
                         "blockHash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSideTransactionByHash")
                         "blockNumber")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSideTransactionByHash")
                         "transactionIndex")))
                (is (string= (fixture-object-field
                              report "databaseRpcRawTransactionByHash")
                             (fixture-object-field
                              report "databaseRpcSideRawTransaction")))
                (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                             (fixture-object-field
                              (fixture-object-field
                               report "databaseRpcSidePendingTransaction")
                              "hash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSidePendingTransaction")
                         "blockHash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSidePendingTransaction")
                         "blockNumber")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report "databaseRpcSidePendingTransaction")
                         "transactionIndex")))
                (is (string= (fixture-object-field
                              report "databaseRpcRawTransactionByHash")
                             (fixture-object-field
                              report
                              "databaseRpcSideRestoredRawTransaction")))
                (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                             (fixture-object-field
                              (fixture-object-field
                               report
                               "databaseRpcSideRestoredPendingTransaction")
                              "hash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report
                          "databaseRpcSideRestoredPendingTransaction")
                         "blockHash")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report
                          "databaseRpcSideRestoredPendingTransaction")
                         "blockNumber")))
                (is (eq nil
                        (fixture-object-field
                         (fixture-object-field
                          report
                          "databaseRpcSideRestoredPendingTransaction")
                         "transactionIndex"))))
              (progn
                (is (eq nil
                        (fixture-object-field
                         report "databaseRpcSideTransactionByHash")))
                (is (eq nil
                        (fixture-object-field
                         report "databaseRpcSideRawTransaction")))
                (is (eq nil
                        (fixture-object-field
                         report "databaseRpcSidePendingTransaction")))
                (is (eq nil
                        (fixture-object-field
                         report "databaseRpcSideRestoredRawTransaction")))
                (is (eq nil
                        (fixture-object-field
                         report
                         "databaseRpcSideRestoredPendingTransaction")))))
          (when (fixture-object-field report
                                      "databaseRpcSideTransactionReinserted")
            (is (= (fixture-object-field report "databaseRpcTransactionCount")
                   (fixture-object-field
                    report "databaseRpcSideReinsertedTransactionCount")))
            (is (= (fixture-object-field report "databaseRpcTransactionCount")
                   (fixture-object-field
                    report
                    "databaseRpcSideRestoredReinsertedTransactionCount")))
            (is (= (fixture-object-field report "databaseRpcTransactionCount")
                   (fixture-object-field
                    report "databaseRpcSideHiddenReceiptCount")))
            (is (= (fixture-object-field report "databaseRpcTransactionCount")
                   (fixture-object-field
                    report
                    "databaseRpcSideRestoredHiddenReceiptCount")))
            (is (equal (fixture-object-field
                        report "databaseRpcSideReinsertedTransactionHashes")
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredReinsertedTransactionHashes")))
            (is (member (fixture-object-field
                         report "databaseRpcReceiptTransactionHash")
                        (fixture-object-field
                         report
                         "databaseRpcSideReinsertedTransactionHashes")
                        :test #'string=)))
          (is (eq nil
                  (fixture-object-field report "databaseRpcSideReceipt")))
          (is (eq nil
                  (fixture-object-field
                   report "databaseRpcSideRestoredReceipt")))
          (is (string= (fixture-object-field report "databaseRpcBlockHash")
                       (fixture-object-field
                        report "databaseRpcSideRestoredChildBlockHash")))
          (is (string= "eth_getBalance block hash is not canonical"
                       (fixture-object-field
                        report
                        "databaseRpcSideRestoredChildRequireCanonicalError")))
          (is (equal (devnet-cli-noncanonical-state-error-messages)
                     (fixture-object-field
                      report
                      "databaseRpcSideRestoredChildRequireCanonicalErrors")))
          (is (= 0
                 (fixture-object-field
                  report "databaseRpcSideRestoredBlockReceiptsCount")))
          (is (= 0
                 (fixture-object-field
                  report "databaseRpcSideRestoredLogCount")))
          (let* ((transaction-count
                   (fixture-object-field report "databaseRpcTransactionCount"))
                 (extra-transaction-count (max 0 (1- transaction-count)))
                 (side-public-connections (+ 9 extra-transaction-count))
                 (restored-public-connections
                   (+ 20 extra-transaction-count)))
            (is (= 3
                   (fixture-object-field
                    report "databaseRpcSideEngineConnections")))
            (is (= side-public-connections
                   (fixture-object-field
                    report "databaseRpcSidePublicConnections")))
            (is (= restored-public-connections
                   (fixture-object-field
                    report
                    "databaseRpcSideRestoredPublicConnections")))
            (is (= (+ 3 side-public-connections
                      restored-public-connections)
                   (fixture-object-field
                    report "databaseRpcSideTotalConnections"))))))))

(defun devnet-cli-pruned-state-error-messages ()
  '("eth_getBalance state is not available"
    "eth_getTransactionCount state is not available"
    "eth_getCode state is not available"
    "eth_getStorageAt state is not available"
    "eth_getProof state is not available"
    "eth_call state is not available"
    "eth_estimateGas state is not available"
    "eth_createAccessList state is not available"))

(defun devnet-cli-noncanonical-state-error-messages ()
  '("eth_getBalance block hash is not canonical"
    "eth_getTransactionCount block hash is not canonical"
    "eth_getCode block hash is not canonical"
    "eth_getStorageAt block hash is not canonical"
    "eth_getProof block hash is not canonical"
    "eth_call block hash is not canonical"
    "eth_estimateGas block hash is not canonical"
    "eth_createAccessList block hash is not canonical"))

(defun devnet-cli-pruned-state-covered-p (report prune-boundary)
  (< (hex-to-quantity (fixture-object-field report "safeBlockNumber"))
     prune-boundary))

(defun devnet-cli-assert-pruned-state-case
    (case prune-boundary)
  (if (devnet-cli-pruned-state-covered-p case prune-boundary)
      (progn
        (is (eq nil
                (fixture-object-field
                 case "databasePrunedStateAvailable")))
        (is (string= "eth_getBalance state is not available"
                     (fixture-object-field
                      case "databaseRpcPrunedStateError")))
        (is (equal (devnet-cli-pruned-state-error-messages)
                   (fixture-object-field
                    case "databaseRpcPrunedStateErrors"))))
      (progn
        (is (eq t
                (fixture-object-field
                 case "databasePrunedStateAvailable")))
        (is (eq nil
                (fixture-object-field
                 case "databaseRpcPrunedStateError")))
        (is (eq nil
                (fixture-object-field
                 case "databaseRpcPrunedStateErrors"))))))

(defun devnet-cli-assert-pruned-state-suite
    (report cases prune-boundary)
  (let ((pruned-case-count
          (count-if
           (lambda (case)
             (devnet-cli-pruned-state-covered-p case prune-boundary))
           cases)))
    (is (< 0 pruned-case-count))
    (is (< pruned-case-count (length cases)))
    (is (= prune-boundary
           (fixture-object-field report "databasePruneStateBefore")))
    (is (= pruned-case-count
           (fixture-object-field
            report "databasePrunedStateCaseCount")))
    (is (= pruned-case-count
           (fixture-object-field
            report "databaseRpcPrunedStateErrorCaseCount")))
    (dolist (case cases)
      (devnet-cli-assert-pruned-state-case case prune-boundary))))

