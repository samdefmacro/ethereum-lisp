(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-verify-engine-only-kzg-opt-in ()
  #+sbcl
  (labels ((field-present-p (object name)
             (not (null (assoc name object :test #'string=))))
           (forkchoice-state-object (head-hash)
             (list (cons "headBlockHash" head-hash)
                   (cons "safeBlockHash" head-hash)
                   (cons "finalizedBlockHash" head-hash)))
           (withdrawal-object ()
             (list (cons "index" "0x4")
                   (cons "validatorIndex" "0x5")
                   (cons "address" (address-to-hex (zero-address)))
                   (cons "amount" "0x6")))
           (payload-attributes-v3-object
               (timestamp parent-beacon-block-root)
             (list (cons "timestamp" timestamp)
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" (list (withdrawal-object)))
                   (cons "parentBeaconBlockRoot"
                         parent-beacon-block-root)))
           (payload-attributes-v4-object
               (timestamp parent-beacon-block-root slot-number)
             (append
              (payload-attributes-v3-object
               timestamp
               parent-beacon-block-root)
              (list (cons "slotNumber" slot-number))))
           (forkchoice-request (id method head-hash payload-attributes)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params"
                          (list
                           (forkchoice-state-object head-hash)
                           payload-attributes)))))
           (get-payload-request (id method payload-id)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" (list payload-id)))))
           (get-payload-bodies-by-hash-request (id method block-hashes)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" (list block-hashes)))))
           (get-payload-bodies-by-range-request (id method start count)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" (list start count)))))
           (get-blobs-request (id method versioned-hashes)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" (list versioned-hashes)))))
           (hex-prefix (hex bytes)
             (subseq hex 0 (min (length hex) (+ 2 (* bytes 2))))))
    (let* ((script
           (namestring
            (truename
             (merge-pathnames "scripts/ethereum-lisp.lisp"
                              *ethereum-lisp-devnet-smoke-gate-root*))))
         (genesis
           (namestring
            (truename
             (merge-pathnames +devnet-cli-genesis-fixture+
                              *ethereum-lisp-devnet-smoke-gate-root*))))
         (genesis-json
           (parse-json (devnet-smoke-gate-file-string genesis)))
         (blob-database
           (devnet-smoke-gate-write-kzg-prepared-payload-database genesis))
         (database-path
           (getf blob-database :database-path))
         (kzg-command
           (devnet-cli-temp-path "ethereum-lisp-smoke-kzg-command" "sh"))
         (ready-path
           (devnet-cli-temp-path "ethereum-lisp-smoke-kzg-ready" "json"))
         (log-path
           (devnet-cli-temp-path "ethereum-lisp-smoke-kzg" "log"))
         (pid-path
           (devnet-cli-temp-path "ethereum-lisp-smoke-kzg" "pid"))
         (process nil)
         (report nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file kzg-command "#!/bin/sh\necho true\n")
           (devnet-cli-make-executable kzg-command)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        genesis
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http=false"
                        "--database"
                        (namestring database-path)
                        "--kzg.verifier-command"
                        (namestring kzg-command)
                        "--kzg.verifier-timeout"
                        "2"
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
             (error
              "KZG opt-in devnet did not write readiness JSON. stdout=~S stderr=~S"
              (devnet-cli-read-stream-string
               (uiop:process-info-output process))
              (devnet-cli-read-stream-string
               (uiop:process-info-error-output process))))
           (let* ((ready-summary
                    (parse-json (devnet-smoke-gate-file-string ready-path)))
                  (raw-engine-endpoint
                        (fixture-object-field ready-summary "engineEndpoint"))
                  (engine-endpoint
                    (and raw-engine-endpoint
                         (if (uiop:string-prefix-p
                              "http://"
                              raw-engine-endpoint)
                             raw-engine-endpoint
                             (format nil "http://~A"
                                     raw-engine-endpoint))))
                  (head-hash
                    (fixture-object-field ready-summary "headHash"))
                  (head-number
                    (fixture-object-field ready-summary "headNumber"))
                  (next-block-number
                    (quantity-to-hex (1+ head-number)))
                  (genesis-timestamp
                    (fixture-quantity-field genesis-json "timestamp"))
                  (v3-parent-beacon-block-root
                    "0x3333333333333333333333333333333333333333333333333333333333333333")
                  (v4-parent-beacon-block-root
                    "0x4444444444444444444444444444444444444444444444444444444444444444")
                  (v3-timestamp
                    (quantity-to-hex (1+ genesis-timestamp)))
                  (v4-timestamp
                    (quantity-to-hex (+ genesis-timestamp 2)))
                  (v4-slot-number "0x2a")
                  (unknown-versioned-hash
                    (hash32-to-hex
                     (make-hash32
                      (make-byte-vector 32 :initial-element #x11))))
                  (capabilities-body
                    "{\"jsonrpc\":\"2.0\",\"id\":715,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                  (capabilities-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request capabilities-body)))
                  (capabilities-rpc
                    (parse-json (devnet-cli-http-body capabilities-response)))
                  (capabilities-result
                    (fixture-object-field capabilities-rpc "result"))
                  (prepare-v3-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (forkchoice-request
                       716
                       "engine_forkchoiceUpdatedV3"
                       head-hash
                       (payload-attributes-v3-object
                        v3-timestamp
                        v3-parent-beacon-block-root)))))
                  (prepare-v3-rpc
                    (parse-json (devnet-cli-http-body prepare-v3-response)))
                  (prepare-v3-result
                    (fixture-object-field prepare-v3-rpc "result"))
                  (prepare-v3-status
                    (fixture-object-field prepare-v3-result "payloadStatus"))
                  (payload-id-v3
                    (fixture-object-field prepare-v3-result "payloadId"))
                  (get-payload-v3-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-request
                       717
                       "engine_getPayloadV3"
                       payload-id-v3))))
                  (get-payload-v3-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-v3-response)))
                  (payload-envelope-v3
                    (fixture-object-field get-payload-v3-rpc "result"))
                  (execution-payload-v3
                    (fixture-object-field payload-envelope-v3
                                          "executionPayload"))
                  (blobs-bundle-v3
                    (fixture-object-field payload-envelope-v3
                                          "blobsBundle"))
                  (prepare-v4-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (forkchoice-request
                       718
                       "engine_forkchoiceUpdatedV4"
                       head-hash
                       (payload-attributes-v4-object
                        v4-timestamp
                        v4-parent-beacon-block-root
                        v4-slot-number)))))
                  (prepare-v4-rpc
                    (parse-json (devnet-cli-http-body prepare-v4-response)))
                  (prepare-v4-result
                    (fixture-object-field prepare-v4-rpc "result"))
                  (prepare-v4-status
                    (fixture-object-field prepare-v4-result "payloadStatus"))
                  (payload-id-v4
                    (fixture-object-field prepare-v4-result "payloadId"))
                  (get-payload-v4-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-request
                       719
                       "engine_getPayloadV4"
                       payload-id-v4))))
                  (get-payload-v4-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-v4-response)))
                  (payload-envelope-v4
                    (fixture-object-field get-payload-v4-rpc "result"))
                  (execution-payload-v4
                    (fixture-object-field payload-envelope-v4
                                          "executionPayload"))
                  (blobs-bundle-v4
                    (fixture-object-field payload-envelope-v4
                                          "blobsBundle"))
                  (get-payload-v5-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-request
                       720
                       "engine_getPayloadV5"
                       (getf blob-database :payload-id-v5)))))
                  (get-payload-v5-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-v5-response)))
                  (payload-envelope-v5
                    (fixture-object-field get-payload-v5-rpc "result"))
                  (execution-payload-v5
                    (fixture-object-field payload-envelope-v5
                                          "executionPayload"))
                  (blobs-bundle-v5
                    (fixture-object-field payload-envelope-v5
                                          "blobsBundle"))
                  (get-payload-v6-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-request
                       721
                       "engine_getPayloadV6"
                       (getf blob-database :payload-id-v6)))))
                  (get-payload-v6-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-v6-response)))
                  (payload-envelope-v6
                    (fixture-object-field get-payload-v6-rpc "result"))
                  (execution-payload-v6
                    (fixture-object-field payload-envelope-v6
                                          "executionPayload"))
                  (execution-requests-v6
                    (fixture-object-field payload-envelope-v6
                                          "executionRequests"))
                  (blobs-bundle-v6
                    (fixture-object-field payload-envelope-v6
                                          "blobsBundle"))
                  (get-payload-bodies-v2-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-hash-request
                       722
                       "engine_getPayloadBodiesByHashV2"
                       (list (getf blob-database :block-hash-v6))))))
                  (get-payload-bodies-v2-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-bodies-v2-response)))
                  (get-payload-bodies-v2-result
                    (fixture-object-field get-payload-bodies-v2-rpc "result"))
                  (payload-body-v2
                    (first get-payload-bodies-v2-result))
                  (payload-body-v2-transactions
                    (and payload-body-v2
                         (fixture-object-field payload-body-v2
                                               "transactions")))
                  (payload-body-v2-withdrawals
                    (and payload-body-v2
                         (fixture-object-field payload-body-v2
                                               "withdrawals")))
                  (select-v6-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (forkchoice-request
                       723
                       "engine_forkchoiceUpdatedV2"
                       (getf blob-database :block-hash-v6)
                       nil))))
                  (select-v6-rpc
                    (parse-json
                     (devnet-cli-http-body select-v6-response)))
                  (select-v6-result
                    (fixture-object-field select-v6-rpc "result"))
                  (select-v6-status
                    (fixture-object-field select-v6-result "payloadStatus"))
                  (payload-bodies-range-v2-start-block
                    (quantity-to-hex
                     (1- (hex-to-quantity
                          (getf blob-database :block-number-v6)))))
                  (get-payload-bodies-range-v2-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       724
                       "engine_getPayloadBodiesByRangeV2"
                       payload-bodies-range-v2-start-block
                       "0x2"))))
                  (get-payload-bodies-range-v2-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-response)))
                  (get-payload-bodies-range-v2-result
                    (fixture-object-field get-payload-bodies-range-v2-rpc
                                          "result"))
                  (get-payload-bodies-range-v2-zero-start-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       729
                       "engine_getPayloadBodiesByRangeV2"
                       "0x0"
                       "0x1"))))
                  (get-payload-bodies-range-v2-zero-start-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-zero-start-response)))
                  (get-payload-bodies-range-v2-zero-start-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-zero-start-rpc
                     "error"))
                  (get-payload-bodies-range-v2-zero-count-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       730
                       "engine_getPayloadBodiesByRangeV2"
                       payload-bodies-range-v2-start-block
                       "0x0"))))
                  (get-payload-bodies-range-v2-zero-count-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-zero-count-response)))
                  (get-payload-bodies-range-v2-zero-count-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-zero-count-rpc
                     "error"))
                  (get-payload-bodies-range-v2-malformed-start-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       731
                       "engine_getPayloadBodiesByRangeV2"
                       "0xzz"
                       "0x1"))))
                  (get-payload-bodies-range-v2-malformed-start-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-malformed-start-response)))
                  (get-payload-bodies-range-v2-malformed-start-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-malformed-start-rpc
                     "error"))
                  (get-payload-bodies-range-v2-malformed-count-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       732
                       "engine_getPayloadBodiesByRangeV2"
                       payload-bodies-range-v2-start-block
                       "0xzz"))))
                  (get-payload-bodies-range-v2-malformed-count-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-malformed-count-response)))
                  (get-payload-bodies-range-v2-malformed-count-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-malformed-count-rpc
                     "error"))
                  (get-payload-bodies-range-v2-params-envelope-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 733)
                             (cons "method"
                                   "engine_getPayloadBodiesByRangeV2")
                             (cons "params"
                                   (list payload-bodies-range-v2-start-block)))))))
                  (get-payload-bodies-range-v2-params-envelope-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-params-envelope-response)))
                  (get-payload-bodies-range-v2-params-envelope-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-params-envelope-rpc
                     "error"))
                  (get-payload-bodies-range-v2-invalid-request-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 734)
                             (cons "method"
                                   "engine_getPayloadBodiesByRangeV2")
                             (cons "params" "0x1"))))))
                  (get-payload-bodies-range-v2-invalid-request-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-invalid-request-response)))
                  (get-payload-bodies-range-v2-invalid-request-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-invalid-request-rpc
                     "error"))
                  (get-payload-bodies-range-v2-null-params-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 735)
                             (cons "method"
                                   "engine_getPayloadBodiesByRangeV2")
                             (cons "params" nil))))))
                  (get-payload-bodies-range-v2-null-params-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-null-params-response)))
                  (get-payload-bodies-range-v2-null-params-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-null-params-rpc
                     "error"))
                  (get-payload-bodies-range-v2-object-params-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 736)
                             (cons "method"
                                   "engine_getPayloadBodiesByRangeV2")
                             (cons "params"
                                   (list (cons "start" "0x1")
                                         (cons "count" "0x1"))))))))
                  (get-payload-bodies-range-v2-object-params-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-object-params-response)))
                  (get-payload-bodies-range-v2-object-params-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-object-params-rpc
                     "error"))
                  (get-payload-bodies-range-v2-missing-start-object-params-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      "{\"jsonrpc\":\"2.0\",\"id\":737,\"method\":\"engine_getPayloadBodiesByRangeV2\",\"params\":{\"count\":\"0x1\"}}")))
                  (get-payload-bodies-range-v2-missing-start-object-params-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-missing-start-object-params-response)))
                  (get-payload-bodies-range-v2-missing-start-object-params-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-missing-start-object-params-rpc
                     "error"))
                  (get-payload-bodies-range-v2-missing-count-object-params-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      "{\"jsonrpc\":\"2.0\",\"id\":738,\"method\":\"engine_getPayloadBodiesByRangeV2\",\"params\":{\"start\":\"0x1\"}}")))
                  (get-payload-bodies-range-v2-missing-count-object-params-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-missing-count-object-params-response)))
                  (get-payload-bodies-range-v2-missing-count-object-params-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-missing-count-object-params-rpc
                     "error"))
                  (get-payload-bodies-range-v2-unexpected-key-object-params-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      "{\"jsonrpc\":\"2.0\",\"id\":739,\"method\":\"engine_getPayloadBodiesByRangeV2\",\"params\":{\"foo\":\"0x1\"}}")))
                  (get-payload-bodies-range-v2-unexpected-key-object-params-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-unexpected-key-object-params-response)))
                  (get-payload-bodies-range-v2-unexpected-key-object-params-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-unexpected-key-object-params-rpc
                     "error"))
                  (get-payload-bodies-range-v2-empty-object-params-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      "{\"jsonrpc\":\"2.0\",\"id\":740,\"method\":\"engine_getPayloadBodiesByRangeV2\",\"params\":{}}")))
                  (get-payload-bodies-range-v2-empty-object-params-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-empty-object-params-response)))
                  (get-payload-bodies-range-v2-empty-object-params-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-empty-object-params-rpc
                     "error"))
                  (get-payload-bodies-range-v2-oversized-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       728
                       "engine_getPayloadBodiesByRangeV2"
                       payload-bodies-range-v2-start-block
                       "0x401"))))
                  (get-payload-bodies-range-v2-oversized-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-oversized-response)))
                  (get-payload-bodies-range-v2-oversized-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-oversized-rpc
                     "error"))
                  (missing-payload-body-range-v2
                    (first get-payload-bodies-range-v2-result))
                  (payload-body-range-v2
                    (second get-payload-bodies-range-v2-result))
                  (payload-body-range-v2-transactions
                    (and payload-body-range-v2
                         (fixture-object-field payload-body-range-v2
                                               "transactions")))
                  (payload-body-range-v2-withdrawals
                    (and payload-body-range-v2
                         (fixture-object-field payload-body-range-v2
                                               "withdrawals")))
                  (get-blobs-v1-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-blobs-request
                       725
                       "engine_getBlobsV1"
                       (list (getf blob-database :versioned-hash-hex)
                             unknown-versioned-hash)))))
                  (get-blobs-v1-rpc
                    (parse-json
                     (devnet-cli-http-body get-blobs-v1-response)))
                  (get-blobs-v1-result
                    (fixture-object-field get-blobs-v1-rpc "result"))
                  (direct-blob-v1
                    (first get-blobs-v1-result))
                  (missing-blob-v1
                    (second get-blobs-v1-result))
                  (get-blobs-v2-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-blobs-request
                       726
                       "engine_getBlobsV2"
                       (list (getf blob-database :versioned-hash-hex))))))
                  (get-blobs-v2-rpc
                    (parse-json
                     (devnet-cli-http-body get-blobs-v2-response)))
                  (get-blobs-v2-result
                    (fixture-object-field get-blobs-v2-rpc "result"))
                  (direct-blob-v2
                    (first get-blobs-v2-result))
                  (direct-blob-v2-proofs
                    (fixture-object-field direct-blob-v2 "proofs"))
                  (get-blobs-v3-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-blobs-request
                       727
                       "engine_getBlobsV3"
                       (list (getf blob-database :versioned-hash-hex)
                             unknown-versioned-hash)))))
                  (get-blobs-v3-rpc
                    (parse-json
                     (devnet-cli-http-body get-blobs-v3-response)))
                  (get-blobs-v3-result
                    (fixture-object-field get-blobs-v3-rpc "result"))
                  (direct-blob-v3
                    (first get-blobs-v3-result))
                  (direct-blob-v3-proofs
                    (fixture-object-field direct-blob-v3 "proofs"))
                  (missing-blob-v3
                    (second get-blobs-v3-result)))
             (devnet-smoke-gate-require
              (stringp engine-endpoint)
              "KZG opt-in ready file omitted Engine endpoint")
             (devnet-smoke-gate-require
              (not (fixture-object-field ready-summary "rpcEndpoint"))
              "KZG opt-in ready file must disable public rpcEndpoint")
             (devnet-smoke-gate-require
              (not (fixture-object-field ready-summary "publicRpcEnabled"))
              "KZG opt-in ready file must disable publicRpcEnabled")
             (devnet-smoke-gate-require
              (string= (namestring kzg-command)
                       (fixture-object-field ready-summary
                                             "kzgVerifierCommand"))
              "KZG opt-in ready file verifier command mismatch")
             (devnet-smoke-gate-require
              (= 2 (fixture-object-field ready-summary
                                          "kzgVerifierTimeoutSeconds"))
              "KZG opt-in ready file verifier timeout mismatch")
             (devnet-smoke-gate-require
              (fixture-object-field ready-summary
                                    "kzgProofVerificationAvailable")
              "KZG opt-in ready file did not expose proof availability")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status capabilities-response))
              "KZG opt-in engine_exchangeCapabilities HTTP status mismatch")
             (devnet-smoke-gate-require
              (= 715 (fixture-object-field capabilities-rpc "id"))
              "KZG opt-in engine_exchangeCapabilities id mismatch")
             (dolist (method '("engine_forkchoiceUpdatedV3"
                               "engine_forkchoiceUpdatedV4"
                               "engine_getPayloadV3"
                               "engine_getPayloadV4"
                               "engine_getPayloadV5"
                               "engine_getPayloadV6"
                               "engine_newPayloadV3"
                               "engine_getBlobsV1"
                               "engine_getBlobsV2"
                               "engine_getBlobsV3"
                               "engine_getPayloadBodiesByHashV2"
                               "engine_getPayloadBodiesByRangeV2"))
               (devnet-smoke-gate-require
                (member method capabilities-result :test #'string=)
                "KZG opt-in capabilities omitted ~A from ~S"
                method
                capabilities-result))
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status prepare-v3-response))
              "KZG opt-in engine_forkchoiceUpdatedV3 HTTP status mismatch")
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field prepare-v3-status "status"))
              "KZG opt-in engine_forkchoiceUpdatedV3 status mismatch")
             (devnet-smoke-gate-require
              (and (stringp payload-id-v3)
                   (= 18 (length payload-id-v3))
                   (string= "03" (subseq payload-id-v3 2 4)))
              "KZG opt-in engine_forkchoiceUpdatedV3 did not return a V3 payload id")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-v3-response))
              "KZG opt-in engine_getPayloadV3 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-v3-rpc "error"))
              "KZG opt-in engine_getPayloadV3 returned an error: ~S"
              (fixture-object-field get-payload-v3-rpc "error"))
             (devnet-smoke-gate-require
              (string= head-hash
                       (fixture-object-field execution-payload-v3
                                             "parentHash"))
              "KZG opt-in engine_getPayloadV3 parentHash mismatch")
             (devnet-smoke-gate-require
              (string= next-block-number
                       (fixture-object-field execution-payload-v3
                                             "blockNumber"))
              "KZG opt-in engine_getPayloadV3 blockNumber mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field payload-envelope-v3
                                         "shouldOverrideBuilder"))
              "KZG opt-in engine_getPayloadV3 shouldOverrideBuilder mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v3 "blobsBundle")
              "KZG opt-in engine_getPayloadV3 omitted blobsBundle")
             (dolist (field '("commitments" "proofs" "blobs"))
               (devnet-smoke-gate-require
                (field-present-p blobs-bundle-v3 field)
                "KZG opt-in engine_getPayloadV3 blobsBundle omitted ~A"
                field)
               (devnet-smoke-gate-require
                (listp (fixture-object-field blobs-bundle-v3 field))
                "KZG opt-in engine_getPayloadV3 blobsBundle ~A must be a JSON array"
                field))
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status prepare-v4-response))
              "KZG opt-in engine_forkchoiceUpdatedV4 HTTP status mismatch")
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field prepare-v4-status "status"))
              "KZG opt-in engine_forkchoiceUpdatedV4 status mismatch")
             (devnet-smoke-gate-require
              (and (stringp payload-id-v4)
                   (= 18 (length payload-id-v4))
                   (string= "04" (subseq payload-id-v4 2 4)))
              "KZG opt-in engine_forkchoiceUpdatedV4 did not return a V4 payload id")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-v4-response))
              "KZG opt-in engine_getPayloadV4 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-v4-rpc "error"))
              "KZG opt-in engine_getPayloadV4 returned an error: ~S"
              (fixture-object-field get-payload-v4-rpc "error"))
             (devnet-smoke-gate-require
              (string= head-hash
                       (fixture-object-field execution-payload-v4
                                             "parentHash"))
              "KZG opt-in engine_getPayloadV4 parentHash mismatch")
             (devnet-smoke-gate-require
              (string= next-block-number
                       (fixture-object-field execution-payload-v4
                                             "blockNumber"))
              "KZG opt-in engine_getPayloadV4 blockNumber mismatch")
             (devnet-smoke-gate-require
              (string= v4-slot-number
                       (fixture-object-field execution-payload-v4
                                             "slotNumber"))
              "KZG opt-in engine_getPayloadV4 slotNumber mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field payload-envelope-v4
                                         "shouldOverrideBuilder"))
              "KZG opt-in engine_getPayloadV4 shouldOverrideBuilder mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v4 "blobsBundle")
              "KZG opt-in engine_getPayloadV4 omitted blobsBundle")
             (dolist (field '("commitments" "proofs" "blobs"))
               (devnet-smoke-gate-require
                (field-present-p blobs-bundle-v4 field)
                "KZG opt-in engine_getPayloadV4 blobsBundle omitted ~A"
                field)
               (devnet-smoke-gate-require
                (listp (fixture-object-field blobs-bundle-v4 field))
                "KZG opt-in engine_getPayloadV4 blobsBundle ~A must be a JSON array"
                field))
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-v5-response))
              "KZG opt-in engine_getPayloadV5 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-v5-rpc "error"))
              "KZG opt-in engine_getPayloadV5 returned an error: ~S"
              (fixture-object-field get-payload-v5-rpc "error"))
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-number)
                       (fixture-object-field execution-payload-v5
                                             "blockNumber"))
              "KZG opt-in engine_getPayloadV5 blockNumber mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v5 "blobsBundle")
              "KZG opt-in engine_getPayloadV5 omitted blobsBundle")
             (devnet-smoke-gate-require
              (= 1 (length (fixture-object-field blobs-bundle-v5 "blobs")))
              "KZG opt-in engine_getPayloadV5 blob count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (first (fixture-object-field blobs-bundle-v5 "blobs")))
              "KZG opt-in engine_getPayloadV5 blob mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :commitment-hex)
                       (first (fixture-object-field
                               blobs-bundle-v5
                               "commitments")))
              "KZG opt-in engine_getPayloadV5 commitment mismatch")
             (devnet-smoke-gate-require
              (= (getf blob-database :cell-proof-count)
                 (length (fixture-object-field blobs-bundle-v5 "proofs")))
              "KZG opt-in engine_getPayloadV5 proof count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :proof-hex)
                       (first (fixture-object-field blobs-bundle-v5 "proofs")))
              "KZG opt-in engine_getPayloadV5 proof mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-v6-response))
              "KZG opt-in engine_getPayloadV6 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-v6-rpc "error"))
              "KZG opt-in engine_getPayloadV6 returned an error: ~S"
              (fixture-object-field get-payload-v6-rpc "error"))
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-number-v6)
                       (fixture-object-field execution-payload-v6
                                             "blockNumber"))
              "KZG opt-in engine_getPayloadV6 blockNumber mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :slot-number-v6)
                       (fixture-object-field execution-payload-v6
                                             "slotNumber"))
              "KZG opt-in engine_getPayloadV6 slotNumber mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v6 "executionRequests")
              "KZG opt-in engine_getPayloadV6 omitted executionRequests")
             (devnet-smoke-gate-require
              (and (listp execution-requests-v6)
                   (= 1 (length execution-requests-v6)))
              "KZG opt-in engine_getPayloadV6 execution request count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :execution-request-hex)
                       (first execution-requests-v6))
              "KZG opt-in engine_getPayloadV6 execution request mismatch")
             (devnet-smoke-gate-require
              (field-present-p execution-payload-v6 "blockAccessList")
              "KZG opt-in engine_getPayloadV6 omitted blockAccessList")
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-access-list-hex)
                       (fixture-object-field execution-payload-v6
                                             "blockAccessList"))
              "KZG opt-in engine_getPayloadV6 blockAccessList mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v6 "blobsBundle")
              "KZG opt-in engine_getPayloadV6 omitted blobsBundle")
             (devnet-smoke-gate-require
              (= 1 (length (fixture-object-field blobs-bundle-v6 "blobs")))
              "KZG opt-in engine_getPayloadV6 blob count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (first (fixture-object-field blobs-bundle-v6 "blobs")))
              "KZG opt-in engine_getPayloadV6 blob mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :commitment-hex)
                       (first (fixture-object-field
                               blobs-bundle-v6
                               "commitments")))
              "KZG opt-in engine_getPayloadV6 commitment mismatch")
             (devnet-smoke-gate-require
              (= (getf blob-database :cell-proof-count)
                 (length (fixture-object-field blobs-bundle-v6 "proofs")))
              "KZG opt-in engine_getPayloadV6 proof count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :proof-hex)
                       (first (fixture-object-field blobs-bundle-v6 "proofs")))
              "KZG opt-in engine_getPayloadV6 proof mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-bodies-v2-response))
              "KZG opt-in engine_getPayloadBodiesByHashV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-bodies-v2-rpc "error"))
              "KZG opt-in engine_getPayloadBodiesByHashV2 returned an error: ~S"
              (fixture-object-field get-payload-bodies-v2-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-payload-bodies-v2-result)
                   (= 1 (length get-payload-bodies-v2-result)))
              "KZG opt-in engine_getPayloadBodiesByHashV2 result count mismatch: ~S"
              get-payload-bodies-v2-result)
             (devnet-smoke-gate-require
              payload-body-v2
              "KZG opt-in engine_getPayloadBodiesByHashV2 returned null for prepared V6 block")
             (devnet-smoke-gate-require
              (assoc "transactions" payload-body-v2 :test #'string=)
              "KZG opt-in engine_getPayloadBodiesByHashV2 omitted transactions")
             (devnet-smoke-gate-require
              (listp payload-body-v2-transactions)
              "KZG opt-in engine_getPayloadBodiesByHashV2 transactions must be a JSON array")
             (devnet-smoke-gate-require
              (null payload-body-v2-transactions)
              "KZG opt-in engine_getPayloadBodiesByHashV2 transactions mismatch: ~S"
              payload-body-v2-transactions)
             (devnet-smoke-gate-require
              (assoc "withdrawals" payload-body-v2 :test #'string=)
              "KZG opt-in engine_getPayloadBodiesByHashV2 omitted withdrawals")
             (devnet-smoke-gate-require
              (listp payload-body-v2-withdrawals)
              "KZG opt-in engine_getPayloadBodiesByHashV2 withdrawals must be a JSON array")
             (devnet-smoke-gate-require
              (null payload-body-v2-withdrawals)
              "KZG opt-in engine_getPayloadBodiesByHashV2 withdrawals mismatch: ~S"
              payload-body-v2-withdrawals)
             (devnet-smoke-gate-require
              (field-present-p payload-body-v2 "blockAccessList")
              "KZG opt-in engine_getPayloadBodiesByHashV2 omitted blockAccessList")
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-access-list-hex)
                       (fixture-object-field payload-body-v2
                                             "blockAccessList"))
              "KZG opt-in engine_getPayloadBodiesByHashV2 blockAccessList mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status select-v6-response))
              "KZG opt-in engine_forkchoiceUpdatedV2 selection HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field select-v6-rpc "error"))
              "KZG opt-in engine_forkchoiceUpdatedV2 selection returned an error: ~S"
              (fixture-object-field select-v6-rpc "error"))
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field select-v6-status "status"))
              "KZG opt-in engine_forkchoiceUpdatedV2 selection status mismatch: ~S"
              select-v6-status)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-bodies-range-v2-response))
              "KZG opt-in engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-bodies-range-v2-rpc "error"))
              "KZG opt-in engine_getPayloadBodiesByRangeV2 returned an error: ~S"
              (fixture-object-field get-payload-bodies-range-v2-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-payload-bodies-range-v2-result)
                   (= 2 (length get-payload-bodies-range-v2-result)))
              "KZG opt-in engine_getPayloadBodiesByRangeV2 result count mismatch: ~S"
              get-payload-bodies-range-v2-result)
             (devnet-smoke-gate-require
              (null missing-payload-body-range-v2)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 sparse range lost the leading null placeholder: ~S"
              get-payload-bodies-range-v2-result)
             (devnet-smoke-gate-require
              payload-body-range-v2
              "KZG opt-in engine_getPayloadBodiesByRangeV2 returned null for prepared V6 block range hit")
             (devnet-smoke-gate-require
              (assoc "transactions" payload-body-range-v2 :test #'string=)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 omitted transactions")
             (devnet-smoke-gate-require
              (listp payload-body-range-v2-transactions)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 transactions must be a JSON array")
             (devnet-smoke-gate-require
              (null payload-body-range-v2-transactions)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 transactions mismatch: ~S"
              payload-body-range-v2-transactions)
             (devnet-smoke-gate-require
              (assoc "withdrawals" payload-body-range-v2 :test #'string=)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 omitted withdrawals")
             (devnet-smoke-gate-require
              (listp payload-body-range-v2-withdrawals)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 withdrawals must be a JSON array")
             (devnet-smoke-gate-require
              (null payload-body-range-v2-withdrawals)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 withdrawals mismatch: ~S"
              payload-body-range-v2-withdrawals)
             (devnet-smoke-gate-require
              (field-present-p payload-body-range-v2 "blockAccessList")
              "KZG opt-in engine_getPayloadBodiesByRangeV2 omitted blockAccessList")
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-access-list-hex)
                       (fixture-object-field payload-body-range-v2
                                             "blockAccessList"))
              "KZG opt-in engine_getPayloadBodiesByRangeV2 blockAccessList mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-zero-start-response))
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-zero-start-error
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-zero-start-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-zero-start-error
                  "code"))
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-zero-start-error)
             (devnet-smoke-gate-require
              (string= "start and count must be positive numbers"
                       (fixture-object-field
                        get-payload-bodies-range-v2-zero-start-error
                        "message"))
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-zero-start-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-zero-start-rpc
                                    "result"))
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-zero-start-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-zero-count-response))
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-zero-count-error
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-zero-count-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-zero-count-error
                  "code"))
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-zero-count-error)
             (devnet-smoke-gate-require
              (string= "start and count must be positive numbers"
                       (fixture-object-field
                        get-payload-bodies-range-v2-zero-count-error
                        "message"))
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-zero-count-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-zero-count-rpc
                                    "result"))
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-zero-count-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-malformed-start-response))
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-malformed-start-error
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-malformed-start-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-malformed-start-error
                  "code"))
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-malformed-start-error)
             (devnet-smoke-gate-require
              (string= "start must be a non-negative quantity"
                       (fixture-object-field
                        get-payload-bodies-range-v2-malformed-start-error
                        "message"))
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-malformed-start-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-malformed-start-rpc
                                    "result"))
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-malformed-start-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-malformed-count-response))
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-malformed-count-error
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-malformed-count-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-malformed-count-error
                  "code"))
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-malformed-count-error)
             (devnet-smoke-gate-require
             (string= "count must be a non-negative quantity"
                       (fixture-object-field
                        get-payload-bodies-range-v2-malformed-count-error
                        "message"))
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-malformed-count-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-malformed-count-rpc
                                    "result"))
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-malformed-count-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-params-envelope-response))
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-params-envelope-error
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-params-envelope-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-params-envelope-error
                  "code"))
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-params-envelope-error)
             (devnet-smoke-gate-require
              (string= "engine_getPayloadBodiesByRangeV2 param count is missing"
                       (fixture-object-field
                        get-payload-bodies-range-v2-params-envelope-error
                        "message"))
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-params-envelope-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-params-envelope-rpc
                    "result"))
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-params-envelope-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-invalid-request-response))
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-invalid-request-error
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-invalid-request-rpc)
             (devnet-smoke-gate-require
              (= -32600
                 (fixture-object-field
                  get-payload-bodies-range-v2-invalid-request-error
                  "code"))
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-invalid-request-error)
             (devnet-smoke-gate-require
              (string= "Invalid Request"
                       (fixture-object-field
                        get-payload-bodies-range-v2-invalid-request-error
                        "message"))
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-invalid-request-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-invalid-request-rpc
                    "result"))
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-invalid-request-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-null-params-response))
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-null-params-error
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-null-params-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-null-params-error
                  "code"))
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-null-params-error)
             (devnet-smoke-gate-require
              (string= "engine_getPayloadBodiesByRangeV2 params must include start and count"
                       (fixture-object-field
                        get-payload-bodies-range-v2-null-params-error
                        "message"))
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-null-params-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-null-params-rpc
                    "result"))
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-null-params-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-object-params-response))
              "KZG opt-in object-params engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-object-params-error
              "KZG opt-in object-params engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-object-params-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-object-params-error
                  "code"))
              "KZG opt-in object-params engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-object-params-error)
             (devnet-smoke-gate-require
              (string= "start must be a non-negative quantity"
                       (fixture-object-field
                        get-payload-bodies-range-v2-object-params-error
                        "message"))
              "KZG opt-in object-params engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-object-params-error)
             (devnet-smoke-gate-require
             (not (field-present-p
                    get-payload-bodies-range-v2-object-params-rpc
                    "result"))
              "KZG opt-in object-params engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-object-params-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-missing-start-object-params-response))
              "KZG opt-in missing-start-object-params engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-missing-start-object-params-error
              "KZG opt-in missing-start-object-params engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-missing-start-object-params-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-missing-start-object-params-error
                  "code"))
              "KZG opt-in missing-start-object-params engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-missing-start-object-params-error)
             (devnet-smoke-gate-require
              (string= "start must be a non-negative quantity"
                       (fixture-object-field
                        get-payload-bodies-range-v2-missing-start-object-params-error
                        "message"))
              "KZG opt-in missing-start-object-params engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-missing-start-object-params-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-missing-start-object-params-rpc
                    "result"))
              "KZG opt-in missing-start-object-params engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-missing-start-object-params-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-missing-count-object-params-response))
              "KZG opt-in missing-count-object-params engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-missing-count-object-params-error
              "KZG opt-in missing-count-object-params engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-missing-count-object-params-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-missing-count-object-params-error
                  "code"))
              "KZG opt-in missing-count-object-params engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-missing-count-object-params-error)
             (devnet-smoke-gate-require
              (string= "start must be a non-negative quantity"
                       (fixture-object-field
                        get-payload-bodies-range-v2-missing-count-object-params-error
                        "message"))
              "KZG opt-in missing-count-object-params engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-missing-count-object-params-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-missing-count-object-params-rpc
                    "result"))
              "KZG opt-in missing-count-object-params engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-missing-count-object-params-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-unexpected-key-object-params-response))
              "KZG opt-in unexpected-key-object-params engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-unexpected-key-object-params-error
              "KZG opt-in unexpected-key-object-params engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-unexpected-key-object-params-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-unexpected-key-object-params-error
                  "code"))
              "KZG opt-in unexpected-key-object-params engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-unexpected-key-object-params-error)
             (devnet-smoke-gate-require
              (string= "start must be a non-negative quantity"
                       (fixture-object-field
                        get-payload-bodies-range-v2-unexpected-key-object-params-error
                        "message"))
              "KZG opt-in unexpected-key-object-params engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-unexpected-key-object-params-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-unexpected-key-object-params-rpc
                    "result"))
              "KZG opt-in unexpected-key-object-params engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-unexpected-key-object-params-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-empty-object-params-response))
              "KZG opt-in empty-object-params engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-empty-object-params-error
              "KZG opt-in empty-object-params engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-empty-object-params-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-empty-object-params-error
                  "code"))
              "KZG opt-in empty-object-params engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-empty-object-params-error)
             (devnet-smoke-gate-require
              (string= "engine_getPayloadBodiesByRangeV2 params must include start and count"
                       (fixture-object-field
                        get-payload-bodies-range-v2-empty-object-params-error
                        "message"))
              "KZG opt-in empty-object-params engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-empty-object-params-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-empty-object-params-rpc
                    "result"))
              "KZG opt-in empty-object-params engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-empty-object-params-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-oversized-response))
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-oversized-error
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-oversized-rpc)
             (devnet-smoke-gate-require
              (= -38004
                 (fixture-object-field
                  get-payload-bodies-range-v2-oversized-error
                  "code"))
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-oversized-error)
             (devnet-smoke-gate-require
              (string= "The number of requested bodies must not exceed 1024"
                       (fixture-object-field
                        get-payload-bodies-range-v2-oversized-error
                        "message"))
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-oversized-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-oversized-rpc
                                    "result"))
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-oversized-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-blobs-v1-response))
              "KZG opt-in engine_getBlobsV1 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-blobs-v1-rpc "error"))
              "KZG opt-in engine_getBlobsV1 returned an error: ~S"
              (fixture-object-field get-blobs-v1-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-blobs-v1-result)
                   (= 2 (length get-blobs-v1-result)))
              "KZG opt-in engine_getBlobsV1 result count mismatch: ~S"
              get-blobs-v1-result)
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v1 "blob")
              "KZG opt-in engine_getBlobsV1 omitted blob")
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v1 "proof")
              "KZG opt-in engine_getBlobsV1 omitted proof")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (fixture-object-field direct-blob-v1 "blob"))
              "KZG opt-in engine_getBlobsV1 blob mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :proof-hex)
                       (fixture-object-field direct-blob-v1 "proof"))
              "KZG opt-in engine_getBlobsV1 proof mismatch")
             (devnet-smoke-gate-require
              (null missing-blob-v1)
              "KZG opt-in engine_getBlobsV1 unknown hash must return null: ~S"
              missing-blob-v1)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-blobs-v2-response))
              "KZG opt-in engine_getBlobsV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-blobs-v2-rpc "error"))
              "KZG opt-in engine_getBlobsV2 returned an error: ~S"
              (fixture-object-field get-blobs-v2-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-blobs-v2-result)
                   (= 1 (length get-blobs-v2-result)))
              "KZG opt-in engine_getBlobsV2 result count mismatch: ~S"
              get-blobs-v2-result)
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v2 "blob")
              "KZG opt-in engine_getBlobsV2 omitted blob")
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v2 "proofs")
              "KZG opt-in engine_getBlobsV2 omitted proofs")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (fixture-object-field direct-blob-v2 "blob"))
              "KZG opt-in engine_getBlobsV2 blob mismatch")
             (devnet-smoke-gate-require
              (and (listp direct-blob-v2-proofs)
                   (= (getf blob-database :cell-proof-count)
                      (length direct-blob-v2-proofs)))
              "KZG opt-in engine_getBlobsV2 cell proof count mismatch: ~S"
              direct-blob-v2-proofs)
             (devnet-smoke-gate-require
              (string= (getf blob-database :first-cell-proof-hex)
                       (first direct-blob-v2-proofs))
              "KZG opt-in engine_getBlobsV2 first cell proof mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :last-cell-proof-hex)
                       (car (last direct-blob-v2-proofs)))
              "KZG opt-in engine_getBlobsV2 last cell proof mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-blobs-v3-response))
              "KZG opt-in engine_getBlobsV3 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-blobs-v3-rpc "error"))
              "KZG opt-in engine_getBlobsV3 returned an error: ~S"
              (fixture-object-field get-blobs-v3-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-blobs-v3-result)
                   (= 2 (length get-blobs-v3-result)))
              "KZG opt-in engine_getBlobsV3 result count mismatch: ~S"
              get-blobs-v3-result)
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v3 "blob")
              "KZG opt-in engine_getBlobsV3 omitted blob")
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v3 "proofs")
              "KZG opt-in engine_getBlobsV3 omitted proofs")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (fixture-object-field direct-blob-v3 "blob"))
              "KZG opt-in engine_getBlobsV3 blob mismatch")
             (devnet-smoke-gate-require
              (and (listp direct-blob-v3-proofs)
                   (= (getf blob-database :cell-proof-count)
                      (length direct-blob-v3-proofs)))
              "KZG opt-in engine_getBlobsV3 cell proof count mismatch: ~S"
              direct-blob-v3-proofs)
             (devnet-smoke-gate-require
              (string= (getf blob-database :first-cell-proof-hex)
                       (first direct-blob-v3-proofs))
              "KZG opt-in engine_getBlobsV3 first cell proof mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :last-cell-proof-hex)
                       (car (last direct-blob-v3-proofs)))
              "KZG opt-in engine_getBlobsV3 last cell proof mismatch")
             (devnet-smoke-gate-require
              (null missing-blob-v3)
              "KZG opt-in engine_getBlobsV3 unknown hash must return null: ~S"
              missing-blob-v3)
             (let ((status (devnet-cli-wait-process-exit process 10)))
               (when (eq status :timeout)
                 (uiop:terminate-process process))
               (devnet-smoke-gate-require
                (and (numberp status) (= 0 status))
                "KZG opt-in devnet process status mismatch: ~A"
                status)
               (let ((stdout
                       (devnet-cli-read-stream-string
                        (uiop:process-info-output process)))
                     (stderr
                       (devnet-cli-read-stream-string
                        (uiop:process-info-error-output process))))
                 (devnet-smoke-gate-require
                  (string= "" stderr)
                  "KZG opt-in devnet stderr mismatch: ~S"
                  stderr)
                 (let* ((stdout-summary (parse-json stdout))
                        (log-records (devnet-smoke-gate-file-forms log-path))
                        (ready-record
                          (find "devnet.ready" log-records
                                :test #'string=
                                :key (lambda (record)
                                       (getf record :name))))
                        (shutdown-record
                          (find "devnet.shutdown" log-records
                                :test #'string=
                                :key (lambda (record)
                                       (getf record :name))))
                        (shutdown-fields (getf shutdown-record :fields)))
                   (dolist (summary (list stdout-summary ready-summary))
                     (devnet-smoke-gate-require
                      (string= (namestring kzg-command)
                               (fixture-object-field
                                summary
                                "kzgVerifierCommand"))
                      "KZG opt-in summary verifier command mismatch")
                     (devnet-smoke-gate-require
                      (= 2 (fixture-object-field
                            summary
                            "kzgVerifierTimeoutSeconds"))
                      "KZG opt-in summary verifier timeout mismatch")
                     (devnet-smoke-gate-require
                      (fixture-object-field
                       summary
                       "kzgProofVerificationAvailable")
                      "KZG opt-in summary proof availability mismatch"))
                   (dolist (record (list ready-record shutdown-record))
                     (devnet-smoke-gate-require
                      record
                      "KZG opt-in log omitted lifecycle record")
                     (let ((fields (getf record :fields)))
                       (devnet-smoke-gate-require
                        (string= (namestring kzg-command)
                                 (cdr (assoc "kzgVerifierCommand"
                                             fields
                                             :test #'string=)))
                        "KZG opt-in log verifier command mismatch")
                       (devnet-smoke-gate-require
                        (string= "2"
                                 (cdr (assoc "kzgVerifierTimeoutSeconds"
                                             fields
                                             :test #'string=)))
                        "KZG opt-in log verifier timeout mismatch")
                       (devnet-smoke-gate-require
                        (string= "true"
                                 (cdr (assoc "kzgProofVerificationAvailable"
                                             fields
                                             :test #'string=)))
                        "KZG opt-in log proof availability mismatch")))
                   (devnet-smoke-gate-require
                    (string= "26"
                             (cdr (assoc "engineConnections"
                                         shutdown-fields
                                         :test #'string=)))
                    "KZG opt-in shutdown engine connection count mismatch")
                   (devnet-smoke-gate-require
                    (string= "0"
                             (cdr (assoc "publicConnections"
                                         shutdown-fields
                                         :test #'string=)))
                    "KZG opt-in shutdown public connection count mismatch")
                   (devnet-smoke-gate-require
                    (string= "26"
                             (cdr (assoc "totalConnections"
                                         shutdown-fields
                                         :test #'string=)))
                    "KZG opt-in shutdown total connection count mismatch")
                   (setf report
                         (list
                          (cons "status" "ok")
                          (cons "mode" "devnet-engine-only-kzg-opt-in")
                          (cons "publicRpcEnabled" :false)
                          (cons "rpcEndpoint" :false)
                          (cons "engineEndpoint" engine-endpoint)
                          (cons "kzgVerifierCommand"
                                (namestring kzg-command))
                          (cons "kzgVerifierCommandOption"
                                "--kzg.verifier-command")
                          (cons "kzgVerifierTimeoutSeconds" 2)
                          (cons "kzgVerifierTimeoutOption"
                                "--kzg.verifier-timeout")
                          (cons "kzgProofVerificationAvailable" t)
                          (cons "engineCapabilityCount"
                                (length capabilities-result))
                          (cons "engineCapabilityHasForkchoiceUpdatedV3"
                                (if (member "engine_forkchoiceUpdatedV3"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasForkchoiceUpdatedV4"
                                (if (member "engine_forkchoiceUpdatedV4"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasGetPayloadV3"
                                (if (member "engine_getPayloadV3"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasGetPayloadV4"
                                (if (member "engine_getPayloadV4"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasGetPayloadV6"
                                (if (member "engine_getPayloadV6"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasNewPayloadV3"
                                (if (member "engine_newPayloadV3"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasGetBlobsV1"
                                (if (member "engine_getBlobsV1"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasGetBlobsV2"
                                (if (member "engine_getBlobsV2"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasPayloadBodiesV2"
                                (if (member
                                     "engine_getPayloadBodiesByHashV2"
                                     capabilities-result
                                     :test #'string=)
                                    t
                                    :false))
                          (cons "preparedPayloadV3Id" payload-id-v3)
                          (cons "preparedPayloadV3ParentHash"
                                (fixture-object-field execution-payload-v3
                                                      "parentHash"))
                          (cons "preparedPayloadV3BlockNumber"
                                (fixture-object-field execution-payload-v3
                                                      "blockNumber"))
                          (cons "preparedPayloadV3ShouldOverrideBuilder"
                                (fixture-object-field payload-envelope-v3
                                                      "shouldOverrideBuilder"))
                          (cons "preparedPayloadV3BlobCount"
                                (length
                                 (fixture-object-field blobs-bundle-v3
                                                       "blobs")))
                          (cons "preparedPayloadV4Id" payload-id-v4)
                          (cons "preparedPayloadV4ParentHash"
                                (fixture-object-field execution-payload-v4
                                                      "parentHash"))
                          (cons "preparedPayloadV4BlockNumber"
                                (fixture-object-field execution-payload-v4
                                                      "blockNumber"))
                          (cons "preparedPayloadV4SlotNumber"
                                (fixture-object-field execution-payload-v4
                                                      "slotNumber"))
                          (cons "preparedPayloadV4ShouldOverrideBuilder"
                                (fixture-object-field payload-envelope-v4
                                                      "shouldOverrideBuilder"))
                          (cons "preparedPayloadV4BlobCount"
                                (length
                                 (fixture-object-field blobs-bundle-v4
                                                       "blobs")))
                          (cons "preparedPayloadV5Id"
                                (getf blob-database :payload-id))
                          (cons "preparedPayloadV5BlockNumber"
                                (fixture-object-field execution-payload-v5
                                                      "blockNumber"))
                          (cons "preparedPayloadV5BlobPrefix"
                                (hex-prefix
                                 (first (fixture-object-field blobs-bundle-v5
                                                              "blobs"))
                                 8))
                          (cons "preparedPayloadV5BlobCount"
                                (length
                                 (fixture-object-field blobs-bundle-v5
                                                       "blobs")))
                          (cons "preparedPayloadV5Commitment"
                                (first (fixture-object-field
                                        blobs-bundle-v5
                                        "commitments")))
                          (cons "preparedPayloadV5ProofCount"
                                (length
                                 (fixture-object-field blobs-bundle-v5
                                                       "proofs")))
                          (cons "preparedPayloadV6Id"
                                (getf blob-database :payload-id-v6))
                          (cons "preparedPayloadV6BlockHash"
                                (getf blob-database :block-hash-v6))
                          (cons "preparedPayloadV6BlockNumber"
                                (fixture-object-field execution-payload-v6
                                                      "blockNumber"))
                          (cons "preparedPayloadV6SlotNumber"
                                (fixture-object-field execution-payload-v6
                                                      "slotNumber"))
                          (cons "preparedPayloadV6ExecutionRequestCount"
                                (length execution-requests-v6))
                          (cons "preparedPayloadV6FirstExecutionRequest"
                                (first execution-requests-v6))
                          (cons "preparedPayloadV6BlockAccessList"
                                (fixture-object-field execution-payload-v6
                                                      "blockAccessList"))
                          (cons "preparedPayloadV6BlockAccessListPrefix"
                                (hex-prefix
                                 (fixture-object-field execution-payload-v6
                                                       "blockAccessList")
                                 8))
                          (cons "preparedPayloadV6BlobPrefix"
                                (hex-prefix
                                 (first (fixture-object-field blobs-bundle-v6
                                                              "blobs"))
                                 8))
                          (cons "preparedPayloadV6BlobCount"
                                (length
                                 (fixture-object-field blobs-bundle-v6
                                                       "blobs")))
                          (cons "preparedPayloadV6Commitment"
                                (first (fixture-object-field
                                        blobs-bundle-v6
                                        "commitments")))
                          (cons "preparedPayloadV6ProofCount"
                                (length
                                 (fixture-object-field blobs-bundle-v6
                                                       "proofs")))
                          (cons "preparedPayloadBodiesByHashV2Count"
                                (length get-payload-bodies-v2-result))
                          (cons "preparedPayloadBodiesByHashV2TransactionCount"
                                (length payload-body-v2-transactions))
                          (cons "preparedPayloadBodiesByHashV2WithdrawalCount"
                                (length payload-body-v2-withdrawals))
                          (cons "preparedPayloadBodiesByHashV2BlockAccessList"
                                (fixture-object-field payload-body-v2
                                                      "blockAccessList"))
                          (cons "preparedPayloadBodiesByRangeV2StartBlockNumber"
                                payload-bodies-range-v2-start-block)
                          (cons "preparedPayloadBodiesByRangeV2Count"
                                (length get-payload-bodies-range-v2-result))
                          (cons "preparedPayloadBodiesByRangeV2LeadingNull"
                                (if (null missing-payload-body-range-v2)
                                    t
                                    :false))
                          (cons "preparedPayloadBodiesByRangeV2HitIndex" 1)
                          (cons "preparedPayloadBodiesByRangeV2TransactionCount"
                                (length payload-body-range-v2-transactions))
                          (cons "preparedPayloadBodiesByRangeV2WithdrawalCount"
                                (length payload-body-range-v2-withdrawals))
                          (cons "preparedPayloadBodiesByRangeV2BlockAccessList"
                                (fixture-object-field payload-body-range-v2
                                                      "blockAccessList"))
                          (cons "preparedPayloadBodiesByRangeV2ZeroStartErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-zero-start-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2ZeroStartErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-zero-start-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2ZeroCountErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-zero-count-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2ZeroCountErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-zero-count-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2MalformedStartErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-malformed-start-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2MalformedStartErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-malformed-start-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2MalformedCountErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-malformed-count-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2MalformedCountErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-malformed-count-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2ParamsEnvelopeErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-params-envelope-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2ParamsEnvelopeErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-params-envelope-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2InvalidRequestErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-invalid-request-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2InvalidRequestErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-invalid-request-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2NullParamsErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-null-params-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2NullParamsErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-null-params-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2ObjectParamsErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-object-params-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2ObjectParamsErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-object-params-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2MissingStartObjectParamsErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-missing-start-object-params-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2MissingStartObjectParamsErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-missing-start-object-params-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2MissingCountObjectParamsErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-missing-count-object-params-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2MissingCountObjectParamsErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-missing-count-object-params-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2UnexpectedKeyObjectParamsErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-unexpected-key-object-params-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2UnexpectedKeyObjectParamsErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-unexpected-key-object-params-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2EmptyObjectParamsErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-empty-object-params-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2EmptyObjectParamsErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-empty-object-params-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2OversizedErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-oversized-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2OversizedErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-oversized-error
                                 "message"))
                          (cons "directBlobLookupVersionedHash"
                                (getf blob-database :versioned-hash-hex))
                          (cons "directBlobLookupCount"
                                (length get-blobs-v1-result))
                          (cons "directBlobLookupBlobPrefix"
                                (hex-prefix
                                 (fixture-object-field direct-blob-v1 "blob")
                                 8))
                          (cons "directBlobLookupBlobHexLength"
                                (length
                                 (fixture-object-field direct-blob-v1 "blob")))
                          (cons "directBlobLookupProof"
                                (fixture-object-field direct-blob-v1 "proof"))
                          (cons "directBlobLookupProofPrefix"
                                (hex-prefix
                                 (fixture-object-field direct-blob-v1 "proof")
                                 8))
                          (cons "directBlobLookupProofHexLength"
                                (length
                                 (fixture-object-field direct-blob-v1 "proof")))
                          (cons "directCellProofLookupV2Count"
                                (length get-blobs-v2-result))
                          (cons "directCellProofLookupV3Count"
                                (length get-blobs-v3-result))
                          (cons "directCellProofLookupProofCount"
                                (length direct-blob-v2-proofs))
                          (cons "directCellProofLookupFirstProof"
                                (first direct-blob-v2-proofs))
                          (cons "directCellProofLookupFirstProofPrefix"
                                (hex-prefix
                                 (first direct-blob-v2-proofs)
                                 8))
                          (cons "directCellProofLookupLastProof"
                                (car (last direct-blob-v2-proofs)))
                          (cons "directCellProofLookupLastProofPrefix"
                                (hex-prefix
                                 (car (last direct-blob-v2-proofs))
                                 8))
                          (cons "engineConnections" 26)
                          (cons "publicConnections" 0)
                          (cons "totalConnections" 26))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (and database-path (probe-file database-path))
        (delete-file database-path))
      (when (probe-file kzg-command)
        (delete-file kzg-command))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))
      report))
  #-sbcl
  (error "Devnet engine-only KZG opt-in smoke requires SBCL sockets"))

