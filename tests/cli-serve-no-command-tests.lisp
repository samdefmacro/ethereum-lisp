(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-serve-mode-honors-runner-http-shaping
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-http-shape" "jwt"))
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-http-shape-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-http-shape" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-http-shape" "pid"))
        (coinbase "0x00000000000000000000000000000000000000cb")
        (process nil))
    (unwind-protect
         (progn
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string +devnet-cli-jwt-secret+ stream))
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
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--authrpc.corsdomain"
                        "https://engine.runner"
                        "--http.rpcprefix"
                        "/rpc"
                        "--authrpc.vhosts"
                        "engine.runner,localhost"
                        "--http.vhosts"
                        "public.runner,localhost"
                        "--http.corsdomain"
                        "https://runner.example"
                        "--http.api"
                        "eth,net"
                        "--networkid"
                        "4242"
                        "--miner.etherbase"
                        coinbase
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "11"
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
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":601,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"shape-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-chain-body
                      "{\"jsonrpc\":\"2.0\",\"id\":602,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-body
                      "{\"jsonrpc\":\"2.0\",\"id\":603,\"method\":\"net_version\",\"params\":[]}")
                    (public-coinbase-body
                      "{\"jsonrpc\":\"2.0\",\"id\":607,\"method\":\"eth_coinbase\",\"params\":[]}")
                    (public-web3-body
                      "{\"jsonrpc\":\"2.0\",\"id\":604,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":605,\"method\":\"rpc_modules\",\"params\":[]}")
                    (public-txpool-body
                      "{\"jsonrpc\":\"2.0\",\"id\":606,\"method\":\"txpool_status\",\"params\":[]}")
                    engine-prefixed-response
                    engine-preflight-response
                    engine-root-response
                    engine-blocked-host-response
                    engine-unsupported-method-response
                    engine-unsupported-content-type-response
                    public-prefixed-response
                    public-net-response
                    public-coinbase-response
                    public-rpc-modules-response
                    public-blocked-host-response
                    public-root-response
                    public-web3-response
                    public-txpool-response
                    public-preflight-response
                    public-unsupported-method-response
                    public-unsupported-content-type-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (dolist (summary-field
                         '(("engineRpcPrefix" . "/engine")
                           ("publicRpcPrefix" . "/rpc")))
                 (is (string= (cdr summary-field)
                              (fixture-object-field
                               ready-summary
                               (car summary-field)))))
               (is (= 4242 (fixture-object-field ready-summary "networkId")))
               (is (equal '("eth" "net")
                          (fixture-object-field
                           ready-summary "publicApiModules")))
               (is (string= coinbase
                            (fixture-object-field ready-summary "coinbase")))
               (is (equal '("https://engine.runner")
                          (fixture-object-field
                           ready-summary "engineCorsOrigins")))
               (is (equal '("https://runner.example")
                          (fixture-object-field
                           ready-summary "publicCorsOrigins")))
               (is (equal '("engine.runner" "localhost")
                          (fixture-object-field ready-summary
                                                "engineVhosts")))
               (is (equal '("public.runner" "localhost")
                          (fixture-object-field ready-summary
                                                "publicVhosts")))
               (handler-case
                   (progn
                     (setf engine-prefixed-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :host "engine.runner"
                             :origin "https://engine.runner"
                             :token token)))
                     (setf engine-preflight-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-options-http-request
                             :target "/engine"
                             :host "engine.runner"
                             :origin "https://engine.runner"
                             :request-method "OPTIONS"
                             :request-headers
                             '(("Access-Control-Request-Method" . "POST")
                               ("Access-Control-Request-Headers" .
                                "authorization, content-type")))))
                     (setf engine-root-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/"
                             :host "engine.runner"
                             :token token)))
                     (setf engine-blocked-host-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :target "/engine"
                             :host "blocked.engine"
                             :token token)))
                     (setf engine-unsupported-method-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (with-output-to-string (stream)
                              (format stream "PUT /engine HTTP/1.1~%")
                              (format stream "Host: engine.runner~%")
                              (format stream "Content-Type: application/json~%")
                              (format stream "Authorization: Bearer ~A~%" token)
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length engine-body)
                                      engine-body))))
                     (setf engine-unsupported-content-type-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (with-output-to-string (stream)
                              (format stream "POST /engine HTTP/1.1~%")
                              (format stream "Host: engine.runner~%")
                              (format stream "Content-Type: text/plain~%")
                              (format stream "Authorization: Bearer ~A~%" token)
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length engine-body)
                                      engine-body))))
                     (setf public-prefixed-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-chain-body
                             :target "/rpc"
                             :host "public.runner"
                             :origin "https://runner.example")))
                     (setf public-net-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-coinbase-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-coinbase-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-rpc-modules-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-blocked-host-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-chain-body
                             :target "/rpc"
                             :host "blocked.public")))
                     (setf public-root-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-chain-body
                             :target "/"
                             :host "public.runner")))
                     (setf public-web3-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-web3-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-txpool-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-txpool-body
                             :target "/rpc"
                             :host "public.runner")))
                     (setf public-preflight-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-options-http-request
                             :target "/rpc"
                             :host "public.runner"
                             :origin "https://runner.example"
                             :request-method "OPTIONS"
                             :request-headers
                             '(("Access-Control-Request-Method" . "POST")
                               ("Access-Control-Request-Headers" .
                                "content-type")))))
                     (setf public-unsupported-method-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (with-output-to-string (stream)
                              (format stream "PUT /rpc HTTP/1.1~%")
                              (format stream "Host: public.runner~%")
                              (format stream "Content-Type: application/json~%")
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length public-chain-body)
                                      public-chain-body))))
                     (setf public-unsupported-content-type-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (with-output-to-string (stream)
                              (format stream "POST /rpc HTTP/1.1~%")
                              (format stream "Host: public.runner~%")
                              (format stream "Content-Type: text/plain~%")
                              (format stream "Content-Length: ~D~%~%~A"
                                      (length public-chain-body)
                                      public-chain-body)))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-prefixed-response)))
               (is (search "Access-Control-Allow-Origin: https://engine.runner"
                           engine-prefixed-response))
               (is (= 204 (devnet-cli-http-status engine-preflight-response)))
               (is (search "Access-Control-Allow-Origin: https://engine.runner"
                           engine-preflight-response))
               (is (= 404 (devnet-cli-http-status engine-root-response)))
               (is (= 403
                      (devnet-cli-http-status
                       engine-blocked-host-response)))
               (is (= 405
                      (devnet-cli-http-status
                       engine-unsupported-method-response)))
               (is (search "method not allowed"
                           (devnet-cli-http-body
                            engine-unsupported-method-response)))
               (is (= 415
                      (devnet-cli-http-status
                       engine-unsupported-content-type-response)))
               (is (search "invalid content type"
                           (devnet-cli-http-body
                            engine-unsupported-content-type-response)))
               (is (= 200 (devnet-cli-http-status public-prefixed-response)))
               (is (search "Access-Control-Allow-Origin: https://runner.example"
                           public-prefixed-response))
               (is (= 200 (devnet-cli-http-status public-net-response)))
               (is (= 200 (devnet-cli-http-status public-coinbase-response)))
               (is (= 200
                      (devnet-cli-http-status
                       public-rpc-modules-response)))
               (is (= 403
                      (devnet-cli-http-status
                       public-blocked-host-response)))
               (is (= 404 (devnet-cli-http-status public-root-response)))
               (is (= 200 (devnet-cli-http-status public-web3-response)))
               (is (= 200 (devnet-cli-http-status public-txpool-response)))
               (is (= 204 (devnet-cli-http-status public-preflight-response)))
               (is (= 405
                      (devnet-cli-http-status
                       public-unsupported-method-response)))
               (is (search "method not allowed"
                           (devnet-cli-http-body
                            public-unsupported-method-response)))
               (is (= 415
                      (devnet-cli-http-status
                       public-unsupported-content-type-response)))
               (is (search "invalid content type"
                           (devnet-cli-http-body
                            public-unsupported-content-type-response)))
               (let* ((engine-json
                        (parse-json
                         (devnet-cli-http-body engine-prefixed-response)))
                      (public-json
                        (parse-json
                         (devnet-cli-http-body public-prefixed-response)))
                      (public-net-json
                        (parse-json
                         (devnet-cli-http-body public-net-response)))
                      (public-coinbase-json
                        (parse-json
                         (devnet-cli-http-body public-coinbase-response)))
                      (public-rpc-modules-json
                        (parse-json
                         (devnet-cli-http-body
                          public-rpc-modules-response)))
                      (public-web3-json
                        (parse-json
                         (devnet-cli-http-body public-web3-response)))
                      (public-txpool-json
                        (parse-json
                         (devnet-cli-http-body public-txpool-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result")))
                      (public-modules
                        (fixture-object-field
                         public-rpc-modules-json "result")))
                 (is (= 601 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 602 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result")))
                 (is (= 603 (fixture-object-field public-net-json "id")))
                 (is (string= "4242"
                              (fixture-object-field
                               public-net-json "result")))
                 (is (= 607
                        (fixture-object-field public-coinbase-json "id")))
                 (is (string= coinbase
                              (fixture-object-field
                               public-coinbase-json "result")))
                 (is (= 605
                        (fixture-object-field public-rpc-modules-json "id")))
                 (is (string= "1.0"
                              (fixture-object-field public-modules "eth")))
                 (is (string= "1.0"
                              (fixture-object-field public-modules "net")))
                 (is (string= "1.0"
                              (fixture-object-field public-modules "rpc")))
                 (is (not (fixture-object-field public-modules "txpool")))
                 (is (not (fixture-object-field public-modules "web3")))
                 (is (= 604 (fixture-object-field public-web3-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field public-web3-json "error")
                         "code")))
                 (is (= 606 (fixture-object-field public-txpool-json "id")))
                 (is (= -32601
                        (fixture-object-field
                         (fixture-object-field public-txpool-json "error")
                         "code"))))
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
                                           (getf record :name)))))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (string= "/rpc"
                                      (fixture-object-field
                                       summary "publicRpcPrefix")))
                         (is (equal '("eth" "net")
                                    (fixture-object-field
                                     summary "publicApiModules")))
                         (is (string= coinbase
                                      (fixture-object-field
                                       summary "coinbase")))
                         (is (equal '("https://engine.runner")
                                    (fixture-object-field
                                     summary "engineCorsOrigins")))
                         (is (equal '("https://runner.example")
                                    (fixture-object-field
                                     summary "publicCorsOrigins"))))
                       (dolist (record (list ready-record shutdown-record))
                         (is record)
                         (let ((fields (getf record :fields)))
                           (is (string= "/engine"
                                        (cdr (assoc "engineRpcPrefix" fields
                                                    :test #'string=))))
                           (is (string= "/rpc"
                                        (cdr (assoc "publicRpcPrefix" fields
                                                    :test #'string=))))
                           (is (string= "eth,net"
                                        (cdr (assoc "publicApiModules" fields
                                                    :test #'string=))))
                           (is (string= coinbase
                                        (cdr (assoc "coinbase" fields
                                                    :test #'string=))))
                           (is (string= "https://engine.runner"
                                        (cdr (assoc "engineCorsOrigins" fields
                                                    :test #'string=))))
                           (is (string= "https://runner.example"
                                        (cdr (assoc "publicCorsOrigins" fields
                                                    :test #'string=))))
                           (is (string= "engine.runner,localhost"
                                        (cdr (assoc "engineVhosts" fields
                                                    :test #'string=))))
                           (is (string= "public.runner,localhost"
                                        (cdr (assoc "publicVhosts" fields
                                                    :test #'string=))))))
                       (let ((shutdown-fields
                               (getf shutdown-record :fields)))
                         (is (string= "6"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "11"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "17"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

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
                 (uiop:launch-program
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
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
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
                 (devnet-cli-assert-engine-capability-list
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

(deftest ethereum-lisp-script-no-command-split-serve-mode
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (terminal-block-hash
           "0x4444444444444444444444444444444444444444444444444444444444444444")
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 813)
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
             (cons "id" 814)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3039")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 815)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3038")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split" "jwt"))
        (config-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split"
                                "toml"))
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-no-command-split-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command-split" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file config-path
                                       "# runner config placeholder\n")
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--config"
                        (namestring config-path)
                        "--dev"
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--override.terminaltotaldifficulty"
                        "0x3039"
                        "--override.terminalblockhash"
                        terminal-block-hash
                        "--override.terminalblocknumber"
                        "66"
                        "--http"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--http.rpcprefix"
                        "/rpc"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "4"
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
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (engine-body
                      (concatenate
                       'string
                       "{\"jsonrpc\":\"2.0\",\"id\":811,"
                       "\"method\":\"engine_getClientVersionV1\","
                       "\"params\":[{\"code\":\"runner\","
                       "\"name\":\"no-command-split-script\","
                       "\"version\":\"1\",\"commit\":\"0x00000000\"}]}"))
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":812,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":816,\"method\":\"net_version\",\"params\":[]}")
                    (public-client-version-body
                      "{\"jsonrpc\":\"2.0\",\"id\":817,\"method\":\"web3_clientVersion\",\"params\":[]}")
                    (public-rpc-modules-body
                      "{\"jsonrpc\":\"2.0\",\"id\":818,\"method\":\"rpc_modules\",\"params\":[]}")
                    engine-response
                    public-response
                    public-net-version-response
                    public-client-version-response
                    public-rpc-modules-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (stringp rpc-endpoint))
               (is (fixture-object-field ready-summary "publicRpcEnabled"))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field ready-summary
                                                  "publicRpcPrefix")))
               (handler-case
                   (progn
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :target "/engine")))
                     (setf public-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-body
                             :target "/rpc")))
                     (setf public-net-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-net-version-body
                             :target "/rpc")))
                     (setf public-client-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-client-version-body
                             :target "/rpc")))
                     (setf public-rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             public-rpc-modules-body
                             :target "/rpc"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-response)))
               (is (= 200 (devnet-cli-http-status
                            transition-configuration-mismatch-response)))
               (dolist (response (list public-response
                                       public-net-version-response
                                       public-client-version-response
                                       public-rpc-modules-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((engine-rpc
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-result
                        (first (fixture-object-field engine-rpc "result")))
                      (public-rpc
                        (parse-json (devnet-cli-http-body public-response))))
                 (is (= 811 (fixture-object-field engine-rpc "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field engine-result "name")))
                 (is (= 812 (fixture-object-field public-rpc "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-rpc "result"))))
               (let* ((capabilities-rpc
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
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 813 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 814
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= terminal-block-hash
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 815
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
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
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field
                                       summary "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field
                                       summary "rpcEndpoint")))
                         (is (fixture-object-field
                              summary "publicRpcEnabled"))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (string= "/rpc"
                                      (fixture-object-field
                                       summary "publicRpcPrefix"))))
                       (is ready-record)
                       (is shutdown-record)
                       (is (string= engine-endpoint
                                    (cdr (assoc "engineEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= rpc-endpoint
                                    (cdr (assoc "rpcEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "true"
                                    (cdr (assoc "publicRpcEnabled"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "8"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list jwt-path config-path ready-path log-path pid-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-split-imports-payload
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (terminal-block-hash
           "0x5555555555555555555555555555555555555555555555555555555555555555")
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
         (expect (fixture-object-field case "expect"))
         (recipient (fixture-address-field expect "recipient"))
         (block-hash-hex (hash32-to-hex (block-hash child-block)))
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 819)
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
             (cons "id" 820)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3039")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 825)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3038")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (new-payload-body
           (json-encode (engine-fixture-payload-request 821 payload)))
         (forkchoice-body
           (json-encode
            (devnet-cli-engine-forkchoice-v2-request
             822
             (block-hash child-block)
             :safe (block-hash parent-block)
             :finalized (block-hash parent-block))))
         (block-number-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 823)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (balance-body
           (json-encode (engine-fixture-balance-request 824 recipient)))
         (net-version-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 826)
                  (cons "method" "net_version")
                  (cons "params" '()))))
         (client-version-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 827)
                  (cons "method" "web3_clientVersion")
                  (cons "params" '()))))
         (rpc-modules-body
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 828)
                  (cons "method" "rpc_modules")
                  (cons "params" '()))))
         (genesis-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import-genesis" "json"))
         (jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "jwt"))
         (ready-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import-ready" "json"))
         (log-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "log"))
         (pid-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "pid"))
         (database-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-no-command-split-import" "db"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (json-encode
             (devnet-cli-engine-fixture-parent-genesis-object case)))
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--genesis"
                        (namestring genesis-path)
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--authrpc.jwtsecret"
                        (namestring jwt-path)
                        "--authrpc.rpcprefix"
                        "/engine"
                        "--override.terminaltotaldifficulty"
                        "0x3039"
                        "--override.terminalblockhash"
                        terminal-block-hash
                        "--override.terminalblocknumber"
                        "66"
                        "--http"
                        "--http.addr"
                        "127.0.0.1"
                        "--http.port"
                        "0"
                        "--http.rpcprefix"
                        "/rpc"
                        "--database"
                        (namestring database-path)
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
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field ready-summary "rpcEndpoint"))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response
                    new-payload-response
                    forkchoice-response
                    block-number-response
                    balance-response
                    net-version-response
                    client-version-response
                    rpc-modules-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (stringp rpc-endpoint))
               (is (fixture-object-field ready-summary "publicRpcEnabled"))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field ready-summary
                                                  "publicRpcPrefix")))
               (is (= (block-header-number (block-header parent-block))
                      (fixture-object-field ready-summary "headNumber")))
               (handler-case
                   (progn
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
                             :target "/engine")))
                     (setf new-payload-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             new-payload-body
                             :token token
                             :target "/engine")))
                     (setf forkchoice-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             forkchoice-body
                             :token token
                             :target "/engine")))
                     (setf block-number-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             block-number-body
                             :target "/rpc")))
                     (setf balance-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             balance-body
                             :target "/rpc")))
                     (setf net-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             net-version-body
                             :target "/rpc")))
                     (setf client-version-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             client-version-body
                             :target "/rpc")))
                     (setf rpc-modules-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request
                             rpc-modules-body
                             :target "/rpc"))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (dolist (response (list capabilities-response
                                       transition-configuration-response
                                       transition-configuration-mismatch-response
                                       new-payload-response
                                       forkchoice-response
                                       block-number-response
                                       balance-response
                                       net-version-response
                                       client-version-response
                                       rpc-modules-response))
                 (is (= 200 (devnet-cli-http-status response))))
               (let* ((capabilities-rpc
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
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 819 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 820
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= terminal-block-hash
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 825
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
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
                      (net-version-rpc
                        (parse-json
                         (devnet-cli-http-body net-version-response)))
                      (client-version-rpc
                        (parse-json
                         (devnet-cli-http-body client-version-response)))
                      (rpc-modules-rpc
                        (parse-json
                         (devnet-cli-http-body rpc-modules-response))))
                 (is (= 821 (fixture-object-field new-payload-rpc "id")))
                 (is (= 822 (fixture-object-field forkchoice-rpc "id")))
                 (is (= 823 (fixture-object-field block-number-rpc "id")))
                 (is (= 824 (fixture-object-field balance-rpc "id")))
                 (is (= 826 (fixture-object-field net-version-rpc "id")))
                 (is (= 827 (fixture-object-field client-version-rpc "id")))
                 (is (= 828 (fixture-object-field rpc-modules-rpc "id")))
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
                              (fixture-object-field balance-rpc "result")))
                 (is (string= "1"
                              (fixture-object-field net-version-rpc "result")))
                 (is (search "ethereum-lisp/"
                             (fixture-object-field
                              client-version-rpc "result")))
                 (is (fixture-object-field
                      (fixture-object-field rpc-modules-rpc "result")
                      "eth")))
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
                            (shutdown-fields
                              (getf shutdown-record :fields)))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (= pid
                                (fixture-object-field summary "processId")))
                         (is (string= engine-endpoint
                                      (fixture-object-field
                                       summary "engineEndpoint")))
                         (is (string= rpc-endpoint
                                      (fixture-object-field
                                       summary "rpcEndpoint")))
                         (is (fixture-object-field
                              summary "publicRpcEnabled"))
                         (is (string= "/engine"
                                      (fixture-object-field
                                       summary "engineRpcPrefix")))
                         (is (string= "/rpc"
                                      (fixture-object-field
                                       summary "publicRpcPrefix")))
                         (is (string= (namestring database-path)
                                      (fixture-object-field
                                       summary "databasePath"))))
                       (is ready-record)
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
                                                :test #'string=))))
                       (is (probe-file database-path))
                       (multiple-value-bind
                             (restore-stdout restore-stderr restore-status)
                           (uiop:run-program
                            (list "sbcl"
                                  "--script"
                                  script
                                  "--"
                                  "--genesis"
                                  (namestring genesis-path)
                                  "--database"
                                  (namestring database-path)
                                  "--authrpc.rpcprefix"
                                  "/engine"
                                  "--http"
                                  "--http.rpcprefix"
                                  "/rpc"
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
                             (is (fixture-object-field
                                  restore-summary "publicRpcEnabled"))
                             (is (string= "/engine"
                                          (fixture-object-field
                                           restore-summary
                                           "engineRpcPrefix")))
                             (is (string= "/rpc"
                                          (fixture-object-field
                                           restore-summary
                                           "publicRpcPrefix")))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list genesis-path jwt-path ready-path log-path pid-path
                          database-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest ethereum-lisp-script-no-command-engine-only-serve-mode
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (terminal-block-hash
           "0x3333333333333333333333333333333333333333333333333333333333333333")
         (capabilities-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 802)
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
             (cons "id" 803)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3039")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
         (transition-configuration-mismatch-body
           (json-encode
            (list
             (cons "jsonrpc" "2.0")
             (cons "id" 804)
             (cons "method" "engine_exchangeTransitionConfigurationV1")
             (cons "params"
                   (list
                    (list
                     (cons "terminalTotalDifficulty" "0x3038")
                     (cons "terminalBlockHash" terminal-block-hash)
                     (cons "terminalBlockNumber" "0x42")))))))
        (jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command" "jwt"))
        (public-port nil)
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-no-command-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-no-command" "pid"))
        (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (setf public-port (devnet-cli-unused-loopback-port))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--dev"
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
                        "--override.terminaltotaldifficulty"
                        "0x3039"
                        "--override.terminalblockhash"
                        terminal-block-hash
                        "--override.terminalblocknumber"
                        "66"
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
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (configured-public-endpoint
                      (format nil "http://127.0.0.1:~D" public-port))
                    (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    (engine-body
                      (concatenate
                       'string
                       "{\"jsonrpc\":\"2.0\",\"id\":801,"
                       "\"method\":\"engine_getClientVersionV1\","
                       "\"params\":[{\"code\":\"runner\","
                       "\"name\":\"no-command-script\","
                       "\"version\":\"1\",\"commit\":\"0x00000000\"}]}"))
                    blocked-engine-response
                    engine-response
                    capabilities-response
                    transition-configuration-response
                    transition-configuration-mismatch-response)
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
                             :token token)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :target "/engine")))
                     (setf capabilities-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             capabilities-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-body
                             :token token
                             :target "/engine")))
                     (setf transition-configuration-mismatch-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             transition-configuration-mismatch-body
                             :token token
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
               (let* ((engine-rpc
                        (parse-json (devnet-cli-http-body engine-response)))
                      (engine-result
                        (first (fixture-object-field engine-rpc "result"))))
                 (is (= 801 (fixture-object-field engine-rpc "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field engine-result "name"))))
               (let* ((capabilities-rpc
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
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error")))
                 (is (= 802 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-engine-capability-list
                  capabilities-result)
                 (is (= 803
                        (fixture-object-field
                         transition-configuration-rpc "id")))
                 (is (string= "0x3039"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalTotalDifficulty")))
                 (is (string= terminal-block-hash
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockHash")))
                 (is (string= "0x42"
                              (fixture-object-field
                               transition-configuration-result
                               "terminalBlockNumber")))
                 (is (= 804
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "id")))
                 (is (= -32602
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code")))
                 (is (search "terminalTotalDifficulty mismatch"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))))
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
                                       summary "engineRpcPrefix"))))
                       (is ready-record)
                       (is shutdown-record)
                       (is (string= engine-endpoint
                                    (cdr (assoc "engineEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= ""
                                    (cdr (assoc "rpcEndpoint"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "false"
                                    (cdr (assoc "publicRpcEnabled"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "0"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "5"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list jwt-path ready-path log-path pid-path))
        (when (probe-file path)
          (delete-file path))))))

