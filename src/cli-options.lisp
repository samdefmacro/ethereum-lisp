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
        ((and (string= section "Eth.TxPool") (string= key "Lifetime")
              (non-empty-scalar))
         (list "--txpool.lifetime" scalar))
        ((and (string= section "Eth.TxPool") (string= key "Journal")
              (non-empty-scalar))
         (list "--txpool.journal" scalar))
        ((and (string= section "Eth.TxPool") (string= key "Rejournal")
              (non-empty-scalar))
         (list "--txpool.rejournal" scalar))
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

(defun devnet-cli-duration-unit-seconds (unit option)
  (cond
    ((or (null unit) (string= unit "") (string= unit "s")) 1)
    ((string= unit "m") 60)
    ((string= unit "h") 3600)
    ((string= unit "d") 86400)
    (t
     (error "~A duration unit must be one of s, m, h, or d" option))))

(defun devnet-cli-parse-duration-seconds (value option)
  (unless (and (stringp value) (plusp (length value)))
    (error "~A requires a duration value" option))
  (let ((length (length value))
        (position 0)
        (total 0))
    (loop
      (when (>= position length)
        (return total))
      (let* ((number-start position)
             (unit-start
               (or (position-if-not #'digit-char-p value :start position)
                   length))
             (number-token (subseq value number-start unit-start)))
        (when (zerop (length number-token))
          (error "~A requires a non-negative duration" option))
        (when (and (= unit-start length) (/= number-start 0))
          (error "~A duration unit must be one of s, m, h, or d" option))
        (let* ((next-position
                 (if (< unit-start length)
                     (1+ unit-start)
                     unit-start))
               (unit-token
                 (if (< unit-start length)
                     (string-downcase (subseq value unit-start next-position))
                     ""))
               (seconds
                 (* (devnet-cli-parse-non-negative-integer
                     number-token
                     option)
                    (devnet-cli-duration-unit-seconds unit-token option))))
          (incf total seconds)
          (setf position next-position))))))

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
        (dev-period-seconds nil)
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
        (txpool-lifetime-seconds nil)
        (txpool-journal-path nil)
        (txpool-rejournal-seconds nil)
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
               ((string= option "--dev.period")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf dev-period-seconds
                        (devnet-cli-parse-duration-seconds value option)
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
               ((string= option "--txpool.lifetime")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-lifetime-seconds
                        (devnet-cli-parse-duration-seconds value option)
                        args rest)))
               ((string= option "--txpool.journal")
                (multiple-value-setq (txpool-journal-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--txpool.rejournal")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf txpool-rejournal-seconds
                        (devnet-cli-parse-duration-seconds value option)
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
          :dev-period-seconds dev-period-seconds
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
          :txpool-lifetime-seconds txpool-lifetime-seconds
          :txpool-journal-path txpool-journal-path
          :txpool-rejournal-seconds txpool-rejournal-seconds
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
