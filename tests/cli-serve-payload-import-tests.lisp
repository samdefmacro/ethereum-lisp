(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-serve-mode-imports-payload-and-serves-public-state
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload" "jwt"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload-genesis" "json"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-payload" "pid"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-log-contract-call-with-withdrawal"))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (side-sibling-block
                  (devnet-cli-engine-fixture-side-sibling-block
                   case parent-block))
                (remote-block (devnet-cli-remote-block child-block))
                (invalid-block (devnet-cli-invalid-child-block child-block))
                (payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
                (side-sibling-payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data side-sibling-block)))
                (remote-payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data remote-block)))
                (invalid-payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data invalid-block)))
                (parent (fixture-object-field case "parent"))
                (payload-case (fixture-object-field case "payload"))
                (expect (fixture-object-field case "expect"))
                (recipient (fixture-address-field expect "recipient"))
                (sender (fixture-address-field expect "sender"))
                (code-address (fixture-address-field expect "codeAddress"))
                (storage-address
                  (fixture-address-field expect "storageAddress"))
                (transaction
                  (first (block-transactions child-block)))
                (block-hash-hex
                  (hash32-to-hex (block-hash child-block)))
                (side-sibling-block-hash-hex
                  (hash32-to-hex (block-hash side-sibling-block)))
                (transaction-hash-hex
                  (hash32-to-hex
                   (transaction-hash transaction)))
                (raw-transaction-hex
                  (devnet-cli-transaction-raw transaction))
                (expected-transaction-count-hex
                  (quantity-to-hex (length (block-transactions child-block))))
                (simulation-call-object
                  (list (cons "from" (address-to-hex sender))
                        (cons "to" (address-to-hex code-address))
                        (cons "gas" "0x186a0")
                        (cons "gasPrice" "0x64")
                        (cons "data" "0x")))
                (prepare-payload-attributes
                  (devnet-cli-payload-attributes-v2
                   child-block
                   (block-header-beneficiary (block-header child-block))))
                (new-payload-body
                  (json-encode (engine-fixture-payload-request 601 payload)))
                (remote-payload-body
                  (json-encode
                   (engine-fixture-payload-request 613 remote-payload)))
                (invalid-payload-body
                  (json-encode
                   (engine-fixture-payload-request 614 invalid-payload)))
                (side-sibling-payload-body
                  (json-encode
                   (engine-fixture-payload-request 647
                                                   side-sibling-payload)))
                (forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    602 (block-hash child-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (side-sibling-forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    648 (block-hash side-sibling-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (payload-bodies-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 609)
                         (cons "method" "engine_getPayloadBodiesByHashV1")
                         (cons "params"
                               (list
                                (vector
                                 (hash32-to-hex
                                  (block-hash child-block))))))))
                (payload-bodies-by-range-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 610)
                         (cons "method" "engine_getPayloadBodiesByRangeV1")
                         (cons "params"
                               (list
                                (fixture-object-field payload-case "number")
                                "0x1")))))
                (prepare-payload-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-payload-attributes-request
                    605
                    (block-hash child-block)
                    prepare-payload-attributes
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 603)
                         (cons "method" "eth_blockNumber")
                         (cons "params" #()))))
                (post-status-block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 615)
                         (cons "method" "eth_blockNumber")
                         (cons "params" #()))))
                (balance-body
                  (json-encode (engine-fixture-balance-request
                                604 recipient)))
                (safe-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 622)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list (address-to-hex recipient) "safe")))))
                (finalized-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 623)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list (address-to-hex recipient)
                                     "finalized")))))
                (proof-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 633)
                         (cons "method" "eth_getProof")
                         (cons "params"
                               (list (address-to-hex storage-address)
                                     (list (fixture-object-field expect
                                                                 "storageKey"))
                                     "latest")))))
                (block-hash-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 634)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list
                                (address-to-hex recipient)
                                (list (cons "blockHash" block-hash-hex)))))))
                (require-canonical-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 635)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list
                                (address-to-hex recipient)
                                (list (cons "blockHash" block-hash-hex)
                                      (cons "requireCanonical" t)))))))
                (transaction-count-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 607)
                         (cons "method" "eth_getTransactionCount")
                         (cons "params"
                               (list (address-to-hex sender)
                                     "latest")))))
                (block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 608)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" :false)))))
                (block-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 624)
                         (cons "method" "eth_getBlockByHash")
                         (cons "params" (list block-hash-hex :false)))))
                (full-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 640)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" t)))))
                (full-block-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 641)
                         (cons "method" "eth_getBlockByHash")
                         (cons "params" (list block-hash-hex t)))))
                (block-transaction-count-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 625)
                         (cons "method"
                               "eth_getBlockTransactionCountByHash")
                         (cons "params" (list block-hash-hex)))))
                (block-transaction-count-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 626)
                         (cons "method"
                               "eth_getBlockTransactionCountByNumber")
                         (cons "params"
                               (list (fixture-object-field payload-case
                                                           "number"))))))
                (transaction-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 627)
                         (cons "method" "eth_getTransactionByHash")
                         (cons "params" (list transaction-hash-hex)))))
                (transaction-by-block-hash-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 628)
                         (cons "method"
                               "eth_getTransactionByBlockHashAndIndex")
                         (cons "params" (list block-hash-hex "0x0")))))
                (transaction-by-block-number-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 629)
                         (cons "method"
                               "eth_getTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list (fixture-object-field payload-case
                                                           "number")
                                     "0x0")))))
                (raw-transaction-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 630)
                         (cons "method" "eth_getRawTransactionByHash")
                         (cons "params" (list transaction-hash-hex)))))
                (raw-transaction-by-block-hash-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 631)
                         (cons "method"
                               "eth_getRawTransactionByBlockHashAndIndex")
                         (cons "params" (list block-hash-hex "0x0")))))
                (raw-transaction-by-block-number-and-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 632)
                         (cons "method"
                               "eth_getRawTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list (fixture-object-field payload-case
                                                           "number")
                                     "0x0")))))
                (safe-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 620)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "safe" :false)))))
                (finalized-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 621)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "finalized" :false)))))
                (post-status-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 616)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" :false)))))
                (code-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 611)
                         (cons "method" "eth_getCode")
                         (cons "params"
                               (list (address-to-hex code-address)
                                     "latest")))))
                (storage-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 612)
                         (cons "method" "eth_getStorageAt")
                         (cons "params"
                               (list (address-to-hex storage-address)
                                     (fixture-object-field expect
                                                           "storageKey")
                                     "latest")))))
                (call-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 636)
                         (cons "method" "eth_call")
                         (cons "params"
                               (list simulation-call-object "latest")))))
                (estimate-gas-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 637)
                         (cons "method" "eth_estimateGas")
                         (cons "params"
                               (list simulation-call-object "latest")))))
                (create-access-list-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 638)
                         (cons "method" "eth_createAccessList")
                         (cons "params"
                               (list simulation-call-object "latest")))))
                (post-call-storage-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 639)
                         (cons "method" "eth_getStorageAt")
                         (cons "params"
                               (list (address-to-hex storage-address)
                                     (fixture-object-field expect
                                                           "storageKey")
                                     "latest")))))
                (receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 617)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex)))))
                (block-receipts-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 618)
                         (cons "method" "eth_getBlockReceipts")
                         (cons "params" (list "latest")))))
                (logs-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 619)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" "latest")
                                 (cons "toBlock" "latest")
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (logs-by-block-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 642)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "blockHash" block-hash-hex)
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (new-log-filter-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 645)
                         (cons "method" "eth_newFilter")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" "latest")
                                 (cons "toBlock" "latest")
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (new-block-filter-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 643)
                         (cons "method" "eth_newBlockFilter")
                         (cons "params" #()))))
                (post-reorg-block-by-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 651)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "latest" :false)))))
                (post-reorg-transaction-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 652)
                         (cons "method" "eth_getTransactionByHash")
                         (cons "params" (list transaction-hash-hex)))))
                (post-reorg-receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 653)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex)))))
                (post-reorg-logs-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 654)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" "latest")
                                 (cons "toBlock" "latest")
                                 (cons "address"
                                       (fixture-object-field expect
                                                             "logAddress"))
                                 (cons "topics"
                                       (list
                                        (fixture-object-field
                                         expect "logTopic")))))))))
                (post-reorg-pending-block-count-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 655)
                         (cons "method"
                               "eth_getBlockTransactionCountByNumber")
                         (cons "params" (list "pending")))))
                (post-reorg-pending-transaction-by-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 656)
                         (cons "method"
                               "eth_getTransactionByBlockNumberAndIndex")
                         (cons "params" (list "pending" "0x0")))))
                (post-reorg-pending-raw-transaction-by-index-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 657)
                         (cons "method"
                               "eth_getRawTransactionByBlockNumberAndIndex")
                         (cons "params" (list "pending" "0x0")))))
                (post-reorg-pending-block-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 658)
                         (cons "method" "eth_getBlockByNumber")
                         (cons "params" (list "pending" t)))))
                (post-reorg-pending-header-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 659)
                         (cons "method" "eth_getHeaderByNumber")
                         (cons "params" (list "pending")))))
                (post-reorg-pending-sender-nonce-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 660)
                         (cons "method" "eth_getTransactionCount")
                         (cons "params"
                               (list (address-to-hex sender)
                                     "pending"))))))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :public-port 0))
                  (script-genesis
                    (ethereum-lisp.cli::devnet-node-genesis-block node)))
             (is (string= (hash32-to-hex (block-hash parent-block))
                          (hash32-to-hex (block-hash script-genesis))))
             (is (= (fixture-quantity-field payload-case "number")
                    (1+ (block-header-number
                         (block-header script-genesis))))))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf process
                 (test-launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        (namestring genesis-path)
                        "--engine-port"
                        "0"
                        "--public-port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "50"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret (unix-time)))
                    new-block-filter-response
                    new-log-filter-response
                    new-payload-response
                    forkchoice-response
                    payload-bodies-by-hash-response
                    payload-bodies-by-range-response
                    prepare-payload-response
                    get-payload-response
                    remote-payload-response
                    invalid-payload-response
                    side-sibling-payload-response
                    side-sibling-forkchoice-response
                    block-number-response
                    post-status-block-number-response
                    balance-response
                    safe-balance-response
                    finalized-balance-response
                    proof-response
                    block-hash-balance-response
                    require-canonical-balance-response
                    transaction-count-response
                    block-by-number-response
                    block-by-hash-response
                    full-block-by-number-response
                    full-block-by-hash-response
                    block-transaction-count-by-hash-response
                    block-transaction-count-by-number-response
                    transaction-by-hash-response
                    transaction-by-block-hash-and-index-response
                    transaction-by-block-number-and-index-response
                    raw-transaction-by-hash-response
                    raw-transaction-by-block-hash-and-index-response
                    raw-transaction-by-block-number-and-index-response
                    safe-block-by-number-response
                    finalized-block-by-number-response
                    post-status-block-by-number-response
                    code-response
                    storage-response
                    call-response
                    estimate-gas-response
                    create-access-list-response
                    post-call-storage-response
                    receipt-response
                    block-receipts-response
                    logs-response
                    logs-by-block-hash-response
                    block-filter-changes-response
                    log-filter-changes-response
                    post-reorg-block-filter-changes-response
                    post-reorg-log-filter-changes-response
                    post-reorg-block-by-number-response
                    post-reorg-transaction-by-hash-response
                    post-reorg-receipt-response
                    post-reorg-logs-response
                    post-reorg-pending-block-count-response
                    post-reorg-pending-transaction-by-index-response
                    post-reorg-pending-raw-transaction-by-index-response
                    post-reorg-pending-block-response
                    post-reorg-pending-header-response
                    post-reorg-pending-sender-nonce-response
                    block-filter-id
                    log-filter-id)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (handler-case
                   (progn
                     (setf new-block-filter-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-block-filter-body)))
                     (setf new-log-filter-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-log-filter-body)))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token)))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token)))
                     (setf payload-bodies-by-hash-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             payload-bodies-by-hash-body
                             :token token)))
                     (setf payload-bodies-by-range-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             payload-bodies-by-range-body
                             :token token)))
                     (setf prepare-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             prepare-payload-body
                             :token token)))
                     (let* ((prepare-payload-rpc
                              (parse-json
                               (devnet-cli-http-body
                                prepare-payload-response)))
                            (prepare-payload-result
                              (fixture-object-field
                               prepare-payload-rpc "result"))
                            (prepared-payload-id
                              (fixture-object-field
                               prepare-payload-result "payloadId"))
                            (get-payload-body
                              (json-encode
                               (list
                                (cons "jsonrpc" "2.0")
                                (cons "id" 606)
                                (cons "method" "engine_getPayloadV2")
                                (cons "params"
                                      (list prepared-payload-id))))))
                       (setf get-payload-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               get-payload-body
                               :token token))))
                     (setf remote-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             remote-payload-body
                             :token token)))
                     (setf invalid-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             invalid-payload-body
                             :token token)))
                     (setf block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-number-body)))
                     (setf balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             balance-body)))
                     (setf safe-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             safe-balance-body)))
                     (setf finalized-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             finalized-balance-body)))
                     (setf proof-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             proof-body)))
                     (setf block-hash-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-hash-balance-body)))
                     (setf require-canonical-balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             require-canonical-balance-body)))
                     (setf transaction-count-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-count-body)))
                     (setf block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-by-number-body)))
                     (setf block-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-by-hash-body)))
                     (setf full-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             full-block-by-number-body)))
                     (setf full-block-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             full-block-by-hash-body)))
                     (setf block-transaction-count-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-transaction-count-by-hash-body)))
                     (setf block-transaction-count-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-transaction-count-by-number-body)))
                     (setf transaction-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-by-hash-body)))
                     (setf transaction-by-block-hash-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-by-block-hash-and-index-body)))
                     (setf transaction-by-block-number-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             transaction-by-block-number-and-index-body)))
                     (setf raw-transaction-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             raw-transaction-by-hash-body)))
                     (setf raw-transaction-by-block-hash-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             raw-transaction-by-block-hash-and-index-body)))
                     (setf raw-transaction-by-block-number-and-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             raw-transaction-by-block-number-and-index-body)))
                     (setf safe-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             safe-block-by-number-body)))
                     (setf finalized-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             finalized-block-by-number-body)))
                     (setf code-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             code-body)))
                     (setf storage-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             storage-body)))
                     (setf call-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             call-body)))
                     (setf estimate-gas-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             estimate-gas-body)))
                     (setf create-access-list-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             create-access-list-body)))
                     (setf post-call-storage-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-call-storage-body)))
                     (setf receipt-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             receipt-body)))
                     (setf block-receipts-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-receipts-body)))
                     (setf logs-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             logs-body)))
                     (setf logs-by-block-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             logs-by-block-hash-body)))
                     (let* ((new-block-filter-rpc
                              (parse-json
                               (devnet-cli-http-body
                                new-block-filter-response))))
                       (setf block-filter-id
                             (fixture-object-field
                              new-block-filter-rpc "result"))
                       (let ((block-filter-changes-body
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 644)
                                 (cons "method" "eth_getFilterChanges")
                                 (cons "params"
                                       (list block-filter-id))))))
                       (setf block-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-filter-changes-body)))))
                     (let* ((new-log-filter-rpc
                              (parse-json
                               (devnet-cli-http-body
                                new-log-filter-response))))
                       (setf log-filter-id
                             (fixture-object-field
                              new-log-filter-rpc "result"))
                       (let ((log-filter-changes-body
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 646)
                                 (cons "method" "eth_getFilterChanges")
                                 (cons "params"
                                       (list log-filter-id))))))
                       (setf log-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               log-filter-changes-body)))))
                     (setf post-status-block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-status-block-number-body)))
                     (setf post-status-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-status-block-by-number-body)))
                     (setf side-sibling-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             side-sibling-payload-body
                             :token token)))
                     (setf side-sibling-forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             side-sibling-forkchoice-body
                             :token token)))
                     (setf post-reorg-block-by-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-block-by-number-body)))
                     (setf post-reorg-transaction-by-hash-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-transaction-by-hash-body)))
                     (setf post-reorg-receipt-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-receipt-body)))
                     (setf post-reorg-logs-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-logs-body)))
                     (setf post-reorg-pending-block-count-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-block-count-body)))
                     (setf post-reorg-pending-transaction-by-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-transaction-by-index-body)))
                     (setf post-reorg-pending-raw-transaction-by-index-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-raw-transaction-by-index-body)))
                     (setf post-reorg-pending-block-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-block-body)))
                     (setf post-reorg-pending-header-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-header-body)))
                     (setf post-reorg-pending-sender-nonce-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             post-reorg-pending-sender-nonce-body)))
                     (let ((post-reorg-block-filter-changes-body
                             (json-encode
                              (list
                               (cons "jsonrpc" "2.0")
                               (cons "id" 649)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list block-filter-id))))))
                       (setf post-reorg-block-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               post-reorg-block-filter-changes-body))))
                     (let ((post-reorg-log-filter-changes-body
                             (json-encode
                              (list
                               (cons "jsonrpc" "2.0")
                               (cons "id" 650)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list log-filter-id))))))
                       (setf post-reorg-log-filter-changes-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               post-reorg-log-filter-changes-body)))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                               "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status new-block-filter-response)))
               (is (= 200 (devnet-cli-http-status new-log-filter-response)))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (is (= 200 (devnet-cli-http-status forkchoice-response)))
               (is (= 200 (devnet-cli-http-status
                            payload-bodies-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            payload-bodies-by-range-response)))
               (is (= 200 (devnet-cli-http-status prepare-payload-response)))
               (is (= 200 (devnet-cli-http-status get-payload-response)))
               (is (= 200 (devnet-cli-http-status remote-payload-response)))
               (is (= 200 (devnet-cli-http-status invalid-payload-response)))
               (is (= 200 (devnet-cli-http-status
                            side-sibling-payload-response)))
               (is (= 200 (devnet-cli-http-status
                            side-sibling-forkchoice-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-transaction-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-receipt-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-logs-response)))
               (is (= 200 (devnet-cli-http-status block-number-response)))
               (is (= 200 (devnet-cli-http-status
                            post-status-block-number-response)))
               (is (= 200 (devnet-cli-http-status balance-response)))
               (is (= 200 (devnet-cli-http-status safe-balance-response)))
               (is (= 200 (devnet-cli-http-status finalized-balance-response)))
               (is (= 200 (devnet-cli-http-status proof-response)))
               (is (= 200 (devnet-cli-http-status
                            block-hash-balance-response)))
               (is (= 200 (devnet-cli-http-status
                            require-canonical-balance-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-count-response)))
               (is (= 200 (devnet-cli-http-status
                            block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            block-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            full-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            full-block-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            block-transaction-count-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            block-transaction-count-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-by-block-hash-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            transaction-by-block-number-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            raw-transaction-by-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            raw-transaction-by-block-hash-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            raw-transaction-by-block-number-and-index-response)))
               (is (= 200 (devnet-cli-http-status
                            safe-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            finalized-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status
                            post-status-block-by-number-response)))
               (is (= 200 (devnet-cli-http-status code-response)))
               (is (= 200 (devnet-cli-http-status storage-response)))
               (is (= 200 (devnet-cli-http-status call-response)))
               (is (= 200 (devnet-cli-http-status estimate-gas-response)))
               (is (= 200 (devnet-cli-http-status
                            create-access-list-response)))
               (is (= 200 (devnet-cli-http-status
                            post-call-storage-response)))
               (is (= 200 (devnet-cli-http-status receipt-response)))
               (is (= 200 (devnet-cli-http-status block-receipts-response)))
               (is (= 200 (devnet-cli-http-status logs-response)))
               (is (= 200 (devnet-cli-http-status
                            logs-by-block-hash-response)))
               (is (= 200 (devnet-cli-http-status
                            block-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            log-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-block-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-log-filter-changes-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-block-count-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-transaction-by-index-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-raw-transaction-by-index-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-block-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-header-response)))
               (is (= 200 (devnet-cli-http-status
                            post-reorg-pending-sender-nonce-response)))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-block-filter-rpc
                        (parse-json
                         (devnet-cli-http-body
                          new-block-filter-response)))
                      (new-log-filter-rpc
                        (parse-json
                         (devnet-cli-http-body
                          new-log-filter-response)))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (payload-bodies-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          payload-bodies-by-hash-response)))
                      (payload-bodies-by-range-rpc
                        (parse-json
                         (devnet-cli-http-body
                          payload-bodies-by-range-response)))
                      (prepare-payload-rpc
                        (parse-json
                         (devnet-cli-http-body prepare-payload-response)))
                      (get-payload-rpc
                        (parse-json
                         (devnet-cli-http-body get-payload-response)))
                      (remote-payload-rpc
                        (parse-json
                         (devnet-cli-http-body remote-payload-response)))
                      (invalid-payload-rpc
                        (parse-json
                         (devnet-cli-http-body invalid-payload-response)))
                      (side-sibling-payload-rpc
                        (parse-json
                         (devnet-cli-http-body
                          side-sibling-payload-response)))
                      (side-sibling-forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body
                          side-sibling-forkchoice-response)))
                      (post-reorg-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-block-by-number-response)))
                      (post-reorg-transaction-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-transaction-by-hash-response)))
                      (post-reorg-receipt-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-receipt-response)))
                      (post-reorg-logs-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-logs-response)))
                      (post-reorg-pending-block-count-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-block-count-response)))
                      (post-reorg-pending-transaction-by-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-transaction-by-index-response)))
                      (post-reorg-pending-raw-transaction-by-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-raw-transaction-by-index-response)))
                      (post-reorg-pending-block-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-block-response)))
                      (post-reorg-pending-header-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-header-response)))
                      (post-reorg-pending-sender-nonce-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-pending-sender-nonce-response)))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (post-status-block-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-status-block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (safe-balance-rpc
                        (parse-json
                         (devnet-cli-http-body safe-balance-response)))
                      (finalized-balance-rpc
                        (parse-json
                         (devnet-cli-http-body finalized-balance-response)))
                      (proof-rpc
                        (parse-json
                         (devnet-cli-http-body proof-response)))
                      (block-hash-balance-rpc
                        (parse-json
                         (devnet-cli-http-body block-hash-balance-response)))
                      (require-canonical-balance-rpc
                        (parse-json
                         (devnet-cli-http-body
                          require-canonical-balance-response)))
                      (transaction-count-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-count-response)))
                      (block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-by-number-response)))
                      (block-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-by-hash-response)))
                      (full-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          full-block-by-number-response)))
                      (full-block-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          full-block-by-hash-response)))
                      (block-transaction-count-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-transaction-count-by-hash-response)))
                      (block-transaction-count-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-transaction-count-by-number-response)))
                      (transaction-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-by-hash-response)))
                      (transaction-by-block-hash-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-by-block-hash-and-index-response)))
                      (transaction-by-block-number-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transaction-by-block-number-and-index-response)))
                      (raw-transaction-by-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          raw-transaction-by-hash-response)))
                      (raw-transaction-by-block-hash-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          raw-transaction-by-block-hash-and-index-response)))
                      (raw-transaction-by-block-number-and-index-rpc
                        (parse-json
                         (devnet-cli-http-body
                          raw-transaction-by-block-number-and-index-response)))
                      (safe-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          safe-block-by-number-response)))
                      (finalized-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          finalized-block-by-number-response)))
                      (post-status-block-by-number-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-status-block-by-number-response)))
                      (code-rpc
                        (parse-json
                         (devnet-cli-http-body code-response)))
                      (storage-rpc
                        (parse-json
                         (devnet-cli-http-body storage-response)))
                      (call-rpc
                        (parse-json
                         (devnet-cli-http-body call-response)))
                      (estimate-gas-rpc
                        (parse-json
                         (devnet-cli-http-body estimate-gas-response)))
                      (create-access-list-rpc
                        (parse-json
                         (devnet-cli-http-body
                          create-access-list-response)))
                      (post-call-storage-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-call-storage-response)))
                      (receipt-rpc
                        (parse-json
                         (devnet-cli-http-body receipt-response)))
                      (block-receipts-rpc
                        (parse-json
                         (devnet-cli-http-body block-receipts-response)))
                      (logs-rpc
                        (parse-json
                         (devnet-cli-http-body logs-response)))
                      (logs-by-block-hash-rpc
                        (parse-json
                         (devnet-cli-http-body
                          logs-by-block-hash-response)))
                      (block-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          block-filter-changes-response)))
                      (block-filter-changes
                        (fixture-object-field block-filter-changes-rpc
                                              "result"))
                      (log-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          log-filter-changes-response)))
                      (log-filter-changes
                        (fixture-object-field log-filter-changes-rpc
                                              "result"))
                      (log-filter-change-log (first log-filter-changes))
                      (post-reorg-block-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-block-filter-changes-response)))
                      (post-reorg-block-filter-changes
                        (fixture-object-field
                         post-reorg-block-filter-changes-rpc
                         "result"))
                      (post-reorg-log-filter-changes-rpc
                        (parse-json
                         (devnet-cli-http-body
                          post-reorg-log-filter-changes-response)))
                      (post-reorg-log-filter-changes
                        (fixture-object-field
                         post-reorg-log-filter-changes-rpc
                         "result"))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (side-sibling-payload-result
                        (fixture-object-field
                         side-sibling-payload-rpc "result"))
                      (side-sibling-forkchoice-status
                        (fixture-object-field
                         (fixture-object-field
                          side-sibling-forkchoice-rpc "result")
                         "payloadStatus"))
                      (post-reorg-block-by-number-result
                        (fixture-object-field
                         post-reorg-block-by-number-rpc "result"))
                      (post-reorg-transaction-by-hash-result
                        (fixture-object-field
                         post-reorg-transaction-by-hash-rpc "result"))
                      (post-reorg-logs
                        (fixture-object-field post-reorg-logs-rpc "result"))
                      (post-reorg-pending-block-count
                        (fixture-object-field
                         post-reorg-pending-block-count-rpc "result"))
                      (post-reorg-pending-transaction-by-index
                        (fixture-object-field
                         post-reorg-pending-transaction-by-index-rpc
                         "result"))
                      (post-reorg-pending-raw-transaction-by-index
                        (fixture-object-field
                         post-reorg-pending-raw-transaction-by-index-rpc
                         "result"))
                      (post-reorg-pending-block
                        (fixture-object-field
                         post-reorg-pending-block-rpc "result"))
                      (post-reorg-pending-header
                        (fixture-object-field
                         post-reorg-pending-header-rpc "result"))
                      (post-reorg-pending-sender-nonce
                        (fixture-object-field
                         post-reorg-pending-sender-nonce-rpc "result"))
                      (post-reorg-pending-block-transactions
                        (fixture-object-field
                         post-reorg-pending-block "transactions"))
                      (post-reorg-pending-block-transaction
                        (first post-reorg-pending-block-transactions))
                      (payload-bodies-by-hash-result
                        (fixture-object-field
                         payload-bodies-by-hash-rpc "result"))
                      (payload-bodies-by-range-result
                        (fixture-object-field
                         payload-bodies-by-range-rpc "result"))
                      (payload-body-by-hash-transactions
                        (fixture-object-field
                         (first payload-bodies-by-hash-result)
                         "transactions"))
                      (payload-body-by-range-transactions
                        (fixture-object-field
                         (first payload-bodies-by-range-result)
                         "transactions"))
                      (expected-payload-body-transaction-count
                        (length (block-transactions child-block)))
                      (prepare-payload-result
                        (fixture-object-field prepare-payload-rpc "result"))
                      (prepare-payload-status
                        (fixture-object-field
                         prepare-payload-result
                         "payloadStatus"))
                      (prepared-payload-id
                        (fixture-object-field
                         prepare-payload-result "payloadId"))
                      (get-payload-result
                        (fixture-object-field get-payload-rpc "result"))
                      (get-payload-execution-payload
                        (fixture-object-field
                         get-payload-result
                         "executionPayload"))
                      (get-payload-transactions
                        (fixture-object-field
                         get-payload-execution-payload
                         "transactions"))
                      (remote-payload-result
                        (fixture-object-field remote-payload-rpc "result"))
                      (invalid-payload-result
                        (fixture-object-field invalid-payload-rpc "result"))
                      (block-by-number-result
                        (fixture-object-field block-by-number-rpc "result"))
                      (block-by-hash-result
                        (fixture-object-field block-by-hash-rpc "result"))
                      (full-block-by-number-result
                        (fixture-object-field full-block-by-number-rpc
                                              "result"))
                      (full-block-by-hash-result
                        (fixture-object-field full-block-by-hash-rpc
                                              "result"))
                      (full-block-by-number-transactions
                        (fixture-object-field full-block-by-number-result
                                              "transactions"))
                      (full-block-by-hash-transactions
                        (fixture-object-field full-block-by-hash-result
                                              "transactions"))
                      (full-block-by-number-transaction
                        (first full-block-by-number-transactions))
                      (full-block-by-hash-transaction
                        (first full-block-by-hash-transactions))
                      (transaction-by-hash-result
                        (fixture-object-field transaction-by-hash-rpc
                                              "result"))
                      (transaction-by-block-hash-and-index-result
                        (fixture-object-field
                         transaction-by-block-hash-and-index-rpc "result"))
                      (transaction-by-block-number-and-index-result
                        (fixture-object-field
                         transaction-by-block-number-and-index-rpc "result"))
                      (proof-result
                        (fixture-object-field proof-rpc "result"))
                      (proof-storage
                        (first (fixture-object-field proof-result
                                                     "storageProof")))
                      (create-access-list-result
                        (fixture-object-field create-access-list-rpc
                                              "result"))
                      (actual-access-list
                        (fixture-object-field create-access-list-result
                                              "accessList"))
                      (actual-access-list-gas-used
                        (fixture-object-field create-access-list-result
                                              "gasUsed"))
                      (actual-access-list-entry
                        (find (address-to-hex storage-address)
                              actual-access-list
                              :test #'string=
                              :key (lambda (entry)
                                     (fixture-object-field entry "address"))))
                      (actual-access-list-storage-keys
                        (and actual-access-list-entry
                             (fixture-object-field actual-access-list-entry
                                                   "storageKeys")))
                      (safe-block-by-number-result
                        (fixture-object-field safe-block-by-number-rpc
                                              "result"))
                      (finalized-block-by-number-result
                        (fixture-object-field finalized-block-by-number-rpc
                                              "result"))
                      (post-status-block-by-number-result
                        (fixture-object-field post-status-block-by-number-rpc
                                              "result"))
                      (receipt
                        (fixture-object-field receipt-rpc "result"))
                      (receipt-logs
                        (fixture-object-field receipt "logs"))
                      (receipt-log (first receipt-logs))
                      (block-receipts
                        (fixture-object-field block-receipts-rpc "result"))
                      (block-receipt (first block-receipts))
                      (block-receipt-logs
                        (fixture-object-field block-receipt "logs"))
                      (block-receipt-log (first block-receipt-logs))
                      (filtered-logs
                        (fixture-object-field logs-rpc "result"))
                      (filtered-log (first filtered-logs))
                      (block-hash-filtered-logs
                        (fixture-object-field logs-by-block-hash-rpc
                                              "result"))
                      (block-hash-filtered-log
                        (first block-hash-filtered-logs))
                      (expected-prepared-block-number
                        (quantity-to-hex
                         (1+ (block-header-number
                              (block-header child-block)))))
                      (expected-post-reorg-pending-block-number
                        (quantity-to-hex
                         (1+ (block-header-number
                              (block-header side-sibling-block))))))
                 (is (= 601 (fixture-object-field new-payload-rpc "id")))
                 (is (= 602 (fixture-object-field forkchoice-rpc "id")))
                 (is (= 603 (fixture-object-field block-number-rpc "id")))
                 (is (= 604 (fixture-object-field balance-rpc "id")))
                 (is (= 605 (fixture-object-field prepare-payload-rpc "id")))
                 (is (= 606 (fixture-object-field get-payload-rpc "id")))
                 (is (= 607 (fixture-object-field
                              transaction-count-rpc "id")))
                 (is (= 608 (fixture-object-field block-by-number-rpc "id")))
                 (is (= 609 (fixture-object-field
                              payload-bodies-by-hash-rpc "id")))
                 (is (= 610 (fixture-object-field
                              payload-bodies-by-range-rpc "id")))
                 (is (= 611 (fixture-object-field code-rpc "id")))
                 (is (= 612 (fixture-object-field storage-rpc "id")))
                 (is (= 613 (fixture-object-field remote-payload-rpc "id")))
                 (is (= 614 (fixture-object-field invalid-payload-rpc "id")))
                 (is (= 647 (fixture-object-field
                              side-sibling-payload-rpc "id")))
                 (is (= 648 (fixture-object-field
                              side-sibling-forkchoice-rpc "id")))
                 (is (= 651 (fixture-object-field
                              post-reorg-block-by-number-rpc "id")))
                 (is (= 652 (fixture-object-field
                              post-reorg-transaction-by-hash-rpc "id")))
                 (is (= 653 (fixture-object-field
                              post-reorg-receipt-rpc "id")))
                 (is (= 654 (fixture-object-field
                              post-reorg-logs-rpc "id")))
                 (is (= 655 (fixture-object-field
                              post-reorg-pending-block-count-rpc "id")))
                 (is (= 656
                        (fixture-object-field
                         post-reorg-pending-transaction-by-index-rpc "id")))
                 (is (= 657
                        (fixture-object-field
                         post-reorg-pending-raw-transaction-by-index-rpc
                         "id")))
                 (is (= 658 (fixture-object-field
                              post-reorg-pending-block-rpc "id")))
                 (is (= 659 (fixture-object-field
                              post-reorg-pending-header-rpc "id")))
                 (is (= 660 (fixture-object-field
                              post-reorg-pending-sender-nonce-rpc "id")))
                 (is (= 615 (fixture-object-field
                              post-status-block-number-rpc "id")))
                 (is (= 616 (fixture-object-field
                              post-status-block-by-number-rpc "id")))
                 (is (= 617 (fixture-object-field receipt-rpc "id")))
                 (is (= 618 (fixture-object-field block-receipts-rpc "id")))
                 (is (= 619 (fixture-object-field logs-rpc "id")))
                 (is (= 620 (fixture-object-field
                              safe-block-by-number-rpc "id")))
                 (is (= 621 (fixture-object-field
                              finalized-block-by-number-rpc "id")))
                 (is (= 622 (fixture-object-field safe-balance-rpc "id")))
                 (is (= 623 (fixture-object-field finalized-balance-rpc "id")))
                 (is (= 624 (fixture-object-field block-by-hash-rpc "id")))
                 (is (= 625 (fixture-object-field
                              block-transaction-count-by-hash-rpc "id")))
                 (is (= 626 (fixture-object-field
                              block-transaction-count-by-number-rpc "id")))
                 (is (= 627 (fixture-object-field
                              transaction-by-hash-rpc "id")))
                 (is (= 628 (fixture-object-field
                              transaction-by-block-hash-and-index-rpc "id")))
                 (is (= 629 (fixture-object-field
                              transaction-by-block-number-and-index-rpc "id")))
                 (is (= 630 (fixture-object-field
                              raw-transaction-by-hash-rpc "id")))
                 (is (= 631 (fixture-object-field
                              raw-transaction-by-block-hash-and-index-rpc
                              "id")))
                 (is (= 632 (fixture-object-field
                              raw-transaction-by-block-number-and-index-rpc
                              "id")))
                 (is (= 633 (fixture-object-field proof-rpc "id")))
                 (is (= 634 (fixture-object-field
                              block-hash-balance-rpc "id")))
                 (is (= 635 (fixture-object-field
                              require-canonical-balance-rpc "id")))
                 (is (= 636 (fixture-object-field call-rpc "id")))
                 (is (= 637 (fixture-object-field estimate-gas-rpc "id")))
                 (is (= 638 (fixture-object-field create-access-list-rpc "id")))
                 (is (= 639 (fixture-object-field post-call-storage-rpc "id")))
                 (is (= 640 (fixture-object-field
                              full-block-by-number-rpc "id")))
                 (is (= 641 (fixture-object-field
                              full-block-by-hash-rpc "id")))
                 (is (= 642 (fixture-object-field
                              logs-by-block-hash-rpc "id")))
                 (is (= 643 (fixture-object-field
                              new-block-filter-rpc "id")))
                 (is (= 644 (fixture-object-field
                              block-filter-changes-rpc "id")))
                 (is (= 645 (fixture-object-field
                              new-log-filter-rpc "id")))
                 (is (= 646 (fixture-object-field
                              log-filter-changes-rpc "id")))
                 (is (= 649 (fixture-object-field
                              post-reorg-block-filter-changes-rpc "id")))
                 (is (= 650 (fixture-object-field
                              post-reorg-log-filter-changes-rpc "id")))
                 (is (string= "0x1"
                              (fixture-object-field
                               new-block-filter-rpc "result")))
                 (is (string= "0x2"
                              (fixture-object-field
                               new-log-filter-rpc "result")))
                 (is (= 1 (length block-filter-changes)))
                 (is (string= block-hash-hex (first block-filter-changes)))
                 (is (= (length receipt-logs) (length log-filter-changes)))
                 (is (= 1 (length post-reorg-block-filter-changes)))
                 (is (string= side-sibling-block-hash-hex
                              (first post-reorg-block-filter-changes)))
                 (is (= (length receipt-logs)
                        (length post-reorg-log-filter-changes)))
                 (dolist (removed-log post-reorg-log-filter-changes)
                   (is (eq t (fixture-object-field removed-log "removed")))
                   (is (string= (fixture-object-field expect "logAddress")
                                (fixture-object-field removed-log "address")))
                   (is (string= (fixture-object-field expect "logData")
                                (fixture-object-field removed-log "data")))
                   (is (equal (list (fixture-object-field expect "logTopic"))
                              (fixture-object-field removed-log "topics")))
                   (is (string= block-hash-hex
                                (fixture-object-field removed-log
                                                      "blockHash"))))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field
                               side-sibling-payload-result "status")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               side-sibling-payload-result
                               "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field
                               side-sibling-forkchoice-status
                               "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field
                               post-reorg-block-by-number-result
                               "number")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               post-reorg-block-by-number-result
                               "hash")))
                 (is (equal '()
                            (fixture-object-field
                             post-reorg-block-by-number-result
                             "transactions")))
                 (is (string= transaction-hash-hex
                              (fixture-object-field
                               post-reorg-transaction-by-hash-result
                               "hash")))
                 (is (null (fixture-object-field
                            post-reorg-transaction-by-hash-result
                            "blockHash")))
                 (is (null (fixture-object-field
                            post-reorg-transaction-by-hash-result
                            "blockNumber")))
                 (is (null (fixture-object-field
                            post-reorg-transaction-by-hash-result
                            "transactionIndex")))
                 (is (string= "0x1" post-reorg-pending-block-count))
                 (is (string= transaction-hash-hex
                              (fixture-object-field
                               post-reorg-pending-transaction-by-index
                               "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-transaction-by-index
                            "blockHash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-transaction-by-index
                            "blockNumber")))
                 (is (null (fixture-object-field
                            post-reorg-pending-transaction-by-index
                            "transactionIndex")))
                 (is (string= raw-transaction-hex
                              post-reorg-pending-raw-transaction-by-index))
                 (is (null (fixture-object-field
                            post-reorg-pending-block "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block "nonce")))
                 (is (string= expected-post-reorg-pending-block-number
                              (fixture-object-field
                               post-reorg-pending-block "number")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               post-reorg-pending-block "parentHash")))
                 (is (= 1 (length post-reorg-pending-block-transactions)))
                 (is (string= transaction-hash-hex
                              (fixture-object-field
                               post-reorg-pending-block-transaction
                               "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block-transaction
                            "blockHash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block-transaction
                            "blockNumber")))
                 (is (null (fixture-object-field
                            post-reorg-pending-block-transaction
                            "transactionIndex")))
                 (is (null (fixture-object-field
                            post-reorg-pending-header "hash")))
                 (is (null (fixture-object-field
                            post-reorg-pending-header "nonce")))
                 (is (string= expected-post-reorg-pending-block-number
                              (fixture-object-field
                               post-reorg-pending-header "number")))
                 (is (string= side-sibling-block-hash-hex
                              (fixture-object-field
                               post-reorg-pending-header "parentHash")))
                 (is (string= (fixture-object-field expect "senderNonce")
                              post-reorg-pending-sender-nonce))
                 (is (null (fixture-object-field
                            post-reorg-receipt-rpc "result")))
                 (is (null post-reorg-logs))
                 (is (= 1 (length payload-bodies-by-hash-result)))
                 (is (= 1 (length payload-bodies-by-range-result)))
                 (is (= expected-payload-body-transaction-count
                        (length payload-body-by-hash-transactions)))
                 (is (= expected-payload-body-transaction-count
                        (length payload-body-by-range-transactions)))
                 (is (string= +payload-status-valid+
                              (fixture-object-field prepare-payload-status
                                                    "status")))
                 (is (and (stringp prepared-payload-id)
                          (= 18 (length prepared-payload-id))))
                 (is (not (fixture-object-field get-payload-rpc "error")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field
                               get-payload-execution-payload
                               "parentHash")))
                 (is (string= expected-prepared-block-number
                              (fixture-object-field
                               get-payload-execution-payload
                               "blockNumber")))
                 (is (and (listp get-payload-transactions)
                          (null get-payload-transactions)))
                 (is (string= +payload-status-syncing+
                              (fixture-object-field remote-payload-result
                                                    "status")))
                 (is (null (fixture-object-field remote-payload-result
                                                 "latestValidHash")))
                 (is (string= +payload-status-invalid+
                              (fixture-object-field invalid-payload-result
                                                    "status")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field invalid-payload-result
                                                    "latestValidHash")))
                 (is (string= "Timestamp is not greater than parent timestamp"
                              (fixture-object-field invalid-payload-result
                                                    "validationError")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field
                               post-status-block-number-rpc
                               "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc
                                                    "result")))
                 (is (string= "0x0"
                              (fixture-object-field safe-balance-rpc
                                                    "result")))
                 (is (string= "0x0"
                              (fixture-object-field finalized-balance-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field block-hash-balance-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field
                               require-canonical-balance-rpc "result")))
                 (is (string= (fixture-object-field expect "senderNonce")
                              (fixture-object-field transaction-count-rpc
                                                    "result")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-by-number-result
                                                    "number")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field block-by-number-result
                                                    "hash")))
                 (is (equal (list transaction-hash-hex)
                            (fixture-object-field block-by-number-result
                                                  "transactions")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-by-hash-result
                                                    "number")))
                 (is (string= block-hash-hex
                              (fixture-object-field block-by-hash-result
                                                    "hash")))
                 (is (equal (list transaction-hash-hex)
                            (fixture-object-field block-by-hash-result
                                                  "transactions")))
                 (dolist (full-block-result
                          (list full-block-by-number-result
                                full-block-by-hash-result))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field full-block-result
                                                      "number")))
                   (is (string= block-hash-hex
                                (fixture-object-field full-block-result
                                                      "hash"))))
                 (dolist (transactions
                          (list full-block-by-number-transactions
                                full-block-by-hash-transactions))
                   (is (= 1 (length transactions))))
                 (dolist (full-block-transaction
                          (list full-block-by-number-transaction
                                full-block-by-hash-transaction))
                   (is (string= transaction-hash-hex
                                (fixture-object-field full-block-transaction
                                                      "hash")))
                   (is (string= block-hash-hex
                                (fixture-object-field full-block-transaction
                                                      "blockHash")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field full-block-transaction
                                                      "blockNumber")))
                   (is (string= "0x0"
                                (fixture-object-field full-block-transaction
                                                      "transactionIndex"))))
                 (is (string= expected-transaction-count-hex
                              (fixture-object-field
                               block-transaction-count-by-hash-rpc
                               "result")))
                 (is (string= expected-transaction-count-hex
                              (fixture-object-field
                               block-transaction-count-by-number-rpc
                               "result")))
                 (dolist (transaction-result
                          (list transaction-by-hash-result
                                transaction-by-block-hash-and-index-result
                                transaction-by-block-number-and-index-result))
                   (is (string= transaction-hash-hex
                                (fixture-object-field transaction-result
                                                      "hash")))
                   (is (string= block-hash-hex
                                (fixture-object-field transaction-result
                                                      "blockHash")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field transaction-result
                                                      "blockNumber")))
                   (is (string= "0x0"
                                (fixture-object-field transaction-result
                                                      "transactionIndex"))))
                 (is (string= raw-transaction-hex
                              (fixture-object-field raw-transaction-by-hash-rpc
                                                    "result")))
                 (is (string= raw-transaction-hex
                              (fixture-object-field
                               raw-transaction-by-block-hash-and-index-rpc
                               "result")))
                 (is (string= raw-transaction-hex
                              (fixture-object-field
                               raw-transaction-by-block-number-and-index-rpc
                               "result")))
                 (is (string= (address-to-hex storage-address)
                              (fixture-object-field proof-result "address")))
                 (is (listp (fixture-object-field proof-result
                                                  "accountProof")))
                 (is (string= (fixture-object-field expect "storageKey")
                              (fixture-object-field proof-storage "key")))
                 (is (string= (quantity-to-hex
                               (hex-to-quantity
                                (fixture-object-field expect "storageValue")))
                              (fixture-object-field proof-storage "value")))
                 (is (listp (fixture-object-field proof-storage "proof")))
                 (is (string= (fixture-object-field parent "number")
                              (fixture-object-field
                               safe-block-by-number-result
                               "number")))
                 (is (string= (hash32-to-hex (block-hash parent-block))
                              (fixture-object-field
                               safe-block-by-number-result
                               "hash")))
                 (is (string= (fixture-object-field parent "number")
                              (fixture-object-field
                               finalized-block-by-number-result
                               "number")))
                 (is (string= (hash32-to-hex (block-hash parent-block))
                              (fixture-object-field
                               finalized-block-by-number-result
                               "hash")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field
                               post-status-block-by-number-result
                               "number")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field
                               post-status-block-by-number-result
                               "hash")))
                 (is (string= (fixture-object-field expect "code")
                              (fixture-object-field code-rpc "result")))
                 (is (string= (fixture-object-field expect "storageValue")
                              (fixture-object-field storage-rpc "result")))
                 (is (not (fixture-object-field call-rpc "error")))
                 (is (string= "0x"
                              (fixture-object-field call-rpc "result")))
                 (is (<= 21000
                         (hex-to-quantity
                          (fixture-object-field estimate-gas-rpc "result"))))
                 (is (stringp actual-access-list-gas-used))
                 (is actual-access-list-entry)
                 (is (member (fixture-object-field expect "storageKey")
                             actual-access-list-storage-keys
                             :test #'string=))
                 (is (string= (fixture-object-field expect "storageValue")
                              (fixture-object-field post-call-storage-rpc
                                                    "result")))
                 (is (string= transaction-hash-hex
                              (fixture-object-field receipt
                                                    "transactionHash")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field receipt "blockNumber")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field receipt "blockHash")))
                 (is (string= (fixture-object-field expect "receiptType")
                              (fixture-object-field receipt "type")))
                 (is (string= (fixture-object-field expect "receiptStatus")
                              (fixture-object-field receipt "status")))
                 (is (= (hex-to-quantity
                         (fixture-object-field expect "logCount"))
                        (length receipt-logs)))
                 (is (= 1 (length block-receipts)))
                 (is (string= transaction-hash-hex
                              (fixture-object-field block-receipt
                                                    "transactionHash")))
                 (is (= (length receipt-logs) (length block-receipt-logs)))
                 (is (= (length receipt-logs) (length filtered-logs)))
                 (is (= (length receipt-logs)
                        (length block-hash-filtered-logs)))
                 (dolist (log (list receipt-log block-receipt-log
                                    filtered-log block-hash-filtered-log
                                    log-filter-change-log))
                   (is (string= (fixture-object-field expect "logAddress")
                                (fixture-object-field log "address")))
                   (is (string= (fixture-object-field expect "logData")
                                (fixture-object-field log "data")))
                   (is (equal (list (fixture-object-field expect "logTopic"))
                              (fixture-object-field log "topics")))
                   (is (string= transaction-hash-hex
                                (fixture-object-field log "transactionHash")))
                   (is (string= (hash32-to-hex (block-hash child-block))
                                (fixture-object-field log "blockHash")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field log "blockNumber")))
                   (is (string= "0x0"
                                (fixture-object-field log
                                                      "transactionIndex")))
                   (is (string= "0x0"
                                (fixture-object-field log "logIndex"))))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (= (fixture-quantity-field parent "number")
                              (fixture-object-field stdout-summary
                                                    "headNumber")))
                       (is (string= (hash32-to-hex (block-hash parent-block))
                                    (fixture-object-field stdout-summary
                                                          "headHash")))
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= side-sibling-block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "10"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "50"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "60"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))
