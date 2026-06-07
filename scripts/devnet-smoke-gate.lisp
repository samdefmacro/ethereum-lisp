(defparameter *ethereum-lisp-devnet-smoke-gate-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defconstant +devnet-smoke-gate-early-help-flag+ "--help")

(defun devnet-smoke-gate-early-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun devnet-smoke-gate-early-help-p (args)
  (member +devnet-smoke-gate-early-help-flag+ args :test #'string=))

(defun devnet-smoke-gate-print-early-help ()
  (format t "~&Usage: sbcl --script scripts/devnet-smoke-gate.lisp -- [options] [FIXTURE-CASE]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --fixture-case NAME  Engine newPayloadV2 fixture case to import.~%")
  (format t "  --all-fixtures       Import every pinned Phase A newPayloadV2 smoke case.~%")
  (format t "  --ready-file PATH    Write devnet readiness JSON and verify it.~%")
  (format t "  --log-file PATH      Write devnet telemetry events and verify them.~%")
  (format t "  --database PATH      Export and verify a file-backed KV chain snapshot.~%")
  (format t "  --json               Print machine-readable JSON output.~%")
  (format t "  --help               Print this help.~%")
  (format t "~%"))

#+sbcl
(when (devnet-smoke-gate-early-help-p (devnet-smoke-gate-early-arguments))
  (devnet-smoke-gate-print-early-help)
  (sb-ext:exit :code 0))

(load (merge-pathnames "tests/load-tests.lisp"
                       *ethereum-lisp-devnet-smoke-gate-root*))

(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-devnet-smoke-gate-root*
  (symbol-value 'cl-user::*ethereum-lisp-devnet-smoke-gate-root*))

(defconstant +devnet-smoke-gate-json-flag+ "--json")
(defconstant +devnet-smoke-gate-help-flag+ "--help")
(defconstant +devnet-smoke-gate-fixture-case-option+ "--fixture-case")
(defconstant +devnet-smoke-gate-ready-file-option+ "--ready-file")
(defconstant +devnet-smoke-gate-log-file-option+ "--log-file")
(defconstant +devnet-smoke-gate-database-option+ "--database")
(defconstant +devnet-smoke-gate-all-fixtures-flag+ "--all-fixtures")
(defconstant +devnet-smoke-gate-default-fixture-case+
  "shanghai-one-transfer-with-withdrawal")
(defconstant +devnet-smoke-gate-eest-repository+
  "ethereum/execution-spec-tests")
(defconstant +devnet-smoke-gate-eest-release+ "v5.4.0")
(defconstant +devnet-smoke-gate-eest-tag-target+ "88e9fb8")
(defconstant +devnet-smoke-gate-eest-archive+ "fixtures_stable.tar.gz")

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

(defun devnet-smoke-gate-all-fixtures-p (args)
  (member +devnet-smoke-gate-all-fixtures-flag+ args :test #'string=))

(defun devnet-smoke-gate-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun devnet-smoke-gate-fixture-case-specified-p (args)
  (let ((specified-p nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((or (string= arg +devnet-smoke-gate-json-flag+)
                 (string= arg +devnet-smoke-gate-help-flag+)
                 (string= arg +devnet-smoke-gate-all-fixtures-flag+)))
            ((or (string= arg +devnet-smoke-gate-ready-file-option+)
                 (string= arg +devnet-smoke-gate-log-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+)
                 (string= arg +devnet-smoke-gate-fixture-case-option+))
             (when (and (string= arg +devnet-smoke-gate-fixture-case-option+)
                        args)
               (setf specified-p t))
             (when args
               (pop args)))
            ((devnet-smoke-gate-option-like-p arg))
            (t
             (setf specified-p t))))
    specified-p))

(defun devnet-smoke-gate-fixture-case-name (args)
  (let ((fixture-case nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((string= arg +devnet-smoke-gate-json-flag+))
            ((string= arg +devnet-smoke-gate-help-flag+))
            ((string= arg +devnet-smoke-gate-all-fixtures-flag+))
            ((or (string= arg +devnet-smoke-gate-ready-file-option+)
                 (string= arg +devnet-smoke-gate-log-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+))
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
                 (string= arg +devnet-smoke-gate-log-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+))
             (when args
               (pop args)))))
    path))

(defun devnet-smoke-gate-print-help ()
  (format t "~&Usage: sbcl --script scripts/devnet-smoke-gate.lisp -- [options] [FIXTURE-CASE]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --fixture-case NAME  Engine newPayloadV2 fixture case to import.~%")
  (format t "  --all-fixtures       Import every pinned Phase A newPayloadV2 smoke case.~%")
  (format t "  --ready-file PATH    Write devnet readiness JSON and verify it.~%")
  (format t "  --log-file PATH      Write devnet telemetry events and verify them.~%")
  (format t "  --database PATH      Export and verify a file-backed KV chain snapshot.~%")
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
            (namestring
             (devnet-smoke-gate-reference-path
              +engine-newpayload-v2-fixture-path+))
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

(defun devnet-smoke-gate-root-directory ()
  (truename
   (make-pathname :name nil
                  :type nil
                  :defaults *ethereum-lisp-devnet-smoke-gate-root*)))

(defun devnet-smoke-gate-reference-path (relative-path)
  (merge-pathnames relative-path (devnet-smoke-gate-root-directory)))

(defun devnet-smoke-gate-reference-client-object (name relative-path)
  (let ((path (devnet-smoke-gate-reference-path relative-path)))
    (cond
      ((not (probe-file path))
       (list
        (cons "name" name)
        (cons "status" "missing")
        (cons "path" (namestring path))
        (cons "commit" nil)))
      (t
       (multiple-value-bind (stdout stderr status)
           (uiop:run-program
            (list "git" "-C" (namestring path) "rev-parse" "HEAD")
            :output :string
            :error-output :string
            :ignore-error-status t)
         (declare (ignore stderr))
         (if (= 0 status)
             (list
              (cons "name" name)
              (cons "status" "ok")
              (cons "path" (namestring path))
              (cons "commit" (string-trim '(#\Space #\Tab #\Newline #\Return)
                                          stdout)))
             (list
              (cons "name" name)
              (cons "status" "unavailable")
              (cons "path" (namestring path))
              (cons "commit" nil))))))))

(defun devnet-smoke-gate-reference-clients ()
  (list
   (devnet-smoke-gate-reference-client-object "geth" "references/go-ethereum/")
   (devnet-smoke-gate-reference-client-object "nethermind" "references/nethermind/")
   (devnet-smoke-gate-reference-client-object "reth" "references/reth/")))

(defun devnet-smoke-gate-execution-spec-tests-source ()
  (list
   (cons "repository" +devnet-smoke-gate-eest-repository+)
   (cons "release" +devnet-smoke-gate-eest-release+)
   (cons "tagTarget" +devnet-smoke-gate-eest-tag-target+)
   (cons "archive" +devnet-smoke-gate-eest-archive+)))

(defun devnet-smoke-gate-add-run-metadata (report)
  (append
   (list
    (cons "executionSpecTests"
          (devnet-smoke-gate-execution-spec-tests-source))
    (cons "referenceClients" (devnet-smoke-gate-reference-clients)))
   report))

(defun devnet-smoke-gate-strip-run-metadata (report)
  (remove-if (lambda (entry)
               (member (car entry)
                       '("executionSpecTests" "referenceClients")
                       :test #'string=))
             report))

(defun devnet-smoke-gate-balance-target (expect)
  (cond
    ((fixture-field-present-p expect "recipient")
     (values (fixture-address-field expect "recipient")
             (fixture-object-field expect "recipientBalance")
             "recipientBalance"))
    ((fixture-field-present-p expect "contractAddress")
     (values (fixture-address-field expect "contractAddress")
             (fixture-object-field expect "contractBalance")
             "contractBalance"))
    (t
     (error "Devnet smoke gate fixture expect must contain recipient or contractAddress"))))

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

(defun devnet-smoke-gate-verify-database (path expected-block-number)
  (let* ((database (make-file-key-value-database path))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 0
            :database-path path))
         (summary (ethereum-lisp.cli:devnet-node-summary node)))
    (devnet-smoke-gate-require
     (< 0 (length (kv-chain-record-entries database :block)))
     "Database export did not write block records")
    (devnet-smoke-gate-require
     (< 0 (length (kv-chain-record-entries database :canonical-hash)))
     "Database export did not write canonical hash records")
    (devnet-smoke-gate-require
     (= (hex-to-quantity expected-block-number)
        (getf summary :head-number))
     "Database restored head mismatch: expected ~A got ~A"
     expected-block-number
     (quantity-to-hex (getf summary :head-number)))
    (devnet-smoke-gate-require
     (string= path (getf summary :database-path))
     "Database path missing from restored node summary")
    summary))

(defun devnet-smoke-gate-run
    (case-name &key ready-file log-file database-file)
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
                                :genesis-path
                                (namestring
                                 (devnet-smoke-gate-reference-path
                                  +devnet-cli-genesis-fixture+))
                                :port 8551
                                :public-port 8545
                                :jwt-secret-path (namestring jwt-path)
                                :log-path log-file
                                :database-path database-file
                                :telemetry-sink telemetry-sink))
                  (balance-address nil)
                  (expected-balance nil)
                  (balance-field nil)
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
                    (multiple-value-bind (address balance field)
                        (devnet-smoke-gate-balance-target expect)
                      (setf balance-address address
                            expected-balance balance
                            balance-field field)
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
                         (engine-fixture-balance-request 32 balance-address))
                        balance-output))))
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
               (when database-file
                 (ethereum-lisp.cli::devnet-node-export-database node))
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
                      (database-summary
                        (and database-file
                             (devnet-smoke-gate-verify-database
                              database-file expected-block-number)))
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
                 (devnet-smoke-gate-add-run-metadata
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
                  (cons "checkedBalanceAddress"
                        (address-to-hex balance-address))
                  (cons "checkedBalanceField" balance-field)
                  (cons "checkedBalance" actual-balance)
                  (cons "recipientBalance" actual-balance)
                  (cons "readyFile" (or ready-file :false))
                  (cons "logFile" (or log-file :false))
                  (cons "databaseFile" (or database-file :false))
                  (cons "databaseHeadNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :head-number))
                            :false)))))))))))
             (when ready-file
               (devnet-smoke-gate-verify-ready-file ready-file))
             (when log-file
               (devnet-smoke-gate-verify-log-file log-file))
             report))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (error "Devnet smoke gate requires SBCL threads"))

(defun devnet-smoke-gate-sanitize-path-component (value)
  (coerce
   (map 'list
        (lambda (char)
          (if (or (alphanumericp char)
                  (member char '(#\- #\_) :test #'char=))
              char
              #\_))
        value)
   'string))

(defun devnet-smoke-gate-case-database-file (database-file case-name)
  (when database-file
    (let* ((pathname (pathname database-file))
           (name (or (pathname-name pathname) "devnet-chain"))
           (type (pathname-type pathname))
           (case-component
             (devnet-smoke-gate-sanitize-path-component case-name)))
      (namestring
       (make-pathname
        :name (format nil "~A-~A" name case-component)
        :type type
        :defaults pathname)))))

(defun devnet-smoke-gate-run-all (case-names &key database-file)
  (let* ((reports
           (mapcar (lambda (case-name)
                     (devnet-smoke-gate-strip-run-metadata
                      (devnet-smoke-gate-run
                       case-name
                       :database-file
                       (devnet-smoke-gate-case-database-file
                        database-file case-name))))
                   case-names))
         (engine-connections
           (reduce #'+ reports
                   :key (lambda (report)
                          (devnet-smoke-gate-field report
                                                   "engineConnections"))
                   :initial-value 0))
         (public-connections
           (reduce #'+ reports
                   :key (lambda (report)
                          (devnet-smoke-gate-field report
                                                   "publicConnections"))
                   :initial-value 0)))
    (devnet-smoke-gate-require
     (= (length case-names) (length reports))
     "Devnet smoke gate suite case count mismatch")
    (when database-file
      (dolist (report reports)
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field report "databaseHeadNumber"))
         "Devnet smoke gate suite database head mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))))
    (devnet-smoke-gate-add-run-metadata
     (list
     (cons "status" "ok")
     (cons "mode" "devnet-listener-boundary-suite")
     (cons "caseCount" (length reports))
     (cons "fixtureCases" case-names)
     (cons "databaseFile" (or database-file :false))
     (cons "databaseCaseCount" (if database-file (length reports) 0))
     (cons "engineConnections" engine-connections)
     (cons "publicConnections" public-connections)
     (cons "totalConnections" (+ engine-connections public-connections))
     (cons "cases" reports)))))

(defun devnet-smoke-gate-suite-report-p (report)
  (string= "devnet-listener-boundary-suite"
           (or (devnet-smoke-gate-field report "mode") "")))

(defun devnet-smoke-gate-print-text (report)
  (format t "~&status=~A~%" (devnet-smoke-gate-field report "status"))
  (format t "mode=~A~%" (devnet-smoke-gate-field report "mode"))
  (let ((execution-spec-tests
          (devnet-smoke-gate-field report "executionSpecTests"))
        (reference-clients
          (devnet-smoke-gate-field report "referenceClients")))
    (format t "executionSpecTestsRepository=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "repository"))
    (format t "executionSpecTestsRelease=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "release"))
    (format t "executionSpecTestsTagTarget=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "tagTarget"))
    (format t "executionSpecTestsArchive=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "archive"))
    (dolist (client reference-clients)
      (format t "referenceClient[~A]=~A"
              (devnet-smoke-gate-field client "name")
              (devnet-smoke-gate-field client "status"))
      (when (devnet-smoke-gate-field client "commit")
        (format t ":~A" (devnet-smoke-gate-field client "commit")))
      (format t "~%")))
  (when (devnet-smoke-gate-suite-report-p report)
    (format t "caseCount=~D~%" (devnet-smoke-gate-field report "caseCount"))
    (format t "databaseFile=~A~%"
            (devnet-smoke-gate-field report "databaseFile"))
    (format t "databaseCaseCount=~D~%"
            (devnet-smoke-gate-field report "databaseCaseCount")))
  (unless (devnet-smoke-gate-suite-report-p report)
    (format t "fixtureCase=~A~%"
            (devnet-smoke-gate-field report "fixtureCase")))
  (format t "engineConnections=~D~%"
          (devnet-smoke-gate-field report "engineConnections"))
  (format t "publicConnections=~D~%"
          (devnet-smoke-gate-field report "publicConnections"))
  (format t "totalConnections=~D~%"
          (devnet-smoke-gate-field report "totalConnections"))
  (if (devnet-smoke-gate-suite-report-p report)
      (dolist (case-report (devnet-smoke-gate-field report "cases"))
        (format t "case=~A status=~A blockNumber=~A checkedBalance=~A~%"
                (devnet-smoke-gate-field case-report "fixtureCase")
                (devnet-smoke-gate-field case-report "newPayloadStatus")
                (devnet-smoke-gate-field case-report "blockNumber")
                (devnet-smoke-gate-field case-report "checkedBalance")))
      (progn
        (format t "newPayloadStatus=~A~%"
                (devnet-smoke-gate-field report "newPayloadStatus"))
        (format t "latestValidHash=~A~%"
                (devnet-smoke-gate-field report "latestValidHash"))
        (format t "forkchoiceStatus=~A~%"
                (devnet-smoke-gate-field report "forkchoiceStatus"))
        (format t "blockNumber=~A~%"
                (devnet-smoke-gate-field report "blockNumber"))
        (format t "checkedBalanceAddress=~A~%"
                (devnet-smoke-gate-field report "checkedBalanceAddress"))
        (format t "checkedBalanceField=~A~%"
                (devnet-smoke-gate-field report "checkedBalanceField"))
        (format t "checkedBalance=~A~%"
                (devnet-smoke-gate-field report "checkedBalance"))
        (format t "recipientBalance=~A~%"
                (devnet-smoke-gate-field report "recipientBalance"))
        (format t "readyFile=~A~%" (devnet-smoke-gate-field report "readyFile"))
        (format t "logFile=~A~%" (devnet-smoke-gate-field report "logFile"))
        (format t "databaseFile=~A~%"
                (devnet-smoke-gate-field report "databaseFile"))
        (format t "databaseHeadNumber=~A~%"
                (devnet-smoke-gate-field report "databaseHeadNumber")))))

(defun devnet-smoke-gate-main ()
  (let* ((args (devnet-smoke-gate-arguments))
         (help-p (devnet-smoke-gate-help-p args))
         (json-p (devnet-smoke-gate-json-p args))
         (all-fixtures-p (devnet-smoke-gate-all-fixtures-p args))
         (ready-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-ready-file-option+))
         (log-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-log-file-option+))
         (database-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-database-option+))
         (case-name (devnet-smoke-gate-fixture-case-name args)))
    (if help-p
        (devnet-smoke-gate-print-help)
        (let ((report
                (if all-fixtures-p
                    (progn
                      (when (devnet-smoke-gate-fixture-case-specified-p args)
                        (error "~A cannot be combined with a fixture case"
                               +devnet-smoke-gate-all-fixtures-flag+))
                      (when (or ready-file log-file)
                        (error "~A cannot be combined with --ready-file or --log-file"
                               +devnet-smoke-gate-all-fixtures-flag+))
                      (devnet-smoke-gate-run-all
                       +engine-newpayload-v2-smoke-case-names+
                       :database-file database-file))
                    (devnet-smoke-gate-run
                     case-name
                     :ready-file ready-file
                     :log-file log-file
                     :database-file database-file))))
          (if json-p
              (format t "~&~A~%" (json-encode report))
              (devnet-smoke-gate-print-text report))))))

(devnet-smoke-gate-main)
