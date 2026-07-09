(in-package #:ethereum-lisp.test)

(defun devnet-cli-temp-directory (name)
  (let ((path
          (merge-pathnames
           (format nil "~A-~A/" name (devnet-cli-temp-token))
           #P"/private/tmp/")))
    (ensure-directories-exist path)
    path))

(defun devnet-cli-restored-public-connections (report)
  (+ 29
     (1- (fixture-object-field report "checkedBalanceCount"))
     (* 7 (1- (fixture-object-field report "transactionCount")))
     (* 6 (fixture-object-field report "checkedLogFilterCount"))
     (fixture-object-field report "checkedSimulationCount")
     (let ((errors
             (fixture-object-field report "databaseRpcPrunedStateErrors")))
       (if errors
           (length errors)
           0))))

(defun devnet-cli-assert-restored-full-block-transactions (report)
  (is (= (fixture-object-field report "transactionCount")
         (fixture-object-field
          report "databaseRpcFullBlockTransactionCount")))
  (is (= (fixture-object-field report "transactionCount")
         (fixture-object-field
          report "databaseRpcFullBlockByNumberTransactionCount")))
  (is (string= (fixture-object-field
                report "databaseRpcReceiptTransactionHash")
               (fixture-object-field
                report "databaseRpcFullBlockTransactionHash")))
  (is (string= (fixture-object-field
                report "databaseRpcReceiptTransactionHash")
               (fixture-object-field
                report "databaseRpcFullBlockByNumberTransactionHash")))
  (is (string= "0x0"
               (fixture-object-field
                report "databaseRpcFullBlockTransactionIndex")))
  (is (string= "0x0"
               (fixture-object-field
                report "databaseRpcFullBlockByNumberTransactionIndex"))))

(defun devnet-cli-assert-restored-log-filters (report)
  (let ((checked-log-count
          (fixture-object-field report "checkedLogCount"))
        (checked-filter-count
          (fixture-object-field report "checkedLogFilterCount")))
    (is (= checked-filter-count
           (fixture-object-field report "databaseRpcLogFilterCount")))
    (is (= checked-log-count
           (fixture-object-field
            report "databaseRpcLogFilterLogCount")))
    (is (= checked-filter-count
           (fixture-object-field
            report "databaseRpcLogFilterUninstallCount")))
    (let ((missing-error-codes
            (fixture-object-field
             report "databaseRpcLogFilterMissingErrorCodes")))
      (is (= checked-filter-count (length missing-error-codes)))
      (is (every (lambda (code)
                   (= -32602 code))
                 missing-error-codes)))))

(defun devnet-cli-assert-restored-block-filter (report)
  (is (string= (quantity-to-hex
                (1+ (fixture-object-field report "checkedLogFilterCount")))
               (fixture-object-field report "databaseRpcBlockFilterId")))
  (is (= 0
         (fixture-object-field
          report "databaseRpcBlockFilterChangeCount")))
  (is (= -32602
         (fixture-object-field
          report "databaseRpcBlockFilterGetLogsErrorCode")))
  (is (fixture-object-field
       report "databaseRpcBlockFilterUninstallResult"))
  (is (= -32602
         (fixture-object-field
          report "databaseRpcBlockFilterMissingErrorCode"))))

(defun devnet-cli-assert-txpool-subpool-persistence (report)
  (is (string= "0x1"
               (fixture-object-field report "txpoolStatusPending")))
  (is (string= "0x2"
               (fixture-object-field report "txpoolStatusQueued")))
  (is (string= (fixture-object-field report "txpoolImportTransactionHash")
               (fixture-object-field report "databaseRpcTxpoolPendingHash")))
  (is (string= (fixture-object-field report "txpoolImportRawTransaction")
               (fixture-object-field report "databaseRpcTxpoolRawTransaction")))
  (is (string= (fixture-object-field report "txpoolPendingSender")
               (fixture-object-field report "databaseRpcTxpoolSender")))
  (is (string= (fixture-object-field report "txpoolPendingNonce")
               (fixture-object-field report "databaseRpcTxpoolNonce")))
  (is (= (1+ (parse-integer
              (fixture-object-field report "txpoolPendingNonce")))
         (hex-to-quantity
          (fixture-object-field report "txpoolPendingSenderNonce"))))
  (is (string= (fixture-object-field report "txpoolPendingSenderNonce")
               (fixture-object-field
                report "databaseRpcTxpoolPendingSenderNonce")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolInspectSummary")))
  (is (string= "0x1"
               (fixture-object-field report "txpoolPendingFilterId")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field report "txpoolPendingFilterHash")))
  (let ((filter-changes
          (fixture-object-field report "txpoolPendingFilterChanges")))
    (is (= 1 (length filter-changes)))
    (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
                 (first filter-changes))))
  (is (devnet-cli-empty-json-array-or-lossy-null-p
       (fixture-object-field report "txpoolPendingFilterEmptyChanges")))
  (is (eq t (fixture-object-field
             report "txpoolPendingFilterUninstallResult")))
  (is (= -32602
         (fixture-object-field
          report "txpoolPendingFilterMissingErrorCode")))
  (is (= 1
         (fixture-object-field report "txpoolRejournalSeconds")))
  (is (eq t
          (fixture-object-field
           report "txpoolRejournalObservedBeforeShutdown")))
  (is (= 3
         (fixture-object-field report "txpoolRejournalRecordCount")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field report
                                     "txpoolRejournalTransactionHash")))
  (is (string= "pending"
               (fixture-object-field report "txpoolRejournalSubpool")))
  (is (= 1
         (fixture-object-field report "devPeriodSeconds")))
  (is (stringp
       (fixture-object-field report "devPeriodTransactionHash")))
  (is (string= (fixture-object-field report "devPeriodBlockNumber")
               (fixture-object-field
                report "devPeriodReceiptBlockNumber")))
  (is (string= (fixture-object-field report "devPeriodBlockHash")
               (fixture-object-field report "devPeriodReceiptBlockHash")))
  (is (string= "0x0"
               (fixture-object-field report "devPeriodTransactionIndex")))
  (is (string= "0x0"
               (fixture-object-field
                report "devPeriodTxpoolStatusPending")))
  (is (string= "0x0"
               (fixture-object-field
                report "devPeriodTxpoolStatusQueued")))
  (is (= 0
         (fixture-object-field
          report "devPeriodPendingTransactionCount")))
  (is (= 0
         (fixture-object-field report "devPeriodEngineConnections")))
  (is (= 7
         (fixture-object-field report "devPeriodPublicConnections")))
  (is (= 7
         (fixture-object-field report "devPeriodTotalConnections")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field report "databaseRpcTxpoolBasefeeHash")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionRaw")
               (fixture-object-field
                report "databaseRpcTxpoolBasefeeRawTransaction")))
  (is (string= (fixture-object-field report "txpoolBasefeeNonce")
               (fixture-object-field report "databaseRpcTxpoolBasefeeNonce")))
  (is (string= (fixture-object-field report "txpoolBasefeeInspectSummary")
               (fixture-object-field
                report "databaseRpcTxpoolBasefeeInspectSummary")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field report "databaseRpcTxpoolQueuedHash")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionRaw")
               (fixture-object-field
                report "databaseRpcTxpoolQueuedRawTransaction")))
  (is (string= (fixture-object-field report "txpoolQueuedNonce")
               (fixture-object-field report "databaseRpcTxpoolQueuedNonce")))
  (is (string= (fixture-object-field report "txpoolQueuedInspectSummary")
               (fixture-object-field
                report "databaseRpcTxpoolQueuedInspectSummary")))
  (is (string= "0x0"
               (fixture-object-field report "databaseRpcTxpoolStatusPending")))
  (is (string= "0x2"
               (fixture-object-field report "databaseRpcTxpoolStatusQueued")))
  (is (string= "0x0"
               (fixture-object-field
                report "databaseRpcTxpoolPendingBlockCount")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingBlockHash")))
  (is (stringp (fixture-object-field
                report "databaseRpcTxpoolPendingBlockBaseFee")))
  (is (stringp (fixture-object-field
                report "databaseRpcTxpoolPendingHeaderNumber")))
  (is (stringp (fixture-object-field
                report "databaseRpcTxpoolPendingHeaderParentHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingHeaderHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingHeaderNonce")))
  (is (string= (fixture-object-field
                report "databaseRpcTxpoolPendingFeeHistoryNextBaseFee")
               (fixture-object-field
                report "databaseRpcTxpoolPendingBlockBaseFee")))
  (is (string= (fixture-object-field
                report "databaseRpcTxpoolPendingFeeHistoryNextBaseFee")
               (fixture-object-field
                report "databaseRpcTxpoolPendingHeaderBaseFee")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingBlockTransactionHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingBlockTransactionBlockHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingIndexHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingIndexBlockHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolPendingRawByIndex")))
  (is (null (fixture-object-field report "databaseRpcTxpoolContentHash")))
  (is (null (fixture-object-field
             report "databaseRpcTxpoolContentFromHash")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report "databaseRpcTxpoolBasefeeContentHash")))
  (is (string= (fixture-object-field report "txpoolBasefeeTransactionHash")
               (fixture-object-field
                report "databaseRpcTxpoolBasefeeContentFromHash")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report "databaseRpcTxpoolQueuedContentHash")))
  (is (string= (fixture-object-field report "txpoolQueuedTransactionHash")
               (fixture-object-field
                report "databaseRpcTxpoolQueuedContentFromHash")))
  (is (= 15
         (fixture-object-field report "databaseRpcTxpoolPublicConnections"))))

