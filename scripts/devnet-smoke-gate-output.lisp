(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-sanitize-path-component (value)
  (coerce
   (map 'list
        (lambda (char)
          (if (or (alphanumericp char)
                  (member char '(#\- #\_) :test #'char=))
              char
              #\_))
        value)
   'string))

(defun devnet-smoke-gate-case-path (path case-name &key default-name)
  (when path
    (let* ((pathname (pathname path))
           (name (or (pathname-name pathname) "devnet-chain"))
           (type (pathname-type pathname))
           (case-component
             (devnet-smoke-gate-sanitize-path-component case-name)))
      (namestring
       (make-pathname
        :name (format nil "~A-~A"
                      (or name default-name "devnet-artifact")
                      case-component)
        :type type
        :defaults pathname)))))

(defun devnet-smoke-gate-run-all
    (case-names &key ready-file log-file pid-file database-file
       state-prune-before terminal-total-difficulty
       terminal-total-difficulty-passed-p terminal-block-hash
       terminal-block-number)
  (let* ((reports
           (mapcar (lambda (case-name)
                     (devnet-smoke-gate-strip-run-metadata
                      (devnet-smoke-gate-run
                       case-name
                       :ready-file
                       (devnet-smoke-gate-case-path
                        ready-file case-name :default-name "ready")
                       :log-file
                       (devnet-smoke-gate-case-path
                        log-file case-name :default-name "devnet")
                       :pid-file
                       (devnet-smoke-gate-case-path
                        pid-file case-name :default-name "devnet")
                       :database-file
                       (devnet-smoke-gate-case-path
                        database-file case-name
                        :default-name "devnet-chain")
                       :state-prune-before state-prune-before
                       :terminal-total-difficulty
                       terminal-total-difficulty
                       :terminal-total-difficulty-passed-p
                       terminal-total-difficulty-passed-p
                       :terminal-block-hash terminal-block-hash
                       :terminal-block-number terminal-block-number)))
                   case-names))
         (engine-connections
           (reduce #'+ reports
                   :key (lambda (report)
                          (devnet-smoke-gate-field report
                                                   "engineConnections"))
                   :initial-value 0))
         (public-connections
           (reduce #'+ reports
                   :key (lambda (report)
                          (devnet-smoke-gate-field report
                                                   "publicConnections"))
                   :initial-value 0))
         (pruned-state-case-count
           (count-if
            (lambda (report)
              (devnet-smoke-gate-report-pruned-state-covered-p
               report state-prune-before))
            reports))
         (pruned-state-error-case-count
           (count-if
            (lambda (report)
              (let ((errors
                      (devnet-smoke-gate-field
                       report "databaseRpcPrunedStateErrors")))
                (and errors
                     (equal (devnet-smoke-gate-pruned-state-error-messages)
                            errors))))
            reports)))
    (devnet-smoke-gate-require
     (= (length case-names) (length reports))
     "Devnet smoke gate suite case count mismatch")
    (when database-file
      (dolist (report reports)
        (let ((expected-head-number
                (or (devnet-smoke-gate-field report "txpoolImportBlockNumber")
                    (devnet-smoke-gate-field report "blockNumber"))))
          (devnet-smoke-gate-require
           (string= expected-head-number
                    (devnet-smoke-gate-field report "databaseHeadNumber"))
           "Devnet smoke gate suite database head mismatch for ~A"
           (devnet-smoke-gate-field report "fixtureCase")))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockNumber")
                  (devnet-smoke-gate-field report "databaseSafeNumber"))
         "Devnet smoke gate suite database safe checkpoint mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockHash")
                  (devnet-smoke-gate-field report "databaseSafeHash"))
         "Devnet smoke gate suite database safe hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockNumber")
                  (devnet-smoke-gate-field report "databaseFinalizedNumber"))
         "Devnet smoke gate suite database finalized checkpoint mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                  (devnet-smoke-gate-field report "databaseFinalizedHash"))
         "Devnet smoke gate suite database finalized hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (let ((pruned-state-covered-p
                (devnet-smoke-gate-report-pruned-state-covered-p
                 report state-prune-before))
              (pruned-errors
                (devnet-smoke-gate-field
                 report "databaseRpcPrunedStateErrors")))
          (if pruned-state-covered-p
              (progn
                (devnet-smoke-gate-require
                 (devnet-smoke-gate-false-p
                  (devnet-smoke-gate-field
                   report "databasePrunedStateAvailable"))
                 "Devnet smoke gate suite pruned state still available for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (equal (devnet-smoke-gate-pruned-state-error-messages)
                        pruned-errors)
                 "Devnet smoke gate suite pruned-state RPC errors mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase")))
              (when state-prune-before
                (devnet-smoke-gate-require
                 (devnet-smoke-gate-field
                  report "databasePrunedStateAvailable")
                 "Devnet smoke gate suite unexpectedly pruned state for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (devnet-smoke-gate-false-p pruned-errors)
                 "Devnet smoke gate suite unexpected pruned-state RPC errors for ~A"
                 (devnet-smoke-gate-field report "fixtureCase")))))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedCode")
                  (devnet-smoke-gate-field report "databaseRpcCode"))
         "Devnet smoke gate suite restored code mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedNonce")
                  (devnet-smoke-gate-field report "databaseRpcNonce"))
         "Devnet smoke gate suite restored nonce mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorage")
                  (devnet-smoke-gate-field report "databaseRpcStorage"))
         "Devnet smoke gate suite restored storage mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorageAddress")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofAddress"))
         "Devnet smoke gate suite restored proof address mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedProofCodeHash")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofCodeHash"))
         "Devnet smoke gate suite restored proof code hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorageKey")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofStorageKey"))
         "Devnet smoke gate suite restored proof storage key mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedProofStorageValue")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofStorageValue"))
         "Devnet smoke gate suite restored proof storage value mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= 1 (devnet-smoke-gate-field report
                                       "databaseRpcProofStorageCount"))
         "Devnet smoke gate suite restored proof storage count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (<= 0 (devnet-smoke-gate-field
                report "databaseRpcProofAccountProofCount"))
         "Devnet smoke gate suite restored proof account proof count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcReceiptBlockNumber"))
         "Devnet smoke gate suite restored receipt block mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcBlockByHashNumber"))
         "Devnet smoke gate suite restored block-by-hash number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockByNumberNumber"))
         "Devnet smoke gate suite restored block-by-number number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionBlockNumber"))
         "Devnet smoke gate suite restored transaction block mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockReceiptBlockNumber"))
         "Devnet smoke gate suite restored block receipt number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field report
                                     "databaseRpcBlockReceiptsCount"))
         "Devnet smoke gate suite restored block receipts count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (quantity-to-hex
                   (devnet-smoke-gate-field report "transactionCount"))
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockTransactionCountByHash"))
         "Devnet smoke gate suite restored block tx count by hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (quantity-to-hex
                   (devnet-smoke-gate-field report "transactionCount"))
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockTransactionCountByNumber"))
         "Devnet smoke gate suite restored block tx count by number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field report "databaseRpcTransactionCount"))
         "Devnet smoke gate suite restored transaction count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field
             report "databaseRpcFullBlockTransactionCount"))
         "Devnet smoke gate suite restored full block transaction count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field
             report "databaseRpcFullBlockByNumberTransactionCount"))
         "Devnet smoke gate suite restored full block-by-number transaction count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockTransactionHash"))
         "Devnet smoke gate suite restored full block transaction hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockByNumberTransactionHash"))
         "Devnet smoke gate suite restored full block-by-number transaction hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockTransactionIndex"))
         "Devnet smoke gate suite restored full block transaction index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockByNumberTransactionIndex"))
         "Devnet smoke gate suite restored full block-by-number transaction index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedBalanceCount")
            (devnet-smoke-gate-field report "databaseRpcBalanceCount"))
         "Devnet smoke gate suite restored balance count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedLogCount")
            (devnet-smoke-gate-field report "databaseRpcLogCount"))
         "Devnet smoke gate suite restored log count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedLogFilterCount")
            (devnet-smoke-gate-field report "databaseRpcLogFilterCount"))
         "Devnet smoke gate suite restored log filter count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedLogCount")
            (devnet-smoke-gate-field report "databaseRpcLogFilterLogCount"))
         "Devnet smoke gate suite restored log filter log count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedLogFilterCount")
            (devnet-smoke-gate-field
             report "databaseRpcLogFilterUninstallCount"))
         "Devnet smoke gate suite restored log filter uninstall count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (let ((missing-error-codes
                (devnet-smoke-gate-field
                 report "databaseRpcLogFilterMissingErrorCodes")))
          (devnet-smoke-gate-require
           (= (devnet-smoke-gate-field report "checkedLogFilterCount")
              (length missing-error-codes))
           "Devnet smoke gate suite restored log filter missing error count mismatch for ~A"
           (devnet-smoke-gate-field report "fixtureCase"))
          (devnet-smoke-gate-require
           (every (lambda (code)
                    (= -32602 code))
                  missing-error-codes)
           "Devnet smoke gate suite restored log filter missing error code mismatch for ~A"
           (devnet-smoke-gate-field report "fixtureCase")))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedSimulationCount")
            (devnet-smoke-gate-field report "databaseRpcSimulationCount"))
         "Devnet smoke gate suite restored simulation count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x"
                  (devnet-smoke-gate-field report "databaseRpcCallResult"))
         "Devnet smoke gate suite restored eth_call mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (if (devnet-smoke-gate-executable-code-p
             (devnet-smoke-gate-field report "checkedCode"))
            (devnet-smoke-gate-require
             (string= "eth_call execution failed"
                      (devnet-smoke-gate-field
                       report "databaseRpcFailedCallError"))
             "Devnet smoke gate suite restored failing eth_call mismatch for ~A"
             (devnet-smoke-gate-field report "fixtureCase"))
            (devnet-smoke-gate-require
             (devnet-smoke-gate-false-p
              (devnet-smoke-gate-field report "databaseRpcFailedCallError"))
             "Devnet smoke gate suite unexpected failing eth_call for ~A"
             (devnet-smoke-gate-field report "fixtureCase")))
        (devnet-smoke-gate-require
         (<= 21000
             (hex-to-quantity
              (devnet-smoke-gate-field report "databaseRpcEstimateGas")))
         "Devnet smoke gate suite restored estimateGas mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (stringp (devnet-smoke-gate-field
                   report "databaseRpcAccessListGasUsed"))
         "Devnet smoke gate suite restored access list gasUsed mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorage")
                  (devnet-smoke-gate-field
                   report "databaseRpcPostCallStorage"))
         "Devnet smoke gate suite restored eth_call mutated storage for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByBlockHashAndIndex")
                  (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByBlockNumberAndIndex"))
         "Devnet smoke gate suite restored raw transaction index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByBlockHashAndIndex"))
         "Devnet smoke gate suite restored raw transaction hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockHashAndIndexHash"))
         "Devnet smoke gate suite restored tx by hash/index hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockNumberAndIndexHash"))
         "Devnet smoke gate suite restored tx by number/index hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "databaseRpcBlockHash")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockHashAndIndexBlockHash"))
         "Devnet smoke gate suite restored tx by hash/index block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "databaseRpcBlockHash")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockNumberAndIndexBlockHash"))
         "Devnet smoke gate suite restored tx by number/index block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockHashAndIndexBlockNumber"))
         "Devnet smoke gate suite restored tx by hash/index block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockNumberAndIndexBlockNumber"))
         "Devnet smoke gate suite restored tx by number/index block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockHashAndIndexIndex"))
         "Devnet smoke gate suite restored tx by hash/index index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockNumberAndIndexIndex"))
         "Devnet smoke gate suite restored tx by number/index index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockHash")
                  (devnet-smoke-gate-field report
                                           "databaseRpcSafeBlockHash"))
         "Devnet smoke gate suite restored safe block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcSafeBlockNumber"))
         "Devnet smoke gate suite restored safe block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                  (devnet-smoke-gate-field report
                                           "databaseRpcFinalizedBlockHash"))
         "Devnet smoke gate suite restored finalized block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcFinalizedBlockNumber"))
         "Devnet smoke gate suite restored finalized block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (if state-prune-before
            (devnet-smoke-gate-require
             (devnet-smoke-gate-false-p
              (devnet-smoke-gate-field report "databaseRpcSideBlockHash"))
             "Devnet smoke gate suite unexpectedly ran side reorg for pruned database ~A"
             (devnet-smoke-gate-field report "fixtureCase"))
            (progn
              (devnet-smoke-gate-require
               (string= +payload-status-valid+
                        (devnet-smoke-gate-field
                         report "databaseRpcSideForkchoiceStatus"))
               "Devnet smoke gate suite side forkchoice status mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= "forkchoice safe block is not an ancestor of head"
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRejectedCheckpointError"))
               "Devnet smoke gate suite side rejected checkpoint error mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "blockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideBlockNumber"))
               "Devnet smoke gate suite side block number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcSideBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideLatestBlockHash"))
               "Devnet smoke gate suite side latest hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcSideBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredHeadHash"))
               "Devnet smoke gate suite side restored head hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "blockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredHeadNumber"))
               "Devnet smoke gate suite side restored head number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "blockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcBlockNumber"))
               "Devnet smoke gate suite side fresh public block number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcSideBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcLatestBlockHash"))
               "Devnet smoke gate suite side fresh latest hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredSafeHash"))
               "Devnet smoke gate suite side restored safe hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredSafeNumber"))
               "Devnet smoke gate suite side restored safe number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredFinalizedHash"))
               "Devnet smoke gate suite side restored finalized hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report
                                                 "finalizedBlockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredFinalizedNumber"))
               "Devnet smoke gate suite side restored finalized number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcSafeHash"))
               "Devnet smoke gate suite side restored public safe hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcSafeNumber"))
               "Devnet smoke gate suite side restored public safe number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcFinalizedHash"))
               "Devnet smoke gate suite side restored public finalized hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report
                                                 "finalizedBlockNumber")
                        (devnet-smoke-gate-field
                         report
                         "databaseRpcSideRestoredRpcFinalizedNumber"))
               "Devnet smoke gate suite side restored public finalized number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "checkedCheckpointBalance")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredSafeBalance"))
               "Devnet smoke gate suite side restored safe balance mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "checkedCheckpointBalance")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredFinalizedBalance"))
               "Devnet smoke gate suite side restored finalized balance mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (not (string= (devnet-smoke-gate-field
                              report "databaseRpcBlockHash")
                             (devnet-smoke-gate-field
                              report "databaseRpcSideBlockHash")))
               "Devnet smoke gate suite side block reused child hash for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideChildBlockHash"))
               "Devnet smoke gate suite side reorg lost child block for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideBlockReceiptsCount"))
               "Devnet smoke gate suite side reorg kept canonical receipts for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideLogCount"))
               "Devnet smoke gate suite side reorg kept canonical logs for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (if (not (devnet-smoke-gate-false-p
                        (devnet-smoke-gate-field
                         report "databaseRpcSideTransactionReinserted")))
                  (progn
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               (devnet-smoke-gate-field
                                report "databaseRpcSideTransactionByHash")
                               "hash"))
                     "Devnet smoke gate suite side reorg lost pending transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSideTransactionByHash")
                            "blockHash"))
                     "Devnet smoke gate suite side reorg kept old transaction block hash for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSideTransactionByHash")
                            "blockNumber"))
                     "Devnet smoke gate suite side reorg kept old transaction block number for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSideTransactionByHash")
                            "transactionIndex"))
                     "Devnet smoke gate suite side reorg kept old transaction index for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcRawTransactionByHash")
                              (devnet-smoke-gate-field
                               report "databaseRpcSideRawTransaction"))
                     "Devnet smoke gate suite side reorg lost pending raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               (devnet-smoke-gate-field
                                report "databaseRpcSidePendingTransaction")
                               "hash"))
                     "Devnet smoke gate suite side reorg lost pending transaction pool view for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSidePendingTransaction")
                            "blockHash"))
                     "Devnet smoke gate suite side reorg pending view kept old block hash for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSidePendingTransaction")
                            "blockNumber"))
                     "Devnet smoke gate suite side reorg pending view kept old block number for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSidePendingTransaction")
                            "transactionIndex"))
                     "Devnet smoke gate suite side reorg pending view kept old transaction index for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcRawTransactionByHash")
                              (devnet-smoke-gate-field
                               report "databaseRpcSideRestoredRawTransaction"))
                     "Devnet smoke gate suite side reorg fresh restore lost pending raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               (devnet-smoke-gate-field
                                report "databaseRpcSideRestoredPendingTransaction")
                               "hash"))
                     "Devnet smoke gate suite side reorg fresh restore lost pending transaction view for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report
                             "databaseRpcSideRestoredPendingTransaction")
                            "blockHash"))
                     "Devnet smoke gate suite side reorg fresh pending view kept old block hash for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report
                             "databaseRpcSideRestoredPendingTransaction")
                            "blockNumber"))
                     "Devnet smoke gate suite side reorg fresh pending view kept old block number for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report
                             "databaseRpcSideRestoredPendingTransaction")
                            "transactionIndex"))
                     "Devnet smoke gate suite side reorg fresh pending view kept old transaction index for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (= (devnet-smoke-gate-field
                         report "databaseRpcTransactionCount")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideHiddenReceiptCount"))
                     "Devnet smoke gate suite side hidden receipt count mismatch for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (= (devnet-smoke-gate-field
                         report "databaseRpcTransactionCount")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredHiddenReceiptCount"))
                     "Devnet smoke gate suite side fresh hidden receipt count mismatch for ~A"
                     (devnet-smoke-gate-field report "fixtureCase")))
                  (progn
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideTransactionByHash"))
                     "Devnet smoke gate suite side reorg reinserted wrong-chain transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideRawTransaction"))
                     "Devnet smoke gate suite side reorg exposed wrong-chain raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSidePendingTransaction"))
                     "Devnet smoke gate suite side reorg exposed wrong-chain pending transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredRawTransaction"))
                     "Devnet smoke gate suite side reorg fresh restore exposed wrong-chain raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredPendingTransaction"))
                     "Devnet smoke gate suite side reorg fresh restore exposed wrong-chain pending transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))))
              (devnet-smoke-gate-require
               (devnet-smoke-gate-false-p
                (devnet-smoke-gate-field report "databaseRpcSideReceipt"))
               "Devnet smoke gate suite side reorg kept old receipt canonical for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (devnet-smoke-gate-false-p
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredReceipt"))
               "Devnet smoke gate suite side reorg fresh restore kept old receipt canonical for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredChildBlockHash"))
               "Devnet smoke gate suite side fresh restore lost child block for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= "eth_getBalance block hash is not canonical"
                        (devnet-smoke-gate-field
                         report
                         "databaseRpcSideRestoredChildRequireCanonicalError"))
               "Devnet smoke gate suite side fresh restore child requireCanonical error mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (equal (devnet-smoke-gate-noncanonical-state-error-messages)
                      (devnet-smoke-gate-field
                       report
                       "databaseRpcSideRestoredChildRequireCanonicalErrors"))
               "Devnet smoke gate suite side fresh restore child requireCanonical state errors mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredBlockReceiptsCount"))
               "Devnet smoke gate suite side fresh restore kept canonical receipts for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredLogCount"))
               "Devnet smoke gate suite side fresh restore kept canonical logs for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (let* ((transaction-count
                       (devnet-smoke-gate-field
                        report "databaseRpcTransactionCount"))
                     (extra-transaction-count (max 0 (1- transaction-count)))
                     (side-public-connections
                       (+ 9 extra-transaction-count))
                     (restored-public-connections
                       (+ 20 extra-transaction-count)))
                (devnet-smoke-gate-require
                 (= 3 (devnet-smoke-gate-field
                       report "databaseRpcSideEngineConnections"))
                 "Devnet smoke gate suite side Engine connection count mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (= side-public-connections
                    (devnet-smoke-gate-field
                     report "databaseRpcSidePublicConnections"))
                 "Devnet smoke gate suite side public connection count mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (= restored-public-connections
                    (devnet-smoke-gate-field
                     report "databaseRpcSideRestoredPublicConnections"))
                 "Devnet smoke gate suite side fresh public connection count mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (= (+ 3 side-public-connections restored-public-connections)
                    (devnet-smoke-gate-field
                     report "databaseRpcSideTotalConnections"))
                 "Devnet smoke gate suite side total connection count mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase")))))))
    (devnet-smoke-gate-add-run-metadata
     (list
     (cons "status" "ok")
     (cons "mode" "devnet-listener-boundary-suite")
     (cons "caseCount" (length reports))
     (cons "fixtureCases" case-names)
     (cons "readyFile" (or ready-file :false))
     (cons "readyCaseCount" (if ready-file (length reports) 0))
     (cons "logFile" (or log-file :false))
     (cons "logCaseCount" (if log-file (length reports) 0))
     (cons "pidFile" (or pid-file :false))
     (cons "pidCaseCount" (if pid-file (length reports) 0))
     (cons "databaseFile" (or database-file :false))
     (cons "databasePruneStateBefore" (or state-prune-before :false))
     (cons "databaseCaseCount" (if database-file (length reports) 0))
     (cons "databasePrunedStateCaseCount" pruned-state-case-count)
     (cons "databaseRpcPrunedStateErrorCaseCount"
           pruned-state-error-case-count)
     (cons "engineConnections" engine-connections)
     (cons "publicConnections" public-connections)
     (cons "totalConnections" (+ engine-connections public-connections))
     (cons "connectionContract"
           (devnet-smoke-gate-connection-contract (length reports)))
     (cons "cases" reports)))))

(defun devnet-smoke-gate-suite-report-p (report)
  (string= "devnet-listener-boundary-suite"
           (or (devnet-smoke-gate-field report "mode") "")))

(defun devnet-smoke-gate-engine-only-report-p (report)
  (string= "devnet-engine-only-serve"
           (or (devnet-smoke-gate-field report "mode") "")))

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

