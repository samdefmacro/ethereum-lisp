(in-package #:ethereum-lisp.test)

(deftest devnet-smoke-gate-script-engine-only-serve-mode
  (:layer :e2e :module :devnet-smoke :launches-processes t
   :requires-local-sockets t)
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let* ((artifact-root
           (devnet-cli-temp-directory
            "ethereum-lisp-devnet-engine-only-smoke"))
         (ready-path
           (merge-pathnames "ready/engine-only.json" artifact-root))
         (log-path
           (merge-pathnames "logs/engine-only.log" artifact-root))
         (pid-path
           (merge-pathnames "pid/engine-only.pid" artifact-root))
         (database-path
           (merge-pathnames "db/engine-only.sexp" artifact-root)))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    "scripts/devnet-smoke-gate.lisp"
                    "--"
                    "--engine-only-serve"
                    "--json"
                    "--ready-file"
                    (namestring ready-path)
                    "--log-file"
                    (namestring log-path)
                    "--pid-file"
                    (namestring pid-path)
                    "--database"
                    (namestring database-path))
              :output :string
              :error-output :string
              :ignore-error-status t)
           (when (and (not (= 0 status))
                      (search "Operation not permitted" stderr))
             (skip-test "Local socket bind is not permitted in this sandbox"))
           (unless (= 0 status)
             (error "Devnet engine-only smoke gate failed:~%~A" stderr))
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((report (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
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
                      (getf shutdown-record :fields))
                    (engine-endpoint
                      (fixture-object-field report "engineEndpoint")))
               (is (string= "ok" (fixture-object-field report "status")))
               (is (string= "devnet-engine-only-serve"
                            (fixture-object-field report "mode")))
               (is (search "http://127.0.0.1:" engine-endpoint))
               (is (not (fixture-object-field report "publicRpcEnabled")))
               (is (not (fixture-object-field report "rpcEndpoint")))
               (is (string= "/engine"
                            (fixture-object-field report "engineRpcPrefix")))
               (is (= 200 (fixture-object-field report
                                                 "engineRpcPrefixStatus")))
               (is (= 404 (fixture-object-field
                            report
                            "engineRpcPrefixBlockedStatus")))
               (devnet-cli-assert-engine-only-http-shaping-report report)
               (devnet-cli-assert-engine-capability-report report)
               (devnet-cli-assert-kzg-opt-in-smoke-report
                (fixture-object-field report "kzgOptIn"))
               (devnet-cli-assert-engine-client-version report)
               (devnet-cli-assert-engine-transition-configuration report)
               (devnet-cli-assert-engine-only-payload-report report)
               (devnet-cli-assert-engine-only-hidden-payload-bodies-v2-report
                report)
               (is (search "http://127.0.0.1:"
                           (fixture-object-field report
                                                 "configuredPublicEndpoint")))
               (is (not (fixture-object-field report
                                               "publicEndpointConnectable")))
               (devnet-cli-assert-engine-only-connection-contract report)
               (is (string= (namestring database-path)
                            (fixture-object-field report "databaseFile")))
               (is (probe-file database-path))
               (is (= (fixture-quantity-field report "forkchoiceHeadNumber")
                      (fixture-object-field report "databaseHeadNumber")))
               (is (string= (fixture-object-field report
                                                  "forkchoiceHeadHash")
                            (fixture-object-field report
                                                  "databaseHeadHash")))
               (is (fixture-object-field report "databaseStateAvailable"))
               (is (string= "ethereum-lisp"
                            (fixture-object-field report
                                                  "engineClientVersionName")))
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= engine-endpoint
                            (fixture-object-field ready-summary
                                                  "engineEndpoint")))
               (is (string= "/engine"
                            (fixture-object-field ready-summary
                                                  "engineRpcPrefix")))
               (is (equal '("https://engine-runner.example"
                            "https://engine-observer.example")
                          (fixture-object-field ready-summary
                                                "engineCorsOrigins")))
               (is (equal '("engine.runner" "localhost")
                          (fixture-object-field ready-summary
                                                "engineVhosts")))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                              "publicRpcEnabled")))
               (is ready-record)
               (is shutdown-record)
               (is (string= "11"
                            (cdr (assoc "engineConnections"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "0"
                            (cdr (assoc "publicConnections"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "11"
                            (cdr (assoc "totalConnections"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "https://engine-runner.example,https://engine-observer.example"
                            (cdr (assoc "engineCorsOrigins"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "engine.runner,localhost"
                            (cdr (assoc "engineVhosts"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= (fixture-object-field report
                                                  "forkchoiceHeadNumber")
                            (cdr (assoc "headNumber"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= (fixture-object-field report
                                                  "forkchoiceHeadHash")
                            (cdr (assoc "headHash"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= ""
                            (cdr (assoc "rpcEndpoint"
                                        shutdown-fields
                                        :test #'string=))))
               (is (string= "false"
                            (cdr (assoc "publicRpcEnabled"
                                        shutdown-fields
                                        :test #'string=)))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file database-path)
        (delete-file database-path)))))
