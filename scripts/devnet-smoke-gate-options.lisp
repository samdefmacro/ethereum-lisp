(in-package #:ethereum-lisp.test)

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
    (node-store-import-from-kv
     (ethereum-lisp.cli:devnet-node-store node)
     (make-file-key-value-database path)
     :expected-chain-id (chain-config-chain-id config))
    (setf (ethereum-lisp.cli::devnet-node-database-path node) path)
    (devnet-cli-set-node-store-config
     node
     (ethereum-lisp.cli:devnet-node-store node)
     config)
    node))

(defun devnet-smoke-gate-write-kzg-prepared-payload-database
    (genesis-path &key database-path)
  (let* ((database-path
           (or database-path
               (devnet-cli-temp-path "ethereum-lisp-smoke-kzg-blob" "db")))
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
                   (ethereum-lisp.chain-store.state:memory-chain-store-blocks
                    (ethereum-lisp.chain-store.state:chain-store-component
                     store)))
          block-v6)
    (commit-state-db-to-chain-store store (block-hash block-v6) state)
    (setf (gethash (hash32-to-hex (block-hash block-v6))
                   (ethereum-lisp.chain-store.state:memory-chain-store-state-blocks
                    (ethereum-lisp.chain-store.state:chain-store-component
                     store)))
          t)
    (remhash (hash32-to-hex (block-hash block-v6))
             (ethereum-lisp.chain-store.state:memory-chain-store-blocks
              (ethereum-lisp.chain-store.state:chain-store-component store)))
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
      (node-store-export-to-kv store database)
      (kv-put-chain-record
       database
       :block
       (hash32-bytes (block-hash block-v6))
       (block-rlp block-v6))
      (kv-put-chain-record
       database
       :block-access-list
       (hash32-bytes (block-hash block-v6))
       (block-encoded-block-access-list block-v6)))
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
         (cons "params" (if (null params) #() params)))))

(defun devnet-smoke-gate-error-code (rpc)
  (fixture-object-field
   (fixture-object-field rpc "error")
   "code"))
