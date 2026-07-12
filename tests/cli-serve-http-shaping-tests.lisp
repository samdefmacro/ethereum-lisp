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
                 (test-launch-program
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

