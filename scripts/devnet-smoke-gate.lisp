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
  (format t "  --pid-file PATH      Write the devnet process id and verify it.~%")
  (format t "  --database PATH      Export and verify a file-backed KV chain snapshot.~%")
  (format t "  --prune-state-before NUMBER~%")
  (format t "                       Prune retained state before NUMBER when exporting --database.~%")
  (format t "  --json               Print machine-readable JSON output.~%")
  (format t "  --help               Print this help.~%")
  (format t "~%")
  (format t "Reference client roots: ETHEREUM_LISP_GETH_ROOT, ~
ETHEREUM_LISP_NETHERMIND_ROOT, ETHEREUM_LISP_RETH_ROOT override ~
references/ checkouts.~%")
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
(defconstant +devnet-smoke-gate-pid-file-option+ "--pid-file")
(defconstant +devnet-smoke-gate-database-option+ "--database")
(defconstant +devnet-smoke-gate-prune-state-before-option+
  "--prune-state-before")
(defconstant +devnet-smoke-gate-all-fixtures-flag+ "--all-fixtures")
(defconstant +devnet-smoke-gate-default-fixture-case+
  "shanghai-one-transfer-with-withdrawal")
(defconstant +devnet-smoke-gate-eest-repository+
  "ethereum/execution-spec-tests")
(defconstant +devnet-smoke-gate-eest-release+ "v5.4.0")
(defconstant +devnet-smoke-gate-eest-tag-target+ "88e9fb8")
(defconstant +devnet-smoke-gate-eest-archive+ "fixtures_stable.tar.gz")
(defconstant +devnet-smoke-gate-simulation-gas+ "0x186a0")
(defconstant +devnet-smoke-gate-txpool-private-key+ 1)
(defconstant +devnet-smoke-gate-txpool-balance+ 1000000000000000000)
(defconstant +devnet-smoke-gate-txpool-gas-price+ 200)
(defconstant +devnet-smoke-gate-txpool-basefee-gas-price+ 0)
(defconstant +devnet-smoke-gate-txpool-gas-limit+ 21000)
(defconstant +devnet-smoke-gate-txpool-value+ 1)
(defconstant +devnet-smoke-gate-txpool-recipient+
  "0x0000000000000000000000000000000000003001")

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
                 (string= arg +devnet-smoke-gate-pid-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+)
                 (string= arg +devnet-smoke-gate-prune-state-before-option+)
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
                 (string= arg +devnet-smoke-gate-pid-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+)
                 (string= arg +devnet-smoke-gate-prune-state-before-option+))
             (unless args
               (error "~A requires a value" arg))
             (let ((value (pop args)))
               (when (and (not (string= arg
                                         +devnet-smoke-gate-prune-state-before-option+))
                          (devnet-smoke-gate-option-like-p value))
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
                 (string= arg +devnet-smoke-gate-pid-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+)
                 (string= arg +devnet-smoke-gate-prune-state-before-option+))
             (when args
               (pop args)))))
    path))

(defun devnet-smoke-gate-non-negative-integer-option (args option)
  (let ((integer nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((string= arg option)
             (when integer
               (error "Only one ~A option is supported" option))
             (unless args
               (error "~A requires a value" option))
             (let ((value (pop args)))
               (handler-case
                   (setf integer (parse-integer value :junk-allowed nil))
                 (error ()
                   (error "~A requires an integer value" option)))
               (when (minusp integer)
                 (error "~A must be non-negative" option))))
            ((string= arg +devnet-smoke-gate-fixture-case-option+)
             (when args
               (pop args)))
            ((or (string= arg +devnet-smoke-gate-ready-file-option+)
                 (string= arg +devnet-smoke-gate-log-file-option+)
                 (string= arg +devnet-smoke-gate-pid-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+))
             (when args
               (pop args)))))
    integer))

(defun devnet-smoke-gate-print-help ()
  (format t "~&Usage: sbcl --script scripts/devnet-smoke-gate.lisp -- [options] [FIXTURE-CASE]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --fixture-case NAME  Engine newPayloadV2 fixture case to import.~%")
  (format t "  --all-fixtures       Import every pinned Phase A newPayloadV2 smoke case.~%")
  (format t "  --ready-file PATH    Write devnet readiness JSON and verify it.~%")
  (format t "  --log-file PATH      Write devnet telemetry events and verify them.~%")
  (format t "  --pid-file PATH      Write the devnet process id and verify it.~%")
  (format t "  --database PATH      Export and verify a file-backed KV chain snapshot.~%")
  (format t "  --prune-state-before NUMBER~%")
  (format t "                       Prune retained state before NUMBER when exporting --database.~%")
  (format t "  --json               Print machine-readable JSON output.~%")
  (format t "  --help               Print this help.~%")
  (format t "~%")
  (format t "Reference client roots: ETHEREUM_LISP_GETH_ROOT, ~
ETHEREUM_LISP_NETHERMIND_ROOT, ETHEREUM_LISP_RETH_ROOT override ~
references/ checkouts.~%")
  (format t "Default fixture case: ~A~%"
          +devnet-smoke-gate-default-fixture-case+))

(defun devnet-smoke-gate-require (condition format-control &rest args)
  (unless condition
    (apply #'error format-control args)))

(defun devnet-smoke-gate-pruned-state-error-messages ()
  '("eth_getBalance state is not available"
    "eth_getTransactionCount state is not available"
    "eth_getCode state is not available"
    "eth_getStorageAt state is not available"
    "eth_getProof state is not available"
    "eth_call state is not available"
    "eth_estimateGas state is not available"
    "eth_createAccessList state is not available"))

(defun devnet-smoke-gate-noncanonical-state-error-messages ()
  '("eth_getBalance block hash is not canonical"
    "eth_getTransactionCount block hash is not canonical"
    "eth_getCode block hash is not canonical"
    "eth_getStorageAt block hash is not canonical"
    "eth_getProof block hash is not canonical"
    "eth_call block hash is not canonical"
    "eth_estimateGas block hash is not canonical"
    "eth_createAccessList block hash is not canonical"))

(defun devnet-smoke-gate-false-p (value)
  (or (null value) (eq value :false)))

(defun devnet-smoke-gate-report-pruned-state-covered-p
    (report state-prune-before)
  (and state-prune-before
       (< (hex-to-quantity
           (devnet-smoke-gate-field report "safeBlockNumber"))
          state-prune-before)))

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

(defun devnet-smoke-gate-txpool-sender-address ()
  (fixture-private-key-address +devnet-smoke-gate-txpool-private-key+))

(defun devnet-smoke-gate-ensure-txpool-account (state)
  (let ((address (devnet-smoke-gate-txpool-sender-address)))
    (unless (state-db-get-account state address)
      (state-db-set-account
       state
       address
       (make-state-account
        :nonce 0
        :balance +devnet-smoke-gate-txpool-balance+)))
    address))

(defun devnet-smoke-gate-txpool-transaction
    (config nonce gas-price)
  (let ((transaction
          (make-legacy-transaction
           :nonce nonce
           :gas-price gas-price
           :gas-limit +devnet-smoke-gate-txpool-gas-limit+
           :to (address-from-hex +devnet-smoke-gate-txpool-recipient+)
           :value +devnet-smoke-gate-txpool-value+)))
    (fixture-sign-legacy-transaction
     transaction
     +devnet-smoke-gate-txpool-private-key+
     (chain-config-chain-id config))))

(defun devnet-smoke-gate-make-restored-node
    (path config &key (port 0) (public-port 0) jwt-secret-path)
  (let ((node
          (ethereum-lisp.cli:make-devnet-node
           :genesis-path
           (namestring
            (devnet-smoke-gate-reference-path
             +devnet-cli-genesis-fixture+))
           :port port
           :public-port public-port
           :jwt-secret-path jwt-secret-path)))
    (chain-store-import-from-kv
     (ethereum-lisp.cli:devnet-node-store node)
     (make-file-key-value-database path)
     :expected-chain-id (chain-config-chain-id config))
    (devnet-cli-set-node-store-config
     node
     (ethereum-lisp.cli:devnet-node-store node)
     config)
    (setf (ethereum-lisp.cli::devnet-node-database-path node) path)
    node))

(defun devnet-smoke-gate-txpool-transactions
    (state config sender-address)
  (let* ((account (state-db-get-account state sender-address))
         (nonce (state-account-nonce account)))
    (list
     (cons "pending"
           (devnet-smoke-gate-txpool-transaction
            config nonce +devnet-smoke-gate-txpool-gas-price+))
     (cons "basefee"
           (devnet-smoke-gate-txpool-transaction
            config
            (1+ nonce)
            +devnet-smoke-gate-txpool-basefee-gas-price+))
     (cons "queued"
           (devnet-smoke-gate-txpool-transaction
            config
            (+ nonce 2)
            +devnet-smoke-gate-txpool-gas-price+)))))

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
         (txpool-sender
           (devnet-smoke-gate-ensure-txpool-account parent-state))
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
         (side-block
           (devnet-smoke-gate-side-sibling-block
            parent-block parent-state config payload-case withdrawals
            fee-recipient))
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data child-block)))
         (side-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data side-block)))
         (txpool-transactions
           (devnet-smoke-gate-txpool-transactions
            child-state
            config
            txpool-sender)))
    (list
     (cons "case" case)
     (cons "store" store)
     (cons "config" config)
     (cons "parentState" parent-state)
     (cons "parentBlock" parent-block)
     (cons "childBlock" child-block)
     (cons "payload" payload)
     (cons "sideBlock" side-block)
     (cons "sidePayload" side-payload)
     (cons "txpoolTransactions" txpool-transactions)
     (cons "pendingTransaction"
           (cdr (assoc "pending" txpool-transactions :test #'string=)))
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

(defun devnet-smoke-gate-reference-client-path (relative-path env-var)
  (let ((override (and env-var (uiop:getenv env-var))))
    (if (and override (plusp (length override)))
        (uiop:ensure-directory-pathname
         (merge-pathnames override (devnet-smoke-gate-root-directory)))
        (devnet-smoke-gate-reference-path relative-path))))

(defun devnet-smoke-gate-reference-client-object
    (name env-var relative-path)
  (let ((path (devnet-smoke-gate-reference-client-path
               relative-path
               env-var)))
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
   (devnet-smoke-gate-reference-client-object
    "geth" "ETHEREUM_LISP_GETH_ROOT" "references/go-ethereum/")
   (devnet-smoke-gate-reference-client-object
    "nethermind" "ETHEREUM_LISP_NETHERMIND_ROOT" "references/nethermind/")
   (devnet-smoke-gate-reference-client-object
    "reth" "ETHEREUM_LISP_RETH_ROOT" "references/reth/")))

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

(defun devnet-smoke-gate-balance-targets (expect)
  (cond
    ((fixture-field-present-p expect "recipients")
     (loop for recipient in (fixture-object-field expect "recipients")
           for balance in (fixture-object-field expect "recipientBalances")
           collect (list :address (address-from-hex recipient)
                         :balance balance
                         :field "recipientBalance")))
    (t
     (multiple-value-bind (address balance field)
         (devnet-smoke-gate-balance-target expect)
       (list (list :address address :balance balance :field field))))))

(defun devnet-smoke-gate-checkpoint-balance-targets
    (state balance-targets)
  (loop for target in balance-targets
        for address = (getf target :address)
        collect (list :address address
                      :balance (quantity-to-hex
                                (fixture-account-balance state address))
                      :field (getf target :field))))

(defun devnet-smoke-gate-transaction-checks (block)
  (loop for transaction in (block-transactions block)
        collect (list :hash (transaction-hash transaction)
                      :raw (bytes-to-hex
                            (transaction-encoding transaction)))))

(defun devnet-smoke-gate-log-targets (expect)
  (if (fixture-field-present-p expect "logAddress")
      (list
       (list :address (fixture-address-field expect "logAddress")
             :topic (fixture-object-field expect "logTopic")
             :data (fixture-object-field expect "logData")
             :count (hex-to-quantity
                     (fixture-object-field expect "logCount"))))
      '()))

(defun devnet-smoke-gate-verify-rpc-log
    (log target expected-block-number block-hash transaction-hash
     transaction-index log-index context)
  (devnet-smoke-gate-require
   log
   "~A missing expected log" context)
  (devnet-smoke-gate-require
   (string= (address-to-hex (getf target :address))
            (fixture-object-field log "address"))
   "~A log address mismatch" context)
  (devnet-smoke-gate-require
   (string= (getf target :data)
            (fixture-object-field log "data"))
   "~A log data mismatch" context)
  (devnet-smoke-gate-require
   (equal (list (getf target :topic))
          (fixture-object-field log "topics"))
   "~A log topics mismatch" context)
  (devnet-smoke-gate-require
   (string= expected-block-number
            (fixture-object-field log "blockNumber"))
   "~A log block number mismatch" context)
  (devnet-smoke-gate-require
   (string= (hash32-to-hex block-hash)
            (fixture-object-field log "blockHash"))
   "~A log block hash mismatch" context)
  (devnet-smoke-gate-require
   (string= (hash32-to-hex transaction-hash)
            (fixture-object-field log "transactionHash"))
   "~A log transaction hash mismatch" context)
  (devnet-smoke-gate-require
   (string= (quantity-to-hex transaction-index)
            (fixture-object-field log "transactionIndex"))
   "~A log transaction index mismatch" context)
  (devnet-smoke-gate-require
   (string= (quantity-to-hex log-index)
            (fixture-object-field log "logIndex"))
   "~A log index mismatch" context)
  log)

(defun devnet-smoke-gate-simulation-call-object
    (sender-address target-address)
  (list (cons "from" (address-to-hex sender-address))
        (cons "to" (address-to-hex target-address))
        (cons "gas" +devnet-smoke-gate-simulation-gas+)
        (cons "gasPrice" "0x64")
        (cons "data" "0x")))

(defun devnet-smoke-gate-state-error-probes
    (start-id block-id expected-errors
     balance-address sender-address code-address storage-address storage-key)
  (labels ((request (id method params)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" method)
                   (cons "params" params)))
           (probe (id method expected-error params)
             (list :method method
                   :expected-error expected-error
                   :output (make-string-output-stream)
                   :request (request id method params))))
    (destructuring-bind
        (balance-error nonce-error code-error storage-error proof-error
         call-error estimate-error access-list-error)
        expected-errors
      (list
       (probe start-id
              "eth_getBalance"
              balance-error
              (list (address-to-hex balance-address) block-id))
       (probe (+ start-id 1)
              "eth_getTransactionCount"
              nonce-error
              (list (address-to-hex sender-address) block-id))
       (probe (+ start-id 2)
              "eth_getCode"
              code-error
              (list (address-to-hex code-address) block-id))
       (probe (+ start-id 3)
              "eth_getStorageAt"
              storage-error
              (list (address-to-hex storage-address) storage-key block-id))
       (probe (+ start-id 4)
              "eth_getProof"
              proof-error
              (list (address-to-hex storage-address)
                    (list storage-key)
                    block-id))
       (probe (+ start-id 5)
              "eth_call"
              call-error
              (list
               (devnet-smoke-gate-simulation-call-object
                sender-address code-address)
               block-id))
       (probe (+ start-id 6)
              "eth_estimateGas"
              estimate-error
              (list
               (devnet-smoke-gate-simulation-call-object
                sender-address code-address)
               block-id))
       (probe (+ start-id 7)
              "eth_createAccessList"
              access-list-error
              (list
               (devnet-smoke-gate-simulation-call-object
                sender-address code-address)
               block-id))))))

(defun devnet-smoke-gate-verify-state-error-probes (probes label)
  (mapcar
   (lambda (probe)
     (let* ((response
              (get-output-stream-string (getf probe :output)))
            (rpc (devnet-smoke-gate-rpc-body response))
            (error (fixture-object-field rpc "error"))
            (message
              (and error
                   (fixture-object-field error "message"))))
       (devnet-smoke-gate-require
        (= 200 (devnet-cli-http-status response))
        "Restored ~A ~A HTTP status mismatch"
        label
        (getf probe :method))
       (devnet-smoke-gate-require
        error
        "Restored ~A ~A did not return an error"
        label
        (getf probe :method))
       (devnet-smoke-gate-require
        (string= (getf probe :expected-error) message)
        "Restored ~A ~A error mismatch: ~A"
        label
        (getf probe :method)
        message)
       message))
   probes))

(defun devnet-smoke-gate-payload-attributes-v2
    (parent-block suggested-fee-recipient)
  (let ((parent-header (block-header parent-block)))
    (list (cons "timestamp"
                (quantity-to-hex
                 (1+ (block-header-timestamp parent-header))))
          (cons "prevRandao" (hash32-to-hex (zero-hash32)))
          (cons "suggestedFeeRecipient"
                (address-to-hex suggested-fee-recipient))
          (cons "withdrawals" '()))))

(defun devnet-smoke-gate-forkchoice-v2-payload-attributes-request
    (id head payload-attributes
     &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (let ((request (devnet-cli-engine-forkchoice-v2-request
                  id head :safe safe :finalized finalized)))
    (setf (cdr (assoc "params" request :test #'string=))
          (list (first (fixture-object-field request "params"))
                payload-attributes))
    request))

(defun devnet-smoke-gate-remote-block (parent-block)
  (let ((parent-header (block-header parent-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash
      (hash32-from-hex
       "0x9999999999999999999999999999999999999999999999999999999999999999")
      :beneficiary (block-header-beneficiary parent-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number parent-header))
      :gas-limit (block-header-gas-limit parent-header)
      :gas-used 0
      :timestamp (1+ (block-header-timestamp parent-header))
      :base-fee-per-gas (block-header-base-fee-per-gas parent-header))
     :withdrawals '())))

(defun devnet-smoke-gate-invalid-child-block (parent-block)
  (let ((parent-header (block-header parent-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash (block-hash parent-block)
      :beneficiary (block-header-beneficiary parent-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number parent-header))
      :gas-limit (block-header-gas-limit parent-header)
      :gas-used 0
      :timestamp (block-header-timestamp parent-header)
      :base-fee-per-gas (block-header-base-fee-per-gas parent-header))
     :withdrawals '())))

(defun devnet-smoke-gate-invalid-grandchild-block (invalid-block)
  (let ((invalid-header (block-header invalid-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash (block-hash invalid-block)
      :beneficiary (block-header-beneficiary invalid-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number invalid-header))
      :gas-limit (block-header-gas-limit invalid-header)
      :gas-used 0
      :timestamp (1+ (block-header-timestamp invalid-header))
      :base-fee-per-gas (block-header-base-fee-per-gas invalid-header))
     :withdrawals '())))

(defun devnet-smoke-gate-side-sibling-block
    (parent-block parent-state config payload-case withdrawals fee-recipient)
  (let* ((side-state (state-db-copy parent-state))
         (side-header
           (make-block-header
            :parent-hash (block-hash parent-block)
            :beneficiary fee-recipient
            :mix-hash
            (hash32-from-hex
             "0x0300000000000000000000000000000000000000000000000000000000000000")
            :number (fixture-quantity-field payload-case "number")
            :gas-limit (fixture-quantity-field payload-case "gasLimit")
            :gas-used 0
            :timestamp (1+ (fixture-quantity-field payload-case "timestamp"))
            :base-fee-per-gas
            (fixture-quantity-field payload-case "baseFeePerGas"))))
    (execute-signed-block
     side-state
     '()
     :expected-chain-id (chain-config-chain-id config)
     :header side-header
     :chain-config config
     :withdrawals withdrawals)))

(defun devnet-smoke-gate-access-list-entry (access-list address)
  (find (address-to-hex address)
        access-list
        :test #'string=
        :key (lambda (entry)
               (fixture-object-field entry "address"))))

(defun devnet-smoke-gate-executable-code-p (code)
  (and (stringp code)
       (> (length code) 2)
       (not (string= code "0x00"))))

(defun devnet-smoke-gate-verify-ready-file
    (path expected-head-number expected-head-hash)
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
    (devnet-smoke-gate-require
     (integerp (fixture-object-field summary "processId"))
     "Ready file processId must be an integer")
    (devnet-smoke-gate-require
     (< 0 (fixture-object-field summary "processId"))
     "Ready file processId must be positive")
    (devnet-smoke-gate-require
     (string= expected-head-number
              (quantity-to-hex
               (fixture-object-field summary "headNumber")))
     "Ready file head number mismatch")
    (devnet-smoke-gate-require
     (string= expected-head-hash
              (fixture-object-field summary "headHash"))
     "Ready file head hash mismatch")
    summary))

(defun devnet-smoke-gate-verify-pid-file
    (path &key expected-process-id)
  (let ((process-id
          (parse-integer
           (string-trim '(#\Space #\Tab #\Newline #\Return)
                        (devnet-smoke-gate-file-string path))
           :junk-allowed nil)))
    (devnet-smoke-gate-require
     (< 0 process-id)
     "PID file process id must be positive")
    (when expected-process-id
      (devnet-smoke-gate-require
       (= expected-process-id process-id)
       "PID file process id mismatch"))
    process-id))

(defun devnet-smoke-gate-verify-log-file
    (path ready-head-number ready-head-hash shutdown-head-number
     shutdown-head-hash &key expected-process-id)
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
        (let* ((fields (getf record :fields))
               (ready-p (string= "devnet.ready" (getf record :name)))
               (expected-head-number
                 (if ready-p ready-head-number shutdown-head-number))
               (expected-head-hash
                 (if ready-p ready-head-hash shutdown-head-hash)))
          (devnet-smoke-gate-require
           (string= "engine"
                    (cdr (assoc "engineEndpoint" fields :test #'string=)))
           "Log file Engine endpoint mismatch")
          (devnet-smoke-gate-require
           (string= "public"
                    (cdr (assoc "rpcEndpoint" fields :test #'string=)))
           "Log file public RPC endpoint mismatch")
          (when expected-process-id
            (devnet-smoke-gate-require
             (string= (write-to-string expected-process-id)
                      (cdr (assoc "processId" fields :test #'string=)))
             "Log file processId mismatch"))
          (devnet-smoke-gate-require
           (string= expected-head-number
                    (cdr (assoc "headNumber" fields :test #'string=)))
           "Log file head number mismatch")
          (devnet-smoke-gate-require
           (string= expected-head-hash
                    (cdr (assoc "headHash" fields :test #'string=)))
           "Log file head hash mismatch")
          (devnet-smoke-gate-require
           (string= "true"
                    (cdr (assoc "stateAvailable" fields :test #'string=)))
           "Log file state availability mismatch"))))
    records))

(defun devnet-smoke-gate-verify-restored-public-rpc
    (node expected-block-number balance-targets
     sender-address expected-sender-nonce
     code-address expected-code storage-address storage-key expected-storage
     transaction-checks log-targets block-hash
     expected-safe-block-number expected-safe-block-hash
     expected-finalized-block-number expected-finalized-block-hash
     &key pruned-state-rpc-tag)
  #+sbcl
  (let* ((primary-balance-target (first balance-targets))
         (balance-address (getf primary-balance-target :address))
         (expected-balance (getf primary-balance-target :balance))
         (primary-transaction-check (first transaction-checks))
         (transaction-hash (getf primary-transaction-check :hash))
         (expected-raw-transaction (getf primary-transaction-check :raw))
         (transaction-count (length transaction-checks))
         (expected-transaction-count (quantity-to-hex transaction-count))
         (executable-code-p
           (devnet-smoke-gate-executable-code-p expected-code))
         (extra-balance-outputs
           (loop repeat (length (rest balance-targets))
                 collect (make-string-output-stream)))
         (extra-receipt-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-transaction-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-raw-transaction-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-raw-transaction-by-hash-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-raw-transaction-by-number-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-transaction-by-hash-index-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-transaction-by-number-index-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (log-range-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-block-hash-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (block-number-output (make-string-output-stream))
        (balance-output (make-string-output-stream))
        (nonce-output (make-string-output-stream))
        (code-output (make-string-output-stream))
        (storage-output (make-string-output-stream))
        (proof-output (make-string-output-stream))
        (receipt-output (make-string-output-stream))
        (block-output (make-string-output-stream))
        (block-by-number-output (make-string-output-stream))
        (full-block-output (make-string-output-stream))
        (full-block-by-number-output (make-string-output-stream))
        (transaction-output (make-string-output-stream))
        (block-receipts-output (make-string-output-stream))
        (block-transaction-count-by-hash-output (make-string-output-stream))
        (block-transaction-count-by-number-output (make-string-output-stream))
        (canonical-hash-balance-output (make-string-output-stream))
        (canonical-hash-require-balance-output (make-string-output-stream))
        (raw-transaction-output (make-string-output-stream))
        (raw-transaction-by-hash-output (make-string-output-stream))
        (raw-transaction-by-number-output (make-string-output-stream))
        (transaction-by-hash-index-output (make-string-output-stream))
        (transaction-by-number-index-output (make-string-output-stream))
        (safe-block-output (make-string-output-stream))
        (finalized-block-output (make-string-output-stream))
        (call-output (make-string-output-stream))
        (failed-call-output
          (and executable-code-p (make-string-output-stream)))
        (estimate-gas-output (make-string-output-stream))
        (create-access-list-output (make-string-output-stream))
        (post-call-storage-output (make-string-output-stream))
        (pruned-state-probes
          (when pruned-state-rpc-tag
            (devnet-smoke-gate-state-error-probes
             154
             pruned-state-rpc-tag
             (devnet-smoke-gate-pruned-state-error-messages)
             balance-address
             sender-address
             code-address
             storage-address
             storage-key)))
         (expected-public-connections
           (+ 22
              (length extra-balance-outputs)
              (* 7 (length extra-receipt-outputs))
              (* 2 (length log-targets))
              2
              4
              (if executable-code-p 1 0)
              (length pruned-state-probes)))
        (public-requests nil))
    (setf public-requests
          (remove
           nil
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
                   (cons "method" "eth_getTransactionCount")
                   (cons "params" (list (address-to-hex sender-address)
                                        expected-block-number))))
            nonce-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 44)
                   (cons "method" "eth_getCode")
                   (cons "params" (list (address-to-hex code-address)
                                        expected-block-number))))
            code-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 45)
                   (cons "method" "eth_getStorageAt")
                   (cons "params" (list (address-to-hex storage-address)
                                        storage-key
                                        expected-block-number))))
            storage-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 46)
                   (cons "method" "eth_getProof")
                   (cons "params" (list (address-to-hex storage-address)
                                        (list storage-key)
                                        expected-block-number))))
            proof-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 47)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            receipt-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 48)
                   (cons "method" "eth_getBlockByHash")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        :false))))
            block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 49)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list expected-block-number :false))))
            block-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 165)
                   (cons "method" "eth_getBlockByHash")
                   (cons "params" (list (hash32-to-hex block-hash) t))))
            full-block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 166)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list expected-block-number t))))
           full-block-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 50)
                   (cons "method" "eth_getTransactionByHash")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            transaction-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 167)
                   (cons "method" "eth_getRawTransactionByHash")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            raw-transaction-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 51)
                   (cons "method" "eth_getBlockReceipts")
                   (cons "params" (list (hash32-to-hex block-hash)))))
            block-receipts-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 52)
                   (cons "method" "eth_getBlockTransactionCountByHash")
                   (cons "params" (list (hash32-to-hex block-hash)))))
            block-transaction-count-by-hash-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 53)
                   (cons "method" "eth_getBlockTransactionCountByNumber")
                   (cons "params" (list expected-block-number))))
            block-transaction-count-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 163)
                   (cons "method" "eth_getBalance")
                   (cons "params"
                         (list
                          (address-to-hex balance-address)
                          (list (cons "blockHash"
                                      (hash32-to-hex block-hash)))))))
            canonical-hash-balance-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 164)
                   (cons "method" "eth_getBalance")
                   (cons "params"
                         (list
                          (address-to-hex balance-address)
                          (list (cons "blockHash"
                                      (hash32-to-hex block-hash))
                                (cons "requireCanonical" t))))))
            canonical-hash-require-balance-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 54)
                   (cons "method" "eth_getRawTransactionByBlockHashAndIndex")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        "0x0"))))
            raw-transaction-by-hash-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 55)
                   (cons "method" "eth_getRawTransactionByBlockNumberAndIndex")
                   (cons "params" (list expected-block-number "0x0"))))
            raw-transaction-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 56)
                   (cons "method" "eth_getTransactionByBlockHashAndIndex")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        "0x0"))))
            transaction-by-hash-index-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 57)
                   (cons "method" "eth_getTransactionByBlockNumberAndIndex")
                   (cons "params" (list expected-block-number "0x0"))))
            transaction-by-number-index-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 58)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list "safe" :false))))
            safe-block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 59)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list "finalized" :false))))
            finalized-block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 150)
                   (cons "method" "eth_call")
                   (cons "params"
                         (list
                          (devnet-smoke-gate-simulation-call-object
                           sender-address code-address)
                          expected-block-number))))
            call-output)
           (when executable-code-p
             (cons
              (json-encode
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 162)
                     (cons "method" "eth_call")
                     (cons "params"
                           (list
                            (list
                             (cons "from" (address-to-hex sender-address))
                             (cons "to" (address-to-hex code-address))
                             (cons "gas" (quantity-to-hex 22000))
                             (cons "gasPrice" "0x64")
                             (cons "data" "0x"))
                            expected-block-number))))
              failed-call-output))
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 151)
                   (cons "method" "eth_estimateGas")
                   (cons "params"
                         (list
                          (devnet-smoke-gate-simulation-call-object
                           sender-address code-address)
                          expected-block-number))))
            estimate-gas-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 152)
                   (cons "method" "eth_createAccessList")
                   (cons "params"
                         (list
                          (devnet-smoke-gate-simulation-call-object
                           sender-address code-address)
                          expected-block-number))))
            create-access-list-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 153)
                   (cons "method" "eth_getStorageAt")
                   (cons "params" (list (address-to-hex storage-address)
                                        storage-key
                                        expected-block-number))))
            post-call-storage-output))))
    (when pruned-state-probes
      (setf public-requests
            (append
             public-requests
             (mapcar
              (lambda (probe)
                (cons (json-encode (getf probe :request))
                      (getf probe :output)))
              pruned-state-probes))))
    (setf public-requests
          (nconc
           public-requests
           (loop for target in (rest balance-targets)
                 for output in extra-balance-outputs
                 for id from 60
                 collect
                 (cons
                  (json-encode
                   (engine-fixture-balance-request
                    id (getf target :address)))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-receipt-outputs
                 for id from 70
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params"
                               (list (hash32-to-hex
                                      (getf check :hash))))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-transaction-outputs
                 for id from 80
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getTransactionByHash")
                         (cons "params"
                               (list (hash32-to-hex
                                      (getf check :hash))))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-raw-transaction-outputs
                 for id from 170
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getRawTransactionByHash")
                         (cons "params"
                               (list (hash32-to-hex
                                      (getf check :hash))))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-raw-transaction-by-hash-outputs
                 for index from 1
                 for id from 90
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getRawTransactionByBlockHashAndIndex")
                         (cons "params"
                               (list (hash32-to-hex block-hash)
                                     (quantity-to-hex index)))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-raw-transaction-by-number-outputs
                 for index from 1
                 for id from 100
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getRawTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list expected-block-number
                                     (quantity-to-hex index)))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-transaction-by-hash-index-outputs
                 for index from 1
                 for id from 110
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getTransactionByBlockHashAndIndex")
                         (cons "params"
                               (list (hash32-to-hex block-hash)
                                     (quantity-to-hex index)))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-transaction-by-number-index-outputs
                 for index from 1
                 for id from 120
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list expected-block-number
                                     (quantity-to-hex index)))))
                  output))
           (loop for target in log-targets
                 for output in log-range-outputs
                 for id from 130
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" expected-block-number)
                                 (cons "toBlock" expected-block-number)
                                 (cons "address"
                                       (address-to-hex
                                        (getf target :address)))
                                 (cons "topics"
                                       (list (getf target :topic))))))))
                  output))
           (loop for target in log-targets
                 for output in log-block-hash-outputs
                 for id from 140
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "blockHash"
                                       (hash32-to-hex block-hash))
                                 (cons "address"
                                       (address-to-hex
                                        (getf target :address)))
                                 (cons "topics"
                                       (list (getf target :topic))))))))
                  output))))
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
             :max-connections expected-public-connections)))
      (let* ((block-number-response
               (get-output-stream-string block-number-output))
             (balance-response
               (get-output-stream-string balance-output))
             (nonce-response
               (get-output-stream-string nonce-output))
             (code-response
               (get-output-stream-string code-output))
             (storage-response
               (get-output-stream-string storage-output))
             (proof-response
               (get-output-stream-string proof-output))
             (receipt-response
               (get-output-stream-string receipt-output))
             (block-response
               (get-output-stream-string block-output))
             (block-by-number-response
               (get-output-stream-string block-by-number-output))
             (full-block-response
               (get-output-stream-string full-block-output))
             (full-block-by-number-response
               (get-output-stream-string full-block-by-number-output))
             (transaction-response
               (get-output-stream-string transaction-output))
             (raw-transaction-response
               (get-output-stream-string raw-transaction-output))
             (block-receipts-response
               (get-output-stream-string block-receipts-output))
             (block-transaction-count-by-hash-response
               (get-output-stream-string
                block-transaction-count-by-hash-output))
             (block-transaction-count-by-number-response
               (get-output-stream-string
                block-transaction-count-by-number-output))
             (canonical-hash-balance-response
               (get-output-stream-string canonical-hash-balance-output))
             (canonical-hash-require-balance-response
               (get-output-stream-string
                canonical-hash-require-balance-output))
             (raw-transaction-by-hash-response
               (get-output-stream-string raw-transaction-by-hash-output))
             (raw-transaction-by-number-response
               (get-output-stream-string raw-transaction-by-number-output))
             (transaction-by-hash-index-response
               (get-output-stream-string transaction-by-hash-index-output))
             (transaction-by-number-index-response
               (get-output-stream-string transaction-by-number-index-output))
             (safe-block-response
               (get-output-stream-string safe-block-output))
             (finalized-block-response
               (get-output-stream-string finalized-block-output))
             (call-response
               (get-output-stream-string call-output))
             (failed-call-response
               (and failed-call-output
                    (get-output-stream-string failed-call-output)))
             (estimate-gas-response
               (get-output-stream-string estimate-gas-output))
             (create-access-list-response
               (get-output-stream-string create-access-list-output))
             (post-call-storage-response
               (get-output-stream-string post-call-storage-output))
             (block-number-rpc
               (devnet-smoke-gate-rpc-body block-number-response))
             (balance-rpc
               (devnet-smoke-gate-rpc-body balance-response))
             (nonce-rpc
               (devnet-smoke-gate-rpc-body nonce-response))
             (code-rpc
               (devnet-smoke-gate-rpc-body code-response))
             (storage-rpc
               (devnet-smoke-gate-rpc-body storage-response))
             (proof-rpc
               (devnet-smoke-gate-rpc-body proof-response))
             (receipt-rpc
               (devnet-smoke-gate-rpc-body receipt-response))
             (block-rpc
               (devnet-smoke-gate-rpc-body block-response))
             (block-by-number-rpc
               (devnet-smoke-gate-rpc-body block-by-number-response))
             (full-block-rpc
               (devnet-smoke-gate-rpc-body full-block-response))
             (full-block-by-number-rpc
               (devnet-smoke-gate-rpc-body full-block-by-number-response))
             (transaction-rpc
               (devnet-smoke-gate-rpc-body transaction-response))
             (raw-transaction-rpc
               (devnet-smoke-gate-rpc-body raw-transaction-response))
             (block-receipts-rpc
               (devnet-smoke-gate-rpc-body block-receipts-response))
             (block-transaction-count-by-hash-rpc
               (devnet-smoke-gate-rpc-body
                block-transaction-count-by-hash-response))
             (block-transaction-count-by-number-rpc
               (devnet-smoke-gate-rpc-body
                block-transaction-count-by-number-response))
             (canonical-hash-balance-rpc
               (devnet-smoke-gate-rpc-body
                canonical-hash-balance-response))
             (canonical-hash-require-balance-rpc
               (devnet-smoke-gate-rpc-body
                canonical-hash-require-balance-response))
             (raw-transaction-by-hash-rpc
               (devnet-smoke-gate-rpc-body
                raw-transaction-by-hash-response))
             (raw-transaction-by-number-rpc
               (devnet-smoke-gate-rpc-body
                raw-transaction-by-number-response))
             (transaction-by-hash-index-rpc
               (devnet-smoke-gate-rpc-body
                transaction-by-hash-index-response))
             (transaction-by-number-index-rpc
               (devnet-smoke-gate-rpc-body
                transaction-by-number-index-response))
             (safe-block-rpc
               (devnet-smoke-gate-rpc-body safe-block-response))
             (finalized-block-rpc
               (devnet-smoke-gate-rpc-body finalized-block-response))
             (call-rpc
               (devnet-smoke-gate-rpc-body call-response))
             (failed-call-rpc
               (and failed-call-response
                    (devnet-smoke-gate-rpc-body failed-call-response)))
             (estimate-gas-rpc
               (devnet-smoke-gate-rpc-body estimate-gas-response))
             (create-access-list-rpc
               (devnet-smoke-gate-rpc-body create-access-list-response))
             (post-call-storage-rpc
               (devnet-smoke-gate-rpc-body post-call-storage-response))
             (pruned-state-error-messages
               (devnet-smoke-gate-verify-state-error-probes
                pruned-state-probes
                "pruned-state"))
             (actual-block-number
               (fixture-object-field block-number-rpc "result"))
             (actual-balance
               (fixture-object-field balance-rpc "result"))
             (actual-nonce
               (fixture-object-field nonce-rpc "result"))
             (actual-code
               (fixture-object-field code-rpc "result"))
             (actual-storage
               (fixture-object-field storage-rpc "result"))
             (actual-proof
               (fixture-object-field proof-rpc "result"))
             (actual-proof-storage-proofs
               (fixture-object-field actual-proof "storageProof"))
             (actual-proof-storage
               (first actual-proof-storage-proofs))
             (actual-receipt
               (fixture-object-field receipt-rpc "result"))
             (actual-receipt-transaction-hash
               (fixture-object-field actual-receipt "transactionHash"))
             (actual-receipt-block-number
               (fixture-object-field actual-receipt "blockNumber"))
             (actual-receipt-block-hash
               (fixture-object-field actual-receipt "blockHash"))
             (actual-receipt-logs
               (fixture-object-field actual-receipt "logs"))
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
             (actual-full-block
               (fixture-object-field full-block-rpc "result"))
             (actual-full-block-transactions
               (fixture-object-field actual-full-block "transactions"))
             (actual-full-block-transaction
               (first actual-full-block-transactions))
             (actual-full-block-transaction-hash
               (fixture-object-field actual-full-block-transaction "hash"))
             (actual-full-block-transaction-index
               (fixture-object-field actual-full-block-transaction
                                     "transactionIndex"))
             (actual-full-block-transaction-block-hash
               (fixture-object-field actual-full-block-transaction
                                     "blockHash"))
             (actual-full-block-transaction-block-number
               (fixture-object-field actual-full-block-transaction
                                     "blockNumber"))
             (actual-full-block-by-number
               (fixture-object-field full-block-by-number-rpc "result"))
             (actual-full-block-by-number-transactions
               (fixture-object-field
                actual-full-block-by-number "transactions"))
             (actual-full-block-by-number-transaction
               (first actual-full-block-by-number-transactions))
             (actual-full-block-by-number-transaction-hash
               (fixture-object-field
                actual-full-block-by-number-transaction "hash"))
             (actual-full-block-by-number-transaction-index
               (fixture-object-field
                actual-full-block-by-number-transaction "transactionIndex"))
             (actual-full-block-by-number-transaction-block-hash
               (fixture-object-field
                actual-full-block-by-number-transaction "blockHash"))
             (actual-full-block-by-number-transaction-block-number
               (fixture-object-field
                actual-full-block-by-number-transaction "blockNumber"))
             (actual-transaction
               (fixture-object-field transaction-rpc "result"))
             (actual-transaction-hash
               (fixture-object-field actual-transaction "hash"))
             (actual-transaction-block-hash
               (fixture-object-field actual-transaction "blockHash"))
             (actual-transaction-block-number
               (fixture-object-field actual-transaction "blockNumber"))
             (actual-raw-transaction
               (fixture-object-field raw-transaction-rpc "result"))
             (actual-block-receipts
               (fixture-object-field block-receipts-rpc "result"))
             (actual-block-receipt
               (first actual-block-receipts))
             (actual-block-receipt-transaction-hash
               (fixture-object-field actual-block-receipt "transactionHash"))
             (actual-block-receipt-block-hash
               (fixture-object-field actual-block-receipt "blockHash"))
             (actual-block-receipt-block-number
               (fixture-object-field actual-block-receipt "blockNumber"))
             (actual-block-receipt-logs
               (fixture-object-field actual-block-receipt "logs"))
             (actual-block-transaction-count-by-hash
               (fixture-object-field
                block-transaction-count-by-hash-rpc "result"))
             (actual-block-transaction-count-by-number
               (fixture-object-field
                block-transaction-count-by-number-rpc "result"))
             (actual-canonical-hash-balance
               (fixture-object-field canonical-hash-balance-rpc "result"))
             (actual-canonical-hash-require-balance
               (fixture-object-field
                canonical-hash-require-balance-rpc "result"))
             (actual-raw-transaction-by-hash
               (fixture-object-field raw-transaction-by-hash-rpc "result"))
             (actual-raw-transaction-by-number
               (fixture-object-field raw-transaction-by-number-rpc "result"))
             (actual-transaction-by-hash-index
               (fixture-object-field transaction-by-hash-index-rpc "result"))
             (actual-transaction-by-number-index
               (fixture-object-field transaction-by-number-index-rpc "result"))
             (actual-transaction-by-hash-index-hash
               (fixture-object-field
                actual-transaction-by-hash-index "hash"))
             (actual-transaction-by-hash-index-block-hash
               (fixture-object-field
                actual-transaction-by-hash-index "blockHash"))
             (actual-transaction-by-hash-index-block-number
               (fixture-object-field
                actual-transaction-by-hash-index "blockNumber"))
             (actual-transaction-by-hash-index-transaction-index
               (fixture-object-field
                actual-transaction-by-hash-index "transactionIndex"))
             (actual-transaction-by-number-index-hash
               (fixture-object-field
                actual-transaction-by-number-index "hash"))
             (actual-transaction-by-number-index-block-hash
               (fixture-object-field
                actual-transaction-by-number-index "blockHash"))
             (actual-transaction-by-number-index-block-number
               (fixture-object-field
                actual-transaction-by-number-index "blockNumber"))
             (actual-transaction-by-number-index-transaction-index
               (fixture-object-field
                actual-transaction-by-number-index "transactionIndex"))
             (actual-safe-block
               (fixture-object-field safe-block-rpc "result"))
             (actual-safe-block-hash
               (fixture-object-field actual-safe-block "hash"))
             (actual-safe-block-number
               (fixture-object-field actual-safe-block "number"))
             (actual-finalized-block
               (fixture-object-field finalized-block-rpc "result"))
             (actual-finalized-block-hash
               (fixture-object-field actual-finalized-block "hash"))
             (actual-finalized-block-number
               (fixture-object-field actual-finalized-block "number"))
             (actual-call-result
               (fixture-object-field call-rpc "result"))
             (actual-failed-call-error
               (and failed-call-rpc
                    (fixture-object-field failed-call-rpc "error")))
             (actual-failed-call-error-message
               (and actual-failed-call-error
                    (fixture-object-field
                     actual-failed-call-error "message")))
             (actual-estimate-gas
               (fixture-object-field estimate-gas-rpc "result"))
             (actual-create-access-list
               (fixture-object-field create-access-list-rpc "result"))
             (actual-access-list
               (fixture-object-field actual-create-access-list "accessList"))
             (actual-access-list-gas-used
               (fixture-object-field actual-create-access-list "gasUsed"))
             (actual-access-list-entry
               (devnet-smoke-gate-access-list-entry
                actual-access-list storage-address))
             (actual-access-list-storage-keys
               (and actual-access-list-entry
                    (fixture-object-field actual-access-list-entry
                                          "storageKeys")))
             (actual-post-call-storage
               (fixture-object-field post-call-storage-rpc "result"))
             (expected-proof-code-hash
               (hash32-to-hex (keccak-256-hash (hex-to-bytes expected-code))))
             (expected-proof-storage-value
               (quantity-to-hex (hex-to-quantity expected-storage))))
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Restored database verification should not use Engine RPC")
        (devnet-smoke-gate-require
         (= expected-public-connections (getf summary :public-connections))
         "Restored database verification expected ~S public RPC connections, got ~S"
         expected-public-connections
         (getf summary :public-connections))
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-number-response))
         "Restored eth_blockNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status balance-response))
         "Restored eth_getBalance HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status nonce-response))
         "Restored eth_getTransactionCount HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status code-response))
         "Restored eth_getCode HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status storage-response))
         "Restored eth_getStorageAt HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status proof-response))
         "Restored eth_getProof HTTP status mismatch")
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
         (= 200 (devnet-cli-http-status full-block-response))
         "Restored full eth_getBlockByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status full-block-by-number-response))
         "Restored full eth_getBlockByNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-response))
         "Restored eth_getTransactionByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status raw-transaction-response))
         "Restored eth_getRawTransactionByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-receipts-response))
         "Restored eth_getBlockReceipts HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status
                 block-transaction-count-by-hash-response))
         "Restored eth_getBlockTransactionCountByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status
                 block-transaction-count-by-number-response))
         "Restored eth_getBlockTransactionCountByNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status canonical-hash-balance-response))
         "Restored EIP-1898 eth_getBalance blockHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status
                 canonical-hash-require-balance-response))
         "Restored EIP-1898 eth_getBalance requireCanonical HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status raw-transaction-by-hash-response))
         "Restored eth_getRawTransactionByBlockHashAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status raw-transaction-by-number-response))
         "Restored eth_getRawTransactionByBlockNumberAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-by-hash-index-response))
         "Restored eth_getTransactionByBlockHashAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-by-number-index-response))
         "Restored eth_getTransactionByBlockNumberAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status safe-block-response))
         "Restored eth_getBlockByNumber safe HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status finalized-block-response))
         "Restored eth_getBlockByNumber finalized HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status call-response))
         "Restored eth_call HTTP status mismatch")
        (when failed-call-response
          (devnet-smoke-gate-require
           (= 200 (devnet-cli-http-status failed-call-response))
           "Restored failing eth_call HTTP status mismatch"))
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status estimate-gas-response))
         "Restored eth_estimateGas HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status create-access-list-response))
         "Restored eth_createAccessList HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status post-call-storage-response))
         "Restored post-eth_call eth_getStorageAt HTTP status mismatch")
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
        (loop for target in (rest balance-targets)
              for output in extra-balance-outputs
              for response = (get-output-stream-string output)
              for rpc = (devnet-smoke-gate-rpc-body response)
              for actual-extra-balance =
                (fixture-object-field rpc "result")
              do
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status response))
                  "Restored extra eth_getBalance HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (string= (getf target :balance) actual-extra-balance)
                  "Restored extra eth_getBalance mismatch: expected ~A got ~A"
                  (getf target :balance)
                  actual-extra-balance))
        (devnet-smoke-gate-require
         (string= expected-sender-nonce actual-nonce)
         "Restored eth_getTransactionCount mismatch: expected ~A got ~A"
         expected-sender-nonce
         actual-nonce)
        (devnet-smoke-gate-require
         (string= expected-code actual-code)
         "Restored eth_getCode mismatch: expected ~A got ~A"
         expected-code
         actual-code)
        (devnet-smoke-gate-require
         (string= expected-storage actual-storage)
         "Restored eth_getStorageAt mismatch: expected ~A got ~A"
         expected-storage
         actual-storage)
        (devnet-smoke-gate-require
         actual-call-result
         "Restored eth_call returned error response: ~S"
         call-rpc)
        (devnet-smoke-gate-require
         (string= "0x" actual-call-result)
         "Restored eth_call result mismatch: expected empty return, got ~A"
         actual-call-result)
        (when executable-code-p
          (devnet-smoke-gate-require
           actual-failed-call-error
           "Restored failing eth_call did not return an error response: ~S"
           failed-call-rpc)
          (devnet-smoke-gate-require
           (string= "eth_call execution failed"
                    actual-failed-call-error-message)
           "Restored failing eth_call error mismatch: ~A"
           actual-failed-call-error-message))
        (devnet-smoke-gate-require
         (<= 21000 (hex-to-quantity actual-estimate-gas))
         "Restored eth_estimateGas must be at least intrinsic gas")
        (devnet-smoke-gate-require
         (stringp actual-access-list-gas-used)
         "Restored eth_createAccessList gasUsed must be a string")
        (when (devnet-smoke-gate-executable-code-p expected-code)
          (devnet-smoke-gate-require
           actual-access-list-entry
           "Restored eth_createAccessList missing storage account entry")
          (devnet-smoke-gate-require
           (member storage-key actual-access-list-storage-keys
                   :test #'string=)
           "Restored eth_createAccessList missing storage key"))
        (devnet-smoke-gate-require
         (string= expected-storage actual-post-call-storage)
         "Restored eth_call mutated retained storage: expected ~A got ~A"
         expected-storage
         actual-post-call-storage)
        (devnet-smoke-gate-require
         (string= (address-to-hex storage-address)
                  (fixture-object-field actual-proof "address"))
         "Restored eth_getProof address mismatch")
        (devnet-smoke-gate-require
         (string= expected-proof-code-hash
                  (fixture-object-field actual-proof "codeHash"))
         "Restored eth_getProof codeHash mismatch: expected ~A got ~A"
         expected-proof-code-hash
         (fixture-object-field actual-proof "codeHash"))
        (devnet-smoke-gate-require
         (listp (fixture-object-field actual-proof "accountProof"))
         "Restored eth_getProof accountProof must be a list")
        (devnet-smoke-gate-require
         (= 1 (length actual-proof-storage-proofs))
         "Restored eth_getProof expected 1 storage proof, got ~S"
         (length actual-proof-storage-proofs))
        (devnet-smoke-gate-require
         (string= storage-key (fixture-object-field actual-proof-storage "key"))
         "Restored eth_getProof storage key mismatch: expected ~A got ~A"
         storage-key
         (fixture-object-field actual-proof-storage "key"))
        (devnet-smoke-gate-require
         (string= expected-proof-storage-value
                  (fixture-object-field actual-proof-storage "value"))
         "Restored eth_getProof storage value mismatch: expected ~A got ~A"
         expected-proof-storage-value
         (fixture-object-field actual-proof-storage "value"))
        (devnet-smoke-gate-require
         (listp (fixture-object-field actual-proof-storage "proof"))
         "Restored eth_getProof storage proof must be a list")
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
         (= transaction-count (length actual-block-transactions))
         "Restored eth_getBlockByHash transaction count mismatch")
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
         (= transaction-count (length actual-block-by-number-transactions))
         "Restored eth_getBlockByNumber transaction count mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-full-block-transactions))
         "Restored full eth_getBlockByHash transaction count mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-full-block-transaction-hash)
         "Restored full eth_getBlockByHash transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" actual-full-block-transaction-index)
         "Restored full eth_getBlockByHash transaction index mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-full-block-transaction-block-hash)
         "Restored full eth_getBlockByHash transaction block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-full-block-transaction-block-number)
         "Restored full eth_getBlockByHash transaction block number mismatch")
        (devnet-smoke-gate-require
         (= transaction-count
            (length actual-full-block-by-number-transactions))
         "Restored full eth_getBlockByNumber transaction count mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-full-block-by-number-transaction-hash)
         "Restored full eth_getBlockByNumber transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" actual-full-block-by-number-transaction-index)
         "Restored full eth_getBlockByNumber transaction index mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-full-block-by-number-transaction-block-hash)
         "Restored full eth_getBlockByNumber transaction block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-full-block-by-number-transaction-block-number)
         "Restored full eth_getBlockByNumber transaction block number mismatch")
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
         (string= expected-raw-transaction actual-raw-transaction)
         "Restored eth_getRawTransactionByHash mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-block-receipts))
         "Restored eth_getBlockReceipts expected ~S receipts, got ~S"
         transaction-count
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
        (when log-targets
          (let ((target (first log-targets)))
            (devnet-smoke-gate-require
             (= (getf target :count) (length actual-receipt-logs))
             "Restored eth_getTransactionReceipt log count mismatch")
            (devnet-smoke-gate-require
             (= (getf target :count) (length actual-block-receipt-logs))
             "Restored eth_getBlockReceipts log count mismatch")
            (devnet-smoke-gate-verify-rpc-log
             (first actual-receipt-logs)
             target
             expected-block-number
             block-hash
             transaction-hash
             0
             0
             "Restored eth_getTransactionReceipt")
            (devnet-smoke-gate-verify-rpc-log
             (first actual-block-receipt-logs)
             target
             expected-block-number
             block-hash
             transaction-hash
             0
             0
             "Restored eth_getBlockReceipts")))
        (devnet-smoke-gate-require
         (string= expected-transaction-count
                  actual-block-transaction-count-by-hash)
         "Restored eth_getBlockTransactionCountByHash mismatch")
        (devnet-smoke-gate-require
         (string= expected-transaction-count
                  actual-block-transaction-count-by-number)
         "Restored eth_getBlockTransactionCountByNumber mismatch")
        (devnet-smoke-gate-require
         (string= expected-balance actual-canonical-hash-balance)
         "Restored EIP-1898 eth_getBalance blockHash mismatch: expected ~A got ~A"
         expected-balance
         actual-canonical-hash-balance)
        (devnet-smoke-gate-require
         (string= expected-balance actual-canonical-hash-require-balance)
         "Restored EIP-1898 eth_getBalance requireCanonical mismatch: expected ~A got ~A"
         expected-balance
         actual-canonical-hash-require-balance)
        (devnet-smoke-gate-require
         (string= expected-raw-transaction actual-raw-transaction-by-hash)
         "Restored eth_getRawTransactionByBlockHashAndIndex mismatch")
        (devnet-smoke-gate-require
         (string= expected-raw-transaction actual-raw-transaction-by-number)
         "Restored eth_getRawTransactionByBlockNumberAndIndex mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-transaction-by-hash-index-hash)
         "Restored eth_getTransactionByBlockHashAndIndex hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-transaction-by-hash-index-block-hash)
         "Restored eth_getTransactionByBlockHashAndIndex block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-transaction-by-hash-index-block-number)
         "Restored eth_getTransactionByBlockHashAndIndex block number mismatch")
        (devnet-smoke-gate-require
         (string= "0x0"
                  actual-transaction-by-hash-index-transaction-index)
         "Restored eth_getTransactionByBlockHashAndIndex index mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-transaction-by-number-index-hash)
         "Restored eth_getTransactionByBlockNumberAndIndex hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-transaction-by-number-index-block-hash)
         "Restored eth_getTransactionByBlockNumberAndIndex block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-transaction-by-number-index-block-number)
         "Restored eth_getTransactionByBlockNumberAndIndex block number mismatch")
        (devnet-smoke-gate-require
         (string= "0x0"
                  actual-transaction-by-number-index-transaction-index)
         "Restored eth_getTransactionByBlockNumberAndIndex index mismatch")
        (loop for check in (rest transaction-checks)
              for index from 1
              for receipt-output in extra-receipt-outputs
              for transaction-output in extra-transaction-outputs
              for raw-output in extra-raw-transaction-outputs
              for raw-by-hash-output in extra-raw-transaction-by-hash-outputs
              for raw-by-number-output in extra-raw-transaction-by-number-outputs
              for tx-by-hash-index-output in extra-transaction-by-hash-index-outputs
              for tx-by-number-index-output in extra-transaction-by-number-index-outputs
              for expected-hash = (hash32-to-hex (getf check :hash))
              for expected-raw = (getf check :raw)
              for expected-index = (quantity-to-hex index)
              do
                 (let* ((receipt-response
                          (get-output-stream-string receipt-output))
                        (transaction-response
                          (get-output-stream-string transaction-output))
                        (raw-response
                          (get-output-stream-string raw-output))
                        (raw-by-hash-response
                          (get-output-stream-string raw-by-hash-output))
                        (raw-by-number-response
                          (get-output-stream-string raw-by-number-output))
                        (tx-by-hash-index-response
                          (get-output-stream-string tx-by-hash-index-output))
                        (tx-by-number-index-response
                          (get-output-stream-string
                           tx-by-number-index-output))
                        (receipt
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body receipt-response)
                           "result"))
                        (transaction
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body
                            transaction-response)
                           "result"))
                        (tx-by-hash-index
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body
                            tx-by-hash-index-response)
                           "result"))
                        (tx-by-number-index
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body
                            tx-by-number-index-response)
                           "result")))
                   (dolist (response
                            (list receipt-response transaction-response
                                  raw-response raw-by-hash-response
                                  raw-by-number-response tx-by-hash-index-response
                                  tx-by-number-index-response))
                     (devnet-smoke-gate-require
                      (= 200 (devnet-cli-http-status response))
                      "Restored extra transaction RPC HTTP status mismatch"))
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field receipt
                                                   "transactionHash"))
                    "Restored extra receipt transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-block-number
                             (fixture-object-field receipt "blockNumber"))
                    "Restored extra receipt block number mismatch")
                   (devnet-smoke-gate-require
                    (string= (hash32-to-hex block-hash)
                             (fixture-object-field receipt "blockHash"))
                    "Restored extra receipt block hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field transaction "hash"))
                    "Restored extra eth_getTransactionByHash mismatch")
                   (devnet-smoke-gate-require
                    (string= (hash32-to-hex block-hash)
                             (fixture-object-field transaction
                                                   "blockHash"))
                    "Restored extra eth_getTransactionByHash block hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-block-number
                             (fixture-object-field transaction
                                                   "blockNumber"))
                    "Restored extra eth_getTransactionByHash block number mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-raw
                             (fixture-object-field
                              (devnet-smoke-gate-rpc-body
                               raw-response)
                              "result"))
                    "Restored extra raw transaction by transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-raw
                             (fixture-object-field
                              (devnet-smoke-gate-rpc-body
                               raw-by-hash-response)
                              "result"))
                    "Restored extra raw transaction by hash/index mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-raw
                             (fixture-object-field
                              (devnet-smoke-gate-rpc-body
                               raw-by-number-response)
                              "result"))
                    "Restored extra raw transaction by number/index mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field tx-by-hash-index "hash"))
                    "Restored extra tx by hash/index hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-index
                             (fixture-object-field tx-by-hash-index
                                                   "transactionIndex"))
                    "Restored extra tx by hash/index index mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field tx-by-number-index "hash"))
                    "Restored extra tx by number/index hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-index
                             (fixture-object-field tx-by-number-index
                                                   "transactionIndex"))
                    "Restored extra tx by number/index index mismatch")))
        (loop for target in log-targets
              for range-output in log-range-outputs
              for block-hash-output in log-block-hash-outputs
              do
                 (let* ((range-response
                          (get-output-stream-string range-output))
                        (block-hash-response
                          (get-output-stream-string block-hash-output))
                        (range-logs
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body range-response)
                           "result"))
                        (block-hash-logs
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body block-hash-response)
                           "result")))
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status range-response))
                    "Restored eth_getLogs range HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status block-hash-response))
                    "Restored eth_getLogs blockHash HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= (getf target :count) (length range-logs))
                    "Restored eth_getLogs range log count mismatch")
                   (devnet-smoke-gate-require
                    (= (getf target :count) (length block-hash-logs))
                    "Restored eth_getLogs blockHash log count mismatch")
                   (devnet-smoke-gate-verify-rpc-log
                    (first range-logs)
                    target
                    expected-block-number
                    block-hash
                    transaction-hash
                    0
                    0
                    "Restored eth_getLogs range")
                   (devnet-smoke-gate-verify-rpc-log
                    (first block-hash-logs)
                    target
                    expected-block-number
                    block-hash
                    transaction-hash
                    0
                    0
                    "Restored eth_getLogs blockHash")))
        (devnet-smoke-gate-require
         (string= (hash32-to-hex expected-safe-block-hash)
                  actual-safe-block-hash)
         "Restored eth_getBlockByNumber safe hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-safe-block-number actual-safe-block-number)
         "Restored eth_getBlockByNumber safe number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex expected-finalized-block-hash)
                  actual-finalized-block-hash)
         "Restored eth_getBlockByNumber finalized hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-finalized-block-number
                  actual-finalized-block-number)
         "Restored eth_getBlockByNumber finalized number mismatch")
        (list :block-number actual-block-number
              :balance actual-balance
              :nonce actual-nonce
              :code actual-code
              :storage actual-storage
              :proof-address (fixture-object-field actual-proof "address")
              :proof-code-hash
              (fixture-object-field actual-proof "codeHash")
              :proof-storage-key
              (fixture-object-field actual-proof-storage "key")
              :proof-storage-value
              (fixture-object-field actual-proof-storage "value")
              :proof-storage-count (length actual-proof-storage-proofs)
              :proof-account-proof-count
              (length (fixture-object-field actual-proof "accountProof"))
              :receipt-transaction-hash actual-receipt-transaction-hash
              :receipt-block-number actual-receipt-block-number
              :block-hash actual-block-hash
              :block-by-hash-number actual-block-by-hash-number
              :block-transaction-hash actual-block-transaction-hash
              :block-by-number-hash actual-block-by-number-hash
              :block-by-number-number actual-block-by-number-number
              :block-by-number-transaction-hash
              actual-block-by-number-transaction-hash
              :full-block-transaction-count
              (length actual-full-block-transactions)
              :full-block-transaction-hash
              actual-full-block-transaction-hash
              :full-block-transaction-index
              actual-full-block-transaction-index
              :full-block-by-number-transaction-count
              (length actual-full-block-by-number-transactions)
              :full-block-by-number-transaction-hash
              actual-full-block-by-number-transaction-hash
              :full-block-by-number-transaction-index
              actual-full-block-by-number-transaction-index
              :transaction-hash actual-transaction-hash
              :transaction-block-hash actual-transaction-block-hash
              :transaction-block-number actual-transaction-block-number
              :raw-transaction actual-raw-transaction
              :block-receipts-count (length actual-block-receipts)
              :block-receipt-transaction-hash
              actual-block-receipt-transaction-hash
              :block-receipt-block-hash actual-block-receipt-block-hash
              :block-receipt-block-number actual-block-receipt-block-number
              :block-transaction-count-by-hash
              actual-block-transaction-count-by-hash
              :block-transaction-count-by-number
              actual-block-transaction-count-by-number
              :canonical-hash-balance actual-canonical-hash-balance
              :canonical-hash-require-balance
              actual-canonical-hash-require-balance
              :transaction-count transaction-count
              :balance-count (length balance-targets)
              :log-count (reduce #'+ log-targets
                                  :key (lambda (target)
                                         (getf target :count))
                                  :initial-value 0)
              :raw-transaction-by-hash actual-raw-transaction-by-hash
              :raw-transaction-by-number actual-raw-transaction-by-number
              :transaction-by-hash-index-hash
              actual-transaction-by-hash-index-hash
              :transaction-by-hash-index-block-hash
              actual-transaction-by-hash-index-block-hash
              :transaction-by-hash-index-block-number
              actual-transaction-by-hash-index-block-number
              :transaction-by-hash-index-transaction-index
              actual-transaction-by-hash-index-transaction-index
              :transaction-by-number-index-hash
              actual-transaction-by-number-index-hash
              :transaction-by-number-index-block-hash
              actual-transaction-by-number-index-block-hash
              :transaction-by-number-index-block-number
              actual-transaction-by-number-index-block-number
              :transaction-by-number-index-transaction-index
              actual-transaction-by-number-index-transaction-index
              :safe-block-hash actual-safe-block-hash
              :safe-block-number actual-safe-block-number
              :finalized-block-hash actual-finalized-block-hash
              :finalized-block-number actual-finalized-block-number
              :call-result actual-call-result
              :failed-call-error-message
              (or actual-failed-call-error-message :false)
              :estimate-gas actual-estimate-gas
              :access-list-count (length actual-access-list)
              :access-list-gas-used actual-access-list-gas-used
              :post-call-storage actual-post-call-storage
              :simulation-count (if executable-code-p 5 4)
              :pruned-state-error-message
              (first pruned-state-error-messages)
              :pruned-state-error-messages pruned-state-error-messages
              :public-connections (getf summary :public-connections)))))
  #-sbcl
  (error "Restored devnet public RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-engine-rpc
    (node payload-id expected-parent-hash expected-block-number
     expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 170)
                  (cons "method" "engine_getPayloadV2")
                  (cons "params" (list payload-id)))))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 171)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-prepared-payload"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-prepared-payload"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload
           (fixture-object-field
            (fixture-object-field engine-rpc "result")
            "executionPayload")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored Engine prepared-payload probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored Engine prepared-payload probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored engine_getPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored prepared-payload eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored engine_getPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= (hash32-to-hex expected-parent-hash)
              (fixture-object-field payload "parentHash"))
     "Restored prepared payload parent hash mismatch")
    (devnet-smoke-gate-require
     (string= expected-block-number
              (fixture-object-field payload "blockNumber"))
     "Restored prepared payload block number mismatch")
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored prepared-payload public block number mismatch")
    (list :prepared-payload-id payload-id
          :prepared-payload-parent-hash
          (fixture-object-field payload "parentHash")
          :prepared-payload-block-number
          (fixture-object-field payload "blockNumber")
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node payload-id expected-parent-hash expected-block-number
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-remote-block-rpc
    (node remote-payload expected-block-hash expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (engine-fixture-payload-request 172 remote-payload)))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 173)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-remote-block"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-remote-block"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload-status (fixture-object-field engine-rpc "result")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored remote-block probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored remote-block probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored remote-block engine_newPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored remote-block eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored remote-block engine_newPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= +payload-status-syncing+
              (fixture-object-field payload-status "status"))
     "Restored remote-block engine_newPayloadV2 status mismatch")
    (devnet-smoke-gate-require
     (null (fixture-object-field payload-status "latestValidHash"))
     "Restored remote-block SYNCING status should not report latestValidHash")
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored remote-block public block number mismatch")
    (list :remote-block-hash (hash32-to-hex expected-block-hash)
          :remote-block-status (fixture-object-field payload-status "status")
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node remote-payload expected-block-hash
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet remote-block Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-invalid-tipset-rpc
    (node descendant-payload expected-latest-valid-hash
     expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (engine-fixture-payload-request 174 descendant-payload)))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 175)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-invalid-tipset"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-invalid-tipset"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload-status (fixture-object-field engine-rpc "result"))
         (validation-error
           (fixture-object-field payload-status "validationError")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored invalid-tipset probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored invalid-tipset probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored invalid-tipset engine_newPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored invalid-tipset eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored invalid-tipset engine_newPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= +payload-status-invalid+
              (fixture-object-field payload-status "status"))
     "Restored invalid-tipset engine_newPayloadV2 status mismatch")
    (devnet-smoke-gate-require
     (string= (hash32-to-hex expected-latest-valid-hash)
              (fixture-object-field payload-status "latestValidHash"))
     "Restored invalid-tipset latestValidHash mismatch")
    (devnet-smoke-gate-require
     (string= "links to previously rejected block" validation-error)
     "Restored invalid-tipset validation error mismatch: ~A"
     validation-error)
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored invalid-tipset public block number mismatch")
    (list :invalid-tipset-status
          (fixture-object-field payload-status "status")
          :invalid-tipset-validation-error validation-error
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node descendant-payload expected-latest-valid-hash
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet invalid-tipset Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-txpool-transaction-entry
    (txpool-transactions name)
  (or (cdr (assoc name txpool-transactions :test #'string=))
      (error "Missing txpool transaction entry ~A" name)))

(defun devnet-smoke-gate-transaction-hash-hex (transaction)
  (hash32-to-hex (transaction-hash transaction)))

(defun devnet-smoke-gate-transaction-raw (transaction)
  (bytes-to-hex (transaction-encoding transaction)))

(defun devnet-smoke-gate-transaction-nonce-key (transaction)
  (format nil "~D" (transaction-nonce transaction)))

(defun devnet-smoke-gate-transaction-summary (transaction)
  (let ((to (transaction-to transaction)))
    (format nil "~A: ~D wei + ~D gas x ~D wei"
            (if to
                (address-to-hex to)
                "contract creation")
            (transaction-value transaction)
            (transaction-gas-limit transaction)
            (transaction-max-fee-per-gas transaction))))

(defun devnet-smoke-gate-verify-restored-txpool-rpc
    (node txpool-transactions)
  #+sbcl
  (let* ((pending-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "pending"))
         (basefee-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "basefee"))
         (queued-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "queued"))
         (transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex pending-transaction))
         (basefee-transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex basefee-transaction))
         (queued-transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex queued-transaction))
         (raw-transaction
           (devnet-smoke-gate-transaction-raw pending-transaction))
         (basefee-raw-transaction
           (devnet-smoke-gate-transaction-raw basefee-transaction))
         (queued-raw-transaction
           (devnet-smoke-gate-transaction-raw queued-transaction))
         (transaction-summary
           (devnet-smoke-gate-transaction-summary pending-transaction))
         (basefee-transaction-summary
           (devnet-smoke-gate-transaction-summary basefee-transaction))
         (queued-transaction-summary
           (devnet-smoke-gate-transaction-summary queued-transaction))
         (sender (transaction-sender pending-transaction))
         (sender-hex (address-to-hex sender))
         (nonce-key
           (devnet-smoke-gate-transaction-nonce-key pending-transaction))
         (basefee-nonce-key
           (devnet-smoke-gate-transaction-nonce-key basefee-transaction))
         (queued-nonce-key
           (devnet-smoke-gate-transaction-nonce-key queued-transaction))
         (raw-output (make-string-output-stream))
         (basefee-raw-output (make-string-output-stream))
         (queued-raw-output (make-string-output-stream))
         (pending-output (make-string-output-stream))
         (status-output (make-string-output-stream))
         (content-output (make-string-output-stream))
         (content-from-output (make-string-output-stream))
         (inspect-output (make-string-output-stream))
         (public-requests
           (list
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 176)
                    (cons "method" "eth_getRawTransactionByHash")
                    (cons "params" (list transaction-hash-hex))))
             raw-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 181)
                    (cons "method" "eth_getRawTransactionByHash")
                    (cons "params" (list basefee-transaction-hash-hex))))
             basefee-raw-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 182)
                    (cons "method" "eth_getRawTransactionByHash")
                    (cons "params" (list queued-transaction-hash-hex))))
             queued-raw-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 177)
                    (cons "method" "eth_pendingTransactions")
                    (cons "params" '())))
             pending-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 178)
                    (cons "method" "txpool_status")
                    (cons "params" '())))
             status-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 179)
                    (cons "method" "txpool_content")
                    (cons "params" '())))
             content-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 180)
                    (cons "method" "txpool_contentFrom")
                    (cons "params" (list sender-hex))))
             content-from-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 183)
                    (cons "method" "txpool_inspect")
                    (cons "params" '())))
             inspect-output)))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-txpool"
             :accept-function (lambda () nil)
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-txpool"
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
            :max-connections 8))
         (raw-response (get-output-stream-string raw-output))
         (basefee-raw-response
           (get-output-stream-string basefee-raw-output))
         (queued-raw-response
           (get-output-stream-string queued-raw-output))
         (pending-response (get-output-stream-string pending-output))
         (status-response (get-output-stream-string status-output))
         (content-response (get-output-stream-string content-output))
         (content-from-response
           (get-output-stream-string content-from-output))
         (inspect-response (get-output-stream-string inspect-output))
         (raw-rpc (devnet-smoke-gate-rpc-body raw-response))
         (basefee-raw-rpc
           (devnet-smoke-gate-rpc-body basefee-raw-response))
         (queued-raw-rpc
           (devnet-smoke-gate-rpc-body queued-raw-response))
         (pending-rpc (devnet-smoke-gate-rpc-body pending-response))
         (status-rpc (devnet-smoke-gate-rpc-body status-response))
         (content-rpc (devnet-smoke-gate-rpc-body content-response))
         (content-from-rpc
           (devnet-smoke-gate-rpc-body content-from-response))
         (inspect-rpc (devnet-smoke-gate-rpc-body inspect-response))
         (pending-transactions
           (fixture-object-field pending-rpc "result"))
         (pending-object (first pending-transactions))
         (status (fixture-object-field status-rpc "result"))
         (content (fixture-object-field content-rpc "result"))
         (content-pending (fixture-object-field content "pending"))
         (content-sender
           (fixture-object-field content-pending sender-hex))
         (content-transaction
           (fixture-object-field content-sender nonce-key))
         (content-queued (fixture-object-field content "queued"))
         (content-queued-sender
           (fixture-object-field content-queued sender-hex))
         (content-basefee-transaction
           (fixture-object-field content-queued-sender basefee-nonce-key))
         (content-queued-transaction
           (fixture-object-field content-queued-sender queued-nonce-key))
         (content-from
           (fixture-object-field content-from-rpc "result"))
         (content-from-pending
           (fixture-object-field content-from "pending"))
         (content-from-queued
           (fixture-object-field content-from "queued"))
         (content-from-transaction
           (fixture-object-field content-from-pending nonce-key))
         (content-from-basefee-transaction
           (fixture-object-field content-from-queued basefee-nonce-key))
         (content-from-queued-transaction
           (fixture-object-field content-from-queued queued-nonce-key))
         (inspect (fixture-object-field inspect-rpc "result"))
         (inspect-pending (fixture-object-field inspect "pending"))
         (inspect-sender
           (fixture-object-field inspect-pending sender-hex))
         (inspect-transaction
           (fixture-object-field inspect-sender nonce-key))
         (inspect-queued (fixture-object-field inspect "queued"))
         (inspect-queued-sender
           (fixture-object-field inspect-queued sender-hex))
         (inspect-basefee-transaction
           (fixture-object-field inspect-queued-sender basefee-nonce-key))
         (inspect-queued-transaction
           (fixture-object-field inspect-queued-sender queued-nonce-key)))
    (devnet-smoke-gate-require
     (= 8 (getf summary :public-connections))
     "Restored txpool probe expected 8 public connections, got ~S"
     (getf summary :public-connections))
    (dolist (response (list raw-response basefee-raw-response
                            queued-raw-response pending-response
                            status-response content-response
                            content-from-response inspect-response))
      (devnet-smoke-gate-require
       (= 200 (devnet-cli-http-status response))
       "Restored txpool RPC HTTP status mismatch"))
    (devnet-smoke-gate-require
     (string= raw-transaction (fixture-object-field raw-rpc "result"))
     "Restored txpool raw transaction mismatch")
    (devnet-smoke-gate-require
     (string= basefee-raw-transaction
              (fixture-object-field basefee-raw-rpc "result"))
     "Restored basefee txpool raw transaction mismatch")
    (devnet-smoke-gate-require
     (string= queued-raw-transaction
              (fixture-object-field queued-raw-rpc "result"))
     "Restored queued txpool raw transaction mismatch")
    (devnet-smoke-gate-require
     (= 1 (length pending-transactions))
     "Restored txpool pending transaction count mismatch")
    (devnet-smoke-gate-require
     (string= transaction-hash-hex
              (fixture-object-field pending-object "hash"))
     "Restored eth_pendingTransactions hash mismatch")
    (devnet-smoke-gate-require
     (null (fixture-object-field pending-object "blockHash"))
     "Restored pending transaction should not have a block hash")
    (devnet-smoke-gate-require
     (string= "0x1" (fixture-object-field status "pending"))
     "Restored txpool_status pending count mismatch")
    (devnet-smoke-gate-require
     (string= "0x2" (fixture-object-field status "queued"))
     "Restored txpool_status queued count mismatch")
    (devnet-smoke-gate-require
     (string= transaction-hash-hex
              (fixture-object-field content-transaction "hash"))
     "Restored txpool_content hash mismatch")
    (devnet-smoke-gate-require
     (string= transaction-hash-hex
              (fixture-object-field content-from-transaction "hash"))
     "Restored txpool_contentFrom hash mismatch")
    (devnet-smoke-gate-require
     (string= basefee-transaction-hash-hex
              (fixture-object-field content-basefee-transaction "hash"))
     "Restored txpool_content basefee hash mismatch")
    (devnet-smoke-gate-require
     (string= queued-transaction-hash-hex
              (fixture-object-field content-queued-transaction "hash"))
     "Restored txpool_content queued hash mismatch")
    (devnet-smoke-gate-require
     (string= basefee-transaction-hash-hex
              (fixture-object-field content-from-basefee-transaction "hash"))
     "Restored txpool_contentFrom basefee hash mismatch")
    (devnet-smoke-gate-require
     (string= queued-transaction-hash-hex
              (fixture-object-field content-from-queued-transaction "hash"))
     "Restored txpool_contentFrom queued hash mismatch")
    (devnet-smoke-gate-require
     (string= transaction-summary inspect-transaction)
     "Restored txpool_inspect pending summary mismatch")
    (devnet-smoke-gate-require
     (string= basefee-transaction-summary inspect-basefee-transaction)
     "Restored txpool_inspect basefee summary mismatch")
    (devnet-smoke-gate-require
     (string= queued-transaction-summary inspect-queued-transaction)
     "Restored txpool_inspect queued summary mismatch")
    (list :txpool-transaction-hash transaction-hash-hex
          :txpool-raw-transaction raw-transaction
          :txpool-sender sender-hex
          :txpool-nonce nonce-key
          :txpool-inspect-summary inspect-transaction
          :txpool-basefee-transaction-hash basefee-transaction-hash-hex
          :txpool-basefee-raw-transaction basefee-raw-transaction
          :txpool-basefee-nonce basefee-nonce-key
          :txpool-basefee-inspect-summary inspect-basefee-transaction
          :txpool-queued-transaction-hash queued-transaction-hash-hex
          :txpool-queued-raw-transaction queued-raw-transaction
          :txpool-queued-nonce queued-nonce-key
          :txpool-queued-inspect-summary inspect-queued-transaction
          :txpool-status-pending
          (fixture-object-field status "pending")
          :txpool-status-queued
          (fixture-object-field status "queued")
          :txpool-content-hash
          (fixture-object-field content-transaction "hash")
          :txpool-content-from-hash
          (fixture-object-field content-from-transaction "hash")
          :txpool-basefee-content-hash
          (fixture-object-field content-basefee-transaction "hash")
          :txpool-basefee-content-from-hash
          (fixture-object-field content-from-basefee-transaction "hash")
          :txpool-queued-content-hash
          (fixture-object-field content-queued-transaction "hash")
          :txpool-queued-content-from-hash
          (fixture-object-field content-from-queued-transaction "hash")
          :public-connections (getf summary :public-connections)))
  #-sbcl
  (declare (ignore node txpool-transactions))
  #-sbcl
  (error "Restored devnet txpool RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-side-reorg-rpc
    (path side-payload side-block child-block balance-targets
     checkpoint-balance-targets transaction-checks expected-safe-block-hash
     sender-address code-address storage-address storage-key config)
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-side-reorg-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (devnet-smoke-gate-make-restored-node
                     path
                     config
                     :port 0
                     :public-port 0
                     :jwt-secret-path (namestring jwt-path)))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (primary-balance-target (first balance-targets))
                  (balance-address
                    (getf primary-balance-target :address))
                  (primary-checkpoint-balance-target
                    (first checkpoint-balance-targets))
                  (expected-checkpoint-balance
                    (getf primary-checkpoint-balance-target :balance))
                  (transaction-hash
                    (getf (first transaction-checks) :hash))
                  (expected-raw-transaction
                    (getf (first transaction-checks) :raw))
                  (transaction-hash-hex
                    (hash32-to-hex transaction-hash))
                  (displaced-transaction
                    (first (block-transactions child-block)))
                  (side-block-hash (block-hash side-block))
                  (child-block-hash (block-hash child-block))
                  (node-chain-id
                    (chain-config-chain-id
                     (ethereum-lisp.cli:devnet-node-config node)))
                  (reinsertable-transaction-p
                    (not (null
                          (transaction-sender
                           displaced-transaction
                           :expected-chain-id node-chain-id))))
                  (expected-safe-block-number
                    (quantity-to-hex
                     (1- (block-header-number
                          (block-header child-block)))))
                  (expected-side-block-number
                    (quantity-to-hex
                     (block-header-number (block-header side-block))))
                  (side-payload-output (make-string-output-stream))
                  (side-rejected-forkchoice-output
                    (make-string-output-stream))
                  (side-forkchoice-output (make-string-output-stream))
                  (side-block-number-output (make-string-output-stream))
                  (side-latest-block-output (make-string-output-stream))
                  (side-transaction-output (make-string-output-stream))
                  (side-raw-transaction-output
                    (make-string-output-stream))
                  (side-pending-transactions-output
                    (make-string-output-stream))
                  (side-receipt-output (make-string-output-stream))
                  (child-block-output (make-string-output-stream))
                  (side-block-receipts-output (make-string-output-stream))
                  (side-logs-output (make-string-output-stream))
                  (engine-requests
                    (list
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 201 side-payload))
                      side-payload-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        202 side-block-hash
                        :safe child-block-hash
                        :finalized expected-safe-block-hash))
                      side-rejected-forkchoice-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        210 side-block-hash
                        :safe expected-safe-block-hash
                        :finalized expected-safe-block-hash))
                      side-forkchoice-output)))
                  (public-requests
                    (list
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 203)
                             (cons "method" "eth_blockNumber")
                             (cons "params" '())))
                      side-block-number-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 204)
                             (cons "method" "eth_getBlockByNumber")
                             (cons "params" (list "latest" :false))))
                      side-latest-block-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 205)
                             (cons "method" "eth_getTransactionByHash")
                             (cons "params"
                                   (list (hash32-to-hex
                                          transaction-hash)))))
                      side-transaction-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 206)
                             (cons "method" "eth_getRawTransactionByHash")
                             (cons "params"
                                   (list transaction-hash-hex))))
                      side-raw-transaction-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 207)
                             (cons "method" "eth_pendingTransactions")
                             (cons "params" '())))
                      side-pending-transactions-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 208)
                             (cons "method" "eth_getTransactionReceipt")
                             (cons "params"
                                   (list transaction-hash-hex))))
                      side-receipt-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 209)
                             (cons "method" "eth_getBlockByHash")
                             (cons "params"
                                   (list (hash32-to-hex child-block-hash)
                                         :false))))
                      child-block-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 211)
                             (cons "method" "eth_getBlockReceipts")
                             (cons "params" (list "latest"))))
                      side-block-receipts-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 212)
                             (cons "method" "eth_getLogs")
                             (cons "params"
                                   (list
                                    (list
                                     (cons "fromBlock"
                                           expected-side-block-number)
                                     (cons "toBlock"
                                           expected-side-block-number))))))
                      side-logs-output)))
                  (engine-done-p nil)
                  (engine-served-count 0)
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "engine-side-reorg"
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
                               (when (= engine-served-count 3)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "public-side-reorg"
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
                             :close-function (lambda () nil)))))
                     :close-function (lambda () nil))
                     :max-connections 9))
                  (side-payload-response
                    (get-output-stream-string side-payload-output))
                  (side-rejected-forkchoice-response
                    (get-output-stream-string
                     side-rejected-forkchoice-output))
                  (side-forkchoice-response
                    (get-output-stream-string side-forkchoice-output))
                  (side-block-number-response
                    (get-output-stream-string side-block-number-output))
                  (side-latest-block-response
                    (get-output-stream-string side-latest-block-output))
                  (side-transaction-response
                    (get-output-stream-string side-transaction-output))
                  (side-raw-transaction-response
                    (get-output-stream-string side-raw-transaction-output))
                  (side-pending-transactions-response
                    (get-output-stream-string
                     side-pending-transactions-output))
                  (side-receipt-response
                    (get-output-stream-string side-receipt-output))
                  (child-block-response
                    (get-output-stream-string child-block-output))
                  (side-block-receipts-response
                    (get-output-stream-string side-block-receipts-output))
                  (side-logs-response
                    (get-output-stream-string side-logs-output))
                  (side-payload-rpc
                    (devnet-smoke-gate-rpc-body side-payload-response))
                  (side-rejected-forkchoice-rpc
                    (devnet-smoke-gate-rpc-body
                     side-rejected-forkchoice-response))
                  (side-forkchoice-rpc
                    (devnet-smoke-gate-rpc-body side-forkchoice-response))
                  (side-block-number-rpc
                    (devnet-smoke-gate-rpc-body side-block-number-response))
                  (side-latest-block-rpc
                    (devnet-smoke-gate-rpc-body side-latest-block-response))
                  (side-transaction-rpc
                    (devnet-smoke-gate-rpc-body side-transaction-response))
                  (side-raw-transaction-rpc
                    (devnet-smoke-gate-rpc-body
                     side-raw-transaction-response))
                  (side-pending-transactions-rpc
                    (devnet-smoke-gate-rpc-body
                     side-pending-transactions-response))
                  (side-receipt-rpc
                    (devnet-smoke-gate-rpc-body side-receipt-response))
                  (child-block-rpc
                    (devnet-smoke-gate-rpc-body child-block-response))
                  (side-block-receipts-rpc
                    (devnet-smoke-gate-rpc-body
                     side-block-receipts-response))
                  (side-logs-rpc
                    (devnet-smoke-gate-rpc-body side-logs-response))
                  (side-payload-result
                    (fixture-object-field side-payload-rpc "result"))
                  (side-rejected-forkchoice-error
                    (fixture-object-field side-rejected-forkchoice-rpc
                                          "error"))
                  (side-forkchoice-status
                    (fixture-object-field
                     (fixture-object-field side-forkchoice-rpc "result")
                     "payloadStatus"))
                  (side-latest-block
                    (fixture-object-field side-latest-block-rpc "result"))
                  (side-transaction
                    (fixture-object-field side-transaction-rpc "result"))
                  (side-raw-transaction
                    (fixture-object-field side-raw-transaction-rpc "result"))
                  (side-pending-transactions
                    (fixture-object-field side-pending-transactions-rpc
                                          "result"))
                  (side-pending-transaction
                    (find transaction-hash-hex side-pending-transactions
                          :test #'string=
                          :key (lambda (transaction)
                                 (fixture-object-field transaction
                                                       "hash"))))
                  (child-block-by-hash
                    (fixture-object-field child-block-rpc "result"))
                  (side-block-receipts
                    (fixture-object-field side-block-receipts-rpc "result"))
                  (side-logs
                    (fixture-object-field side-logs-rpc "result")))
             (devnet-smoke-gate-require
              (= 3 (getf summary :engine-connections))
              "Expected 3 side-reorg Engine connections, got ~S"
              (getf summary :engine-connections))
             (devnet-smoke-gate-require
              (= 9 (getf summary :public-connections))
              "Expected 9 side-reorg public connections, got ~S"
              (getf summary :public-connections))
             (dolist (response
                      (list side-payload-response
                            side-rejected-forkchoice-response
                            side-forkchoice-response
	                            side-block-number-response
	                            side-latest-block-response
	                            side-transaction-response
                                    side-raw-transaction-response
                                    side-pending-transactions-response
	                            side-receipt-response child-block-response
                                    side-block-receipts-response
                                    side-logs-response))
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status response))
                "Restored side-reorg RPC HTTP status mismatch"))
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field side-payload-result "status"))
              "Restored side sibling engine_newPayloadV2 status mismatch")
             (devnet-smoke-gate-require
              (string= (hash32-to-hex side-block-hash)
                       (fixture-object-field side-payload-result
                                             "latestValidHash"))
              "Restored side sibling latestValidHash mismatch")
             (devnet-smoke-gate-require
              (= -38002
                 (fixture-object-field side-rejected-forkchoice-error
                                       "code"))
              "Restored side sibling rejected checkpoint error code mismatch")
             (devnet-smoke-gate-require
              (string= "forkchoice safe block is not an ancestor of head"
                       (fixture-object-field side-rejected-forkchoice-error
                                             "message"))
              "Restored side sibling rejected checkpoint error mismatch")
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field side-forkchoice-status "status"))
              "Restored side sibling forkchoice status mismatch")
             (devnet-smoke-gate-require
              (string= expected-side-block-number
                       (fixture-object-field side-block-number-rpc "result"))
              "Restored side sibling eth_blockNumber mismatch")
             (devnet-smoke-gate-require
              (string= (hash32-to-hex side-block-hash)
                       (fixture-object-field side-latest-block "hash"))
              "Restored side sibling latest block hash mismatch")
             (if reinsertable-transaction-p
                 (progn
                   (devnet-smoke-gate-require
                    (string= transaction-hash-hex
                             (fixture-object-field side-transaction "hash"))
                    "Restored side sibling should reinsert old canonical transaction")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction "blockHash"))
                    "Restored side sibling transaction should be pending")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction
                                                "blockNumber"))
                    "Restored side sibling transaction should not have a block number")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction
                                                "transactionIndex"))
                    "Restored side sibling transaction should not have an index")
                   (devnet-smoke-gate-require
                    (string= expected-raw-transaction side-raw-transaction)
                    "Restored side sibling should expose pending raw transaction")
                   (devnet-smoke-gate-require
                    side-pending-transaction
                    "Restored side sibling should expose displaced transaction in pending view")
                   (devnet-smoke-gate-require
                    (string= transaction-hash-hex
                             (fixture-object-field side-pending-transaction
                                                   "hash"))
                    "Restored side sibling pending view transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "blockHash"))
                    "Restored side sibling pending view should not have a block hash")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "blockNumber"))
                    "Restored side sibling pending view should not have a block number")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "transactionIndex"))
                    "Restored side sibling pending view should not have an index"))
               (progn
                 (devnet-smoke-gate-require
                  (null side-transaction)
                  "Restored side sibling should reject wrong-chain displaced transaction")
                 (devnet-smoke-gate-require
                  (null side-raw-transaction)
                  "Restored side sibling should hide wrong-chain raw transaction")
                 (devnet-smoke-gate-require
                  (null side-pending-transaction)
                  "Restored side sibling should hide wrong-chain pending transaction")))
             (devnet-smoke-gate-require
              (null (fixture-object-field side-receipt-rpc "result"))
              "Restored side sibling should hide old canonical receipt")
	             (devnet-smoke-gate-require
	              (string= (hash32-to-hex child-block-hash)
	                       (fixture-object-field child-block-by-hash "hash"))
	              "Restored side sibling lost child block hash lookup")
	             (devnet-smoke-gate-require
	              (zerop (length side-block-receipts))
	              "Restored side sibling should have no canonical receipts")
	             (devnet-smoke-gate-require
	              (zerop (length side-logs))
	              "Restored side sibling should have no canonical logs")
             (ethereum-lisp.cli::devnet-node-export-database node)
             (let* ((fresh-node
                      (devnet-smoke-gate-make-restored-node
                       path config :port 0))
                    (fresh-summary
                      (ethereum-lisp.cli:devnet-node-summary fresh-node))
                    (fresh-raw-transaction-output
                      (make-string-output-stream))
                    (fresh-pending-transactions-output
                      (make-string-output-stream))
                    (fresh-receipt-output
                      (make-string-output-stream))
                    (fresh-block-number-output
                      (make-string-output-stream))
                    (fresh-latest-block-output
                      (make-string-output-stream))
                    (fresh-child-block-output
                      (make-string-output-stream))
                    (fresh-block-receipts-output
                      (make-string-output-stream))
                    (fresh-logs-output
                      (make-string-output-stream))
                    (fresh-safe-block-output
                      (make-string-output-stream))
                    (fresh-finalized-block-output
                      (make-string-output-stream))
                    (fresh-safe-balance-output
                      (make-string-output-stream))
                    (fresh-finalized-balance-output
                      (make-string-output-stream))
                    (fresh-child-require-canonical-state-probes
                      (devnet-smoke-gate-state-error-probes
                       225
                       (list
                        (cons "blockHash" (hash32-to-hex child-block-hash))
                        (cons "requireCanonical" t))
                       (devnet-smoke-gate-noncanonical-state-error-messages)
                       balance-address
                       sender-address
                       code-address
                       storage-address
                       storage-key))
                    (fresh-public-requests
                      (append
                       (list
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 213)
                                (cons "method" "eth_getRawTransactionByHash")
                                (cons "params" (list transaction-hash-hex))))
                         fresh-raw-transaction-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 214)
                                (cons "method" "eth_pendingTransactions")
                                (cons "params" '())))
                         fresh-pending-transactions-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 215)
                                (cons "method" "eth_getTransactionReceipt")
                                (cons "params" (list transaction-hash-hex))))
                         fresh-receipt-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 216)
                                (cons "method" "eth_blockNumber")
                                (cons "params" '())))
                         fresh-block-number-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 217)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "latest" :false))))
                         fresh-latest-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 218)
                                (cons "method" "eth_getBlockByHash")
                                (cons "params"
                                      (list (hash32-to-hex child-block-hash)
                                            :false))))
                         fresh-child-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 219)
                                (cons "method" "eth_getBlockReceipts")
                                (cons "params" (list "latest"))))
                         fresh-block-receipts-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 220)
                                (cons "method" "eth_getLogs")
                                (cons "params"
                                      (list
                                       (list
                                        (cons "fromBlock"
                                              expected-side-block-number)
                                        (cons "toBlock"
                                              expected-side-block-number))))))
                         fresh-logs-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 221)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "safe" :false))))
                         fresh-safe-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 222)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "finalized" :false))))
                         fresh-finalized-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 223)
                                (cons "method" "eth_getBalance")
                                (cons "params"
                                      (list (address-to-hex balance-address)
                                            "safe"))))
                         fresh-safe-balance-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 224)
                                (cons "method" "eth_getBalance")
                                (cons "params"
                                      (list (address-to-hex balance-address)
                                            "finalized"))))
                         fresh-finalized-balance-output))
                       (mapcar
                        (lambda (probe)
                          (cons (json-encode (getf probe :request))
                                (getf probe :output)))
                        fresh-child-require-canonical-state-probes)))
                    (fresh-rpc-summary
                      (ethereum-lisp.cli:start-devnet-node-listeners
                       fresh-node
                       (make-engine-rpc-http-listener
                        :endpoint "engine-side-reorg-fresh-restore"
                        :accept-function (lambda () nil)
                        :close-function (lambda () nil))
                       (make-engine-rpc-http-listener
                        :endpoint "public-side-reorg-fresh-restore"
                        :accept-function
                        (lambda ()
                          (when fresh-public-requests
                            (destructuring-bind (body . output)
                                (pop fresh-public-requests)
                              (make-engine-rpc-http-connection
                               :input-stream
                               (make-string-input-stream
                                (devnet-cli-json-rpc-http-request body))
                               :output-stream output
                               :close-function (lambda () nil)))))
                       :close-function (lambda () nil))
                       :max-connections 20))
                    (fresh-raw-transaction-response
                      (get-output-stream-string
                       fresh-raw-transaction-output))
                    (fresh-pending-transactions-response
                      (get-output-stream-string
                       fresh-pending-transactions-output))
                    (fresh-receipt-response
                      (get-output-stream-string fresh-receipt-output))
                    (fresh-block-number-response
                      (get-output-stream-string fresh-block-number-output))
                    (fresh-latest-block-response
                      (get-output-stream-string fresh-latest-block-output))
                    (fresh-child-block-response
                      (get-output-stream-string fresh-child-block-output))
                    (fresh-block-receipts-response
                      (get-output-stream-string fresh-block-receipts-output))
                    (fresh-logs-response
                      (get-output-stream-string fresh-logs-output))
                    (fresh-safe-block-response
                      (get-output-stream-string fresh-safe-block-output))
                    (fresh-finalized-block-response
                      (get-output-stream-string fresh-finalized-block-output))
                    (fresh-safe-balance-response
                      (get-output-stream-string fresh-safe-balance-output))
                    (fresh-finalized-balance-response
                      (get-output-stream-string
                       fresh-finalized-balance-output))
                    (fresh-raw-transaction-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-raw-transaction-response))
                    (fresh-pending-transactions-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-pending-transactions-response))
                    (fresh-receipt-rpc
                      (devnet-smoke-gate-rpc-body fresh-receipt-response))
                    (fresh-block-number-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-block-number-response))
                    (fresh-latest-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-latest-block-response))
                    (fresh-child-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-child-block-response))
                    (fresh-block-receipts-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-block-receipts-response))
                    (fresh-logs-rpc
                      (devnet-smoke-gate-rpc-body fresh-logs-response))
                    (fresh-safe-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-safe-block-response))
                    (fresh-finalized-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-finalized-block-response))
                    (fresh-safe-balance-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-safe-balance-response))
                    (fresh-finalized-balance-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-finalized-balance-response))
                    (fresh-raw-transaction
                      (fixture-object-field fresh-raw-transaction-rpc
                                            "result"))
                    (fresh-pending-transactions
                      (fixture-object-field fresh-pending-transactions-rpc
                                            "result"))
                    (fresh-pending-transaction
                      (find transaction-hash-hex fresh-pending-transactions
                            :test #'string=
                            :key (lambda (transaction)
                                   (fixture-object-field transaction
                                                         "hash"))))
                    (fresh-latest-block
                      (fixture-object-field fresh-latest-block-rpc "result"))
                    (fresh-child-block
                      (fixture-object-field fresh-child-block-rpc "result"))
                    (fresh-block-receipts
                      (fixture-object-field fresh-block-receipts-rpc
                                            "result"))
                    (fresh-logs
                      (fixture-object-field fresh-logs-rpc "result"))
                    (fresh-safe-block
                      (fixture-object-field fresh-safe-block-rpc "result"))
                    (fresh-finalized-block
                      (fixture-object-field fresh-finalized-block-rpc
                                            "result"))
                    (fresh-safe-balance
                      (fixture-object-field fresh-safe-balance-rpc
                                            "result"))
                    (fresh-finalized-balance
                      (fixture-object-field fresh-finalized-balance-rpc
                                            "result"))
                    (fresh-child-require-canonical-state-errors
                      (devnet-smoke-gate-verify-state-error-probes
                       fresh-child-require-canonical-state-probes
                       "noncanonical-state")))
               (devnet-smoke-gate-require
                (= (block-header-number (block-header side-block))
                   (getf fresh-summary :head-number))
                "Side-reorg database restore head number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex side-block-hash)
                         (getf fresh-summary :head-hash))
                "Side-reorg database restore head hash mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (getf fresh-summary :safe-hash))
                "Side-reorg database restore safe hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (quantity-to-hex
                          (getf fresh-summary :safe-number)))
                "Side-reorg database restore safe number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (getf fresh-summary :finalized-hash))
                "Side-reorg database restore finalized hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (quantity-to-hex
                          (getf fresh-summary :finalized-number)))
                "Side-reorg database restore finalized number mismatch")
               (devnet-smoke-gate-require
                (chain-store-known-block
                 (ethereum-lisp.cli:devnet-node-store fresh-node)
                 child-block-hash)
                "Side-reorg database restore lost old child block")
               (devnet-smoke-gate-require
                (= 0 (getf fresh-rpc-summary :engine-connections))
                "Fresh side-reorg restore expected 0 Engine connections, got ~S"
                (getf fresh-rpc-summary :engine-connections))
               (devnet-smoke-gate-require
                (= 20 (getf fresh-rpc-summary :public-connections))
                "Fresh side-reorg restore expected 20 public connections, got ~S"
                (getf fresh-rpc-summary :public-connections))
               (dolist (response (list fresh-raw-transaction-response
                                        fresh-pending-transactions-response
                                        fresh-receipt-response
                                        fresh-block-number-response
                                        fresh-latest-block-response
                                        fresh-child-block-response
                                        fresh-block-receipts-response
                                        fresh-logs-response
                                        fresh-safe-block-response
                                        fresh-finalized-block-response
                                        fresh-safe-balance-response
                                        fresh-finalized-balance-response))
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status response))
                  "Fresh side-reorg restore public RPC HTTP status mismatch"))
               (if reinsertable-transaction-p
                   (progn
                     (devnet-smoke-gate-require
                      (string= expected-raw-transaction
                               fresh-raw-transaction)
                      "Fresh side-reorg restore lost pending raw transaction")
                     (devnet-smoke-gate-require
                      fresh-pending-transaction
                      "Fresh side-reorg restore lost pending transaction view")
                     (devnet-smoke-gate-require
                      (string= transaction-hash-hex
                               (fixture-object-field
                                fresh-pending-transaction
                                "hash"))
                      "Fresh side-reorg restore pending transaction hash mismatch")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "blockHash"))
                      "Fresh side-reorg restore pending view kept old block hash")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "blockNumber"))
                      "Fresh side-reorg restore pending view kept old block number")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "transactionIndex"))
                      "Fresh side-reorg restore pending view kept old index"))
                 (progn
                   (devnet-smoke-gate-require
                    (null fresh-raw-transaction)
                    "Fresh side-reorg restore exposed wrong-chain raw transaction")
                   (devnet-smoke-gate-require
                    (null fresh-pending-transaction)
                    "Fresh side-reorg restore exposed wrong-chain pending transaction")))
               (devnet-smoke-gate-require
                (null (fixture-object-field fresh-receipt-rpc "result"))
                "Fresh side-reorg restore kept old canonical receipt")
               (devnet-smoke-gate-require
                (string= expected-side-block-number
                         (fixture-object-field fresh-block-number-rpc
                                               "result"))
                "Fresh side-reorg restore public block number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex side-block-hash)
                         (fixture-object-field fresh-latest-block "hash"))
                "Fresh side-reorg restore latest block hash mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex child-block-hash)
                         (fixture-object-field fresh-child-block "hash"))
                "Fresh side-reorg restore lost old child block hash lookup")
               (devnet-smoke-gate-require
                (equal (devnet-smoke-gate-noncanonical-state-error-messages)
                       fresh-child-require-canonical-state-errors)
                "Fresh side-reorg restore child requireCanonical state errors mismatch")
               (devnet-smoke-gate-require
                (zerop (length fresh-block-receipts))
                "Fresh side-reorg restore kept canonical receipts")
               (devnet-smoke-gate-require
                (zerop (length fresh-logs))
                "Fresh side-reorg restore kept canonical logs")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (fixture-object-field fresh-safe-block "hash"))
                "Fresh side-reorg restore safe block hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (fixture-object-field fresh-safe-block "number"))
                "Fresh side-reorg restore safe block number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (fixture-object-field fresh-finalized-block "hash"))
                "Fresh side-reorg restore finalized block hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (fixture-object-field fresh-finalized-block "number"))
                "Fresh side-reorg restore finalized block number mismatch")
               (devnet-smoke-gate-require
                (string= expected-checkpoint-balance fresh-safe-balance)
                "Fresh side-reorg restore safe balance mismatch")
               (devnet-smoke-gate-require
                (string= expected-checkpoint-balance
                         fresh-finalized-balance)
                "Fresh side-reorg restore finalized balance mismatch")
               (list :side-block-hash (hash32-to-hex side-block-hash)
                     :side-forkchoice-status
                     (fixture-object-field side-forkchoice-status "status")
                     :side-rejected-checkpoint-error
                     (fixture-object-field side-rejected-forkchoice-error
                                           "message")
                     :side-block-number
                     (fixture-object-field side-block-number-rpc "result")
                     :side-latest-block-hash
                     (fixture-object-field side-latest-block "hash")
                     :side-transaction-reinserted-p
                     (if reinsertable-transaction-p t :false)
                     :side-transaction-by-hash
                     (or side-transaction :false)
                     :side-raw-transaction
                     (or side-raw-transaction :false)
                     :side-pending-transaction
                     (or side-pending-transaction :false)
                     :side-receipt
                     (or (fixture-object-field side-receipt-rpc "result")
                         :false)
	                     :side-child-block-hash
	                     (fixture-object-field child-block-by-hash "hash")
                             :side-block-receipts-count
                             (length side-block-receipts)
                             :side-log-count
                             (length side-logs)
	                     :side-restored-head-number
                     (quantity-to-hex (getf fresh-summary :head-number))
                     :side-restored-head-hash
                     (getf fresh-summary :head-hash)
                     :side-restored-rpc-block-number
                     (fixture-object-field fresh-block-number-rpc "result")
                     :side-restored-rpc-latest-block-hash
                     (fixture-object-field fresh-latest-block "hash")
                     :side-restored-safe-number
                     (quantity-to-hex (getf fresh-summary :safe-number))
                     :side-restored-safe-hash
                     (getf fresh-summary :safe-hash)
                     :side-restored-finalized-number
                     (quantity-to-hex
                      (getf fresh-summary :finalized-number))
                     :side-restored-finalized-hash
                     (getf fresh-summary :finalized-hash)
                     :side-restored-rpc-safe-number
                     (fixture-object-field fresh-safe-block "number")
                     :side-restored-rpc-safe-hash
                     (fixture-object-field fresh-safe-block "hash")
                     :side-restored-rpc-finalized-number
                     (fixture-object-field fresh-finalized-block "number")
                     :side-restored-rpc-finalized-hash
                     (fixture-object-field fresh-finalized-block "hash")
                     :side-restored-safe-balance
                     fresh-safe-balance
                     :side-restored-finalized-balance
                     fresh-finalized-balance
                     :side-restored-raw-transaction
                     (or fresh-raw-transaction :false)
                     :side-restored-pending-transaction
                     (or fresh-pending-transaction :false)
                     :side-restored-receipt
                     (or (fixture-object-field fresh-receipt-rpc "result")
                         :false)
                     :side-restored-child-block-hash
                     (fixture-object-field fresh-child-block "hash")
                     :side-restored-child-require-canonical-error
                     (first fresh-child-require-canonical-state-errors)
                     :side-restored-child-require-canonical-errors
                     fresh-child-require-canonical-state-errors
                     :side-restored-block-receipts-count
                     (length fresh-block-receipts)
                     :side-restored-log-count
                     (length fresh-logs)
                     :side-restored-public-connections
                     (getf fresh-rpc-summary :public-connections)
                     :engine-connections (getf summary :engine-connections)
                     :public-connections
                     (getf summary :public-connections)))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (declare (ignore path side-payload side-block child-block transaction-checks
                   balance-targets expected-safe-block-hash sender-address
                   code-address storage-address storage-key config))
  #-sbcl
  (error "Restored devnet side reorg RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-database
    (path expected-block-number balance-targets
     sender-address expected-sender-nonce
     code-address expected-code storage-address storage-key expected-storage
     transaction-checks log-targets block-hash
     expected-safe-block-number expected-safe-block-hash
     expected-finalized-block-number expected-finalized-block-hash
     config
     &key state-prune-before pruned-state-hash
          checkpoint-balance-targets
          prepared-payload-id prepared-payload-parent-hash
          prepared-payload-block-number
          remote-payload remote-block
          invalid-block invalid-descendant-payload
          txpool-transactions
          side-payload side-block child-block)
  (let* ((database (make-file-key-value-database path))
         (node
           (devnet-smoke-gate-make-restored-node path config :port 0))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (restored-store (ethereum-lisp.cli:devnet-node-store node))
         (pruned-state-expected-p
           (and state-prune-before
                pruned-state-hash
                (< (hex-to-quantity expected-safe-block-number)
                   state-prune-before)))
         (public-rpc-summary
           (devnet-smoke-gate-verify-restored-public-rpc
            node
            expected-block-number
            balance-targets
            sender-address
            expected-sender-nonce
            code-address
            expected-code
            storage-address
            storage-key
            expected-storage
            transaction-checks
            log-targets
            block-hash
            expected-safe-block-number
            expected-safe-block-hash
            expected-finalized-block-number
            expected-finalized-block-hash
            :pruned-state-rpc-tag
            (when pruned-state-expected-p "safe")))
         (engine-rpc-summary
           (and prepared-payload-id
                (devnet-smoke-gate-verify-restored-engine-rpc
                 node
                 prepared-payload-id
                 prepared-payload-parent-hash
                 prepared-payload-block-number
                 expected-block-number)))
         (remote-block-hash (and remote-block (block-hash remote-block)))
         (restored-remote-block
           (and remote-block-hash
                (ethereum-lisp.core::engine-payload-store-remote-block
                 restored-store remote-block-hash)))
         (remote-block-rpc-summary
           (and remote-payload
                remote-block
                (devnet-smoke-gate-verify-restored-remote-block-rpc
                 node
                 remote-payload
                 remote-block-hash
                 expected-block-number)))
         (invalid-block-hash (and invalid-block (block-hash invalid-block)))
         (restored-invalid-block
           (and invalid-block-hash
                (ethereum-lisp.core::engine-payload-store-invalid-block
                 restored-store invalid-block-hash)))
         (invalid-tipset-rpc-summary
           (and invalid-block
                invalid-descendant-payload
                (devnet-smoke-gate-verify-restored-invalid-tipset-rpc
                 node
                 invalid-descendant-payload
                 (block-header-parent-hash (block-header invalid-block))
                 expected-block-number)))
         (txpool-rpc-summary
           (and txpool-transactions
                (devnet-smoke-gate-verify-restored-txpool-rpc
                 node txpool-transactions)))
         (side-reorg-rpc-summary
           (and (not state-prune-before)
                side-payload
                side-block
                child-block
                (devnet-smoke-gate-verify-restored-side-reorg-rpc
                 path
                 side-payload
                 side-block
                 child-block
                 balance-targets
                 checkpoint-balance-targets
                 transaction-checks
                 expected-safe-block-hash
                 sender-address
                 code-address
                 storage-address
                 storage-key
                 config))))
    (devnet-smoke-gate-require
     (< 0 (length (kv-chain-record-entries database :block)))
     "Database export did not write block records")
    (devnet-smoke-gate-require
     (< 0 (length (kv-chain-record-entries database :canonical-hash)))
     "Database export did not write canonical hash records")
    (when prepared-payload-id
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :prepared-payload)))
       "Database export did not write prepared payload records"))
    (when remote-block
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :remote-block)))
       "Database export did not write remote block records")
      (devnet-smoke-gate-require
       restored-remote-block
       "Database restore did not publish the remote block cache")
      (devnet-smoke-gate-require
       (bytes= (block-rlp remote-block)
               (block-rlp restored-remote-block))
       "Database restore changed the remote block RLP"))
    (when invalid-block
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :invalid-tipset)))
       "Database export did not write invalid-tipset records")
      (devnet-smoke-gate-require
       restored-invalid-block
       "Database restore did not publish the invalid-tipset cache")
      (devnet-smoke-gate-require
       (bytes= (block-rlp invalid-block)
               (block-rlp restored-invalid-block))
       "Database restore changed the invalid-tipset block RLP"))
    (when txpool-transactions
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :txpool)))
       "Database export did not write txpool records"))
    (devnet-smoke-gate-require
     (= (hex-to-quantity expected-block-number)
        (getf summary :head-number))
     "Database restored head mismatch: expected ~A got ~A"
     expected-block-number
     (quantity-to-hex (getf summary :head-number)))
    (devnet-smoke-gate-require
     (string= path (getf summary :database-path))
     "Database path missing from restored node summary")
    (when pruned-state-expected-p
      (devnet-smoke-gate-require
       (chain-store-known-block restored-store pruned-state-hash)
       "Pruned-state block was not restored by hash")
      (devnet-smoke-gate-require
       (not (chain-store-state-available-p restored-store pruned-state-hash))
       "Pruned state snapshot is still available after restore"))
    (append summary
            (list :pruned-state-before state-prune-before
                  :pruned-state-available-p
                  (and pruned-state-hash
                       (chain-store-state-available-p
                        restored-store pruned-state-hash))
                  :rpc-block-number
                  (getf public-rpc-summary :block-number)
                  :rpc-balance
                  (getf public-rpc-summary :balance)
                  :rpc-nonce
                  (getf public-rpc-summary :nonce)
                  :rpc-code
                  (getf public-rpc-summary :code)
                  :rpc-storage
                  (getf public-rpc-summary :storage)
                  :rpc-proof-address
                  (getf public-rpc-summary :proof-address)
                  :rpc-proof-code-hash
                  (getf public-rpc-summary :proof-code-hash)
                  :rpc-proof-storage-key
                  (getf public-rpc-summary :proof-storage-key)
                  :rpc-proof-storage-value
                  (getf public-rpc-summary :proof-storage-value)
                  :rpc-proof-storage-count
                  (getf public-rpc-summary :proof-storage-count)
                  :rpc-proof-account-proof-count
                  (getf public-rpc-summary :proof-account-proof-count)
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
                  :rpc-full-block-transaction-count
                  (getf public-rpc-summary
                        :full-block-transaction-count)
                  :rpc-full-block-transaction-hash
                  (getf public-rpc-summary :full-block-transaction-hash)
                  :rpc-full-block-transaction-index
                  (getf public-rpc-summary :full-block-transaction-index)
                  :rpc-full-block-by-number-transaction-count
                  (getf public-rpc-summary
                        :full-block-by-number-transaction-count)
                  :rpc-full-block-by-number-transaction-hash
                  (getf public-rpc-summary
                        :full-block-by-number-transaction-hash)
                  :rpc-full-block-by-number-transaction-index
                  (getf public-rpc-summary
                        :full-block-by-number-transaction-index)
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
                  :rpc-block-transaction-count-by-hash
                  (getf public-rpc-summary
                        :block-transaction-count-by-hash)
                  :rpc-block-transaction-count-by-number
                  (getf public-rpc-summary
                        :block-transaction-count-by-number)
                  :rpc-canonical-hash-balance
                  (getf public-rpc-summary :canonical-hash-balance)
                  :rpc-canonical-hash-require-balance
                  (getf public-rpc-summary
                        :canonical-hash-require-balance)
                  :rpc-transaction-count
                  (getf public-rpc-summary :transaction-count)
                  :rpc-balance-count
                  (getf public-rpc-summary :balance-count)
                  :rpc-log-count
                  (getf public-rpc-summary :log-count)
                  :rpc-raw-transaction
                  (getf public-rpc-summary :raw-transaction)
                  :rpc-raw-transaction-by-hash
                  (getf public-rpc-summary :raw-transaction-by-hash)
                  :rpc-raw-transaction-by-number
                  (getf public-rpc-summary :raw-transaction-by-number)
                  :rpc-transaction-by-hash-index-hash
                  (getf public-rpc-summary
                        :transaction-by-hash-index-hash)
                  :rpc-transaction-by-hash-index-block-hash
                  (getf public-rpc-summary
                        :transaction-by-hash-index-block-hash)
                  :rpc-transaction-by-hash-index-block-number
                  (getf public-rpc-summary
                        :transaction-by-hash-index-block-number)
                  :rpc-transaction-by-hash-index-transaction-index
                  (getf public-rpc-summary
                        :transaction-by-hash-index-transaction-index)
                  :rpc-transaction-by-number-index-hash
                  (getf public-rpc-summary
                        :transaction-by-number-index-hash)
                  :rpc-transaction-by-number-index-block-hash
                  (getf public-rpc-summary
                        :transaction-by-number-index-block-hash)
                  :rpc-transaction-by-number-index-block-number
                  (getf public-rpc-summary
                        :transaction-by-number-index-block-number)
                  :rpc-transaction-by-number-index-transaction-index
                  (getf public-rpc-summary
                        :transaction-by-number-index-transaction-index)
                  :rpc-safe-block-hash
                  (getf public-rpc-summary :safe-block-hash)
                  :rpc-safe-block-number
                  (getf public-rpc-summary :safe-block-number)
                  :rpc-finalized-block-hash
                  (getf public-rpc-summary :finalized-block-hash)
                  :rpc-finalized-block-number
                  (getf public-rpc-summary :finalized-block-number)
                  :rpc-call-result
                  (getf public-rpc-summary :call-result)
                  :rpc-failed-call-error-message
                  (getf public-rpc-summary :failed-call-error-message)
                  :rpc-estimate-gas
                  (getf public-rpc-summary :estimate-gas)
                  :rpc-access-list-count
                  (getf public-rpc-summary :access-list-count)
                  :rpc-access-list-gas-used
                  (getf public-rpc-summary :access-list-gas-used)
                  :rpc-post-call-storage
                  (getf public-rpc-summary :post-call-storage)
                  :rpc-simulation-count
                  (getf public-rpc-summary :simulation-count)
                  :rpc-pruned-state-error-message
                  (getf public-rpc-summary :pruned-state-error-message)
                  :rpc-pruned-state-error-messages
                  (getf public-rpc-summary :pruned-state-error-messages)
                  :rpc-public-connections
                  (getf public-rpc-summary :public-connections)
                  :rpc-prepared-payload-id
                  (and engine-rpc-summary
                       (getf engine-rpc-summary :prepared-payload-id))
                  :rpc-prepared-payload-parent-hash
                  (and engine-rpc-summary
                       (getf engine-rpc-summary
                             :prepared-payload-parent-hash))
                  :rpc-prepared-payload-block-number
                  (and engine-rpc-summary
                       (getf engine-rpc-summary
                             :prepared-payload-block-number))
                  :rpc-engine-connections
                  (and engine-rpc-summary
                       (getf engine-rpc-summary :engine-connections))
                  :remote-block-hash
                  (and remote-block-rpc-summary
                       (getf remote-block-rpc-summary :remote-block-hash))
                  :rpc-remote-block-status
                  (and remote-block-rpc-summary
                       (getf remote-block-rpc-summary :remote-block-status))
                  :rpc-remote-block-engine-connections
                  (and remote-block-rpc-summary
                       (getf remote-block-rpc-summary
                             :engine-connections))
                  :invalid-tipset-block-hash
                  (and invalid-block
                       (hash32-to-hex (block-hash invalid-block)))
                  :rpc-invalid-tipset-status
                  (and invalid-tipset-rpc-summary
                       (getf invalid-tipset-rpc-summary
                             :invalid-tipset-status))
                  :rpc-invalid-tipset-validation-error
                  (and invalid-tipset-rpc-summary
                       (getf invalid-tipset-rpc-summary
                             :invalid-tipset-validation-error))
                  :rpc-invalid-tipset-engine-connections
                  (and invalid-tipset-rpc-summary
                       (getf invalid-tipset-rpc-summary
                             :engine-connections))
                  :rpc-txpool-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-transaction-hash))
                  :rpc-txpool-raw-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-raw-transaction))
                  :rpc-txpool-sender
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary :txpool-sender))
                  :rpc-txpool-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary :txpool-nonce))
                  :rpc-txpool-inspect-summary
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-inspect-summary))
                  :rpc-txpool-basefee-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-transaction-hash))
                  :rpc-txpool-basefee-raw-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-raw-transaction))
                  :rpc-txpool-basefee-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-nonce))
                  :rpc-txpool-basefee-inspect-summary
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-inspect-summary))
                  :rpc-txpool-queued-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-transaction-hash))
                  :rpc-txpool-queued-raw-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-raw-transaction))
                  :rpc-txpool-queued-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-nonce))
                  :rpc-txpool-queued-inspect-summary
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-inspect-summary))
                  :rpc-txpool-status-pending
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-status-pending))
                  :rpc-txpool-status-queued
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-status-queued))
                  :rpc-txpool-content-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-content-hash))
                  :rpc-txpool-content-from-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-content-from-hash))
                  :rpc-txpool-basefee-content-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-content-hash))
                  :rpc-txpool-basefee-content-from-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-content-from-hash))
                  :rpc-txpool-queued-content-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-content-hash))
                  :rpc-txpool-queued-content-from-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-content-from-hash))
                  :rpc-txpool-public-connections
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :public-connections))
                  :rpc-side-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-block-hash))
                  :rpc-side-forkchoice-status
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-forkchoice-status))
                  :rpc-side-rejected-checkpoint-error
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-rejected-checkpoint-error))
                  :rpc-side-block-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-block-number))
                  :rpc-side-latest-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-latest-block-hash))
                  :rpc-side-transaction-reinserted-p
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-transaction-reinserted-p))
                  :rpc-side-transaction-by-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-transaction-by-hash))
                  :rpc-side-raw-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-raw-transaction))
                  :rpc-side-pending-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-pending-transaction))
                  :rpc-side-receipt
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-receipt))
                  :rpc-side-child-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-child-block-hash))
                  :rpc-side-block-receipts-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-block-receipts-count))
                  :rpc-side-log-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-log-count))
                  :rpc-side-restored-head-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-head-number))
                  :rpc-side-restored-head-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-head-hash))
                  :rpc-side-restored-rpc-block-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-block-number))
                  :rpc-side-restored-rpc-latest-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-latest-block-hash))
                  :rpc-side-restored-safe-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-safe-number))
                  :rpc-side-restored-safe-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-safe-hash))
                  :rpc-side-restored-finalized-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-finalized-number))
                  :rpc-side-restored-finalized-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-finalized-hash))
                  :rpc-side-restored-rpc-safe-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-safe-number))
                  :rpc-side-restored-rpc-safe-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-safe-hash))
                  :rpc-side-restored-rpc-finalized-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-finalized-number))
                  :rpc-side-restored-rpc-finalized-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-finalized-hash))
                  :rpc-side-restored-safe-balance
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-safe-balance))
                  :rpc-side-restored-finalized-balance
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-finalized-balance))
                  :rpc-side-restored-raw-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-raw-transaction))
                  :rpc-side-restored-pending-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-pending-transaction))
                  :rpc-side-restored-receipt
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-receipt))
                  :rpc-side-restored-child-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-child-block-hash))
                  :rpc-side-restored-child-require-canonical-error
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-child-require-canonical-error))
                  :rpc-side-restored-child-require-canonical-errors
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-child-require-canonical-errors))
                  :rpc-side-restored-block-receipts-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-block-receipts-count))
                  :rpc-side-restored-log-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-log-count))
                  :rpc-side-restored-public-connections
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-public-connections))
                  :rpc-side-engine-connections
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :engine-connections))
                  :rpc-side-public-connections
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :public-connections))))))

(defun devnet-smoke-gate-run
    (case-name &key ready-file log-file pid-file database-file
       state-prune-before)
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
                             (side-block
                               (devnet-smoke-gate-field fixture
                                                        "sideBlock"))
                             (side-payload
                               (devnet-smoke-gate-field fixture
                                                        "sidePayload"))
                             (txpool-transactions
                               (devnet-smoke-gate-field
                                fixture "txpoolTransactions"))
                             (pending-transaction
                               (devnet-smoke-gate-txpool-transaction-entry
                                txpool-transactions "pending"))
                             (basefee-transaction
                               (devnet-smoke-gate-txpool-transaction-entry
                                txpool-transactions "basefee"))
                             (queued-transaction
                               (devnet-smoke-gate-txpool-transaction-entry
                                txpool-transactions "queued"))
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
                                :pid-file-path pid-file
                                :telemetry-sink telemetry-sink))
                  (balance-address nil)
                  (expected-balance nil)
                  (balance-field nil)
                  (sender-address nil)
                  (expected-sender-nonce nil)
                  (code-address nil)
                  (expected-code nil)
                  (storage-address nil)
                  (storage-key nil)
                  (expected-storage nil)
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (new-payload-output (make-string-output-stream))
                  (forkchoice-output (make-string-output-stream))
                  (prepare-payload-output (make-string-output-stream))
                  (remote-payload-output (make-string-output-stream))
                  (invalid-payload-output (make-string-output-stream))
                  (block-number-output (make-string-output-stream))
                  (balance-output (make-string-output-stream))
                  (prepared-public-output (make-string-output-stream))
                  (remote-public-output (make-string-output-stream))
                  (invalid-public-output (make-string-output-stream))
                  (send-raw-output (make-string-output-stream))
                  (send-basefee-output (make-string-output-stream))
                  (send-queued-output (make-string-output-stream))
                  (raw-pending-output (make-string-output-stream))
                  (raw-basefee-output (make-string-output-stream))
                  (raw-queued-output (make-string-output-stream))
                  (txpool-status-output (make-string-output-stream))
                  (txpool-content-from-output (make-string-output-stream))
                  (txpool-inspect-output (make-string-output-stream))
                  (balance-targets
                    (devnet-smoke-gate-balance-targets expect))
                  (checkpoint-balance-targets
                    (devnet-smoke-gate-checkpoint-balance-targets
                     parent-state
                     balance-targets))
                  (transaction-checks
                    (devnet-smoke-gate-transaction-checks child-block))
                  (log-targets
                    (devnet-smoke-gate-log-targets expect))
                  (prepare-payload-attributes
                    (devnet-smoke-gate-payload-attributes-v2
                     child-block
                     (getf (first balance-targets) :address)))
                  (remote-block
                    (devnet-smoke-gate-remote-block child-block))
                  (remote-payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data remote-block)))
                  (invalid-block
                    (devnet-smoke-gate-invalid-child-block child-block))
                  (invalid-payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data invalid-block)))
                  (invalid-descendant-block
                    (devnet-smoke-gate-invalid-grandchild-block
                     invalid-block))
                  (invalid-descendant-payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data invalid-descendant-block)))
                  (pending-transaction-hash
                    (transaction-hash pending-transaction))
                  (pending-transaction-hash-hex
                    (hash32-to-hex pending-transaction-hash))
                  (basefee-transaction-hash-hex
                    (devnet-smoke-gate-transaction-hash-hex
                     basefee-transaction))
                  (queued-transaction-hash-hex
                    (devnet-smoke-gate-transaction-hash-hex
                     queued-transaction))
                  (pending-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     pending-transaction))
                  (basefee-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     basefee-transaction))
                  (queued-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     queued-transaction))
                  (pending-transaction-summary
                    (devnet-smoke-gate-transaction-summary
                     pending-transaction))
                  (basefee-transaction-summary
                    (devnet-smoke-gate-transaction-summary
                     basefee-transaction))
                  (queued-transaction-summary
                    (devnet-smoke-gate-transaction-summary
                     queued-transaction))
                  (pending-transaction-sender
                    (transaction-sender pending-transaction))
                  (pending-transaction-sender-hex
                    (address-to-hex pending-transaction-sender))
                  (pending-transaction-nonce-key
                    (devnet-smoke-gate-transaction-nonce-key
                     pending-transaction))
                  (basefee-transaction-nonce-key
                    (devnet-smoke-gate-transaction-nonce-key
                     basefee-transaction))
                  (queued-transaction-nonce-key
                    (devnet-smoke-gate-transaction-nonce-key
                     queued-transaction))
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
                      forkchoice-output)
                     (cons
                      (json-encode
                       (devnet-smoke-gate-forkchoice-v2-payload-attributes-request
                        23
                        (block-hash child-block)
                        prepare-payload-attributes
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      prepare-payload-output)
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 24 remote-payload))
                      remote-payload-output)
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 25 invalid-payload))
                      invalid-payload-output)))
                  (public-requests
                    (let ((target (first balance-targets)))
                      (setf balance-address (getf target :address)
                            expected-balance (getf target :balance)
                            balance-field (getf target :field)
                            sender-address
                            (fixture-address-field expect "sender")
                            expected-sender-nonce
                            (fixture-object-field expect "senderNonce")
                            code-address
                            (fixture-address-field expect "codeAddress")
                            expected-code
                            (fixture-object-field expect "code")
                            storage-address
                            (fixture-address-field expect "storageAddress")
                            storage-key
                            (fixture-object-field expect "storageKey")
                            expected-storage
                            (fixture-object-field expect "storageValue"))
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
                        balance-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 33)
                               (cons "method" "eth_blockNumber")
                               (cons "params" '())))
                        prepared-public-output)
                       (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                               (cons "id" 34)
                               (cons "method" "eth_blockNumber")
                               (cons "params" '())))
                        remote-public-output)
                       (cons
                       (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 35)
                               (cons "method" "eth_blockNumber")
                               (cons "params" '())))
                        invalid-public-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 36)
                               (cons "method" "eth_sendRawTransaction")
                               (cons "params"
                                     (list pending-transaction-raw))))
                        send-raw-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 37)
                               (cons "method" "eth_sendRawTransaction")
                               (cons "params"
                                     (list basefee-transaction-raw))))
                        send-basefee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 38)
                               (cons "method" "eth_sendRawTransaction")
                               (cons "params"
                                     (list queued-transaction-raw))))
                        send-queued-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 39)
                               (cons "method" "eth_getRawTransactionByHash")
                               (cons "params"
                                     (list pending-transaction-hash-hex))))
                        raw-pending-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 40)
                               (cons "method" "eth_getRawTransactionByHash")
                               (cons "params"
                                     (list basefee-transaction-hash-hex))))
                        raw-basefee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 41)
                               (cons "method" "eth_getRawTransactionByHash")
                               (cons "params"
                                     (list queued-transaction-hash-hex))))
                        raw-queued-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 42)
                               (cons "method" "txpool_status")
                               (cons "params" '())))
                        txpool-status-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 43)
                               (cons "method" "txpool_contentFrom")
                               (cons "params"
                                     (list pending-transaction-sender-hex))))
                        txpool-content-from-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 44)
                               (cons "method" "txpool_inspect")
                               (cons "params" '())))
                        txpool-inspect-output))))
                  (engine-served-count 0)
                  (engine-done-p nil)
                  (public-served-count 0))
             (devnet-cli-set-node-store-config node store config)
             (engine-payload-store-put-block
              store parent-block :state-available-p t)
             (commit-state-db-to-chain-store
              store (block-hash parent-block) parent-state)
             (when pid-file
               (ethereum-lisp.cli::devnet-cli-write-pid-file pid-file))
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
                                (when (= engine-served-count 5)
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
                      :max-connections 14
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
                      (prepare-payload-response
                        (get-output-stream-string prepare-payload-output))
                      (remote-payload-response
                        (get-output-stream-string remote-payload-output))
                      (invalid-payload-response
                        (get-output-stream-string invalid-payload-output))
                      (block-number-response
                        (get-output-stream-string block-number-output))
                      (balance-response
                        (get-output-stream-string balance-output))
                      (prepared-public-response
                        (get-output-stream-string prepared-public-output))
                      (remote-public-response
                        (get-output-stream-string remote-public-output))
                      (invalid-public-response
                        (get-output-stream-string invalid-public-output))
                      (send-raw-response
                        (get-output-stream-string send-raw-output))
                      (send-basefee-response
                        (get-output-stream-string send-basefee-output))
                      (send-queued-response
                        (get-output-stream-string send-queued-output))
                      (raw-pending-response
                        (get-output-stream-string raw-pending-output))
                      (raw-basefee-response
                        (get-output-stream-string raw-basefee-output))
                      (raw-queued-response
                        (get-output-stream-string raw-queued-output))
                      (txpool-status-response
                        (get-output-stream-string txpool-status-output))
                      (txpool-content-from-response
                        (get-output-stream-string
                         txpool-content-from-output))
                      (txpool-inspect-response
                        (get-output-stream-string txpool-inspect-output))
                      (new-payload-rpc
                        (devnet-smoke-gate-rpc-body new-payload-response))
                      (forkchoice-rpc
                        (devnet-smoke-gate-rpc-body forkchoice-response))
                      (prepare-payload-rpc
                        (devnet-smoke-gate-rpc-body prepare-payload-response))
                      (remote-payload-rpc
                        (devnet-smoke-gate-rpc-body remote-payload-response))
                      (invalid-payload-rpc
                        (devnet-smoke-gate-rpc-body invalid-payload-response))
                      (block-number-rpc
                        (devnet-smoke-gate-rpc-body block-number-response))
                      (balance-rpc
                        (devnet-smoke-gate-rpc-body balance-response))
                      (prepared-public-rpc
                        (devnet-smoke-gate-rpc-body prepared-public-response))
                      (remote-public-rpc
                        (devnet-smoke-gate-rpc-body remote-public-response))
                      (invalid-public-rpc
                        (devnet-smoke-gate-rpc-body invalid-public-response))
                      (send-raw-rpc
                        (devnet-smoke-gate-rpc-body send-raw-response))
                      (send-basefee-rpc
                        (devnet-smoke-gate-rpc-body send-basefee-response))
                      (send-queued-rpc
                        (devnet-smoke-gate-rpc-body send-queued-response))
                      (raw-pending-rpc
                        (devnet-smoke-gate-rpc-body raw-pending-response))
                      (raw-basefee-rpc
                        (devnet-smoke-gate-rpc-body raw-basefee-response))
                      (raw-queued-rpc
                        (devnet-smoke-gate-rpc-body raw-queued-response))
                      (txpool-status-rpc
                        (devnet-smoke-gate-rpc-body txpool-status-response))
                      (txpool-content-from-rpc
                        (devnet-smoke-gate-rpc-body
                         txpool-content-from-response))
                      (txpool-inspect-rpc
                        (devnet-smoke-gate-rpc-body txpool-inspect-response))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (prepare-payload-result
                        (fixture-object-field prepare-payload-rpc "result"))
                      (prepare-payload-status
                        (fixture-object-field
                         prepare-payload-result
                         "payloadStatus"))
                      (prepared-payload-id
                        (fixture-object-field
                         prepare-payload-result
                         "payloadId"))
                      (remote-payload-result
                        (fixture-object-field remote-payload-rpc "result"))
                      (invalid-payload-result
                        (fixture-object-field invalid-payload-rpc "result"))
                      (expected-hash
                        (hash32-to-hex (block-hash child-block)))
                      (expected-remote-block-hash
                        (hash32-to-hex (block-hash remote-block)))
                      (expected-invalid-block-hash
                        (hash32-to-hex (block-hash invalid-block)))
                      (txpool-status
                        (fixture-object-field txpool-status-rpc "result"))
                      (txpool-content-from
                        (fixture-object-field
                         txpool-content-from-rpc "result"))
                      (txpool-content-from-pending
                        (fixture-object-field
                         txpool-content-from "pending"))
                      (txpool-content-from-transaction
                        (fixture-object-field
                         txpool-content-from-pending
                         pending-transaction-nonce-key))
                      (txpool-content-from-queued
                        (fixture-object-field
                         txpool-content-from "queued"))
                      (txpool-content-from-basefee-transaction
                        (fixture-object-field
                         txpool-content-from-queued
                         basefee-transaction-nonce-key))
                      (txpool-content-from-queued-transaction
                        (fixture-object-field
                         txpool-content-from-queued
                         queued-transaction-nonce-key))
                      (txpool-inspect
                        (fixture-object-field txpool-inspect-rpc "result"))
                      (txpool-inspect-pending
                        (fixture-object-field txpool-inspect "pending"))
                      (txpool-inspect-sender
                        (fixture-object-field
                         txpool-inspect-pending
                         pending-transaction-sender-hex))
                      (txpool-inspect-transaction
                        (fixture-object-field
                         txpool-inspect-sender
                         pending-transaction-nonce-key))
                      (txpool-inspect-queued
                        (fixture-object-field txpool-inspect "queued"))
                      (txpool-inspect-queued-sender
                        (fixture-object-field
                         txpool-inspect-queued
                         pending-transaction-sender-hex))
                      (txpool-inspect-basefee-transaction
                        (fixture-object-field
                         txpool-inspect-queued-sender
                         basefee-transaction-nonce-key))
                      (txpool-inspect-queued-transaction
                        (fixture-object-field
                         txpool-inspect-queued-sender
                         queued-transaction-nonce-key))
                  (expected-block-number
                    (fixture-object-field payload-case "number"))
                  (expected-prepared-block-number
                    (quantity-to-hex
                     (1+ (block-header-number (block-header child-block)))))
                  (expected-safe-block-number
                    (quantity-to-hex
                     (block-header-number (block-header parent-block))))
                  (expected-safe-block-hash (block-hash parent-block))
                  (expected-finalized-block-number expected-safe-block-number)
                  (expected-finalized-block-hash expected-safe-block-hash)
                      (actual-block-number
                        (fixture-object-field block-number-rpc "result"))
                      (actual-balance
                        (fixture-object-field balance-rpc "result")))
                 (devnet-smoke-gate-require
                  (= 5 (getf summary :engine-connections))
                  "Expected 5 Engine connections, got ~S"
                  (getf summary :engine-connections))
                 (devnet-smoke-gate-require
                  (= 14 (getf summary :public-connections))
                  "Expected 14 public RPC connections, got ~S"
                  (getf summary :public-connections))
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status new-payload-response))
                  "engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status forkchoice-response))
                  "engine_forkchoiceUpdatedV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status prepare-payload-response))
                  "engine_forkchoiceUpdatedV2 payloadAttributes HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status remote-payload-response))
                  "orphan engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status invalid-payload-response))
                  "invalid engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status block-number-response))
                  "eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status balance-response))
                  "eth_getBalance HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status prepared-public-response))
                  "prepared-payload eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status remote-public-response))
                  "remote-block eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status invalid-public-response))
                  "invalid-tipset eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status send-raw-response))
                  "eth_sendRawTransaction HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-basefee-response))
                  "eth_sendRawTransaction basefee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-queued-response))
                  "eth_sendRawTransaction queued HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status raw-pending-response))
                  "eth_getRawTransactionByHash pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status raw-basefee-response))
                  "eth_getRawTransactionByHash basefee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status raw-queued-response))
                  "eth_getRawTransactionByHash queued HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status txpool-status-response))
                  "txpool_status HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status txpool-content-from-response))
                  "txpool_contentFrom HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status txpool-inspect-response))
                  "txpool_inspect HTTP status mismatch")
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
                  (string= +payload-status-valid+
                           (fixture-object-field prepare-payload-status
                                                 "status"))
                  "engine_forkchoiceUpdatedV2 payloadAttributes status mismatch")
                 (devnet-smoke-gate-require
                  (and (stringp prepared-payload-id)
                       (= 18 (length prepared-payload-id)))
                  "engine_forkchoiceUpdatedV2 did not return an 8-byte payloadId")
                 (devnet-smoke-gate-require
                  (string= +payload-status-syncing+
                           (fixture-object-field remote-payload-result
                                                 "status"))
                  "orphan engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field remote-payload-result
                                              "latestValidHash"))
                  "orphan engine_newPayloadV2 should not report latestValidHash")
                 (devnet-smoke-gate-require
                  (ethereum-lisp.core::engine-payload-store-remote-block
                   store (block-hash remote-block))
                  "orphan engine_newPayloadV2 did not populate remote-block cache")
                 (devnet-smoke-gate-require
                  (string= +payload-status-invalid+
                           (fixture-object-field invalid-payload-result
                                                 "status"))
                  "invalid engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-hash
                           (fixture-object-field invalid-payload-result
                                                 "latestValidHash"))
                  "invalid engine_newPayloadV2 latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= "Timestamp is not greater than parent timestamp"
                           (fixture-object-field invalid-payload-result
                                                 "validationError"))
                  "invalid engine_newPayloadV2 validation error mismatch")
                 (devnet-smoke-gate-require
                  (ethereum-lisp.core::engine-payload-store-invalid-block
                   store (block-hash invalid-block))
                  "invalid engine_newPayloadV2 did not populate invalid-tipset cache")
                 (devnet-smoke-gate-require
                  (string= expected-block-number actual-block-number)
                  "eth_blockNumber mismatch: expected ~A got ~A"
                  expected-block-number
                  actual-block-number)
                 (devnet-smoke-gate-require
                  (string= expected-block-number
                           (fixture-object-field prepared-public-rpc "result"))
                  "prepared-payload eth_blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-block-number
                           (fixture-object-field remote-public-rpc "result"))
                  "remote-block eth_blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-block-number
                           (fixture-object-field invalid-public-rpc "result"))
                  "invalid-tipset eth_blockNumber mismatch")
                 (devnet-smoke-gate-require
                 (string= pending-transaction-hash-hex
                           (fixture-object-field send-raw-rpc "result"))
                  "eth_sendRawTransaction hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field send-basefee-rpc "result"))
                  "eth_sendRawTransaction basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field send-queued-rpc "result"))
                  "eth_sendRawTransaction queued hash mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-raw
                           (fixture-object-field raw-pending-rpc "result"))
                  "eth_getRawTransactionByHash pending raw mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-raw
                           (fixture-object-field raw-basefee-rpc "result"))
                  "eth_getRawTransactionByHash basefee raw mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-raw
                           (fixture-object-field raw-queued-rpc "result"))
                  "eth_getRawTransactionByHash queued raw mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x1"
                           (fixture-object-field txpool-status "pending"))
                  "txpool_status pending count mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x2"
                           (fixture-object-field txpool-status "queued"))
                  "txpool_status queued count mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-hash-hex
                           (fixture-object-field
                            txpool-content-from-transaction "hash"))
                  "txpool_contentFrom pending hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field
                            txpool-content-from-basefee-transaction "hash"))
                  "txpool_contentFrom basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field
                            txpool-content-from-queued-transaction "hash"))
                  "txpool_contentFrom queued hash mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-summary
                           txpool-inspect-transaction)
                  "txpool_inspect pending summary mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-summary
                           txpool-inspect-basefee-transaction)
                  "txpool_inspect basefee summary mismatch")
                 (devnet-smoke-gate-require
                 (string= queued-transaction-summary
                          txpool-inspect-queued-transaction)
                  "txpool_inspect queued summary mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-balance actual-balance)
                  "eth_getBalance mismatch: expected ~A got ~A"
                  expected-balance
                  actual-balance)
                 (when database-file
                   (ethereum-lisp.cli::devnet-node-export-database
                    node
                    :state-prune-before state-prune-before))
                 (let ((database-summary
                         (and database-file
                              (devnet-smoke-gate-verify-database
                               database-file
                               expected-block-number
                               balance-targets
                               sender-address
                               expected-sender-nonce
                               code-address
                               expected-code
                               storage-address
                               storage-key
                               expected-storage
                               transaction-checks
                               log-targets
                               (block-hash child-block)
                               expected-safe-block-number
                               expected-safe-block-hash
                               expected-finalized-block-number
                               expected-finalized-block-hash
                               config
                               :state-prune-before state-prune-before
                               :pruned-state-hash expected-safe-block-hash
                               :checkpoint-balance-targets
                               checkpoint-balance-targets
                               :prepared-payload-id prepared-payload-id
                               :prepared-payload-parent-hash
                               (block-hash child-block)
                               :prepared-payload-block-number
                               expected-prepared-block-number
                               :remote-payload remote-payload
                               :remote-block remote-block
                               :invalid-block invalid-block
                               :invalid-descendant-payload
                               invalid-descendant-payload
                               :txpool-transactions txpool-transactions
                               :side-payload side-payload
                               :side-block side-block
                               :child-block child-block))))
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
                  (cons "preparedPayloadId" prepared-payload-id)
                  (cons "preparedPayloadParentHash"
                        (hash32-to-hex (block-hash child-block)))
                  (cons "preparedPayloadBlockNumber"
                        expected-prepared-block-number)
                  (cons "remoteBlockHash" expected-remote-block-hash)
                  (cons "remoteBlockStatus"
                        (fixture-object-field remote-payload-result "status"))
                  (cons "invalidTipsetBlockHash"
                        expected-invalid-block-hash)
                  (cons "invalidTipsetStatus"
                        (fixture-object-field invalid-payload-result "status"))
                  (cons "invalidTipsetValidationError"
                        (fixture-object-field invalid-payload-result
                                              "validationError"))
                  (cons "txpoolPendingTransactionHash"
                        pending-transaction-hash-hex)
                  (cons "txpoolPendingTransactionRaw"
                        pending-transaction-raw)
                  (cons "txpoolPendingSender"
                        pending-transaction-sender-hex)
                  (cons "txpoolPendingNonce"
                        pending-transaction-nonce-key)
                  (cons "txpoolPendingInspectSummary"
                        txpool-inspect-transaction)
                  (cons "txpoolBasefeeTransactionHash"
                        basefee-transaction-hash-hex)
                  (cons "txpoolBasefeeTransactionRaw"
                        basefee-transaction-raw)
                  (cons "txpoolBasefeeNonce"
                        basefee-transaction-nonce-key)
                  (cons "txpoolBasefeeInspectSummary"
                        txpool-inspect-basefee-transaction)
                  (cons "txpoolQueuedTransactionHash"
                        queued-transaction-hash-hex)
                  (cons "txpoolQueuedTransactionRaw"
                        queued-transaction-raw)
                  (cons "txpoolQueuedNonce"
                        queued-transaction-nonce-key)
                  (cons "txpoolQueuedInspectSummary"
                        txpool-inspect-queued-transaction)
                  (cons "txpoolStatusPending"
                        (fixture-object-field txpool-status "pending"))
                  (cons "txpoolStatusQueued"
                        (fixture-object-field txpool-status "queued"))
                  (cons "blockNumber" actual-block-number)
                  (cons "safeBlockNumber" expected-safe-block-number)
                  (cons "safeBlockHash"
                        (hash32-to-hex expected-safe-block-hash))
                  (cons "finalizedBlockNumber"
                        expected-finalized-block-number)
                  (cons "finalizedBlockHash"
                        (hash32-to-hex expected-finalized-block-hash))
                  (cons "checkedBalanceAddress"
                        (address-to-hex balance-address))
                  (cons "checkedBalanceField" balance-field)
                  (cons "checkedBalance" actual-balance)
                  (cons "checkedCheckpointBalance"
                        (getf (first checkpoint-balance-targets) :balance))
                  (cons "recipientBalance" actual-balance)
                  (cons "checkedBalanceCount" (length balance-targets))
                  (cons "transactionCount" (length transaction-checks))
                  (cons "checkedLogCount"
                        (reduce #'+ log-targets
                                :key (lambda (target)
                                       (getf target :count))
                                :initial-value 0))
                  (cons "checkedSimulationCount"
                        (if database-summary
                            (getf database-summary :rpc-simulation-count)
                            0))
                  (cons "checkedNonceAddress" (address-to-hex sender-address))
                  (cons "checkedNonce" expected-sender-nonce)
                  (cons "checkedCodeAddress" (address-to-hex code-address))
                  (cons "checkedCode" expected-code)
                  (cons "checkedStorageAddress"
                        (address-to-hex storage-address))
                  (cons "checkedStorageKey" storage-key)
                  (cons "checkedStorage" expected-storage)
                  (cons "checkedProofCodeHash"
                        (hash32-to-hex
                         (keccak-256-hash (hex-to-bytes expected-code))))
                  (cons "checkedProofStorageValue"
                        (quantity-to-hex (hex-to-quantity expected-storage)))
                  (cons "readyFile" (or ready-file :false))
                  (cons "logFile" (or log-file :false))
                  (cons "pidFile" (or pid-file :false))
                  (cons "databaseFile" (or database-file :false))
                  (cons "databasePruneStateBefore"
                        (or state-prune-before :false))
                  (cons "databasePrunedStateAvailable"
                        (if database-summary
                            (if (getf database-summary
                                      :pruned-state-available-p)
                                t
                                :false)
                            :false))
                  (cons "databaseHeadNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :head-number))
                            :false))
                  (cons "databaseSafeNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :safe-number))
                            :false))
                  (cons "databaseSafeHash"
                        (if database-summary
                            (getf database-summary :safe-hash)
                            :false))
                  (cons "databaseFinalizedNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :finalized-number))
                            :false))
                  (cons "databaseFinalizedHash"
                        (if database-summary
                            (getf database-summary :finalized-hash)
                            :false))
                  (cons "databaseRpcBlockNumber"
                        (if database-summary
                            (getf database-summary :rpc-block-number)
                            :false))
                  (cons "databaseRpcBalance"
                        (if database-summary
                            (getf database-summary :rpc-balance)
                            :false))
                  (cons "databaseRpcNonce"
                        (if database-summary
                            (getf database-summary :rpc-nonce)
                            :false))
                  (cons "databaseRpcCode"
                        (if database-summary
                            (getf database-summary :rpc-code)
                            :false))
                  (cons "databaseRpcStorage"
                        (if database-summary
                            (getf database-summary :rpc-storage)
                            :false))
                  (cons "databaseRpcPreparedPayloadId"
                        (if database-summary
                            (getf database-summary
                                  :rpc-prepared-payload-id)
                            :false))
                  (cons "databaseRpcPreparedPayloadParentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-prepared-payload-parent-hash)
                            :false))
                  (cons "databaseRpcPreparedPayloadBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-prepared-payload-block-number)
                            :false))
                  (cons "databaseRemoteBlockHash"
                        (if database-summary
                            (getf database-summary :remote-block-hash)
                            :false))
                  (cons "databaseRpcRemoteBlockStatus"
                        (if database-summary
                            (getf database-summary
                                  :rpc-remote-block-status)
                            :false))
                  (cons "databaseInvalidTipsetBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :invalid-tipset-block-hash)
                            :false))
                  (cons "databaseRpcInvalidTipsetStatus"
                        (if database-summary
                            (getf database-summary
                                  :rpc-invalid-tipset-status)
                            :false))
                  (cons "databaseRpcInvalidTipsetValidationError"
                        (if database-summary
                            (getf database-summary
                                  :rpc-invalid-tipset-validation-error)
                            :false))
                  (cons "databaseRpcTxpoolPendingHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolRawTransaction"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-raw-transaction)
                            :false))
                  (cons "databaseRpcTxpoolSender"
                        (if database-summary
                            (getf database-summary :rpc-txpool-sender)
                            :false))
                  (cons "databaseRpcTxpoolNonce"
                        (if database-summary
                            (getf database-summary :rpc-txpool-nonce)
                            :false))
                  (cons "databaseRpcTxpoolInspectSummary"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-inspect-summary)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeRawTransaction"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-raw-transaction)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-nonce)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeInspectSummary"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-inspect-summary)
                            :false))
                  (cons "databaseRpcTxpoolQueuedHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolQueuedRawTransaction"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-raw-transaction)
                            :false))
                  (cons "databaseRpcTxpoolQueuedNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-nonce)
                            :false))
                  (cons "databaseRpcTxpoolQueuedInspectSummary"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-inspect-summary)
                            :false))
                  (cons "databaseRpcTxpoolStatusPending"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-status-pending)
                            :false))
                  (cons "databaseRpcTxpoolStatusQueued"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-status-queued)
                            :false))
                  (cons "databaseRpcTxpoolContentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-content-hash)
                            :false))
                  (cons "databaseRpcTxpoolContentFromHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-content-from-hash)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeContentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-content-hash)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeContentFromHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-content-from-hash)
                            :false))
                  (cons "databaseRpcTxpoolQueuedContentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-content-hash)
                            :false))
                  (cons "databaseRpcTxpoolQueuedContentFromHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-content-from-hash)
                            :false))
                  (cons "databaseRpcTxpoolPublicConnections"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-public-connections)
                            :false))
                  (cons "databaseRpcProofAddress"
                        (if database-summary
                            (getf database-summary :rpc-proof-address)
                            :false))
                  (cons "databaseRpcProofCodeHash"
                        (if database-summary
                            (getf database-summary :rpc-proof-code-hash)
                            :false))
                  (cons "databaseRpcProofStorageKey"
                        (if database-summary
                            (getf database-summary :rpc-proof-storage-key)
                            :false))
                  (cons "databaseRpcProofStorageValue"
                        (if database-summary
                            (getf database-summary :rpc-proof-storage-value)
                            :false))
                  (cons "databaseRpcProofStorageCount"
                        (if database-summary
                            (getf database-summary :rpc-proof-storage-count)
                            :false))
                  (cons "databaseRpcProofAccountProofCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-proof-account-proof-count)
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
                  (cons "databaseRpcFullBlockTransactionCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-transaction-count)
                            :false))
                  (cons "databaseRpcFullBlockTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-transaction-hash)
                            :false))
                  (cons "databaseRpcFullBlockTransactionIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-transaction-index)
                            :false))
                  (cons "databaseRpcFullBlockByNumberTransactionCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-by-number-transaction-count)
                            :false))
                  (cons "databaseRpcFullBlockByNumberTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-by-number-transaction-hash)
                            :false))
                  (cons "databaseRpcFullBlockByNumberTransactionIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-by-number-transaction-index)
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
                  (cons "databaseRpcBlockTransactionCountByHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-transaction-count-by-hash)
                            :false))
                  (cons "databaseRpcBlockTransactionCountByNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-transaction-count-by-number)
                            :false))
                  (cons "databaseRpcCanonicalHashBalance"
                        (if database-summary
                            (getf database-summary
                                  :rpc-canonical-hash-balance)
                            :false))
                  (cons "databaseRpcCanonicalHashRequireBalance"
                        (if database-summary
                            (getf database-summary
                                  :rpc-canonical-hash-require-balance)
                            :false))
                  (cons "databaseRpcTransactionCount"
                        (if database-summary
                            (getf database-summary :rpc-transaction-count)
                            :false))
                  (cons "databaseRpcBalanceCount"
                        (if database-summary
                            (getf database-summary :rpc-balance-count)
                            :false))
                  (cons "databaseRpcLogCount"
                        (if database-summary
                            (getf database-summary :rpc-log-count)
                            :false))
                  (cons "databaseRpcRawTransactionByBlockHashAndIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-raw-transaction-by-hash)
                            :false))
                  (cons "databaseRpcRawTransactionByHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-raw-transaction)
                            :false))
                  (cons "databaseRpcRawTransactionByBlockNumberAndIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-raw-transaction-by-number)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-block-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-block-number)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-transaction-index)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-block-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-block-number)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-transaction-index)
                            :false))
                  (cons "databaseRpcSafeBlockHash"
                        (if database-summary
                            (getf database-summary :rpc-safe-block-hash)
                            :false))
                  (cons "databaseRpcSafeBlockNumber"
                        (if database-summary
                            (getf database-summary :rpc-safe-block-number)
                            :false))
                  (cons "databaseRpcFinalizedBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-finalized-block-hash)
                            :false))
                  (cons "databaseRpcFinalizedBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-finalized-block-number)
                            :false))
                  (cons "databaseRpcCallResult"
                        (if database-summary
                            (getf database-summary :rpc-call-result)
                            :false))
                  (cons "databaseRpcFailedCallError"
                        (if database-summary
                            (getf database-summary
                                  :rpc-failed-call-error-message)
                            :false))
                  (cons "databaseRpcEstimateGas"
                        (if database-summary
                            (getf database-summary :rpc-estimate-gas)
                            :false))
                  (cons "databaseRpcAccessListCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-access-list-count)
                            :false))
                  (cons "databaseRpcAccessListGasUsed"
                        (if database-summary
                            (getf database-summary
                                  :rpc-access-list-gas-used)
                            :false))
                  (cons "databaseRpcPostCallStorage"
                        (if database-summary
                            (getf database-summary
                                  :rpc-post-call-storage)
                            :false))
                  (cons "databaseRpcSimulationCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-simulation-count)
                            :false))
                  (cons "databaseRpcPrunedStateError"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-pruned-state-error-message)
                                :false)
                            :false))
                  (cons "databaseRpcPrunedStateErrors"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-pruned-state-error-messages)
                                :false)
                            :false))
                  (cons "databaseRpcPublicConnections"
                        (if database-summary
                            (getf database-summary :rpc-public-connections)
                            :false))
                  (cons "databaseRpcSideBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideForkchoiceStatus"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-forkchoice-status)
                                :false)
                            :false))
                  (cons "databaseRpcSideRejectedCheckpointError"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-rejected-checkpoint-error)
                                :false)
                            :false))
                  (cons "databaseRpcSideBlockNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-block-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideLatestBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-latest-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideTransactionReinserted"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-transaction-reinserted-p)
                                :false)
                            :false))
                  (cons "databaseRpcSideTransactionByHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-transaction-by-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRawTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-raw-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSidePendingTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-pending-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSideReceipt"
                        (if database-summary
                            (or (getf database-summary :rpc-side-receipt)
                                :false)
                            :false))
                  (cons "databaseRpcSideChildBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-child-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideBlockReceiptsCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-block-receipts-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideLogCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-log-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredHeadNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-head-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredHeadHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-head-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcBlockNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-block-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcLatestBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-latest-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredSafeNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-safe-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredSafeHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-safe-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredFinalizedNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-finalized-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredFinalizedHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-finalized-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcSafeNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-safe-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcSafeHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-safe-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcFinalizedNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-finalized-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcFinalizedHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-finalized-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredSafeBalance"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-safe-balance)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredFinalizedBalance"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-finalized-balance)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRawTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-raw-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredPendingTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-pending-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredReceipt"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-receipt)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredChildBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-child-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredChildRequireCanonicalError"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-child-require-canonical-error)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredChildRequireCanonicalErrors"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-child-require-canonical-errors)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredBlockReceiptsCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-block-receipts-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredLogCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-log-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredPublicConnections"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-public-connections)
                                :false)
                            :false))
                  (cons "databaseRpcSideTotalConnections"
                        (if database-summary
                            (let ((side-engine
                                    (getf database-summary
                                          :rpc-side-engine-connections))
                                  (side-public
                                    (getf database-summary
                                          :rpc-side-public-connections))
                                  (side-restored-public
                                    (getf database-summary
                                          :rpc-side-restored-public-connections)))
                              (if (and side-engine
                                       side-public
                                       side-restored-public)
                                  (+ side-engine
                                     side-public
                                     side-restored-public)
                                  :false))
                            :false))
                  (cons "databaseRpcSideEngineConnections"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-engine-connections)
                                :false)
                            :false))
                  (cons "databaseRpcSidePublicConnections"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-public-connections)
                                :false)
                            :false))))))))))))
             (let* ((ready-summary
                      (when ready-file
                        (devnet-smoke-gate-verify-ready-file
                         ready-file
                         (devnet-smoke-gate-field report "safeBlockNumber")
                         (devnet-smoke-gate-field report "safeBlockHash"))))
                    (ready-process-id
                      (and ready-summary
                           (fixture-object-field ready-summary "processId")))
                    (pid-file-process-id
                      (when pid-file
                        (devnet-smoke-gate-verify-pid-file
                         pid-file
                         :expected-process-id ready-process-id)))
                    (expected-process-id
                      (or pid-file-process-id ready-process-id)))
               (when log-file
                 (devnet-smoke-gate-verify-log-file
                  log-file
                  (devnet-smoke-gate-field report "safeBlockNumber")
                  (devnet-smoke-gate-field report "safeBlockHash")
                  (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field report "latestValidHash")
                  :expected-process-id expected-process-id))
               report)))
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
    (case-names &key ready-file log-file pid-file database-file
       state-prune-before)
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
                       :pid-file
                       (devnet-smoke-gate-case-path
                        pid-file case-name :default-name "devnet")
                       :database-file
                       (devnet-smoke-gate-case-path
                        database-file case-name
                        :default-name "devnet-chain")
                       :state-prune-before state-prune-before)))
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
                   :initial-value 0))
         (pruned-state-case-count
           (count-if
            (lambda (report)
              (devnet-smoke-gate-report-pruned-state-covered-p
               report state-prune-before))
            reports))
         (pruned-state-error-case-count
           (count-if
            (lambda (report)
              (let ((errors
                      (devnet-smoke-gate-field
                       report "databaseRpcPrunedStateErrors")))
                (and errors
                     (equal (devnet-smoke-gate-pruned-state-error-messages)
                            errors))))
            reports)))
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
         (string= (devnet-smoke-gate-field report "safeBlockNumber")
                  (devnet-smoke-gate-field report "databaseSafeNumber"))
         "Devnet smoke gate suite database safe checkpoint mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockHash")
                  (devnet-smoke-gate-field report "databaseSafeHash"))
         "Devnet smoke gate suite database safe hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockNumber")
                  (devnet-smoke-gate-field report "databaseFinalizedNumber"))
         "Devnet smoke gate suite database finalized checkpoint mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                  (devnet-smoke-gate-field report "databaseFinalizedHash"))
         "Devnet smoke gate suite database finalized hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (let ((pruned-state-covered-p
                (devnet-smoke-gate-report-pruned-state-covered-p
                 report state-prune-before))
              (pruned-errors
                (devnet-smoke-gate-field
                 report "databaseRpcPrunedStateErrors")))
          (if pruned-state-covered-p
              (progn
                (devnet-smoke-gate-require
                 (devnet-smoke-gate-false-p
                  (devnet-smoke-gate-field
                   report "databasePrunedStateAvailable"))
                 "Devnet smoke gate suite pruned state still available for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (equal (devnet-smoke-gate-pruned-state-error-messages)
                        pruned-errors)
                 "Devnet smoke gate suite pruned-state RPC errors mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase")))
              (when state-prune-before
                (devnet-smoke-gate-require
                 (devnet-smoke-gate-field
                  report "databasePrunedStateAvailable")
                 "Devnet smoke gate suite unexpectedly pruned state for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (devnet-smoke-gate-false-p pruned-errors)
                 "Devnet smoke gate suite unexpected pruned-state RPC errors for ~A"
                 (devnet-smoke-gate-field report "fixtureCase")))))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedCode")
                  (devnet-smoke-gate-field report "databaseRpcCode"))
         "Devnet smoke gate suite restored code mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedNonce")
                  (devnet-smoke-gate-field report "databaseRpcNonce"))
         "Devnet smoke gate suite restored nonce mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorage")
                  (devnet-smoke-gate-field report "databaseRpcStorage"))
         "Devnet smoke gate suite restored storage mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorageAddress")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofAddress"))
         "Devnet smoke gate suite restored proof address mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedProofCodeHash")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofCodeHash"))
         "Devnet smoke gate suite restored proof code hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorageKey")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofStorageKey"))
         "Devnet smoke gate suite restored proof storage key mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedProofStorageValue")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofStorageValue"))
         "Devnet smoke gate suite restored proof storage value mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= 1 (devnet-smoke-gate-field report
                                       "databaseRpcProofStorageCount"))
         "Devnet smoke gate suite restored proof storage count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (<= 0 (devnet-smoke-gate-field
                report "databaseRpcProofAccountProofCount"))
         "Devnet smoke gate suite restored proof account proof count mismatch for ~A"
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
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field report
                                     "databaseRpcBlockReceiptsCount"))
         "Devnet smoke gate suite restored block receipts count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (quantity-to-hex
                   (devnet-smoke-gate-field report "transactionCount"))
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockTransactionCountByHash"))
         "Devnet smoke gate suite restored block tx count by hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (quantity-to-hex
                   (devnet-smoke-gate-field report "transactionCount"))
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockTransactionCountByNumber"))
         "Devnet smoke gate suite restored block tx count by number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field report "databaseRpcTransactionCount"))
         "Devnet smoke gate suite restored transaction count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field
             report "databaseRpcFullBlockTransactionCount"))
         "Devnet smoke gate suite restored full block transaction count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field
             report "databaseRpcFullBlockByNumberTransactionCount"))
         "Devnet smoke gate suite restored full block-by-number transaction count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockTransactionHash"))
         "Devnet smoke gate suite restored full block transaction hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockByNumberTransactionHash"))
         "Devnet smoke gate suite restored full block-by-number transaction hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockTransactionIndex"))
         "Devnet smoke gate suite restored full block transaction index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockByNumberTransactionIndex"))
         "Devnet smoke gate suite restored full block-by-number transaction index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedBalanceCount")
            (devnet-smoke-gate-field report "databaseRpcBalanceCount"))
         "Devnet smoke gate suite restored balance count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedLogCount")
            (devnet-smoke-gate-field report "databaseRpcLogCount"))
         "Devnet smoke gate suite restored log count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedSimulationCount")
            (devnet-smoke-gate-field report "databaseRpcSimulationCount"))
         "Devnet smoke gate suite restored simulation count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x"
                  (devnet-smoke-gate-field report "databaseRpcCallResult"))
         "Devnet smoke gate suite restored eth_call mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (if (devnet-smoke-gate-executable-code-p
             (devnet-smoke-gate-field report "checkedCode"))
            (devnet-smoke-gate-require
             (string= "eth_call execution failed"
                      (devnet-smoke-gate-field
                       report "databaseRpcFailedCallError"))
             "Devnet smoke gate suite restored failing eth_call mismatch for ~A"
             (devnet-smoke-gate-field report "fixtureCase"))
            (devnet-smoke-gate-require
             (devnet-smoke-gate-false-p
              (devnet-smoke-gate-field report "databaseRpcFailedCallError"))
             "Devnet smoke gate suite unexpected failing eth_call for ~A"
             (devnet-smoke-gate-field report "fixtureCase")))
        (devnet-smoke-gate-require
         (<= 21000
             (hex-to-quantity
              (devnet-smoke-gate-field report "databaseRpcEstimateGas")))
         "Devnet smoke gate suite restored estimateGas mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (stringp (devnet-smoke-gate-field
                   report "databaseRpcAccessListGasUsed"))
         "Devnet smoke gate suite restored access list gasUsed mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorage")
                  (devnet-smoke-gate-field
                   report "databaseRpcPostCallStorage"))
         "Devnet smoke gate suite restored eth_call mutated storage for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByBlockHashAndIndex")
                  (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByBlockNumberAndIndex"))
         "Devnet smoke gate suite restored raw transaction index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByBlockHashAndIndex"))
         "Devnet smoke gate suite restored raw transaction hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockHashAndIndexHash"))
         "Devnet smoke gate suite restored tx by hash/index hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockNumberAndIndexHash"))
         "Devnet smoke gate suite restored tx by number/index hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "databaseRpcBlockHash")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockHashAndIndexBlockHash"))
         "Devnet smoke gate suite restored tx by hash/index block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "databaseRpcBlockHash")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockNumberAndIndexBlockHash"))
         "Devnet smoke gate suite restored tx by number/index block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockHashAndIndexBlockNumber"))
         "Devnet smoke gate suite restored tx by hash/index block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockNumberAndIndexBlockNumber"))
         "Devnet smoke gate suite restored tx by number/index block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockHashAndIndexIndex"))
         "Devnet smoke gate suite restored tx by hash/index index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockNumberAndIndexIndex"))
         "Devnet smoke gate suite restored tx by number/index index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockHash")
                  (devnet-smoke-gate-field report
                                           "databaseRpcSafeBlockHash"))
         "Devnet smoke gate suite restored safe block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcSafeBlockNumber"))
         "Devnet smoke gate suite restored safe block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                  (devnet-smoke-gate-field report
                                           "databaseRpcFinalizedBlockHash"))
         "Devnet smoke gate suite restored finalized block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcFinalizedBlockNumber"))
         "Devnet smoke gate suite restored finalized block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (if state-prune-before
            (devnet-smoke-gate-require
             (devnet-smoke-gate-false-p
              (devnet-smoke-gate-field report "databaseRpcSideBlockHash"))
             "Devnet smoke gate suite unexpectedly ran side reorg for pruned database ~A"
             (devnet-smoke-gate-field report "fixtureCase"))
            (progn
              (devnet-smoke-gate-require
               (string= +payload-status-valid+
                        (devnet-smoke-gate-field
                         report "databaseRpcSideForkchoiceStatus"))
               "Devnet smoke gate suite side forkchoice status mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= "forkchoice safe block is not an ancestor of head"
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRejectedCheckpointError"))
               "Devnet smoke gate suite side rejected checkpoint error mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "blockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideBlockNumber"))
               "Devnet smoke gate suite side block number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcSideBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideLatestBlockHash"))
               "Devnet smoke gate suite side latest hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcSideBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredHeadHash"))
               "Devnet smoke gate suite side restored head hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "blockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredHeadNumber"))
               "Devnet smoke gate suite side restored head number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "blockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcBlockNumber"))
               "Devnet smoke gate suite side fresh public block number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcSideBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcLatestBlockHash"))
               "Devnet smoke gate suite side fresh latest hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredSafeHash"))
               "Devnet smoke gate suite side restored safe hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredSafeNumber"))
               "Devnet smoke gate suite side restored safe number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredFinalizedHash"))
               "Devnet smoke gate suite side restored finalized hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report
                                                 "finalizedBlockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredFinalizedNumber"))
               "Devnet smoke gate suite side restored finalized number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcSafeHash"))
               "Devnet smoke gate suite side restored public safe hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcSafeNumber"))
               "Devnet smoke gate suite side restored public safe number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcFinalizedHash"))
               "Devnet smoke gate suite side restored public finalized hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report
                                                 "finalizedBlockNumber")
                        (devnet-smoke-gate-field
                         report
                         "databaseRpcSideRestoredRpcFinalizedNumber"))
               "Devnet smoke gate suite side restored public finalized number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "checkedCheckpointBalance")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredSafeBalance"))
               "Devnet smoke gate suite side restored safe balance mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "checkedCheckpointBalance")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredFinalizedBalance"))
               "Devnet smoke gate suite side restored finalized balance mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (not (string= (devnet-smoke-gate-field
                              report "databaseRpcBlockHash")
                             (devnet-smoke-gate-field
                              report "databaseRpcSideBlockHash")))
               "Devnet smoke gate suite side block reused child hash for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideChildBlockHash"))
               "Devnet smoke gate suite side reorg lost child block for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideBlockReceiptsCount"))
               "Devnet smoke gate suite side reorg kept canonical receipts for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideLogCount"))
               "Devnet smoke gate suite side reorg kept canonical logs for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (if (not (devnet-smoke-gate-false-p
                        (devnet-smoke-gate-field
                         report "databaseRpcSideTransactionReinserted")))
                  (progn
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               (devnet-smoke-gate-field
                                report "databaseRpcSideTransactionByHash")
                               "hash"))
                     "Devnet smoke gate suite side reorg lost pending transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSideTransactionByHash")
                            "blockHash"))
                     "Devnet smoke gate suite side reorg kept old transaction block hash for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSideTransactionByHash")
                            "blockNumber"))
                     "Devnet smoke gate suite side reorg kept old transaction block number for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSideTransactionByHash")
                            "transactionIndex"))
                     "Devnet smoke gate suite side reorg kept old transaction index for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcRawTransactionByHash")
                              (devnet-smoke-gate-field
                               report "databaseRpcSideRawTransaction"))
                     "Devnet smoke gate suite side reorg lost pending raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               (devnet-smoke-gate-field
                                report "databaseRpcSidePendingTransaction")
                               "hash"))
                     "Devnet smoke gate suite side reorg lost pending transaction pool view for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSidePendingTransaction")
                            "blockHash"))
                     "Devnet smoke gate suite side reorg pending view kept old block hash for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSidePendingTransaction")
                            "blockNumber"))
                     "Devnet smoke gate suite side reorg pending view kept old block number for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSidePendingTransaction")
                            "transactionIndex"))
                     "Devnet smoke gate suite side reorg pending view kept old transaction index for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcRawTransactionByHash")
                              (devnet-smoke-gate-field
                               report "databaseRpcSideRestoredRawTransaction"))
                     "Devnet smoke gate suite side reorg fresh restore lost pending raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               (devnet-smoke-gate-field
                                report "databaseRpcSideRestoredPendingTransaction")
                               "hash"))
                     "Devnet smoke gate suite side reorg fresh restore lost pending transaction view for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report
                             "databaseRpcSideRestoredPendingTransaction")
                            "blockHash"))
                     "Devnet smoke gate suite side reorg fresh pending view kept old block hash for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report
                             "databaseRpcSideRestoredPendingTransaction")
                            "blockNumber"))
                     "Devnet smoke gate suite side reorg fresh pending view kept old block number for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report
                             "databaseRpcSideRestoredPendingTransaction")
                            "transactionIndex"))
                     "Devnet smoke gate suite side reorg fresh pending view kept old transaction index for ~A"
                     (devnet-smoke-gate-field report "fixtureCase")))
                  (progn
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideTransactionByHash"))
                     "Devnet smoke gate suite side reorg reinserted wrong-chain transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideRawTransaction"))
                     "Devnet smoke gate suite side reorg exposed wrong-chain raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSidePendingTransaction"))
                     "Devnet smoke gate suite side reorg exposed wrong-chain pending transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredRawTransaction"))
                     "Devnet smoke gate suite side reorg fresh restore exposed wrong-chain raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredPendingTransaction"))
                     "Devnet smoke gate suite side reorg fresh restore exposed wrong-chain pending transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))))
              (devnet-smoke-gate-require
               (devnet-smoke-gate-false-p
                (devnet-smoke-gate-field report "databaseRpcSideReceipt"))
               "Devnet smoke gate suite side reorg kept old receipt canonical for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (devnet-smoke-gate-false-p
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredReceipt"))
               "Devnet smoke gate suite side reorg fresh restore kept old receipt canonical for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredChildBlockHash"))
               "Devnet smoke gate suite side fresh restore lost child block for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= "eth_getBalance block hash is not canonical"
                        (devnet-smoke-gate-field
                         report
                         "databaseRpcSideRestoredChildRequireCanonicalError"))
               "Devnet smoke gate suite side fresh restore child requireCanonical error mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (equal (devnet-smoke-gate-noncanonical-state-error-messages)
                      (devnet-smoke-gate-field
                       report
                       "databaseRpcSideRestoredChildRequireCanonicalErrors"))
               "Devnet smoke gate suite side fresh restore child requireCanonical state errors mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredBlockReceiptsCount"))
               "Devnet smoke gate suite side fresh restore kept canonical receipts for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredLogCount"))
               "Devnet smoke gate suite side fresh restore kept canonical logs for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (= 3 (devnet-smoke-gate-field
                     report "databaseRpcSideEngineConnections"))
               "Devnet smoke gate suite side Engine connection count mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (= 9 (devnet-smoke-gate-field
                     report "databaseRpcSidePublicConnections"))
               "Devnet smoke gate suite side public connection count mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (= 20 (devnet-smoke-gate-field
                     report "databaseRpcSideRestoredPublicConnections"))
               "Devnet smoke gate suite side fresh public connection count mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (= 32 (devnet-smoke-gate-field
                      report "databaseRpcSideTotalConnections"))
               "Devnet smoke gate suite side total connection count mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))))))
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
     (cons "pidFile" (or pid-file :false))
     (cons "pidCaseCount" (if pid-file (length reports) 0))
     (cons "databaseFile" (or database-file :false))
     (cons "databasePruneStateBefore" (or state-prune-before :false))
     (cons "databaseCaseCount" (if database-file (length reports) 0))
     (cons "databasePrunedStateCaseCount" pruned-state-case-count)
     (cons "databaseRpcPrunedStateErrorCaseCount"
           pruned-state-error-case-count)
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
    (format t "pidFile=~A~%"
            (devnet-smoke-gate-field report "pidFile"))
    (format t "pidCaseCount=~D~%"
            (devnet-smoke-gate-field report "pidCaseCount"))
    (format t "databaseFile=~A~%"
            (devnet-smoke-gate-field report "databaseFile"))
    (format t "databasePruneStateBefore=~A~%"
            (devnet-smoke-gate-field report "databasePruneStateBefore"))
    (format t "databaseCaseCount=~D~%"
            (devnet-smoke-gate-field report "databaseCaseCount"))
    (format t "databasePrunedStateCaseCount=~D~%"
            (devnet-smoke-gate-field report
                                     "databasePrunedStateCaseCount"))
    (format t "databaseRpcPrunedStateErrorCaseCount=~D~%"
            (devnet-smoke-gate-field
             report "databaseRpcPrunedStateErrorCaseCount")))
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
        (format t "preparedPayloadId=~A~%"
                (devnet-smoke-gate-field report "preparedPayloadId"))
        (format t "preparedPayloadParentHash=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedPayloadParentHash"))
        (format t "preparedPayloadBlockNumber=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedPayloadBlockNumber"))
        (format t "remoteBlockHash=~A~%"
                (devnet-smoke-gate-field report "remoteBlockHash"))
        (format t "remoteBlockStatus=~A~%"
                (devnet-smoke-gate-field report "remoteBlockStatus"))
        (format t "invalidTipsetBlockHash=~A~%"
                (devnet-smoke-gate-field report "invalidTipsetBlockHash"))
        (format t "invalidTipsetStatus=~A~%"
                (devnet-smoke-gate-field report "invalidTipsetStatus"))
        (format t "invalidTipsetValidationError=~A~%"
                (devnet-smoke-gate-field
                 report "invalidTipsetValidationError"))
        (format t "txpoolPendingTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingTransactionHash"))
        (format t "txpoolPendingSender=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingSender"))
        (format t "txpoolPendingNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingNonce"))
        (format t "txpoolPendingInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingInspectSummary"))
        (format t "txpoolBasefeeTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolBasefeeTransactionHash"))
        (format t "txpoolBasefeeNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolBasefeeNonce"))
        (format t "txpoolBasefeeInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolBasefeeInspectSummary"))
        (format t "txpoolQueuedTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolQueuedTransactionHash"))
        (format t "txpoolQueuedNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolQueuedNonce"))
        (format t "txpoolQueuedInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolQueuedInspectSummary"))
        (format t "txpoolStatusPending=~A~%"
                (devnet-smoke-gate-field report "txpoolStatusPending"))
        (format t "txpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field report "txpoolStatusQueued"))
        (format t "blockNumber=~A~%"
                (devnet-smoke-gate-field report "blockNumber"))
        (format t "safeBlockNumber=~A~%"
                (devnet-smoke-gate-field report "safeBlockNumber"))
        (format t "safeBlockHash=~A~%"
                (devnet-smoke-gate-field report "safeBlockHash"))
        (format t "finalizedBlockNumber=~A~%"
                (devnet-smoke-gate-field report "finalizedBlockNumber"))
        (format t "finalizedBlockHash=~A~%"
                (devnet-smoke-gate-field report "finalizedBlockHash"))
        (format t "checkedBalanceAddress=~A~%"
                (devnet-smoke-gate-field report "checkedBalanceAddress"))
        (format t "checkedBalanceField=~A~%"
                (devnet-smoke-gate-field report "checkedBalanceField"))
        (format t "checkedBalance=~A~%"
                (devnet-smoke-gate-field report "checkedBalance"))
        (format t "checkedCheckpointBalance=~A~%"
                (devnet-smoke-gate-field
                 report "checkedCheckpointBalance"))
        (format t "recipientBalance=~A~%"
                (devnet-smoke-gate-field report "recipientBalance"))
        (format t "checkedNonceAddress=~A~%"
                (devnet-smoke-gate-field report "checkedNonceAddress"))
        (format t "checkedNonce=~A~%"
                (devnet-smoke-gate-field report "checkedNonce"))
        (format t "checkedCodeAddress=~A~%"
                (devnet-smoke-gate-field report "checkedCodeAddress"))
        (format t "checkedCode=~A~%"
                (devnet-smoke-gate-field report "checkedCode"))
        (format t "checkedStorageAddress=~A~%"
                (devnet-smoke-gate-field report "checkedStorageAddress"))
        (format t "checkedStorageKey=~A~%"
                (devnet-smoke-gate-field report "checkedStorageKey"))
        (format t "checkedStorage=~A~%"
                (devnet-smoke-gate-field report "checkedStorage"))
        (format t "checkedProofCodeHash=~A~%"
                (devnet-smoke-gate-field report "checkedProofCodeHash"))
        (format t "checkedProofStorageValue=~A~%"
                (devnet-smoke-gate-field report
                                         "checkedProofStorageValue"))
        (format t "checkedLogCount=~A~%"
                (devnet-smoke-gate-field report "checkedLogCount"))
        (format t "checkedSimulationCount=~A~%"
                (devnet-smoke-gate-field report "checkedSimulationCount"))
        (format t "readyFile=~A~%" (devnet-smoke-gate-field report "readyFile"))
        (format t "logFile=~A~%" (devnet-smoke-gate-field report "logFile"))
        (format t "pidFile=~A~%" (devnet-smoke-gate-field report "pidFile"))
        (format t "databaseFile=~A~%"
                (devnet-smoke-gate-field report "databaseFile"))
        (format t "databasePruneStateBefore=~A~%"
                (devnet-smoke-gate-field
                 report "databasePruneStateBefore"))
        (format t "databasePrunedStateAvailable=~A~%"
                (devnet-smoke-gate-field
                 report "databasePrunedStateAvailable"))
        (format t "databaseHeadNumber=~A~%"
                (devnet-smoke-gate-field report "databaseHeadNumber"))
        (format t "databaseRpcBlockNumber=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBlockNumber"))
        (format t "databaseSafeNumber=~A~%"
                (devnet-smoke-gate-field report "databaseSafeNumber"))
        (format t "databaseSafeHash=~A~%"
                (devnet-smoke-gate-field report "databaseSafeHash"))
        (format t "databaseFinalizedNumber=~A~%"
                (devnet-smoke-gate-field report "databaseFinalizedNumber"))
        (format t "databaseFinalizedHash=~A~%"
                (devnet-smoke-gate-field report "databaseFinalizedHash"))
        (format t "databaseRpcBalance=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBalance"))
        (format t "databaseRpcNonce=~A~%"
                (devnet-smoke-gate-field report "databaseRpcNonce"))
        (format t "databaseRpcCode=~A~%"
                (devnet-smoke-gate-field report "databaseRpcCode"))
        (format t "databaseRpcStorage=~A~%"
                (devnet-smoke-gate-field report "databaseRpcStorage"))
        (format t "databaseRpcPreparedPayloadId=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcPreparedPayloadId"))
        (format t "databaseRpcPreparedPayloadParentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPreparedPayloadParentHash"))
        (format t "databaseRpcPreparedPayloadBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPreparedPayloadBlockNumber"))
        (format t "databaseRemoteBlockHash=~A~%"
                (devnet-smoke-gate-field report "databaseRemoteBlockHash"))
        (format t "databaseRpcRemoteBlockStatus=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRemoteBlockStatus"))
        (format t "databaseInvalidTipsetBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseInvalidTipsetBlockHash"))
        (format t "databaseRpcInvalidTipsetStatus=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcInvalidTipsetStatus"))
        (format t "databaseRpcInvalidTipsetValidationError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcInvalidTipsetValidationError"))
        (format t "databaseRpcTxpoolPendingHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHash"))
        (format t "databaseRpcTxpoolSender=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolSender"))
        (format t "databaseRpcTxpoolNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolNonce"))
        (format t "databaseRpcTxpoolInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolInspectSummary"))
        (format t "databaseRpcTxpoolBasefeeHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeHash"))
        (format t "databaseRpcTxpoolBasefeeNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeNonce"))
        (format t "databaseRpcTxpoolBasefeeInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeInspectSummary"))
        (format t "databaseRpcTxpoolQueuedHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedHash"))
        (format t "databaseRpcTxpoolQueuedNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedNonce"))
        (format t "databaseRpcTxpoolQueuedInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedInspectSummary"))
        (format t "databaseRpcTxpoolStatusPending=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolStatusPending"))
        (format t "databaseRpcTxpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolStatusQueued"))
        (format t "databaseRpcTxpoolContentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolContentHash"))
        (format t "databaseRpcTxpoolContentFromHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolContentFromHash"))
        (format t "databaseRpcTxpoolBasefeeContentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeContentHash"))
        (format t "databaseRpcTxpoolBasefeeContentFromHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeContentFromHash"))
        (format t "databaseRpcTxpoolQueuedContentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedContentHash"))
        (format t "databaseRpcTxpoolQueuedContentFromHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedContentFromHash"))
        (format t "databaseRpcTxpoolPublicConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPublicConnections"))
        (format t "databaseRpcProofAddress=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofAddress"))
        (format t "databaseRpcProofCodeHash=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofCodeHash"))
        (format t "databaseRpcProofStorageKey=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofStorageKey"))
        (format t "databaseRpcProofStorageValue=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofStorageValue"))
        (format t "databaseRpcProofStorageCount=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofStorageCount"))
        (format t "databaseRpcProofAccountProofCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcProofAccountProofCount"))
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
        (format t "databaseRpcFullBlockTransactionCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockTransactionCount"))
        (format t "databaseRpcFullBlockTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockTransactionHash"))
        (format t "databaseRpcFullBlockTransactionIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockTransactionIndex"))
        (format t "databaseRpcFullBlockByNumberTransactionCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockByNumberTransactionCount"))
        (format t "databaseRpcFullBlockByNumberTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockByNumberTransactionHash"))
        (format t "databaseRpcFullBlockByNumberTransactionIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockByNumberTransactionIndex"))
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
        (format t "databaseRpcLogCount=~A~%"
                (devnet-smoke-gate-field report "databaseRpcLogCount"))
        (format t "databaseRpcBlockReceiptTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptTransactionHash"))
        (format t "databaseRpcBlockReceiptBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptBlockHash"))
        (format t "databaseRpcBlockReceiptBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptBlockNumber"))
        (format t "databaseRpcBlockTransactionCountByHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockTransactionCountByHash"))
        (format t "databaseRpcBlockTransactionCountByNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockTransactionCountByNumber"))
        (format t "databaseRpcCanonicalHashBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcCanonicalHashBalance"))
        (format t "databaseRpcCanonicalHashRequireBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcCanonicalHashRequireBalance"))
        (format t "databaseRpcRawTransactionByBlockHashAndIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRawTransactionByBlockHashAndIndex"))
        (format t "databaseRpcRawTransactionByHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRawTransactionByHash"))
        (format t "databaseRpcRawTransactionByBlockNumberAndIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRawTransactionByBlockNumberAndIndex"))
        (format t "databaseRpcTransactionByBlockHashAndIndexHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockHashAndIndexHash"))
        (format t "databaseRpcTransactionByBlockHashAndIndexBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockHashAndIndexBlockHash"))
        (format t "databaseRpcTransactionByBlockHashAndIndexBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockHashAndIndexBlockNumber"))
        (format t "databaseRpcTransactionByBlockHashAndIndexIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockHashAndIndexIndex"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockNumberAndIndexHash"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockNumberAndIndexBlockHash"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockNumberAndIndexBlockNumber"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockNumberAndIndexIndex"))
        (format t "databaseRpcSafeBlockHash=~A~%"
                (devnet-smoke-gate-field report "databaseRpcSafeBlockHash"))
        (format t "databaseRpcSafeBlockNumber=~A~%"
                (devnet-smoke-gate-field report "databaseRpcSafeBlockNumber"))
        (format t "databaseRpcFinalizedBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFinalizedBlockHash"))
        (format t "databaseRpcFinalizedBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFinalizedBlockNumber"))
        (format t "databaseRpcCallResult=~A~%"
                (devnet-smoke-gate-field report "databaseRpcCallResult"))
        (format t "databaseRpcFailedCallError=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcFailedCallError"))
        (format t "databaseRpcEstimateGas=~A~%"
                (devnet-smoke-gate-field report "databaseRpcEstimateGas"))
        (format t "databaseRpcAccessListCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcAccessListCount"))
        (format t "databaseRpcAccessListGasUsed=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcAccessListGasUsed"))
        (format t "databaseRpcPostCallStorage=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPostCallStorage"))
        (format t "databaseRpcSimulationCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSimulationCount"))
        (format t "databaseRpcSideBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideBlockHash"))
        (format t "databaseRpcSideForkchoiceStatus=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideForkchoiceStatus"))
        (format t "databaseRpcSideRejectedCheckpointError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRejectedCheckpointError"))
        (format t "databaseRpcSideBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideBlockNumber"))
        (format t "databaseRpcSideLatestBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideLatestBlockHash"))
        (format t "databaseRpcSideTransactionReinserted=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideTransactionReinserted"))
        (format t "databaseRpcSideTransactionByHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideTransactionByHash"))
        (format t "databaseRpcSideRawTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRawTransaction"))
        (format t "databaseRpcSidePendingTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSidePendingTransaction"))
        (format t "databaseRpcSideReceipt=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideReceipt"))
        (format t "databaseRpcSideChildBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideChildBlockHash"))
        (format t "databaseRpcSideBlockReceiptsCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideBlockReceiptsCount"))
        (format t "databaseRpcSideLogCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideLogCount"))
        (format t "databaseRpcSideRestoredHeadNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredHeadNumber"))
        (format t "databaseRpcSideRestoredHeadHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredHeadHash"))
        (format t "databaseRpcSideRestoredRpcBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcBlockNumber"))
        (format t "databaseRpcSideRestoredRpcLatestBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcLatestBlockHash"))
        (format t "databaseRpcSideRestoredSafeNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredSafeNumber"))
        (format t "databaseRpcSideRestoredSafeHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredSafeHash"))
        (format t "databaseRpcSideRestoredFinalizedNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredFinalizedNumber"))
        (format t "databaseRpcSideRestoredFinalizedHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredFinalizedHash"))
        (format t "databaseRpcSideRestoredRpcSafeNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcSafeNumber"))
        (format t "databaseRpcSideRestoredRpcSafeHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcSafeHash"))
        (format t "databaseRpcSideRestoredRpcFinalizedNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcFinalizedNumber"))
        (format t "databaseRpcSideRestoredRpcFinalizedHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcFinalizedHash"))
        (format t "databaseRpcSideRestoredSafeBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredSafeBalance"))
        (format t "databaseRpcSideRestoredFinalizedBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredFinalizedBalance"))
        (format t "databaseRpcSideRestoredRawTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRawTransaction"))
        (format t "databaseRpcSideRestoredPendingTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredPendingTransaction"))
        (format t "databaseRpcSideRestoredReceipt=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredReceipt"))
        (format t "databaseRpcSideRestoredChildBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredChildBlockHash"))
        (format t "databaseRpcSideRestoredChildRequireCanonicalError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredChildRequireCanonicalError"))
        (format t "databaseRpcSideRestoredChildRequireCanonicalErrors=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredChildRequireCanonicalErrors"))
        (format t "databaseRpcSideRestoredBlockReceiptsCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredBlockReceiptsCount"))
        (format t "databaseRpcSideRestoredLogCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredLogCount"))
        (format t "databaseRpcSideRestoredPublicConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredPublicConnections"))
        (format t "databaseRpcSideTotalConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideTotalConnections"))
        (format t "databaseRpcSideEngineConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideEngineConnections"))
        (format t "databaseRpcSidePublicConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSidePublicConnections"))
        (format t "databaseRpcPrunedStateError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPrunedStateError"))
        (format t "databaseRpcPrunedStateErrors=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPrunedStateErrors")))))

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
         (pid-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-pid-file-option+))
         (database-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-database-option+))
         (state-prune-before
           (devnet-smoke-gate-non-negative-integer-option
            args +devnet-smoke-gate-prune-state-before-option+))
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
                       :pid-file pid-file
                       :database-file database-file
                       :state-prune-before state-prune-before))
                    (devnet-smoke-gate-run
                     case-name
                     :ready-file ready-file
                     :log-file log-file
                     :pid-file pid-file
                     :database-file database-file
                     :state-prune-before state-prune-before))))
          (if json-p
              (format t "~&~A~%" (json-encode report))
              (devnet-smoke-gate-print-text report))))))

(devnet-smoke-gate-main)
