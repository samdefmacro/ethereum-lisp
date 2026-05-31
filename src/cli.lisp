(in-package #:ethereum-lisp.cli)

(defstruct (devnet-node
            (:constructor %make-devnet-node
                (&key genesis-path store config genesis-block service
                      public-service telemetry-sink jwt-secret-path log-path)))
  genesis-path
  store
  config
  genesis-block
  service
  public-service
  telemetry-sink
  jwt-secret-path
  log-path)

(defstruct devnet-shutdown-controller
  requested-p
  engine-listener
  public-listener)

(defconstant +devnet-default-public-rpc-port+ 8545)

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

(defun make-devnet-node
    (&key
       genesis-path
       (host "127.0.0.1")
       (port +engine-rpc-default-http-port+)
       (public-host host)
       (public-port +devnet-default-public-rpc-port+)
       jwt-secret-path
       log-path
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
    (%make-devnet-node
     :genesis-path genesis-path
     :store store
     :config config
     :genesis-block genesis-block
     :service service
     :public-service public-service
     :telemetry-sink telemetry-sink
     :jwt-secret-path jwt-secret-path
     :log-path log-path)))

(defun devnet-block-number (block)
  (and block (block-header-number (block-header block))))

(defun devnet-block-hash-hex (block)
  (and block (hash32-to-hex (block-hash block))))

(defun devnet-node-summary (node &key engine-endpoint rpc-endpoint)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let* ((store (devnet-node-store node))
         (head (chain-store-latest-block store))
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
          :auth-required-p
          (not (null (engine-rpc-http-service-jwt-secret
                      (devnet-node-service node))))
          :jwt-secret-path (devnet-node-jwt-secret-path node)
          :log-path (devnet-node-log-path node)
          :chain-id (chain-config-chain-id (devnet-node-config node))
          :head-number (devnet-block-number head)
          :head-hash (devnet-block-hash-hex head)
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
      ("authRequired" . ,(if (getf summary :auth-required-p) t :false))
      ("jwtSecretPath" . ,(getf summary :jwt-secret-path))
      ("logPath" . ,(getf summary :log-path))
      ("chainId" . ,(getf summary :chain-id))
      ("headNumber" . ,(getf summary :head-number))
      ("headHash" . ,(getf summary :head-hash))
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
        (public-host nil)
        (public-port +devnet-default-public-rpc-port+)
        (jwt-secret-path nil)
        (max-connections nil)
        (serve-p t)
        (summary-format :sexp)
        (ready-file nil)
        (log-file nil)
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
                  (devnet-cli-next-value args option)))
               ((string= option "--port")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf port (devnet-cli-parse-port value option)
                        args rest)))
               ((string= option "--public-host")
                (multiple-value-setq (public-host args)
                  (devnet-cli-next-value args option)))
               ((string= option "--public-port")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf public-port (devnet-cli-parse-port value option)
                        args rest)))
               ((string= option "--jwt-secret")
                (multiple-value-setq (jwt-secret-path args)
                  (devnet-cli-next-value args option)))
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
               (t
                (error "Unknown option ~A" option))))
    (list :genesis-path genesis-path
          :host host
          :port port
          :public-host (or public-host host)
          :public-port public-port
          :jwt-secret-path jwt-secret-path
          :max-connections max-connections
          :serve-p serve-p
          :summary-format summary-format
          :ready-file ready-file
          :log-file log-file
          :help-p help-p)))

(defun devnet-cli-print-usage (stream)
  (format stream
          "Usage: ethereum-lisp devnet --genesis PATH [--host HOST] [--port PORT] [--public-host HOST] [--public-port PORT] [--jwt-secret PATH] [--max-connections N] [--json] [--ready-file PATH] [--log-file PATH] [--no-serve]~%"))

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

(defun devnet-node-telemetry-fields
    (node &key engine-endpoint rpc-endpoint)
  (let ((summary (devnet-node-summary
                  node
                  :engine-endpoint engine-endpoint
                  :rpc-endpoint rpc-endpoint)))
    `(("engineEndpoint" . ,(getf summary :engine-endpoint))
      ("rpcEndpoint" . ,(getf summary :rpc-endpoint))
      ("chainId" . ,(quantity-to-hex (getf summary :chain-id)))
      ("headNumber" . ,(quantity-to-hex (getf summary :head-number)))
      ("headHash" . ,(getf summary :head-hash))
      ("authRequired" . ,(if (getf summary :auth-required-p) "true" "false"))
      ("jwtSecretPath" . ,(or (getf summary :jwt-secret-path) ""))
      ("logPath" . ,(or (getf summary :log-path) "")))))

(defun devnet-cli-log-event (node name &key engine-endpoint rpc-endpoint)
  (ethereum-lisp.telemetry:telemetry-log
   :info
   name
   :sink (devnet-node-telemetry-sink node)
   :fields (devnet-node-telemetry-fields
            node
            :engine-endpoint engine-endpoint
            :rpc-endpoint rpc-endpoint)))

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
                          :telemetry-sink telemetry-sink)))
                   (if (getf options :serve-p)
                       (let ((bound-engine-endpoint nil)
                             (bound-rpc-endpoint nil))
                         (unwind-protect
                              (start-devnet-node
                               node
                               :max-connections (getf options :max-connections)
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
                                  :rpc-endpoint bound-rpc-endpoint)))
                           (when (getf options :log-file)
                             (devnet-cli-log-event
                              node
                              "devnet.shutdown"
                              :engine-endpoint bound-engine-endpoint
                              :rpc-endpoint bound-rpc-endpoint))))
                       (progn
                         (when (getf options :ready-file)
                           (devnet-cli-write-ready-file
                            node
                            (getf options :ready-file)))
                         (when (getf options :log-file)
                           (devnet-cli-log-event node "devnet.ready"))
                         (devnet-cli-print-summary
                          node
                          output-stream
                          :format (getf options :summary-format))))
                   0))))))
    (error (condition)
      (format error-stream "~A~%" condition)
      (devnet-cli-print-usage error-stream)
      1)))
