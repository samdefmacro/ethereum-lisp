(in-package #:ethereum-lisp.cli)

(defstruct (devnet-endpoint-config
            (:constructor %make-devnet-endpoint-config
                (&key host port rpc-prefix cors-origins allowed-hosts
                      allowed-method-p)))
  host
  port
  rpc-prefix
  cors-origins
  allowed-hosts
  allowed-method-p)

(defun make-devnet-endpoint-config
    (&key host port rpc-prefix cors-origins allowed-hosts allowed-method-p)
  (%make-devnet-endpoint-config
   :host host
   :port port
   :rpc-prefix rpc-prefix
   :cors-origins (and cors-origins (copy-list cors-origins))
   :allowed-hosts (and allowed-hosts (copy-list allowed-hosts))
   :allowed-method-p allowed-method-p))

(defstruct (devnet-txpool-policy
            (:constructor %make-devnet-txpool-policy
                (&key allow-unprotected-transactions-p price-limit
                      price-bump-percent account-slot-limit global-slot-limit
                      account-queue-limit global-queue-limit local-addresses
                      no-local-exemptions-p lifetime-seconds)))
  allow-unprotected-transactions-p
  price-limit
  price-bump-percent
  account-slot-limit
  global-slot-limit
  account-queue-limit
  global-queue-limit
  local-addresses
  no-local-exemptions-p
  lifetime-seconds)

(defun make-devnet-txpool-policy
    (&key allow-unprotected-transactions-p price-limit price-bump-percent
          account-slot-limit global-slot-limit account-queue-limit
          global-queue-limit local-addresses no-local-exemptions-p
          lifetime-seconds)
  (%make-devnet-txpool-policy
   :allow-unprotected-transactions-p allow-unprotected-transactions-p
   :price-limit price-limit
   :price-bump-percent price-bump-percent
   :account-slot-limit account-slot-limit
   :global-slot-limit global-slot-limit
   :account-queue-limit account-queue-limit
   :global-queue-limit global-queue-limit
   :local-addresses (and local-addresses (copy-list local-addresses))
   :no-local-exemptions-p no-local-exemptions-p
   :lifetime-seconds lifetime-seconds))

(defstruct (devnet-kzg-config
            (:constructor make-devnet-kzg-config
                (&key command timeout-seconds)))
  command
  timeout-seconds)

(defstruct (devnet-persistence-state
            (:constructor make-devnet-persistence-state
                (&key (current-generation 0) (chain-generation 0)
                      chain-id genesis-hash authority-id)))
  (current-generation 0 :type integer)
  (chain-generation 0 :type integer)
  chain-id
  genesis-hash
  authority-id)

(defstruct (devnet-node
            (:constructor %make-devnet-node
                (&key genesis-path store config genesis-block service
                      public-service telemetry-sink jwt-secret-path log-path
                      database-path pid-file-path network-id
                      public-api-modules engine-endpoint-config
                      public-endpoint-config txpool-policy kzg-config
                      dev-mode-p coinbase store-guard-function
                      persistence-state
                      canonical-transition-persistence-function
                      txpool-journal-path
                      txpool-rejournal-seconds
                      dev-period-seconds)))
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
  engine-endpoint-config
  public-endpoint-config
  txpool-policy
  kzg-config
  dev-mode-p
  coinbase
  store-guard-function
  persistence-state
  canonical-transition-persistence-function
  txpool-journal-path
  txpool-rejournal-seconds
  dev-period-seconds)

(defun make-devnet-store-guard-function ()
  #+sbcl
  (let ((mutex (sb-thread:make-mutex :name "ethereum-lisp-node-store")))
    (lambda (thunk)
      (sb-thread:with-mutex (mutex)
        (funcall thunk))))
  #-sbcl
  (lambda (thunk)
    (funcall thunk)))

(defun call-with-devnet-node-store-guard (node thunk)
  (unless (typep node 'devnet-node)
    (error "Devnet store guard requires a devnet node"))
  (unless (functionp thunk)
    (error "Devnet store guard requires a function"))
  (funcall (devnet-node-store-guard-function node) thunk))

(defun devnet-node-engine-cors-origins (node)
  (devnet-endpoint-config-cors-origins
   (devnet-node-engine-endpoint-config node)))

(defun devnet-node-public-cors-origins (node)
  (devnet-endpoint-config-cors-origins
   (devnet-node-public-endpoint-config node)))

(defun devnet-node-engine-vhosts (node)
  (devnet-endpoint-config-allowed-hosts
   (devnet-node-engine-endpoint-config node)))

(defun devnet-node-public-vhosts (node)
  (devnet-endpoint-config-allowed-hosts
   (devnet-node-public-endpoint-config node)))

(defun devnet-node-allow-unprotected-transactions-p (node)
  (devnet-txpool-policy-allow-unprotected-transactions-p
   (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-price-limit (node)
  (devnet-txpool-policy-price-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-price-bump-percent (node)
  (devnet-txpool-policy-price-bump-percent (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-account-slot-limit (node)
  (devnet-txpool-policy-account-slot-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-global-slot-limit (node)
  (devnet-txpool-policy-global-slot-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-account-queue-limit (node)
  (devnet-txpool-policy-account-queue-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-global-queue-limit (node)
  (devnet-txpool-policy-global-queue-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-local-addresses (node)
  (devnet-txpool-policy-local-addresses (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-no-local-exemptions-p (node)
  (devnet-txpool-policy-no-local-exemptions-p
   (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-lifetime-seconds (node)
  (devnet-txpool-policy-lifetime-seconds (devnet-node-txpool-policy node)))

(defun devnet-node-kzg-verifier-command (node)
  (devnet-kzg-config-command (devnet-node-kzg-config node)))

(defun devnet-node-kzg-verifier-timeout-seconds (node)
  (devnet-kzg-config-timeout-seconds (devnet-node-kzg-config node)))

(defstruct devnet-shutdown-controller
  requested-p
  engine-listener
  public-listener)

(defstruct (devnet-rejournal-state
            (:constructor %make-devnet-rejournal-state
                (&key node interval-seconds now-function last-run-time)))
  node
  interval-seconds
  now-function
  last-run-time)

(defstruct (devnet-dev-period-state
            (:constructor %make-devnet-dev-period-state
                (&key node interval-seconds now-function last-run-time)))
  node
  interval-seconds
  now-function
  last-run-time)

(defconstant +devnet-default-public-rpc-port+ 8545)
(defparameter +devnet-datadir-database-file+ "ethereum-lisp-chain.sexp")
(defparameter +devnet-datadir-genesis-file+ "genesis.json")
(defparameter +devnet-datadir-jwt-secret-file+ "jwtsecret")
(defparameter +devnet-geth-datadir-directory+ "geth/")
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
