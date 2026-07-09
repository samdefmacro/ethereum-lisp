(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-serve-mode-serves-engine-v1-workflow
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1" "jwt"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1-genesis"
                                "json"))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1-ready"
                                "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-v1" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode (devnet-cli-pre-shanghai-genesis-object)))
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string +devnet-cli-jwt-secret+ stream))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :public-port 0))
                  (genesis-block
                    (ethereum-lisp.cli::devnet-node-genesis-block node))
                  (payload-attributes
                    (make-payload-attributes-v1
                     :timestamp
                     (1+ (block-header-timestamp
                          (block-header genesis-block)))
                     :prev-randao (zero-hash32)
                     :suggested-fee-recipient (zero-address)))
                  (child-block
                    (ethereum-lisp.core::engine-build-empty-payload
                     genesis-block
                     payload-attributes))
                  (prepared-block
                    (ethereum-lisp.core::engine-build-empty-payload
                     child-block
                     (make-payload-attributes-v1
                      :timestamp
                      (1+ (block-header-timestamp
                           (block-header child-block)))
                      :prev-randao (zero-hash32)
                      :suggested-fee-recipient (zero-address))))
                  (payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data child-block)))
                  (child-hash (block-hash child-block))
                  (child-hash-hex (hash32-to-hex child-hash))
                  (prepared-block-number
                    (quantity-to-hex
                     (block-header-number (block-header prepared-block))))
                  (prepare-payload-attributes
                    (devnet-cli-payload-attributes-v1 child-block
                                                      (zero-address)))
                  (new-payload-body
                    (json-encode
                     (devnet-cli-engine-new-payload-v1-request 701
                                                               payload)))
                  (forkchoice-body
                    (json-encode
                     (engine-fixture-forkchoice-request
                      702 child-hash
                      :safe (block-hash genesis-block)
                      :finalized (block-hash genesis-block))))
                  (prepare-body
                    (json-encode
                     (devnet-cli-engine-forkchoice-v1-payload-attributes-request
                      703 child-hash prepare-payload-attributes
                      :safe (block-hash genesis-block)
                      :finalized (block-hash genesis-block))))
                  (block-number-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 704)
                           (cons "method" "eth_blockNumber")
                           (cons "params" '()))))
                  (latest-block-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 705)
                           (cons "method" "eth_getBlockByNumber")
                           (cons "params" (list "latest" :false)))))
                  (chain-id-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 706)
                           (cons "method" "eth_chainId")
                           (cons "params" '()))))
                  (net-version-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 707)
                           (cons "method" "net_version")
                           (cons "params" '()))))
                  (client-version-body
                    (json-encode
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 708)
                           (cons "method" "web3_clientVersion")
                           (cons "params" '())))))
             (setf process
                   (uiop:launch-program
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
                          "5"
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
                        (fixture-object-field ready-summary
                                              "engineEndpoint"))
                      (rpc-endpoint
                        (fixture-object-field ready-summary "rpcEndpoint"))
                      (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                      (token (engine-rpc-make-jwt-token jwt-secret 0))
                      new-payload-response
                      forkchoice-response
                      prepare-response
                      get-payload-v1-response
                      get-payload-v2-response
                      block-number-response
                      latest-block-response
                      chain-id-response
                      net-version-response
                      client-version-response)
                 (is (= pid (fixture-object-field ready-summary
                                                   "processId")))
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
                       (setf prepare-response
                             (devnet-cli-http-endpoint-request
                              engine-endpoint
                              (devnet-cli-json-rpc-http-request
                               prepare-body
                               :token token)))
                       (let* ((prepare-json
                                (parse-json
                                 (devnet-cli-http-body prepare-response)))
                              (payload-id
                                (fixture-object-field
                                 (fixture-object-field prepare-json "result")
                                 "payloadId"))
                              (get-payload-v1-body
                                (json-encode
                                 (list (cons "jsonrpc" "2.0")
                                       (cons "id" 709)
                                       (cons "method" "engine_getPayloadV1")
                                       (cons "params" (list payload-id)))))
                              (get-payload-v2-body
                                (json-encode
                                 (list (cons "jsonrpc" "2.0")
                                       (cons "id" 710)
                                       (cons "method" "engine_getPayloadV2")
                                       (cons "params" (list payload-id))))))
                         (setf get-payload-v1-response
                               (devnet-cli-http-endpoint-request
                                engine-endpoint
                                (devnet-cli-json-rpc-http-request
                                 get-payload-v1-body
                                 :token token)))
                         (setf get-payload-v2-response
                               (devnet-cli-http-endpoint-request
                                engine-endpoint
                                (devnet-cli-json-rpc-http-request
                                 get-payload-v2-body
                                 :token token))))
                       (setf block-number-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               block-number-body)))
                       (setf latest-block-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               latest-block-body)))
                       (setf chain-id-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               chain-id-body)))
                       (setf net-version-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               net-version-body)))
                       (setf client-version-response
                             (devnet-cli-http-endpoint-request
                              rpc-endpoint
                              (devnet-cli-json-rpc-http-request
                               client-version-body))))
                   (sb-bsd-sockets:operation-not-permitted-error ()
                     (skip-test
                      "Local socket connect is not permitted in this sandbox")))
                 (is (= 200 (devnet-cli-http-status new-payload-response)))
                 (is (= 200 (devnet-cli-http-status forkchoice-response)))
                 (is (= 200 (devnet-cli-http-status prepare-response)))
                 (is (= 200 (devnet-cli-http-status get-payload-v1-response)))
                 (is (= 200 (devnet-cli-http-status get-payload-v2-response)))
                 (is (= 200 (devnet-cli-http-status block-number-response)))
                 (is (= 200 (devnet-cli-http-status latest-block-response)))
                 (is (= 200 (devnet-cli-http-status chain-id-response)))
                 (is (= 200 (devnet-cli-http-status net-version-response)))
                 (is (= 200 (devnet-cli-http-status
                              client-version-response)))
                 (let* ((new-payload-json
                          (parse-json
                           (devnet-cli-http-body new-payload-response)))
                        (new-payload-result
                          (fixture-object-field new-payload-json "result"))
                        (forkchoice-json
                          (parse-json
                           (devnet-cli-http-body forkchoice-response)))
                        (forkchoice-result
                          (fixture-object-field forkchoice-json "result"))
                        (forkchoice-status
                          (fixture-object-field forkchoice-result
                                                "payloadStatus"))
                        (prepare-json
                          (parse-json
                           (devnet-cli-http-body prepare-response)))
                        (prepare-result
                          (fixture-object-field prepare-json "result"))
                        (prepare-status
                          (fixture-object-field prepare-result
                                                "payloadStatus"))
                        (payload-id
                          (fixture-object-field prepare-result
                                                "payloadId"))
                        (get-payload-v1-json
                          (parse-json
                           (devnet-cli-http-body get-payload-v1-response)))
                        (get-payload-v1-result
                          (fixture-object-field get-payload-v1-json
                                                "result"))
                        (get-payload-v2-json
                          (parse-json
                           (devnet-cli-http-body get-payload-v2-response)))
                        (get-payload-v2-result
                          (fixture-object-field get-payload-v2-json
                                                "result"))
                        (get-payload-v2-payload
                          (fixture-object-field get-payload-v2-result
                                                "executionPayload"))
                        (block-number-json
                          (parse-json
                           (devnet-cli-http-body block-number-response)))
                        (latest-block-json
                          (parse-json
                           (devnet-cli-http-body latest-block-response)))
                        (latest-block
                          (fixture-object-field latest-block-json
                                                "result"))
                        (chain-id-json
                          (parse-json
                           (devnet-cli-http-body chain-id-response)))
                        (net-version-json
                          (parse-json
                           (devnet-cli-http-body net-version-response)))
                        (client-version-json
                          (parse-json
                           (devnet-cli-http-body client-version-response))))
                   (is (= 701 (fixture-object-field new-payload-json "id")))
                   (is (string= "VALID"
                                (fixture-object-field new-payload-result
                                                      "status")))
                   (is (string= child-hash-hex
                                (fixture-object-field new-payload-result
                                                      "latestValidHash")))
                   (is (= 702 (fixture-object-field forkchoice-json "id")))
                   (is (string= "VALID"
                                (fixture-object-field forkchoice-status
                                                      "status")))
                   (is (null (fixture-object-field forkchoice-result
                                                   "payloadId")))
                   (is (= 703 (fixture-object-field prepare-json "id")))
                   (is (string= "VALID"
                                (fixture-object-field prepare-status
                                                      "status")))
                   (is (stringp payload-id))
                   (is (= 18 (length payload-id)))
                   (is (= 709 (fixture-object-field get-payload-v1-json
                                                    "id")))
                   (is (string= child-hash-hex
                                (fixture-object-field get-payload-v1-result
                                                      "parentHash")))
                   (is (string= prepared-block-number
                                (fixture-object-field get-payload-v1-result
                                                      "blockNumber")))
                   (is (= 0 (length (fixture-object-field
                                     get-payload-v1-result
                                     "transactions"))))
                   (is (not (fixture-field-present-p get-payload-v1-result
                                                     "withdrawals")))
                   (is (not (fixture-field-present-p get-payload-v1-result
                                                     "executionPayload")))
                   (is (= 710 (fixture-object-field get-payload-v2-json
                                                    "id")))
                   (is (string= child-hash-hex
                                (fixture-object-field get-payload-v2-payload
                                                      "parentHash")))
                   (is (string= prepared-block-number
                                (fixture-object-field get-payload-v2-payload
                                                      "blockNumber")))
                   (is (string= "0x1"
                                (fixture-object-field block-number-json
                                                      "result")))
                   (is (string= child-hash-hex
                                (fixture-object-field latest-block "hash")))
                   (is (string= "0x1"
                                (fixture-object-field latest-block
                                                      "number")))
                   (is (string= "0x539"
                                (fixture-object-field chain-id-json
                                                      "result")))
                   (is (string= "1337"
                                (fixture-object-field net-version-json
                                                      "result")))
                   (is (search "ethereum-lisp"
                               (fixture-object-field client-version-json
                                                     "result"))))
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
                         (is (string= engine-endpoint
                                      (fixture-object-field stdout-summary
                                                            "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field stdout-summary
                                                            "rpcEndpoint")))
                         (is shutdown-record)
                         (is (string= "5"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "5"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "10"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))))
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
        (delete-file pid-path))))

