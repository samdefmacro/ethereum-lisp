(in-package #:ethereum-lisp.cli)

(defun devnet-cli-reject-malformed-init-json-assignment (args)
  (dolist (arg args)
    (let ((separator
            (and (devnet-cli-option-token-p arg)
                 (position #\= arg :start 2))))
      (when (and separator
                 (string= "--json" arg :end2 separator))
        (let ((value (subseq arg (1+ separator))))
          (unless (devnet-cli-boolean-token-p value)
            (devnet-cli-parse-boolean-token value "--json")))))))

(defun devnet-cli-init-options (args)
  (devnet-cli-reject-malformed-init-json-assignment args)
  (setf args (devnet-cli-remove-command-token args "init"))
  (setf args (devnet-cli-normalize-option-args args))
  (setf args (devnet-cli-apply-config-args args))
  (let ((genesis-path nil)
        (database-path nil)
        (datadir-path nil)
        (jwt-secret-path nil)
        (ready-file nil)
        (log-file nil)
        (pid-file nil)
        (summary-format :sexp)
        (help-p nil))
    (loop while args
          for option = (pop args)
          do (cond
               ((string= option "--help")
                (setf help-p t))
               ((string= option "--genesis")
                (multiple-value-setq (genesis-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--database")
                (multiple-value-setq (database-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--datadir")
                (multiple-value-setq (datadir-path args)
                  (devnet-cli-next-value args option)))
               ((or (string= option "--jwt-secret")
                    (string= option "--authrpc.jwtsecret"))
                (multiple-value-setq (jwt-secret-path args)
                  (devnet-cli-next-value args option)))
               ((string= option "--ready-file")
                (multiple-value-setq (ready-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--log-file")
                (multiple-value-setq (log-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--pid-file")
                (multiple-value-setq (pid-file args)
                  (devnet-cli-next-value args option)))
               ((string= option "--json")
                (setf summary-format :json)
                (when (and args
                           (not (devnet-cli-option-token-p (first args)))
                           (devnet-cli-boolean-token-p (first args)))
                  (let ((enabled-p
                          (devnet-cli-parse-boolean-token
                           (first args)
                           option)))
                    (setf summary-format (if enabled-p :json :sexp)))
                  (setf args (rest args))))
               ((member option *devnet-cli-value-options* :test #'string=)
                (setf args (devnet-cli-consume-value-option args option)))
               ((member option *devnet-cli-optional-boolean-options*
                        :test #'string=)
                (setf args
                      (devnet-cli-consume-optional-boolean-value
                       args
                       option)))
               ((devnet-cli-option-token-p option)
                (error "Unknown option ~A" option))
               ((null genesis-path)
                (setf genesis-path option))
               (t
                (error "Unexpected init argument ~A" option))))
    (list :genesis-path genesis-path
          :datadir-path datadir-path
          :database-path (or database-path
                             (and datadir-path
                                  (devnet-cli-datadir-database-path
                                   datadir-path)))
          :jwt-secret-path jwt-secret-path
          :ready-file ready-file
          :log-file log-file
          :pid-file pid-file
          :summary-format summary-format
          :help-p help-p)))

(defun devnet-cli-resolve-genesis-path (options)
  (or (getf options :genesis-path)
      (let ((datadir-path (getf options :datadir-path)))
        (when datadir-path
          (let ((stored-genesis
                  (devnet-cli-datadir-genesis-path datadir-path)))
            (and (probe-file stored-genesis)
                 (namestring (truename stored-genesis))))))))

(defun devnet-cli-resolve-genesis-json (options genesis-path)
  (when (and (getf options :dev-mode-p)
             (null genesis-path))
    (devnet-cli-dev-genesis-json
     :gas-limit (or (getf options :dev-gas-limit)
                    (getf options :miner-gas-limit)
                    +devnet-default-dev-gas-limit+)
     :coinbase (getf options :coinbase))))

(defun devnet-cli-print-init-usage (stream)
  (format stream
          "Usage: ethereum-lisp init --datadir PATH [--database PATH] [runner options] [--json] GENESIS~%"))

(defun devnet-cli-run-init (options output-stream)
  (let ((genesis-path (getf options :genesis-path))
        (datadir-path (getf options :datadir-path))
        (database-path (getf options :database-path))
        (explicit-jwt-secret-path (getf options :jwt-secret-path))
        (jwt-secret-path nil))
    (unless genesis-path
      (error "init requires a genesis file"))
    (unless database-path
      (error "init requires --datadir or --database"))
    (when datadir-path
      (devnet-cli-copy-file-string
       genesis-path
       (devnet-cli-datadir-genesis-path datadir-path))
      (setf jwt-secret-path
            (devnet-cli-ensure-datadir-jwt-secret
             datadir-path
             :source-path explicit-jwt-secret-path)))
    (call-with-devnet-cli-telemetry-sink
     options
     output-stream
     (lambda (telemetry-sink)
       (let ((node
               (make-devnet-node
                :genesis-path genesis-path
                :database-path database-path
                :jwt-secret-path jwt-secret-path
                :log-path (getf options :log-file)
                :pid-file-path (getf options :pid-file)
                :telemetry-sink telemetry-sink)))
         (when (getf options :pid-file)
           (devnet-cli-write-pid-file (getf options :pid-file)))
         (devnet-node-export-database node)
         (when (getf options :ready-file)
           (devnet-cli-write-ready-file
            node
            (getf options :ready-file)))
         (when (getf options :log-file)
           (devnet-cli-log-event node "init.ready"))
         (devnet-cli-print-summary
          node
          output-stream
          :format (getf options :summary-format))
         (when (getf options :log-file)
           (devnet-cli-log-event node "init.shutdown")))))))
