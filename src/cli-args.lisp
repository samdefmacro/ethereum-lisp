(in-package #:ethereum-lisp.cli)

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
