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
  (handler-case
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
            (sb-bsd-sockets:socket-close socket))))
    (sb-bsd-sockets:operation-not-permitted-error ()
      (skip-test "Local socket bind is not permitted in this sandbox"))))

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
