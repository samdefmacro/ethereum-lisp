(in-package #:ethereum-lisp.test)

(defun phase-a-smoke-gate-reference-client
    (reference-clients name)
  (find name reference-clients
        :key (lambda (client)
               (fixture-object-field client "name"))
        :test #'string=))

(defun phase-a-smoke-gate-reference-commit-p (commit)
  (and (stringp commit)
       (= 40 (length commit))
       (every (lambda (char)
                (or (and (char<= #\0 char) (char<= char #\9))
                    (and (char<= #\a char) (char<= char #\f))))
              commit)))

(defun phase-a-smoke-gate-assert-reference-client (reference-clients name)
  (let* ((client
           (phase-a-smoke-gate-reference-client reference-clients name))
         (status (and client
                      (fixture-object-field client "status")))
         (commit (and client
                      (fixture-object-field client "commit"))))
    (is client)
    (is (member status '("ok" "missing" "unavailable") :test #'string=))
    (if (string= "ok" status)
        (is (phase-a-smoke-gate-reference-commit-p commit))
        (is (null commit)))))

(defun phase-a-smoke-gate-assert-reference-client-path
    (reference-clients name expected-path)
  (let ((client
          (phase-a-smoke-gate-reference-client reference-clients name)))
    (is client)
    (is (string= expected-path
                 (fixture-object-field client "path")))))

(defun phase-a-smoke-gate-assert-execution-spec-tests-source (report)
  (let ((source (fixture-object-field report "executionSpecTests")))
    (is source)
    (is (string= "ethereum/execution-spec-tests"
                 (fixture-object-field source "repository")))
    (is (string= "v5.4.0"
                 (fixture-object-field source "release")))
    (is (string= "88e9fb8"
                 (fixture-object-field source "tagTarget")))
    (is (string= "fixtures_stable.tar.gz"
                 (fixture-object-field source "archive")))))

(defun phase-a-smoke-gate-section-count (section field)
  (or (fixture-object-field section field) 0))

(defun phase-a-smoke-gate-assert-counts (report)
  (let* ((state (fixture-object-field report "state"))
         (transaction (fixture-object-field report "transaction"))
         (blockchain (fixture-object-field report "blockchain"))
         (devnet (fixture-object-field report "devnet"))
         (devnet-side-reorg
           (fixture-object-field report "devnetSideReorg"))
         (devnet-engine-only
           (fixture-object-field report "devnetEngineOnly"))
         (fixture-case-count
           (+ (phase-a-smoke-gate-section-count state "count")
              (phase-a-smoke-gate-section-count transaction "count")
              (phase-a-smoke-gate-section-count blockchain "count")))
         (fixture-executed-count
           (+ (phase-a-smoke-gate-section-count state "executedCount")
              (phase-a-smoke-gate-section-count transaction "executedCount")
              (phase-a-smoke-gate-section-count blockchain "executedCount")))
         (devnet-case-count
           (if devnet
               (phase-a-smoke-gate-section-count devnet "caseCount")
               0))
         (devnet-side-reorg-case-count
           (if devnet-side-reorg
               (phase-a-smoke-gate-section-count
                devnet-side-reorg "sideReorgCaseCount")
               0))
         (devnet-engine-only-case-count
           (if devnet-engine-only
               (phase-a-smoke-gate-section-count
                devnet-engine-only "caseCount")
               0)))
    (is (= fixture-case-count
           (fixture-object-field report "fixtureCaseCount")))
    (is (= fixture-executed-count
           (fixture-object-field report "fixtureExecutedCount")))
    (is (= (+ fixture-case-count
              devnet-case-count
              devnet-side-reorg-case-count
              devnet-engine-only-case-count)
           (fixture-object-field report "totalCaseCount")))
    (is (= (+ fixture-executed-count
              devnet-case-count
              devnet-side-reorg-case-count
              devnet-engine-only-case-count)
           (fixture-object-field report "totalExecutedCount")))))

(defun phase-a-smoke-gate-assert-in-repo-fixture-counts (report)
  (let* ((state (fixture-object-field report "state"))
         (transaction (fixture-object-field report "transaction"))
         (blockchain (fixture-object-field report "blockchain"))
         (kind-counts (fixture-object-field blockchain "kindCounts")))
    (is (= 4 (fixture-object-field state "count")))
    (is (= 4 (fixture-object-field state "executedCount")))
    (is (= 25 (fixture-object-field transaction "count")))
    (is (= 25 (fixture-object-field transaction "executedCount")))
    (is (= 9 (fixture-object-field blockchain "count")))
    (is (= 9 (fixture-object-field blockchain "executedCount")))
    (is (= 1 (fixture-object-field blockchain "blockCount")))
    (is (= 8 (fixture-object-field kind-counts "engineNewPayloadV2")))
    (is (= 1 (fixture-object-field kind-counts "blockRlp")))
    (is (= 38 (fixture-object-field report "fixtureCaseCount")))
    (is (= 38 (fixture-object-field report "fixtureExecutedCount")))))

(defun devnet-smoke-gate-case-files (report field)
  (loop for case-report in (or (fixture-object-field report "cases") nil)
        for path = (fixture-object-field case-report field)
        when (stringp path)
          collect path))

(defun devnet-smoke-gate-case-database-files (report)
  (devnet-smoke-gate-case-files report "databaseFile"))

(defun devnet-cli-read-stream-string (stream)
  (with-output-to-string (output)
    (let ((buffer (make-string 8192)))
      (loop for count = (read-sequence buffer stream)
            until (zerop count)
            do (write-string buffer output :end count)))))

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

#+sbcl
(defun devnet-cli-open-loopback-socket (&key (port 0))
  (let ((socket
          (make-instance 'sb-bsd-sockets:inet-socket
                         :type :stream
                         :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
    (handler-case
        (progn
          (sb-bsd-sockets:socket-bind
           socket
           (sb-bsd-sockets:make-inet-address "127.0.0.1")
           port)
          (sb-bsd-sockets:socket-listen socket 1)
          (multiple-value-bind (address bound-port)
              (sb-bsd-sockets:socket-name socket)
            (declare (ignore address))
            (values socket bound-port)))
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))

#+sbcl
(defun devnet-cli-http-endpoint-host-port (endpoint)
  (let* ((prefix "http://")
         (start (if (and (<= (length prefix) (length endpoint))
                         (string= prefix endpoint :end2 (length prefix)))
                    (length prefix)
                    0))
         (colon (position #\: endpoint :start start :from-end t)))
    (unless colon
      (error "HTTP endpoint lacks a port: ~A" endpoint))
    (values (subseq endpoint start colon)
            (parse-integer endpoint :start (1+ colon)))))

#+sbcl
(defun devnet-cli-connect-stream (host port)
  (let ((socket
          (make-instance 'sb-bsd-sockets:inet-socket
                         :type :stream
                         :protocol :tcp)))
    (sb-bsd-sockets:socket-connect
     socket
     (sb-bsd-sockets:make-inet-address host)
     port)
    (sb-bsd-sockets:socket-make-stream
     socket
     :input t
     :output t
     :element-type 'character
     :external-format :utf-8
     :buffering :none)))

#+sbcl
(defun devnet-cli-unused-loopback-port ()
  (let ((socket
          (make-instance 'sb-bsd-sockets:inet-socket
                         :type :stream
                         :protocol :tcp)))
    (unwind-protect
         (progn
           (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
           (sb-bsd-sockets:socket-bind
            socket
            (sb-bsd-sockets:make-inet-address "127.0.0.1")
            0)
           (multiple-value-bind (address port)
               (sb-bsd-sockets:socket-name socket)
             (declare (ignore address))
             port))
      (ignore-errors
        (sb-bsd-sockets:socket-close socket)))))

#+sbcl
(defun devnet-cli-http-endpoint-connectable-p (endpoint)
  (multiple-value-bind (host port)
      (devnet-cli-http-endpoint-host-port endpoint)
    (let ((stream nil))
      (handler-case
          (progn
            (setf stream (devnet-cli-connect-stream host port))
            t)
        (sb-bsd-sockets:operation-not-permitted-error ()
          (error "Local socket connect is not permitted in this sandbox"))
        (error ()
          nil))
      (when stream
        (close stream)))))

#+sbcl
(defun devnet-cli-http-endpoint-request (endpoint request)
  (multiple-value-bind (host port)
      (devnet-cli-http-endpoint-host-port endpoint)
    (let ((stream (devnet-cli-connect-stream host port)))
      (unwind-protect
           (progn
             (write-string request stream)
             (finish-output stream)
             (devnet-cli-read-stream-string stream))
        (close stream)))))

(deftest engine-rpc-http-socket-listener-advertises-loopback-for-wildcard-host
  #-sbcl
  (skip-test "Devnet wildcard socket endpoint test requires SBCL sockets")
  #+sbcl
  (let ((listener nil))
    (handler-case
        (unwind-protect
             (progn
               (setf listener
                     (make-engine-rpc-http-socket-listener
                      (make-engine-rpc-http-service
                       :host "0.0.0.0"
                       :port 0)))
               (let ((endpoint
                       (engine-rpc-http-listener-endpoint listener)))
                 (is (search "127.0.0.1:" endpoint))
                 (is (not (search "0.0.0.0:" endpoint)))))
          (when listener
            (ignore-errors
              (engine-rpc-http-listener-close listener))))
      (sb-bsd-sockets:operation-not-permitted-error ()
        (skip-test "Local socket bind is not permitted in this sandbox")))))

(deftest devnet-node-start-closes-engine-socket-on-public-bind-error
  #-sbcl
  (skip-test "Devnet socket bind cleanup requires SBCL sockets")
  #+sbcl
  (let ((engine-probe nil)
        (public-socket nil)
        (rebound-socket nil)
        (engine-port nil)
        (public-port nil)
        (rebound-port nil))
    (handler-case
        (unwind-protect
             (progn
               (multiple-value-setq (engine-probe engine-port)
                 (devnet-cli-open-loopback-socket))
               (sb-bsd-sockets:socket-close engine-probe)
               (setf engine-probe nil)
               (multiple-value-setq (public-socket public-port)
                 (devnet-cli-open-loopback-socket))
               (let ((node (ethereum-lisp.cli:make-devnet-node
                            :genesis-path +devnet-cli-genesis-fixture+
                            :port engine-port
                            :public-port public-port)))
                 (signals error
                   (ethereum-lisp.cli:start-devnet-node
                    node
                    :max-connections 0)))
               (multiple-value-setq (rebound-socket rebound-port)
                 (devnet-cli-open-loopback-socket :port engine-port))
               (is (= engine-port rebound-port)))
          (when engine-probe
            (ignore-errors (sb-bsd-sockets:socket-close engine-probe)))
          (when public-socket
            (ignore-errors (sb-bsd-sockets:socket-close public-socket)))
          (when rebound-socket
            (ignore-errors (sb-bsd-sockets:socket-close rebound-socket))))
      (sb-bsd-sockets:operation-not-permitted-error ()
        (skip-test "Local socket bind is not permitted in this sandbox")))))

(deftest ethereum-lisp-script-public-bind-error-reports-error-only
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL sockets")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (public-socket nil)
        (public-port nil)
        (ready-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-bind-error-ready" "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-bind-error" "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-script-bind-error" "pid")))
    (handler-case
        (unwind-protect
             (progn
               (multiple-value-setq (public-socket public-port)
                 (devnet-cli-open-loopback-socket))
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
                          (write-to-string public-port)
                          "--ready-file"
                          (namestring ready-path)
                          "--log-file"
                          (namestring log-path)
                          "--pid-file"
                          (namestring pid-path)
                          "--json")
                    :directory #P"/private/tmp/"
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (when (search "Operation not permitted" stderr)
                   (skip-test
                    "Local socket bind is not permitted in this sandbox"))
                 (is (= 1 status))
                 (is (string= "" stdout))
                 (is (search "Usage: ethereum-lisp devnet" stderr))
                 (is (not (probe-file ready-path)))
                 (is (probe-file pid-path))
                 (let* ((log-records (devnet-cli-file-forms log-path))
                        (record (first log-records))
                        (fields (getf record :fields))
                        (log-names
                          (mapcar (lambda (entry) (getf entry :name))
                                  log-records))
                        (process-id
                          (parse-integer
                           (cdr (assoc "processId" fields :test #'string=))
                           :junk-allowed nil)))
                   (is (= 1 (length log-records)))
                   (is (eq :log (getf record :kind)))
                   (is (eq :error (getf record :value)))
                   (is (string= "devnet.error" (getf record :name)))
                   (is (not (member "devnet.ready"
                                    log-names
                                    :test #'string=)))
                   (is (not (member "devnet.shutdown"
                                    log-names
                                    :test #'string=)))
                   (is (string= "error"
                                (cdr (assoc "lifecyclePhase"
                                            fields
                                            :test #'string=))))
                   (is (string= "1"
                                (cdr (assoc "exitCode"
                                            fields
                                            :test #'string=))))
                   (is (plusp process-id))
                   (is (not (= (devnet-cli-current-process-id) process-id)))
                   (is (search "bind"
                               (string-downcase
                                (cdr (assoc "errorMessage"
                                            fields
                                            :test #'string=)))))
                   (is (string= (namestring log-path)
                                (cdr (assoc "logPath"
                                            fields
                                            :test #'string=))))
                   (is (= process-id
                          (devnet-cli-pid-file-process-id pid-path))))))
          (when public-socket
            (ignore-errors (sb-bsd-sockets:socket-close public-socket)))
          (when (probe-file ready-path)
            (delete-file ready-path))
          (when (probe-file log-path)
            (delete-file log-path))
          (when (probe-file pid-path)
            (delete-file pid-path)))
      (sb-bsd-sockets:operation-not-permitted-error ()
        (skip-test "Local socket bind is not permitted in this sandbox")))))

(deftest ethereum-lisp-script-ready-file-error-reports-error-only
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL sockets")
  #+sbcl
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-directory
          (devnet-cli-temp-directory
           "ethereum-lisp-script-ready-file-error"))
        (log-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-ready-file-error" "log"))
        (pid-path
          (devnet-cli-temp-path
           "ethereum-lisp-script-ready-file-error" "pid")))
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
                    (namestring ready-directory)
                    "--log-file"
                    (namestring log-path)
                    "--pid-file"
                    (namestring pid-path)
                    "--json"
                    "--max-connections"
                    "0")
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (when (search "Operation not permitted" stderr)
             (skip-test "Local socket bind is not permitted in this sandbox"))
           (is (= 1 status))
           (is (string= "" stdout))
           (is (search "Expected a file pathname" stderr))
           (is (search "Usage: ethereum-lisp devnet" stderr))
           (is (probe-file pid-path))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields))
                  (log-names
                    (mapcar (lambda (entry) (getf entry :name))
                            log-records))
                  (process-id
                    (parse-integer
                     (cdr (assoc "processId" fields :test #'string=))
                     :junk-allowed nil)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= "devnet.error" (getf record :name)))
             (is (not (member "devnet.ready" log-names :test #'string=)))
             (is (not (member "devnet.shutdown" log-names :test #'string=)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (plusp process-id))
             (is (not (= (devnet-cli-current-process-id) process-id)))
             (is (search "Expected a file pathname"
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= (namestring log-path)
                          (cdr (assoc "logPath" fields :test #'string=))))
             (is (= process-id
                    (devnet-cli-pid-file-process-id pid-path)))))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file ready-directory)
        (ignore-errors
          (uiop:delete-directory-tree ready-directory :validate t))))))

(defun devnet-smoke-gate-launch-json-process ()
  (uiop:launch-program
   (list "sbcl"
         "--script"
         "scripts/devnet-smoke-gate.lisp"
         "--"
         "--json")
   :output :stream
   :error-output :stream))

(defun devnet-smoke-gate-finish-json-process (process)
  (let ((status (uiop:wait-process process))
        (stdout
          (devnet-cli-read-stream-string (uiop:process-info-output process)))
        (stderr
          (devnet-cli-read-stream-string
           (uiop:process-info-error-output process))))
    (values stdout stderr status)))

(deftest devnet-smoke-gate-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/devnet-smoke-gate.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/devnet-smoke-gate.lisp"
                stdout))
    (is (search "--all-fixtures" stdout))
    (is (search "--engine-only-serve" stdout))
    (is (search "--ready-file PATH" stdout))
    (is (search "--log-file PATH" stdout))
    (is (search "--pid-file PATH" stdout))
    (is (search "--database PATH" stdout))
    (is (search "--prune-state-before NUMBER" stdout))
    (is (search "--override.terminaltotaldifficulty TTD" stdout))
    (is (search "--override.terminaltotaldifficultypassed" stdout))
    (is (search "--override.terminalblockhash HASH" stdout))
    (is (search "--override.terminalblocknumber NUMBER" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest devnet-smoke-gate-script-engine-only-serve-mode
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

(deftest devnet-smoke-gate-script-writes-ready-and-log-files
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let* ((artifact-root
           (devnet-cli-temp-directory "ethereum-lisp-devnet-smoke-artifacts"))
         (ready-path
           (merge-pathnames "ready/nested/devnet-ready.json" artifact-root))
         (log-path
           (merge-pathnames "logs/nested/devnet.log" artifact-root))
         (pid-path
           (merge-pathnames "pid/nested/devnet.pid" artifact-root))
         (database-path
           (merge-pathnames "database/nested/devnet-chain.sexp" artifact-root))
         (terminal-block-hash
           "0x4444444444444444444444444444444444444444444444444444444444444444")
         (reference-token
           (format nil "~A-~A" (sb-unix:unix-getpid) (gensym))))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "env"
                    (format nil "ETHEREUM_LISP_GETH_ROOT=/private/tmp/ethereum-lisp-devnet-geth-root-~A/"
                            reference-token)
                    (format nil "ETHEREUM_LISP_NETHERMIND_ROOT=/private/tmp/ethereum-lisp-devnet-nethermind-root-~A/"
                            reference-token)
                    (format nil "ETHEREUM_LISP_RETH_ROOT=/private/tmp/ethereum-lisp-devnet-reth-root-~A/"
                            reference-token)
                    "sbcl"
                    "--script"
                    "scripts/devnet-smoke-gate.lisp"
                    "--"
                    "--json=true"
                    "--all-fixtures=false"
                    (format nil "--ready-file=~A" (namestring ready-path))
                    (format nil "--log-file=~A" (namestring log-path))
                    (format nil "--pid-file=~A" (namestring pid-path))
                    (format nil "--database=~A" (namestring database-path))
                    "--prune-state-before=42"
                    "--override.terminaltotaldifficulty=0x3039"
                    "--override.terminaltotaldifficultypassed=true"
                    (format nil "--override.terminalblockhash=~A"
                            terminal-block-hash)
                    "--override.terminalblocknumber=66")
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (is (search "\"txpoolPendingFilterEmptyChanges\":[]" stdout))
           (when (= 0 status)
             (let* ((report (parse-json stdout))
                    (ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (database
                      (make-file-key-value-database database-path))
                    (log-records (devnet-cli-file-forms log-path))
                    (reference-clients
                      (fixture-object-field report "referenceClients"))
                    (log-names
                      (mapcar (lambda (record) (getf record :name))
                              log-records)))
               (is (string= "ok" (fixture-object-field report "status")))
               (is (string= "devnet-listener-boundary"
                            (fixture-object-field report "mode")))
               (phase-a-smoke-gate-assert-execution-spec-tests-source report)
               (is (= 3 (length reference-clients)))
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "geth")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "nethermind")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "reth")
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "geth"
                (format nil "/private/tmp/ethereum-lisp-devnet-geth-root-~A/"
                        reference-token))
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "nethermind"
                (format nil "/private/tmp/ethereum-lisp-devnet-nethermind-root-~A/"
                        reference-token))
               (phase-a-smoke-gate-assert-reference-client-path
                reference-clients
                "reth"
                (format nil "/private/tmp/ethereum-lisp-devnet-reth-root-~A/"
                        reference-token))
               (is (string= (namestring ready-path)
                            (fixture-object-field report "readyFile")))
               (is (string= (namestring log-path)
                            (fixture-object-field report "logFile")))
               (is (string= (namestring pid-path)
                            (fixture-object-field report "pidFile")))
               (is (string= "http://127.0.0.1:8551"
                            (fixture-object-field report "engineEndpoint")))
               (is (string= "http://127.0.0.1:8545"
                            (fixture-object-field report "rpcEndpoint")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineUnauthenticatedStatus")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineInvalidAuthStatus")))
               (is (= 401
                      (fixture-object-field
                       report
                       "engineDuplicateAuthStatus")))
               (is (= 404
                      (fixture-object-field
                       report
                       "engineRootWrongPathStatus")))
               (devnet-cli-assert-engine-capability-report report)
               (devnet-cli-assert-engine-client-version report)
               (devnet-cli-assert-engine-transition-configuration
                report
                :terminal-total-difficulty "0x3039"
                :terminal-block-hash terminal-block-hash
                :terminal-block-number "0x42")
               (devnet-cli-assert-engine-payload-bodies report)
               (devnet-cli-assert-engine-get-payload-v2 report)
               (is (= -32601
                      (fixture-object-field
                       report
                       "enginePublicNamespaceErrorCode")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicEngineNamespaceErrorCode")))
               (is (= -32700
                      (fixture-object-field
                       report
                       "publicMalformedJsonErrorCode")))
               (is (= 404
                      (fixture-object-field
                       report
                       "publicRootWrongPathStatus")))
               (is (equal '("eth" "net")
                          (fixture-object-field report
                                                "publicApiAllowlist")))
               (is (equal '("eth" "net")
                          (fixture-object-field
                           report
                           "publicApiAllowlistReportedModules")))
               (is (string= "eth,net"
                            (fixture-object-field
                             report
                             "publicApiAllowlistTelemetryModules")))
               (is (= 0
                      (fixture-object-field
                       report
                       "publicApiAllowlistEngineConnections")))
               (is (= 6
                      (fixture-object-field
                       report
                       "publicApiAllowlistPublicConnections")))
               (is (= 6
                      (fixture-object-field
                       report
                       "publicApiAllowlistTotalConnections")))
               (is (string= "0x539"
                            (fixture-object-field
                             report
                             "publicApiAllowlistChainId")))
               (is (string= "7331"
                            (fixture-object-field
                             report
                             "publicApiAllowlistNetworkVersion")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicApiBlockedWeb3ErrorCode")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicApiBlockedTxpoolErrorCode")))
               (is (= -32601
                      (fixture-object-field
                       report
                       "publicApiBlockedEngineErrorCode")))
               (devnet-cli-assert-public-cors-smoke-report report)
               (devnet-cli-assert-engine-cors-smoke-report report)
               (devnet-cli-assert-http-shaping-smoke-report report)
               (devnet-cli-assert-vhost-smoke-report report)
               (devnet-cli-assert-rpc-prefix-smoke-report report)
               (devnet-cli-assert-connection-contract report 1)
               (is (= (fixture-object-field ready-summary "processId")
                      (devnet-cli-pid-file-process-id pid-path)))
               (is (string= (namestring database-path)
                            (fixture-object-field report "databaseFile")))
               (is (= 42 (fixture-object-field
                          report "databasePruneStateBefore")))
               (is (eq nil
                       (fixture-object-field
                        report "databasePrunedStateAvailable")))
               (is (string= "eth_getBalance state is not available"
                            (fixture-object-field
                             report "databaseRpcPrunedStateError")))
               (let ((errors
                       (fixture-object-field
                        report "databaseRpcPrunedStateErrors")))
                 (is (= 8 (length errors)))
                 (dolist (message (devnet-cli-pruned-state-error-messages))
                   (is (member message errors :test #'string=))))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database
                    :state
                    (hash32-bytes
                     (hash32-from-hex
                      (fixture-object-field report "safeBlockHash")))
                    :missing)
                 (is (eq :missing value))
                 (is (not present-p)))
               (is (string= (fixture-object-field
                              report "txpoolImportBlockNumber")
                            (fixture-object-field report
                                                  "databaseHeadNumber")))
               (is (string= (fixture-object-field report "blockGasLimit")
                            (fixture-object-field report
                                                  "databaseHeadGasLimit")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (fixture-object-field report
                                                  "databaseSafeNumber")))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field report "databaseSafeHash")))
               (is (string= (fixture-object-field
                              report "finalizedBlockNumber")
                            (fixture-object-field
                             report "databaseFinalizedNumber")))
               (is (string= (fixture-object-field report "finalizedBlockHash")
                            (fixture-object-field
                             report "databaseFinalizedHash")))
               (is (string= (fixture-object-field
                              report "txpoolImportBlockNumber")
                            (fixture-object-field
                             report "databaseRpcBlockNumber")))
               (is (string= (fixture-object-field report "checkedBalance")
                            (fixture-object-field
                             report "databaseRpcBalance")))
               (is (string= (fixture-object-field report "checkedNonce")
                            (fixture-object-field report "databaseRpcNonce")))
               (is (string= (fixture-object-field report "checkedCode")
                            (fixture-object-field report "databaseRpcCode")))
               (is (string= (fixture-object-field report "checkedStorage")
                            (fixture-object-field
                             report "databaseRpcStorage")))
               (is (string= (fixture-object-field
                              report "checkedStorageAddress")
                            (fixture-object-field
                             report "databaseRpcProofAddress")))
               (is (string= (fixture-object-field
                              report "checkedProofCodeHash")
                            (fixture-object-field
                             report "databaseRpcProofCodeHash")))
               (is (string= (fixture-object-field report "checkedStorageKey")
                            (fixture-object-field
                             report "databaseRpcProofStorageKey")))
               (is (string= (fixture-object-field
                              report "checkedProofStorageValue")
                            (fixture-object-field
                             report "databaseRpcProofStorageValue")))
               (is (= 1 (fixture-object-field
                         report "databaseRpcProofStorageCount")))
               (is (<= 0 (fixture-object-field
                          report "databaseRpcProofAccountProofCount")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByHashNumber")
                            (fixture-object-field report "blockNumber")))
               (is (stringp
                    (fixture-object-field report "databaseRpcBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberNumber")
                            (fixture-object-field report "blockNumber")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberHash")
                            (fixture-object-field
                             report "databaseRpcBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockByNumberTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcTransactionBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcTransactionBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (= (fixture-object-field report "transactionCount")
                      (fixture-object-field
                       report "databaseRpcBlockReceiptsCount")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockReceiptTransactionHash")
                            (fixture-object-field
                             report "databaseRpcReceiptTransactionHash")))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcBlockReceiptBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockReceiptBlockNumber")
                            (fixture-object-field report "blockNumber")))
               (is (= (fixture-object-field report "transactionCount")
                      (fixture-object-field report
                                            "databaseRpcTransactionCount")))
               (devnet-cli-assert-restored-full-block-transactions report)
               (is (= (fixture-object-field report "checkedBalanceCount")
                      (fixture-object-field report
                                            "databaseRpcBalanceCount")))
               (is (= (fixture-object-field report "checkedLogCount")
                      (fixture-object-field report
                                            "databaseRpcLogCount")))
               (devnet-cli-assert-restored-log-filters report)
               (devnet-cli-assert-restored-block-filter report)
               (is (string= (quantity-to-hex
                              (fixture-object-field report "transactionCount"))
                            (fixture-object-field
                             report
                             "databaseRpcBlockTransactionCountByHash")))
               (is (string= (quantity-to-hex
                              (fixture-object-field report "transactionCount"))
                            (fixture-object-field
                             report
                             "databaseRpcBlockTransactionCountByNumber")))
               (is (string= (fixture-object-field report "databaseRpcBalance")
                            (fixture-object-field
                             report "databaseRpcCanonicalHashBalance")))
               (is (string= (fixture-object-field report "databaseRpcBalance")
                            (fixture-object-field
                             report
                             "databaseRpcCanonicalHashRequireBalance")))
               (is (string= (fixture-object-field
                              report
                              "databaseRpcRawTransactionByBlockHashAndIndex")
                            (fixture-object-field
                             report
                             "databaseRpcRawTransactionByBlockNumberAndIndex")))
               (is (string= (fixture-object-field
                              report
                              "databaseRpcRawTransactionByHash")
                            (fixture-object-field
                             report
                             "databaseRpcRawTransactionByBlockHashAndIndex")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcReceiptTransactionHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexBlockHash")))
               (is (string= (fixture-object-field
                              report "databaseRpcBlockHash")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexBlockHash")))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexBlockNumber")))
               (is (string= (fixture-object-field report "blockNumber")
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexBlockNumber")))
               (is (string= "0x0"
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockHashAndIndexIndex")))
               (is (string= "0x0"
                            (fixture-object-field
                             report
                             "databaseRpcTransactionByBlockNumberAndIndexIndex")))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field
                             report "databaseRpcSafeBlockHash")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (fixture-object-field
                             report "databaseRpcSafeBlockNumber")))
               (is (string= (fixture-object-field report "finalizedBlockHash")
                            (fixture-object-field
                             report "databaseRpcFinalizedBlockHash")))
               (is (string= (fixture-object-field
                              report "finalizedBlockNumber")
                            (fixture-object-field
                             report "databaseRpcFinalizedBlockNumber")))
               (is (= (fixture-object-field report "checkedSimulationCount")
                      (fixture-object-field report
                                            "databaseRpcSimulationCount")))
               (is (string= "0x"
                            (fixture-object-field
                             report "databaseRpcCallResult")))
               (is (<= 21000
                       (hex-to-quantity
                        (fixture-object-field
                         report "databaseRpcEstimateGas"))))
               (is (stringp
                    (fixture-object-field
                     report "databaseRpcAccessListGasUsed")))
               (is (string= (fixture-object-field report "checkedStorage")
                            (fixture-object-field
                             report "databaseRpcPostCallStorage")))
               (is (= (devnet-cli-restored-public-connections report)
                      (fixture-object-field
                       report "databaseRpcPublicConnections")))
               (is (string= (fixture-object-field report "preparedPayloadId")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadId")))
               (is (string= (fixture-object-field
                              report "preparedPayloadParentHash")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadParentHash")))
               (is (string= (fixture-object-field
                              report "preparedPayloadBlockNumber")
                            (fixture-object-field
                             report "databaseRpcPreparedPayloadBlockNumber")))
               (is (string= +payload-status-syncing+
                            (fixture-object-field report "remoteBlockStatus")))
               (is (string= (fixture-object-field report "remoteBlockHash")
                            (fixture-object-field
                             report "databaseRemoteBlockHash")))
               (is (string= +payload-status-syncing+
                            (fixture-object-field
                             report "databaseRpcRemoteBlockStatus")))
               (is (string= +payload-status-invalid+
                            (fixture-object-field report
                                                  "invalidTipsetStatus")))
               (is (string= "Timestamp is not greater than parent timestamp"
                            (fixture-object-field
                             report "invalidTipsetValidationError")))
               (is (string= (fixture-object-field
                              report "invalidTipsetBlockHash")
                            (fixture-object-field
                             report "databaseInvalidTipsetBlockHash")))
               (is (string= +payload-status-invalid+
                            (fixture-object-field
                             report "databaseRpcInvalidTipsetStatus")))
               (is (string= "links to previously rejected block"
                            (fixture-object-field
                             report
                             "databaseRpcInvalidTipsetValidationError")))
               (devnet-cli-assert-txpool-subpool-persistence report)
               (devnet-cli-assert-side-reorg-persistence report)
               (is (< 0 (length (kv-chain-record-entries database :block))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :prepared-payload))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :remote-block))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :invalid-tipset))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :txpool))))
               (is (< 0 (length (kv-chain-record-entries
                                 database :canonical-hash))))
               (is (string= "http://127.0.0.1:8551"
                            (fixture-object-field ready-summary
                                                  "engineEndpoint")))
               (is (string= "http://127.0.0.1:8545"
                            (fixture-object-field ready-summary
                                                  "rpcEndpoint")))
               (is (integerp (fixture-object-field ready-summary
                                                    "processId")))
               (is (< 0 (fixture-object-field ready-summary "processId")))
               (is (eq t (fixture-object-field ready-summary
                                                "authRequired")))
               (is (eq t (fixture-object-field ready-summary
                                                "stateAvailable")))
               (is (string= (fixture-object-field report "safeBlockNumber")
                            (quantity-to-hex
                             (fixture-object-field ready-summary
                                                   "headNumber"))))
               (is (string= (fixture-object-field report "safeBlockHash")
                            (fixture-object-field ready-summary
                                                  "headHash")))
               (is (string= (fixture-object-field report "safeBlockGasLimit")
                            (quantity-to-hex
                             (fixture-object-field ready-summary
                                                   "headGasLimit"))))
               (is (string= (namestring database-path)
                            (fixture-object-field ready-summary
                                                  "databasePath")))
               (is (member "devnet.ready" log-names :test #'string=))
               (is (member "devnet.shutdown" log-names :test #'string=))
               (dolist (log-record log-records)
                 (when (member (getf log-record :name)
                               '("devnet.ready" "devnet.shutdown")
                               :test #'string=)
                   (let* ((fields (getf log-record :fields))
                          (ready-p (string= "devnet.ready"
                                            (getf log-record :name)))
	                          (expected-head-number
	                            (fixture-object-field
	                             report
	                             (if ready-p
	                                 "safeBlockNumber"
	                                 "txpoolImportBlockNumber")))
	                          (expected-head-hash
	                            (fixture-object-field
	                             report
	                             (if ready-p
	                                 "safeBlockHash"
	                                 "txpoolImportBlockHash")))
                          (expected-head-gas-limit
                            (fixture-object-field
                             report
                             (if ready-p
                                 "safeBlockGasLimit"
                                 "blockGasLimit"))))
                     (is (string= expected-head-number
                                  (cdr (assoc "headNumber" fields
                                              :test #'string=))))
                     (is (string= expected-head-hash
                                  (cdr (assoc "headHash" fields
                                              :test #'string=))))
                     (is (string= expected-head-gas-limit
                                  (cdr (assoc "headGasLimit" fields
                                              :test #'string=))))
                     (is (string= (if ready-p "ready" "shutdown")
                                  (cdr (assoc "lifecyclePhase" fields
                                              :test #'string=))))
                     (is (string= (fixture-object-field report
                                                        "engineEndpoint")
                                  (cdr (assoc "engineEndpoint" fields
                                              :test #'string=))))
                     (is (string= (fixture-object-field report "rpcEndpoint")
                                  (cdr (assoc "rpcEndpoint" fields
                                              :test #'string=))))
                     (is (string= (write-to-string
                                    (fixture-object-field ready-summary
                                                          "processId"))
                                  (cdr (assoc "processId" fields
                                              :test #'string=))))
                     (is (string= "true"
                                  (cdr (assoc "stateAvailable" fields
                                              :test #'string=))))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-smoke-gate-script-rejects-malformed-boolean-assignment
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/devnet-smoke-gate.lisp"
             "--"
             "--json=maybe")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--json boolean value must be true or false" stderr))))

(deftest devnet-smoke-gate-script-runs-all-pinned-fixtures
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let ((ready-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite-ready"
                                "json"))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite"
                                "log"))
        (pid-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite"
                                "pid"))
        (database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-suite-chain"
                                "sexp"))
        (prune-boundary 42)
        (ready-files nil)
        (log-files nil)
        (pid-files nil)
        (database-files nil))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (list "sbcl"
                    "--script"
                    "scripts/devnet-smoke-gate.lisp"
                    "--"
                    "--json"
                    "--all-fixtures"
                    "--ready-file" (namestring ready-path)
                    "--log-file" (namestring log-path)
                    "--pid-file" (namestring pid-path)
                    "--database" (namestring database-path)
                    "--prune-state-before"
                    (write-to-string prune-boundary))
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 0 status))
           (is (string= "" stderr))
           (when (= 0 status)
             (let* ((report (parse-json stdout))
                    (cases (fixture-object-field report "cases"))
                    (reference-clients
                      (fixture-object-field report "referenceClients"))
                    (case-names
                      (mapcar (lambda (case)
                                (fixture-object-field case "fixtureCase"))
                              cases)))
               (setf database-files
                     (devnet-smoke-gate-case-database-files report)
                     ready-files
                     (devnet-smoke-gate-case-files report "readyFile")
                     log-files
                     (devnet-smoke-gate-case-files report "logFile")
                     pid-files
                     (devnet-smoke-gate-case-files report "pidFile"))
               (is (string= "ok" (fixture-object-field report "status")))
               (is (string= "devnet-listener-boundary-suite"
                            (fixture-object-field report "mode")))
               (phase-a-smoke-gate-assert-execution-spec-tests-source report)
               (is (= 3 (length reference-clients)))
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "geth")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "nethermind")
               (phase-a-smoke-gate-assert-reference-client
                reference-clients "reth")
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "caseCount")))
               (is (string= (namestring ready-path)
                            (fixture-object-field report "readyFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "readyCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length ready-files)))
               (is (string= (namestring log-path)
                            (fixture-object-field report "logFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "logCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length log-files)))
               (is (string= (namestring pid-path)
                            (fixture-object-field report "pidFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "pidCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length pid-files)))
               (is (string= (namestring database-path)
                            (fixture-object-field report "databaseFile")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (fixture-object-field report "databaseCaseCount")))
               (is (= (length +engine-newpayload-v2-smoke-case-names+)
                      (length database-files)))
               (devnet-cli-assert-pruned-state-suite
                report cases prune-boundary)
               (is (= (* 23 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "engineConnections")))
               (is (= (* 54 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "publicConnections")))
               (is (= (* 77 (length +engine-newpayload-v2-smoke-case-names+))
                      (fixture-object-field report "totalConnections")))
               (devnet-cli-assert-connection-contract
                report
                (length +engine-newpayload-v2-smoke-case-names+))
               (is (equal +engine-newpayload-v2-smoke-case-names+ case-names))
               (dolist (case cases)
                 (let ((expected-block-number
                         (devnet-cli-engine-fixture-payload-number
                          (fixture-object-field case "fixtureCase"))))
                   (is (string= "ok" (fixture-object-field case "status")))
                   (is (string= +payload-status-valid+
                                (fixture-object-field
                                 case "newPayloadStatus")))
                   (is (string= +payload-status-valid+
                                (fixture-object-field
                                 case "forkchoiceStatus")))
                   (is (= 23 (fixture-object-field case "engineConnections")))
                   (is (= 54 (fixture-object-field case "publicConnections")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineUnauthenticatedStatus")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineInvalidAuthStatus")))
                   (is (= 401
                          (fixture-object-field
                           case
                           "engineDuplicateAuthStatus")))
                   (is (= 404
                          (fixture-object-field
                           case
                           "engineRootWrongPathStatus")))
                   (devnet-cli-assert-engine-capability-report case)
                   (devnet-cli-assert-engine-client-version case)
                   (devnet-cli-assert-engine-transition-configuration case)
                   (devnet-cli-assert-public-readiness case)
                   (devnet-cli-assert-engine-payload-bodies case)
                   (devnet-cli-assert-engine-get-payload-v2 case)
                   (is (= -32601
                          (fixture-object-field
                           case
                           "enginePublicNamespaceErrorCode")))
                   (is (= -32601
                          (fixture-object-field
                           case
                           "publicEngineNamespaceErrorCode")))
                   (is (= -32700
                          (fixture-object-field
                           case
                           "publicMalformedJsonErrorCode")))
                   (is (= 404
                          (fixture-object-field
                           case
                           "publicRootWrongPathStatus")))
                   (devnet-cli-assert-public-cors-smoke-report case)
                   (devnet-cli-assert-engine-cors-smoke-report case)
                   (devnet-cli-assert-http-shaping-smoke-report case)
                   (devnet-cli-assert-vhost-smoke-report case)
                   (devnet-cli-assert-rpc-prefix-smoke-report case)
                   (is (string= expected-block-number
                                 (fixture-object-field case "blockNumber"))))
                 (is (string= (fixture-object-field
                                case "txpoolImportBlockNumber")
                              (fixture-object-field
                               case "databaseHeadNumber")))
                 (is (string= (fixture-object-field case "blockGasLimit")
                              (fixture-object-field
                               case "databaseHeadGasLimit")))
                 (is (string= (fixture-object-field case "safeBlockNumber")
                              (fixture-object-field
                               case "databaseSafeNumber")))
                 (is (stringp (fixture-object-field
                                case "safeBlockGasLimit")))
                 (is (string= (fixture-object-field case "safeBlockHash")
                              (fixture-object-field
                               case "databaseSafeHash")))
                 (is (string= (fixture-object-field
                                case "finalizedBlockNumber")
                              (fixture-object-field
                               case "databaseFinalizedNumber")))
                 (is (string= (fixture-object-field case "finalizedBlockHash")
                              (fixture-object-field
                               case "databaseFinalizedHash")))
                 (is (string= (fixture-object-field
                                case "txpoolImportBlockNumber")
                              (fixture-object-field
                               case "databaseRpcBlockNumber")))
                 (is (string= (fixture-object-field case "checkedBalance")
                              (fixture-object-field
                               case "databaseRpcBalance")))
                 (is (string= (fixture-object-field case "checkedNonce")
                              (fixture-object-field
                               case "databaseRpcNonce")))
                 (is (string= (fixture-object-field case "checkedCode")
                              (fixture-object-field
                               case "databaseRpcCode")))
                 (is (string= (fixture-object-field case "checkedStorage")
                              (fixture-object-field
                               case "databaseRpcStorage")))
                 (is (string= (fixture-object-field
                                case "checkedStorageAddress")
                              (fixture-object-field
                               case "databaseRpcProofAddress")))
                 (is (string= (fixture-object-field
                                case "checkedProofCodeHash")
                              (fixture-object-field
                               case "databaseRpcProofCodeHash")))
                 (is (string= (fixture-object-field case "checkedStorageKey")
                              (fixture-object-field
                               case "databaseRpcProofStorageKey")))
                 (is (string= (fixture-object-field
                                case "checkedProofStorageValue")
                              (fixture-object-field
                               case "databaseRpcProofStorageValue")))
                 (is (= 1 (fixture-object-field
                           case "databaseRpcProofStorageCount")))
                 (is (<= 0 (fixture-object-field
                            case "databaseRpcProofAccountProofCount")))
                 (is (string= (fixture-object-field
                                case "databaseRpcReceiptBlockNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcReceiptTransactionHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByHashNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (stringp
                      (fixture-object-field case "databaseRpcBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByNumberNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByNumberHash")
                              (fixture-object-field
                               case "databaseRpcBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockByNumberTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcTransactionBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcTransactionBlockNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (= (fixture-object-field case "transactionCount")
                        (fixture-object-field
                         case "databaseRpcBlockReceiptsCount")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockReceiptTransactionHash")
                              (fixture-object-field
                               case "databaseRpcReceiptTransactionHash")))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcBlockReceiptBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockReceiptBlockNumber")
                              (fixture-object-field case "blockNumber")))
                 (is (= (fixture-object-field case "transactionCount")
                        (fixture-object-field case
                                              "databaseRpcTransactionCount")))
                 (devnet-cli-assert-restored-full-block-transactions case)
                 (is (= (fixture-object-field case "checkedBalanceCount")
                        (fixture-object-field case "databaseRpcBalanceCount")))
                 (is (= (fixture-object-field case "checkedLogCount")
                        (fixture-object-field case "databaseRpcLogCount")))
                 (devnet-cli-assert-restored-log-filters case)
                 (devnet-cli-assert-restored-block-filter case)
                 (is (string= (quantity-to-hex
                                (fixture-object-field case "transactionCount"))
                              (fixture-object-field
                               case
                               "databaseRpcBlockTransactionCountByHash")))
                 (is (string= (quantity-to-hex
                                (fixture-object-field case "transactionCount"))
                              (fixture-object-field
                               case
                               "databaseRpcBlockTransactionCountByNumber")))
                 (is (string= (fixture-object-field case "databaseRpcBalance")
                              (fixture-object-field
                               case "databaseRpcCanonicalHashBalance")))
                 (is (string= (fixture-object-field case "databaseRpcBalance")
                              (fixture-object-field
                               case
                               "databaseRpcCanonicalHashRequireBalance")))
                 (is (string= (fixture-object-field
                                case
                                "databaseRpcRawTransactionByBlockHashAndIndex")
                              (fixture-object-field
                               case
                               "databaseRpcRawTransactionByBlockNumberAndIndex")))
                 (is (string= (fixture-object-field
                                case
                                "databaseRpcRawTransactionByHash")
                              (fixture-object-field
                               case
                               "databaseRpcRawTransactionByBlockHashAndIndex")))
                 (is (string= (fixture-object-field
                                case "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexBlockHash")))
                 (is (string= (fixture-object-field
                                case "databaseRpcBlockHash")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexBlockHash")))
                 (is (string= (fixture-object-field case "blockNumber")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexBlockNumber")))
                 (is (string= (fixture-object-field case "blockNumber")
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexBlockNumber")))
                 (is (string= "0x0"
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockHashAndIndexIndex")))
                 (is (string= "0x0"
                              (fixture-object-field
                               case
                               "databaseRpcTransactionByBlockNumberAndIndexIndex")))
                 (is (string= (fixture-object-field case "safeBlockHash")
                              (fixture-object-field
                               case "databaseRpcSafeBlockHash")))
                 (is (string= (fixture-object-field case "safeBlockNumber")
                              (fixture-object-field
                               case "databaseRpcSafeBlockNumber")))
                 (is (string= (fixture-object-field case "finalizedBlockHash")
                              (fixture-object-field
                               case "databaseRpcFinalizedBlockHash")))
                 (is (string= (fixture-object-field
                                case "finalizedBlockNumber")
                              (fixture-object-field
                               case "databaseRpcFinalizedBlockNumber")))
                 (is (= (fixture-object-field case "checkedSimulationCount")
                        (fixture-object-field
                         case "databaseRpcSimulationCount")))
                 (is (string= "0x"
                              (fixture-object-field
                               case "databaseRpcCallResult")))
                 (is (<= 21000
                         (hex-to-quantity
                          (fixture-object-field
                           case "databaseRpcEstimateGas"))))
                 (is (stringp
                      (fixture-object-field
                       case "databaseRpcAccessListGasUsed")))
                 (is (string= (fixture-object-field case "checkedStorage")
                              (fixture-object-field
                               case "databaseRpcPostCallStorage")))
                 (is (= (devnet-cli-restored-public-connections case)
                        (fixture-object-field
                         case "databaseRpcPublicConnections")))
                 (is (string= (fixture-object-field case "preparedPayloadId")
                              (fixture-object-field
                               case "databaseRpcPreparedPayloadId")))
                 (is (string= (fixture-object-field
                                case "preparedPayloadParentHash")
                              (fixture-object-field
                               case "databaseRpcPreparedPayloadParentHash")))
                 (is (string= (fixture-object-field
                                case "preparedPayloadBlockNumber")
                              (fixture-object-field
                               case "databaseRpcPreparedPayloadBlockNumber")))
                 (is (string= +payload-status-syncing+
                              (fixture-object-field case "remoteBlockStatus")))
                 (is (string= (fixture-object-field case "remoteBlockHash")
                              (fixture-object-field
                               case "databaseRemoteBlockHash")))
                 (is (string= +payload-status-syncing+
                              (fixture-object-field
                               case "databaseRpcRemoteBlockStatus")))
                 (is (string= +payload-status-invalid+
                              (fixture-object-field case
                                                    "invalidTipsetStatus")))
                 (is (string= "Timestamp is not greater than parent timestamp"
                              (fixture-object-field
                               case "invalidTipsetValidationError")))
                 (is (string= (fixture-object-field
                                case "invalidTipsetBlockHash")
                              (fixture-object-field
                               case "databaseInvalidTipsetBlockHash")))
                 (is (string= +payload-status-invalid+
                              (fixture-object-field
                               case "databaseRpcInvalidTipsetStatus")))
                 (is (string= "links to previously rejected block"
                              (fixture-object-field
                               case
                               "databaseRpcInvalidTipsetValidationError")))
                 (devnet-cli-assert-txpool-subpool-persistence case)
                 (devnet-cli-assert-side-reorg-persistence case)
                 (is (probe-file
                      (fixture-object-field case "readyFile")))
                 (is (probe-file
                      (fixture-object-field case "logFile")))
                 (is (probe-file
                      (fixture-object-field case "databaseFile")))))))
      (dolist (path (append ready-files log-files pid-files database-files))
        (when (probe-file path)
          (delete-file path)))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-smoke-gate-script-runs-concurrently
  #-sbcl
  (skip-test "Devnet smoke gate script requires SBCL")
  #+sbcl
  (let ((first-process (devnet-smoke-gate-launch-json-process))
        (second-process (devnet-smoke-gate-launch-json-process)))
    (multiple-value-bind (first-stdout first-stderr first-status)
        (devnet-smoke-gate-finish-json-process first-process)
      (multiple-value-bind (second-stdout second-stderr second-status)
          (devnet-smoke-gate-finish-json-process second-process)
        (is (= 0 first-status))
        (is (= 0 second-status))
        (is (string= "" first-stderr))
        (is (string= "" second-stderr))
        (when (and (= 0 first-status) (= 0 second-status))
          (dolist (report (list (parse-json first-stdout)
                                (parse-json second-stdout)))
            (is (string= "ok" (fixture-object-field report "status")))
            (is (string= "devnet-listener-boundary"
                         (fixture-object-field report "mode")))
            (phase-a-smoke-gate-assert-execution-spec-tests-source report)
            (is (= 3 (length (fixture-object-field report
                                                   "referenceClients"))))))))))

(deftest phase-a-fixture-report-includes-reference-client-pins
  #-sbcl
  (skip-test "Phase A fixture report script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--json"
             "--root"
             "tests/fixtures/execution-spec-tests-root/")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (reference-clients
               (fixture-object-field report "referenceClients")))
        (phase-a-smoke-gate-assert-execution-spec-tests-source report)
        (is (= 3 (length reference-clients)))
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "geth")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "nethermind")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "reth")))))

(deftest phase-a-report-scripts-honor-reference-client-root-env
  #-sbcl
  (skip-test "Phase A report scripts require SBCL")
  #+sbcl
  (let* ((token (format nil "~A-~A" (sb-unix:unix-getpid) (gensym)))
         (geth-root
           (format nil "/private/tmp/ethereum-lisp-geth-root-~A/" token))
         (nethermind-root
           (format nil "/private/tmp/ethereum-lisp-nethermind-root-~A/"
                   token))
         (reth-root
           (format nil "/private/tmp/ethereum-lisp-reth-root-~A/" token))
         (environment
           (list
            (format nil "ETHEREUM_LISP_GETH_ROOT=~A" geth-root)
            (format nil "ETHEREUM_LISP_NETHERMIND_ROOT=~A"
                    nethermind-root)
            (format nil "ETHEREUM_LISP_RETH_ROOT=~A" reth-root))))
    (labels ((run-report (script &rest extra-args)
               (uiop:run-program
                (append
                 (list "env")
                 environment
                 (list "sbcl" "--script" script "--")
                 extra-args)
                :output :string
                :error-output :string
                :ignore-error-status t))
             (assert-reference-roots (report)
               (let ((reference-clients
                       (fixture-object-field report "referenceClients")))
                 (is (= 3 (length reference-clients)))
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "geth" geth-root)
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "nethermind" nethermind-root)
                 (phase-a-smoke-gate-assert-reference-client-path
                  reference-clients "reth" reth-root)
                 (dolist (name '("geth" "nethermind" "reth"))
                   (phase-a-smoke-gate-assert-reference-client
                    reference-clients name)))))
      (multiple-value-bind (stdout stderr status)
          (run-report
           "scripts/phase-a-fixture-report.lisp"
           "--json"
           "--root"
           "tests/fixtures/execution-spec-tests-root/")
        (is (= 0 status))
        (is (string= "" stderr))
        (when (= 0 status)
          (assert-reference-roots (parse-json stdout))))
      (multiple-value-bind (stdout stderr status)
          (run-report
           "scripts/phase-a-smoke-gate.lisp"
           "--json"
           "--root"
           "tests/fixtures/execution-spec-tests-root/")
        (is (= 0 status))
        (is (string= "" stderr))
        (when (= 0 status)
          (assert-reference-roots (parse-json stdout)))))))

(deftest phase-a-fixture-report-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Phase A fixture report script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-fixture-report.lisp"
                stdout))
    (is (search "--root PATH" stdout))
    (is (search "--pinned-v5.4.0" stdout))
    (is (search "--json" stdout))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest phase-a-smoke-gate-help-prints-reference-root-env
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-smoke-gate.lisp"
                stdout))
    (is (search "--root PATH" stdout))
    (is (search "--pinned-v5.4.0" stdout))
    (is (search "--devnet" stdout))
    (is (search "--drift-map" stdout))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stdout))
    (is (search "ETHEREUM_LISP_GETH_ROOT" stdout))
    (is (search "ETHEREUM_LISP_NETHERMIND_ROOT" stdout))
    (is (search "ETHEREUM_LISP_RETH_ROOT" stdout))))

(deftest phase-a-smoke-gate-script-accepts-geth-style-option-values
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-phase-a-smoke-equals-root"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               "-u"
               "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--json=true"
               "--devnet=false"
               "--drift-map=false"
               "--pinned-v5.4.0=false"
               (format nil "--root=~A" root-string))
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Phase A smoke gate requires an EEST state_tests root under"
                  stderr))
      (is (not (search "Unsupported smoke gate option" stderr))))))

(deftest phase-a-smoke-gate-script-rejects-malformed-boolean-assignment
  #-sbcl
  (skip-test "Phase A smoke gate script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--devnet=maybe")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--devnet boolean value must be true or false" stderr))))

(deftest phase-a-fixture-report-pinned-mode-requires-root
  #-sbcl
  (skip-test "Phase A fixture report pinned mode requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "env"
             "-u"
             "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
             "sbcl"
             "--script"
             "scripts/phase-a-fixture-report.lisp"
             "--"
             "--pinned-v5.4.0"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Pinned Phase A fixture report requires an EEST fixture root"
                stderr))
    (is (search "--root" stderr))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stderr))
    (is (not (search "do not match pinned selectors" stderr)))))

(deftest phase-a-fixture-report-pinned-mode-rejects-missing-env-root
  #-sbcl
  (skip-test "Phase A fixture report pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-pinned-report-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               (format nil "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                       root-string)
               "sbcl"
               "--script"
               "scripts/phase-a-fixture-report.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Pinned Phase A fixture report root from" stderr))
      (is (not (search "do not match pinned selectors" stderr))))))

(deftest phase-a-selector-scripts-accept-root-option
  #-sbcl
  (skip-test "Phase A selector scripts require SBCL")
  #+sbcl
  (labels ((run-selector-script (script)
             (multiple-value-bind (stdout stderr status)
                 (uiop:run-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "--json"
                        "--root"
                        "tests/fixtures/execution-spec-tests-root/")
                  :output :string
                  :error-output :string
                  :ignore-error-status t)
               (is (= 0 status))
               (is (string= "" stderr))
               (when (= 0 status)
                 (let ((report (parse-json stdout)))
                   (is (search "tests/fixtures/execution-spec-tests-root/"
                               (fixture-object-field report "root")))
                   (is (plusp (fixture-object-field report "count"))))))))
    (run-selector-script "scripts/list-state-test-selectors.lisp")
    (run-selector-script "scripts/list-transaction-test-selectors.lisp")
    (run-selector-script "scripts/list-blockchain-replay-selectors.lisp")))

(deftest phase-a-fixture-sync-scripts-reject-missing-env-root
  #-sbcl
  (skip-test "Phase A fixture sync scripts require SBCL")
  #+sbcl
  (let* ((env-root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-fixture-sync-env-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (env-root-string (namestring env-root))
         (explicit-root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-fixture-sync-explicit-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (explicit-root-string (namestring explicit-root)))
    (labels ((run-script-with-missing-env-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          (format nil
                                  "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                                  env-root-string)
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json")
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search env-root-string stderr))
                 (is (search "Configured EEST fixture root from" stderr))
                 (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                             stderr))))
             (run-script-with-missing-explicit-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          "-u"
                          "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json"
                          "--root"
                          explicit-root-string)
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search explicit-root-string stderr))
                 (is (search "Configured EEST fixture root from" stderr))
                 (is (search "--root" stderr)))))
      (dolist (script
               '("scripts/phase-a-fixture-report.lisp"
                 "scripts/classify-state-test-selectors.lisp"
                 "scripts/classify-transaction-test-selectors.lisp"
                 "scripts/list-state-test-selectors.lisp"
                 "scripts/list-transaction-test-selectors.lisp"
                 "scripts/list-blockchain-replay-selectors.lisp"))
        (run-script-with-missing-env-root script)
        (run-script-with-missing-explicit-root script)))))

(deftest phase-a-fixture-sync-scripts-reject-empty-suite-root
  #-sbcl
  (skip-test "Phase A fixture sync scripts require SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-empty-fixture-sync-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (dolist (subdir '("state_tests/"
                      "transaction_tests/"
                      "blockchain_tests_engine/"))
      (ensure-directories-exist (merge-pathnames subdir root)))
    (labels ((run-script-with-empty-root (script)
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    (list "env"
                          "-u"
                          "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
                          "sbcl"
                          "--script"
                          script
                          "--"
                          "--json"
                          "--root"
                          root-string)
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (not (= 0 status)))
                 (is (string= "" stdout))
                 (is (search root-string stderr))
                 (is (search "contains no JSON files" stderr))
                 (is (search "Configured EEST" stderr)))))
      (dolist (script
               '("scripts/phase-a-fixture-report.lisp"
                 "scripts/phase-a-smoke-gate.lisp"
                 "scripts/classify-state-test-selectors.lisp"
                 "scripts/classify-transaction-test-selectors.lisp"
                 "scripts/list-state-test-selectors.lisp"
                 "scripts/list-transaction-test-selectors.lisp"
                 "scripts/list-blockchain-replay-selectors.lisp"))
        (run-script-with-empty-root script)))))

(deftest phase-a-smoke-gate-script-can-include-devnet-suite
  #-sbcl
  (skip-test "Phase A smoke gate devnet mode requires SBCL")
  #+sbcl
  (let ((prune-boundary 42))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--json"
               "--devnet")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (reference-clients
                 (fixture-object-field report "referenceClients"))
               (devnet (fixture-object-field report "devnet"))
               (devnet-side-reorg
                 (fixture-object-field report "devnetSideReorg"))
               (devnet-engine-only
                 (fixture-object-field report "devnetEngineOnly"))
               (cases (fixture-object-field devnet "cases")))
        (is (string= "ok" (fixture-object-field report "status")))
        (is (string= "in-repo" (fixture-object-field report "mode")))
        (phase-a-smoke-gate-assert-execution-spec-tests-source report)
        (phase-a-smoke-gate-assert-counts report)
        (phase-a-smoke-gate-assert-in-repo-fixture-counts report)
        (is (= 3 (length reference-clients)))
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "geth")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "nethermind")
        (phase-a-smoke-gate-assert-reference-client
         reference-clients "reth")
        (is (string= "ok" (fixture-object-field devnet "status")))
        (is (string= "devnet-listener-boundary-suite"
                     (fixture-object-field devnet "mode")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "caseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "readyCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-files devnet "readyFile"))))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "logCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-files devnet "logFile"))))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "pidCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-files devnet "pidFile"))))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (fixture-object-field devnet "databaseCaseCount")))
        (is (= (length +engine-newpayload-v2-smoke-case-names+)
               (length (devnet-smoke-gate-case-database-files devnet))))
        (devnet-cli-assert-pruned-state-suite
         devnet cases prune-boundary)
        (is (= 0 (fixture-object-field devnet "sideReorgCaseCount")))
        (is (string= "ok"
                     (fixture-object-field
                      devnet-engine-only "status")))
        (is (string= "devnet-engine-only-serve"
                     (fixture-object-field
                      devnet-engine-only "mode")))
        (is (= 1 (fixture-object-field
                  devnet-engine-only "caseCount")))
        (is (not (fixture-object-field
                  devnet-engine-only "publicRpcEnabled")))
        (is (not (fixture-object-field
                  devnet-engine-only "rpcEndpoint")))
        (is (string= "/engine"
                     (fixture-object-field
                      devnet-engine-only "engineRpcPrefix")))
        (is (= 200 (fixture-object-field
                    devnet-engine-only "engineRpcPrefixStatus")))
        (is (= 404 (fixture-object-field
                    devnet-engine-only
                    "engineRpcPrefixBlockedStatus")))
        (devnet-cli-assert-engine-only-http-shaping-report
         devnet-engine-only)
        (devnet-cli-assert-engine-capability-report
         devnet-engine-only)
        (devnet-cli-assert-engine-client-version
         devnet-engine-only)
        (devnet-cli-assert-engine-transition-configuration
         devnet-engine-only)
        (devnet-cli-assert-engine-only-payload-report
         devnet-engine-only)
        (devnet-cli-assert-engine-only-hidden-payload-bodies-v2-report
         devnet-engine-only)
        (devnet-cli-assert-engine-only-database-report
         devnet-engine-only)
        (is (search "http://127.0.0.1:"
                    (fixture-object-field
                     devnet-engine-only "configuredPublicEndpoint")))
        (is (not (fixture-object-field
                  devnet-engine-only "publicEndpointConnectable")))
        (devnet-cli-assert-engine-only-connection-contract
         devnet-engine-only)
        (let ((side-reorg-cases
                (fixture-object-field devnet-side-reorg "cases")))
          (is (string= "ok"
                       (fixture-object-field devnet-side-reorg "status")))
          (is (string= "devnet-side-reorg-suite"
                       (fixture-object-field devnet-side-reorg "mode")))
          (is (equal +devnet-side-reorg-smoke-case-names+
                     (fixture-object-field
                      devnet-side-reorg "fixtureCases")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field devnet-side-reorg "caseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "sideReorgCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "readyCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "logCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "pidCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "databaseCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (length side-reorg-cases)))
          (dolist (case side-reorg-cases)
            (devnet-cli-assert-side-reorg-persistence case))
          (let ((log-case
                  (find "shanghai-log-contract-call-with-withdrawal"
                        side-reorg-cases
                        :key (lambda (case)
                               (fixture-object-field case "fixtureCase"))
                        :test #'string=)))
            (is log-case)
            (when log-case
              (is (= 1 (fixture-object-field log-case "checkedLogCount")))
              (is (= 1 (fixture-object-field
                        log-case "databaseRpcLogCount")))
              (devnet-cli-assert-restored-log-filters log-case)
              (devnet-cli-assert-restored-block-filter log-case)))
          (let ((two-transfer-case
                  (find "shanghai-two-legacy-transfers-with-withdrawal"
                        side-reorg-cases
                        :key (lambda (case)
                               (fixture-object-field case "fixtureCase"))
                        :test #'string=)))
            (is two-transfer-case)
            (when two-transfer-case
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideReinsertedTransactionCount")))
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideRestoredReinsertedTransactionCount")))
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideHiddenReceiptCount")))
              (is (= 2 (fixture-object-field
                        two-transfer-case
                        "databaseRpcSideRestoredHiddenReceiptCount")))
              (is (= 2 (length
                        (fixture-object-field
                         two-transfer-case
                         "databaseRpcSideReinsertedTransactionHashes")))))))
        (is (= (* 23 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "engineConnections")))
        (is (= (* 54 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "publicConnections")))
        (is (= (* 77 (length +engine-newpayload-v2-smoke-case-names+))
               (fixture-object-field devnet "totalConnections")))
        (dolist (case cases)
          (devnet-cli-assert-public-readiness case)
          (is (string= (fixture-object-field case "txpoolImportBlockNumber")
                       (fixture-object-field
                        case "databaseRpcBlockNumber")))
          (is (string= (fixture-object-field case "safeBlockNumber")
                       (fixture-object-field
                        case "databaseSafeNumber")))
          (is (string= (fixture-object-field case "safeBlockHash")
                       (fixture-object-field case "databaseSafeHash")))
          (is (string= (fixture-object-field case "finalizedBlockNumber")
                       (fixture-object-field
                        case "databaseFinalizedNumber")))
          (is (string= (fixture-object-field case "finalizedBlockHash")
                       (fixture-object-field
                        case "databaseFinalizedHash")))
          (is (string= (fixture-object-field case "checkedBalance")
                       (fixture-object-field
                        case "databaseRpcBalance")))
          (is (string= (fixture-object-field case "checkedNonce")
                       (fixture-object-field
                        case "databaseRpcNonce")))
          (is (string= (fixture-object-field case "checkedCode")
                       (fixture-object-field
                        case "databaseRpcCode")))
          (is (string= (fixture-object-field case "checkedStorage")
                       (fixture-object-field
                        case "databaseRpcStorage")))
          (is (string= (fixture-object-field case "checkedStorageAddress")
                       (fixture-object-field
                        case "databaseRpcProofAddress")))
          (is (string= (fixture-object-field case "checkedProofCodeHash")
                       (fixture-object-field
                        case "databaseRpcProofCodeHash")))
          (is (string= (fixture-object-field case "checkedStorageKey")
                       (fixture-object-field
                        case "databaseRpcProofStorageKey")))
          (is (string= (fixture-object-field case "checkedProofStorageValue")
                       (fixture-object-field
                        case "databaseRpcProofStorageValue")))
          (is (= 1 (fixture-object-field
                    case "databaseRpcProofStorageCount")))
          (is (<= 0 (fixture-object-field
                     case "databaseRpcProofAccountProofCount")))
          (is (string= (fixture-object-field
                        case "databaseRpcReceiptBlockNumber")
                       (fixture-object-field case "blockNumber")))
          (is (stringp
               (fixture-object-field
                case "databaseRpcReceiptTransactionHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockByHashNumber")
                       (fixture-object-field case "blockNumber")))
          (is (stringp
               (fixture-object-field case "databaseRpcBlockHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockTransactionHash")
                       (fixture-object-field
                        case "databaseRpcReceiptTransactionHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockByNumberNumber")
                       (fixture-object-field case "blockNumber")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockByNumberHash")
                       (fixture-object-field
                        case "databaseRpcBlockHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockByNumberTransactionHash")
                       (fixture-object-field
                        case "databaseRpcReceiptTransactionHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcTransactionHash")
                       (fixture-object-field
                        case "databaseRpcReceiptTransactionHash")))
          (is (stringp
               (fixture-object-field
                case "databaseRpcTransactionBlockHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcTransactionBlockNumber")
                       (fixture-object-field case "blockNumber")))
          (is (= (fixture-object-field case "transactionCount")
                 (fixture-object-field
                  case "databaseRpcBlockReceiptsCount")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockReceiptTransactionHash")
                       (fixture-object-field
                        case "databaseRpcReceiptTransactionHash")))
          (is (stringp
               (fixture-object-field
                case "databaseRpcBlockReceiptBlockHash")))
          (is (string= (fixture-object-field
                        case "databaseRpcBlockReceiptBlockNumber")
                       (fixture-object-field case "blockNumber")))
          (is (= (fixture-object-field case "transactionCount")
                 (fixture-object-field case
                                       "databaseRpcTransactionCount")))
          (devnet-cli-assert-restored-full-block-transactions case)
          (is (= (fixture-object-field case "checkedBalanceCount")
                 (fixture-object-field case "databaseRpcBalanceCount")))
          (is (= (fixture-object-field case "checkedLogCount")
                 (fixture-object-field case "databaseRpcLogCount")))
          (devnet-cli-assert-restored-log-filters case)
          (devnet-cli-assert-restored-block-filter case)
          (is (string= (quantity-to-hex
                         (fixture-object-field case "transactionCount"))
                       (fixture-object-field
                        case
                        "databaseRpcBlockTransactionCountByHash")))
          (is (string= (quantity-to-hex
                         (fixture-object-field case "transactionCount"))
                       (fixture-object-field
                        case
                        "databaseRpcBlockTransactionCountByNumber")))
          (is (string= (fixture-object-field case "databaseRpcBalance")
                       (fixture-object-field
                        case "databaseRpcCanonicalHashBalance")))
          (is (string= (fixture-object-field case "databaseRpcBalance")
                       (fixture-object-field
                        case
                        "databaseRpcCanonicalHashRequireBalance")))
          (is (string= (fixture-object-field
                         case
                         "databaseRpcRawTransactionByBlockHashAndIndex")
                       (fixture-object-field
                        case
                        "databaseRpcRawTransactionByBlockNumberAndIndex")))
          (is (string= (fixture-object-field
                         case
                         "databaseRpcRawTransactionByHash")
                       (fixture-object-field
                        case
                        "databaseRpcRawTransactionByBlockHashAndIndex")))
          (is (string= (fixture-object-field
                         case "databaseRpcReceiptTransactionHash")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockHashAndIndexHash")))
          (is (string= (fixture-object-field
                         case "databaseRpcReceiptTransactionHash")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockNumberAndIndexHash")))
          (is (string= (fixture-object-field
                         case "databaseRpcBlockHash")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockHashAndIndexBlockHash")))
          (is (string= (fixture-object-field
                         case "databaseRpcBlockHash")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockNumberAndIndexBlockHash")))
          (is (string= (fixture-object-field case "blockNumber")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockHashAndIndexBlockNumber")))
          (is (string= (fixture-object-field case "blockNumber")
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockNumberAndIndexBlockNumber")))
          (is (string= "0x0"
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockHashAndIndexIndex")))
          (is (string= "0x0"
                       (fixture-object-field
                        case
                        "databaseRpcTransactionByBlockNumberAndIndexIndex")))
          (is (string= (fixture-object-field case "safeBlockHash")
                       (fixture-object-field
                        case "databaseRpcSafeBlockHash")))
          (is (string= (fixture-object-field case "safeBlockNumber")
                       (fixture-object-field
                        case "databaseRpcSafeBlockNumber")))
          (is (string= (fixture-object-field case "finalizedBlockHash")
                       (fixture-object-field
                        case "databaseRpcFinalizedBlockHash")))
          (is (string= (fixture-object-field case "finalizedBlockNumber")
                       (fixture-object-field
                        case "databaseRpcFinalizedBlockNumber")))
          (is (= (fixture-object-field case "checkedSimulationCount")
                 (fixture-object-field case "databaseRpcSimulationCount")))
          (is (string= "0x"
                       (fixture-object-field
                        case "databaseRpcCallResult")))
          (is (<= 21000
                  (hex-to-quantity
                   (fixture-object-field
                    case "databaseRpcEstimateGas"))))
          (is (stringp
               (fixture-object-field
                case "databaseRpcAccessListGasUsed")))
          (is (string= (fixture-object-field case "checkedStorage")
                       (fixture-object-field
                        case "databaseRpcPostCallStorage")))
          (is (= (devnet-cli-restored-public-connections case)
                 (fixture-object-field
                  case "databaseRpcPublicConnections")))
          (is (string= (fixture-object-field case "preparedPayloadId")
                       (fixture-object-field
                        case "databaseRpcPreparedPayloadId")))
          (is (string= (fixture-object-field
                         case "preparedPayloadParentHash")
                       (fixture-object-field
                        case "databaseRpcPreparedPayloadParentHash")))
          (is (string= (fixture-object-field
                         case "preparedPayloadBlockNumber")
                       (fixture-object-field
                        case "databaseRpcPreparedPayloadBlockNumber")))
          (devnet-cli-assert-engine-get-payload-v2 case)
          (is (string= +payload-status-syncing+
                       (fixture-object-field case "remoteBlockStatus")))
          (is (string= (fixture-object-field case "remoteBlockHash")
                       (fixture-object-field
                        case "databaseRemoteBlockHash")))
          (is (string= +payload-status-syncing+
                       (fixture-object-field
                        case "databaseRpcRemoteBlockStatus")))
          (is (string= +payload-status-invalid+
                       (fixture-object-field case "invalidTipsetStatus")))
          (is (string= "Timestamp is not greater than parent timestamp"
                       (fixture-object-field
                        case "invalidTipsetValidationError")))
          (is (string= (fixture-object-field case "invalidTipsetBlockHash")
                       (fixture-object-field
                        case "databaseInvalidTipsetBlockHash")))
          (is (string= +payload-status-invalid+
                       (fixture-object-field
                        case "databaseRpcInvalidTipsetStatus")))
          (is (string= "links to previously rejected block"
                       (fixture-object-field
                        case
                        "databaseRpcInvalidTipsetValidationError")))
          (devnet-cli-assert-txpool-subpool-persistence case)
          (devnet-cli-assert-side-reorg-persistence case)))))))

(deftest phase-a-smoke-gate-devnet-mode-is-cwd-independent
  #-sbcl
  (skip-test "Phase A smoke gate cwd-independent devnet mode requires SBCL")
  #+sbcl
  (let ((script (namestring (truename "scripts/phase-a-smoke-gate.lisp")))
        (root (namestring
               (truename "tests/fixtures/execution-spec-tests-root/"))))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "sbcl"
               "--script"
               script
               "--"
               "--json"
               "--devnet"
               "--root"
               root)
         :directory #P"/private/tmp/"
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (devnet (fixture-object-field report "devnet"))
               (devnet-side-reorg
                 (fixture-object-field report "devnetSideReorg"))
               (devnet-engine-only
                 (fixture-object-field report "devnetEngineOnly")))
          (is (string= "ok" (fixture-object-field report "status")))
          (phase-a-smoke-gate-assert-counts report)
          (is (string= "ok" (fixture-object-field devnet "status")))
          (is (string= "devnet-listener-boundary-suite"
                       (fixture-object-field devnet "mode")))
          (is (= 0 (fixture-object-field
                    devnet "sideReorgCaseCount")))
          (is (string= "ok"
                       (fixture-object-field
                        devnet-side-reorg "status")))
          (is (string= "devnet-side-reorg-suite"
                       (fixture-object-field
                        devnet-side-reorg "mode")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "sideReorgCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "readyCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "logCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "pidCaseCount")))
          (is (= (length +devnet-side-reorg-smoke-case-names+)
                 (fixture-object-field
                  devnet-side-reorg "databaseCaseCount")))
          (is (string= "ok"
                       (fixture-object-field
                        devnet-engine-only "status")))
          (is (string= "devnet-engine-only-serve"
                       (fixture-object-field
                        devnet-engine-only "mode")))
          (is (= 1 (fixture-object-field
                    devnet-engine-only "caseCount")))
          (is (string= "/engine"
                       (fixture-object-field
                        devnet-engine-only "engineRpcPrefix")))
          (is (= 200 (fixture-object-field
                      devnet-engine-only "engineRpcPrefixStatus")))
          (is (= 404 (fixture-object-field
                      devnet-engine-only
                      "engineRpcPrefixBlockedStatus")))
          (devnet-cli-assert-engine-only-http-shaping-report
           devnet-engine-only)
          (devnet-cli-assert-engine-capability-report
           devnet-engine-only)
          (devnet-cli-assert-engine-client-version
           devnet-engine-only)
          (devnet-cli-assert-engine-transition-configuration
            devnet-engine-only)
          (devnet-cli-assert-engine-only-payload-report
           devnet-engine-only)
          (devnet-cli-assert-engine-only-hidden-payload-bodies-v2-report
           devnet-engine-only)
          (devnet-cli-assert-engine-only-database-report
           devnet-engine-only)
          (is (search "http://127.0.0.1:"
                      (fixture-object-field
                       devnet-engine-only "configuredPublicEndpoint")))
          (is (not (fixture-object-field
                    devnet-engine-only "publicEndpointConnectable")))
          (devnet-cli-assert-engine-only-connection-contract
           devnet-engine-only))))))

(deftest phase-a-smoke-gate-text-output-includes-aggregate-counts
  #-sbcl
  (skip-test "Phase A smoke gate text output test requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "fixtureCaseCount=" stdout))
    (is (search "fixtureExecutedCount=" stdout))
    (is (search "totalCaseCount=" stdout))
    (is (search "totalExecutedCount=" stdout))
    (is (search "blockchainCount=9" stdout))
    (is (search "blockchainExecuted=9" stdout))
    (is (search "(\"engineNewPayloadV2\" . 8)" stdout))
    (is (search "(\"blockRlp\" . 1)" stdout))
    (is (search "fixtureCaseCount=38" stdout))
    (is (search "fixtureExecutedCount=38" stdout))))

(deftest phase-a-smoke-gate-drift-map-fails-on-materializable-gaps
  #-sbcl
  (skip-test "Phase A smoke gate drift map failure requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--drift-map"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Phase A drift map found materializable selector gaps"
                stderr))
    (is (search "implementationBugCandidates=1" stderr))))

(deftest phase-a-smoke-gate-pinned-mode-defaults-to-eest-root-env
  #-sbcl
  (skip-test "Phase A smoke gate pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (devnet-cli-temp-directory
            "ethereum-lisp-pinned-smoke-root"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               (format nil "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                       root-string)
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Phase A smoke gate requires an EEST blockchain root"
                  stderr)))))

(deftest phase-a-smoke-gate-pinned-mode-requires-root
  #-sbcl
  (skip-test "Phase A smoke gate pinned mode requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "env"
             "-u"
             "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT"
             "sbcl"
             "--script"
             "scripts/phase-a-smoke-gate.lisp"
             "--"
             "--pinned-v5.4.0"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "Pinned Phase A smoke gate requires an EEST fixture root"
                stderr))
    (is (search "--root" stderr))
    (is (search "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT" stderr))
    (is (not (search "do not match pinned selectors" stderr)))))

(deftest phase-a-smoke-gate-pinned-mode-rejects-missing-env-root
  #-sbcl
  (skip-test "Phase A smoke gate pinned mode requires SBCL")
  #+sbcl
  (let* ((root
           (merge-pathnames
            (format nil "ethereum-lisp-missing-pinned-smoke-root-~A/"
                    (devnet-cli-temp-token))
            #P"/private/tmp/"))
         (root-string (namestring root)))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "env"
               (format nil "ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT=~A"
                       root-string)
               "sbcl"
               "--script"
               "scripts/phase-a-smoke-gate.lisp"
               "--"
               "--pinned-v5.4.0"
               "--json")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (not (= 0 status)))
      (is (string= "" stdout))
      (is (search root-string stderr))
      (is (search "Pinned Phase A smoke gate root from" stderr))
      (is (not (search "do not match pinned selectors" stderr))))))

(deftest blockchain-replay-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-blockchain-replay-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-blockchain-replay-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "--failures-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest blockchain-replay-classifier-script-json-summarizes-families
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-blockchain-replay-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "shanghai/phase-a"
             "--limit"
             "2"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-blockchain-replay-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (family families)
          (is (= 0 (fixture-object-field
                    family
                    "knownImplementationDriftCount"))))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest blockchain-replay-classifier-script-json-filters-passing-results
  #-sbcl
  (skip-test "Blockchain replay classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-blockchain-replay-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "shanghai/phase-a"
             "--limit"
             "2"
             "--failures-only"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (eq t (fixture-object-field report "failuresOnly")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (length results)))
        (is (plusp (length families)))))))

(deftest transaction-test-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Transaction test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-transaction-test-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-transaction-test-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "--failures-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest transaction-test-classifier-script-json-summarizes-families
  #-sbcl
  (skip-test "Transaction test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-transaction-test-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "phase-a-sample.json"
             "--limit"
             "2"
             "--include-pinned"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-transaction-test-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (family families)
          (is (= 0 (fixture-object-field
                    family
                    "knownImplementationDriftCount"))))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest transaction-test-classifier-script-json-classifies-prague-out-of-scope
  #-sbcl
  (skip-test "Transaction test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-transaction-test-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "prague/eip7702_set_code_tx/test_empty_authorization_list.json"
             "--limit"
             "1"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families"))
             (result (first results)))
        (is (string= "unpinned-transaction-test-classification"
                     (fixture-object-field report "mode")))
        (is (= 1 (fixture-object-field report "classifiedCount")))
        (is (= 0 (fixture-object-field report "passingCount")))
        (is (= 1 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 1 (fixture-object-field
                  report
                  "outOfScopeForkFeatureCount")))
        (is (= 1 (length families)))
        (is (string= "out-of-scope-fork-feature"
                     (fixture-object-field result "classification")))
        (is (search "Prague/EIP-7702"
                    (fixture-object-field result "error")))))))

(deftest state-test-classifier-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "State test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-state-test-selectors.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/classify-state-test-selectors.lisp"
                stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--limit NUMBER" stdout))
    (is (search "--include-pinned" stdout))
    (is (search "--failures-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "implementation-bug-candidate" stdout))))

(deftest state-test-classifier-script-json-summarizes-families
  #-sbcl
  (skip-test "State test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-state-test-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "london/phase-a"
             "--limit"
             "2"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (string= "unpinned-state-test-classification"
                     (fixture-object-field report "mode")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (fixture-object-field
                  report
                  "knownImplementationDriftCount")))
        (is (= 0 (fixture-object-field
                  report
                  "implementationBugCandidateCount")))
        (is (plusp (length families)))
        (dolist (family families)
          (is (= 0 (fixture-object-field
                    family
                    "knownImplementationDriftCount"))))
        (dolist (result results)
          (is (string= "passing"
                       (fixture-object-field result "classification")))
          (is (fixture-object-field result "family")))))))

(deftest state-test-classifier-script-json-filters-passing-results
  #-sbcl
  (skip-test "State test classifier script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/classify-state-test-selectors.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--prefix"
             "london/phase-a"
             "--limit"
             "2"
             "--failures-only"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (results (fixture-object-field report "results"))
             (families (fixture-object-field report "families")))
        (is (eq t (fixture-object-field report "failuresOnly")))
        (is (= 2 (fixture-object-field report "classifiedCount")))
        (is (= 2 (fixture-object-field report "passingCount")))
        (is (= 0 (fixture-object-field report "failingCount")))
        (is (= 0 (length results)))
        (is (plusp (length families)))))))

(deftest classifier-scripts-accept-assigned-options
  #-sbcl
  (skip-test "Fixture classifier scripts require SBCL")
  #+sbcl
  (labels ((run-classifier (script prefix &key include-pinned)
             (let ((args
                     (append
                      (list "sbcl"
                            "--script"
                            script
                            "--"
                            "--root=tests/fixtures/execution-spec-tests-root/"
                            (format nil "--prefix=~A" prefix)
                            "--limit=1"
                            "--json=true"
                            "--failures-only=false")
                      (when include-pinned
                        (list "--include-pinned=true")))))
               (multiple-value-bind (stdout stderr status)
                   (uiop:run-program
                    args
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (= 0 status))
                 (is (string= "" stderr))
                 (when (= 0 status)
                   (let ((report (parse-json stdout)))
                     (is (= 1 (fixture-object-field report "classifiedCount")))
                     (is (= 1 (fixture-object-field report "candidateCount")))
                     (is (= 1 (fixture-object-field report "passingCount")))
                     (is (= 0 (fixture-object-field report "failingCount")))
                     (is (not (fixture-object-field report "failuresOnly")))
                     (is (string= prefix
                                  (fixture-object-field report "prefix")))
                     report))))))
    (run-classifier
     "scripts/classify-blockchain-replay-selectors.lisp"
     "shanghai/phase-a")
    (let ((transaction-report
            (run-classifier
             "scripts/classify-transaction-test-selectors.lisp"
             "phase-a-sample.json"
             :include-pinned t)))
      (is (eq t (fixture-object-field transaction-report "includePinned"))))
    (run-classifier
     "scripts/classify-state-test-selectors.lisp"
     "london/phase-a")))

(deftest phase-a-drift-map-script-help-prints-without-loading-errors
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--help"
             "--unsupported-option")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (is (search "Usage: sbcl --script scripts/phase-a-drift-map.lisp"
                stdout))
    (is (search "--suite SUITE" stdout))
    (is (search "--prefix PREFIX" stdout))
    (is (search "--state-prefix PREFIX" stdout))
    (is (search "--transaction-prefix PREFIX" stdout))
    (is (search "--blockchain-prefix PREFIX" stdout))
    (is (search "--state-limit NUMBER" stdout))
    (is (search "--transaction-limit NUMBER" stdout))
    (is (search "--blockchain-limit NUMBER" stdout))
    (is (search "--summary-only" stdout))
    (is (search "known-implementation-drift" stdout))
    (is (search "out-of-scope-fork-feature" stdout))))

(deftest phase-a-drift-map-script-json-summarizes-suites
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--limit"
             "1"
             "--failures-only"
             "--summary-only"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (overall (fixture-object-field report "overall"))
             (suites (fixture-object-field report "suites")))
        (is (string= "phase-a-drift-map"
                     (fixture-object-field report "mode")))
        (is (eq t (fixture-object-field report "failuresOnly")))
        (is (eq t (fixture-object-field report "summaryOnly")))
        (is (= 3 (length suites)))
        (is (= 3 (fixture-object-field overall "suiteCount")))
        (is (= 3 (fixture-object-field overall "candidateCount")))
        (is (= 3 (fixture-object-field overall "classifiedCount")))
        (is (= 0
               (fixture-object-field
                overall
                "knownImplementationDriftCount")))
        (is (= 0
               (fixture-object-field
                overall
                "fixtureHarnessErrorCount")))
        (is (eq t (fixture-object-field
                   overall
                   "phaseAMaterializableClear")))
        (dolist (suite suites)
          (is (member (fixture-object-field suite "suite")
                      '("state" "transaction" "blockchain")
                      :test #'string=))
          (is (string= "" (fixture-object-field suite "prefix")))
          (is (= 1 (fixture-object-field suite "candidateCount")))
          (is (= 1 (fixture-object-field suite "classifiedCount")))
          (is (= 0 (fixture-object-field
                    suite
                    "knownImplementationDriftCount")))
          (is (fixture-object-field suite "families"))
          (is (null (fixture-object-field suite "results"))))
        (let* ((transaction-suite
                 (find "transaction" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=))
               (transaction-family
                 (first (fixture-object-field transaction-suite "families"))))
          (is (= 1
                 (fixture-object-field transaction-family
                                       "outOfScopeForkFeatureCount")))
          (is (null (fixture-object-field transaction-family
                                          "outOfScopeCount"))))))))

(deftest phase-a-drift-map-script-json-filters-suite
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--root"
             "tests/fixtures/execution-spec-tests-root/"
             "--suite"
             "transaction"
             "--limit"
             "1"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (= 0 status))
    (is (string= "" stderr))
    (when (= 0 status)
      (let* ((report (parse-json stdout))
             (overall (fixture-object-field report "overall"))
             (suites (fixture-object-field report "suites"))
             (suite (first suites)))
        (is (string= "transaction" (fixture-object-field report "suite")))
        (is (= 1 (length suites)))
        (is (= 1 (fixture-object-field overall "suiteCount")))
        (is (= 1 (fixture-object-field overall "candidateCount")))
        (is (= 1 (fixture-object-field overall "classifiedCount")))
        (is (string= "transaction"
                     (fixture-object-field suite "suite")))
        (is (= 1 (fixture-object-field suite "candidateCount")))
        (is (= 1 (fixture-object-field suite "classifiedCount")))))))

(deftest phase-a-drift-map-script-accepts-assigned-options
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (let ((root "tests/fixtures/execution-spec-tests-root/"))
    (multiple-value-bind (stdout stderr status)
        (uiop:run-program
         (list "sbcl"
               "--script"
               "scripts/phase-a-drift-map.lisp"
               "--"
               (format nil "--root=~A" root)
               "--limit=1"
               "--state-prefix=london/phase-a-state-sample.json/phase_a_london_access_list"
               "--transaction-prefix=prague/eip7702_set_code_tx/test_empty_authorization_list"
               "--blockchain-prefix=shanghai/phase-a-empty-engine"
               "--failures-only=true"
               "--summary-only=true"
               "--json=1")
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (= 0 status))
      (is (string= "" stderr))
      (when (= 0 status)
        (let* ((report (parse-json stdout))
               (overall (fixture-object-field report "overall"))
               (suites (fixture-object-field report "suites"))
               (state-suite
                 (find "state" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=))
               (transaction-suite
                 (find "transaction" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=))
               (blockchain-suite
                 (find "blockchain" suites
                       :key (lambda (suite)
                              (fixture-object-field suite "suite"))
                       :test #'string=)))
          (is (string= "phase-a-drift-map"
                       (fixture-object-field report "mode")))
          (is (string= root (fixture-object-field report "root")))
          (is (eq t (fixture-object-field report "failuresOnly")))
          (is (eq t (fixture-object-field report "summaryOnly")))
          (is (string= "london/phase-a-state-sample.json/phase_a_london_access_list"
                       (fixture-object-field state-suite "prefix")))
          (is (string= "prague/eip7702_set_code_tx/test_empty_authorization_list"
                       (fixture-object-field transaction-suite "prefix")))
          (is (string= "shanghai/phase-a-empty-engine"
                       (fixture-object-field blockchain-suite "prefix")))
          (is (= 3 (fixture-object-field overall "classifiedCount"))))))))

(deftest phase-a-drift-map-script-rejects-malformed-boolean-assignment
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--json=maybe")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--json boolean value must be true or false" stderr))))

(deftest phase-a-drift-map-script-rejects-unknown-suite
  #-sbcl
  (skip-test "Phase A drift map script requires SBCL")
  #+sbcl
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (list "sbcl"
             "--script"
             "scripts/phase-a-drift-map.lisp"
             "--"
             "--suite=receipts"
             "--json")
       :output :string
       :error-output :string
       :ignore-error-status t)
    (is (not (= 0 status)))
    (is (string= "" stdout))
    (is (search "--suite requires state, transaction, or blockchain" stderr))))

