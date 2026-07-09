(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-serve-mode-boots-initialized-datadir
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (datadir
           (devnet-cli-temp-directory "ethereum-lisp-script-serve-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path
            "ethereum-lisp-script-serve-datadir-explicit-jwt"
            "hex"))
         (ready-path
           (devnet-cli-temp-path "ethereum-lisp-script-serve-datadir-ready"
                                 "json"))
         (log-path
           (devnet-cli-temp-path "ethereum-lisp-script-serve-datadir" "log"))
         (pid-path
           (devnet-cli-temp-path "ethereum-lisp-script-serve-datadir" "pid"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file explicit-jwt-path
                                       +devnet-cli-jwt-secret+)
           (multiple-value-bind (init-stdout init-stderr init-status)
               (uiop:run-program
                (list "sbcl"
                      "--script"
                      script
                      "--"
                      "--datadir"
                      (namestring datadir)
                      "--authrpc.jwtsecret"
                      (namestring explicit-jwt-path)
                      "init"
                      "--json"
                      genesis)
                :directory #P"/private/tmp/"
                :output :string
                :error-output :string
                :ignore-error-status t)
             (is (= 0 init-status))
             (is (string= "" init-stderr))
             (when (= 0 init-status)
               (let ((summary (parse-json init-stdout)))
                 (is (string= (namestring datadir-database-path)
                              (fixture-object-field summary
                                                    "databasePath")))
                 (is (string= (namestring datadir-jwt-path)
                              (fixture-object-field summary
                                                    "jwtSecretPath")))
                 (is (eq t (fixture-object-field summary
                                                  "authRequired"))))))
           (is (probe-file datadir-genesis-path))
           (is (probe-file datadir-database-path))
           (is (probe-file datadir-jwt-path))
           (is (string= +devnet-cli-jwt-secret+
                        (string-trim
                         '(#\Space #\Tab #\Newline #\Return)
                         (devnet-cli-file-string datadir-jwt-path))))
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--datadir"
                        (namestring datadir)
                        "devnet"
                        "--json"
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
                        "2")
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
                    (engine-body
                      "{\"jsonrpc\":\"2.0\",\"id\":701,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"datadir-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                    (public-body
                      "{\"jsonrpc\":\"2.0\",\"id\":702,\"method\":\"eth_chainId\",\"params\":[]}")
                    (public-net-body
                      "{\"jsonrpc\":\"2.0\",\"id\":703,\"method\":\"net_version\",\"params\":[]}")
                    (jwt-secret
                      (hex-to-bytes
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (devnet-cli-file-string
                                     datadir-jwt-path))))
                    (token (engine-rpc-make-jwt-token jwt-secret 0))
                    engine-unauthenticated-response
                    engine-response
                    public-response
                    public-net-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= (namestring (truename datadir-genesis-path))
                            (fixture-object-field ready-summary
                                                  "genesisPath")))
               (is (string= (namestring datadir-database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (string= (namestring datadir-jwt-path)
                            (fixture-object-field ready-summary
                                                  "jwtSecretPath")))
               (handler-case
                   (progn
                     (setf engine-unauthenticated-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request engine-body)))
                     (setf engine-response
                           (devnet-cli-http-endpoint-request
                            engine-endpoint
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token)))
                     (setf public-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                            (devnet-cli-json-rpc-http-request public-body)))
                     (setf public-net-response
                           (devnet-cli-http-endpoint-request
                            rpc-endpoint
                             (devnet-cli-json-rpc-http-request
                              public-net-body))))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 401
                      (devnet-cli-http-status engine-unauthenticated-response)))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status public-response)))
               (is (= 200 (devnet-cli-http-status public-net-response)))
               (let* ((engine-json
                        (parse-json (devnet-cli-http-body engine-response)))
                      (public-json
                        (parse-json (devnet-cli-http-body public-response)))
                      (public-net-json
                        (parse-json
                         (devnet-cli-http-body public-net-response)))
                      (client-version
                        (first (fixture-object-field engine-json "result"))))
                 (is (= 701 (fixture-object-field engine-json "id")))
                 (is (string= "ethereum-lisp"
                              (fixture-object-field client-version "name")))
                 (is (= 702 (fixture-object-field public-json "id")))
                 (is (string= "0x539"
                              (fixture-object-field public-json "result")))
                 (is (= 703 (fixture-object-field public-net-json "id")))
                 (is (string= "1337"
                              (fixture-object-field public-net-json
                                                    "result"))))
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
                       (is (string= (namestring
                                     (truename datadir-genesis-path))
                                    (fixture-object-field stdout-summary
                                                          "genesisPath")))
                       (is (string= (namestring datadir-database-path)
                                    (fixture-object-field stdout-summary
                                                          "databasePath")))
                       (is (eq t (fixture-object-field stdout-summary
                                                       "authRequired")))
                       (is (string= (namestring datadir-jwt-path)
                                    (fixture-object-field stdout-summary
                                                          "jwtSecretPath")))
                       (is (string= engine-endpoint
                                    (fixture-object-field stdout-summary
                                                          "engineEndpoint")))
                       (is (string= rpc-endpoint
                                    (fixture-object-field stdout-summary
                                                          "rpcEndpoint")))
                       (is shutdown-record)
                       (is (string= "2"
                                    (cdr (assoc "engineConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "2"
                                    (cdr (assoc "publicConnections"
                                                shutdown-fields
                                                :test #'string=))))
                       (is (string= "4"
                                    (cdr (assoc "totalConnections"
                                                shutdown-fields
                                                :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (dolist (path (list datadir-genesis-path
                          datadir-database-path
                          datadir-jwt-path
                          explicit-jwt-path
                          ready-path
                          log-path
                          pid-path))
        (when (probe-file path)
          (delete-file path))))))

