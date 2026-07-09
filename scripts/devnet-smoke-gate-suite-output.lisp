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

