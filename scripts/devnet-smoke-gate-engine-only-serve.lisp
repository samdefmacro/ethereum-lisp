(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-verify-engine-only-serve
    (&key ready-file log-file pid-file database-file)
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-engine-only" "jwt"))
        (genesis-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-engine-only-genesis"
           "json"))
        (client-thread nil)
        (client-response nil)
        (blocked-client-response nil)
        (hidden-blobs-v1-response nil)
        (hidden-blobs-v2-response nil)
        (hidden-payload-bodies-v2-response nil)
        (hidden-payload-bodies-by-hash-v2-response nil)
        (capabilities-response nil)
        (capabilities-result nil)
        (hidden-blobs-v1-rpc nil)
        (hidden-blobs-v1-error nil)
        (hidden-blobs-v2-rpc nil)
        (hidden-blobs-v2-error nil)
        (hidden-payload-bodies-v2-rpc nil)
        (hidden-payload-bodies-v2-error nil)
        (hidden-payload-bodies-by-hash-v2-rpc nil)
        (hidden-payload-bodies-by-hash-v2-error nil)
        (transition-configuration-response nil)
        (transition-configuration-result nil)
        (transition-configuration-mismatch-response nil)
        (transition-configuration-mismatch-error nil)
        (new-payload-response nil)
        (forkchoice-response nil)
        (client-version nil)
        (client-error nil)
        (engine-endpoint nil)
        (configured-public-endpoint nil)
        (public-endpoint-connectable-p nil)
        (database-summary nil)
        (report nil))
    (unwind-protect
         (progn
           (devnet-smoke-gate-call-with-telemetry-sink
            log-file
            (lambda (telemetry-sink)
              (let* ((fixture
                       (devnet-smoke-gate-engine-fixture
                        +devnet-smoke-gate-default-fixture-case+))
                     (case
                       (devnet-smoke-gate-field fixture "case"))
                     (parent-block
                       (devnet-smoke-gate-field fixture "parentBlock"))
                     (child-block
                       (devnet-smoke-gate-field fixture "childBlock"))
                     (payload
                       (devnet-smoke-gate-field fixture "payload"))
                     (expected-child-hash
                       (hash32-to-hex (block-hash child-block)))
                     (expected-child-number
                       (quantity-to-hex
                        (block-header-number
                         (block-header child-block))))
                     (fixture-inputs-written-p
                       (progn
                         (devnet-cli-write-temp-file
                          genesis-path
                          (json-encode
                           (devnet-cli-engine-fixture-parent-genesis-with-txpool-account
                            case)))
                         (devnet-cli-write-temp-file
                          jwt-path
                          +devnet-cli-jwt-secret+)
                         t))
                     (node
                       (ethereum-lisp.cli:make-devnet-node
                        :genesis-path
                        (namestring genesis-path)
                        :port 0
                        :public-port (devnet-cli-unused-loopback-port)
                        :jwt-secret-path (namestring jwt-path)
                        :engine-rpc-prefix +devnet-smoke-gate-engine-rpc-prefix+
                        :engine-cors-origins
                        *devnet-smoke-gate-engine-cors-origins*
                        :engine-vhosts *devnet-smoke-gate-engine-vhosts*
                        :log-path log-file
                        :database-path database-file
                        :pid-file-path pid-file
                        :telemetry-sink telemetry-sink))
                  (genesis-block
                    (ethereum-lisp.cli::devnet-node-genesis-block node))
                  (head-number
                    (quantity-to-hex
                     (block-header-number (block-header genesis-block))))
                  (head-hash (hash32-to-hex (block-hash genesis-block)))
                  (head-gas-limit
                    (quantity-to-hex
                     (block-header-gas-limit
                      (block-header genesis-block))))
                  (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token jwt-secret 0))
                  (engine-body
                    "{\"jsonrpc\":\"2.0\",\"id\":901,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"engine-only-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                  (capabilities-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 904)
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
                  (hidden-blobs-v1-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 909)
                      (cons "method" "engine_getBlobsV1")
                      (cons
                       "params"
                       (list
                        (list
                         "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))))))
                  (hidden-blobs-v2-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 910)
                      (cons "method" "engine_getBlobsV2")
                      (cons
                       "params"
                       (list
                        (list
                         "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))))))
                  (hidden-payload-bodies-v2-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 907)
                      (cons "method" "engine_getPayloadBodiesByRangeV2")
                      (cons "params" (list "0x1" "0x1")))))
                  (hidden-payload-bodies-by-hash-v2-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 908)
                      (cons "method" "engine_getPayloadBodiesByHashV2")
                      (cons
                       "params"
                       (list
                        (list
                         "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))))))
                  (transition-configuration-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 905)
                      (cons "method"
                            "engine_exchangeTransitionConfigurationV1")
                      (cons "params"
                            (list
                             (list
                              (cons "terminalTotalDifficulty" "0x0")
                              (cons "terminalBlockHash"
                                    (hash32-to-hex (zero-hash32)))
                              (cons "terminalBlockNumber" "0x0")))))))
                  (transition-configuration-mismatch-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 906)
                      (cons "method"
                            "engine_exchangeTransitionConfigurationV1")
                      (cons "params"
                            (list
                             (list
                              (cons "terminalTotalDifficulty" "0x1")
                              (cons "terminalBlockHash"
                                    (hash32-to-hex (zero-hash32)))
                              (cons "terminalBlockNumber" "0x0")))))))
                  (new-payload-body
                    (json-encode
                     (engine-fixture-payload-request 902 payload)))
                  (forkchoice-body
                    (json-encode
                     (devnet-cli-engine-forkchoice-v2-request
                      903
                      (block-hash child-block)
                      :safe (block-hash parent-block)
                      :finalized (block-hash parent-block)))))
             (declare (ignore fixture-inputs-written-p))
             (setf configured-public-endpoint
                   (format nil "http://127.0.0.1:~D"
                           (ethereum-lisp.rpc-http:engine-rpc-http-service-port
                            (ethereum-lisp.cli:devnet-node-public-service
                             node))))
             (when pid-file
               (ethereum-lisp.cli::devnet-cli-write-pid-file pid-file))
              (let ((summary
                      (ethereum-lisp.cli:start-devnet-node
                      node
                      :max-connections 11
                      :public-rpc-enabled-p nil
                      :on-listeners-ready
                      (lambda (engine-listener public-listener)
                        (declare (ignore public-listener))
                        (let ((raw-engine-endpoint
                                (engine-rpc-http-listener-endpoint
                                 engine-listener)))
                          (setf engine-endpoint
                                (if (uiop:string-prefix-p
                                     "http://"
                                     raw-engine-endpoint)
                                    raw-engine-endpoint
                                    (format nil "http://~A"
                                            raw-engine-endpoint))))
                        (when ready-file
                          (ethereum-lisp.cli::devnet-cli-write-ready-file
                           node
                           ready-file
                           :engine-endpoint engine-endpoint
                           :rpc-endpoint nil
                           :public-rpc-enabled-p nil))
                        (when log-file
                          (ethereum-lisp.cli::devnet-cli-log-event
                           node
                           "devnet.ready"
                           :engine-endpoint engine-endpoint
                           :rpc-endpoint nil
                           :public-rpc-enabled-p nil))
                        (setf client-thread
                              (sb-thread:make-thread
                               (lambda ()
                                 (handler-case
                                     (progn
                                       (sleep 0.05)
                                       (setf blocked-client-response
                                             (devnet-cli-http-endpoint-request
                                              engine-endpoint
                                              (devnet-cli-json-rpc-http-request
                                               engine-body
                                               :host "engine.runner"
                                               :token token)))
                                       (setf client-response
                                             (devnet-cli-http-endpoint-request
                                              engine-endpoint
                                              (devnet-cli-json-rpc-http-request
                                               engine-body
                                               :token token
                                               :host "engine.runner"
                                               :origin
                                               "https://engine-runner.example"
                                               :target
                                               +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf capabilities-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              capabilities-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf hidden-blobs-v1-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              hidden-blobs-v1-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf hidden-blobs-v2-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              hidden-blobs-v2-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf hidden-payload-bodies-v2-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              hidden-payload-bodies-v2-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf hidden-payload-bodies-by-hash-v2-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              hidden-payload-bodies-by-hash-v2-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf transition-configuration-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              transition-configuration-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf transition-configuration-mismatch-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              transition-configuration-mismatch-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf new-payload-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              new-payload-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf forkchoice-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              forkchoice-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+))))
                                   (error (condition)
                                     (setf client-error condition))))
                               :name
                               "ethereum-lisp-devnet-engine-only-client"))))))
               (when client-thread
                 (sb-thread:join-thread client-thread))
               (when client-error
                 (error client-error))
               (when log-file
                 (ethereum-lisp.cli::devnet-cli-log-event
                  node
                  "devnet.shutdown"
                  :engine-endpoint engine-endpoint
                  :rpc-endpoint nil
                  :connection-summary summary
                  :public-rpc-enabled-p nil))
               (when database-file
                 (ethereum-lisp.cli::devnet-node-export-database node)
                 (let* ((restored-node
                          (ethereum-lisp.cli:make-devnet-node
                           :genesis-path (namestring genesis-path)
                           :port 0
                           :public-port 0
                           :jwt-secret-path (namestring jwt-path)
                           :database-path database-file))
                        (restored-summary
                          (ethereum-lisp.cli:devnet-node-summary
                           restored-node
                           :public-rpc-enabled-p nil)))
                   (devnet-smoke-gate-require
                    (string= database-file
                             (getf restored-summary :database-path))
                    "Engine-only database restore path mismatch")
                   (devnet-smoke-gate-require
                    (= (hex-to-quantity expected-child-number)
                       (getf restored-summary :head-number))
                    "Engine-only database restore head number mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-child-hash
                             (getf restored-summary :head-hash))
                    "Engine-only database restore head hash mismatch")
                   (devnet-smoke-gate-require
                    (getf restored-summary :state-available-p)
                    "Engine-only database restore head state unavailable")
                   (setf database-summary restored-summary)))
               (devnet-smoke-gate-require
                (= 11 (getf summary :engine-connections))
                "Engine-only serve Engine connection count mismatch")
               (devnet-smoke-gate-require
                (= 0 (getf summary :public-connections))
                "Engine-only serve public connection count mismatch")
               (devnet-smoke-gate-require
                (= 11 (getf summary :total-connections))
                "Engine-only serve total connection count mismatch")
               (devnet-smoke-gate-require
                (and engine-endpoint
                     (devnet-smoke-gate-http-endpoint-p engine-endpoint))
                "Engine-only serve did not publish a loopback Engine endpoint")
               (setf public-endpoint-connectable-p
                     (devnet-cli-http-endpoint-connectable-p
                      configured-public-endpoint))
               (devnet-smoke-gate-require
                (not public-endpoint-connectable-p)
                "Engine-only serve public endpoint unexpectedly accepted a connection")
               (devnet-smoke-gate-require
                (= 404 (devnet-cli-http-status blocked-client-response))
                "Engine-only serve root Engine response HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status hidden-blobs-v1-response))
                "Engine-only serve hidden engine_getBlobsV1 HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status hidden-blobs-v2-response))
                "Engine-only serve hidden engine_getBlobsV2 HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status hidden-payload-bodies-v2-response))
                "Engine-only serve hidden engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200
                   (devnet-cli-http-status
                    hidden-payload-bodies-by-hash-v2-response))
                "Engine-only serve hidden engine_getPayloadBodiesByHashV2 HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status client-response))
                "Engine-only serve Engine response HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status capabilities-response))
                "Engine-only serve engine_exchangeCapabilities HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status
                        transition-configuration-response))
                "Engine-only serve engine_exchangeTransitionConfigurationV1 HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status
                        transition-configuration-mismatch-response))
                "Engine-only serve engine_exchangeTransitionConfigurationV1 mismatch HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status new-payload-response))
                "Engine-only serve engine_newPayloadV2 HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status forkchoice-response))
                "Engine-only serve engine_forkchoiceUpdatedV2 HTTP status mismatch")
               (devnet-smoke-gate-require
                (string= "https://engine-runner.example"
                         (devnet-smoke-gate-http-header
                          client-response
                          "Access-Control-Allow-Origin"))
                "Engine-only serve Engine CORS response header mismatch")
               (devnet-smoke-gate-require
                (string= "Origin"
                         (devnet-smoke-gate-http-header
                          client-response
                          "Vary"))
                "Engine-only serve Engine CORS Vary header mismatch")
               (let* ((engine-rpc
                        (parse-json
                         (devnet-cli-http-body client-response)))
                      (parsed-hidden-payload-bodies-v2-rpc
                        (parse-json
                         (devnet-cli-http-body
                          hidden-payload-bodies-v2-response)))
                      (parsed-hidden-blobs-v1-rpc
                        (parse-json
                         (devnet-cli-http-body hidden-blobs-v1-response)))
                      (parsed-hidden-blobs-v2-rpc
                        (parse-json
                         (devnet-cli-http-body hidden-blobs-v2-response)))
                      (parsed-hidden-blobs-v1-error
                        (fixture-object-field
                         parsed-hidden-blobs-v1-rpc
                         "error"))
                      (parsed-hidden-blobs-v2-error
                        (fixture-object-field
                         parsed-hidden-blobs-v2-rpc
                         "error"))
                      (parsed-hidden-payload-bodies-v2-error
                        (fixture-object-field
                         parsed-hidden-payload-bodies-v2-rpc
                         "error"))
                      (parsed-hidden-payload-bodies-by-hash-v2-rpc
                        (parse-json
                         (devnet-cli-http-body
                          hidden-payload-bodies-by-hash-v2-response)))
                      (parsed-hidden-payload-bodies-by-hash-v2-error
                        (fixture-object-field
                         parsed-hidden-payload-bodies-by-hash-v2-rpc
                         "error"))
                      (capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (parsed-capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (parsed-transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc
                         "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (parsed-transition-configuration-mismatch-error
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
                         "payloadStatus"))
                      (parsed-client-version
                        (first (fixture-object-field engine-rpc "result"))))
                 (setf hidden-payload-bodies-v2-rpc
                       parsed-hidden-payload-bodies-v2-rpc
                       hidden-blobs-v1-rpc
                       parsed-hidden-blobs-v1-rpc
                       hidden-blobs-v1-error
                       parsed-hidden-blobs-v1-error
                       hidden-blobs-v2-rpc
                       parsed-hidden-blobs-v2-rpc
                       hidden-blobs-v2-error
                       parsed-hidden-blobs-v2-error
                       hidden-payload-bodies-v2-error
                       parsed-hidden-payload-bodies-v2-error
                       hidden-payload-bodies-by-hash-v2-rpc
                       parsed-hidden-payload-bodies-by-hash-v2-rpc
                       hidden-payload-bodies-by-hash-v2-error
                       parsed-hidden-payload-bodies-by-hash-v2-error
                       capabilities-result parsed-capabilities-result
                       transition-configuration-result
                       parsed-transition-configuration-result
                       transition-configuration-mismatch-error
                       parsed-transition-configuration-mismatch-error
                       client-version parsed-client-version)
                 (devnet-smoke-gate-require
                  (= 901 (fixture-object-field engine-rpc "id"))
                  "Engine-only serve Engine response id mismatch")
                 (devnet-smoke-gate-require
                  (string= "ethereum-lisp"
                           (fixture-object-field client-version "name"))
                 "Engine-only serve client version mismatch")
                 (devnet-smoke-gate-require
                  (and capabilities-result
                       (listp capabilities-result))
                  "Engine-only serve engine_exchangeCapabilities result missing from ~A"
                  (devnet-cli-http-body capabilities-response))
                 (devnet-smoke-gate-require
                  hidden-blobs-v1-error
                  "Engine-only serve hidden engine_getBlobsV1 unexpectedly returned success: ~S"
                  hidden-blobs-v1-rpc)
                 (devnet-smoke-gate-require
                  (= -32601
                     (fixture-object-field hidden-blobs-v1-error "code"))
                  "Engine-only serve hidden engine_getBlobsV1 error code mismatch: ~S"
                  hidden-blobs-v1-error)
                 (devnet-smoke-gate-require
                  (string= "Method not found"
                           (fixture-object-field hidden-blobs-v1-error
                                                 "message"))
                  "Engine-only serve hidden engine_getBlobsV1 error message mismatch: ~S"
                  hidden-blobs-v1-error)
                 (devnet-smoke-gate-require
                  (not (find "result"
                             hidden-blobs-v1-rpc
                             :test #'string=
                             :key #'car))
                  "Engine-only serve hidden engine_getBlobsV1 should not include a success result: ~S"
                  hidden-blobs-v1-rpc)
                 (devnet-smoke-gate-require
                  hidden-blobs-v2-error
                  "Engine-only serve hidden engine_getBlobsV2 unexpectedly returned success: ~S"
                  hidden-blobs-v2-rpc)
                 (devnet-smoke-gate-require
                  (= -32601
                     (fixture-object-field hidden-blobs-v2-error "code"))
                  "Engine-only serve hidden engine_getBlobsV2 error code mismatch: ~S"
                  hidden-blobs-v2-error)
                 (devnet-smoke-gate-require
                  (string= "Method not found"
                           (fixture-object-field hidden-blobs-v2-error
                                                 "message"))
                  "Engine-only serve hidden engine_getBlobsV2 error message mismatch: ~S"
                  hidden-blobs-v2-error)
                 (devnet-smoke-gate-require
                  (not (find "result"
                             hidden-blobs-v2-rpc
                             :test #'string=
                             :key #'car))
                  "Engine-only serve hidden engine_getBlobsV2 should not include a success result: ~S"
                  hidden-blobs-v2-rpc)
                 (devnet-smoke-gate-require
                  hidden-payload-bodies-v2-error
                  "Engine-only serve hidden engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
                  hidden-payload-bodies-v2-rpc)
                 (devnet-smoke-gate-require
                  (= -32601
                     (fixture-object-field hidden-payload-bodies-v2-error
                                           "code"))
                  "Engine-only serve hidden engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
                  hidden-payload-bodies-v2-error)
                 (devnet-smoke-gate-require
                 (string= "Method not found"
                           (fixture-object-field hidden-payload-bodies-v2-error
                                                 "message"))
                  "Engine-only serve hidden engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
                  hidden-payload-bodies-v2-error)
                 (devnet-smoke-gate-require
                 (not (find "result"
                             hidden-payload-bodies-v2-rpc
                             :test #'string=
                             :key #'car))
                  "Engine-only serve hidden engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
                  hidden-payload-bodies-v2-rpc)
                 (devnet-smoke-gate-require
                  hidden-payload-bodies-by-hash-v2-error
                  "Engine-only serve hidden engine_getPayloadBodiesByHashV2 unexpectedly returned success: ~S"
                  hidden-payload-bodies-by-hash-v2-rpc)
                 (devnet-smoke-gate-require
                  (= -32601
                     (fixture-object-field
                      hidden-payload-bodies-by-hash-v2-error
                      "code"))
                  "Engine-only serve hidden engine_getPayloadBodiesByHashV2 error code mismatch: ~S"
                  hidden-payload-bodies-by-hash-v2-error)
                 (devnet-smoke-gate-require
                  (string=
                   "Method not found"
                   (fixture-object-field
                    hidden-payload-bodies-by-hash-v2-error
                    "message"))
                  "Engine-only serve hidden engine_getPayloadBodiesByHashV2 error message mismatch: ~S"
                  hidden-payload-bodies-by-hash-v2-error)
                 (devnet-smoke-gate-require
                  (not (find "result"
                             hidden-payload-bodies-by-hash-v2-rpc
                             :test #'string=
                             :key #'car))
                  "Engine-only serve hidden engine_getPayloadBodiesByHashV2 should not include a success result: ~S"
                  hidden-payload-bodies-by-hash-v2-rpc)
                 (dolist (method '("engine_newPayloadV1"
                                    "engine_forkchoiceUpdatedV1"
                                    "engine_getPayloadV1"
                                    "engine_newPayloadV2"
                                    "engine_forkchoiceUpdatedV2"
                                    "engine_getPayloadV2"
                                    "engine_getPayloadBodiesByHashV1"
                                    "engine_getPayloadBodiesByRangeV1"))
                   (devnet-smoke-gate-require
                   (member method capabilities-result :test #'string=)
                    "Engine-only serve engine_exchangeCapabilities omitted ~A from ~S"
                    method
                    capabilities-result))
                 (dolist (method '("engine_newPayloadV3"
                                    "engine_getBlobsV1"
                                    "engine_getBlobsV2"
                                    "engine_getPayloadBodiesByHashV2"
                                    "engine_getPayloadBodiesByRangeV2"))
                   (devnet-smoke-gate-require
                    (not (member method capabilities-result :test #'string=))
                    "Engine-only serve engine_exchangeCapabilities advertised ~A"
                    method))
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            transition-configuration-result
                            "terminalTotalDifficulty"))
                  "Engine-only serve transition terminalTotalDifficulty mismatch")
                 (devnet-smoke-gate-require
                  (string= (hash32-to-hex (zero-hash32))
                           (fixture-object-field
                            transition-configuration-result
                            "terminalBlockHash"))
                  "Engine-only serve transition terminalBlockHash mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            transition-configuration-result
                            "terminalBlockNumber"))
                  "Engine-only serve transition terminalBlockNumber mismatch")
                 (devnet-smoke-gate-require
                  (= -32602
                     (fixture-object-field
                      transition-configuration-mismatch-error
                      "code"))
                  "Engine-only serve transition mismatch error code mismatch")
                 (devnet-smoke-gate-require
                  (search "terminalTotalDifficulty mismatch"
                          (fixture-object-field
                           transition-configuration-mismatch-error
                           "message"))
                  "Engine-only serve transition mismatch error message mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field new-payload-result "status"))
                  "Engine-only serve engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-child-hash
                           (fixture-object-field new-payload-result
                                                 "latestValidHash"))
                  "Engine-only serve latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field forkchoice-status "status"))
                  "Engine-only serve forkchoice status mismatch"))
               (when ready-file
                 (let ((ready-summary
                         (parse-json
                          (devnet-smoke-gate-file-string ready-file))))
                   (devnet-smoke-gate-require
                    (string= engine-endpoint
                             (fixture-object-field ready-summary
                                                   "engineEndpoint"))
                    "Engine-only ready file Engine endpoint mismatch")
                   (devnet-smoke-gate-require
                    (string= +devnet-smoke-gate-engine-rpc-prefix+
                             (fixture-object-field ready-summary
                                                   "engineRpcPrefix"))
                    "Engine-only ready file Engine RPC prefix mismatch")
                   (devnet-smoke-gate-require
                    (equal *devnet-smoke-gate-engine-cors-origins*
                           (fixture-object-field ready-summary
                                                 "engineCorsOrigins"))
                    "Engine-only ready file Engine CORS origins mismatch")
                   (devnet-smoke-gate-require
                    (equal *devnet-smoke-gate-engine-vhosts*
                           (fixture-object-field ready-summary
                                                 "engineVhosts"))
                    "Engine-only ready file Engine vhosts mismatch")
                   (devnet-smoke-gate-require
                    (not (fixture-object-field ready-summary "rpcEndpoint"))
                    "Engine-only ready file must disable rpcEndpoint")
                   (devnet-smoke-gate-require
                    (not (fixture-object-field ready-summary
                                               "publicRpcEnabled"))
                    "Engine-only ready file must disable publicRpcEnabled")
                   (devnet-smoke-gate-require
                    (string= head-number
                             (quantity-to-hex
                              (fixture-object-field ready-summary
                                                    "headNumber")))
                    "Engine-only ready file head number mismatch")
                   (devnet-smoke-gate-require
                    (string= head-hash
                             (fixture-object-field ready-summary
                                                   "headHash"))
                    "Engine-only ready file head hash mismatch")
                   (devnet-smoke-gate-require
                    (string= head-gas-limit
                             (quantity-to-hex
                              (fixture-object-field ready-summary
                                                    "headGasLimit")))
                    "Engine-only ready file head gas limit mismatch")))
               (when log-file
                 (let ((records
                         (devnet-smoke-gate-file-forms log-file)))
                   (dolist (event '("devnet.ready" "devnet.shutdown"))
                     (let* ((record
                              (find event records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (fields (and record (getf record :fields))))
                       (devnet-smoke-gate-require
                        record
                        "Engine-only log file missing ~A" event)
                       (devnet-smoke-gate-require
                        (string= engine-endpoint
                                 (cdr (assoc "engineEndpoint" fields
                                             :test #'string=)))
                        "Engine-only log Engine endpoint mismatch")
                       (devnet-smoke-gate-require
                        (string= +devnet-smoke-gate-engine-rpc-prefix+
                                 (cdr (assoc "engineRpcPrefix" fields
                                             :test #'string=)))
                        "Engine-only log Engine RPC prefix mismatch")
                       (devnet-smoke-gate-require
                        (string= "https://engine-runner.example,https://engine-observer.example"
                                 (cdr (assoc "engineCorsOrigins" fields
                                             :test #'string=)))
                        "Engine-only log Engine CORS origins mismatch")
                       (devnet-smoke-gate-require
                        (string= "engine.runner,localhost"
                                 (cdr (assoc "engineVhosts" fields
                                             :test #'string=)))
                        "Engine-only log Engine vhosts mismatch")
                       (devnet-smoke-gate-require
                        (string= ""
                                 (cdr (assoc "rpcEndpoint" fields
                                             :test #'string=)))
                        "Engine-only log must emit an empty rpcEndpoint")
                       (devnet-smoke-gate-require
                        (string= "false"
                                 (cdr (assoc "publicRpcEnabled" fields
                                             :test #'string=)))
                        "Engine-only log must disable publicRpcEnabled")
                       (devnet-smoke-gate-require
                        (string= (if (string= event "devnet.shutdown")
                                     expected-child-number
                                     head-number)
                                 (cdr (assoc "headNumber" fields
                                             :test #'string=)))
                        "Engine-only log head number mismatch")
                       (devnet-smoke-gate-require
                        (string= (if (string= event "devnet.shutdown")
                                     expected-child-hash
                                     head-hash)
                                 (cdr (assoc "headHash" fields
                                             :test #'string=)))
                        "Engine-only log head hash mismatch")))))
               (setf report
                     (devnet-smoke-gate-add-run-metadata
                      (list
                       (cons "status" "ok")
                       (cons "mode" "devnet-engine-only-serve")
                       (cons "publicRpcEnabled" :false)
                       (cons "engineEndpoint" engine-endpoint)
                       (cons "engineRpcPrefix"
                             +devnet-smoke-gate-engine-rpc-prefix+)
                       (cons "engineRpcPrefixStatus"
                             (devnet-cli-http-status client-response))
                       (cons "engineRpcPrefixBlockedStatus"
                             (devnet-cli-http-status blocked-client-response))
                       (cons "hiddenBlobsV1Status"
                             (devnet-cli-http-status
                              hidden-blobs-v1-response))
                       (cons "hiddenBlobsV1ErrorCode"
                             (fixture-object-field
                              hidden-blobs-v1-error
                              "code"))
                       (cons "hiddenBlobsV1ErrorMessage"
                             (fixture-object-field
                              hidden-blobs-v1-error
                              "message"))
                       (cons "hiddenBlobsV2Status"
                             (devnet-cli-http-status
                              hidden-blobs-v2-response))
                       (cons "hiddenBlobsV2ErrorCode"
                             (fixture-object-field
                              hidden-blobs-v2-error
                              "code"))
                       (cons "hiddenBlobsV2ErrorMessage"
                             (fixture-object-field
                              hidden-blobs-v2-error
                              "message"))
                       (cons "hiddenPayloadBodiesByRangeV2Status"
                            (devnet-cli-http-status
                             hidden-payload-bodies-v2-response))
                       (cons "hiddenPayloadBodiesByRangeV2ErrorCode"
                             (fixture-object-field
                              hidden-payload-bodies-v2-error
                              "code"))
                       (cons "hiddenPayloadBodiesByRangeV2ErrorMessage"
                             (fixture-object-field
                              hidden-payload-bodies-v2-error
                              "message"))
                       (cons "hiddenPayloadBodiesByHashV2Status"
                             (devnet-cli-http-status
                              hidden-payload-bodies-by-hash-v2-response))
                       (cons "hiddenPayloadBodiesByHashV2ErrorCode"
                             (fixture-object-field
                              hidden-payload-bodies-by-hash-v2-error
                              "code"))
                       (cons "hiddenPayloadBodiesByHashV2ErrorMessage"
                             (fixture-object-field
                              hidden-payload-bodies-by-hash-v2-error
                              "message"))
                       (cons "engineCorsOrigins"
                             *devnet-smoke-gate-engine-cors-origins*)
                       (cons "engineCorsHeader"
                             (devnet-smoke-gate-http-header
                              client-response
                              "Access-Control-Allow-Origin"))
                       (cons "engineCorsVaryHeader"
                             (devnet-smoke-gate-http-header
                              client-response
                              "Vary"))
                       (cons "engineVhosts"
                             *devnet-smoke-gate-engine-vhosts*)
                       (cons "fixtureCase"
                             +devnet-smoke-gate-default-fixture-case+)
                       (cons "newPayloadStatus" +payload-status-valid+)
                       (cons "latestValidHash" expected-child-hash)
                       (cons "forkchoiceStatus" +payload-status-valid+)
                       (cons "forkchoiceHeadNumber" expected-child-number)
                       (cons "forkchoiceHeadHash" expected-child-hash)
                       (cons "rpcEndpoint" :false)
                       (cons "configuredPublicEndpoint"
                             configured-public-endpoint)
                       (cons "publicEndpointConnectable"
                             (if public-endpoint-connectable-p t :false))
                       (cons "readyFile" (or ready-file :false))
                       (cons "logFile" (or log-file :false))
                       (cons "pidFile" (or pid-file :false))
                       (cons "databaseFile" (or database-file :false))
                       (cons "databaseHeadNumber"
                             (if database-summary
                                 (getf database-summary :head-number)
                                 :false))
                       (cons "databaseHeadHash"
                             (if database-summary
                                 (getf database-summary :head-hash)
                                 :false))
                       (cons "databaseStateAvailable"
                             (if database-summary
                                 (if (getf database-summary
                                           :state-available-p)
                                     t
                                     :false)
                                 :false))
                       (cons "engineConnections"
                             (getf summary :engine-connections))
                       (cons "publicConnections"
                             (getf summary :public-connections))
                       (cons "totalConnections"
                             (getf summary :total-connections))
                       (cons "connectionContract"
                             (list
                              (cons "expectedEngineConnections" 11)
                              (cons "expectedPublicConnections" 0)
                              (cons "expectedTotalConnections" 11)))
                       (cons "engineCapabilityCount"
                             (length capabilities-result))
                       (cons "engineCapabilityHasNewPayloadV1"
                             (if (member "engine_newPayloadV1"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasForkchoiceUpdatedV1"
                             (if (member "engine_forkchoiceUpdatedV1"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasGetPayloadV1"
                             (if (member "engine_getPayloadV1"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasNewPayloadV2"
                             (if (member "engine_newPayloadV2"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasForkchoiceUpdatedV2"
                             (if (member "engine_forkchoiceUpdatedV2"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasGetPayloadV2"
                             (if (member "engine_getPayloadV2"
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
                             (if (or (member "engine_getPayloadBodiesByHashV2"
                                             capabilities-result
                                             :test #'string=)
                                     (member "engine_getPayloadBodiesByRangeV2"
                                             capabilities-result
                                             :test #'string=))
                                 t
                                 :false))
                       (cons "engineClientVersionCode"
                             (fixture-object-field client-version "code"))
                       (cons "engineClientVersionName" "ethereum-lisp")
                       (cons "engineClientVersionVersion"
                             (fixture-object-field client-version "version"))
                       (cons "engineClientVersionCommit"
                             (fixture-object-field client-version "commit"))
                       (cons "engineTransitionTerminalTotalDifficulty"
                             (fixture-object-field
                              transition-configuration-result
                              "terminalTotalDifficulty"))
                       (cons "engineTransitionTerminalBlockHash"
                             (fixture-object-field
                              transition-configuration-result
                              "terminalBlockHash"))
                       (cons "engineTransitionTerminalBlockNumber"
                             (fixture-object-field
                              transition-configuration-result
                              "terminalBlockNumber"))
                       (cons "engineTransitionMismatchErrorCode"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "code"))
                       (cons "engineTransitionMismatchErrorMessage"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))
                       (cons "headNumber" head-number)
                       (cons "headHash" head-hash)
                       (cons "headGasLimit" head-gas-limit)))))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))
    report)
  #-sbcl
  (error "Devnet engine-only serve smoke requires SBCL sockets"))
