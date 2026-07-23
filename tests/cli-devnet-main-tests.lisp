(in-package #:ethereum-lisp.test)

(deftest devnet-cli-main-no-serve-prints-summary
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--port" "0"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (read-from-string (get-output-stream-string output))))
      (is (= 1337 (getf summary :chain-id)))
      (is (= 0 (getf summary :head-number)))
      (is (string= "127.0.0.1:8545" (getf summary :rpc-endpoint)))
      (is (getf summary :state-available-p)))))

(deftest devnet-cli-main-kzg-verifier-command-scopes-hooks
  (:layer :integration :module :kzg :launches-processes t)
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream))
        (missing-output (make-string-output-stream))
        (missing-errors (make-string-output-stream))
        (non-executable-output (make-string-output-stream))
        (non-executable-errors (make-string-output-stream))
        (kzg-command
          (devnet-cli-temp-path "ethereum-lisp-kzg-scoped" "sh"))
        (missing-kzg-command
          (devnet-cli-temp-path "ethereum-lisp-kzg-missing" "sh"))
        (non-executable-kzg-command
          (devnet-cli-temp-path "ethereum-lisp-kzg-non-executable" "sh"))
        (old-point-verifier *kzg-point-proof-verifier*)
        (old-blob-verifier *kzg-blob-proof-verifier*))
    (unwind-protect
         (progn
           (setf *kzg-point-proof-verifier* nil
                 *kzg-blob-proof-verifier* nil)
           (devnet-cli-write-temp-file
            kzg-command
            "#!/bin/sh\necho true\n")
           (devnet-cli-make-executable kzg-command)
           (devnet-cli-write-temp-file
            non-executable-kzg-command
            "#!/bin/sh\necho true\n")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--kzg-verifier-command" (namestring kzg-command)
                         "--kzg-verifier-timeout" "2"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= (namestring kzg-command)
                          (fixture-object-field
                           summary "kzgVerifierCommand")))
             (is (= 2 (fixture-object-field
                       summary "kzgVerifierTimeoutSeconds")))
             (is (fixture-object-field
                  summary "kzgProofVerificationAvailable")))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--kzg-verifier-command"
                         (namestring missing-kzg-command)
                         "--json"
                         "--no-serve")
                   :output-stream missing-output
                   :error-stream missing-errors)))
           (is (string= "" (get-output-stream-string missing-output)))
           (is (search "KZG verifier command is not executable"
                       (get-output-stream-string missing-errors)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--kzg-verifier-command"
                         (namestring non-executable-kzg-command)
                         "--json"
                         "--no-serve")
                   :output-stream non-executable-output
                   :error-stream non-executable-errors)))
           (is (string= ""
                        (get-output-stream-string non-executable-output)))
           (is (search "KZG verifier command is not executable"
                       (get-output-stream-string non-executable-errors)))
           (is (not (kzg-proof-verification-available-p))))
      (setf *kzg-point-proof-verifier* old-point-verifier
            *kzg-blob-proof-verifier* old-blob-verifier)
      (when (probe-file kzg-command)
        (delete-file kzg-command))
      (when (probe-file missing-kzg-command)
        (delete-file missing-kzg-command))
      (when (probe-file non-executable-kzg-command)
        (delete-file non-executable-kzg-command)))))

(deftest ethereum-lisp-script-engine-only-kzg-verifier-advertises-blob-capabilities
  (:layer :e2e :module :cli :launches-processes t
   :requires-local-sockets t)
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (kzg-command
           (devnet-cli-temp-path "ethereum-lisp-script-kzg-command" "sh"))
         (ready-path
           (devnet-cli-temp-path "ethereum-lisp-script-kzg-ready" "json"))
         (log-path
           (devnet-cli-temp-path "ethereum-lisp-script-kzg" "log"))
         (pid-path
           (devnet-cli-temp-path "ethereum-lisp-script-kzg" "pid"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            kzg-command
            "#!/bin/sh\necho true\n")
           (devnet-cli-make-executable kzg-command)
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
                        "--http=false"
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
                        "1"
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
                    (capabilities-body
                      "{\"jsonrpc\":\"2.0\",\"id\":715,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    capabilities-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= (namestring kzg-command)
                            (fixture-object-field ready-summary
                                                  "kzgVerifierCommand")))
               (is (= 2 (fixture-object-field
                         ready-summary "kzgVerifierTimeoutSeconds")))
               (is (fixture-object-field
                    ready-summary "kzgProofVerificationAvailable"))
               (handler-case
                   (setf capabilities-response
                         (devnet-cli-http-endpoint-request
                          engine-endpoint
                          (devnet-cli-json-rpc-http-request
                           capabilities-body)))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result")))
                 (is (= 715 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-kzg-backed-engine-capability-list
                  capabilities-result))
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
                         (is (string= (namestring kzg-command)
                                      (fixture-object-field
                                       summary "kzgVerifierCommand")))
                         (is (= 2 (fixture-object-field
                                   summary
                                   "kzgVerifierTimeoutSeconds")))
                         (is (fixture-object-field
                              summary
                              "kzgProofVerificationAvailable")))
                       (dolist (record (list ready-record shutdown-record))
                         (is record)
                         (let ((fields (getf record :fields)))
                           (is (string= (namestring kzg-command)
                                        (cdr (assoc "kzgVerifierCommand"
                                                    fields
                                                    :test #'string=))))
                           (is (string= "2"
                                        (cdr (assoc
                                              "kzgVerifierTimeoutSeconds"
                                              fields
                                              :test #'string=))))
                           (is (string= "true"
                                        (cdr (assoc
                                              "kzgProofVerificationAvailable"
                                              fields
                                              :test #'string=))))))
                       (let ((shutdown-fields
                               (getf shutdown-record :fields)))
                         (is (string= "1"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "0"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "1"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file kzg-command)
        (delete-file kzg-command))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))))

(deftest devnet-cli-main-database-restores-and-exports-chain-store
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-chain" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (genesis
                    (ethereum-lisp.cli:devnet-node-genesis-block seed-node))
                  (funded
                    (address-from-hex
                     "0x0000000000000000000000000000000000001001"))
                  (child
                    (make-block
                     :header
                     (make-block-header
                      :number 1
                      :parent-hash (block-hash genesis)
                      :timestamp 1
                      :gas-limit 30000000))))
             (let ((state (make-state-db)))
               (state-db-set-account
                state funded (make-state-account :balance 42))
               (setf (block-header-state-root (block-header child))
                     (state-db-root state)))
             (chain-store-put-block seed-store child :state-available-p t)
             (chain-store-put-account-balance
              seed-store (block-hash child) funded 42)
             (chain-store-set-canonical-head seed-store (block-hash child))
             (node-store-export-to-kv
              seed-store
              (make-file-key-value-database database-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-port" "0"
                         "--database" (namestring database-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary
                    (parse-json (get-output-stream-string output)))
                  (database
                    (make-file-key-value-database database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (head
                    (chain-store-latest-block restored-store))
                  (funded
                    (address-from-hex
                     "0x0000000000000000000000000000000000001001")))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (= 1 (fixture-object-field summary "headNumber")))
             (is (string= (namestring database-path)
                          (fixture-object-field summary "databasePath")))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries
                               database :canonical-hash))))
             (is (= 1 (block-header-number (block-header head))))
             (is (chain-store-state-available-p restored-store
                                                (block-hash head)))
             (is (= 42
                    (chain-store-account-balance
                     restored-store (block-hash head) funded)))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-rejects-partial-database-without-chain-baseline
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-partial-chain" "sexp"))
        (raw-key #(255 238 221 204))
        (raw-value #(1 3 3 7))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (let* ((database (make-file-key-value-database database-path)))
           (kv-put database raw-key raw-value)
           ;; The database file is binary; compare octets, not characters.
           (let ((before (devnet-cli-file-octets database-path)))
             (is (= 1
                    (ethereum-lisp.cli:main
                     (list "devnet"
                           "--genesis" +devnet-cli-genesis-fixture+
                           "--port" "0"
                           "--database" (namestring database-path)
                           "--json"
                           "--no-serve")
                     :output-stream output
                     :error-stream errors)))
             (is (string= "" (get-output-stream-string output)))
             (is (search "Devnet database contains records without a chain baseline"
                         (get-output-stream-string errors)))
             (is (bytes= before (devnet-cli-file-octets database-path)))
             (let ((reopened (make-file-key-value-database database-path)))
               (multiple-value-bind (value present-p)
                   (kv-get reopened raw-key)
                 (is present-p)
                 (is (bytes= raw-value value)))
               (dolist (kind '(:block :header :receipt :canonical-hash
                               :checkpoint :state :transaction-location))
                 (is (null (kv-chain-record-entries reopened kind)))))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-datadir-defaults-database-path
  (let* ((datadir
           (devnet-cli-temp-directory "ethereum-lisp-devnet-datadir"))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (datadir-geth-jwt-path
           (merge-pathnames "geth/jwtsecret" datadir))
         (explicit-database-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-explicit-chain" "sexp"))
         (explicit-jwt-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-explicit-jwt" "hex"))
         (output (make-string-output-stream))
         (errors (make-string-output-stream))
         (override-output (make-string-output-stream))
         (override-errors (make-string-output-stream))
         (explicit-jwt-output (make-string-output-stream))
         (explicit-jwt-errors (make-string-output-stream))
         (geth-jwt-output (make-string-output-stream))
         (geth-jwt-errors (make-string-output-stream))
         (precommand-output (make-string-output-stream))
         (precommand-errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file datadir-jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file explicit-jwt-path +devnet-cli-jwt-secret+)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary (parse-json (get-output-stream-string output)))
                  (database
                    (make-file-key-value-database datadir-database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring datadir-database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (head (chain-store-latest-block restored-store)))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field summary "databasePath")))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired"))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries database :state))))
             (is (= 0 (block-header-number (block-header head))))
             (is (chain-store-state-available-p restored-store
                                                (block-hash head))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--database" (namestring explicit-database-path)
                         "--json"
                         "--no-serve")
                   :output-stream override-output
                   :error-stream override-errors)))
           (is (string= "" (get-output-stream-string override-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string override-output))))
             (is (string= (namestring explicit-database-path)
                          (fixture-object-field summary "databasePath"))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--jwt-secret" (namestring explicit-jwt-path)
                         "--json"
                         "--no-serve")
                   :output-stream explicit-jwt-output
                   :error-stream explicit-jwt-errors)))
           (is (string= "" (get-output-stream-string explicit-jwt-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string explicit-jwt-output))))
             (is (string= (namestring explicit-jwt-path)
                          (fixture-object-field summary "jwtSecretPath"))))
           (ensure-directories-exist datadir-geth-jwt-path)
           (devnet-cli-write-temp-file datadir-geth-jwt-path
                                       +devnet-cli-jwt-secret+)
           (delete-file datadir-jwt-path)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream geth-jwt-output
                   :error-stream geth-jwt-errors)))
           (is (string= "" (get-output-stream-string geth-jwt-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string geth-jwt-output))))
             (is (string= (namestring datadir-geth-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired")))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "--identity" "init"
                         "--datadir" (namestring datadir)
                         "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--json"
                         "--no-serve")
                   :output-stream precommand-output
                   :error-stream precommand-errors)))
           (is (string= "" (get-output-stream-string precommand-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string precommand-output))))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field summary "databasePath")))))
      (when (probe-file datadir-database-path)
        (delete-file datadir-database-path))
      (when (probe-file datadir-jwt-path)
        (delete-file datadir-jwt-path))
      (when (probe-file datadir-geth-jwt-path)
        (delete-file datadir-geth-jwt-path))
      (when (probe-file explicit-database-path)
        (delete-file explicit-database-path))
      (when (probe-file explicit-jwt-path)
        (delete-file explicit-jwt-path)))))

(deftest devnet-cli-main-init-datadir-seeds-genesis-and-database
  (let* ((datadir
           (devnet-cli-temp-directory "ethereum-lisp-devnet-init-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-init-explicit-jwt"
                                 "hex"))
         (init-output (make-string-output-stream))
         (init-errors (make-string-output-stream))
         (devnet-output (make-string-output-stream))
         (devnet-errors (make-string-output-stream))
         (explicit-init-output (make-string-output-stream))
         (explicit-init-errors (make-string-output-stream))
         (explicit-devnet-output (make-string-output-stream))
         (explicit-devnet-errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "init"
                         "--datadir" (namestring datadir)
                         "--json"
                         +devnet-cli-genesis-fixture+)
                   :output-stream init-output
                   :error-stream init-errors)))
           (is (string= "" (get-output-stream-string init-errors)))
           (let* ((init-summary
                    (parse-json (get-output-stream-string init-output)))
                  (database
                    (make-file-key-value-database datadir-database-path)))
             (is (= 1337 (fixture-object-field init-summary "chainId")))
             (is (= 0 (fixture-object-field init-summary "headNumber")))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field init-summary "databasePath")))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field init-summary "jwtSecretPath")))
             (is (fixture-object-field init-summary "authRequired"))
             (is (probe-file datadir-genesis-path))
             (is (probe-file datadir-jwt-path))
             (is (= 32
                    (length
                     (hex-to-bytes
                      (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   (devnet-cli-file-string
                                    datadir-jwt-path))))))
             (is (string= (devnet-cli-file-string
                           +devnet-cli-genesis-fixture+)
                          (devnet-cli-file-string datadir-genesis-path)))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries database :state)))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream devnet-output
                   :error-stream devnet-errors)))
           (is (string= "" (get-output-stream-string devnet-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string devnet-output))))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (= 0 (fixture-object-field summary "headNumber")))
             (is (string= (namestring (truename datadir-genesis-path))
                          (fixture-object-field summary "genesisPath")))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field summary "databasePath")))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired")))
           (devnet-cli-write-temp-file explicit-jwt-path +devnet-cli-jwt-secret+)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "init"
                         "--datadir" (namestring datadir)
                         "--authrpc.jwtsecret" (namestring explicit-jwt-path)
                         "--json"
                         +devnet-cli-genesis-fixture+)
                   :output-stream explicit-init-output
                   :error-stream explicit-init-errors)))
           (is (string= "" (get-output-stream-string explicit-init-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string explicit-init-output))))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired"))
             (is (string= +devnet-cli-jwt-secret+
                          (string-trim
                           '(#\Space #\Tab #\Newline #\Return)
                           (devnet-cli-file-string datadir-jwt-path)))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream explicit-devnet-output
                   :error-stream explicit-devnet-errors)))
           (is (string= "" (get-output-stream-string explicit-devnet-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string explicit-devnet-output))))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired"))))
      (when (probe-file datadir-genesis-path)
        (delete-file datadir-genesis-path))
      (when (probe-file datadir-jwt-path)
        (delete-file datadir-jwt-path))
      (when (probe-file explicit-jwt-path)
        (delete-file explicit-jwt-path))
      (when (probe-file datadir-database-path)
        (delete-file datadir-database-path)))))

(deftest devnet-cli-main-dev-mode-uses-embedded-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet" "--dev" "--json" "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (= 1337 (fixture-object-field summary "chainId")))
      (is (= 0 (fixture-object-field summary "headNumber")))
      (is (= #x1c9c380
             (fixture-object-field summary "headGasLimit")))
      (is (fixture-field-present-p summary "genesisPath"))
      (is (null (fixture-object-field summary "genesisPath")))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (eq t (fixture-object-field summary "stateAvailable"))))))

(deftest devnet-cli-main-dev-gaslimit-shapes-embedded-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--dev.gaslimit"
                  "31000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (= 31000000
             (fixture-object-field summary "headGasLimit"))))))

(deftest devnet-cli-main-miner-gaslimit-shapes-embedded-dev-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.gaslimit"
                  "32000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (= 32000000
             (fixture-object-field summary "headGasLimit")))))
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.gaslimit"
                  "32000000"
                  "--dev.gaslimit"
                  "33000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (= 33000000
             (fixture-object-field summary "headGasLimit"))))))

(deftest devnet-cli-main-miner-etherbase-shapes-dev-coinbase
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream))
        (coinbase "0x00000000000000000000000000000000000000cb"))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.etherbase"
                  coinbase
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (string= coinbase
                   (fixture-object-field summary "coinbase")))))
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream))
        (coinbase "0x00000000000000000000000000000000000000cc"))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.etherbase"
                  "0x00000000000000000000000000000000000000cb"
                  "--etherbase"
                  coinbase
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (string= coinbase
                   (fixture-object-field summary "coinbase"))))))

(deftest devnet-cli-main-treats-empty-database-as-new-chain
  (labels ((write-empty-kv-database (path)
             (with-open-file (stream path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (let ((*print-readably* t)
                     (*print-pretty* nil))
                 (write '(:ethereum-lisp-kv-v1 nil) :stream stream)
                 (terpri stream)))))
    (dolist (mode '(:empty-file :empty-kv))
      (let ((database-path
              (devnet-cli-temp-path "ethereum-lisp-devnet-empty-chain"
                                     "sexp"))
            (output (make-string-output-stream))
            (errors (make-string-output-stream)))
        (unwind-protect
             (progn
               (ecase mode
                 (:empty-file
                  (devnet-cli-write-temp-file database-path ""))
                 (:empty-kv
                  (write-empty-kv-database database-path)))
               (is (= 0
                      (ethereum-lisp.cli:main
                       (list "devnet"
                             "--genesis" +devnet-cli-genesis-fixture+
                             "--port" "0"
                             "--database" (namestring database-path)
                             "--json"
                             "--no-serve")
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string errors)))
               (let* ((summary
                        (parse-json (get-output-stream-string output)))
                      (database (make-file-key-value-database database-path))
                      (restored-node
                        (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 0
                         :database-path (namestring database-path)))
                      (restored-store
                        (ethereum-lisp.cli:devnet-node-store restored-node))
                      (head (chain-store-latest-block restored-store)))
                 (is (= 1337 (fixture-object-field summary "chainId")))
                 (is (= 0 (fixture-object-field summary "headNumber")))
                 (is (eq t (fixture-object-field summary "stateAvailable")))
                 (is (< 0 (length (kv-chain-record-entries database :block))))
                 (is (< 0 (length (kv-chain-record-entries
                                   database :canonical-hash))))
                 (is (< 0 (length (kv-chain-record-entries database :state))))
                 (is (= 0 (block-header-number (block-header head))))
                 (is (chain-store-state-available-p restored-store
                                                    (block-hash head)))))
          (when (probe-file database-path)
            (delete-file database-path)))))))

(deftest devnet-cli-main-rejects-database-genesis-mismatch
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-mismatched-chain"
                                "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (state (make-state-db))
                  (mismatched-genesis
                    (make-block
                     :header
                     (make-block-header
                      :number 0
                      :timestamp 99
                      :gas-limit 30000000
                      :state-root (state-db-root state)))))
             (chain-store-put-block seed-store
                                    mismatched-genesis
                                    :state-available-p t)
             (commit-state-db-to-chain-store
              seed-store (block-hash mismatched-genesis) state)
             (chain-store-set-canonical-head seed-store
                                             (block-hash mismatched-genesis))
             (node-store-export-to-kv
              seed-store
              (make-file-key-value-database database-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--database" (namestring database-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "Devnet database genesis does not match genesis file"
                       (get-output-stream-string errors))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-prunes-state-before-database-export
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-pruned-chain" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (let* ((seed-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :port 0))
                (seed-store
                  (ethereum-lisp.cli:devnet-node-store seed-node))
                (genesis
                  (ethereum-lisp.cli:devnet-node-genesis-block seed-node))
                (funded
                  (address-from-hex
                   "0x0000000000000000000000000000000000001001"))
                (child
                  (make-block
                   :header
                   (make-block-header
                    :number 1
                    :parent-hash (block-hash genesis)
                    :timestamp 1
                    :gas-limit 30000000)))
                (genesis-id (hash32-bytes (block-hash genesis)))
                child-id)
           (let ((state (make-state-db)))
             (state-db-set-account
              state funded (make-state-account :balance 42))
             (setf (block-header-state-root (block-header child))
                   (state-db-root state)
                   child-id (hash32-bytes (block-hash child))))
           (chain-store-put-block seed-store child :state-available-p t)
           (chain-store-put-account-balance
            seed-store (block-hash child) funded 42)
           (chain-store-set-canonical-head seed-store (block-hash child))
           (node-store-export-to-kv
            seed-store
            (make-file-key-value-database database-path))
           (let ((database (make-file-key-value-database database-path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state genesis-id)
               (declare (ignore value))
               (is present-p)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--database" (namestring database-path)
                         "--prune-state-before" "2"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary (parse-json (get-output-stream-string output)))
                  (database (make-file-key-value-database database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node)))
             (is (= 1 (fixture-object-field summary "headNumber")))
             (is (eq t (fixture-object-field summary "stateAvailable")))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state genesis-id :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state child-id)
               (declare (ignore value))
               (is present-p))
             (is (chain-store-known-block restored-store (block-hash genesis)))
             (is (not (chain-store-state-available-p
                       restored-store (block-hash genesis))))
             (is (chain-store-state-available-p
                  restored-store (block-hash child)))
             (is (= 42
                    (chain-store-account-balance
                     restored-store (block-hash child) funded)))))
      (when (probe-file database-path)
        (delete-file database-path)))))
