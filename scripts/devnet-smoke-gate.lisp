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

(defun devnet-smoke-gate-verify-restored-public-rpc
    (node expected-block-number balance-address expected-balance
     transaction-hash block-hash)
  #+sbcl
  (let ((block-number-output (make-string-output-stream))
        (balance-output (make-string-output-stream))
        (receipt-output (make-string-output-stream))
        (block-output (make-string-output-stream))
        (block-by-number-output (make-string-output-stream))
        (transaction-output (make-string-output-stream))
        (block-receipts-output (make-string-output-stream))
        (public-requests nil))
    (setf public-requests
          (list
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 41)
                   (cons "method" "eth_blockNumber")
                   (cons "params" '())))
            block-number-output)
           (cons
            (json-encode
             (engine-fixture-balance-request 42 balance-address))
            balance-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 43)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            receipt-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 44)
                   (cons "method" "eth_getBlockByHash")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        :false))))
            block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 45)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list expected-block-number :false))))
            block-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 46)
                   (cons "method" "eth_getTransactionByHash")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            transaction-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 47)
                   (cons "method" "eth_getBlockReceipts")
                   (cons "params" (list (hash32-to-hex block-hash)))))
            block-receipts-output)))
    (let ((summary
            (ethereum-lisp.cli:start-devnet-node-listeners
             node
             (make-engine-rpc-http-listener
              :endpoint "restored-engine"
              :accept-function (lambda () nil)
              :close-function (lambda () nil))
             (make-engine-rpc-http-listener
              :endpoint "restored-public"
              :accept-function
              (lambda ()
                (when public-requests
                  (destructuring-bind (body . output)
                      (pop public-requests)
                    (make-engine-rpc-http-connection
                     :input-stream
                     (make-string-input-stream
                      (devnet-cli-json-rpc-http-request body))
                     :output-stream output
                     :close-function (lambda () nil)))))
              :close-function (lambda () nil))
             :max-connections 7)))
      (let* ((block-number-response
               (get-output-stream-string block-number-output))
             (balance-response
               (get-output-stream-string balance-output))
             (receipt-response
               (get-output-stream-string receipt-output))
             (block-response
               (get-output-stream-string block-output))
             (block-by-number-response
               (get-output-stream-string block-by-number-output))
             (transaction-response
               (get-output-stream-string transaction-output))
             (block-receipts-response
               (get-output-stream-string block-receipts-output))
             (block-number-rpc
               (devnet-smoke-gate-rpc-body block-number-response))
             (balance-rpc
               (devnet-smoke-gate-rpc-body balance-response))
             (receipt-rpc
               (devnet-smoke-gate-rpc-body receipt-response))
             (block-rpc
               (devnet-smoke-gate-rpc-body block-response))
             (block-by-number-rpc
               (devnet-smoke-gate-rpc-body block-by-number-response))
             (transaction-rpc
               (devnet-smoke-gate-rpc-body transaction-response))
             (block-receipts-rpc
               (devnet-smoke-gate-rpc-body block-receipts-response))
             (actual-block-number
               (fixture-object-field block-number-rpc "result"))
             (actual-balance
               (fixture-object-field balance-rpc "result"))
             (actual-receipt
               (fixture-object-field receipt-rpc "result"))
             (actual-receipt-transaction-hash
               (fixture-object-field actual-receipt "transactionHash"))
             (actual-receipt-block-number
               (fixture-object-field actual-receipt "blockNumber"))
             (actual-receipt-block-hash
               (fixture-object-field actual-receipt "blockHash"))
             (actual-block
               (fixture-object-field block-rpc "result"))
             (actual-block-hash
               (fixture-object-field actual-block "hash"))
             (actual-block-by-hash-number
               (fixture-object-field actual-block "number"))
             (actual-block-transactions
               (fixture-object-field actual-block "transactions"))
             (actual-block-transaction-hash
               (first actual-block-transactions))
             (actual-block-by-number
               (fixture-object-field block-by-number-rpc "result"))
             (actual-block-by-number-hash
               (fixture-object-field actual-block-by-number "hash"))
             (actual-block-by-number-number
               (fixture-object-field actual-block-by-number "number"))
             (actual-block-by-number-transactions
               (fixture-object-field actual-block-by-number "transactions"))
             (actual-block-by-number-transaction-hash
               (first actual-block-by-number-transactions))
             (actual-transaction
               (fixture-object-field transaction-rpc "result"))
             (actual-transaction-hash
               (fixture-object-field actual-transaction "hash"))
             (actual-transaction-block-hash
               (fixture-object-field actual-transaction "blockHash"))
             (actual-transaction-block-number
               (fixture-object-field actual-transaction "blockNumber"))
             (actual-block-receipts
               (fixture-object-field block-receipts-rpc "result"))
             (actual-block-receipt
               (first actual-block-receipts))
             (actual-block-receipt-transaction-hash
               (fixture-object-field actual-block-receipt "transactionHash"))
             (actual-block-receipt-block-hash
               (fixture-object-field actual-block-receipt "blockHash"))
             (actual-block-receipt-block-number
               (fixture-object-field actual-block-receipt "blockNumber")))
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Restored database verification should not use Engine RPC")
        (devnet-smoke-gate-require
         (= 7 (getf summary :public-connections))
         "Restored database verification expected 7 public RPC connections, got ~S"
         (getf summary :public-connections))
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-number-response))
         "Restored eth_blockNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status balance-response))
         "Restored eth_getBalance HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status receipt-response))
         "Restored eth_getTransactionReceipt HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-response))
         "Restored eth_getBlockByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-by-number-response))
         "Restored eth_getBlockByNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-response))
         "Restored eth_getTransactionByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-receipts-response))
         "Restored eth_getBlockReceipts HTTP status mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-number)
         "Restored eth_blockNumber mismatch: expected ~A got ~A"
         expected-block-number
         actual-block-number)
        (devnet-smoke-gate-require
         (string= expected-balance actual-balance)
         "Restored eth_getBalance mismatch: expected ~A got ~A"
         expected-balance
         actual-balance)
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-receipt-transaction-hash)
         "Restored eth_getTransactionReceipt hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-receipt-block-number)
         "Restored eth_getTransactionReceipt block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash) actual-receipt-block-hash)
         "Restored eth_getTransactionReceipt block hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash) actual-block-hash)
         "Restored eth_getBlockByHash hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-by-hash-number)
         "Restored eth_getBlockByHash block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-block-transaction-hash)
         "Restored eth_getBlockByHash transaction list mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash) actual-block-by-number-hash)
         "Restored eth_getBlockByNumber hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-by-number-number)
         "Restored eth_getBlockByNumber block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-block-by-number-transaction-hash)
         "Restored eth_getBlockByNumber transaction list mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash) actual-transaction-hash)
         "Restored eth_getTransactionByHash hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-transaction-block-hash)
         "Restored eth_getTransactionByHash block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-transaction-block-number)
         "Restored eth_getTransactionByHash block number mismatch")
        (devnet-smoke-gate-require
         (= 1 (length actual-block-receipts))
         "Restored eth_getBlockReceipts expected 1 receipt, got ~S"
         (length actual-block-receipts))
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-block-receipt-transaction-hash)
         "Restored eth_getBlockReceipts transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-block-receipt-block-hash)
         "Restored eth_getBlockReceipts block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-receipt-block-number)
         "Restored eth_getBlockReceipts block number mismatch")
        (list :block-number actual-block-number
              :balance actual-balance
              :receipt-transaction-hash actual-receipt-transaction-hash
              :receipt-block-number actual-receipt-block-number
              :block-hash actual-block-hash
              :block-by-hash-number actual-block-by-hash-number
              :block-transaction-hash actual-block-transaction-hash
              :block-by-number-hash actual-block-by-number-hash
              :block-by-number-number actual-block-by-number-number
              :block-by-number-transaction-hash
              actual-block-by-number-transaction-hash
              :transaction-hash actual-transaction-hash
              :transaction-block-hash actual-transaction-block-hash
              :transaction-block-number actual-transaction-block-number
              :block-receipts-count (length actual-block-receipts)
              :block-receipt-transaction-hash
              actual-block-receipt-transaction-hash
              :block-receipt-block-hash actual-block-receipt-block-hash
              :block-receipt-block-number actual-block-receipt-block-number
              :public-connections (getf summary :public-connections)))))
  #-sbcl
  (error "Restored devnet public RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-database
    (path expected-block-number balance-address expected-balance
     transaction-hash block-hash)
  (let* ((database (make-file-key-value-database path))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 0
            :database-path path))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (public-rpc-summary
           (devnet-smoke-gate-verify-restored-public-rpc
            node
            expected-block-number
            balance-address
            expected-balance
            transaction-hash
            block-hash)))
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
    (append summary
            (list :rpc-block-number
                  (getf public-rpc-summary :block-number)
                  :rpc-balance
                  (getf public-rpc-summary :balance)
                  :rpc-receipt-transaction-hash
                  (getf public-rpc-summary :receipt-transaction-hash)
                  :rpc-receipt-block-number
                  (getf public-rpc-summary :receipt-block-number)
                  :rpc-block-hash
                  (getf public-rpc-summary :block-hash)
                  :rpc-block-by-hash-number
                  (getf public-rpc-summary :block-by-hash-number)
                  :rpc-block-transaction-hash
                  (getf public-rpc-summary :block-transaction-hash)
                  :rpc-block-by-number-hash
                  (getf public-rpc-summary :block-by-number-hash)
                  :rpc-block-by-number-number
                  (getf public-rpc-summary :block-by-number-number)
                  :rpc-block-by-number-transaction-hash
                  (getf public-rpc-summary
                        :block-by-number-transaction-hash)
                  :rpc-transaction-hash
                  (getf public-rpc-summary :transaction-hash)
                  :rpc-transaction-block-hash
                  (getf public-rpc-summary :transaction-block-hash)
                  :rpc-transaction-block-number
                  (getf public-rpc-summary :transaction-block-number)
                  :rpc-block-receipts-count
                  (getf public-rpc-summary :block-receipts-count)
                  :rpc-block-receipt-transaction-hash
                  (getf public-rpc-summary :block-receipt-transaction-hash)
                  :rpc-block-receipt-block-hash
                  (getf public-rpc-summary :block-receipt-block-hash)
                  :rpc-block-receipt-block-number
                  (getf public-rpc-summary :block-receipt-block-number)
                  :rpc-public-connections
                  (getf public-rpc-summary :public-connections)))))

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
                  (expected-transaction-hash
                    (transaction-hash (first (block-transactions child-block))))
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
                              database-file
                              expected-block-number
                              balance-address
                              expected-balance
                              expected-transaction-hash
                              (block-hash child-block))))
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
                            :false))
                  (cons "databaseRpcBlockNumber"
                        (if database-summary
                            (getf database-summary :rpc-block-number)
                            :false))
                  (cons "databaseRpcBalance"
                        (if database-summary
                            (getf database-summary :rpc-balance)
                            :false))
                  (cons "databaseRpcReceiptTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-receipt-transaction-hash)
                            :false))
                  (cons "databaseRpcReceiptBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-receipt-block-number)
                            :false))
                  (cons "databaseRpcBlockHash"
                        (if database-summary
                            (getf database-summary :rpc-block-hash)
                            :false))
                  (cons "databaseRpcBlockByHashNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-hash-number)
                            :false))
                  (cons "databaseRpcBlockTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-transaction-hash)
                            :false))
                  (cons "databaseRpcBlockByNumberHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-number-hash)
                            :false))
                  (cons "databaseRpcBlockByNumberNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-number-number)
                            :false))
                  (cons "databaseRpcBlockByNumberTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-number-transaction-hash)
                            :false))
                  (cons "databaseRpcTransactionHash"
                        (if database-summary
                            (getf database-summary :rpc-transaction-hash)
                            :false))
                  (cons "databaseRpcTransactionBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-block-hash)
                            :false))
                  (cons "databaseRpcTransactionBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-block-number)
                            :false))
                  (cons "databaseRpcBlockReceiptsCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipts-count)
                            :false))
                  (cons "databaseRpcBlockReceiptTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipt-transaction-hash)
                            :false))
                  (cons "databaseRpcBlockReceiptBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipt-block-hash)
                            :false))
                  (cons "databaseRpcBlockReceiptBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipt-block-number)
                            :false))
                  (cons "databaseRpcPublicConnections"
                        (if database-summary
                            (getf database-summary :rpc-public-connections)
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

(defun devnet-smoke-gate-case-path (path case-name &key default-name)
  (when path
    (let* ((pathname (pathname path))
           (name (or (pathname-name pathname) "devnet-chain"))
           (type (pathname-type pathname))
           (case-component
             (devnet-smoke-gate-sanitize-path-component case-name)))
      (namestring
       (make-pathname
        :name (format nil "~A-~A"
                      (or name default-name "devnet-artifact")
                      case-component)
        :type type
        :defaults pathname)))))

(defun devnet-smoke-gate-run-all
    (case-names &key ready-file log-file database-file)
  (let* ((reports
           (mapcar (lambda (case-name)
                     (devnet-smoke-gate-strip-run-metadata
                      (devnet-smoke-gate-run
                       case-name
                       :ready-file
                       (devnet-smoke-gate-case-path
                        ready-file case-name :default-name "ready")
                       :log-file
                       (devnet-smoke-gate-case-path
                        log-file case-name :default-name "devnet")
                       :database-file
                       (devnet-smoke-gate-case-path
                        database-file case-name
                        :default-name "devnet-chain"))))
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
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcReceiptBlockNumber"))
         "Devnet smoke gate suite restored receipt block mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcBlockByHashNumber"))
         "Devnet smoke gate suite restored block-by-hash number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockByNumberNumber"))
         "Devnet smoke gate suite restored block-by-number number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionBlockNumber"))
         "Devnet smoke gate suite restored transaction block mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockReceiptBlockNumber"))
         "Devnet smoke gate suite restored block receipt number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= 1 (devnet-smoke-gate-field report
                                       "databaseRpcBlockReceiptsCount"))
         "Devnet smoke gate suite restored block receipts count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))))
    (devnet-smoke-gate-add-run-metadata
     (list
     (cons "status" "ok")
     (cons "mode" "devnet-listener-boundary-suite")
     (cons "caseCount" (length reports))
     (cons "fixtureCases" case-names)
     (cons "readyFile" (or ready-file :false))
     (cons "readyCaseCount" (if ready-file (length reports) 0))
     (cons "logFile" (or log-file :false))
     (cons "logCaseCount" (if log-file (length reports) 0))
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
    (format t "readyFile=~A~%"
            (devnet-smoke-gate-field report "readyFile"))
    (format t "readyCaseCount=~D~%"
            (devnet-smoke-gate-field report "readyCaseCount"))
    (format t "logFile=~A~%"
            (devnet-smoke-gate-field report "logFile"))
    (format t "logCaseCount=~D~%"
            (devnet-smoke-gate-field report "logCaseCount"))
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
                (devnet-smoke-gate-field report "databaseHeadNumber"))
        (format t "databaseRpcBlockNumber=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBlockNumber"))
        (format t "databaseRpcBalance=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBalance"))
        (format t "databaseRpcReceiptTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcReceiptTransactionHash"))
        (format t "databaseRpcReceiptBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcReceiptBlockNumber"))
        (format t "databaseRpcBlockHash=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBlockHash"))
        (format t "databaseRpcBlockByHashNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByHashNumber"))
        (format t "databaseRpcBlockTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockTransactionHash"))
        (format t "databaseRpcBlockByNumberHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByNumberHash"))
        (format t "databaseRpcBlockByNumberNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByNumberNumber"))
        (format t "databaseRpcBlockByNumberTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByNumberTransactionHash"))
        (format t "databaseRpcTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionHash"))
        (format t "databaseRpcTransactionBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionBlockHash"))
        (format t "databaseRpcTransactionBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionBlockNumber"))
        (format t "databaseRpcBlockReceiptsCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptsCount"))
        (format t "databaseRpcBlockReceiptTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptTransactionHash"))
        (format t "databaseRpcBlockReceiptBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptBlockHash"))
        (format t "databaseRpcBlockReceiptBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptBlockNumber")))))

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
                      (devnet-smoke-gate-run-all
                       +engine-newpayload-v2-smoke-case-names+
                       :ready-file ready-file
                       :log-file log-file
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
