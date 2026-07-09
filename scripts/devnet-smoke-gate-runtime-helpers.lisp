(in-package #:ethereum-lisp.test)

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

(defun devnet-smoke-gate-http-endpoint-p (endpoint)
  (and (stringp endpoint)
       (or (uiop:string-prefix-p "http://127.0.0.1:" endpoint)
           (uiop:string-prefix-p "http://localhost:" endpoint))))

(defun devnet-smoke-gate-verify-ready-file
    (path expected-head-number expected-head-hash
     &key expected-head-gas-limit expected-engine-endpoint
       expected-rpc-endpoint)
  (let ((summary (parse-json (devnet-smoke-gate-file-string path))))
    (devnet-smoke-gate-require
     (string= (or expected-engine-endpoint +devnet-smoke-gate-engine-endpoint+)
              (fixture-object-field summary "engineEndpoint"))
     "Ready file Engine endpoint mismatch")
    (devnet-smoke-gate-require
     (string= (or expected-rpc-endpoint +devnet-smoke-gate-public-endpoint+)
              (fixture-object-field summary "rpcEndpoint"))
     "Ready file public RPC endpoint mismatch")
    (devnet-smoke-gate-require
     (devnet-smoke-gate-http-endpoint-p
      (fixture-object-field summary "engineEndpoint"))
     "Ready file Engine endpoint must be an HTTP loopback endpoint")
    (devnet-smoke-gate-require
     (devnet-smoke-gate-http-endpoint-p
      (fixture-object-field summary "rpcEndpoint"))
     "Ready file public RPC endpoint must be an HTTP loopback endpoint")
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
    (when expected-head-gas-limit
      (devnet-smoke-gate-require
       (string= expected-head-gas-limit
                (quantity-to-hex
                 (fixture-object-field summary "headGasLimit")))
       "Ready file head gas limit mismatch"))
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

(defun devnet-smoke-gate-connection-count-string (summary key)
  (write-to-string (or (getf summary key) 0)))

(defun devnet-smoke-gate-verify-log-file
    (path ready-head-number ready-head-hash shutdown-head-number
     shutdown-head-hash &key expected-process-id expected-connection-summary
       ready-head-gas-limit shutdown-head-gas-limit
       expected-engine-endpoint expected-rpc-endpoint)
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
                 (if ready-p ready-head-hash shutdown-head-hash))
               (expected-head-gas-limit
                 (if ready-p ready-head-gas-limit shutdown-head-gas-limit)))
          (devnet-smoke-gate-require
           (string= (or expected-engine-endpoint
                        +devnet-smoke-gate-engine-endpoint+)
                    (cdr (assoc "engineEndpoint" fields :test #'string=)))
           "Log file Engine endpoint mismatch")
          (devnet-smoke-gate-require
           (string= (or expected-rpc-endpoint
                        +devnet-smoke-gate-public-endpoint+)
                    (cdr (assoc "rpcEndpoint" fields :test #'string=)))
           "Log file public RPC endpoint mismatch")
          (devnet-smoke-gate-require
           (devnet-smoke-gate-http-endpoint-p
            (cdr (assoc "engineEndpoint" fields :test #'string=)))
           "Log file Engine endpoint must be an HTTP loopback endpoint")
          (devnet-smoke-gate-require
           (devnet-smoke-gate-http-endpoint-p
            (cdr (assoc "rpcEndpoint" fields :test #'string=)))
           "Log file public RPC endpoint must be an HTTP loopback endpoint")
          (devnet-smoke-gate-require
           (string= (if ready-p "ready" "shutdown")
                    (cdr (assoc "lifecyclePhase" fields :test #'string=)))
           "Log file lifecycle phase mismatch")
          (devnet-smoke-gate-require
           (string= (if ready-p
                        "0"
                        (devnet-smoke-gate-connection-count-string
                         expected-connection-summary
                         :engine-connections))
                    (cdr (assoc "engineConnections" fields :test #'string=)))
           "Log file Engine connection count mismatch")
          (devnet-smoke-gate-require
           (string= (if ready-p
                        "0"
                        (devnet-smoke-gate-connection-count-string
                         expected-connection-summary
                         :public-connections))
                    (cdr (assoc "publicConnections" fields :test #'string=)))
           "Log file public connection count mismatch")
          (devnet-smoke-gate-require
           (string= (if ready-p
                        "0"
                        (devnet-smoke-gate-connection-count-string
                         expected-connection-summary
                         :total-connections))
                    (cdr (assoc "totalConnections" fields :test #'string=)))
           "Log file total connection count mismatch")
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
          (when expected-head-gas-limit
            (devnet-smoke-gate-require
             (string= expected-head-gas-limit
                      (cdr (assoc "headGasLimit" fields :test #'string=)))
             "Log file head gas limit mismatch"))
          (devnet-smoke-gate-require
           (string= "true"
                    (cdr (assoc "stateAvailable" fields :test #'string=)))
           "Log file state availability mismatch"))))
    records))

