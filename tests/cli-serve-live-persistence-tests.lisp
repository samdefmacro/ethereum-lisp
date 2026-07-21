(in-package #:ethereum-lisp.test)

#+sbcl
(defun devnet-cli-wait-for-non-null-json-rpc-result
    (endpoint body timeout-seconds
     &key (label "non-null JSON-RPC result")
          (interval-seconds 0.25d0))
  (let ((last-body nil))
    (wait-for-test-condition
     label
     timeout-seconds
     (lambda ()
       (let ((response
               (devnet-cli-http-endpoint-request
                endpoint
                (devnet-cli-json-rpc-http-request body))))
         (is (= 200 (devnet-cli-http-status response)))
         (setf last-body (devnet-cli-http-body response))
         (fixture-object-field (parse-json last-body) "result")))
     :interval-seconds interval-seconds
     :diagnostics (lambda () last-body))))

(deftest ethereum-lisp-script-live-persistence-survives-abrupt-restart
  (:estimated-seconds 40)
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-live-persistence" "jwt"))
        (genesis-path
          (devnet-cli-temp-path
           "ethereum-lisp-live-persistence-genesis" "json"))
        (database-path
          (devnet-cli-temp-path
           "ethereum-lisp-live-persistence-chain" "sexp"))
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-live-persistence-ready" "json"))
        (log-path
          (devnet-cli-temp-path
           "ethereum-lisp-live-persistence" "log"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-one-transfer-with-withdrawal"))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (child-hash-hex (hash32-to-hex (block-hash child-block)))
                (parent-hash-hex (hash32-to-hex (block-hash parent-block)))
                (payload-case (fixture-object-field case "payload"))
                (payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
                (new-payload-body
                  (json-encode (engine-fixture-payload-request 71 payload)))
                (forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    72 (block-hash child-block)
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block)))))
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
                        "--http=false"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--max-connections"
                        "100"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 30)
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
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (token
                      (engine-rpc-make-jwt-token
                       (hex-to-bytes +devnet-cli-jwt-secret+) (unix-time)))
                    new-payload-response
                    forkchoice-response)
               (handler-case
                   (progn
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body :token token)))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body :token token))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (is (= 200 (devnet-cli-http-status forkchoice-response)))
               (let* ((new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (new-payload-status
                        (fixture-object-field
                         (fixture-object-field new-payload-rpc "result")
                         "status"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus")))
                 (is (string= +payload-status-valid+ new-payload-status))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status"))))
               (is (probe-file database-path))
               ;; An urgent termination bypasses the CLI unwind-protect and its
               ;; lifecycle export, so recovery below depends on the live FCU
               ;; commit that completed before the response was returned.
               (uiop:terminate-process process :urgent t)
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (is (not (eq status :timeout))))
               (let ((stderr
                       (devnet-cli-read-stream-string
                        (uiop:process-info-error-output process))))
                 (is (not (search
                           "Devnet shutdown requested; closing RPC listeners."
                           stderr))))
               (is (not (search "devnet.shutdown"
                                (if (probe-file log-path)
                                    (devnet-cli-file-string log-path)
                                    ""))))
               (multiple-value-bind
                     (restore-stdout restore-stderr restore-status)
                   (uiop:run-program
                    (list "sbcl"
                          "--script"
                          script
                          "--"
                          "devnet"
                          "--genesis"
                          (namestring genesis-path)
                          "--database"
                          (namestring database-path)
                          "--http=false"
                          "--no-serve"
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (= 0 restore-status))
                 (is (string= "" restore-stderr))
                 (when (= 0 restore-status)
                   (let ((summary (parse-json restore-stdout)))
                     (is (= (fixture-quantity-field payload-case "number")
                            (fixture-object-field summary "headNumber")))
                     (is (string= child-hash-hex
                                  (fixture-object-field summary "headHash")))
                     (is (string= parent-hash-hex
                                  (fixture-object-field summary "safeHash")))
                     (is (string= parent-hash-hex
                                  (fixture-object-field summary
                                                        "finalizedHash")))
                     (is (fixture-object-field summary "stateAvailable"))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process :urgent t))
      (dolist (path (list jwt-path genesis-path database-path ready-path log-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-new-payload-candidate-survives-sigkill
  (:estimated-seconds 80)
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-candidate-persistence" "jwt"))
        (genesis-path
          (devnet-cli-temp-path
           "ethereum-lisp-candidate-persistence-genesis" "json"))
        (database-path
          (devnet-cli-temp-path
           "ethereum-lisp-candidate-persistence-chain" "sexp"))
        (first-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-candidate-persistence-first-ready" "json"))
        (first-log-path
          (devnet-cli-temp-path
           "ethereum-lisp-candidate-persistence-first" "log"))
        (second-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-candidate-persistence-second-ready" "json"))
        (second-log-path
          (devnet-cli-temp-path
           "ethereum-lisp-candidate-persistence-second" "log"))
        (process nil))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-one-transfer-with-withdrawal"))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (parent-hash (block-hash parent-block))
                (child-hash (block-hash child-block))
                (parent-hash-hex (hash32-to-hex parent-hash))
                (child-hash-hex (hash32-to-hex child-hash))
                (parent-number
                  (block-header-number (block-header parent-block)))
                (child-number-hex
                  (fixture-object-field
                   (fixture-object-field case "payload")
                   "number"))
                (expect (fixture-object-field case "expect"))
                (recipient (fixture-address-field expect "recipient"))
                (expected-recipient-balance
                  (fixture-object-field expect "recipientBalance"))
                (transaction (first (block-transactions child-block)))
                (transaction-hash-hex
                  (hash32-to-hex (transaction-hash transaction)))
                (payload
                  (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
                (new-payload-body
                  (json-encode (engine-fixture-payload-request 91 payload)))
                (forkchoice-body
                  (json-encode
                   (devnet-cli-engine-forkchoice-v2-request
                    92 child-hash
                    :safe parent-hash
                    :finalized parent-hash)))
                (block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 93)
                         (cons "method" "eth_blockNumber")
                         (cons "params" #()))))
                (block-by-hash-body
                  (json-encode
                   (engine-fixture-block-by-hash-request
                    94 child-hash :false)))
                (candidate-balance-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 95)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list
                                (address-to-hex recipient)
                                (list (cons "blockHash"
                                            child-hash-hex)))))))
                (latest-balance-body
                  (json-encode
                   (engine-fixture-balance-request 96 recipient)))
                (receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 97)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex)))))
                (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                (token (engine-rpc-make-jwt-token jwt-secret (unix-time))))
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           ;; The first process exposes only Engine API.  It receives a valid
           ;; candidate but never receives forkchoiceUpdated, then is killed
           ;; urgently so no lifecycle export can hide a missing live commit.
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
                        "--http=false"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--ready-file"
                        (namestring first-ready-path)
                        "--log-file"
                        (namestring first-log-path)
                        "--max-connections"
                        "100"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file first-ready-path 30)
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
                      (parse-json
                       (devnet-cli-file-string first-ready-path)))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    new-payload-response)
               (is (= parent-number
                      (fixture-object-field ready-summary "headNumber")))
               (is (string= parent-hash-hex
                            (fixture-object-field ready-summary "headHash")))
               (handler-case
                   (setf new-payload-response
                         (devnet-cli-http-endpoint-request
                          engine-endpoint
                          (devnet-cli-json-rpc-http-request
                           new-payload-body :token token)))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (let* ((rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (result (fixture-object-field rpc "result")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field result "status")))
                 (is (string= child-hash-hex
                              (fixture-object-field result
                                                    "latestValidHash"))))
               (is (probe-file database-path))
               (uiop:terminate-process process :urgent t)
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (is (not (eq status :timeout))))
               (let ((stderr
                       (devnet-cli-read-stream-string
                        (uiop:process-info-error-output process))))
                 (is (not (search
                           "Devnet shutdown requested; closing RPC listeners."
                           stderr))))
               (is (not (search "devnet.shutdown"
                                (if (probe-file first-log-path)
                                    (devnet-cli-file-string first-log-path)
                                    "")))))
             ;; Restart as a full Engine/public RPC process.  Its ready summary
             ;; must still report the old canonical head even though the child
             ;; candidate and its post-state are recoverable by hash.
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
                          (namestring second-ready-path)
                          "--log-file"
                          (namestring second-log-path)
                          "--max-connections"
                          "100"
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :stream
                    :error-output :stream))
             (unless (devnet-cli-wait-for-file second-ready-path 30)
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
                      (engine-endpoint
                        (fixture-object-field ready-summary "engineEndpoint"))
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      block-number-response
                      block-by-hash-response
                      candidate-balance-response
                      latest-balance-response
                      receipt-response
                      forkchoice-response
                      post-block-number-response
                      post-balance-response
                      post-receipt-response)
                 (is (= parent-number
                        (fixture-object-field ready-summary "headNumber")))
                 (is (string= parent-hash-hex
                              (fixture-object-field ready-summary
                                                    "headHash")))
                 (handler-case
                     (progn
                       (setf block-number-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-number-body)))
                       (setf block-by-hash-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-by-hash-body)))
                       (setf candidate-balance-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               candidate-balance-body)))
                       (setf latest-balance-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               latest-balance-body)))
                       (setf receipt-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               receipt-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (dolist (response (list block-number-response
                                         block-by-hash-response
                                         candidate-balance-response
                                         latest-balance-response
                                         receipt-response))
                   (is (= 200 (devnet-cli-http-status response))))
                 (let* ((block-number-rpc
                          (parse-json
                           (devnet-cli-http-body block-number-response)))
                        (block-by-hash-rpc
                          (parse-json
                           (devnet-cli-http-body block-by-hash-response)))
                        (block-by-hash-result
                          (fixture-object-field block-by-hash-rpc "result"))
                        (candidate-balance-rpc
                          (parse-json
                           (devnet-cli-http-body candidate-balance-response)))
                        (latest-balance-rpc
                          (parse-json
                           (devnet-cli-http-body latest-balance-response)))
                        (receipt-rpc
                          (parse-json
                           (devnet-cli-http-body receipt-response))))
                   (is (string= (quantity-to-hex parent-number)
                                (fixture-object-field block-number-rpc
                                                      "result")))
                   (is (string= child-hash-hex
                                (fixture-object-field block-by-hash-result
                                                      "hash")))
                   (is (string= expected-recipient-balance
                                (fixture-object-field candidate-balance-rpc
                                                      "result")))
                   (is (string= "0x0"
                                (fixture-object-field latest-balance-rpc
                                                      "result")))
                   (is (not (fixture-object-field receipt-rpc "result"))))
                 (handler-case
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body :token token)))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (is (= 200 (devnet-cli-http-status forkchoice-response)))
                 (let* ((forkchoice-rpc
                          (parse-json
                           (devnet-cli-http-body forkchoice-response)))
                        (payload-status
                          (fixture-object-field
                           (fixture-object-field forkchoice-rpc "result")
                           "payloadStatus")))
                   (is (string= +payload-status-valid+
                                (fixture-object-field payload-status
                                                      "status"))))
                 (handler-case
                     (progn
                       (setf post-block-number-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-number-body)))
                       (setf post-balance-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               latest-balance-body)))
                       (setf post-receipt-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               receipt-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (dolist (response (list post-block-number-response
                                         post-balance-response
                                         post-receipt-response))
                   (is (= 200 (devnet-cli-http-status response))))
                 (let* ((block-number-rpc
                          (parse-json
                           (devnet-cli-http-body post-block-number-response)))
                        (balance-rpc
                          (parse-json
                           (devnet-cli-http-body post-balance-response)))
                        (receipt-rpc
                          (parse-json
                           (devnet-cli-http-body post-receipt-response)))
                        (receipt (fixture-object-field receipt-rpc "result")))
                   (is (string= child-number-hex
                                (fixture-object-field block-number-rpc
                                                      "result")))
                   (is (string= expected-recipient-balance
                                (fixture-object-field balance-rpc "result")))
                   (is (string= transaction-hash-hex
                                (fixture-object-field receipt
                                                      "transactionHash")))
                   (is (string= child-hash-hex
                                (fixture-object-field receipt
                                                      "blockHash"))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process :urgent t)
        (devnet-cli-wait-process-exit process 10))
      (dolist (path (list jwt-path
                          genesis-path
                          database-path
                          first-ready-path
                          first-log-path
                          second-ready-path
                          second-log-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-dev-period-seal-survives-sigkill-after-public-visibility
  (:estimated-seconds 80)
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis-path
          (devnet-cli-temp-path
           "ethereum-lisp-dev-period-persistence-genesis" "json"))
        (database-path
          (devnet-cli-temp-path
           "ethereum-lisp-dev-period-persistence-chain" "sexp"))
        (first-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-dev-period-persistence-first-ready" "json"))
        (first-log-path
          (devnet-cli-temp-path
           "ethereum-lisp-dev-period-persistence-first" "log"))
        (second-ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-dev-period-persistence-second-ready" "json"))
        (second-log-path
          (devnet-cli-temp-path
           "ethereum-lisp-dev-period-persistence-second" "log"))
        (process nil))
    (unwind-protect
         (let* ((genesis-json (devnet-cli-funded-txpool-genesis-json))
                (config (chain-config-from-genesis-json-string genesis-json))
                (genesis-block
                  (genesis-block-from-state-genesis-json-string
                   genesis-json :config config))
                (genesis-number
                  (block-header-number (block-header genesis-block)))
                (transaction
                  (devnet-cli-txpool-transaction
                   config 0 +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash-hex
                  (hash32-to-hex (transaction-hash transaction)))
                (send-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 101)
                         (cons "method" "eth_sendRawTransaction")
                         (cons "params"
                               (list
                                (devnet-cli-transaction-raw transaction))))))
                (receipt-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 102)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params" (list transaction-hash-hex)))))
                (block-number-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 103)
                         (cons "method" "eth_blockNumber")
                         (cons "params" #()))))
                (latest-balance-body
                  (json-encode
                   (engine-fixture-balance-request
                    104
                    (address-from-hex +devnet-cli-txpool-recipient+))))
                (txpool-status-body
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 105)
                         (cons "method" "txpool_status")
                         (cons "params" #()))))
                (sealed-block-hash-hex nil)
                (sealed-block-number-hex nil))
           (devnet-cli-write-temp-file genesis-path genesis-json)
           ;; The first process mines locally.  Receipt visibility is the
           ;; publication barrier; it is killed immediately afterwards so no
           ;; lifecycle export can repair a missing synchronous seal commit.
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
                        "--dev.period"
                        "1"
                        "--ready-file"
                        (namestring first-ready-path)
                        "--log-file"
                        (namestring first-log-path)
                        "--max-connections"
                        "200"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file first-ready-path 30)
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
                      (parse-json
                       (devnet-cli-file-string first-ready-path)))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (send-response nil)
                    (receipt nil))
               (is (= genesis-number
                      (fixture-object-field ready-summary "headNumber")))
               (handler-case
                   (progn
                     (setf send-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request send-body)))
                     (setf receipt
                           (devnet-cli-wait-for-non-null-json-rpc-result
                            rpc-endpoint
                            receipt-body
                            20
                            :label "dev-period transaction receipt")))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status send-response)))
               (is (string=
                    transaction-hash-hex
                    (fixture-object-field
                     (parse-json (devnet-cli-http-body send-response))
                     "result")))
               (is (string= transaction-hash-hex
                            (fixture-object-field receipt
                                                  "transactionHash")))
               (setf sealed-block-hash-hex
                     (fixture-object-field receipt "blockHash")
                     sealed-block-number-hex
                     (fixture-object-field receipt "blockNumber"))
               (is (stringp sealed-block-hash-hex))
               (is (string=
                    (quantity-to-hex (1+ genesis-number))
                    sealed-block-number-hex))
               (is (probe-file database-path))
               (uiop:terminate-process process :urgent t)
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (is (not (eq status :timeout))))
               (let ((stderr
                       (devnet-cli-read-stream-string
                        (uiop:process-info-error-output process))))
                 (is (not (search
                           "Devnet shutdown requested; closing RPC listeners."
                           stderr))))
               (is (not (search
                         "devnet.shutdown"
                         (if (probe-file first-log-path)
                             (devnet-cli-file-string first-log-path)
                             "")))))
             ;; Restart without dev-period mining.  Every public view must be
             ;; reconstructed solely from the live seal commit.
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
                          "--max-connections"
                          "100"
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :stream
                    :error-output :stream))
             (unless (devnet-cli-wait-for-file second-ready-path 30)
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
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      (block-by-hash-body
                        (json-encode
                         (engine-fixture-block-by-hash-request
                          106
                          (hash32-from-hex sealed-block-hash-hex)
                          :false)))
                      (block-number-response nil)
                      (block-by-hash-response nil)
                      (receipt-response nil)
                      (balance-response nil)
                      (txpool-response nil))
                 (is (= (hex-to-quantity sealed-block-number-hex)
                        (fixture-object-field ready-summary "headNumber")))
                 (is (string= sealed-block-hash-hex
                              (fixture-object-field ready-summary "headHash")))
                 (is (fixture-object-field ready-summary "stateAvailable"))
                 (handler-case
                     (progn
                       (setf block-number-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-number-body)))
                       (setf block-by-hash-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-by-hash-body)))
                       (setf receipt-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               receipt-body)))
                       (setf balance-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               latest-balance-body)))
                       (setf txpool-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               txpool-status-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (dolist (response
                          (list block-number-response
                                block-by-hash-response
                                receipt-response
                                balance-response
                                txpool-response))
                   (is (= 200 (devnet-cli-http-status response))))
                 (let* ((block-number-rpc
                          (parse-json
                           (devnet-cli-http-body block-number-response)))
                        (block-rpc
                          (parse-json
                           (devnet-cli-http-body block-by-hash-response)))
                        (block
                          (fixture-object-field block-rpc "result"))
                        (transactions
                          (fixture-object-field block "transactions"))
                        (receipt-rpc
                          (parse-json
                           (devnet-cli-http-body receipt-response)))
                        (receipt
                          (fixture-object-field receipt-rpc "result"))
                        (balance-rpc
                          (parse-json
                           (devnet-cli-http-body balance-response)))
                        (txpool-rpc
                          (parse-json
                           (devnet-cli-http-body txpool-response)))
                        (txpool
                          (fixture-object-field txpool-rpc "result")))
                   (is (string=
                        sealed-block-number-hex
                        (fixture-object-field block-number-rpc "result")))
                   (is (string= sealed-block-hash-hex
                                (fixture-object-field block "hash")))
                   (is (= 1 (length transactions)))
                   (is (string= transaction-hash-hex
                                (elt transactions 0)))
                   (is (string= transaction-hash-hex
                                (fixture-object-field receipt
                                                      "transactionHash")))
                   (is (string= sealed-block-hash-hex
                                (fixture-object-field receipt "blockHash")))
                   (is (string= sealed-block-number-hex
                                (fixture-object-field receipt "blockNumber")))
                   (is (string= "0x1"
                                (fixture-object-field balance-rpc "result")))
                   (is (string= "0x0"
                                (fixture-object-field txpool "pending")))
                   (is (string= "0x0"
                                (fixture-object-field txpool "queued"))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process :urgent t)
        (devnet-cli-wait-process-exit process 10))
      (dolist (path (list genesis-path
                          database-path
                          first-ready-path
                          first-log-path
                          second-ready-path
                          second-log-path))
        (when (probe-file path)
          (delete-file path))))))
