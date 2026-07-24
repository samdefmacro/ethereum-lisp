(in-package #:ethereum-lisp.cli)

(defun devnet-cli-print-usage (stream)
  (format stream
          "Usage: ethereum-lisp devnet [--config PATH] [--genesis PATH] [--engine-host HOST|--authrpc.addr HOST] [--engine-port PORT|--authrpc.port PORT] [--host HOST] [--port P2P-PORT] [--public-host HOST|--http.addr HOST] [--public-port PORT|--http.port PORT] [--jwt-secret PATH|--authrpc.jwtsecret PATH] [--authrpc.rpcprefix PATH] [--authrpc.vhosts HOSTS] [--authrpc.corsdomain DOMAINS] [--http] [--http.api LIST] [--http.rpcprefix PATH] [--http.vhosts HOSTS] [--http.corsdomain DOMAINS] [--http.maxclients N] [--http.readtimeout DURATION] [--http.writetimeout DURATION] [--http.idletimeout DURATION] [--ws] [--ws.addr HOST] [--ws.port PORT] [--ws.api LIST] [--ws.origins ORIGINS] [--ws.rpcprefix PATH] [--graphql] [--graphql.addr HOST] [--graphql.port PORT] [--graphql.vhosts HOSTS] [--graphql.corsdomain DOMAINS] [--networkid ID|--network-id ID] [--mainnet] [--sepolia] [--holesky] [--hoodi] [--goerli] [--syncmode MODE] [--nodiscover] [--ipcdisable] [--ipcpath PATH] [--ipcapi LIST] [--verbosity LEVEL] [--log.file PATH] [--log.format FORMAT] [--log.maxsize MB] [--log.maxbackups N] [--log.maxage DAYS] [--log.compress] [--maxpeers N] [--nat MODE] [--netrestrict CIDRS] [--identity NAME] [--nodekey PATH] [--nodekeyhex HEX] [--discovery.port PORT] [--discovery.dns URL] [--gcmode MODE] [--state.scheme SCHEME] [--db.engine ENGINE] [--datadir.ancient PATH] [--cache MB] [--cache.database MB] [--cache.gc MB] [--cache.trie MB] [--txlookuplimit N] [--history.transactions N] [--bootnodes URLS] [--peer ENODE] [--rpc.gascap GAS] [--rpc.evmtimeout DURATION] [--rpc.txfeecap ETH] [--rpc.batch-request-limit N] [--rpc.batch-response-max-size BYTES] [--override.terminaltotaldifficulty TTD] [--override.terminaltotaldifficultypassed] [--override.terminalblockhash HASH] [--override.terminalblocknumber NUMBER] [--mine] [--miner.etherbase ADDRESS] [--etherbase ADDRESS] [--miner.gaslimit N] [--miner.gasprice WEI] [--unlock ACCOUNTS] [--password PATH] [--allow-insecure-unlock] [--rpc.allow-unprotected-txs] [--txpool.locals ACCOUNTS] [--txpool.nolocals] [--txpool.journal PATH] [--txpool.rejournal DURATION] [--txpool.pricelimit N] [--txpool.pricebump N] [--txpool.accountslots N] [--txpool.globalslots N] [--txpool.accountqueue N] [--txpool.globalqueue N] [--txpool.lifetime DURATION] [--txpool.blobpool.datacap BYTES] [--txpool.blobpool.pricebump N] [--dev] [--dev.period SECONDS] [--dev.gaslimit GAS] [--nousb] [--metrics] [--metrics.addr HOST] [--metrics.port PORT] [--pprof] [--pprof.addr HOST] [--pprof.port PORT] [--snapshot] [--database PATH] [--datadir PATH] [--prune-state-before NUMBER] [--max-connections N] [--json] [--ready-file PATH] [--log-file PATH] [--pid-file PATH] [--no-serve]~%"))

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
