(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-serve-mode-honors-http-false-engine-only
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (case
          (select-engine-newpayload-v2-fixture-case
           +engine-newpayload-v2-fixture-path+
           "shanghai-one-transfer-with-withdrawal"))
        (parent-block (devnet-cli-engine-fixture-parent-block case))
        (child-block (devnet-cli-engine-fixture-child-block case))
        (payload
          (execution-payload-envelope-execution-payload
           (block-to-executable-data child-block)))
        (payload-case (fixture-object-field case "payload"))
        (block-hash-hex (hash32-to-hex (block-hash child-block)))
        (new-payload-body
          (json-encode (engine-fixture-payload-request 702 payload)))
        (forkchoice-body
          (json-encode
           (devnet-cli-engine-forkchoice-v2-request
            703
            (block-hash child-block)
            :safe (block-hash parent-block)
            :finalized (block-hash parent-block))))
        (capabilities-body
          (json-encode
           (list
            (cons "jsonrpc" "2.0")
            (cons "id" 704)
            (cons "method" "engine_exchangeCapabilities")
            (cons "params"
                  (list
                   (list
                    "engine_newPayloadV1"
                    "engine_forkchoiceUpdatedV1"
                    "engine_getPayloadV1"
                    "engine_newPayloadV2"
                    "engine_forkchoiceUpdatedV2"
                    "engine_getPayloadV2"))))))
        (transition-configuration-body
          (json-encode
           (list
            (cons "jsonrpc" "2.0")
            (cons "id" 705)
            (cons "method" "engine_exchangeTransitionConfigurationV1")
            (cons "params"
                  (list
                   (list
                    (cons "terminalTotalDifficulty" "0x0")
                    (cons "terminalBlockHash" (hash32-to-hex (zero-hash32)))
                    (cons "terminalBlockNumber" "0x0")))))))
        (transition-configuration-mismatch-body
          (json-encode
           (list
            (cons "jsonrpc" "2.0")
            (cons "id" 706)
            (cons "method" "engine_exchangeTransitionConfigurationV1")
            (cons "params"
                  (list
                   (list
                    (cons "terminalTotalDifficulty" "0x1")
                    (cons "terminalBlockHash" (hash32-to-hex (zero-hash32)))
                    (cons "terminalBlockNumber" "0x0")))))))
        (genesis-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-engine-only-genesis" "json"))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-only" "jwt"))
        (public-port nil)
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-engine-only-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-engine-only" "log"))
	        (pid-path
	          (devnet-cli-temp-path "ethereum-lisp-script-engine-only" "pid"))
	        (database-path
	          (devnet-cli-temp-path
	           "ethereum-lisp-script-engine-only-chain" "sexp"))
	        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf public-port (devnet-cli-unused-loopback-port))
           (setf process
                 (test-launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        (namestring genesis-path)
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http=false"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        (write-to-string public-port)
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--authrpc.corsdomain"
                        "https://engine.runner"
                        "--authrpc.vhosts"
                        "engine.runner,localhost"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
	                        "--pid-file"
	                        (namestring pid-path)
	                        "--database"
	                        (namestring database-path)
	                        "--max-connections"
	                        "7"
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
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret (unix-time)))
                    (configured-public-endpoint
                      (format nil "http://127.0.0.1:~D" public-port))
                    (engine-body
                      (concatenate
                       'string
                       "{\"jsonrpc\":\"2.0\",\"id\":701,"
                       "\"method\":\"engine_getClientVersionV1\","
                       "\"params\":[{\"code\":\"runner\","
                       "\"name\":\"engine-only-script\","
                       "\"version\":\"1\",\"commit\":\"0x00000000\"}]}"))
                    blocked-engine-response
                    engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response
                    new-payload-response
                    forkchoice-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (not (devnet-cli-http-endpoint-connectable-p
                         configured-public-endpoint)))
               (handler-case
                   (progn
                     (setf blocked-engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :host "engine.runner"
                             :token token)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :host "engine.runner"
                             :origin "https://engine.runner"
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token
                             :host "engine.runner"
                             :target "/engine")))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token
                             :host "engine.runner"
                             :target "/engine"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 404 (devnet-cli-http-status blocked-engine-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (is (= 200 (devnet-cli-http-status new-payload-response)))
               (is (= 200 (devnet-cli-http-status forkchoice-response)))
               (is (search "Access-Control-Allow-Origin: https://engine.runner"
                           engine-response))
               (let* ((engine-rpc
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-result
                        (first (fixture-object-field engine-rpc "result")))
                      (capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc
                         "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc
                         "error"))
                      (new-payload-rpc
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
                         "payloadStatus")))
                 (is (= 701 (fixture-object-field engine-rpc "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field engine-result "name")))
                 (is (= 704 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-kzg-backed-engine-capability-list
                  capabilities-result)
                 (is (= 705 (fixture-object-field
                              transition-configuration-rpc
                              "id")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= (hash32-to-hex (zero-hash32))
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x0"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 706 (fixture-object-field
                              transition-configuration-mismatch-rpc
                              "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= block-hash-hex
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status"))))
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
                            (ready-fields (getf ready-record :fields))
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (not (fixture-object-field summary
                                                         "rpcEndpoint")))
                         (is (not (fixture-object-field
                                   summary "publicRpcEnabled")))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (equal '("https://engine.runner")
                                    (fixture-object-field
                                     summary "engineCorsOrigins")))
                         (is (equal '("engine.runner" "localhost")
                                    (fixture-object-field
                                     summary "engineVhosts"))))
                       (is ready-record)
                       (is shutdown-record)
                       (dolist (fields (list ready-fields shutdown-fields))
                         (is (string= engine-endpoint
                                      (cdr (assoc "engineEndpoint"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "/engine"
                                      (cdr (assoc "engineRpcPrefix"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "https://engine.runner"
                                      (cdr (assoc "engineCorsOrigins"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "engine.runner,localhost"
                                      (cdr (assoc "engineVhosts"
                                                  fields
                                                  :test #'string=))))
                         (is (string= ""
                                      (cdr (assoc "rpcEndpoint"
                                                  fields
                                                  :test #'string=))))
                         (is (string= "false"
                                      (cdr (assoc "publicRpcEnabled"
                                                  fields
                                                  :test #'string=)))))
                       (is (string= (fixture-object-field payload-case
                                                          "number")
                                    (cdr (assoc "headNumber"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= block-hash-hex
                                    (cdr (assoc "headHash"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "7"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "0"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "7"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (multiple-value-bind
                             (restore-stdout restore-stderr
                              restore-status)
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
	                           (let ((restore-summary
	                                   (parse-json restore-stdout)))
	                             (is (string= (namestring database-path)
	                                          (fixture-object-field
	                                           restore-summary
	                                           "databasePath")))
	                             (is (= (fixture-quantity-field
	                                     payload-case "number")
	                                    (fixture-object-field
	                                     restore-summary "headNumber")))
	                             (is (string= block-hash-hex
	                                          (fixture-object-field
	                                           restore-summary "headHash")))
	                             (is (fixture-object-field
	                                  restore-summary "stateAvailable"))
	                             (is (not (fixture-object-field
	                                       restore-summary
	                                       "publicRpcEnabled")))
	                             (is (not (fixture-object-field
	                                       restore-summary
	                                       "rpcEndpoint")))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
	      (dolist (path (list genesis-path jwt-path ready-path log-path
	                          pid-path database-path))
	        (when (probe-file path)
	          (delete-file path))))))

