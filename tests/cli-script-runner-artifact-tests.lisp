(in-package #:ethereum-lisp.test)

(deftest ethereum-lisp-script-is-cwd-independent-for-runner-artifacts
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script" "pid")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    script
                    "--"
                    "devnet"
                    "--genesis"
                    genesis
                    "--engine-port"
                    "0"
                    "--public-port"
                    "8546"
                    "--ready-file"
                    (namestring ready-path)
                    "--log-file"
                    (namestring log-path)
                    "--pid-file"
                    (namestring pid-path)
                    "--json"
                    "--no-serve")
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((stdout-summary (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records)))
               (dolist (summary (list stdout-summary ready-summary))
                 (is (string= genesis
                              (fixture-object-field summary "genesisPath")))
                 (is (= pid (fixture-object-field summary "processId")))
                 (is (string= "127.0.0.1:0"
                              (fixture-object-field summary
                                                    "engineEndpoint")))
                 (is (string= "127.0.0.1:8546"
                              (fixture-object-field summary "rpcEndpoint")))
                 (is (string= (namestring log-path)
                              (fixture-object-field summary "logPath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field summary "pidFilePath")))
                 (is (eq t
                         (fixture-object-field summary "stateAvailable"))))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (let ((fields (getf log-record :fields)))
                   (is (string= "127.0.0.1:0"
                                (cdr (assoc "engineEndpoint" fields
                                            :test #'string=))))
                   (is (string= "127.0.0.1:8546"
                                (cdr (assoc "rpcEndpoint" fields
                                            :test #'string=))))
                   (is (string= (if (string= "devnet.ready"
                                              (getf log-record :name))
                                     "ready"
                                     "shutdown")
                                (cdr (assoc "lifecyclePhase" fields
                                            :test #'string=))))
                   (is (string= (write-to-string pid)
                                (cdr (assoc "processId" fields
                                            :test #'string=))))
                   (is (string= (namestring log-path)
                                (cdr (assoc "logPath" fields
                                            :test #'string=))))
                   (is (string= (namestring pid-path)
                                (cdr (assoc "pidFilePath" fields
                                            :test #'string=)))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest ethereum-lisp-script-serve-mode-writes-runner-artifacts
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-serve" "pid")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    script
                    "--"
                    "devnet"
                    "--genesis"
                    genesis
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
                    "0"
                    "--json")
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (when (and (not (= 0 status))
                      (search "Operation not permitted" stderr))
             (skip-test "Local socket bind is not permitted in this sandbox"))
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((stdout-summary (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records))
                    (engine-endpoint
                      (fixture-object-field stdout-summary "engineEndpoint"))
                    (rpc-endpoint
                      (fixture-object-field stdout-summary "rpcEndpoint")))
               (is (string= genesis
                            (fixture-object-field stdout-summary
                                                  "genesisPath")))
               (is (= pid (fixture-object-field stdout-summary "processId")))
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (string= engine-endpoint
                            (fixture-object-field ready-summary
                                                  "engineEndpoint")))
               (is (string= rpc-endpoint
                            (fixture-object-field ready-summary
                                                  "rpcEndpoint")))
               (is (not (string= "127.0.0.1:0" engine-endpoint)))
               (is (not (string= "127.0.0.1:0" rpc-endpoint)))
               (is (search "127.0.0.1:" engine-endpoint))
               (is (search "127.0.0.1:" rpc-endpoint))
               (dolist (summary (list stdout-summary ready-summary))
                 (is (string= (namestring log-path)
                              (fixture-object-field summary "logPath")))
                 (is (string= (namestring pid-path)
                              (fixture-object-field summary "pidFilePath")))
                 (is (eq t
                         (fixture-object-field summary "stateAvailable"))))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (when (member (getf log-record :name)
                               '("devnet.ready" "devnet.shutdown")
                               :test #'string=)
                   (let ((fields (getf log-record :fields)))
                     (is (string= engine-endpoint
                                  (cdr (assoc "engineEndpoint" fields
                                              :test #'string=))))
                     (is (string= rpc-endpoint
                                  (cdr (assoc "rpcEndpoint" fields
                                              :test #'string=))))
                     (is (string= (if (string= "devnet.ready"
                                                (getf log-record :name))
                                       "ready"
                                       "shutdown")
                                  (cdr (assoc "lifecyclePhase" fields
                                              :test #'string=))))
                     (is (string= "0"
                                  (cdr (assoc "engineConnections" fields
                                              :test #'string=))))
                     (is (string= "0"
                                  (cdr (assoc "publicConnections" fields
                                              :test #'string=))))
                     (is (string= "0"
                                  (cdr (assoc "totalConnections" fields
                                              :test #'string=))))
                     (is (string= (write-to-string pid)
                                  (cdr (assoc "processId" fields
                                              :test #'string=))))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

