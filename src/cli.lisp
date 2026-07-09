(in-package #:ethereum-lisp.cli)

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
         (let ((options (devnet-cli-init-options args)))
           (if (getf options :help-p)
               (progn
                 (devnet-cli-print-init-usage output-stream)
                 0)
               (progn
                 (devnet-cli-run-init options output-stream)
                 0))))
        (t
         (let ((options (devnet-cli-options args)))
           (if (getf options :help-p)
               (progn
                 (devnet-cli-print-usage output-stream)
                 0)
               (let* ((genesis-path (devnet-cli-resolve-genesis-path options))
                      (genesis-json
                        (devnet-cli-resolve-genesis-json
                         options genesis-path)))
                 (unless (or genesis-path genesis-json)
                   (error "--genesis is required unless --datadir contains an initialized genesis or --dev is enabled"))
                 (call-with-devnet-cli-telemetry-sink
                  options
                  output-stream
                  (lambda (telemetry-sink)
                    (call-with-devnet-cli-kzg-verifier
                     (getf options :kzg-verifier-command)
                     (getf options :kzg-verifier-timeout-seconds)
                     (lambda ()
                       (let ((node
                               (make-devnet-node
                                :genesis-path genesis-path
                                :genesis-json genesis-json
                                :dev-mode-p (and genesis-json
                                                 (getf options :dev-mode-p))
                                :host (getf options :host)
                                :port (getf options :port)
                                :public-host (getf options :public-host)
                                :public-port (getf options :public-port)
                                :jwt-secret-path (getf options :jwt-secret-path)
                                :engine-rpc-prefix
                                (getf options :engine-rpc-prefix)
                                :public-rpc-prefix
                                (getf options :public-rpc-prefix)
                                :log-path (getf options :log-file)
                                :database-path (getf options :database-path)
                                :pid-file-path (getf options :pid-file)
                                :network-id (getf options :network-id)
                                :public-api-modules
                                (getf options :http-api-modules)
                                :engine-cors-origins
                                (getf options :authrpc-cors-origins)
                                :public-cors-origins
                                (getf options :http-cors-origins)
                                :engine-vhosts
                                (getf options :engine-vhosts)
                                :public-vhosts
                                (getf options :http-vhosts)
                                :terminal-total-difficulty
                                (getf options :terminal-total-difficulty)
                                :terminal-total-difficulty-passed
                                (getf options
                                      :terminal-total-difficulty-passed)
                                :terminal-total-difficulty-passed-specified-p
                                (getf options
                                      :terminal-total-difficulty-passed-specified-p)
                                :terminal-block-hash
                                (getf options :terminal-block-hash)
                                :terminal-block-number
                                (getf options :terminal-block-number)
                                :dev-mode-p (getf options :dev-mode-p)
                                :dev-period-seconds
                                (getf options :dev-period-seconds)
                                :coinbase (getf options :coinbase)
                                :allow-unprotected-transactions-p
                                (getf options
                                      :allow-unprotected-transactions-p)
                                :txpool-price-limit
                                (getf options :txpool-price-limit)
                                :txpool-price-bump-percent
                                (getf options :txpool-price-bump-percent)
                                :txpool-account-slot-limit
                                (getf options :txpool-account-slot-limit)
                                :txpool-global-slot-limit
                                (getf options :txpool-global-slot-limit)
                                :txpool-account-queue-limit
                                (getf options :txpool-account-queue-limit)
                                :txpool-global-queue-limit
                                (getf options :txpool-global-queue-limit)
                                :txpool-local-addresses
                                (getf options :txpool-local-addresses)
                                :txpool-no-local-exemptions-p
                                (getf options :txpool-no-local-exemptions-p)
                                :txpool-lifetime-seconds
                                (getf options :txpool-lifetime-seconds)
                                :txpool-journal-path
                                (getf options :txpool-journal-path)
                                :txpool-rejournal-seconds
                                (getf options :txpool-rejournal-seconds)
                                :kzg-verifier-command
                                (getf options :kzg-verifier-command)
                                :kzg-verifier-timeout-seconds
                                (getf options
                                      :kzg-verifier-timeout-seconds)
                                :public-allowed-method-p
                                (devnet-cli-public-api-method-filter
                                 (getf options :http-api-modules))
                                :telemetry-sink telemetry-sink)))
                         (when (getf options :pid-file)
                           (devnet-cli-write-pid-file
                            (getf options :pid-file)))
                         (if (getf options :serve-p)
                             (let ((bound-engine-endpoint nil)
                                   (bound-rpc-endpoint nil)
                                   (ready-p nil)
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
                                              (and public-listener
                                                   (engine-rpc-http-listener-endpoint
                                                    public-listener)))
                                        (when (getf options :ready-file)
                                          (devnet-cli-write-ready-file
                                           node
                                           (getf options :ready-file)
                                           :engine-endpoint
                                           bound-engine-endpoint
                                           :rpc-endpoint bound-rpc-endpoint
                                           :public-rpc-enabled-p
                                           (getf options
                                                 :public-rpc-enabled-p)))
                                        (when (getf options :log-file)
                                          (devnet-cli-log-event
                                           node
                                           "devnet.ready"
                                           :engine-endpoint
                                           bound-engine-endpoint
                                           :rpc-endpoint bound-rpc-endpoint
                                           :public-rpc-enabled-p
                                           (getf options
                                                 :public-rpc-enabled-p)))
                                        (setf ready-p t)
                                        (devnet-cli-print-summary
                                         node
                                         output-stream
                                         :format
                                         (getf options :summary-format)
                                         :engine-endpoint
                                         bound-engine-endpoint
                                         :rpc-endpoint bound-rpc-endpoint
                                         :public-rpc-enabled-p
                                         (getf options
                                               :public-rpc-enabled-p)))
                                      :public-rpc-enabled-p
                                      (getf options :public-rpc-enabled-p)))
                                 (devnet-node-export-database
                                  node
                                  :state-prune-before
                                  (getf options :state-prune-before))
                                 (when (and (getf options :log-file)
                                            (or ready-p serve-summary))
                                   (devnet-cli-log-event
                                    node
                                    "devnet.shutdown"
                                    :engine-endpoint bound-engine-endpoint
                                    :rpc-endpoint bound-rpc-endpoint
                                    :public-rpc-enabled-p
                                    (getf options :public-rpc-enabled-p)
                                    :connection-summary serve-summary))))
                             (progn
                               (devnet-node-export-database
                                node
                                :state-prune-before
                                (getf options :state-prune-before))
                               (when (getf options :ready-file)
                                 (devnet-cli-write-ready-file
                                  node
                                  (getf options :ready-file)
                                  :public-rpc-enabled-p
                                  (getf options :public-rpc-enabled-p)))
                               (when (getf options :log-file)
                                 (devnet-cli-log-event
                                  node
                                  "devnet.ready"
                                  :public-rpc-enabled-p
                                  (getf options :public-rpc-enabled-p)))
                               (devnet-cli-print-summary
                                node
                                output-stream
                                :format (getf options :summary-format)
                                :public-rpc-enabled-p
                                (getf options :public-rpc-enabled-p))
                               (when (getf options :log-file)
                                 (devnet-cli-log-event
                                  node
                                  "devnet.shutdown"
                                  :public-rpc-enabled-p
                                  (getf options :public-rpc-enabled-p)))))
                         0))))))))))
    (error (condition)
      (ignore-errors
       (devnet-cli-log-error-event args condition))
      (format error-stream "~A~%" condition)
      (if (devnet-cli-init-command-p args)
          (devnet-cli-print-init-usage error-stream)
          (devnet-cli-print-usage error-stream))
      1)))

(defun main (&rest arguments)
  (multiple-value-bind (args output-stream error-stream)
      (devnet-cli-main-arguments arguments)
    (devnet-cli-run args output-stream error-stream)))
