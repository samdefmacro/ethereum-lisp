(defparameter *ethereum-lisp-devnet-smoke-gate-root*
  (merge-pathnames "../" (or *load-truename* *default-pathname-defaults*)))

(defconstant +devnet-smoke-gate-early-help-flag+ "--help")

(defun devnet-smoke-gate-early-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    args)
  #-sbcl nil)

(defun devnet-smoke-gate-early-help-p (args)
  (member +devnet-smoke-gate-early-help-flag+ args :test #'string=))

(defun devnet-smoke-gate-print-early-help ()
  (format t "~&Usage: sbcl --script scripts/devnet-smoke-gate.lisp -- [options] [FIXTURE-CASE]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --fixture-case NAME  Engine newPayloadV2 fixture case to import.~%")
  (format t "  --all-fixtures       Import every pinned Phase A newPayloadV2 smoke case.~%")
  (format t "  --engine-only-serve Run a focused serve-mode check with public HTTP disabled.~%")
  (format t "  --ready-file PATH    Write devnet readiness JSON and verify it.~%")
  (format t "  --log-file PATH      Write devnet telemetry events and verify them.~%")
  (format t "  --pid-file PATH      Write the devnet process id and verify it.~%")
  (format t "  --database PATH      Export and verify a file-backed KV chain snapshot.~%")
  (format t "  --prune-state-before NUMBER~%")
  (format t "                       Prune retained state before NUMBER when exporting --database.~%")
  (format t "  --override.terminaltotaldifficulty TTD~%")
  (format t "                       Configure the Engine transition total difficulty.~%")
  (format t "  --override.terminaltotaldifficultypassed~%")
  (format t "                       Mark terminal total difficulty as passed.~%")
  (format t "  --override.terminalblockhash HASH~%")
  (format t "                       Configure the Engine transition terminal block hash.~%")
  (format t "  --override.terminalblocknumber NUMBER~%")
  (format t "                       Configure the Engine transition terminal block number.~%")
  (format t "  --json               Print machine-readable JSON output.~%")
  (format t "  --help               Print this help.~%")
  (format t "~%")
  (format t "Reference client roots: ETHEREUM_LISP_GETH_ROOT, ~
ETHEREUM_LISP_NETHERMIND_ROOT, ETHEREUM_LISP_RETH_ROOT override ~
references/ checkouts.~%")
  (format t "~%"))

#+sbcl
(when (devnet-smoke-gate-early-help-p (devnet-smoke-gate-early-arguments))
  (devnet-smoke-gate-print-early-help)
  (sb-ext:exit :code 0))

(load (merge-pathnames "tests/load-tests.lisp"
                       *ethereum-lisp-devnet-smoke-gate-root*))

(in-package #:ethereum-lisp.test)

(defparameter *ethereum-lisp-devnet-smoke-gate-root*
  (symbol-value 'cl-user::*ethereum-lisp-devnet-smoke-gate-root*))

(defconstant +devnet-smoke-gate-json-flag+ "--json")
(defconstant +devnet-smoke-gate-help-flag+ "--help")
(defconstant +devnet-smoke-gate-fixture-case-option+ "--fixture-case")
(defconstant +devnet-smoke-gate-ready-file-option+ "--ready-file")
(defconstant +devnet-smoke-gate-log-file-option+ "--log-file")
(defconstant +devnet-smoke-gate-pid-file-option+ "--pid-file")
(defconstant +devnet-smoke-gate-database-option+ "--database")
(defconstant +devnet-smoke-gate-prune-state-before-option+
  "--prune-state-before")
(defconstant +devnet-smoke-gate-terminal-total-difficulty-option+
  "--override.terminaltotaldifficulty")
(defconstant +devnet-smoke-gate-terminal-total-difficulty-passed-flag+
  "--override.terminaltotaldifficultypassed")
(defconstant +devnet-smoke-gate-terminal-block-hash-option+
  "--override.terminalblockhash")
(defconstant +devnet-smoke-gate-terminal-block-number-option+
  "--override.terminalblocknumber")
(defconstant +devnet-smoke-gate-all-fixtures-flag+ "--all-fixtures")
(defconstant +devnet-smoke-gate-engine-only-serve-flag+
  "--engine-only-serve")
(defconstant +devnet-smoke-gate-default-fixture-case+
  "shanghai-one-transfer-with-withdrawal")
(defconstant +devnet-smoke-gate-eest-repository+
  "ethereum/execution-spec-tests")
(defconstant +devnet-smoke-gate-eest-release+ "v5.4.0")
(defconstant +devnet-smoke-gate-eest-tag-target+ "88e9fb8")
(defconstant +devnet-smoke-gate-eest-archive+ "fixtures_stable.tar.gz")
(defconstant +devnet-smoke-gate-simulation-gas+ "0x186a0")
(defconstant +devnet-smoke-gate-txpool-private-key+ 1)
(defconstant +devnet-smoke-gate-txpool-balance+ 1000000000000000000)
(defconstant +devnet-smoke-gate-txpool-gas-price+ 200)
(defconstant +devnet-smoke-gate-txpool-replacement-gas-price+ 220)
(defconstant +devnet-smoke-gate-txpool-basefee-gas-price+ 0)
(defconstant +devnet-smoke-gate-txpool-gas-limit+ 21000)
(defconstant +devnet-smoke-gate-txpool-value+ 1)
(defconstant +devnet-smoke-gate-txpool-recipient+
  "0x0000000000000000000000000000000000003001")
(defconstant +devnet-smoke-gate-engine-endpoint+ "http://127.0.0.1:8551")
(defconstant +devnet-smoke-gate-public-endpoint+ "http://127.0.0.1:8545")
(defconstant +devnet-smoke-gate-engine-boundary-connections+ 5)
(defconstant +devnet-smoke-gate-engine-workflow-connections+ 18)
(defconstant +devnet-smoke-gate-engine-connections+
  (+ +devnet-smoke-gate-engine-boundary-connections+
     +devnet-smoke-gate-engine-workflow-connections+))
(defconstant +devnet-smoke-gate-public-canonical-read-connections+ 23)
(defconstant +devnet-smoke-gate-public-boundary-connections+ 3)
(defconstant +devnet-smoke-gate-public-txpool-connections+ 28)
(defconstant +devnet-smoke-gate-public-connections+
  (+ +devnet-smoke-gate-public-canonical-read-connections+
     +devnet-smoke-gate-public-boundary-connections+
     +devnet-smoke-gate-public-txpool-connections+))
(defconstant +devnet-smoke-gate-total-connections+
  (+ +devnet-smoke-gate-engine-connections+
     +devnet-smoke-gate-public-connections+))
(defparameter *devnet-smoke-gate-public-api-allowlist*
  '("eth" "net"))
(defconstant +devnet-smoke-gate-public-api-allowlist-connections+ 6)
(defparameter *devnet-smoke-gate-public-cors-origins*
  '("https://runner.example" "https://observer.example"))
(defconstant +devnet-smoke-gate-public-cors-connections+ 3)
(defparameter *devnet-smoke-gate-engine-cors-origins*
  '("https://engine-runner.example" "https://engine-observer.example"))
(defconstant +devnet-smoke-gate-engine-cors-connections+ 3)
(defconstant +devnet-smoke-gate-http-shaping-engine-connections+ 2)
(defconstant +devnet-smoke-gate-http-shaping-public-connections+ 2)
(defparameter *devnet-smoke-gate-engine-vhosts*
  '("engine.runner" "localhost"))
(defparameter *devnet-smoke-gate-public-vhosts*
  '("public.runner" "localhost"))
(defconstant +devnet-smoke-gate-vhost-engine-connections+ 2)
(defconstant +devnet-smoke-gate-vhost-public-connections+ 2)
(defconstant +devnet-smoke-gate-engine-rpc-prefix+ "/engine")
(defconstant +devnet-smoke-gate-public-rpc-prefix+ "/rpc")
(defconstant +devnet-smoke-gate-rpc-prefix-engine-connections+ 2)
(defconstant +devnet-smoke-gate-rpc-prefix-public-connections+ 2)

(defun devnet-smoke-gate-arguments ()
  #+sbcl
  (let ((args (cdr sb-ext:*posix-argv*)))
    (when (and args (string= (first args) "--"))
      (setf args (cdr args)))
    (devnet-smoke-gate-normalize-option-args args))
  #-sbcl nil)

(defun devnet-smoke-gate-value-option-p (arg)
  (member arg
          (list +devnet-smoke-gate-fixture-case-option+
                +devnet-smoke-gate-ready-file-option+
                +devnet-smoke-gate-log-file-option+
                +devnet-smoke-gate-pid-file-option+
                +devnet-smoke-gate-database-option+
                +devnet-smoke-gate-prune-state-before-option+
                +devnet-smoke-gate-terminal-total-difficulty-option+
                +devnet-smoke-gate-terminal-block-hash-option+
                +devnet-smoke-gate-terminal-block-number-option+)
          :test #'string=))

(defun devnet-smoke-gate-boolean-option-p (arg)
  (member arg
          (list +devnet-smoke-gate-json-flag+
                +devnet-smoke-gate-all-fixtures-flag+
                +devnet-smoke-gate-engine-only-serve-flag+
                +devnet-smoke-gate-terminal-total-difficulty-passed-flag+)
          :test #'string=))

(defun devnet-smoke-gate-parse-boolean-assignment (option value)
  (let ((normalized (and (stringp value) (string-downcase value))))
    (cond
      ((member normalized '("true" "1") :test #'string=) t)
      ((member normalized '("false" "0") :test #'string=) nil)
      (t (error "~A boolean value must be true or false" option)))))

(defun devnet-smoke-gate-normalize-option-args (args)
  (loop for arg in args
        for equals-position = (and (stringp arg)
                                   (<= 2 (length arg))
                                   (string= "--" arg :end2 2)
                                   (position #\= arg :start 2))
        for option = (and equals-position (subseq arg 0 equals-position))
        for value = (and equals-position (subseq arg (1+ equals-position)))
        append
        (cond
          ((and equals-position (devnet-smoke-gate-value-option-p option))
           (list option value))
          ((and equals-position (devnet-smoke-gate-boolean-option-p option))
           (if (devnet-smoke-gate-parse-boolean-assignment option value)
               (list option)
               '()))
          (t
           (list arg)))))

(defun devnet-smoke-gate-json-p (args)
  (member +devnet-smoke-gate-json-flag+ args :test #'string=))

(defun devnet-smoke-gate-help-p (args)
  (member +devnet-smoke-gate-help-flag+ args :test #'string=))

(defun devnet-smoke-gate-all-fixtures-p (args)
  (member +devnet-smoke-gate-all-fixtures-flag+ args :test #'string=))

(defun devnet-smoke-gate-engine-only-serve-p (args)
  (member +devnet-smoke-gate-engine-only-serve-flag+ args :test #'string=))

(defun devnet-smoke-gate-option-like-p (value)
  (and (stringp value)
       (plusp (length value))
       (char= #\- (char value 0))))

(defun devnet-smoke-gate-fixture-case-specified-p (args)
  (let ((specified-p nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((or (string= arg +devnet-smoke-gate-json-flag+)
                 (string= arg +devnet-smoke-gate-help-flag+)
                 (string= arg +devnet-smoke-gate-all-fixtures-flag+)
                 (string= arg +devnet-smoke-gate-engine-only-serve-flag+)
                 (string= arg
                          +devnet-smoke-gate-terminal-total-difficulty-passed-flag+)))
            ((or (string= arg +devnet-smoke-gate-ready-file-option+)
                 (string= arg +devnet-smoke-gate-log-file-option+)
                 (string= arg +devnet-smoke-gate-pid-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+)
                 (string= arg +devnet-smoke-gate-prune-state-before-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-total-difficulty-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-block-hash-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-block-number-option+)
                 (string= arg +devnet-smoke-gate-fixture-case-option+))
             (when (and (string= arg +devnet-smoke-gate-fixture-case-option+)
                        args)
               (setf specified-p t))
             (when args
               (pop args)))
            ((devnet-smoke-gate-option-like-p arg))
            (t
             (setf specified-p t))))
    specified-p))

(defun devnet-smoke-gate-fixture-case-name (args)
  (let ((fixture-case nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((string= arg +devnet-smoke-gate-json-flag+))
            ((string= arg +devnet-smoke-gate-help-flag+))
            ((string= arg +devnet-smoke-gate-all-fixtures-flag+))
            ((string= arg +devnet-smoke-gate-engine-only-serve-flag+))
            ((string= arg
                      +devnet-smoke-gate-terminal-total-difficulty-passed-flag+))
            ((or (string= arg +devnet-smoke-gate-ready-file-option+)
                 (string= arg +devnet-smoke-gate-log-file-option+)
                 (string= arg +devnet-smoke-gate-pid-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+)
                 (string= arg +devnet-smoke-gate-prune-state-before-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-total-difficulty-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-block-hash-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-block-number-option+))
             (unless args
               (error "~A requires a value" arg))
             (let ((value (pop args)))
               (when (and (not (string= arg
                                         +devnet-smoke-gate-prune-state-before-option+))
                          (devnet-smoke-gate-option-like-p value))
                 (error "~A requires a path, got option ~A" arg value))))
            ((string= arg +devnet-smoke-gate-fixture-case-option+)
             (when fixture-case
               (error "Only one fixture case argument is supported"))
             (unless args
               (error "~A requires a fixture case name"
                      +devnet-smoke-gate-fixture-case-option+))
             (let ((value (pop args)))
               (when (devnet-smoke-gate-option-like-p value)
                 (error "~A requires a fixture case name, got option ~A"
                        +devnet-smoke-gate-fixture-case-option+
                        value))
               (setf fixture-case value)))
            ((devnet-smoke-gate-option-like-p arg)
             (error "Unsupported devnet smoke gate option ~A" arg))
            (t
             (when fixture-case
               (error "Only one fixture case argument is supported"))
             (setf fixture-case arg))))
    (or fixture-case +devnet-smoke-gate-default-fixture-case+)))

(defun devnet-smoke-gate-path-option (args option)
  (let ((path nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((string= arg option)
             (when path
               (error "Only one ~A option is supported" option))
             (unless args
               (error "~A requires a path" option))
             (let ((value (pop args)))
               (when (devnet-smoke-gate-option-like-p value)
                 (error "~A requires a path, got option ~A" option value))
               (setf path value)))
            ((string= arg +devnet-smoke-gate-fixture-case-option+)
             (when args
               (pop args)))
            ((or (string= arg +devnet-smoke-gate-ready-file-option+)
                 (string= arg +devnet-smoke-gate-log-file-option+)
                 (string= arg +devnet-smoke-gate-pid-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+)
                 (string= arg +devnet-smoke-gate-prune-state-before-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-total-difficulty-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-block-hash-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-block-number-option+))
             (when args
               (pop args)))))
    path))

(defun devnet-smoke-gate-non-negative-integer-option (args option)
  (let ((integer nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((string= arg option)
             (when integer
               (error "Only one ~A option is supported" option))
             (unless args
               (error "~A requires a value" option))
             (let ((value (pop args)))
               (handler-case
                   (setf integer (parse-integer value :junk-allowed nil))
                 (error ()
                   (error "~A requires an integer value" option)))
               (when (minusp integer)
                 (error "~A must be non-negative" option))))
            ((string= arg +devnet-smoke-gate-fixture-case-option+)
             (when args
               (pop args)))
            ((or (string= arg +devnet-smoke-gate-ready-file-option+)
                 (string= arg +devnet-smoke-gate-log-file-option+)
                 (string= arg +devnet-smoke-gate-pid-file-option+)
                 (string= arg +devnet-smoke-gate-database-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-total-difficulty-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-block-hash-option+)
                 (string= arg
                          +devnet-smoke-gate-terminal-block-number-option+))
             (when args
               (pop args)))))
    integer))

(defun devnet-smoke-gate-quantity-token-p (value)
  (and (stringp value)
       (<= 2 (length value))
       (char= #\0 (char value 0))
       (char= #\x (char-downcase (char value 1)))))

(defun devnet-smoke-gate-quantity-option (args option)
  (let ((quantity nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((string= arg option)
             (when quantity
               (error "Only one ~A option is supported" option))
             (unless args
               (error "~A requires a value" option))
             (let ((value (pop args)))
               (handler-case
                   (setf quantity
                         (if (devnet-smoke-gate-quantity-token-p value)
                             (hex-to-quantity value)
                             (parse-integer value :junk-allowed nil)))
                 (error ()
                   (error "~A requires a non-negative integer or hex quantity"
                          option)))
               (when (minusp quantity)
                 (error "~A must be non-negative" option))))
            ((and (devnet-smoke-gate-value-option-p arg) args)
             (pop args))))
    quantity))

(defun devnet-smoke-gate-hash32-option (args option)
  (let ((hash nil))
    (loop while args
          for arg = (pop args)
          do
          (cond
            ((string= arg option)
             (when hash
               (error "Only one ~A option is supported" option))
             (unless args
               (error "~A requires a value" option))
             (let ((value (pop args)))
               (handler-case
                   (setf hash (hash32-from-hex value))
                 (error ()
                   (error "~A requires a 32-byte hex hash" option)))))
            ((and (devnet-smoke-gate-value-option-p arg) args)
             (pop args))))
    hash))

(defun devnet-smoke-gate-print-help ()
  (format t "~&Usage: sbcl --script scripts/devnet-smoke-gate.lisp -- [options] [FIXTURE-CASE]~%")
  (format t "~%")
  (format t "Options:~%")
  (format t "  --fixture-case NAME  Engine newPayloadV2 fixture case to import.~%")
  (format t "  --all-fixtures       Import every pinned Phase A newPayloadV2 smoke case.~%")
  (format t "  --engine-only-serve Run a focused serve-mode check with public HTTP disabled.~%")
  (format t "  --ready-file PATH    Write devnet readiness JSON and verify it.~%")
  (format t "  --log-file PATH      Write devnet telemetry events and verify them.~%")
  (format t "  --pid-file PATH      Write the devnet process id and verify it.~%")
  (format t "  --database PATH      Export and verify a file-backed KV chain snapshot.~%")
  (format t "  --prune-state-before NUMBER~%")
  (format t "                       Prune retained state before NUMBER when exporting --database.~%")
  (format t "  --override.terminaltotaldifficulty TTD~%")
  (format t "                       Configure the Engine transition total difficulty.~%")
  (format t "  --override.terminaltotaldifficultypassed~%")
  (format t "                       Mark terminal total difficulty as passed.~%")
  (format t "  --override.terminalblockhash HASH~%")
  (format t "                       Configure the Engine transition terminal block hash.~%")
  (format t "  --override.terminalblocknumber NUMBER~%")
  (format t "                       Configure the Engine transition terminal block number.~%")
  (format t "  --json               Print machine-readable JSON output.~%")
  (format t "  --help               Print this help.~%")
  (format t "~%")
  (format t "Reference client roots: ETHEREUM_LISP_GETH_ROOT, ~
ETHEREUM_LISP_NETHERMIND_ROOT, ETHEREUM_LISP_RETH_ROOT override ~
references/ checkouts.~%")
  (format t "Default fixture case: ~A~%"
          +devnet-smoke-gate-default-fixture-case+))

(defun devnet-smoke-gate-require (condition format-control &rest args)
  (unless condition
    (apply #'error format-control args)))

(defun devnet-smoke-gate-pruned-state-error-messages ()
  '("eth_getBalance state is not available"
    "eth_getTransactionCount state is not available"
    "eth_getCode state is not available"
    "eth_getStorageAt state is not available"
    "eth_getProof state is not available"
    "eth_call state is not available"
    "eth_estimateGas state is not available"
    "eth_createAccessList state is not available"))

(defun devnet-smoke-gate-noncanonical-state-error-messages ()
  '("eth_getBalance block hash is not canonical"
    "eth_getTransactionCount block hash is not canonical"
    "eth_getCode block hash is not canonical"
    "eth_getStorageAt block hash is not canonical"
    "eth_getProof block hash is not canonical"
    "eth_call block hash is not canonical"
    "eth_estimateGas block hash is not canonical"
    "eth_createAccessList block hash is not canonical"))

(defun devnet-smoke-gate-false-p (value)
  (or (null value) (eq value :false)))

(defun devnet-smoke-gate-report-pruned-state-covered-p
    (report state-prune-before)
  (and state-prune-before
       (< (hex-to-quantity
           (devnet-smoke-gate-field report "safeBlockNumber"))
          state-prune-before)))

(defun devnet-smoke-gate-rpc-body (response &key preserve-empty-arrays)
  (parse-json (devnet-cli-http-body response)
              :preserve-empty-arrays preserve-empty-arrays))

(defun devnet-smoke-gate-empty-json-array-p (value)
  (and (vectorp value)
       (zerop (length value))))

(defun devnet-smoke-gate-http-header (response name)
  (let* ((boundary (search (format nil "~C~C~C~C"
                                   #\Return #\Newline #\Return #\Newline)
                           response))
         (head (and boundary (subseq response 0 boundary)))
         (prefix (format nil "~A: " name)))
    (when head
      (loop for line in (uiop:split-string head :separator '(#\Return #\Newline))
            when (and (>= (length line) (length prefix))
                      (string-equal prefix
                                    (subseq line 0 (length prefix))))
              return (subseq line (length prefix))))))

(defun devnet-smoke-gate-http-request
    (method target &key body origin content-type authorization
       (host "localhost"))
  (let ((body (or body "")))
    (with-output-to-string (stream)
      (format stream "~A ~A HTTP/1.1~%Host: ~A~%"
              method target host)
      (when origin
        (format stream "Origin: ~A~%" origin))
      (when content-type
        (format stream "Content-Type: ~A~%" content-type))
      (when authorization
        (format stream "Authorization: ~A~%" authorization))
      (format stream "Content-Length: ~D~%~%~A" (length body) body))))

(defun devnet-smoke-gate-call-with-telemetry-sink (log-file thunk)
  (if log-file
      (with-open-file (stream (ethereum-lisp.cli::devnet-cli-ensure-path-parent-directory
                               log-file)
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (funcall thunk
                 (ethereum-lisp.telemetry:make-stream-telemetry-sink
                  :stream stream)))
      (funcall thunk ethereum-lisp.telemetry:*telemetry-sink*)))

(defun devnet-smoke-gate-file-string (path)
  (with-open-file (stream path :direction :input)
    (let ((string (make-string (file-length stream))))
      (read-sequence string stream)
      string)))

(defun devnet-smoke-gate-file-forms (path)
  (with-open-file (stream path :direction :input)
    (loop for form = (read stream nil :eof)
          until (eq form :eof)
          collect form)))

(defun devnet-smoke-gate-txpool-sender-address ()
  (fixture-private-key-address +devnet-smoke-gate-txpool-private-key+))

(defun devnet-smoke-gate-ensure-txpool-account (state)
  (let ((address (devnet-smoke-gate-txpool-sender-address)))
    (unless (state-db-get-account state address)
      (state-db-set-account
       state
       address
       (make-state-account
        :nonce 0
        :balance +devnet-smoke-gate-txpool-balance+)))
    address))

(defun devnet-smoke-gate-txpool-transaction
    (config nonce gas-price)
  (let ((transaction
          (make-legacy-transaction
           :nonce nonce
           :gas-price gas-price
           :gas-limit +devnet-smoke-gate-txpool-gas-limit+
           :to (address-from-hex +devnet-smoke-gate-txpool-recipient+)
           :value +devnet-smoke-gate-txpool-value+)))
    (fixture-sign-legacy-transaction
     transaction
     +devnet-smoke-gate-txpool-private-key+
     (chain-config-chain-id config))))

(defun devnet-smoke-gate-make-restored-node
    (path config &key (port 0) (public-port 0) jwt-secret-path)
  (let ((node
          (ethereum-lisp.cli:make-devnet-node
           :genesis-path
           (namestring
            (devnet-smoke-gate-reference-path
             +devnet-cli-genesis-fixture+))
           :port port
           :public-port public-port
           :jwt-secret-path jwt-secret-path)))
    (chain-store-import-from-kv
     (ethereum-lisp.cli:devnet-node-store node)
     (make-file-key-value-database path)
     :expected-chain-id (chain-config-chain-id config))
    (devnet-cli-set-node-store-config
     node
     (ethereum-lisp.cli:devnet-node-store node)
     config)
    (setf (ethereum-lisp.cli::devnet-node-database-path node) path)
    node))

(defun devnet-smoke-gate-write-kzg-prepared-payload-database (genesis-path)
  (let* ((database-path
           (devnet-cli-temp-path "ethereum-lisp-smoke-kzg-blob" "db"))
         (store (make-engine-payload-memory-store))
         (config (chain-config-from-genesis-json-file genesis-path))
         (state (state-db-from-genesis-json-file genesis-path))
         (genesis-block
           (genesis-block-from-state-genesis-json-file
           genesis-path
           :config config))
         (payload-id-v5 #(5 0 0 0 0 0 0 1))
         (payload-id-v6 #(6 0 0 0 0 0 0 1))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proofs
           (loop for index below +cell-proofs-per-blob+
                 collect
                 (let ((proof (make-byte-vector +kzg-proof-size+)))
                   (setf (aref proof 0) (+ #x05 index)
                         (aref proof 1) #xff)
                   proof)))
         (sidecar
           (make-blob-sidecar
            :blobs (list blob)
            :commitments (list commitment)
            :proofs proofs))
         (execution-request #(#x82 #x06 #xaa))
         (block-access-account
           (make-block-access-account
            :address (address-from-hex
                      "0x0000000000000000000000000000000000000001")))
         (versioned-hash nil)
         (block-v5
           (make-block
            :header
            (make-block-header
             :number 9
             :timestamp 14
             :withdrawals-root (withdrawal-list-root '()))
            :withdrawals '()))
         (block-v6
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary (zero-address)
             :state-root (block-header-state-root
                          (block-header genesis-block))
             :mix-hash (zero-hash32)
             :number 10
             :gas-limit 50000
             :gas-used 21000
             :timestamp 15
             :base-fee-per-gas 100
             :withdrawals-root (withdrawal-list-root '())
             :blob-gas-used 0
             :excess-blob-gas 0
             :parent-beacon-root (zero-hash32)
             :slot-number 42)
            :withdrawals '()
            :requests (list execution-request)
            :block-access-list (list block-access-account))))
    (setf (aref blob 0) #x03
          (aref blob 1) #xdd
          (aref commitment 0) #x04
          (aref commitment 1) #xee
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
    (chain-store-put-block store genesis-block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis-block) state)
    (setf (gethash (hash32-to-hex (block-hash block-v6))
                   (ethereum-lisp.core::engine-payload-memory-store-blocks
                    store))
          block-v6)
    (commit-state-db-to-chain-store store (block-hash block-v6) state)
    (setf (gethash (hash32-to-hex (block-hash block-v6))
                   (ethereum-lisp.core::engine-payload-memory-store-state-blocks
                    store))
          t)
    (remhash (hash32-to-hex (block-hash block-v6))
             (ethereum-lisp.core::engine-payload-memory-store-blocks store))
    (engine-payload-store-put-blob-sidecar store sidecar)
    (chain-store-put-prepared-payload
     store
     (make-engine-prepared-payload
      :payload-id payload-id-v5
      :version 5
      :block block-v5
      :blobs-bundle sidecar))
    (chain-store-put-prepared-payload
     store
     (make-engine-prepared-payload
      :payload-id payload-id-v6
      :version 6
      :block block-v6
      :blobs-bundle sidecar))
    (let ((database (make-file-key-value-database database-path)))
      (chain-store-export-to-kv store database)
      (kv-put-chain-record
       database
       :block
       (hash32-bytes (block-hash block-v6))
       (block-rlp block-v6)))
    (let* ((blob-hex (bytes-to-hex blob))
           (block-access-list-hex
             (bytes-to-hex (block-encoded-block-access-list block-v6)))
           (first-proof-hex (bytes-to-hex (first proofs)))
           (last-proof-hex (bytes-to-hex (car (last proofs)))))
      (list :database-path database-path
            :payload-id (bytes-to-hex payload-id-v5)
            :payload-id-v5 (bytes-to-hex payload-id-v5)
            :payload-id-v6 (bytes-to-hex payload-id-v6)
            :block-hash-v6 (hash32-to-hex (block-hash block-v6))
            :versioned-hash-hex (hash32-to-hex versioned-hash)
            :block-number "0x9"
            :block-number-v5 "0x9"
            :block-number-v6 "0xa"
            :slot-number-v6 "0x2a"
            :execution-request-hex (bytes-to-hex execution-request)
            :block-access-list-hex block-access-list-hex
            :block-access-list-prefix
            (subseq block-access-list-hex
                    0
                    (min (length block-access-list-hex) 18))
            :blob-hex blob-hex
            :blob-prefix (subseq blob-hex 0 (min (length blob-hex) 18))
            :blob-hex-length (length blob-hex)
            :commitment-hex (bytes-to-hex commitment)
            :proof-hex first-proof-hex
            :proof-prefix
            (subseq first-proof-hex 0 (min (length first-proof-hex) 18))
            :proof-hex-length (length first-proof-hex)
            :cell-proof-count +cell-proofs-per-blob+
            :first-cell-proof-hex first-proof-hex
            :first-cell-proof-prefix
            (subseq first-proof-hex 0 (min (length first-proof-hex) 18))
            :last-cell-proof-hex last-proof-hex
            :last-cell-proof-prefix
            (subseq last-proof-hex 0 (min (length last-proof-hex) 18))))))

(defun devnet-smoke-gate-txpool-transactions
    (state config sender-address)
  (let* ((account (state-db-get-account state sender-address))
         (nonce (state-account-nonce account)))
    (list
     (cons "pending"
           (devnet-smoke-gate-txpool-transaction
            config nonce +devnet-smoke-gate-txpool-gas-price+))
     (cons "basefee"
           (devnet-smoke-gate-txpool-transaction
            config
            (1+ nonce)
            +devnet-smoke-gate-txpool-basefee-gas-price+))
     (cons "queued"
           (devnet-smoke-gate-txpool-transaction
            config
            (+ nonce 2)
            +devnet-smoke-gate-txpool-gas-price+)))))

(defun devnet-smoke-gate-engine-fixture (case-name)
  (let* ((case
           (select-engine-newpayload-v2-fixture-case
            (namestring
             (devnet-smoke-gate-reference-path
              +engine-newpayload-v2-fixture-path+))
            case-name))
         (store (make-engine-payload-memory-store))
         (config (engine-fixture-chain-config case))
         (parent (fixture-object-field case "parent"))
         (payload-case (fixture-object-field case "payload"))
         (expect (fixture-object-field case "expect"))
         (parent-state (engine-fixture-parent-state parent))
         (fee-recipient (fixture-address-field parent "feeRecipient"))
         (txpool-sender
           (devnet-smoke-gate-ensure-txpool-account parent-state))
         (transactions
           (mapcar (lambda (raw)
                     (transaction-from-encoding (hex-to-bytes raw)))
                   (fixture-object-field payload-case "transactions")))
         (withdrawals
           (mapcar #'engine-fixture-withdrawal
                   (fixture-object-field payload-case "withdrawals")))
         (parent-header
           (make-block-header
            :parent-hash (zero-hash32)
            :beneficiary fee-recipient
            :state-root (state-db-root parent-state)
            :mix-hash (zero-hash32)
            :number (fixture-quantity-field parent "number")
            :gas-limit (fixture-quantity-field parent "gasLimit")
            :gas-used (fixture-quantity-field parent "gasUsed")
            :timestamp (fixture-quantity-field parent "timestamp")
            :base-fee-per-gas (fixture-quantity-field parent "baseFeePerGas")
            :withdrawals-root (withdrawal-list-root '())))
         (parent-block (make-block :header parent-header))
         (child-state (state-db-copy parent-state))
         (child-header
           (make-block-header
            :parent-hash (block-hash parent-block)
            :beneficiary fee-recipient
            :mix-hash (zero-hash32)
            :number (fixture-quantity-field payload-case "number")
            :gas-limit (fixture-quantity-field payload-case "gasLimit")
            :gas-used 0
            :timestamp (fixture-quantity-field payload-case "timestamp")
            :base-fee-per-gas
            (fixture-quantity-field payload-case "baseFeePerGas")))
         (child-block
           (execute-signed-block
            child-state
            transactions
            :expected-chain-id (chain-config-chain-id config)
            :header child-header
            :chain-config config
            :withdrawals withdrawals))
         (side-block
           (devnet-smoke-gate-side-sibling-block
            parent-block parent-state config payload-case withdrawals
            fee-recipient))
         (payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data child-block)))
         (side-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data side-block)))
         (txpool-transactions
           (devnet-smoke-gate-txpool-transactions
            child-state
            config
            txpool-sender)))
    (list
     (cons "case" case)
     (cons "store" store)
     (cons "config" config)
     (cons "parentState" parent-state)
     (cons "parentBlock" parent-block)
     (cons "childBlock" child-block)
     (cons "payload" payload)
     (cons "sideBlock" side-block)
     (cons "sidePayload" side-payload)
     (cons "txpoolTransactions" txpool-transactions)
     (cons "pendingTransaction"
           (cdr (assoc "pending" txpool-transactions :test #'string=)))
     (cons "payloadCase" payload-case)
     (cons "expect" expect))))

(defun devnet-smoke-gate-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun devnet-smoke-gate-root-directory ()
  (truename
   (make-pathname :name nil
                  :type nil
                  :defaults *ethereum-lisp-devnet-smoke-gate-root*)))

(defun devnet-smoke-gate-reference-path (relative-path)
  (merge-pathnames relative-path (devnet-smoke-gate-root-directory)))

(defun devnet-smoke-gate-reference-client-path (relative-path env-var)
  (let ((override (and env-var (uiop:getenv env-var))))
    (if (and override (plusp (length override)))
        (uiop:ensure-directory-pathname
         (merge-pathnames override (devnet-smoke-gate-root-directory)))
        (devnet-smoke-gate-reference-path relative-path))))

(defun devnet-smoke-gate-reference-client-object
    (name env-var relative-path)
  (let ((path (devnet-smoke-gate-reference-client-path
               relative-path
               env-var)))
    (cond
      ((not (probe-file path))
       (list
        (cons "name" name)
        (cons "status" "missing")
        (cons "path" (namestring path))
        (cons "commit" nil)))
      (t
       (multiple-value-bind (stdout stderr status)
           (uiop:run-program
            (list "git" "-C" (namestring path) "rev-parse" "HEAD")
            :output :string
            :error-output :string
            :ignore-error-status t)
         (declare (ignore stderr))
         (if (= 0 status)
             (list
              (cons "name" name)
              (cons "status" "ok")
              (cons "path" (namestring path))
              (cons "commit" (string-trim '(#\Space #\Tab #\Newline #\Return)
                                          stdout)))
             (list
              (cons "name" name)
              (cons "status" "unavailable")
              (cons "path" (namestring path))
              (cons "commit" nil))))))))

(defun devnet-smoke-gate-reference-clients ()
  (list
   (devnet-smoke-gate-reference-client-object
    "geth" "ETHEREUM_LISP_GETH_ROOT" "references/go-ethereum/")
   (devnet-smoke-gate-reference-client-object
    "nethermind" "ETHEREUM_LISP_NETHERMIND_ROOT" "references/nethermind/")
   (devnet-smoke-gate-reference-client-object
    "reth" "ETHEREUM_LISP_RETH_ROOT" "references/reth/")))

(defun devnet-smoke-gate-connection-contract (&optional (case-count 1))
  (list
   (cons "caseCount" case-count)
   (cons "engineBoundaryConnections"
         (* case-count +devnet-smoke-gate-engine-boundary-connections+))
   (cons "engineWorkflowConnections"
         (* case-count +devnet-smoke-gate-engine-workflow-connections+))
   (cons "publicCanonicalReadConnections"
         (* case-count +devnet-smoke-gate-public-canonical-read-connections+))
   (cons "publicBoundaryConnections"
         (* case-count +devnet-smoke-gate-public-boundary-connections+))
   (cons "publicTxpoolConnections"
         (* case-count +devnet-smoke-gate-public-txpool-connections+))
   (cons "expectedEngineConnections"
         (* case-count +devnet-smoke-gate-engine-connections+))
   (cons "expectedPublicConnections"
         (* case-count +devnet-smoke-gate-public-connections+))
   (cons "expectedTotalConnections"
         (* case-count +devnet-smoke-gate-total-connections+))))

(defun devnet-smoke-gate-json-rpc-request (id method params)
  (json-encode
   (list (cons "jsonrpc" "2.0")
         (cons "id" id)
         (cons "method" method)
         (cons "params" params))))

(defun devnet-smoke-gate-error-code (rpc)
  (fixture-object-field
   (fixture-object-field rpc "error")
   "code"))

(defun devnet-smoke-gate-verify-public-api-allowlist ()
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 8551
            :public-port 8545
            :network-id 7331
            :public-allowed-method-p
            (ethereum-lisp.cli::devnet-cli-public-api-method-filter
             *devnet-smoke-gate-public-api-allowlist*)
            :public-api-modules
            *devnet-smoke-gate-public-api-allowlist*))
         (chain-id-output (make-string-output-stream))
         (network-output (make-string-output-stream))
         (rpc-modules-output (make-string-output-stream))
         (web3-output (make-string-output-stream))
         (txpool-output (make-string-output-stream))
         (engine-output (make-string-output-stream))
         (public-requests
           (list
            (cons (devnet-smoke-gate-json-rpc-request
                   301 "eth_chainId" '())
                  chain-id-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   302 "net_version" '())
                  network-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   306 "rpc_modules" '())
                  rpc-modules-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   303 "web3_clientVersion" '())
                  web3-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   304 "txpool_status" '())
                  txpool-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   305 "engine_exchangeCapabilities" (list '()))
                  engine-output))))
    (let ((summary
            (ethereum-lisp.cli:start-devnet-node-listeners
             node
             (make-engine-rpc-http-listener
              :endpoint "allowlist-engine"
              :accept-function (lambda () nil)
              :close-function (lambda () nil))
             (make-engine-rpc-http-listener
              :endpoint "allowlist-public"
              :accept-function
              (lambda ()
                (when public-requests
                  (destructuring-bind (body . output)
                      (pop public-requests)
                    (make-engine-rpc-http-connection
                     :input-stream
                     (make-string-input-stream
                      (devnet-cli-json-rpc-http-request body))
                     :output-stream output
                     :close-function (lambda () nil)))))
              :close-function (lambda () nil))
             :max-connections
             +devnet-smoke-gate-public-api-allowlist-connections+)))
      (let* ((chain-id-response
               (get-output-stream-string chain-id-output))
             (network-response
               (get-output-stream-string network-output))
             (rpc-modules-response
               (get-output-stream-string rpc-modules-output))
             (web3-response
               (get-output-stream-string web3-output))
             (txpool-response
               (get-output-stream-string txpool-output))
             (engine-response
               (get-output-stream-string engine-output))
             (chain-id-rpc (devnet-smoke-gate-rpc-body chain-id-response))
             (network-rpc (devnet-smoke-gate-rpc-body network-response))
             (rpc-modules-rpc
               (devnet-smoke-gate-rpc-body rpc-modules-response))
             (rpc-modules
               (fixture-object-field rpc-modules-rpc "result"))
             (web3-rpc (devnet-smoke-gate-rpc-body web3-response))
             (txpool-rpc (devnet-smoke-gate-rpc-body txpool-response))
             (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
             (chain-id (fixture-object-field chain-id-rpc "result"))
             (network-version
               (fixture-object-field network-rpc "result"))
             (web3-error-code
               (devnet-smoke-gate-error-code web3-rpc))
             (txpool-error-code
               (devnet-smoke-gate-error-code txpool-rpc))
             (engine-error-code
               (devnet-smoke-gate-error-code engine-rpc))
             (summary-json
               (ethereum-lisp.cli::devnet-node-summary-json-object node))
             (telemetry-fields
               (ethereum-lisp.cli::devnet-node-telemetry-fields node))
             (reported-modules
               (cdr (assoc "publicApiModules"
                           summary-json
                           :test #'string=)))
             (telemetry-modules
               (cdr (assoc "publicApiModules"
                           telemetry-fields
                           :test #'string=))))
        (dolist (response (list chain-id-response network-response
                                rpc-modules-response web3-response
                                txpool-response
                                engine-response))
          (devnet-smoke-gate-require
           (= 200 (devnet-cli-http-status response))
           "Public API allowlist probe HTTP status mismatch"))
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Public API allowlist Engine connection count mismatch")
        (devnet-smoke-gate-require
         (= +devnet-smoke-gate-public-api-allowlist-connections+
            (getf summary :public-connections))
         "Public API allowlist public connection count mismatch")
        (devnet-smoke-gate-require
         (string= "0x539" chain-id)
         "Public API allowlist eth_chainId mismatch")
        (devnet-smoke-gate-require
         (string= "7331" network-version)
         "Public API allowlist net_version mismatch")
        (devnet-smoke-gate-require
         (string= "1.0" (fixture-object-field rpc-modules "eth"))
         "Public API allowlist rpc_modules eth module mismatch")
        (devnet-smoke-gate-require
         (string= "1.0" (fixture-object-field rpc-modules "net"))
         "Public API allowlist rpc_modules net module mismatch")
        (devnet-smoke-gate-require
         (string= "1.0" (fixture-object-field rpc-modules "rpc"))
         "Public API allowlist rpc_modules rpc module mismatch")
        (devnet-smoke-gate-require
         (not (fixture-object-field rpc-modules "txpool"))
         "Public API allowlist rpc_modules unexpectedly reported txpool")
        (devnet-smoke-gate-require
         (not (fixture-object-field rpc-modules "web3"))
         "Public API allowlist rpc_modules unexpectedly reported web3")
        (dolist (code (list web3-error-code txpool-error-code
                            engine-error-code))
          (devnet-smoke-gate-require
           (= -32601 code)
           "Public API allowlist did not reject a blocked method"))
        (devnet-smoke-gate-require
         (equal *devnet-smoke-gate-public-api-allowlist*
                reported-modules)
         "Public API allowlist summary modules mismatch")
        (devnet-smoke-gate-require
         (string= "eth,net" telemetry-modules)
         "Public API allowlist telemetry modules mismatch")
        (list :allowed-modules
              (copy-list *devnet-smoke-gate-public-api-allowlist*)
              :reported-modules reported-modules
              :telemetry-modules telemetry-modules
              :rpc-modules rpc-modules
              :engine-connections (getf summary :engine-connections)
              :public-connections (getf summary :public-connections)
              :total-connections (getf summary :total-connections)
              :chain-id chain-id
              :network-version network-version
              :web3-error-code web3-error-code
              :txpool-error-code txpool-error-code
              :engine-error-code engine-error-code))))
  #-sbcl
  (error "Public API allowlist smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-public-cors ()
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 8551
            :public-port 8545
            :public-cors-origins *devnet-smoke-gate-public-cors-origins*))
         (preflight-output (make-string-output-stream))
         (post-output (make-string-output-stream))
         (blocked-output (make-string-output-stream))
         (public-requests
           (list
            (cons
             (devnet-smoke-gate-http-request
              "OPTIONS" "/" :origin "https://runner.example")
             preflight-output)
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :origin "https://observer.example"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     401 "eth_chainId" '()))
             post-output)
            (cons
             (devnet-smoke-gate-http-request
              "OPTIONS" "/" :origin "https://blocked.example")
             blocked-output))))
    (let ((summary
            (ethereum-lisp.cli:start-devnet-node-listeners
             node
             (make-engine-rpc-http-listener
              :endpoint "cors-engine"
              :accept-function (lambda () nil)
              :close-function (lambda () nil))
             (make-engine-rpc-http-listener
              :endpoint "cors-public"
              :accept-function
              (lambda ()
                (when public-requests
                  (destructuring-bind (request . output)
                      (pop public-requests)
                    (make-engine-rpc-http-connection
                     :input-stream (make-string-input-stream request)
                     :output-stream output
                     :close-function (lambda () nil)))))
              :close-function (lambda () nil))
             :max-connections +devnet-smoke-gate-public-cors-connections+)))
      (let* ((preflight-response
               (get-output-stream-string preflight-output))
             (post-response
               (get-output-stream-string post-output))
             (blocked-response
               (get-output-stream-string blocked-output))
             (post-rpc (devnet-smoke-gate-rpc-body post-response))
             (post-chain-id (fixture-object-field post-rpc "result"))
             (summary-json
               (ethereum-lisp.cli::devnet-node-summary-json-object node))
             (telemetry-fields
               (ethereum-lisp.cli::devnet-node-telemetry-fields node))
             (reported-origins
               (cdr (assoc "publicCorsOrigins"
                           summary-json
                           :test #'string=)))
             (telemetry-origins
               (cdr (assoc "publicCorsOrigins"
                           telemetry-fields
                           :test #'string=))))
        (devnet-smoke-gate-require
         (= 204 (devnet-cli-http-status preflight-response))
         "Public CORS preflight status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status post-response))
         "Public CORS JSON-RPC status mismatch")
        (devnet-smoke-gate-require
         (= 403 (devnet-cli-http-status blocked-response))
         "Public CORS blocked-origin status mismatch")
        (devnet-smoke-gate-require
         (string= "https://runner.example"
                  (devnet-smoke-gate-http-header
                   preflight-response
                   "Access-Control-Allow-Origin"))
         "Public CORS preflight origin header mismatch")
        (devnet-smoke-gate-require
         (string= "GET, POST, OPTIONS"
                  (devnet-smoke-gate-http-header
                   preflight-response
                   "Access-Control-Allow-Methods"))
         "Public CORS preflight methods header mismatch")
        (devnet-smoke-gate-require
         (string= "Authorization, Content-Type"
                  (devnet-smoke-gate-http-header
                   preflight-response
                   "Access-Control-Allow-Headers"))
         "Public CORS preflight allowed-headers mismatch")
        (devnet-smoke-gate-require
         (string= "https://observer.example"
                  (devnet-smoke-gate-http-header
                   post-response
                   "Access-Control-Allow-Origin"))
         "Public CORS JSON-RPC origin header mismatch")
        (devnet-smoke-gate-require
         (string= "Origin"
                  (devnet-smoke-gate-http-header post-response "Vary"))
         "Public CORS JSON-RPC Vary header mismatch")
        (devnet-smoke-gate-require
         (string= "0x539" post-chain-id)
         "Public CORS JSON-RPC chain id mismatch")
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Public CORS Engine connection count mismatch")
        (devnet-smoke-gate-require
         (= +devnet-smoke-gate-public-cors-connections+
            (getf summary :public-connections))
         "Public CORS public connection count mismatch")
        (devnet-smoke-gate-require
         (equal *devnet-smoke-gate-public-cors-origins* reported-origins)
         "Public CORS summary origins mismatch")
        (devnet-smoke-gate-require
         (string= "https://runner.example,https://observer.example"
                  telemetry-origins)
         "Public CORS telemetry origins mismatch")
        (list :origins (copy-list *devnet-smoke-gate-public-cors-origins*)
              :reported-origins reported-origins
              :telemetry-origins telemetry-origins
              :preflight-status (devnet-cli-http-status preflight-response)
              :post-status (devnet-cli-http-status post-response)
              :blocked-status (devnet-cli-http-status blocked-response)
              :engine-connections (getf summary :engine-connections)
              :public-connections (getf summary :public-connections)
              :total-connections (getf summary :total-connections)))))
  #-sbcl
  (error "Public CORS smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-engine-cors ()
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-engine-cors-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path
                     (namestring
                      (devnet-smoke-gate-reference-path
                       +devnet-cli-genesis-fixture+))
                     :port 8551
                     :public-port 8545
                     :jwt-secret-path (namestring jwt-path)
                     :engine-cors-origins
                     *devnet-smoke-gate-engine-cors-origins*))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (engine-body
                    (devnet-smoke-gate-json-rpc-request
                     451
                     "engine_getClientVersionV1"
                     (list
                      (list (cons "code" "TT")
                            (cons "name" "test")
                            (cons "version" "1.1.1")
                            (cons "commit" "0x12345678")))))
                  (preflight-output (make-string-output-stream))
                  (post-output (make-string-output-stream))
                  (blocked-output (make-string-output-stream))
                  (engine-served-count 0)
                  (engine-done-p nil)
                  (engine-requests
                    (list
                     (cons
                      (devnet-smoke-gate-http-request
                       "OPTIONS" "/" :origin
                       "https://engine-runner.example")
                      preflight-output)
                     (cons
                      (devnet-cli-json-rpc-http-request
                       engine-body
                       :token token
                       :origin "https://engine-observer.example")
                      post-output)
                     (cons
                      (devnet-smoke-gate-http-request
                       "OPTIONS" "/" :origin
                       "https://blocked-engine.example")
                      blocked-output)))
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "engine-cors-engine"
                      :accept-function
                      (lambda ()
                        (when engine-requests
                          (destructuring-bind (request . output)
                              (pop engine-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function
                             (lambda ()
                               (incf engine-served-count)
                               (when (= engine-served-count
                                        +devnet-smoke-gate-engine-cors-connections+)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "engine-cors-public"
                      :accept-function
                      (lambda ()
                        (loop until engine-done-p
                              do (sleep 0.001))
                        nil)
                      :close-function (lambda () nil))
                     :max-connections
                     +devnet-smoke-gate-engine-cors-connections+))
                  (preflight-response
                    (get-output-stream-string preflight-output))
                  (post-response
                    (get-output-stream-string post-output))
                  (blocked-response
                    (get-output-stream-string blocked-output))
                  (post-rpc
                    (devnet-smoke-gate-rpc-body post-response))
                  (post-result
                    (first (fixture-object-field post-rpc "result")))
                  (summary-json
                    (ethereum-lisp.cli::devnet-node-summary-json-object
                     node))
                  (telemetry-fields
                    (ethereum-lisp.cli::devnet-node-telemetry-fields node))
                  (reported-origins
                    (cdr (assoc "engineCorsOrigins"
                                summary-json
                                :test #'string=)))
                  (telemetry-origins
                    (cdr (assoc "engineCorsOrigins"
                                telemetry-fields
                                :test #'string=))))
             (devnet-smoke-gate-require
              (= 204 (devnet-cli-http-status preflight-response))
              "Engine CORS preflight status mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status post-response))
              "Engine CORS JSON-RPC status mismatch")
             (devnet-smoke-gate-require
              (= 403 (devnet-cli-http-status blocked-response))
              "Engine CORS blocked-origin status mismatch")
             (devnet-smoke-gate-require
              (string= "https://engine-runner.example"
                       (devnet-smoke-gate-http-header
                        preflight-response
                        "Access-Control-Allow-Origin"))
              "Engine CORS preflight origin header mismatch")
             (devnet-smoke-gate-require
              (string= "GET, POST, OPTIONS"
                       (devnet-smoke-gate-http-header
                        preflight-response
                        "Access-Control-Allow-Methods"))
              "Engine CORS preflight methods header mismatch")
             (devnet-smoke-gate-require
              (string= "Authorization, Content-Type"
                       (devnet-smoke-gate-http-header
                        preflight-response
                        "Access-Control-Allow-Headers"))
              "Engine CORS preflight allowed-headers mismatch")
             (devnet-smoke-gate-require
              (string= "https://engine-observer.example"
                       (devnet-smoke-gate-http-header
                        post-response
                        "Access-Control-Allow-Origin"))
              "Engine CORS JSON-RPC origin header mismatch")
             (devnet-smoke-gate-require
              (string= "Origin"
                       (devnet-smoke-gate-http-header post-response "Vary"))
              "Engine CORS JSON-RPC Vary header mismatch")
             (devnet-smoke-gate-require
              (string= "ethereum-lisp"
                       (fixture-object-field post-result "name"))
              "Engine CORS JSON-RPC client version mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-engine-cors-connections+
                 (getf summary :engine-connections))
              "Engine CORS Engine connection count mismatch")
             (devnet-smoke-gate-require
              (= 0 (getf summary :public-connections))
              "Engine CORS public connection count mismatch")
             (devnet-smoke-gate-require
              (equal *devnet-smoke-gate-engine-cors-origins*
                     reported-origins)
              "Engine CORS summary origins mismatch")
             (devnet-smoke-gate-require
              (string= "https://engine-runner.example,https://engine-observer.example"
                       telemetry-origins)
              "Engine CORS telemetry origins mismatch")
             (list :origins
                   (copy-list *devnet-smoke-gate-engine-cors-origins*)
                   :reported-origins reported-origins
                   :telemetry-origins telemetry-origins
                   :preflight-status
                   (devnet-cli-http-status preflight-response)
                   :post-status (devnet-cli-http-status post-response)
                   :blocked-status
                   (devnet-cli-http-status blocked-response)
                   :engine-connections
                   (getf summary :engine-connections)
                   :public-connections
                   (getf summary :public-connections)
                   :total-connections
                   (getf summary :total-connections))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (error "Engine CORS smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-http-shaping ()
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-http-shaping-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path
                     (namestring
                      (devnet-smoke-gate-reference-path
                       +devnet-cli-genesis-fixture+))
                     :port 8551
                     :public-port 8545
                     :jwt-secret-path (namestring jwt-path)))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (engine-body
                    (devnet-smoke-gate-json-rpc-request
                     461
                     "engine_getClientVersionV1"
                     (list
                      (list (cons "code" "TT")
                            (cons "name" "test")
                            (cons "version" "1.1.1")
                            (cons "commit" "0x12345678")))))
                  (public-body
                    (devnet-smoke-gate-json-rpc-request
                     462 "eth_chainId" '()))
                  (engine-method-output (make-string-output-stream))
                  (engine-content-type-output (make-string-output-stream))
                  (public-method-output (make-string-output-stream))
                  (public-content-type-output (make-string-output-stream))
                  (engine-served-count 0)
                  (engine-done-p nil)
                  (engine-requests
                    (list
                     (cons
                      (devnet-smoke-gate-http-request
                       "PUT" "/"
                       :content-type "application/json"
                       :authorization (format nil "Bearer ~A" token)
                       :body engine-body)
                      engine-method-output)
                     (cons
                      (devnet-smoke-gate-http-request
                       "POST" "/"
                       :content-type "text/plain"
                       :authorization (format nil "Bearer ~A" token)
                       :body engine-body)
                      engine-content-type-output)))
                  (public-requests
                    (list
                     (cons
                      (devnet-smoke-gate-http-request
                       "PUT" "/"
                       :content-type "application/json"
                       :body public-body)
                      public-method-output)
                     (cons
                      (devnet-smoke-gate-http-request
                       "POST" "/"
                       :content-type "text/plain"
                       :body public-body)
                      public-content-type-output)))
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "http-shaping-engine"
                      :accept-function
                      (lambda ()
                        (when engine-requests
                          (destructuring-bind (request . output)
                              (pop engine-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function
                             (lambda ()
                               (incf engine-served-count)
                               (when (= engine-served-count
                                        +devnet-smoke-gate-http-shaping-engine-connections+)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "http-shaping-public"
                      :accept-function
                      (lambda ()
                        (loop until engine-done-p
                              do (sleep 0.001))
                        (when public-requests
                          (destructuring-bind (request . output)
                              (pop public-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function (lambda () nil)))))
                      :close-function (lambda () nil))
                     :max-connections
                     +devnet-smoke-gate-http-shaping-public-connections+))
                  (engine-method-response
                    (get-output-stream-string engine-method-output))
                  (engine-content-type-response
                    (get-output-stream-string engine-content-type-output))
                  (public-method-response
                    (get-output-stream-string public-method-output))
                  (public-content-type-response
                    (get-output-stream-string public-content-type-output)))
             (devnet-smoke-gate-require
              (= 405 (devnet-cli-http-status engine-method-response))
              "Engine HTTP method rejection status mismatch")
             (devnet-smoke-gate-require
              (search "method not allowed"
                      (devnet-cli-http-body engine-method-response))
              "Engine HTTP method rejection body mismatch")
             (devnet-smoke-gate-require
              (= 415 (devnet-cli-http-status engine-content-type-response))
              "Engine HTTP content-type rejection status mismatch")
             (devnet-smoke-gate-require
              (search "invalid content type"
                      (devnet-cli-http-body engine-content-type-response))
              "Engine HTTP content-type rejection body mismatch")
             (devnet-smoke-gate-require
              (= 405 (devnet-cli-http-status public-method-response))
              "Public HTTP method rejection status mismatch")
             (devnet-smoke-gate-require
              (search "method not allowed"
                      (devnet-cli-http-body public-method-response))
              "Public HTTP method rejection body mismatch")
             (devnet-smoke-gate-require
              (= 415 (devnet-cli-http-status public-content-type-response))
              "Public HTTP content-type rejection status mismatch")
             (devnet-smoke-gate-require
              (search "invalid content type"
                      (devnet-cli-http-body public-content-type-response))
              "Public HTTP content-type rejection body mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-http-shaping-engine-connections+
                 (getf summary :engine-connections))
              "HTTP shaping Engine connection count mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-http-shaping-public-connections+
                 (getf summary :public-connections))
              "HTTP shaping public connection count mismatch")
             (list :engine-method-status
                   (devnet-cli-http-status engine-method-response)
                   :engine-content-type-status
                   (devnet-cli-http-status engine-content-type-response)
                   :public-method-status
                   (devnet-cli-http-status public-method-response)
                   :public-content-type-status
                   (devnet-cli-http-status public-content-type-response)
                   :engine-connections
                   (getf summary :engine-connections)
                   :public-connections
                   (getf summary :public-connections)
                   :total-connections
                   (getf summary :total-connections))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (error "HTTP shaping smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-vhosts ()
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 8551
            :public-port 8545
            :engine-vhosts *devnet-smoke-gate-engine-vhosts*
            :public-vhosts *devnet-smoke-gate-public-vhosts*))
         (engine-output (make-string-output-stream))
         (blocked-engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (blocked-public-output (make-string-output-stream))
         (engine-requests
           (list
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :host "engine.runner"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     501 "engine_getClientVersionV1"
                     (list
                      (list (cons "code" "TT")
                            (cons "name" "test")
                            (cons "version" "1.1.1")
                            (cons "commit" "0x12345678")))))
             engine-output)
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :host "blocked.engine"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     502 "engine_getClientVersionV1" (list '())))
             blocked-engine-output)))
         (public-requests
           (list
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :host "public.runner"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     503 "eth_chainId" '()))
             public-output)
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :host "blocked.public"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     504 "eth_chainId" '()))
             blocked-public-output))))
    (dolist (request engine-requests)
      (destructuring-bind (request-string . output) request
        (engine-rpc-http-service-handle-stream
         (ethereum-lisp.cli:devnet-node-service node)
         (make-string-input-stream request-string)
         output)))
    (dolist (request public-requests)
      (destructuring-bind (request-string . output) request
        (engine-rpc-http-service-handle-stream
         (ethereum-lisp.cli:devnet-node-public-service node)
         (make-string-input-stream request-string)
         output)))
    (let ((engine-connection-count
            +devnet-smoke-gate-vhost-engine-connections+)
          (public-connection-count
            +devnet-smoke-gate-vhost-public-connections+))
      (let* ((engine-response (get-output-stream-string engine-output))
             (blocked-engine-response
               (get-output-stream-string blocked-engine-output))
             (public-response (get-output-stream-string public-output))
             (blocked-public-response
               (get-output-stream-string blocked-public-output))
             (summary-json
               (ethereum-lisp.cli::devnet-node-summary-json-object node))
             (telemetry-fields
               (ethereum-lisp.cli::devnet-node-telemetry-fields node))
             (reported-engine-vhosts
               (cdr (assoc "engineVhosts" summary-json :test #'string=)))
             (reported-public-vhosts
               (cdr (assoc "publicVhosts" summary-json :test #'string=)))
             (telemetry-engine-vhosts
               (cdr (assoc "engineVhosts" telemetry-fields :test #'string=)))
             (telemetry-public-vhosts
               (cdr (assoc "publicVhosts" telemetry-fields :test #'string=))))
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status engine-response))
         "Engine vhost allowed status mismatch")
        (devnet-smoke-gate-require
         (= 403 (devnet-cli-http-status blocked-engine-response))
         "Engine vhost blocked status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status public-response))
         "Public vhost allowed status mismatch")
        (devnet-smoke-gate-require
         (= 403 (devnet-cli-http-status blocked-public-response))
         "Public vhost blocked status mismatch")
        (devnet-smoke-gate-require
         (= +devnet-smoke-gate-vhost-engine-connections+
            engine-connection-count)
         "Vhost Engine connection count mismatch")
        (devnet-smoke-gate-require
         (= +devnet-smoke-gate-vhost-public-connections+
            public-connection-count)
         "Vhost public connection count mismatch")
        (devnet-smoke-gate-require
         (equal *devnet-smoke-gate-engine-vhosts* reported-engine-vhosts)
         "Vhost Engine summary mismatch")
        (devnet-smoke-gate-require
         (equal *devnet-smoke-gate-public-vhosts* reported-public-vhosts)
         "Vhost public summary mismatch")
        (devnet-smoke-gate-require
         (string= "engine.runner,localhost" telemetry-engine-vhosts)
         "Vhost Engine telemetry mismatch")
        (devnet-smoke-gate-require
         (string= "public.runner,localhost" telemetry-public-vhosts)
         "Vhost public telemetry mismatch")
        (list :engine-vhosts
              (copy-list *devnet-smoke-gate-engine-vhosts*)
              :public-vhosts
              (copy-list *devnet-smoke-gate-public-vhosts*)
              :reported-engine-vhosts reported-engine-vhosts
              :reported-public-vhosts reported-public-vhosts
              :telemetry-engine-vhosts telemetry-engine-vhosts
              :telemetry-public-vhosts telemetry-public-vhosts
              :engine-allowed-status
              (devnet-cli-http-status engine-response)
              :engine-blocked-status
              (devnet-cli-http-status blocked-engine-response)
              :public-allowed-status
              (devnet-cli-http-status public-response)
              :public-blocked-status
              (devnet-cli-http-status blocked-public-response)
              :engine-connections engine-connection-count
              :public-connections public-connection-count
              :total-connections
              (+ engine-connection-count public-connection-count)))))
  #-sbcl
  (error "Vhost smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-rpc-prefixes ()
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-rpc-prefix-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path
                     (namestring
                      (devnet-smoke-gate-reference-path
                       +devnet-cli-genesis-fixture+))
                     :port 8551
                     :public-port 8545
                     :jwt-secret-path (namestring jwt-path)
                     :engine-rpc-prefix
                     +devnet-smoke-gate-engine-rpc-prefix+
                     :public-rpc-prefix
                     +devnet-smoke-gate-public-rpc-prefix+))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (engine-body
                    (devnet-smoke-gate-json-rpc-request
                     601
                     "engine_getClientVersionV1"
                     (list
                      (list (cons "code" "TT")
                            (cons "name" "test")
                            (cons "version" "1.1.1")
                            (cons "commit" "0x12345678")))))
                  (public-body
                    (devnet-smoke-gate-json-rpc-request
                     602 "eth_chainId" '()))
                  (engine-output (make-string-output-stream))
                  (blocked-engine-output (make-string-output-stream))
                  (public-output (make-string-output-stream))
                  (blocked-public-output (make-string-output-stream))
                  (engine-served-count 0)
                  (public-served-count 0)
                  (engine-done-p nil)
                  (engine-requests
                    (list
                     (cons
                      (devnet-cli-json-rpc-http-request
                       engine-body
                       :token token
                       :target
                       +devnet-smoke-gate-engine-rpc-prefix+)
                      engine-output)
                     (cons
                      (devnet-cli-json-rpc-http-request
                       engine-body
                       :token token
                       :target "/")
                      blocked-engine-output)))
                  (public-requests
                    (list
                     (cons
                      (devnet-cli-json-rpc-http-request
                       public-body
                       :target
                       +devnet-smoke-gate-public-rpc-prefix+)
                      public-output)
                     (cons
                      (devnet-cli-json-rpc-http-request
                       public-body
                       :target "/")
                      blocked-public-output)))
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "rpc-prefix-engine"
                      :accept-function
                      (lambda ()
                        (when engine-requests
                          (destructuring-bind (request . output)
                              (pop engine-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function
                             (lambda ()
                               (incf engine-served-count)
                               (when (= engine-served-count
                                        +devnet-smoke-gate-rpc-prefix-engine-connections+)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "rpc-prefix-public"
                      :accept-function
                      (lambda ()
                        (loop until engine-done-p
                              do (sleep 0.001))
                        (when public-requests
                          (destructuring-bind (request . output)
                              (pop public-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function
                             (lambda () (incf public-served-count))))))
                      :close-function (lambda () nil))
                     :max-connections
                     +devnet-smoke-gate-rpc-prefix-engine-connections+))
                  (engine-response
                    (get-output-stream-string engine-output))
                  (blocked-engine-response
                    (get-output-stream-string blocked-engine-output))
                  (public-response
                    (get-output-stream-string public-output))
                  (blocked-public-response
                    (get-output-stream-string blocked-public-output))
                  (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
                  (public-rpc (devnet-smoke-gate-rpc-body public-response))
                  (summary-json
                    (ethereum-lisp.cli::devnet-node-summary-json-object
                     node))
                  (telemetry-fields
                    (ethereum-lisp.cli::devnet-node-telemetry-fields node))
                  (reported-engine-prefix
                    (cdr (assoc "engineRpcPrefix"
                                summary-json
                                :test #'string=)))
                  (reported-public-prefix
                    (cdr (assoc "publicRpcPrefix"
                                summary-json
                                :test #'string=)))
                  (telemetry-engine-prefix
                    (cdr (assoc "engineRpcPrefix"
                                telemetry-fields
                                :test #'string=)))
                  (telemetry-public-prefix
                    (cdr (assoc "publicRpcPrefix"
                                telemetry-fields
                                :test #'string=))))
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status engine-response))
              "Engine RPC prefix status mismatch")
             (devnet-smoke-gate-require
              (= 404 (devnet-cli-http-status blocked-engine-response))
              "Engine RPC blocked-prefix status mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status public-response))
              "Public RPC prefix status mismatch")
             (devnet-smoke-gate-require
              (= 404 (devnet-cli-http-status blocked-public-response))
              "Public RPC blocked-prefix status mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-rpc-prefix-engine-connections+
                 (getf summary :engine-connections))
              "RPC prefix Engine connection count mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-rpc-prefix-public-connections+
                 (getf summary :public-connections))
              "RPC prefix public connection count mismatch")
             (devnet-smoke-gate-require
              (= engine-served-count
                 (getf summary :engine-connections))
              "RPC prefix served Engine count mismatch")
             (devnet-smoke-gate-require
              (= public-served-count
                 (getf summary :public-connections))
              "RPC prefix served public count mismatch")
             (devnet-smoke-gate-require
              (string= "ethereum-lisp"
                       (fixture-object-field
                        (first (fixture-object-field engine-rpc "result"))
                        "name"))
              "Engine RPC prefix client-version result mismatch")
             (devnet-smoke-gate-require
              (string= "0x539" (fixture-object-field public-rpc "result"))
              "Public RPC prefix chain id mismatch")
             (devnet-smoke-gate-require
              (string= +devnet-smoke-gate-engine-rpc-prefix+
                       reported-engine-prefix)
              "Engine RPC prefix summary mismatch")
             (devnet-smoke-gate-require
              (string= +devnet-smoke-gate-public-rpc-prefix+
                       reported-public-prefix)
              "Public RPC prefix summary mismatch")
             (devnet-smoke-gate-require
              (string= +devnet-smoke-gate-engine-rpc-prefix+
                       telemetry-engine-prefix)
              "Engine RPC prefix telemetry mismatch")
             (devnet-smoke-gate-require
              (string= +devnet-smoke-gate-public-rpc-prefix+
                       telemetry-public-prefix)
              "Public RPC prefix telemetry mismatch")
             (list :engine-prefix +devnet-smoke-gate-engine-rpc-prefix+
                   :public-prefix +devnet-smoke-gate-public-rpc-prefix+
                   :reported-engine-prefix reported-engine-prefix
                   :reported-public-prefix reported-public-prefix
                   :telemetry-engine-prefix telemetry-engine-prefix
                   :telemetry-public-prefix telemetry-public-prefix
                   :engine-status (devnet-cli-http-status engine-response)
                   :engine-blocked-status
                   (devnet-cli-http-status blocked-engine-response)
                   :public-status (devnet-cli-http-status public-response)
                   :public-blocked-status
                   (devnet-cli-http-status blocked-public-response)
                   :engine-connections (getf summary :engine-connections)
                   :public-connections (getf summary :public-connections)
                   :total-connections
                   (getf summary :total-connections))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (error "RPC prefix smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-execution-spec-tests-source ()
  (list
   (cons "repository" +devnet-smoke-gate-eest-repository+)
   (cons "release" +devnet-smoke-gate-eest-release+)
   (cons "tagTarget" +devnet-smoke-gate-eest-tag-target+)
   (cons "archive" +devnet-smoke-gate-eest-archive+)))

(defun devnet-smoke-gate-add-run-metadata (report)
  (append
   (list
    (cons "executionSpecTests"
          (devnet-smoke-gate-execution-spec-tests-source))
    (cons "referenceClients" (devnet-smoke-gate-reference-clients)))
   report))

(defun devnet-smoke-gate-strip-run-metadata (report)
  (remove-if (lambda (entry)
               (member (car entry)
                       '("executionSpecTests" "referenceClients")
                       :test #'string=))
             report))

(defun devnet-smoke-gate-balance-target (expect)
  (cond
    ((fixture-field-present-p expect "recipient")
     (values (fixture-address-field expect "recipient")
             (fixture-object-field expect "recipientBalance")
             "recipientBalance"))
    ((fixture-field-present-p expect "contractAddress")
     (values (fixture-address-field expect "contractAddress")
             (fixture-object-field expect "contractBalance")
             "contractBalance"))
    (t
     (error "Devnet smoke gate fixture expect must contain recipient or contractAddress"))))

(defun devnet-smoke-gate-balance-targets (expect)
  (cond
    ((fixture-field-present-p expect "recipients")
     (loop for recipient in (fixture-object-field expect "recipients")
           for balance in (fixture-object-field expect "recipientBalances")
           collect (list :address (address-from-hex recipient)
                         :balance balance
                         :field "recipientBalance")))
    (t
     (multiple-value-bind (address balance field)
         (devnet-smoke-gate-balance-target expect)
       (list (list :address address :balance balance :field field))))))

(defun devnet-smoke-gate-checkpoint-balance-targets
    (state balance-targets)
  (loop for target in balance-targets
        for address = (getf target :address)
        collect (list :address address
                      :balance (quantity-to-hex
                                (fixture-account-balance state address))
                      :field (getf target :field))))

(defun devnet-smoke-gate-transaction-checks (block)
  (loop for transaction in (block-transactions block)
        collect (list :hash (transaction-hash transaction)
                      :raw (bytes-to-hex
                            (transaction-encoding transaction)))))

(defun devnet-smoke-gate-log-targets (expect)
  (if (fixture-field-present-p expect "logAddress")
      (list
       (list :address (fixture-address-field expect "logAddress")
             :topic (fixture-object-field expect "logTopic")
             :data (fixture-object-field expect "logData")
             :count (hex-to-quantity
                     (fixture-object-field expect "logCount"))))
      '()))

(defun devnet-smoke-gate-verify-rpc-log
    (log target expected-block-number block-hash transaction-hash
     transaction-index log-index context)
  (devnet-smoke-gate-require
   log
   "~A missing expected log" context)
  (devnet-smoke-gate-require
   (string= (address-to-hex (getf target :address))
            (fixture-object-field log "address"))
   "~A log address mismatch" context)
  (devnet-smoke-gate-require
   (string= (getf target :data)
            (fixture-object-field log "data"))
   "~A log data mismatch" context)
  (devnet-smoke-gate-require
   (equal (list (getf target :topic))
          (fixture-object-field log "topics"))
   "~A log topics mismatch" context)
  (devnet-smoke-gate-require
   (string= expected-block-number
            (fixture-object-field log "blockNumber"))
   "~A log block number mismatch" context)
  (devnet-smoke-gate-require
   (string= (hash32-to-hex block-hash)
            (fixture-object-field log "blockHash"))
   "~A log block hash mismatch" context)
  (devnet-smoke-gate-require
   (string= (hash32-to-hex transaction-hash)
            (fixture-object-field log "transactionHash"))
   "~A log transaction hash mismatch" context)
  (devnet-smoke-gate-require
   (string= (quantity-to-hex transaction-index)
            (fixture-object-field log "transactionIndex"))
   "~A log transaction index mismatch" context)
  (devnet-smoke-gate-require
   (string= (quantity-to-hex log-index)
            (fixture-object-field log "logIndex"))
   "~A log index mismatch" context)
  log)

(defun devnet-smoke-gate-simulation-call-object
    (sender-address target-address)
  (list (cons "from" (address-to-hex sender-address))
        (cons "to" (address-to-hex target-address))
        (cons "gas" +devnet-smoke-gate-simulation-gas+)
        (cons "gasPrice" "0x64")
        (cons "data" "0x")))

(defun devnet-smoke-gate-state-error-probes
    (start-id block-id expected-errors
     balance-address sender-address code-address storage-address storage-key)
  (labels ((request (id method params)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" method)
                   (cons "params" params)))
           (probe (id method expected-error params)
             (list :method method
                   :expected-error expected-error
                   :output (make-string-output-stream)
                   :request (request id method params))))
    (destructuring-bind
        (balance-error nonce-error code-error storage-error proof-error
         call-error estimate-error access-list-error)
        expected-errors
      (list
       (probe start-id
              "eth_getBalance"
              balance-error
              (list (address-to-hex balance-address) block-id))
       (probe (+ start-id 1)
              "eth_getTransactionCount"
              nonce-error
              (list (address-to-hex sender-address) block-id))
       (probe (+ start-id 2)
              "eth_getCode"
              code-error
              (list (address-to-hex code-address) block-id))
       (probe (+ start-id 3)
              "eth_getStorageAt"
              storage-error
              (list (address-to-hex storage-address) storage-key block-id))
       (probe (+ start-id 4)
              "eth_getProof"
              proof-error
              (list (address-to-hex storage-address)
                    (list storage-key)
                    block-id))
       (probe (+ start-id 5)
              "eth_call"
              call-error
              (list
               (devnet-smoke-gate-simulation-call-object
                sender-address code-address)
               block-id))
       (probe (+ start-id 6)
              "eth_estimateGas"
              estimate-error
              (list
               (devnet-smoke-gate-simulation-call-object
                sender-address code-address)
               block-id))
       (probe (+ start-id 7)
              "eth_createAccessList"
              access-list-error
              (list
               (devnet-smoke-gate-simulation-call-object
                sender-address code-address)
               block-id))))))

(defun devnet-smoke-gate-verify-state-error-probes (probes label)
  (mapcar
   (lambda (probe)
     (let* ((response
              (get-output-stream-string (getf probe :output)))
            (rpc (devnet-smoke-gate-rpc-body response))
            (error (fixture-object-field rpc "error"))
            (message
              (and error
                   (fixture-object-field error "message"))))
       (devnet-smoke-gate-require
        (= 200 (devnet-cli-http-status response))
        "Restored ~A ~A HTTP status mismatch"
        label
        (getf probe :method))
       (devnet-smoke-gate-require
        error
        "Restored ~A ~A did not return an error"
        label
        (getf probe :method))
       (devnet-smoke-gate-require
        (string= (getf probe :expected-error) message)
        "Restored ~A ~A error mismatch: ~A"
        label
        (getf probe :method)
        message)
       message))
   probes))

(defun devnet-smoke-gate-payload-attributes-v2
    (parent-block suggested-fee-recipient)
  (let ((parent-header (block-header parent-block)))
    (list (cons "timestamp"
                (quantity-to-hex
                 (1+ (block-header-timestamp parent-header))))
          (cons "prevRandao" (hash32-to-hex (zero-hash32)))
          (cons "suggestedFeeRecipient"
                (address-to-hex suggested-fee-recipient))
          (cons "withdrawals" '()))))

(defun devnet-smoke-gate-forkchoice-v2-payload-attributes-request
    (id head payload-attributes
     &key (safe (zero-hash32)) (finalized (zero-hash32)))
  (let ((request (devnet-cli-engine-forkchoice-v2-request
                  id head :safe safe :finalized finalized)))
    (setf (cdr (assoc "params" request :test #'string=))
          (list (first (fixture-object-field request "params"))
                payload-attributes))
    request))

(defun devnet-smoke-gate-remote-block (parent-block)
  (let ((parent-header (block-header parent-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash
      (hash32-from-hex
       "0x9999999999999999999999999999999999999999999999999999999999999999")
      :beneficiary (block-header-beneficiary parent-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number parent-header))
      :gas-limit (block-header-gas-limit parent-header)
      :gas-used 0
      :timestamp (1+ (block-header-timestamp parent-header))
      :base-fee-per-gas (block-header-base-fee-per-gas parent-header))
     :withdrawals '())))

(defun devnet-smoke-gate-invalid-child-block (parent-block)
  (let ((parent-header (block-header parent-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash (block-hash parent-block)
      :beneficiary (block-header-beneficiary parent-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number parent-header))
      :gas-limit (block-header-gas-limit parent-header)
      :gas-used 0
      :timestamp (block-header-timestamp parent-header)
      :base-fee-per-gas (block-header-base-fee-per-gas parent-header))
     :withdrawals '())))

(defun devnet-smoke-gate-invalid-grandchild-block (invalid-block)
  (let ((invalid-header (block-header invalid-block)))
    (make-block
     :header
     (make-block-header
      :parent-hash (block-hash invalid-block)
      :beneficiary (block-header-beneficiary invalid-header)
      :state-root +empty-trie-hash+
      :mix-hash (zero-hash32)
      :number (1+ (block-header-number invalid-header))
      :gas-limit (block-header-gas-limit invalid-header)
      :gas-used 0
      :timestamp (1+ (block-header-timestamp invalid-header))
      :base-fee-per-gas (block-header-base-fee-per-gas invalid-header))
     :withdrawals '())))

(defun devnet-smoke-gate-side-sibling-block
    (parent-block parent-state config payload-case withdrawals fee-recipient)
  (let* ((side-state (state-db-copy parent-state))
         (side-header
           (make-block-header
            :parent-hash (block-hash parent-block)
            :beneficiary fee-recipient
            :mix-hash
            (hash32-from-hex
             "0x0300000000000000000000000000000000000000000000000000000000000000")
            :number (fixture-quantity-field payload-case "number")
            :gas-limit (fixture-quantity-field payload-case "gasLimit")
            :gas-used 0
            :timestamp (1+ (fixture-quantity-field payload-case "timestamp"))
            :base-fee-per-gas
            (fixture-quantity-field payload-case "baseFeePerGas"))))
    (execute-signed-block
     side-state
     '()
     :expected-chain-id (chain-config-chain-id config)
     :header side-header
     :chain-config config
     :withdrawals withdrawals)))

(defun devnet-smoke-gate-access-list-entry (access-list address)
  (find (address-to-hex address)
        access-list
        :test #'string=
        :key (lambda (entry)
               (fixture-object-field entry "address"))))

(defun devnet-smoke-gate-executable-code-p (code)
  (and (stringp code)
       (> (length code) 2)
       (not (string= code "0x00"))))

(defun devnet-smoke-gate-http-endpoint-p (endpoint)
  (and (stringp endpoint)
       (or (uiop:string-prefix-p "http://127.0.0.1:" endpoint)
           (uiop:string-prefix-p "http://localhost:" endpoint))))

(defun devnet-smoke-gate-verify-ready-file
    (path expected-head-number expected-head-hash
     &key expected-head-gas-limit expected-engine-endpoint
       expected-rpc-endpoint)
  (let ((summary (parse-json (devnet-smoke-gate-file-string path))))
    (devnet-smoke-gate-require
     (string= (or expected-engine-endpoint +devnet-smoke-gate-engine-endpoint+)
              (fixture-object-field summary "engineEndpoint"))
     "Ready file Engine endpoint mismatch")
    (devnet-smoke-gate-require
     (string= (or expected-rpc-endpoint +devnet-smoke-gate-public-endpoint+)
              (fixture-object-field summary "rpcEndpoint"))
     "Ready file public RPC endpoint mismatch")
    (devnet-smoke-gate-require
     (devnet-smoke-gate-http-endpoint-p
      (fixture-object-field summary "engineEndpoint"))
     "Ready file Engine endpoint must be an HTTP loopback endpoint")
    (devnet-smoke-gate-require
     (devnet-smoke-gate-http-endpoint-p
      (fixture-object-field summary "rpcEndpoint"))
     "Ready file public RPC endpoint must be an HTTP loopback endpoint")
    (devnet-smoke-gate-require
     (eq t (fixture-object-field summary "authRequired"))
     "Ready file must report authenticated Engine RPC")
    (devnet-smoke-gate-require
     (eq t (fixture-object-field summary "stateAvailable"))
     "Ready file must report available head state")
    (devnet-smoke-gate-require
     (integerp (fixture-object-field summary "processId"))
     "Ready file processId must be an integer")
    (devnet-smoke-gate-require
     (< 0 (fixture-object-field summary "processId"))
     "Ready file processId must be positive")
    (devnet-smoke-gate-require
     (string= expected-head-number
              (quantity-to-hex
               (fixture-object-field summary "headNumber")))
     "Ready file head number mismatch")
    (devnet-smoke-gate-require
     (string= expected-head-hash
              (fixture-object-field summary "headHash"))
     "Ready file head hash mismatch")
    (when expected-head-gas-limit
      (devnet-smoke-gate-require
       (string= expected-head-gas-limit
                (quantity-to-hex
                 (fixture-object-field summary "headGasLimit")))
       "Ready file head gas limit mismatch"))
    summary))

(defun devnet-smoke-gate-verify-pid-file
    (path &key expected-process-id)
  (let ((process-id
          (parse-integer
           (string-trim '(#\Space #\Tab #\Newline #\Return)
                        (devnet-smoke-gate-file-string path))
           :junk-allowed nil)))
    (devnet-smoke-gate-require
     (< 0 process-id)
     "PID file process id must be positive")
    (when expected-process-id
      (devnet-smoke-gate-require
       (= expected-process-id process-id)
       "PID file process id mismatch"))
    process-id))

(defun devnet-smoke-gate-connection-count-string (summary key)
  (write-to-string (or (getf summary key) 0)))

(defun devnet-smoke-gate-verify-log-file
    (path ready-head-number ready-head-hash shutdown-head-number
     shutdown-head-hash &key expected-process-id expected-connection-summary
       ready-head-gas-limit shutdown-head-gas-limit
       expected-engine-endpoint expected-rpc-endpoint)
  (let* ((records (devnet-smoke-gate-file-forms path))
         (names (mapcar (lambda (record) (getf record :name)) records)))
    (devnet-smoke-gate-require
     (member "devnet.ready" names :test #'string=)
     "Log file missing devnet.ready event")
    (devnet-smoke-gate-require
     (member "devnet.shutdown" names :test #'string=)
     "Log file missing devnet.shutdown event")
    (dolist (record records)
      (when (member (getf record :name)
                    '("devnet.ready" "devnet.shutdown")
                    :test #'string=)
        (let* ((fields (getf record :fields))
               (ready-p (string= "devnet.ready" (getf record :name)))
               (expected-head-number
                 (if ready-p ready-head-number shutdown-head-number))
               (expected-head-hash
                 (if ready-p ready-head-hash shutdown-head-hash))
               (expected-head-gas-limit
                 (if ready-p ready-head-gas-limit shutdown-head-gas-limit)))
          (devnet-smoke-gate-require
           (string= (or expected-engine-endpoint
                        +devnet-smoke-gate-engine-endpoint+)
                    (cdr (assoc "engineEndpoint" fields :test #'string=)))
           "Log file Engine endpoint mismatch")
          (devnet-smoke-gate-require
           (string= (or expected-rpc-endpoint
                        +devnet-smoke-gate-public-endpoint+)
                    (cdr (assoc "rpcEndpoint" fields :test #'string=)))
           "Log file public RPC endpoint mismatch")
          (devnet-smoke-gate-require
           (devnet-smoke-gate-http-endpoint-p
            (cdr (assoc "engineEndpoint" fields :test #'string=)))
           "Log file Engine endpoint must be an HTTP loopback endpoint")
          (devnet-smoke-gate-require
           (devnet-smoke-gate-http-endpoint-p
            (cdr (assoc "rpcEndpoint" fields :test #'string=)))
           "Log file public RPC endpoint must be an HTTP loopback endpoint")
          (devnet-smoke-gate-require
           (string= (if ready-p "ready" "shutdown")
                    (cdr (assoc "lifecyclePhase" fields :test #'string=)))
           "Log file lifecycle phase mismatch")
          (devnet-smoke-gate-require
           (string= (if ready-p
                        "0"
                        (devnet-smoke-gate-connection-count-string
                         expected-connection-summary
                         :engine-connections))
                    (cdr (assoc "engineConnections" fields :test #'string=)))
           "Log file Engine connection count mismatch")
          (devnet-smoke-gate-require
           (string= (if ready-p
                        "0"
                        (devnet-smoke-gate-connection-count-string
                         expected-connection-summary
                         :public-connections))
                    (cdr (assoc "publicConnections" fields :test #'string=)))
           "Log file public connection count mismatch")
          (devnet-smoke-gate-require
           (string= (if ready-p
                        "0"
                        (devnet-smoke-gate-connection-count-string
                         expected-connection-summary
                         :total-connections))
                    (cdr (assoc "totalConnections" fields :test #'string=)))
           "Log file total connection count mismatch")
          (when expected-process-id
            (devnet-smoke-gate-require
             (string= (write-to-string expected-process-id)
                      (cdr (assoc "processId" fields :test #'string=)))
             "Log file processId mismatch"))
          (devnet-smoke-gate-require
           (string= expected-head-number
                    (cdr (assoc "headNumber" fields :test #'string=)))
           "Log file head number mismatch")
          (devnet-smoke-gate-require
           (string= expected-head-hash
                    (cdr (assoc "headHash" fields :test #'string=)))
           "Log file head hash mismatch")
          (when expected-head-gas-limit
            (devnet-smoke-gate-require
             (string= expected-head-gas-limit
                      (cdr (assoc "headGasLimit" fields :test #'string=)))
             "Log file head gas limit mismatch"))
          (devnet-smoke-gate-require
           (string= "true"
                    (cdr (assoc "stateAvailable" fields :test #'string=)))
           "Log file state availability mismatch"))))
    records))

(defun devnet-smoke-gate-verify-engine-only-serve
    (&key ready-file log-file pid-file database-file)
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-engine-only" "jwt"))
        (genesis-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-engine-only-genesis"
           "json"))
        (client-thread nil)
        (client-response nil)
        (blocked-client-response nil)
        (capabilities-response nil)
        (capabilities-result nil)
        (transition-configuration-response nil)
        (transition-configuration-result nil)
        (transition-configuration-mismatch-response nil)
        (transition-configuration-mismatch-error nil)
        (new-payload-response nil)
        (forkchoice-response nil)
        (client-version nil)
        (client-error nil)
        (engine-endpoint nil)
        (configured-public-endpoint nil)
        (public-endpoint-connectable-p nil)
        (database-summary nil)
        (report nil))
    (unwind-protect
         (progn
           (devnet-smoke-gate-call-with-telemetry-sink
            log-file
            (lambda (telemetry-sink)
              (let* ((fixture
                       (devnet-smoke-gate-engine-fixture
                        +devnet-smoke-gate-default-fixture-case+))
                     (case
                       (devnet-smoke-gate-field fixture "case"))
                     (parent-block
                       (devnet-smoke-gate-field fixture "parentBlock"))
                     (child-block
                       (devnet-smoke-gate-field fixture "childBlock"))
                     (payload
                       (devnet-smoke-gate-field fixture "payload"))
                     (expected-child-hash
                       (hash32-to-hex (block-hash child-block)))
                     (expected-child-number
                       (quantity-to-hex
                        (block-header-number
                         (block-header child-block))))
                     (fixture-inputs-written-p
                       (progn
                         (devnet-cli-write-temp-file
                          genesis-path
                          (json-encode
                           (devnet-cli-engine-fixture-parent-genesis-with-txpool-account
                            case)))
                         (devnet-cli-write-temp-file
                          jwt-path
                          +devnet-cli-jwt-secret+)
                         t))
                     (node
                       (ethereum-lisp.cli:make-devnet-node
                        :genesis-path
                        (namestring genesis-path)
                        :port 0
                        :public-port (devnet-cli-unused-loopback-port)
                        :jwt-secret-path (namestring jwt-path)
                        :engine-rpc-prefix +devnet-smoke-gate-engine-rpc-prefix+
                        :engine-cors-origins
                        *devnet-smoke-gate-engine-cors-origins*
                        :engine-vhosts *devnet-smoke-gate-engine-vhosts*
                        :log-path log-file
                        :database-path database-file
                        :pid-file-path pid-file
                        :telemetry-sink telemetry-sink))
                  (genesis-block
                    (ethereum-lisp.cli::devnet-node-genesis-block node))
                  (head-number
                    (quantity-to-hex
                     (block-header-number (block-header genesis-block))))
                  (head-hash (hash32-to-hex (block-hash genesis-block)))
                  (head-gas-limit
                    (quantity-to-hex
                     (block-header-gas-limit
                      (block-header genesis-block))))
                  (jwt-secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token jwt-secret 0))
                  (engine-body
                    "{\"jsonrpc\":\"2.0\",\"id\":901,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"runner\",\"name\":\"engine-only-smoke\",\"version\":\"1\",\"commit\":\"0x00000000\"}]}")
                  (capabilities-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 904)
                      (cons "method" "engine_exchangeCapabilities")
                      (cons "params"
                            (list
                             (list
                              "engine_newPayloadV1"
                              "engine_forkchoiceUpdatedV1"
                              "engine_getPayloadV1"
                              "engine_newPayloadV2"
                              "engine_forkchoiceUpdatedV2"
                              "engine_getPayloadV2"))))))
                  (transition-configuration-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 905)
                      (cons "method"
                            "engine_exchangeTransitionConfigurationV1")
                      (cons "params"
                            (list
                             (list
                              (cons "terminalTotalDifficulty" "0x0")
                              (cons "terminalBlockHash"
                                    (hash32-to-hex (zero-hash32)))
                              (cons "terminalBlockNumber" "0x0")))))))
                  (transition-configuration-mismatch-body
                    (json-encode
                     (list
                      (cons "jsonrpc" "2.0")
                      (cons "id" 906)
                      (cons "method"
                            "engine_exchangeTransitionConfigurationV1")
                      (cons "params"
                            (list
                             (list
                              (cons "terminalTotalDifficulty" "0x1")
                              (cons "terminalBlockHash"
                                    (hash32-to-hex (zero-hash32)))
                              (cons "terminalBlockNumber" "0x0")))))))
                  (new-payload-body
                    (json-encode
                     (engine-fixture-payload-request 902 payload)))
                  (forkchoice-body
                    (json-encode
                     (devnet-cli-engine-forkchoice-v2-request
                      903
                      (block-hash child-block)
                      :safe (block-hash parent-block)
                      :finalized (block-hash parent-block)))))
             (declare (ignore fixture-inputs-written-p))
             (setf configured-public-endpoint
                   (format nil "http://127.0.0.1:~D"
                           (ethereum-lisp.core::engine-rpc-http-service-port
                            (ethereum-lisp.cli:devnet-node-public-service
                             node))))
             (when pid-file
               (ethereum-lisp.cli::devnet-cli-write-pid-file pid-file))
             (let ((summary
                      (ethereum-lisp.cli:start-devnet-node
                      node
                      :max-connections 7
                      :public-rpc-enabled-p nil
                      :on-listeners-ready
                      (lambda (engine-listener public-listener)
                        (declare (ignore public-listener))
                        (let ((raw-engine-endpoint
                                (engine-rpc-http-listener-endpoint
                                 engine-listener)))
                          (setf engine-endpoint
                                (if (uiop:string-prefix-p
                                     "http://"
                                     raw-engine-endpoint)
                                    raw-engine-endpoint
                                    (format nil "http://~A"
                                            raw-engine-endpoint))))
                        (when ready-file
                          (ethereum-lisp.cli::devnet-cli-write-ready-file
                           node
                           ready-file
                           :engine-endpoint engine-endpoint
                           :rpc-endpoint nil
                           :public-rpc-enabled-p nil))
                        (when log-file
                          (ethereum-lisp.cli::devnet-cli-log-event
                           node
                           "devnet.ready"
                           :engine-endpoint engine-endpoint
                           :rpc-endpoint nil
                           :public-rpc-enabled-p nil))
                        (setf client-thread
                              (sb-thread:make-thread
                               (lambda ()
                                 (handler-case
                                     (progn
                                       (sleep 0.05)
                                       (setf blocked-client-response
                                             (devnet-cli-http-endpoint-request
                                              engine-endpoint
                                              (devnet-cli-json-rpc-http-request
                                               engine-body
                                               :host "engine.runner"
                                               :token token)))
                                       (setf client-response
                                             (devnet-cli-http-endpoint-request
                                              engine-endpoint
                                              (devnet-cli-json-rpc-http-request
                                               engine-body
                                               :token token
                                               :host "engine.runner"
                                               :origin
                                               "https://engine-runner.example"
                                               :target
                                               +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf capabilities-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              capabilities-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf transition-configuration-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              transition-configuration-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf transition-configuration-mismatch-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              transition-configuration-mismatch-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf new-payload-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              new-payload-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+)))
                                      (setf forkchoice-response
                                            (devnet-cli-http-endpoint-request
                                             engine-endpoint
                                             (devnet-cli-json-rpc-http-request
                                              forkchoice-body
                                              :token token
                                              :host "engine.runner"
                                              :target
                                              +devnet-smoke-gate-engine-rpc-prefix+))))
                                   (error (condition)
                                     (setf client-error condition))))
                               :name
                               "ethereum-lisp-devnet-engine-only-client"))))))
               (when client-thread
                 (sb-thread:join-thread client-thread))
               (when client-error
                 (error client-error))
               (when log-file
                 (ethereum-lisp.cli::devnet-cli-log-event
                  node
                  "devnet.shutdown"
                  :engine-endpoint engine-endpoint
                  :rpc-endpoint nil
                  :connection-summary summary
                  :public-rpc-enabled-p nil))
               (when database-file
                 (ethereum-lisp.cli::devnet-node-export-database node)
                 (let* ((restored-node
                          (ethereum-lisp.cli:make-devnet-node
                           :genesis-path (namestring genesis-path)
                           :port 0
                           :public-port 0
                           :jwt-secret-path (namestring jwt-path)
                           :database-path database-file))
                        (restored-summary
                          (ethereum-lisp.cli:devnet-node-summary
                           restored-node
                           :public-rpc-enabled-p nil)))
                   (devnet-smoke-gate-require
                    (string= database-file
                             (getf restored-summary :database-path))
                    "Engine-only database restore path mismatch")
                   (devnet-smoke-gate-require
                    (= (hex-to-quantity expected-child-number)
                       (getf restored-summary :head-number))
                    "Engine-only database restore head number mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-child-hash
                             (getf restored-summary :head-hash))
                    "Engine-only database restore head hash mismatch")
                   (devnet-smoke-gate-require
                    (getf restored-summary :state-available-p)
                    "Engine-only database restore head state unavailable")
                   (setf database-summary restored-summary)))
               (devnet-smoke-gate-require
                (= 7 (getf summary :engine-connections))
                "Engine-only serve Engine connection count mismatch")
               (devnet-smoke-gate-require
                (= 0 (getf summary :public-connections))
                "Engine-only serve public connection count mismatch")
               (devnet-smoke-gate-require
                (= 7 (getf summary :total-connections))
                "Engine-only serve total connection count mismatch")
               (devnet-smoke-gate-require
                (and engine-endpoint
                     (devnet-smoke-gate-http-endpoint-p engine-endpoint))
                "Engine-only serve did not publish a loopback Engine endpoint")
               (setf public-endpoint-connectable-p
                     (devnet-cli-http-endpoint-connectable-p
                      configured-public-endpoint))
               (devnet-smoke-gate-require
                (not public-endpoint-connectable-p)
                "Engine-only serve public endpoint unexpectedly accepted a connection")
               (devnet-smoke-gate-require
                (= 404 (devnet-cli-http-status blocked-client-response))
                "Engine-only serve root Engine response HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status client-response))
                "Engine-only serve Engine response HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status capabilities-response))
                "Engine-only serve engine_exchangeCapabilities HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status
                        transition-configuration-response))
                "Engine-only serve engine_exchangeTransitionConfigurationV1 HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status
                        transition-configuration-mismatch-response))
                "Engine-only serve engine_exchangeTransitionConfigurationV1 mismatch HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status new-payload-response))
                "Engine-only serve engine_newPayloadV2 HTTP status mismatch")
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status forkchoice-response))
                "Engine-only serve engine_forkchoiceUpdatedV2 HTTP status mismatch")
               (devnet-smoke-gate-require
                (string= "https://engine-runner.example"
                         (devnet-smoke-gate-http-header
                          client-response
                          "Access-Control-Allow-Origin"))
                "Engine-only serve Engine CORS response header mismatch")
               (devnet-smoke-gate-require
                (string= "Origin"
                         (devnet-smoke-gate-http-header
                          client-response
                          "Vary"))
                "Engine-only serve Engine CORS Vary header mismatch")
               (let* ((engine-rpc
                        (parse-json
                         (devnet-cli-http-body client-response)))
                      (capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (parsed-capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (transition-configuration-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-response)))
                      (parsed-transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc
                         "result"))
                      (transition-configuration-mismatch-rpc
                        (parse-json
                         (devnet-cli-http-body
                          transition-configuration-mismatch-response)))
                      (parsed-transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc
                         "error"))
                      (new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (parsed-client-version
                        (first (fixture-object-field engine-rpc "result"))))
                 (setf capabilities-result parsed-capabilities-result
                       transition-configuration-result
                       parsed-transition-configuration-result
                       transition-configuration-mismatch-error
                       parsed-transition-configuration-mismatch-error
                       client-version parsed-client-version)
                 (devnet-smoke-gate-require
                  (= 901 (fixture-object-field engine-rpc "id"))
                  "Engine-only serve Engine response id mismatch")
                 (devnet-smoke-gate-require
                  (string= "ethereum-lisp"
                           (fixture-object-field client-version "name"))
                 "Engine-only serve client version mismatch")
                 (devnet-smoke-gate-require
                  (and capabilities-result
                       (listp capabilities-result))
                  "Engine-only serve engine_exchangeCapabilities result missing from ~A"
                  (devnet-cli-http-body capabilities-response))
                 (dolist (method '("engine_newPayloadV1"
                                    "engine_forkchoiceUpdatedV1"
                                    "engine_getPayloadV1"
                                    "engine_newPayloadV2"
                                    "engine_forkchoiceUpdatedV2"
                                    "engine_getPayloadV2"
                                    "engine_getPayloadBodiesByHashV1"
                                    "engine_getPayloadBodiesByRangeV1"))
                   (devnet-smoke-gate-require
                   (member method capabilities-result :test #'string=)
                    "Engine-only serve engine_exchangeCapabilities omitted ~A from ~S"
                    method
                    capabilities-result))
                 (dolist (method '("engine_newPayloadV3"
                                    "engine_getBlobsV1"
                                    "engine_getPayloadBodiesByHashV2"
                                    "engine_getPayloadBodiesByRangeV2"))
                   (devnet-smoke-gate-require
                    (not (member method capabilities-result :test #'string=))
                    "Engine-only serve engine_exchangeCapabilities advertised ~A"
                    method))
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            transition-configuration-result
                            "terminalTotalDifficulty"))
                  "Engine-only serve transition terminalTotalDifficulty mismatch")
                 (devnet-smoke-gate-require
                  (string= (hash32-to-hex (zero-hash32))
                           (fixture-object-field
                            transition-configuration-result
                            "terminalBlockHash"))
                  "Engine-only serve transition terminalBlockHash mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            transition-configuration-result
                            "terminalBlockNumber"))
                  "Engine-only serve transition terminalBlockNumber mismatch")
                 (devnet-smoke-gate-require
                  (= -32602
                     (fixture-object-field
                      transition-configuration-mismatch-error
                      "code"))
                  "Engine-only serve transition mismatch error code mismatch")
                 (devnet-smoke-gate-require
                  (search "terminalTotalDifficulty mismatch"
                          (fixture-object-field
                           transition-configuration-mismatch-error
                           "message"))
                  "Engine-only serve transition mismatch error message mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field new-payload-result "status"))
                  "Engine-only serve engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-child-hash
                           (fixture-object-field new-payload-result
                                                 "latestValidHash"))
                  "Engine-only serve latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field forkchoice-status "status"))
                  "Engine-only serve forkchoice status mismatch"))
               (when ready-file
                 (let ((ready-summary
                         (parse-json
                          (devnet-smoke-gate-file-string ready-file))))
                   (devnet-smoke-gate-require
                    (string= engine-endpoint
                             (fixture-object-field ready-summary
                                                   "engineEndpoint"))
                    "Engine-only ready file Engine endpoint mismatch")
                   (devnet-smoke-gate-require
                    (string= +devnet-smoke-gate-engine-rpc-prefix+
                             (fixture-object-field ready-summary
                                                   "engineRpcPrefix"))
                    "Engine-only ready file Engine RPC prefix mismatch")
                   (devnet-smoke-gate-require
                    (equal *devnet-smoke-gate-engine-cors-origins*
                           (fixture-object-field ready-summary
                                                 "engineCorsOrigins"))
                    "Engine-only ready file Engine CORS origins mismatch")
                   (devnet-smoke-gate-require
                    (equal *devnet-smoke-gate-engine-vhosts*
                           (fixture-object-field ready-summary
                                                 "engineVhosts"))
                    "Engine-only ready file Engine vhosts mismatch")
                   (devnet-smoke-gate-require
                    (not (fixture-object-field ready-summary "rpcEndpoint"))
                    "Engine-only ready file must disable rpcEndpoint")
                   (devnet-smoke-gate-require
                    (not (fixture-object-field ready-summary
                                               "publicRpcEnabled"))
                    "Engine-only ready file must disable publicRpcEnabled")
                   (devnet-smoke-gate-require
                    (string= head-number
                             (quantity-to-hex
                              (fixture-object-field ready-summary
                                                    "headNumber")))
                    "Engine-only ready file head number mismatch")
                   (devnet-smoke-gate-require
                    (string= head-hash
                             (fixture-object-field ready-summary
                                                   "headHash"))
                    "Engine-only ready file head hash mismatch")
                   (devnet-smoke-gate-require
                    (string= head-gas-limit
                             (quantity-to-hex
                              (fixture-object-field ready-summary
                                                    "headGasLimit")))
                    "Engine-only ready file head gas limit mismatch")))
               (when log-file
                 (let ((records
                         (devnet-smoke-gate-file-forms log-file)))
                   (dolist (event '("devnet.ready" "devnet.shutdown"))
                     (let* ((record
                              (find event records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (fields (and record (getf record :fields))))
                       (devnet-smoke-gate-require
                        record
                        "Engine-only log file missing ~A" event)
                       (devnet-smoke-gate-require
                        (string= engine-endpoint
                                 (cdr (assoc "engineEndpoint" fields
                                             :test #'string=)))
                        "Engine-only log Engine endpoint mismatch")
                       (devnet-smoke-gate-require
                        (string= +devnet-smoke-gate-engine-rpc-prefix+
                                 (cdr (assoc "engineRpcPrefix" fields
                                             :test #'string=)))
                        "Engine-only log Engine RPC prefix mismatch")
                       (devnet-smoke-gate-require
                        (string= "https://engine-runner.example,https://engine-observer.example"
                                 (cdr (assoc "engineCorsOrigins" fields
                                             :test #'string=)))
                        "Engine-only log Engine CORS origins mismatch")
                       (devnet-smoke-gate-require
                        (string= "engine.runner,localhost"
                                 (cdr (assoc "engineVhosts" fields
                                             :test #'string=)))
                        "Engine-only log Engine vhosts mismatch")
                       (devnet-smoke-gate-require
                        (string= ""
                                 (cdr (assoc "rpcEndpoint" fields
                                             :test #'string=)))
                        "Engine-only log must emit an empty rpcEndpoint")
                       (devnet-smoke-gate-require
                        (string= "false"
                                 (cdr (assoc "publicRpcEnabled" fields
                                             :test #'string=)))
                        "Engine-only log must disable publicRpcEnabled")
                       (devnet-smoke-gate-require
                        (string= (if (string= event "devnet.shutdown")
                                     expected-child-number
                                     head-number)
                                 (cdr (assoc "headNumber" fields
                                             :test #'string=)))
                        "Engine-only log head number mismatch")
                       (devnet-smoke-gate-require
                        (string= (if (string= event "devnet.shutdown")
                                     expected-child-hash
                                     head-hash)
                                 (cdr (assoc "headHash" fields
                                             :test #'string=)))
                        "Engine-only log head hash mismatch")))))
               (setf report
                     (devnet-smoke-gate-add-run-metadata
                      (list
                       (cons "status" "ok")
                       (cons "mode" "devnet-engine-only-serve")
                       (cons "publicRpcEnabled" :false)
                       (cons "engineEndpoint" engine-endpoint)
                       (cons "engineRpcPrefix"
                             +devnet-smoke-gate-engine-rpc-prefix+)
                       (cons "engineRpcPrefixStatus"
                             (devnet-cli-http-status client-response))
                       (cons "engineRpcPrefixBlockedStatus"
                             (devnet-cli-http-status blocked-client-response))
                       (cons "engineCorsOrigins"
                             *devnet-smoke-gate-engine-cors-origins*)
                       (cons "engineCorsHeader"
                             (devnet-smoke-gate-http-header
                              client-response
                              "Access-Control-Allow-Origin"))
                       (cons "engineCorsVaryHeader"
                             (devnet-smoke-gate-http-header
                              client-response
                              "Vary"))
                       (cons "engineVhosts"
                             *devnet-smoke-gate-engine-vhosts*)
                       (cons "fixtureCase"
                             +devnet-smoke-gate-default-fixture-case+)
                       (cons "newPayloadStatus" +payload-status-valid+)
                       (cons "latestValidHash" expected-child-hash)
                       (cons "forkchoiceStatus" +payload-status-valid+)
                       (cons "forkchoiceHeadNumber" expected-child-number)
                       (cons "forkchoiceHeadHash" expected-child-hash)
                       (cons "rpcEndpoint" :false)
                       (cons "configuredPublicEndpoint"
                             configured-public-endpoint)
                       (cons "publicEndpointConnectable"
                             (if public-endpoint-connectable-p t :false))
                       (cons "readyFile" (or ready-file :false))
                       (cons "logFile" (or log-file :false))
                       (cons "pidFile" (or pid-file :false))
                       (cons "databaseFile" (or database-file :false))
                       (cons "databaseHeadNumber"
                             (if database-summary
                                 (getf database-summary :head-number)
                                 :false))
                       (cons "databaseHeadHash"
                             (if database-summary
                                 (getf database-summary :head-hash)
                                 :false))
                       (cons "databaseStateAvailable"
                             (if database-summary
                                 (if (getf database-summary
                                           :state-available-p)
                                     t
                                     :false)
                                 :false))
                       (cons "engineConnections"
                             (getf summary :engine-connections))
                       (cons "publicConnections"
                             (getf summary :public-connections))
                       (cons "totalConnections"
                             (getf summary :total-connections))
                       (cons "connectionContract"
                             (list
                              (cons "expectedEngineConnections" 7)
                              (cons "expectedPublicConnections" 0)
                              (cons "expectedTotalConnections" 7)))
                       (cons "engineCapabilityCount"
                             (length capabilities-result))
                       (cons "engineCapabilityHasNewPayloadV1"
                             (if (member "engine_newPayloadV1"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasForkchoiceUpdatedV1"
                             (if (member "engine_forkchoiceUpdatedV1"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasGetPayloadV1"
                             (if (member "engine_getPayloadV1"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasNewPayloadV2"
                             (if (member "engine_newPayloadV2"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasForkchoiceUpdatedV2"
                             (if (member "engine_forkchoiceUpdatedV2"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasGetPayloadV2"
                             (if (member "engine_getPayloadV2"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasNewPayloadV3"
                             (if (member "engine_newPayloadV3"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasGetBlobsV1"
                             (if (member "engine_getBlobsV1"
                                         capabilities-result
                                         :test #'string=)
                                 t
                                 :false))
                       (cons "engineCapabilityHasPayloadBodiesV2"
                             (if (or (member "engine_getPayloadBodiesByHashV2"
                                             capabilities-result
                                             :test #'string=)
                                     (member "engine_getPayloadBodiesByRangeV2"
                                             capabilities-result
                                             :test #'string=))
                                 t
                                 :false))
                       (cons "engineClientVersionCode"
                             (fixture-object-field client-version "code"))
                       (cons "engineClientVersionName" "ethereum-lisp")
                       (cons "engineClientVersionVersion"
                             (fixture-object-field client-version "version"))
                       (cons "engineClientVersionCommit"
                             (fixture-object-field client-version "commit"))
                       (cons "engineTransitionTerminalTotalDifficulty"
                             (fixture-object-field
                              transition-configuration-result
                              "terminalTotalDifficulty"))
                       (cons "engineTransitionTerminalBlockHash"
                             (fixture-object-field
                              transition-configuration-result
                              "terminalBlockHash"))
                       (cons "engineTransitionTerminalBlockNumber"
                             (fixture-object-field
                              transition-configuration-result
                              "terminalBlockNumber"))
                       (cons "engineTransitionMismatchErrorCode"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "code"))
                       (cons "engineTransitionMismatchErrorMessage"
                             (fixture-object-field
                              transition-configuration-mismatch-error
                              "message"))
                       (cons "headNumber" head-number)
                       (cons "headHash" head-hash)
                       (cons "headGasLimit" head-gas-limit)))))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))
    report)
  #-sbcl
  (error "Devnet engine-only serve smoke requires SBCL sockets"))

(defun devnet-smoke-gate-verify-engine-only-kzg-opt-in ()
  #+sbcl
  (labels ((field-present-p (object name)
             (not (null (assoc name object :test #'string=))))
           (forkchoice-state-object (head-hash)
             (list (cons "headBlockHash" head-hash)
                   (cons "safeBlockHash" head-hash)
                   (cons "finalizedBlockHash" head-hash)))
           (withdrawal-object ()
             (list (cons "index" "0x4")
                   (cons "validatorIndex" "0x5")
                   (cons "address" (address-to-hex (zero-address)))
                   (cons "amount" "0x6")))
           (payload-attributes-v3-object
               (timestamp parent-beacon-block-root)
             (list (cons "timestamp" timestamp)
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" (list (withdrawal-object)))
                   (cons "parentBeaconBlockRoot"
                         parent-beacon-block-root)))
           (payload-attributes-v4-object
               (timestamp parent-beacon-block-root slot-number)
             (append
              (payload-attributes-v3-object
               timestamp
               parent-beacon-block-root)
              (list (cons "slotNumber" slot-number))))
           (forkchoice-request (id method head-hash payload-attributes)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params"
                          (list
                           (forkchoice-state-object head-hash)
                           payload-attributes)))))
           (get-payload-request (id method payload-id)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" (list payload-id)))))
           (get-payload-bodies-by-hash-request (id method block-hashes)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" (list block-hashes)))))
           (get-payload-bodies-by-range-request (id method start count)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" (list start count)))))
           (get-blobs-request (id method versioned-hashes)
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" (list versioned-hashes)))))
           (hex-prefix (hex bytes)
             (subseq hex 0 (min (length hex) (+ 2 (* bytes 2))))))
    (let* ((script
           (namestring
            (truename
             (merge-pathnames "scripts/ethereum-lisp.lisp"
                              *ethereum-lisp-devnet-smoke-gate-root*))))
         (genesis
           (namestring
            (truename
             (merge-pathnames +devnet-cli-genesis-fixture+
                              *ethereum-lisp-devnet-smoke-gate-root*))))
         (genesis-json
           (parse-json (devnet-smoke-gate-file-string genesis)))
         (blob-database
           (devnet-smoke-gate-write-kzg-prepared-payload-database genesis))
         (database-path
           (getf blob-database :database-path))
         (kzg-command
           (devnet-cli-temp-path "ethereum-lisp-smoke-kzg-command" "sh"))
         (ready-path
           (devnet-cli-temp-path "ethereum-lisp-smoke-kzg-ready" "json"))
         (log-path
           (devnet-cli-temp-path "ethereum-lisp-smoke-kzg" "log"))
         (pid-path
           (devnet-cli-temp-path "ethereum-lisp-smoke-kzg" "pid"))
         (process nil)
         (report nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file kzg-command "#!/bin/sh\necho true\n")
           (devnet-cli-make-executable kzg-command)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        genesis
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http=false"
                        "--database"
                        (namestring database-path)
                        "--kzg.verifier-command"
                        (namestring kzg-command)
                        "--kzg.verifier-timeout"
                        "2"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "21"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (error
              "KZG opt-in devnet did not write readiness JSON. stdout=~S stderr=~S"
              (devnet-cli-read-stream-string
               (uiop:process-info-output process))
              (devnet-cli-read-stream-string
               (uiop:process-info-error-output process))))
           (let* ((ready-summary
                    (parse-json (devnet-smoke-gate-file-string ready-path)))
                  (raw-engine-endpoint
                        (fixture-object-field ready-summary "engineEndpoint"))
                  (engine-endpoint
                    (and raw-engine-endpoint
                         (if (uiop:string-prefix-p
                              "http://"
                              raw-engine-endpoint)
                             raw-engine-endpoint
                             (format nil "http://~A"
                                     raw-engine-endpoint))))
                  (head-hash
                    (fixture-object-field ready-summary "headHash"))
                  (head-number
                    (fixture-object-field ready-summary "headNumber"))
                  (next-block-number
                    (quantity-to-hex (1+ head-number)))
                  (genesis-timestamp
                    (fixture-quantity-field genesis-json "timestamp"))
                  (v3-parent-beacon-block-root
                    "0x3333333333333333333333333333333333333333333333333333333333333333")
                  (v4-parent-beacon-block-root
                    "0x4444444444444444444444444444444444444444444444444444444444444444")
                  (v3-timestamp
                    (quantity-to-hex (1+ genesis-timestamp)))
                  (v4-timestamp
                    (quantity-to-hex (+ genesis-timestamp 2)))
                  (v4-slot-number "0x2a")
                  (unknown-versioned-hash
                    (hash32-to-hex
                     (make-hash32
                      (make-byte-vector 32 :initial-element #x11))))
                  (capabilities-body
                    "{\"jsonrpc\":\"2.0\",\"id\":715,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                  (capabilities-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request capabilities-body)))
                  (capabilities-rpc
                    (parse-json (devnet-cli-http-body capabilities-response)))
                  (capabilities-result
                    (fixture-object-field capabilities-rpc "result"))
                  (prepare-v3-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (forkchoice-request
                       716
                       "engine_forkchoiceUpdatedV3"
                       head-hash
                       (payload-attributes-v3-object
                        v3-timestamp
                        v3-parent-beacon-block-root)))))
                  (prepare-v3-rpc
                    (parse-json (devnet-cli-http-body prepare-v3-response)))
                  (prepare-v3-result
                    (fixture-object-field prepare-v3-rpc "result"))
                  (prepare-v3-status
                    (fixture-object-field prepare-v3-result "payloadStatus"))
                  (payload-id-v3
                    (fixture-object-field prepare-v3-result "payloadId"))
                  (get-payload-v3-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-request
                       717
                       "engine_getPayloadV3"
                       payload-id-v3))))
                  (get-payload-v3-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-v3-response)))
                  (payload-envelope-v3
                    (fixture-object-field get-payload-v3-rpc "result"))
                  (execution-payload-v3
                    (fixture-object-field payload-envelope-v3
                                          "executionPayload"))
                  (blobs-bundle-v3
                    (fixture-object-field payload-envelope-v3
                                          "blobsBundle"))
                  (prepare-v4-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (forkchoice-request
                       718
                       "engine_forkchoiceUpdatedV4"
                       head-hash
                       (payload-attributes-v4-object
                        v4-timestamp
                        v4-parent-beacon-block-root
                        v4-slot-number)))))
                  (prepare-v4-rpc
                    (parse-json (devnet-cli-http-body prepare-v4-response)))
                  (prepare-v4-result
                    (fixture-object-field prepare-v4-rpc "result"))
                  (prepare-v4-status
                    (fixture-object-field prepare-v4-result "payloadStatus"))
                  (payload-id-v4
                    (fixture-object-field prepare-v4-result "payloadId"))
                  (get-payload-v4-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-request
                       719
                       "engine_getPayloadV4"
                       payload-id-v4))))
                  (get-payload-v4-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-v4-response)))
                  (payload-envelope-v4
                    (fixture-object-field get-payload-v4-rpc "result"))
                  (execution-payload-v4
                    (fixture-object-field payload-envelope-v4
                                          "executionPayload"))
                  (blobs-bundle-v4
                    (fixture-object-field payload-envelope-v4
                                          "blobsBundle"))
                  (get-payload-v5-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-request
                       720
                       "engine_getPayloadV5"
                       (getf blob-database :payload-id-v5)))))
                  (get-payload-v5-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-v5-response)))
                  (payload-envelope-v5
                    (fixture-object-field get-payload-v5-rpc "result"))
                  (execution-payload-v5
                    (fixture-object-field payload-envelope-v5
                                          "executionPayload"))
                  (blobs-bundle-v5
                    (fixture-object-field payload-envelope-v5
                                          "blobsBundle"))
                  (get-payload-v6-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-request
                       721
                       "engine_getPayloadV6"
                       (getf blob-database :payload-id-v6)))))
                  (get-payload-v6-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-v6-response)))
                  (payload-envelope-v6
                    (fixture-object-field get-payload-v6-rpc "result"))
                  (execution-payload-v6
                    (fixture-object-field payload-envelope-v6
                                          "executionPayload"))
                  (execution-requests-v6
                    (fixture-object-field payload-envelope-v6
                                          "executionRequests"))
                  (blobs-bundle-v6
                    (fixture-object-field payload-envelope-v6
                                          "blobsBundle"))
                  (get-payload-bodies-v2-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-hash-request
                       722
                       "engine_getPayloadBodiesByHashV2"
                       (list (getf blob-database :block-hash-v6))))))
                  (get-payload-bodies-v2-rpc
                    (parse-json
                     (devnet-cli-http-body get-payload-bodies-v2-response)))
                  (get-payload-bodies-v2-result
                    (fixture-object-field get-payload-bodies-v2-rpc "result"))
                  (payload-body-v2
                    (first get-payload-bodies-v2-result))
                  (payload-body-v2-transactions
                    (and payload-body-v2
                         (fixture-object-field payload-body-v2
                                               "transactions")))
                  (payload-body-v2-withdrawals
                    (and payload-body-v2
                         (fixture-object-field payload-body-v2
                                               "withdrawals")))
                  (select-v6-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (forkchoice-request
                       723
                       "engine_forkchoiceUpdatedV2"
                       (getf blob-database :block-hash-v6)
                       nil))))
                  (select-v6-rpc
                    (parse-json
                     (devnet-cli-http-body select-v6-response)))
                  (select-v6-result
                    (fixture-object-field select-v6-rpc "result"))
                  (select-v6-status
                    (fixture-object-field select-v6-result "payloadStatus"))
                  (payload-bodies-range-v2-start-block
                    (quantity-to-hex
                     (1- (hex-to-quantity
                          (getf blob-database :block-number-v6)))))
                  (get-payload-bodies-range-v2-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       724
                       "engine_getPayloadBodiesByRangeV2"
                       payload-bodies-range-v2-start-block
                       "0x2"))))
                  (get-payload-bodies-range-v2-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-response)))
                  (get-payload-bodies-range-v2-result
                    (fixture-object-field get-payload-bodies-range-v2-rpc
                                          "result"))
                  (get-payload-bodies-range-v2-zero-start-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       729
                       "engine_getPayloadBodiesByRangeV2"
                       "0x0"
                       "0x1"))))
                  (get-payload-bodies-range-v2-zero-start-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-zero-start-response)))
                  (get-payload-bodies-range-v2-zero-start-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-zero-start-rpc
                     "error"))
                  (get-payload-bodies-range-v2-zero-count-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       730
                       "engine_getPayloadBodiesByRangeV2"
                       payload-bodies-range-v2-start-block
                       "0x0"))))
                  (get-payload-bodies-range-v2-zero-count-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-zero-count-response)))
                  (get-payload-bodies-range-v2-zero-count-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-zero-count-rpc
                     "error"))
                  (get-payload-bodies-range-v2-malformed-start-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       731
                       "engine_getPayloadBodiesByRangeV2"
                       "0xzz"
                       "0x1"))))
                  (get-payload-bodies-range-v2-malformed-start-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-malformed-start-response)))
                  (get-payload-bodies-range-v2-malformed-start-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-malformed-start-rpc
                     "error"))
                  (get-payload-bodies-range-v2-malformed-count-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       732
                       "engine_getPayloadBodiesByRangeV2"
                       payload-bodies-range-v2-start-block
                       "0xzz"))))
                  (get-payload-bodies-range-v2-malformed-count-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-malformed-count-response)))
                  (get-payload-bodies-range-v2-malformed-count-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-malformed-count-rpc
                     "error"))
                  (get-payload-bodies-range-v2-params-envelope-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 733)
                             (cons "method"
                                   "engine_getPayloadBodiesByRangeV2")
                             (cons "params"
                                   (list payload-bodies-range-v2-start-block)))))))
                  (get-payload-bodies-range-v2-params-envelope-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-params-envelope-response)))
                  (get-payload-bodies-range-v2-params-envelope-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-params-envelope-rpc
                     "error"))
                  (get-payload-bodies-range-v2-invalid-request-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 734)
                             (cons "method"
                                   "engine_getPayloadBodiesByRangeV2")
                             (cons "params" "0x1"))))))
                  (get-payload-bodies-range-v2-invalid-request-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-invalid-request-response)))
                  (get-payload-bodies-range-v2-invalid-request-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-invalid-request-rpc
                     "error"))
                  (get-payload-bodies-range-v2-null-params-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 735)
                             (cons "method"
                                   "engine_getPayloadBodiesByRangeV2")
                             (cons "params" nil))))))
                  (get-payload-bodies-range-v2-null-params-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-null-params-response)))
                  (get-payload-bodies-range-v2-null-params-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-null-params-rpc
                     "error"))
                  (get-payload-bodies-range-v2-oversized-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-payload-bodies-by-range-request
                       728
                       "engine_getPayloadBodiesByRangeV2"
                       payload-bodies-range-v2-start-block
                       "0x401"))))
                  (get-payload-bodies-range-v2-oversized-rpc
                    (parse-json
                     (devnet-cli-http-body
                      get-payload-bodies-range-v2-oversized-response)))
                  (get-payload-bodies-range-v2-oversized-error
                    (fixture-object-field
                     get-payload-bodies-range-v2-oversized-rpc
                     "error"))
                  (missing-payload-body-range-v2
                    (first get-payload-bodies-range-v2-result))
                  (payload-body-range-v2
                    (second get-payload-bodies-range-v2-result))
                  (payload-body-range-v2-transactions
                    (and payload-body-range-v2
                         (fixture-object-field payload-body-range-v2
                                               "transactions")))
                  (payload-body-range-v2-withdrawals
                    (and payload-body-range-v2
                         (fixture-object-field payload-body-range-v2
                                               "withdrawals")))
                  (get-blobs-v1-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-blobs-request
                       725
                       "engine_getBlobsV1"
                       (list (getf blob-database :versioned-hash-hex)
                             unknown-versioned-hash)))))
                  (get-blobs-v1-rpc
                    (parse-json
                     (devnet-cli-http-body get-blobs-v1-response)))
                  (get-blobs-v1-result
                    (fixture-object-field get-blobs-v1-rpc "result"))
                  (direct-blob-v1
                    (first get-blobs-v1-result))
                  (missing-blob-v1
                    (second get-blobs-v1-result))
                  (get-blobs-v2-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-blobs-request
                       726
                       "engine_getBlobsV2"
                       (list (getf blob-database :versioned-hash-hex))))))
                  (get-blobs-v2-rpc
                    (parse-json
                     (devnet-cli-http-body get-blobs-v2-response)))
                  (get-blobs-v2-result
                    (fixture-object-field get-blobs-v2-rpc "result"))
                  (direct-blob-v2
                    (first get-blobs-v2-result))
                  (direct-blob-v2-proofs
                    (fixture-object-field direct-blob-v2 "proofs"))
                  (get-blobs-v3-response
                    (devnet-cli-http-endpoint-request
                     engine-endpoint
                     (devnet-cli-json-rpc-http-request
                      (get-blobs-request
                       727
                       "engine_getBlobsV3"
                       (list (getf blob-database :versioned-hash-hex)
                             unknown-versioned-hash)))))
                  (get-blobs-v3-rpc
                    (parse-json
                     (devnet-cli-http-body get-blobs-v3-response)))
                  (get-blobs-v3-result
                    (fixture-object-field get-blobs-v3-rpc "result"))
                  (direct-blob-v3
                    (first get-blobs-v3-result))
                  (direct-blob-v3-proofs
                    (fixture-object-field direct-blob-v3 "proofs"))
                  (missing-blob-v3
                    (second get-blobs-v3-result)))
             (devnet-smoke-gate-require
              (stringp engine-endpoint)
              "KZG opt-in ready file omitted Engine endpoint")
             (devnet-smoke-gate-require
              (not (fixture-object-field ready-summary "rpcEndpoint"))
              "KZG opt-in ready file must disable public rpcEndpoint")
             (devnet-smoke-gate-require
              (not (fixture-object-field ready-summary "publicRpcEnabled"))
              "KZG opt-in ready file must disable publicRpcEnabled")
             (devnet-smoke-gate-require
              (string= (namestring kzg-command)
                       (fixture-object-field ready-summary
                                             "kzgVerifierCommand"))
              "KZG opt-in ready file verifier command mismatch")
             (devnet-smoke-gate-require
              (= 2 (fixture-object-field ready-summary
                                          "kzgVerifierTimeoutSeconds"))
              "KZG opt-in ready file verifier timeout mismatch")
             (devnet-smoke-gate-require
              (fixture-object-field ready-summary
                                    "kzgProofVerificationAvailable")
              "KZG opt-in ready file did not expose proof availability")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status capabilities-response))
              "KZG opt-in engine_exchangeCapabilities HTTP status mismatch")
             (devnet-smoke-gate-require
              (= 715 (fixture-object-field capabilities-rpc "id"))
              "KZG opt-in engine_exchangeCapabilities id mismatch")
             (dolist (method '("engine_forkchoiceUpdatedV3"
                               "engine_forkchoiceUpdatedV4"
                               "engine_getPayloadV3"
                               "engine_getPayloadV4"
                               "engine_getPayloadV5"
                               "engine_getPayloadV6"
                               "engine_newPayloadV3"
                               "engine_getBlobsV1"
                               "engine_getBlobsV2"
                               "engine_getBlobsV3"
                               "engine_getPayloadBodiesByHashV2"
                               "engine_getPayloadBodiesByRangeV2"))
               (devnet-smoke-gate-require
                (member method capabilities-result :test #'string=)
                "KZG opt-in capabilities omitted ~A from ~S"
                method
                capabilities-result))
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status prepare-v3-response))
              "KZG opt-in engine_forkchoiceUpdatedV3 HTTP status mismatch")
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field prepare-v3-status "status"))
              "KZG opt-in engine_forkchoiceUpdatedV3 status mismatch")
             (devnet-smoke-gate-require
              (and (stringp payload-id-v3)
                   (= 18 (length payload-id-v3))
                   (string= "03" (subseq payload-id-v3 2 4)))
              "KZG opt-in engine_forkchoiceUpdatedV3 did not return a V3 payload id")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-v3-response))
              "KZG opt-in engine_getPayloadV3 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-v3-rpc "error"))
              "KZG opt-in engine_getPayloadV3 returned an error: ~S"
              (fixture-object-field get-payload-v3-rpc "error"))
             (devnet-smoke-gate-require
              (string= head-hash
                       (fixture-object-field execution-payload-v3
                                             "parentHash"))
              "KZG opt-in engine_getPayloadV3 parentHash mismatch")
             (devnet-smoke-gate-require
              (string= next-block-number
                       (fixture-object-field execution-payload-v3
                                             "blockNumber"))
              "KZG opt-in engine_getPayloadV3 blockNumber mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field payload-envelope-v3
                                         "shouldOverrideBuilder"))
              "KZG opt-in engine_getPayloadV3 shouldOverrideBuilder mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v3 "blobsBundle")
              "KZG opt-in engine_getPayloadV3 omitted blobsBundle")
             (dolist (field '("commitments" "proofs" "blobs"))
               (devnet-smoke-gate-require
                (field-present-p blobs-bundle-v3 field)
                "KZG opt-in engine_getPayloadV3 blobsBundle omitted ~A"
                field)
               (devnet-smoke-gate-require
                (listp (fixture-object-field blobs-bundle-v3 field))
                "KZG opt-in engine_getPayloadV3 blobsBundle ~A must be a JSON array"
                field))
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status prepare-v4-response))
              "KZG opt-in engine_forkchoiceUpdatedV4 HTTP status mismatch")
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field prepare-v4-status "status"))
              "KZG opt-in engine_forkchoiceUpdatedV4 status mismatch")
             (devnet-smoke-gate-require
              (and (stringp payload-id-v4)
                   (= 18 (length payload-id-v4))
                   (string= "04" (subseq payload-id-v4 2 4)))
              "KZG opt-in engine_forkchoiceUpdatedV4 did not return a V4 payload id")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-v4-response))
              "KZG opt-in engine_getPayloadV4 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-v4-rpc "error"))
              "KZG opt-in engine_getPayloadV4 returned an error: ~S"
              (fixture-object-field get-payload-v4-rpc "error"))
             (devnet-smoke-gate-require
              (string= head-hash
                       (fixture-object-field execution-payload-v4
                                             "parentHash"))
              "KZG opt-in engine_getPayloadV4 parentHash mismatch")
             (devnet-smoke-gate-require
              (string= next-block-number
                       (fixture-object-field execution-payload-v4
                                             "blockNumber"))
              "KZG opt-in engine_getPayloadV4 blockNumber mismatch")
             (devnet-smoke-gate-require
              (string= v4-slot-number
                       (fixture-object-field execution-payload-v4
                                             "slotNumber"))
              "KZG opt-in engine_getPayloadV4 slotNumber mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field payload-envelope-v4
                                         "shouldOverrideBuilder"))
              "KZG opt-in engine_getPayloadV4 shouldOverrideBuilder mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v4 "blobsBundle")
              "KZG opt-in engine_getPayloadV4 omitted blobsBundle")
             (dolist (field '("commitments" "proofs" "blobs"))
               (devnet-smoke-gate-require
                (field-present-p blobs-bundle-v4 field)
                "KZG opt-in engine_getPayloadV4 blobsBundle omitted ~A"
                field)
               (devnet-smoke-gate-require
                (listp (fixture-object-field blobs-bundle-v4 field))
                "KZG opt-in engine_getPayloadV4 blobsBundle ~A must be a JSON array"
                field))
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-v5-response))
              "KZG opt-in engine_getPayloadV5 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-v5-rpc "error"))
              "KZG opt-in engine_getPayloadV5 returned an error: ~S"
              (fixture-object-field get-payload-v5-rpc "error"))
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-number)
                       (fixture-object-field execution-payload-v5
                                             "blockNumber"))
              "KZG opt-in engine_getPayloadV5 blockNumber mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v5 "blobsBundle")
              "KZG opt-in engine_getPayloadV5 omitted blobsBundle")
             (devnet-smoke-gate-require
              (= 1 (length (fixture-object-field blobs-bundle-v5 "blobs")))
              "KZG opt-in engine_getPayloadV5 blob count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (first (fixture-object-field blobs-bundle-v5 "blobs")))
              "KZG opt-in engine_getPayloadV5 blob mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :commitment-hex)
                       (first (fixture-object-field
                               blobs-bundle-v5
                               "commitments")))
              "KZG opt-in engine_getPayloadV5 commitment mismatch")
             (devnet-smoke-gate-require
              (= (getf blob-database :cell-proof-count)
                 (length (fixture-object-field blobs-bundle-v5 "proofs")))
              "KZG opt-in engine_getPayloadV5 proof count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :proof-hex)
                       (first (fixture-object-field blobs-bundle-v5 "proofs")))
              "KZG opt-in engine_getPayloadV5 proof mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-v6-response))
              "KZG opt-in engine_getPayloadV6 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-v6-rpc "error"))
              "KZG opt-in engine_getPayloadV6 returned an error: ~S"
              (fixture-object-field get-payload-v6-rpc "error"))
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-number-v6)
                       (fixture-object-field execution-payload-v6
                                             "blockNumber"))
              "KZG opt-in engine_getPayloadV6 blockNumber mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :slot-number-v6)
                       (fixture-object-field execution-payload-v6
                                             "slotNumber"))
              "KZG opt-in engine_getPayloadV6 slotNumber mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v6 "executionRequests")
              "KZG opt-in engine_getPayloadV6 omitted executionRequests")
             (devnet-smoke-gate-require
              (and (listp execution-requests-v6)
                   (= 1 (length execution-requests-v6)))
              "KZG opt-in engine_getPayloadV6 execution request count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :execution-request-hex)
                       (first execution-requests-v6))
              "KZG opt-in engine_getPayloadV6 execution request mismatch")
             (devnet-smoke-gate-require
              (field-present-p execution-payload-v6 "blockAccessList")
              "KZG opt-in engine_getPayloadV6 omitted blockAccessList")
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-access-list-hex)
                       (fixture-object-field execution-payload-v6
                                             "blockAccessList"))
              "KZG opt-in engine_getPayloadV6 blockAccessList mismatch")
             (devnet-smoke-gate-require
              (field-present-p payload-envelope-v6 "blobsBundle")
              "KZG opt-in engine_getPayloadV6 omitted blobsBundle")
             (devnet-smoke-gate-require
              (= 1 (length (fixture-object-field blobs-bundle-v6 "blobs")))
              "KZG opt-in engine_getPayloadV6 blob count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (first (fixture-object-field blobs-bundle-v6 "blobs")))
              "KZG opt-in engine_getPayloadV6 blob mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :commitment-hex)
                       (first (fixture-object-field
                               blobs-bundle-v6
                               "commitments")))
              "KZG opt-in engine_getPayloadV6 commitment mismatch")
             (devnet-smoke-gate-require
              (= (getf blob-database :cell-proof-count)
                 (length (fixture-object-field blobs-bundle-v6 "proofs")))
              "KZG opt-in engine_getPayloadV6 proof count mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :proof-hex)
                       (first (fixture-object-field blobs-bundle-v6 "proofs")))
              "KZG opt-in engine_getPayloadV6 proof mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-bodies-v2-response))
              "KZG opt-in engine_getPayloadBodiesByHashV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-bodies-v2-rpc "error"))
              "KZG opt-in engine_getPayloadBodiesByHashV2 returned an error: ~S"
              (fixture-object-field get-payload-bodies-v2-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-payload-bodies-v2-result)
                   (= 1 (length get-payload-bodies-v2-result)))
              "KZG opt-in engine_getPayloadBodiesByHashV2 result count mismatch: ~S"
              get-payload-bodies-v2-result)
             (devnet-smoke-gate-require
              payload-body-v2
              "KZG opt-in engine_getPayloadBodiesByHashV2 returned null for prepared V6 block")
             (devnet-smoke-gate-require
              (assoc "transactions" payload-body-v2 :test #'string=)
              "KZG opt-in engine_getPayloadBodiesByHashV2 omitted transactions")
             (devnet-smoke-gate-require
              (listp payload-body-v2-transactions)
              "KZG opt-in engine_getPayloadBodiesByHashV2 transactions must be a JSON array")
             (devnet-smoke-gate-require
              (null payload-body-v2-transactions)
              "KZG opt-in engine_getPayloadBodiesByHashV2 transactions mismatch: ~S"
              payload-body-v2-transactions)
             (devnet-smoke-gate-require
              (assoc "withdrawals" payload-body-v2 :test #'string=)
              "KZG opt-in engine_getPayloadBodiesByHashV2 omitted withdrawals")
             (devnet-smoke-gate-require
              (listp payload-body-v2-withdrawals)
              "KZG opt-in engine_getPayloadBodiesByHashV2 withdrawals must be a JSON array")
             (devnet-smoke-gate-require
              (null payload-body-v2-withdrawals)
              "KZG opt-in engine_getPayloadBodiesByHashV2 withdrawals mismatch: ~S"
              payload-body-v2-withdrawals)
             (devnet-smoke-gate-require
              (field-present-p payload-body-v2 "blockAccessList")
              "KZG opt-in engine_getPayloadBodiesByHashV2 omitted blockAccessList")
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-access-list-hex)
                       (fixture-object-field payload-body-v2
                                             "blockAccessList"))
              "KZG opt-in engine_getPayloadBodiesByHashV2 blockAccessList mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status select-v6-response))
              "KZG opt-in engine_forkchoiceUpdatedV2 selection HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field select-v6-rpc "error"))
              "KZG opt-in engine_forkchoiceUpdatedV2 selection returned an error: ~S"
              (fixture-object-field select-v6-rpc "error"))
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field select-v6-status "status"))
              "KZG opt-in engine_forkchoiceUpdatedV2 selection status mismatch: ~S"
              select-v6-status)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-payload-bodies-range-v2-response))
              "KZG opt-in engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-payload-bodies-range-v2-rpc "error"))
              "KZG opt-in engine_getPayloadBodiesByRangeV2 returned an error: ~S"
              (fixture-object-field get-payload-bodies-range-v2-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-payload-bodies-range-v2-result)
                   (= 2 (length get-payload-bodies-range-v2-result)))
              "KZG opt-in engine_getPayloadBodiesByRangeV2 result count mismatch: ~S"
              get-payload-bodies-range-v2-result)
             (devnet-smoke-gate-require
              (null missing-payload-body-range-v2)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 sparse range lost the leading null placeholder: ~S"
              get-payload-bodies-range-v2-result)
             (devnet-smoke-gate-require
              payload-body-range-v2
              "KZG opt-in engine_getPayloadBodiesByRangeV2 returned null for prepared V6 block range hit")
             (devnet-smoke-gate-require
              (assoc "transactions" payload-body-range-v2 :test #'string=)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 omitted transactions")
             (devnet-smoke-gate-require
              (listp payload-body-range-v2-transactions)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 transactions must be a JSON array")
             (devnet-smoke-gate-require
              (null payload-body-range-v2-transactions)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 transactions mismatch: ~S"
              payload-body-range-v2-transactions)
             (devnet-smoke-gate-require
              (assoc "withdrawals" payload-body-range-v2 :test #'string=)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 omitted withdrawals")
             (devnet-smoke-gate-require
              (listp payload-body-range-v2-withdrawals)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 withdrawals must be a JSON array")
             (devnet-smoke-gate-require
              (null payload-body-range-v2-withdrawals)
              "KZG opt-in engine_getPayloadBodiesByRangeV2 withdrawals mismatch: ~S"
              payload-body-range-v2-withdrawals)
             (devnet-smoke-gate-require
              (field-present-p payload-body-range-v2 "blockAccessList")
              "KZG opt-in engine_getPayloadBodiesByRangeV2 omitted blockAccessList")
             (devnet-smoke-gate-require
              (string= (getf blob-database :block-access-list-hex)
                       (fixture-object-field payload-body-range-v2
                                             "blockAccessList"))
              "KZG opt-in engine_getPayloadBodiesByRangeV2 blockAccessList mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-zero-start-response))
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-zero-start-error
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-zero-start-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-zero-start-error
                  "code"))
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-zero-start-error)
             (devnet-smoke-gate-require
              (string= "start and count must be positive numbers"
                       (fixture-object-field
                        get-payload-bodies-range-v2-zero-start-error
                        "message"))
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-zero-start-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-zero-start-rpc
                                    "result"))
              "KZG opt-in zero-start engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-zero-start-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-zero-count-response))
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-zero-count-error
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-zero-count-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-zero-count-error
                  "code"))
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-zero-count-error)
             (devnet-smoke-gate-require
              (string= "start and count must be positive numbers"
                       (fixture-object-field
                        get-payload-bodies-range-v2-zero-count-error
                        "message"))
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-zero-count-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-zero-count-rpc
                                    "result"))
              "KZG opt-in zero-count engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-zero-count-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-malformed-start-response))
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-malformed-start-error
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-malformed-start-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-malformed-start-error
                  "code"))
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-malformed-start-error)
             (devnet-smoke-gate-require
              (string= "start must be a non-negative quantity"
                       (fixture-object-field
                        get-payload-bodies-range-v2-malformed-start-error
                        "message"))
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-malformed-start-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-malformed-start-rpc
                                    "result"))
              "KZG opt-in malformed-start engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-malformed-start-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-malformed-count-response))
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-malformed-count-error
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-malformed-count-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-malformed-count-error
                  "code"))
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-malformed-count-error)
             (devnet-smoke-gate-require
             (string= "count must be a non-negative quantity"
                       (fixture-object-field
                        get-payload-bodies-range-v2-malformed-count-error
                        "message"))
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-malformed-count-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-malformed-count-rpc
                                    "result"))
              "KZG opt-in malformed-count engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-malformed-count-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-params-envelope-response))
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-params-envelope-error
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-params-envelope-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-params-envelope-error
                  "code"))
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-params-envelope-error)
             (devnet-smoke-gate-require
              (string= "engine_getPayloadBodiesByRangeV2 param count is missing"
                       (fixture-object-field
                        get-payload-bodies-range-v2-params-envelope-error
                        "message"))
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-params-envelope-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-params-envelope-rpc
                    "result"))
              "KZG opt-in params-envelope engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-params-envelope-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-invalid-request-response))
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-invalid-request-error
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-invalid-request-rpc)
             (devnet-smoke-gate-require
              (= -32600
                 (fixture-object-field
                  get-payload-bodies-range-v2-invalid-request-error
                  "code"))
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-invalid-request-error)
             (devnet-smoke-gate-require
              (string= "Invalid Request"
                       (fixture-object-field
                        get-payload-bodies-range-v2-invalid-request-error
                        "message"))
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-invalid-request-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-invalid-request-rpc
                    "result"))
              "KZG opt-in invalid-request engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-invalid-request-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-null-params-response))
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-null-params-error
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-null-params-rpc)
             (devnet-smoke-gate-require
              (= -32602
                 (fixture-object-field
                  get-payload-bodies-range-v2-null-params-error
                  "code"))
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-null-params-error)
             (devnet-smoke-gate-require
              (string= "engine_getPayloadBodiesByRangeV2 params must include start and count"
                       (fixture-object-field
                        get-payload-bodies-range-v2-null-params-error
                        "message"))
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-null-params-error)
             (devnet-smoke-gate-require
              (not (field-present-p
                    get-payload-bodies-range-v2-null-params-rpc
                    "result"))
              "KZG opt-in null-params engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-null-params-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status
                      get-payload-bodies-range-v2-oversized-response))
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              get-payload-bodies-range-v2-oversized-error
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 unexpectedly returned success: ~S"
              get-payload-bodies-range-v2-oversized-rpc)
             (devnet-smoke-gate-require
              (= -38004
                 (fixture-object-field
                  get-payload-bodies-range-v2-oversized-error
                  "code"))
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 error code mismatch: ~S"
              get-payload-bodies-range-v2-oversized-error)
             (devnet-smoke-gate-require
              (string= "The number of requested bodies must not exceed 1024"
                       (fixture-object-field
                        get-payload-bodies-range-v2-oversized-error
                        "message"))
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 error message mismatch: ~S"
              get-payload-bodies-range-v2-oversized-error)
             (devnet-smoke-gate-require
              (not (field-present-p get-payload-bodies-range-v2-oversized-rpc
                                    "result"))
              "KZG opt-in oversized engine_getPayloadBodiesByRangeV2 should not include a success result: ~S"
              get-payload-bodies-range-v2-oversized-rpc)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-blobs-v1-response))
              "KZG opt-in engine_getBlobsV1 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-blobs-v1-rpc "error"))
              "KZG opt-in engine_getBlobsV1 returned an error: ~S"
              (fixture-object-field get-blobs-v1-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-blobs-v1-result)
                   (= 2 (length get-blobs-v1-result)))
              "KZG opt-in engine_getBlobsV1 result count mismatch: ~S"
              get-blobs-v1-result)
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v1 "blob")
              "KZG opt-in engine_getBlobsV1 omitted blob")
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v1 "proof")
              "KZG opt-in engine_getBlobsV1 omitted proof")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (fixture-object-field direct-blob-v1 "blob"))
              "KZG opt-in engine_getBlobsV1 blob mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :proof-hex)
                       (fixture-object-field direct-blob-v1 "proof"))
              "KZG opt-in engine_getBlobsV1 proof mismatch")
             (devnet-smoke-gate-require
              (null missing-blob-v1)
              "KZG opt-in engine_getBlobsV1 unknown hash must return null: ~S"
              missing-blob-v1)
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-blobs-v2-response))
              "KZG opt-in engine_getBlobsV2 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-blobs-v2-rpc "error"))
              "KZG opt-in engine_getBlobsV2 returned an error: ~S"
              (fixture-object-field get-blobs-v2-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-blobs-v2-result)
                   (= 1 (length get-blobs-v2-result)))
              "KZG opt-in engine_getBlobsV2 result count mismatch: ~S"
              get-blobs-v2-result)
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v2 "blob")
              "KZG opt-in engine_getBlobsV2 omitted blob")
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v2 "proofs")
              "KZG opt-in engine_getBlobsV2 omitted proofs")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (fixture-object-field direct-blob-v2 "blob"))
              "KZG opt-in engine_getBlobsV2 blob mismatch")
             (devnet-smoke-gate-require
              (and (listp direct-blob-v2-proofs)
                   (= (getf blob-database :cell-proof-count)
                      (length direct-blob-v2-proofs)))
              "KZG opt-in engine_getBlobsV2 cell proof count mismatch: ~S"
              direct-blob-v2-proofs)
             (devnet-smoke-gate-require
              (string= (getf blob-database :first-cell-proof-hex)
                       (first direct-blob-v2-proofs))
              "KZG opt-in engine_getBlobsV2 first cell proof mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :last-cell-proof-hex)
                       (car (last direct-blob-v2-proofs)))
              "KZG opt-in engine_getBlobsV2 last cell proof mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status get-blobs-v3-response))
              "KZG opt-in engine_getBlobsV3 HTTP status mismatch")
             (devnet-smoke-gate-require
              (not (fixture-object-field get-blobs-v3-rpc "error"))
              "KZG opt-in engine_getBlobsV3 returned an error: ~S"
              (fixture-object-field get-blobs-v3-rpc "error"))
             (devnet-smoke-gate-require
              (and (listp get-blobs-v3-result)
                   (= 2 (length get-blobs-v3-result)))
              "KZG opt-in engine_getBlobsV3 result count mismatch: ~S"
              get-blobs-v3-result)
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v3 "blob")
              "KZG opt-in engine_getBlobsV3 omitted blob")
             (devnet-smoke-gate-require
              (field-present-p direct-blob-v3 "proofs")
              "KZG opt-in engine_getBlobsV3 omitted proofs")
             (devnet-smoke-gate-require
              (string= (getf blob-database :blob-hex)
                       (fixture-object-field direct-blob-v3 "blob"))
              "KZG opt-in engine_getBlobsV3 blob mismatch")
             (devnet-smoke-gate-require
              (and (listp direct-blob-v3-proofs)
                   (= (getf blob-database :cell-proof-count)
                      (length direct-blob-v3-proofs)))
              "KZG opt-in engine_getBlobsV3 cell proof count mismatch: ~S"
              direct-blob-v3-proofs)
             (devnet-smoke-gate-require
              (string= (getf blob-database :first-cell-proof-hex)
                       (first direct-blob-v3-proofs))
              "KZG opt-in engine_getBlobsV3 first cell proof mismatch")
             (devnet-smoke-gate-require
              (string= (getf blob-database :last-cell-proof-hex)
                       (car (last direct-blob-v3-proofs)))
              "KZG opt-in engine_getBlobsV3 last cell proof mismatch")
             (devnet-smoke-gate-require
              (null missing-blob-v3)
              "KZG opt-in engine_getBlobsV3 unknown hash must return null: ~S"
              missing-blob-v3)
             (let ((status (devnet-cli-wait-process-exit process 10)))
               (when (eq status :timeout)
                 (uiop:terminate-process process))
               (devnet-smoke-gate-require
                (and (numberp status) (= 0 status))
                "KZG opt-in devnet process status mismatch: ~A"
                status)
               (let ((stdout
                       (devnet-cli-read-stream-string
                        (uiop:process-info-output process)))
                     (stderr
                       (devnet-cli-read-stream-string
                        (uiop:process-info-error-output process))))
                 (devnet-smoke-gate-require
                  (string= "" stderr)
                  "KZG opt-in devnet stderr mismatch: ~S"
                  stderr)
                 (let* ((stdout-summary (parse-json stdout))
                        (log-records (devnet-smoke-gate-file-forms log-path))
                        (ready-record
                          (find "devnet.ready" log-records
                                :test #'string=
                                :key (lambda (record)
                                       (getf record :name))))
                        (shutdown-record
                          (find "devnet.shutdown" log-records
                                :test #'string=
                                :key (lambda (record)
                                       (getf record :name))))
                        (shutdown-fields (getf shutdown-record :fields)))
                   (dolist (summary (list stdout-summary ready-summary))
                     (devnet-smoke-gate-require
                      (string= (namestring kzg-command)
                               (fixture-object-field
                                summary
                                "kzgVerifierCommand"))
                      "KZG opt-in summary verifier command mismatch")
                     (devnet-smoke-gate-require
                      (= 2 (fixture-object-field
                            summary
                            "kzgVerifierTimeoutSeconds"))
                      "KZG opt-in summary verifier timeout mismatch")
                     (devnet-smoke-gate-require
                      (fixture-object-field
                       summary
                       "kzgProofVerificationAvailable")
                      "KZG opt-in summary proof availability mismatch"))
                   (dolist (record (list ready-record shutdown-record))
                     (devnet-smoke-gate-require
                      record
                      "KZG opt-in log omitted lifecycle record")
                     (let ((fields (getf record :fields)))
                       (devnet-smoke-gate-require
                        (string= (namestring kzg-command)
                                 (cdr (assoc "kzgVerifierCommand"
                                             fields
                                             :test #'string=)))
                        "KZG opt-in log verifier command mismatch")
                       (devnet-smoke-gate-require
                        (string= "2"
                                 (cdr (assoc "kzgVerifierTimeoutSeconds"
                                             fields
                                             :test #'string=)))
                        "KZG opt-in log verifier timeout mismatch")
                       (devnet-smoke-gate-require
                        (string= "true"
                                 (cdr (assoc "kzgProofVerificationAvailable"
                                             fields
                                             :test #'string=)))
                        "KZG opt-in log proof availability mismatch")))
                   (devnet-smoke-gate-require
                    (string= "21"
                             (cdr (assoc "engineConnections"
                                         shutdown-fields
                                         :test #'string=)))
                    "KZG opt-in shutdown engine connection count mismatch")
                   (devnet-smoke-gate-require
                    (string= "0"
                             (cdr (assoc "publicConnections"
                                         shutdown-fields
                                         :test #'string=)))
                    "KZG opt-in shutdown public connection count mismatch")
                   (devnet-smoke-gate-require
                    (string= "21"
                             (cdr (assoc "totalConnections"
                                         shutdown-fields
                                         :test #'string=)))
                    "KZG opt-in shutdown total connection count mismatch")
                   (setf report
                         (list
                          (cons "status" "ok")
                          (cons "mode" "devnet-engine-only-kzg-opt-in")
                          (cons "publicRpcEnabled" :false)
                          (cons "rpcEndpoint" :false)
                          (cons "engineEndpoint" engine-endpoint)
                          (cons "kzgVerifierCommand"
                                (namestring kzg-command))
                          (cons "kzgVerifierCommandOption"
                                "--kzg.verifier-command")
                          (cons "kzgVerifierTimeoutSeconds" 2)
                          (cons "kzgVerifierTimeoutOption"
                                "--kzg.verifier-timeout")
                          (cons "kzgProofVerificationAvailable" t)
                          (cons "engineCapabilityCount"
                                (length capabilities-result))
                          (cons "engineCapabilityHasForkchoiceUpdatedV3"
                                (if (member "engine_forkchoiceUpdatedV3"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasForkchoiceUpdatedV4"
                                (if (member "engine_forkchoiceUpdatedV4"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasGetPayloadV3"
                                (if (member "engine_getPayloadV3"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasGetPayloadV4"
                                (if (member "engine_getPayloadV4"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasGetPayloadV6"
                                (if (member "engine_getPayloadV6"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasNewPayloadV3"
                                (if (member "engine_newPayloadV3"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasGetBlobsV1"
                                (if (member "engine_getBlobsV1"
                                            capabilities-result
                                            :test #'string=)
                                    t
                                    :false))
                          (cons "engineCapabilityHasPayloadBodiesV2"
                                (if (member
                                     "engine_getPayloadBodiesByHashV2"
                                     capabilities-result
                                     :test #'string=)
                                    t
                                    :false))
                          (cons "preparedPayloadV3Id" payload-id-v3)
                          (cons "preparedPayloadV3ParentHash"
                                (fixture-object-field execution-payload-v3
                                                      "parentHash"))
                          (cons "preparedPayloadV3BlockNumber"
                                (fixture-object-field execution-payload-v3
                                                      "blockNumber"))
                          (cons "preparedPayloadV3ShouldOverrideBuilder"
                                (fixture-object-field payload-envelope-v3
                                                      "shouldOverrideBuilder"))
                          (cons "preparedPayloadV3BlobCount"
                                (length
                                 (fixture-object-field blobs-bundle-v3
                                                       "blobs")))
                          (cons "preparedPayloadV4Id" payload-id-v4)
                          (cons "preparedPayloadV4ParentHash"
                                (fixture-object-field execution-payload-v4
                                                      "parentHash"))
                          (cons "preparedPayloadV4BlockNumber"
                                (fixture-object-field execution-payload-v4
                                                      "blockNumber"))
                          (cons "preparedPayloadV4SlotNumber"
                                (fixture-object-field execution-payload-v4
                                                      "slotNumber"))
                          (cons "preparedPayloadV4ShouldOverrideBuilder"
                                (fixture-object-field payload-envelope-v4
                                                      "shouldOverrideBuilder"))
                          (cons "preparedPayloadV4BlobCount"
                                (length
                                 (fixture-object-field blobs-bundle-v4
                                                       "blobs")))
                          (cons "preparedPayloadV5Id"
                                (getf blob-database :payload-id))
                          (cons "preparedPayloadV5BlockNumber"
                                (fixture-object-field execution-payload-v5
                                                      "blockNumber"))
                          (cons "preparedPayloadV5BlobPrefix"
                                (hex-prefix
                                 (first (fixture-object-field blobs-bundle-v5
                                                              "blobs"))
                                 8))
                          (cons "preparedPayloadV5BlobCount"
                                (length
                                 (fixture-object-field blobs-bundle-v5
                                                       "blobs")))
                          (cons "preparedPayloadV5Commitment"
                                (first (fixture-object-field
                                        blobs-bundle-v5
                                        "commitments")))
                          (cons "preparedPayloadV5ProofCount"
                                (length
                                 (fixture-object-field blobs-bundle-v5
                                                       "proofs")))
                          (cons "preparedPayloadV6Id"
                                (getf blob-database :payload-id-v6))
                          (cons "preparedPayloadV6BlockHash"
                                (getf blob-database :block-hash-v6))
                          (cons "preparedPayloadV6BlockNumber"
                                (fixture-object-field execution-payload-v6
                                                      "blockNumber"))
                          (cons "preparedPayloadV6SlotNumber"
                                (fixture-object-field execution-payload-v6
                                                      "slotNumber"))
                          (cons "preparedPayloadV6ExecutionRequestCount"
                                (length execution-requests-v6))
                          (cons "preparedPayloadV6FirstExecutionRequest"
                                (first execution-requests-v6))
                          (cons "preparedPayloadV6BlockAccessList"
                                (fixture-object-field execution-payload-v6
                                                      "blockAccessList"))
                          (cons "preparedPayloadV6BlockAccessListPrefix"
                                (hex-prefix
                                 (fixture-object-field execution-payload-v6
                                                       "blockAccessList")
                                 8))
                          (cons "preparedPayloadV6BlobPrefix"
                                (hex-prefix
                                 (first (fixture-object-field blobs-bundle-v6
                                                              "blobs"))
                                 8))
                          (cons "preparedPayloadV6BlobCount"
                                (length
                                 (fixture-object-field blobs-bundle-v6
                                                       "blobs")))
                          (cons "preparedPayloadV6Commitment"
                                (first (fixture-object-field
                                        blobs-bundle-v6
                                        "commitments")))
                          (cons "preparedPayloadV6ProofCount"
                                (length
                                 (fixture-object-field blobs-bundle-v6
                                                       "proofs")))
                          (cons "preparedPayloadBodiesByHashV2Count"
                                (length get-payload-bodies-v2-result))
                          (cons "preparedPayloadBodiesByHashV2TransactionCount"
                                (length payload-body-v2-transactions))
                          (cons "preparedPayloadBodiesByHashV2WithdrawalCount"
                                (length payload-body-v2-withdrawals))
                          (cons "preparedPayloadBodiesByHashV2BlockAccessList"
                                (fixture-object-field payload-body-v2
                                                      "blockAccessList"))
                          (cons "preparedPayloadBodiesByRangeV2StartBlockNumber"
                                payload-bodies-range-v2-start-block)
                          (cons "preparedPayloadBodiesByRangeV2Count"
                                (length get-payload-bodies-range-v2-result))
                          (cons "preparedPayloadBodiesByRangeV2LeadingNull"
                                (if (null missing-payload-body-range-v2)
                                    t
                                    :false))
                          (cons "preparedPayloadBodiesByRangeV2HitIndex" 1)
                          (cons "preparedPayloadBodiesByRangeV2TransactionCount"
                                (length payload-body-range-v2-transactions))
                          (cons "preparedPayloadBodiesByRangeV2WithdrawalCount"
                                (length payload-body-range-v2-withdrawals))
                          (cons "preparedPayloadBodiesByRangeV2BlockAccessList"
                                (fixture-object-field payload-body-range-v2
                                                      "blockAccessList"))
                          (cons "preparedPayloadBodiesByRangeV2ZeroStartErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-zero-start-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2ZeroStartErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-zero-start-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2ZeroCountErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-zero-count-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2ZeroCountErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-zero-count-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2MalformedStartErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-malformed-start-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2MalformedStartErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-malformed-start-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2MalformedCountErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-malformed-count-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2MalformedCountErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-malformed-count-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2ParamsEnvelopeErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-params-envelope-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2ParamsEnvelopeErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-params-envelope-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2InvalidRequestErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-invalid-request-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2InvalidRequestErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-invalid-request-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2NullParamsErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-null-params-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2NullParamsErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-null-params-error
                                 "message"))
                          (cons "preparedPayloadBodiesByRangeV2OversizedErrorCode"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-oversized-error
                                 "code"))
                          (cons "preparedPayloadBodiesByRangeV2OversizedErrorMessage"
                                (fixture-object-field
                                 get-payload-bodies-range-v2-oversized-error
                                 "message"))
                          (cons "directBlobLookupVersionedHash"
                                (getf blob-database :versioned-hash-hex))
                          (cons "directBlobLookupCount"
                                (length get-blobs-v1-result))
                          (cons "directBlobLookupBlobPrefix"
                                (hex-prefix
                                 (fixture-object-field direct-blob-v1 "blob")
                                 8))
                          (cons "directBlobLookupBlobHexLength"
                                (length
                                 (fixture-object-field direct-blob-v1 "blob")))
                          (cons "directBlobLookupProof"
                                (fixture-object-field direct-blob-v1 "proof"))
                          (cons "directBlobLookupProofPrefix"
                                (hex-prefix
                                 (fixture-object-field direct-blob-v1 "proof")
                                 8))
                          (cons "directBlobLookupProofHexLength"
                                (length
                                 (fixture-object-field direct-blob-v1 "proof")))
                          (cons "directCellProofLookupV2Count"
                                (length get-blobs-v2-result))
                          (cons "directCellProofLookupV3Count"
                                (length get-blobs-v3-result))
                          (cons "directCellProofLookupProofCount"
                                (length direct-blob-v2-proofs))
                          (cons "directCellProofLookupFirstProof"
                                (first direct-blob-v2-proofs))
                          (cons "directCellProofLookupFirstProofPrefix"
                                (hex-prefix
                                 (first direct-blob-v2-proofs)
                                 8))
                          (cons "directCellProofLookupLastProof"
                                (car (last direct-blob-v2-proofs)))
                          (cons "directCellProofLookupLastProofPrefix"
                                (hex-prefix
                                 (car (last direct-blob-v2-proofs))
                                 8))
                          (cons "engineConnections" 21)
                          (cons "publicConnections" 0)
                          (cons "totalConnections" 21))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (and database-path (probe-file database-path))
        (delete-file database-path))
      (when (probe-file kzg-command)
        (delete-file kzg-command))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))
      report))
  #-sbcl
  (error "Devnet engine-only KZG opt-in smoke requires SBCL sockets"))

(defun devnet-smoke-gate-verify-restored-public-rpc
    (node expected-block-number balance-targets
     sender-address expected-sender-nonce
     code-address expected-code storage-address storage-key expected-storage
     transaction-checks log-targets block-hash
     expected-safe-block-number expected-safe-block-hash
     expected-finalized-block-number expected-finalized-block-hash
     &key pruned-state-rpc-tag
          (expected-head-block-number expected-block-number))
  #+sbcl
  (let* ((primary-balance-target (first balance-targets))
         (balance-address (getf primary-balance-target :address))
         (expected-balance (getf primary-balance-target :balance))
         (primary-transaction-check (first transaction-checks))
         (transaction-hash (getf primary-transaction-check :hash))
         (expected-raw-transaction (getf primary-transaction-check :raw))
         (transaction-count (length transaction-checks))
         (expected-transaction-count (quantity-to-hex transaction-count))
         (executable-code-p
           (devnet-smoke-gate-executable-code-p expected-code))
         (extra-balance-outputs
           (loop repeat (length (rest balance-targets))
                 collect (make-string-output-stream)))
         (extra-receipt-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-transaction-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-raw-transaction-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-raw-transaction-by-hash-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-raw-transaction-by-number-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-transaction-by-hash-index-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (extra-transaction-by-number-index-outputs
           (loop repeat (length (rest transaction-checks))
                 collect (make-string-output-stream)))
         (log-range-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-block-hash-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-filter-create-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-filter-logs-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-filter-uninstall-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (log-filter-missing-outputs
           (loop repeat (length log-targets)
                 collect (make-string-output-stream)))
         (block-filter-create-output (make-string-output-stream))
         (block-filter-changes-output (make-string-output-stream))
         (block-filter-get-logs-output (make-string-output-stream))
         (block-filter-uninstall-output (make-string-output-stream))
         (block-filter-missing-output (make-string-output-stream))
         (block-number-output (make-string-output-stream))
        (balance-output (make-string-output-stream))
        (nonce-output (make-string-output-stream))
        (code-output (make-string-output-stream))
        (storage-output (make-string-output-stream))
        (proof-output (make-string-output-stream))
        (receipt-output (make-string-output-stream))
        (block-output (make-string-output-stream))
        (block-by-number-output (make-string-output-stream))
        (full-block-output (make-string-output-stream))
        (full-block-by-number-output (make-string-output-stream))
        (transaction-output (make-string-output-stream))
        (block-receipts-output (make-string-output-stream))
        (block-transaction-count-by-hash-output (make-string-output-stream))
        (block-transaction-count-by-number-output (make-string-output-stream))
        (canonical-hash-balance-output (make-string-output-stream))
        (canonical-hash-require-balance-output (make-string-output-stream))
        (raw-transaction-output (make-string-output-stream))
        (raw-transaction-by-hash-output (make-string-output-stream))
        (raw-transaction-by-number-output (make-string-output-stream))
        (transaction-by-hash-index-output (make-string-output-stream))
        (transaction-by-number-index-output (make-string-output-stream))
        (safe-block-output (make-string-output-stream))
        (finalized-block-output (make-string-output-stream))
        (call-output (make-string-output-stream))
        (failed-call-output
          (and executable-code-p (make-string-output-stream)))
        (estimate-gas-output (make-string-output-stream))
        (create-access-list-output (make-string-output-stream))
        (post-call-storage-output (make-string-output-stream))
        (pruned-state-probes
          (when pruned-state-rpc-tag
            (devnet-smoke-gate-state-error-probes
             154
             pruned-state-rpc-tag
             (devnet-smoke-gate-pruned-state-error-messages)
             balance-address
             sender-address
             code-address
             storage-address
             storage-key)))
         (expected-public-connections
           (+ 22
              (length extra-balance-outputs)
              (* 7 (length extra-receipt-outputs))
              (* 6 (length log-targets))
              5
              2
              4
              (if executable-code-p 1 0)
              (length pruned-state-probes)))
        (public-requests nil))
    (setf public-requests
          (remove
           nil
           (list
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 41)
                    (cons "method" "eth_blockNumber")
                    (cons "params" '())))
             block-number-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 42)
                    (cons "method" "eth_getBalance")
                    (cons "params"
                          (list (address-to-hex balance-address)
                                expected-block-number))))
             balance-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 43)
                   (cons "method" "eth_getTransactionCount")
                   (cons "params" (list (address-to-hex sender-address)
                                        expected-block-number))))
            nonce-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 44)
                   (cons "method" "eth_getCode")
                   (cons "params" (list (address-to-hex code-address)
                                        expected-block-number))))
            code-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 45)
                   (cons "method" "eth_getStorageAt")
                   (cons "params" (list (address-to-hex storage-address)
                                        storage-key
                                        expected-block-number))))
            storage-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 46)
                   (cons "method" "eth_getProof")
                   (cons "params" (list (address-to-hex storage-address)
                                        (list storage-key)
                                        expected-block-number))))
            proof-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 47)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            receipt-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 48)
                   (cons "method" "eth_getBlockByHash")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        :false))))
            block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 49)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list expected-block-number :false))))
            block-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 165)
                   (cons "method" "eth_getBlockByHash")
                   (cons "params" (list (hash32-to-hex block-hash) t))))
            full-block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 166)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list expected-block-number t))))
           full-block-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 50)
                   (cons "method" "eth_getTransactionByHash")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            transaction-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 167)
                   (cons "method" "eth_getRawTransactionByHash")
                   (cons "params" (list (hash32-to-hex transaction-hash)))))
            raw-transaction-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 51)
                   (cons "method" "eth_getBlockReceipts")
                   (cons "params" (list (hash32-to-hex block-hash)))))
            block-receipts-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 52)
                   (cons "method" "eth_getBlockTransactionCountByHash")
                   (cons "params" (list (hash32-to-hex block-hash)))))
            block-transaction-count-by-hash-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 53)
                   (cons "method" "eth_getBlockTransactionCountByNumber")
                   (cons "params" (list expected-block-number))))
            block-transaction-count-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 163)
                   (cons "method" "eth_getBalance")
                   (cons "params"
                         (list
                          (address-to-hex balance-address)
                          (list (cons "blockHash"
                                      (hash32-to-hex block-hash)))))))
            canonical-hash-balance-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 164)
                   (cons "method" "eth_getBalance")
                   (cons "params"
                         (list
                          (address-to-hex balance-address)
                          (list (cons "blockHash"
                                      (hash32-to-hex block-hash))
                                (cons "requireCanonical" t))))))
            canonical-hash-require-balance-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 54)
                   (cons "method" "eth_getRawTransactionByBlockHashAndIndex")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        "0x0"))))
            raw-transaction-by-hash-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 55)
                   (cons "method" "eth_getRawTransactionByBlockNumberAndIndex")
                   (cons "params" (list expected-block-number "0x0"))))
            raw-transaction-by-number-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 56)
                   (cons "method" "eth_getTransactionByBlockHashAndIndex")
                   (cons "params" (list (hash32-to-hex block-hash)
                                        "0x0"))))
            transaction-by-hash-index-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 57)
                   (cons "method" "eth_getTransactionByBlockNumberAndIndex")
                   (cons "params" (list expected-block-number "0x0"))))
            transaction-by-number-index-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 58)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list "safe" :false))))
            safe-block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 59)
                   (cons "method" "eth_getBlockByNumber")
                   (cons "params" (list "finalized" :false))))
            finalized-block-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 150)
                   (cons "method" "eth_call")
                   (cons "params"
                         (list
                          (devnet-smoke-gate-simulation-call-object
                           sender-address code-address)
                          expected-block-number))))
            call-output)
           (when executable-code-p
             (cons
              (json-encode
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 162)
                     (cons "method" "eth_call")
                     (cons "params"
                           (list
                            (list
                             (cons "from" (address-to-hex sender-address))
                             (cons "to" (address-to-hex code-address))
                             (cons "gas" (quantity-to-hex 22000))
                             (cons "gasPrice" "0x64")
                             (cons "data" "0x"))
                            expected-block-number))))
              failed-call-output))
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 151)
                   (cons "method" "eth_estimateGas")
                   (cons "params"
                         (list
                          (devnet-smoke-gate-simulation-call-object
                           sender-address code-address)
                          expected-block-number))))
            estimate-gas-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 152)
                   (cons "method" "eth_createAccessList")
                   (cons "params"
                         (list
                          (devnet-smoke-gate-simulation-call-object
                           sender-address code-address)
                          expected-block-number))))
            create-access-list-output)
           (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 153)
                   (cons "method" "eth_getStorageAt")
                   (cons "params" (list (address-to-hex storage-address)
                                        storage-key
                                        expected-block-number))))
            post-call-storage-output))))
    (when pruned-state-probes
      (setf public-requests
            (append
             public-requests
             (mapcar
              (lambda (probe)
                (cons (json-encode (getf probe :request))
                      (getf probe :output)))
              pruned-state-probes))))
    (setf public-requests
          (nconc
           public-requests
           (loop for target in (rest balance-targets)
                 for output in extra-balance-outputs
                 for id from 60
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getBalance")
                         (cons "params"
                               (list
                                (address-to-hex (getf target :address))
                                expected-block-number))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-receipt-outputs
                 for id from 70
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getTransactionReceipt")
                         (cons "params"
                               (list (hash32-to-hex
                                      (getf check :hash))))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-transaction-outputs
                 for id from 80
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getTransactionByHash")
                         (cons "params"
                               (list (hash32-to-hex
                                      (getf check :hash))))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-raw-transaction-outputs
                 for id from 170
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getRawTransactionByHash")
                         (cons "params"
                               (list (hash32-to-hex
                                      (getf check :hash))))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-raw-transaction-by-hash-outputs
                 for index from 1
                 for id from 90
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getRawTransactionByBlockHashAndIndex")
                         (cons "params"
                               (list (hash32-to-hex block-hash)
                                     (quantity-to-hex index)))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-raw-transaction-by-number-outputs
                 for index from 1
                 for id from 100
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getRawTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list expected-block-number
                                     (quantity-to-hex index)))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-transaction-by-hash-index-outputs
                 for index from 1
                 for id from 110
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getTransactionByBlockHashAndIndex")
                         (cons "params"
                               (list (hash32-to-hex block-hash)
                                     (quantity-to-hex index)))))
                  output))
           (loop for check in (rest transaction-checks)
                 for output in extra-transaction-by-number-index-outputs
                 for index from 1
                 for id from 120
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method"
                               "eth_getTransactionByBlockNumberAndIndex")
                         (cons "params"
                               (list expected-block-number
                                     (quantity-to-hex index)))))
                  output))
           (loop for target in log-targets
                 for output in log-range-outputs
                 for id from 130
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" expected-block-number)
                                 (cons "toBlock" expected-block-number)
                                 (cons "address"
                                       (address-to-hex
                                        (getf target :address)))
                                 (cons "topics"
                                       (list (getf target :topic))))))))
                  output))
           (loop for target in log-targets
                 for output in log-block-hash-outputs
                 for id from 140
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getLogs")
                         (cons "params"
                               (list
                                (list
                                 (cons "blockHash"
                                       (hash32-to-hex block-hash))
                                 (cons "address"
                                       (address-to-hex
                                        (getf target :address)))
                                 (cons "topics"
                                       (list (getf target :topic))))))))
                  output))
           (loop for target in log-targets
                 for output in log-filter-create-outputs
                 for id from 180
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_newFilter")
                         (cons "params"
                               (list
                                (list
                                 (cons "fromBlock" expected-block-number)
                                 (cons "toBlock" expected-block-number)
                                 (cons "address"
                                       (address-to-hex
                                        (getf target :address)))
                                 (cons "topics"
                                       (list (getf target :topic))))))))
                  output))
           (loop for target in log-targets
                 for output in log-filter-logs-outputs
                 for filter-id from 1
                 for id from 190
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getFilterLogs")
                         (cons "params"
                               (list (quantity-to-hex filter-id)))))
                  output))
           (loop for target in log-targets
                 for output in log-filter-uninstall-outputs
                 for filter-id from 1
                 for id from 200
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_uninstallFilter")
                         (cons "params"
                               (list (quantity-to-hex filter-id)))))
                  output))
           (loop for target in log-targets
                 for output in log-filter-missing-outputs
                 for filter-id from 1
                 for id from 210
                 collect
                 (cons
                  (json-encode
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" id)
                         (cons "method" "eth_getFilterLogs")
                         (cons "params"
                               (list (quantity-to-hex filter-id)))))
                  output))
           (let ((block-filter-id
                   (quantity-to-hex (1+ (length log-targets)))))
             (list
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 220)
                      (cons "method" "eth_newBlockFilter")
                      (cons "params" '())))
               block-filter-create-output)
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 221)
                      (cons "method" "eth_getFilterChanges")
                      (cons "params" (list block-filter-id))))
               block-filter-changes-output)
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 222)
                      (cons "method" "eth_getFilterLogs")
                      (cons "params" (list block-filter-id))))
               block-filter-get-logs-output)
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 223)
                      (cons "method" "eth_uninstallFilter")
                      (cons "params" (list block-filter-id))))
               block-filter-uninstall-output)
              (cons
               (json-encode
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 224)
                      (cons "method" "eth_getFilterChanges")
                      (cons "params" (list block-filter-id))))
               block-filter-missing-output)))))
    (let ((summary
            (ethereum-lisp.cli:start-devnet-node-listeners
             node
             (make-engine-rpc-http-listener
              :endpoint "restored-engine"
              :accept-function (lambda () nil)
              :close-function (lambda () nil))
             (make-engine-rpc-http-listener
              :endpoint "restored-public"
              :accept-function
              (lambda ()
                (when public-requests
                  (destructuring-bind (body . output)
                      (pop public-requests)
                    (make-engine-rpc-http-connection
                     :input-stream
                     (make-string-input-stream
                      (devnet-cli-json-rpc-http-request body))
                     :output-stream output
                     :close-function (lambda () nil)))))
              :close-function (lambda () nil))
             :max-connections expected-public-connections)))
      (let* ((block-number-response
               (get-output-stream-string block-number-output))
             (balance-response
               (get-output-stream-string balance-output))
             (nonce-response
               (get-output-stream-string nonce-output))
             (code-response
               (get-output-stream-string code-output))
             (storage-response
               (get-output-stream-string storage-output))
             (proof-response
               (get-output-stream-string proof-output))
             (receipt-response
               (get-output-stream-string receipt-output))
             (block-response
               (get-output-stream-string block-output))
             (block-by-number-response
               (get-output-stream-string block-by-number-output))
             (full-block-response
               (get-output-stream-string full-block-output))
             (full-block-by-number-response
               (get-output-stream-string full-block-by-number-output))
             (transaction-response
               (get-output-stream-string transaction-output))
             (raw-transaction-response
               (get-output-stream-string raw-transaction-output))
             (block-receipts-response
               (get-output-stream-string block-receipts-output))
             (block-transaction-count-by-hash-response
               (get-output-stream-string
                block-transaction-count-by-hash-output))
             (block-transaction-count-by-number-response
               (get-output-stream-string
                block-transaction-count-by-number-output))
             (canonical-hash-balance-response
               (get-output-stream-string canonical-hash-balance-output))
             (canonical-hash-require-balance-response
               (get-output-stream-string
                canonical-hash-require-balance-output))
             (raw-transaction-by-hash-response
               (get-output-stream-string raw-transaction-by-hash-output))
             (raw-transaction-by-number-response
               (get-output-stream-string raw-transaction-by-number-output))
             (transaction-by-hash-index-response
               (get-output-stream-string transaction-by-hash-index-output))
             (transaction-by-number-index-response
               (get-output-stream-string transaction-by-number-index-output))
             (safe-block-response
               (get-output-stream-string safe-block-output))
             (finalized-block-response
               (get-output-stream-string finalized-block-output))
             (call-response
               (get-output-stream-string call-output))
             (failed-call-response
               (and failed-call-output
                    (get-output-stream-string failed-call-output)))
             (estimate-gas-response
               (get-output-stream-string estimate-gas-output))
             (create-access-list-response
               (get-output-stream-string create-access-list-output))
             (post-call-storage-response
               (get-output-stream-string post-call-storage-output))
             (block-number-rpc
               (devnet-smoke-gate-rpc-body block-number-response))
             (balance-rpc
               (devnet-smoke-gate-rpc-body balance-response))
             (nonce-rpc
               (devnet-smoke-gate-rpc-body nonce-response))
             (code-rpc
               (devnet-smoke-gate-rpc-body code-response))
             (storage-rpc
               (devnet-smoke-gate-rpc-body storage-response))
             (proof-rpc
               (devnet-smoke-gate-rpc-body proof-response))
             (receipt-rpc
               (devnet-smoke-gate-rpc-body receipt-response))
             (block-rpc
               (devnet-smoke-gate-rpc-body block-response))
             (block-by-number-rpc
               (devnet-smoke-gate-rpc-body block-by-number-response))
             (full-block-rpc
               (devnet-smoke-gate-rpc-body full-block-response))
             (full-block-by-number-rpc
               (devnet-smoke-gate-rpc-body full-block-by-number-response))
             (transaction-rpc
               (devnet-smoke-gate-rpc-body transaction-response))
             (raw-transaction-rpc
               (devnet-smoke-gate-rpc-body raw-transaction-response))
             (block-receipts-rpc
               (devnet-smoke-gate-rpc-body block-receipts-response))
             (block-transaction-count-by-hash-rpc
               (devnet-smoke-gate-rpc-body
                block-transaction-count-by-hash-response))
             (block-transaction-count-by-number-rpc
               (devnet-smoke-gate-rpc-body
                block-transaction-count-by-number-response))
             (canonical-hash-balance-rpc
               (devnet-smoke-gate-rpc-body
                canonical-hash-balance-response))
             (canonical-hash-require-balance-rpc
               (devnet-smoke-gate-rpc-body
                canonical-hash-require-balance-response))
             (raw-transaction-by-hash-rpc
               (devnet-smoke-gate-rpc-body
                raw-transaction-by-hash-response))
             (raw-transaction-by-number-rpc
               (devnet-smoke-gate-rpc-body
                raw-transaction-by-number-response))
             (transaction-by-hash-index-rpc
               (devnet-smoke-gate-rpc-body
                transaction-by-hash-index-response))
             (transaction-by-number-index-rpc
               (devnet-smoke-gate-rpc-body
                transaction-by-number-index-response))
             (safe-block-rpc
               (devnet-smoke-gate-rpc-body safe-block-response))
             (finalized-block-rpc
               (devnet-smoke-gate-rpc-body finalized-block-response))
             (call-rpc
               (devnet-smoke-gate-rpc-body call-response))
             (failed-call-rpc
               (and failed-call-response
                    (devnet-smoke-gate-rpc-body failed-call-response)))
             (estimate-gas-rpc
               (devnet-smoke-gate-rpc-body estimate-gas-response))
             (create-access-list-rpc
               (devnet-smoke-gate-rpc-body create-access-list-response))
             (post-call-storage-rpc
               (devnet-smoke-gate-rpc-body post-call-storage-response))
             (pruned-state-error-messages
               (devnet-smoke-gate-verify-state-error-probes
                pruned-state-probes
                "pruned-state"))
             (actual-block-number
               (fixture-object-field block-number-rpc "result"))
             (actual-balance
               (fixture-object-field balance-rpc "result"))
             (actual-nonce
               (fixture-object-field nonce-rpc "result"))
             (actual-code
               (fixture-object-field code-rpc "result"))
             (actual-storage
               (fixture-object-field storage-rpc "result"))
             (actual-proof
               (fixture-object-field proof-rpc "result"))
             (actual-proof-storage-proofs
               (fixture-object-field actual-proof "storageProof"))
             (actual-proof-storage
               (first actual-proof-storage-proofs))
             (actual-receipt
               (fixture-object-field receipt-rpc "result"))
             (actual-receipt-transaction-hash
               (fixture-object-field actual-receipt "transactionHash"))
             (actual-receipt-block-number
               (fixture-object-field actual-receipt "blockNumber"))
             (actual-receipt-block-hash
               (fixture-object-field actual-receipt "blockHash"))
             (actual-receipt-logs
               (fixture-object-field actual-receipt "logs"))
             (actual-block
               (fixture-object-field block-rpc "result"))
             (actual-block-hash
               (fixture-object-field actual-block "hash"))
             (actual-block-by-hash-number
               (fixture-object-field actual-block "number"))
             (actual-block-transactions
               (fixture-object-field actual-block "transactions"))
             (actual-block-transaction-hash
               (first actual-block-transactions))
             (actual-block-by-number
               (fixture-object-field block-by-number-rpc "result"))
             (actual-block-by-number-hash
               (fixture-object-field actual-block-by-number "hash"))
             (actual-block-by-number-number
               (fixture-object-field actual-block-by-number "number"))
             (actual-block-by-number-transactions
               (fixture-object-field actual-block-by-number "transactions"))
             (actual-block-by-number-transaction-hash
               (first actual-block-by-number-transactions))
             (actual-full-block
               (fixture-object-field full-block-rpc "result"))
             (actual-full-block-transactions
               (fixture-object-field actual-full-block "transactions"))
             (actual-full-block-transaction
               (first actual-full-block-transactions))
             (actual-full-block-transaction-hash
               (fixture-object-field actual-full-block-transaction "hash"))
             (actual-full-block-transaction-index
               (fixture-object-field actual-full-block-transaction
                                     "transactionIndex"))
             (actual-full-block-transaction-block-hash
               (fixture-object-field actual-full-block-transaction
                                     "blockHash"))
             (actual-full-block-transaction-block-number
               (fixture-object-field actual-full-block-transaction
                                     "blockNumber"))
             (actual-full-block-by-number
               (fixture-object-field full-block-by-number-rpc "result"))
             (actual-full-block-by-number-transactions
               (fixture-object-field
                actual-full-block-by-number "transactions"))
             (actual-full-block-by-number-transaction
               (first actual-full-block-by-number-transactions))
             (actual-full-block-by-number-transaction-hash
               (fixture-object-field
                actual-full-block-by-number-transaction "hash"))
             (actual-full-block-by-number-transaction-index
               (fixture-object-field
                actual-full-block-by-number-transaction "transactionIndex"))
             (actual-full-block-by-number-transaction-block-hash
               (fixture-object-field
                actual-full-block-by-number-transaction "blockHash"))
             (actual-full-block-by-number-transaction-block-number
               (fixture-object-field
                actual-full-block-by-number-transaction "blockNumber"))
             (actual-transaction
               (fixture-object-field transaction-rpc "result"))
             (actual-transaction-hash
               (fixture-object-field actual-transaction "hash"))
             (actual-transaction-block-hash
               (fixture-object-field actual-transaction "blockHash"))
             (actual-transaction-block-number
               (fixture-object-field actual-transaction "blockNumber"))
             (actual-raw-transaction
               (fixture-object-field raw-transaction-rpc "result"))
             (actual-block-receipts
               (fixture-object-field block-receipts-rpc "result"))
             (actual-block-receipt
               (first actual-block-receipts))
             (actual-block-receipt-transaction-hash
               (fixture-object-field actual-block-receipt "transactionHash"))
             (actual-block-receipt-block-hash
               (fixture-object-field actual-block-receipt "blockHash"))
             (actual-block-receipt-block-number
               (fixture-object-field actual-block-receipt "blockNumber"))
             (actual-block-receipt-logs
               (fixture-object-field actual-block-receipt "logs"))
             (actual-block-transaction-count-by-hash
               (fixture-object-field
                block-transaction-count-by-hash-rpc "result"))
             (actual-block-transaction-count-by-number
               (fixture-object-field
                block-transaction-count-by-number-rpc "result"))
             (actual-canonical-hash-balance
               (fixture-object-field canonical-hash-balance-rpc "result"))
             (actual-canonical-hash-require-balance
               (fixture-object-field
                canonical-hash-require-balance-rpc "result"))
             (actual-raw-transaction-by-hash
               (fixture-object-field raw-transaction-by-hash-rpc "result"))
             (actual-raw-transaction-by-number
               (fixture-object-field raw-transaction-by-number-rpc "result"))
             (actual-transaction-by-hash-index
               (fixture-object-field transaction-by-hash-index-rpc "result"))
             (actual-transaction-by-number-index
               (fixture-object-field transaction-by-number-index-rpc "result"))
             (actual-transaction-by-hash-index-hash
               (fixture-object-field
                actual-transaction-by-hash-index "hash"))
             (actual-transaction-by-hash-index-block-hash
               (fixture-object-field
                actual-transaction-by-hash-index "blockHash"))
             (actual-transaction-by-hash-index-block-number
               (fixture-object-field
                actual-transaction-by-hash-index "blockNumber"))
             (actual-transaction-by-hash-index-transaction-index
               (fixture-object-field
                actual-transaction-by-hash-index "transactionIndex"))
             (actual-transaction-by-number-index-hash
               (fixture-object-field
                actual-transaction-by-number-index "hash"))
             (actual-transaction-by-number-index-block-hash
               (fixture-object-field
                actual-transaction-by-number-index "blockHash"))
             (actual-transaction-by-number-index-block-number
               (fixture-object-field
                actual-transaction-by-number-index "blockNumber"))
             (actual-transaction-by-number-index-transaction-index
               (fixture-object-field
                actual-transaction-by-number-index "transactionIndex"))
             (actual-safe-block
               (fixture-object-field safe-block-rpc "result"))
             (actual-safe-block-hash
               (fixture-object-field actual-safe-block "hash"))
             (actual-safe-block-number
               (fixture-object-field actual-safe-block "number"))
             (actual-finalized-block
               (fixture-object-field finalized-block-rpc "result"))
             (actual-finalized-block-hash
               (fixture-object-field actual-finalized-block "hash"))
             (actual-finalized-block-number
               (fixture-object-field actual-finalized-block "number"))
             (actual-call-result
               (fixture-object-field call-rpc "result"))
             (actual-failed-call-error
               (and failed-call-rpc
                    (fixture-object-field failed-call-rpc "error")))
             (actual-failed-call-error-message
               (and actual-failed-call-error
                    (fixture-object-field
                     actual-failed-call-error "message")))
             (actual-estimate-gas
               (fixture-object-field estimate-gas-rpc "result"))
             (actual-create-access-list
               (fixture-object-field create-access-list-rpc "result"))
             (actual-access-list
               (fixture-object-field actual-create-access-list "accessList"))
             (actual-access-list-gas-used
               (fixture-object-field actual-create-access-list "gasUsed"))
             (actual-access-list-entry
               (devnet-smoke-gate-access-list-entry
                actual-access-list storage-address))
             (actual-access-list-storage-keys
               (and actual-access-list-entry
                    (fixture-object-field actual-access-list-entry
                                          "storageKeys")))
             (actual-post-call-storage
               (fixture-object-field post-call-storage-rpc "result"))
             (actual-log-filter-log-count 0)
             (actual-log-filter-uninstall-count 0)
             (actual-log-filter-missing-error-codes nil)
             (actual-block-filter-id nil)
             (actual-block-filter-change-count nil)
             (actual-block-filter-get-logs-error-code nil)
             (actual-block-filter-uninstall-result nil)
             (actual-block-filter-missing-error-code nil)
             (expected-proof-code-hash
               (hash32-to-hex (keccak-256-hash (hex-to-bytes expected-code))))
             (expected-proof-storage-value
               (quantity-to-hex (hex-to-quantity expected-storage))))
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Restored database verification should not use Engine RPC")
        (devnet-smoke-gate-require
         (= expected-public-connections (getf summary :public-connections))
         "Restored database verification expected ~S public RPC connections, got ~S"
         expected-public-connections
         (getf summary :public-connections))
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-number-response))
         "Restored eth_blockNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status balance-response))
         "Restored eth_getBalance HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status nonce-response))
         "Restored eth_getTransactionCount HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status code-response))
         "Restored eth_getCode HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status storage-response))
         "Restored eth_getStorageAt HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status proof-response))
         "Restored eth_getProof HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status receipt-response))
         "Restored eth_getTransactionReceipt HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-response))
         "Restored eth_getBlockByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-by-number-response))
         "Restored eth_getBlockByNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status full-block-response))
         "Restored full eth_getBlockByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status full-block-by-number-response))
         "Restored full eth_getBlockByNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-response))
         "Restored eth_getTransactionByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status raw-transaction-response))
         "Restored eth_getRawTransactionByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status block-receipts-response))
         "Restored eth_getBlockReceipts HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status
                 block-transaction-count-by-hash-response))
         "Restored eth_getBlockTransactionCountByHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status
                 block-transaction-count-by-number-response))
         "Restored eth_getBlockTransactionCountByNumber HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status canonical-hash-balance-response))
         "Restored EIP-1898 eth_getBalance blockHash HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status
                 canonical-hash-require-balance-response))
         "Restored EIP-1898 eth_getBalance requireCanonical HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status raw-transaction-by-hash-response))
         "Restored eth_getRawTransactionByBlockHashAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status raw-transaction-by-number-response))
         "Restored eth_getRawTransactionByBlockNumberAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-by-hash-index-response))
         "Restored eth_getTransactionByBlockHashAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status transaction-by-number-index-response))
         "Restored eth_getTransactionByBlockNumberAndIndex HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status safe-block-response))
         "Restored eth_getBlockByNumber safe HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status finalized-block-response))
         "Restored eth_getBlockByNumber finalized HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status call-response))
         "Restored eth_call HTTP status mismatch")
        (when failed-call-response
          (devnet-smoke-gate-require
           (= 200 (devnet-cli-http-status failed-call-response))
           "Restored failing eth_call HTTP status mismatch"))
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status estimate-gas-response))
         "Restored eth_estimateGas HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status create-access-list-response))
         "Restored eth_createAccessList HTTP status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status post-call-storage-response))
         "Restored post-eth_call eth_getStorageAt HTTP status mismatch")
        (devnet-smoke-gate-require
         (string= expected-head-block-number actual-block-number)
         "Restored eth_blockNumber mismatch: expected ~A got ~A"
         expected-head-block-number
         actual-block-number)
        (devnet-smoke-gate-require
         (string= expected-balance actual-balance)
         "Restored eth_getBalance mismatch: expected ~A got ~A"
         expected-balance
         actual-balance)
        (loop for target in (rest balance-targets)
              for output in extra-balance-outputs
              for response = (get-output-stream-string output)
              for rpc = (devnet-smoke-gate-rpc-body response)
              for actual-extra-balance =
                (fixture-object-field rpc "result")
              do
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status response))
                  "Restored extra eth_getBalance HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (string= (getf target :balance) actual-extra-balance)
                  "Restored extra eth_getBalance mismatch: expected ~A got ~A"
                  (getf target :balance)
                  actual-extra-balance))
        (devnet-smoke-gate-require
         (string= expected-sender-nonce actual-nonce)
         "Restored eth_getTransactionCount mismatch: expected ~A got ~A"
         expected-sender-nonce
         actual-nonce)
        (devnet-smoke-gate-require
         (string= expected-code actual-code)
         "Restored eth_getCode mismatch: expected ~A got ~A"
         expected-code
         actual-code)
        (devnet-smoke-gate-require
         (string= expected-storage actual-storage)
         "Restored eth_getStorageAt mismatch: expected ~A got ~A"
         expected-storage
         actual-storage)
        (devnet-smoke-gate-require
         actual-call-result
         "Restored eth_call returned error response: ~S"
         call-rpc)
        (devnet-smoke-gate-require
         (string= "0x" actual-call-result)
         "Restored eth_call result mismatch: expected empty return, got ~A"
         actual-call-result)
        (when executable-code-p
          (devnet-smoke-gate-require
           actual-failed-call-error
           "Restored failing eth_call did not return an error response: ~S"
           failed-call-rpc)
          (devnet-smoke-gate-require
           (string= "eth_call execution failed"
                    actual-failed-call-error-message)
           "Restored failing eth_call error mismatch: ~A"
           actual-failed-call-error-message))
        (devnet-smoke-gate-require
         (<= 21000 (hex-to-quantity actual-estimate-gas))
         "Restored eth_estimateGas must be at least intrinsic gas")
        (devnet-smoke-gate-require
         (stringp actual-access-list-gas-used)
         "Restored eth_createAccessList gasUsed must be a string")
        (when (devnet-smoke-gate-executable-code-p expected-code)
          (devnet-smoke-gate-require
           actual-access-list-entry
           "Restored eth_createAccessList missing storage account entry")
          (devnet-smoke-gate-require
           (member storage-key actual-access-list-storage-keys
                   :test #'string=)
           "Restored eth_createAccessList missing storage key"))
        (devnet-smoke-gate-require
         (string= expected-storage actual-post-call-storage)
         "Restored eth_call mutated retained storage: expected ~A got ~A"
         expected-storage
         actual-post-call-storage)
        (devnet-smoke-gate-require
         (string= (address-to-hex storage-address)
                  (fixture-object-field actual-proof "address"))
         "Restored eth_getProof address mismatch")
        (devnet-smoke-gate-require
         (string= expected-proof-code-hash
                  (fixture-object-field actual-proof "codeHash"))
         "Restored eth_getProof codeHash mismatch: expected ~A got ~A"
         expected-proof-code-hash
         (fixture-object-field actual-proof "codeHash"))
        (devnet-smoke-gate-require
         (listp (fixture-object-field actual-proof "accountProof"))
         "Restored eth_getProof accountProof must be a list")
        (devnet-smoke-gate-require
         (= 1 (length actual-proof-storage-proofs))
         "Restored eth_getProof expected 1 storage proof, got ~S"
         (length actual-proof-storage-proofs))
        (devnet-smoke-gate-require
         (string= storage-key (fixture-object-field actual-proof-storage "key"))
         "Restored eth_getProof storage key mismatch: expected ~A got ~A"
         storage-key
         (fixture-object-field actual-proof-storage "key"))
        (devnet-smoke-gate-require
         (string= expected-proof-storage-value
                  (fixture-object-field actual-proof-storage "value"))
         "Restored eth_getProof storage value mismatch: expected ~A got ~A"
         expected-proof-storage-value
         (fixture-object-field actual-proof-storage "value"))
        (devnet-smoke-gate-require
         (listp (fixture-object-field actual-proof-storage "proof"))
         "Restored eth_getProof storage proof must be a list")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-receipt-transaction-hash)
         "Restored eth_getTransactionReceipt hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-receipt-block-number)
         "Restored eth_getTransactionReceipt block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash) actual-receipt-block-hash)
         "Restored eth_getTransactionReceipt block hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash) actual-block-hash)
         "Restored eth_getBlockByHash hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-by-hash-number)
         "Restored eth_getBlockByHash block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-block-transaction-hash)
         "Restored eth_getBlockByHash transaction list mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-block-transactions))
         "Restored eth_getBlockByHash transaction count mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash) actual-block-by-number-hash)
         "Restored eth_getBlockByNumber hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-by-number-number)
         "Restored eth_getBlockByNumber block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-block-by-number-transaction-hash)
         "Restored eth_getBlockByNumber transaction list mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-block-by-number-transactions))
         "Restored eth_getBlockByNumber transaction count mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-full-block-transactions))
         "Restored full eth_getBlockByHash transaction count mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-full-block-transaction-hash)
         "Restored full eth_getBlockByHash transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" actual-full-block-transaction-index)
         "Restored full eth_getBlockByHash transaction index mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-full-block-transaction-block-hash)
         "Restored full eth_getBlockByHash transaction block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-full-block-transaction-block-number)
         "Restored full eth_getBlockByHash transaction block number mismatch")
        (devnet-smoke-gate-require
         (= transaction-count
            (length actual-full-block-by-number-transactions))
         "Restored full eth_getBlockByNumber transaction count mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-full-block-by-number-transaction-hash)
         "Restored full eth_getBlockByNumber transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" actual-full-block-by-number-transaction-index)
         "Restored full eth_getBlockByNumber transaction index mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-full-block-by-number-transaction-block-hash)
         "Restored full eth_getBlockByNumber transaction block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-full-block-by-number-transaction-block-number)
         "Restored full eth_getBlockByNumber transaction block number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash) actual-transaction-hash)
         "Restored eth_getTransactionByHash hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-transaction-block-hash)
         "Restored eth_getTransactionByHash block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-transaction-block-number)
         "Restored eth_getTransactionByHash block number mismatch")
        (devnet-smoke-gate-require
         (string= expected-raw-transaction actual-raw-transaction)
         "Restored eth_getRawTransactionByHash mismatch")
        (devnet-smoke-gate-require
         (= transaction-count (length actual-block-receipts))
         "Restored eth_getBlockReceipts expected ~S receipts, got ~S"
         transaction-count
         (length actual-block-receipts))
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-block-receipt-transaction-hash)
         "Restored eth_getBlockReceipts transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-block-receipt-block-hash)
         "Restored eth_getBlockReceipts block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number actual-block-receipt-block-number)
         "Restored eth_getBlockReceipts block number mismatch")
        (when log-targets
          (let ((target (first log-targets)))
            (devnet-smoke-gate-require
             (= (getf target :count) (length actual-receipt-logs))
             "Restored eth_getTransactionReceipt log count mismatch")
            (devnet-smoke-gate-require
             (= (getf target :count) (length actual-block-receipt-logs))
             "Restored eth_getBlockReceipts log count mismatch")
            (devnet-smoke-gate-verify-rpc-log
             (first actual-receipt-logs)
             target
             expected-block-number
             block-hash
             transaction-hash
             0
             0
             "Restored eth_getTransactionReceipt")
            (devnet-smoke-gate-verify-rpc-log
             (first actual-block-receipt-logs)
             target
             expected-block-number
             block-hash
             transaction-hash
             0
             0
             "Restored eth_getBlockReceipts")))
        (devnet-smoke-gate-require
         (string= expected-transaction-count
                  actual-block-transaction-count-by-hash)
         "Restored eth_getBlockTransactionCountByHash mismatch")
        (devnet-smoke-gate-require
         (string= expected-transaction-count
                  actual-block-transaction-count-by-number)
         "Restored eth_getBlockTransactionCountByNumber mismatch")
        (devnet-smoke-gate-require
         (string= expected-balance actual-canonical-hash-balance)
         "Restored EIP-1898 eth_getBalance blockHash mismatch: expected ~A got ~A"
         expected-balance
         actual-canonical-hash-balance)
        (devnet-smoke-gate-require
         (string= expected-balance actual-canonical-hash-require-balance)
         "Restored EIP-1898 eth_getBalance requireCanonical mismatch: expected ~A got ~A"
         expected-balance
         actual-canonical-hash-require-balance)
        (devnet-smoke-gate-require
         (string= expected-raw-transaction actual-raw-transaction-by-hash)
         "Restored eth_getRawTransactionByBlockHashAndIndex mismatch")
        (devnet-smoke-gate-require
         (string= expected-raw-transaction actual-raw-transaction-by-number)
         "Restored eth_getRawTransactionByBlockNumberAndIndex mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-transaction-by-hash-index-hash)
         "Restored eth_getTransactionByBlockHashAndIndex hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-transaction-by-hash-index-block-hash)
         "Restored eth_getTransactionByBlockHashAndIndex block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-transaction-by-hash-index-block-number)
         "Restored eth_getTransactionByBlockHashAndIndex block number mismatch")
        (devnet-smoke-gate-require
         (string= "0x0"
                  actual-transaction-by-hash-index-transaction-index)
         "Restored eth_getTransactionByBlockHashAndIndex index mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex transaction-hash)
                  actual-transaction-by-number-index-hash)
         "Restored eth_getTransactionByBlockNumberAndIndex hash mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex block-hash)
                  actual-transaction-by-number-index-block-hash)
         "Restored eth_getTransactionByBlockNumberAndIndex block hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-block-number
                  actual-transaction-by-number-index-block-number)
         "Restored eth_getTransactionByBlockNumberAndIndex block number mismatch")
        (devnet-smoke-gate-require
         (string= "0x0"
                  actual-transaction-by-number-index-transaction-index)
         "Restored eth_getTransactionByBlockNumberAndIndex index mismatch")
        (loop for check in (rest transaction-checks)
              for index from 1
              for receipt-output in extra-receipt-outputs
              for transaction-output in extra-transaction-outputs
              for raw-output in extra-raw-transaction-outputs
              for raw-by-hash-output in extra-raw-transaction-by-hash-outputs
              for raw-by-number-output in extra-raw-transaction-by-number-outputs
              for tx-by-hash-index-output in extra-transaction-by-hash-index-outputs
              for tx-by-number-index-output in extra-transaction-by-number-index-outputs
              for expected-hash = (hash32-to-hex (getf check :hash))
              for expected-raw = (getf check :raw)
              for expected-index = (quantity-to-hex index)
              do
                 (let* ((receipt-response
                          (get-output-stream-string receipt-output))
                        (transaction-response
                          (get-output-stream-string transaction-output))
                        (raw-response
                          (get-output-stream-string raw-output))
                        (raw-by-hash-response
                          (get-output-stream-string raw-by-hash-output))
                        (raw-by-number-response
                          (get-output-stream-string raw-by-number-output))
                        (tx-by-hash-index-response
                          (get-output-stream-string tx-by-hash-index-output))
                        (tx-by-number-index-response
                          (get-output-stream-string
                           tx-by-number-index-output))
                        (receipt
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body receipt-response)
                           "result"))
                        (transaction
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body
                            transaction-response)
                           "result"))
                        (tx-by-hash-index
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body
                            tx-by-hash-index-response)
                           "result"))
                        (tx-by-number-index
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body
                            tx-by-number-index-response)
                           "result")))
                   (dolist (response
                            (list receipt-response transaction-response
                                  raw-response raw-by-hash-response
                                  raw-by-number-response tx-by-hash-index-response
                                  tx-by-number-index-response))
                     (devnet-smoke-gate-require
                      (= 200 (devnet-cli-http-status response))
                      "Restored extra transaction RPC HTTP status mismatch"))
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field receipt
                                                   "transactionHash"))
                    "Restored extra receipt transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-block-number
                             (fixture-object-field receipt "blockNumber"))
                    "Restored extra receipt block number mismatch")
                   (devnet-smoke-gate-require
                    (string= (hash32-to-hex block-hash)
                             (fixture-object-field receipt "blockHash"))
                    "Restored extra receipt block hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field transaction "hash"))
                    "Restored extra eth_getTransactionByHash mismatch")
                   (devnet-smoke-gate-require
                    (string= (hash32-to-hex block-hash)
                             (fixture-object-field transaction
                                                   "blockHash"))
                    "Restored extra eth_getTransactionByHash block hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-block-number
                             (fixture-object-field transaction
                                                   "blockNumber"))
                    "Restored extra eth_getTransactionByHash block number mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-raw
                             (fixture-object-field
                              (devnet-smoke-gate-rpc-body
                               raw-response)
                              "result"))
                    "Restored extra raw transaction by transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-raw
                             (fixture-object-field
                              (devnet-smoke-gate-rpc-body
                               raw-by-hash-response)
                              "result"))
                    "Restored extra raw transaction by hash/index mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-raw
                             (fixture-object-field
                              (devnet-smoke-gate-rpc-body
                               raw-by-number-response)
                              "result"))
                    "Restored extra raw transaction by number/index mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field tx-by-hash-index "hash"))
                    "Restored extra tx by hash/index hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-index
                             (fixture-object-field tx-by-hash-index
                                                   "transactionIndex"))
                    "Restored extra tx by hash/index index mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-hash
                             (fixture-object-field tx-by-number-index "hash"))
                    "Restored extra tx by number/index hash mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-index
                             (fixture-object-field tx-by-number-index
                                                   "transactionIndex"))
                    "Restored extra tx by number/index index mismatch")))
        (loop for target in log-targets
              for range-output in log-range-outputs
              for block-hash-output in log-block-hash-outputs
              do
                 (let* ((range-response
                          (get-output-stream-string range-output))
                        (block-hash-response
                          (get-output-stream-string block-hash-output))
                        (range-logs
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body range-response)
                           "result"))
                        (block-hash-logs
                          (fixture-object-field
                           (devnet-smoke-gate-rpc-body block-hash-response)
                           "result")))
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status range-response))
                    "Restored eth_getLogs range HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status block-hash-response))
                    "Restored eth_getLogs blockHash HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= (getf target :count) (length range-logs))
                    "Restored eth_getLogs range log count mismatch")
                   (devnet-smoke-gate-require
                    (= (getf target :count) (length block-hash-logs))
                    "Restored eth_getLogs blockHash log count mismatch")
                   (devnet-smoke-gate-verify-rpc-log
                    (first range-logs)
                    target
                    expected-block-number
                    block-hash
                    transaction-hash
                    0
                    0
                    "Restored eth_getLogs range")
                   (devnet-smoke-gate-verify-rpc-log
                    (first block-hash-logs)
                    target
                    expected-block-number
                    block-hash
                    transaction-hash
                    0
                    0
                    "Restored eth_getLogs blockHash")))
        (loop for target in log-targets
              for create-output in log-filter-create-outputs
              for logs-output in log-filter-logs-outputs
              for uninstall-output in log-filter-uninstall-outputs
              for missing-output in log-filter-missing-outputs
              for filter-id from 1
              do
                 (let* ((create-response
                          (get-output-stream-string create-output))
                        (logs-response
                          (get-output-stream-string logs-output))
                        (uninstall-response
                          (get-output-stream-string uninstall-output))
                        (missing-response
                          (get-output-stream-string missing-output))
                        (create-rpc
                          (devnet-smoke-gate-rpc-body create-response))
                        (logs-rpc
                          (devnet-smoke-gate-rpc-body logs-response))
                        (uninstall-rpc
                          (devnet-smoke-gate-rpc-body
                           uninstall-response))
                        (missing-rpc
                          (devnet-smoke-gate-rpc-body missing-response))
                        (filter-logs
                          (fixture-object-field logs-rpc "result"))
                        (missing-error-code
                          (devnet-smoke-gate-error-code missing-rpc)))
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status create-response))
                    "Restored eth_newFilter HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status logs-response))
                    "Restored eth_getFilterLogs HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status uninstall-response))
                    "Restored eth_uninstallFilter HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (= 200 (devnet-cli-http-status missing-response))
                    "Restored missing eth_getFilterLogs HTTP status mismatch")
                   (devnet-smoke-gate-require
                    (string= (quantity-to-hex filter-id)
                             (fixture-object-field create-rpc "result"))
                    "Restored eth_newFilter id mismatch")
                   (devnet-smoke-gate-require
                    (= (getf target :count) (length filter-logs))
                    "Restored eth_getFilterLogs log count mismatch")
                   (devnet-smoke-gate-verify-rpc-log
                    (first filter-logs)
                    target
                    expected-block-number
                    block-hash
                    transaction-hash
                    0
                    0
                    "Restored eth_getFilterLogs")
                   (devnet-smoke-gate-require
                    (member (fixture-object-field uninstall-rpc "result")
                            '(t :true))
                    "Restored eth_uninstallFilter result mismatch")
                   (devnet-smoke-gate-require
                    (= -32602 missing-error-code)
                    "Restored missing eth_getFilterLogs error code mismatch")
                   (incf actual-log-filter-log-count
                         (length filter-logs))
                   (incf actual-log-filter-uninstall-count)
                   (push missing-error-code
                         actual-log-filter-missing-error-codes)))
        (let* ((block-filter-create-response
                 (get-output-stream-string block-filter-create-output))
               (block-filter-changes-response
                 (get-output-stream-string block-filter-changes-output))
               (block-filter-get-logs-response
                 (get-output-stream-string block-filter-get-logs-output))
               (block-filter-uninstall-response
                 (get-output-stream-string block-filter-uninstall-output))
               (block-filter-missing-response
                 (get-output-stream-string block-filter-missing-output))
               (block-filter-create-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-create-response))
               (block-filter-changes-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-changes-response))
               (block-filter-get-logs-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-get-logs-response))
               (block-filter-uninstall-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-uninstall-response))
               (block-filter-missing-rpc
                 (devnet-smoke-gate-rpc-body
                  block-filter-missing-response))
               (expected-block-filter-id
                 (quantity-to-hex (1+ (length log-targets))))
               (block-filter-changes
                 (fixture-object-field block-filter-changes-rpc "result")))
          (dolist (response
                   (list block-filter-create-response
                         block-filter-changes-response
                         block-filter-get-logs-response
                         block-filter-uninstall-response
                         block-filter-missing-response))
            (devnet-smoke-gate-require
             (= 200 (devnet-cli-http-status response))
             "Restored block filter HTTP status mismatch"))
          (setf actual-block-filter-id
                (fixture-object-field block-filter-create-rpc "result")
                actual-block-filter-change-count
                (length block-filter-changes)
                actual-block-filter-get-logs-error-code
                (devnet-smoke-gate-error-code block-filter-get-logs-rpc)
                actual-block-filter-uninstall-result
                (fixture-object-field block-filter-uninstall-rpc "result")
                actual-block-filter-missing-error-code
                (devnet-smoke-gate-error-code block-filter-missing-rpc))
          (devnet-smoke-gate-require
           (string= expected-block-filter-id actual-block-filter-id)
           "Restored eth_newBlockFilter id mismatch")
          (devnet-smoke-gate-require
           (zerop actual-block-filter-change-count)
           "Restored eth_getFilterChanges block filter initial count mismatch")
          (devnet-smoke-gate-require
           (= -32602 actual-block-filter-get-logs-error-code)
           "Restored eth_getFilterLogs block filter error code mismatch")
          (devnet-smoke-gate-require
           (member actual-block-filter-uninstall-result '(t :true))
           "Restored eth_uninstallFilter block filter result mismatch")
          (devnet-smoke-gate-require
           (= -32602 actual-block-filter-missing-error-code)
           "Restored missing eth_getFilterChanges block filter error code mismatch"))
        (devnet-smoke-gate-require
         (string= (hash32-to-hex expected-safe-block-hash)
                  actual-safe-block-hash)
         "Restored eth_getBlockByNumber safe hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-safe-block-number actual-safe-block-number)
         "Restored eth_getBlockByNumber safe number mismatch")
        (devnet-smoke-gate-require
         (string= (hash32-to-hex expected-finalized-block-hash)
                  actual-finalized-block-hash)
         "Restored eth_getBlockByNumber finalized hash mismatch")
        (devnet-smoke-gate-require
         (string= expected-finalized-block-number
                  actual-finalized-block-number)
         "Restored eth_getBlockByNumber finalized number mismatch")
        (list :block-number actual-block-number
              :balance actual-balance
              :nonce actual-nonce
              :code actual-code
              :storage actual-storage
              :proof-address (fixture-object-field actual-proof "address")
              :proof-code-hash
              (fixture-object-field actual-proof "codeHash")
              :proof-storage-key
              (fixture-object-field actual-proof-storage "key")
              :proof-storage-value
              (fixture-object-field actual-proof-storage "value")
              :proof-storage-count (length actual-proof-storage-proofs)
              :proof-account-proof-count
              (length (fixture-object-field actual-proof "accountProof"))
              :receipt-transaction-hash actual-receipt-transaction-hash
              :receipt-block-number actual-receipt-block-number
              :block-hash actual-block-hash
              :block-by-hash-number actual-block-by-hash-number
              :block-transaction-hash actual-block-transaction-hash
              :block-by-number-hash actual-block-by-number-hash
              :block-by-number-number actual-block-by-number-number
              :block-by-number-transaction-hash
              actual-block-by-number-transaction-hash
              :full-block-transaction-count
              (length actual-full-block-transactions)
              :full-block-transaction-hash
              actual-full-block-transaction-hash
              :full-block-transaction-index
              actual-full-block-transaction-index
              :full-block-by-number-transaction-count
              (length actual-full-block-by-number-transactions)
              :full-block-by-number-transaction-hash
              actual-full-block-by-number-transaction-hash
              :full-block-by-number-transaction-index
              actual-full-block-by-number-transaction-index
              :transaction-hash actual-transaction-hash
              :transaction-block-hash actual-transaction-block-hash
              :transaction-block-number actual-transaction-block-number
              :raw-transaction actual-raw-transaction
              :block-receipts-count (length actual-block-receipts)
              :block-receipt-transaction-hash
              actual-block-receipt-transaction-hash
              :block-receipt-block-hash actual-block-receipt-block-hash
              :block-receipt-block-number actual-block-receipt-block-number
              :block-transaction-count-by-hash
              actual-block-transaction-count-by-hash
              :block-transaction-count-by-number
              actual-block-transaction-count-by-number
              :canonical-hash-balance actual-canonical-hash-balance
              :canonical-hash-require-balance
              actual-canonical-hash-require-balance
              :transaction-count transaction-count
              :balance-count (length balance-targets)
              :log-count (reduce #'+ log-targets
                                  :key (lambda (target)
                                         (getf target :count))
                                  :initial-value 0)
              :log-filter-count actual-log-filter-uninstall-count
              :log-filter-log-count actual-log-filter-log-count
              :log-filter-uninstall-count
              actual-log-filter-uninstall-count
              :log-filter-missing-error-codes
              (nreverse actual-log-filter-missing-error-codes)
              :block-filter-id actual-block-filter-id
              :block-filter-change-count actual-block-filter-change-count
              :block-filter-get-logs-error-code
              actual-block-filter-get-logs-error-code
              :block-filter-uninstall-result
              actual-block-filter-uninstall-result
              :block-filter-missing-error-code
              actual-block-filter-missing-error-code
              :raw-transaction-by-hash actual-raw-transaction-by-hash
              :raw-transaction-by-number actual-raw-transaction-by-number
              :transaction-by-hash-index-hash
              actual-transaction-by-hash-index-hash
              :transaction-by-hash-index-block-hash
              actual-transaction-by-hash-index-block-hash
              :transaction-by-hash-index-block-number
              actual-transaction-by-hash-index-block-number
              :transaction-by-hash-index-transaction-index
              actual-transaction-by-hash-index-transaction-index
              :transaction-by-number-index-hash
              actual-transaction-by-number-index-hash
              :transaction-by-number-index-block-hash
              actual-transaction-by-number-index-block-hash
              :transaction-by-number-index-block-number
              actual-transaction-by-number-index-block-number
              :transaction-by-number-index-transaction-index
              actual-transaction-by-number-index-transaction-index
              :safe-block-hash actual-safe-block-hash
              :safe-block-number actual-safe-block-number
              :finalized-block-hash actual-finalized-block-hash
              :finalized-block-number actual-finalized-block-number
              :call-result actual-call-result
              :failed-call-error-message
              (or actual-failed-call-error-message :false)
              :estimate-gas actual-estimate-gas
              :access-list-count (length actual-access-list)
              :access-list-gas-used actual-access-list-gas-used
              :post-call-storage actual-post-call-storage
              :simulation-count (if executable-code-p 5 4)
              :pruned-state-error-message
              (first pruned-state-error-messages)
              :pruned-state-error-messages pruned-state-error-messages
              :public-connections (getf summary :public-connections)))))
  #-sbcl
  (error "Restored devnet public RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-engine-rpc
    (node payload-id expected-parent-hash expected-block-number
     expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 170)
                  (cons "method" "engine_getPayloadV2")
                  (cons "params" (list payload-id)))))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 171)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-prepared-payload"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-prepared-payload"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload
           (fixture-object-field
            (fixture-object-field engine-rpc "result")
            "executionPayload")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored Engine prepared-payload probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored Engine prepared-payload probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored engine_getPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored prepared-payload eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored engine_getPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= (hash32-to-hex expected-parent-hash)
              (fixture-object-field payload "parentHash"))
     "Restored prepared payload parent hash mismatch")
    (devnet-smoke-gate-require
     (string= expected-block-number
              (fixture-object-field payload "blockNumber"))
     "Restored prepared payload block number mismatch")
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored prepared-payload public block number mismatch")
    (list :prepared-payload-id payload-id
          :prepared-payload-parent-hash
          (fixture-object-field payload "parentHash")
          :prepared-payload-block-number
          (fixture-object-field payload "blockNumber")
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node payload-id expected-parent-hash expected-block-number
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-remote-block-rpc
    (node remote-payload expected-block-hash expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (engine-fixture-payload-request 172 remote-payload)))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 173)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-remote-block"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-remote-block"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload-status (fixture-object-field engine-rpc "result")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored remote-block probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored remote-block probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored remote-block engine_newPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored remote-block eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored remote-block engine_newPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= +payload-status-syncing+
              (fixture-object-field payload-status "status"))
     "Restored remote-block engine_newPayloadV2 status mismatch")
    (devnet-smoke-gate-require
     (null (fixture-object-field payload-status "latestValidHash"))
     "Restored remote-block SYNCING status should not report latestValidHash")
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored remote-block public block number mismatch")
    (list :remote-block-hash (hash32-to-hex expected-block-hash)
          :remote-block-status (fixture-object-field payload-status "status")
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node remote-payload expected-block-hash
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet remote-block Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-invalid-tipset-rpc
    (node descendant-payload expected-latest-valid-hash
     expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (engine-fixture-payload-request 174 descendant-payload)))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 175)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-invalid-tipset"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-invalid-tipset"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload-status (fixture-object-field engine-rpc "result"))
         (validation-error
           (fixture-object-field payload-status "validationError")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored invalid-tipset probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored invalid-tipset probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored invalid-tipset engine_newPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored invalid-tipset eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored invalid-tipset engine_newPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= +payload-status-invalid+
              (fixture-object-field payload-status "status"))
     "Restored invalid-tipset engine_newPayloadV2 status mismatch")
    (devnet-smoke-gate-require
     (string= (hash32-to-hex expected-latest-valid-hash)
              (fixture-object-field payload-status "latestValidHash"))
     "Restored invalid-tipset latestValidHash mismatch")
    (devnet-smoke-gate-require
     (string= "links to previously rejected block" validation-error)
     "Restored invalid-tipset validation error mismatch: ~A"
     validation-error)
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored invalid-tipset public block number mismatch")
    (list :invalid-tipset-status
          (fixture-object-field payload-status "status")
          :invalid-tipset-validation-error validation-error
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node descendant-payload expected-latest-valid-hash
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet invalid-tipset Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-txpool-transaction-entry
    (txpool-transactions name)
  (or (cdr (assoc name txpool-transactions :test #'string=))
      (error "Missing txpool transaction entry ~A" name)))

(defun devnet-smoke-gate-transaction-hash-hex (transaction)
  (hash32-to-hex (transaction-hash transaction)))

(defun devnet-smoke-gate-transaction-raw (transaction)
  (bytes-to-hex (transaction-encoding transaction)))

(defun devnet-smoke-gate-txpool-journal-records (journal-path)
  (when (probe-file journal-path)
    (handler-case
        (let ((database (make-file-key-value-database journal-path)))
          (loop for entry in (kv-chain-record-entries database :txpool)
                collect
                (multiple-value-bind (subpool transaction)
                    (ethereum-lisp.core::chain-store-txpool-transaction-record-values
                     (cdr entry))
                  (list :hash (hash32-to-hex (transaction-hash transaction))
                        :subpool subpool
                        :raw (devnet-smoke-gate-transaction-raw
                              transaction)))))
      (error (condition)
        (error "Unable to read txpool rejournal file ~A: ~A"
               (namestring journal-path)
               condition)))))

(defun devnet-smoke-gate-wait-for-txpool-journal-record
    (journal-path expected-hash expected-raw timeout-seconds
     &key expected-record-count)
  (let* ((deadline
           (+ (get-internal-real-time)
              (* timeout-seconds internal-time-units-per-second)))
         (last-records nil))
    (loop
      (setf last-records
            (devnet-smoke-gate-txpool-journal-records journal-path))
      (let ((record
              (find-if
               (lambda (record)
                 (and (string= expected-hash (getf record :hash))
                      (string= expected-raw (getf record :raw))))
               last-records)))
        (when (and record
                   (or (null expected-record-count)
                       (>= (length last-records) expected-record-count)))
          (return
            (list :record-count (length last-records)
                  :transaction-hash (getf record :hash)
                  :subpool (getf record :subpool)))))
      (when (>= (get-internal-real-time) deadline)
        (error "Timed out after ~D seconds waiting for txpool journal ~A to contain ~A with at least ~A records; observed hashes: ~S"
               timeout-seconds
               (namestring journal-path)
               expected-hash
               (or expected-record-count 1)
               (mapcar (lambda (record) (getf record :hash))
                       last-records)))
      (sleep 0.05))))

(defun devnet-smoke-gate-wait-for-dev-period-transaction
    (node transaction-hash timeout-seconds)
  (let* ((deadline
           (+ (get-internal-real-time)
              (* timeout-seconds internal-time-units-per-second)))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (last-block-number nil))
    (loop
      (setf last-block-number
            (quantity-to-hex (chain-store-head-number store)))
      (let ((location
              (chain-store-transaction-location store transaction-hash)))
        (when location
          (return location)))
      (when (>= (get-internal-real-time) deadline)
        (error "Timed out after ~D seconds waiting for dev-period mining of ~A; latest block was ~A"
               timeout-seconds
               (hash32-to-hex transaction-hash)
               last-block-number))
      (sleep 0.05))))

(defun devnet-smoke-gate-verify-dev-period-mining
    (case-name &key terminal-total-difficulty
       terminal-total-difficulty-passed-p terminal-block-hash
       terminal-block-number)
  (declare (ignore case-name))
  #+sbcl
  (let* ((probe-case-name "shanghai-one-transfer-with-withdrawal")
         (fixture (devnet-smoke-gate-engine-fixture probe-case-name))
         (store (devnet-smoke-gate-field fixture "store"))
         (config
           (ethereum-lisp.cli::devnet-cli-apply-merge-overrides
            (devnet-smoke-gate-field fixture "config")
            :terminal-total-difficulty terminal-total-difficulty
            :terminal-total-difficulty-passed
            terminal-total-difficulty-passed-p
            :terminal-total-difficulty-passed-specified-p
            terminal-total-difficulty-passed-p
            :terminal-block-hash terminal-block-hash
            :terminal-block-number terminal-block-number))
         (parent-state
           (devnet-smoke-gate-field fixture "parentState"))
         (parent-block
           (devnet-smoke-gate-field fixture "parentBlock"))
         (txpool-transactions
           (devnet-smoke-gate-field fixture "txpoolTransactions"))
         (pending-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "pending"))
         (transaction-hash (transaction-hash pending-transaction))
         (transaction-hash-hex (hash32-to-hex transaction-hash))
         (raw-transaction
           (devnet-smoke-gate-transaction-raw pending-transaction))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 8551
            :public-port 8545
            :dev-mode-p t
            :dev-period-seconds 1
            :terminal-total-difficulty terminal-total-difficulty
            :terminal-total-difficulty-passed
            terminal-total-difficulty-passed-p
            :terminal-total-difficulty-passed-specified-p
            terminal-total-difficulty-passed-p
            :terminal-block-hash terminal-block-hash
            :terminal-block-number terminal-block-number))
         (send-output (make-string-output-stream))
         (wait-output (make-string-output-stream))
         (transaction-output (make-string-output-stream))
         (receipt-output (make-string-output-stream))
         (status-output (make-string-output-stream))
         (pending-output (make-string-output-stream))
         (block-output (make-string-output-stream))
         (public-requests
           (list
            (cons
             (devnet-smoke-gate-json-rpc-request
              301 "eth_sendRawTransaction" (list raw-transaction))
             send-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              302 "eth_blockNumber" '())
             wait-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              303 "eth_getTransactionByHash" (list transaction-hash-hex))
             transaction-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              304 "eth_getTransactionReceipt" (list transaction-hash-hex))
             receipt-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              305 "txpool_status" '())
             status-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              306 "eth_pendingTransactions" '())
             pending-output)
            (cons
             (devnet-smoke-gate-json-rpc-request
              307 "eth_getBlockByNumber" (list "latest" :false))
             block-output)))
         (mined-location nil))
    (devnet-cli-set-node-store-config node store config)
    (engine-payload-store-put-block store parent-block :state-available-p t)
    (commit-state-db-to-chain-store
     store (block-hash parent-block) parent-state)
    (let ((summary
            (ethereum-lisp.cli:start-devnet-node-listeners
             node
             (make-engine-rpc-http-listener
              :endpoint "dev-period-engine"
              :accept-function (lambda () nil)
              :close-function (lambda () nil))
             (make-engine-rpc-http-listener
              :endpoint "dev-period-public"
              :accept-function
              (lambda ()
                (when public-requests
                  (destructuring-bind (body . output)
                      (pop public-requests)
                    (when (eq output wait-output)
                      (setf mined-location
                            (devnet-smoke-gate-wait-for-dev-period-transaction
                             node transaction-hash 8)))
                    (make-engine-rpc-http-connection
                     :input-stream
                     (make-string-input-stream
                      (devnet-cli-json-rpc-http-request body))
                     :output-stream output
                     :close-function (lambda () nil)))))
              :close-function (lambda () nil))
             :max-connections 7)))
      (let* ((send-response (get-output-stream-string send-output))
             (wait-response (get-output-stream-string wait-output))
             (transaction-response
               (get-output-stream-string transaction-output))
             (receipt-response
               (get-output-stream-string receipt-output))
             (status-response (get-output-stream-string status-output))
             (pending-response (get-output-stream-string pending-output))
             (block-response (get-output-stream-string block-output))
             (send-rpc (devnet-smoke-gate-rpc-body send-response))
             (wait-rpc (devnet-smoke-gate-rpc-body wait-response))
             (transaction-rpc
               (devnet-smoke-gate-rpc-body transaction-response))
             (receipt-rpc
               (devnet-smoke-gate-rpc-body receipt-response))
             (status-rpc (devnet-smoke-gate-rpc-body status-response))
             (pending-rpc
               (devnet-smoke-gate-rpc-body pending-response
                                           :preserve-empty-arrays t))
             (block-rpc (devnet-smoke-gate-rpc-body block-response))
             (mined-transaction
               (fixture-object-field transaction-rpc "result"))
             (receipt (fixture-object-field receipt-rpc "result"))
             (status (fixture-object-field status-rpc "result"))
             (pending-transactions
               (fixture-object-field pending-rpc "result"))
             (latest-block
               (fixture-object-field block-rpc "result"))
             (mined-block
               (and mined-location
                    (engine-transaction-location-block mined-location)))
             (mined-block-number
               (quantity-to-hex
                (block-header-number (block-header mined-block))))
             (mined-block-hash
               (hash32-to-hex (block-hash mined-block))))
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Dev-period smoke expected 0 Engine connections, got ~S"
         (getf summary :engine-connections))
        (devnet-smoke-gate-require
         (= 7 (getf summary :public-connections))
         "Dev-period smoke expected 7 public connections, got ~S"
         (getf summary :public-connections))
        (dolist (response (list send-response wait-response
                                transaction-response receipt-response
                                status-response pending-response
                                block-response))
          (devnet-smoke-gate-require
           (= 200 (devnet-cli-http-status response))
           "Dev-period smoke RPC HTTP status mismatch"))
        (devnet-smoke-gate-require
         (string= transaction-hash-hex
                  (fixture-object-field send-rpc "result"))
         "Dev-period eth_sendRawTransaction hash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-number
                  (fixture-object-field wait-rpc "result"))
         "Dev-period mined eth_blockNumber mismatch")
        (devnet-smoke-gate-require
         (string= transaction-hash-hex
                  (fixture-object-field mined-transaction "hash"))
         "Dev-period mined transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-hash
                  (fixture-object-field mined-transaction "blockHash"))
         "Dev-period mined transaction blockHash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-number
                  (fixture-object-field mined-transaction "blockNumber"))
         "Dev-period mined transaction blockNumber mismatch")
        (devnet-smoke-gate-require
         (string= "0x0"
                  (fixture-object-field mined-transaction "transactionIndex"))
         "Dev-period mined transaction index mismatch")
        (devnet-smoke-gate-require
         (string= transaction-hash-hex
                  (fixture-object-field receipt "transactionHash"))
         "Dev-period receipt transaction hash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-hash
                  (fixture-object-field receipt "blockHash"))
         "Dev-period receipt blockHash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-number
                  (fixture-object-field receipt "blockNumber"))
         "Dev-period receipt blockNumber mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" (fixture-object-field receipt "transactionIndex"))
         "Dev-period receipt transaction index mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" (fixture-object-field status "pending"))
         "Dev-period txpool_status pending count mismatch")
        (devnet-smoke-gate-require
         (string= "0x0" (fixture-object-field status "queued"))
         "Dev-period txpool_status queued count mismatch")
        (devnet-smoke-gate-require
         (devnet-smoke-gate-empty-json-array-p pending-transactions)
         "Dev-period eth_pendingTransactions should be empty after mining")
        (devnet-smoke-gate-require
         (string= mined-block-hash
                  (fixture-object-field latest-block "hash"))
         "Dev-period latest block hash mismatch")
        (devnet-smoke-gate-require
         (string= mined-block-number
                  (fixture-object-field latest-block "number"))
         "Dev-period latest block number mismatch")
        (list :dev-period-seconds 1
              :transaction-hash transaction-hash-hex
              :block-number mined-block-number
              :block-hash mined-block-hash
              :receipt-block-number
              (fixture-object-field receipt "blockNumber")
              :receipt-block-hash
              (fixture-object-field receipt "blockHash")
              :transaction-index
              (fixture-object-field mined-transaction "transactionIndex")
              :txpool-status-pending
              (fixture-object-field status "pending")
              :txpool-status-queued
              (fixture-object-field status "queued")
              :pending-transaction-count (length pending-transactions)
              :public-connections (getf summary :public-connections)
              :engine-connections (getf summary :engine-connections)
              :total-connections (getf summary :total-connections)))))
  #-sbcl
  (declare (ignore terminal-total-difficulty
                   terminal-total-difficulty-passed-p terminal-block-hash
                   terminal-block-number))
  #-sbcl
  (error "Dev-period smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-transaction-nonce-key (transaction)
  (format nil "~D" (transaction-nonce transaction)))

(defun devnet-smoke-gate-transaction-summary (transaction)
  (let ((to (transaction-to transaction)))
    (format nil "~A: ~D wei + ~D gas x ~D wei"
            (if to
                (address-to-hex to)
                "contract creation")
            (transaction-value transaction)
            (transaction-gas-limit transaction)
            (transaction-max-fee-per-gas transaction))))

(defun devnet-smoke-gate-verify-restored-txpool-rpc
    (node txpool-transactions
     &key selected-pending-imported-p selected-pending-transaction)
  #+sbcl
  (let* ((pending-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "pending"))
         (selected-transaction
           (or selected-pending-transaction pending-transaction))
         (basefee-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "basefee"))
         (queued-transaction
           (devnet-smoke-gate-txpool-transaction-entry
            txpool-transactions "queued"))
         (transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex pending-transaction))
         (selected-transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex selected-transaction))
         (basefee-transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex basefee-transaction))
         (queued-transaction-hash-hex
           (devnet-smoke-gate-transaction-hash-hex queued-transaction))
         (raw-transaction
           (devnet-smoke-gate-transaction-raw pending-transaction))
         (selected-raw-transaction
           (devnet-smoke-gate-transaction-raw selected-transaction))
         (basefee-raw-transaction
           (devnet-smoke-gate-transaction-raw basefee-transaction))
         (queued-raw-transaction
           (devnet-smoke-gate-transaction-raw queued-transaction))
         (transaction-summary
           (devnet-smoke-gate-transaction-summary pending-transaction))
         (basefee-transaction-summary
           (devnet-smoke-gate-transaction-summary basefee-transaction))
         (queued-transaction-summary
           (devnet-smoke-gate-transaction-summary queued-transaction))
         (sender (transaction-sender pending-transaction))
         (sender-hex (address-to-hex sender))
         (nonce-key
           (devnet-smoke-gate-transaction-nonce-key pending-transaction))
         (expected-pending-sender-nonce
           (quantity-to-hex (1+ (transaction-nonce pending-transaction))))
         (basefee-nonce-key
           (devnet-smoke-gate-transaction-nonce-key basefee-transaction))
         (queued-nonce-key
           (devnet-smoke-gate-transaction-nonce-key queued-transaction))
         (expected-pending-count
           (if selected-pending-imported-p 0 1))
         (expected-pending-count-hex
           (quantity-to-hex expected-pending-count))
         (raw-output (make-string-output-stream))
         (basefee-raw-output (make-string-output-stream))
         (queued-raw-output (make-string-output-stream))
         (pending-block-count-output (make-string-output-stream))
         (pending-block-output (make-string-output-stream))
         (pending-header-output (make-string-output-stream))
         (pending-fee-history-output (make-string-output-stream))
         (pending-nonce-output (make-string-output-stream))
         (pending-index-output (make-string-output-stream))
         (pending-raw-index-output (make-string-output-stream))
         (pending-output (make-string-output-stream))
         (status-output (make-string-output-stream))
         (content-output (make-string-output-stream))
         (content-from-output (make-string-output-stream))
         (inspect-output (make-string-output-stream))
         (public-requests
           (list
            (cons
            (json-encode
             (list (cons "jsonrpc" "2.0")
                    (cons "id" 176)
                    (cons "method" "eth_getRawTransactionByHash")
                    (cons "params" (list selected-transaction-hash-hex))))
             raw-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 181)
                    (cons "method" "eth_getRawTransactionByHash")
                    (cons "params" (list basefee-transaction-hash-hex))))
             basefee-raw-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 182)
                    (cons "method" "eth_getRawTransactionByHash")
                    (cons "params" (list queued-transaction-hash-hex))))
             queued-raw-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 184)
                    (cons "method" "eth_getBlockTransactionCountByNumber")
                    (cons "params" (list "pending"))))
             pending-block-count-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 187)
                    (cons "method" "eth_getBlockByNumber")
                    (cons "params" (list "pending" t))))
             pending-block-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 188)
                    (cons "method" "eth_getHeaderByNumber")
                    (cons "params" (list "pending"))))
             pending-header-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 189)
                    (cons "method" "eth_feeHistory")
                    (cons "params" (list "0x1" "latest" '()))))
             pending-fee-history-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 190)
                    (cons "method" "eth_getTransactionCount")
                    (cons "params" (list sender-hex "pending"))))
             pending-nonce-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 185)
                    (cons "method"
                          "eth_getTransactionByBlockNumberAndIndex")
                    (cons "params" (list "pending" "0x0"))))
             pending-index-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 186)
                    (cons "method"
                          "eth_getRawTransactionByBlockNumberAndIndex")
                    (cons "params" (list "pending" "0x0"))))
             pending-raw-index-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 177)
                    (cons "method" "eth_pendingTransactions")
                    (cons "params" '())))
             pending-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 178)
                    (cons "method" "txpool_status")
                    (cons "params" '())))
             status-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 179)
                    (cons "method" "txpool_content")
                    (cons "params" '())))
             content-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 180)
                    (cons "method" "txpool_contentFrom")
                    (cons "params" (list sender-hex))))
             content-from-output)
            (cons
             (json-encode
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 183)
                    (cons "method" "txpool_inspect")
                    (cons "params" '())))
             inspect-output)))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-txpool"
             :accept-function (lambda () nil)
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-txpool"
             :accept-function
             (lambda ()
               (when public-requests
                 (destructuring-bind (body . output)
                     (pop public-requests)
                   (make-engine-rpc-http-connection
                    :input-stream
                    (make-string-input-stream
                     (devnet-cli-json-rpc-http-request body))
                    :output-stream output
                    :close-function (lambda () nil)))))
            :close-function (lambda () nil))
            :max-connections 15))
         (raw-response (get-output-stream-string raw-output))
         (basefee-raw-response
           (get-output-stream-string basefee-raw-output))
         (queued-raw-response
           (get-output-stream-string queued-raw-output))
         (pending-block-count-response
           (get-output-stream-string pending-block-count-output))
         (pending-block-response
           (get-output-stream-string pending-block-output))
         (pending-header-response
           (get-output-stream-string pending-header-output))
         (pending-fee-history-response
           (get-output-stream-string pending-fee-history-output))
         (pending-nonce-response
           (get-output-stream-string pending-nonce-output))
         (pending-index-response
           (get-output-stream-string pending-index-output))
         (pending-raw-index-response
           (get-output-stream-string pending-raw-index-output))
         (pending-response (get-output-stream-string pending-output))
         (status-response (get-output-stream-string status-output))
         (content-response (get-output-stream-string content-output))
         (content-from-response
           (get-output-stream-string content-from-output))
         (inspect-response (get-output-stream-string inspect-output))
         (raw-rpc (devnet-smoke-gate-rpc-body raw-response))
         (basefee-raw-rpc
           (devnet-smoke-gate-rpc-body basefee-raw-response))
         (queued-raw-rpc
           (devnet-smoke-gate-rpc-body queued-raw-response))
         (pending-block-count-rpc
           (devnet-smoke-gate-rpc-body pending-block-count-response))
         (pending-block-rpc
           (devnet-smoke-gate-rpc-body pending-block-response))
         (pending-header-rpc
           (devnet-smoke-gate-rpc-body pending-header-response))
         (pending-fee-history-rpc
           (devnet-smoke-gate-rpc-body pending-fee-history-response))
         (pending-nonce-rpc
           (devnet-smoke-gate-rpc-body pending-nonce-response))
         (pending-index-rpc
           (devnet-smoke-gate-rpc-body pending-index-response))
         (pending-raw-index-rpc
           (devnet-smoke-gate-rpc-body pending-raw-index-response))
         (pending-rpc (devnet-smoke-gate-rpc-body pending-response))
         (status-rpc (devnet-smoke-gate-rpc-body status-response))
         (content-rpc (devnet-smoke-gate-rpc-body content-response))
         (content-from-rpc
           (devnet-smoke-gate-rpc-body content-from-response))
         (inspect-rpc (devnet-smoke-gate-rpc-body inspect-response))
         (pending-transactions
           (fixture-object-field pending-rpc "result"))
         (pending-object (first pending-transactions))
         (pending-block
           (fixture-object-field pending-block-rpc "result"))
         (pending-header
           (fixture-object-field pending-header-rpc "result"))
         (pending-fee-history
           (fixture-object-field pending-fee-history-rpc "result"))
         (pending-fee-history-base-fees
           (fixture-object-field pending-fee-history "baseFeePerGas"))
         (pending-fee-history-next-base-fee
           (second pending-fee-history-base-fees))
         (pending-block-transactions
           (fixture-object-field pending-block "transactions"))
         (pending-block-transaction
           (first pending-block-transactions))
         (pending-index-transaction
           (fixture-object-field pending-index-rpc "result"))
         (status (fixture-object-field status-rpc "result"))
         (content (fixture-object-field content-rpc "result"))
         (content-pending (fixture-object-field content "pending"))
         (content-sender
           (fixture-object-field content-pending sender-hex))
         (content-transaction
           (fixture-object-field content-sender nonce-key))
         (content-queued (fixture-object-field content "queued"))
         (content-queued-sender
           (fixture-object-field content-queued sender-hex))
         (content-basefee-transaction
           (fixture-object-field content-queued-sender basefee-nonce-key))
         (content-queued-transaction
           (fixture-object-field content-queued-sender queued-nonce-key))
         (content-from
           (fixture-object-field content-from-rpc "result"))
         (content-from-pending
           (fixture-object-field content-from "pending"))
         (content-from-queued
           (fixture-object-field content-from "queued"))
         (content-from-transaction
           (fixture-object-field content-from-pending nonce-key))
         (content-from-basefee-transaction
           (fixture-object-field content-from-queued basefee-nonce-key))
         (content-from-queued-transaction
           (fixture-object-field content-from-queued queued-nonce-key))
         (inspect (fixture-object-field inspect-rpc "result"))
         (inspect-pending (fixture-object-field inspect "pending"))
         (inspect-sender
           (fixture-object-field inspect-pending sender-hex))
         (inspect-transaction
           (fixture-object-field inspect-sender nonce-key))
         (inspect-queued (fixture-object-field inspect "queued"))
         (inspect-queued-sender
           (fixture-object-field inspect-queued sender-hex))
         (inspect-basefee-transaction
           (fixture-object-field inspect-queued-sender basefee-nonce-key))
         (inspect-queued-transaction
           (fixture-object-field inspect-queued-sender queued-nonce-key)))
    (devnet-smoke-gate-require
     (= 15 (getf summary :public-connections))
     "Restored txpool probe expected 15 public connections, got ~S"
     (getf summary :public-connections))
    (dolist (response (list raw-response basefee-raw-response
                            queued-raw-response pending-block-count-response
                            pending-block-response pending-header-response
                            pending-fee-history-response
                            pending-nonce-response
                            pending-index-response pending-raw-index-response
                            pending-response
                            status-response content-response
                            content-from-response inspect-response))
      (devnet-smoke-gate-require
       (= 200 (devnet-cli-http-status response))
       "Restored txpool RPC HTTP status mismatch"))
    (devnet-smoke-gate-require
     (string= selected-raw-transaction
              (fixture-object-field raw-rpc "result"))
     "Restored txpool raw transaction mismatch")
    (devnet-smoke-gate-require
     (string= basefee-raw-transaction
              (fixture-object-field basefee-raw-rpc "result"))
     "Restored basefee txpool raw transaction mismatch")
    (devnet-smoke-gate-require
     (string= queued-raw-transaction
              (fixture-object-field queued-raw-rpc "result"))
     "Restored queued txpool raw transaction mismatch")
    (devnet-smoke-gate-require
     (string= expected-pending-count-hex
              (fixture-object-field pending-block-count-rpc "result"))
     "Restored pending block-tag transaction count mismatch")
    (devnet-smoke-gate-require
     (null (fixture-object-field pending-block "hash"))
     "Restored pending block-tag block should not expose a block hash")
    (devnet-smoke-gate-require
     (string= (fixture-object-field pending-block "number")
              (fixture-object-field pending-header "number"))
     "Restored pending header number should match pending block number")
    (devnet-smoke-gate-require
     (string= (fixture-object-field pending-block "parentHash")
              (fixture-object-field pending-header "parentHash"))
     "Restored pending header parent hash should match pending block parent hash")
    (devnet-smoke-gate-require
     (null (fixture-object-field pending-header "hash"))
     "Restored pending header should not expose a block hash")
    (devnet-smoke-gate-require
     (null (fixture-object-field pending-header "nonce"))
     "Restored pending header should not expose a nonce")
    (devnet-smoke-gate-require
     (= 2 (length pending-fee-history-base-fees))
     "Restored pending fee history baseFeePerGas length mismatch")
    (devnet-smoke-gate-require
     (string= pending-fee-history-next-base-fee
              (fixture-object-field pending-block "baseFeePerGas"))
     "Restored pending block base fee should match fee history next base fee")
    (devnet-smoke-gate-require
     (string= pending-fee-history-next-base-fee
              (fixture-object-field pending-header "baseFeePerGas"))
     "Restored pending header base fee should match fee history next base fee")
    (devnet-smoke-gate-require
     (string= expected-pending-sender-nonce
              (fixture-object-field pending-nonce-rpc "result"))
     "Restored pending transaction count nonce mismatch")
    (devnet-smoke-gate-require
     (= expected-pending-count (length pending-block-transactions))
     "Restored pending block-tag block transaction count mismatch")
    (if selected-pending-imported-p
        (progn
          (devnet-smoke-gate-require
           (null pending-index-transaction)
           "Restored pending block-tag transaction index should be empty")
          (devnet-smoke-gate-require
           (null (fixture-object-field pending-raw-index-rpc "result"))
           "Restored pending block-tag raw transaction should be empty"))
        (progn
          (devnet-smoke-gate-require
           (string= transaction-hash-hex
                    (fixture-object-field pending-block-transaction "hash"))
           "Restored pending block-tag block transaction hash mismatch")
          (devnet-smoke-gate-require
           (null (fixture-object-field pending-block-transaction "blockHash"))
           "Restored pending block-tag block transaction should not have a block hash")
          (devnet-smoke-gate-require
           (string= transaction-hash-hex
                    (fixture-object-field pending-index-transaction "hash"))
           "Restored pending block-tag transaction index hash mismatch")
          (devnet-smoke-gate-require
           (null (fixture-object-field pending-index-transaction "blockHash"))
           "Restored pending block-tag transaction should not have a block hash")
          (devnet-smoke-gate-require
           (string= raw-transaction
                    (fixture-object-field pending-raw-index-rpc "result"))
           "Restored pending block-tag raw transaction mismatch")))
    (devnet-smoke-gate-require
     (= expected-pending-count (length pending-transactions))
     "Restored txpool pending transaction count mismatch")
    (unless selected-pending-imported-p
      (devnet-smoke-gate-require
       (string= transaction-hash-hex
                (fixture-object-field pending-object "hash"))
       "Restored eth_pendingTransactions hash mismatch")
      (devnet-smoke-gate-require
       (null (fixture-object-field pending-object "blockHash"))
       "Restored pending transaction should not have a block hash"))
    (devnet-smoke-gate-require
     (string= expected-pending-count-hex
              (fixture-object-field status "pending"))
     "Restored txpool_status pending count mismatch")
    (devnet-smoke-gate-require
     (string= "0x2" (fixture-object-field status "queued"))
     "Restored txpool_status queued count mismatch")
    (if selected-pending-imported-p
        (progn
          (devnet-smoke-gate-require
           (null content-transaction)
           "Restored txpool_content should not expose mined pending transaction")
          (devnet-smoke-gate-require
           (null content-from-transaction)
           "Restored txpool_contentFrom should not expose mined pending transaction"))
        (progn
          (devnet-smoke-gate-require
           (string= transaction-hash-hex
                    (fixture-object-field content-transaction "hash"))
           "Restored txpool_content hash mismatch")
          (devnet-smoke-gate-require
           (string= transaction-hash-hex
                    (fixture-object-field content-from-transaction "hash"))
           "Restored txpool_contentFrom hash mismatch")))
    (devnet-smoke-gate-require
     (string= basefee-transaction-hash-hex
              (fixture-object-field content-basefee-transaction "hash"))
     "Restored txpool_content basefee hash mismatch")
    (devnet-smoke-gate-require
     (string= queued-transaction-hash-hex
              (fixture-object-field content-queued-transaction "hash"))
     "Restored txpool_content queued hash mismatch")
    (devnet-smoke-gate-require
     (string= basefee-transaction-hash-hex
              (fixture-object-field content-from-basefee-transaction "hash"))
     "Restored txpool_contentFrom basefee hash mismatch")
    (devnet-smoke-gate-require
     (string= queued-transaction-hash-hex
              (fixture-object-field content-from-queued-transaction "hash"))
     "Restored txpool_contentFrom queued hash mismatch")
    (if selected-pending-imported-p
        (devnet-smoke-gate-require
         (null inspect-transaction)
         "Restored txpool_inspect should not expose mined pending transaction")
        (devnet-smoke-gate-require
         (string= transaction-summary inspect-transaction)
         "Restored txpool_inspect pending summary mismatch"))
    (devnet-smoke-gate-require
     (string= basefee-transaction-summary inspect-basefee-transaction)
     "Restored txpool_inspect basefee summary mismatch")
    (devnet-smoke-gate-require
     (string= queued-transaction-summary inspect-queued-transaction)
     "Restored txpool_inspect queued summary mismatch")
    (list :txpool-transaction-hash selected-transaction-hash-hex
          :txpool-raw-transaction selected-raw-transaction
          :txpool-sender sender-hex
          :txpool-nonce nonce-key
          :txpool-inspect-summary inspect-transaction
          :txpool-basefee-transaction-hash basefee-transaction-hash-hex
          :txpool-basefee-raw-transaction basefee-raw-transaction
          :txpool-basefee-nonce basefee-nonce-key
          :txpool-basefee-inspect-summary inspect-basefee-transaction
          :txpool-queued-transaction-hash queued-transaction-hash-hex
          :txpool-queued-raw-transaction queued-raw-transaction
          :txpool-queued-nonce queued-nonce-key
          :txpool-queued-inspect-summary inspect-queued-transaction
          :txpool-status-pending
          (fixture-object-field status "pending")
          :txpool-status-queued
          (fixture-object-field status "queued")
          :txpool-pending-block-count
          (fixture-object-field pending-block-count-rpc "result")
          :txpool-pending-block-hash
          (fixture-object-field pending-block "hash")
          :txpool-pending-block-base-fee
          (fixture-object-field pending-block "baseFeePerGas")
          :txpool-pending-header-number
          (fixture-object-field pending-header "number")
          :txpool-pending-header-parent-hash
          (fixture-object-field pending-header "parentHash")
          :txpool-pending-header-hash
          (fixture-object-field pending-header "hash")
          :txpool-pending-header-nonce
          (fixture-object-field pending-header "nonce")
          :txpool-pending-header-base-fee
          (fixture-object-field pending-header "baseFeePerGas")
          :txpool-pending-fee-history-next-base-fee
          pending-fee-history-next-base-fee
          :txpool-pending-sender-nonce
          (fixture-object-field pending-nonce-rpc "result")
          :txpool-pending-block-transaction-hash
          (fixture-object-field pending-block-transaction "hash")
          :txpool-pending-block-transaction-block-hash
          (fixture-object-field pending-block-transaction "blockHash")
          :txpool-pending-index-transaction-hash
          (fixture-object-field pending-index-transaction "hash")
          :txpool-pending-index-block-hash
          (fixture-object-field pending-index-transaction "blockHash")
          :txpool-pending-raw-index-transaction
          (fixture-object-field pending-raw-index-rpc "result")
          :txpool-content-hash
          (fixture-object-field content-transaction "hash")
          :txpool-content-from-hash
          (fixture-object-field content-from-transaction "hash")
          :txpool-basefee-content-hash
          (fixture-object-field content-basefee-transaction "hash")
          :txpool-basefee-content-from-hash
          (fixture-object-field content-from-basefee-transaction "hash")
          :txpool-queued-content-hash
          (fixture-object-field content-queued-transaction "hash")
          :txpool-queued-content-from-hash
          (fixture-object-field content-from-queued-transaction "hash")
          :public-connections (getf summary :public-connections)))
  #-sbcl
  (declare (ignore node txpool-transactions))
  #-sbcl
  (error "Restored devnet txpool RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-side-reorg-rpc
    (path side-payload side-block child-block balance-targets
     checkpoint-balance-targets transaction-checks expected-safe-block-hash
     sender-address code-address storage-address storage-key config)
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-side-reorg-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (devnet-smoke-gate-make-restored-node
                     path
                     config
                     :port 0
                     :public-port 0
                     :jwt-secret-path (namestring jwt-path)))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (primary-balance-target (first balance-targets))
                  (balance-address
                    (getf primary-balance-target :address))
                  (primary-checkpoint-balance-target
                    (first checkpoint-balance-targets))
                  (expected-checkpoint-balance
                    (getf primary-checkpoint-balance-target :balance))
                  (transaction-hash
                    (getf (first transaction-checks) :hash))
                  (expected-raw-transaction
                    (getf (first transaction-checks) :raw))
                  (transaction-hash-hex
                    (hash32-to-hex transaction-hash))
                  (displaced-transaction
                    (first (block-transactions child-block)))
                  (transaction-items
                    (loop for check in transaction-checks
                          for transaction in (block-transactions child-block)
                          collect
                          (list
                           :hash (getf check :hash)
                           :hash-hex (hash32-to-hex (getf check :hash))
                           :raw (getf check :raw)
                           :reinsertable-p
                           (not (null
                                 (transaction-sender
                                  transaction
                                  :expected-chain-id
                                  (chain-config-chain-id
                                   (ethereum-lisp.cli:devnet-node-config
                                    node))))))))
                  (reinsertable-transaction-items
                    (remove-if-not
                     (lambda (item) (getf item :reinsertable-p))
                     transaction-items))
                  (reinsertable-transaction-hashes
                    (mapcar
                     (lambda (item) (getf item :hash-hex))
                     reinsertable-transaction-items))
                  (extra-transaction-items
                    (rest transaction-items))
                  (side-public-connection-count
                    (+ 9 (length extra-transaction-items)))
                  (fresh-public-connection-count
                    (+ 20 (length extra-transaction-items)))
                  (side-block-hash (block-hash side-block))
                  (child-block-hash (block-hash child-block))
                  (node-chain-id
                    (chain-config-chain-id
                     (ethereum-lisp.cli:devnet-node-config node)))
                  (reinsertable-transaction-p
                    (not (null
                          (transaction-sender
                           displaced-transaction
                           :expected-chain-id node-chain-id))))
                  (expected-safe-block-number
                    (quantity-to-hex
                     (1- (block-header-number
                          (block-header child-block)))))
                  (expected-side-block-number
                    (quantity-to-hex
                     (block-header-number (block-header side-block))))
                  (side-payload-output (make-string-output-stream))
                  (side-rejected-forkchoice-output
                    (make-string-output-stream))
                  (side-forkchoice-output (make-string-output-stream))
                  (side-block-number-output (make-string-output-stream))
                  (side-latest-block-output (make-string-output-stream))
                  (side-transaction-output (make-string-output-stream))
                  (side-raw-transaction-output
                    (make-string-output-stream))
                  (side-pending-transactions-output
                    (make-string-output-stream))
                  (side-receipt-output (make-string-output-stream))
                  (side-extra-receipt-outputs
                    (loop repeat (length extra-transaction-items)
                          collect (make-string-output-stream)))
                  (child-block-output (make-string-output-stream))
                  (side-block-receipts-output (make-string-output-stream))
                  (side-logs-output (make-string-output-stream))
                  (engine-requests
                    (list
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 201 side-payload))
                      side-payload-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        202 side-block-hash
                        :safe child-block-hash
                        :finalized expected-safe-block-hash))
                      side-rejected-forkchoice-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        210 side-block-hash
                        :safe expected-safe-block-hash
                        :finalized expected-safe-block-hash))
                      side-forkchoice-output)))
                  (public-requests
                    (append
                     (list
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 203)
                              (cons "method" "eth_blockNumber")
                              (cons "params" '())))
                       side-block-number-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 204)
                              (cons "method" "eth_getBlockByNumber")
                              (cons "params" (list "latest" :false))))
                       side-latest-block-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 205)
                              (cons "method" "eth_getTransactionByHash")
                              (cons "params"
                                    (list (hash32-to-hex
                                           transaction-hash)))))
                       side-transaction-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 206)
                              (cons "method" "eth_getRawTransactionByHash")
                              (cons "params"
                                    (list transaction-hash-hex))))
                       side-raw-transaction-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 207)
                              (cons "method" "eth_pendingTransactions")
                              (cons "params" '())))
                       side-pending-transactions-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 208)
                              (cons "method" "eth_getTransactionReceipt")
                              (cons "params"
                                    (list transaction-hash-hex))))
                       side-receipt-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 209)
                              (cons "method" "eth_getBlockByHash")
                              (cons "params"
                                    (list (hash32-to-hex child-block-hash)
                                          :false))))
                       child-block-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 211)
                              (cons "method" "eth_getBlockReceipts")
                              (cons "params" (list "latest"))))
                       side-block-receipts-output)
                      (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 212)
                              (cons "method" "eth_getLogs")
                              (cons "params"
                                    (list
                                     (list
                                      (cons "fromBlock"
                                            expected-side-block-number)
                                      (cons "toBlock"
                                            expected-side-block-number))))))
                       side-logs-output))
                     (loop for item in extra-transaction-items
                           for output in side-extra-receipt-outputs
                           for id from 230
                           collect
                           (cons
                            (json-encode
                             (list (cons "jsonrpc" "2.0")
                                   (cons "id" id)
                                   (cons "method" "eth_getTransactionReceipt")
                                   (cons "params"
                                         (list (getf item :hash-hex)))))
                            output))))
                  (engine-done-p nil)
                  (engine-served-count 0)
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "engine-side-reorg"
                      :accept-function
                      (lambda ()
                        (when engine-requests
                          (destructuring-bind (body . output)
                              (pop engine-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               body :token token))
                             :output-stream output
                             :close-function
                             (lambda ()
                               (incf engine-served-count)
                               (when (= engine-served-count 3)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "public-side-reorg"
                      :accept-function
                      (lambda ()
                        (loop until engine-done-p
                              do (sleep 0.001))
                        (when public-requests
                          (destructuring-bind (body . output)
                              (pop public-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request body))
                             :output-stream output
                             :close-function (lambda () nil)))))
                     :close-function (lambda () nil))
                     :max-connections side-public-connection-count))
                  (side-payload-response
                    (get-output-stream-string side-payload-output))
                  (side-rejected-forkchoice-response
                    (get-output-stream-string
                     side-rejected-forkchoice-output))
                  (side-forkchoice-response
                    (get-output-stream-string side-forkchoice-output))
                  (side-block-number-response
                    (get-output-stream-string side-block-number-output))
                  (side-latest-block-response
                    (get-output-stream-string side-latest-block-output))
                  (side-transaction-response
                    (get-output-stream-string side-transaction-output))
                  (side-raw-transaction-response
                    (get-output-stream-string side-raw-transaction-output))
                  (side-pending-transactions-response
                    (get-output-stream-string
                     side-pending-transactions-output))
                  (side-receipt-response
                    (get-output-stream-string side-receipt-output))
                  (side-extra-receipt-responses
                    (mapcar #'get-output-stream-string
                            side-extra-receipt-outputs))
                  (child-block-response
                    (get-output-stream-string child-block-output))
                  (side-block-receipts-response
                    (get-output-stream-string side-block-receipts-output))
                  (side-logs-response
                    (get-output-stream-string side-logs-output))
                  (side-payload-rpc
                    (devnet-smoke-gate-rpc-body side-payload-response))
                  (side-rejected-forkchoice-rpc
                    (devnet-smoke-gate-rpc-body
                     side-rejected-forkchoice-response))
                  (side-forkchoice-rpc
                    (devnet-smoke-gate-rpc-body side-forkchoice-response))
                  (side-block-number-rpc
                    (devnet-smoke-gate-rpc-body side-block-number-response))
                  (side-latest-block-rpc
                    (devnet-smoke-gate-rpc-body side-latest-block-response))
                  (side-transaction-rpc
                    (devnet-smoke-gate-rpc-body side-transaction-response))
                  (side-raw-transaction-rpc
                    (devnet-smoke-gate-rpc-body
                     side-raw-transaction-response))
                  (side-pending-transactions-rpc
                    (devnet-smoke-gate-rpc-body
                     side-pending-transactions-response))
                  (side-receipt-rpc
                    (devnet-smoke-gate-rpc-body side-receipt-response))
                  (side-extra-receipt-rpcs
                    (mapcar #'devnet-smoke-gate-rpc-body
                            side-extra-receipt-responses))
                  (child-block-rpc
                    (devnet-smoke-gate-rpc-body child-block-response))
                  (side-block-receipts-rpc
                    (devnet-smoke-gate-rpc-body
                     side-block-receipts-response))
                  (side-logs-rpc
                    (devnet-smoke-gate-rpc-body side-logs-response))
                  (side-payload-result
                    (fixture-object-field side-payload-rpc "result"))
                  (side-rejected-forkchoice-error
                    (fixture-object-field side-rejected-forkchoice-rpc
                                          "error"))
                  (side-forkchoice-status
                    (fixture-object-field
                     (fixture-object-field side-forkchoice-rpc "result")
                     "payloadStatus"))
                  (side-latest-block
                    (fixture-object-field side-latest-block-rpc "result"))
                  (side-transaction
                    (fixture-object-field side-transaction-rpc "result"))
                  (side-raw-transaction
                    (fixture-object-field side-raw-transaction-rpc "result"))
                  (side-pending-transactions
                    (fixture-object-field side-pending-transactions-rpc
                                          "result"))
                  (side-pending-transaction
                    (find transaction-hash-hex side-pending-transactions
                          :test #'string=
                          :key (lambda (transaction)
                                 (fixture-object-field transaction
                                                       "hash"))))
                  (side-reinserted-transactions
                    (loop for item in reinsertable-transaction-items
                          collect
                          (find (getf item :hash-hex)
                                side-pending-transactions
                                :test #'string=
                                :key (lambda (transaction)
                                       (fixture-object-field transaction
                                                             "hash")))))
                  (child-block-by-hash
                    (fixture-object-field child-block-rpc "result"))
                  (side-block-receipts
                    (fixture-object-field side-block-receipts-rpc "result"))
                  (side-logs
                    (fixture-object-field side-logs-rpc "result"))
                  (side-hidden-receipt-count
                    (count-if
                     #'identity
                     (cons
                      (null (fixture-object-field side-receipt-rpc "result"))
                      (mapcar
                       (lambda (rpc)
                         (null (fixture-object-field rpc "result")))
                       side-extra-receipt-rpcs)))))
             (devnet-smoke-gate-require
              (= 3 (getf summary :engine-connections))
              "Expected 3 side-reorg Engine connections, got ~S"
              (getf summary :engine-connections))
             (devnet-smoke-gate-require
              (= side-public-connection-count
                 (getf summary :public-connections))
              "Expected ~S side-reorg public connections, got ~S"
              side-public-connection-count
              (getf summary :public-connections))
             (dolist (response
                      (append
                       (list side-payload-response
                             side-rejected-forkchoice-response
                             side-forkchoice-response
                             side-block-number-response
                             side-latest-block-response
                             side-transaction-response
                             side-raw-transaction-response
                             side-pending-transactions-response
                             side-receipt-response
                             child-block-response
                             side-block-receipts-response
                             side-logs-response)
                       side-extra-receipt-responses))
               (devnet-smoke-gate-require
                (= 200 (devnet-cli-http-status response))
                "Restored side-reorg RPC HTTP status mismatch"))
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field side-payload-result "status"))
              "Restored side sibling engine_newPayloadV2 status mismatch")
             (devnet-smoke-gate-require
              (string= (hash32-to-hex side-block-hash)
                       (fixture-object-field side-payload-result
                                             "latestValidHash"))
              "Restored side sibling latestValidHash mismatch")
             (devnet-smoke-gate-require
              (= -38002
                 (fixture-object-field side-rejected-forkchoice-error
                                       "code"))
              "Restored side sibling rejected checkpoint error code mismatch")
             (devnet-smoke-gate-require
              (string= "forkchoice safe block is not an ancestor of head"
                       (fixture-object-field side-rejected-forkchoice-error
                                             "message"))
              "Restored side sibling rejected checkpoint error mismatch")
             (devnet-smoke-gate-require
              (string= +payload-status-valid+
                       (fixture-object-field side-forkchoice-status "status"))
              "Restored side sibling forkchoice status mismatch")
             (devnet-smoke-gate-require
              (string= expected-side-block-number
                       (fixture-object-field side-block-number-rpc "result"))
              "Restored side sibling eth_blockNumber mismatch")
             (devnet-smoke-gate-require
              (string= (hash32-to-hex side-block-hash)
                       (fixture-object-field side-latest-block "hash"))
              "Restored side sibling latest block hash mismatch")
             (if reinsertable-transaction-p
                 (progn
                   (devnet-smoke-gate-require
                    (string= transaction-hash-hex
                             (fixture-object-field side-transaction "hash"))
                    "Restored side sibling should reinsert old canonical transaction")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction "blockHash"))
                    "Restored side sibling transaction should be pending")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction
                                                "blockNumber"))
                    "Restored side sibling transaction should not have a block number")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-transaction
                                                "transactionIndex"))
                    "Restored side sibling transaction should not have an index")
                   (devnet-smoke-gate-require
                    (string= expected-raw-transaction side-raw-transaction)
                    "Restored side sibling should expose pending raw transaction")
                   (devnet-smoke-gate-require
                    side-pending-transaction
                    "Restored side sibling should expose displaced transaction in pending view")
                   (devnet-smoke-gate-require
                    (string= transaction-hash-hex
                             (fixture-object-field side-pending-transaction
                                                   "hash"))
                    "Restored side sibling pending view transaction hash mismatch")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "blockHash"))
                    "Restored side sibling pending view should not have a block hash")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "blockNumber"))
                    "Restored side sibling pending view should not have a block number")
                   (devnet-smoke-gate-require
                    (null (fixture-object-field side-pending-transaction
                                                "transactionIndex"))
                    "Restored side sibling pending view should not have an index")
                 (loop for item in reinsertable-transaction-items
                       for pending-transaction in side-reinserted-transactions
                       do
                          (devnet-smoke-gate-require
                           pending-transaction
                           "Restored side sibling missing displaced transaction in pending view")
                          (devnet-smoke-gate-require
                           (string= (getf item :hash-hex)
                                    (fixture-object-field
                                     pending-transaction
                                     "hash"))
                           "Restored side sibling displaced pending hash mismatch")
                          (devnet-smoke-gate-require
                           (null (fixture-object-field pending-transaction
                                                       "blockHash"))
                           "Restored side sibling displaced pending kept old block hash")
                          (devnet-smoke-gate-require
                           (null (fixture-object-field pending-transaction
                                                       "blockNumber"))
                           "Restored side sibling displaced pending kept old block number")
                          (devnet-smoke-gate-require
                           (null (fixture-object-field pending-transaction
                                                       "transactionIndex"))
                           "Restored side sibling displaced pending kept old index")))
               (progn
                 (devnet-smoke-gate-require
                  (null side-transaction)
                  "Restored side sibling should reject wrong-chain displaced transaction")
                 (devnet-smoke-gate-require
                  (null side-raw-transaction)
                  "Restored side sibling should hide wrong-chain raw transaction")
                 (devnet-smoke-gate-require
                  (null side-pending-transaction)
                  "Restored side sibling should hide wrong-chain pending transaction")))
             (devnet-smoke-gate-require
              (null (fixture-object-field side-receipt-rpc "result"))
              "Restored side sibling should hide old canonical receipt")
             (loop for item in extra-transaction-items
                   for rpc in side-extra-receipt-rpcs
                   do
                      (devnet-smoke-gate-require
                       (null (fixture-object-field rpc "result"))
                       "Restored side sibling should hide displaced canonical receipt ~S"
                       (getf item :hash-hex)))
	             (devnet-smoke-gate-require
	              (string= (hash32-to-hex child-block-hash)
	                       (fixture-object-field child-block-by-hash "hash"))
	              "Restored side sibling lost child block hash lookup")
	             (devnet-smoke-gate-require
	              (zerop (length side-block-receipts))
	              "Restored side sibling should have no canonical receipts")
	             (devnet-smoke-gate-require
	              (zerop (length side-logs))
	              "Restored side sibling should have no canonical logs")
             (ethereum-lisp.cli::devnet-node-export-database node)
             (let* ((fresh-node
                      (devnet-smoke-gate-make-restored-node
                       path config :port 0))
                    (fresh-summary
                      (ethereum-lisp.cli:devnet-node-summary fresh-node))
                    (fresh-raw-transaction-output
                      (make-string-output-stream))
                    (fresh-pending-transactions-output
                      (make-string-output-stream))
                    (fresh-receipt-output
                      (make-string-output-stream))
                    (fresh-extra-receipt-outputs
                      (loop repeat (length extra-transaction-items)
                            collect (make-string-output-stream)))
                    (fresh-block-number-output
                      (make-string-output-stream))
                    (fresh-latest-block-output
                      (make-string-output-stream))
                    (fresh-child-block-output
                      (make-string-output-stream))
                    (fresh-block-receipts-output
                      (make-string-output-stream))
                    (fresh-logs-output
                      (make-string-output-stream))
                    (fresh-safe-block-output
                      (make-string-output-stream))
                    (fresh-finalized-block-output
                      (make-string-output-stream))
                    (fresh-safe-balance-output
                      (make-string-output-stream))
                    (fresh-finalized-balance-output
                      (make-string-output-stream))
                    (fresh-child-require-canonical-state-probes
                      (devnet-smoke-gate-state-error-probes
                       225
                       (list
                        (cons "blockHash" (hash32-to-hex child-block-hash))
                        (cons "requireCanonical" t))
                       (devnet-smoke-gate-noncanonical-state-error-messages)
                       balance-address
                       sender-address
                       code-address
                       storage-address
                       storage-key))
                    (fresh-public-requests
                      (append
                       (list
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 213)
                                (cons "method" "eth_getRawTransactionByHash")
                                (cons "params" (list transaction-hash-hex))))
                         fresh-raw-transaction-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 214)
                                (cons "method" "eth_pendingTransactions")
                                (cons "params" '())))
                         fresh-pending-transactions-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 215)
                                (cons "method" "eth_getTransactionReceipt")
                                (cons "params" (list transaction-hash-hex))))
                         fresh-receipt-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 216)
                                (cons "method" "eth_blockNumber")
                                (cons "params" '())))
                         fresh-block-number-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 217)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "latest" :false))))
                         fresh-latest-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 218)
                                (cons "method" "eth_getBlockByHash")
                                (cons "params"
                                      (list (hash32-to-hex child-block-hash)
                                            :false))))
                         fresh-child-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 219)
                                (cons "method" "eth_getBlockReceipts")
                                (cons "params" (list "latest"))))
                         fresh-block-receipts-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 220)
                                (cons "method" "eth_getLogs")
                                (cons "params"
                                      (list
                                       (list
                                        (cons "fromBlock"
                                              expected-side-block-number)
                                        (cons "toBlock"
                                              expected-side-block-number))))))
                         fresh-logs-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 221)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "safe" :false))))
                         fresh-safe-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 222)
                                (cons "method" "eth_getBlockByNumber")
                                (cons "params" (list "finalized" :false))))
                         fresh-finalized-block-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 223)
                                (cons "method" "eth_getBalance")
                                (cons "params"
                                      (list (address-to-hex balance-address)
                                            "safe"))))
                         fresh-safe-balance-output)
                        (cons
                         (json-encode
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 224)
                                (cons "method" "eth_getBalance")
                                (cons "params"
                                      (list (address-to-hex balance-address)
                                            "finalized"))))
                         fresh-finalized-balance-output))
                       (loop for item in extra-transaction-items
                             for output in fresh-extra-receipt-outputs
                             for id from 240
                             collect
                             (cons
                              (json-encode
                               (list (cons "jsonrpc" "2.0")
                                     (cons "id" id)
                                     (cons "method"
                                           "eth_getTransactionReceipt")
                                     (cons "params"
                                           (list (getf item :hash-hex)))))
                              output))
                       (mapcar
                        (lambda (probe)
                          (cons (json-encode (getf probe :request))
                                (getf probe :output)))
                        fresh-child-require-canonical-state-probes)))
                    (fresh-rpc-summary
                      (ethereum-lisp.cli:start-devnet-node-listeners
                       fresh-node
                       (make-engine-rpc-http-listener
                        :endpoint "engine-side-reorg-fresh-restore"
                        :accept-function (lambda () nil)
                        :close-function (lambda () nil))
                       (make-engine-rpc-http-listener
                        :endpoint "public-side-reorg-fresh-restore"
                        :accept-function
                        (lambda ()
                          (when fresh-public-requests
                            (destructuring-bind (body . output)
                                (pop fresh-public-requests)
                              (make-engine-rpc-http-connection
                               :input-stream
                               (make-string-input-stream
                                (devnet-cli-json-rpc-http-request body))
                               :output-stream output
                               :close-function (lambda () nil)))))
                       :close-function (lambda () nil))
                       :max-connections fresh-public-connection-count))
                    (fresh-raw-transaction-response
                      (get-output-stream-string
                       fresh-raw-transaction-output))
                    (fresh-pending-transactions-response
                      (get-output-stream-string
                       fresh-pending-transactions-output))
                    (fresh-receipt-response
                      (get-output-stream-string fresh-receipt-output))
                    (fresh-extra-receipt-responses
                      (mapcar #'get-output-stream-string
                              fresh-extra-receipt-outputs))
                    (fresh-block-number-response
                      (get-output-stream-string fresh-block-number-output))
                    (fresh-latest-block-response
                      (get-output-stream-string fresh-latest-block-output))
                    (fresh-child-block-response
                      (get-output-stream-string fresh-child-block-output))
                    (fresh-block-receipts-response
                      (get-output-stream-string fresh-block-receipts-output))
                    (fresh-logs-response
                      (get-output-stream-string fresh-logs-output))
                    (fresh-safe-block-response
                      (get-output-stream-string fresh-safe-block-output))
                    (fresh-finalized-block-response
                      (get-output-stream-string fresh-finalized-block-output))
                    (fresh-safe-balance-response
                      (get-output-stream-string fresh-safe-balance-output))
                    (fresh-finalized-balance-response
                      (get-output-stream-string
                       fresh-finalized-balance-output))
                    (fresh-raw-transaction-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-raw-transaction-response))
                    (fresh-pending-transactions-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-pending-transactions-response))
                    (fresh-receipt-rpc
                      (devnet-smoke-gate-rpc-body fresh-receipt-response))
                    (fresh-extra-receipt-rpcs
                      (mapcar #'devnet-smoke-gate-rpc-body
                              fresh-extra-receipt-responses))
                    (fresh-block-number-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-block-number-response))
                    (fresh-latest-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-latest-block-response))
                    (fresh-child-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-child-block-response))
                    (fresh-block-receipts-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-block-receipts-response))
                    (fresh-logs-rpc
                      (devnet-smoke-gate-rpc-body fresh-logs-response))
                    (fresh-safe-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-safe-block-response))
                    (fresh-finalized-block-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-finalized-block-response))
                    (fresh-safe-balance-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-safe-balance-response))
                    (fresh-finalized-balance-rpc
                      (devnet-smoke-gate-rpc-body
                       fresh-finalized-balance-response))
                    (fresh-raw-transaction
                      (fixture-object-field fresh-raw-transaction-rpc
                                            "result"))
                    (fresh-pending-transactions
                      (fixture-object-field fresh-pending-transactions-rpc
                                            "result"))
                    (fresh-pending-transaction
                      (find transaction-hash-hex fresh-pending-transactions
                            :test #'string=
                            :key (lambda (transaction)
                                   (fixture-object-field transaction
                                                         "hash"))))
                    (fresh-reinserted-transactions
                      (loop for item in reinsertable-transaction-items
                            collect
                            (find (getf item :hash-hex)
                                  fresh-pending-transactions
                                  :test #'string=
                                  :key (lambda (transaction)
                                         (fixture-object-field transaction
                                                               "hash")))))
                    (fresh-latest-block
                      (fixture-object-field fresh-latest-block-rpc "result"))
                    (fresh-child-block
                      (fixture-object-field fresh-child-block-rpc "result"))
                    (fresh-block-receipts
                      (fixture-object-field fresh-block-receipts-rpc
                                            "result"))
                    (fresh-logs
                      (fixture-object-field fresh-logs-rpc "result"))
                    (fresh-safe-block
                      (fixture-object-field fresh-safe-block-rpc "result"))
                    (fresh-finalized-block
                      (fixture-object-field fresh-finalized-block-rpc
                                            "result"))
                    (fresh-safe-balance
                      (fixture-object-field fresh-safe-balance-rpc
                                            "result"))
                    (fresh-finalized-balance
                      (fixture-object-field fresh-finalized-balance-rpc
                                            "result"))
                    (fresh-child-require-canonical-state-errors
                      (devnet-smoke-gate-verify-state-error-probes
                       fresh-child-require-canonical-state-probes
                       "noncanonical-state"))
                    (fresh-hidden-receipt-count
                      (count-if
                       #'identity
                       (cons
                        (null (fixture-object-field fresh-receipt-rpc
                                                    "result"))
                        (mapcar
                         (lambda (rpc)
                           (null (fixture-object-field rpc "result")))
                         fresh-extra-receipt-rpcs)))))
               (devnet-smoke-gate-require
                (= (block-header-number (block-header side-block))
                   (getf fresh-summary :head-number))
                "Side-reorg database restore head number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex side-block-hash)
                         (getf fresh-summary :head-hash))
                "Side-reorg database restore head hash mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (getf fresh-summary :safe-hash))
                "Side-reorg database restore safe hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (quantity-to-hex
                          (getf fresh-summary :safe-number)))
                "Side-reorg database restore safe number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (getf fresh-summary :finalized-hash))
                "Side-reorg database restore finalized hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (quantity-to-hex
                          (getf fresh-summary :finalized-number)))
                "Side-reorg database restore finalized number mismatch")
               (devnet-smoke-gate-require
                (chain-store-known-block
                 (ethereum-lisp.cli:devnet-node-store fresh-node)
                 child-block-hash)
                "Side-reorg database restore lost old child block")
               (devnet-smoke-gate-require
                (= 0 (getf fresh-rpc-summary :engine-connections))
                "Fresh side-reorg restore expected 0 Engine connections, got ~S"
                (getf fresh-rpc-summary :engine-connections))
               (devnet-smoke-gate-require
                (= fresh-public-connection-count
                   (getf fresh-rpc-summary :public-connections))
                "Fresh side-reorg restore expected ~S public connections, got ~S"
                fresh-public-connection-count
                (getf fresh-rpc-summary :public-connections))
               (dolist (response (append
                                   (list fresh-raw-transaction-response
                                         fresh-pending-transactions-response
                                         fresh-receipt-response
                                         fresh-block-number-response
                                         fresh-latest-block-response
                                         fresh-child-block-response
                                         fresh-block-receipts-response
                                         fresh-logs-response
                                         fresh-safe-block-response
                                         fresh-finalized-block-response
                                         fresh-safe-balance-response
                                         fresh-finalized-balance-response)
                                   fresh-extra-receipt-responses))
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status response))
                  "Fresh side-reorg restore public RPC HTTP status mismatch"))
               (if reinsertable-transaction-p
                   (progn
                     (devnet-smoke-gate-require
                      (string= expected-raw-transaction
                               fresh-raw-transaction)
                      "Fresh side-reorg restore lost pending raw transaction")
                     (devnet-smoke-gate-require
                      fresh-pending-transaction
                      "Fresh side-reorg restore lost pending transaction view")
                     (devnet-smoke-gate-require
                      (string= transaction-hash-hex
                               (fixture-object-field
                                fresh-pending-transaction
                                "hash"))
                      "Fresh side-reorg restore pending transaction hash mismatch")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "blockHash"))
                      "Fresh side-reorg restore pending view kept old block hash")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "blockNumber"))
                      "Fresh side-reorg restore pending view kept old block number")
                     (devnet-smoke-gate-require
                      (null (fixture-object-field fresh-pending-transaction
                                                  "transactionIndex"))
                      "Fresh side-reorg restore pending view kept old index")
                     (loop for item in reinsertable-transaction-items
                           for pending-transaction in fresh-reinserted-transactions
                           do
                              (devnet-smoke-gate-require
                               pending-transaction
                               "Fresh side-reorg restore missing displaced transaction in pending view")
                              (devnet-smoke-gate-require
                               (string= (getf item :hash-hex)
                                        (fixture-object-field
                                         pending-transaction
                                         "hash"))
                               "Fresh side-reorg restore displaced pending hash mismatch")
                              (devnet-smoke-gate-require
                               (null (fixture-object-field pending-transaction
                                                           "blockHash"))
                               "Fresh side-reorg restore displaced pending kept old block hash")
                              (devnet-smoke-gate-require
                               (null (fixture-object-field pending-transaction
                                                           "blockNumber"))
                               "Fresh side-reorg restore displaced pending kept old block number")
                              (devnet-smoke-gate-require
                               (null (fixture-object-field pending-transaction
                                                           "transactionIndex"))
                               "Fresh side-reorg restore displaced pending kept old index")))
                 (progn
                   (devnet-smoke-gate-require
                    (null fresh-raw-transaction)
                    "Fresh side-reorg restore exposed wrong-chain raw transaction")
                   (devnet-smoke-gate-require
                    (null fresh-pending-transaction)
                    "Fresh side-reorg restore exposed wrong-chain pending transaction")))
               (devnet-smoke-gate-require
                (null (fixture-object-field fresh-receipt-rpc "result"))
                "Fresh side-reorg restore kept old canonical receipt")
               (loop for item in extra-transaction-items
                     for rpc in fresh-extra-receipt-rpcs
                     do
                        (devnet-smoke-gate-require
                         (null (fixture-object-field rpc "result"))
                         "Fresh side-reorg restore kept displaced canonical receipt ~S"
                         (getf item :hash-hex)))
               (devnet-smoke-gate-require
                (string= expected-side-block-number
                         (fixture-object-field fresh-block-number-rpc
                                               "result"))
                "Fresh side-reorg restore public block number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex side-block-hash)
                         (fixture-object-field fresh-latest-block "hash"))
                "Fresh side-reorg restore latest block hash mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex child-block-hash)
                         (fixture-object-field fresh-child-block "hash"))
                "Fresh side-reorg restore lost old child block hash lookup")
               (devnet-smoke-gate-require
                (equal (devnet-smoke-gate-noncanonical-state-error-messages)
                       fresh-child-require-canonical-state-errors)
                "Fresh side-reorg restore child requireCanonical state errors mismatch")
               (devnet-smoke-gate-require
                (zerop (length fresh-block-receipts))
                "Fresh side-reorg restore kept canonical receipts")
               (devnet-smoke-gate-require
                (zerop (length fresh-logs))
                "Fresh side-reorg restore kept canonical logs")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (fixture-object-field fresh-safe-block "hash"))
                "Fresh side-reorg restore safe block hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (fixture-object-field fresh-safe-block "number"))
                "Fresh side-reorg restore safe block number mismatch")
               (devnet-smoke-gate-require
                (string= (hash32-to-hex expected-safe-block-hash)
                         (fixture-object-field fresh-finalized-block "hash"))
                "Fresh side-reorg restore finalized block hash mismatch")
               (devnet-smoke-gate-require
                (string= expected-safe-block-number
                         (fixture-object-field fresh-finalized-block "number"))
                "Fresh side-reorg restore finalized block number mismatch")
               (devnet-smoke-gate-require
                (string= expected-checkpoint-balance fresh-safe-balance)
                "Fresh side-reorg restore safe balance mismatch")
               (devnet-smoke-gate-require
                (string= expected-checkpoint-balance
                         fresh-finalized-balance)
                "Fresh side-reorg restore finalized balance mismatch")
               (list :side-block-hash (hash32-to-hex side-block-hash)
                     :side-forkchoice-status
                     (fixture-object-field side-forkchoice-status "status")
                     :side-rejected-checkpoint-error
                     (fixture-object-field side-rejected-forkchoice-error
                                           "message")
                     :side-block-number
                     (fixture-object-field side-block-number-rpc "result")
                     :side-latest-block-hash
                     (fixture-object-field side-latest-block "hash")
                     :side-transaction-reinserted-p
                     (if reinsertable-transaction-p t :false)
                     :side-transaction-by-hash
                     (or side-transaction :false)
                     :side-raw-transaction
                     (or side-raw-transaction :false)
                     :side-pending-transaction
                     (or side-pending-transaction :false)
                     :side-reinserted-transaction-count
                     (if reinsertable-transaction-p
                         (length reinsertable-transaction-items)
                         :false)
                     :side-reinserted-transaction-hashes
                     (if reinsertable-transaction-p
                         reinsertable-transaction-hashes
                         :false)
                     :side-receipt
                     (or (fixture-object-field side-receipt-rpc "result")
                         :false)
                     :side-hidden-receipt-count
                     side-hidden-receipt-count
	                     :side-child-block-hash
	                     (fixture-object-field child-block-by-hash "hash")
                             :side-block-receipts-count
                             (length side-block-receipts)
                             :side-log-count
                             (length side-logs)
	                     :side-restored-head-number
                     (quantity-to-hex (getf fresh-summary :head-number))
                     :side-restored-head-hash
                     (getf fresh-summary :head-hash)
                     :side-restored-rpc-block-number
                     (fixture-object-field fresh-block-number-rpc "result")
                     :side-restored-rpc-latest-block-hash
                     (fixture-object-field fresh-latest-block "hash")
                     :side-restored-safe-number
                     (quantity-to-hex (getf fresh-summary :safe-number))
                     :side-restored-safe-hash
                     (getf fresh-summary :safe-hash)
                     :side-restored-finalized-number
                     (quantity-to-hex
                      (getf fresh-summary :finalized-number))
                     :side-restored-finalized-hash
                     (getf fresh-summary :finalized-hash)
                     :side-restored-rpc-safe-number
                     (fixture-object-field fresh-safe-block "number")
                     :side-restored-rpc-safe-hash
                     (fixture-object-field fresh-safe-block "hash")
                     :side-restored-rpc-finalized-number
                     (fixture-object-field fresh-finalized-block "number")
                     :side-restored-rpc-finalized-hash
                     (fixture-object-field fresh-finalized-block "hash")
                     :side-restored-safe-balance
                     fresh-safe-balance
                     :side-restored-finalized-balance
                     fresh-finalized-balance
                     :side-restored-raw-transaction
                     (or fresh-raw-transaction :false)
                     :side-restored-pending-transaction
                     (or fresh-pending-transaction :false)
                     :side-restored-reinserted-transaction-count
                     (if reinsertable-transaction-p
                         (length reinsertable-transaction-items)
                         :false)
                     :side-restored-reinserted-transaction-hashes
                     (if reinsertable-transaction-p
                         reinsertable-transaction-hashes
                         :false)
                     :side-restored-receipt
                     (or (fixture-object-field fresh-receipt-rpc "result")
                         :false)
                     :side-restored-hidden-receipt-count
                     fresh-hidden-receipt-count
                     :side-restored-child-block-hash
                     (fixture-object-field fresh-child-block "hash")
                     :side-restored-child-require-canonical-error
                     (first fresh-child-require-canonical-state-errors)
                     :side-restored-child-require-canonical-errors
                     fresh-child-require-canonical-state-errors
                     :side-restored-block-receipts-count
                     (length fresh-block-receipts)
                     :side-restored-log-count
                     (length fresh-logs)
                     :side-restored-public-connections
                     (getf fresh-rpc-summary :public-connections)
                     :engine-connections (getf summary :engine-connections)
                     :public-connections
                     (getf summary :public-connections)))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (declare (ignore path side-payload side-block child-block transaction-checks
                   balance-targets expected-safe-block-hash sender-address
                   code-address storage-address storage-key config))
  #-sbcl
  (error "Restored devnet side reorg RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-database
    (path expected-block-number balance-targets
     sender-address expected-sender-nonce
     code-address expected-code storage-address storage-key expected-storage
     transaction-checks log-targets block-hash
     expected-safe-block-number expected-safe-block-hash
     expected-finalized-block-number expected-finalized-block-hash
     config
     &key state-prune-before pruned-state-hash
          (expected-head-block-number expected-block-number)
          checkpoint-balance-targets
          prepared-payload-id prepared-payload-parent-hash
          prepared-payload-block-number
          remote-payload remote-block
          invalid-block invalid-descendant-payload
          txpool-transactions
          selected-txpool-transaction
          side-payload side-block child-block)
  (let* ((database (make-file-key-value-database path))
         (node
           (devnet-smoke-gate-make-restored-node path config :port 0))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (restored-store (ethereum-lisp.cli:devnet-node-store node))
         (pruned-state-expected-p
           (and state-prune-before
                pruned-state-hash
                (< (hex-to-quantity expected-safe-block-number)
                   state-prune-before)))
         (public-rpc-summary
           (devnet-smoke-gate-verify-restored-public-rpc
            node
            expected-block-number
            balance-targets
            sender-address
            expected-sender-nonce
            code-address
            expected-code
            storage-address
            storage-key
            expected-storage
            transaction-checks
            log-targets
            block-hash
            expected-safe-block-number
            expected-safe-block-hash
            expected-finalized-block-number
            expected-finalized-block-hash
            :pruned-state-rpc-tag
            (when pruned-state-expected-p "safe")
            :expected-head-block-number expected-head-block-number))
         (engine-rpc-summary
           (and prepared-payload-id
                (devnet-smoke-gate-verify-restored-engine-rpc
                 node
                 prepared-payload-id
                 prepared-payload-parent-hash
                 prepared-payload-block-number
                 expected-head-block-number)))
         (remote-block-hash (and remote-block (block-hash remote-block)))
         (restored-remote-block
           (and remote-block-hash
                (ethereum-lisp.core::engine-payload-store-remote-block
                 restored-store remote-block-hash)))
         (remote-block-rpc-summary
           (and remote-payload
                remote-block
                (devnet-smoke-gate-verify-restored-remote-block-rpc
                 node
                 remote-payload
                 remote-block-hash
                 expected-head-block-number)))
         (invalid-block-hash (and invalid-block (block-hash invalid-block)))
         (restored-invalid-block
           (and invalid-block-hash
                (ethereum-lisp.core::engine-payload-store-invalid-block
                 restored-store invalid-block-hash)))
         (invalid-tipset-rpc-summary
           (and invalid-block
                invalid-descendant-payload
                (devnet-smoke-gate-verify-restored-invalid-tipset-rpc
                 node
                 invalid-descendant-payload
                 (block-header-parent-hash (block-header invalid-block))
                 expected-head-block-number)))
         (txpool-rpc-summary
           (and txpool-transactions
                (devnet-smoke-gate-verify-restored-txpool-rpc
                 node txpool-transactions
                 :selected-pending-imported-p
                 (and expected-head-block-number
                      (not (string= expected-block-number
                                    expected-head-block-number)))
                 :selected-pending-transaction
                 selected-txpool-transaction)))
         (side-reorg-rpc-summary
           (and (not state-prune-before)
                side-payload
                side-block
                child-block
                (devnet-smoke-gate-verify-restored-side-reorg-rpc
                 path
                 side-payload
                 side-block
                 child-block
                 balance-targets
                 checkpoint-balance-targets
                 transaction-checks
                 expected-safe-block-hash
                 sender-address
                 code-address
                 storage-address
                 storage-key
                 config))))
    (devnet-smoke-gate-require
     (< 0 (length (kv-chain-record-entries database :block)))
     "Database export did not write block records")
    (devnet-smoke-gate-require
     (< 0 (length (kv-chain-record-entries database :canonical-hash)))
     "Database export did not write canonical hash records")
    (when prepared-payload-id
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :prepared-payload)))
       "Database export did not write prepared payload records"))
    (when remote-block
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :remote-block)))
       "Database export did not write remote block records")
      (devnet-smoke-gate-require
       restored-remote-block
       "Database restore did not publish the remote block cache")
      (devnet-smoke-gate-require
       (bytes= (block-rlp remote-block)
               (block-rlp restored-remote-block))
       "Database restore changed the remote block RLP"))
    (when invalid-block
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :invalid-tipset)))
       "Database export did not write invalid-tipset records")
      (devnet-smoke-gate-require
       restored-invalid-block
       "Database restore did not publish the invalid-tipset cache")
      (devnet-smoke-gate-require
       (bytes= (block-rlp invalid-block)
               (block-rlp restored-invalid-block))
       "Database restore changed the invalid-tipset block RLP"))
    (when txpool-transactions
      (devnet-smoke-gate-require
       (< 0 (length (kv-chain-record-entries database :txpool)))
       "Database export did not write txpool records"))
    (devnet-smoke-gate-require
     (= (hex-to-quantity expected-head-block-number)
        (getf summary :head-number))
     "Database restored head mismatch: expected ~A got ~A"
     expected-head-block-number
     (quantity-to-hex (getf summary :head-number)))
    (devnet-smoke-gate-require
     (string= path (getf summary :database-path))
     "Database path missing from restored node summary")
    (when pruned-state-expected-p
      (devnet-smoke-gate-require
       (chain-store-known-block restored-store pruned-state-hash)
       "Pruned-state block was not restored by hash")
      (devnet-smoke-gate-require
       (not (chain-store-state-available-p restored-store pruned-state-hash))
       "Pruned state snapshot is still available after restore"))
    (append summary
            (list :pruned-state-before state-prune-before
                  :pruned-state-available-p
                  (and pruned-state-hash
                       (chain-store-state-available-p
                        restored-store pruned-state-hash))
                  :rpc-block-number
                  (getf public-rpc-summary :block-number)
                  :rpc-balance
                  (getf public-rpc-summary :balance)
                  :rpc-nonce
                  (getf public-rpc-summary :nonce)
                  :rpc-code
                  (getf public-rpc-summary :code)
                  :rpc-storage
                  (getf public-rpc-summary :storage)
                  :rpc-proof-address
                  (getf public-rpc-summary :proof-address)
                  :rpc-proof-code-hash
                  (getf public-rpc-summary :proof-code-hash)
                  :rpc-proof-storage-key
                  (getf public-rpc-summary :proof-storage-key)
                  :rpc-proof-storage-value
                  (getf public-rpc-summary :proof-storage-value)
                  :rpc-proof-storage-count
                  (getf public-rpc-summary :proof-storage-count)
                  :rpc-proof-account-proof-count
                  (getf public-rpc-summary :proof-account-proof-count)
                  :rpc-receipt-transaction-hash
                  (getf public-rpc-summary :receipt-transaction-hash)
                  :rpc-receipt-block-number
                  (getf public-rpc-summary :receipt-block-number)
                  :rpc-block-hash
                  (getf public-rpc-summary :block-hash)
                  :rpc-block-by-hash-number
                  (getf public-rpc-summary :block-by-hash-number)
                  :rpc-block-transaction-hash
                  (getf public-rpc-summary :block-transaction-hash)
                  :rpc-block-by-number-hash
                  (getf public-rpc-summary :block-by-number-hash)
                  :rpc-block-by-number-number
                  (getf public-rpc-summary :block-by-number-number)
                  :rpc-block-by-number-transaction-hash
                  (getf public-rpc-summary
                        :block-by-number-transaction-hash)
                  :rpc-full-block-transaction-count
                  (getf public-rpc-summary
                        :full-block-transaction-count)
                  :rpc-full-block-transaction-hash
                  (getf public-rpc-summary :full-block-transaction-hash)
                  :rpc-full-block-transaction-index
                  (getf public-rpc-summary :full-block-transaction-index)
                  :rpc-full-block-by-number-transaction-count
                  (getf public-rpc-summary
                        :full-block-by-number-transaction-count)
                  :rpc-full-block-by-number-transaction-hash
                  (getf public-rpc-summary
                        :full-block-by-number-transaction-hash)
                  :rpc-full-block-by-number-transaction-index
                  (getf public-rpc-summary
                        :full-block-by-number-transaction-index)
                  :rpc-transaction-hash
                  (getf public-rpc-summary :transaction-hash)
                  :rpc-transaction-block-hash
                  (getf public-rpc-summary :transaction-block-hash)
                  :rpc-transaction-block-number
                  (getf public-rpc-summary :transaction-block-number)
                  :rpc-block-receipts-count
                  (getf public-rpc-summary :block-receipts-count)
                  :rpc-block-receipt-transaction-hash
                  (getf public-rpc-summary :block-receipt-transaction-hash)
                  :rpc-block-receipt-block-hash
                  (getf public-rpc-summary :block-receipt-block-hash)
                  :rpc-block-receipt-block-number
                  (getf public-rpc-summary :block-receipt-block-number)
                  :rpc-block-transaction-count-by-hash
                  (getf public-rpc-summary
                        :block-transaction-count-by-hash)
                  :rpc-block-transaction-count-by-number
                  (getf public-rpc-summary
                        :block-transaction-count-by-number)
                  :rpc-canonical-hash-balance
                  (getf public-rpc-summary :canonical-hash-balance)
                  :rpc-canonical-hash-require-balance
                  (getf public-rpc-summary
                        :canonical-hash-require-balance)
                  :rpc-transaction-count
                  (getf public-rpc-summary :transaction-count)
                  :rpc-balance-count
                  (getf public-rpc-summary :balance-count)
                  :rpc-log-count
                  (getf public-rpc-summary :log-count)
                  :rpc-log-filter-count
                  (getf public-rpc-summary :log-filter-count)
                  :rpc-log-filter-log-count
                  (getf public-rpc-summary :log-filter-log-count)
                  :rpc-log-filter-uninstall-count
                  (getf public-rpc-summary
                        :log-filter-uninstall-count)
                  :rpc-log-filter-missing-error-codes
                  (getf public-rpc-summary
                        :log-filter-missing-error-codes)
                  :rpc-block-filter-id
                  (getf public-rpc-summary :block-filter-id)
                  :rpc-block-filter-change-count
                  (getf public-rpc-summary :block-filter-change-count)
                  :rpc-block-filter-get-logs-error-code
                  (getf public-rpc-summary
                        :block-filter-get-logs-error-code)
                  :rpc-block-filter-uninstall-result
                  (getf public-rpc-summary
                        :block-filter-uninstall-result)
                  :rpc-block-filter-missing-error-code
                  (getf public-rpc-summary
                        :block-filter-missing-error-code)
                  :rpc-raw-transaction
                  (getf public-rpc-summary :raw-transaction)
                  :rpc-raw-transaction-by-hash
                  (getf public-rpc-summary :raw-transaction-by-hash)
                  :rpc-raw-transaction-by-number
                  (getf public-rpc-summary :raw-transaction-by-number)
                  :rpc-transaction-by-hash-index-hash
                  (getf public-rpc-summary
                        :transaction-by-hash-index-hash)
                  :rpc-transaction-by-hash-index-block-hash
                  (getf public-rpc-summary
                        :transaction-by-hash-index-block-hash)
                  :rpc-transaction-by-hash-index-block-number
                  (getf public-rpc-summary
                        :transaction-by-hash-index-block-number)
                  :rpc-transaction-by-hash-index-transaction-index
                  (getf public-rpc-summary
                        :transaction-by-hash-index-transaction-index)
                  :rpc-transaction-by-number-index-hash
                  (getf public-rpc-summary
                        :transaction-by-number-index-hash)
                  :rpc-transaction-by-number-index-block-hash
                  (getf public-rpc-summary
                        :transaction-by-number-index-block-hash)
                  :rpc-transaction-by-number-index-block-number
                  (getf public-rpc-summary
                        :transaction-by-number-index-block-number)
                  :rpc-transaction-by-number-index-transaction-index
                  (getf public-rpc-summary
                        :transaction-by-number-index-transaction-index)
                  :rpc-safe-block-hash
                  (getf public-rpc-summary :safe-block-hash)
                  :rpc-safe-block-number
                  (getf public-rpc-summary :safe-block-number)
                  :rpc-finalized-block-hash
                  (getf public-rpc-summary :finalized-block-hash)
                  :rpc-finalized-block-number
                  (getf public-rpc-summary :finalized-block-number)
                  :rpc-call-result
                  (getf public-rpc-summary :call-result)
                  :rpc-failed-call-error-message
                  (getf public-rpc-summary :failed-call-error-message)
                  :rpc-estimate-gas
                  (getf public-rpc-summary :estimate-gas)
                  :rpc-access-list-count
                  (getf public-rpc-summary :access-list-count)
                  :rpc-access-list-gas-used
                  (getf public-rpc-summary :access-list-gas-used)
                  :rpc-post-call-storage
                  (getf public-rpc-summary :post-call-storage)
                  :rpc-simulation-count
                  (getf public-rpc-summary :simulation-count)
                  :rpc-pruned-state-error-message
                  (getf public-rpc-summary :pruned-state-error-message)
                  :rpc-pruned-state-error-messages
                  (getf public-rpc-summary :pruned-state-error-messages)
                  :rpc-public-connections
                  (getf public-rpc-summary :public-connections)
                  :rpc-prepared-payload-id
                  (and engine-rpc-summary
                       (getf engine-rpc-summary :prepared-payload-id))
                  :rpc-prepared-payload-parent-hash
                  (and engine-rpc-summary
                       (getf engine-rpc-summary
                             :prepared-payload-parent-hash))
                  :rpc-prepared-payload-block-number
                  (and engine-rpc-summary
                       (getf engine-rpc-summary
                             :prepared-payload-block-number))
                  :rpc-engine-connections
                  (and engine-rpc-summary
                       (getf engine-rpc-summary :engine-connections))
                  :remote-block-hash
                  (and remote-block-rpc-summary
                       (getf remote-block-rpc-summary :remote-block-hash))
                  :rpc-remote-block-status
                  (and remote-block-rpc-summary
                       (getf remote-block-rpc-summary :remote-block-status))
                  :rpc-remote-block-engine-connections
                  (and remote-block-rpc-summary
                       (getf remote-block-rpc-summary
                             :engine-connections))
                  :invalid-tipset-block-hash
                  (and invalid-block
                       (hash32-to-hex (block-hash invalid-block)))
                  :rpc-invalid-tipset-status
                  (and invalid-tipset-rpc-summary
                       (getf invalid-tipset-rpc-summary
                             :invalid-tipset-status))
                  :rpc-invalid-tipset-validation-error
                  (and invalid-tipset-rpc-summary
                       (getf invalid-tipset-rpc-summary
                             :invalid-tipset-validation-error))
                  :rpc-invalid-tipset-engine-connections
                  (and invalid-tipset-rpc-summary
                       (getf invalid-tipset-rpc-summary
                             :engine-connections))
                  :rpc-txpool-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-transaction-hash))
                  :rpc-txpool-raw-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-raw-transaction))
                  :rpc-txpool-sender
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary :txpool-sender))
                  :rpc-txpool-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary :txpool-nonce))
                  :rpc-txpool-inspect-summary
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-inspect-summary))
                  :rpc-txpool-basefee-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-transaction-hash))
                  :rpc-txpool-basefee-raw-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-raw-transaction))
                  :rpc-txpool-basefee-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-nonce))
                  :rpc-txpool-basefee-inspect-summary
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-inspect-summary))
                  :rpc-txpool-queued-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-transaction-hash))
                  :rpc-txpool-queued-raw-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-raw-transaction))
                  :rpc-txpool-queued-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-nonce))
                  :rpc-txpool-queued-inspect-summary
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-inspect-summary))
                  :rpc-txpool-status-pending
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-status-pending))
                  :rpc-txpool-status-queued
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-status-queued))
                  :rpc-txpool-pending-block-count
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-count))
                  :rpc-txpool-pending-block-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-hash))
                  :rpc-txpool-pending-block-base-fee
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-base-fee))
                  :rpc-txpool-pending-header-number
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-number))
                  :rpc-txpool-pending-header-parent-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-parent-hash))
                  :rpc-txpool-pending-header-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-hash))
                  :rpc-txpool-pending-header-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-nonce))
                  :rpc-txpool-pending-header-base-fee
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-header-base-fee))
                  :rpc-txpool-pending-fee-history-next-base-fee
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-fee-history-next-base-fee))
                  :rpc-txpool-pending-sender-nonce
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-sender-nonce))
                  :rpc-txpool-pending-block-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-transaction-hash))
                  :rpc-txpool-pending-block-transaction-block-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-block-transaction-block-hash))
                  :rpc-txpool-pending-index-transaction-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-index-transaction-hash))
                  :rpc-txpool-pending-index-block-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-index-block-hash))
                  :rpc-txpool-pending-raw-index-transaction
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-pending-raw-index-transaction))
                  :rpc-txpool-content-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-content-hash))
                  :rpc-txpool-content-from-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-content-from-hash))
                  :rpc-txpool-basefee-content-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-content-hash))
                  :rpc-txpool-basefee-content-from-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-basefee-content-from-hash))
                  :rpc-txpool-queued-content-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-content-hash))
                  :rpc-txpool-queued-content-from-hash
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :txpool-queued-content-from-hash))
                  :rpc-txpool-public-connections
                  (and txpool-rpc-summary
                       (getf txpool-rpc-summary
                             :public-connections))
                  :rpc-side-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-block-hash))
                  :rpc-side-forkchoice-status
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-forkchoice-status))
                  :rpc-side-rejected-checkpoint-error
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-rejected-checkpoint-error))
                  :rpc-side-block-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-block-number))
                  :rpc-side-latest-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-latest-block-hash))
                  :rpc-side-transaction-reinserted-p
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-transaction-reinserted-p))
                  :rpc-side-transaction-by-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-transaction-by-hash))
                  :rpc-side-raw-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-raw-transaction))
                  :rpc-side-pending-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-pending-transaction))
                  :rpc-side-reinserted-transaction-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-reinserted-transaction-count))
                  :rpc-side-reinserted-transaction-hashes
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-reinserted-transaction-hashes))
                  :rpc-side-receipt
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-receipt))
                  :rpc-side-hidden-receipt-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-hidden-receipt-count))
                  :rpc-side-child-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-child-block-hash))
                  :rpc-side-block-receipts-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-block-receipts-count))
                  :rpc-side-log-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :side-log-count))
                  :rpc-side-restored-head-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-head-number))
                  :rpc-side-restored-head-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-head-hash))
                  :rpc-side-restored-rpc-block-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-block-number))
                  :rpc-side-restored-rpc-latest-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-latest-block-hash))
                  :rpc-side-restored-safe-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-safe-number))
                  :rpc-side-restored-safe-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-safe-hash))
                  :rpc-side-restored-finalized-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-finalized-number))
                  :rpc-side-restored-finalized-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-finalized-hash))
                  :rpc-side-restored-rpc-safe-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-safe-number))
                  :rpc-side-restored-rpc-safe-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-safe-hash))
                  :rpc-side-restored-rpc-finalized-number
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-finalized-number))
                  :rpc-side-restored-rpc-finalized-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-rpc-finalized-hash))
                  :rpc-side-restored-safe-balance
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-safe-balance))
                  :rpc-side-restored-finalized-balance
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-finalized-balance))
                  :rpc-side-restored-raw-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-raw-transaction))
                  :rpc-side-restored-pending-transaction
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-pending-transaction))
                  :rpc-side-restored-reinserted-transaction-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-reinserted-transaction-count))
                  :rpc-side-restored-reinserted-transaction-hashes
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-reinserted-transaction-hashes))
                  :rpc-side-restored-receipt
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-receipt))
                  :rpc-side-restored-hidden-receipt-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-hidden-receipt-count))
                  :rpc-side-restored-child-block-hash
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-child-block-hash))
                  :rpc-side-restored-child-require-canonical-error
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-child-require-canonical-error))
                  :rpc-side-restored-child-require-canonical-errors
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-child-require-canonical-errors))
                  :rpc-side-restored-block-receipts-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-block-receipts-count))
                  :rpc-side-restored-log-count
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-log-count))
                  :rpc-side-restored-public-connections
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :side-restored-public-connections))
                  :rpc-side-engine-connections
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary :engine-connections))
                  :rpc-side-public-connections
                  (and side-reorg-rpc-summary
                       (getf side-reorg-rpc-summary
                             :public-connections))))))

(defun devnet-smoke-gate-run
    (case-name &key ready-file log-file pid-file database-file
       state-prune-before terminal-total-difficulty
       terminal-total-difficulty-passed-p terminal-block-hash
       terminal-block-number)
  #+sbcl
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-jwt" "hex"))
        (journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-txpool-journal"
                                "sexp")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let ((report
                   (devnet-smoke-gate-call-with-telemetry-sink
                    log-file
                    (lambda (telemetry-sink)
                      (let* ((fixture
                               (devnet-smoke-gate-engine-fixture case-name))
                             (store
                               (devnet-smoke-gate-field fixture "store"))
                             (config
                               (ethereum-lisp.cli::devnet-cli-apply-merge-overrides
                                (devnet-smoke-gate-field fixture "config")
                                :terminal-total-difficulty
                                terminal-total-difficulty
                                :terminal-total-difficulty-passed
                                terminal-total-difficulty-passed-p
                                :terminal-total-difficulty-passed-specified-p
                                terminal-total-difficulty-passed-p
                                :terminal-block-hash terminal-block-hash
                                :terminal-block-number
                                terminal-block-number))
                             (parent-state
                               (devnet-smoke-gate-field fixture
                                                        "parentState"))
                             (parent-block
                               (devnet-smoke-gate-field fixture
                                                        "parentBlock"))
                             (child-block
                               (devnet-smoke-gate-field fixture
                                                        "childBlock"))
                             (payload
                               (devnet-smoke-gate-field fixture "payload"))
                             (side-block
                               (devnet-smoke-gate-field fixture
                                                        "sideBlock"))
                             (side-payload
                               (devnet-smoke-gate-field fixture
                                                        "sidePayload"))
                             (txpool-transactions
                               (devnet-smoke-gate-field
                                fixture "txpoolTransactions"))
                             (pending-transaction
                               (devnet-smoke-gate-txpool-transaction-entry
                                txpool-transactions "pending"))
                             (basefee-transaction
                               (devnet-smoke-gate-txpool-transaction-entry
                                txpool-transactions "basefee"))
                             (queued-transaction
                               (devnet-smoke-gate-txpool-transaction-entry
                                txpool-transactions "queued"))
                             (payload-case
                               (devnet-smoke-gate-field fixture
                                                        "payloadCase"))
                             (expect
                               (devnet-smoke-gate-field fixture "expect"))
                             (node
                               (ethereum-lisp.cli:make-devnet-node
                                :genesis-path
                                (namestring
                                 (devnet-smoke-gate-reference-path
                                  +devnet-cli-genesis-fixture+))
                                :port 8551
                                :public-port 8545
                                :jwt-secret-path (namestring jwt-path)
                                :log-path log-file
                                :database-path database-file
                                :pid-file-path pid-file
                                :txpool-journal-path (namestring journal-path)
                                :txpool-rejournal-seconds 1
                                :terminal-total-difficulty
                                terminal-total-difficulty
                                :terminal-total-difficulty-passed
                                terminal-total-difficulty-passed-p
                                :terminal-total-difficulty-passed-specified-p
                                terminal-total-difficulty-passed-p
                                :terminal-block-hash terminal-block-hash
                                :terminal-block-number terminal-block-number
                                :telemetry-sink telemetry-sink))
                  (expected-terminal-total-difficulty
                    (quantity-to-hex (or terminal-total-difficulty 0)))
                  (expected-terminal-block-hash
                    (hash32-to-hex (or terminal-block-hash (zero-hash32))))
                  (expected-terminal-block-number
                    (quantity-to-hex (or terminal-block-number 0)))
                  (mismatched-terminal-total-difficulty
                    (quantity-to-hex
                     (if (= 1 (or terminal-total-difficulty 0)) 2 1)))
                  (balance-address nil)
                  (expected-balance nil)
                  (balance-field nil)
                  (sender-address nil)
                  (expected-sender-nonce nil)
                  (code-address nil)
                  (expected-code nil)
                  (storage-address nil)
                  (storage-key nil)
                  (expected-storage nil)
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (invalid-token
                    (engine-rpc-make-jwt-token
                     (make-byte-vector 32 :initial-element #x99)
                     0))
                  (unauthenticated-engine-output (make-string-output-stream))
                  (invalid-auth-engine-output (make-string-output-stream))
                  (duplicate-auth-engine-output (make-string-output-stream))
                  (engine-root-wrong-path-output
                    (make-string-output-stream))
                  (client-version-output (make-string-output-stream))
                  (capabilities-output (make-string-output-stream))
                  (transition-configuration-output
                    (make-string-output-stream))
                  (transition-configuration-mismatch-output
                    (make-string-output-stream))
                  (engine-public-namespace-output
                    (make-string-output-stream))
                  (new-payload-output (make-string-output-stream))
                  (forkchoice-output (make-string-output-stream))
                  (payload-bodies-by-hash-output
                    (make-string-output-stream))
                  (payload-bodies-by-range-output
                    (make-string-output-stream))
                  (prepare-payload-output (make-string-output-stream))
                  (get-payload-output (make-string-output-stream))
                  (prepare-txpool-payload-output
                    (make-string-output-stream))
                  (get-txpool-payload-output (make-string-output-stream))
                  (import-txpool-payload-output
                    (make-string-output-stream))
                  (forkchoice-txpool-payload-output
                    (make-string-output-stream))
                  (remote-payload-output (make-string-output-stream))
                  (invalid-payload-output (make-string-output-stream))
                  (block-number-output (make-string-output-stream))
                  (balance-output (make-string-output-stream))
                  (prepared-public-output (make-string-output-stream))
                  (remote-public-output (make-string-output-stream))
                  (invalid-public-output (make-string-output-stream))
                  (public-client-version-output (make-string-output-stream))
                  (public-net-version-output (make-string-output-stream))
                  (public-net-listening-output (make-string-output-stream))
                  (public-syncing-output (make-string-output-stream))
                  (public-net-peer-count-output
                    (make-string-output-stream))
                  (public-accounts-output (make-string-output-stream))
                  (public-coinbase-output (make-string-output-stream))
                  (public-mining-output (make-string-output-stream))
                  (public-hashrate-output (make-string-output-stream))
                  (public-rpc-modules-output (make-string-output-stream))
                  (public-protocol-version-output
                    (make-string-output-stream))
                  (public-web3-sha3-output (make-string-output-stream))
                  (public-gas-price-output (make-string-output-stream))
                  (public-priority-fee-output (make-string-output-stream))
                  (public-base-fee-output (make-string-output-stream))
                  (public-blob-base-fee-output
                    (make-string-output-stream))
                  (public-fee-history-output (make-string-output-stream))
                  (public-batch-output (make-string-output-stream))
                  (public-engine-namespace-output
                    (make-string-output-stream))
                  (public-malformed-json-output
                    (make-string-output-stream))
                  (public-root-wrong-path-output
                    (make-string-output-stream))
                  (new-pending-filter-output
                    (make-string-output-stream))
                  (pending-filter-changes-output
                    (make-string-output-stream))
                  (empty-pending-filter-changes-output
                    (make-string-output-stream))
                  (uninstall-pending-filter-output
                    (make-string-output-stream))
                  (removed-pending-filter-changes-output
                    (make-string-output-stream))
                  (send-raw-output (make-string-output-stream))
                  (send-basefee-output (make-string-output-stream))
                  (send-queued-output (make-string-output-stream))
                  (send-replacement-output (make-string-output-stream))
                  (txpool-rejournal-output (make-string-output-stream))
                  (raw-pending-output (make-string-output-stream))
                  (raw-basefee-output (make-string-output-stream))
                  (raw-queued-output (make-string-output-stream))
                  (pending-nonce-output (make-string-output-stream))
                  (pending-block-receipts-output
                    (make-string-output-stream))
                  (pending-uncle-count-output
                    (make-string-output-stream))
                  (pending-logs-output (make-string-output-stream))
                  (txpool-status-output (make-string-output-stream))
                  (txpool-content-from-output (make-string-output-stream))
                  (txpool-inspect-output (make-string-output-stream))
                  (post-prepared-txpool-content-from-output
                    (make-string-output-stream))
                  (prepare-replacement-txpool-payload-output
                    (make-string-output-stream))
                  (get-replacement-txpool-payload-output
                    (make-string-output-stream))
                  (post-replacement-txpool-content-from-output
                    (make-string-output-stream))
                  (post-import-transaction-output
                    (make-string-output-stream))
                  (post-import-receipt-output
                    (make-string-output-stream))
                  (post-import-raw-output
                    (make-string-output-stream))
                  (post-import-block-output
                    (make-string-output-stream))
                  (post-import-txpool-status-output
                    (make-string-output-stream))
                  (post-import-txpool-content-from-output
                    (make-string-output-stream))
                  (balance-targets
                    (devnet-smoke-gate-balance-targets expect))
                  (checkpoint-balance-targets
                    (devnet-smoke-gate-checkpoint-balance-targets
                     parent-state
                     balance-targets))
                  (transaction-checks
                    (devnet-smoke-gate-transaction-checks child-block))
                  (log-targets
                    (devnet-smoke-gate-log-targets expect))
                  (prepare-payload-attributes
                    (devnet-smoke-gate-payload-attributes-v2
                     child-block
                     (getf (first balance-targets) :address)))
                  (expected-prepared-payload-id
                    (ethereum-lisp.core::engine-payload-id-to-hex
                     (ethereum-lisp.core::engine-payload-id
                      2
                      (block-hash child-block)
                      (ethereum-lisp.core::engine-rpc-validate-payload-attributes-v2
                       prepare-payload-attributes))))
                  (txpool-payload-attributes
                    (let ((attributes (copy-tree prepare-payload-attributes)))
                      (setf (cdr (assoc "timestamp" attributes
                                        :test #'string=))
                            (quantity-to-hex
                             (+ 2
                                (block-header-timestamp
                                 (block-header child-block)))))
                      attributes))
                  (remote-block
                    (devnet-smoke-gate-remote-block child-block))
                  (remote-payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data remote-block)))
                  (invalid-block
                    (devnet-smoke-gate-invalid-child-block child-block))
                  (invalid-payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data invalid-block)))
                  (invalid-descendant-block
                    (devnet-smoke-gate-invalid-grandchild-block
                     invalid-block))
                  (invalid-descendant-payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data invalid-descendant-block)))
                  (pending-transaction-hash
                    (transaction-hash pending-transaction))
                  (pending-transaction-hash-hex
                    (hash32-to-hex pending-transaction-hash))
                  (replacement-transaction
                    (devnet-smoke-gate-txpool-transaction
                     config
                     (transaction-nonce pending-transaction)
                     +devnet-smoke-gate-txpool-replacement-gas-price+))
                  (replacement-transaction-hash
                    (transaction-hash replacement-transaction))
                  (replacement-transaction-hash-hex
                    (hash32-to-hex replacement-transaction-hash))
                  (basefee-transaction-hash-hex
                    (devnet-smoke-gate-transaction-hash-hex
                     basefee-transaction))
                  (queued-transaction-hash-hex
                    (devnet-smoke-gate-transaction-hash-hex
                     queued-transaction))
                  (pending-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     pending-transaction))
                  (replacement-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     replacement-transaction))
                  (basefee-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     basefee-transaction))
                  (queued-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     queued-transaction))
                  (pending-transaction-summary
                    (devnet-smoke-gate-transaction-summary
                     pending-transaction))
                  (basefee-transaction-summary
                    (devnet-smoke-gate-transaction-summary
                     basefee-transaction))
                  (queued-transaction-summary
                    (devnet-smoke-gate-transaction-summary
                     queued-transaction))
                  (pending-transaction-sender
                    (transaction-sender pending-transaction))
                  (pending-transaction-sender-hex
                    (address-to-hex pending-transaction-sender))
                  (pending-transaction-nonce-key
                    (devnet-smoke-gate-transaction-nonce-key
                     pending-transaction))
                  (expected-pending-sender-nonce
                    (quantity-to-hex
                     (1+ (transaction-nonce pending-transaction))))
                  (basefee-transaction-nonce-key
                    (devnet-smoke-gate-transaction-nonce-key
                     basefee-transaction))
                  (queued-transaction-nonce-key
                    (devnet-smoke-gate-transaction-nonce-key
                     queued-transaction))
                  (txpool-rejournal-report nil)
                  (prepare-txpool-payload-response-cache nil)
                  (get-txpool-payload-response-cache nil)
                  (post-public-txpool-payload-id nil)
                  (post-public-txpool-execution-payload nil)
                  (post-public-txpool-block-hash nil)
                  (prepare-replacement-txpool-payload-response-cache nil)
                  (get-replacement-txpool-payload-response-cache nil)
                  (replacement-txpool-payload-id nil)
                  (replacement-txpool-execution-payload nil)
                  (replacement-txpool-block-hash nil)
                  (engine-requests
                    (list
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 18)
                        (cons "method" "engine_getClientVersionV1")
                        (cons "params"
                              (list
                               (list
                                (cons "code" "CL")
                                (cons "name" "ethereum-lisp-smoke")
                                (cons "version" "0.0.0")
                                (cons "commit" "0x00000000"))))))
                      client-version-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 19)
                             (cons "method" "engine_exchangeCapabilities")
                             (cons "params"
                                   (list
                                    (list
                                     "engine_newPayloadV1"
                                     "engine_forkchoiceUpdatedV1"
                                     "engine_getPayloadV1"
                                     "engine_newPayloadV2"
                                     "engine_forkchoiceUpdatedV2"
                                     "engine_getPayloadV2")))))
                      capabilities-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 27)
                        (cons "method"
                              "engine_exchangeTransitionConfigurationV1")
                        (cons "params"
                              (list
                               (list
                                (cons "terminalTotalDifficulty"
                                      expected-terminal-total-difficulty)
                                (cons "terminalBlockHash"
                                      expected-terminal-block-hash)
                                (cons "terminalBlockNumber"
                                      expected-terminal-block-number))))))
                      transition-configuration-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 28)
                        (cons "method"
                              "engine_exchangeTransitionConfigurationV1")
                        (cons "params"
                              (list
                               (list
                                (cons "terminalTotalDifficulty"
                                      mismatched-terminal-total-difficulty)
                                (cons "terminalBlockHash"
                                      expected-terminal-block-hash)
                                (cons "terminalBlockNumber"
                                      expected-terminal-block-number))))))
                      transition-configuration-mismatch-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 71)
                             (cons "method" "eth_chainId")
                             (cons "params" '())))
                      engine-public-namespace-output)
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 21 payload))
                      new-payload-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        22 (block-hash child-block)
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      forkchoice-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 28)
                        (cons "method" "engine_getPayloadBodiesByHashV1")
                        (cons "params"
                              (list
                               (list
                                (hash32-to-hex (block-hash child-block)))))))
                      payload-bodies-by-hash-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 29)
                        (cons "method" "engine_getPayloadBodiesByRangeV1")
                        (cons "params"
                              (list
                               (quantity-to-hex
                                (block-header-number
                                 (block-header child-block)))
                               "0x1"))))
                      payload-bodies-by-range-output)
                     (cons
                      (json-encode
                       (devnet-smoke-gate-forkchoice-v2-payload-attributes-request
                        23
                        (block-hash child-block)
                        prepare-payload-attributes
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      prepare-payload-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 30)
                        (cons "method" "engine_getPayloadV2")
                        (cons "params"
                              (list expected-prepared-payload-id))))
                      get-payload-output)
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 24 remote-payload))
                      remote-payload-output)
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 25 invalid-payload))
                      invalid-payload-output)))
                  (post-public-engine-requests
                    (list
                     (cons
                      (json-encode
                       (devnet-smoke-gate-forkchoice-v2-payload-attributes-request
                        78
                        (block-hash child-block)
                        txpool-payload-attributes
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      prepare-txpool-payload-output)
                     (cons
                      :txpool-get-payload
                      get-txpool-payload-output)))
                  (replacement-engine-requests
                    (list
                     (cons
                      (json-encode
                       (devnet-smoke-gate-forkchoice-v2-payload-attributes-request
                        89
                        (block-hash child-block)
                        txpool-payload-attributes
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      prepare-replacement-txpool-payload-output)
                     (cons
                      :replacement-txpool-get-payload
                      get-replacement-txpool-payload-output)))
                  (post-prepared-engine-requests
                    (list
                     (cons
                      :txpool-new-payload
                      import-txpool-payload-output)
                     (cons
                      :txpool-forkchoice
                      forkchoice-txpool-payload-output)))
                  (public-requests
                    (let ((target (first balance-targets)))
                      (setf balance-address (getf target :address)
                            expected-balance (getf target :balance)
                            balance-field (getf target :field)
                            sender-address
                            (fixture-address-field expect "sender")
                            expected-sender-nonce
                            (fixture-object-field expect "senderNonce")
                            code-address
                            (fixture-address-field expect "codeAddress")
                            expected-code
                            (fixture-object-field expect "code")
                            storage-address
                            (fixture-address-field expect "storageAddress")
                            storage-key
                            (fixture-object-field expect "storageKey")
                            expected-storage
                            (fixture-object-field expect "storageValue"))
                      (list
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 31)
                               (cons "method" "eth_blockNumber")
                               (cons "params" '())))
                        block-number-output)
                       (cons
                        (json-encode
                         (engine-fixture-balance-request 32 balance-address))
                        balance-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 33)
                               (cons "method" "eth_blockNumber")
                               (cons "params" '())))
                        prepared-public-output)
                       (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                               (cons "id" 34)
                               (cons "method" "eth_blockNumber")
                               (cons "params" '())))
                        remote-public-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 35)
                               (cons "method" "eth_blockNumber")
                               (cons "params" '())))
                        invalid-public-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 46)
                               (cons "method" "web3_clientVersion")
                               (cons "params" '())))
                        public-client-version-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 47)
                               (cons "method" "net_version")
                               (cons "params" '())))
                        public-net-version-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 48)
                               (cons "method" "net_listening")
                               (cons "params" '())))
                        public-net-listening-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 49)
                               (cons "method" "eth_syncing")
                               (cons "params" '())))
                        public-syncing-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 53)
                               (cons "method" "net_peerCount")
                               (cons "params" '())))
                        public-net-peer-count-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 54)
                               (cons "method" "eth_accounts")
                               (cons "params" '())))
                        public-accounts-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 55)
                               (cons "method" "eth_coinbase")
                               (cons "params" '())))
                        public-coinbase-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 56)
                               (cons "method" "eth_mining")
                               (cons "params" '())))
                        public-mining-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 57)
                               (cons "method" "eth_hashrate")
                               (cons "params" '())))
                        public-hashrate-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 58)
                               (cons "method" "rpc_modules")
                               (cons "params" '())))
                        public-rpc-modules-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 59)
                               (cons "method" "eth_protocolVersion")
                               (cons "params" '())))
                        public-protocol-version-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 60)
                               (cons "method" "web3_sha3")
                               (cons "params" (list "0x68656c6c6f"))))
                        public-web3-sha3-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 61)
                               (cons "method" "eth_gasPrice")
                               (cons "params" '())))
                        public-gas-price-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 62)
                               (cons "method" "eth_maxPriorityFeePerGas")
                               (cons "params" '())))
                        public-priority-fee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 63)
                               (cons "method" "eth_baseFee")
                               (cons "params" '())))
                        public-base-fee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 64)
                               (cons "method" "eth_blobBaseFee")
                               (cons "params" '())))
                        public-blob-base-fee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 65)
                               (cons "method" "eth_feeHistory")
                               (cons "params" (list "0x1" "latest" '()))))
                        public-fee-history-output)
                       (cons
                        (json-encode
                         (list
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 50)
                                (cons "method" "eth_chainId")
                                (cons "params" '()))
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 51)
                                (cons "method" "net_version")
                                (cons "params" '()))
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 52)
                                (cons "method" "web3_clientVersion")
                                (cons "params" '()))))
                        public-batch-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 45)
                               (cons "method" "engine_exchangeCapabilities")
                               (cons "params" (list '()))))
                        public-engine-namespace-output)
                       (cons "{" public-malformed-json-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 66)
                               (cons "method"
                                     "eth_newPendingTransactionFilter")
                               (cons "params" '())))
                        new-pending-filter-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 36)
                               (cons "method" "eth_sendRawTransaction")
                               (cons "params"
                                     (list pending-transaction-raw))))
                        send-raw-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 37)
                               (cons "method" "eth_sendRawTransaction")
                               (cons "params"
                                     (list basefee-transaction-raw))))
                        send-basefee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 38)
                               (cons "method" "eth_sendRawTransaction")
                               (cons "params"
                                     (list queued-transaction-raw))))
                        send-queued-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 77)
                               (cons "method" "eth_blockNumber")
                               (cons "params" '())))
                        txpool-rejournal-output)
                       (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 67)
                              (cons "method" "eth_getFilterChanges")
                              (cons "params" (list "0x1"))))
                        pending-filter-changes-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 68)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list "0x1"))))
                        empty-pending-filter-changes-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 69)
                               (cons "method" "eth_uninstallFilter")
                               (cons "params" (list "0x1"))))
                        uninstall-pending-filter-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 70)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list "0x1"))))
                        removed-pending-filter-changes-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 39)
                               (cons "method" "eth_getRawTransactionByHash")
                               (cons "params"
                                     (list pending-transaction-hash-hex))))
                        raw-pending-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 40)
                               (cons "method" "eth_getRawTransactionByHash")
                               (cons "params"
                                     (list basefee-transaction-hash-hex))))
                        raw-basefee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 41)
                               (cons "method" "eth_getRawTransactionByHash")
                               (cons "params"
                                     (list queued-transaction-hash-hex))))
                        raw-queued-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 46)
                               (cons "method" "eth_getTransactionCount")
                               (cons "params"
                                     (list pending-transaction-sender-hex
                                           "pending"))))
                        pending-nonce-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 74)
                               (cons "method" "eth_getBlockReceipts")
                               (cons "params" (list "pending"))))
                        pending-block-receipts-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 75)
                               (cons "method"
                                     "eth_getUncleCountByBlockNumber")
                               (cons "params" (list "pending"))))
                        pending-uncle-count-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 76)
                               (cons "method" "eth_getLogs")
                               (cons "params"
                                     (list
                                      (list
                                       (cons "fromBlock" "pending")
                                       (cons "toBlock" "pending"))))))
                        pending-logs-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 42)
                               (cons "method" "txpool_status")
                               (cons "params" '())))
                        txpool-status-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 43)
                               (cons "method" "txpool_contentFrom")
                               (cons "params"
                                     (list pending-transaction-sender-hex))))
                        txpool-content-from-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 44)
                               (cons "method" "txpool_inspect")
                               (cons "params" '())))
                        txpool-inspect-output))))
                  (engine-served-count 0)
                  (unauthenticated-engine-served-p nil)
                  (invalid-auth-engine-served-p nil)
                  (duplicate-auth-engine-served-p nil)
                  (engine-root-wrong-path-served-p nil)
                  (engine-pre-txpool-done-p nil)
                  (engine-prepared-txpool-done-p nil)
                  (engine-replacement-prepared-txpool-done-p nil)
                  (engine-done-p nil)
                  (public-served-count 0)
                  (public-txpool-done-p nil)
                  (post-prepared-txpool-content-served-p nil)
                  (replacement-send-served-p nil)
                  (post-replacement-txpool-content-served-p nil)
                  (post-import-public-requests
                    (list
                     (cons :txpool-import-transaction
                           post-import-transaction-output)
                     (cons :txpool-import-receipt
                           post-import-receipt-output)
                     (cons :txpool-import-raw
                           post-import-raw-output)
                     (cons :txpool-import-block
                           post-import-block-output)
                     (cons :txpool-import-status
                           post-import-txpool-status-output)
                     (cons :txpool-import-content-from
                           post-import-txpool-content-from-output)))
                  (public-root-wrong-path-served-p nil))
             (devnet-cli-set-node-store-config node store config)
             (engine-payload-store-put-block
              store parent-block :state-available-p t)
             (commit-state-db-to-chain-store
              store (block-hash parent-block) parent-state)
             (when pid-file
               (ethereum-lisp.cli::devnet-cli-write-pid-file pid-file))
             (let ((summary
                     (ethereum-lisp.cli:start-devnet-node-listeners
                      node
                      (make-engine-rpc-http-listener
                       :endpoint +devnet-smoke-gate-engine-endpoint+
                       :accept-function
                       (lambda ()
                         (cond
                           ((not unauthenticated-engine-served-p)
                            (setf unauthenticated-engine-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 20)
                                 (cons "method"
                                       "engine_getClientVersionV1")
                                 (cons "params" (list '()))))))
                             :output-stream unauthenticated-engine-output
                             :close-function
                             (lambda ()
                               (incf engine-served-count))))
                           ((not invalid-auth-engine-served-p)
                            (setf invalid-auth-engine-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 26)
                                 (cons "method"
                                       "engine_getClientVersionV1")
                                 (cons "params" (list '()))))
                               :token invalid-token))
                             :output-stream invalid-auth-engine-output
                             :close-function
                             (lambda ()
                               (incf engine-served-count))))
                           ((not duplicate-auth-engine-served-p)
                            (setf duplicate-auth-engine-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-duplicate-auth-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 45)
                                 (cons "method"
                                       "engine_getClientVersionV1")
                                 (cons "params" (list '()))))
                               token invalid-token))
                             :output-stream duplicate-auth-engine-output
                             :close-function
                             (lambda ()
                               (incf engine-served-count))))
                           ((not engine-root-wrong-path-served-p)
                            (setf engine-root-wrong-path-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 72)
                                 (cons "method"
                                       "engine_getClientVersionV1")
                                 (cons "params" (list '()))))
                               :token token
                               :target "/unexpected"))
                             :output-stream engine-root-wrong-path-output
                             :close-function
                             (lambda ()
                               (incf engine-served-count))))
                           (engine-requests
                            (destructuring-bind (body . output)
                                (pop engine-requests)
                             (make-engine-rpc-http-connection
                              :input-stream
                              (make-string-input-stream
                               (devnet-cli-json-rpc-http-request
                                body :token token))
                              :output-stream output
                              :close-function
                              (lambda ()
                                (incf engine-served-count)
                                (unless engine-requests
                                  (setf engine-pre-txpool-done-p t))))))
                           (post-public-engine-requests
                            (loop until public-txpool-done-p
                                  do (sleep 0.001))
                            (destructuring-bind (body . output)
                                (pop post-public-engine-requests)
                              (let ((request-body
                                      (if (eq body :txpool-get-payload)
                                          (json-encode
                                           (list
                                            (cons "jsonrpc" "2.0")
                                            (cons "id" 79)
                                            (cons "method"
                                                  "engine_getPayloadV2")
                                            (cons "params"
                                                  (list
                                                   post-public-txpool-payload-id))))
                                          body)))
                                (make-engine-rpc-http-connection
                                 :input-stream
                                 (make-string-input-stream
                                  (devnet-cli-json-rpc-http-request
                                   request-body :token token))
                                 :output-stream output
                                 :close-function
                                 (lambda ()
                                   (incf engine-served-count)
                                   (when (eq output
                                             prepare-txpool-payload-output)
                                     (setf
                                      prepare-txpool-payload-response-cache
                                      (get-output-stream-string
                                       prepare-txpool-payload-output)
                                      post-public-txpool-payload-id
                                      (fixture-object-field
                                       (fixture-object-field
                                        (devnet-smoke-gate-rpc-body
                                         prepare-txpool-payload-response-cache)
                                        "result")
                                       "payloadId")))
                                   (when (eq output
                                             get-txpool-payload-output)
                                     (setf
                                      get-txpool-payload-response-cache
                                      (get-output-stream-string
                                       get-txpool-payload-output)
                                      post-public-txpool-execution-payload
                                      (fixture-object-field
                                       (fixture-object-field
                                        (devnet-smoke-gate-rpc-body
                                         get-txpool-payload-response-cache)
                                        "result")
                                       "executionPayload")
                                      post-public-txpool-block-hash
                                      (fixture-object-field
                                       post-public-txpool-execution-payload
                                       "blockHash")))
                                   (unless post-public-engine-requests
                                     (setf
                                      engine-prepared-txpool-done-p
                                      t)))))))
                           (replacement-engine-requests
                            (loop until replacement-send-served-p
                                  do (sleep 0.001))
                            (destructuring-bind (body . output)
                                (pop replacement-engine-requests)
                              (let ((request-body
                                      (if (eq body
                                              :replacement-txpool-get-payload)
                                          (json-encode
                                           (list
                                            (cons "jsonrpc" "2.0")
                                            (cons "id" 90)
                                            (cons "method"
                                                  "engine_getPayloadV2")
                                            (cons "params"
                                                  (list
                                                   replacement-txpool-payload-id))))
                                          body)))
                                (make-engine-rpc-http-connection
                                 :input-stream
                                 (make-string-input-stream
                                  (devnet-cli-json-rpc-http-request
                                   request-body :token token))
                                 :output-stream output
                                 :close-function
                                 (lambda ()
                                   (incf engine-served-count)
                                   (when (eq output
                                             prepare-replacement-txpool-payload-output)
                                     (setf
                                      prepare-replacement-txpool-payload-response-cache
                                      (get-output-stream-string
                                       prepare-replacement-txpool-payload-output)
                                      replacement-txpool-payload-id
                                      (fixture-object-field
                                       (fixture-object-field
                                        (devnet-smoke-gate-rpc-body
                                         prepare-replacement-txpool-payload-response-cache)
                                        "result")
                                       "payloadId")))
                                   (when (eq output
                                             get-replacement-txpool-payload-output)
                                     (setf
                                      get-replacement-txpool-payload-response-cache
                                      (get-output-stream-string
                                       get-replacement-txpool-payload-output)
                                      replacement-txpool-execution-payload
                                      (fixture-object-field
                                       (fixture-object-field
                                        (devnet-smoke-gate-rpc-body
                                         get-replacement-txpool-payload-response-cache)
                                        "result")
                                       "executionPayload")
                                      replacement-txpool-block-hash
                                      (fixture-object-field
                                       replacement-txpool-execution-payload
                                       "blockHash")))
                                   (unless replacement-engine-requests
                                     (setf
                                      engine-replacement-prepared-txpool-done-p
                                      t)))))))
                           (post-prepared-engine-requests
                            (loop until post-replacement-txpool-content-served-p
                                  do (sleep 0.001))
                            (destructuring-bind (body . output)
                                (pop post-prepared-engine-requests)
                              (let ((request-body
                                      (cond
                                        ((eq body :txpool-new-payload)
                                         (devnet-smoke-gate-json-rpc-request
                                          81
                                          "engine_newPayloadV2"
                                          (list
                                           replacement-txpool-execution-payload)))
                                        ((eq body :txpool-forkchoice)
                                         (json-encode
                                          (devnet-cli-engine-forkchoice-v2-request
                                           82
                                           (hash32-from-hex
                                            replacement-txpool-block-hash)
                                           :safe (block-hash parent-block)
                                           :finalized
                                           (block-hash parent-block))))
                                        (t body))))
                                (make-engine-rpc-http-connection
                                 :input-stream
                                 (make-string-input-stream
                                  (devnet-cli-json-rpc-http-request
                                   request-body :token token))
                                 :output-stream output
                                 :close-function
                                 (lambda ()
                                   (incf engine-served-count)
                                   (unless post-prepared-engine-requests
                                     (setf engine-done-p t)))))))))
                       :close-function (lambda () nil))
                      (make-engine-rpc-http-listener
                       :endpoint +devnet-smoke-gate-public-endpoint+
                       :accept-function
                       (lambda ()
                         (loop until engine-pre-txpool-done-p
                               do (sleep 0.001))
                         (cond
                           ((not public-root-wrong-path-served-p)
                            (setf public-root-wrong-path-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 73)
                                 (cons "method" "eth_chainId")
                                 (cons "params" '())))
                               :target "/unexpected"))
                             :output-stream public-root-wrong-path-output
                             :close-function
                             (lambda () (incf public-served-count))))
                           (public-requests
                            (destructuring-bind (body . output)
                                (pop public-requests)
                              (when (eq output txpool-rejournal-output)
                                (setf txpool-rejournal-report
                                      (devnet-smoke-gate-wait-for-txpool-journal-record
                                       journal-path
                                       pending-transaction-hash-hex
                                       pending-transaction-raw
                                       5
                                       :expected-record-count 3)))
                              (make-engine-rpc-http-connection
                               :input-stream
                               (make-string-input-stream
                                (devnet-cli-json-rpc-http-request body))
                               :output-stream output
                               :close-function
                               (lambda () (incf public-served-count)))))
                           ((not post-prepared-txpool-content-served-p)
                            (setf public-txpool-done-p t)
                            (loop until engine-prepared-txpool-done-p
                                  do (sleep 0.001))
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list (cons "jsonrpc" "2.0")
                                      (cons "id" 80)
                                      (cons "method" "txpool_contentFrom")
                                      (cons "params"
                                            (list pending-transaction-sender-hex))))))
                             :output-stream
                             post-prepared-txpool-content-from-output
                             :close-function
                             (lambda ()
                               (incf public-served-count)
                               (setf
                                post-prepared-txpool-content-served-p
                                t))))
                           ((not replacement-send-served-p)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list (cons "jsonrpc" "2.0")
                                      (cons "id" 91)
                                      (cons "method"
                                            "eth_sendRawTransaction")
                                      (cons "params"
                                            (list replacement-transaction-raw))))))
                             :output-stream send-replacement-output
                             :close-function
                             (lambda ()
                               (incf public-served-count)
                               (setf replacement-send-served-p t))))
                           ((not post-replacement-txpool-content-served-p)
                            (loop until engine-replacement-prepared-txpool-done-p
                                  do (sleep 0.001))
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list (cons "jsonrpc" "2.0")
                                      (cons "id" 92)
                                      (cons "method" "txpool_contentFrom")
                                      (cons "params"
                                            (list pending-transaction-sender-hex))))))
                             :output-stream
                             post-replacement-txpool-content-from-output
                             :close-function
                             (lambda ()
                               (incf public-served-count)
                               (setf
                                post-replacement-txpool-content-served-p
                                t))))
                           (post-import-public-requests
                            (loop until engine-done-p
                                  do (sleep 0.001))
                            (destructuring-bind (body . output)
                                (pop post-import-public-requests)
                              (let ((request-body
                                      (case body
                                        (:txpool-import-transaction
                                         (devnet-smoke-gate-json-rpc-request
                                          83
                                          "eth_getTransactionByHash"
                                          (list replacement-transaction-hash-hex)))
                                        (:txpool-import-receipt
                                         (devnet-smoke-gate-json-rpc-request
                                          84
                                          "eth_getTransactionReceipt"
                                          (list replacement-transaction-hash-hex)))
                                        (:txpool-import-raw
                                         (devnet-smoke-gate-json-rpc-request
                                          85
                                          "eth_getRawTransactionByHash"
                                          (list replacement-transaction-hash-hex)))
                                        (:txpool-import-block
                                         (devnet-smoke-gate-json-rpc-request
                                          86
                                          "eth_getBlockByHash"
                                          (list replacement-txpool-block-hash
                                                :false)))
                                        (:txpool-import-status
                                         (devnet-smoke-gate-json-rpc-request
                                          87
                                          "txpool_status"
                                          '()))
                                        (:txpool-import-content-from
                                         (devnet-smoke-gate-json-rpc-request
                                          88
                                          "txpool_contentFrom"
                                          (list pending-transaction-sender-hex)))
                                        (otherwise body))))
                                (make-engine-rpc-http-connection
                                 :input-stream
                                 (make-string-input-stream
                                  (devnet-cli-json-rpc-http-request
                                   request-body))
                                 :output-stream output
                                 :close-function
                                 (lambda ()
                                   (incf public-served-count))))))))
                      :close-function (lambda () nil))
                      :max-connections
                      +devnet-smoke-gate-public-connections+
                      :on-listeners-ready
                      (lambda (engine-listener public-listener)
                        (let ((engine-endpoint
                                (engine-rpc-http-listener-endpoint
                                 engine-listener))
                              (rpc-endpoint
                                (engine-rpc-http-listener-endpoint
                                 public-listener)))
                          (when ready-file
                            (ethereum-lisp.cli::devnet-cli-write-ready-file
                             node
                             ready-file
                             :engine-endpoint engine-endpoint
                             :rpc-endpoint rpc-endpoint))
                          (when log-file
                            (ethereum-lisp.cli::devnet-cli-log-event
                             node
                             "devnet.ready"
                            :engine-endpoint engine-endpoint
                            :rpc-endpoint rpc-endpoint)))))))
               (devnet-smoke-gate-require
                (= +devnet-smoke-gate-engine-connections+
                   (getf summary :engine-connections))
                "Devnet smoke gate Engine connection count mismatch")
               (devnet-smoke-gate-require
                (= +devnet-smoke-gate-public-connections+
                   (getf summary :public-connections))
                "Devnet smoke gate public connection count mismatch")
               (devnet-smoke-gate-require
                (= +devnet-smoke-gate-total-connections+
                   (getf summary :total-connections))
                "Devnet smoke gate total connection count mismatch")
               (when log-file
                 (ethereum-lisp.cli::devnet-cli-log-event
                  node
                  "devnet.shutdown"
                  :engine-endpoint +devnet-smoke-gate-engine-endpoint+
                  :rpc-endpoint +devnet-smoke-gate-public-endpoint+
                  :connection-summary summary))
               (let* ((capabilities-response
                        (get-output-stream-string capabilities-output))
                      (client-version-response
                        (get-output-stream-string client-version-output))
                      (transition-configuration-response
                        (get-output-stream-string
                         transition-configuration-output))
                      (transition-configuration-mismatch-response
                        (get-output-stream-string
                         transition-configuration-mismatch-output))
                      (engine-public-namespace-response
                        (get-output-stream-string
                         engine-public-namespace-output))
                      (new-payload-response
                        (get-output-stream-string new-payload-output))
                      (unauthenticated-engine-response
                        (get-output-stream-string
                         unauthenticated-engine-output))
                      (invalid-auth-engine-response
                        (get-output-stream-string
                         invalid-auth-engine-output))
                      (duplicate-auth-engine-response
                        (get-output-stream-string
                         duplicate-auth-engine-output))
                      (engine-root-wrong-path-response
                        (get-output-stream-string
                         engine-root-wrong-path-output))
                      (forkchoice-response
                        (get-output-stream-string forkchoice-output))
                      (payload-bodies-by-hash-response
                        (get-output-stream-string
                         payload-bodies-by-hash-output))
                      (payload-bodies-by-range-response
                        (get-output-stream-string
                         payload-bodies-by-range-output))
                      (prepare-payload-response
                        (get-output-stream-string prepare-payload-output))
                      (get-payload-response
                        (get-output-stream-string get-payload-output))
                      (prepare-txpool-payload-response
                        (or prepare-txpool-payload-response-cache
                            (get-output-stream-string
                             prepare-txpool-payload-output)))
                      (get-txpool-payload-response
                        (or get-txpool-payload-response-cache
                            (get-output-stream-string
                             get-txpool-payload-output)))
                      (import-txpool-payload-response
                        (get-output-stream-string
                         import-txpool-payload-output))
                      (forkchoice-txpool-payload-response
                        (get-output-stream-string
                         forkchoice-txpool-payload-output))
                      (remote-payload-response
                        (get-output-stream-string remote-payload-output))
                      (invalid-payload-response
                        (get-output-stream-string invalid-payload-output))
                      (block-number-response
                        (get-output-stream-string block-number-output))
                      (balance-response
                        (get-output-stream-string balance-output))
                      (prepared-public-response
                        (get-output-stream-string prepared-public-output))
                      (remote-public-response
                        (get-output-stream-string remote-public-output))
                      (invalid-public-response
                        (get-output-stream-string invalid-public-output))
                      (public-client-version-response
                        (get-output-stream-string
                         public-client-version-output))
                      (public-net-version-response
                        (get-output-stream-string public-net-version-output))
                      (public-net-listening-response
                        (get-output-stream-string
                         public-net-listening-output))
                      (public-syncing-response
                        (get-output-stream-string public-syncing-output))
                      (public-net-peer-count-response
                        (get-output-stream-string
                         public-net-peer-count-output))
                      (public-accounts-response
                        (get-output-stream-string public-accounts-output))
                      (public-coinbase-response
                        (get-output-stream-string public-coinbase-output))
                      (public-mining-response
                        (get-output-stream-string public-mining-output))
                      (public-hashrate-response
                        (get-output-stream-string public-hashrate-output))
                      (public-rpc-modules-response
                        (get-output-stream-string
                         public-rpc-modules-output))
                      (public-protocol-version-response
                        (get-output-stream-string
                         public-protocol-version-output))
                      (public-web3-sha3-response
                        (get-output-stream-string public-web3-sha3-output))
                      (public-gas-price-response
                        (get-output-stream-string public-gas-price-output))
                      (public-priority-fee-response
                        (get-output-stream-string public-priority-fee-output))
                      (public-base-fee-response
                        (get-output-stream-string public-base-fee-output))
                      (public-blob-base-fee-response
                        (get-output-stream-string public-blob-base-fee-output))
                      (public-fee-history-response
                        (get-output-stream-string public-fee-history-output))
                      (public-batch-response
                        (get-output-stream-string public-batch-output))
                      (public-engine-namespace-response
                        (get-output-stream-string
                         public-engine-namespace-output))
                      (public-malformed-json-response
                        (get-output-stream-string
                         public-malformed-json-output))
                      (public-root-wrong-path-response
                        (get-output-stream-string
                         public-root-wrong-path-output))
                      (new-pending-filter-response
                        (get-output-stream-string new-pending-filter-output))
                      (pending-filter-changes-response
                        (get-output-stream-string
                         pending-filter-changes-output))
                      (empty-pending-filter-changes-response
                        (get-output-stream-string
                         empty-pending-filter-changes-output))
                      (uninstall-pending-filter-response
                        (get-output-stream-string
                         uninstall-pending-filter-output))
                      (removed-pending-filter-changes-response
                        (get-output-stream-string
                         removed-pending-filter-changes-output))
                      (send-raw-response
                        (get-output-stream-string send-raw-output))
                      (send-basefee-response
                        (get-output-stream-string send-basefee-output))
                      (send-queued-response
                        (get-output-stream-string send-queued-output))
                      (send-replacement-response
                        (get-output-stream-string send-replacement-output))
                      (txpool-rejournal-response
                        (get-output-stream-string txpool-rejournal-output))
                      (raw-pending-response
                        (get-output-stream-string raw-pending-output))
                      (raw-basefee-response
                        (get-output-stream-string raw-basefee-output))
                      (raw-queued-response
                        (get-output-stream-string raw-queued-output))
                      (pending-nonce-response
                        (get-output-stream-string pending-nonce-output))
                      (pending-block-receipts-response
                        (get-output-stream-string
                         pending-block-receipts-output))
                      (pending-uncle-count-response
                        (get-output-stream-string pending-uncle-count-output))
                      (pending-logs-response
                        (get-output-stream-string pending-logs-output))
                      (txpool-status-response
                        (get-output-stream-string txpool-status-output))
                      (txpool-content-from-response
                        (get-output-stream-string
                         txpool-content-from-output))
                      (txpool-inspect-response
                        (get-output-stream-string txpool-inspect-output))
                      (post-prepared-txpool-content-from-response
                        (get-output-stream-string
                         post-prepared-txpool-content-from-output))
                      (prepare-replacement-txpool-payload-response
                        (or prepare-replacement-txpool-payload-response-cache
                            (get-output-stream-string
                             prepare-replacement-txpool-payload-output)))
                      (get-replacement-txpool-payload-response
                        (or get-replacement-txpool-payload-response-cache
                            (get-output-stream-string
                             get-replacement-txpool-payload-output)))
                      (post-replacement-txpool-content-from-response
                        (get-output-stream-string
                         post-replacement-txpool-content-from-output))
                      (post-import-transaction-response
                        (get-output-stream-string
                         post-import-transaction-output))
                      (post-import-receipt-response
                        (get-output-stream-string
                         post-import-receipt-output))
                      (post-import-raw-response
                        (get-output-stream-string
                         post-import-raw-output))
                      (post-import-block-response
                        (get-output-stream-string
                         post-import-block-output))
                      (post-import-txpool-status-response
                        (get-output-stream-string
                         post-import-txpool-status-output))
                      (post-import-txpool-content-from-response
                        (get-output-stream-string
                         post-import-txpool-content-from-output))
                      (capabilities-rpc
                        (devnet-smoke-gate-rpc-body capabilities-response))
                      (client-version-rpc
                        (devnet-smoke-gate-rpc-body
                         client-version-response))
                      (transition-configuration-rpc
                        (devnet-smoke-gate-rpc-body
                         transition-configuration-response))
                      (transition-configuration-mismatch-rpc
                        (devnet-smoke-gate-rpc-body
                         transition-configuration-mismatch-response))
                      (engine-public-namespace-rpc
                        (devnet-smoke-gate-rpc-body
                         engine-public-namespace-response))
                      (new-payload-rpc
                        (devnet-smoke-gate-rpc-body new-payload-response))
                      (forkchoice-rpc
                        (devnet-smoke-gate-rpc-body forkchoice-response))
                      (payload-bodies-by-hash-rpc
                        (devnet-smoke-gate-rpc-body
                         payload-bodies-by-hash-response))
                      (payload-bodies-by-range-rpc
                        (devnet-smoke-gate-rpc-body
                         payload-bodies-by-range-response))
                      (prepare-payload-rpc
                        (devnet-smoke-gate-rpc-body prepare-payload-response))
                      (get-payload-rpc
                        (devnet-smoke-gate-rpc-body get-payload-response))
                      (prepare-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         prepare-txpool-payload-response))
                      (get-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         get-txpool-payload-response))
                      (import-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         import-txpool-payload-response))
                      (forkchoice-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         forkchoice-txpool-payload-response))
                      (remote-payload-rpc
                        (devnet-smoke-gate-rpc-body remote-payload-response))
                      (invalid-payload-rpc
                        (devnet-smoke-gate-rpc-body invalid-payload-response))
                      (block-number-rpc
                        (devnet-smoke-gate-rpc-body block-number-response))
                      (balance-rpc
                        (devnet-smoke-gate-rpc-body balance-response))
                      (prepared-public-rpc
                        (devnet-smoke-gate-rpc-body prepared-public-response))
                      (remote-public-rpc
                        (devnet-smoke-gate-rpc-body remote-public-response))
                      (invalid-public-rpc
                        (devnet-smoke-gate-rpc-body invalid-public-response))
                      (public-client-version-rpc
                        (devnet-smoke-gate-rpc-body
                         public-client-version-response))
                      (public-net-version-rpc
                        (devnet-smoke-gate-rpc-body
                         public-net-version-response))
                      (public-net-listening-rpc
                        (devnet-smoke-gate-rpc-body
                         public-net-listening-response))
                      (public-syncing-rpc
                        (devnet-smoke-gate-rpc-body public-syncing-response))
                      (public-net-peer-count-rpc
                        (devnet-smoke-gate-rpc-body
                         public-net-peer-count-response))
                      (public-accounts-rpc
                        (devnet-smoke-gate-rpc-body public-accounts-response))
                      (public-coinbase-rpc
                        (devnet-smoke-gate-rpc-body public-coinbase-response))
                      (public-mining-rpc
                        (devnet-smoke-gate-rpc-body public-mining-response))
                      (public-hashrate-rpc
                        (devnet-smoke-gate-rpc-body public-hashrate-response))
                      (public-rpc-modules-rpc
                        (devnet-smoke-gate-rpc-body
                         public-rpc-modules-response))
                      (public-rpc-modules
                        (fixture-object-field public-rpc-modules-rpc
                                              "result"))
                      (public-protocol-version-rpc
                        (devnet-smoke-gate-rpc-body
                         public-protocol-version-response))
                      (public-web3-sha3-rpc
                        (devnet-smoke-gate-rpc-body
                         public-web3-sha3-response))
                      (public-gas-price-rpc
                        (devnet-smoke-gate-rpc-body public-gas-price-response))
                      (public-priority-fee-rpc
                        (devnet-smoke-gate-rpc-body
                         public-priority-fee-response))
                      (public-base-fee-rpc
                        (devnet-smoke-gate-rpc-body public-base-fee-response))
                      (public-blob-base-fee-rpc
                        (devnet-smoke-gate-rpc-body
                         public-blob-base-fee-response))
                      (public-fee-history-rpc
                        (devnet-smoke-gate-rpc-body
                         public-fee-history-response))
                      (public-fee-history
                        (fixture-object-field public-fee-history-rpc
                                              "result"))
                      (public-batch-rpc
                        (devnet-smoke-gate-rpc-body public-batch-response))
                      (public-batch-chain-id-rpc (first public-batch-rpc))
                      (public-batch-network-rpc (second public-batch-rpc))
                      (public-batch-client-version-rpc (third public-batch-rpc))
                      (public-engine-namespace-rpc
                        (devnet-smoke-gate-rpc-body
                         public-engine-namespace-response))
                      (public-malformed-json-rpc
                        (devnet-smoke-gate-rpc-body
                         public-malformed-json-response))
                      (new-pending-filter-rpc
                        (devnet-smoke-gate-rpc-body
                         new-pending-filter-response))
                      (pending-filter-changes-rpc
                        (devnet-smoke-gate-rpc-body
                         pending-filter-changes-response))
                      (empty-pending-filter-changes-rpc
                        (devnet-smoke-gate-rpc-body
                         empty-pending-filter-changes-response
                         :preserve-empty-arrays t))
                      (uninstall-pending-filter-rpc
                        (devnet-smoke-gate-rpc-body
                         uninstall-pending-filter-response))
                      (removed-pending-filter-changes-rpc
                        (devnet-smoke-gate-rpc-body
                         removed-pending-filter-changes-response))
                      (send-raw-rpc
                        (devnet-smoke-gate-rpc-body send-raw-response))
                      (send-basefee-rpc
                        (devnet-smoke-gate-rpc-body send-basefee-response))
                      (send-queued-rpc
                        (devnet-smoke-gate-rpc-body send-queued-response))
                      (send-replacement-rpc
                        (devnet-smoke-gate-rpc-body
                         send-replacement-response))
                      (txpool-rejournal-rpc
                        (devnet-smoke-gate-rpc-body
                         txpool-rejournal-response))
                      (raw-pending-rpc
                        (devnet-smoke-gate-rpc-body raw-pending-response))
                      (raw-basefee-rpc
                        (devnet-smoke-gate-rpc-body raw-basefee-response))
                      (raw-queued-rpc
                        (devnet-smoke-gate-rpc-body raw-queued-response))
                      (pending-nonce-rpc
                        (devnet-smoke-gate-rpc-body pending-nonce-response))
                      (pending-block-receipts-rpc
                        (devnet-smoke-gate-rpc-body
                         pending-block-receipts-response))
                      (pending-uncle-count-rpc
                        (devnet-smoke-gate-rpc-body
                         pending-uncle-count-response))
                      (pending-logs-rpc
                        (devnet-smoke-gate-rpc-body
                         pending-logs-response
                         :preserve-empty-arrays t))
                      (txpool-status-rpc
                        (devnet-smoke-gate-rpc-body txpool-status-response))
                      (txpool-content-from-rpc
                        (devnet-smoke-gate-rpc-body
                         txpool-content-from-response))
                      (txpool-inspect-rpc
                        (devnet-smoke-gate-rpc-body txpool-inspect-response))
                      (post-prepared-txpool-content-from-rpc
                        (devnet-smoke-gate-rpc-body
                         post-prepared-txpool-content-from-response))
                      (prepare-replacement-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         prepare-replacement-txpool-payload-response))
                      (get-replacement-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         get-replacement-txpool-payload-response))
                      (post-replacement-txpool-content-from-rpc
                        (devnet-smoke-gate-rpc-body
                         post-replacement-txpool-content-from-response))
                      (post-import-transaction-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-transaction-response))
                      (post-import-receipt-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-receipt-response))
                      (post-import-raw-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-raw-response))
                      (post-import-block-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-block-response))
                      (post-import-txpool-status-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-txpool-status-response))
                      (post-import-txpool-content-from-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-txpool-content-from-response))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (client-version-result
                        (first (fixture-object-field
                                client-version-rpc "result")))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error"))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (payload-bodies-by-hash-result
                        (fixture-object-field
                         payload-bodies-by-hash-rpc "result"))
                      (payload-bodies-by-range-result
                        (fixture-object-field
                         payload-bodies-by-range-rpc "result"))
                      (payload-body-by-hash
                        (first payload-bodies-by-hash-result))
                      (payload-body-by-range
                        (first payload-bodies-by-range-result))
                      (payload-body-by-hash-transactions
                        (fixture-object-field
                         payload-body-by-hash "transactions"))
                      (payload-body-by-range-transactions
                        (fixture-object-field
                         payload-body-by-range "transactions"))
                      (expected-payload-body-transaction-count
                        (length (block-transactions child-block)))
                      (prepare-payload-result
                        (fixture-object-field prepare-payload-rpc "result"))
                      (prepare-payload-status
                        (fixture-object-field
                         prepare-payload-result
                         "payloadStatus"))
                      (prepared-payload-id
                        (fixture-object-field
                         prepare-payload-result
                         "payloadId"))
                      (get-payload-result
                        (fixture-object-field get-payload-rpc "result"))
                      (get-payload-execution-payload
                        (fixture-object-field
                         get-payload-result
                         "executionPayload"))
                      (get-payload-transactions
                        (fixture-object-field
                         get-payload-execution-payload
                         "transactions"))
                      (prepare-txpool-payload-result
                        (fixture-object-field prepare-txpool-payload-rpc
                                              "result"))
                      (prepare-txpool-payload-status
                        (fixture-object-field
                         prepare-txpool-payload-result
                         "payloadStatus"))
                      (prepared-txpool-payload-id
                        (fixture-object-field
                         prepare-txpool-payload-result
                         "payloadId"))
                      (get-txpool-payload-result
                        (fixture-object-field get-txpool-payload-rpc
                                              "result"))
                      (get-txpool-payload-execution-payload
                        (fixture-object-field
                         get-txpool-payload-result
                         "executionPayload"))
                      (get-txpool-payload-transactions
                        (fixture-object-field
                         get-txpool-payload-execution-payload
                         "transactions"))
                      (txpool-payload-block-hash
                        (fixture-object-field
                         get-txpool-payload-execution-payload
                         "blockHash"))
                      (prepare-replacement-txpool-payload-result
                        (fixture-object-field
                         prepare-replacement-txpool-payload-rpc
                         "result"))
                      (prepare-replacement-txpool-payload-status
                        (fixture-object-field
                         prepare-replacement-txpool-payload-result
                         "payloadStatus"))
                      (prepared-replacement-txpool-payload-id
                        (fixture-object-field
                         prepare-replacement-txpool-payload-result
                         "payloadId"))
                      (get-replacement-txpool-payload-result
                        (fixture-object-field
                         get-replacement-txpool-payload-rpc
                         "result"))
                      (get-replacement-txpool-payload-execution-payload
                        (fixture-object-field
                         get-replacement-txpool-payload-result
                         "executionPayload"))
                      (get-replacement-txpool-payload-transactions
                        (fixture-object-field
                         get-replacement-txpool-payload-execution-payload
                         "transactions"))
                      (import-txpool-payload-result
                        (fixture-object-field import-txpool-payload-rpc
                                              "result"))
                      (forkchoice-txpool-payload-status
                        (fixture-object-field
                         (fixture-object-field
                          forkchoice-txpool-payload-rpc "result")
                         "payloadStatus"))
                      (remote-payload-result
                        (fixture-object-field remote-payload-rpc "result"))
                      (invalid-payload-result
                        (fixture-object-field invalid-payload-rpc "result"))
                      (expected-hash
                        (hash32-to-hex (block-hash child-block)))
                      (expected-remote-block-hash
                        (hash32-to-hex (block-hash remote-block)))
                      (expected-invalid-block-hash
                        (hash32-to-hex (block-hash invalid-block)))
                      (expected-gas-price
                        (quantity-to-hex
                         (or (block-header-base-fee-per-gas
                              (block-header child-block))
                             0)))
                      (expected-next-base-fee
                        (quantity-to-hex
                         (expected-base-fee-per-gas
                          (block-header child-block)
                          :london-parent-p
                          (not (null
                                (block-header-base-fee-per-gas
                                 (block-header child-block)))))))
                      (txpool-status
                        (fixture-object-field txpool-status-rpc "result"))
                      (pending-filter-id
                        (fixture-object-field new-pending-filter-rpc
                                              "result"))
                      (pending-filter-changes
                        (fixture-object-field pending-filter-changes-rpc
                                              "result"))
                      (empty-pending-filter-changes
                        (fixture-object-field
                         empty-pending-filter-changes-rpc
                         "result"))
                      (removed-pending-filter-error
                        (fixture-object-field
                         removed-pending-filter-changes-rpc
                         "error"))
                      (txpool-content-from
                        (fixture-object-field
                         txpool-content-from-rpc "result"))
                      (txpool-content-from-pending
                        (fixture-object-field
                         txpool-content-from "pending"))
                      (txpool-content-from-transaction
                        (fixture-object-field
                         txpool-content-from-pending
                         pending-transaction-nonce-key))
                      (txpool-content-from-queued
                        (fixture-object-field
                         txpool-content-from "queued"))
                      (txpool-content-from-basefee-transaction
                        (fixture-object-field
                         txpool-content-from-queued
                         basefee-transaction-nonce-key))
                      (txpool-content-from-queued-transaction
                        (fixture-object-field
                         txpool-content-from-queued
                         queued-transaction-nonce-key))
                      (txpool-inspect
                        (fixture-object-field txpool-inspect-rpc "result"))
                      (txpool-inspect-pending
                        (fixture-object-field txpool-inspect "pending"))
                      (txpool-inspect-sender
                        (fixture-object-field
                         txpool-inspect-pending
                         pending-transaction-sender-hex))
                      (txpool-inspect-transaction
                        (fixture-object-field
                         txpool-inspect-sender
                         pending-transaction-nonce-key))
                      (txpool-inspect-queued
                        (fixture-object-field txpool-inspect "queued"))
                      (txpool-inspect-queued-sender
                        (fixture-object-field
                         txpool-inspect-queued
                         pending-transaction-sender-hex))
                      (txpool-inspect-basefee-transaction
                        (fixture-object-field
                         txpool-inspect-queued-sender
                         basefee-transaction-nonce-key))
                      (txpool-inspect-queued-transaction
                        (fixture-object-field
                         txpool-inspect-queued-sender
                         queued-transaction-nonce-key))
                      (post-prepared-txpool-content-from
                        (fixture-object-field
                         post-prepared-txpool-content-from-rpc "result"))
                      (post-prepared-txpool-content-from-pending
                        (fixture-object-field
                         post-prepared-txpool-content-from "pending"))
                      (post-prepared-txpool-content-from-transaction
                        (fixture-object-field
                         post-prepared-txpool-content-from-pending
                         pending-transaction-nonce-key))
                      (post-prepared-txpool-content-from-queued
                        (fixture-object-field
                         post-prepared-txpool-content-from "queued"))
                      (post-prepared-txpool-content-from-basefee-transaction
                        (fixture-object-field
                         post-prepared-txpool-content-from-queued
                         basefee-transaction-nonce-key))
                      (post-prepared-txpool-content-from-queued-transaction
                        (fixture-object-field
                         post-prepared-txpool-content-from-queued
                         queued-transaction-nonce-key))
                      (post-replacement-txpool-content-from
                        (fixture-object-field
                         post-replacement-txpool-content-from-rpc "result"))
                      (post-replacement-txpool-content-from-pending
                        (fixture-object-field
                         post-replacement-txpool-content-from "pending"))
                      (post-replacement-txpool-content-from-transaction
                        (fixture-object-field
                         post-replacement-txpool-content-from-pending
                         pending-transaction-nonce-key))
                      (post-replacement-txpool-content-from-queued
                        (fixture-object-field
                         post-replacement-txpool-content-from "queued"))
                      (post-replacement-txpool-content-from-basefee-transaction
                        (fixture-object-field
                         post-replacement-txpool-content-from-queued
                         basefee-transaction-nonce-key))
                      (post-replacement-txpool-content-from-queued-transaction
                        (fixture-object-field
                         post-replacement-txpool-content-from-queued
                         queued-transaction-nonce-key))
                      (post-import-transaction
                        (fixture-object-field
                         post-import-transaction-rpc "result"))
                      (post-import-receipt
                        (fixture-object-field
                         post-import-receipt-rpc "result"))
                      (post-import-raw-transaction
                        (fixture-object-field
                         post-import-raw-rpc "result"))
                      (post-import-block
                        (fixture-object-field
                         post-import-block-rpc "result"))
                      (post-import-block-transactions
                        (fixture-object-field
                         post-import-block "transactions"))
                      (post-import-txpool-status
                        (fixture-object-field
                         post-import-txpool-status-rpc "result"))
                      (post-import-txpool-content-from
                        (fixture-object-field
                         post-import-txpool-content-from-rpc "result"))
                      (post-import-txpool-content-from-pending
                        (fixture-object-field
                         post-import-txpool-content-from "pending"))
                      (post-import-txpool-content-from-selected
                        (fixture-object-field
                         post-import-txpool-content-from-pending
                         pending-transaction-nonce-key))
                      (post-import-txpool-content-from-queued
                        (fixture-object-field
                         post-import-txpool-content-from "queued"))
                      (post-import-txpool-content-from-basefee-transaction
                        (fixture-object-field
                         post-import-txpool-content-from-queued
                         basefee-transaction-nonce-key))
                      (post-import-txpool-content-from-queued-transaction
                        (fixture-object-field
                         post-import-txpool-content-from-queued
                         queued-transaction-nonce-key))
                  (expected-block-number
                    (fixture-object-field payload-case "number"))
                  (expected-prepared-block-number
                    (quantity-to-hex
                     (1+ (block-header-number (block-header child-block)))))
                  (expected-safe-block-number
                    (quantity-to-hex
                     (block-header-number (block-header parent-block))))
                  (expected-safe-block-hash (block-hash parent-block))
                  (expected-finalized-block-number expected-safe-block-number)
                  (expected-finalized-block-hash expected-safe-block-hash)
                      (actual-block-number
                        (fixture-object-field block-number-rpc "result"))
                      (actual-balance
                        (fixture-object-field balance-rpc "result")))
                 (devnet-smoke-gate-require
                  (= +devnet-smoke-gate-engine-connections+
                     (getf summary :engine-connections))
                  "Expected ~D Engine connections, got ~S"
                  +devnet-smoke-gate-engine-connections+
                  (getf summary :engine-connections))
                 (devnet-smoke-gate-require
                  (= +devnet-smoke-gate-public-connections+
                     (getf summary :public-connections))
                  "Expected ~D public RPC connections, got ~S"
                  +devnet-smoke-gate-public-connections+
                  (getf summary :public-connections))
                 (devnet-smoke-gate-require
                  (= 401 (devnet-cli-http-status
                          unauthenticated-engine-response))
                  "Unauthenticated Engine request HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 401 (devnet-cli-http-status
                          invalid-auth-engine-response))
                 "Invalid-token Engine request HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 401 (devnet-cli-http-status
                          duplicate-auth-engine-response))
                  "Duplicate-authorization Engine request HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 404 (devnet-cli-http-status
                          engine-root-wrong-path-response))
                  "Engine default root wrong-path HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status capabilities-response))
                  "engine_exchangeCapabilities HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status client-version-response))
                  "engine_getClientVersionV1 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          transition-configuration-response))
                  "engine_exchangeTransitionConfigurationV1 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          transition-configuration-mismatch-response))
                  "engine_exchangeTransitionConfigurationV1 mismatch HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          engine-public-namespace-response))
                  "Engine public namespace probe HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status new-payload-response))
                  "engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status forkchoice-response))
                  "engine_forkchoiceUpdatedV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          payload-bodies-by-hash-response))
                  "engine_getPayloadBodiesByHashV1 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          payload-bodies-by-range-response))
                  "engine_getPayloadBodiesByRangeV1 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status prepare-payload-response))
                  "engine_forkchoiceUpdatedV2 payloadAttributes HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status get-payload-response))
                  "engine_getPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          prepare-txpool-payload-response))
                  "engine_forkchoiceUpdatedV2 txpool payloadAttributes HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status
                          get-txpool-payload-response))
                  "engine_getPayloadV2 txpool HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          import-txpool-payload-response))
                  "engine_newPayloadV2 txpool prepared payload HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          forkchoice-txpool-payload-response))
                  "engine_forkchoiceUpdatedV2 txpool prepared payload HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status remote-payload-response))
                  "orphan engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status invalid-payload-response))
                  "invalid engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status block-number-response))
                  "eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status balance-response))
                  "eth_getBalance HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status prepared-public-response))
                  "prepared-payload eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status remote-public-response))
                  "remote-block eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status invalid-public-response))
                  "invalid-tipset eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-client-version-response))
                  "web3_clientVersion HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-net-version-response))
                  "net_version HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-net-listening-response))
                  "net_listening HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-syncing-response))
                  "eth_syncing HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-net-peer-count-response))
                  "net_peerCount HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-accounts-response))
                  "eth_accounts HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-coinbase-response))
                  "eth_coinbase HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-mining-response))
                  "eth_mining HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status public-hashrate-response))
                  "eth_hashrate HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-rpc-modules-response))
                  "rpc_modules HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-protocol-version-response))
                  "eth_protocolVersion HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-web3-sha3-response))
                  "web3_sha3 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-gas-price-response))
                  "eth_gasPrice HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-priority-fee-response))
                  "eth_maxPriorityFeePerGas HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-base-fee-response))
                  "eth_baseFee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-blob-base-fee-response))
                  "eth_blobBaseFee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-fee-history-response))
                  "eth_feeHistory HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-batch-response))
                  "Public JSON-RPC batch HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-engine-namespace-response))
                 "Public Engine namespace probe HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-malformed-json-response))
                  "Public malformed JSON probe HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 404 (devnet-cli-http-status
                          public-root-wrong-path-response))
                  "Public default root wrong-path HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          new-pending-filter-response))
                  "eth_newPendingTransactionFilter HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          pending-filter-changes-response))
                  "eth_getFilterChanges HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          empty-pending-filter-changes-response))
                  "drained eth_getFilterChanges HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          uninstall-pending-filter-response))
                  "eth_uninstallFilter HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          removed-pending-filter-changes-response))
                  "removed eth_getFilterChanges HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= -32601
                     (fixture-object-field
                      (fixture-object-field
                       public-engine-namespace-rpc
                       "error")
                      "code"))
                  "Public listener exposed Engine namespace")
                 (devnet-smoke-gate-require
                  (= -32700
                     (fixture-object-field
                      (fixture-object-field
                       public-malformed-json-rpc
                       "error")
                      "code"))
                  "Public listener malformed JSON did not return parse error")
                 (devnet-smoke-gate-require
                  (string= "0x1" pending-filter-id)
                  "eth_newPendingTransactionFilter id mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-raw-response))
                  "eth_sendRawTransaction HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-basefee-response))
                  "eth_sendRawTransaction basefee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-queued-response))
                  "eth_sendRawTransaction queued HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-replacement-response))
                  "eth_sendRawTransaction replacement HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status raw-pending-response))
                  "eth_getRawTransactionByHash pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status raw-basefee-response))
                  "eth_getRawTransactionByHash basefee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status raw-queued-response))
                  "eth_getRawTransactionByHash queued HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status pending-nonce-response))
                  "eth_getTransactionCount pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          pending-block-receipts-response))
                  "eth_getBlockReceipts pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          pending-uncle-count-response))
                  "eth_getUncleCountByBlockNumber pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status pending-logs-response))
                  "eth_getLogs pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status txpool-status-response))
                  "txpool_status HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status txpool-content-from-response))
                 "txpool_contentFrom HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status txpool-inspect-response))
                  "txpool_inspect HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status
                          post-prepared-txpool-content-from-response))
                  "post-prepared txpool_contentFrom HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status
                          post-replacement-txpool-content-from-response))
                  "post-replacement txpool_contentFrom HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-transaction-response))
                  "post-import eth_getTransactionByHash HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-receipt-response))
                  "post-import eth_getTransactionReceipt HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-raw-response))
                  "post-import eth_getRawTransactionByHash HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-block-response))
                  "post-import eth_getBlockByHash HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-txpool-status-response))
                  "post-import txpool_status HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-txpool-content-from-response))
                  "post-import txpool_contentFrom HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (member "engine_newPayloadV1"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_newPayloadV1")
                 (devnet-smoke-gate-require
                  (member "engine_forkchoiceUpdatedV1"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_forkchoiceUpdatedV1")
                 (devnet-smoke-gate-require
                  (member "engine_getPayloadV1"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_getPayloadV1")
                 (devnet-smoke-gate-require
                  (member "engine_newPayloadV2"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_newPayloadV2")
                 (devnet-smoke-gate-require
                  (member "engine_forkchoiceUpdatedV2"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_forkchoiceUpdatedV2")
                 (devnet-smoke-gate-require
                  (member "engine_getPayloadV2"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_getPayloadV2")
                 (devnet-smoke-gate-require
                  (member "engine_getPayloadBodiesByHashV1"
                          capabilities-result
                          :test #'string=)
                 "engine_exchangeCapabilities omitted engine_getPayloadBodiesByHashV1")
                 (devnet-smoke-gate-require
                  (member "engine_getPayloadBodiesByRangeV1"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_getPayloadBodiesByRangeV1")
                 (devnet-smoke-gate-require
                  (not (member "engine_newPayloadV3"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_newPayloadV3 without KZG verification")
                 (devnet-smoke-gate-require
                  (not (member "engine_getBlobsV1"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getBlobsV1 without KZG verification")
                 (devnet-smoke-gate-require
                  (not (member "engine_getBlobsV2"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getBlobsV2 without KZG verification")
                 (devnet-smoke-gate-require
                  (not (member "engine_getBlobsV3"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getBlobsV3 without KZG verification")
                 (devnet-smoke-gate-require
                 (not (member "engine_getPayloadBodiesByHashV2"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getPayloadBodiesByHashV2 without KZG verification")
                 (devnet-smoke-gate-require
                  (not (member "engine_getPayloadBodiesByRangeV2"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getPayloadBodiesByRangeV2 without KZG verification")
                 (devnet-smoke-gate-require
                  (string= "CL"
                           (fixture-object-field client-version-result "code"))
                  "engine_getClientVersionV1 code mismatch")
                 (devnet-smoke-gate-require
                  (string= "ethereum-lisp"
                           (fixture-object-field client-version-result "name"))
                  "engine_getClientVersionV1 name mismatch")
                 (devnet-smoke-gate-require
                  (string= "0.1.0"
                           (fixture-object-field client-version-result "version"))
                  "engine_getClientVersionV1 version mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x00000000"
                           (fixture-object-field client-version-result "commit"))
                  "engine_getClientVersionV1 commit mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-terminal-total-difficulty
                           (fixture-object-field
                            transition-configuration-result
                            "terminalTotalDifficulty"))
                  "engine_exchangeTransitionConfigurationV1 terminalTotalDifficulty mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-terminal-block-hash
                           (fixture-object-field
                            transition-configuration-result
                            "terminalBlockHash"))
                  "engine_exchangeTransitionConfigurationV1 terminalBlockHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-terminal-block-number
                           (fixture-object-field
                            transition-configuration-result
                            "terminalBlockNumber"))
                  "engine_exchangeTransitionConfigurationV1 terminalBlockNumber mismatch")
                 (devnet-smoke-gate-require
                  (= -32602
                     (fixture-object-field
                      transition-configuration-mismatch-error
                      "code"))
                  "engine_exchangeTransitionConfigurationV1 mismatch error code mismatch")
                 (devnet-smoke-gate-require
                  (search "terminalTotalDifficulty mismatch"
                          (fixture-object-field
                           transition-configuration-mismatch-error
                           "message"))
                  "engine_exchangeTransitionConfigurationV1 mismatch error message mismatch")
                 (devnet-smoke-gate-require
                  (= -32601
                     (fixture-object-field
                      (fixture-object-field
                       engine-public-namespace-rpc
                       "error")
                      "code"))
                  "Engine listener exposed public namespace")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field new-payload-result "status"))
                  "engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-hash
                           (fixture-object-field new-payload-result
                                                 "latestValidHash"))
                  "latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field forkchoice-status "status"))
                  "engine_forkchoiceUpdatedV2 status mismatch")
                 (devnet-smoke-gate-require
                  (= 1 (length payload-bodies-by-hash-result))
                  "engine_getPayloadBodiesByHashV1 body count mismatch")
                 (devnet-smoke-gate-require
                  (= 1 (length payload-bodies-by-range-result))
                  "engine_getPayloadBodiesByRangeV1 body count mismatch")
                 (devnet-smoke-gate-require
                  (= expected-payload-body-transaction-count
                     (length payload-body-by-hash-transactions))
                  "engine_getPayloadBodiesByHashV1 transaction count mismatch")
                 (devnet-smoke-gate-require
                  (= expected-payload-body-transaction-count
                     (length payload-body-by-range-transactions))
                  "engine_getPayloadBodiesByRangeV1 transaction count mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field prepare-payload-status
                                                 "status"))
                  "engine_forkchoiceUpdatedV2 payloadAttributes status mismatch")
                 (devnet-smoke-gate-require
                  (and (stringp prepared-payload-id)
                       (= 18 (length prepared-payload-id)))
                  "engine_forkchoiceUpdatedV2 did not return an 8-byte payloadId")
                 (devnet-smoke-gate-require
                  (not (fixture-object-field get-payload-rpc "error"))
                  "engine_getPayloadV2 returned an error")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-payload-id prepared-payload-id)
                  "engine_forkchoiceUpdatedV2 payloadId mismatch")
                 (devnet-smoke-gate-require
                  (string= (hash32-to-hex (block-hash child-block))
                           (fixture-object-field
                            get-payload-execution-payload
                            "parentHash"))
                  "engine_getPayloadV2 parentHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            get-payload-execution-payload
                            "blockNumber"))
                  "engine_getPayloadV2 blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (listp get-payload-transactions)
                  "engine_getPayloadV2 transactions must be a JSON array")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field
                            prepare-txpool-payload-status
                            "status"))
                  "engine_forkchoiceUpdatedV2 txpool payloadAttributes status mismatch")
                 (devnet-smoke-gate-require
                  (and (stringp prepared-txpool-payload-id)
                       (= 18 (length prepared-txpool-payload-id)))
                  "engine_forkchoiceUpdatedV2 txpool did not return an 8-byte payloadId")
                 (devnet-smoke-gate-require
                  (not (fixture-object-field get-txpool-payload-rpc "error"))
                  "engine_getPayloadV2 txpool returned an error: ~S"
                  (fixture-object-field get-txpool-payload-rpc "error"))
                 (devnet-smoke-gate-require
                  (string= (hash32-to-hex (block-hash child-block))
                           (fixture-object-field
                            get-txpool-payload-execution-payload
                            "parentHash"))
                  "engine_getPayloadV2 txpool parentHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            get-txpool-payload-execution-payload
                            "blockNumber"))
                  "engine_getPayloadV2 txpool blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (listp get-txpool-payload-transactions)
                  "engine_getPayloadV2 txpool transactions must be a JSON array")
                 (devnet-smoke-gate-require
                  (= 1 (length get-txpool-payload-transactions))
                  "engine_getPayloadV2 txpool should select exactly one executable transaction")
                 (devnet-smoke-gate-require
                  (member pending-transaction-raw
                          get-txpool-payload-transactions
                          :test #'string=)
                  "engine_getPayloadV2 txpool omitted executable pending transaction")
                 (devnet-smoke-gate-require
                  (not (member basefee-transaction-raw
                               get-txpool-payload-transactions
                               :test #'string=))
                  "engine_getPayloadV2 txpool selected underpriced basefee transaction")
                 (devnet-smoke-gate-require
                 (not (member queued-transaction-raw
                               get-txpool-payload-transactions
                               :test #'string=))
                  "engine_getPayloadV2 txpool selected nonce-gapped queued transaction")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (fixture-object-field
                            send-replacement-rpc "result"))
                  "eth_sendRawTransaction replacement hash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field
                            prepare-replacement-txpool-payload-status
                            "status"))
                  "replacement engine_forkchoiceUpdatedV2 txpool payloadAttributes status mismatch")
                 (devnet-smoke-gate-require
                  (and (stringp prepared-replacement-txpool-payload-id)
                       (= 18 (length prepared-replacement-txpool-payload-id)))
                  "replacement engine_forkchoiceUpdatedV2 txpool did not return an 8-byte payloadId")
                 (devnet-smoke-gate-require
                  (not (string= prepared-txpool-payload-id
                                prepared-replacement-txpool-payload-id))
                  "replacement txpool payload id did not change")
                 (devnet-smoke-gate-require
                  (not (fixture-object-field
                        get-replacement-txpool-payload-rpc "error"))
                  "replacement engine_getPayloadV2 txpool returned an error: ~S"
                  (fixture-object-field
                   get-replacement-txpool-payload-rpc "error"))
                 (devnet-smoke-gate-require
                  (string= (hash32-to-hex (block-hash child-block))
                           (fixture-object-field
                            get-replacement-txpool-payload-execution-payload
                            "parentHash"))
                  "replacement engine_getPayloadV2 txpool parentHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            get-replacement-txpool-payload-execution-payload
                            "blockNumber"))
                  "replacement engine_getPayloadV2 txpool blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (listp get-replacement-txpool-payload-transactions)
                  "replacement engine_getPayloadV2 txpool transactions must be a JSON array")
                 (devnet-smoke-gate-require
                  (= 1 (length get-replacement-txpool-payload-transactions))
                  "replacement engine_getPayloadV2 txpool should select exactly one executable transaction")
                 (devnet-smoke-gate-require
                  (member replacement-transaction-raw
                          get-replacement-txpool-payload-transactions
                          :test #'string=)
                  "replacement engine_getPayloadV2 txpool omitted replacement transaction")
                 (devnet-smoke-gate-require
                  (not (member pending-transaction-raw
                               get-replacement-txpool-payload-transactions
                               :test #'string=))
                  "replacement engine_getPayloadV2 txpool retained original transaction")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field
                            import-txpool-payload-result
                            "status"))
                  "engine_newPayloadV2 txpool prepared payload status mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-txpool-block-hash
                           (fixture-object-field
                            import-txpool-payload-result
                            "latestValidHash"))
                  "engine_newPayloadV2 txpool latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field
                            forkchoice-txpool-payload-status
                            "status"))
                  "engine_forkchoiceUpdatedV2 txpool prepared payload status mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (fixture-object-field
                            post-import-transaction
                            "hash"))
                  "post-import eth_getTransactionByHash hash mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-txpool-block-hash
                           (fixture-object-field
                            post-import-transaction
                            "blockHash"))
                  "post-import eth_getTransactionByHash blockHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            post-import-transaction
                            "blockNumber"))
                  "post-import eth_getTransactionByHash blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            post-import-transaction
                            "transactionIndex"))
                  "post-import eth_getTransactionByHash transactionIndex mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (fixture-object-field
                            post-import-receipt
                            "transactionHash"))
                  "post-import eth_getTransactionReceipt hash mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-txpool-block-hash
                           (fixture-object-field
                            post-import-receipt
                            "blockHash"))
                  "post-import eth_getTransactionReceipt blockHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            post-import-receipt
                            "blockNumber"))
                  "post-import eth_getTransactionReceipt blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-raw
                           post-import-raw-transaction)
                  "post-import eth_getRawTransactionByHash raw mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-txpool-block-hash
                           (fixture-object-field post-import-block "hash"))
                  "post-import eth_getBlockByHash hash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field post-import-block "number"))
                  "post-import eth_getBlockByHash number mismatch")
                 (devnet-smoke-gate-require
                  (= 1 (length post-import-block-transactions))
                  "post-import eth_getBlockByHash transaction count mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (first post-import-block-transactions))
                  "post-import eth_getBlockByHash transaction hash mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            post-import-txpool-status
                            "pending"))
                  "post-import txpool_status pending count mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x2"
                           (fixture-object-field
                            post-import-txpool-status
                            "queued"))
                  "post-import txpool_status queued count mismatch")
                 (devnet-smoke-gate-require
                  (null post-import-txpool-content-from-selected)
                  "post-import txpool_contentFrom still exposes mined pending transaction")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (fixture-object-field
                            post-replacement-txpool-content-from-transaction
                            "hash"))
                  "post-replacement txpool_contentFrom hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field
                            post-import-txpool-content-from-basefee-transaction
                            "hash"))
                  "post-import txpool_contentFrom basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field
                            post-import-txpool-content-from-queued-transaction
                            "hash"))
                  "post-import txpool_contentFrom queued hash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-syncing+
                           (fixture-object-field remote-payload-result
                                                 "status"))
                  "orphan engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field remote-payload-result
                                              "latestValidHash"))
                  "orphan engine_newPayloadV2 should not report latestValidHash")
                 (devnet-smoke-gate-require
                  (ethereum-lisp.core::engine-payload-store-remote-block
                   store (block-hash remote-block))
                  "orphan engine_newPayloadV2 did not populate remote-block cache")
                 (devnet-smoke-gate-require
                  (string= +payload-status-invalid+
                           (fixture-object-field invalid-payload-result
                                                 "status"))
                  "invalid engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-hash
                           (fixture-object-field invalid-payload-result
                                                 "latestValidHash"))
                  "invalid engine_newPayloadV2 latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= "Timestamp is not greater than parent timestamp"
                           (fixture-object-field invalid-payload-result
                                                 "validationError"))
                  "invalid engine_newPayloadV2 validation error mismatch")
                 (devnet-smoke-gate-require
                  (ethereum-lisp.core::engine-payload-store-invalid-block
                   store (block-hash invalid-block))
                  "invalid engine_newPayloadV2 did not populate invalid-tipset cache")
                 (devnet-smoke-gate-require
                  (string= expected-block-number actual-block-number)
                  "eth_blockNumber mismatch: expected ~A got ~A"
                  expected-block-number
                  actual-block-number)
                 (devnet-smoke-gate-require
                  (string= expected-block-number
                           (fixture-object-field prepared-public-rpc "result"))
                  "prepared-payload eth_blockNumber mismatch")
                 (devnet-smoke-gate-require
                 (string= expected-block-number
                           (fixture-object-field remote-public-rpc "result"))
                  "remote-block eth_blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-block-number
                           (fixture-object-field invalid-public-rpc "result"))
                  "invalid-tipset eth_blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (search "ethereum-lisp"
                          (fixture-object-field public-client-version-rpc
                                                "result"))
                  "web3_clientVersion did not expose ethereum-lisp")
                 (devnet-smoke-gate-require
                  (string= (write-to-string
                             (ethereum-lisp.cli::devnet-node-network-id node)
                             :base 10)
                           (fixture-object-field public-net-version-rpc
                                                 "result"))
                  "net_version mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-net-listening-rpc
                                              "result"))
                  "net_listening mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-syncing-rpc "result"))
                  "eth_syncing mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex 0)
                           (fixture-object-field public-net-peer-count-rpc
                                                 "result"))
                  "net_peerCount mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-accounts-rpc "result"))
                  "eth_accounts mismatch")
                 (devnet-smoke-gate-require
                  (string= (address-to-hex (zero-address))
                           (fixture-object-field public-coinbase-rpc
                                                 "result"))
                  "eth_coinbase mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-mining-rpc "result"))
                  "eth_mining mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex 0)
                           (fixture-object-field public-hashrate-rpc
                                                 "result"))
                  "eth_hashrate mismatch")
                 (devnet-smoke-gate-require
                  (string= "1.0"
                           (fixture-object-field public-rpc-modules "eth"))
                  "rpc_modules eth module mismatch")
                 (devnet-smoke-gate-require
                  (string= "1.0"
                           (fixture-object-field public-rpc-modules "net"))
                  "rpc_modules net module mismatch")
                 (devnet-smoke-gate-require
                  (string= "1.0"
                           (fixture-object-field public-rpc-modules "rpc"))
                  "rpc_modules rpc module mismatch")
                 (devnet-smoke-gate-require
                  (string= "1.0"
                           (fixture-object-field public-rpc-modules "txpool"))
                  "rpc_modules txpool module mismatch")
                 (devnet-smoke-gate-require
                 (string= "1.0"
                          (fixture-object-field public-rpc-modules "web3"))
                  "rpc_modules web3 module mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex
                            ethereum-lisp.core::+eth-protocol-version+)
                           (fixture-object-field
                            public-protocol-version-rpc
                            "result"))
                  "eth_protocolVersion mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
                           (fixture-object-field public-web3-sha3-rpc
                                                 "result"))
                  "web3_sha3 mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-gas-price
                           (fixture-object-field public-gas-price-rpc
                                                 "result"))
                  "eth_gasPrice mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex 0)
                           (fixture-object-field public-priority-fee-rpc
                                                 "result"))
                  "eth_maxPriorityFeePerGas mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-next-base-fee
                           (fixture-object-field public-base-fee-rpc
                                                 "result"))
                  "eth_baseFee mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-blob-base-fee-rpc
                                              "result"))
                  "eth_blobBaseFee should be null before Cancun blob data")
                 (devnet-smoke-gate-require
                  (string= expected-block-number
                           (fixture-object-field public-fee-history
                                                 "oldestBlock"))
                  "eth_feeHistory oldestBlock mismatch")
                 (let ((base-fees
                         (fixture-object-field public-fee-history
                                               "baseFeePerGas"))
                       (gas-ratios
                         (fixture-object-field public-fee-history
                                               "gasUsedRatio")))
                   (devnet-smoke-gate-require
                    (= 2 (length base-fees))
                    "eth_feeHistory baseFeePerGas length mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-gas-price (first base-fees))
                    "eth_feeHistory base fee mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-next-base-fee (second base-fees))
                    "eth_feeHistory next base fee mismatch")
                   (devnet-smoke-gate-require
                    (= 1 (length gas-ratios))
                    "eth_feeHistory gasUsedRatio length mismatch")
                   (devnet-smoke-gate-require
                    (realp (first gas-ratios))
                    "eth_feeHistory gasUsedRatio must be numeric"))
                 (devnet-smoke-gate-require
                  (= 3 (length public-batch-rpc))
                  "Public JSON-RPC batch response count mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex
                             (chain-config-chain-id config))
                           (fixture-object-field
                            public-batch-chain-id-rpc
                            "result"))
                  "Public batch eth_chainId mismatch")
                 (devnet-smoke-gate-require
                  (string= (write-to-string
                             (ethereum-lisp.cli::devnet-node-network-id node)
                             :base 10)
                           (fixture-object-field
                            public-batch-network-rpc
                            "result"))
                  "Public batch net_version mismatch")
                 (devnet-smoke-gate-require
                  (search "ethereum-lisp"
                          (fixture-object-field
                           public-batch-client-version-rpc
                           "result"))
                  "Public batch web3_clientVersion mismatch")
                 (devnet-smoke-gate-require
                 (string= pending-transaction-hash-hex
                           (fixture-object-field send-raw-rpc "result"))
                  "eth_sendRawTransaction hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field send-basefee-rpc "result"))
                  "eth_sendRawTransaction basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field send-queued-rpc "result"))
                  "eth_sendRawTransaction queued hash mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status txpool-rejournal-response))
                  "txpool rejournal wait request HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (string= actual-block-number
                           (fixture-object-field
                            txpool-rejournal-rpc "result"))
                  "txpool rejournal wait request block number mismatch")
                 (devnet-smoke-gate-require
                  txpool-rejournal-report
                  "txpool rejournal did not report the expected record")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-hash-hex
                           (getf txpool-rejournal-report
                                 :transaction-hash))
                  "txpool rejournal transaction hash mismatch")
                 (devnet-smoke-gate-require
                  (eq :pending (getf txpool-rejournal-report :subpool))
                  "txpool rejournal transaction subpool mismatch")
                 (devnet-smoke-gate-require
                  (= 1 (length pending-filter-changes))
                  "eth_getFilterChanges pending transaction count mismatch")
                 (devnet-smoke-gate-require
                 (string= pending-transaction-hash-hex
                           (first pending-filter-changes))
                  "eth_getFilterChanges pending transaction hash mismatch")
                 (devnet-smoke-gate-require
                  (devnet-smoke-gate-empty-json-array-p
                   empty-pending-filter-changes)
                  "drained eth_getFilterChanges should be empty")
                 (devnet-smoke-gate-require
                  (member (fixture-object-field
                           uninstall-pending-filter-rpc
                           "result")
                          '(t :true))
                  "eth_uninstallFilter result mismatch")
                 (devnet-smoke-gate-require
                  (= -32602
                     (fixture-object-field
                      removed-pending-filter-error
                      "code"))
                  "removed eth_getFilterChanges error code mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-raw
                           (fixture-object-field raw-pending-rpc "result"))
                  "eth_getRawTransactionByHash pending raw mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-raw
                           (fixture-object-field raw-basefee-rpc "result"))
                  "eth_getRawTransactionByHash basefee raw mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-raw
                           (fixture-object-field raw-queued-rpc "result"))
                  "eth_getRawTransactionByHash queued raw mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-pending-sender-nonce
                           (fixture-object-field pending-nonce-rpc "result"))
                  "eth_getTransactionCount pending nonce mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field
                         pending-block-receipts-rpc "result"))
                  "eth_getBlockReceipts pending should be null")
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            pending-uncle-count-rpc "result"))
                  "eth_getUncleCountByBlockNumber pending mismatch")
                 (devnet-smoke-gate-require
                  (devnet-smoke-gate-empty-json-array-p
                   (fixture-object-field pending-logs-rpc "result"))
                  "eth_getLogs pending should be empty")
                 (devnet-smoke-gate-require
                  (string= "0x1"
                           (fixture-object-field txpool-status "pending"))
                  "txpool_status pending count mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x2"
                           (fixture-object-field txpool-status "queued"))
                  "txpool_status queued count mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-hash-hex
                           (fixture-object-field
                            txpool-content-from-transaction "hash"))
                  "txpool_contentFrom pending hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field
                            txpool-content-from-basefee-transaction "hash"))
                  "txpool_contentFrom basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field
                            txpool-content-from-queued-transaction "hash"))
                  "txpool_contentFrom queued hash mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-hash-hex
                           (fixture-object-field
                            post-prepared-txpool-content-from-transaction
                            "hash"))
                  "post-prepared txpool_contentFrom pending hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field
                            post-prepared-txpool-content-from-basefee-transaction
                            "hash"))
                  "post-prepared txpool_contentFrom basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field
                            post-prepared-txpool-content-from-queued-transaction
                            "hash"))
                  "post-prepared txpool_contentFrom queued hash mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-summary
                           txpool-inspect-transaction)
                  "txpool_inspect pending summary mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-summary
                           txpool-inspect-basefee-transaction)
                  "txpool_inspect basefee summary mismatch")
                 (devnet-smoke-gate-require
                 (string= queued-transaction-summary
                          txpool-inspect-queued-transaction)
                  "txpool_inspect queued summary mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-balance actual-balance)
                  "eth_getBalance mismatch: expected ~A got ~A"
                  expected-balance
                  actual-balance)
                 (when database-file
                   (ethereum-lisp.cli::devnet-node-export-database
                    node
                    :state-prune-before state-prune-before))
                 (let ((database-summary
                         (and database-file
                              (devnet-smoke-gate-verify-database
                               database-file
                               expected-block-number
                               balance-targets
                               sender-address
                               expected-sender-nonce
                               code-address
                               expected-code
                               storage-address
                               storage-key
                               expected-storage
                               transaction-checks
                               log-targets
                               (block-hash child-block)
                               expected-safe-block-number
                               expected-safe-block-hash
                               expected-finalized-block-number
                               expected-finalized-block-hash
                               config
                               :state-prune-before state-prune-before
                               :pruned-state-hash expected-safe-block-hash
                               :expected-head-block-number
                               expected-prepared-block-number
                               :checkpoint-balance-targets
                               checkpoint-balance-targets
                               :prepared-payload-id prepared-payload-id
                               :prepared-payload-parent-hash
                               (block-hash child-block)
                               :prepared-payload-block-number
                               expected-prepared-block-number
                               :remote-payload remote-payload
                               :remote-block remote-block
                               :invalid-block invalid-block
                               :invalid-descendant-payload
                               invalid-descendant-payload
                               :txpool-transactions txpool-transactions
                               :selected-txpool-transaction
                               replacement-transaction
                               :side-payload side-payload
                               :side-block side-block
                               :child-block child-block)))
                       (public-api-allowlist-summary
                         (devnet-smoke-gate-verify-public-api-allowlist))
                       (public-cors-summary
                         (devnet-smoke-gate-verify-public-cors))
                       (engine-cors-summary
                         (devnet-smoke-gate-verify-engine-cors))
                       (http-shaping-summary
                         (devnet-smoke-gate-verify-http-shaping))
                       (vhost-summary
                         (devnet-smoke-gate-verify-vhosts))
                       (rpc-prefix-summary
                         (devnet-smoke-gate-verify-rpc-prefixes))
                       (dev-period-summary
                         (devnet-smoke-gate-verify-dev-period-mining
                          case-name
                          :terminal-total-difficulty
                          terminal-total-difficulty
                          :terminal-total-difficulty-passed-p
                          terminal-total-difficulty-passed-p
                          :terminal-block-hash terminal-block-hash
                          :terminal-block-number terminal-block-number)))
                 (devnet-smoke-gate-add-run-metadata
                  (list
                  (cons "status" "ok")
                  (cons "mode" "devnet-listener-boundary")
                  (cons "fixtureCase" case-name)
                  (cons "chainId"
                        (quantity-to-hex
                         (chain-config-chain-id config)))
                  (cons "engineConnections"
                        (getf summary :engine-connections))
                  (cons "publicConnections"
                        (getf summary :public-connections))
                  (cons "totalConnections"
                        (getf summary :total-connections))
                  (cons "connectionContract"
                        (devnet-smoke-gate-connection-contract))
                  (cons "publicApiAllowlist"
                        (getf public-api-allowlist-summary
                              :allowed-modules))
                  (cons "publicApiAllowlistReportedModules"
                        (getf public-api-allowlist-summary
                              :reported-modules))
                  (cons "publicApiAllowlistTelemetryModules"
                        (getf public-api-allowlist-summary
                              :telemetry-modules))
                  (cons "publicApiAllowlistEngineConnections"
                        (getf public-api-allowlist-summary
                              :engine-connections))
                  (cons "publicApiAllowlistPublicConnections"
                        (getf public-api-allowlist-summary
                              :public-connections))
                  (cons "publicApiAllowlistTotalConnections"
                        (getf public-api-allowlist-summary
                              :total-connections))
                  (cons "publicApiAllowlistChainId"
                        (getf public-api-allowlist-summary
                              :chain-id))
                  (cons "publicApiAllowlistNetworkVersion"
                        (getf public-api-allowlist-summary
                              :network-version))
                  (cons "publicApiBlockedWeb3ErrorCode"
                        (getf public-api-allowlist-summary
                              :web3-error-code))
                  (cons "publicApiBlockedTxpoolErrorCode"
                        (getf public-api-allowlist-summary
                              :txpool-error-code))
                  (cons "publicApiBlockedEngineErrorCode"
                        (getf public-api-allowlist-summary
                              :engine-error-code))
                  (cons "publicCorsOrigins"
                        (getf public-cors-summary :origins))
                  (cons "publicCorsReportedOrigins"
                        (getf public-cors-summary :reported-origins))
                  (cons "publicCorsTelemetryOrigins"
                        (getf public-cors-summary :telemetry-origins))
                  (cons "publicCorsPreflightStatus"
                        (getf public-cors-summary :preflight-status))
                  (cons "publicCorsRpcStatus"
                        (getf public-cors-summary :post-status))
                  (cons "publicCorsBlockedStatus"
                        (getf public-cors-summary :blocked-status))
                  (cons "publicCorsEngineConnections"
                        (getf public-cors-summary :engine-connections))
                  (cons "publicCorsPublicConnections"
                        (getf public-cors-summary :public-connections))
                  (cons "publicCorsTotalConnections"
                        (getf public-cors-summary :total-connections))
                  (cons "engineCorsOrigins"
                        (getf engine-cors-summary :origins))
                  (cons "engineCorsReportedOrigins"
                        (getf engine-cors-summary :reported-origins))
                  (cons "engineCorsTelemetryOrigins"
                        (getf engine-cors-summary :telemetry-origins))
                  (cons "engineCorsPreflightStatus"
                        (getf engine-cors-summary :preflight-status))
                  (cons "engineCorsRpcStatus"
                        (getf engine-cors-summary :post-status))
                  (cons "engineCorsBlockedStatus"
                        (getf engine-cors-summary :blocked-status))
                  (cons "engineCorsEngineConnections"
                        (getf engine-cors-summary :engine-connections))
                  (cons "engineCorsPublicConnections"
                        (getf engine-cors-summary :public-connections))
                  (cons "engineCorsTotalConnections"
                        (getf engine-cors-summary :total-connections))
                  (cons "engineHttpMethodStatus"
                        (getf http-shaping-summary :engine-method-status))
                  (cons "engineHttpContentTypeStatus"
                        (getf http-shaping-summary
                              :engine-content-type-status))
                  (cons "publicHttpMethodStatus"
                        (getf http-shaping-summary :public-method-status))
                  (cons "publicHttpContentTypeStatus"
                        (getf http-shaping-summary
                              :public-content-type-status))
                  (cons "httpShapingEngineConnections"
                        (getf http-shaping-summary :engine-connections))
                  (cons "httpShapingPublicConnections"
                        (getf http-shaping-summary :public-connections))
                  (cons "httpShapingTotalConnections"
                        (getf http-shaping-summary :total-connections))
                  (cons "engineVhosts"
                        (getf vhost-summary :engine-vhosts))
                  (cons "publicVhosts"
                        (getf vhost-summary :public-vhosts))
                  (cons "engineVhostsReported"
                        (getf vhost-summary :reported-engine-vhosts))
                  (cons "publicVhostsReported"
                        (getf vhost-summary :reported-public-vhosts))
                  (cons "engineVhostsTelemetry"
                        (getf vhost-summary :telemetry-engine-vhosts))
                  (cons "publicVhostsTelemetry"
                        (getf vhost-summary :telemetry-public-vhosts))
                  (cons "engineVhostAllowedStatus"
                        (getf vhost-summary :engine-allowed-status))
                  (cons "engineVhostBlockedStatus"
                        (getf vhost-summary :engine-blocked-status))
                  (cons "publicVhostAllowedStatus"
                        (getf vhost-summary :public-allowed-status))
                  (cons "publicVhostBlockedStatus"
                        (getf vhost-summary :public-blocked-status))
                  (cons "vhostEngineConnections"
                        (getf vhost-summary :engine-connections))
                  (cons "vhostPublicConnections"
                        (getf vhost-summary :public-connections))
                  (cons "vhostTotalConnections"
                        (getf vhost-summary :total-connections))
                  (cons "engineRpcPrefix"
                        (getf rpc-prefix-summary :engine-prefix))
                  (cons "publicRpcPrefix"
                        (getf rpc-prefix-summary :public-prefix))
                  (cons "engineRpcPrefixReported"
                        (getf rpc-prefix-summary
                              :reported-engine-prefix))
                  (cons "publicRpcPrefixReported"
                        (getf rpc-prefix-summary
                              :reported-public-prefix))
                  (cons "engineRpcPrefixTelemetry"
                        (getf rpc-prefix-summary
                              :telemetry-engine-prefix))
                  (cons "publicRpcPrefixTelemetry"
                        (getf rpc-prefix-summary
                              :telemetry-public-prefix))
                  (cons "engineRpcPrefixStatus"
                        (getf rpc-prefix-summary :engine-status))
                  (cons "engineRpcPrefixBlockedStatus"
                        (getf rpc-prefix-summary
                              :engine-blocked-status))
                  (cons "publicRpcPrefixStatus"
                        (getf rpc-prefix-summary :public-status))
                  (cons "publicRpcPrefixBlockedStatus"
                        (getf rpc-prefix-summary
                              :public-blocked-status))
                  (cons "rpcPrefixEngineConnections"
                        (getf rpc-prefix-summary :engine-connections))
                  (cons "rpcPrefixPublicConnections"
                        (getf rpc-prefix-summary :public-connections))
                  (cons "rpcPrefixTotalConnections"
                        (getf rpc-prefix-summary :total-connections))
                  (cons "engineUnauthenticatedStatus"
                        (devnet-cli-http-status
                         unauthenticated-engine-response))
                  (cons "engineInvalidAuthStatus"
                        (devnet-cli-http-status
                         invalid-auth-engine-response))
                  (cons "engineDuplicateAuthStatus"
                        (devnet-cli-http-status
                         duplicate-auth-engine-response))
                  (cons "engineRootWrongPathStatus"
                        (devnet-cli-http-status
                         engine-root-wrong-path-response))
                  (cons "engineCapabilityCount"
                        (length capabilities-result))
                  (cons "engineCapabilityHasNewPayloadV1"
                        (if (member "engine_newPayloadV1"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasForkchoiceUpdatedV1"
                        (if (member "engine_forkchoiceUpdatedV1"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasGetPayloadV1"
                        (if (member "engine_getPayloadV1"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasNewPayloadV2"
                        (if (member "engine_newPayloadV2"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasForkchoiceUpdatedV2"
                        (if (member "engine_forkchoiceUpdatedV2"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasGetPayloadV2"
                        (if (member "engine_getPayloadV2"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasNewPayloadV3"
                        (if (member "engine_newPayloadV3"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasGetBlobsV1"
                        (if (member "engine_getBlobsV1"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasPayloadBodiesV2"
                        (if (or (member "engine_getPayloadBodiesByHashV2"
                                        capabilities-result
                                        :test #'string=)
                                (member "engine_getPayloadBodiesByRangeV2"
                                        capabilities-result
                                        :test #'string=))
                            t
                            :false))
                  (cons "engineClientVersionCode"
                        (fixture-object-field client-version-result "code"))
                  (cons "engineClientVersionName"
                        (fixture-object-field client-version-result "name"))
                  (cons "engineClientVersionVersion"
                        (fixture-object-field client-version-result "version"))
                  (cons "engineClientVersionCommit"
                        (fixture-object-field client-version-result "commit"))
                  (cons "engineTransitionTerminalTotalDifficulty"
                        (fixture-object-field
                         transition-configuration-result
                         "terminalTotalDifficulty"))
                  (cons "engineTransitionTerminalBlockHash"
                        (fixture-object-field
                         transition-configuration-result
                         "terminalBlockHash"))
                  (cons "engineTransitionTerminalBlockNumber"
                        (fixture-object-field
                         transition-configuration-result
                         "terminalBlockNumber"))
                  (cons "engineTransitionMismatchErrorCode"
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code"))
                  (cons "engineTransitionMismatchErrorMessage"
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "message"))
                  (cons "enginePublicNamespaceErrorCode"
                        (fixture-object-field
                         (fixture-object-field
                          engine-public-namespace-rpc
                          "error")
                         "code"))
                  (cons "publicEngineNamespaceErrorCode"
                        (fixture-object-field
                         (fixture-object-field
                          public-engine-namespace-rpc
                          "error")
                         "code"))
                  (cons "publicMalformedJsonErrorCode"
                        (fixture-object-field
                         (fixture-object-field
                          public-malformed-json-rpc
                          "error")
                         "code"))
                  (cons "publicRootWrongPathStatus"
                        (devnet-cli-http-status
                         public-root-wrong-path-response))
                  (cons "publicClientVersion"
                        (fixture-object-field public-client-version-rpc
                                              "result"))
                  (cons "publicNetVersion"
                        (fixture-object-field public-net-version-rpc
                                              "result"))
                  (cons "publicNetListening"
                        (if (fixture-object-field public-net-listening-rpc
                                                  "result")
                            t
                            :false))
                  (cons "publicSyncing"
                        (if (fixture-object-field public-syncing-rpc "result")
                            t
                            :false))
                  (cons "publicNetPeerCount"
                        (fixture-object-field public-net-peer-count-rpc
                                              "result"))
                  (cons "publicAccountCount"
                        (length (fixture-object-field public-accounts-rpc
                                                      "result")))
                  (cons "publicCoinbase"
                        (fixture-object-field public-coinbase-rpc "result"))
                  (cons "publicMining"
                        (if (fixture-object-field public-mining-rpc "result")
                            t
                            :false))
                  (cons "publicHashrate"
                        (fixture-object-field public-hashrate-rpc "result"))
                  (cons "publicRpcModules" public-rpc-modules)
                  (cons "publicProtocolVersion"
                        (fixture-object-field public-protocol-version-rpc
                                              "result"))
                  (cons "publicWeb3Sha3"
                        (fixture-object-field public-web3-sha3-rpc "result"))
                  (cons "publicGasPrice"
                        (fixture-object-field public-gas-price-rpc "result"))
                  (cons "publicMaxPriorityFeePerGas"
                        (fixture-object-field public-priority-fee-rpc
                                              "result"))
                  (cons "publicBaseFee"
                        (fixture-object-field public-base-fee-rpc "result"))
                  (cons "publicBlobBaseFee"
                        (or (fixture-object-field public-blob-base-fee-rpc
                                                  "result")
                            :false))
                  (cons "publicFeeHistoryOldestBlock"
                        (fixture-object-field public-fee-history
                                              "oldestBlock"))
                  (cons "publicFeeHistoryBaseFeeCount"
                        (length
                         (fixture-object-field public-fee-history
                                               "baseFeePerGas")))
                  (cons "publicFeeHistoryGasUsedRatioCount"
                        (length
                         (fixture-object-field public-fee-history
                                               "gasUsedRatio")))
                  (cons "publicBatchResponseCount"
                        (length public-batch-rpc))
                  (cons "publicBatchChainId"
                        (fixture-object-field public-batch-chain-id-rpc
                                              "result"))
                  (cons "publicBatchNetVersion"
                        (fixture-object-field public-batch-network-rpc
                                              "result"))
                  (cons "publicBatchClientVersion"
                        (fixture-object-field
                         public-batch-client-version-rpc
                         "result"))
                  (cons "pendingBlockReceipts"
                        (or (fixture-object-field
                             pending-block-receipts-rpc "result")
                            :false))
                  (cons "pendingUncleCount"
                        (fixture-object-field pending-uncle-count-rpc
                                              "result"))
                  (cons "pendingLogCount"
                        (length (fixture-object-field pending-logs-rpc
                                                      "result")))
                  (cons "newPayloadStatus"
                        (fixture-object-field new-payload-result "status"))
                  (cons "latestValidHash" expected-hash)
                  (cons "forkchoiceStatus"
                        (fixture-object-field forkchoice-status "status"))
                  (cons "enginePayloadBodiesByHashCount"
                        (length payload-bodies-by-hash-result))
                  (cons "enginePayloadBodiesByHashTransactionCount"
                        (length payload-body-by-hash-transactions))
                  (cons "enginePayloadBodiesByRangeCount"
                        (length payload-bodies-by-range-result))
                  (cons "enginePayloadBodiesByRangeTransactionCount"
                        (length payload-body-by-range-transactions))
                  (cons "preparedPayloadId" prepared-payload-id)
                  (cons "preparedPayloadParentHash"
                        (hash32-to-hex (block-hash child-block)))
                  (cons "preparedPayloadBlockNumber"
                        expected-prepared-block-number)
                  (cons "engineGetPayloadV2ParentHash"
                        (fixture-object-field
                         get-payload-execution-payload
                         "parentHash"))
                  (cons "engineGetPayloadV2BlockNumber"
                        (fixture-object-field
                         get-payload-execution-payload
                         "blockNumber"))
                  (cons "engineGetPayloadV2TransactionCount"
                        (length get-payload-transactions))
                  (cons "preparedTxpoolPayloadId"
                        prepared-txpool-payload-id)
                  (cons "engineGetPayloadV2TxpoolParentHash"
                        (fixture-object-field
                         get-txpool-payload-execution-payload
                         "parentHash"))
                  (cons "engineGetPayloadV2TxpoolBlockNumber"
                        (fixture-object-field
                         get-txpool-payload-execution-payload
                         "blockNumber"))
                  (cons "engineGetPayloadV2TxpoolTransactionCount"
                        (length get-txpool-payload-transactions))
                  (cons "engineGetPayloadV2TxpoolSelectedTransactionRaw"
                        (first get-txpool-payload-transactions))
                  (cons "engineGetPayloadV2TxpoolSelectedTransactionHash"
                        pending-transaction-hash-hex)
                  (cons "engineGetPayloadV2TxpoolSelectedStillPending"
                        (fixture-object-field
                         post-prepared-txpool-content-from-transaction
                         "hash"))
                  (cons "engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued"
                        (fixture-object-field
                         post-prepared-txpool-content-from-basefee-transaction
                         "hash"))
                  (cons "engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued"
                        (fixture-object-field
                         post-prepared-txpool-content-from-queued-transaction
                         "hash"))
                  (cons "preparedReplacementTxpoolPayloadId"
                        prepared-replacement-txpool-payload-id)
                  (cons "engineGetPayloadV2TxpoolReplacementParentHash"
                        (fixture-object-field
                         get-replacement-txpool-payload-execution-payload
                         "parentHash"))
                  (cons "engineGetPayloadV2TxpoolReplacementBlockNumber"
                        (fixture-object-field
                         get-replacement-txpool-payload-execution-payload
                         "blockNumber"))
                  (cons "engineGetPayloadV2TxpoolReplacementTransactionCount"
                        (length get-replacement-txpool-payload-transactions))
                  (cons "engineGetPayloadV2TxpoolReplacementTransactionRaw"
                        (first get-replacement-txpool-payload-transactions))
                  (cons "engineGetPayloadV2TxpoolReplacementTransactionHash"
                        replacement-transaction-hash-hex)
                  (cons "engineGetPayloadV2TxpoolReplacementStillPending"
                        (fixture-object-field
                         post-replacement-txpool-content-from-transaction
                         "hash"))
                  (cons "engineGetPayloadV2TxpoolReplacementNonSelectedBasefeeStillQueued"
                        (fixture-object-field
                         post-replacement-txpool-content-from-basefee-transaction
                         "hash"))
                  (cons "engineGetPayloadV2TxpoolReplacementNonSelectedQueuedStillQueued"
                        (fixture-object-field
                         post-replacement-txpool-content-from-queued-transaction
                         "hash"))
                  (cons "engineNewPayloadV2TxpoolImportStatus"
                        (fixture-object-field
                         import-txpool-payload-result
                         "status"))
                  (cons "engineNewPayloadV2TxpoolImportLatestValidHash"
                        (fixture-object-field
                         import-txpool-payload-result
                         "latestValidHash"))
                  (cons "engineForkchoiceUpdatedV2TxpoolImportStatus"
                        (fixture-object-field
                         forkchoice-txpool-payload-status
                         "status"))
                  (cons "txpoolImportBlockHash"
                        replacement-txpool-block-hash)
                  (cons "txpoolImportBlockNumber"
                        expected-prepared-block-number)
                  (cons "txpoolImportTransactionHash"
                        (fixture-object-field
                         post-import-transaction
                         "hash"))
                  (cons "txpoolImportTransactionBlockHash"
                        (fixture-object-field
                         post-import-transaction
                         "blockHash"))
                  (cons "txpoolImportTransactionBlockNumber"
                        (fixture-object-field
                         post-import-transaction
                         "blockNumber"))
                  (cons "txpoolImportReceiptTransactionHash"
                        (fixture-object-field
                         post-import-receipt
                         "transactionHash"))
                  (cons "txpoolImportReceiptBlockHash"
                        (fixture-object-field
                         post-import-receipt
                         "blockHash"))
                  (cons "txpoolImportReceiptBlockNumber"
                        (fixture-object-field
                         post-import-receipt
                         "blockNumber"))
                  (cons "txpoolImportRawTransaction"
                        post-import-raw-transaction)
                  (cons "txpoolImportBlockTransactionCount"
                        (length post-import-block-transactions))
                  (cons "txpoolImportBlockTransactionHash"
                        (first post-import-block-transactions))
                  (cons "txpoolImportTxpoolStatusPending"
                        (fixture-object-field
                         post-import-txpool-status
                         "pending"))
                  (cons "txpoolImportTxpoolStatusQueued"
                        (fixture-object-field
                         post-import-txpool-status
                         "queued"))
                  (cons "txpoolImportSelectedStillPending"
                        (or (and post-import-txpool-content-from-selected
                                 (fixture-object-field
                                  post-import-txpool-content-from-selected
                                  "hash"))
                            :false))
                  (cons "txpoolImportNonSelectedBasefeeStillQueued"
                        (fixture-object-field
                         post-import-txpool-content-from-basefee-transaction
                         "hash"))
                  (cons "txpoolImportNonSelectedQueuedStillQueued"
                        (fixture-object-field
                         post-import-txpool-content-from-queued-transaction
                         "hash"))
                  (cons "remoteBlockHash" expected-remote-block-hash)
                  (cons "remoteBlockStatus"
                        (fixture-object-field remote-payload-result "status"))
                  (cons "invalidTipsetBlockHash"
                        expected-invalid-block-hash)
                  (cons "invalidTipsetStatus"
                        (fixture-object-field invalid-payload-result "status"))
                  (cons "invalidTipsetValidationError"
                        (fixture-object-field invalid-payload-result
                                              "validationError"))
                  (cons "txpoolPendingTransactionHash"
                        pending-transaction-hash-hex)
                  (cons "txpoolPendingTransactionRaw"
                        pending-transaction-raw)
                  (cons "txpoolReplacementTransactionHash"
                        replacement-transaction-hash-hex)
                  (cons "txpoolReplacementTransactionRaw"
                        replacement-transaction-raw)
                  (cons "txpoolPendingSender"
                        pending-transaction-sender-hex)
                  (cons "txpoolPendingNonce"
                        pending-transaction-nonce-key)
                  (cons "txpoolPendingSenderNonce"
                        (fixture-object-field pending-nonce-rpc "result"))
                  (cons "txpoolPendingInspectSummary"
                        txpool-inspect-transaction)
                  (cons "txpoolPendingFilterId" pending-filter-id)
                  (cons "txpoolPendingFilterHash"
                        (first pending-filter-changes))
                  (cons "txpoolPendingFilterChanges"
                        pending-filter-changes)
                  (cons "txpoolPendingFilterEmptyChanges"
                        empty-pending-filter-changes)
                  (cons "txpoolPendingFilterUninstallResult"
                        (fixture-object-field
                         uninstall-pending-filter-rpc
                         "result"))
                  (cons "txpoolPendingFilterMissingErrorCode"
                        (fixture-object-field
                         removed-pending-filter-error
                         "code"))
                  (cons "txpoolRejournalSeconds" 1)
                  (cons "txpoolRejournalObservedBeforeShutdown" t)
                  (cons "txpoolRejournalRecordCount"
                        (getf txpool-rejournal-report :record-count))
                  (cons "txpoolRejournalTransactionHash"
                        (getf txpool-rejournal-report
                              :transaction-hash))
                  (cons "txpoolRejournalSubpool"
                        (string-downcase
                         (symbol-name
                          (getf txpool-rejournal-report :subpool))))
                  (cons "devPeriodSeconds"
                        (getf dev-period-summary :dev-period-seconds))
                  (cons "devPeriodTransactionHash"
                        (getf dev-period-summary :transaction-hash))
                  (cons "devPeriodBlockNumber"
                        (getf dev-period-summary :block-number))
                  (cons "devPeriodBlockHash"
                        (getf dev-period-summary :block-hash))
                  (cons "devPeriodReceiptBlockNumber"
                        (getf dev-period-summary :receipt-block-number))
                  (cons "devPeriodReceiptBlockHash"
                        (getf dev-period-summary :receipt-block-hash))
                  (cons "devPeriodTransactionIndex"
                        (getf dev-period-summary :transaction-index))
                  (cons "devPeriodTxpoolStatusPending"
                        (getf dev-period-summary :txpool-status-pending))
                  (cons "devPeriodTxpoolStatusQueued"
                        (getf dev-period-summary :txpool-status-queued))
                  (cons "devPeriodPendingTransactionCount"
                        (getf dev-period-summary
                              :pending-transaction-count))
                  (cons "devPeriodEngineConnections"
                        (getf dev-period-summary :engine-connections))
                  (cons "devPeriodPublicConnections"
                        (getf dev-period-summary :public-connections))
                  (cons "devPeriodTotalConnections"
                        (getf dev-period-summary :total-connections))
                  (cons "txpoolBasefeeTransactionHash"
                        basefee-transaction-hash-hex)
                  (cons "txpoolBasefeeTransactionRaw"
                        basefee-transaction-raw)
                  (cons "txpoolBasefeeNonce"
                        basefee-transaction-nonce-key)
                  (cons "txpoolBasefeeInspectSummary"
                        txpool-inspect-basefee-transaction)
                  (cons "txpoolQueuedTransactionHash"
                        queued-transaction-hash-hex)
                  (cons "txpoolQueuedTransactionRaw"
                        queued-transaction-raw)
                  (cons "txpoolQueuedNonce"
                        queued-transaction-nonce-key)
                  (cons "txpoolQueuedInspectSummary"
                        txpool-inspect-queued-transaction)
                  (cons "txpoolStatusPending"
                        (fixture-object-field txpool-status "pending"))
                  (cons "txpoolStatusQueued"
                        (fixture-object-field txpool-status "queued"))
                  (cons "blockNumber" actual-block-number)
                  (cons "blockGasLimit"
                        (quantity-to-hex
                         (block-header-gas-limit
                          (block-header child-block))))
                  (cons "safeBlockNumber" expected-safe-block-number)
                  (cons "safeBlockGasLimit"
                        (quantity-to-hex
                         (block-header-gas-limit
                          (block-header parent-block))))
                  (cons "safeBlockHash"
                        (hash32-to-hex expected-safe-block-hash))
                  (cons "finalizedBlockNumber"
                        expected-finalized-block-number)
                  (cons "finalizedBlockHash"
                        (hash32-to-hex expected-finalized-block-hash))
                  (cons "checkedBalanceAddress"
                        (address-to-hex balance-address))
                  (cons "checkedBalanceField" balance-field)
                  (cons "checkedBalance" actual-balance)
                  (cons "checkedCheckpointBalance"
                        (getf (first checkpoint-balance-targets) :balance))
                  (cons "recipientBalance" actual-balance)
                  (cons "checkedBalanceCount" (length balance-targets))
                  (cons "transactionCount" (length transaction-checks))
                  (cons "checkedLogCount"
                        (reduce #'+ log-targets
                                :key (lambda (target)
                                       (getf target :count))
                                :initial-value 0))
                  (cons "checkedLogFilterCount"
                        (length log-targets))
                  (cons "checkedSimulationCount"
                        (if database-summary
                            (getf database-summary :rpc-simulation-count)
                            0))
                  (cons "checkedNonceAddress" (address-to-hex sender-address))
                  (cons "checkedNonce" expected-sender-nonce)
                  (cons "checkedCodeAddress" (address-to-hex code-address))
                  (cons "checkedCode" expected-code)
                  (cons "checkedStorageAddress"
                        (address-to-hex storage-address))
                  (cons "checkedStorageKey" storage-key)
                  (cons "checkedStorage" expected-storage)
                  (cons "checkedProofCodeHash"
                        (hash32-to-hex
                         (keccak-256-hash (hex-to-bytes expected-code))))
                  (cons "checkedProofStorageValue"
                        (quantity-to-hex (hex-to-quantity expected-storage)))
                  (cons "readyFile" (or ready-file :false))
                  (cons "engineEndpoint" +devnet-smoke-gate-engine-endpoint+)
                  (cons "rpcEndpoint" +devnet-smoke-gate-public-endpoint+)
                  (cons "logFile" (or log-file :false))
                  (cons "pidFile" (or pid-file :false))
                  (cons "databaseFile" (or database-file :false))
                  (cons "databasePruneStateBefore"
                        (or state-prune-before :false))
                  (cons "databasePrunedStateAvailable"
                        (if database-summary
                            (if (getf database-summary
                                      :pruned-state-available-p)
                                t
                                :false)
                            :false))
                  (cons "databaseHeadNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :head-number))
                            :false))
                  (cons "databaseHeadGasLimit"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :head-gas-limit))
                            :false))
                  (cons "databaseSafeNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :safe-number))
                            :false))
                  (cons "databaseSafeHash"
                        (if database-summary
                            (getf database-summary :safe-hash)
                            :false))
                  (cons "databaseFinalizedNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :finalized-number))
                            :false))
                  (cons "databaseFinalizedHash"
                        (if database-summary
                            (getf database-summary :finalized-hash)
                            :false))
                  (cons "databaseRpcBlockNumber"
                        (if database-summary
                            (getf database-summary :rpc-block-number)
                            :false))
                  (cons "databaseRpcBalance"
                        (if database-summary
                            (getf database-summary :rpc-balance)
                            :false))
                  (cons "databaseRpcNonce"
                        (if database-summary
                            (getf database-summary :rpc-nonce)
                            :false))
                  (cons "databaseRpcCode"
                        (if database-summary
                            (getf database-summary :rpc-code)
                            :false))
                  (cons "databaseRpcStorage"
                        (if database-summary
                            (getf database-summary :rpc-storage)
                            :false))
                  (cons "databaseRpcPreparedPayloadId"
                        (if database-summary
                            (getf database-summary
                                  :rpc-prepared-payload-id)
                            :false))
                  (cons "databaseRpcPreparedPayloadParentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-prepared-payload-parent-hash)
                            :false))
                  (cons "databaseRpcPreparedPayloadBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-prepared-payload-block-number)
                            :false))
                  (cons "databaseRemoteBlockHash"
                        (if database-summary
                            (getf database-summary :remote-block-hash)
                            :false))
                  (cons "databaseRpcRemoteBlockStatus"
                        (if database-summary
                            (getf database-summary
                                  :rpc-remote-block-status)
                            :false))
                  (cons "databaseInvalidTipsetBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :invalid-tipset-block-hash)
                            :false))
                  (cons "databaseRpcInvalidTipsetStatus"
                        (if database-summary
                            (getf database-summary
                                  :rpc-invalid-tipset-status)
                            :false))
                  (cons "databaseRpcInvalidTipsetValidationError"
                        (if database-summary
                            (getf database-summary
                                  :rpc-invalid-tipset-validation-error)
                            :false))
                  (cons "databaseRpcTxpoolPendingHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolRawTransaction"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-raw-transaction)
                            :false))
                  (cons "databaseRpcTxpoolSender"
                        (if database-summary
                            (getf database-summary :rpc-txpool-sender)
                            :false))
                  (cons "databaseRpcTxpoolNonce"
                        (if database-summary
                            (getf database-summary :rpc-txpool-nonce)
                            :false))
                  (cons "databaseRpcTxpoolInspectSummary"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-inspect-summary)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeRawTransaction"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-raw-transaction)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-nonce)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeInspectSummary"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-inspect-summary)
                            :false))
                  (cons "databaseRpcTxpoolQueuedHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolQueuedRawTransaction"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-raw-transaction)
                            :false))
                  (cons "databaseRpcTxpoolQueuedNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-nonce)
                            :false))
                  (cons "databaseRpcTxpoolQueuedInspectSummary"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-inspect-summary)
                            :false))
                  (cons "databaseRpcTxpoolStatusPending"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-status-pending)
                            :false))
                  (cons "databaseRpcTxpoolStatusQueued"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-status-queued)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-count)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockBaseFee"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-base-fee)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-number)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderParentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-parent-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-nonce)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderBaseFee"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-base-fee)
                            :false))
                  (cons "databaseRpcTxpoolPendingFeeHistoryNextBaseFee"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-fee-history-next-base-fee)
                            :false))
                  (cons "databaseRpcTxpoolPendingSenderNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-sender-nonce)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockTransactionBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-transaction-block-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingIndexHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-index-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingIndexBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-index-block-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingRawByIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-raw-index-transaction)
                            :false))
                  (cons "databaseRpcTxpoolContentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-content-hash)
                            :false))
                  (cons "databaseRpcTxpoolContentFromHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-content-from-hash)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeContentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-content-hash)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeContentFromHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-content-from-hash)
                            :false))
                  (cons "databaseRpcTxpoolQueuedContentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-content-hash)
                            :false))
                  (cons "databaseRpcTxpoolQueuedContentFromHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-content-from-hash)
                            :false))
                  (cons "databaseRpcTxpoolPublicConnections"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-public-connections)
                            :false))
                  (cons "databaseRpcProofAddress"
                        (if database-summary
                            (getf database-summary :rpc-proof-address)
                            :false))
                  (cons "databaseRpcProofCodeHash"
                        (if database-summary
                            (getf database-summary :rpc-proof-code-hash)
                            :false))
                  (cons "databaseRpcProofStorageKey"
                        (if database-summary
                            (getf database-summary :rpc-proof-storage-key)
                            :false))
                  (cons "databaseRpcProofStorageValue"
                        (if database-summary
                            (getf database-summary :rpc-proof-storage-value)
                            :false))
                  (cons "databaseRpcProofStorageCount"
                        (if database-summary
                            (getf database-summary :rpc-proof-storage-count)
                            :false))
                  (cons "databaseRpcProofAccountProofCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-proof-account-proof-count)
                            :false))
                  (cons "databaseRpcReceiptTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-receipt-transaction-hash)
                            :false))
                  (cons "databaseRpcReceiptBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-receipt-block-number)
                            :false))
                  (cons "databaseRpcBlockHash"
                        (if database-summary
                            (getf database-summary :rpc-block-hash)
                            :false))
                  (cons "databaseRpcBlockByHashNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-hash-number)
                            :false))
                  (cons "databaseRpcBlockTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-transaction-hash)
                            :false))
                  (cons "databaseRpcBlockByNumberHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-number-hash)
                            :false))
                  (cons "databaseRpcBlockByNumberNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-number-number)
                            :false))
                  (cons "databaseRpcBlockByNumberTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-number-transaction-hash)
                            :false))
                  (cons "databaseRpcFullBlockTransactionCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-transaction-count)
                            :false))
                  (cons "databaseRpcFullBlockTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-transaction-hash)
                            :false))
                  (cons "databaseRpcFullBlockTransactionIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-transaction-index)
                            :false))
                  (cons "databaseRpcFullBlockByNumberTransactionCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-by-number-transaction-count)
                            :false))
                  (cons "databaseRpcFullBlockByNumberTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-by-number-transaction-hash)
                            :false))
                  (cons "databaseRpcFullBlockByNumberTransactionIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-by-number-transaction-index)
                            :false))
                  (cons "databaseRpcTransactionHash"
                        (if database-summary
                            (getf database-summary :rpc-transaction-hash)
                            :false))
                  (cons "databaseRpcTransactionBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-block-hash)
                            :false))
                  (cons "databaseRpcTransactionBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-block-number)
                            :false))
                  (cons "databaseRpcBlockReceiptsCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipts-count)
                            :false))
                  (cons "databaseRpcBlockReceiptTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipt-transaction-hash)
                            :false))
                  (cons "databaseRpcBlockReceiptBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipt-block-hash)
                            :false))
                  (cons "databaseRpcBlockReceiptBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipt-block-number)
                            :false))
                  (cons "databaseRpcBlockTransactionCountByHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-transaction-count-by-hash)
                            :false))
                  (cons "databaseRpcBlockTransactionCountByNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-transaction-count-by-number)
                            :false))
                  (cons "databaseRpcCanonicalHashBalance"
                        (if database-summary
                            (getf database-summary
                                  :rpc-canonical-hash-balance)
                            :false))
                  (cons "databaseRpcCanonicalHashRequireBalance"
                        (if database-summary
                            (getf database-summary
                                  :rpc-canonical-hash-require-balance)
                            :false))
                  (cons "databaseRpcTransactionCount"
                        (if database-summary
                            (getf database-summary :rpc-transaction-count)
                            :false))
                  (cons "databaseRpcBalanceCount"
                        (if database-summary
                            (getf database-summary :rpc-balance-count)
                            :false))
                  (cons "databaseRpcLogCount"
                        (if database-summary
                            (getf database-summary :rpc-log-count)
                            :false))
                  (cons "databaseRpcLogFilterCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-log-filter-count)
                            :false))
                  (cons "databaseRpcLogFilterLogCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-log-filter-log-count)
                            :false))
                  (cons "databaseRpcLogFilterUninstallCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-log-filter-uninstall-count)
                            :false))
                  (cons "databaseRpcLogFilterMissingErrorCodes"
                        (if database-summary
                            (getf database-summary
                                  :rpc-log-filter-missing-error-codes)
                            :false))
                  (cons "databaseRpcBlockFilterId"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-id)
                            :false))
                  (cons "databaseRpcBlockFilterChangeCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-change-count)
                            :false))
                  (cons "databaseRpcBlockFilterGetLogsErrorCode"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-get-logs-error-code)
                            :false))
                  (cons "databaseRpcBlockFilterUninstallResult"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-uninstall-result)
                            :false))
                  (cons "databaseRpcBlockFilterMissingErrorCode"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-missing-error-code)
                            :false))
                  (cons "databaseRpcRawTransactionByBlockHashAndIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-raw-transaction-by-hash)
                            :false))
                  (cons "databaseRpcRawTransactionByHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-raw-transaction)
                            :false))
                  (cons "databaseRpcRawTransactionByBlockNumberAndIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-raw-transaction-by-number)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-block-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-block-number)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-transaction-index)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-block-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-block-number)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-transaction-index)
                            :false))
                  (cons "databaseRpcSafeBlockHash"
                        (if database-summary
                            (getf database-summary :rpc-safe-block-hash)
                            :false))
                  (cons "databaseRpcSafeBlockNumber"
                        (if database-summary
                            (getf database-summary :rpc-safe-block-number)
                            :false))
                  (cons "databaseRpcFinalizedBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-finalized-block-hash)
                            :false))
                  (cons "databaseRpcFinalizedBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-finalized-block-number)
                            :false))
                  (cons "databaseRpcCallResult"
                        (if database-summary
                            (getf database-summary :rpc-call-result)
                            :false))
                  (cons "databaseRpcFailedCallError"
                        (if database-summary
                            (getf database-summary
                                  :rpc-failed-call-error-message)
                            :false))
                  (cons "databaseRpcEstimateGas"
                        (if database-summary
                            (getf database-summary :rpc-estimate-gas)
                            :false))
                  (cons "databaseRpcAccessListCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-access-list-count)
                            :false))
                  (cons "databaseRpcAccessListGasUsed"
                        (if database-summary
                            (getf database-summary
                                  :rpc-access-list-gas-used)
                            :false))
                  (cons "databaseRpcPostCallStorage"
                        (if database-summary
                            (getf database-summary
                                  :rpc-post-call-storage)
                            :false))
                  (cons "databaseRpcSimulationCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-simulation-count)
                            :false))
                  (cons "databaseRpcPrunedStateError"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-pruned-state-error-message)
                                :false)
                            :false))
                  (cons "databaseRpcPrunedStateErrors"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-pruned-state-error-messages)
                                :false)
                            :false))
                  (cons "databaseRpcPublicConnections"
                        (if database-summary
                            (getf database-summary :rpc-public-connections)
                            :false))
                  (cons "databaseRpcSideBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideForkchoiceStatus"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-forkchoice-status)
                                :false)
                            :false))
                  (cons "databaseRpcSideRejectedCheckpointError"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-rejected-checkpoint-error)
                                :false)
                            :false))
                  (cons "databaseRpcSideBlockNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-block-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideLatestBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-latest-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideTransactionReinserted"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-transaction-reinserted-p)
                                :false)
                            :false))
                  (cons "databaseRpcSideTransactionByHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-transaction-by-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRawTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-raw-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSidePendingTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-pending-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSideReinsertedTransactionCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-reinserted-transaction-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideReinsertedTransactionHashes"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-reinserted-transaction-hashes)
                                :false)
                            :false))
                  (cons "databaseRpcSideReceipt"
                        (if database-summary
                            (or (getf database-summary :rpc-side-receipt)
                                :false)
                            :false))
                  (cons "databaseRpcSideHiddenReceiptCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-hidden-receipt-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideChildBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-child-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideBlockReceiptsCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-block-receipts-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideLogCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-log-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredHeadNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-head-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredHeadHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-head-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcBlockNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-block-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcLatestBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-latest-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredSafeNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-safe-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredSafeHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-safe-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredFinalizedNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-finalized-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredFinalizedHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-finalized-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcSafeNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-safe-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcSafeHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-safe-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcFinalizedNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-finalized-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcFinalizedHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-finalized-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredSafeBalance"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-safe-balance)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredFinalizedBalance"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-finalized-balance)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRawTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-raw-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredPendingTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-pending-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredReinsertedTransactionCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-reinserted-transaction-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredReinsertedTransactionHashes"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-reinserted-transaction-hashes)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredReceipt"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-receipt)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredHiddenReceiptCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-hidden-receipt-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredChildBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-child-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredChildRequireCanonicalError"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-child-require-canonical-error)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredChildRequireCanonicalErrors"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-child-require-canonical-errors)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredBlockReceiptsCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-block-receipts-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredLogCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-log-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredPublicConnections"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-public-connections)
                                :false)
                            :false))
                  (cons "databaseRpcSideTotalConnections"
                        (if database-summary
                            (let ((side-engine
                                    (getf database-summary
                                          :rpc-side-engine-connections))
                                  (side-public
                                    (getf database-summary
                                          :rpc-side-public-connections))
                                  (side-restored-public
                                    (getf database-summary
                                          :rpc-side-restored-public-connections)))
                              (if (and side-engine
                                       side-public
                                       side-restored-public)
                                  (+ side-engine
                                     side-public
                                     side-restored-public)
                                  :false))
                            :false))
                  (cons "databaseRpcSideEngineConnections"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-engine-connections)
                                :false)
                            :false))
                  (cons "databaseRpcSidePublicConnections"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-public-connections)
                                :false)
                            :false))))))))))))
             (let* ((ready-summary
                      (when ready-file
                        (devnet-smoke-gate-verify-ready-file
                         ready-file
                         (devnet-smoke-gate-field report "safeBlockNumber")
                         (devnet-smoke-gate-field report "safeBlockHash")
                         :expected-head-gas-limit
                         (devnet-smoke-gate-field report "safeBlockGasLimit")
                         :expected-engine-endpoint
                         (devnet-smoke-gate-field report "engineEndpoint")
                         :expected-rpc-endpoint
                         (devnet-smoke-gate-field report "rpcEndpoint"))))
                    (ready-process-id
                      (and ready-summary
                           (fixture-object-field ready-summary "processId")))
                    (pid-file-process-id
                      (when pid-file
                        (devnet-smoke-gate-verify-pid-file
                         pid-file
                         :expected-process-id ready-process-id)))
                    (expected-process-id
                      (or pid-file-process-id ready-process-id)))
               (when log-file
                 (devnet-smoke-gate-verify-log-file
	                  log-file
	                  (devnet-smoke-gate-field report "safeBlockNumber")
	                  (devnet-smoke-gate-field report "safeBlockHash")
	                  (devnet-smoke-gate-field report
	                                           "txpoolImportBlockNumber")
	                  (devnet-smoke-gate-field report
	                                           "txpoolImportBlockHash")
                  :ready-head-gas-limit
                  (devnet-smoke-gate-field report "safeBlockGasLimit")
                  :shutdown-head-gas-limit
                  (devnet-smoke-gate-field report "blockGasLimit")
                  :expected-process-id expected-process-id
                  :expected-connection-summary
                  (list :engine-connections
                        (fixture-object-field report "engineConnections")
                        :public-connections
                        (fixture-object-field report "publicConnections")
                        :total-connections
                        (fixture-object-field report "totalConnections"))
                  :expected-engine-endpoint
                  (devnet-smoke-gate-field report "engineEndpoint")
                  :expected-rpc-endpoint
                  (devnet-smoke-gate-field report "rpcEndpoint")))
               report)))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file journal-path)
        (delete-file journal-path))))
  #-sbcl
  (error "Devnet smoke gate requires SBCL threads"))

(defun devnet-smoke-gate-sanitize-path-component (value)
  (coerce
   (map 'list
        (lambda (char)
          (if (or (alphanumericp char)
                  (member char '(#\- #\_) :test #'char=))
              char
              #\_))
        value)
   'string))

(defun devnet-smoke-gate-case-path (path case-name &key default-name)
  (when path
    (let* ((pathname (pathname path))
           (name (or (pathname-name pathname) "devnet-chain"))
           (type (pathname-type pathname))
           (case-component
             (devnet-smoke-gate-sanitize-path-component case-name)))
      (namestring
       (make-pathname
        :name (format nil "~A-~A"
                      (or name default-name "devnet-artifact")
                      case-component)
        :type type
        :defaults pathname)))))

(defun devnet-smoke-gate-run-all
    (case-names &key ready-file log-file pid-file database-file
       state-prune-before terminal-total-difficulty
       terminal-total-difficulty-passed-p terminal-block-hash
       terminal-block-number)
  (let* ((reports
           (mapcar (lambda (case-name)
                     (devnet-smoke-gate-strip-run-metadata
                      (devnet-smoke-gate-run
                       case-name
                       :ready-file
                       (devnet-smoke-gate-case-path
                        ready-file case-name :default-name "ready")
                       :log-file
                       (devnet-smoke-gate-case-path
                        log-file case-name :default-name "devnet")
                       :pid-file
                       (devnet-smoke-gate-case-path
                        pid-file case-name :default-name "devnet")
                       :database-file
                       (devnet-smoke-gate-case-path
                        database-file case-name
                        :default-name "devnet-chain")
                       :state-prune-before state-prune-before
                       :terminal-total-difficulty
                       terminal-total-difficulty
                       :terminal-total-difficulty-passed-p
                       terminal-total-difficulty-passed-p
                       :terminal-block-hash terminal-block-hash
                       :terminal-block-number terminal-block-number)))
                   case-names))
         (engine-connections
           (reduce #'+ reports
                   :key (lambda (report)
                          (devnet-smoke-gate-field report
                                                   "engineConnections"))
                   :initial-value 0))
         (public-connections
           (reduce #'+ reports
                   :key (lambda (report)
                          (devnet-smoke-gate-field report
                                                   "publicConnections"))
                   :initial-value 0))
         (pruned-state-case-count
           (count-if
            (lambda (report)
              (devnet-smoke-gate-report-pruned-state-covered-p
               report state-prune-before))
            reports))
         (pruned-state-error-case-count
           (count-if
            (lambda (report)
              (let ((errors
                      (devnet-smoke-gate-field
                       report "databaseRpcPrunedStateErrors")))
                (and errors
                     (equal (devnet-smoke-gate-pruned-state-error-messages)
                            errors))))
            reports)))
    (devnet-smoke-gate-require
     (= (length case-names) (length reports))
     "Devnet smoke gate suite case count mismatch")
    (when database-file
      (dolist (report reports)
        (let ((expected-head-number
                (or (devnet-smoke-gate-field report "txpoolImportBlockNumber")
                    (devnet-smoke-gate-field report "blockNumber"))))
          (devnet-smoke-gate-require
           (string= expected-head-number
                    (devnet-smoke-gate-field report "databaseHeadNumber"))
           "Devnet smoke gate suite database head mismatch for ~A"
           (devnet-smoke-gate-field report "fixtureCase")))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockNumber")
                  (devnet-smoke-gate-field report "databaseSafeNumber"))
         "Devnet smoke gate suite database safe checkpoint mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockHash")
                  (devnet-smoke-gate-field report "databaseSafeHash"))
         "Devnet smoke gate suite database safe hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockNumber")
                  (devnet-smoke-gate-field report "databaseFinalizedNumber"))
         "Devnet smoke gate suite database finalized checkpoint mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                  (devnet-smoke-gate-field report "databaseFinalizedHash"))
         "Devnet smoke gate suite database finalized hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (let ((pruned-state-covered-p
                (devnet-smoke-gate-report-pruned-state-covered-p
                 report state-prune-before))
              (pruned-errors
                (devnet-smoke-gate-field
                 report "databaseRpcPrunedStateErrors")))
          (if pruned-state-covered-p
              (progn
                (devnet-smoke-gate-require
                 (devnet-smoke-gate-false-p
                  (devnet-smoke-gate-field
                   report "databasePrunedStateAvailable"))
                 "Devnet smoke gate suite pruned state still available for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (equal (devnet-smoke-gate-pruned-state-error-messages)
                        pruned-errors)
                 "Devnet smoke gate suite pruned-state RPC errors mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase")))
              (when state-prune-before
                (devnet-smoke-gate-require
                 (devnet-smoke-gate-field
                  report "databasePrunedStateAvailable")
                 "Devnet smoke gate suite unexpectedly pruned state for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (devnet-smoke-gate-false-p pruned-errors)
                 "Devnet smoke gate suite unexpected pruned-state RPC errors for ~A"
                 (devnet-smoke-gate-field report "fixtureCase")))))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedCode")
                  (devnet-smoke-gate-field report "databaseRpcCode"))
         "Devnet smoke gate suite restored code mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedNonce")
                  (devnet-smoke-gate-field report "databaseRpcNonce"))
         "Devnet smoke gate suite restored nonce mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorage")
                  (devnet-smoke-gate-field report "databaseRpcStorage"))
         "Devnet smoke gate suite restored storage mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorageAddress")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofAddress"))
         "Devnet smoke gate suite restored proof address mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedProofCodeHash")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofCodeHash"))
         "Devnet smoke gate suite restored proof code hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorageKey")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofStorageKey"))
         "Devnet smoke gate suite restored proof storage key mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedProofStorageValue")
                  (devnet-smoke-gate-field report
                                           "databaseRpcProofStorageValue"))
         "Devnet smoke gate suite restored proof storage value mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= 1 (devnet-smoke-gate-field report
                                       "databaseRpcProofStorageCount"))
         "Devnet smoke gate suite restored proof storage count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (<= 0 (devnet-smoke-gate-field
                report "databaseRpcProofAccountProofCount"))
         "Devnet smoke gate suite restored proof account proof count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcReceiptBlockNumber"))
         "Devnet smoke gate suite restored receipt block mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcBlockByHashNumber"))
         "Devnet smoke gate suite restored block-by-hash number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockByNumberNumber"))
         "Devnet smoke gate suite restored block-by-number number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionBlockNumber"))
         "Devnet smoke gate suite restored transaction block mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockReceiptBlockNumber"))
         "Devnet smoke gate suite restored block receipt number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field report
                                     "databaseRpcBlockReceiptsCount"))
         "Devnet smoke gate suite restored block receipts count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (quantity-to-hex
                   (devnet-smoke-gate-field report "transactionCount"))
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockTransactionCountByHash"))
         "Devnet smoke gate suite restored block tx count by hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (quantity-to-hex
                   (devnet-smoke-gate-field report "transactionCount"))
                  (devnet-smoke-gate-field
                   report "databaseRpcBlockTransactionCountByNumber"))
         "Devnet smoke gate suite restored block tx count by number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field report "databaseRpcTransactionCount"))
         "Devnet smoke gate suite restored transaction count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field
             report "databaseRpcFullBlockTransactionCount"))
         "Devnet smoke gate suite restored full block transaction count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "transactionCount")
            (devnet-smoke-gate-field
             report "databaseRpcFullBlockByNumberTransactionCount"))
         "Devnet smoke gate suite restored full block-by-number transaction count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockTransactionHash"))
         "Devnet smoke gate suite restored full block transaction hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockByNumberTransactionHash"))
         "Devnet smoke gate suite restored full block-by-number transaction hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockTransactionIndex"))
         "Devnet smoke gate suite restored full block transaction index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcFullBlockByNumberTransactionIndex"))
         "Devnet smoke gate suite restored full block-by-number transaction index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedBalanceCount")
            (devnet-smoke-gate-field report "databaseRpcBalanceCount"))
         "Devnet smoke gate suite restored balance count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedLogCount")
            (devnet-smoke-gate-field report "databaseRpcLogCount"))
         "Devnet smoke gate suite restored log count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedLogFilterCount")
            (devnet-smoke-gate-field report "databaseRpcLogFilterCount"))
         "Devnet smoke gate suite restored log filter count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedLogCount")
            (devnet-smoke-gate-field report "databaseRpcLogFilterLogCount"))
         "Devnet smoke gate suite restored log filter log count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedLogFilterCount")
            (devnet-smoke-gate-field
             report "databaseRpcLogFilterUninstallCount"))
         "Devnet smoke gate suite restored log filter uninstall count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (let ((missing-error-codes
                (devnet-smoke-gate-field
                 report "databaseRpcLogFilterMissingErrorCodes")))
          (devnet-smoke-gate-require
           (= (devnet-smoke-gate-field report "checkedLogFilterCount")
              (length missing-error-codes))
           "Devnet smoke gate suite restored log filter missing error count mismatch for ~A"
           (devnet-smoke-gate-field report "fixtureCase"))
          (devnet-smoke-gate-require
           (every (lambda (code)
                    (= -32602 code))
                  missing-error-codes)
           "Devnet smoke gate suite restored log filter missing error code mismatch for ~A"
           (devnet-smoke-gate-field report "fixtureCase")))
        (devnet-smoke-gate-require
         (= (devnet-smoke-gate-field report "checkedSimulationCount")
            (devnet-smoke-gate-field report "databaseRpcSimulationCount"))
         "Devnet smoke gate suite restored simulation count mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x"
                  (devnet-smoke-gate-field report "databaseRpcCallResult"))
         "Devnet smoke gate suite restored eth_call mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (if (devnet-smoke-gate-executable-code-p
             (devnet-smoke-gate-field report "checkedCode"))
            (devnet-smoke-gate-require
             (string= "eth_call execution failed"
                      (devnet-smoke-gate-field
                       report "databaseRpcFailedCallError"))
             "Devnet smoke gate suite restored failing eth_call mismatch for ~A"
             (devnet-smoke-gate-field report "fixtureCase"))
            (devnet-smoke-gate-require
             (devnet-smoke-gate-false-p
              (devnet-smoke-gate-field report "databaseRpcFailedCallError"))
             "Devnet smoke gate suite unexpected failing eth_call for ~A"
             (devnet-smoke-gate-field report "fixtureCase")))
        (devnet-smoke-gate-require
         (<= 21000
             (hex-to-quantity
              (devnet-smoke-gate-field report "databaseRpcEstimateGas")))
         "Devnet smoke gate suite restored estimateGas mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (stringp (devnet-smoke-gate-field
                   report "databaseRpcAccessListGasUsed"))
         "Devnet smoke gate suite restored access list gasUsed mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "checkedStorage")
                  (devnet-smoke-gate-field
                   report "databaseRpcPostCallStorage"))
         "Devnet smoke gate suite restored eth_call mutated storage for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByBlockHashAndIndex")
                  (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByBlockNumberAndIndex"))
         "Devnet smoke gate suite restored raw transaction index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcRawTransactionByBlockHashAndIndex"))
         "Devnet smoke gate suite restored raw transaction hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockHashAndIndexHash"))
         "Devnet smoke gate suite restored tx by hash/index hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field
                   report "databaseRpcReceiptTransactionHash")
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockNumberAndIndexHash"))
         "Devnet smoke gate suite restored tx by number/index hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "databaseRpcBlockHash")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockHashAndIndexBlockHash"))
         "Devnet smoke gate suite restored tx by hash/index block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "databaseRpcBlockHash")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockNumberAndIndexBlockHash"))
         "Devnet smoke gate suite restored tx by number/index block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockHashAndIndexBlockNumber"))
         "Devnet smoke gate suite restored tx by hash/index block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "blockNumber")
                  (devnet-smoke-gate-field
                   report
                   "databaseRpcTransactionByBlockNumberAndIndexBlockNumber"))
         "Devnet smoke gate suite restored tx by number/index block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockHashAndIndexIndex"))
         "Devnet smoke gate suite restored tx by hash/index index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= "0x0"
                  (devnet-smoke-gate-field
                   report "databaseRpcTransactionByBlockNumberAndIndexIndex"))
         "Devnet smoke gate suite restored tx by number/index index mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockHash")
                  (devnet-smoke-gate-field report
                                           "databaseRpcSafeBlockHash"))
         "Devnet smoke gate suite restored safe block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "safeBlockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcSafeBlockNumber"))
         "Devnet smoke gate suite restored safe block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                  (devnet-smoke-gate-field report
                                           "databaseRpcFinalizedBlockHash"))
         "Devnet smoke gate suite restored finalized block hash mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (devnet-smoke-gate-require
         (string= (devnet-smoke-gate-field report "finalizedBlockNumber")
                  (devnet-smoke-gate-field report
                                           "databaseRpcFinalizedBlockNumber"))
         "Devnet smoke gate suite restored finalized block number mismatch for ~A"
         (devnet-smoke-gate-field report "fixtureCase"))
        (if state-prune-before
            (devnet-smoke-gate-require
             (devnet-smoke-gate-false-p
              (devnet-smoke-gate-field report "databaseRpcSideBlockHash"))
             "Devnet smoke gate suite unexpectedly ran side reorg for pruned database ~A"
             (devnet-smoke-gate-field report "fixtureCase"))
            (progn
              (devnet-smoke-gate-require
               (string= +payload-status-valid+
                        (devnet-smoke-gate-field
                         report "databaseRpcSideForkchoiceStatus"))
               "Devnet smoke gate suite side forkchoice status mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= "forkchoice safe block is not an ancestor of head"
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRejectedCheckpointError"))
               "Devnet smoke gate suite side rejected checkpoint error mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "blockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideBlockNumber"))
               "Devnet smoke gate suite side block number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcSideBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideLatestBlockHash"))
               "Devnet smoke gate suite side latest hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcSideBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredHeadHash"))
               "Devnet smoke gate suite side restored head hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "blockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredHeadNumber"))
               "Devnet smoke gate suite side restored head number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "blockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcBlockNumber"))
               "Devnet smoke gate suite side fresh public block number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcSideBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcLatestBlockHash"))
               "Devnet smoke gate suite side fresh latest hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredSafeHash"))
               "Devnet smoke gate suite side restored safe hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredSafeNumber"))
               "Devnet smoke gate suite side restored safe number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredFinalizedHash"))
               "Devnet smoke gate suite side restored finalized hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report
                                                 "finalizedBlockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredFinalizedNumber"))
               "Devnet smoke gate suite side restored finalized number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcSafeHash"))
               "Devnet smoke gate suite side restored public safe hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "safeBlockNumber")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcSafeNumber"))
               "Devnet smoke gate suite side restored public safe number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report "finalizedBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredRpcFinalizedHash"))
               "Devnet smoke gate suite side restored public finalized hash mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field report
                                                 "finalizedBlockNumber")
                        (devnet-smoke-gate-field
                         report
                         "databaseRpcSideRestoredRpcFinalizedNumber"))
               "Devnet smoke gate suite side restored public finalized number mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "checkedCheckpointBalance")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredSafeBalance"))
               "Devnet smoke gate suite side restored safe balance mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "checkedCheckpointBalance")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredFinalizedBalance"))
               "Devnet smoke gate suite side restored finalized balance mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (not (string= (devnet-smoke-gate-field
                              report "databaseRpcBlockHash")
                             (devnet-smoke-gate-field
                              report "databaseRpcSideBlockHash")))
               "Devnet smoke gate suite side block reused child hash for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideChildBlockHash"))
               "Devnet smoke gate suite side reorg lost child block for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideBlockReceiptsCount"))
               "Devnet smoke gate suite side reorg kept canonical receipts for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideLogCount"))
               "Devnet smoke gate suite side reorg kept canonical logs for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (if (not (devnet-smoke-gate-false-p
                        (devnet-smoke-gate-field
                         report "databaseRpcSideTransactionReinserted")))
                  (progn
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               (devnet-smoke-gate-field
                                report "databaseRpcSideTransactionByHash")
                               "hash"))
                     "Devnet smoke gate suite side reorg lost pending transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSideTransactionByHash")
                            "blockHash"))
                     "Devnet smoke gate suite side reorg kept old transaction block hash for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSideTransactionByHash")
                            "blockNumber"))
                     "Devnet smoke gate suite side reorg kept old transaction block number for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSideTransactionByHash")
                            "transactionIndex"))
                     "Devnet smoke gate suite side reorg kept old transaction index for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcRawTransactionByHash")
                              (devnet-smoke-gate-field
                               report "databaseRpcSideRawTransaction"))
                     "Devnet smoke gate suite side reorg lost pending raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               (devnet-smoke-gate-field
                                report "databaseRpcSidePendingTransaction")
                               "hash"))
                     "Devnet smoke gate suite side reorg lost pending transaction pool view for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSidePendingTransaction")
                            "blockHash"))
                     "Devnet smoke gate suite side reorg pending view kept old block hash for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSidePendingTransaction")
                            "blockNumber"))
                     "Devnet smoke gate suite side reorg pending view kept old block number for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report "databaseRpcSidePendingTransaction")
                            "transactionIndex"))
                     "Devnet smoke gate suite side reorg pending view kept old transaction index for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcRawTransactionByHash")
                              (devnet-smoke-gate-field
                               report "databaseRpcSideRestoredRawTransaction"))
                     "Devnet smoke gate suite side reorg fresh restore lost pending raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (string= (devnet-smoke-gate-field
                               report "databaseRpcReceiptTransactionHash")
                              (fixture-object-field
                               (devnet-smoke-gate-field
                                report "databaseRpcSideRestoredPendingTransaction")
                               "hash"))
                     "Devnet smoke gate suite side reorg fresh restore lost pending transaction view for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report
                             "databaseRpcSideRestoredPendingTransaction")
                            "blockHash"))
                     "Devnet smoke gate suite side reorg fresh pending view kept old block hash for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report
                             "databaseRpcSideRestoredPendingTransaction")
                            "blockNumber"))
                     "Devnet smoke gate suite side reorg fresh pending view kept old block number for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (null (fixture-object-field
                            (devnet-smoke-gate-field
                             report
                             "databaseRpcSideRestoredPendingTransaction")
                            "transactionIndex"))
                     "Devnet smoke gate suite side reorg fresh pending view kept old transaction index for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (= (devnet-smoke-gate-field
                         report "databaseRpcTransactionCount")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideHiddenReceiptCount"))
                     "Devnet smoke gate suite side hidden receipt count mismatch for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (= (devnet-smoke-gate-field
                         report "databaseRpcTransactionCount")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredHiddenReceiptCount"))
                     "Devnet smoke gate suite side fresh hidden receipt count mismatch for ~A"
                     (devnet-smoke-gate-field report "fixtureCase")))
                  (progn
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideTransactionByHash"))
                     "Devnet smoke gate suite side reorg reinserted wrong-chain transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideRawTransaction"))
                     "Devnet smoke gate suite side reorg exposed wrong-chain raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSidePendingTransaction"))
                     "Devnet smoke gate suite side reorg exposed wrong-chain pending transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredRawTransaction"))
                     "Devnet smoke gate suite side reorg fresh restore exposed wrong-chain raw transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))
                    (devnet-smoke-gate-require
                     (devnet-smoke-gate-false-p
                      (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredPendingTransaction"))
                     "Devnet smoke gate suite side reorg fresh restore exposed wrong-chain pending transaction for ~A"
                     (devnet-smoke-gate-field report "fixtureCase"))))
              (devnet-smoke-gate-require
               (devnet-smoke-gate-false-p
                (devnet-smoke-gate-field report "databaseRpcSideReceipt"))
               "Devnet smoke gate suite side reorg kept old receipt canonical for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (devnet-smoke-gate-false-p
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredReceipt"))
               "Devnet smoke gate suite side reorg fresh restore kept old receipt canonical for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= (devnet-smoke-gate-field
                         report "databaseRpcBlockHash")
                        (devnet-smoke-gate-field
                         report "databaseRpcSideRestoredChildBlockHash"))
               "Devnet smoke gate suite side fresh restore lost child block for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (string= "eth_getBalance block hash is not canonical"
                        (devnet-smoke-gate-field
                         report
                         "databaseRpcSideRestoredChildRequireCanonicalError"))
               "Devnet smoke gate suite side fresh restore child requireCanonical error mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (equal (devnet-smoke-gate-noncanonical-state-error-messages)
                      (devnet-smoke-gate-field
                       report
                       "databaseRpcSideRestoredChildRequireCanonicalErrors"))
               "Devnet smoke gate suite side fresh restore child requireCanonical state errors mismatch for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredBlockReceiptsCount"))
               "Devnet smoke gate suite side fresh restore kept canonical receipts for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (devnet-smoke-gate-require
               (zerop (devnet-smoke-gate-field
                       report "databaseRpcSideRestoredLogCount"))
               "Devnet smoke gate suite side fresh restore kept canonical logs for ~A"
               (devnet-smoke-gate-field report "fixtureCase"))
              (let* ((transaction-count
                       (devnet-smoke-gate-field
                        report "databaseRpcTransactionCount"))
                     (extra-transaction-count (max 0 (1- transaction-count)))
                     (side-public-connections
                       (+ 9 extra-transaction-count))
                     (restored-public-connections
                       (+ 20 extra-transaction-count)))
                (devnet-smoke-gate-require
                 (= 3 (devnet-smoke-gate-field
                       report "databaseRpcSideEngineConnections"))
                 "Devnet smoke gate suite side Engine connection count mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (= side-public-connections
                    (devnet-smoke-gate-field
                     report "databaseRpcSidePublicConnections"))
                 "Devnet smoke gate suite side public connection count mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (= restored-public-connections
                    (devnet-smoke-gate-field
                     report "databaseRpcSideRestoredPublicConnections"))
                 "Devnet smoke gate suite side fresh public connection count mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase"))
                (devnet-smoke-gate-require
                 (= (+ 3 side-public-connections restored-public-connections)
                    (devnet-smoke-gate-field
                     report "databaseRpcSideTotalConnections"))
                 "Devnet smoke gate suite side total connection count mismatch for ~A"
                 (devnet-smoke-gate-field report "fixtureCase")))))))
    (devnet-smoke-gate-add-run-metadata
     (list
     (cons "status" "ok")
     (cons "mode" "devnet-listener-boundary-suite")
     (cons "caseCount" (length reports))
     (cons "fixtureCases" case-names)
     (cons "readyFile" (or ready-file :false))
     (cons "readyCaseCount" (if ready-file (length reports) 0))
     (cons "logFile" (or log-file :false))
     (cons "logCaseCount" (if log-file (length reports) 0))
     (cons "pidFile" (or pid-file :false))
     (cons "pidCaseCount" (if pid-file (length reports) 0))
     (cons "databaseFile" (or database-file :false))
     (cons "databasePruneStateBefore" (or state-prune-before :false))
     (cons "databaseCaseCount" (if database-file (length reports) 0))
     (cons "databasePrunedStateCaseCount" pruned-state-case-count)
     (cons "databaseRpcPrunedStateErrorCaseCount"
           pruned-state-error-case-count)
     (cons "engineConnections" engine-connections)
     (cons "publicConnections" public-connections)
     (cons "totalConnections" (+ engine-connections public-connections))
     (cons "connectionContract"
           (devnet-smoke-gate-connection-contract (length reports)))
     (cons "cases" reports)))))

(defun devnet-smoke-gate-suite-report-p (report)
  (string= "devnet-listener-boundary-suite"
           (or (devnet-smoke-gate-field report "mode") "")))

(defun devnet-smoke-gate-engine-only-report-p (report)
  (string= "devnet-engine-only-serve"
           (or (devnet-smoke-gate-field report "mode") "")))

(defun devnet-smoke-gate-print-text (report)
  (format t "~&status=~A~%" (devnet-smoke-gate-field report "status"))
  (format t "mode=~A~%" (devnet-smoke-gate-field report "mode"))
  (let ((execution-spec-tests
          (devnet-smoke-gate-field report "executionSpecTests"))
        (reference-clients
          (devnet-smoke-gate-field report "referenceClients")))
    (format t "executionSpecTestsRepository=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "repository"))
    (format t "executionSpecTestsRelease=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "release"))
    (format t "executionSpecTestsTagTarget=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "tagTarget"))
    (format t "executionSpecTestsArchive=~A~%"
            (devnet-smoke-gate-field execution-spec-tests "archive"))
    (dolist (client reference-clients)
      (format t "referenceClient[~A]=~A"
              (devnet-smoke-gate-field client "name")
              (devnet-smoke-gate-field client "status"))
      (when (devnet-smoke-gate-field client "commit")
        (format t ":~A" (devnet-smoke-gate-field client "commit")))
      (format t "~%")))
  (when (devnet-smoke-gate-suite-report-p report)
    (format t "caseCount=~D~%" (devnet-smoke-gate-field report "caseCount"))
    (format t "readyFile=~A~%"
            (devnet-smoke-gate-field report "readyFile"))
    (format t "readyCaseCount=~D~%"
            (devnet-smoke-gate-field report "readyCaseCount"))
    (format t "logFile=~A~%"
            (devnet-smoke-gate-field report "logFile"))
    (format t "logCaseCount=~D~%"
            (devnet-smoke-gate-field report "logCaseCount"))
    (format t "pidFile=~A~%"
            (devnet-smoke-gate-field report "pidFile"))
    (format t "pidCaseCount=~D~%"
            (devnet-smoke-gate-field report "pidCaseCount"))
    (format t "databaseFile=~A~%"
            (devnet-smoke-gate-field report "databaseFile"))
    (format t "databasePruneStateBefore=~A~%"
            (devnet-smoke-gate-field report "databasePruneStateBefore"))
    (format t "databaseCaseCount=~D~%"
            (devnet-smoke-gate-field report "databaseCaseCount"))
    (format t "databasePrunedStateCaseCount=~D~%"
            (devnet-smoke-gate-field report
                                     "databasePrunedStateCaseCount"))
    (format t "databaseRpcPrunedStateErrorCaseCount=~D~%"
            (devnet-smoke-gate-field
             report "databaseRpcPrunedStateErrorCaseCount")))
  (when (devnet-smoke-gate-engine-only-report-p report)
    (format t "publicRpcEnabled=~A~%"
            (devnet-smoke-gate-field report "publicRpcEnabled"))
    (format t "engineEndpoint=~A~%"
            (devnet-smoke-gate-field report "engineEndpoint"))
    (format t "rpcEndpoint=~A~%"
            (devnet-smoke-gate-field report "rpcEndpoint"))
    (format t "readyFile=~A~%"
            (devnet-smoke-gate-field report "readyFile"))
    (format t "logFile=~A~%"
            (devnet-smoke-gate-field report "logFile"))
    (format t "pidFile=~A~%"
            (devnet-smoke-gate-field report "pidFile"))
    (format t "databaseFile=~A~%"
            (devnet-smoke-gate-field report "databaseFile"))
    (format t "databaseHeadNumber=~A~%"
            (devnet-smoke-gate-field report "databaseHeadNumber"))
    (format t "databaseHeadHash=~A~%"
            (devnet-smoke-gate-field report "databaseHeadHash"))
    (format t "databaseStateAvailable=~A~%"
            (devnet-smoke-gate-field report "databaseStateAvailable"))
    (format t "engineConnections=~D~%"
            (devnet-smoke-gate-field report "engineConnections"))
    (format t "publicConnections=~D~%"
            (devnet-smoke-gate-field report "publicConnections"))
    (format t "totalConnections=~D~%"
            (devnet-smoke-gate-field report "totalConnections"))
    (format t "engineCapabilityCount=~D~%"
            (devnet-smoke-gate-field report "engineCapabilityCount"))
    (format t "engineCapabilityHasNewPayloadV1=~A~%"
            (devnet-smoke-gate-field
             report "engineCapabilityHasNewPayloadV1"))
    (format t "engineCapabilityHasForkchoiceUpdatedV1=~A~%"
            (devnet-smoke-gate-field
             report "engineCapabilityHasForkchoiceUpdatedV1"))
    (format t "engineCapabilityHasGetPayloadV1=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasGetPayloadV1"))
    (format t "engineCapabilityHasNewPayloadV2=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasNewPayloadV2"))
    (format t "engineCapabilityHasForkchoiceUpdatedV2=~A~%"
            (devnet-smoke-gate-field
             report "engineCapabilityHasForkchoiceUpdatedV2"))
    (format t "engineCapabilityHasGetPayloadV2=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasGetPayloadV2"))
    (format t "engineCapabilityHasNewPayloadV3=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasNewPayloadV3"))
    (format t "engineCapabilityHasGetBlobsV1=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasGetBlobsV1"))
    (format t "engineCapabilityHasPayloadBodiesV2=~A~%"
            (devnet-smoke-gate-field report "engineCapabilityHasPayloadBodiesV2"))
    (format t "engineClientVersionCode=~A~%"
            (devnet-smoke-gate-field report "engineClientVersionCode"))
    (format t "engineClientVersionName=~A~%"
            (devnet-smoke-gate-field report "engineClientVersionName"))
    (format t "engineClientVersionVersion=~A~%"
            (devnet-smoke-gate-field report "engineClientVersionVersion"))
    (format t "engineClientVersionCommit=~A~%"
            (devnet-smoke-gate-field report "engineClientVersionCommit"))
    (format t "engineTransitionTerminalTotalDifficulty=~A~%"
            (devnet-smoke-gate-field
             report "engineTransitionTerminalTotalDifficulty"))
    (format t "engineTransitionTerminalBlockHash=~A~%"
            (devnet-smoke-gate-field report "engineTransitionTerminalBlockHash"))
    (format t "engineTransitionTerminalBlockNumber=~A~%"
            (devnet-smoke-gate-field
             report "engineTransitionTerminalBlockNumber"))
    (format t "engineTransitionMismatchErrorCode=~A~%"
            (devnet-smoke-gate-field report "engineTransitionMismatchErrorCode"))
    (format t "engineTransitionMismatchErrorMessage=~A~%"
            (devnet-smoke-gate-field
             report "engineTransitionMismatchErrorMessage"))
    (format t "headNumber=~A~%"
            (devnet-smoke-gate-field report "headNumber"))
    (return-from devnet-smoke-gate-print-text nil))
  (unless (devnet-smoke-gate-suite-report-p report)
    (format t "fixtureCase=~A~%"
            (devnet-smoke-gate-field report "fixtureCase")))
  (format t "engineConnections=~D~%"
          (devnet-smoke-gate-field report "engineConnections"))
  (format t "publicConnections=~D~%"
          (devnet-smoke-gate-field report "publicConnections"))
  (format t "totalConnections=~D~%"
          (devnet-smoke-gate-field report "totalConnections"))
  (let ((connection-contract
          (devnet-smoke-gate-field report "connectionContract")))
    (format t "expectedEngineConnections=~D~%"
            (devnet-smoke-gate-field connection-contract
                                     "expectedEngineConnections"))
    (format t "expectedPublicConnections=~D~%"
            (devnet-smoke-gate-field connection-contract
                                     "expectedPublicConnections"))
    (format t "expectedTotalConnections=~D~%"
            (devnet-smoke-gate-field connection-contract
                                     "expectedTotalConnections")))
  (if (devnet-smoke-gate-suite-report-p report)
      (dolist (case-report (devnet-smoke-gate-field report "cases"))
        (format t "case=~A status=~A blockNumber=~A checkedBalance=~A~%"
                (devnet-smoke-gate-field case-report "fixtureCase")
                (devnet-smoke-gate-field case-report "newPayloadStatus")
                (devnet-smoke-gate-field case-report "blockNumber")
                (devnet-smoke-gate-field case-report "checkedBalance")))
      (progn
        (format t "engineUnauthenticatedStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "engineUnauthenticatedStatus"))
        (format t "engineInvalidAuthStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "engineInvalidAuthStatus"))
        (format t "engineDuplicateAuthStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "engineDuplicateAuthStatus"))
        (format t "engineRootWrongPathStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "engineRootWrongPathStatus"))
        (format t "engineCapabilityCount=~D~%"
                (devnet-smoke-gate-field report "engineCapabilityCount"))
        (format t "engineCapabilityHasNewPayloadV1=~A~%"
                (devnet-smoke-gate-field
                 report "engineCapabilityHasNewPayloadV1"))
        (format t "engineCapabilityHasForkchoiceUpdatedV1=~A~%"
                (devnet-smoke-gate-field
                 report "engineCapabilityHasForkchoiceUpdatedV1"))
        (format t "engineCapabilityHasGetPayloadV1=~A~%"
                (devnet-smoke-gate-field
                 report "engineCapabilityHasGetPayloadV1"))
        (format t "engineClientVersionCode=~A~%"
                (devnet-smoke-gate-field report "engineClientVersionCode"))
        (format t "engineClientVersionName=~A~%"
                (devnet-smoke-gate-field report "engineClientVersionName"))
        (format t "engineClientVersionVersion=~A~%"
                (devnet-smoke-gate-field report "engineClientVersionVersion"))
        (format t "engineClientVersionCommit=~A~%"
                (devnet-smoke-gate-field report "engineClientVersionCommit"))
        (format t "engineTransitionTerminalTotalDifficulty=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionTerminalTotalDifficulty"))
        (format t "engineTransitionTerminalBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionTerminalBlockHash"))
        (format t "engineTransitionTerminalBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionTerminalBlockNumber"))
        (format t "engineTransitionMismatchErrorCode=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionMismatchErrorCode"))
        (format t "engineTransitionMismatchErrorMessage=~A~%"
                (devnet-smoke-gate-field
                 report "engineTransitionMismatchErrorMessage"))
        (format t "enginePublicNamespaceErrorCode=~A~%"
                (devnet-smoke-gate-field
                 report "enginePublicNamespaceErrorCode"))
        (format t "publicRootWrongPathStatus=~D~%"
                (devnet-smoke-gate-field report
                                         "publicRootWrongPathStatus"))
        (format t "publicClientVersion=~A~%"
                (devnet-smoke-gate-field report "publicClientVersion"))
        (format t "publicNetVersion=~A~%"
                (devnet-smoke-gate-field report "publicNetVersion"))
        (format t "publicNetListening=~A~%"
                (devnet-smoke-gate-field report "publicNetListening"))
        (format t "publicSyncing=~A~%"
                (devnet-smoke-gate-field report "publicSyncing"))
        (format t "publicNetPeerCount=~A~%"
                (devnet-smoke-gate-field report "publicNetPeerCount"))
        (format t "publicAccountCount=~D~%"
                (devnet-smoke-gate-field report "publicAccountCount"))
        (format t "publicCoinbase=~A~%"
                (devnet-smoke-gate-field report "publicCoinbase"))
        (format t "publicMining=~A~%"
                (devnet-smoke-gate-field report "publicMining"))
        (format t "publicHashrate=~A~%"
                (devnet-smoke-gate-field report "publicHashrate"))
        (format t "publicRpcModules=~S~%"
                (devnet-smoke-gate-field report "publicRpcModules"))
        (format t "publicProtocolVersion=~A~%"
                (devnet-smoke-gate-field report "publicProtocolVersion"))
        (format t "publicWeb3Sha3=~A~%"
                (devnet-smoke-gate-field report "publicWeb3Sha3"))
        (format t "publicGasPrice=~A~%"
                (devnet-smoke-gate-field report "publicGasPrice"))
        (format t "publicMaxPriorityFeePerGas=~A~%"
                (devnet-smoke-gate-field
                 report "publicMaxPriorityFeePerGas"))
        (format t "publicBaseFee=~A~%"
                (devnet-smoke-gate-field report "publicBaseFee"))
        (format t "publicBlobBaseFee=~A~%"
                (devnet-smoke-gate-field report "publicBlobBaseFee"))
        (format t "publicFeeHistoryOldestBlock=~A~%"
                (devnet-smoke-gate-field
                 report "publicFeeHistoryOldestBlock"))
        (format t "publicBatchResponseCount=~D~%"
                (devnet-smoke-gate-field
                 report "publicBatchResponseCount"))
        (format t "publicBatchChainId=~A~%"
                (devnet-smoke-gate-field report "publicBatchChainId"))
        (format t "publicBatchNetVersion=~A~%"
                (devnet-smoke-gate-field report "publicBatchNetVersion"))
        (format t "publicBatchClientVersion=~A~%"
                (devnet-smoke-gate-field
                 report "publicBatchClientVersion"))
        (format t "newPayloadStatus=~A~%"
                (devnet-smoke-gate-field report "newPayloadStatus"))
        (format t "latestValidHash=~A~%"
                (devnet-smoke-gate-field report "latestValidHash"))
        (format t "forkchoiceStatus=~A~%"
                (devnet-smoke-gate-field report "forkchoiceStatus"))
        (format t "enginePayloadBodiesByHashCount=~D~%"
                (devnet-smoke-gate-field
                 report "enginePayloadBodiesByHashCount"))
        (format t "enginePayloadBodiesByHashTransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report "enginePayloadBodiesByHashTransactionCount"))
        (format t "enginePayloadBodiesByRangeCount=~D~%"
                (devnet-smoke-gate-field
                 report "enginePayloadBodiesByRangeCount"))
        (format t "enginePayloadBodiesByRangeTransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report "enginePayloadBodiesByRangeTransactionCount"))
        (format t "preparedPayloadId=~A~%"
                (devnet-smoke-gate-field report "preparedPayloadId"))
        (format t "preparedPayloadParentHash=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedPayloadParentHash"))
        (format t "preparedPayloadBlockNumber=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedPayloadBlockNumber"))
        (format t "engineGetPayloadV2ParentHash=~A~%"
                (devnet-smoke-gate-field report
                                         "engineGetPayloadV2ParentHash"))
        (format t "engineGetPayloadV2BlockNumber=~A~%"
                (devnet-smoke-gate-field report
                                         "engineGetPayloadV2BlockNumber"))
        (format t "engineGetPayloadV2TransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TransactionCount"))
        (format t "preparedTxpoolPayloadId=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedTxpoolPayloadId"))
        (format t "engineGetPayloadV2TxpoolTransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolTransactionCount"))
        (format t "engineGetPayloadV2TxpoolSelectedTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolSelectedTransactionHash"))
        (format t "engineGetPayloadV2TxpoolSelectedStillPending=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolSelectedStillPending"))
        (format t "engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued"))
        (format t "engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued"))
        (format t "preparedReplacementTxpoolPayloadId=~A~%"
                (devnet-smoke-gate-field report
                                         "preparedReplacementTxpoolPayloadId"))
        (format t "engineGetPayloadV2TxpoolReplacementTransactionCount=~D~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolReplacementTransactionCount"))
        (format t "engineGetPayloadV2TxpoolReplacementTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolReplacementTransactionHash"))
        (format t "engineGetPayloadV2TxpoolReplacementStillPending=~A~%"
                (devnet-smoke-gate-field
                 report
                 "engineGetPayloadV2TxpoolReplacementStillPending"))
        (format t "engineNewPayloadV2TxpoolImportStatus=~A~%"
                (devnet-smoke-gate-field
                 report "engineNewPayloadV2TxpoolImportStatus"))
        (format t "engineForkchoiceUpdatedV2TxpoolImportStatus=~A~%"
                (devnet-smoke-gate-field
                 report "engineForkchoiceUpdatedV2TxpoolImportStatus"))
        (format t "txpoolImportTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportTransactionHash"))
        (format t "txpoolImportReceiptTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportReceiptTransactionHash"))
        (format t "txpoolImportTxpoolStatusPending=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportTxpoolStatusPending"))
        (format t "txpoolImportTxpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportTxpoolStatusQueued"))
        (format t "txpoolImportSelectedStillPending=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportSelectedStillPending"))
        (format t "txpoolImportNonSelectedBasefeeStillQueued=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportNonSelectedBasefeeStillQueued"))
        (format t "txpoolImportNonSelectedQueuedStillQueued=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolImportNonSelectedQueuedStillQueued"))
        (format t "remoteBlockHash=~A~%"
                (devnet-smoke-gate-field report "remoteBlockHash"))
        (format t "remoteBlockStatus=~A~%"
                (devnet-smoke-gate-field report "remoteBlockStatus"))
        (format t "invalidTipsetBlockHash=~A~%"
                (devnet-smoke-gate-field report "invalidTipsetBlockHash"))
        (format t "invalidTipsetStatus=~A~%"
                (devnet-smoke-gate-field report "invalidTipsetStatus"))
        (format t "invalidTipsetValidationError=~A~%"
                (devnet-smoke-gate-field
                 report "invalidTipsetValidationError"))
        (format t "txpoolPendingTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingTransactionHash"))
        (format t "txpoolReplacementTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolReplacementTransactionHash"))
        (format t "txpoolPendingSender=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingSender"))
        (format t "txpoolPendingNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingNonce"))
        (format t "txpoolPendingSenderNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingSenderNonce"))
        (format t "txpoolPendingInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingInspectSummary"))
        (format t "txpoolPendingFilterId=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingFilterId"))
        (format t "txpoolPendingFilterHash=~A~%"
                (devnet-smoke-gate-field report "txpoolPendingFilterHash"))
        (format t "txpoolPendingFilterUninstallResult=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingFilterUninstallResult"))
        (format t "txpoolPendingFilterMissingErrorCode=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolPendingFilterMissingErrorCode"))
        (format t "txpoolBasefeeTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolBasefeeTransactionHash"))
        (format t "txpoolBasefeeNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolBasefeeNonce"))
        (format t "txpoolBasefeeInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolBasefeeInspectSummary"))
        (format t "txpoolQueuedTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolQueuedTransactionHash"))
        (format t "txpoolQueuedNonce=~A~%"
                (devnet-smoke-gate-field report "txpoolQueuedNonce"))
        (format t "txpoolQueuedInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "txpoolQueuedInspectSummary"))
        (format t "txpoolStatusPending=~A~%"
                (devnet-smoke-gate-field report "txpoolStatusPending"))
        (format t "txpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field report "txpoolStatusQueued"))
        (format t "devPeriodSeconds=~A~%"
                (devnet-smoke-gate-field report "devPeriodSeconds"))
        (format t "devPeriodTransactionHash=~A~%"
                (devnet-smoke-gate-field report "devPeriodTransactionHash"))
        (format t "devPeriodBlockNumber=~A~%"
                (devnet-smoke-gate-field report "devPeriodBlockNumber"))
        (format t "devPeriodBlockHash=~A~%"
                (devnet-smoke-gate-field report "devPeriodBlockHash"))
        (format t "devPeriodTxpoolStatusPending=~A~%"
                (devnet-smoke-gate-field
                 report "devPeriodTxpoolStatusPending"))
        (format t "devPeriodTxpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field
                 report "devPeriodTxpoolStatusQueued"))
        (format t "blockNumber=~A~%"
                (devnet-smoke-gate-field report "blockNumber"))
        (format t "blockGasLimit=~A~%"
                (devnet-smoke-gate-field report "blockGasLimit"))
        (format t "safeBlockNumber=~A~%"
                (devnet-smoke-gate-field report "safeBlockNumber"))
        (format t "safeBlockGasLimit=~A~%"
                (devnet-smoke-gate-field report "safeBlockGasLimit"))
        (format t "safeBlockHash=~A~%"
                (devnet-smoke-gate-field report "safeBlockHash"))
        (format t "finalizedBlockNumber=~A~%"
                (devnet-smoke-gate-field report "finalizedBlockNumber"))
        (format t "finalizedBlockHash=~A~%"
                (devnet-smoke-gate-field report "finalizedBlockHash"))
        (format t "checkedBalanceAddress=~A~%"
                (devnet-smoke-gate-field report "checkedBalanceAddress"))
        (format t "checkedBalanceField=~A~%"
                (devnet-smoke-gate-field report "checkedBalanceField"))
        (format t "checkedBalance=~A~%"
                (devnet-smoke-gate-field report "checkedBalance"))
        (format t "checkedCheckpointBalance=~A~%"
                (devnet-smoke-gate-field
                 report "checkedCheckpointBalance"))
        (format t "recipientBalance=~A~%"
                (devnet-smoke-gate-field report "recipientBalance"))
        (format t "checkedNonceAddress=~A~%"
                (devnet-smoke-gate-field report "checkedNonceAddress"))
        (format t "checkedNonce=~A~%"
                (devnet-smoke-gate-field report "checkedNonce"))
        (format t "checkedCodeAddress=~A~%"
                (devnet-smoke-gate-field report "checkedCodeAddress"))
        (format t "checkedCode=~A~%"
                (devnet-smoke-gate-field report "checkedCode"))
        (format t "checkedStorageAddress=~A~%"
                (devnet-smoke-gate-field report "checkedStorageAddress"))
        (format t "checkedStorageKey=~A~%"
                (devnet-smoke-gate-field report "checkedStorageKey"))
        (format t "checkedStorage=~A~%"
                (devnet-smoke-gate-field report "checkedStorage"))
        (format t "checkedProofCodeHash=~A~%"
                (devnet-smoke-gate-field report "checkedProofCodeHash"))
        (format t "checkedProofStorageValue=~A~%"
                (devnet-smoke-gate-field report
                                         "checkedProofStorageValue"))
        (format t "checkedLogCount=~A~%"
                (devnet-smoke-gate-field report "checkedLogCount"))
        (format t "checkedSimulationCount=~A~%"
                (devnet-smoke-gate-field report "checkedSimulationCount"))
        (format t "readyFile=~A~%" (devnet-smoke-gate-field report "readyFile"))
        (format t "logFile=~A~%" (devnet-smoke-gate-field report "logFile"))
        (format t "pidFile=~A~%" (devnet-smoke-gate-field report "pidFile"))
        (format t "databaseFile=~A~%"
                (devnet-smoke-gate-field report "databaseFile"))
        (format t "databasePruneStateBefore=~A~%"
                (devnet-smoke-gate-field
                 report "databasePruneStateBefore"))
        (format t "databasePrunedStateAvailable=~A~%"
                (devnet-smoke-gate-field
                 report "databasePrunedStateAvailable"))
        (format t "databaseHeadNumber=~A~%"
                (devnet-smoke-gate-field report "databaseHeadNumber"))
        (format t "databaseHeadGasLimit=~A~%"
                (devnet-smoke-gate-field report "databaseHeadGasLimit"))
        (format t "databaseRpcBlockNumber=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBlockNumber"))
        (format t "databaseSafeNumber=~A~%"
                (devnet-smoke-gate-field report "databaseSafeNumber"))
        (format t "databaseSafeHash=~A~%"
                (devnet-smoke-gate-field report "databaseSafeHash"))
        (format t "databaseFinalizedNumber=~A~%"
                (devnet-smoke-gate-field report "databaseFinalizedNumber"))
        (format t "databaseFinalizedHash=~A~%"
                (devnet-smoke-gate-field report "databaseFinalizedHash"))
        (format t "databaseRpcBalance=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBalance"))
        (format t "databaseRpcNonce=~A~%"
                (devnet-smoke-gate-field report "databaseRpcNonce"))
        (format t "databaseRpcCode=~A~%"
                (devnet-smoke-gate-field report "databaseRpcCode"))
        (format t "databaseRpcStorage=~A~%"
                (devnet-smoke-gate-field report "databaseRpcStorage"))
        (format t "databaseRpcPreparedPayloadId=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcPreparedPayloadId"))
        (format t "databaseRpcPreparedPayloadParentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPreparedPayloadParentHash"))
        (format t "databaseRpcPreparedPayloadBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPreparedPayloadBlockNumber"))
        (format t "databaseRemoteBlockHash=~A~%"
                (devnet-smoke-gate-field report "databaseRemoteBlockHash"))
        (format t "databaseRpcRemoteBlockStatus=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRemoteBlockStatus"))
        (format t "databaseInvalidTipsetBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseInvalidTipsetBlockHash"))
        (format t "databaseRpcInvalidTipsetStatus=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcInvalidTipsetStatus"))
        (format t "databaseRpcInvalidTipsetValidationError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcInvalidTipsetValidationError"))
        (format t "databaseRpcTxpoolPendingHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHash"))
        (format t "databaseRpcTxpoolSender=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolSender"))
        (format t "databaseRpcTxpoolNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolNonce"))
        (format t "databaseRpcTxpoolInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolInspectSummary"))
        (format t "databaseRpcTxpoolBasefeeHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeHash"))
        (format t "databaseRpcTxpoolBasefeeNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeNonce"))
        (format t "databaseRpcTxpoolBasefeeInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeInspectSummary"))
        (format t "databaseRpcTxpoolQueuedHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedHash"))
        (format t "databaseRpcTxpoolQueuedNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedNonce"))
        (format t "databaseRpcTxpoolQueuedInspectSummary=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedInspectSummary"))
        (format t "databaseRpcTxpoolStatusPending=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolStatusPending"))
        (format t "databaseRpcTxpoolStatusQueued=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolStatusQueued"))
        (format t "databaseRpcTxpoolPendingBlockCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockCount"))
        (format t "databaseRpcTxpoolPendingBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockHash"))
        (format t "databaseRpcTxpoolPendingBlockBaseFee=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockBaseFee"))
        (format t "databaseRpcTxpoolPendingHeaderNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderNumber"))
        (format t "databaseRpcTxpoolPendingHeaderParentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderParentHash"))
        (format t "databaseRpcTxpoolPendingHeaderHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderHash"))
        (format t "databaseRpcTxpoolPendingHeaderNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderNonce"))
        (format t "databaseRpcTxpoolPendingHeaderBaseFee=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingHeaderBaseFee"))
        (format t "databaseRpcTxpoolPendingFeeHistoryNextBaseFee=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingFeeHistoryNextBaseFee"))
        (format t "databaseRpcTxpoolPendingSenderNonce=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingSenderNonce"))
        (format t "databaseRpcTxpoolPendingBlockTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockTransactionHash"))
        (format t "databaseRpcTxpoolPendingBlockTransactionBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingBlockTransactionBlockHash"))
        (format t "databaseRpcTxpoolPendingIndexHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingIndexHash"))
        (format t "databaseRpcTxpoolPendingIndexBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingIndexBlockHash"))
        (format t "databaseRpcTxpoolPendingRawByIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPendingRawByIndex"))
        (format t "databaseRpcTxpoolContentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolContentHash"))
        (format t "databaseRpcTxpoolContentFromHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolContentFromHash"))
        (format t "databaseRpcTxpoolBasefeeContentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeContentHash"))
        (format t "databaseRpcTxpoolBasefeeContentFromHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolBasefeeContentFromHash"))
        (format t "databaseRpcTxpoolQueuedContentHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedContentHash"))
        (format t "databaseRpcTxpoolQueuedContentFromHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolQueuedContentFromHash"))
        (format t "databaseRpcTxpoolPublicConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTxpoolPublicConnections"))
        (format t "databaseRpcProofAddress=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofAddress"))
        (format t "databaseRpcProofCodeHash=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofCodeHash"))
        (format t "databaseRpcProofStorageKey=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofStorageKey"))
        (format t "databaseRpcProofStorageValue=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofStorageValue"))
        (format t "databaseRpcProofStorageCount=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcProofStorageCount"))
        (format t "databaseRpcProofAccountProofCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcProofAccountProofCount"))
        (format t "databaseRpcReceiptTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcReceiptTransactionHash"))
        (format t "databaseRpcReceiptBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcReceiptBlockNumber"))
        (format t "databaseRpcBlockHash=~A~%"
                (devnet-smoke-gate-field report "databaseRpcBlockHash"))
        (format t "databaseRpcBlockByHashNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByHashNumber"))
        (format t "databaseRpcBlockTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockTransactionHash"))
        (format t "databaseRpcBlockByNumberHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByNumberHash"))
        (format t "databaseRpcBlockByNumberNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByNumberNumber"))
        (format t "databaseRpcBlockByNumberTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockByNumberTransactionHash"))
        (format t "databaseRpcFullBlockTransactionCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockTransactionCount"))
        (format t "databaseRpcFullBlockTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockTransactionHash"))
        (format t "databaseRpcFullBlockTransactionIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockTransactionIndex"))
        (format t "databaseRpcFullBlockByNumberTransactionCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockByNumberTransactionCount"))
        (format t "databaseRpcFullBlockByNumberTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockByNumberTransactionHash"))
        (format t "databaseRpcFullBlockByNumberTransactionIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFullBlockByNumberTransactionIndex"))
        (format t "databaseRpcTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionHash"))
        (format t "databaseRpcTransactionBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionBlockHash"))
        (format t "databaseRpcTransactionBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionBlockNumber"))
        (format t "databaseRpcBlockReceiptsCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptsCount"))
        (format t "databaseRpcLogCount=~A~%"
                (devnet-smoke-gate-field report "databaseRpcLogCount"))
        (format t "databaseRpcLogFilterCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcLogFilterCount"))
        (format t "databaseRpcLogFilterLogCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcLogFilterLogCount"))
        (format t "databaseRpcLogFilterUninstallCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcLogFilterUninstallCount"))
        (format t "databaseRpcBlockReceiptTransactionHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptTransactionHash"))
        (format t "databaseRpcBlockReceiptBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptBlockHash"))
        (format t "databaseRpcBlockReceiptBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockReceiptBlockNumber"))
        (format t "databaseRpcBlockTransactionCountByHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockTransactionCountByHash"))
        (format t "databaseRpcBlockTransactionCountByNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcBlockTransactionCountByNumber"))
        (format t "databaseRpcCanonicalHashBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcCanonicalHashBalance"))
        (format t "databaseRpcCanonicalHashRequireBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcCanonicalHashRequireBalance"))
        (format t "databaseRpcRawTransactionByBlockHashAndIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRawTransactionByBlockHashAndIndex"))
        (format t "databaseRpcRawTransactionByHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRawTransactionByHash"))
        (format t "databaseRpcRawTransactionByBlockNumberAndIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcRawTransactionByBlockNumberAndIndex"))
        (format t "databaseRpcTransactionByBlockHashAndIndexHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockHashAndIndexHash"))
        (format t "databaseRpcTransactionByBlockHashAndIndexBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockHashAndIndexBlockHash"))
        (format t "databaseRpcTransactionByBlockHashAndIndexBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockHashAndIndexBlockNumber"))
        (format t "databaseRpcTransactionByBlockHashAndIndexIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockHashAndIndexIndex"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockNumberAndIndexHash"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockNumberAndIndexBlockHash"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report
                 "databaseRpcTransactionByBlockNumberAndIndexBlockNumber"))
        (format t "databaseRpcTransactionByBlockNumberAndIndexIndex=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcTransactionByBlockNumberAndIndexIndex"))
        (format t "databaseRpcSafeBlockHash=~A~%"
                (devnet-smoke-gate-field report "databaseRpcSafeBlockHash"))
        (format t "databaseRpcSafeBlockNumber=~A~%"
                (devnet-smoke-gate-field report "databaseRpcSafeBlockNumber"))
        (format t "databaseRpcFinalizedBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFinalizedBlockHash"))
        (format t "databaseRpcFinalizedBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcFinalizedBlockNumber"))
        (format t "databaseRpcCallResult=~A~%"
                (devnet-smoke-gate-field report "databaseRpcCallResult"))
        (format t "databaseRpcFailedCallError=~A~%"
                (devnet-smoke-gate-field report
                                         "databaseRpcFailedCallError"))
        (format t "databaseRpcEstimateGas=~A~%"
                (devnet-smoke-gate-field report "databaseRpcEstimateGas"))
        (format t "databaseRpcAccessListCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcAccessListCount"))
        (format t "databaseRpcAccessListGasUsed=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcAccessListGasUsed"))
        (format t "databaseRpcPostCallStorage=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPostCallStorage"))
        (format t "databaseRpcSimulationCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSimulationCount"))
        (format t "databaseRpcSideBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideBlockHash"))
        (format t "databaseRpcSideForkchoiceStatus=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideForkchoiceStatus"))
        (format t "databaseRpcSideRejectedCheckpointError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRejectedCheckpointError"))
        (format t "databaseRpcSideBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideBlockNumber"))
        (format t "databaseRpcSideLatestBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideLatestBlockHash"))
        (format t "databaseRpcSideTransactionReinserted=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideTransactionReinserted"))
        (format t "databaseRpcSideTransactionByHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideTransactionByHash"))
        (format t "databaseRpcSideRawTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRawTransaction"))
        (format t "databaseRpcSidePendingTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSidePendingTransaction"))
        (format t "databaseRpcSideReceipt=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideReceipt"))
        (format t "databaseRpcSideHiddenReceiptCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideHiddenReceiptCount"))
        (format t "databaseRpcSideChildBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideChildBlockHash"))
        (format t "databaseRpcSideBlockReceiptsCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideBlockReceiptsCount"))
        (format t "databaseRpcSideLogCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideLogCount"))
        (format t "databaseRpcSideRestoredHeadNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredHeadNumber"))
        (format t "databaseRpcSideRestoredHeadHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredHeadHash"))
        (format t "databaseRpcSideRestoredRpcBlockNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcBlockNumber"))
        (format t "databaseRpcSideRestoredRpcLatestBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcLatestBlockHash"))
        (format t "databaseRpcSideRestoredSafeNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredSafeNumber"))
        (format t "databaseRpcSideRestoredSafeHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredSafeHash"))
        (format t "databaseRpcSideRestoredFinalizedNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredFinalizedNumber"))
        (format t "databaseRpcSideRestoredFinalizedHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredFinalizedHash"))
        (format t "databaseRpcSideRestoredRpcSafeNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcSafeNumber"))
        (format t "databaseRpcSideRestoredRpcSafeHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcSafeHash"))
        (format t "databaseRpcSideRestoredRpcFinalizedNumber=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcFinalizedNumber"))
        (format t "databaseRpcSideRestoredRpcFinalizedHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRpcFinalizedHash"))
        (format t "databaseRpcSideRestoredSafeBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredSafeBalance"))
        (format t "databaseRpcSideRestoredFinalizedBalance=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredFinalizedBalance"))
        (format t "databaseRpcSideRestoredRawTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredRawTransaction"))
        (format t "databaseRpcSideRestoredPendingTransaction=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredPendingTransaction"))
        (format t "databaseRpcSideRestoredReceipt=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredReceipt"))
        (format t "databaseRpcSideRestoredHiddenReceiptCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredHiddenReceiptCount"))
        (format t "databaseRpcSideRestoredChildBlockHash=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredChildBlockHash"))
        (format t "databaseRpcSideRestoredChildRequireCanonicalError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredChildRequireCanonicalError"))
        (format t "databaseRpcSideRestoredChildRequireCanonicalErrors=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredChildRequireCanonicalErrors"))
        (format t "databaseRpcSideRestoredBlockReceiptsCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredBlockReceiptsCount"))
        (format t "databaseRpcSideRestoredLogCount=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredLogCount"))
        (format t "databaseRpcSideRestoredPublicConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideRestoredPublicConnections"))
        (format t "databaseRpcSideTotalConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideTotalConnections"))
        (format t "databaseRpcSideEngineConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSideEngineConnections"))
        (format t "databaseRpcSidePublicConnections=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcSidePublicConnections"))
        (format t "databaseRpcPrunedStateError=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPrunedStateError"))
        (format t "databaseRpcPrunedStateErrors=~A~%"
                (devnet-smoke-gate-field
                 report "databaseRpcPrunedStateErrors")))))

(defun devnet-smoke-gate-main ()
  (let* ((args (devnet-smoke-gate-arguments))
         (help-p (devnet-smoke-gate-help-p args))
         (json-p (devnet-smoke-gate-json-p args))
         (all-fixtures-p (devnet-smoke-gate-all-fixtures-p args))
         (engine-only-serve-p
           (devnet-smoke-gate-engine-only-serve-p args))
         (ready-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-ready-file-option+))
         (log-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-log-file-option+))
         (pid-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-pid-file-option+))
         (database-file
           (devnet-smoke-gate-path-option
            args +devnet-smoke-gate-database-option+))
         (state-prune-before
           (devnet-smoke-gate-non-negative-integer-option
            args +devnet-smoke-gate-prune-state-before-option+))
         (terminal-total-difficulty
           (devnet-smoke-gate-quantity-option
            args +devnet-smoke-gate-terminal-total-difficulty-option+))
         (terminal-total-difficulty-passed-p
           (not
            (null
             (member +devnet-smoke-gate-terminal-total-difficulty-passed-flag+
                     args
                     :test #'string=))))
         (terminal-block-hash
           (devnet-smoke-gate-hash32-option
            args +devnet-smoke-gate-terminal-block-hash-option+))
         (terminal-block-number
           (devnet-smoke-gate-quantity-option
            args +devnet-smoke-gate-terminal-block-number-option+))
         (case-name (devnet-smoke-gate-fixture-case-name args)))
    (if help-p
        (devnet-smoke-gate-print-help)
        (let ((report
                (cond
                  (engine-only-serve-p
                   (when all-fixtures-p
                     (error "~A cannot be combined with ~A"
                            +devnet-smoke-gate-engine-only-serve-flag+
                            +devnet-smoke-gate-all-fixtures-flag+))
                   (when (devnet-smoke-gate-fixture-case-specified-p args)
                     (error "~A cannot be combined with a fixture case"
                            +devnet-smoke-gate-engine-only-serve-flag+))
                   (append
                    (devnet-smoke-gate-verify-engine-only-serve
                     :ready-file ready-file
                     :log-file log-file
                     :pid-file pid-file
                     :database-file database-file)
                    (list
                     (cons
                      "kzgOptIn"
                      (devnet-smoke-gate-verify-engine-only-kzg-opt-in)))))
                  (all-fixtures-p
                   (when (devnet-smoke-gate-fixture-case-specified-p args)
                     (error "~A cannot be combined with a fixture case"
                            +devnet-smoke-gate-all-fixtures-flag+))
                   (devnet-smoke-gate-run-all
                    +engine-newpayload-v2-smoke-case-names+
                    :ready-file ready-file
                    :log-file log-file
                    :pid-file pid-file
                    :database-file database-file
                    :state-prune-before state-prune-before
                    :terminal-total-difficulty
                    terminal-total-difficulty
                    :terminal-total-difficulty-passed-p
                    terminal-total-difficulty-passed-p
                    :terminal-block-hash terminal-block-hash
                    :terminal-block-number terminal-block-number))
                  (t
                   (devnet-smoke-gate-run
                    case-name
                    :ready-file ready-file
                    :log-file log-file
                    :pid-file pid-file
                    :database-file database-file
                    :state-prune-before state-prune-before
                    :terminal-total-difficulty
                    terminal-total-difficulty
                    :terminal-total-difficulty-passed-p
                    terminal-total-difficulty-passed-p
                    :terminal-block-hash terminal-block-hash
                    :terminal-block-number terminal-block-number)))))
          (if json-p
              (format t "~&~A~%" (json-encode report))
              (devnet-smoke-gate-print-text report))))))

(devnet-smoke-gate-main)
