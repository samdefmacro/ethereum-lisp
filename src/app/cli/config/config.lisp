(in-package #:ethereum-lisp.cli)

;;;; Geth-style TOML config conversion into devnet CLI options.

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
                (setf args (devnet-cli-consume-present-value args)))
               ((member option *devnet-cli-optional-boolean-options*
                        :test #'string=)
                (setf args
                      (devnet-cli-consume-present-boolean-token args)))))
    (nreverse paths)))

(defun devnet-cli-config-args (args)
  (loop for path in (devnet-cli-config-paths args)
        append (devnet-cli-read-config-args path)))

(defun devnet-cli-apply-config-args (args)
  (append (devnet-cli-config-args args) args))
