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
   ;; Keep the operator defaults aligned with the admission-service defaults.
   ;; NIL means the flag was omitted; zero remains an explicit operator value.
   :price-limit (if (null price-limit) 1 price-limit)
   :price-bump-percent
   (if (null price-bump-percent) 10 price-bump-percent)
   :account-slot-limit
   (if (null account-slot-limit) 16 account-slot-limit)
   :global-slot-limit
   (if (null global-slot-limit) 5120 global-slot-limit)
   :account-queue-limit
   (if (null account-queue-limit) 64 account-queue-limit)
   :global-queue-limit
   (if (null global-queue-limit) 1024 global-queue-limit)
   :local-addresses (and local-addresses (copy-list local-addresses))
   :no-local-exemptions-p no-local-exemptions-p
   :lifetime-seconds
   (if (null lifetime-seconds) (* 3 60 60) lifetime-seconds)))

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
                      database-path (db-engine :file) pid-file-path network-id
                      public-api-modules engine-endpoint-config
                      public-endpoint-config txpool-policy
                      dev-mode-p coinbase store-guard-function
                      store-guard-try-function
                      persistence-state
                      candidate-persistence-function
                      peer-sync-progress-function
                      peer-sync-progress-reset-function
                      canonical-transition-persistence-function
                      txpool-journal-path
                      txpool-rejournal-seconds
                      dev-period-seconds
                      miner-gas-limit
                      peers
                      bootnodes
                      node-key
                      dial-registry
                      dial-guard-function
                      p2p-host
                      p2p-port
                      nat-policy
                      peer-table
                      discovery-table
                      metrics-host
                      metrics-port
                      ws-enabled-p
                      ws-host
                      ws-port
                      ws-origins
                      ws-rpc-prefix)))
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
  (db-engine :file)
  pid-file-path
  network-id
  public-api-modules
  engine-endpoint-config
  public-endpoint-config
  txpool-policy
  dev-mode-p
  coinbase
  store-guard-function
  ;; The same guard, but giving up rather than waiting. See
  ;; CALL-WITH-DEVNET-NODE-STORE-GUARD-IF-FREE.
  store-guard-try-function
  persistence-state
  ;; One durable candidate sink is shared by Engine and P2P imports.  The P2P
  ;; path may additionally supply a peer-sync progress record that the adapter
  ;; commits in the candidate's database batch.
  candidate-persistence-function
  ;; Point reader for a peer's last durable contiguous candidate.  Keeping the
  ;; database adapter behind a closure avoids leaking persistence concerns into
  ;; the networking package.
  peer-sync-progress-function
  ;; Atomically removes a cursor whose branch Engine forkchoice abandoned.
  ;; Its replacement is written with the first candidate on the new branch.
  peer-sync-progress-reset-function
  canonical-transition-persistence-function
  txpool-journal-path
  txpool-rejournal-seconds
  dev-period-seconds
  miner-gas-limit
  peers
  bootnodes
  node-key
  dial-registry
  dial-guard-function
  ;; Inbound peering. P2P-PORT NIL means no listener at all, which is the
  ;; default: binding a fixed port by habit is how two nodes on one machine
  ;; collide. The peer table carries the peer limit and our own identity.
  p2p-host
  p2p-port
  nat-policy
  peer-table
  ;; Who discovery knows about, bucketed by distance. Guarded by the same mutex
  ;; as the peer table and the dial registry.
  discovery-table
  ;; Where --metrics.addr/--metrics.port asked the metrics endpoint to bind.
  ;; A port with --metrics off binds nothing; see DEVNET-NODE-METRICS-ENDPOINT.
  metrics-host
  metrics-port
  ;; The WebSocket endpoint. Off unless --ws; it carries the same public method
  ;; filter as the HTTP listener plus eth_subscribe, which only means anything
  ;; on a connection that stays open.
  ws-enabled-p
  ws-host
  ws-port
  ws-origins
  ws-rpc-prefix
  ;; Whether a peer session is currently catching up. Guarded by the peer-table
  ;; mutex, and the reason it exists is in DEVNET-NODE-CLAIM-SYNC.
  (syncing-p nil)
  ;; The last eth chain context discovery managed to read, kept so discovery
  ;; never has to WAIT for the store guard to learn our fork id. See
  ;; DEVNET-NODE-CHAIN-CONTEXT for why waiting there is not an option.
  (chain-context-cache nil)
  ;; EIP-778 sequence and the exact pairs it describes. The responder updates
  ;; these under the peer-table lock, so a changed endpoint/fork id increments
  ;; monotonically even across a chain reorg whose head number decreases.
  (enr-seq 1)
  (enr-pairs nil))

(defun devnet-make-mutex (name)
  "A mutex on SBCL, NIL elsewhere. CALL-WITH-DEVNET-MUTEX degrades accordingly."
  #+sbcl (sb-thread:make-mutex :name name)
  #-sbcl (progn name nil))

(defun call-with-devnet-mutex (mutex thunk)
  #+sbcl
  (if mutex
      (sb-thread:with-mutex (mutex) (funcall thunk))
      (funcall thunk))
  #-sbcl
  (progn mutex (funcall thunk)))

(defun make-devnet-store-guard-try-function (mutex)
  "A companion to a store-guard function that gives up instead of waiting.

Returns a function of a thunk yielding (VALUES RESULT RAN-P): the thunk runs
under MUTEX when it is free right now, and does not run at all when it is
held."
  #+sbcl
  (lambda (thunk)
    (if (sb-thread:grab-mutex mutex :waitp nil)
        (unwind-protect (values (funcall thunk) t)
          (sb-thread:release-mutex mutex))
        (values nil nil)))
  #-sbcl
  (progn mutex (lambda (thunk) (values (funcall thunk) t))))

(defun make-devnet-store-guard-function ()
  "Return (VALUES GUARD TRY): the blocking store guard and its give-up-instead
companion, over the same mutex. Two functions rather than one with a flag so
that a caller cannot accidentally block by omitting an argument."
  #+sbcl
  (let ((mutex (sb-thread:make-mutex :name "ethereum-lisp-node-store")))
    (values (lambda (thunk)
              (sb-thread:with-mutex (mutex)
                (funcall thunk)))
            (make-devnet-store-guard-try-function mutex)))
  #-sbcl
  (values (lambda (thunk) (funcall thunk))
          (lambda (thunk) (values (funcall thunk) t))))

(defun call-with-devnet-node-store-guard (node thunk)
  (unless (typep node 'devnet-node)
    (error "Devnet store guard requires a devnet node"))
  (unless (functionp thunk)
    (error "Devnet store guard requires a function"))
  (funcall (devnet-node-store-guard-function node) thunk))

(defun call-with-devnet-node-store-guard-if-free (node thunk)
  "Run THUNK under NODE's store guard only if the guard is free right now.

Returns (VALUES RESULT T) when THUNK ran and (VALUES NIL NIL) when the guard
was held. For callers that would rather have a stale answer than block: the
store guard is held for the whole of a block import, so a background thread
that waits on it does not run slowly, it stops until the node is idle.

Falls back to a blocking acquisition when the node has no try function, which
is what the non-SBCL build and any node built before this existed will have."
  (unless (typep node 'devnet-node)
    (error "Devnet store guard requires a devnet node"))
  (unless (functionp thunk)
    (error "Devnet store guard requires a function"))
  (let ((try (devnet-node-store-guard-try-function node)))
    (if (functionp try)
        (funcall try thunk)
        (values (call-with-devnet-node-store-guard node thunk) t))))

(defun call-with-devnet-peer-table (node thunk)
  "Run THUNK with exclusive access to NODE's peer table AND dial registry.

The two share one mutex on purpose: a scheduler decision reads both (is this
peer already connected? is there a free dial slot?) and then mutates both, and
that has to be one atomic step. It is independent of the store guard, so peer
bookkeeping never blocks behind block import or an RPC call.

The mutex is NOT recursive. Nothing called from inside THUNK may take it again --
which is why the peer table and the dial registry lock nothing themselves."
  (funcall (devnet-node-dial-guard-function node) thunk))

(defun devnet-node-metrics-enabled-p (node)
  "Whether --metrics is on.

Distinct from DEVNET-NODE-METRICS having a value: a node that has just started
with metrics on has counted nothing yet, so its snapshot is legitimately empty.
Anything deciding whether to publish metrics must ask this, not the counts."
  (counting-telemetry-sink-p (devnet-node-telemetry-sink node)))

(defun devnet-node-metrics (node)
  "Event counts collected since start, or NIL when --metrics is off.

These are counts of the telemetry events the node already emits, so they follow
whatever it really does rather than a separate set of counters that has to be
kept in step by hand."
  (let ((sink (devnet-node-telemetry-sink node)))
    (when (counting-telemetry-sink-p sink)
      (counting-telemetry-sink-snapshot sink))))

(defun devnet-node-metric-gauges (node)
  "Live operator levels sampled atomically enough for one Prometheus scrape."
  (let* ((store (devnet-node-store node))
         (head (chain-store-latest-block store))
         (safe (chain-store-safe-block store))
         (finalized (chain-store-finalized-block store)))
    `(("ethereum_lisp_txpool_pending"
       . ,(engine-payload-store-pending-transaction-count store))
      ("ethereum_lisp_txpool_queued"
       . ,(engine-payload-store-queued-transaction-count store))
      ("ethereum_lisp_txpool_basefee"
       . ,(engine-payload-store-basefee-transaction-count store))
      ("ethereum_lisp_txpool_blob"
       . ,(engine-payload-store-blob-transaction-count store))
      ("ethereum_lisp_chain_head_number"
       . ,(if head (block-header-number (block-header head)) 0))
      ("ethereum_lisp_chain_safe_number"
       . ,(if safe (block-header-number (block-header safe)) 0))
      ("ethereum_lisp_chain_finalized_number"
       . ,(if finalized (block-header-number (block-header finalized)) 0))
      ("ethereum_lisp_peer_count"
       . ,(devnet-peer-table-count (devnet-node-peer-table node))))))

(defun devnet-node-enode (node)
  "Our own enode URL, or NIL when we are not listening.

The address is the one a peer could actually dial: a wildcard bind reports as
loopback rather than advertising 0.0.0.0, which is not an address."
  (let ((port (devnet-node-p2p-port node)))
    (when port
      (enode-url (node-id-from-private-key (devnet-node-node-key node))
                 (devnet-node-advertised-host node)
                 port))))

(defun devnet-node-advertised-host (node)
  (let ((policy (devnet-node-nat-policy node)))
    (if (and policy (eq :extip (ethereum-lisp.nat:nat-policy-mode policy)))
        (ethereum-lisp.nat:nat-policy-address policy)
        (eth-sync-socket-endpoint-host
         (or (devnet-node-p2p-host node) "0.0.0.0")))))

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

(defstruct devnet-shutdown-controller
  requested-p
  engine-listener
  public-listener
  ;; Anything else that must be closed to wake a thread blocked on it, as an
  ;; alist of (token . thunk) under CLOSEABLE-LOCK. The two listener slots above
  ;; predate this and stay as they are; peer sockets, which come and go, ride
  ;; here. See DEVNET-SHUTDOWN-CONTROLLER-ADD-CLOSEABLE.
  (closeables '())
  (closeable-counter 0)
  (closeable-lock (devnet-make-mutex "ethereum-lisp-devnet-closeables")))

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
(defparameter +devnet-datadir-rocksdb-directory+ "chaindata/"
  "Datadir-relative directory holding the RocksDB chain database when the
--db.engine=rocksdb backend is selected. RocksDB owns a directory of SST and
WAL files rather than the single CRC-framed log file the default backend uses.")
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

(defun devnet-shutdown-controller-add-closeable (controller thunk)
  "Register THUNK to be run when shutdown is requested, and return a token for
DEVNET-SHUTDOWN-CONTROLLER-REMOVE-CLOSEABLE.

If shutdown has ALREADY been requested the thunk is run immediately and NIL is
returned. Without that, a thread registering its socket a moment after the sweep
would never be closed and would block on a read forever, which is precisely the
shutdown a caller was trying to perform."
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (let ((token
          (call-with-devnet-mutex
           (devnet-shutdown-controller-closeable-lock controller)
           (lambda ()
             (unless (devnet-shutdown-controller-requested-p controller)
               (let ((token (incf (devnet-shutdown-controller-closeable-counter
                                   controller))))
                 (push (cons token thunk)
                       (devnet-shutdown-controller-closeables controller))
                 token))))))
    (unless token
      (ignore-errors (funcall thunk)))
    token))

(defun devnet-shutdown-controller-remove-closeable (controller token)
  "Forget the closeable registered under TOKEN, without running it."
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (when token
    (call-with-devnet-mutex
     (devnet-shutdown-controller-closeable-lock controller)
     (lambda ()
       (setf (devnet-shutdown-controller-closeables controller)
             (remove token (devnet-shutdown-controller-closeables controller)
                     :key #'car)))))
  t)

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
  ;; Snapshot under the lock, then close OUTSIDE it. Closing while holding it
  ;; would block every session thread trying to deregister — and those threads
  ;; are exactly what the caller is about to wait for.
  (let ((closeables
          (call-with-devnet-mutex
           (devnet-shutdown-controller-closeable-lock controller)
           (lambda ()
             (prog1 (devnet-shutdown-controller-closeables controller)
               (setf (devnet-shutdown-controller-closeables controller) '()))))))
    (dolist (entry closeables)
      (ignore-errors (funcall (cdr entry)))))
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
