(in-package #:ethereum-lisp.cli)

(define-condition devnet-cli-usage-error (error)
  ((cause :initarg :cause :reader devnet-cli-usage-error-cause))
  (:report
   (lambda (condition stream)
     (princ (devnet-cli-usage-error-cause condition) stream))))

(defun devnet-cli-parse-options-or-usage-error (parser args)
  (handler-case
      (funcall parser args)
    (error (condition)
      (error 'devnet-cli-usage-error :cause condition))))

(defun devnet-cli-main-arguments (arguments)
  (let ((args (uiop:command-line-arguments))
        (output-stream *standard-output*)
        (error-stream *error-output*))
    (when (and arguments (not (keywordp (first arguments))))
      (setf args (pop arguments)))
    (loop while arguments
          for key = (pop arguments)
          do (unless (keywordp key)
               (error "Unexpected main argument ~A" key))
             (when (null arguments)
               (error "Missing value for main option ~A" key))
             (let ((value (pop arguments)))
               (ecase key
                 (:output-stream
                  (setf output-stream value))
                 (:error-stream
                  (setf error-stream value)))))
    (values args output-stream error-stream)))

(defun devnet-cli-make-node (options genesis-path genesis-json telemetry-sink)
  (make-devnet-node
   :genesis-path genesis-path
   :genesis-json genesis-json
   :genesis-preset (getf options :genesis-preset)
   :dev-mode-p (getf options :dev-mode-p)
   :host (getf options :host)
   :port (getf options :port)
   :public-host (getf options :public-host)
   :public-port (getf options :public-port)
   :jwt-secret-path (getf options :jwt-secret-path)
   :engine-rpc-prefix (getf options :engine-rpc-prefix)
   :public-rpc-prefix (getf options :public-rpc-prefix)
   :log-path (getf options :log-file)
   :database-path (getf options :database-path)
   :db-engine (or (getf options :db-engine) :file)
   :pid-file-path (getf options :pid-file)
   :network-id (getf options :network-id)
   :public-api-modules (getf options :http-api-modules)
   :engine-cors-origins (getf options :authrpc-cors-origins)
   :public-cors-origins (getf options :http-cors-origins)
   :engine-vhosts (getf options :engine-vhosts)
   :public-vhosts (getf options :http-vhosts)
   :terminal-total-difficulty (getf options :terminal-total-difficulty)
   :terminal-total-difficulty-passed
   (getf options :terminal-total-difficulty-passed)
   :terminal-total-difficulty-passed-specified-p
   (getf options :terminal-total-difficulty-passed-specified-p)
   :terminal-block-hash (getf options :terminal-block-hash)
   :terminal-block-number (getf options :terminal-block-number)
   :dev-period-seconds (getf options :dev-period-seconds)
   :miner-gas-limit (getf options :miner-gas-limit)
   :coinbase (getf options :coinbase)
   :allow-unprotected-transactions-p
   (getf options :allow-unprotected-transactions-p)
   :txpool-price-limit (getf options :txpool-price-limit)
   :txpool-price-bump-percent (getf options :txpool-price-bump-percent)
   :txpool-account-slot-limit (getf options :txpool-account-slot-limit)
   :txpool-global-slot-limit (getf options :txpool-global-slot-limit)
   :txpool-account-queue-limit (getf options :txpool-account-queue-limit)
   :txpool-global-queue-limit (getf options :txpool-global-queue-limit)
   :txpool-local-addresses (getf options :txpool-local-addresses)
   :txpool-no-local-exemptions-p (getf options :txpool-no-local-exemptions-p)
   :txpool-lifetime-seconds (getf options :txpool-lifetime-seconds)
   :txpool-journal-path (getf options :txpool-journal-path)
   :txpool-rejournal-seconds (getf options :txpool-rejournal-seconds)
   :peers (getf options :peers)
   :bootnodes (getf options :bootnodes)
   :node-key (getf options :node-key)
   :p2p-port (getf options :p2p-port)
   :max-peers (getf options :max-peers)
   :metrics (getf options :metrics)
   :metrics-host (getf options :metrics-host)
   :metrics-port (getf options :metrics-port)
   :ws-enabled-p (getf options :ws-enabled-p)
   :ws-host (getf options :ws-host)
   :ws-port (getf options :ws-port)
   :ws-origins (getf options :ws-origins)
   :ws-rpc-prefix (getf options :ws-rpc-prefix)
   :public-allowed-method-p
   (devnet-cli-public-api-method-filter (getf options :http-api-modules))
   :telemetry-sink telemetry-sink))

(defun devnet-cli-export-node-database (node options)
  (devnet-node-export-database
   node
   :state-prune-before (getf options :state-prune-before)))

(defun devnet-cli-log-event-when-enabled (node options name &rest arguments)
  (when (getf options :log-file)
    (apply #'devnet-cli-log-event node name arguments)))

(defun devnet-cli-run-no-serve-node (node options output-stream)
  (devnet-cli-export-node-database node options)
  (when (getf options :ready-file)
    (devnet-cli-write-ready-file
     node
     (getf options :ready-file)
     :public-rpc-enabled-p (getf options :public-rpc-enabled-p)))
  (devnet-cli-log-event-when-enabled
   node
   options
   "devnet.ready"
   :public-rpc-enabled-p (getf options :public-rpc-enabled-p))
  (devnet-cli-print-summary
   node
   output-stream
   :format (getf options :summary-format)
   :public-rpc-enabled-p (getf options :public-rpc-enabled-p))
  (devnet-cli-log-event-when-enabled
   node
   options
   "devnet.shutdown"
   :public-rpc-enabled-p (getf options :public-rpc-enabled-p)))

(defun devnet-cli-run-serve-node (node options output-stream error-stream)
  (let ((bound-engine-endpoint nil)
        (bound-rpc-endpoint nil)
        (ready-p nil)
        (serve-summary nil))
    (unwind-protect
         (setf serve-summary
               (start-devnet-node
                node
                :max-connections (getf options :max-connections)
                :install-signal-handlers-p t
                :signal-stream error-stream
                :on-listeners-ready
                (lambda (engine-listener public-listener)
                  (setf bound-engine-endpoint
                        (engine-rpc-http-listener-endpoint engine-listener)
                        bound-rpc-endpoint
                        (and public-listener
                             (engine-rpc-http-listener-endpoint
                              public-listener)))
                  (when (getf options :ready-file)
                    (devnet-cli-write-ready-file
                     node
                     (getf options :ready-file)
                     :engine-endpoint bound-engine-endpoint
                     :rpc-endpoint bound-rpc-endpoint
                     :public-rpc-enabled-p
                     (getf options :public-rpc-enabled-p)))
                  (devnet-cli-log-event-when-enabled
                   node
                   options
                   "devnet.ready"
                   :engine-endpoint bound-engine-endpoint
                   :rpc-endpoint bound-rpc-endpoint
                   :public-rpc-enabled-p (getf options :public-rpc-enabled-p))
                  (setf ready-p t)
                  (devnet-cli-print-summary
                   node
                   output-stream
                   :format (getf options :summary-format)
                   :engine-endpoint bound-engine-endpoint
                   :rpc-endpoint bound-rpc-endpoint
                   :public-rpc-enabled-p (getf options :public-rpc-enabled-p)))
                :public-rpc-enabled-p (getf options :public-rpc-enabled-p)))
      (devnet-cli-export-node-database node options)
      (when (or ready-p serve-summary)
        (devnet-cli-log-event-when-enabled
         node
         options
         "devnet.shutdown"
         :engine-endpoint bound-engine-endpoint
         :rpc-endpoint bound-rpc-endpoint
         :public-rpc-enabled-p (getf options :public-rpc-enabled-p)
         :connection-summary serve-summary)))))

(defun devnet-cli-run (args output-stream error-stream)
  (handler-case
      (cond
        ((devnet-cli-top-level-help-p args)
         (devnet-cli-print-top-level-help output-stream)
         0)
        ((devnet-cli-top-level-version-p args)
         (devnet-cli-print-version output-stream)
         0)
        ((devnet-cli-init-command-p args)
         (let ((options
                 (devnet-cli-parse-options-or-usage-error
                  #'devnet-cli-init-options args)))
           (if (getf options :help-p)
               (progn
                 (devnet-cli-print-init-usage output-stream)
                 0)
               (progn
                 (devnet-cli-run-init options output-stream)
                 0))))
        ((devnet-cli-db-command-p args)
         (let ((options
                 (devnet-cli-parse-options-or-usage-error
                  #'devnet-cli-db-options args)))
           (if (getf options :help-p)
               (progn
                 (devnet-cli-print-db-usage output-stream)
                 0)
               (devnet-cli-run-db options output-stream))))
        (t
         (let ((options
                 (devnet-cli-apply-chain-preset
                  (devnet-cli-parse-options-or-usage-error
                   #'devnet-cli-options args))))
           (devnet-cli-report-ignored-options options error-stream)
           (if (getf options :help-p)
               (progn
                 (devnet-cli-print-usage output-stream)
                 0)
               (let* ((genesis-preset (getf options :genesis-preset))
                      (genesis-path
                        (unless genesis-preset
                          (devnet-cli-resolve-genesis-path options)))
                      (genesis-json
                        (devnet-cli-resolve-genesis-json
                         options genesis-path)))
                 (unless (or genesis-path genesis-json genesis-preset)
                   (error
                    'devnet-cli-usage-error
                    :cause
                    "--genesis is required unless --datadir contains an initialized genesis, --dev is enabled, or a public network preset is selected"))
                 (call-with-devnet-cli-datadir-lock
                  (getf options :datadir-path)
                  (lambda ()
                    (call-with-devnet-cli-telemetry-sink
                     options
                     output-stream
                     (lambda (telemetry-sink)
                    (call-with-devnet-cli-kzg-verifier
                     (lambda ()
                       (call-with-devnet-cli-bls12381-backend
                        (lambda ()
                          (call-with-devnet-cli-http-limits
                           options
                           (lambda ()
                             ;; Innermost, so the node's import, every
                             ;; persist, and the shutdown export all share one
                             ;; open handle per artifact.
                             (call-with-devnet-cli-kv-database-cache
                              (lambda ()
                                (let ((node
                                        (devnet-cli-make-node
                                         options genesis-path genesis-json
                                         telemetry-sink)))
                                  (when (getf options :pid-file)
                                    (devnet-cli-write-pid-file
                                     (getf options :pid-file)))
                                  (if (getf options :serve-p)
                                      (devnet-cli-run-serve-node
                                       node options output-stream error-stream)
                                      (devnet-cli-run-no-serve-node
                                       node options output-stream))
                                  0))))))))))))))))))
    (devnet-cli-usage-error (condition)
      (ignore-errors
       (devnet-cli-log-error-event args condition))
      (format error-stream "~A~%" condition)
      (cond
        ((devnet-cli-init-command-p args)
         (devnet-cli-print-init-usage error-stream))
        ((devnet-cli-db-command-p args)
         (devnet-cli-print-db-usage error-stream))
        (t
         (devnet-cli-print-usage error-stream)))
      1)
    (error (condition)
      (ignore-errors
       (devnet-cli-log-error-event args condition))
      (format error-stream "~A~%" condition)
      1)))

(defun main (&rest arguments)
  (multiple-value-bind (args output-stream error-stream)
      (devnet-cli-main-arguments arguments)
    (devnet-cli-run args output-stream error-stream)))
