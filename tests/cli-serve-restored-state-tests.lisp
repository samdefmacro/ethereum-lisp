(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-serve-mode-restores-imported-database-state
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart" "jwt"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-genesis" "json"))
        (database-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-chain" "sexp"))
        (first-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-restart-first-ready" "json"))
        (first-log-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-first" "log"))
        (first-pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-first" "pid"))
        (second-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-restart-second-ready" "json"))
        (second-log-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-second" "log"))
        (second-pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-restart-second" "pid"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-log-contract-call-with-withdrawal"))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
                (payload-case (fixture-object-field case "payload"))
                (expect (fixture-object-field case "expect"))
                (recipient (fixture-address-field expect "recipient"))
                (transaction (first (block-transactions child-block)))
                (block-hash-hex (hash32-to-hex (block-hash child-block)))
                (transaction-hash-hex
                  (hash32-to-hex (transaction-hash transaction)))
                (new-payload-body
                  (json-encode (engine-fixture-payload-request 801 payload)))
                (forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    802 (block-hash child-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))))
                (block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 803)
                         (cons "method" "eth_blockNumber")
                         (cons "params" #()))))
                (balance-body
                  (json-encode (engine-fixture-balance-request
                                804 recipient)))
                (block-by-hash-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 805)
                         (cons "method" "eth_getBlockByHash")
                         (cons "params" (list block-hash-hex :false)))))
                (receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 806)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex))))))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
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
                        "--database"
                        (namestring database-path)
                        "--engine-port"
                        "0"
                        "--public-port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--ready-file"
                        (namestring first-ready-path)
                        "--log-file"
                        (namestring first-log-path)
                        "--pid-file"
                        (namestring first-pid-path)
                        "--max-connections"
                        "100"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file first-ready-path 10)
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
               (is (probe-file first-ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file first-ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string first-ready-path)))
                    (pid (devnet-cli-pid-file-process-id first-pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    new-payload-response
                    forkchoice-response
                    block-number-response
                    balance-response
                    receipt-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= (namestring database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (handler-case
                   (progn
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
                     (setf receipt-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             receipt-body))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (dolist (response (list new-payload-response
                                       forkchoice-response
                                       block-number-response
                                       balance-response
                                       receipt-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (receipt-rpc
                        (parse-json
                         (devnet-cli-http-body receipt-response)))
                      (receipt
                        (fixture-object-field receipt-rpc "result")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
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
                                                    "result")))
                 (is (string= transaction-hash-hex
                              (fixture-object-field receipt
                                                    "transactionHash")))
                 (is (string= block-hash-hex
                              (fixture-object-field receipt
                                                    "blockHash"))))
               (multiple-value-bind (kill-stdout kill-stderr kill-status)
                   (uiop:run-program
                    (list "kill" "-TERM" (write-to-string pid))
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (= 0 kill-status))
                 (is (string= "" kill-stdout))
                 (is (string= "" kill-stderr)))
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
                   (is (search
                        "Devnet shutdown requested; closing RPC listeners."
                        stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records
                              (devnet-cli-file-forms first-log-path))
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
                       (is (= (block-header-number
                               (block-header parent-block))
                              (fixture-object-field stdout-summary
                                                    "headNumber")))
                       (is shutdown-record)
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "2"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "3"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))
             (is (probe-file database-path))
             (setf process
                   (test-launch-program
                    (list "sbcl"
                          "--script"
                          script
                          "--"
                          "devnet"
                          "--genesis"
                          (namestring genesis-path)
                          "--database"
                          (namestring database-path)
                          "--engine-port"
                          "0"
                          "--public-port"
                          "0"
                          "--ready-file"
                          (namestring second-ready-path)
                          "--log-file"
                          (namestring second-log-path)
                          "--pid-file"
                          (namestring second-pid-path)
                          "--max-connections"
                          "100"
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :stream
                    :error-output :stream))
             (unless (devnet-cli-wait-for-file second-ready-path 10)
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
                 (is (probe-file second-ready-path))
                 (is (string= "" stdout))
                 (is (string= "" stderr))))
             (when (probe-file second-ready-path)
               (let* ((ready-summary
                        (parse-json
                         (devnet-cli-file-string second-ready-path)))
                      (pid (devnet-cli-pid-file-process-id second-pid-path))
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      block-number-response
                      balance-response
                      block-by-hash-response
                      receipt-response)
                 (is (= pid (fixture-object-field ready-summary
                                                   "processId")))
                 (is (string= (namestring database-path)
                              (fixture-object-field ready-summary
                                                    "databasePath")))
                 (is (= (fixture-quantity-field payload-case "number")
                        (fixture-object-field ready-summary "headNumber")))
                 (is (string= block-hash-hex
                              (fixture-object-field ready-summary
                                                    "headHash")))
                 (handler-case
                     (progn
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
                       (setf block-by-hash-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-by-hash-body)))
                       (setf receipt-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               receipt-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (dolist (response (list block-number-response
                                         balance-response
                                         block-by-hash-response
                                         receipt-response))
                   (is (= 200 (devnet-cli-http-status response))))
                 (let* ((block-number-rpc
                          (parse-json
                           (devnet-cli-http-body block-number-response)))
                        (balance-rpc
                          (parse-json
                           (devnet-cli-http-body balance-response)))
                        (block-by-hash-rpc
                          (parse-json
                           (devnet-cli-http-body block-by-hash-response)))
                        (block-by-hash-result
                          (fixture-object-field block-by-hash-rpc "result"))
                        (receipt-rpc
                          (parse-json
                           (devnet-cli-http-body receipt-response)))
                        (receipt
                          (fixture-object-field receipt-rpc "result")))
                   (is (string= (fixture-object-field payload-case "number")
                                (fixture-object-field block-number-rpc
                                                      "result")))
                   (is (string= (fixture-object-field expect
                                                      "recipientBalance")
                                (fixture-object-field balance-rpc
                                                      "result")))
                   (is (string= block-hash-hex
                                (fixture-object-field block-by-hash-result
                                                      "hash")))
                   (is (equal (list transaction-hash-hex)
                              (fixture-object-field block-by-hash-result
                                                    "transactions")))
                   (is (string= transaction-hash-hex
                                (fixture-object-field receipt
                                                      "transactionHash")))
                   (is (string= block-hash-hex
                                (fixture-object-field receipt
                                                      "blockHash"))))
                 (multiple-value-bind (kill-stdout kill-stderr kill-status)
                     (uiop:run-program
                      (list "kill" "-TERM" (write-to-string pid))
                      :output :string
                      :error-output :string
                      :ignore-error-status t)
                   (is (= 0 kill-status))
                   (is (string= "" kill-stdout))
                   (is (string= "" kill-stderr)))
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
                     (is (search
                          "Devnet shutdown requested; closing RPC listeners."
                          stderr))
                     (when (and (numberp status) (= 0 status))
                       (let* ((stdout-summary (parse-json stdout))
                              (log-records
                                (devnet-cli-file-forms second-log-path))
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
                         (is (= (fixture-quantity-field payload-case
                                                        "number")
                                (fixture-object-field stdout-summary
                                                      "headNumber")))
                         (is (string= block-hash-hex
                                      (fixture-object-field stdout-summary
                                                            "headHash")))
                         (is shutdown-record)
                         (is (string= (fixture-object-field payload-case
                                                            "number")
                                      (cdr (assoc "headNumber"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= block-hash-hex
                                      (cdr (assoc "headHash"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "0"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "4"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "4"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list jwt-path
                          genesis-path
                          database-path
                          first-ready-path
                          first-log-path
                          first-pid-path
                          second-ready-path
                          second-log-path
                          second-pid-path))
        (when (probe-file path)
          (delete-file path)))))

