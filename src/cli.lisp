(in-package #:ethereum-lisp.cli)

(defstruct (devnet-node
            (:constructor %make-devnet-node
                (&key genesis-path store config genesis-block service
                      public-service telemetry-sink jwt-secret-path)))
  genesis-path
  store
  config
  genesis-block
  service
  public-service
  telemetry-sink
  jwt-secret-path)

(defconstant +devnet-default-public-rpc-port+ 8545)

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
     :jwt-secret-path jwt-secret-path)))

(defun devnet-block-number (block)
  (and block (block-header-number (block-header block))))

(defun devnet-block-hash-hex (block)
  (and block (hash32-to-hex (block-hash block))))

(defun devnet-node-summary (node)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let* ((store (devnet-node-store node))
         (head (chain-store-latest-block store))
         (engine-endpoint (engine-rpc-http-service-endpoint
                           (devnet-node-service node)))
         (rpc-endpoint (engine-rpc-http-service-endpoint
                        (devnet-node-public-service node))))
    (list :genesis-path (devnet-node-genesis-path node)
          :engine-endpoint engine-endpoint
          :rpc-endpoint rpc-endpoint
          :auth-required-p
          (not (null (engine-rpc-http-service-jwt-secret
                      (devnet-node-service node))))
          :jwt-secret-path (devnet-node-jwt-secret-path node)
          :chain-id (chain-config-chain-id (devnet-node-config node))
          :head-number (devnet-block-number head)
          :head-hash (devnet-block-hash-hex head)
          :state-available-p
          (and head
               (chain-store-state-available-p store (block-hash head))))))

(defun devnet-node-summary-json-object (node)
  (let ((summary (devnet-node-summary node)))
    `(("genesisPath" . ,(getf summary :genesis-path))
      ("engineEndpoint" . ,(getf summary :engine-endpoint))
      ("rpcEndpoint" . ,(getf summary :rpc-endpoint))
      ("authRequired" . ,(if (getf summary :auth-required-p) t :false))
      ("jwtSecretPath" . ,(getf summary :jwt-secret-path))
      ("chainId" . ,(getf summary :chain-id))
      ("headNumber" . ,(getf summary :head-number))
      ("headHash" . ,(getf summary :head-hash))
      ("stateAvailable" . ,(if (getf summary :state-available-p) t :false)))))

(defun start-devnet-node-listeners
    (node engine-listener public-listener &key max-connections stop-p)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (unless (typep engine-listener 'engine-rpc-http-listener)
    (error "Devnet Engine listener must be engine-rpc-http-listener"))
  (unless (typep public-listener 'engine-rpc-http-listener)
    (error "Devnet public listener must be engine-rpc-http-listener"))
  #-sbcl
  (declare (ignore node engine-listener public-listener max-connections stop-p))
  #-sbcl
  (error "Devnet split listener serving requires SBCL threads")
  #+sbcl
  (let ((engine-count nil)
        (engine-error nil)
        (public-count nil)
        (public-error nil))
    (let ((engine-thread
            (sb-thread:make-thread
             (lambda ()
               (handler-case
                   (setf engine-count
                         (engine-rpc-http-service-serve-listener
                          (devnet-node-service node)
                          engine-listener
                          :max-connections max-connections
                          :stop-p stop-p))
                 (error (condition)
                   (setf engine-error condition)
                   (ignore-errors
                    (engine-rpc-http-listener-close public-listener)))))
             :name "ethereum-lisp-devnet-engine-rpc")))
      (handler-case
          (setf public-count
                (engine-rpc-http-service-serve-listener
                 (devnet-node-public-service node)
                 public-listener
                 :max-connections max-connections
                 :stop-p stop-p))
        (error (condition)
          (setf public-error condition)
          (ignore-errors
           (engine-rpc-http-listener-close engine-listener))))
      (when public-count
        (ignore-errors
         (engine-rpc-http-listener-close engine-listener)))
      (sb-thread:join-thread engine-thread)
      (cond
        (public-error (error public-error))
        (engine-error (error engine-error))
        (t
         (list :engine-connections engine-count
               :public-connections public-count
               :total-connections (+ engine-count public-count)))))))

(defun start-devnet-node (node &key max-connections stop-p)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let ((engine-listener nil)
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
               (start-devnet-node-listeners
                node
                engine-listener
                public-listener
                :max-connections max-connections
                :stop-p stop-p)
             (setf served-p t)))
      (unless served-p
        (when engine-listener
          (ignore-errors (engine-rpc-http-listener-close engine-listener)))
        (when public-listener
          (ignore-errors (engine-rpc-http-listener-close public-listener)))))))

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
          :help-p help-p)))

(defun devnet-cli-print-usage (stream)
  (format stream
          "Usage: ethereum-lisp devnet --genesis PATH [--host HOST] [--port PORT] [--public-host HOST] [--public-port PORT] [--jwt-secret PATH] [--max-connections N] [--json] [--ready-file PATH] [--no-serve]~%"))

(defun devnet-cli-print-summary (node stream &key (format :sexp))
  (ecase format
    (:sexp (write (devnet-node-summary node) :stream stream :pretty nil))
    (:json (write-string (json-encode (devnet-node-summary-json-object node))
                         stream)))
  (terpri stream))

(defun devnet-cli-write-ready-file (node path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string (json-encode (devnet-node-summary-json-object node)) stream)
    (terpri stream)))

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
              (let ((node
                      (make-devnet-node
                       :genesis-path (getf options :genesis-path)
                       :host (getf options :host)
                       :port (getf options :port)
                       :public-host (getf options :public-host)
                       :public-port (getf options :public-port)
                       :jwt-secret-path (getf options :jwt-secret-path)
                       :telemetry-sink
                       (ethereum-lisp.telemetry:make-stream-telemetry-sink
                        :stream output-stream))))
                (when (getf options :ready-file)
                  (devnet-cli-write-ready-file
                   node
                   (getf options :ready-file)))
                (devnet-cli-print-summary
                 node
                 output-stream
                 :format (getf options :summary-format))
                (when (getf options :serve-p)
                  (start-devnet-node
                   node
                   :max-connections (getf options :max-connections)))
                0))))
    (error (condition)
      (format error-stream "~A~%" condition)
      (devnet-cli-print-usage error-stream)
      1)))
