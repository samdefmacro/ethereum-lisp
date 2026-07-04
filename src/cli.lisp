(in-package #:ethereum-lisp.cli)

(defstruct (devnet-node
            (:constructor %make-devnet-node
                (&key genesis-path store config genesis-block service
                      public-service telemetry-sink jwt-secret-path log-path
                      database-path pid-file-path network-id
                      public-api-modules engine-cors-origins
                      public-cors-origins
                      engine-vhosts public-vhosts dev-mode-p coinbase
                      allow-unprotected-transactions-p
                      txpool-price-limit txpool-price-bump-percent
                      txpool-account-slot-limit
                      txpool-global-slot-limit
                      txpool-account-queue-limit
                      txpool-global-queue-limit
                      txpool-local-addresses txpool-no-local-exemptions-p
                      kzg-verifier-command
                      kzg-verifier-timeout-seconds)))
  genesis-path
  store
  config
  genesis-block
  service
  public-service
  telemetry-sink
  jwt-secret-path
  log-path
  database-path
  pid-file-path
  network-id
  public-api-modules
  engine-cors-origins
  public-cors-origins
  engine-vhosts
  public-vhosts
  dev-mode-p
  coinbase
  allow-unprotected-transactions-p
  txpool-price-limit
  txpool-price-bump-percent
  txpool-account-slot-limit
  txpool-global-slot-limit
  txpool-account-queue-limit
  txpool-global-queue-limit
  txpool-local-addresses
  txpool-no-local-exemptions-p
  kzg-verifier-command
  kzg-verifier-timeout-seconds)

(defstruct devnet-shutdown-controller
  requested-p
  engine-listener
  public-listener)

(defconstant +devnet-default-public-rpc-port+ 8545)
(defconstant +devnet-datadir-database-file+ "ethereum-lisp-chain.sexp")
(defconstant +devnet-datadir-genesis-file+ "genesis.json")
(defconstant +devnet-datadir-jwt-secret-file+ "jwtsecret")
(defconstant +devnet-geth-datadir-directory+ "geth/")
(defconstant +devnet-default-dev-gas-limit+ #x1c9c380)

(defun devnet-cli-dev-genesis-json (&key
                                      (gas-limit
                                       +devnet-default-dev-gas-limit+)
                                      (coinbase (zero-address)))
  (concatenate
   'string
   "{"
   "\"config\":{\"chainId\":1337,\"terminalTotalDifficulty\":0,"
   "\"londonBlock\":0,\"shanghaiTime\":0},"
   "\"nonce\":\"0x0\","
   "\"timestamp\":\"0x0\","
   "\"extraData\":\"0x\","
   "\"gasLimit\":\"" (quantity-to-hex gas-limit) "\","
   "\"difficulty\":\"0x0\","
   "\"mixHash\":\"0x0000000000000000000000000000000000000000000000000000000000000000\","
   "\"coinbase\":\"" (address-to-hex coinbase) "\","
   "\"stateRoot\":\"0x23cc0c47d1238030e9c1ec18013dcb17024d3d42729567adbb6406a64d3007f3\","
   "\"alloc\":{"
   "\"0x0000000000000000000000000000000000001001\":{"
   "\"balance\":\"0xde0b6b3a7640000\",\"nonce\":\"0x1\"},"
   "\"0x0000000000000000000000000000000000001002\":{"
   "\"balance\":\"0x5\",\"code\":\"0x6001600055\","
   "\"storage\":{\"0x00\":\"0x2a\",\"0x01\":\"0x00\"}}"
   "}}"))

(defun devnet-process-id ()
  #+sbcl
  (sb-unix:unix-getpid)
  #-sbcl
  nil)

(defun devnet-shutdown-requested-p (controller)
  (and controller
       (devnet-shutdown-controller-requested-p controller)))

(defun devnet-shutdown-controller-register-listeners
    (controller engine-listener public-listener)
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (setf (devnet-shutdown-controller-engine-listener controller) engine-listener
        (devnet-shutdown-controller-public-listener controller) public-listener)
  controller)

(defun devnet-shutdown-request (controller)
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (setf (devnet-shutdown-controller-requested-p controller) t)
  (let ((engine-listener
          (devnet-shutdown-controller-engine-listener controller))
        (public-listener
          (devnet-shutdown-controller-public-listener controller)))
    (when engine-listener
      (ignore-errors
       (engine-rpc-http-listener-close engine-listener)))
    (when public-listener
      (ignore-errors
       (engine-rpc-http-listener-close public-listener))))
  t)

(defun devnet-signal-number (name)
  #+sbcl
  (let* ((package (find-package "SB-UNIX"))
         (symbol (and package (find-symbol name package))))
    (unless (and symbol (boundp symbol))
      (error "SBCL signal ~A is not available" name))
    (symbol-value symbol))
  #-sbcl
  (declare (ignore name))
  #-sbcl
  nil)

(defun call-with-devnet-shutdown-signal-handlers
    (controller thunk &key (stream *error-output*))
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (unless (functionp thunk)
    (error "Devnet shutdown signal thunk must be a function"))
  #-sbcl
  (declare (ignore controller stream))
  #-sbcl
  (funcall thunk)
  #+sbcl
  (let ((sigint (devnet-signal-number "SIGINT"))
        (sigterm (devnet-signal-number "SIGTERM")))
    (flet ((request-shutdown (&rest ignored)
             (declare (ignore ignored))
             (format stream "Devnet shutdown requested; closing RPC listeners.~%")
             (devnet-shutdown-request controller)))
      (unwind-protect
           (progn
             (sb-sys:enable-interrupt sigint #'request-shutdown)
             (sb-sys:enable-interrupt sigterm #'request-shutdown)
             (funcall thunk))
        (sb-sys:enable-interrupt sigint :default)
        (sb-sys:enable-interrupt sigterm :default)))))

(defun devnet-cli-read-file-string (path)
  (with-open-file (stream path :direction :input)
    (let ((string (make-string (file-length stream))))
      (read-sequence string stream)
      string)))

(defun devnet-cli-jwt-secret-file-error (path &optional condition)
  (error
   "--jwt-secret/--authrpc.jwtsecret must name a readable file containing a 32-byte hex secret: ~A~@[ (~A)~]"
   path
   condition))

(defun devnet-cli-read-jwt-secret (path)
  (let* ((text
           (handler-case
               (devnet-cli-read-file-string path)
             (error (condition)
               (devnet-cli-jwt-secret-file-error path condition))))
         (trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) text))
         (secret
           (handler-case
               (hex-to-bytes trimmed)
             (error (condition)
               (devnet-cli-jwt-secret-file-error path condition)))))
    (unless (= 32 (length secret))
      (devnet-cli-jwt-secret-file-error path))
    secret))

(defun devnet-cli-empty-file-p (path)
  (with-open-file (stream path :direction :input)
    (zerop (file-length stream))))

(defun devnet-cli-kv-chain-records-present-p (database)
  (some
   (lambda (kind)
     (not (null
           (ethereum-lisp.database:kv-chain-record-entries database kind))))
   '(:block :header :receipt :canonical-hash :checkpoint :state
     :transaction-location)))

(defun devnet-cli-make-output-kv-database (path)
  (ensure-directories-exist (pathname path))
  (let ((existing-path (probe-file path)))
    (when (and existing-path (devnet-cli-empty-file-p existing-path))
      (delete-file existing-path)))
  (ethereum-lisp.database:make-file-key-value-database path))

(defun devnet-cli-datadir-database-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-database-file+
    (uiop:ensure-directory-pathname datadir))))

(defun devnet-cli-datadir-genesis-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-genesis-file+
    (uiop:ensure-directory-pathname datadir))))

(defun devnet-cli-datadir-jwt-secret-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-jwt-secret-file+
    (uiop:ensure-directory-pathname datadir))))

(defun devnet-cli-datadir-geth-jwt-secret-path (datadir)
  (namestring
   (merge-pathnames
    +devnet-datadir-jwt-secret-file+
    (merge-pathnames
     +devnet-geth-datadir-directory+
     (uiop:ensure-directory-pathname datadir)))))

(defun devnet-cli-datadir-jwt-secret-paths (datadir)
  (list (devnet-cli-datadir-jwt-secret-path datadir)
        (devnet-cli-datadir-geth-jwt-secret-path datadir)))

(defun devnet-cli-existing-datadir-jwt-secret-path (datadir)
  (loop for path in (devnet-cli-datadir-jwt-secret-paths datadir)
        when (probe-file path)
          return path))

(defun devnet-cli-copy-file-string (source target)
  (let ((contents (devnet-cli-read-file-string source)))
    (with-open-file (stream (devnet-cli-ensure-path-parent-directory target)
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string contents stream))))

(defun devnet-cli-random-bytes (length)
  (let ((bytes (make-array length :element-type '(unsigned-byte 8))))
    (handler-case
        (with-open-file (stream #P"/dev/urandom"
                                :direction :input
                                :element-type '(unsigned-byte 8))
          (unless (= length (read-sequence bytes stream))
            (error "Unable to read enough bytes from /dev/urandom"))
          bytes)
      (error ()
        (let ((state (make-random-state t)))
          (dotimes (index length bytes)
            (setf (aref bytes index) (random 256 state))))))))

(defun devnet-cli-ensure-datadir-jwt-secret (datadir &key source-path)
  (when datadir
    (if source-path
        (let ((path (devnet-cli-datadir-jwt-secret-path datadir))
              (secret (devnet-cli-read-jwt-secret source-path)))
          (with-open-file (stream (devnet-cli-ensure-path-parent-directory path)
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
            (write-string (bytes-to-hex secret :prefix nil) stream)
            (terpri stream))
          path)
        (or (devnet-cli-existing-datadir-jwt-secret-path datadir)
            (let ((path (devnet-cli-datadir-jwt-secret-path datadir)))
              (with-open-file
                  (stream (devnet-cli-ensure-path-parent-directory path)
                          :direction :output
                          :if-exists nil
                          :if-does-not-exist :create)
                (when stream
                  (write-string
                   (bytes-to-hex (devnet-cli-random-bytes 32) :prefix nil)
                   stream)
                  (terpri stream)))
              path)))))

(defun devnet-cli-validate-imported-genesis (store genesis-block database-path)
  (let ((restored-genesis (chain-store-block-by-number store 0)))
    (when (and restored-genesis
               (not (equalp (hash32-bytes (block-hash restored-genesis))
                            (hash32-bytes (block-hash genesis-block)))))
      (error
       "Devnet database genesis does not match genesis file (~A): expected ~A, got ~A"
       database-path
       (hash32-to-hex (block-hash genesis-block))
       (hash32-to-hex (block-hash restored-genesis))))))

(defun make-devnet-node
    (&key
       genesis-path
       genesis-json
       dev-mode-p
       (host "127.0.0.1")
       (port +engine-rpc-default-http-port+)
       (public-host host)
       (public-port +devnet-default-public-rpc-port+)
       jwt-secret-path
       (engine-rpc-prefix "/")
       (public-rpc-prefix "/")
       log-path
       database-path
       pid-file-path
       network-id
       public-api-modules
       engine-cors-origins
       public-cors-origins
       engine-vhosts
       public-vhosts
       terminal-total-difficulty
       terminal-total-difficulty-passed
       terminal-total-difficulty-passed-specified-p
       terminal-block-hash
       terminal-block-number
       (coinbase (zero-address))
       allow-unprotected-transactions-p
       txpool-price-limit
       txpool-price-bump-percent
       txpool-account-slot-limit
       txpool-global-slot-limit
       txpool-account-queue-limit
       txpool-global-queue-limit
       txpool-local-addresses
       txpool-no-local-exemptions-p
       kzg-verifier-command
       kzg-verifier-timeout-seconds
       (public-allowed-method-p #'engine-rpc-public-method-p)
       (telemetry-sink ethereum-lisp.telemetry:*telemetry-sink*))
  (unless (or (and genesis-path (stringp genesis-path))
              (and genesis-json (stringp genesis-json)))
    (error "Devnet node requires a genesis JSON path or source"))
  (unless (functionp public-allowed-method-p)
    (error "Devnet public RPC method filter must be a function"))
  (let* ((genesis-json (and (null genesis-path) genesis-json))
         (config
           (devnet-cli-apply-merge-overrides
            (if genesis-json
                (chain-config-from-genesis-json-string genesis-json)
                (chain-config-from-genesis-json-file genesis-path))
            :terminal-total-difficulty terminal-total-difficulty
            :terminal-total-difficulty-passed terminal-total-difficulty-passed
            :terminal-total-difficulty-passed-specified-p
            terminal-total-difficulty-passed-specified-p
            :terminal-block-hash terminal-block-hash
            :terminal-block-number terminal-block-number))
         (state
           (if genesis-json
               (state-db-from-genesis-json-string genesis-json)
               (state-db-from-genesis-json-file genesis-path)))
         (genesis-block
           (if genesis-json
               (genesis-block-from-state-genesis-json-string
                genesis-json
                :config config)
               (genesis-block-from-state-genesis-json-file
                genesis-path
                :config config)))
         (effective-network-id (or network-id (chain-config-chain-id config)))
         (store (make-engine-payload-memory-store))
         (jwt-secret (and jwt-secret-path
                          (devnet-cli-read-jwt-secret jwt-secret-path)))
         (service
           (make-engine-rpc-http-service
            :host host
            :port port
            :store store
            :config config
            :network-id effective-network-id
            :coinbase coinbase
            :jwt-secret jwt-secret
            :rpc-prefix engine-rpc-prefix
            :allowed-method-p #'engine-rpc-engine-method-p
            :cors-origins engine-cors-origins
            :allowed-hosts engine-vhosts
            :telemetry-sink telemetry-sink))
         (public-service
           (make-engine-rpc-http-service
            :host public-host
            :port public-port
            :store store
            :config config
            :network-id effective-network-id
            :coinbase coinbase
            :rpc-prefix public-rpc-prefix
            :allowed-method-p public-allowed-method-p
            :cors-origins public-cors-origins
            :allowed-hosts public-vhosts
            :allow-unprotected-transactions-p
            allow-unprotected-transactions-p
            :txpool-price-limit txpool-price-limit
            :txpool-price-bump-percent txpool-price-bump-percent
            :txpool-account-slot-limit txpool-account-slot-limit
            :txpool-global-slot-limit txpool-global-slot-limit
            :txpool-account-queue-limit txpool-account-queue-limit
            :txpool-global-queue-limit txpool-global-queue-limit
            :txpool-local-addresses txpool-local-addresses
            :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
            :telemetry-sink telemetry-sink)))
    (chain-store-put-block store genesis-block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis-block) state)
    (when database-path
      (let ((existing-database-path (probe-file database-path)))
        (when (and existing-database-path
                   (not (devnet-cli-empty-file-p existing-database-path)))
          (let ((database
                  (ethereum-lisp.database:make-file-key-value-database
                   existing-database-path)))
            (when (devnet-cli-kv-chain-records-present-p database)
              (chain-store-import-from-kv
               store
               database
               :expected-chain-id (chain-config-chain-id config)
               :chain-config config)
              (devnet-cli-validate-imported-genesis
               store genesis-block existing-database-path))))))
    (%make-devnet-node
     :genesis-path genesis-path
     :store store
     :config config
     :genesis-block genesis-block
     :service service
     :public-service public-service
     :telemetry-sink telemetry-sink
     :jwt-secret-path jwt-secret-path
     :log-path log-path
     :database-path database-path
     :pid-file-path pid-file-path
     :network-id effective-network-id
     :public-api-modules (and public-api-modules
                              (copy-list public-api-modules))
     :engine-cors-origins (and engine-cors-origins
                               (copy-list engine-cors-origins))
     :public-cors-origins (and public-cors-origins
                               (copy-list public-cors-origins))
     :engine-vhosts (and engine-vhosts
                         (copy-list engine-vhosts))
     :public-vhosts (and public-vhosts
                         (copy-list public-vhosts))
     :dev-mode-p dev-mode-p
     :coinbase coinbase
     :allow-unprotected-transactions-p allow-unprotected-transactions-p
     :txpool-price-limit txpool-price-limit
     :txpool-price-bump-percent txpool-price-bump-percent
     :txpool-account-slot-limit txpool-account-slot-limit
     :txpool-global-slot-limit txpool-global-slot-limit
     :txpool-account-queue-limit txpool-account-queue-limit
     :txpool-global-queue-limit txpool-global-queue-limit
     :txpool-local-addresses (and txpool-local-addresses
                                  (copy-list txpool-local-addresses))
     :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
     :kzg-verifier-command kzg-verifier-command
     :kzg-verifier-timeout-seconds
     (and kzg-verifier-command
          (or kzg-verifier-timeout-seconds
              *kzg-verifier-command-timeout-seconds*)))))

(defun devnet-cli-apply-merge-overrides
    (config &key terminal-total-difficulty
                  terminal-total-difficulty-passed
                  terminal-total-difficulty-passed-specified-p
                  terminal-block-hash
                  terminal-block-number)
  (unless (typep config 'chain-config)
    (error "Devnet Merge overrides require a chain config"))
  (when terminal-total-difficulty
    (setf (chain-config-terminal-total-difficulty config)
          terminal-total-difficulty))
  (when terminal-total-difficulty-passed-specified-p
    (setf (chain-config-terminal-total-difficulty-passed config)
          terminal-total-difficulty-passed))
  (when terminal-block-hash
    (setf (chain-config-terminal-block-hash config) terminal-block-hash))
  (when terminal-block-number
    (setf (chain-config-terminal-block-number config) terminal-block-number))
  config)

(defun devnet-node-prune-state-before (node block-number)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (when block-number
    (chain-store-prune-state-before (devnet-node-store node) block-number)))

(defun devnet-node-export-database (node &key state-prune-before)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (devnet-node-prune-state-before node state-prune-before)
  (let ((database-path (devnet-node-database-path node)))
    (when database-path
      (chain-store-export-to-kv
       (devnet-node-store node)
       (devnet-cli-make-output-kv-database database-path)))))

(defun devnet-block-number (block)
  (and block (block-header-number (block-header block))))

(defun devnet-block-hash-hex (block)
  (and block (hash32-to-hex (block-hash block))))

(defun devnet-node-summary
    (node &key engine-endpoint rpc-endpoint (public-rpc-enabled-p t))
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let* ((store (devnet-node-store node))
         (head (chain-store-latest-block store))
         (safe (chain-store-safe-block store))
         (finalized (chain-store-finalized-block store))
         (engine-endpoint
           (or engine-endpoint
                (engine-rpc-http-service-endpoint
                (devnet-node-service node))))
         (rpc-endpoint
           (and public-rpc-enabled-p
                (or rpc-endpoint
                    (engine-rpc-http-service-endpoint
                     (devnet-node-public-service node))))))
    (list :genesis-path (devnet-node-genesis-path node)
          :engine-endpoint engine-endpoint
          :rpc-endpoint rpc-endpoint
          :public-rpc-enabled-p public-rpc-enabled-p
          :engine-rpc-prefix
          (engine-rpc-http-service-rpc-prefix (devnet-node-service node))
          :public-rpc-prefix
          (engine-rpc-http-service-rpc-prefix
           (devnet-node-public-service node))
          :process-id (devnet-process-id)
          :auth-required-p
          (not (null (engine-rpc-http-service-jwt-secret
                      (devnet-node-service node))))
          :jwt-secret-path (devnet-node-jwt-secret-path node)
          :log-path (devnet-node-log-path node)
          :database-path (devnet-node-database-path node)
          :pid-file-path (devnet-node-pid-file-path node)
          :network-id (devnet-node-network-id node)
          :public-api-modules (devnet-node-public-api-modules node)
          :engine-cors-origins (devnet-node-engine-cors-origins node)
          :public-cors-origins (devnet-node-public-cors-origins node)
          :engine-vhosts (devnet-node-engine-vhosts node)
          :public-vhosts (devnet-node-public-vhosts node)
          :dev-mode-p (devnet-node-dev-mode-p node)
          :coinbase (address-to-hex (devnet-node-coinbase node))
          :allow-unprotected-transactions-p
          (devnet-node-allow-unprotected-transactions-p node)
          :txpool-price-limit (devnet-node-txpool-price-limit node)
          :txpool-price-bump-percent
          (devnet-node-txpool-price-bump-percent node)
          :txpool-account-slot-limit
          (devnet-node-txpool-account-slot-limit node)
          :txpool-global-slot-limit
          (devnet-node-txpool-global-slot-limit node)
          :txpool-account-queue-limit
          (devnet-node-txpool-account-queue-limit node)
          :txpool-global-queue-limit
          (devnet-node-txpool-global-queue-limit node)
          :txpool-local-addresses
          (mapcar #'address-to-hex (or (devnet-node-txpool-local-addresses node)
                                       '()))
          :txpool-no-local-exemptions-p
          (devnet-node-txpool-no-local-exemptions-p node)
          :kzg-verifier-command (devnet-node-kzg-verifier-command node)
          :kzg-verifier-timeout-seconds
          (devnet-node-kzg-verifier-timeout-seconds node)
          :kzg-proof-verification-available-p
          (kzg-proof-verification-available-p)
          :chain-id (chain-config-chain-id (devnet-node-config node))
          :head-number (devnet-block-number head)
          :head-hash (devnet-block-hash-hex head)
          :safe-number (devnet-block-number safe)
          :safe-hash (devnet-block-hash-hex safe)
          :finalized-number (devnet-block-number finalized)
          :finalized-hash (devnet-block-hash-hex finalized)
          :head-gas-limit
          (and head
               (block-header-gas-limit (block-header head)))
          :state-available-p
          (and head
               (chain-store-state-available-p store (block-hash head))))))

(defun devnet-node-summary-json-object
    (node &key engine-endpoint rpc-endpoint (public-rpc-enabled-p t))
  (let ((summary (devnet-node-summary
                  node
                  :engine-endpoint engine-endpoint
                  :rpc-endpoint rpc-endpoint
                  :public-rpc-enabled-p public-rpc-enabled-p)))
    `(("genesisPath" . ,(getf summary :genesis-path))
      ("engineEndpoint" . ,(getf summary :engine-endpoint))
      ("rpcEndpoint" . ,(or (getf summary :rpc-endpoint) :false))
      ("publicRpcEnabled" . ,(if (getf summary :public-rpc-enabled-p)
                                 t
                                 :false))
      ("engineRpcPrefix" . ,(getf summary :engine-rpc-prefix))
      ("publicRpcPrefix" . ,(getf summary :public-rpc-prefix))
      ("processId" . ,(or (getf summary :process-id) :false))
      ("authRequired" . ,(if (getf summary :auth-required-p) t :false))
      ("jwtSecretPath" . ,(getf summary :jwt-secret-path))
      ("logPath" . ,(getf summary :log-path))
      ("databasePath" . ,(getf summary :database-path))
      ("pidFilePath" . ,(getf summary :pid-file-path))
      ("devMode" . ,(if (getf summary :dev-mode-p) t :false))
      ("coinbase" . ,(getf summary :coinbase))
      ("allowUnprotectedTransactions" .
       ,(if (getf summary :allow-unprotected-transactions-p) t :false))
      ("txpoolPriceLimit" . ,(or (getf summary :txpool-price-limit) :false))
      ("txpoolPriceBump" .
       ,(or (getf summary :txpool-price-bump-percent) :false))
      ("txpoolAccountSlots" .
       ,(or (getf summary :txpool-account-slot-limit) :false))
      ("txpoolGlobalSlots" .
       ,(or (getf summary :txpool-global-slot-limit) :false))
      ("txpoolAccountQueue" .
       ,(or (getf summary :txpool-account-queue-limit) :false))
      ("txpoolGlobalQueue" .
       ,(or (getf summary :txpool-global-queue-limit) :false))
      ("txpoolLocals" . ,(getf summary :txpool-local-addresses))
      ("txpoolNoLocals" .
       ,(if (getf summary :txpool-no-local-exemptions-p) t :false))
      ("networkId" . ,(getf summary :network-id))
      ("publicApiModules" . ,(getf summary :public-api-modules))
      ("engineCorsOrigins" . ,(getf summary :engine-cors-origins))
      ("publicCorsOrigins" . ,(getf summary :public-cors-origins))
      ("engineVhosts" . ,(getf summary :engine-vhosts))
      ("publicVhosts" . ,(getf summary :public-vhosts))
      ("kzgVerifierCommand" . ,(or (getf summary :kzg-verifier-command)
                                   :false))
      ("kzgVerifierTimeoutSeconds" .
       ,(or (getf summary :kzg-verifier-timeout-seconds) :false))
      ("kzgProofVerificationAvailable" .
       ,(if (getf summary :kzg-proof-verification-available-p) t :false))
      ("chainId" . ,(getf summary :chain-id))
      ("headNumber" . ,(getf summary :head-number))
      ("headHash" . ,(getf summary :head-hash))
      ("headGasLimit" . ,(or (getf summary :head-gas-limit) :false))
      ("safeNumber" . ,(or (getf summary :safe-number) :false))
      ("safeHash" . ,(or (getf summary :safe-hash) :false))
      ("finalizedNumber" . ,(or (getf summary :finalized-number) :false))
      ("finalizedHash" . ,(or (getf summary :finalized-hash) :false))
      ("stateAvailable" . ,(if (getf summary :state-available-p) t :false)))))

(defun start-devnet-node-listeners
    (node engine-listener public-listener
     &key max-connections stop-p shutdown-controller on-listeners-ready)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (unless (typep engine-listener 'engine-rpc-http-listener)
    (error "Devnet Engine listener must be engine-rpc-http-listener"))
  (when (and public-listener
             (not (typep public-listener 'engine-rpc-http-listener)))
    (error "Devnet public listener must be engine-rpc-http-listener"))
  (when (and stop-p (not (functionp stop-p)))
    (error "Devnet stop predicate must be a function"))
  (when (and shutdown-controller
             (not (typep shutdown-controller 'devnet-shutdown-controller)))
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (when (and on-listeners-ready (not (functionp on-listeners-ready)))
    (error "Devnet listener-ready callback must be a function"))
  #-sbcl
  (declare (ignore node engine-listener public-listener max-connections stop-p
                   shutdown-controller on-listeners-ready))
  #-sbcl
  (error "Devnet split listener serving requires SBCL threads")
  #+sbcl
  (let* ((shutdown-controller
           (or shutdown-controller (make-devnet-shutdown-controller)))
         (stop-requested-p
           (lambda ()
             (or (devnet-shutdown-requested-p shutdown-controller)
                 (and stop-p (funcall stop-p)))))
         (engine-count nil)
         (engine-error nil)
         (public-count nil)
         (public-error nil))
    (devnet-shutdown-controller-register-listeners
     shutdown-controller engine-listener public-listener)
    (handler-case
        (when on-listeners-ready
          (funcall on-listeners-ready engine-listener public-listener))
      (error (condition)
        (devnet-shutdown-request shutdown-controller)
        (error condition)))
    (if public-listener
        (let ((engine-thread
                (sb-thread:make-thread
                 (lambda ()
                   (handler-case
                       (setf engine-count
                             (engine-rpc-http-service-serve-listener
                              (devnet-node-service node)
                              engine-listener
                              :max-connections max-connections
                              :stop-p stop-requested-p))
                     (error (condition)
                       (setf engine-error condition)
                       (devnet-shutdown-request shutdown-controller))))
                 :name "ethereum-lisp-devnet-engine-rpc")))
          (handler-case
              (setf public-count
                    (engine-rpc-http-service-serve-listener
                     (devnet-node-public-service node)
                     public-listener
                     :max-connections max-connections
                     :stop-p stop-requested-p))
            (error (condition)
              (setf public-error condition)
              (devnet-shutdown-request shutdown-controller)))
          (when public-count
            (devnet-shutdown-request shutdown-controller))
          (sb-thread:join-thread engine-thread)
          (cond
            (public-error (error public-error))
            (engine-error (error engine-error))
            (t
             (list :engine-connections engine-count
                   :public-connections public-count
                   :total-connections (+ engine-count public-count)))))
        (handler-case
            (let ((engine-count
                    (engine-rpc-http-service-serve-listener
                     (devnet-node-service node)
                     engine-listener
                     :max-connections max-connections
                     :stop-p stop-requested-p)))
              (devnet-shutdown-request shutdown-controller)
              (list :engine-connections engine-count
                    :public-connections 0
                    :total-connections engine-count))
          (error (condition)
            (devnet-shutdown-request shutdown-controller)
            (error condition))))))

(defun start-devnet-node
    (node &key max-connections stop-p shutdown-controller
            install-signal-handlers-p signal-stream on-listeners-ready
            (public-rpc-enabled-p t))
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (when (and shutdown-controller
             (not (typep shutdown-controller 'devnet-shutdown-controller)))
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (when (and on-listeners-ready (not (functionp on-listeners-ready)))
    (error "Devnet listener-ready callback must be a function"))
  (let ((shutdown-controller
          (or shutdown-controller (make-devnet-shutdown-controller)))
        (engine-listener nil)
        (public-listener nil)
        (served-p nil))
    (unwind-protect
         (progn
           (setf engine-listener
                 (make-engine-rpc-http-socket-listener
                  (devnet-node-service node)))
           (devnet-shutdown-controller-register-listeners
            shutdown-controller engine-listener nil)
           (when public-rpc-enabled-p
             (setf public-listener
                   (make-engine-rpc-http-socket-listener
                    (devnet-node-public-service node))))
           (devnet-shutdown-controller-register-listeners
            shutdown-controller engine-listener public-listener)
           (prog1
               (flet ((serve ()
                        (start-devnet-node-listeners
                         node
                         engine-listener
                         public-listener
                         :max-connections max-connections
                         :stop-p stop-p
                         :shutdown-controller shutdown-controller
                         :on-listeners-ready on-listeners-ready)))
                 (if install-signal-handlers-p
                     (call-with-devnet-shutdown-signal-handlers
                      shutdown-controller
                      #'serve
                      :stream (or signal-stream *error-output*))
                     (serve)))
             (setf served-p t)))
      (unless served-p
        (devnet-shutdown-request shutdown-controller)))))

(defun devnet-cli-option-token-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (string= "--" value :end2 2)))

(defun devnet-cli-normalize-option-args (args)
  (loop for arg in args
        for separator = (and (devnet-cli-option-token-p arg)
                             (position #\= arg :start 2))
        append (if separator
                   (list (subseq arg 0 separator)
                         (subseq arg (1+ separator)))
                   (list arg))))

(defun devnet-cli-parse-boolean-token (value option)
  (let ((normalized (and (stringp value) (string-downcase value))))
    (cond
      ((member normalized '("true" "1") :test #'string=) t)
      ((member normalized '("false" "0") :test #'string=) nil)
      (t (error "~A boolean value must be true or false" option)))))

(defun devnet-cli-boolean-token-p (value)
  (and (stringp value)
       (member (string-downcase value)
               '("true" "false" "1" "0")
               :test #'string=)))

(defparameter *devnet-cli-value-options*
  '("--config" "--genesis" "--host" "--engine-host" "--authrpc.addr"
    "--port" "--engine-port" "--authrpc.port" "--public-host"
    "--http.addr" "--public-port" "--http.port" "--jwt-secret"
    "--authrpc.jwtsecret" "--authrpc.rpcprefix" "--http.rpcprefix"
    "--database" "--datadir" "--networkid" "--network-id"
    "--prune-state-before" "--max-connections" "--http.api"
    "--http.corsdomain" "--authrpc.corsdomain" "--authrpc.vhosts"
    "--http.vhosts" "--http.maxclients" "--http.readtimeout"
    "--http.writetimeout" "--http.idletimeout"
    "--ws.addr" "--ws.port" "--ws.api" "--ws.origins" "--ws.rpcprefix"
    "--ipcapi"
    "--graphql.addr" "--graphql.port" "--graphql.vhosts"
    "--graphql.corsdomain" "--syncmode" "--verbosity" "--maxpeers"
    "--log.file" "--log.format" "--log.maxsize" "--log.maxbackups"
    "--log.maxage" "--nat" "--identity" "--gcmode" "--cache"
    "--cache.database" "--cache.gc" "--cache.trie" "--state.scheme" "--db.engine"
    "--datadir.ancient" "--ipcpath" "--netrestrict" "--nodekey"
    "--nodekeyhex" "--discovery.port" "--discovery.dns"
    "--txlookuplimit" "--history.transactions" "--bootnodes"
    "--rpc.gascap" "--rpc.evmtimeout" "--rpc.txfeecap"
    "--rpc.batch-request-limit" "--rpc.batch-response-max-size"
    "--override.terminaltotaldifficulty" "--override.terminalblockhash"
    "--override.terminalblocknumber"
    "--miner.etherbase" "--etherbase" "--miner.gaslimit"
    "--miner.gasprice" "--unlock" "--password" "--metrics.addr"
    "--metrics.port" "--pprof.addr" "--pprof.port" "--txpool.locals"
    "--txpool.journal" "--txpool.rejournal"
    "--txpool.accountslots" "--txpool.globalslots"
    "--txpool.lifetime"
    "--txpool.blobpool.datacap" "--txpool.blobpool.pricebump"
    "--dev.period" "--dev.gaslimit"
    "--kzg-verifier-command" "--kzg.verifier-command"
    "--kzg-verifier-timeout" "--kzg.verifier-timeout"
    "--ready-file" "--log-file" "--pid-file"))

(defparameter *devnet-cli-optional-boolean-options*
  '("--http" "--ws" "--graphql" "--nodiscover" "--ipcdisable"
    "--allow-insecure-unlock" "--mine" "--metrics" "--pprof"
    "--snapshot" "--rpc.allow-unprotected-txs" "--txpool.nolocals"
    "--log.compress" "--override.terminaltotaldifficultypassed"
    "--mainnet" "--sepolia" "--holesky" "--hoodi" "--goerli"
    "--dev" "--nousb" "--json" "--no-serve"))

(defun devnet-cli-command-position (args command)
  (let ((args (devnet-cli-normalize-option-args args))
        (position 0))
    (loop while args
          for token = (pop args)
          do (cond
               ((devnet-cli-option-token-p token)
                (incf position)
                (cond
                  ((member token *devnet-cli-value-options* :test #'string=)
                   (when args
                     (pop args)
                     (incf position)))
                  ((member token
                           *devnet-cli-optional-boolean-options*
                           :test #'string=)
                   (when (and args
                              (not (devnet-cli-option-token-p (first args)))
                              (devnet-cli-boolean-token-p (first args)))
                     (pop args)
                     (incf position)))
                  (t
                   (when (and args
                              (not (devnet-cli-option-token-p (first args))))
                     (pop args)
                     (incf position)))))
               (t
                (return (and (string= token command) position))))
          finally (return nil))))

(defun devnet-cli-optional-boolean-value (args option)
  (if (and args
           (not (devnet-cli-option-token-p (first args))))
      (values (devnet-cli-parse-boolean-token (first args) option)
              (rest args))
      (values t args)))

(defun devnet-cli-consume-optional-boolean-value (args option)
  (multiple-value-bind (enabled-p rest)
      (devnet-cli-optional-boolean-value args option)
    (declare (ignore enabled-p))
    rest))

(defun devnet-cli-next-value (args option)
  (unless (and args
               (not (devnet-cli-option-token-p (first args))))
    (error "~A requires a value" option))
  (values (first args) (rest args)))

(defun devnet-cli-toml-strip-comment (line)
  (loop for index below (length line)
        for char = (char line index)
        with in-string-p = nil
        with escaped-p = nil
        do (cond
             (escaped-p
              (setf escaped-p nil))
             ((and in-string-p (char= char #\\))
              (setf escaped-p t))
             ((char= char #\")
              (setf in-string-p (not in-string-p)))
             ((and (not in-string-p) (char= char #\#))
              (return (subseq line 0 index))))
        finally (return line)))

(defun devnet-cli-toml-trim (value)
  (string-trim '(#\Space #\Tab #\Newline #\Return) value))

(defun devnet-cli-toml-parse-string-at (value start)
  (unless (and (< start (length value))
               (char= #\" (char value start)))
    (error "TOML string value must begin with a quote"))
  (let ((output (make-string-output-stream))
        (index (1+ start))
        (escaped-p nil))
    (loop while (< index (length value))
          for char = (char value index)
          do (cond
               (escaped-p
                (write-char
                 (case char
                   (#\" #\")
                   (#\\ #\\)
                   (#\/ #\/)
                   (#\b #\Backspace)
                   (#\t #\Tab)
                   (#\n #\Newline)
                   (#\f #\Page)
                   (#\r #\Return)
                   (t char))
                 output)
                (setf escaped-p nil))
               ((char= char #\\)
                (setf escaped-p t))
               ((char= char #\")
                (return (values (get-output-stream-string output)
                                (1+ index))))
               (t
                (write-char char output)))
          do (incf index)
          finally (error "Unterminated TOML string value"))))

(defun devnet-cli-toml-skip-space (value index)
  (loop while (and (< index (length value))
                   (member (char value index)
                           '(#\Space #\Tab #\Newline #\Return)))
        do (incf index)
        finally (return index)))

(defun devnet-cli-toml-parse-string-array (value)
  (let* ((value (devnet-cli-toml-trim value))
         (length (length value)))
    (unless (and (<= 2 length)
                 (char= #\[ (char value 0))
                 (char= #\] (char value (1- length))))
      (error "TOML array value must be bracketed"))
    (let ((index (devnet-cli-toml-skip-space value 1))
          (items nil))
      (loop
        (setf index (devnet-cli-toml-skip-space value index))
        (when (>= index (1- length))
          (return (nreverse items)))
        (multiple-value-bind (item next-index)
            (devnet-cli-toml-parse-string-at value index)
          (push item items)
          (setf index (devnet-cli-toml-skip-space value next-index))
          (cond
            ((and (< index (1- length))
                  (char= #\, (char value index)))
             (incf index))
            ((= index (1- length))
             (return (nreverse items)))
            (t
             (error "TOML string arrays must contain comma-separated strings"))))))))

(defun devnet-cli-toml-parse-value (value)
  (let ((value (devnet-cli-toml-trim value)))
    (cond
      ((zerop (length value))
       "")
      ((char= #\" (char value 0))
       (multiple-value-bind (parsed next-index)
           (devnet-cli-toml-parse-string-at value 0)
         (unless (zerop (length (devnet-cli-toml-trim
                                 (subseq value next-index))))
           (error "Unexpected text after TOML string value"))
         parsed))
      ((char= #\[ (char value 0))
       (devnet-cli-toml-parse-string-array value))
      (t
       value))))

(defun devnet-cli-config-list-string (value)
  (cond
    ((null value) nil)
    ((and (listp value)
          (every #'stringp value))
     (format nil "~{~A~^,~}" value))
    ((stringp value) value)
    (t nil)))

(defun devnet-cli-config-scalar-string (value)
  (cond
    ((stringp value) value)
    ((integerp value) (write-to-string value))
    (t nil)))

(defun devnet-cli-config-option-args (section key value)
  (let ((scalar (devnet-cli-config-scalar-string value))
        (list-value (devnet-cli-config-list-string value)))
    (labels ((non-empty-scalar ()
               (and scalar (plusp (length scalar)) scalar))
             (non-empty-list ()
               (and list-value (plusp (length list-value)) list-value)))
      (cond
        ((and (string= section "Node") (string= key "DataDir")
              (non-empty-scalar))
         (list "--datadir" scalar))
        ((and (string= section "Node") (string= key "HTTPHost")
              scalar)
         (if (plusp (length scalar))
             (list "--http.addr" scalar)
             (list "--http" "false")))
        ((and (string= section "Node") (string= key "HTTPPort")
              (non-empty-scalar))
         (list "--http.port" scalar))
        ((and (string= section "Node") (string= key "HTTPModules")
              (non-empty-list))
         (list "--http.api" list-value))
        ((and (string= section "Node") (string= key "HTTPCors")
              (non-empty-list))
         (list "--http.corsdomain" list-value))
        ((and (string= section "Node") (string= key "HTTPVirtualHosts")
              (non-empty-list))
         (list "--http.vhosts" list-value))
        ((and (string= section "Node") (string= key "HTTPPathPrefix")
              (non-empty-scalar))
         (list "--http.rpcprefix" scalar))
        ((and (string= section "Node") (string= key "AuthAddr")
              (non-empty-scalar))
         (list "--authrpc.addr" scalar))
        ((and (string= section "Node") (string= key "AuthPort")
              (non-empty-scalar))
         (list "--authrpc.port" scalar))
        ((and (string= section "Node") (string= key "AuthVirtualHosts")
              (non-empty-list))
         (list "--authrpc.vhosts" list-value))
        ((and (string= section "Node") (string= key "JWTSecret")
              (non-empty-scalar))
         (list "--authrpc.jwtsecret" scalar))
        ((and (string= section "Eth") (string= key "NetworkId")
              (non-empty-scalar))
         (list "--networkid" scalar))
        ((and (string= section "Eth.TxPool") (string= key "PriceLimit")
              (non-empty-scalar))
         (list "--txpool.pricelimit" scalar))
        ((and (string= section "Eth.TxPool") (string= key "PriceBump")
              (non-empty-scalar))
         (list "--txpool.pricebump" scalar))
        ((and (string= section "Eth.TxPool") (string= key "AccountSlots")
              (non-empty-scalar))
         (list "--txpool.accountslots" scalar))
        ((and (string= section "Eth.TxPool") (string= key "GlobalSlots")
              (non-empty-scalar))
         (list "--txpool.globalslots" scalar))
        ((and (string= section "Eth.TxPool") (string= key "AccountQueue")
              (non-empty-scalar))
         (list "--txpool.accountqueue" scalar))
        ((and (string= section "Eth.TxPool") (string= key "GlobalQueue")
              (non-empty-scalar))
         (list "--txpool.globalqueue" scalar))
        ((and (string= section "Eth.TxPool") (string= key "Locals")
              (non-empty-list))
         (list "--txpool.locals" list-value))
        ((and (string= section "Eth.TxPool") (string= key "NoLocals")
              (non-empty-scalar))
         (list "--txpool.nolocals" scalar))
        ((and (string= section "Eth.Miner") (string= key "GasCeil")
              (non-empty-scalar))
         (list "--miner.gaslimit" scalar))
        (t nil)))))

(defun devnet-cli-read-config-args (path)
  (let ((config-path (probe-file path)))
    (unless config-path
      (error "--config requires a readable TOML file: ~A" path))
    (with-open-file (stream config-path :direction :input)
      (loop for raw-line = (read-line stream nil nil)
            while raw-line
            with section = ""
            append
            (let ((line (devnet-cli-toml-trim
                         (devnet-cli-toml-strip-comment raw-line))))
              (cond
                ((zerop (length line))
                 nil)
                ((and (char= #\[ (char line 0))
                      (char= #\] (char line (1- (length line)))))
                 (setf section
                       (devnet-cli-toml-trim
                        (subseq line 1 (1- (length line)))))
                 nil)
                (t
                 (let ((separator (position #\= line)))
                   (unless separator
                     (error "Malformed TOML config line in ~A: ~A"
                            path
                            raw-line))
                   (let ((key (devnet-cli-toml-trim
                               (subseq line 0 separator)))
                         (value (devnet-cli-toml-parse-value
                                 (subseq line (1+ separator)))))
                     (devnet-cli-config-option-args
                      section
                      key
                      value))))))))))

(defun devnet-cli-config-paths (args)
  (let ((args (devnet-cli-normalize-option-args args))
        (paths nil))
    (loop while args
          for option = (pop args)
          do (cond
               ((string= option "--config")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (push value paths)
                  (setf args rest)))
               ((member option *devnet-cli-value-options* :test #'string=)
                (when (and args
                           (not (devnet-cli-option-token-p (first args))))
                  (pop args)))
               ((member option *devnet-cli-optional-boolean-options*
                        :test #'string=)
                (when (and args
                           (not (devnet-cli-option-token-p (first args)))
                           (devnet-cli-boolean-token-p (first args)))
                  (pop args)))))
    (nreverse paths)))

(defun devnet-cli-config-args (args)
  (loop for path in (devnet-cli-config-paths args)
        append (devnet-cli-read-config-args path)))

(defun devnet-cli-apply-config-args (args)
  (append (devnet-cli-config-args args) args))

(defun devnet-cli-parse-integer (value option)
  (handler-case
      (parse-integer value :junk-allowed nil)
    (error ()
      (error "~A requires an integer value" option))))

(defun devnet-cli-parse-port (value option)
  (let ((port (devnet-cli-parse-integer value option)))
    (unless (<= 0 port 65535)
      (error "~A must be between 0 and 65535" option))
    port))

(defun devnet-cli-parse-non-negative-integer (value option)
  (let ((integer (devnet-cli-parse-integer value option)))
    (when (minusp integer)
      (error "~A must be non-negative" option))
    integer))

(defun devnet-cli-parse-positive-integer (value option)
  (let ((integer (devnet-cli-parse-integer value option)))
    (unless (plusp integer)
      (error "~A must be positive" option))
    integer))

(defun devnet-cli-hex-quantity-token-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (char= #\0 (char value 0))
       (char= #\x (char-downcase (char value 1)))))

(defun devnet-cli-parse-non-negative-quantity (value option)
  (let ((quantity
          (handler-case
              (if (devnet-cli-hex-quantity-token-p value)
                  (hex-to-quantity value)
                  (parse-integer value :junk-allowed nil))
            (error ()
              (error "~A requires a non-negative integer or hex quantity"
                     option)))))
    (when (minusp quantity)
      (error "~A must be non-negative" option))
    quantity))

(defun devnet-cli-parse-uint64-quantity (value option)
  (let ((quantity (devnet-cli-parse-non-negative-quantity value option)))
    (unless (< quantity (expt 2 64))
      (error "~A must be less than 2^64" option))
    quantity))

(defun devnet-cli-parse-hash32 (value option)
  (handler-case
      (hash32-from-hex value)
    (error ()
      (error "~A requires a 32-byte hex hash" option))))

(defun devnet-cli-parse-address (value option)
  (handler-case
      (address-from-hex value)
    (error ()
      (error "~A requires a 20-byte hex address" option))))

(defun devnet-cli-parse-address-list (value option)
  (let ((addresses
          (loop for raw in (uiop:split-string value :separator ",")
                for token = (string-trim
                             '(#\Space #\Tab #\Newline #\Return)
                             raw)
                unless (zerop (length token))
                  collect (devnet-cli-parse-address token option))))
    (unless addresses
      (error "~A requires at least one 20-byte hex address" option))
    addresses))

(defun devnet-cli-parse-http-api-list (value option)
  (let ((modules
          (loop for raw in (uiop:split-string value :separator ",")
                for module = (string-downcase
                              (string-trim '(#\Space #\Tab #\Newline #\Return)
                                           raw))
                unless (zerop (length module))
                  collect module)))
    (unless modules
      (error "~A requires at least one API module" option))
    modules))

(defun devnet-cli-parse-cors-origin-list (value)
  (loop for raw in (uiop:split-string value :separator ",")
        for origin = (string-trim '(#\Space #\Tab #\Newline #\Return) raw)
        unless (zerop (length origin))
          collect origin))

(defun devnet-cli-parse-vhost-list (value)
  (loop for raw in (uiop:split-string value :separator ",")
        for host = (string-trim '(#\Space #\Tab #\Newline #\Return) raw)
        unless (zerop (length host))
          collect host))

(defun devnet-cli-parse-rpc-prefix (value option)
  (unless (and (stringp value)
               (plusp (length value))
               (char= #\/ (char value 0)))
    (error "~A requires a path beginning with /" option))
  value)

(defun devnet-cli-rpc-method-module (method)
  (let ((separator (and (stringp method) (position #\_ method))))
    (and separator
         (subseq method 0 separator))))

(defun devnet-cli-public-api-method-filter (modules)
  (if (null modules)
      #'engine-rpc-public-method-p
      (let ((modules (copy-list modules)))
        (lambda (method)
          (and (engine-rpc-public-method-p method)
               (or (string= method "rpc_modules")
                   (let ((module (devnet-cli-rpc-method-module method)))
                     (and module
                          (member module modules :test #'string=)))))))))

(defun devnet-cli-options (args)
  (setf args (devnet-cli-remove-command-token args "devnet"))
  (setf args (devnet-cli-normalize-option-args args))
  (setf args (devnet-cli-apply-config-args args))
  (let ((genesis-path nil)
        (host "127.0.0.1")
        (port +engine-rpc-default-http-port+)
        (default-public-host "127.0.0.1")
        (public-host nil)
        (public-port +devnet-default-public-rpc-port+)
        (jwt-secret-path nil)
        (engine-rpc-prefix "/")
        (public-rpc-prefix "/")
        (database-path nil)
        (datadir-path nil)
        (network-id nil)
        (http-api-modules nil)
        (authrpc-cors-origins nil)
        (http-cors-origins nil)
        (engine-vhosts nil)
        (http-vhosts nil)
        (public-rpc-enabled-p t)
        (state-prune-before nil)
        (max-connections nil)
        (terminal-total-difficulty nil)
        (terminal-total-difficulty-passed nil)
        (terminal-total-difficulty-passed-specified-p nil)
        (terminal-block-hash nil)
        (terminal-block-number nil)
        (dev-mode-p nil)
        (dev-gas-limit nil)
        (miner-gas-limit nil)
        (coinbase (zero-address))
        (allow-unprotected-transactions-p nil)
        (txpool-price-limit nil)
        (txpool-price-bump-percent nil)
        (txpool-account-slot-limit nil)
        (txpool-global-slot-limit nil)
        (txpool-account-queue-limit nil)
        (txpool-global-queue-limit nil)
        (txpool-local-addresses nil)
        (txpool-no-local-exemptions-p nil)
        (serve-p t)
        (summary-format :sexp)
        (ready-file nil)
        (log-file nil)
        (pid-file nil)
        (kzg-verifier-command nil)
        (kzg-verifier-timeout-seconds nil)
        (help-p nil))
    (loop while args
          for option = (pop args)
          do (cond
               ((string= option "--help")
                (setf help-p t))
               ((string= option "--genesis")
                (multiple-value-setq (genesis-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--host")
                (multiple-value-setq (host args)
                  (devnet-cli-next-value args option))
                (setf default-public-host host))
               ((or (string= option "--engine-host")
                    (string= option "--authrpc.addr"))
                (multiple-value-setq (host args)
                  (devnet-cli-next-value args option)))
               ((string= option "--port")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (devnet-cli-parse-port value option)
                  (setf args rest)))
               ((or (string= option "--engine-port")
                    (string= option "--authrpc.port"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf port (devnet-cli-parse-port value option)
                        args rest)))
               ((or (string= option "--public-host")
                    (string= option "--http.addr"))
                (multiple-value-setq (public-host args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--public-port")
                    (string= option "--http.port"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf public-port (devnet-cli-parse-port value option)
                        args rest)))
               ((or (string= option "--jwt-secret")
                    (string= option "--authrpc.jwtsecret"))
                (multiple-value-setq (jwt-secret-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--authrpc.rpcprefix")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf engine-rpc-prefix
                        (devnet-cli-parse-rpc-prefix value option)
                        args rest)))
               ((string= option "--http.rpcprefix")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf public-rpc-prefix
                        (devnet-cli-parse-rpc-prefix value option)
                        args rest)))
               ((string= option "--database")
                (multiple-value-setq (database-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--datadir")
                (multiple-value-setq (datadir-path args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--networkid")
                    (string= option "--network-id"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf network-id
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--prune-state-before")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf state-prune-before
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--max-connections")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf max-connections
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--override.terminaltotaldifficulty")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf terminal-total-difficulty
                        (devnet-cli-parse-non-negative-quantity value option)
                        args rest)))
               ((string= option "--override.terminaltotaldifficultypassed")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf terminal-total-difficulty-passed enabled-p
                        terminal-total-difficulty-passed-specified-p t
                        args rest)))
               ((string= option "--override.terminalblockhash")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf terminal-block-hash
                        (devnet-cli-parse-hash32 value option)
                        args rest)))
               ((string= option "--override.terminalblocknumber")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf terminal-block-number
                        (devnet-cli-parse-non-negative-quantity value option)
                        args rest)))
               ((string= option "--http")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf public-rpc-enabled-p enabled-p
                        args rest)))
               ((string= option "--http.api")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf http-api-modules
                        (devnet-cli-parse-http-api-list value option))
                  (setf args rest)))
               ((string= option "--http.corsdomain")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf http-cors-origins
                        (devnet-cli-parse-cors-origin-list value)
                        args rest)))
               ((string= option "--authrpc.corsdomain")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf authrpc-cors-origins
                        (devnet-cli-parse-cors-origin-list value)
                        args rest)))
               ((string= option "--authrpc.vhosts")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf engine-vhosts
                        (devnet-cli-parse-vhost-list value)
                        args rest)))
               ((string= option "--http.vhosts")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf http-vhosts
                        (devnet-cli-parse-vhost-list value)
                        args rest)))
               ((string= option "--ready-file")
                (multiple-value-setq (ready-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--log-file")
                (multiple-value-setq (log-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--pid-file")
                (multiple-value-setq (pid-file args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--kzg-verifier-command")
                    (string= option "--kzg.verifier-command"))
                (multiple-value-setq (kzg-verifier-command args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--kzg-verifier-timeout")
                    (string= option "--kzg.verifier-timeout"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf kzg-verifier-timeout-seconds
                        (devnet-cli-parse-positive-integer value option)
                        args rest)))
               ((string= option "--no-serve")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (when enabled-p
                    (setf serve-p nil))
                  (setf args rest)))
               ((string= option "--json")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (when enabled-p
                    (setf summary-format :json))
                  (setf args rest)))
               ((string= option "--dev")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf dev-mode-p enabled-p
                        args rest)))
               ((string= option "--dev.gaslimit")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf dev-gas-limit
                        (devnet-cli-parse-uint64-quantity value option)
                        args rest)))
               ((string= option "--miner.gaslimit")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf miner-gas-limit
                        (devnet-cli-parse-uint64-quantity value option)
                        args rest)))
               ((or (string= option "--miner.etherbase")
                    (string= option "--etherbase"))
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf coinbase (devnet-cli-parse-address value option)
                        args rest)))
               ((string= option "--rpc.allow-unprotected-txs")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf allow-unprotected-transactions-p enabled-p
                        args rest)))
               ((string= option "--txpool.locals")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-local-addresses
                        (devnet-cli-parse-address-list value option)
                        args rest)))
               ((string= option "--txpool.nolocals")
                (multiple-value-bind (enabled-p rest)
                    (devnet-cli-optional-boolean-value args option)
                  (setf txpool-no-local-exemptions-p enabled-p
                        args rest)))
               ((string= option "--txpool.pricelimit")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-price-limit
                        (devnet-cli-parse-non-negative-quantity value option)
                        args rest)))
               ((string= option "--txpool.pricebump")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-price-bump-percent
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--txpool.accountslots")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-account-slot-limit
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--txpool.globalslots")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-global-slot-limit
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--txpool.accountqueue")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-account-queue-limit
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((string= option "--txpool.globalqueue")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-global-queue-limit
                        (devnet-cli-parse-non-negative-integer value option)
                        args rest)))
               ((member option *devnet-cli-value-options* :test #'string=)
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (declare (ignore value))
                  (setf args rest)))
               ((member option *devnet-cli-optional-boolean-options*
                        :test #'string=)
                (setf args
                      (devnet-cli-consume-optional-boolean-value
                       args option)))
               (t
                (error "Unknown option ~A" option))))
    (list :genesis-path genesis-path
          :host host
          :port port
          :public-host (or public-host default-public-host)
          :public-port public-port
          :jwt-secret-path (or jwt-secret-path
                               (and datadir-path
                                    (devnet-cli-existing-datadir-jwt-secret-path
                                     datadir-path)))
          :engine-rpc-prefix engine-rpc-prefix
          :public-rpc-prefix public-rpc-prefix
          :datadir-path datadir-path
          :database-path (or database-path
                             (and datadir-path
                                  (devnet-cli-datadir-database-path
                                   datadir-path)))
          :network-id network-id
          :http-api-modules http-api-modules
          :authrpc-cors-origins authrpc-cors-origins
          :http-cors-origins http-cors-origins
          :engine-vhosts engine-vhosts
          :http-vhosts http-vhosts
          :public-rpc-enabled-p public-rpc-enabled-p
          :terminal-total-difficulty terminal-total-difficulty
          :terminal-total-difficulty-passed terminal-total-difficulty-passed
          :terminal-total-difficulty-passed-specified-p
          terminal-total-difficulty-passed-specified-p
          :terminal-block-hash terminal-block-hash
          :terminal-block-number terminal-block-number
          :dev-mode-p dev-mode-p
          :dev-gas-limit dev-gas-limit
          :miner-gas-limit miner-gas-limit
          :coinbase coinbase
          :allow-unprotected-transactions-p allow-unprotected-transactions-p
          :txpool-price-limit txpool-price-limit
          :txpool-price-bump-percent txpool-price-bump-percent
          :txpool-account-slot-limit txpool-account-slot-limit
          :txpool-global-slot-limit txpool-global-slot-limit
          :txpool-account-queue-limit txpool-account-queue-limit
          :txpool-global-queue-limit txpool-global-queue-limit
          :txpool-local-addresses txpool-local-addresses
          :txpool-no-local-exemptions-p txpool-no-local-exemptions-p
          :state-prune-before state-prune-before
          :max-connections max-connections
          :serve-p serve-p
          :summary-format summary-format
          :ready-file ready-file
          :log-file log-file
          :pid-file pid-file
          :kzg-verifier-command kzg-verifier-command
          :kzg-verifier-timeout-seconds kzg-verifier-timeout-seconds
          :help-p help-p)))

(defun devnet-cli-remove-command-token (args command)
  (let* ((args (devnet-cli-normalize-option-args args))
         (position (devnet-cli-command-position args command)))
    (if position
        (loop for arg in args
              for index from 0
              unless (= index position)
                collect arg)
        args)))

(defun devnet-cli-init-command-p (args)
  (devnet-cli-command-position args "init"))

(defun devnet-cli-reject-malformed-init-json-assignment (args)
  (dolist (arg args)
    (let ((separator
            (and (devnet-cli-option-token-p arg)
                 (position #\= arg :start 2))))
      (when (and separator
                 (string= "--json" arg :end2 separator))
        (let ((value (subseq arg (1+ separator))))
          (unless (devnet-cli-boolean-token-p value)
            (devnet-cli-parse-boolean-token value "--json")))))))

(defun devnet-cli-init-options (args)
  (devnet-cli-reject-malformed-init-json-assignment args)
  (setf args (devnet-cli-remove-command-token args "init"))
  (setf args (devnet-cli-normalize-option-args args))
  (setf args (devnet-cli-apply-config-args args))
  (let ((genesis-path nil)
        (database-path nil)
        (datadir-path nil)
        (jwt-secret-path nil)
        (ready-file nil)
        (log-file nil)
        (pid-file nil)
        (summary-format :sexp)
        (help-p nil))
    (loop while args
          for option = (pop args)
          do (cond
               ((string= option "--help")
                (setf help-p t))
               ((string= option "--genesis")
                (multiple-value-setq (genesis-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--database")
                (multiple-value-setq (database-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--datadir")
                (multiple-value-setq (datadir-path args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--jwt-secret")
                    (string= option "--authrpc.jwtsecret"))
                (multiple-value-setq (jwt-secret-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--ready-file")
                (multiple-value-setq (ready-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--log-file")
                (multiple-value-setq (log-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--pid-file")
                (multiple-value-setq (pid-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--json")
                (setf summary-format :json)
                (when (and args
                           (not (devnet-cli-option-token-p (first args)))
                           (devnet-cli-boolean-token-p (first args)))
                  (let ((enabled-p
                          (devnet-cli-parse-boolean-token
                           (first args)
                           option)))
                    (setf summary-format (if enabled-p :json :sexp)))
                  (setf args (rest args))))
               ((member option *devnet-cli-value-options* :test #'string=)
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (declare (ignore value))
                  (setf args rest)))
               ((member option *devnet-cli-optional-boolean-options*
                        :test #'string=)
                (setf args
                      (devnet-cli-consume-optional-boolean-value
                       args
                       option)))
               ((devnet-cli-option-token-p option)
                (error "Unknown option ~A" option))
               ((null genesis-path)
                (setf genesis-path option))
               (t
                (error "Unexpected init argument ~A" option))))
    (list :genesis-path genesis-path
          :datadir-path datadir-path
          :database-path (or database-path
                             (and datadir-path
                                  (devnet-cli-datadir-database-path
                                   datadir-path)))
          :jwt-secret-path jwt-secret-path
          :ready-file ready-file
          :log-file log-file
          :pid-file pid-file
          :summary-format summary-format
          :help-p help-p)))

(defun devnet-cli-resolve-genesis-path (options)
  (or (getf options :genesis-path)
      (let ((datadir-path (getf options :datadir-path)))
        (when datadir-path
          (let ((stored-genesis
                  (devnet-cli-datadir-genesis-path datadir-path)))
            (and (probe-file stored-genesis)
                 (namestring (truename stored-genesis))))))))

(defun devnet-cli-resolve-genesis-json (options genesis-path)
  (when (and (getf options :dev-mode-p)
             (null genesis-path))
    (devnet-cli-dev-genesis-json
     :gas-limit (or (getf options :dev-gas-limit)
                    (getf options :miner-gas-limit)
                    +devnet-default-dev-gas-limit+)
     :coinbase (getf options :coinbase))))

(defun devnet-cli-print-init-usage (stream)
  (format stream
          "Usage: ethereum-lisp init --datadir PATH [--database PATH] [runner options] [--json] GENESIS~%"))

(defun devnet-cli-run-init (options output-stream)
  (let ((genesis-path (getf options :genesis-path))
        (datadir-path (getf options :datadir-path))
        (database-path (getf options :database-path))
        (explicit-jwt-secret-path (getf options :jwt-secret-path))
        (jwt-secret-path nil))
    (unless genesis-path
      (error "init requires a genesis file"))
    (unless database-path
      (error "init requires --datadir or --database"))
    (when datadir-path
      (devnet-cli-copy-file-string
       genesis-path
       (devnet-cli-datadir-genesis-path datadir-path))
      (setf jwt-secret-path
            (devnet-cli-ensure-datadir-jwt-secret
             datadir-path
             :source-path explicit-jwt-secret-path)))
    (call-with-devnet-cli-telemetry-sink
     options
     output-stream
     (lambda (telemetry-sink)
       (let ((node
               (make-devnet-node
                :genesis-path genesis-path
                :database-path database-path
                :jwt-secret-path jwt-secret-path
                :log-path (getf options :log-file)
                :pid-file-path (getf options :pid-file)
                :telemetry-sink telemetry-sink)))
         (when (getf options :pid-file)
           (devnet-cli-write-pid-file (getf options :pid-file)))
         (devnet-node-export-database node)
         (when (getf options :ready-file)
           (devnet-cli-write-ready-file
            node
            (getf options :ready-file)))
         (when (getf options :log-file)
           (devnet-cli-log-event node "init.ready"))
         (devnet-cli-print-summary
          node
          output-stream
          :format (getf options :summary-format))
         (when (getf options :log-file)
           (devnet-cli-log-event node "init.shutdown")))))))

(defun devnet-cli-print-usage (stream)
  (format stream
          "Usage: ethereum-lisp devnet [--config PATH] [--genesis PATH] [--engine-host HOST|--authrpc.addr HOST] [--engine-port PORT|--authrpc.port PORT] [--host HOST] [--port P2P-PORT] [--public-host HOST|--http.addr HOST] [--public-port PORT|--http.port PORT] [--jwt-secret PATH|--authrpc.jwtsecret PATH] [--authrpc.rpcprefix PATH] [--authrpc.vhosts HOSTS] [--authrpc.corsdomain DOMAINS] [--http] [--http.api LIST] [--http.rpcprefix PATH] [--http.vhosts HOSTS] [--http.corsdomain DOMAINS] [--http.maxclients N] [--http.readtimeout DURATION] [--http.writetimeout DURATION] [--http.idletimeout DURATION] [--ws] [--ws.addr HOST] [--ws.port PORT] [--ws.api LIST] [--ws.origins ORIGINS] [--ws.rpcprefix PATH] [--graphql] [--graphql.addr HOST] [--graphql.port PORT] [--graphql.vhosts HOSTS] [--graphql.corsdomain DOMAINS] [--networkid ID|--network-id ID] [--mainnet] [--sepolia] [--holesky] [--hoodi] [--goerli] [--syncmode MODE] [--nodiscover] [--ipcdisable] [--ipcpath PATH] [--ipcapi LIST] [--verbosity LEVEL] [--log.file PATH] [--log.format FORMAT] [--log.maxsize MB] [--log.maxbackups N] [--log.maxage DAYS] [--log.compress] [--maxpeers N] [--nat MODE] [--netrestrict CIDRS] [--identity NAME] [--nodekey PATH] [--nodekeyhex HEX] [--discovery.port PORT] [--discovery.dns URL] [--gcmode MODE] [--state.scheme SCHEME] [--db.engine ENGINE] [--datadir.ancient PATH] [--cache MB] [--cache.database MB] [--cache.gc MB] [--cache.trie MB] [--txlookuplimit N] [--history.transactions N] [--bootnodes URLS] [--rpc.gascap GAS] [--rpc.evmtimeout DURATION] [--rpc.txfeecap ETH] [--rpc.batch-request-limit N] [--rpc.batch-response-max-size BYTES] [--override.terminaltotaldifficulty TTD] [--override.terminaltotaldifficultypassed] [--override.terminalblockhash HASH] [--override.terminalblocknumber NUMBER] [--mine] [--miner.etherbase ADDRESS] [--etherbase ADDRESS] [--miner.gaslimit N] [--miner.gasprice WEI] [--unlock ACCOUNTS] [--password PATH] [--allow-insecure-unlock] [--rpc.allow-unprotected-txs] [--txpool.locals ACCOUNTS] [--txpool.nolocals] [--txpool.journal PATH] [--txpool.rejournal DURATION] [--txpool.pricelimit N] [--txpool.pricebump N] [--txpool.accountslots N] [--txpool.globalslots N] [--txpool.accountqueue N] [--txpool.globalqueue N] [--txpool.lifetime DURATION] [--txpool.blobpool.datacap BYTES] [--txpool.blobpool.pricebump N] [--dev] [--dev.period SECONDS] [--dev.gaslimit GAS] [--nousb] [--metrics] [--metrics.addr HOST] [--metrics.port PORT] [--pprof] [--pprof.addr HOST] [--pprof.port PORT] [--snapshot] [--database PATH] [--datadir PATH] [--prune-state-before NUMBER] [--max-connections N] [--kzg-verifier-command PATH|--kzg.verifier-command PATH] [--kzg-verifier-timeout SECONDS|--kzg.verifier-timeout SECONDS] [--json] [--ready-file PATH] [--log-file PATH] [--pid-file PATH] [--no-serve]~%"))

(defun devnet-cli-print-top-level-help (stream)
  (format stream "Usage: ethereum-lisp COMMAND [options]~%")
  (format stream "~%")
  (format stream "Commands:~%")
  (format stream "  init        Initialize a datadir from a genesis file.~%")
  (format stream "  devnet      Run a local Engine/public JSON-RPC devnet node.~%")
  (format stream "  help        Print this help.~%")
  (format stream "  version     Print the local client version.~%")
  (format stream "~%")
  (format stream "Use `ethereum-lisp init --help` or `ethereum-lisp devnet --help` for command options.~%"))

(defun devnet-cli-version-string ()
  (let ((version (engine-rpc-client-version)))
    (format nil "~A/~A/~A"
            (cdr (assoc "name" version :test #'string=))
            (cdr (assoc "version" version :test #'string=))
            (cdr (assoc "commit" version :test #'string=)))))

(defun devnet-cli-print-version (stream)
  (format stream "~A~%" (devnet-cli-version-string)))

(defun devnet-cli-top-level-help-p (args)
  (or (null args)
      (and (= 1 (length args))
           (member (first args) '("help" "--help" "-h")
                   :test #'string=))))

(defun devnet-cli-top-level-version-p (args)
  (and (= 1 (length args))
       (member (first args) '("version" "--version" "-v")
               :test #'string=)))

(defun devnet-cli-print-summary
    (node stream &key (format :sexp) engine-endpoint rpc-endpoint
            (public-rpc-enabled-p t))
  (ecase format
    (:sexp
     (write (devnet-node-summary
             node
             :engine-endpoint engine-endpoint
             :rpc-endpoint rpc-endpoint
             :public-rpc-enabled-p public-rpc-enabled-p)
            :stream stream :pretty nil))
    (:json
     (write-string
      (json-encode
       (devnet-node-summary-json-object
        node
        :engine-endpoint engine-endpoint
        :rpc-endpoint rpc-endpoint
        :public-rpc-enabled-p public-rpc-enabled-p))
      stream)))
  (terpri stream))

(defun devnet-cli-ready-temp-path (path)
  (let* ((pathname (pathname path))
         (name (or (pathname-name pathname) "ready"))
         (type (or (pathname-type pathname) "json")))
    (make-pathname
     :name (format nil ".~A.~A" name (symbol-name (gensym "TMP")))
     :type type
     :defaults pathname)))

(defun devnet-cli-ensure-path-parent-directory (path)
  (ensure-directories-exist (pathname path))
  path)

(defun devnet-cli-write-ready-file
    (node path &key engine-endpoint rpc-endpoint (public-rpc-enabled-p t))
  (devnet-cli-ensure-path-parent-directory path)
  (let ((temp-path (devnet-cli-ready-temp-path path))
        (renamed-p nil))
    (unwind-protect
         (progn
           (with-open-file (stream temp-path
                                   :direction :output
                                   :if-exists :error
                                   :if-does-not-exist :create)
             (write-string
              (json-encode
               (devnet-node-summary-json-object
                node
                :engine-endpoint engine-endpoint
                :rpc-endpoint rpc-endpoint
                :public-rpc-enabled-p public-rpc-enabled-p))
              stream)
             (terpri stream))
           (uiop:rename-file-overwriting-target temp-path path)
           (setf renamed-p t)
           path)
      (unless renamed-p
        (when (probe-file temp-path)
          (ignore-errors (delete-file temp-path)))))))

(defun devnet-cli-write-pid-file (path)
  (let ((process-id (devnet-process-id)))
    (unless process-id
      (error "Process id is not available on this Lisp implementation"))
    (devnet-cli-ensure-path-parent-directory path)
    (let ((temp-path (devnet-cli-ready-temp-path path))
          (renamed-p nil))
      (unwind-protect
           (progn
             (with-open-file (stream temp-path
                                     :direction :output
                                     :if-exists :error
                                     :if-does-not-exist :create)
               (format stream "~D~%" process-id))
             (uiop:rename-file-overwriting-target temp-path path)
             (setf renamed-p t)
             path)
        (unless renamed-p
          (when (probe-file temp-path)
            (ignore-errors (delete-file temp-path))))))))

(defun devnet-node-telemetry-fields
    (node &key engine-endpoint rpc-endpoint lifecycle-phase
            connection-summary (public-rpc-enabled-p t))
  (let ((summary (devnet-node-summary
                  node
                  :engine-endpoint engine-endpoint
                  :rpc-endpoint rpc-endpoint
                  :public-rpc-enabled-p public-rpc-enabled-p)))
    `(("engineEndpoint" . ,(getf summary :engine-endpoint))
      ("rpcEndpoint" . ,(or (getf summary :rpc-endpoint) ""))
      ("publicRpcEnabled" . ,(if (getf summary :public-rpc-enabled-p)
                                 "true"
                                 "false"))
      ("lifecyclePhase" . ,(or lifecycle-phase ""))
      ("engineConnections" . ,(write-to-string
                               (or (getf connection-summary
                                         :engine-connections)
                                   0)))
      ("publicConnections" . ,(write-to-string
                               (or (getf connection-summary
                                         :public-connections)
                                   0)))
      ("totalConnections" . ,(write-to-string
                              (or (getf connection-summary
                                        :total-connections)
                                  0)))
      ("processId" . ,(let ((process-id (getf summary :process-id)))
                         (if process-id
                             (write-to-string process-id)
                             "")))
      ("chainId" . ,(quantity-to-hex (getf summary :chain-id)))
      ("headNumber" . ,(quantity-to-hex (getf summary :head-number)))
      ("headHash" . ,(getf summary :head-hash))
      ("coinbase" . ,(getf summary :coinbase))
      ("allowUnprotectedTransactions" .
       ,(if (getf summary :allow-unprotected-transactions-p)
            "true"
            "false"))
      ("txpoolPriceLimit" .
       ,(if (getf summary :txpool-price-limit)
            (quantity-to-hex (getf summary :txpool-price-limit))
            ""))
      ("txpoolPriceBump" .
       ,(if (getf summary :txpool-price-bump-percent)
            (write-to-string (getf summary :txpool-price-bump-percent))
            ""))
      ("txpoolAccountSlots" .
       ,(if (getf summary :txpool-account-slot-limit)
            (write-to-string (getf summary :txpool-account-slot-limit))
            ""))
      ("txpoolGlobalSlots" .
       ,(if (getf summary :txpool-global-slot-limit)
            (write-to-string (getf summary :txpool-global-slot-limit))
            ""))
      ("txpoolAccountQueue" .
       ,(if (getf summary :txpool-account-queue-limit)
            (write-to-string (getf summary :txpool-account-queue-limit))
            ""))
      ("txpoolGlobalQueue" .
       ,(if (getf summary :txpool-global-queue-limit)
            (write-to-string (getf summary :txpool-global-queue-limit))
            ""))
      ("txpoolLocals" .
       ,(format nil "~{~A~^,~}" (getf summary :txpool-local-addresses)))
      ("txpoolNoLocals" .
       ,(if (getf summary :txpool-no-local-exemptions-p) "true" "false"))
      ("headGasLimit" . ,(if (getf summary :head-gas-limit)
                              (quantity-to-hex
                               (getf summary :head-gas-limit))
                              ""))
      ("safeNumber" . ,(if (getf summary :safe-number)
                            (quantity-to-hex (getf summary :safe-number))
                            ""))
      ("safeHash" . ,(or (getf summary :safe-hash) ""))
      ("finalizedNumber" . ,(if (getf summary :finalized-number)
                                 (quantity-to-hex
                                  (getf summary :finalized-number))
                                 ""))
      ("finalizedHash" . ,(or (getf summary :finalized-hash) ""))
      ("stateAvailable" . ,(if (getf summary :state-available-p)
                                "true"
                                "false"))
      ("authRequired" . ,(if (getf summary :auth-required-p) "true" "false"))
      ("jwtSecretPath" . ,(or (getf summary :jwt-secret-path) ""))
      ("engineRpcPrefix" . ,(getf summary :engine-rpc-prefix))
      ("publicRpcPrefix" . ,(getf summary :public-rpc-prefix))
      ("logPath" . ,(or (getf summary :log-path) ""))
      ("databasePath" . ,(or (getf summary :database-path) ""))
      ("networkId" . ,(quantity-to-hex (getf summary :network-id)))
      ("publicApiModules" .
       ,(if (getf summary :public-api-modules)
            (format nil "~{~A~^,~}" (getf summary :public-api-modules))
            ""))
      ("engineCorsOrigins" .
       ,(if (getf summary :engine-cors-origins)
            (format nil "~{~A~^,~}" (getf summary :engine-cors-origins))
            ""))
      ("publicCorsOrigins" .
       ,(if (getf summary :public-cors-origins)
            (format nil "~{~A~^,~}" (getf summary :public-cors-origins))
            ""))
      ("engineVhosts" .
       ,(if (getf summary :engine-vhosts)
            (format nil "~{~A~^,~}" (getf summary :engine-vhosts))
            ""))
      ("publicVhosts" .
       ,(if (getf summary :public-vhosts)
            (format nil "~{~A~^,~}" (getf summary :public-vhosts))
            ""))
      ("kzgVerifierCommand" .
       ,(or (getf summary :kzg-verifier-command) ""))
      ("kzgVerifierTimeoutSeconds" .
       ,(if (getf summary :kzg-verifier-timeout-seconds)
            (write-to-string (getf summary :kzg-verifier-timeout-seconds))
            ""))
      ("kzgProofVerificationAvailable" .
       ,(if (getf summary :kzg-proof-verification-available-p)
            "true"
            "false"))
      ("pidFilePath" . ,(or (getf summary :pid-file-path) "")))))

(defun call-with-devnet-cli-kzg-verifier
    (command timeout-seconds thunk)
  (unless (functionp thunk)
    (error "Devnet KZG verifier thunk must be a function"))
  (let ((old-point-verifier *kzg-point-proof-verifier*)
        (old-blob-verifier *kzg-blob-proof-verifier*))
    (unwind-protect
         (let ((*kzg-verifier-command-timeout-seconds*
                 (or timeout-seconds
                     *kzg-verifier-command-timeout-seconds*)))
           (when command
             (configure-kzg-proof-command-verifiers command))
           (funcall thunk))
      (setf *kzg-point-proof-verifier* old-point-verifier
            *kzg-blob-proof-verifier* old-blob-verifier))))

(defun devnet-cli-log-event
    (node name &key engine-endpoint rpc-endpoint connection-summary
            (public-rpc-enabled-p t))
  (ethereum-lisp.telemetry:telemetry-log
   :info
   name
   :sink (devnet-node-telemetry-sink node)
   :fields (devnet-node-telemetry-fields
            node
            :engine-endpoint engine-endpoint
            :rpc-endpoint rpc-endpoint
            :public-rpc-enabled-p public-rpc-enabled-p
            :lifecycle-phase
            (cond
              ((string= name "devnet.ready") "ready")
              ((string= name "devnet.shutdown") "shutdown")
              ((string= name "devnet.error") "error")
              ((string= name "init.ready") "ready")
              ((string= name "init.shutdown") "shutdown")
              ((string= name "init.error") "error")
              (t ""))
            :connection-summary connection-summary)))

(defun devnet-cli-error-log-file (args)
  (when (and args (string= "devnet" (first args)))
    (setf args (rest args)))
  (setf args (devnet-cli-normalize-option-args args))
  (loop while args
        for option = (pop args)
        do (cond
             ((string= option "--log-file")
              (when (and args
                         (not (devnet-cli-option-token-p (first args))))
                (return (first args))))
             ((member option *devnet-cli-value-options* :test #'string=)
              (when (and args
                         (not (devnet-cli-option-token-p (first args))))
                (pop args)))
             ((member option
                      *devnet-cli-optional-boolean-options*
                      :test #'string=)
              (when (and args
                         (not (devnet-cli-option-token-p (first args)))
                         (devnet-cli-boolean-token-p (first args)))
                (pop args))))))

(defun devnet-cli-log-error-event (args condition)
  (let ((log-file (devnet-cli-error-log-file args)))
    (when log-file
      (devnet-cli-ensure-path-parent-directory log-file)
      (with-open-file (stream log-file
                              :direction :output
                              :if-exists :append
                              :if-does-not-exist :create)
        (ethereum-lisp.telemetry:telemetry-log
         :error
         (if (devnet-cli-init-command-p args) "init.error" "devnet.error")
         :sink (ethereum-lisp.telemetry:make-stream-telemetry-sink
                :stream stream)
         :fields `(("lifecyclePhase" . "error")
                   ("exitCode" . "1")
                   ("processId" . ,(let ((process-id (devnet-process-id)))
                                      (if process-id
                                          (write-to-string process-id)
                                          "")))
                   ("errorMessage" . ,(princ-to-string condition))
                   ("logPath" . ,log-file)))))))

(defun call-with-devnet-cli-telemetry-sink (options output-stream thunk)
  (let ((log-file (getf options :log-file)))
    (if log-file
        (with-open-file (stream (devnet-cli-ensure-path-parent-directory
                                 log-file)
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (funcall thunk
                   (ethereum-lisp.telemetry:make-stream-telemetry-sink
                    :stream stream)))
        (funcall thunk
                 (ethereum-lisp.telemetry:make-stream-telemetry-sink
                  :stream output-stream)))))

(defun main (&optional (args (uiop:command-line-arguments))
              &key
                (output-stream *standard-output*)
                (error-stream *error-output*))
  (handler-case
      (cond
        ((devnet-cli-top-level-help-p args)
         (devnet-cli-print-top-level-help output-stream)
         0)
        ((devnet-cli-top-level-version-p args)
         (devnet-cli-print-version output-stream)
         0)
        ((devnet-cli-init-command-p args)
         (let ((options (devnet-cli-init-options args)))
           (if (getf options :help-p)
               (progn
                 (devnet-cli-print-init-usage output-stream)
                 0)
               (progn
                 (devnet-cli-run-init options output-stream)
                 0))))
        (t
         (let ((options (devnet-cli-options args)))
           (if (getf options :help-p)
               (progn
                 (devnet-cli-print-usage output-stream)
                 0)
               (let* ((genesis-path (devnet-cli-resolve-genesis-path options))
                      (genesis-json
                        (devnet-cli-resolve-genesis-json
                         options genesis-path)))
                 (unless (or genesis-path genesis-json)
                   (error "--genesis is required unless --datadir contains an initialized genesis or --dev is enabled"))
                 (call-with-devnet-cli-telemetry-sink
                  options
                  output-stream
                  (lambda (telemetry-sink)
                    (call-with-devnet-cli-kzg-verifier
                     (getf options :kzg-verifier-command)
                     (getf options :kzg-verifier-timeout-seconds)
                     (lambda ()
                       (let ((node
                               (make-devnet-node
                                :genesis-path genesis-path
                                :genesis-json genesis-json
                                :dev-mode-p (and genesis-json
                                                 (getf options :dev-mode-p))
                                :host (getf options :host)
                                :port (getf options :port)
                                :public-host (getf options :public-host)
                                :public-port (getf options :public-port)
                                :jwt-secret-path (getf options :jwt-secret-path)
                                :engine-rpc-prefix
                                (getf options :engine-rpc-prefix)
                                :public-rpc-prefix
                                (getf options :public-rpc-prefix)
                                :log-path (getf options :log-file)
                                :database-path (getf options :database-path)
                                :pid-file-path (getf options :pid-file)
                                :network-id (getf options :network-id)
                                :public-api-modules
                                (getf options :http-api-modules)
                                :engine-cors-origins
                                (getf options :authrpc-cors-origins)
                                :public-cors-origins
                                (getf options :http-cors-origins)
                                :engine-vhosts
                                (getf options :engine-vhosts)
                                :public-vhosts
                                (getf options :http-vhosts)
                                :terminal-total-difficulty
                                (getf options :terminal-total-difficulty)
                                :terminal-total-difficulty-passed
                                (getf options
                                      :terminal-total-difficulty-passed)
                                :terminal-total-difficulty-passed-specified-p
                                (getf options
                                      :terminal-total-difficulty-passed-specified-p)
                                :terminal-block-hash
                                (getf options :terminal-block-hash)
                                :terminal-block-number
                                (getf options :terminal-block-number)
                                :coinbase (getf options :coinbase)
                                :allow-unprotected-transactions-p
                                (getf options
                                      :allow-unprotected-transactions-p)
                                :txpool-price-limit
                                (getf options :txpool-price-limit)
                                :txpool-price-bump-percent
                                (getf options :txpool-price-bump-percent)
                                :txpool-account-slot-limit
                                (getf options :txpool-account-slot-limit)
                                :txpool-global-slot-limit
                                (getf options :txpool-global-slot-limit)
                                :txpool-account-queue-limit
                                (getf options :txpool-account-queue-limit)
                                :txpool-global-queue-limit
                                (getf options :txpool-global-queue-limit)
                                :txpool-local-addresses
                                (getf options :txpool-local-addresses)
                                :txpool-no-local-exemptions-p
                                (getf options :txpool-no-local-exemptions-p)
                                :kzg-verifier-command
                                (getf options :kzg-verifier-command)
                                :kzg-verifier-timeout-seconds
                                (getf options
                                      :kzg-verifier-timeout-seconds)
                                :public-allowed-method-p
                                (devnet-cli-public-api-method-filter
                                 (getf options :http-api-modules))
                                :telemetry-sink telemetry-sink)))
                         (when (getf options :pid-file)
                           (devnet-cli-write-pid-file
                            (getf options :pid-file)))
                         (if (getf options :serve-p)
                             (let ((bound-engine-endpoint nil)
                                   (bound-rpc-endpoint nil)
                                   (ready-p nil)
                                   (serve-summary nil))
                               (unwind-protect
                                    (setf
                                     serve-summary
                                     (start-devnet-node
                                      node
                                      :max-connections
                                      (getf options :max-connections)
                                      :install-signal-handlers-p t
                                      :signal-stream error-stream
                                      :on-listeners-ready
                                      (lambda (engine-listener public-listener)
                                        (setf bound-engine-endpoint
                                              (engine-rpc-http-listener-endpoint
                                               engine-listener)
                                              bound-rpc-endpoint
                                              (and public-listener
                                                   (engine-rpc-http-listener-endpoint
                                                    public-listener)))
                                        (when (getf options :ready-file)
                                          (devnet-cli-write-ready-file
                                           node
                                           (getf options :ready-file)
                                           :engine-endpoint
                                           bound-engine-endpoint
                                           :rpc-endpoint bound-rpc-endpoint
                                           :public-rpc-enabled-p
                                           (getf options
                                                 :public-rpc-enabled-p)))
                                        (when (getf options :log-file)
                                          (devnet-cli-log-event
                                           node
                                           "devnet.ready"
                                           :engine-endpoint
                                           bound-engine-endpoint
                                           :rpc-endpoint bound-rpc-endpoint
                                           :public-rpc-enabled-p
                                           (getf options
                                                 :public-rpc-enabled-p)))
                                        (setf ready-p t)
                                        (devnet-cli-print-summary
                                         node
                                         output-stream
                                         :format
                                         (getf options :summary-format)
                                         :engine-endpoint
                                         bound-engine-endpoint
                                         :rpc-endpoint bound-rpc-endpoint
                                         :public-rpc-enabled-p
                                         (getf options
                                               :public-rpc-enabled-p)))
                                      :public-rpc-enabled-p
                                      (getf options :public-rpc-enabled-p)))
                                 (devnet-node-export-database
                                  node
                                  :state-prune-before
                                  (getf options :state-prune-before))
                                 (when (and (getf options :log-file)
                                            (or ready-p serve-summary))
                                   (devnet-cli-log-event
                                    node
                                    "devnet.shutdown"
                                    :engine-endpoint bound-engine-endpoint
                                    :rpc-endpoint bound-rpc-endpoint
                                    :public-rpc-enabled-p
                                    (getf options :public-rpc-enabled-p)
                                    :connection-summary serve-summary))))
                             (progn
                               (devnet-node-export-database
                                node
                                :state-prune-before
                                (getf options :state-prune-before))
                               (when (getf options :ready-file)
                                 (devnet-cli-write-ready-file
                                  node
                                  (getf options :ready-file)
                                  :public-rpc-enabled-p
                                  (getf options :public-rpc-enabled-p)))
                               (when (getf options :log-file)
                                 (devnet-cli-log-event
                                  node
                                  "devnet.ready"
                                  :public-rpc-enabled-p
                                  (getf options :public-rpc-enabled-p)))
                               (devnet-cli-print-summary
                                node
                                output-stream
                                :format (getf options :summary-format)
                                :public-rpc-enabled-p
                                (getf options :public-rpc-enabled-p))
                               (when (getf options :log-file)
                                 (devnet-cli-log-event
                                  node
                                  "devnet.shutdown"
                                  :public-rpc-enabled-p
                                  (getf options :public-rpc-enabled-p)))))
                         0))))))))))
    (error (condition)
      (ignore-errors
       (devnet-cli-log-error-event args condition))
      (format error-stream "~A~%" condition)
      (if (devnet-cli-init-command-p args)
          (devnet-cli-print-init-usage error-stream)
          (devnet-cli-print-usage error-stream))
      1)))
