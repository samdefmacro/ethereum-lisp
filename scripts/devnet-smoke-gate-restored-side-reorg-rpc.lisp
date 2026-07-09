(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-verify-restored-side-reorg-rpc
    (path side-payload side-block child-block balance-targets
     checkpoint-balance-targets transaction-checks expected-safe-block-hash
     sender-address code-address storage-address storage-key config)
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-side-reorg-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (devnet-smoke-gate-make-restored-node
                     path
                     config
                     :port 0
                     :public-port 0
                     :jwt-secret-path (namestring jwt-path)))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (primary-balance-target (first balance-targets))
                  (balance-address
                    (getf primary-balance-target :address))
                  (primary-checkpoint-balance-target
                    (first checkpoint-balance-targets))
                  (expected-checkpoint-balance
                    (getf primary-checkpoint-balance-target :balance))
                  (transaction-hash
                    (getf (first transaction-checks) :hash))
                  (expected-raw-transaction
                    (getf (first transaction-checks) :raw))
                  (transaction-hash-hex
                    (hash32-to-hex transaction-hash))
                  (displaced-transaction
                    (first (block-transactions child-block)))
                  (transaction-items
                    (loop for check in transaction-checks
                          for transaction in (block-transactions child-block)
                          collect
                          (list
                           :hash (getf check :hash)
                           :hash-hex (hash32-to-hex (getf check :hash))
                           :raw (getf check :raw)
                           :reinsertable-p
                           (not (null
                                 (transaction-sender
                                  transaction
                                  :expected-chain-id
                                  (chain-config-chain-id
                                   (ethereum-lisp.cli:devnet-node-config
                                    node))))))))
                  (reinsertable-transaction-items
                    (remove-if-not
                     (lambda (item) (getf item :reinsertable-p))
                     transaction-items))
                  (reinsertable-transaction-hashes
                    (mapcar
                     (lambda (item) (getf item :hash-hex))
                     reinsertable-transaction-items))
                  (extra-transaction-items
                    (rest transaction-items))
                  (side-public-connection-count
                    (+ 9 (length extra-transaction-items)))
                  (fresh-public-connection-count
                    (+ 20 (length extra-transaction-items)))
                  (side-block-hash (block-hash side-block))
                  (child-block-hash (block-hash child-block))
                  (node-chain-id
                    (chain-config-chain-id
                     (ethereum-lisp.cli:devnet-node-config node)))
                  (reinsertable-transaction-p
                    (not (null
                          (transaction-sender
                           displaced-transaction
                           :expected-chain-id node-chain-id))))
                  (expected-safe-block-number
                    (quantity-to-hex
                     (1- (block-header-number
                          (block-header child-block)))))
                  (expected-side-block-number
                    (quantity-to-hex
                     (block-header-number (block-header side-block))))
                  (side-payload-output (make-string-output-stream))
                  (side-rejected-forkchoice-output
                    (make-string-output-stream))
                  (side-forkchoice-output (make-string-output-stream))
                  (side-block-number-output (make-string-output-stream))
                  (side-latest-block-output (make-string-output-stream))
                  (side-transaction-output (make-string-output-stream))
                  (side-raw-transaction-output
                    (make-string-output-stream))
                  (side-pending-transactions-output
                    (make-string-output-stream))
                  (side-receipt-output (make-string-output-stream))
                  (side-extra-receipt-outputs
                    (loop repeat (length extra-transaction-items)
                          collect (make-string-output-stream)))
                  (child-block-output (make-string-output-stream))
                  (side-block-receipts-output (make-string-output-stream))
                  (side-logs-output (make-string-output-stream))
                  (engine-requests
                    (list
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 201 side-payload))
                      side-payload-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        202 side-block-hash
                        :safe child-block-hash
                        :finalized expected-safe-block-hash))
                      side-rejected-forkchoice-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        210 side-block-hash
                        :safe expected-safe-block-hash
                        :finalized expected-safe-block-hash))
                      side-forkchoice-output)))
                  (public-requests
                    (append
                     (list
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 203)
                              (cons "method" "eth_blockNumber")
                              (cons "params" '())))
                       side-block-number-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 204)
                              (cons "method" "eth_getBlockByNumber")
                              (cons "params" (list "latest" :false))))
                       side-latest-block-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 205)
                              (cons "method" "eth_getTransactionByHash")
                              (cons "params"
                                    (list (hash32-to-hex
                                           transaction-hash)))))
                       side-transaction-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 206)
                              (cons "method" "eth_getRawTransactionByHash")
                              (cons "params"
                                    (list transaction-hash-hex))))
                       side-raw-transaction-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 207)
                              (cons "method" "eth_pendingTransactions")
                              (cons "params" '())))
                       side-pending-transactions-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 208)
                              (cons "method" "eth_getTransactionReceipt")
                              (cons "params"
                                    (list transaction-hash-hex))))
                       side-receipt-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 209)
                              (cons "method" "eth_getBlockByHash")
                              (cons "params"
                                    (list (hash32-to-hex child-block-hash)
                                          :false))))
                       child-block-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 211)
                              (cons "method" "eth_getBlockReceipts")
                              (cons "params" (list "latest"))))
                       side-block-receipts-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 212)
                              (cons "method" "eth_getLogs")
                              (cons "params"
                                    (list
                                     (list
                                      (cons "fromBlock"
                                            expected-side-block-number)
                                      (cons "toBlock"
                                            expected-side-block-number))))))
                       side-logs-output))
                     (loop for item in extra-transaction-items
                           for output in side-extra-receipt-outputs
                           for id from 230
                           collect
                           (cons
                            (json-encode
                             (list (cons "jsonrpc" "2.0")
                                   (cons "id" id)
                                   (cons "method" "eth_getTransactionReceipt")
                                   (cons "params"
                                         (list (getf item :hash-hex)))))
                            output))))
                  (engine-done-p nil)
                  (engine-served-count 0)
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "engine-side-reorg"
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
                               (when (= engine-served-count 3)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "public-side-reorg"
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
                             :close-function (lambda () nil)))))
                     :close-function (lambda () nil))
                     :max-connections side-public-connection-count))
                  (side-payload-response
                    (get-output-stream-string side-payload-output))
                  (side-rejected-forkchoice-response
                    (get-output-stream-string
                     side-rejected-forkchoice-output))
                  (side-forkchoice-response
                    (get-output-stream-string side-forkchoice-output))
                  (side-block-number-response
                    (get-output-stream-string side-block-number-output))
                  (side-latest-block-response
                    (get-output-stream-string side-latest-block-output))
                  (side-transaction-response
                    (get-output-stream-string side-transaction-output))
                  (side-raw-transaction-response
                    (get-output-stream-string side-raw-transaction-output))
                  (side-pending-transactions-response
                    (get-output-stream-string
                     side-pending-transactions-output))
                  (side-receipt-response
                    (get-output-stream-string side-receipt-output))
                  (side-extra-receipt-responses
                    (mapcar #'get-output-stream-string
                            side-extra-receipt-outputs))
                  (child-block-response
                    (get-output-stream-string child-block-output))
                  (side-block-receipts-response
                    (get-output-stream-string side-block-receipts-output))
                  (side-logs-response
                    (get-output-stream-string side-logs-output))
                  (side-payload-rpc
                    (devnet-smoke-gate-rpc-body side-payload-response))
                  (side-rejected-forkchoice-rpc
                    (devnet-smoke-gate-rpc-body
                     side-rejected-forkchoice-response))
                  (side-forkchoice-rpc
                    (devnet-smoke-gate-rpc-body side-forkchoice-response))
                  (side-block-number-rpc
                    (devnet-smoke-gate-rpc-body side-block-number-response))
                  (side-latest-block-rpc
                    (devnet-smoke-gate-rpc-body side-latest-block-response))
                  (side-transaction-rpc
                    (devnet-smoke-gate-rpc-body side-transaction-response))
                  (side-raw-transaction-rpc
                    (devnet-smoke-gate-rpc-body
                     side-raw-transaction-response))
                  (side-pending-transactions-rpc
                    (devnet-smoke-gate-rpc-body
                     side-pending-transactions-response))
                  (side-receipt-rpc
                    (devnet-smoke-gate-rpc-body side-receipt-response))
                  (side-extra-receipt-rpcs
                    (mapcar #'devnet-smoke-gate-rpc-body
                            side-extra-receipt-responses))
                  (child-block-rpc
                    (devnet-smoke-gate-rpc-body child-block-response))
                  (side-block-receipts-rpc
                    (devnet-smoke-gate-rpc-body
                     side-block-receipts-response))
                  (side-logs-rpc
                    (devnet-smoke-gate-rpc-body side-logs-response))
                  (side-payload-result
                    (fixture-object-field side-payload-rpc "result"))
                  (side-rejected-forkchoice-error
                    (fixture-object-field side-rejected-forkchoice-rpc
                                          "error"))
                  (side-forkchoice-status
                    (fixture-object-field
                     (fixture-object-field side-forkchoice-rpc "result")
                     "payloadStatus"))
                  (side-latest-block
                    (fixture-object-field side-latest-block-rpc "result"))
                  (side-transaction
                    (fixture-object-field side-transaction-rpc "result"))
                  (side-raw-transaction
                    (fixture-object-field side-raw-transaction-rpc "result"))
                  (side-pending-transactions
                    (fixture-object-field side-pending-transactions-rpc
                                          "result"))
                  (side-pending-transaction
                    (find transaction-hash-hex side-pending-transactions
                          :test #'string=
                          :key (lambda (transaction)
                                 (fixture-object-field transaction
                                                       "hash"))))
                  (side-reinserted-transactions
                    (loop for item in reinsertable-transaction-items
                          collect
                          (find (getf item :hash-hex)
                                side-pending-transactions
                                :test #'string=
                                :key (lambda (transaction)
                                       (fixture-object-field transaction
                                                             "hash")))))
                  (child-block-by-hash
                    (fixture-object-field child-block-rpc "result"))
                  (side-block-receipts
                    (fixture-object-field side-block-receipts-rpc "result"))
                  (side-logs
                    (fixture-object-field side-logs-rpc "result"))
                  (side-hidden-receipt-count
                    (count-if
                     #'identity
                     (cons
                      (null (fixture-object-field side-receipt-rpc "result"))
                      (mapcar
                       (lambda (rpc)
                         (null (fixture-object-field rpc "result")))
                       side-extra-receipt-rpcs)))))
             (devnet-smoke-gate-require
              (= 3 (getf summary :engine-connections))
              "Expected 3 side-reorg Engine connections, got ~S"
              (getf summary :engine-connections))
             (devnet-smoke-gate-require
              (= side-public-connection-count
                 (getf summary :public-connections))
              "Expected ~S side-reorg public connections, got ~S"
              side-public-connection-count
              (getf summary :public-connections))
             (dolist (response
                      (append
                       (list side-payload-response
                             side-rejected-forkchoice-response
                             side-forkchoice-response
                             side-block-number-response
                             side-latest-block-response
                             side-transaction-response
                             side-raw-transaction-response
                             side-pending-transactions-response
                             side-receipt-response
                             child-block-response
                             side-block-receipts-response
                             side-logs-response)
                       side-extra-receipt-responses))
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status response))
                "Restored side-reorg RPC HTTP status mismatch"))
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field side-payload-result "status"))
              "Restored side sibling engine_newPayloadV2 status mismatch")
             (devnet-smoke-gate-require
              (string= (hash32-to-hex side-block-hash)
                       (fixture-object-field side-payload-result
                                             "latestValidHash"))
              "Restored side sibling latestValidHash mismatch")
             (devnet-smoke-gate-require
              (= -38002
                 (fixture-object-field side-rejected-forkchoice-error
                                       "code"))
              "Restored side sibling rejected checkpoint error code mismatch")
             (devnet-smoke-gate-require
              (string= "forkchoice safe block is not an ancestor of head"
                       (fixture-object-field side-rejected-forkchoice-error
                                             "message"))
              "Restored side sibling rejected checkpoint error mismatch")
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field side-forkchoice-status "status"))
              "Restored side sibling forkchoice status mismatch")
             (devnet-smoke-gate-require
              (string= expected-side-block-number
                       (fixture-object-field side-block-number-rpc "result"))
              "Restored side sibling eth_blockNumber mismatch")
             (devnet-smoke-gate-require
              (string= (hash32-to-hex side-block-hash)
                       (fixture-object-field side-latest-block "hash"))
              "Restored side sibling latest block hash mismatch")
             (if reinsertable-transaction-p
                 (progn
                   (devnet-smoke-gate-require
                    (string= transaction-hash-hex
                             (fixture-object-field side-transaction "hash"))
                    "Restored side sibling should reinsert old canonical transaction")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction "blockHash"))
                    "Restored side sibling transaction should be pending")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction
                                                "blockNumber"))
                    "Restored side sibling transaction should not have a block number")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction
                                                "transactionIndex"))
                    "Restored side sibling transaction should not have an index")
                   (devnet-smoke-gate-require
                    (string= expected-raw-transaction side-raw-transaction)
                    "Restored side sibling should expose pending raw transaction")
                   (devnet-smoke-gate-require
                    side-pending-transaction
                    "Restored side sibling should expose displaced transaction in pending view")
                   (devnet-smoke-gate-require
                    (string= transaction-hash-hex
                             (fixture-object-field side-pending-transaction
                                                   "hash"))
                    "Restored side sibling pending view transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "blockHash"))
                    "Restored side sibling pending view should not have a block hash")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "blockNumber"))
                    "Restored side sibling pending view should not have a block number")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "transactionIndex"))
                    "Restored side sibling pending view should not have an index")
                 (loop for item in reinsertable-transaction-items
                       for pending-transaction in side-reinserted-transactions
                       do
                          (devnet-smoke-gate-require
                           pending-transaction
                           "Restored side sibling missing displaced transaction in pending view")
                          (devnet-smoke-gate-require
                           (string= (getf item :hash-hex)
                                    (fixture-object-field
                                     pending-transaction
                                     "hash"))
                           "Restored side sibling displaced pending hash mismatch")
                          (devnet-smoke-gate-require
                           (null (fixture-object-field pending-transaction
                                                       "blockHash"))
                           "Restored side sibling displaced pending kept old block hash")
                          (devnet-smoke-gate-require
                           (null (fixture-object-field pending-transaction
                                                       "blockNumber"))
                           "Restored side sibling displaced pending kept old block number")
                          (devnet-smoke-gate-require
                           (null (fixture-object-field pending-transaction
                                                       "transactionIndex"))
                           "Restored side sibling displaced pending kept old index")))
               (progn
                 (devnet-smoke-gate-require
                  (null side-transaction)
                  "Restored side sibling should reject wrong-chain displaced transaction")
                 (devnet-smoke-gate-require
                  (null side-raw-transaction)
                  "Restored side sibling should hide wrong-chain raw transaction")
                 (devnet-smoke-gate-require
                  (null side-pending-transaction)
                  "Restored side sibling should hide wrong-chain pending transaction")))
             (devnet-smoke-gate-require
              (null (fixture-object-field side-receipt-rpc "result"))
              "Restored side sibling should hide old canonical receipt")
             (loop for item in extra-transaction-items
                   for rpc in side-extra-receipt-rpcs
                   do
                      (devnet-smoke-gate-require
                       (null (fixture-object-field rpc "result"))
                       "Restored side sibling should hide displaced canonical receipt ~S"
                       (getf item :hash-hex)))
	             (devnet-smoke-gate-require
	              (string= (hash32-to-hex child-block-hash)
	                       (fixture-object-field child-block-by-hash "hash"))
	              "Restored side sibling lost child block hash lookup")
	             (devnet-smoke-gate-require
	              (zerop (length side-block-receipts))
	              "Restored side sibling should have no canonical receipts")
	             (devnet-smoke-gate-require
	              (zerop (length side-logs))
	              "Restored side sibling should have no canonical logs")
             (ethereum-lisp.cli::devnet-node-export-database node)
             (let* ((fresh-node
                      (devnet-smoke-gate-make-restored-node
                       path config :port 0))
                    (fresh-summary
                      (ethereum-lisp.cli:devnet-node-summary fresh-node))
                    (fresh-raw-transaction-output
                      (make-string-output-stream))
                    (fresh-pending-transactions-output
                      (make-string-output-stream))
                    (fresh-receipt-output
                      (make-string-output-stream))
                    (fresh-extra-receipt-outputs
                      (loop repeat (length extra-transaction-items)
                            collect (make-string-output-stream)))
                    (fresh-block-number-output
                      (make-string-output-stream))
                    (fresh-latest-block-output
                      (make-string-output-stream))
                    (fresh-child-block-output
                      (make-string-output-stream))
                    (fresh-block-receipts-output
                      (make-string-output-stream))
                    (fresh-logs-output
                      (make-string-output-stream))
                    (fresh-safe-block-output
                      (make-string-output-stream))
                    (fresh-finalized-block-output
                      (make-string-output-stream))
                    (fresh-safe-balance-output
                      (make-string-output-stream))
                    (fresh-finalized-balance-output
                      (make-string-output-stream))
                    (fresh-child-require-canonical-state-probes
                      (devnet-smoke-gate-state-error-probes
                       225
                       (list
                        (cons "blockHash" (hash32-to-hex child-block-hash))
                        (cons "requireCanonical" t))
                       (devnet-smoke-gate-noncanonical-state-error-messages)
                       balance-address
                       sender-address
                       code-address
                       storage-address
                       storage-key))
                    (fresh-public-requests
                      (append
                       (list
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 213)
                                (cons "method" "eth_getRawTransactionByHash")
                                (cons "params" (list transaction-hash-hex))))
                         fresh-raw-transaction-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 214)
                                (cons "method" "eth_pendingTransactions")
                                (cons "params" '())))
                         fresh-pending-transactions-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 215)
                                (cons "method" "eth_getTransactionReceipt")
                                (cons "params" (list transaction-hash-hex))))
                         fresh-receipt-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 216)
                                (cons "method" "eth_blockNumber")
                                (cons "params" '())))
                         fresh-block-number-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 217)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "latest" :false))))
                         fresh-latest-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 218)
                                (cons "method" "eth_getBlockByHash")
                                (cons "params"
                                      (list (hash32-to-hex child-block-hash)
                                            :false))))
                         fresh-child-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 219)
                                (cons "method" "eth_getBlockReceipts")
                                (cons "params" (list "latest"))))
                         fresh-block-receipts-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 220)
                                (cons "method" "eth_getLogs")
                                (cons "params"
                                      (list
                                       (list
                                        (cons "fromBlock"
                                              expected-side-block-number)
                                        (cons "toBlock"
                                              expected-side-block-number))))))
                         fresh-logs-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 221)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "safe" :false))))
                         fresh-safe-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 222)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "finalized" :false))))
                         fresh-finalized-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 223)
                                (cons "method" "eth_getBalance")
                                (cons "params"
                                      (list (address-to-hex balance-address)
                                            "safe"))))
                         fresh-safe-balance-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 224)
                                (cons "method" "eth_getBalance")
                                (cons "params"
                                      (list (address-to-hex balance-address)
                                            "finalized"))))
                         fresh-finalized-balance-output))
                       (loop for item in extra-transaction-items
                             for output in fresh-extra-receipt-outputs
                             for id from 240
                             collect
                             (cons
                              (json-encode
                               (list (cons "jsonrpc" "2.0")
                                     (cons "id" id)
                                     (cons "method"
                                           "eth_getTransactionReceipt")
                                     (cons "params"
                                           (list (getf item :hash-hex)))))
                              output))
                       (mapcar
                        (lambda (probe)
                          (cons (json-encode (getf probe :request))
                                (getf probe :output)))
                        fresh-child-require-canonical-state-probes)))
                    (fresh-rpc-summary
                      (ethereum-lisp.cli:start-devnet-node-listeners
                       fresh-node
                       (make-engine-rpc-http-listener
                        :endpoint "engine-side-reorg-fresh-restore"
                        :accept-function (lambda () nil)
                        :close-function (lambda () nil))
                       (make-engine-rpc-http-listener
                        :endpoint "public-side-reorg-fresh-restore"
                        :accept-function
                        (lambda ()
                          (when fresh-public-requests
                            (destructuring-bind (body . output)
                                (pop fresh-public-requests)
                              (make-engine-rpc-http-connection
                               :input-stream
                               (make-string-input-stream
                                (devnet-cli-json-rpc-http-request body))
                               :output-stream output
                               :close-function (lambda () nil)))))
                       :close-function (lambda () nil))
                       :max-connections fresh-public-connection-count))
                    (fresh-raw-transaction-response
                      (get-output-stream-string
                       fresh-raw-transaction-output))
                    (fresh-pending-transactions-response
                      (get-output-stream-string
                       fresh-pending-transactions-output))
                    (fresh-receipt-response
                      (get-output-stream-string fresh-receipt-output))
                    (fresh-extra-receipt-responses
                      (mapcar #'get-output-stream-string
                              fresh-extra-receipt-outputs))
                    (fresh-block-number-response
                      (get-output-stream-string fresh-block-number-output))
                    (fresh-latest-block-response
                      (get-output-stream-string fresh-latest-block-output))
                    (fresh-child-block-response
                      (get-output-stream-string fresh-child-block-output))
                    (fresh-block-receipts-response
                      (get-output-stream-string fresh-block-receipts-output))
                    (fresh-logs-response
                      (get-output-stream-string fresh-logs-output))
                    (fresh-safe-block-response
                      (get-output-stream-string fresh-safe-block-output))
                    (fresh-finalized-block-response
                      (get-output-stream-string fresh-finalized-block-output))
                    (fresh-safe-balance-response
                      (get-output-stream-string fresh-safe-balance-output))
                    (fresh-finalized-balance-response
                      (get-output-stream-string
                       fresh-finalized-balance-output))
                    (fresh-raw-transaction-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-raw-transaction-response))
                    (fresh-pending-transactions-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-pending-transactions-response))
                    (fresh-receipt-rpc
                      (devnet-smoke-gate-rpc-body fresh-receipt-response))
                    (fresh-extra-receipt-rpcs
                      (mapcar #'devnet-smoke-gate-rpc-body
                              fresh-extra-receipt-responses))
                    (fresh-block-number-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-block-number-response))
                    (fresh-latest-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-latest-block-response))
                    (fresh-child-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-child-block-response))
                    (fresh-block-receipts-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-block-receipts-response))
                    (fresh-logs-rpc
                      (devnet-smoke-gate-rpc-body fresh-logs-response))
                    (fresh-safe-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-safe-block-response))
                    (fresh-finalized-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-finalized-block-response))
                    (fresh-safe-balance-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-safe-balance-response))
                    (fresh-finalized-balance-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-finalized-balance-response))
                    (fresh-raw-transaction
                      (fixture-object-field fresh-raw-transaction-rpc
                                            "result"))
                    (fresh-pending-transactions
                      (fixture-object-field fresh-pending-transactions-rpc
                                            "result"))
                    (fresh-pending-transaction
                      (find transaction-hash-hex fresh-pending-transactions
                            :test #'string=
                            :key (lambda (transaction)
                                   (fixture-object-field transaction
                                                         "hash"))))
                    (fresh-reinserted-transactions
                      (loop for item in reinsertable-transaction-items
                            collect
                            (find (getf item :hash-hex)
                                  fresh-pending-transactions
                                  :test #'string=
                                  :key (lambda (transaction)
                                         (fixture-object-field transaction
                                                               "hash")))))
                    (fresh-latest-block
                      (fixture-object-field fresh-latest-block-rpc "result"))
                    (fresh-child-block
                      (fixture-object-field fresh-child-block-rpc "result"))
                    (fresh-block-receipts
                      (fixture-object-field fresh-block-receipts-rpc
                                            "result"))
                    (fresh-logs
                      (fixture-object-field fresh-logs-rpc "result"))
                    (fresh-safe-block
                      (fixture-object-field fresh-safe-block-rpc "result"))
                    (fresh-finalized-block
                      (fixture-object-field fresh-finalized-block-rpc
                                            "result"))
                    (fresh-safe-balance
                      (fixture-object-field fresh-safe-balance-rpc
                                            "result"))
                    (fresh-finalized-balance
                      (fixture-object-field fresh-finalized-balance-rpc
                                            "result"))
                    (fresh-child-require-canonical-state-errors
                      (devnet-smoke-gate-verify-state-error-probes
                       fresh-child-require-canonical-state-probes
                       "noncanonical-state"))
                    (fresh-hidden-receipt-count
                      (count-if
                       #'identity
                       (cons
                        (null (fixture-object-field fresh-receipt-rpc
                                                    "result"))
                        (mapcar
                         (lambda (rpc)
                           (null (fixture-object-field rpc "result")))
                         fresh-extra-receipt-rpcs)))))
               (devnet-smoke-gate-require
                (= (block-header-number (block-header side-block))
                   (getf fresh-summary :head-number))
                "Side-reorg database restore head number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex side-block-hash)
                         (getf fresh-summary :head-hash))
                "Side-reorg database restore head hash mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (getf fresh-summary :safe-hash))
                "Side-reorg database restore safe hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (quantity-to-hex
                          (getf fresh-summary :safe-number)))
                "Side-reorg database restore safe number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (getf fresh-summary :finalized-hash))
                "Side-reorg database restore finalized hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (quantity-to-hex
                          (getf fresh-summary :finalized-number)))
                "Side-reorg database restore finalized number mismatch")
               (devnet-smoke-gate-require
                (chain-store-known-block
                 (ethereum-lisp.cli:devnet-node-store fresh-node)
                 child-block-hash)
                "Side-reorg database restore lost old child block")
               (devnet-smoke-gate-require
                (= 0 (getf fresh-rpc-summary :engine-connections))
                "Fresh side-reorg restore expected 0 Engine connections, got ~S"
                (getf fresh-rpc-summary :engine-connections))
               (devnet-smoke-gate-require
                (= fresh-public-connection-count
                   (getf fresh-rpc-summary :public-connections))
                "Fresh side-reorg restore expected ~S public connections, got ~S"
                fresh-public-connection-count
                (getf fresh-rpc-summary :public-connections))
               (dolist (response (append
                                   (list fresh-raw-transaction-response
                                         fresh-pending-transactions-response
                                         fresh-receipt-response
                                         fresh-block-number-response
                                         fresh-latest-block-response
                                         fresh-child-block-response
                                         fresh-block-receipts-response
                                         fresh-logs-response
                                         fresh-safe-block-response
                                         fresh-finalized-block-response
                                         fresh-safe-balance-response
                                         fresh-finalized-balance-response)
                                   fresh-extra-receipt-responses))
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status response))
                  "Fresh side-reorg restore public RPC HTTP status mismatch"))
               (if reinsertable-transaction-p
                   (progn
                     (devnet-smoke-gate-require
                      (string= expected-raw-transaction
                               fresh-raw-transaction)
                      "Fresh side-reorg restore lost pending raw transaction")
                     (devnet-smoke-gate-require
                      fresh-pending-transaction
                      "Fresh side-reorg restore lost pending transaction view")
                     (devnet-smoke-gate-require
                      (string= transaction-hash-hex
                               (fixture-object-field
                                fresh-pending-transaction
                                "hash"))
                      "Fresh side-reorg restore pending transaction hash mismatch")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "blockHash"))
                      "Fresh side-reorg restore pending view kept old block hash")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "blockNumber"))
                      "Fresh side-reorg restore pending view kept old block number")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "transactionIndex"))
                      "Fresh side-reorg restore pending view kept old index")
                     (loop for item in reinsertable-transaction-items
                           for pending-transaction in fresh-reinserted-transactions
                           do
                              (devnet-smoke-gate-require
                               pending-transaction
                               "Fresh side-reorg restore missing displaced transaction in pending view")
                              (devnet-smoke-gate-require
                               (string= (getf item :hash-hex)
                                        (fixture-object-field
                                         pending-transaction
                                         "hash"))
                               "Fresh side-reorg restore displaced pending hash mismatch")
                              (devnet-smoke-gate-require
                               (null (fixture-object-field pending-transaction
                                                           "blockHash"))
                               "Fresh side-reorg restore displaced pending kept old block hash")
                              (devnet-smoke-gate-require
                               (null (fixture-object-field pending-transaction
                                                           "blockNumber"))
                               "Fresh side-reorg restore displaced pending kept old block number")
                              (devnet-smoke-gate-require
                               (null (fixture-object-field pending-transaction
                                                           "transactionIndex"))
                               "Fresh side-reorg restore displaced pending kept old index")))
                 (progn
                   (devnet-smoke-gate-require
                    (null fresh-raw-transaction)
                    "Fresh side-reorg restore exposed wrong-chain raw transaction")
                   (devnet-smoke-gate-require
                    (null fresh-pending-transaction)
                    "Fresh side-reorg restore exposed wrong-chain pending transaction")))
               (devnet-smoke-gate-require
                (null (fixture-object-field fresh-receipt-rpc "result"))
                "Fresh side-reorg restore kept old canonical receipt")
               (loop for item in extra-transaction-items
                     for rpc in fresh-extra-receipt-rpcs
                     do
                        (devnet-smoke-gate-require
                         (null (fixture-object-field rpc "result"))
                         "Fresh side-reorg restore kept displaced canonical receipt ~S"
                         (getf item :hash-hex)))
               (devnet-smoke-gate-require
                (string= expected-side-block-number
                         (fixture-object-field fresh-block-number-rpc
                                               "result"))
                "Fresh side-reorg restore public block number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex side-block-hash)
                         (fixture-object-field fresh-latest-block "hash"))
                "Fresh side-reorg restore latest block hash mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex child-block-hash)
                         (fixture-object-field fresh-child-block "hash"))
                "Fresh side-reorg restore lost old child block hash lookup")
               (devnet-smoke-gate-require
                (equal (devnet-smoke-gate-noncanonical-state-error-messages)
                       fresh-child-require-canonical-state-errors)
                "Fresh side-reorg restore child requireCanonical state errors mismatch")
               (devnet-smoke-gate-require
                (zerop (length fresh-block-receipts))
                "Fresh side-reorg restore kept canonical receipts")
               (devnet-smoke-gate-require
                (zerop (length fresh-logs))
                "Fresh side-reorg restore kept canonical logs")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (fixture-object-field fresh-safe-block "hash"))
                "Fresh side-reorg restore safe block hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (fixture-object-field fresh-safe-block "number"))
                "Fresh side-reorg restore safe block number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (fixture-object-field fresh-finalized-block "hash"))
                "Fresh side-reorg restore finalized block hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (fixture-object-field fresh-finalized-block "number"))
                "Fresh side-reorg restore finalized block number mismatch")
               (devnet-smoke-gate-require
                (string= expected-checkpoint-balance fresh-safe-balance)
                "Fresh side-reorg restore safe balance mismatch")
               (devnet-smoke-gate-require
                (string= expected-checkpoint-balance
                         fresh-finalized-balance)
                "Fresh side-reorg restore finalized balance mismatch")
               (list :side-block-hash (hash32-to-hex side-block-hash)
                     :side-forkchoice-status
                     (fixture-object-field side-forkchoice-status "status")
                     :side-rejected-checkpoint-error
                     (fixture-object-field side-rejected-forkchoice-error
                                           "message")
                     :side-block-number
                     (fixture-object-field side-block-number-rpc "result")
                     :side-latest-block-hash
                     (fixture-object-field side-latest-block "hash")
                     :side-transaction-reinserted-p
                     (if reinsertable-transaction-p t :false)
                     :side-transaction-by-hash
                     (or side-transaction :false)
                     :side-raw-transaction
                     (or side-raw-transaction :false)
                     :side-pending-transaction
                     (or side-pending-transaction :false)
                     :side-reinserted-transaction-count
                     (if reinsertable-transaction-p
                         (length reinsertable-transaction-items)
                         :false)
                     :side-reinserted-transaction-hashes
                     (if reinsertable-transaction-p
                         reinsertable-transaction-hashes
                         :false)
                     :side-receipt
                     (or (fixture-object-field side-receipt-rpc "result")
                         :false)
                     :side-hidden-receipt-count
                     side-hidden-receipt-count
	                     :side-child-block-hash
	                     (fixture-object-field child-block-by-hash "hash")
                             :side-block-receipts-count
                             (length side-block-receipts)
                             :side-log-count
                             (length side-logs)
	                     :side-restored-head-number
                     (quantity-to-hex (getf fresh-summary :head-number))
                     :side-restored-head-hash
                     (getf fresh-summary :head-hash)
                     :side-restored-rpc-block-number
                     (fixture-object-field fresh-block-number-rpc "result")
                     :side-restored-rpc-latest-block-hash
                     (fixture-object-field fresh-latest-block "hash")
                     :side-restored-safe-number
                     (quantity-to-hex (getf fresh-summary :safe-number))
                     :side-restored-safe-hash
                     (getf fresh-summary :safe-hash)
                     :side-restored-finalized-number
                     (quantity-to-hex
                      (getf fresh-summary :finalized-number))
                     :side-restored-finalized-hash
                     (getf fresh-summary :finalized-hash)
                     :side-restored-rpc-safe-number
                     (fixture-object-field fresh-safe-block "number")
                     :side-restored-rpc-safe-hash
                     (fixture-object-field fresh-safe-block "hash")
                     :side-restored-rpc-finalized-number
                     (fixture-object-field fresh-finalized-block "number")
                     :side-restored-rpc-finalized-hash
                     (fixture-object-field fresh-finalized-block "hash")
                     :side-restored-safe-balance
                     fresh-safe-balance
                     :side-restored-finalized-balance
                     fresh-finalized-balance
                     :side-restored-raw-transaction
                     (or fresh-raw-transaction :false)
                     :side-restored-pending-transaction
                     (or fresh-pending-transaction :false)
                     :side-restored-reinserted-transaction-count
                     (if reinsertable-transaction-p
                         (length reinsertable-transaction-items)
                         :false)
                     :side-restored-reinserted-transaction-hashes
                     (if reinsertable-transaction-p
                         reinsertable-transaction-hashes
                         :false)
                     :side-restored-receipt
                     (or (fixture-object-field fresh-receipt-rpc "result")
                         :false)
                     :side-restored-hidden-receipt-count
                     fresh-hidden-receipt-count
                     :side-restored-child-block-hash
                     (fixture-object-field fresh-child-block "hash")
                     :side-restored-child-require-canonical-error
                     (first fresh-child-require-canonical-state-errors)
                     :side-restored-child-require-canonical-errors
                     fresh-child-require-canonical-state-errors
                     :side-restored-block-receipts-count
                     (length fresh-block-receipts)
                     :side-restored-log-count
                     (length fresh-logs)
                     :side-restored-public-connections
                     (getf fresh-rpc-summary :public-connections)
                     :engine-connections (getf summary :engine-connections)
                     :public-connections
                     (getf summary :public-connections)))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (declare (ignore path side-payload side-block child-block transaction-checks
                   balance-targets expected-safe-block-hash sender-address
                   code-address storage-address storage-key config))
  #-sbcl
  (error "Restored devnet side reorg RPC verification requires SBCL threads"))

