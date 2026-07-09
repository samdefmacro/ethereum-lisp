(in-package #:ethereum-lisp.test)

(deftest devnet-cli-merge-overrides-configure-transition-handshake
  (let* ((terminal-block-hash-hex
           "0x2222222222222222222222222222222222222222222222222222222222222222")
         (options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet"
                  "--override.terminaltotaldifficulty=0x3039"
                  "--override.terminaltotaldifficultypassed=false"
                  "--override.terminalblockhash" terminal-block-hash-hex
                  "--override.terminalblocknumber" "66"
                  "--no-serve")))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path +devnet-cli-genesis-fixture+
            :terminal-total-difficulty
            (getf options :terminal-total-difficulty)
            :terminal-total-difficulty-passed
            (getf options :terminal-total-difficulty-passed)
            :terminal-total-difficulty-passed-specified-p
            (getf options :terminal-total-difficulty-passed-specified-p)
            :terminal-block-hash
            (getf options :terminal-block-hash)
            :terminal-block-number
            (getf options :terminal-block-number)))
         (config (ethereum-lisp.cli:devnet-node-config node))
         (transition
           (ethereum-lisp.core::engine-rpc-transition-configuration-object
            config)))
    (is (= 12345 (chain-config-terminal-total-difficulty config)))
    (is (not (chain-config-terminal-total-difficulty-passed config)))
    (is (string= terminal-block-hash-hex
                 (hash32-to-hex
                  (chain-config-terminal-block-hash config))))
    (is (= 66 (chain-config-terminal-block-number config)))
    (is (string= "0x3039"
                 (fixture-object-field transition
                                       "terminalTotalDifficulty")))
    (is (string= terminal-block-hash-hex
                 (fixture-object-field transition "terminalBlockHash")))
    (is (string= "0x42"
                 (fixture-object-field transition "terminalBlockNumber")))))

(deftest devnet-cli-main-engine-host-does-not-rewrite-public-default
  (let ((engine-output (make-string-output-stream))
        (engine-errors (make-string-output-stream))
        (host-output (make-string-output-stream))
        (host-errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--engine-host" "192.0.2.10"
                  "--engine-port" "9551"
                  "--json"
                  "--no-serve")
            :output-stream engine-output
            :error-stream engine-errors)))
    (is (string= "" (get-output-stream-string engine-errors)))
    (let ((summary (parse-json (get-output-stream-string engine-output))))
      (is (string= "192.0.2.10:9551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint"))))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--host" "192.0.2.20"
                  "--port" "9552"
                  "--json"
                  "--no-serve")
            :output-stream host-output
            :error-stream host-errors)))
    (is (string= "" (get-output-stream-string host-errors)))
    (let ((summary (parse-json (get-output-stream-string host-output))))
      (is (string= "192.0.2.20:8551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "192.0.2.20:8545"
                   (fixture-object-field summary "rpcEndpoint"))))))

(deftest devnet-cli-main-log-file-records-ready-event
  (let ((ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (pid-path (devnet-cli-temp-path "ethereum-lisp-devnet" "pid"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let ((log-path-string (namestring log-path)))
             (is (= 0
                    (ethereum-lisp.cli:main
                     (list "devnet"
                           "--genesis" +devnet-cli-genesis-fixture+
                           "--engine-port" "0"
                           "--public-port" "8546"
                           "--ready-file" (namestring ready-path)
                           "--log-file" log-path-string
                           "--pid-file" (namestring pid-path)
                           "--json"
                           "--no-serve")
                     :output-stream output
                     :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path))
                  (log-names
                    (mapcar (lambda (record) (getf record :name))
                            log-records)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= log-path-string
                            (fixture-object-field summary "logPath"))))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (is (member "devnet.ready" log-names :test #'string=))
             (is (member "devnet.shutdown" log-names :test #'string=))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (eq :log (getf log-record :kind)))
                 (is (eq :info (getf log-record :value)))
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
                 (is (string= "0"
                              (cdr (assoc "engineConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "publicConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "totalConnections" fields
                                          :test #'string=))))
                 (is (string= (devnet-cli-current-process-id-string)
                              (cdr (assoc "processId" fields
                                          :test #'string=))))
                 (is (string= "0x539"
                              (cdr (assoc "chainId" fields :test #'string=))))
                 (is (string= "0x0"
                              (cdr (assoc "headNumber" fields
                                          :test #'string=))))
                 (is (stringp
                      (cdr (assoc "headHash" fields :test #'string=))))
                 (is (string= "true"
                              (cdr (assoc "stateAvailable" fields
                                          :test #'string=))))
                 (is (string= log-path-string
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

(deftest devnet-cli-main-log-file-records-error-event
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-error-artifacts"))
         (log-path (merge-pathnames "errors/nested/devnet-error.log" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (let ((log-path-string (namestring log-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--log-file" log-path-string
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "--genesis is required"
                       (get-output-stream-string errors)))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= "devnet.error" (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (string= (devnet-cli-current-process-id-string)
                          (cdr (assoc "processId" fields :test #'string=))))
             (is (search "--genesis is required"
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= log-path-string
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest devnet-cli-main-invalid-error-log-path-still-reports-error
  (let* ((log-directory
           (devnet-cli-temp-directory
            "ethereum-lisp-devnet-error-log-directory"))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--log-file" (namestring log-directory)
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (let ((stderr (get-output-stream-string errors)))
      (is (search "--genesis is required" stderr))
      (is (search "Usage: ethereum-lisp devnet" stderr)))))

(deftest devnet-cli-main-log-file-records-option-parse-error-event
  (let ((log-path (devnet-cli-temp-path "ethereum-lisp-devnet-parse-error"
                                        "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (let ((log-path-string (namestring log-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--http"
                         "false"
                         "--ws.api"
                         "eth,net"
                         "--txpool.blobpool.pricebump"
                         "100"
                         (format nil "--log-file=~A" log-path-string)
                         (format nil "--genesis=~A"
                                 +devnet-cli-genesis-fixture+)
                         "--public-port=not-a-port"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "--public-port requires an integer value"
                       (get-output-stream-string errors)))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= "devnet.error" (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (string= (devnet-cli-current-process-id-string)
                          (cdr (assoc "processId" fields :test #'string=))))
             (is (search "--public-port requires an integer value"
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= log-path-string
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

