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
                      txpool-lifetime-seconds
                      txpool-journal-path
                      txpool-rejournal-seconds
                      dev-period-seconds
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
  txpool-lifetime-seconds
  txpool-journal-path
  txpool-rejournal-seconds
  dev-period-seconds
  kzg-verifier-command
  kzg-verifier-timeout-seconds)

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
