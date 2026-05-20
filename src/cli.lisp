(in-package #:ethereum-lisp.cli)

(defstruct (devnet-node
            (:constructor %make-devnet-node
                (&key genesis-path store config genesis-block service
                      telemetry-sink)))
  genesis-path
  store
  config
  genesis-block
  service
  telemetry-sink)

(defun make-devnet-node
    (&key
       genesis-path
       (host "127.0.0.1")
       (port +engine-rpc-default-http-port+)
       (telemetry-sink ethereum-lisp.telemetry:*telemetry-sink*))
  (unless (and genesis-path (stringp genesis-path))
    (error "Devnet node requires a genesis JSON path"))
  (let* ((config (chain-config-from-genesis-json-file genesis-path))
         (state (state-db-from-genesis-json-file genesis-path))
         (genesis-block
           (genesis-block-from-state-genesis-json-file genesis-path
                                                       :config config))
         (store (make-engine-payload-memory-store))
         (service
           (make-engine-rpc-http-service
            :host host
            :port port
            :store store
            :config config
            :telemetry-sink telemetry-sink)))
    (chain-store-put-block store genesis-block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis-block) state)
    (%make-devnet-node
     :genesis-path genesis-path
     :store store
     :config config
     :genesis-block genesis-block
     :service service
     :telemetry-sink telemetry-sink)))

(defun devnet-block-number (block)
  (and block (block-header-number (block-header block))))

(defun devnet-block-hash-hex (block)
  (and block (hash32-to-hex (block-hash block))))

(defun devnet-node-summary (node)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let* ((store (devnet-node-store node))
         (head (chain-store-latest-block store))
         (endpoint (engine-rpc-http-service-endpoint
                    (devnet-node-service node))))
    (list :genesis-path (devnet-node-genesis-path node)
          :engine-endpoint endpoint
          :rpc-endpoint endpoint
          :chain-id (chain-config-chain-id (devnet-node-config node))
          :head-number (devnet-block-number head)
          :head-hash (devnet-block-hash-hex head)
          :state-available-p
          (and head
               (chain-store-state-available-p store (block-hash head))))))

(defun start-devnet-node (node &key max-connections stop-p)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let* ((service (devnet-node-service node))
         (listener (make-engine-rpc-http-socket-listener service)))
    (engine-rpc-http-service-serve-listener
     service
     listener
     :max-connections max-connections
     :stop-p stop-p)))

(defun devnet-cli-next-value (args option)
  (unless args
    (error "~A requires a value" option))
  (values (first args) (rest args)))

(defun devnet-cli-parse-integer (value option)
  (handler-case
      (parse-integer value :junk-allowed nil)
    (error ()
      (error "~A requires an integer value" option))))

(defun devnet-cli-options (args)
  (when (and args (string= "devnet" (first args)))
    (setf args (rest args)))
  (let ((genesis-path nil)
        (host "127.0.0.1")
        (port +engine-rpc-default-http-port+)
        (max-connections nil)
        (serve-p t)
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
                  (setf port (devnet-cli-parse-integer value option)
                        args rest)))
               ((string= option "--max-connections")
                (multiple-value-bind (value rest)
                    (devnet-cli-next-value args option)
                  (setf max-connections
                        (devnet-cli-parse-integer value option)
                        args rest)))
               ((string= option "--no-serve")
                (setf serve-p nil))
               (t
                (error "Unknown option ~A" option))))
    (list :genesis-path genesis-path
          :host host
          :port port
          :max-connections max-connections
          :serve-p serve-p
          :help-p help-p)))

(defun devnet-cli-print-usage (stream)
  (format stream
          "Usage: ethereum-lisp devnet --genesis PATH [--host HOST] [--port PORT] [--max-connections N] [--no-serve]~%"))

(defun devnet-cli-print-summary (node stream)
  (write (devnet-node-summary node) :stream stream :pretty nil)
  (terpri stream))

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
                       :telemetry-sink
                       (ethereum-lisp.telemetry:make-stream-telemetry-sink
                        :stream output-stream))))
                (devnet-cli-print-summary node output-stream)
                (when (getf options :serve-p)
                  (start-devnet-node
                   node
                   :max-connections (getf options :max-connections)))
                0))))
    (error (condition)
      (format error-stream "~A~%" condition)
      (devnet-cli-print-usage error-stream)
      1)))
