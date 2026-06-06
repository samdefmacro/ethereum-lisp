(defparameter *ethereum-lisp-devnet-smoke-gate-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(load (merge-pathnames "tests/load-tests.lisp"
                       *ethereum-lisp-devnet-smoke-gate-root*))

(in-package #:ethereum-lisp.test)

(defconstant +devnet-smoke-gate-json-flag+ "--json")
(defconstant +devnet-smoke-gate-help-flag+ "--help")
(defconstant +devnet-smoke-gate-fixture-case-option+ "--fixture-case")
(defconstant +devnet-smoke-gate-ready-file-option+ "--ready-file")
(defconstant +devnet-smoke-gate-log-file-option+ "--log-file")
(defconstant +devnet-smoke-gate-default-fixture-case+
  "shanghai-one-transfer-with-withdrawal")

(defun devnet-smoke-gate-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun devnet-smoke-gate-json-p (args)
  (member +devnet-smoke-gate-json-flag+ args :test #'string=))

(defun devnet-smoke-gate-help-p (args)
  (member +devnet-smoke-gate-help-flag+ args :test #'string=))

(defun devnet-smoke-gate-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun devnet-smoke-gate-fixture-case-name (args)
  (let ((fixture-case nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((string= arg +devnet-smoke-gate-json-flag+))
            ((string= arg +devnet-smoke-gate-help-flag+))
            ((or (string= arg +devnet-smoke-gate-ready-file-option+)
                 (string= arg +devnet-smoke-gate-log-file-option+))
             (unless args
               (error "~A requires a path" arg))
             (let ((value (pop args)))
               (when (devnet-smoke-gate-option-like-p value)
                 (error "~A requires a path, got option ~A" arg value))))
            ((string= arg +devnet-smoke-gate-fixture-case-option+)
             (when fixture-case
               (error "Only one fixture case argument is supported"))
             (unless args
               (error "~A requires a fixture case name"
                      +devnet-smoke-gate-fixture-case-option+))
             (let ((value (pop args)))
               (when (devnet-smoke-gate-option-like-p value)
                 (error "~A requires a fixture case name, got option ~A"
                        +devnet-smoke-gate-fixture-case-option+
                        value))
               (setf fixture-case value)))
            ((devnet-smoke-gate-option-like-p arg)
             (error "Unsupported devnet smoke gate option ~A" arg))
            (t
             (when fixture-case
               (error "Only one fixture case argument is supported"))
             (setf fixture-case arg))))
    (or fixture-case +devnet-smoke-gate-default-fixture-case+)))

(defun devnet-smoke-gate-path-option (args option)
  (let ((path nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((string= arg option)
             (when path
               (error "Only one ~A option is supported" option))
             (unless args
               (error "~A requires a path" option))
             (let ((value (pop args)))
               (when (devnet-smoke-gate-option-like-p value)
                 (error "~A requires a path, got option ~A" option value))
               (setf path value)))
            ((string= arg +devnet-smoke-gate-fixture-case-option+)
             (when args
               (pop args)))
            ((or (string= arg +devnet-smoke-gate-ready-file-option+)
                 (string= arg +devnet-smoke-gate-log-file-option+))
             (when args
               (pop args)))))
    path))

(defun devnet-smoke-gate-print-help ()
  (format t "~&Usage: sbcl --script scripts/devnet-smoke-gate.lisp -- [options] [FIXTURE-CASE]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --fixture-case NAME  Engine newPayloadV2 fixture case to import.~%")
  (format t "  --ready-file PATH    Write devnet readiness JSON and verify it.~%")
  (format t "  --log-file PATH      Write devnet telemetry events and verify them.~%")
  (format t "  --json               Print machine-readable JSON output.~%")
  (format t "  --help               Print this help.~%")
  (format t "~%")
  (format t "Default fixture case: ~A~%"
          +devnet-smoke-gate-default-fixture-case+))

(defun devnet-smoke-gate-require (condition format-control &rest args)
  (unless condition
    (apply #'error format-control args)))

(defun devnet-smoke-gate-rpc-body (response)
  (parse-json (devnet-cli-http-body response)))

(defun devnet-smoke-gate-call-with-telemetry-sink (log-file thunk)
  (if log-file
      (with-open-file (stream log-file
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (funcall thunk
                 (ethereum-lisp.telemetry:make-stream-telemetry-sink
                  :stream stream)))
      (funcall thunk ethereum-lisp.telemetry:*telemetry-sink*)))

(defun devnet-smoke-gate-file-string (path)
  (with-open-file (stream path :direction :input)
    (let ((string (make-string (file-length stream))))
      (read-sequence string stream)
      string)))

(defun devnet-smoke-gate-file-forms (path)
  (with-open-file (stream path :direction :input)
    (loop for form = (read stream nil :eof)
          until (eq form :eof)
          collect form)))

(defun devnet-smoke-gate-engine-fixture (case-name)
  (let* ((case
           (select-engine-newpayload-v2-fixture-case
            +engine-newpayload-v2-fixture-path+
            case-name))
         (store (make-engine-payload-memory-store))
         (config (engine-fixture-chain-config case))
         (parent (fixture-object-field case "parent"))
         (payload-case (fixture-object-field case "payload"))
         (expect (fixture-object-field case "expect"))
         (parent-state (engine-fixture-parent-state parent))
         (fee-recipient (fixture-address-field parent "feeRecipient"))
         (transactions
           (mapcar (lambda (raw)
                     (transaction-from-encoding (hex-to-bytes raw)))
                   (fixture-object-field payload-case "transactions")))
         (withdrawals
           (mapcar #'engine-fixture-withdrawal
                   (fixture-object-field payload-case "withdrawals")))
         (parent-header
           (make-block-header
            :parent-hash (zero-hash32)
            :beneficiary fee-recipient
            :state-root (state-db-root parent-state)
            :mix-hash (zero-hash32)
            :number (fixture-quantity-field parent "number")
            :gas-limit (fixture-quantity-field parent "gasLimit")
            :gas-used (fixture-quantity-field parent "gasUsed")
            :timestamp (fixture-quantity-field parent "timestamp")
            :base-fee-per-gas (fixture-quantity-field parent "baseFeePerGas")
            :withdrawals-root (withdrawal-list-root '())))
         (parent-block (make-block :header parent-header))
         (child-state (state-db-copy parent-state))
         (child-header
           (make-block-header
            :parent-hash (block-hash parent-block)
            :beneficiary fee-recipient
            :mix-hash (zero-hash32)
            :number (fixture-quantity-field payload-case "number")
            :gas-limit (fixture-quantity-field payload-case "gasLimit")
            :gas-used 0
            :timestamp (fixture-quantity-field payload-case "timestamp")
            :base-fee-per-gas
            (fixture-quantity-field payload-case "baseFeePerGas")))
         (child-block
           (execute-signed-block
            child-state
            transactions
            :expected-chain-id (chain-config-chain-id config)
            :header child-header
            :chain-config config
            :withdrawals withdrawals))
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data child-block))))
    (list
     (cons "case" case)
     (cons "store" store)
     (cons "config" config)
     (cons "parentState" parent-state)
     (cons "parentBlock" parent-block)
     (cons "childBlock" child-block)
     (cons "payload" payload)
     (cons "payloadCase" payload-case)
     (cons "expect" expect))))

(defun devnet-smoke-gate-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun devnet-smoke-gate-verify-ready-file (path)
  (let ((summary (parse-json (devnet-smoke-gate-file-string path))))
    (devnet-smoke-gate-require
     (string= "engine" (fixture-object-field summary "engineEndpoint"))
     "Ready file Engine endpoint mismatch")
    (devnet-smoke-gate-require
     (string= "public" (fixture-object-field summary "rpcEndpoint"))
     "Ready file public RPC endpoint mismatch")
    (devnet-smoke-gate-require
     (eq t (fixture-object-field summary "authRequired"))
     "Ready file must report authenticated Engine RPC")
    (devnet-smoke-gate-require
     (eq t (fixture-object-field summary "stateAvailable"))
     "Ready file must report available head state")
    summary))

(defun devnet-smoke-gate-verify-log-file (path)
  (let* ((records (devnet-smoke-gate-file-forms path))
         (names (mapcar (lambda (record) (getf record :name)) records)))
    (devnet-smoke-gate-require
     (member "devnet.ready" names :test #'string=)
     "Log file missing devnet.ready event")
    (devnet-smoke-gate-require
     (member "devnet.shutdown" names :test #'string=)
     "Log file missing devnet.shutdown event")
    (dolist (record records)
      (when (member (getf record :name)
                    '("devnet.ready" "devnet.shutdown")
                    :test #'string=)
        (let ((fields (getf record :fields)))
          (devnet-smoke-gate-require
           (string= "engine"
                    (cdr (assoc "engineEndpoint" fields :test #'string=)))
           "Log file Engine endpoint mismatch")
          (devnet-smoke-gate-require
           (string= "public"
                    (cdr (assoc "rpcEndpoint" fields :test #'string=)))
           "Log file public RPC endpoint mismatch"))))
    records))

(defun devnet-smoke-gate-run (case-name &key ready-file log-file)
  #+sbcl
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let ((report
                   (devnet-smoke-gate-call-with-telemetry-sink
                    log-file
                    (lambda (telemetry-sink)
                      (let* ((fixture
                               (devnet-smoke-gate-engine-fixture case-name))
                             (store
                               (devnet-smoke-gate-field fixture "store"))
                             (config
                               (devnet-smoke-gate-field fixture "config"))
                             (parent-state
                               (devnet-smoke-gate-field fixture
                                                        "parentState"))
                             (parent-block
                               (devnet-smoke-gate-field fixture
                                                        "parentBlock"))
                             (child-block
                               (devnet-smoke-gate-field fixture
                                                        "childBlock"))
                             (payload
                               (devnet-smoke-gate-field fixture "payload"))
                             (payload-case
                               (devnet-smoke-gate-field fixture
                                                        "payloadCase"))
                             (expect
                               (devnet-smoke-gate-field fixture "expect"))
                             (node
                               (ethereum-lisp.cli:make-devnet-node
                                :genesis-path +devnet-cli-genesis-fixture+
                                :port 8551
                                :public-port 8545
                                :jwt-secret-path (namestring jwt-path)
                                :log-path log-file
                                :telemetry-sink telemetry-sink))
                  (recipient (fixture-address-field expect "recipient"))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (new-payload-output (make-string-output-stream))
                  (forkchoice-output (make-string-output-stream))
                  (block-number-output (make-string-output-stream))
                  (balance-output (make-string-output-stream))
                  (engine-requests
                    (list
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 21 payload))
                      new-payload-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        22 (block-hash child-block)
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      forkchoice-output)))
                  (public-requests
                    (list
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 31)
                             (cons "method" "eth_blockNumber")
                             (cons "params" '())))
                      block-number-output)
                     (cons
                      (json-encode
                       (engine-fixture-balance-request 32 recipient))
                      balance-output)))
                  (engine-served-count 0)
                  (engine-done-p nil)
                  (public-served-count 0))
             (devnet-cli-set-node-store-config node store config)
             (engine-payload-store-put-block
              store parent-block :state-available-p t)
             (commit-state-db-to-chain-store
              store (block-hash parent-block) parent-state)
             (let ((summary
                     (ethereum-lisp.cli:start-devnet-node-listeners
                      node
                      (make-engine-rpc-http-listener
                       :endpoint "engine"
                       :accept-function
                       (lambda ()
                         (when engine-requests
                           (destructuring-bind (body . output)
                               (pop engine-requests)
                             (make-engine-rpc-http-connection
                              :input-stream
                              (make-string-input-stream
                               (devnet-cli-json-rpc-http-request
                                body :token token))
                              :output-stream output
                              :close-function
                              (lambda ()
                                (incf engine-served-count)
                                (when (= engine-served-count 2)
                                  (setf engine-done-p t)))))))
                       :close-function (lambda () nil))
                      (make-engine-rpc-http-listener
                       :endpoint "public"
                       :accept-function
                       (lambda ()
                         (loop until engine-done-p
                               do (sleep 0.001))
                         (when public-requests
                           (destructuring-bind (body . output)
                               (pop public-requests)
                             (make-engine-rpc-http-connection
                              :input-stream
                              (make-string-input-stream
                               (devnet-cli-json-rpc-http-request body))
                              :output-stream output
                              :close-function
                              (lambda () (incf public-served-count))))))
                       :close-function (lambda () nil))
                      :max-connections 2
                      :on-listeners-ready
                      (lambda (engine-listener public-listener)
                        (let ((engine-endpoint
                                (engine-rpc-http-listener-endpoint
                                 engine-listener))
                              (rpc-endpoint
                                (engine-rpc-http-listener-endpoint
                                 public-listener)))
                          (when ready-file
                            (ethereum-lisp.cli::devnet-cli-write-ready-file
                             node
                             ready-file
                             :engine-endpoint engine-endpoint
                             :rpc-endpoint rpc-endpoint))
                          (when log-file
                            (ethereum-lisp.cli::devnet-cli-log-event
                             node
                             "devnet.ready"
                             :engine-endpoint engine-endpoint
                             :rpc-endpoint rpc-endpoint)))))))
               (when log-file
                 (ethereum-lisp.cli::devnet-cli-log-event
                  node
                  "devnet.shutdown"
                  :engine-endpoint "engine"
                  :rpc-endpoint "public"))
               (let* ((new-payload-response
                        (get-output-stream-string new-payload-output))
                      (forkchoice-response
                        (get-output-stream-string forkchoice-output))
                      (block-number-response
                        (get-output-stream-string block-number-output))
                      (balance-response
                        (get-output-stream-string balance-output))
                      (new-payload-rpc
                        (devnet-smoke-gate-rpc-body new-payload-response))
                      (forkchoice-rpc
                        (devnet-smoke-gate-rpc-body forkchoice-response))
                      (block-number-rpc
                        (devnet-smoke-gate-rpc-body block-number-response))
                      (balance-rpc
                        (devnet-smoke-gate-rpc-body balance-response))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (expected-hash
                        (hash32-to-hex (block-hash child-block)))
                      (expected-block-number
                        (fixture-object-field payload-case "number"))
                      (expected-balance
                        (fixture-object-field expect "recipientBalance"))
                      (actual-block-number
                        (fixture-object-field block-number-rpc "result"))
                      (actual-balance
                        (fixture-object-field balance-rpc "result")))
                 (devnet-smoke-gate-require
                  (= 2 (getf summary :engine-connections))
                  "Expected 2 Engine connections, got ~S"
                  (getf summary :engine-connections))
                 (devnet-smoke-gate-require
                  (= 2 (getf summary :public-connections))
                  "Expected 2 public RPC connections, got ~S"
                  (getf summary :public-connections))
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status new-payload-response))
                  "engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status forkchoice-response))
                  "engine_forkchoiceUpdatedV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status block-number-response))
                  "eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status balance-response))
                  "eth_getBalance HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field new-payload-result "status"))
                  "engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-hash
                           (fixture-object-field new-payload-result
                                                 "latestValidHash"))
                  "latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field forkchoice-status "status"))
                  "engine_forkchoiceUpdatedV2 status mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-block-number actual-block-number)
                  "eth_blockNumber mismatch: expected ~A got ~A"
                  expected-block-number
                  actual-block-number)
                 (devnet-smoke-gate-require
                  (string= expected-balance actual-balance)
                  "eth_getBalance mismatch: expected ~A got ~A"
                  expected-balance
                  actual-balance)
                 (list
                  (cons "status" "ok")
                  (cons "mode" "devnet-listener-boundary")
                  (cons "fixtureCase" case-name)
                  (cons "engineConnections"
                        (getf summary :engine-connections))
                  (cons "publicConnections"
                        (getf summary :public-connections))
                  (cons "totalConnections"
                        (getf summary :total-connections))
                  (cons "newPayloadStatus"
                        (fixture-object-field new-payload-result "status"))
                  (cons "latestValidHash" expected-hash)
                  (cons "forkchoiceStatus"
                        (fixture-object-field forkchoice-status "status"))
                  (cons "blockNumber" actual-block-number)
                  (cons "recipientBalance" actual-balance)
                  (cons "readyFile" (or ready-file :false))
                  (cons "logFile" (or log-file :false))))))))))
             (when ready-file
               (devnet-smoke-gate-verify-ready-file ready-file))
             (when log-file
               (devnet-smoke-gate-verify-log-file log-file))
             report))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (error "Devnet smoke gate requires SBCL threads"))

(defun devnet-smoke-gate-print-text (report)
  (format t "~&status=~A~%" (devnet-smoke-gate-field report "status"))
  (format t "mode=~A~%" (devnet-smoke-gate-field report "mode"))
  (format t "fixtureCase=~A~%" (devnet-smoke-gate-field report "fixtureCase"))
  (format t "engineConnections=~D~%"
          (devnet-smoke-gate-field report "engineConnections"))
  (format t "publicConnections=~D~%"
          (devnet-smoke-gate-field report "publicConnections"))
  (format t "totalConnections=~D~%"
          (devnet-smoke-gate-field report "totalConnections"))
  (format t "newPayloadStatus=~A~%"
          (devnet-smoke-gate-field report "newPayloadStatus"))
  (format t "latestValidHash=~A~%"
          (devnet-smoke-gate-field report "latestValidHash"))
  (format t "forkchoiceStatus=~A~%"
          (devnet-smoke-gate-field report "forkchoiceStatus"))
  (format t "blockNumber=~A~%" (devnet-smoke-gate-field report "blockNumber"))
  (format t "recipientBalance=~A~%"
          (devnet-smoke-gate-field report "recipientBalance"))
  (format t "readyFile=~A~%" (devnet-smoke-gate-field report "readyFile"))
  (format t "logFile=~A~%" (devnet-smoke-gate-field report "logFile")))

(defun devnet-smoke-gate-main ()
  (let* ((args (devnet-smoke-gate-arguments))
         (help-p (devnet-smoke-gate-help-p args))
         (json-p (devnet-smoke-gate-json-p args))
         (ready-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-ready-file-option+))
         (log-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-log-file-option+))
         (case-name (devnet-smoke-gate-fixture-case-name args)))
    (if help-p
        (devnet-smoke-gate-print-help)
        (let ((report (devnet-smoke-gate-run
                       case-name
                       :ready-file ready-file
                       :log-file log-file)))
          (if json-p
              (format t "~&~A~%" (json-encode report))
              (devnet-smoke-gate-print-text report))))))

(devnet-smoke-gate-main)
