(in-package #:ethereum-lisp.cli)

(defstruct (devnet-node
            (:constructor %make-devnet-node
                (&key genesis-path store config genesis-block service
                      public-service telemetry-sink jwt-secret-path log-path
                      database-path pid-file-path)))
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
  pid-file-path)

(defstruct devnet-shutdown-controller
  requested-p
  engine-listener
  public-listener)

(defconstant +devnet-default-public-rpc-port+ 8545)

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

(defun devnet-cli-read-jwt-secret (path)
  (let* ((text (devnet-cli-read-file-string path))
         (trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) text))
         (secret (hex-to-bytes trimmed)))
    (unless (= 32 (length secret))
      (error "--jwt-secret must name a file containing a 32-byte hex secret"))
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
  (let ((existing-path (probe-file path)))
    (when (and existing-path (devnet-cli-empty-file-p existing-path))
      (delete-file existing-path)))
  (ethereum-lisp.database:make-file-key-value-database path))

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
       (host "127.0.0.1")
       (port +engine-rpc-default-http-port+)
       (public-host host)
       (public-port +devnet-default-public-rpc-port+)
       jwt-secret-path
       log-path
       database-path
       pid-file-path
       (telemetry-sink ethereum-lisp.telemetry:*telemetry-sink*))
  (unless (and genesis-path (stringp genesis-path))
    (error "Devnet node requires a genesis JSON path"))
  (let* ((config (chain-config-from-genesis-json-file genesis-path))
         (state (state-db-from-genesis-json-file genesis-path))
         (genesis-block
           (genesis-block-from-state-genesis-json-file genesis-path
                                                       :config config))
         (store (make-engine-payload-memory-store))
         (jwt-secret (and jwt-secret-path
                          (devnet-cli-read-jwt-secret jwt-secret-path)))
         (service
           (make-engine-rpc-http-service
            :host host
            :port port
            :store store
            :config config
            :jwt-secret jwt-secret
            :allowed-method-p #'engine-rpc-engine-method-p
            :telemetry-sink telemetry-sink))
         (public-service
           (make-engine-rpc-http-service
            :host public-host
            :port public-port
            :store store
            :config config
            :allowed-method-p #'engine-rpc-public-method-p
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
     :pid-file-path pid-file-path)))

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

(defun devnet-node-summary (node &key engine-endpoint rpc-endpoint)
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
           (or rpc-endpoint
               (engine-rpc-http-service-endpoint
                (devnet-node-public-service node)))))
    (list :genesis-path (devnet-node-genesis-path node)
          :engine-endpoint engine-endpoint
          :rpc-endpoint rpc-endpoint
          :process-id (devnet-process-id)
          :auth-required-p
          (not (null (engine-rpc-http-service-jwt-secret
                      (devnet-node-service node))))
          :jwt-secret-path (devnet-node-jwt-secret-path node)
          :log-path (devnet-node-log-path node)
          :database-path (devnet-node-database-path node)
          :pid-file-path (devnet-node-pid-file-path node)
          :chain-id (chain-config-chain-id (devnet-node-config node))
          :head-number (devnet-block-number head)
          :head-hash (devnet-block-hash-hex head)
          :safe-number (devnet-block-number safe)
          :safe-hash (devnet-block-hash-hex safe)
          :finalized-number (devnet-block-number finalized)
          :finalized-hash (devnet-block-hash-hex finalized)
          :state-available-p
          (and head
               (chain-store-state-available-p store (block-hash head))))))

(defun devnet-node-summary-json-object
    (node &key engine-endpoint rpc-endpoint)
  (let ((summary (devnet-node-summary
                  node
                  :engine-endpoint engine-endpoint
                  :rpc-endpoint rpc-endpoint)))
    `(("genesisPath" . ,(getf summary :genesis-path))
      ("engineEndpoint" . ,(getf summary :engine-endpoint))
      ("rpcEndpoint" . ,(getf summary :rpc-endpoint))
      ("processId" . ,(or (getf summary :process-id) :false))
      ("authRequired" . ,(if (getf summary :auth-required-p) t :false))
      ("jwtSecretPath" . ,(getf summary :jwt-secret-path))
      ("logPath" . ,(getf summary :log-path))
      ("databasePath" . ,(getf summary :database-path))
      ("pidFilePath" . ,(getf summary :pid-file-path))
      ("chainId" . ,(getf summary :chain-id))
      ("headNumber" . ,(getf summary :head-number))
      ("headHash" . ,(getf summary :head-hash))
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
  (unless (typep public-listener 'engine-rpc-http-listener)
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
    (when on-listeners-ready
      (funcall on-listeners-ready engine-listener public-listener))
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
               :total-connections (+ engine-count public-count)))))))

(defun start-devnet-node
    (node &key max-connections stop-p shutdown-controller
            install-signal-handlers-p signal-stream on-listeners-ready)
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
                  (devnet-node-service node))
                 public-listener
                 (make-engine-rpc-http-socket-listener
                  (devnet-node-public-service node)))
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

(defun devnet-cli-next-value (args option)
  (unless (and args
               (not (devnet-cli-option-token-p (first args))))
    (error "~A requires a value" option))
  (values (first args) (rest args)))

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

(defun devnet-cli-options (args)
  (when (and args (string= "devnet" (first args)))
    (setf args (rest args)))
  (let ((genesis-path nil)
        (host "127.0.0.1")
        (port +engine-rpc-default-http-port+)
        (default-public-host "127.0.0.1")
        (public-host nil)
        (public-port +devnet-default-public-rpc-port+)
        (jwt-secret-path nil)
        (database-path nil)
        (state-prune-before nil)
        (max-connections nil)
        (serve-p t)
        (summary-format :sexp)
        (ready-file nil)
        (log-file nil)
        (pid-file nil)
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
               ((or (string= option "--port")
                    (string= option "--engine-port")
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
               ((string= option "--database")
                (multiple-value-setq (database-path args)
                  (devnet-cli-next-value args option)))
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
               ((string= option "--no-serve")
                (setf serve-p nil))
               ((string= option "--json")
                (setf summary-format :json))
               ((string= option "--ready-file")
                (multiple-value-setq (ready-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--log-file")
                (multiple-value-setq (log-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--pid-file")
                (multiple-value-setq (pid-file args)
                  (devnet-cli-next-value args option)))
               (t
                (error "Unknown option ~A" option))))
    (list :genesis-path genesis-path
          :host host
          :port port
          :public-host (or public-host default-public-host)
          :public-port public-port
          :jwt-secret-path jwt-secret-path
          :database-path database-path
          :state-prune-before state-prune-before
          :max-connections max-connections
          :serve-p serve-p
          :summary-format summary-format
          :ready-file ready-file
          :log-file log-file
          :pid-file pid-file
          :help-p help-p)))

(defun devnet-cli-print-usage (stream)
  (format stream
          "Usage: ethereum-lisp devnet --genesis PATH [--engine-host HOST|--authrpc.addr HOST] [--engine-port PORT|--authrpc.port PORT] [--host HOST] [--port PORT] [--public-host HOST|--http.addr HOST] [--public-port PORT|--http.port PORT] [--jwt-secret PATH|--authrpc.jwtsecret PATH] [--database PATH] [--prune-state-before NUMBER] [--max-connections N] [--json] [--ready-file PATH] [--log-file PATH] [--pid-file PATH] [--no-serve]~%"))

(defun devnet-cli-print-summary
    (node stream &key (format :sexp) engine-endpoint rpc-endpoint)
  (ecase format
    (:sexp
     (write (devnet-node-summary
             node
             :engine-endpoint engine-endpoint
             :rpc-endpoint rpc-endpoint)
            :stream stream :pretty nil))
    (:json
     (write-string
      (json-encode
       (devnet-node-summary-json-object
        node
        :engine-endpoint engine-endpoint
        :rpc-endpoint rpc-endpoint))
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

(defun devnet-cli-write-ready-file
    (node path &key engine-endpoint rpc-endpoint)
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
                :rpc-endpoint rpc-endpoint))
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
            connection-summary)
  (let ((summary (devnet-node-summary
                  node
                  :engine-endpoint engine-endpoint
                  :rpc-endpoint rpc-endpoint)))
    `(("engineEndpoint" . ,(getf summary :engine-endpoint))
      ("rpcEndpoint" . ,(getf summary :rpc-endpoint))
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
      ("logPath" . ,(or (getf summary :log-path) ""))
      ("databasePath" . ,(or (getf summary :database-path) ""))
      ("pidFilePath" . ,(or (getf summary :pid-file-path) "")))))

(defun devnet-cli-log-event
    (node name &key engine-endpoint rpc-endpoint connection-summary)
  (ethereum-lisp.telemetry:telemetry-log
   :info
   name
   :sink (devnet-node-telemetry-sink node)
   :fields (devnet-node-telemetry-fields
            node
            :engine-endpoint engine-endpoint
            :rpc-endpoint rpc-endpoint
            :lifecycle-phase
            (cond
              ((string= name "devnet.ready") "ready")
              ((string= name "devnet.shutdown") "shutdown")
              ((string= name "devnet.error") "error")
              (t ""))
            :connection-summary connection-summary)))

(defun devnet-cli-error-log-file (args)
  (when (and args (string= "devnet" (first args)))
    (setf args (rest args)))
  (loop while args
        for option = (pop args)
        do (cond
             ((string= option "--log-file")
              (when (and args
                         (not (devnet-cli-option-token-p (first args))))
                (return (first args))))
             ((member option
                      '("--genesis" "--host" "--engine-host"
                        "--authrpc.addr" "--port" "--engine-port"
                        "--authrpc.port" "--public-host" "--http.addr"
                        "--public-port" "--http.port" "--jwt-secret"
                        "--authrpc.jwtsecret" "--database" "--prune-state-before"
                        "--max-connections" "--ready-file" "--pid-file")
                      :test #'string=)
              (when args (pop args))))))

(defun devnet-cli-log-error-event (args condition)
  (let ((log-file (devnet-cli-error-log-file args)))
    (when log-file
      (with-open-file (stream log-file
                              :direction :output
                              :if-exists :append
                              :if-does-not-exist :create)
        (ethereum-lisp.telemetry:telemetry-log
         :error
         "devnet.error"
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
        (with-open-file (stream log-file
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
      (let ((options (devnet-cli-options args)))
        (if (getf options :help-p)
            (progn
              (devnet-cli-print-usage output-stream)
              0)
            (progn
              (unless (getf options :genesis-path)
                (error "--genesis is required"))
              (call-with-devnet-cli-telemetry-sink
               options
               output-stream
               (lambda (telemetry-sink)
                 (let ((node
                         (make-devnet-node
                          :genesis-path (getf options :genesis-path)
                          :host (getf options :host)
                          :port (getf options :port)
                          :public-host (getf options :public-host)
                          :public-port (getf options :public-port)
                          :jwt-secret-path (getf options :jwt-secret-path)
                          :log-path (getf options :log-file)
                          :database-path (getf options :database-path)
                          :pid-file-path (getf options :pid-file)
                          :telemetry-sink telemetry-sink)))
                   (when (getf options :pid-file)
                     (devnet-cli-write-pid-file (getf options :pid-file)))
                   (if (getf options :serve-p)
                       (let ((bound-engine-endpoint nil)
                             (bound-rpc-endpoint nil)
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
                                        (engine-rpc-http-listener-endpoint
                                         public-listener))
                                  (when (getf options :ready-file)
                                    (devnet-cli-write-ready-file
                                     node
                                     (getf options :ready-file)
                                     :engine-endpoint bound-engine-endpoint
                                     :rpc-endpoint bound-rpc-endpoint))
                                  (when (getf options :log-file)
                                    (devnet-cli-log-event
                                     node
                                     "devnet.ready"
                                     :engine-endpoint bound-engine-endpoint
                                     :rpc-endpoint bound-rpc-endpoint))
                                  (devnet-cli-print-summary
                                   node
                                   output-stream
                                   :format (getf options :summary-format)
                                   :engine-endpoint bound-engine-endpoint
                                   :rpc-endpoint bound-rpc-endpoint))))
                           (devnet-node-export-database
                            node
                            :state-prune-before
                            (getf options :state-prune-before))
                           (when (getf options :log-file)
                             (devnet-cli-log-event
                             node
                             "devnet.shutdown"
                             :engine-endpoint bound-engine-endpoint
                             :rpc-endpoint bound-rpc-endpoint
                             :connection-summary serve-summary))))
                       (progn
                         (devnet-node-export-database
                          node
                          :state-prune-before
                          (getf options :state-prune-before))
                         (when (getf options :ready-file)
                           (devnet-cli-write-ready-file
                            node
                            (getf options :ready-file)))
                         (when (getf options :log-file)
                           (devnet-cli-log-event node "devnet.ready"))
                         (devnet-cli-print-summary
                          node
                          output-stream
                          :format (getf options :summary-format))
                         (when (getf options :log-file)
                           (devnet-cli-log-event node "devnet.shutdown"))))
                   0))))))
    (error (condition)
      (devnet-cli-log-error-event args condition)
      (format error-stream "~A~%" condition)
      (devnet-cli-print-usage error-stream)
      1)))
