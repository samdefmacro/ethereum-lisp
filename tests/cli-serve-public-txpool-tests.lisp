(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-serve-mode-admits-public-txpool-transactions
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool-genesis" "json"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-txpool" "pid"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-one-transfer-with-withdrawal")))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-with-txpool-account
              case)))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :public-port 0))
                  (config (ethereum-lisp.cli:devnet-node-config node))
                  (script-genesis
                    (ethereum-lisp.cli::devnet-node-genesis-block node))
                  (latest-block-hash-hex
                    (hash32-to-hex (block-hash script-genesis)))
                  (expected-pending-block-number
                    (quantity-to-hex
                     (1+ (block-header-number
                          (block-header script-genesis)))))
                  (sender (devnet-cli-txpool-sender-address))
                  (sender-hex (address-to-hex sender))
                  (pending-transaction
                    (devnet-cli-txpool-transaction
                     config 0 +devnet-cli-txpool-gas-price+))
                  (basefee-transaction
                    (devnet-cli-txpool-transaction
                     config 1 +devnet-cli-txpool-basefee-gas-price+))
                  (queued-transaction
                    (devnet-cli-txpool-transaction
                     config 2 +devnet-cli-txpool-gas-price+))
                  (pending-hash
                    (hash32-to-hex (transaction-hash pending-transaction)))
                  (basefee-hash
                    (hash32-to-hex (transaction-hash basefee-transaction)))
                  (queued-hash
                    (hash32-to-hex (transaction-hash queued-transaction)))
                  (pending-raw
                    (devnet-cli-transaction-raw pending-transaction))
                  (basefee-raw
                    (devnet-cli-transaction-raw basefee-transaction))
                  (queued-raw
                    (devnet-cli-transaction-raw queued-transaction))
                  (pending-nonce
                    (devnet-cli-transaction-nonce-key pending-transaction))
                  (expected-pending-sender-nonce
                    (quantity-to-hex
                     (1+ (transaction-nonce pending-transaction))))
                  (basefee-nonce
                    (devnet-cli-transaction-nonce-key basefee-transaction))
                  (queued-nonce
                    (devnet-cli-transaction-nonce-key queued-transaction))
                  (pending-summary
                    (devnet-cli-transaction-summary pending-transaction))
                  (basefee-summary
                    (devnet-cli-transaction-summary basefee-transaction))
                  (queued-summary
                    (devnet-cli-transaction-summary queued-transaction))
                  (send-pending-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 701)
                           (cons "method" "eth_sendRawTransaction")
                           (cons "params" (list pending-raw)))))
                  (send-basefee-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 702)
                           (cons "method" "eth_sendRawTransaction")
                           (cons "params" (list basefee-raw)))))
                  (send-queued-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 703)
                           (cons "method" "eth_sendRawTransaction")
                           (cons "params" (list queued-raw)))))
                  (raw-pending-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 704)
                           (cons "method" "eth_getRawTransactionByHash")
                           (cons "params" (list pending-hash)))))
                  (raw-basefee-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 705)
                           (cons "method" "eth_getRawTransactionByHash")
                           (cons "params" (list basefee-hash)))))
                  (raw-queued-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 706)
                           (cons "method" "eth_getRawTransactionByHash")
                           (cons "params" (list queued-hash)))))
                  (pending-transactions-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 707)
                           (cons "method" "eth_pendingTransactions")
                           (cons "params" #()))))
                  (new-pending-filter-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 717)
                           (cons "method" "eth_newPendingTransactionFilter")
                           (cons "params" #()))))
                  (pending-block-count-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 711)
                           (cons "method"
                                 "eth_getBlockTransactionCountByNumber")
                           (cons "params" (list "pending")))))
                  (pending-transaction-by-index-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 712)
                           (cons "method"
                                 "eth_getTransactionByBlockNumberAndIndex")
                           (cons "params" (list "pending" "0x0")))))
                  (pending-raw-transaction-by-index-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 713)
                           (cons "method"
                                 "eth_getRawTransactionByBlockNumberAndIndex")
                           (cons "params" (list "pending" "0x0")))))
                  (pending-block-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 714)
                           (cons "method" "eth_getBlockByNumber")
                           (cons "params" (list "pending" t)))))
                  (pending-header-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 715)
                           (cons "method" "eth_getHeaderByNumber")
                           (cons "params" (list "pending")))))
                  (pending-fee-history-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 722)
                           (cons "method" "eth_feeHistory")
                           (cons "params" (list "0x1" "latest" #())))))
                  (pending-sender-nonce-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 723)
                           (cons "method" "eth_getTransactionCount")
                           (cons "params" (list sender-hex "pending")))))
                  (pending-block-receipts-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 724)
                           (cons "method" "eth_getBlockReceipts")
                           (cons "params" (list "pending")))))
                  (pending-uncle-count-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 725)
                           (cons "method" "eth_getUncleCountByBlockNumber")
                           (cons "params" (list "pending")))))
                  (pending-logs-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 726)
                           (cons "method" "eth_getLogs")
                           (cons "params"
                                 (list
                                  (list
                                   (cons "fromBlock" "pending")
                                   (cons "toBlock" "pending")))))))
                  (txpool-status-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 708)
                           (cons "method" "txpool_status")
                           (cons "params" #()))))
                  (txpool-content-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 716)
                           (cons "method" "txpool_content")
                           (cons "params" #()))))
                  (txpool-content-from-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 709)
                           (cons "method" "txpool_contentFrom")
                           (cons "params" (list sender-hex)))))
                  (txpool-inspect-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 710)
                           (cons "method" "txpool_inspect")
                           (cons "params" #())))))
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
                          "--ready-file"
                          (namestring ready-path)
                          "--log-file"
                          (namestring log-path)
                          "--pid-file"
                          (namestring pid-path)
                          "--max-connections"
                          "26"
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
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      send-pending-response
                      send-basefee-response
                      send-queued-response
                      raw-pending-response
                      raw-basefee-response
                      raw-queued-response
                      new-pending-filter-response
                      pending-filter-changes-response
                      empty-pending-filter-changes-response
                      uninstall-pending-filter-response
                      removed-pending-filter-changes-response
                      pending-transactions-response
                      pending-block-count-response
                      pending-transaction-by-index-response
                      pending-raw-transaction-by-index-response
                      pending-block-response
                      pending-header-response
                      pending-fee-history-response
                      pending-sender-nonce-response
                      pending-block-receipts-response
                      pending-uncle-count-response
                      pending-logs-response
                      txpool-status-response
                      txpool-content-response
                      txpool-content-from-response
                      txpool-inspect-response)
                 (is (= pid (fixture-object-field ready-summary "processId")))
                 (handler-case
                     (progn
                       (setf new-pending-filter-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               new-pending-filter-body)))
                       (setf send-pending-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               send-pending-body)))
                       (setf send-basefee-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               send-basefee-body)))
                       (setf send-queued-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               send-queued-body)))
                       (setf raw-pending-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               raw-pending-body)))
                       (setf raw-basefee-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               raw-basefee-body)))
                       (setf raw-queued-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               raw-queued-body)))
                       (let* ((new-pending-filter-rpc
                                (parse-json
                                 (devnet-cli-http-body
                                  new-pending-filter-response)))
                              (pending-filter-id
                                (fixture-object-field
                                 new-pending-filter-rpc "result"))
                              (pending-filter-changes-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 718)
                                  (cons "method" "eth_getFilterChanges")
                                  (cons "params"
                                        (list pending-filter-id)))))
                              (empty-pending-filter-changes-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 719)
                                  (cons "method" "eth_getFilterChanges")
                                  (cons "params"
                                        (list pending-filter-id)))))
                              (uninstall-pending-filter-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 720)
                                  (cons "method" "eth_uninstallFilter")
                                  (cons "params"
                                        (list pending-filter-id)))))
                              (removed-pending-filter-changes-body
                                (json-encode
                                 (list
                                  (cons "jsonrpc" "2.0")
                                  (cons "id" 721)
                                  (cons "method" "eth_getFilterChanges")
                                  (cons "params"
                                        (list pending-filter-id))))))
                         (setf pending-filter-changes-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 pending-filter-changes-body)))
                         (setf empty-pending-filter-changes-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 empty-pending-filter-changes-body)))
                         (setf uninstall-pending-filter-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 uninstall-pending-filter-body)))
                         (setf removed-pending-filter-changes-response
                               (devnet-cli-http-endpoint-request
                                rpc-endpoint
                                (devnet-cli-json-rpc-http-request
                                 removed-pending-filter-changes-body))))
                       (setf pending-transactions-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-transactions-body)))
                       (setf pending-block-count-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-block-count-body)))
                       (setf pending-transaction-by-index-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-transaction-by-index-body)))
                       (setf pending-raw-transaction-by-index-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-raw-transaction-by-index-body)))
                       (setf pending-block-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-block-body)))
                       (setf pending-header-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-header-body)))
                       (setf pending-fee-history-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-fee-history-body)))
                       (setf pending-sender-nonce-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-sender-nonce-body)))
                       (setf pending-block-receipts-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-block-receipts-body)))
                       (setf pending-uncle-count-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-uncle-count-body)))
                       (setf pending-logs-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               pending-logs-body)))
                       (setf txpool-status-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-status-body)))
                       (setf txpool-content-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-content-body)))
                       (setf txpool-content-from-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-content-from-body)))
                       (setf txpool-inspect-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-inspect-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (dolist (response
                          (list send-pending-response
                                send-basefee-response
                                send-queued-response
                                raw-pending-response
                                raw-basefee-response
                                raw-queued-response
                                new-pending-filter-response
                                pending-filter-changes-response
                                empty-pending-filter-changes-response
                                uninstall-pending-filter-response
                                removed-pending-filter-changes-response
                                pending-transactions-response
                                pending-block-count-response
                                pending-transaction-by-index-response
                                pending-raw-transaction-by-index-response
                                pending-block-response
                                pending-header-response
                                pending-fee-history-response
                                pending-sender-nonce-response
                                pending-block-receipts-response
                                pending-uncle-count-response
                                pending-logs-response
                                txpool-status-response
                                txpool-content-response
                                txpool-content-from-response
                                txpool-inspect-response))
                   (is (= 200 (devnet-cli-http-status response))))
                 (let* ((send-pending-rpc
                          (parse-json
                           (devnet-cli-http-body send-pending-response)))
                        (send-basefee-rpc
                          (parse-json
                           (devnet-cli-http-body send-basefee-response)))
                        (send-queued-rpc
                          (parse-json
                           (devnet-cli-http-body send-queued-response)))
                        (raw-pending-rpc
                          (parse-json
                           (devnet-cli-http-body raw-pending-response)))
                        (raw-basefee-rpc
                          (parse-json
                           (devnet-cli-http-body raw-basefee-response)))
                        (raw-queued-rpc
                          (parse-json
                           (devnet-cli-http-body raw-queued-response)))
                        (new-pending-filter-rpc
                          (parse-json
                           (devnet-cli-http-body
                            new-pending-filter-response)))
                        (pending-filter-changes-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-filter-changes-response)))
                        (empty-pending-filter-changes-rpc
                          (parse-json
                           (devnet-cli-http-body
                            empty-pending-filter-changes-response)
                           :preserve-empty-arrays t))
                        (uninstall-pending-filter-rpc
                          (parse-json
                           (devnet-cli-http-body
                            uninstall-pending-filter-response)))
                        (removed-pending-filter-changes-rpc
                          (parse-json
                           (devnet-cli-http-body
                            removed-pending-filter-changes-response)))
                        (pending-transactions-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-transactions-response)))
                        (pending-block-count-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-block-count-response)))
                        (pending-transaction-by-index-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-transaction-by-index-response)))
                        (pending-raw-transaction-by-index-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-raw-transaction-by-index-response)))
                        (pending-block-rpc
                          (parse-json
                           (devnet-cli-http-body pending-block-response)))
                        (pending-header-rpc
                          (parse-json
                           (devnet-cli-http-body pending-header-response)))
                        (pending-fee-history-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-fee-history-response)))
                        (pending-sender-nonce-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-sender-nonce-response)))
                        (pending-block-receipts-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-block-receipts-response)))
                        (pending-uncle-count-rpc
                          (parse-json
                           (devnet-cli-http-body
                            pending-uncle-count-response)))
                        (pending-logs-rpc
                          (parse-json
                           (devnet-cli-http-body pending-logs-response)
                           :preserve-empty-arrays t))
                        (txpool-status-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-status-response)))
                        (txpool-content-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-content-response)))
                        (txpool-content-from-rpc
                          (parse-json
                           (devnet-cli-http-body
                            txpool-content-from-response)))
                        (txpool-inspect-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-inspect-response)))
                        (pending-transactions
                          (fixture-object-field
                           pending-transactions-rpc "result"))
                        (pending-filter-changes
                          (fixture-object-field
                           pending-filter-changes-rpc "result"))
                        (empty-pending-filter-changes
                          (fixture-object-field
                           empty-pending-filter-changes-rpc "result"))
                        (removed-pending-filter-error
                          (fixture-object-field
                           removed-pending-filter-changes-rpc "error"))
                        (pending-object (first pending-transactions))
                        (pending-block-count
                          (fixture-object-field pending-block-count-rpc
                                                "result"))
                        (pending-transaction-by-index
                          (fixture-object-field
                           pending-transaction-by-index-rpc "result"))
                        (pending-raw-transaction-by-index
                          (fixture-object-field
                           pending-raw-transaction-by-index-rpc "result"))
                        (pending-block
                          (fixture-object-field pending-block-rpc "result"))
                        (pending-header
                          (fixture-object-field pending-header-rpc "result"))
                        (pending-fee-history
                          (fixture-object-field pending-fee-history-rpc
                                                "result"))
                        (pending-sender-nonce
                          (fixture-object-field pending-sender-nonce-rpc
                                                "result"))
                        (pending-logs
                          (fixture-object-field pending-logs-rpc "result"))
                        (pending-fee-history-base-fees
                          (fixture-object-field pending-fee-history
                                                "baseFeePerGas"))
                        (pending-fee-history-next-base-fee
                          (second pending-fee-history-base-fees))
                        (pending-block-transactions
                          (fixture-object-field pending-block "transactions"))
                        (pending-block-transaction
                          (first pending-block-transactions))
                        (txpool-status
                          (fixture-object-field txpool-status-rpc "result"))
                        (txpool-content
                          (fixture-object-field txpool-content-rpc "result"))
                        (content-pending
                          (fixture-object-field txpool-content "pending"))
                        (content-queued
                          (fixture-object-field txpool-content "queued"))
                        (content-pending-sender
                          (fixture-object-field content-pending sender-hex))
                        (content-queued-sender
                          (fixture-object-field content-queued sender-hex))
                        (content-pending-transaction
                          (fixture-object-field content-pending-sender
                                                pending-nonce))
                        (content-basefee-transaction
                          (fixture-object-field content-queued-sender
                                                basefee-nonce))
                        (content-queued-transaction
                          (fixture-object-field content-queued-sender
                                                queued-nonce))
                        (txpool-content-from
                          (fixture-object-field
                           txpool-content-from-rpc "result"))
                        (content-from-pending
                          (fixture-object-field txpool-content-from "pending"))
                        (content-from-queued
                          (fixture-object-field txpool-content-from "queued"))
                        (content-from-pending-transaction
                          (fixture-object-field
                           content-from-pending pending-nonce))
                        (content-from-basefee-transaction
                          (fixture-object-field
                           content-from-queued basefee-nonce))
                        (content-from-queued-transaction
                          (fixture-object-field
                           content-from-queued queued-nonce))
                        (txpool-inspect
                          (fixture-object-field txpool-inspect-rpc "result"))
                        (inspect-pending
                          (fixture-object-field txpool-inspect "pending"))
                        (inspect-queued
                          (fixture-object-field txpool-inspect "queued"))
                        (inspect-pending-sender
                          (fixture-object-field inspect-pending sender-hex))
                        (inspect-queued-sender
                          (fixture-object-field inspect-queued sender-hex)))
                   (is (= 701 (fixture-object-field send-pending-rpc "id")))
                   (is (= 702 (fixture-object-field send-basefee-rpc "id")))
                   (is (= 703 (fixture-object-field send-queued-rpc "id")))
                   (is (= 717
                          (fixture-object-field new-pending-filter-rpc "id")))
                   (is (= 718
                          (fixture-object-field pending-filter-changes-rpc
                                                "id")))
                   (is (= 719
                          (fixture-object-field
                           empty-pending-filter-changes-rpc "id")))
                   (is (= 720
                          (fixture-object-field
                           uninstall-pending-filter-rpc "id")))
                   (is (= 721
                          (fixture-object-field
                           removed-pending-filter-changes-rpc "id")))
                   (is (= 711 (fixture-object-field pending-block-count-rpc
                                                    "id")))
                   (is (= 712 (fixture-object-field
                               pending-transaction-by-index-rpc "id")))
                   (is (= 713 (fixture-object-field
                               pending-raw-transaction-by-index-rpc "id")))
                   (is (= 714 (fixture-object-field pending-block-rpc "id")))
                   (is (= 715 (fixture-object-field pending-header-rpc "id")))
                   (is (= 722
                          (fixture-object-field pending-fee-history-rpc "id")))
                   (is (= 723
                          (fixture-object-field pending-sender-nonce-rpc "id")))
                   (is (= 724
                          (fixture-object-field
                           pending-block-receipts-rpc "id")))
                   (is (= 725
                          (fixture-object-field pending-uncle-count-rpc "id")))
                   (is (= 726 (fixture-object-field pending-logs-rpc "id")))
                   (is (= 716 (fixture-object-field txpool-content-rpc "id")))
                   (is (string= pending-hash
                                (fixture-object-field
                                 send-pending-rpc "result")))
                   (is (string= basefee-hash
                                (fixture-object-field
                                 send-basefee-rpc "result")))
                   (is (string= queued-hash
                                (fixture-object-field
                                 send-queued-rpc "result")))
                   (is (string= pending-raw
                                (fixture-object-field
                                 raw-pending-rpc "result")))
                   (is (string= basefee-raw
                                (fixture-object-field
                                 raw-basefee-rpc "result")))
                   (is (string= queued-raw
                                (fixture-object-field
                                 raw-queued-rpc "result")))
                   (is (string= "0x1"
                                (fixture-object-field
                                 new-pending-filter-rpc "result")))
                   (is (= 1 (length pending-filter-changes)))
                   (is (string= pending-hash
                                (first pending-filter-changes)))
                   (is (devnet-cli-empty-json-array-p
                        empty-pending-filter-changes))
                   (is (eq t (fixture-object-field
                              uninstall-pending-filter-rpc "result")))
                   (is (= -32602
                          (fixture-object-field
                           removed-pending-filter-error "code")))
                   (is (= 1 (length pending-transactions)))
                   (is (string= pending-hash
                                (fixture-object-field pending-object "hash")))
                   (is (null (fixture-object-field pending-object
                                                   "blockHash")))
                   (is (null (fixture-object-field pending-object
                                                   "blockNumber")))
                   (is (null (fixture-object-field pending-object
                                                   "transactionIndex")))
                   (is (string= "0x1" pending-block-count))
                   (is (string= pending-hash
                                (fixture-object-field
                                 pending-transaction-by-index "hash")))
                   (is (null (fixture-object-field
                              pending-transaction-by-index "blockHash")))
                   (is (null (fixture-object-field
                              pending-transaction-by-index "blockNumber")))
                   (is (null (fixture-object-field
                              pending-transaction-by-index
                              "transactionIndex")))
                   (is (string= pending-raw pending-raw-transaction-by-index))
                   (is (null (fixture-object-field pending-block "hash")))
                   (is (null (fixture-object-field pending-block "nonce")))
                   (is (string= expected-pending-block-number
                                (fixture-object-field pending-block "number")))
                   (is (string= latest-block-hash-hex
                                (fixture-object-field pending-block
                                                      "parentHash")))
                   (is (= 1 (length pending-block-transactions)))
                   (is (string= pending-hash
                                (fixture-object-field
                                 pending-block-transaction "hash")))
                   (is (null (fixture-object-field pending-block-transaction
                                                   "blockHash")))
                   (is (null (fixture-object-field pending-header "hash")))
                   (is (null (fixture-object-field pending-header "nonce")))
                   (is (string= expected-pending-block-number
                                (fixture-object-field pending-header
                                                      "number")))
                   (is (string= latest-block-hash-hex
                                (fixture-object-field pending-header
                                                      "parentHash")))
                   (is (= 2 (length pending-fee-history-base-fees)))
                   (is (string= pending-fee-history-next-base-fee
                                (fixture-object-field pending-block
                                                      "baseFeePerGas")))
                   (is (string= pending-fee-history-next-base-fee
                                (fixture-object-field pending-header
                                                      "baseFeePerGas")))
                   (is (string= expected-pending-sender-nonce
                                pending-sender-nonce))
                   (is (null (fixture-object-field
                              pending-block-receipts-rpc "result")))
                   (is (string= "0x0"
                                (fixture-object-field
                                 pending-uncle-count-rpc "result")))
                   (is (devnet-cli-empty-json-array-p pending-logs))
                   (is (string= "0x1"
                                (fixture-object-field txpool-status
                                                      "pending")))
                   (is (string= "0x2"
                                (fixture-object-field txpool-status
                                                      "queued")))
                   (is (string= pending-hash
                                (fixture-object-field
                                 content-pending-transaction "hash")))
                   (is (string= basefee-hash
                                (fixture-object-field
                                 content-basefee-transaction "hash")))
                   (is (string= queued-hash
                                (fixture-object-field
                                 content-queued-transaction "hash")))
                   (is (string= pending-hash
                                (fixture-object-field
                                 content-from-pending-transaction "hash")))
                   (is (string= basefee-hash
                                (fixture-object-field
                                 content-from-basefee-transaction "hash")))
                   (is (string= queued-hash
                                (fixture-object-field
                                 content-from-queued-transaction "hash")))
                   (is (string= pending-summary
                                (fixture-object-field inspect-pending-sender
                                                      pending-nonce)))
                   (is (string= basefee-summary
                                (fixture-object-field inspect-queued-sender
                                                      basefee-nonce)))
                   (is (string= queued-summary
                                (fixture-object-field inspect-queued-sender
                                                      queued-nonce))))
                 (let ((status (devnet-cli-wait-process-exit process 30)))
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
                         (is (string= rpc-endpoint
                                      (fixture-object-field stdout-summary
                                                            "rpcEndpoint")))
                         (is shutdown-record)
                         (is (string= "0"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "26"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "26"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file genesis-path)
        (delete-file genesis-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))

