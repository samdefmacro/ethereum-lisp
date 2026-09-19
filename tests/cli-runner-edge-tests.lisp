(in-package #:ethereum-lisp.test)

(deftest devnet-cli-selects-embedded-network-presets
  (is (eq :mainnet
          (getf (ethereum-lisp.cli::devnet-cli-options '("--mainnet"))
                :genesis-preset)))
  (is (eq :sepolia
          (getf (ethereum-lisp.cli::devnet-cli-options '("--sepolia"))
                :genesis-preset)))
  (signals error
    (ethereum-lisp.cli::devnet-cli-options
     '("--mainnet" "--holesky")))
  (signals error
    (ethereum-lisp.cli::devnet-cli-options
     '("--mainnet" "--genesis" "custom.json")))
  (is (listp
       (ethereum-lisp.cli::devnet-cli-options '("--mainnet=false")))))

(defun devnet-cli-assert-script-signal-shutdown
    (signal-name temp-name &key engine-only-p)
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-~A-ready" temp-name)
           "json"))
        (log-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-~A" temp-name)
           "log"))
        (pid-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-~A" temp-name)
           "pid"))
        (process nil))
    (unwind-protect
         (progn
           (setf process
                 (test-launch-program
                  (append
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
                         "0")
                   (when engine-only-p
                     (list "--http=false"))
                   (list "--ready-file"
                         (namestring ready-path)
                         "--log-file"
                         (namestring log-path)
                         "--pid-file"
                         (namestring pid-path)
                         "--json"))
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
                    (pid (devnet-cli-pid-file-process-id pid-path)))
               (is (= pid (fixture-object-field ready-summary "processId")))
               (multiple-value-bind (kill-stdout kill-stderr kill-status)
                   (uiop:run-program
                    (list "kill"
                          (format nil "-~A" signal-name)
                          (write-to-string pid))
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (is (= 0 kill-status))
                 (is (string= "" kill-stdout))
                 (is (string= "" kill-stderr)))
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
                   (is (search "Devnet shutdown requested; closing RPC listeners."
                               stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (log-names
                              (mapcar (lambda (record) (getf record :name))
                                      log-records))
                            (engine-endpoint
                              (fixture-object-field stdout-summary
                                                    "engineEndpoint"))
                            (rpc-endpoint
                              (fixture-object-field stdout-summary
                                                    "rpcEndpoint")))
                       (is (= pid
                              (fixture-object-field stdout-summary
                                                    "processId")))
                       (is (string= genesis
                                    (fixture-object-field stdout-summary
                                                          "genesisPath")))
                       (is (string= engine-endpoint
                                    (fixture-object-field ready-summary
                                                          "engineEndpoint")))
                       (if engine-only-p
                           (progn
                             (is (not rpc-endpoint))
                             (is (not (fixture-object-field
                                       ready-summary
                                       "rpcEndpoint")))
                             (is (not (fixture-object-field
                                       stdout-summary
                                       "publicRpcEnabled")))
                             (is (not (fixture-object-field
                                       ready-summary
                                       "publicRpcEnabled"))))
                           (progn
                             (is (string= rpc-endpoint
                                          (fixture-object-field ready-summary
                                                                "rpcEndpoint")))
                             (is (fixture-object-field
                                  stdout-summary
                                  "publicRpcEnabled"))
                             (is (fixture-object-field
                                  ready-summary
                                  "publicRpcEnabled"))))
                       (is (not (string= "127.0.0.1:0" engine-endpoint)))
                       (unless engine-only-p
                         (is (not (string= "127.0.0.1:0" rpc-endpoint))))
                       (is (member "devnet.ready" log-names :test #'string=))
                       (is (member "devnet.shutdown" log-names :test #'string=))
                       (dolist (log-record log-records)
                         (when (member (getf log-record :name)
                                       '("devnet.ready" "devnet.shutdown")
                                       :test #'string=)
                           (let ((fields (getf log-record :fields)))
                             (is (string= engine-endpoint
                                          (cdr (assoc "engineEndpoint"
                                                      fields
                                                      :test #'string=))))
                             (if engine-only-p
                                 (progn
                                   (is (string= ""
                                                (cdr (assoc "rpcEndpoint"
                                                            fields
                                                            :test #'string=))))
                                   (is (string= "false"
                                                (cdr (assoc
                                                      "publicRpcEnabled"
                                                      fields
                                                      :test #'string=)))))
                                 (progn
                                   (is (string= rpc-endpoint
                                                (cdr (assoc "rpcEndpoint"
                                                            fields
                                                            :test #'string=))))
                                   (is (string= "true"
                                                (cdr (assoc
                                                      "publicRpcEnabled"
                                                      fields
                                                      :test #'string=))))))
                             (is (string= (if (string= "devnet.ready"
                                                        (getf log-record :name))
                                               "ready"
                                               "shutdown")
                                          (cdr (assoc "lifecyclePhase"
                                                      fields
                                                      :test #'string=))))
                             (is (string= (write-to-string pid)
                                          (cdr (assoc "processId"
                                                      fields
                                                      :test #'string=))))
                             (is (string= "0"
                                          (cdr (assoc "totalConnections"
                                                      fields
                                                      :test #'string=)))))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))))

(deftest ethereum-lisp-script-serve-mode-handles-sigterm-shutdown
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (devnet-cli-assert-script-signal-shutdown "TERM" "sigterm"))

(deftest ethereum-lisp-script-serve-mode-handles-sigint-shutdown
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (devnet-cli-assert-script-signal-shutdown "INT" "sigint"))

(deftest ethereum-lisp-script-engine-only-serve-mode-handles-sigterm-shutdown
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (devnet-cli-assert-script-signal-shutdown
   "TERM"
   "engine-only-sigterm"
   :engine-only-p t))

(defconstant +devnet-cli-sigterm-stop-budget-seconds+ 20
  "Wall-clock seconds a SIGTERM stop may take while a client is still served.

A container supervisor stops the node with a fixed grace period -- the Hoodi
gate uses `docker stop --time 30` -- and SIGKILLs it when the period expires.
A stop that outlasts the grace period is not a graceful stop at all: it loses
the unwind, the database export and the clean exit status. This budget is the
assertion that a live keep-alive client cannot extend shutdown past it.")

#+sbcl
(defun devnet-cli-keep-alive-rpc-exchange (stream host port)
  "Send one keep-alive eth_chainId request on STREAM and read its response.

Signals on any I/O or framing failure, which is exactly how the driver thread
below learns that the node finally closed the connection."
  (let ((body "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}")
        (crlf (format nil "~C~C" #\Return #\Newline)))
    (write-string
     (with-output-to-string (request)
       (format request "POST / HTTP/1.1~A" crlf)
       (format request "Host: ~A:~D~A" host port crlf)
       (format request "Connection: keep-alive~A" crlf)
       (format request "Content-Type: application/json~A" crlf)
       (format request "Content-Length: ~D~A~A~A"
               (length body) crlf crlf body))
     stream)
    (finish-output stream)
    (let ((content-length nil))
      (loop for line = (read-line stream nil :eof)
            do (when (eq line :eof)
                 (error "Keep-alive response ended before its headers"))
               (let ((trimmed (string-right-trim '(#\Return) line)))
                 (when (string= "" trimmed)
                   (return))
                 (let ((colon (position #\: trimmed)))
                   (when (and colon
                              (string-equal "Content-Length"
                                            (subseq trimmed 0 colon)))
                     (setf content-length
                           (parse-integer trimmed
                                          :start (1+ colon)
                                          :junk-allowed t))))))
      (unless content-length
        (error "Keep-alive response carried no Content-Length"))
      (let ((buffer (make-string content-length)))
        (unless (= content-length (read-sequence buffer stream))
          (error "Keep-alive response body was truncated"))
        buffer))))

#+sbcl
(defconstant +devnet-cli-keep-alive-idle-probe-seconds+ 3
  "How long the idle variant leaves its keep-alive connection unused.

Longer than the connection loop's stop-check interval, so the worker serving it
is genuinely parked in the wait for the next request when the signal arrives --
which is the case the busy variant cannot reach -- and far shorter than the
120-second keep-alive idle budget, so the connection is still open.")

(defparameter *devnet-cli-last-sigterm-stop-seconds* nil
  "Wall-clock seconds the last timed SIGTERM stop took, or NIL.

The budget assertion only says the stop fitted; the number says by how much,
which is what a later reviewer needs when the supervisor's grace period is
argued about. Reset per run, so a run that aborts before measuring cannot
leave the previous run's value looking like its own.")

#+sbcl
(defun devnet-cli-assert-sigterm-stop-is-bounded (&key (mode :busy))
  "Signal a node serving a reused connection, and time the stop.

MODE :BUSY keeps a driver thread issuing requests on the pooled connection
through the whole shutdown. MODE :IDLE leaves the connection open but silent,
which parks the worker serving it in the wait for the next request instead.

RED before the shutdown fix, in both shapes: nothing tells a per-connection
worker to stop. DEVNET-SHUTDOWN-REQUEST closes only the LISTENING sockets, the
per-connection loop consults no stop predicate, and the listener's own unwind
then waits for that worker for `5 + request-timeout + idle-timeout` seconds. A
consensus client that keeps its pooled connection is therefore served straight
through the supervisor's grace period, which is what SIGKILLed the live Hoodi
container at exit 137 while it was still answering Engine requests."
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (ready-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-sigterm-bound-~(~A~)-ready" mode)
           "json"))
        (pid-path
          (devnet-cli-temp-path
           (format nil "ethereum-lisp-script-sigterm-bound-~(~A~)" mode)
           "pid"))
        (process nil)
        (stream nil)
        (driver nil)
        (driving t)
        (exchanges 0))
    (setf *devnet-cli-last-sigterm-stop-seconds* nil)
    (unwind-protect
         (progn
           (setf process
                 (test-launch-program
                  (list "sbcl" "--script" script "--" "devnet"
                        "--genesis" genesis
                        "--engine-port" "0"
                        "--public-port" "0"
                        "--ready-file" (namestring ready-path)
                        "--pid-file" (namestring pid-path)
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))))
           (let* ((summary (parse-json (devnet-cli-file-string ready-path)))
                  (endpoint (fixture-object-field summary "rpcEndpoint"))
                  (pid (devnet-cli-pid-file-process-id pid-path)))
             (multiple-value-bind (host port)
                 (devnet-cli-http-endpoint-host-port endpoint)
               (setf stream
                     (handler-case (devnet-cli-connect-stream host port)
                       (sb-bsd-sockets:operation-not-permitted-error ()
                         (skip-test
                          "Local socket connect is not permitted in this sandbox"))))
               ;; Prove the connection really is reusable before signalling, so
               ;; a failure below is about shutdown and not about the endpoint.
               (is (stringp (devnet-cli-keep-alive-rpc-exchange
                             stream host port)))
               (is (stringp (devnet-cli-keep-alive-rpc-exchange
                             stream host port)))
               (ecase mode
                 (:busy
                  (setf driver
                        (sb-thread:make-thread
                         (lambda ()
                           ;; The whole body is contained: the suite runs as
                           ;; `sbcl --script`, so an escaping condition in ANY
                           ;; thread exits the run with code 1 and no test
                           ;; result at all, rather than failing this test. The
                           ;; server closing the connection is the EXPECTED end
                           ;; of this loop once shutdown is honoured, so it is
                           ;; caught rather than reported.
                           (handler-case
                               (loop while driving
                                     do (devnet-cli-keep-alive-rpc-exchange
                                         stream host port)
                                        (incf exchanges)
                                        (sleep 0.1))
                             (serious-condition () nil)))
                         :name "ethereum-lisp-test-keep-alive-driver")))
                 (:idle
                  ;; Go quiet, then prove the connection SURVIVED the silence
                  ;; by reusing it once more. Without that the stop could be
                  ;; fast merely because the server had already closed a
                  ;; connection this test believes it is still holding.
                  (sleep +devnet-cli-keep-alive-idle-probe-seconds+)
                  (is (stringp (devnet-cli-keep-alive-rpc-exchange
                                stream host port)))
                  (incf exchanges 3)
                  ;; And park the worker in the idle wait again before the
                  ;; signal, which is the state this variant exists to cover.
                  (sleep +devnet-cli-keep-alive-idle-probe-seconds+)))
               (wait-for-test-condition
                "keep-alive traffic on the reused connection"
                10
                (lambda () (<= 2 exchanges))
                :diagnostics
                (lambda () (format nil "mode=~A exchanges=~D" mode exchanges))))
             (let ((started (monotonic-seconds)))
               (multiple-value-bind (kill-stdout kill-stderr kill-status)
                   (uiop:run-program
                    (list "kill" "-TERM" (write-to-string pid))
                    :output :string
                    :error-output :string
                    :ignore-error-status t)
                 (declare (ignore kill-stdout kill-stderr))
                 (is (= 0 kill-status)))
               (let* ((status
                        (devnet-cli-wait-process-exit
                         process +devnet-cli-sigterm-stop-budget-seconds+))
                      (elapsed (- (monotonic-seconds) started)))
                 (setf driving nil)
                 (setf *devnet-cli-last-sigterm-stop-seconds* elapsed)
                 (when (eq status :timeout)
                   (uiop:terminate-process process)
                   (devnet-cli-wait-process-exit process 10))
                 (is (not (eq status :timeout)))
                 (is (< elapsed +devnet-cli-sigterm-stop-budget-seconds+))
                 (is (eql 0 status))))))
      (setf driving nil)
      (when driver
        (ignore-errors
         (sb-thread:join-thread driver :timeout 10 :default :timeout)))
      (when stream (ignore-errors (close stream)))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file ready-path) (delete-file ready-path))
      (when (probe-file pid-path) (delete-file pid-path)))))

(deftest devnet-cli-sigterm-stops-a-node-serving-a-keep-alive-connection
  (:estimated-seconds 45d0)
  #-sbcl
  (skip-test "Bounded SIGTERM shutdown requires SBCL threads and sockets")
  #+sbcl
  (devnet-cli-assert-sigterm-stop-is-bounded :mode :busy))

(deftest devnet-cli-sigterm-stops-a-node-holding-an-idle-keep-alive-connection
  (:estimated-seconds 55d0)
  ;; The other half of the same hazard, and the half a busy client cannot
  ;; reach: a pooled connection that is open but silent leaves its worker
  ;; parked in the wait for the next request, where a stop request the listener
  ;; already knows about was invisible for the whole 120-second idle budget.
  #-sbcl
  (skip-test "Bounded SIGTERM shutdown requires SBCL threads and sockets")
  #+sbcl
  (devnet-cli-assert-sigterm-stop-is-bounded :mode :idle))

(defun devnet-cli-assert-script-error-telemetry
    (args error-substring &key
          (event-name "devnet.error")
          (usage-substring "Usage: ethereum-lisp devnet"))
  (let ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
        (log-path
          (devnet-cli-temp-path "ethereum-lisp-script-error" "log")))
    (unwind-protect
         (multiple-value-bind (stdout stderr status)
             (uiop:run-program
              (append (list "sbcl" "--script" script "--")
                      args
                      (list "--log-file" (namestring log-path)))
              :directory #P"/private/tmp/"
              :output :string
              :error-output :string
              :ignore-error-status t)
           (is (= 1 status))
           (is (string= "" stdout))
           (is (search error-substring stderr))
           (if usage-substring
               (is (search usage-substring stderr))
               (is (null (search "Usage: ethereum-lisp" stderr))))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields))
                  (process-id
                    (parse-integer
                     (cdr (assoc "processId" fields :test #'string=))
                     :junk-allowed nil)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= event-name (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (plusp process-id))
             (is (not (= (devnet-cli-current-process-id) process-id)))
             (is (search error-substring
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= (namestring log-path)
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest ethereum-lisp-script-records-runner-error-telemetry
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let ((genesis (namestring (truename +devnet-cli-genesis-fixture+)))
        (init-datadir
          (devnet-cli-temp-directory
           "ethereum-lisp-script-init-jwt-error-datadir"))
        (bad-jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-bad-jwt" "hex"))
        (missing-jwt-path
          (devnet-cli-temp-path "ethereum-lisp-script-missing-jwt" "hex"))
        (non-executable-kzg-command
          (devnet-cli-temp-path "ethereum-lisp-script-kzg-error" "sh")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file bad-jwt-path "not-hex")
           (devnet-cli-write-temp-file
            non-executable-kzg-command
            "#!/bin/sh\necho true\n")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet" "--json" "--no-serve")
            "--genesis is required")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--public-port"
                  "not-a-port"
                  "--no-serve")
            "--public-port requires an integer value")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--public-port")
            "--public-port requires a value")
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--authrpc.jwtsecret"
                  (namestring bad-jwt-path)
                  "--no-serve")
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret"
            :usage-substring nil)
           (devnet-cli-assert-script-error-telemetry
            (list "devnet"
                  "--genesis"
                  genesis
                  "--authrpc.jwtsecret"
                  (namestring missing-jwt-path)
                  "--no-serve")
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret"
            :usage-substring nil)
           (devnet-cli-assert-script-error-telemetry
            (list "init" "--json")
            "init requires a genesis file"
            :event-name "init.error"
            :usage-substring "Usage: ethereum-lisp init")
           (devnet-cli-assert-script-error-telemetry
            (list "init"
                  "--datadir"
                  (namestring init-datadir)
                  "--authrpc.jwtsecret"
                  (namestring bad-jwt-path)
                  "--json"
                  genesis)
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret"
            :event-name "init.error"
            :usage-substring nil)
           (devnet-cli-assert-script-error-telemetry
            (list "init"
                  "--datadir"
                  (namestring init-datadir)
                  "--authrpc.jwtsecret"
                  (namestring missing-jwt-path)
                  "--json"
                  genesis)
            "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret"
            :event-name "init.error"
            :usage-substring nil))
      (when (probe-file bad-jwt-path)
        (delete-file bad-jwt-path))
      (when (probe-file missing-jwt-path)
        (delete-file missing-jwt-path))
      (when (probe-file non-executable-kzg-command)
        (delete-file non-executable-kzg-command))
      (when (probe-file init-datadir)
        (ignore-errors
          (uiop:delete-directory-tree init-datadir :validate t))))))

(deftest devnet-cli-rejects-missing-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "devnet" "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (is (search "--genesis is required"
                (get-output-stream-string errors)))))

(deftest devnet-cli-boolean-flag-values-affect-semantic-flags
  (let ((disabled
          (ethereum-lisp.cli::devnet-cli-options
           (list "devnet"
                 "--json=false"
                 "--no-serve=0"
                 "--http=true"
                 "--graphql=0"
                 "--nousb=0"
                 "--mine=false"
                 "--dev=false"
                 "--metrics=0"
                 "--pprof=false"
                 "--snapshot"
                 "false")))
         (enabled
          (ethereum-lisp.cli::devnet-cli-options
           (list "devnet"
                 "--json=1"
                 "--no-serve=true"
                 "--http=false"
                 "--dev"))))
    (is (eq :sexp (getf disabled :summary-format)))
    (is (getf disabled :serve-p))
    (is (getf disabled :public-rpc-enabled-p))
    (is (not (getf disabled :dev-mode-p)))
    (is (eq :json (getf enabled :summary-format)))
    (is (not (getf enabled :serve-p)))
    (is (not (getf enabled :public-rpc-enabled-p)))
    (is (getf enabled :dev-mode-p))))

(deftest devnet-cli-init-json-boolean-values-affect-summary-format
  (let ((disabled
          (ethereum-lisp.cli::devnet-cli-init-options
           (list "init" "--json=false")))
        (enabled
          (ethereum-lisp.cli::devnet-cli-init-options
           (list "init" "--json" "1"))))
    (is (eq :sexp (getf disabled :summary-format)))
    (is (eq :json (getf enabled :summary-format)))))

(deftest devnet-cli-init-rejects-malformed-json-boolean-before-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "init" "--json=maybe")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (let ((stderr (get-output-stream-string errors)))
      (is (search "--json boolean value must be true or false" stderr))
      (is (search "Usage: ethereum-lisp init" stderr)))))

#+sbcl
(deftest devnet-cli-datadir-lock-covers-the-node-lifetime
  (:layer :unit :module :cli)
  (let ((directory
          (uiop:ensure-directory-pathname
           (devnet-cli-temp-path "ethereum-lisp-lock-test" nil))))
    (unwind-protect
         (let ((result
                 (ethereum-lisp.cli::call-with-devnet-cli-datadir-lock
                  directory
                  (lambda ()
                    (is (probe-file (merge-pathnames "LOCK" directory)))
                    :owned))))
           (is (eq :owned result)))
      (uiop:delete-directory-tree
       directory :validate t :if-does-not-exist :ignore))))

(deftest devnet-cli-accepts-geth-style-mining-archive-and-metrics-flags
  (let ((config-path
          (devnet-cli-temp-path "ethereum-lisp-geth" "toml")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            config-path
            "# geth runner config intentionally empty for flag coverage\n")
           (let ((options
                   (ethereum-lisp.cli::devnet-cli-options
                    (list "devnet"
                          "--config"
                          (namestring config-path)
                          "--gcmode=archive"
                          "--cache"
                          "256"
                          "--cache.database=64"
                          "--cache.gc"
                          "32"
                          "--cache.trie=160"
                          "--txlookuplimit=0"
                          "--history.transactions"
                          "0"
                          "--bootnodes="
                          "--netrestrict=127.0.0.0/8"
                          "--nodekey=/tmp/ethereum-lisp-nodekey"
                          "--nodekeyhex"
                          "0101010101010101010101010101010101010101010101010101010101010101"
                          "--discovery.port=30303"
                          "--discovery.dns="
                          "--mine=true"
                          "--miner.etherbase"
                          "0x0000000000000000000000000000000000000000"
                          "--etherbase=0x0000000000000000000000000000000000000000"
                          "--miner.gaslimit"
                          "30000000"
                          "--miner.gasprice=0"
                          "--unlock"
                          "0"
                          "--password=/tmp/password"
                          "--allow-insecure-unlock=true"
                          "--metrics=true"
                          "--metrics.addr"
                          "127.0.0.1"
                          "--metrics.port=6060"
                          "--pprof=false"
                          "--pprof.addr"
                          "127.0.0.1"
                          "--pprof.port=6061"
                          "--snapshot=false"
                          "--json"
                          "--no-serve"))))
             (is (eq :json (getf options :summary-format)))
             (is (not (getf options :serve-p)))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-accepts-geth-style-logging-flags
  (let ((options
          (ethereum-lisp.cli::devnet-cli-options
           (list "devnet"
                 "--log.file=/tmp/geth.log"
                 "--log.format"
                 "json"
                 "--log.maxsize=64"
                 "--log.maxbackups"
                 "3"
                 "--log.maxage=7"
                 "--log.compress=false"
                 "--log-file=/tmp/ethereum-lisp-events.jsonl"
                 "--json"
                 "--no-serve"))))
    (is (eq :json (getf options :summary-format)))
    (is (not (getf options :serve-p)))
    (is (string= "/tmp/ethereum-lisp-events.jsonl"
                 (getf options :log-file)))))

(deftest devnet-cli-rejects-malformed-options-before-loading-genesis
  (labels ((run-error (args)
             (let ((output (make-string-output-stream))
                   (errors (make-string-output-stream)))
               (is (= 1
                      (ethereum-lisp.cli:main
                       args
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string output)))
               (get-output-stream-string errors))))
    (is (search "--port requires an integer value"
                (run-error (list "devnet" "--port" "abc" "--no-serve"))))
    (is (search "--port requires an integer value"
                (run-error (list "devnet" "--port=abc" "--no-serve"))))
    (is (search "--port must be between 0 and 65535"
                (run-error (list "devnet" "--port" "70000" "--no-serve"))))
    (is (search "--public-port requires an integer value"
                (run-error (list "devnet"
                                 "--public-port"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--public-port must be between 0 and 65535"
                (run-error (list "devnet"
                                 "--public-port"
                                 "70000"
                                 "--no-serve"))))
    (is (search "--authrpc.rpcprefix requires a path beginning with /"
                (run-error (list "devnet"
                                 "--authrpc.rpcprefix"
                                 "engine"
                                 "--no-serve"))))
    (is (search "--authrpc.rpcprefix requires a path beginning with /"
                (run-error (list "devnet"
                                 "--authrpc.rpcprefix=engine"
                                 "--no-serve"))))
    (is (search "--http boolean value must be true or false"
                (run-error (list "devnet"
                                 "--http=maybe"
                                 "--no-serve"))))
    (is (search "--nousb boolean value must be true or false"
                (run-error (list "devnet"
                                 "--nousb"
                                 "maybe"
                                 "--no-serve"))))
    (is (search "--ws boolean value must be true or false"
                (run-error (list "devnet"
                                 "--ws=maybe"
                                 "--no-serve"))))
    (is (search "--graphql boolean value must be true or false"
                (run-error (list "devnet"
                                 "--graphql=maybe"
                                 "--no-serve"))))
    (is (search "--allow-insecure-unlock boolean value must be true or false"
                (run-error (list "devnet"
                                 "--allow-insecure-unlock=maybe"
                                 "--no-serve"))))
    (is (search "--mine boolean value must be true or false"
                (run-error (list "devnet"
                                 "--mine=maybe"
                                 "--no-serve"))))
    (is (search "--metrics boolean value must be true or false"
                (run-error (list "devnet"
                                 "--metrics=maybe"
                                 "--no-serve"))))
    (is (search "--pprof boolean value must be true or false"
                (run-error (list "devnet"
                                 "--pprof=maybe"
                                 "--no-serve"))))
    (is (search "--snapshot boolean value must be true or false"
                (run-error (list "devnet"
                                 "--snapshot=maybe"
                                 "--no-serve"))))
    (is (search "--log.compress boolean value must be true or false"
                (run-error (list "devnet"
                                 "--log.compress=maybe"
                                 "--no-serve"))))
    (is (search "--rpc.allow-unprotected-txs boolean value must be true or false"
                (run-error (list "devnet"
                                 "--rpc.allow-unprotected-txs=maybe"
                                 "--no-serve"))))
    (is (search "--override.terminaltotaldifficultypassed boolean value must be true or false"
                (run-error (list "devnet"
                                 "--override.terminaltotaldifficultypassed=maybe"
                                 "--no-serve"))))
    (is (search "--txpool.nolocals boolean value must be true or false"
                (run-error (list "devnet"
                                 "--txpool.nolocals=maybe"
                                 "--no-serve"))))
    (is (search "--txpool.locals requires a value"
                (run-error (list "devnet"
                                 "--txpool.locals"
                                 "--no-serve"))))
    (is (search "--txpool.locals requires at least one 20-byte hex address"
                (run-error (list "devnet"
                                 "--txpool.locals=,"
                                 "--no-serve"))))
    (is (search "--txpool.locals requires a 20-byte hex address"
                (run-error (list "devnet"
                                 "--txpool.locals=not-an-address"
                                 "--no-serve"))))
    (is (search "--dev boolean value must be true or false"
                (run-error (list "devnet"
                                 "--dev=maybe"
                                 "--no-serve"))))
    (is (search "--nousb boolean value must be true or false"
                (run-error (list "devnet"
                                 "--nousb=maybe"
                                 "--no-serve"))))
    (is (search "--http.rpcprefix requires a path beginning with /"
                (run-error (list "devnet"
                                 "--http.rpcprefix"
                                 "rpc"
                                 "--no-serve"))))
    (is (search "--max-connections must be non-negative"
                (run-error (list "devnet"
                                 "--max-connections"
                                 "-1"
                                 "--no-serve"))))
    (is (search "--prune-state-before requires an integer value"
                (run-error (list "devnet"
                                 "--prune-state-before"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--prune-state-before must be non-negative"
                (run-error (list "devnet"
                                 "--prune-state-before"
                                 "-1"
                                 "--no-serve"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis" "--no-serve"))))
    (is (search "--config requires a value"
                (run-error (list "devnet" "--config" "--no-serve"))))
    (is (search "--host requires a value"
                (run-error (list "devnet" "--host" "--no-serve"))))
    (is (search "--engine-host requires a value"
                (run-error (list "devnet" "--engine-host" "--no-serve"))))
    (is (search "--public-host requires a value"
                (run-error (list "devnet" "--public-host" "--no-serve"))))
    (is (search "--port requires a value"
                (run-error (list "devnet" "--port" "--no-serve"))))
    (is (search "--engine-port requires a value"
                (run-error (list "devnet" "--engine-port" "--no-serve"))))
    (is (search "--engine-port must be between 0 and 65535"
                (run-error (list "devnet"
                                 "--engine-port"
                                 "70000"
                                 "--no-serve"))))
    (is (search "--public-port requires a value"
                (run-error (list "devnet" "--public-port" "--no-serve"))))
    (is (search "--authrpc.rpcprefix requires a value"
                (run-error (list "devnet"
                                 "--authrpc.rpcprefix"
                                 "--no-serve"))))
    (is (search "--http.rpcprefix requires a value"
                (run-error (list "devnet"
                                 "--http.rpcprefix"
                                 "--no-serve"))))
    (is (search "--graphql.addr requires a value"
                (run-error (list "devnet"
                                 "--graphql.addr"
                                 "--no-serve"))))
    (is (search "--ws.rpcprefix requires a value"
                (run-error (list "devnet"
                                 "--ws.rpcprefix"
                                 "--no-serve"))))
    (is (search "--ipcapi is not supported"
                (run-error (list "devnet"
                                 "--ipcapi"
                                 "--no-serve"))))
    (is (search "--nodekeyhex requires a value"
                (run-error (list "devnet"
                                 "--nodekeyhex"
                                 "--no-serve"))))
    (is (search "--discovery.port requires a value"
                (run-error (list "devnet"
                                 "--discovery.port"
                                 "--no-serve"))))
    (is (search "--ipcpath is not supported"
                (run-error (list "devnet"
                                 "--ipcpath"
                                 "--no-serve"))))
    (is (search "--log.file requires a value"
                (run-error (list "devnet"
                                 "--log.file"
                                 "--no-serve"))))
    (is (search "--http.maxclients requires a value"
                (run-error (list "devnet"
                                 "--http.maxclients"
                                 "--no-serve"))))
    (is (search "--http.readtimeout requires a value"
                (run-error (list "devnet"
                                 "--http.readtimeout"
                                 "--no-serve"))))
    (is (search "--txpool.pricebump requires a value"
                (run-error (list "devnet"
                                 "--txpool.pricebump"
                                 "--no-serve"))))
    (is (search "--txpool.accountslots requires a value"
                (run-error (list "devnet"
                                 "--txpool.accountslots"
                                 "--no-serve"))))
    (is (search "--txpool.globalslots requires a value"
                (run-error (list "devnet"
                                 "--txpool.globalslots"
                                 "--no-serve"))))
    (is (search "--txpool.accountqueue requires a value"
                (run-error (list "devnet"
                                 "--txpool.accountqueue"
                                 "--no-serve"))))
    (is (search "--txpool.globalqueue requires a value"
                (run-error (list "devnet"
                                 "--txpool.globalqueue"
                                 "--no-serve"))))
    (is (search "--txpool.lifetime requires a value"
                (run-error (list "devnet"
                                 "--txpool.lifetime"
                                 "--no-serve"))))
    (is (search "--txpool.pricelimit requires a non-negative integer or hex quantity"
                (run-error (list "devnet"
                                 "--txpool.pricelimit=abc"
                                 "--no-serve"))))
    (is (search "--txpool.pricebump requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.pricebump=abc"
                                 "--no-serve"))))
    (is (search "--txpool.accountslots requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.accountslots=abc"
                                 "--no-serve"))))
    (is (search "--txpool.globalslots requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.globalslots=abc"
                                 "--no-serve"))))
    (is (search "--txpool.accountqueue requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.accountqueue=abc"
                                 "--no-serve"))))
    (is (search "--txpool.globalqueue requires an integer value"
                (run-error (list "devnet"
                                 "--txpool.globalqueue=abc"
                                 "--no-serve"))))
    (is (search "--txpool.lifetime duration unit must be one of s, m, h, or d"
                (run-error (list "devnet"
                                 "--txpool.lifetime=1fortnight"
                                 "--no-serve"))))
    (is (search "--dev.period requires a value"
                (run-error (list "devnet"
                                 "--dev.period"
                                 "--no-serve"))))
    (is (search "--dev.gaslimit requires a value"
                (run-error (list "devnet"
                                 "--dev.gaslimit"
                                 "--no-serve"))))
    (is (search "--dev.gaslimit requires a non-negative integer or hex quantity"
                (run-error (list "devnet"
                                 "--dev.gaslimit=abc"
                                 "--no-serve"))))
    (is (search "--miner.gaslimit requires a non-negative integer or hex quantity"
                (run-error (list "devnet"
                                 "--miner.gaslimit=abc"
                                 "--no-serve"))))
    (is (search "--miner.etherbase requires a 20-byte hex address"
                (run-error (list "devnet"
                                 "--miner.etherbase=0x1234"
                                 "--no-serve"))))
    (is (search "--sepolia boolean value must be true or false"
                (run-error (list "devnet"
                                 "--sepolia=maybe"
                                 "--no-serve"))))
    (is (search "--etherbase requires a 20-byte hex address"
                (run-error (list "devnet"
                                 "--etherbase=not-address"
                                 "--no-serve"))))
    (is (search "--cache requires a value"
                (run-error (list "devnet"
                                 "--cache"
                                 "--no-serve"))))
    (is (search "--override.terminaltotaldifficulty requires a value"
                (run-error (list "devnet"
                                 "--override.terminaltotaldifficulty"
                                 "--no-serve"))))
    (is (search "--database requires a value"
                (run-error (list "devnet" "--database"))))
    (is (search "--prune-state-before requires a value"
                (run-error (list "devnet" "--prune-state-before"))))
    (is (search "--log-file requires a value"
                (run-error (list "devnet" "--log-file"))))
    (is (search "--pid-file requires a value"
                (run-error (list "devnet" "--pid-file"))))
    (is (search "Unknown option --wat"
                (run-error (list "devnet" "--wat"))))))

(deftest devnet-cli-public-chain-presets-use-built-in-genesis
  (:layer :unit :module :cli)
  (let ((options
          (ethereum-lisp.cli:devnet-cli-apply-chain-preset
           (ethereum-lisp.cli::devnet-cli-options
            '("devnet" "--mainnet" "--no-serve")))))
    (is (eq :mainnet (getf options :genesis-preset)))
    (is (null (getf options :chain-preset)))
    (is (null (ethereum-lisp.cli::devnet-cli-resolve-genesis-json
               options nil)))))
