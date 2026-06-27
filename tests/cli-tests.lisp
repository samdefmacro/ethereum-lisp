(in-package #:ethereum-lisp.test)

(defconstant +devnet-cli-genesis-fixture+
  "tests/fixtures/execution-spec-tests/phase-a-shanghai-genesis.json")

(defconstant +devnet-cli-jwt-secret+
  "1111111111111111111111111111111111111111111111111111111111111111")

(defparameter +devnet-side-reorg-smoke-case-names+
  '("shanghai-one-transfer-with-withdrawal"
    "shanghai-two-legacy-transfers-with-withdrawal"
    "shanghai-log-contract-call-with-withdrawal"))

(defvar *devnet-cli-temp-counter* 0)

(defun devnet-cli-current-process-id ()
  #+sbcl
  (sb-unix:unix-getpid)
  #-sbcl
  nil)

(defun devnet-cli-current-process-id-string ()
  (let ((process-id (devnet-cli-current-process-id)))
    (if process-id
        (write-to-string process-id)
        "")))

(defun devnet-cli-temp-token ()
  (format nil "~A-~D-~A"
          (or (devnet-cli-current-process-id) "nopid")
          (incf *devnet-cli-temp-counter*)
          (gensym)))

(defun devnet-cli-temp-path (name type)
  (merge-pathnames
   (make-pathname :name (format nil "~A-~A" name (devnet-cli-temp-token))
                  :type type)
   #P"/private/tmp/"))

(defun devnet-cli-write-temp-file (path contents)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string contents stream)))

(defun devnet-cli-file-string (path)
  (with-open-file (stream path :direction :input)
    (let ((string (make-string (file-length stream))))
      (read-sequence string stream)
      string)))

(defun devnet-cli-pid-file-process-id (path)
  (parse-integer
   (string-trim '(#\Space #\Tab #\Newline #\Return)
                (devnet-cli-file-string path))
   :junk-allowed nil))

(defun devnet-cli-file-forms (path)
  (with-open-file (stream path :direction :input)
    (loop for form = (read stream nil :eof)
          until (eq form :eof)
          collect form)))

(defun devnet-cli-temp-directory (name)
  (let ((path
          (merge-pathnames
           (format nil "~A-~A/" name (devnet-cli-temp-token))
           #P"/private/tmp/")))
    (ensure-directories-exist path)
    path))

(defun devnet-cli-restored-public-connections (report)
  (+ 24
     (1- (fixture-object-field report "checkedBalanceCount"))
     (* 7 (1- (fixture-object-field report "transactionCount")))
     (* 2 (fixture-object-field report "checkedLogCount"))
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

(defun devnet-cli-assert-txpool-subpool-persistence (report)
  (is (string= "0x1"
               (fixture-object-field report "txpoolStatusPending")))
  (is (string= "0x2"
               (fixture-object-field report "txpoolStatusQueued")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field report "databaseRpcTxpoolPendingHash")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionRaw")
               (fixture-object-field report "databaseRpcTxpoolRawTransaction")))
  (is (string= (fixture-object-field report "txpoolPendingSender")
               (fixture-object-field report "databaseRpcTxpoolSender")))
  (is (string= (fixture-object-field report "txpoolPendingNonce")
               (fixture-object-field report "databaseRpcTxpoolNonce")))
  (is (string= (fixture-object-field report "txpoolPendingInspectSummary")
               (fixture-object-field
                report "databaseRpcTxpoolInspectSummary")))
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
  (is (string= "0x1"
               (fixture-object-field report "databaseRpcTxpoolStatusPending")))
  (is (string= "0x2"
               (fixture-object-field report "databaseRpcTxpoolStatusQueued")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field report "databaseRpcTxpoolContentHash")))
  (is (string= (fixture-object-field report "txpoolPendingTransactionHash")
               (fixture-object-field
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
  (is (= 8
         (fixture-object-field report "databaseRpcTxpoolPublicConnections"))))

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

(defun devnet-cli-engine-fixture-payload-number (case-name)
  (let* ((case (select-engine-newpayload-v2-fixture-case
                +engine-newpayload-v2-fixture-path+
                case-name))
         (payload (fixture-object-field case "payload")))
    (fixture-object-field payload "number")))

(defun devnet-cli-http-body (response)
  (let ((boundary (search (format nil "~C~C~C~C"
                                  #\Return #\Newline
                                  #\Return #\Newline)
                          response)))
    (subseq response (+ boundary 4))))

(defun devnet-cli-http-status (response)
  (let* ((line-end (position #\Return response))
         (status-line (subseq response 0 line-end)))
    (parse-integer status-line :start 9 :end 12)))

(defun devnet-cli-json-rpc-http-request (body &key token)
  (with-output-to-string (stream)
    (format stream "POST / HTTP/1.1~%Host: localhost~%")
    (format stream "Content-Type: application/json~%")
    (when token
      (format stream "Authorization: Bearer ~A~%" token))
    (format stream "Content-Length: ~D~%~%~A" (length body) body)))

(defun devnet-cli-set-node-store-config (node store config)
  (setf (ethereum-lisp.cli:devnet-node-store node) store
        (ethereum-lisp.cli:devnet-node-config node) config
        (engine-rpc-http-service-store
         (ethereum-lisp.cli:devnet-node-service node))
        store
        (engine-rpc-http-service-config
         (ethereum-lisp.cli:devnet-node-service node))
        config
        (engine-rpc-http-service-store
         (ethereum-lisp.cli:devnet-node-public-service node))
        store
        (engine-rpc-http-service-config
         (ethereum-lisp.cli:devnet-node-public-service node))
        config)
  node)

(defun devnet-cli-engine-forkchoice-v2-request
    (id head &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (let ((request (engine-fixture-forkchoice-request
                  id head :safe safe :finalized finalized)))
    (setf (cdr (assoc "method" request :test #'string=))
          "engine_forkchoiceUpdatedV2")
    request))

(defun make-devnet-cli-one-shot-listener (endpoint)
  (let ((accepted-p nil))
    (make-engine-rpc-http-listener
     :endpoint endpoint
     :accept-function
     (lambda ()
       (unless accepted-p
         (setf accepted-p t)
         (make-engine-rpc-http-connection
          :input-stream
          (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
          :output-stream (make-string-output-stream)
          :close-function (lambda () nil))))
     :close-function (lambda () nil))))

(deftest devnet-node-loads-genesis-summary
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 0))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (head (ethereum-lisp.cli:devnet-node-genesis-block node))
         (head-hash (block-hash head))
         (funded (address-from-hex "0x0000000000000000000000000000000000001001")))
    (is (= 1337 (getf summary :chain-id)))
    (is (= 0 (getf summary :head-number)))
    (is (string= "127.0.0.1:0" (getf summary :engine-endpoint)))
    (is (string= "127.0.0.1:8545" (getf summary :rpc-endpoint)))
    (is (equal (devnet-cli-current-process-id) (getf summary :process-id)))
    (is (string= (hash32-to-hex head-hash) (getf summary :head-hash)))
    (is (null (getf summary :safe-number)))
    (is (null (getf summary :safe-hash)))
    (is (null (getf summary :finalized-number)))
    (is (null (getf summary :finalized-hash)))
    (is (getf summary :state-available-p))
    (is (not (getf summary :auth-required-p)))
    (is (not (getf summary :jwt-secret-path)))
    (is (funcall (engine-rpc-http-service-allowed-method-p
                  (ethereum-lisp.cli:devnet-node-service node))
                 "engine_exchangeCapabilities"))
    (is (not (funcall (engine-rpc-http-service-allowed-method-p
                       (ethereum-lisp.cli:devnet-node-service node))
                      "eth_chainId")))
    (is (funcall (engine-rpc-http-service-allowed-method-p
                  (ethereum-lisp.cli:devnet-node-public-service node))
                 "eth_chainId"))
    (is (not (funcall (engine-rpc-http-service-allowed-method-p
                       (ethereum-lisp.cli:devnet-node-public-service node))
                      "engine_exchangeCapabilities")))
    (is (= #xde0b6b3a7640000
           (chain-store-account-balance store head-hash funded)))))

(deftest devnet-node-splits-engine-and-public-rpc-methods
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-service (ethereum-lisp.cli:devnet-node-service node))
         (public-service (ethereum-lisp.cli:devnet-node-public-service node))
         (engine-store (engine-rpc-http-service-store engine-service))
         (engine-config (engine-rpc-http-service-config engine-service))
         (public-filter (engine-rpc-http-service-allowed-method-p
                         public-service))
         (engine-filter (engine-rpc-http-service-allowed-method-p
                         engine-service)))
    (let ((engine-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}"
              engine-store
              engine-config
              :allowed-method-p engine-filter)))
          (public-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}"
              engine-store
              engine-config
              :allowed-method-p public-filter)))
          (chain-id-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"eth_chainId\",\"params\":[]}"
              engine-store
              engine-config
              :allowed-method-p public-filter))))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field engine-response "error")
              "code")))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field public-response "error")
              "code")))
      (is (string= "0x539"
                   (fixture-object-field chain-id-response "result"))))))

(deftest devnet-node-start-serves-engine-and-public-listeners
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-accepted-p nil)
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "engine"
             :accept-function
             (lambda ()
               (unless engine-accepted-p
                 (setf engine-accepted-p t)
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
                  :output-stream (make-string-output-stream)
                  :close-function (lambda () nil))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "public"
             :accept-function
             (lambda ()
               (loop until engine-accepted-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
                :output-stream (make-string-output-stream)
                :close-function (lambda () nil)))
             :close-function (lambda () nil))
            :max-connections 1)))
    (is (= 1 (getf summary :engine-connections)))
    (is (= 1 (getf summary :public-connections)))
    (is (= 2 (getf summary :total-connections)))))

(deftest devnet-node-split-listeners-serve-authenticated-engine-and-public-rpc
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 8551
                         :public-port 8545
                         :jwt-secret-path (namestring jwt-path)))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (engine-body
                    (concatenate
                     'string
                     "{\"jsonrpc\":\"2.0\",\"id\":11,"
                     "\"method\":\"engine_getClientVersionV1\","
                     "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
                     "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
                  (public-body
                    "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"eth_chainId\",\"params\":[]}")
                  (engine-output (make-string-output-stream))
                  (public-output (make-string-output-stream))
                  (engine-accepted-p nil)
                  (engine-closed-p nil)
                  (public-closed-p nil)
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "engine"
                      :accept-function
                      (lambda ()
                        (unless engine-accepted-p
                          (setf engine-accepted-p t)
                          (make-engine-rpc-http-connection
                           :input-stream
                           (make-string-input-stream
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token))
                           :output-stream engine-output
                           :close-function
                           (lambda () (setf engine-closed-p t)))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "public"
                      :accept-function
                      (lambda ()
                        (loop until engine-accepted-p
                              do (sleep 0.001))
                        (make-engine-rpc-http-connection
                         :input-stream
                         (make-string-input-stream
                          (devnet-cli-json-rpc-http-request public-body))
                         :output-stream public-output
                         :close-function
                         (lambda () (setf public-closed-p t))))
                      :close-function (lambda () nil))
                     :max-connections 1)))
             (is (= 1 (getf summary :engine-connections)))
             (is (= 1 (getf summary :public-connections)))
             (is (= 2 (getf summary :total-connections)))
             (is engine-closed-p)
             (is public-closed-p)
             (let* ((engine-response (get-output-stream-string engine-output))
                    (public-response (get-output-stream-string public-output))
                    (engine-rpc (parse-json
                                 (devnet-cli-http-body engine-response)))
                    (public-rpc (parse-json
                                 (devnet-cli-http-body public-response)))
                    (local-client
                      (first (fixture-object-field engine-rpc "result"))))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status public-response)))
               (is (= 11 (fixture-object-field engine-rpc "id")))
               (is (string= "ethereum-lisp"
                            (fixture-object-field local-client "name")))
               (is (= 12 (fixture-object-field public-rpc "id")))
               (is (string= "0x539"
                            (fixture-object-field public-rpc "result"))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path)))))

(deftest devnet-node-split-listeners-import-payload-and-serve-public-state
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((case
                    (select-engine-newpayload-v2-fixture-case
                     +engine-newpayload-v2-fixture-path+
                     "shanghai-one-transfer-with-withdrawal"))
                  (node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 8551
                         :public-port 8545
                         :jwt-secret-path (namestring jwt-path)))
                  (store (make-engine-payload-memory-store))
                  (config (engine-fixture-chain-config case))
                  (parent (fixture-object-field case "parent"))
                  (payload-case (fixture-object-field case "payload"))
                  (expect (fixture-object-field case "expect"))
                  (parent-state (engine-fixture-parent-state parent))
                  (fee-recipient (fixture-address-field parent "feeRecipient"))
                  (transactions
                    (mapcar (lambda (raw)
                              (transaction-from-encoding (hex-to-bytes raw)))
                            (fixture-object-field payload-case
                                                  "transactions")))
                  (withdrawals
                    (mapcar #'engine-fixture-withdrawal
                            (fixture-object-field payload-case
                                                  "withdrawals")))
                  (parent-header
                    (make-block-header
                     :parent-hash (zero-hash32)
                     :beneficiary fee-recipient
                     :state-root (state-db-root parent-state)
                     :mix-hash (zero-hash32)
                     :number (fixture-quantity-field parent "number")
                     :gas-limit (fixture-quantity-field parent "gasLimit")
                     :gas-used (fixture-quantity-field parent "gasUsed")
                     :timestamp (fixture-quantity-field parent "timestamp")
                     :base-fee-per-gas
                     (fixture-quantity-field parent "baseFeePerGas")
                     :withdrawals-root (withdrawal-list-root '())))
                  (parent-block (make-block :header parent-header))
                  (child-state (state-db-copy parent-state))
                  (child-header
                    (make-block-header
                     :parent-hash (block-hash parent-block)
                     :beneficiary fee-recipient
                     :mix-hash (zero-hash32)
                     :number (fixture-quantity-field payload-case "number")
                     :gas-limit (fixture-quantity-field payload-case
                                                        "gasLimit")
                     :gas-used 0
                     :timestamp (fixture-quantity-field payload-case
                                                        "timestamp")
                     :base-fee-per-gas
                     (fixture-quantity-field payload-case "baseFeePerGas")))
                  (child-block
                    (execute-signed-block
                     child-state
                     transactions
                     :expected-chain-id (chain-config-chain-id config)
                     :header child-header
                     :chain-config config
                     :withdrawals withdrawals))
                  (payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data child-block)))
                  (recipient (fixture-address-field expect "recipient"))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (new-payload-output (make-string-output-stream))
                  (forkchoice-output (make-string-output-stream))
                  (block-number-output (make-string-output-stream))
                  (balance-output (make-string-output-stream))
                  (engine-requests
                    (list
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 21 payload))
                      new-payload-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        22 (block-hash child-block)
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                     forkchoice-output)))
                  (public-requests
                    (list
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 31)
                             (cons "method" "eth_blockNumber")
                             (cons "params" '())))
                      block-number-output)
                     (cons
                      (json-encode
                       (engine-fixture-balance-request 32 recipient))
                      balance-output)))
                  (engine-served-count 0)
                  (engine-done-p nil)
                  (public-served-count 0))
             (devnet-cli-set-node-store-config node store config)
             (engine-payload-store-put-block
              store parent-block :state-available-p t)
             (commit-state-db-to-chain-store
              store (block-hash parent-block) parent-state)
             (let ((summary
                     (ethereum-lisp.cli:start-devnet-node-listeners
                      node
                      (make-engine-rpc-http-listener
                       :endpoint "engine"
                       :accept-function
                       (lambda ()
                         (when engine-requests
                           (destructuring-bind (body . output)
                               (pop engine-requests)
                             (make-engine-rpc-http-connection
                              :input-stream
                              (make-string-input-stream
                               (devnet-cli-json-rpc-http-request
                                body :token token))
                              :output-stream output
                              :close-function
                              (lambda ()
                                (incf engine-served-count)
                                (when (= engine-served-count 2)
                                  (setf engine-done-p t)))))))
                       :close-function (lambda () nil))
                      (make-engine-rpc-http-listener
                       :endpoint "public"
                       :accept-function
                       (lambda ()
                         (loop until engine-done-p
                               do (sleep 0.001))
                         (when public-requests
                           (destructuring-bind (body . output)
                               (pop public-requests)
                             (make-engine-rpc-http-connection
                              :input-stream
                              (make-string-input-stream
                               (devnet-cli-json-rpc-http-request body))
                              :output-stream output
                              :close-function
                              (lambda () (incf public-served-count))))))
                       :close-function (lambda () nil))
                      :max-connections 2)))
               (is (= 2 (getf summary :engine-connections)))
               (is (= 2 (getf summary :public-connections)))
               (is (= 4 (getf summary :total-connections)))
               (is (= 2 engine-served-count))
               (is (= 2 public-served-count))
               (let* ((new-payload-response
                        (get-output-stream-string new-payload-output))
                      (forkchoice-response
                        (get-output-stream-string forkchoice-output))
                      (block-number-response
                        (get-output-stream-string block-number-output))
                      (balance-response
                        (get-output-stream-string balance-output))
                      (new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus")))
                 (is (= 200 (devnet-cli-http-status new-payload-response)))
                 (is (= 200 (devnet-cli-http-status forkchoice-response)))
                 (is (= 200 (devnet-cli-http-status block-number-response)))
                 (is (= 200 (devnet-cli-http-status balance-response)))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc
                                                    "result")))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path)))))

(deftest devnet-node-start-closes-engine-listener-on-public-error
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function
            (lambda ()
              (loop until engine-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function (lambda () (error "public listener failed"))
            :close-function (lambda () nil))))
    (signals error
      (ethereum-lisp.cli:start-devnet-node-listeners
       node
       engine-listener
       public-listener
       :max-connections 1))
    (is engine-closed-p)))

(deftest devnet-shutdown-controller-stops-split-listeners
  #-sbcl
  (skip-test "Devnet split listener shutdown requires SBCL threads")
  #+sbcl
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (controller
           (ethereum-lisp.cli:make-devnet-shutdown-controller))
         (engine-accepting-p nil)
         (public-accepting-p nil)
         (engine-closed-p nil)
         (public-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function
            (lambda ()
              (setf engine-accepting-p t)
              (loop until engine-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function
            (lambda ()
              (setf public-accepting-p t)
              (loop until public-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf public-closed-p t))))
         (summary nil))
    (let ((serve-thread
            (sb-thread:make-thread
             (lambda ()
               (setf summary
                     (ethereum-lisp.cli:start-devnet-node-listeners
                      node
                      engine-listener
                      public-listener
                      :shutdown-controller controller)))
             :name "ethereum-lisp-devnet-shutdown-test")))
      (loop repeat 1000
            until (and engine-accepting-p public-accepting-p)
            do (sleep 0.001))
      (is engine-accepting-p)
      (is public-accepting-p)
      (is (not (ethereum-lisp.cli:devnet-shutdown-requested-p controller)))
      (is (ethereum-lisp.cli:devnet-shutdown-request controller))
      (sb-thread:join-thread serve-thread)
      (is (ethereum-lisp.cli:devnet-shutdown-requested-p controller))
      (is engine-closed-p)
      (is public-closed-p)
      (is (= 0 (getf summary :engine-connections)))
      (is (= 0 (getf summary :public-connections)))
      (is (= 0 (getf summary :total-connections))))))

(deftest devnet-listener-ready-callback-reports-bound-endpoints
  #-sbcl
  (skip-test "Devnet split listener serving requires SBCL threads")
  #+sbcl
  (let* ((ready-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-bound-ready" "json"))
         (sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 0
                :public-port 0
                :telemetry-sink sink))
         (callback-called-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "127.0.0.1:18551"
            :accept-function (lambda () nil)
            :close-function (lambda () nil)))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "127.0.0.1:18545"
            :accept-function (lambda () nil)
            :close-function (lambda () nil))))
    (unwind-protect
         (let ((summary
                 (ethereum-lisp.cli:start-devnet-node-listeners
                  node
                  engine-listener
                  public-listener
                  :max-connections 0
                  :on-listeners-ready
                  (lambda (engine public)
                    (setf callback-called-p t)
                    (ethereum-lisp.cli::devnet-cli-write-ready-file
                     node
                     ready-path
                     :engine-endpoint
                     (engine-rpc-http-listener-endpoint engine)
                     :rpc-endpoint
                     (engine-rpc-http-listener-endpoint public))
                    (ethereum-lisp.cli::devnet-cli-log-event
                     node
                     "devnet.ready"
                     :engine-endpoint
                     (engine-rpc-http-listener-endpoint engine)
                     :rpc-endpoint
                     (engine-rpc-http-listener-endpoint public))))))
           (is callback-called-p)
           (is (= 0 (getf summary :engine-connections)))
           (is (= 0 (getf summary :public-connections)))
           (ethereum-lisp.cli::devnet-cli-log-event
            node
            "devnet.shutdown"
            :engine-endpoint
            (engine-rpc-http-listener-endpoint engine-listener)
            :rpc-endpoint
            (engine-rpc-http-listener-endpoint public-listener)
            :connection-summary summary)
           (let ((ready-summary
                   (parse-json (devnet-cli-file-string ready-path))))
             (is (string= "127.0.0.1:18551"
                          (fixture-object-field ready-summary
                                                "engineEndpoint")))
             (is (string= "127.0.0.1:18545"
                          (fixture-object-field ready-summary
                                                "rpcEndpoint")))
             (is (equal (devnet-cli-current-process-id)
                        (fixture-object-field ready-summary
                                              "processId"))))
           (let ((events
                   (remove-if-not
                    (lambda (event)
                      (member
                       (ethereum-lisp.telemetry:telemetry-event-name event)
                       '("devnet.ready" "devnet.shutdown")
                       :test #'string=))
                    (ethereum-lisp.telemetry:telemetry-events sink))))
             (is (= 2 (length events)))
             (dolist (event events)
               (let ((fields
                       (ethereum-lisp.telemetry:telemetry-event-fields
                        event)))
                 (is (string= "127.0.0.1:18551"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "127.0.0.1:18545"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))
                 (is (string= (if (string= "devnet.ready"
                                            (ethereum-lisp.telemetry:telemetry-event-name
                                             event))
                                   "ready"
                                   "shutdown")
                              (cdr (assoc "lifecyclePhase" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "engineConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "publicConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "totalConnections" fields
                                          :test #'string=))))
                 (is (string= (devnet-cli-current-process-id-string)
                              (cdr (assoc "processId" fields
                                          :test #'string=))))))))
      (when (probe-file ready-path)
        (delete-file ready-path)))))

(deftest devnet-node-loads-jwt-secret-file
  (let ((path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            path
            (format nil "0x~A~%" +devnet-cli-jwt-secret+))
           (let* ((node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 0
                         :jwt-secret-path (namestring path)))
                  (summary (ethereum-lisp.cli:devnet-node-summary node))
                  (service (ethereum-lisp.cli:devnet-node-service node)))
             (is (getf summary :auth-required-p))
             (is (string= (namestring path)
                          (getf summary :jwt-secret-path)))
             (is (= 32 (length (engine-rpc-http-service-jwt-secret service))))))
      (when (probe-file path)
        (delete-file path)))))

(deftest devnet-cli-main-no-serve-prints-summary
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--port" "0"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (read-from-string (get-output-stream-string output))))
      (is (= 1337 (getf summary :chain-id)))
      (is (= 0 (getf summary :head-number)))
      (is (string= "127.0.0.1:8545" (getf summary :rpc-endpoint)))
      (is (getf summary :state-available-p)))))

(deftest devnet-cli-main-database-restores-and-exports-chain-store
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-chain" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (genesis
                    (ethereum-lisp.cli:devnet-node-genesis-block seed-node))
                  (funded
                    (address-from-hex
                     "0x0000000000000000000000000000000000001001"))
                  (child
                    (make-block
                     :header
                     (make-block-header
                      :number 1
                      :parent-hash (block-hash genesis)
                      :timestamp 1
                      :gas-limit 30000000))))
             (let ((state (make-state-db)))
               (state-db-set-account
                state funded (make-state-account :balance 42))
               (setf (block-header-state-root (block-header child))
                     (state-db-root state)))
             (chain-store-put-block seed-store child :state-available-p t)
             (chain-store-put-account-balance
              seed-store (block-hash child) funded 42)
             (chain-store-set-canonical-head seed-store (block-hash child))
             (chain-store-export-to-kv
              seed-store
              (make-file-key-value-database database-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--database" (namestring database-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary
                    (parse-json (get-output-stream-string output)))
                  (database
                    (make-file-key-value-database database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (head
                    (chain-store-latest-block restored-store))
                  (funded
                    (address-from-hex
                     "0x0000000000000000000000000000000000001001")))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (= 1 (fixture-object-field summary "headNumber")))
             (is (string= (namestring database-path)
                          (fixture-object-field summary "databasePath")))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries
                               database :canonical-hash))))
             (is (= 1 (block-header-number (block-header head))))
             (is (chain-store-state-available-p restored-store
                                                (block-hash head)))
             (is (= 42
                    (chain-store-account-balance
                     restored-store (block-hash head) funded)))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-treats-empty-database-as-new-chain
  (labels ((write-empty-kv-database (path)
             (with-open-file (stream path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (let ((*print-readably* t)
                     (*print-pretty* nil))
                 (write '(:ethereum-lisp-kv-v1 nil) :stream stream)
                 (terpri stream)))))
    (dolist (mode '(:empty-file :empty-kv))
      (let ((database-path
              (devnet-cli-temp-path "ethereum-lisp-devnet-empty-chain"
                                     "sexp"))
            (output (make-string-output-stream))
            (errors (make-string-output-stream)))
        (unwind-protect
             (progn
               (ecase mode
                 (:empty-file
                  (devnet-cli-write-temp-file database-path ""))
                 (:empty-kv
                  (write-empty-kv-database database-path)))
               (is (= 0
                      (ethereum-lisp.cli:main
                       (list "devnet"
                             "--genesis" +devnet-cli-genesis-fixture+
                             "--port" "0"
                             "--database" (namestring database-path)
                             "--json"
                             "--no-serve")
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string errors)))
               (let* ((summary
                        (parse-json (get-output-stream-string output)))
                      (database (make-file-key-value-database database-path))
                      (restored-node
                        (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 0
                         :database-path (namestring database-path)))
                      (restored-store
                        (ethereum-lisp.cli:devnet-node-store restored-node))
                      (head (chain-store-latest-block restored-store)))
                 (is (= 1337 (fixture-object-field summary "chainId")))
                 (is (= 0 (fixture-object-field summary "headNumber")))
                 (is (eq t (fixture-object-field summary "stateAvailable")))
                 (is (< 0 (length (kv-chain-record-entries database :block))))
                 (is (< 0 (length (kv-chain-record-entries
                                   database :canonical-hash))))
                 (is (< 0 (length (kv-chain-record-entries database :state))))
                 (is (= 0 (block-header-number (block-header head))))
                 (is (chain-store-state-available-p restored-store
                                                    (block-hash head)))))
          (when (probe-file database-path)
            (delete-file database-path)))))))

(deftest devnet-cli-main-rejects-database-genesis-mismatch
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-mismatched-chain"
                                "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (state (make-state-db))
                  (mismatched-genesis
                    (make-block
                     :header
                     (make-block-header
                      :number 0
                      :timestamp 99
                      :gas-limit 30000000
                      :state-root (state-db-root state)))))
             (chain-store-put-block seed-store
                                    mismatched-genesis
                                    :state-available-p t)
             (commit-state-db-to-chain-store
              seed-store (block-hash mismatched-genesis) state)
             (chain-store-set-canonical-head seed-store
                                             (block-hash mismatched-genesis))
             (chain-store-export-to-kv
              seed-store
              (make-file-key-value-database database-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--database" (namestring database-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "Devnet database genesis does not match genesis file"
                       (get-output-stream-string errors))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-prunes-state-before-database-export
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-pruned-chain" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (let* ((seed-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :port 0))
                (seed-store
                  (ethereum-lisp.cli:devnet-node-store seed-node))
                (genesis
                  (ethereum-lisp.cli:devnet-node-genesis-block seed-node))
                (funded
                  (address-from-hex
                   "0x0000000000000000000000000000000000001001"))
                (child
                  (make-block
                   :header
                   (make-block-header
                    :number 1
                    :parent-hash (block-hash genesis)
                    :timestamp 1
                    :gas-limit 30000000)))
                (genesis-id (hash32-bytes (block-hash genesis)))
                child-id)
           (let ((state (make-state-db)))
             (state-db-set-account
              state funded (make-state-account :balance 42))
             (setf (block-header-state-root (block-header child))
                   (state-db-root state)
                   child-id (hash32-bytes (block-hash child))))
           (chain-store-put-block seed-store child :state-available-p t)
           (chain-store-put-account-balance
            seed-store (block-hash child) funded 42)
           (chain-store-set-canonical-head seed-store (block-hash child))
           (chain-store-export-to-kv
            seed-store
            (make-file-key-value-database database-path))
           (let ((database (make-file-key-value-database database-path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state genesis-id)
               (declare (ignore value))
               (is present-p)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--database" (namestring database-path)
                         "--prune-state-before" "2"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary (parse-json (get-output-stream-string output)))
                  (database (make-file-key-value-database database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node)))
             (is (= 1 (fixture-object-field summary "headNumber")))
             (is (eq t (fixture-object-field summary "stateAvailable")))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state genesis-id :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state child-id)
               (declare (ignore value))
               (is present-p))
             (is (chain-store-known-block restored-store (block-hash genesis)))
             (is (not (chain-store-state-available-p
                       restored-store (block-hash genesis))))
             (is (chain-store-state-available-p
                  restored-store (block-hash child)))
             (is (= 42
                    (chain-store-account-balance
                     restored-store (block-hash child) funded)))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-json-summary-and-ready-file
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex"))
        (ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (pid-path (devnet-cli-temp-path "ethereum-lisp-devnet" "pid"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file ready-path "stale readiness")
           (devnet-cli-write-temp-file pid-path "0")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--public-port" "8546"
                         "--jwt-secret" (namestring jwt-path)
                         "--ready-file" (namestring ready-path)
                         "--pid-file" (namestring pid-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path))))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (= 1337 (fixture-object-field summary "chainId")))
               (is (= 0 (fixture-object-field summary "headNumber")))
               (is (null (fixture-object-field summary "safeNumber")))
               (is (null (fixture-object-field summary "safeHash")))
               (is (null (fixture-object-field summary "finalizedNumber")))
               (is (null (fixture-object-field summary "finalizedHash")))
               (is (string= "127.0.0.1:0"
                            (fixture-object-field summary "engineEndpoint")))
               (is (string= "127.0.0.1:8546"
                            (fixture-object-field summary "rpcEndpoint")))
               (is (equal (devnet-cli-current-process-id)
                          (fixture-object-field summary "processId")))
               (is (string= (namestring pid-path)
                            (fixture-object-field summary "pidFilePath")))
               (is (eq t (fixture-object-field summary "authRequired")))
               (is (eq t (fixture-object-field summary "stateAvailable")))
               (is (string= (namestring jwt-path)
                            (fixture-object-field summary "jwtSecretPath"))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-accepts-explicit-engine-endpoint-options
  (let ((ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-host" "192.0.2.10"
                         "--engine-port" "9551"
                         "--public-host" "192.0.2.11"
                         "--public-port" "9545"
                         "--ready-file" (namestring ready-path)
                         "--log-file" (namestring log-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= "192.0.2.10:9551"
                            (fixture-object-field summary "engineEndpoint")))
               (is (string= "192.0.2.11:9545"
                            (fixture-object-field summary "rpcEndpoint"))))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (string= "192.0.2.10:9551"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "192.0.2.11:9545"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest devnet-cli-main-engine-host-does-not-rewrite-public-default
  (let ((engine-output (make-string-output-stream))
        (engine-errors (make-string-output-stream))
        (host-output (make-string-output-stream))
        (host-errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--engine-host" "192.0.2.10"
                  "--engine-port" "9551"
                  "--json"
                  "--no-serve")
            :output-stream engine-output
            :error-stream engine-errors)))
    (is (string= "" (get-output-stream-string engine-errors)))
    (let ((summary (parse-json (get-output-stream-string engine-output))))
      (is (string= "192.0.2.10:9551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint"))))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--host" "192.0.2.20"
                  "--port" "9552"
                  "--json"
                  "--no-serve")
            :output-stream host-output
            :error-stream host-errors)))
    (is (string= "" (get-output-stream-string host-errors)))
    (let ((summary (parse-json (get-output-stream-string host-output))))
      (is (string= "192.0.2.20:9552"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "192.0.2.20:8545"
                   (fixture-object-field summary "rpcEndpoint"))))))

(deftest devnet-cli-main-log-file-records-ready-event
  (let ((ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (pid-path (devnet-cli-temp-path "ethereum-lisp-devnet" "pid"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let ((log-path-string (namestring log-path)))
             (is (= 0
                    (ethereum-lisp.cli:main
                     (list "devnet"
                           "--genesis" +devnet-cli-genesis-fixture+
                           "--port" "0"
                           "--public-port" "8546"
                           "--ready-file" (namestring ready-path)
                           "--log-file" log-path-string
                           "--pid-file" (namestring pid-path)
                           "--json"
                           "--no-serve")
                     :output-stream output
                     :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path))
                  (log-names
                    (mapcar (lambda (record) (getf record :name))
                            log-records)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= log-path-string
                            (fixture-object-field summary "logPath"))))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (is (member "devnet.ready" log-names :test #'string=))
             (is (member "devnet.shutdown" log-names :test #'string=))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (eq :log (getf log-record :kind)))
                 (is (eq :info (getf log-record :value)))
                 (is (string= "127.0.0.1:0"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "127.0.0.1:8546"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))
                 (is (string= (if (string= "devnet.ready"
                                            (getf log-record :name))
                                   "ready"
                                   "shutdown")
                              (cdr (assoc "lifecyclePhase" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "engineConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "publicConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "totalConnections" fields
                                          :test #'string=))))
                 (is (string= (devnet-cli-current-process-id-string)
                              (cdr (assoc "processId" fields
                                          :test #'string=))))
                 (is (string= "0x539"
                              (cdr (assoc "chainId" fields :test #'string=))))
                 (is (string= "0x0"
                              (cdr (assoc "headNumber" fields
                                          :test #'string=))))
                 (is (stringp
                      (cdr (assoc "headHash" fields :test #'string=))))
                 (is (string= "true"
                              (cdr (assoc "stateAvailable" fields
                                          :test #'string=))))
                 (is (string= log-path-string
                              (cdr (assoc "logPath" fields
                                          :test #'string=))))
                 (is (string= (namestring pid-path)
                              (cdr (assoc "pidFilePath" fields
                                          :test #'string=)))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-log-file-records-error-event
  (let ((log-path (devnet-cli-temp-path "ethereum-lisp-devnet-error" "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (let ((log-path-string (namestring log-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--log-file" log-path-string
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "--genesis is required"
                       (get-output-stream-string errors)))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= "devnet.error" (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (string= (devnet-cli-current-process-id-string)
                          (cdr (assoc "processId" fields :test #'string=))))
             (is (search "--genesis is required"
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= log-path-string
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

(defun phase-a-smoke-gate-reference-client
    (reference-clients name)
  (find name reference-clients
        :key (lambda (client)
               (fixture-object-field client "name"))
        :test #'string=))

(defun phase-a-smoke-gate-reference-commit-p (commit)
  (and (stringp commit)
       (= 40 (length commit))
       (every (lambda (char)
                (or (and (char<= #\0 char) (char<= char #\9))
                    (and (char<= #\a char) (char<= char #\f))))
              commit)))

(defun phase-a-smoke-gate-assert-reference-client (reference-clients name)
  (let* ((client
           (phase-a-smoke-gate-reference-client reference-clients name))
         (status (and client
                      (fixture-object-field client "status")))
         (commit (and client
                      (fixture-object-field client "commit"))))
    (is client)
    (is (member status '("ok" "missing" "unavailable") :test #'string=))
    (if (string= "ok" status)
        (is (phase-a-smoke-gate-reference-commit-p commit))
        (is (null commit)))))

(defun phase-a-smoke-gate-assert-reference-client-path
    (reference-clients name expected-path)
  (let ((client
          (phase-a-smoke-gate-reference-client reference-clients name)))
    (is client)
    (is (string= expected-path
                 (fixture-object-field client "path")))))

(defun phase-a-smoke-gate-assert-execution-spec-tests-source (report)
  (let ((source (fixture-object-field report "executionSpecTests")))
    (is source)
    (is (string= "ethereum/execution-spec-tests"
                 (fixture-object-field source "repository")))
    (is (string= "v5.4.0"
                 (fixture-object-field source "release")))
    (is (string= "88e9fb8"
                 (fixture-object-field source "tagTarget")))
    (is (string= "fixtures_stable.tar.gz"
                 (fixture-object-field source "archive")))))

(defun phase-a-smoke-gate-section-count (section field)
  (or (fixture-object-field section field) 0))

(defun phase-a-smoke-gate-assert-counts (report)
  (let* ((state (fixture-object-field report "state"))
         (transaction (fixture-object-field report "transaction"))
         (blockchain (fixture-object-field report "blockchain"))
         (devnet (fixture-object-field report "devnet"))
         (devnet-side-reorg
           (fixture-object-field report "devnetSideReorg"))
         (fixture-case-count
           (+ (phase-a-smoke-gate-section-count state "count")
              (phase-a-smoke-gate-section-count transaction "count")
              (phase-a-smoke-gate-section-count blockchain "count")))
         (fixture-executed-count
           (+ (phase-a-smoke-gate-section-count state "executedCount")
              (phase-a-smoke-gate-section-count transaction "executedCount")
              (phase-a-smoke-gate-section-count blockchain "executedCount")))
         (devnet-case-count
           (if devnet
               (phase-a-smoke-gate-section-count devnet "caseCount")
               0))
         (devnet-side-reorg-case-count
           (if devnet-side-reorg
               (phase-a-smoke-gate-section-count
                devnet-side-reorg "sideReorgCaseCount")
               0)))
    (is (= fixture-case-count
           (fixture-object-field report "fixtureCaseCount")))
    (is (= fixture-executed-count
           (fixture-object-field report "fixtureExecutedCount")))
    (is (= (+ fixture-case-count
              devnet-case-count
              devnet-side-reorg-case-count)
           (fixture-object-field report "totalCaseCount")))
    (is (= (+ fixture-executed-count
              devnet-case-count
              devnet-side-reorg-case-count)
           (fixture-object-field report "totalExecutedCount")))))

(defun phase-a-smoke-gate-assert-in-repo-fixture-counts (report)
  (let* ((state (fixture-object-field report "state"))
         (transaction (fixture-object-field report "transaction"))
         (blockchain (fixture-object-field report "blockchain"))
         (kind-counts (fixture-object-field blockchain "kindCounts")))
    (is (= 4 (fixture-object-field state "count")))
    (is (= 4 (fixture-object-field state "executedCount")))
    (is (= 25 (fixture-object-field transaction "count")))
    (is (= 25 (fixture-object-field transaction "executedCount")))
    (is (= 9 (fixture-object-field blockchain "count")))
    (is (= 9 (fixture-object-field blockchain "executedCount")))
    (is (= 1 (fixture-object-field blockchain "blockCount")))
    (is (= 8 (fixture-object-field kind-counts "engineNewPayloadV2")))
    (is (= 1 (fixture-object-field kind-counts "blockRlp")))
    (is (= 38 (fixture-object-field report "fixtureCaseCount")))
    (is (= 38 (fixture-object-field report "fixtureExecutedCount")))))

(defun devnet-smoke-gate-case-files (report field)
  (loop for case-report in (or (fixture-object-field report "cases") nil)
        for path = (fixture-object-field case-report field)
        when (stringp path)
          collect path))

(defun devnet-smoke-gate-case-database-files (report)
  (devnet-smoke-gate-case-files report "databaseFile"))

(defun devnet-cli-read-stream-string (stream)
  (with-output-to-string (output)
    (loop for char = (read-char stream nil nil)
          while char
          do (write-char char output))))

(defun devnet-smoke-gate-launch-json-process ()
  (uiop:launch-program
   (list "sbcl"
         "--script"
         "scripts/devnet-smoke-gate.lisp"
         "--"
         "--json")
   :output :stream
   :error-output :stream))

(defun devnet-smoke-gate-finish-json-process (process)
  (let ((status (uiop:wait-process process))
        (stdout
          (devnet-cli-read-stream-string (uiop:process-info-output process)))
        (stderr
          (devnet-cli-read-stream-string
           (uiop:process-info-error-output process))))
    (values stdout stderr status)))

(deftest devnet-smoke-gate-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/devnet-smoke-gate.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/devnet-smoke-gate.lisp"
                stdout))
    (is (search "--all-fixtures" stdout))
    (is (search "--ready-file PATH" stdout))
    (is (search "--log-file PATH" stdout))
    (is (search "--pid-file PATH" stdout))
    (is (search "--database PATH" stdout))
    (is (search "--prune-state-before NUMBER" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest devnet-smoke-gate-script-writes-ready-and-log-files
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let ((ready-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke" "pid"))
        (database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-chain" "sexp"))
        (reference-token
          (format nil "~A-~A" (sb-unix:unix-getpid) (gensym))))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "env"
                    (format nil "ETHEREUM_LISP_GETH_ROOT=/private/tmp/ethereum-lisp-devnet-geth-root-~A/"
                            reference-token)
                    (format nil "ETHEREUM_LISP_NETHERMIND_ROOT=/private/tmp/ethereum-lisp-devnet-nethermind-root-~A/"
                            reference-token)
                    (format nil "ETHEREUM_LISP_RETH_ROOT=/private/tmp/ethereum-lisp-devnet-reth-root-~A/"
                            reference-token)
                    "sbcl"
                    "--script"
                    "scripts/devnet-smoke-gate.lisp"
                    "--"
                    "--json"
                    "--ready-file" (namestring ready-path)
                    "--log-file" (namestring log-path)
                    "--pid-file" (namestring pid-path)
                    "--database" (namestring database-path)
                    "--prune-state-before" "42")
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((report (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (database
                      (make-file-key-value-database database-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (reference-clients
                      (fixture-object-field report "referenceClients"))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records)))
               (is (string= "ok" (fixture-object-field report "status")))
               (is (string= "devnet-listener-boundary"
                            (fixture-object-field report "mode")))
               (phase-a-smoke-gate-assert-execution-spec-tests-source report)
               (is (= 3 (length reference-clients)))
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "geth")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "nethermind")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "reth")
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "geth"
                (format nil "/private/tmp/ethereum-lisp-devnet-geth-root-~A/"
                        reference-token))
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "nethermind"
                (format nil "/private/tmp/ethereum-lisp-devnet-nethermind-root-~A/"
                        reference-token))
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "reth"
                (format nil "/private/tmp/ethereum-lisp-devnet-reth-root-~A/"
                        reference-token))
               (is (string= (namestring ready-path)
                            (fixture-object-field report "readyFile")))
               (is (string= (namestring log-path)
                            (fixture-object-field report "logFile")))
               (is (string= (namestring pid-path)
                            (fixture-object-field report "pidFile")))
               (is (string= "http://127.0.0.1:8551"
                            (fixture-object-field report "engineEndpoint")))
               (is (string= "http://127.0.0.1:8545"
                            (fixture-object-field report "rpcEndpoint")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineUnauthenticatedStatus")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicEngineNamespaceErrorCode")))
               (is (= (fixture-object-field ready-summary "processId")
                      (devnet-cli-pid-file-process-id pid-path)))
               (is (string= (namestring database-path)
                            (fixture-object-field report "databaseFile")))
               (is (= 42 (fixture-object-field
                          report "databasePruneStateBefore")))
               (is (eq nil
                       (fixture-object-field
                        report "databasePrunedStateAvailable")))
               (is (string= "eth_getBalance state is not available"
                            (fixture-object-field
                             report "databaseRpcPrunedStateError")))
               (let ((errors
                       (fixture-object-field
                        report "databaseRpcPrunedStateErrors")))
                 (is (= 8 (length errors)))
                 (dolist (message (devnet-cli-pruned-state-error-messages))
                   (is (member message errors :test #'string=))))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database
                    :state
                    (hash32-bytes
                     (hash32-from-hex
                      (fixture-object-field report "safeBlockHash")))
                    :missing)
                 (is (eq :missing value))
                 (is (not present-p)))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field report
                                                  "databaseHeadNumber")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (fixture-object-field report
                                                  "databaseSafeNumber")))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field report "databaseSafeHash")))
               (is (string= (fixture-object-field
                              report "finalizedBlockNumber")
                            (fixture-object-field
                             report "databaseFinalizedNumber")))
               (is (string= (fixture-object-field report "finalizedBlockHash")
                            (fixture-object-field
                             report "databaseFinalizedHash")))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field
                             report "databaseRpcBlockNumber")))
               (is (string= (fixture-object-field report "checkedBalance")
                            (fixture-object-field
                             report "databaseRpcBalance")))
               (is (string= (fixture-object-field report "checkedNonce")
                            (fixture-object-field report "databaseRpcNonce")))
               (is (string= (fixture-object-field report "checkedCode")
                            (fixture-object-field report "databaseRpcCode")))
               (is (string= (fixture-object-field report "checkedStorage")
                            (fixture-object-field
                             report "databaseRpcStorage")))
               (is (string= (fixture-object-field
                              report "checkedStorageAddress")
                            (fixture-object-field
                             report "databaseRpcProofAddress")))
               (is (string= (fixture-object-field
                              report "checkedProofCodeHash")
                            (fixture-object-field
                             report "databaseRpcProofCodeHash")))
               (is (string= (fixture-object-field report "checkedStorageKey")
                            (fixture-object-field
                             report "databaseRpcProofStorageKey")))
               (is (string= (fixture-object-field
                              report "checkedProofStorageValue")
                            (fixture-object-field
                             report "databaseRpcProofStorageValue")))
               (is (= 1 (fixture-object-field
                         report "databaseRpcProofStorageCount")))
               (is (<= 0 (fixture-object-field
                          report "databaseRpcProofAccountProofCount")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByHashNumber")
                            (fixture-object-field report "blockNumber")))
               (is (stringp
                    (fixture-object-field report "databaseRpcBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberNumber")
                            (fixture-object-field report "blockNumber")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberHash")
                            (fixture-object-field
                             report "databaseRpcBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcTransactionBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcTransactionBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (= (fixture-object-field report "transactionCount")
                      (fixture-object-field
                       report "databaseRpcBlockReceiptsCount")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockReceiptTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcBlockReceiptBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockReceiptBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (= (fixture-object-field report "transactionCount")
                      (fixture-object-field report
                                            "databaseRpcTransactionCount")))
               (devnet-cli-assert-restored-full-block-transactions report)
               (is (= (fixture-object-field report "checkedBalanceCount")
                      (fixture-object-field report
                                            "databaseRpcBalanceCount")))
               (is (= (fixture-object-field report "checkedLogCount")
                      (fixture-object-field report
                                            "databaseRpcLogCount")))
               (is (string= (quantity-to-hex
                              (fixture-object-field report "transactionCount"))
                            (fixture-object-field
                             report
                             "databaseRpcBlockTransactionCountByHash")))
               (is (string= (quantity-to-hex
                              (fixture-object-field report "transactionCount"))
                            (fixture-object-field
                             report
                             "databaseRpcBlockTransactionCountByNumber")))
               (is (string= (fixture-object-field report "databaseRpcBalance")
                            (fixture-object-field
                             report "databaseRpcCanonicalHashBalance")))
               (is (string= (fixture-object-field report "databaseRpcBalance")
                            (fixture-object-field
                             report
                             "databaseRpcCanonicalHashRequireBalance")))
               (is (string= (fixture-object-field
                              report
                              "databaseRpcRawTransactionByBlockHashAndIndex")
                            (fixture-object-field
                             report
                             "databaseRpcRawTransactionByBlockNumberAndIndex")))
               (is (string= (fixture-object-field
                              report
                              "databaseRpcRawTransactionByHash")
                            (fixture-object-field
                             report
                             "databaseRpcRawTransactionByBlockHashAndIndex")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexBlockHash")))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexBlockNumber")))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexBlockNumber")))
               (is (string= "0x0"
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexIndex")))
               (is (string= "0x0"
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexIndex")))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field
                             report "databaseRpcSafeBlockHash")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (fixture-object-field
                             report "databaseRpcSafeBlockNumber")))
               (is (string= (fixture-object-field report "finalizedBlockHash")
                            (fixture-object-field
                             report "databaseRpcFinalizedBlockHash")))
               (is (string= (fixture-object-field
                              report "finalizedBlockNumber")
                            (fixture-object-field
                             report "databaseRpcFinalizedBlockNumber")))
               (is (= (fixture-object-field report "checkedSimulationCount")
                      (fixture-object-field report
                                            "databaseRpcSimulationCount")))
               (is (string= "0x"
                            (fixture-object-field
                             report "databaseRpcCallResult")))
               (is (<= 21000
                       (hex-to-quantity
                        (fixture-object-field
                         report "databaseRpcEstimateGas"))))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcAccessListGasUsed")))
               (is (string= (fixture-object-field report "checkedStorage")
                            (fixture-object-field
                             report "databaseRpcPostCallStorage")))
               (is (= (devnet-cli-restored-public-connections report)
                      (fixture-object-field
                       report "databaseRpcPublicConnections")))
               (is (string= (fixture-object-field report "preparedPayloadId")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadId")))
               (is (string= (fixture-object-field
                              report "preparedPayloadParentHash")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadParentHash")))
               (is (string= (fixture-object-field
                              report "preparedPayloadBlockNumber")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadBlockNumber")))
               (is (string= +payload-status-syncing+
                            (fixture-object-field report "remoteBlockStatus")))
               (is (string= (fixture-object-field report "remoteBlockHash")
                            (fixture-object-field
                             report "databaseRemoteBlockHash")))
               (is (string= +payload-status-syncing+
                            (fixture-object-field
                             report "databaseRpcRemoteBlockStatus")))
               (is (string= +payload-status-invalid+
                            (fixture-object-field report
                                                  "invalidTipsetStatus")))
               (is (string= "Timestamp is not greater than parent timestamp"
                            (fixture-object-field
                             report "invalidTipsetValidationError")))
               (is (string= (fixture-object-field
                              report "invalidTipsetBlockHash")
                            (fixture-object-field
                             report "databaseInvalidTipsetBlockHash")))
               (is (string= +payload-status-invalid+
                            (fixture-object-field
                             report "databaseRpcInvalidTipsetStatus")))
               (is (string= "links to previously rejected block"
                            (fixture-object-field
                             report
                             "databaseRpcInvalidTipsetValidationError")))
               (devnet-cli-assert-txpool-subpool-persistence report)
               (devnet-cli-assert-side-reorg-persistence report)
               (is (< 0 (length (kv-chain-record-entries database :block))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :prepared-payload))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :remote-block))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :invalid-tipset))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :txpool))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :canonical-hash))))
               (is (string= "http://127.0.0.1:8551"
                            (fixture-object-field ready-summary
                                                  "engineEndpoint")))
               (is (string= "http://127.0.0.1:8545"
                            (fixture-object-field ready-summary
                                                  "rpcEndpoint")))
               (is (integerp (fixture-object-field ready-summary
                                                    "processId")))
               (is (< 0 (fixture-object-field ready-summary "processId")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (eq t (fixture-object-field ready-summary
                                                "stateAvailable")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (quantity-to-hex
                             (fixture-object-field ready-summary
                                                   "headNumber"))))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field ready-summary
                                                  "headHash")))
               (is (string= (namestring database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (when (member (getf log-record :name)
                               '("devnet.ready" "devnet.shutdown")
                               :test #'string=)
                   (let* ((fields (getf log-record :fields))
                          (ready-p (string= "devnet.ready"
                                            (getf log-record :name)))
                          (expected-head-number
                            (fixture-object-field
                             report
                             (if ready-p
                                 "safeBlockNumber"
                                 "blockNumber")))
                          (expected-head-hash
                            (fixture-object-field
                             report
                             (if ready-p
                                 "safeBlockHash"
                                 "latestValidHash"))))
                     (is (string= expected-head-number
                                  (cdr (assoc "headNumber" fields
                                              :test #'string=))))
                     (is (string= expected-head-hash
                                  (cdr (assoc "headHash" fields
                                              :test #'string=))))
                     (is (string= (if ready-p "ready" "shutdown")
                                  (cdr (assoc "lifecyclePhase" fields
                                              :test #'string=))))
                     (is (string= (fixture-object-field report
                                                        "engineEndpoint")
                                  (cdr (assoc "engineEndpoint" fields
                                              :test #'string=))))
                     (is (string= (fixture-object-field report "rpcEndpoint")
                                  (cdr (assoc "rpcEndpoint" fields
                                              :test #'string=))))
                     (is (string= (write-to-string
                                    (fixture-object-field ready-summary
                                                          "processId"))
                                  (cdr (assoc "processId" fields
                                              :test #'string=))))
                     (is (string= "true"
                                  (cdr (assoc "stateAvailable" fields
                                              :test #'string=))))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-smoke-gate-script-runs-all-pinned-fixtures
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
               (is (= (* 6 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "engineConnections")))
               (is (= (* 15 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "publicConnections")))
               (is (= (* 21 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "totalConnections")))
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
                   (is (= 6 (fixture-object-field case "engineConnections")))
                   (is (= 15 (fixture-object-field case "publicConnections")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineUnauthenticatedStatus")))
                   (is (= -32601
                          (fixture-object-field
                           case
                           "publicEngineNamespaceErrorCode")))
                   (is (string= expected-block-number
                                 (fixture-object-field case "blockNumber"))))
                 (is (string= (fixture-object-field case "blockNumber")
                              (fixture-object-field
                               case "databaseHeadNumber")))
                 (is (string= (fixture-object-field case "safeBlockNumber")
                              (fixture-object-field
                               case "databaseSafeNumber")))
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
                 (is (string= (fixture-object-field case "blockNumber")
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

(deftest devnet-smoke-gate-script-runs-concurrently
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let ((first-process (devnet-smoke-gate-launch-json-process))
        (second-process (devnet-smoke-gate-launch-json-process)))
    (multiple-value-bind (first-stdout first-stderr first-status)
        (devnet-smoke-gate-finish-json-process first-process)
      (multiple-value-bind (second-stdout second-stderr second-status)
          (devnet-smoke-gate-finish-json-process second-process)
        (is (= 0 first-status))
        (is (= 0 second-status))
        (is (string= "" first-stderr))
        (is (string= "" second-stderr))
        (when (and (= 0 first-status) (= 0 second-status))
          (dolist (report (list (parse-json first-stdout)
                                (parse-json second-stdout)))
            (is (string= "ok" (fixture-object-field report "status")))
            (is (string= "devnet-listener-boundary"
                         (fixture-object-field report "mode")))
            (phase-a-smoke-gate-assert-execution-spec-tests-source report)
            (is (= 3 (length (fixture-object-field report
                                                   "referenceClients"))))))))))

(deftest phase-a-fixture-report-includes-reference-client-pins
  #-sbcl
  (skip-test "Phase A fixture report script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--json"
             "--root"
             "tests/fixtures/execution-spec-tests-root/")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (reference-clients
               (fixture-object-field report "referenceClients")))
        (phase-a-smoke-gate-assert-execution-spec-tests-source report)
        (is (= 3 (length reference-clients)))
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "geth")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "nethermind")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "reth")))))

(deftest phase-a-report-scripts-honor-reference-client-root-env
  #-sbcl
  (skip-test "Phase A report scripts require SBCL")
  #+sbcl
  (let* ((token (format nil "~A-~A" (sb-unix:unix-getpid) (gensym)))
         (geth-root
           (format nil "/private/tmp/ethereum-lisp-geth-root-~A/" token))
         (nethermind-root
           (format nil "/private/tmp/ethereum-lisp-nethermind-root-~A/"
                   token))
         (reth-root
           (format nil "/private/tmp/ethereum-lisp-reth-root-~A/" token))
         (environment
           (list
            (format nil "ETHEREUM_LISP_GETH_ROOT=~A" geth-root)
            (format nil "ETHEREUM_LISP_NETHERMIND_ROOT=~A"
                    nethermind-root)
            (format nil "ETHEREUM_LISP_RETH_ROOT=~A" reth-root))))
    (labels ((run-report (script &rest extra-args)
               (uiop:run-program
                (append
                 (list "env")
                 environment
                 (list "sbcl" "--script" script "--")
                 extra-args)
                :output :string
                :error-output :string
                :ignore-error-status t))
             (assert-reference-roots (report)
               (let ((reference-clients
                       (fixture-object-field report "referenceClients")))
                 (is (= 3 (length reference-clients)))
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "geth" geth-root)
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "nethermind" nethermind-root)
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "reth" reth-root)
                 (dolist (name '("geth" "nethermind" "reth"))
                   (phase-a-smoke-gate-assert-reference-client
                    reference-clients name)))))
      (multiple-value-bind (stdout stderr status)
          (run-report
           "scripts/phase-a-fixture-report.lisp"
           "--json"
           "--root"
           "tests/fixtures/execution-spec-tests-root/")
        (is (= 0 status))
        (is (string= "" stderr))
        (when (= 0 status)
          (assert-reference-roots (parse-json stdout))))
      (multiple-value-bind (stdout stderr status)
          (run-report
           "scripts/phase-a-smoke-gate.lisp"
           "--json"
           "--root"
           "tests/fixtures/execution-spec-tests-root/")
        (is (= 0 status))
        (is (string= "" stderr))
        (when (= 0 status)
          (assert-reference-roots (parse-json stdout)))))))

(deftest phase-a-fixture-report-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Phase A fixture report script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-fixture-report.lisp"
                stdout))
    (is (search "--root PATH" stdout))
    (is (search "--pinned-v5.4.0" stdout))
    (is (search "--json" stdout))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest phase-a-smoke-gate-help-prints-reference-root-env
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-smoke-gate.lisp"
                stdout))
    (is (search "--root PATH" stdout))
    (is (search "--pinned-v5.4.0" stdout))
    (is (search "--devnet" stdout))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest phase-a-fixture-report-pinned-mode-requires-root
  #-sbcl
  (skip-test "Phase A fixture report pinned mode requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "env"
             "-u"
             "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
             "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--pinned-v5.4.0"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Pinned Phase A fixture report requires an EEST fixture root"
                stderr))
    (is (search "--root" stderr))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stderr))
    (is (not (search "do not match pinned selectors" stderr)))))

(deftest phase-a-fixture-report-pinned-mode-rejects-missing-env-root
  #-sbcl
  (skip-test "Phase A fixture report pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-pinned-report-root-~A/"
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
               "scripts/phase-a-fixture-report.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Pinned Phase A fixture report root from" stderr))
      (is (not (search "do not match pinned selectors" stderr))))))

(deftest phase-a-selector-scripts-accept-root-option
  #-sbcl
  (skip-test "Phase A selector scripts require SBCL")
  #+sbcl
  (labels ((run-selector-script (script)
             (multiple-value-bind (stdout stderr status)
                 (uiop:run-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--json"
                        "--root"
                        "tests/fixtures/execution-spec-tests-root/")
                  :output :string
                  :error-output :string
                  :ignore-error-status t)
               (is (= 0 status))
               (is (string= "" stderr))
               (when (= 0 status)
                 (let ((report (parse-json stdout)))
                   (is (search "tests/fixtures/execution-spec-tests-root/"
                               (fixture-object-field report "root")))
                   (is (plusp (fixture-object-field report "count"))))))))
    (run-selector-script "scripts/list-state-test-selectors.lisp")
    (run-selector-script "scripts/list-transaction-test-selectors.lisp")
    (run-selector-script "scripts/list-blockchain-replay-selectors.lisp")))

(deftest phase-a-fixture-sync-scripts-reject-missing-env-root
  #-sbcl
  (skip-test "Phase A fixture sync scripts require SBCL")
  #+sbcl
  (let* ((env-root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-fixture-sync-env-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (env-root-string (namestring env-root))
         (explicit-root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-fixture-sync-explicit-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (explicit-root-string (namestring explicit-root)))
    (labels ((run-script-with-missing-env-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          (format nil
                                  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                                  env-root-string)
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json")
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search env-root-string stderr))
                 (is (search "Configured EEST fixture root from" stderr))
                 (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                             stderr))))
             (run-script-with-missing-explicit-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          "-u"
                          "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json"
                          "--root"
                          explicit-root-string)
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search explicit-root-string stderr))
                 (is (search "Configured EEST fixture root from" stderr))
                 (is (search "--root" stderr)))))
      (dolist (script
               '("scripts/phase-a-fixture-report.lisp"
                 "scripts/list-state-test-selectors.lisp"
                 "scripts/list-transaction-test-selectors.lisp"
                 "scripts/list-blockchain-replay-selectors.lisp"))
        (run-script-with-missing-env-root script)
        (run-script-with-missing-explicit-root script)))))

(deftest phase-a-fixture-sync-scripts-reject-empty-suite-root
  #-sbcl
  (skip-test "Phase A fixture sync scripts require SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-empty-fixture-sync-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (dolist (subdir '("state_tests/"
                      "transaction_tests/"
                      "blockchain_tests_engine/"))
      (ensure-directories-exist (merge-pathnames subdir root)))
    (labels ((run-script-with-empty-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          "-u"
                          "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json"
                          "--root"
                          root-string)
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search root-string stderr))
                 (is (search "contains no JSON files" stderr))
                 (is (search "Configured EEST" stderr)))))
      (dolist (script
               '("scripts/phase-a-fixture-report.lisp"
                 "scripts/phase-a-smoke-gate.lisp"
                 "scripts/list-state-test-selectors.lisp"
                 "scripts/list-transaction-test-selectors.lisp"
                 "scripts/list-blockchain-replay-selectors.lisp"))
        (run-script-with-empty-root script)))))

(deftest phase-a-smoke-gate-script-can-include-devnet-suite
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
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (reference-clients
                 (fixture-object-field report "referenceClients"))
               (devnet (fixture-object-field report "devnet"))
               (devnet-side-reorg
                 (fixture-object-field report "devnetSideReorg"))
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
                        log-case "databaseRpcLogCount")))))
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
        (is (= (* 6 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "engineConnections")))
        (is (= (* 15 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "publicConnections")))
        (is (= (* 21 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "totalConnections")))
        (dolist (case cases)
          (is (string= (fixture-object-field case "blockNumber")
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
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (devnet (fixture-object-field report "devnet"))
               (devnet-side-reorg
                 (fixture-object-field report "devnetSideReorg")))
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
                  devnet-side-reorg "databaseCaseCount"))))))))

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

(deftest blockchain-replay-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-blockchain-replay-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-blockchain-replay-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest blockchain-replay-classifier-script-json-summarizes-families
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-blockchain-replay-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "shanghai/phase-a"
             "--limit"
             "2"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-blockchain-replay-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest devnet-cli-rejects-missing-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "devnet" "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (is (search "--genesis is required"
                (get-output-stream-string errors)))))

(deftest devnet-cli-rejects-malformed-options-before-loading-genesis
  (labels ((run-error (args)
             (let ((output (make-string-output-stream))
                   (errors (make-string-output-stream)))
               (is (= 1
                      (ethereum-lisp.cli:main
                       args
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string output)))
               (get-output-stream-string errors))))
    (is (search "--port requires an integer value"
                (run-error (list "devnet" "--port" "abc" "--no-serve"))))
    (is (search "--port must be between 0 and 65535"
                (run-error (list "devnet" "--port" "70000" "--no-serve"))))
    (is (search "--public-port requires an integer value"
                (run-error (list "devnet"
                                 "--public-port"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--public-port must be between 0 and 65535"
                (run-error (list "devnet"
                                 "--public-port"
                                 "70000"
                                 "--no-serve"))))
    (is (search "--max-connections must be non-negative"
                (run-error (list "devnet"
                                 "--max-connections"
                                 "-1"
                                 "--no-serve"))))
    (is (search "--prune-state-before requires an integer value"
                (run-error (list "devnet"
                                 "--prune-state-before"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--prune-state-before must be non-negative"
                (run-error (list "devnet"
                                 "--prune-state-before"
                                 "-1"
                                 "--no-serve"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis" "--no-serve"))))
    (is (search "--host requires a value"
                (run-error (list "devnet" "--host" "--no-serve"))))
    (is (search "--engine-host requires a value"
                (run-error (list "devnet" "--engine-host" "--no-serve"))))
    (is (search "--public-host requires a value"
                (run-error (list "devnet" "--public-host" "--no-serve"))))
    (is (search "--port requires a value"
                (run-error (list "devnet" "--port" "--no-serve"))))
    (is (search "--engine-port requires a value"
                (run-error (list "devnet" "--engine-port" "--no-serve"))))
    (is (search "--engine-port must be between 0 and 65535"
                (run-error (list "devnet"
                                 "--engine-port"
                                 "70000"
                                 "--no-serve"))))
    (is (search "--public-port requires a value"
                (run-error (list "devnet" "--public-port" "--no-serve"))))
    (is (search "--database requires a value"
                (run-error (list "devnet" "--database"))))
    (is (search "--prune-state-before requires a value"
                (run-error (list "devnet" "--prune-state-before"))))
    (is (search "--log-file requires a value"
                (run-error (list "devnet" "--log-file"))))
    (is (search "--pid-file requires a value"
                (run-error (list "devnet" "--pid-file"))))
    (is (search "Unknown option --wat"
                (run-error (list "devnet" "--wat"))))))
