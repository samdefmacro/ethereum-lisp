(in-package #:ethereum-lisp.test)

(deftest devnet-live-persistence-migrates-headless-chain-baseline
  (let ((database-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-headless-baseline" "sexp")))
    (unwind-protect
         (let* ((first-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :database-path (namestring database-path)))
                (head-hash
                  (block-hash
                   (ethereum-lisp.cli:devnet-node-genesis-block first-node))))
           (let ((database (make-file-key-value-database database-path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-checkpoint database :head)
               (is present-p)
               (is (bytes= (hash32-bytes head-hash) value)))
             ;; Simulate a validated database written before live deltas
             ;; required an explicit canonical upper bound.
             (kv-delete-chain-checkpoint database :head))
           (let* ((second-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store second-node))
                  (database (make-file-key-value-database database-path)))
             (is (ethereum-lisp.txpool:engine-payload-store-txpool-database-change-tracking-enabled-p
                  restored-store))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-checkpoint database :head)
               (is present-p)
               (is (bytes= (hash32-bytes head-hash) value)))
             (is (bytes=
                  (hash32-bytes head-hash)
                  (hash32-bytes
                   (block-hash
                    (chain-store-head-block restored-store)))))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-live-persistence-restores-forkchoice-before-lifecycle-export
  (let ((database-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-live-forkchoice" "sexp"))
        (journal-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-live-forkchoice-journal" "sexp")))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-one-transfer-with-withdrawal"))
                (genesis-json
                  (json-encode
                   (devnet-cli-engine-fixture-parent-genesis-object case)))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (child-hash (block-hash child-block))
                (included-transaction (first (block-transactions child-block)))
                (raw-transaction
                  (first (fixture-object-field
                          (fixture-object-field case "payload")
                          "transactions")))
                (payload-case (fixture-object-field case "payload"))
                (expect (fixture-object-field case "expect"))
                (recipient (fixture-address-field expect "recipient"))
                (first-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-json genesis-json
                   :database-path (namestring database-path)
                   :txpool-journal-path (namestring journal-path)))
                (first-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-service first-node)))
                (first-public-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-public-service first-node)))
                (send-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 60)
                         (cons "method" "eth_sendRawTransaction")
                         (cons "params" (list raw-transaction)))
                   first-public-context))
                (database-seeded-p
                  (progn
                    ;; Seed a persisted pending record so the live FCU batch
                    ;; must delete it when the transaction becomes canonical.
                    (ethereum-lisp.cli::devnet-node-export-database first-node)
                    (probe-file database-path)))
                (new-payload-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (engine-fixture-payload-request
                    61
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data child-block)))
                   first-context))
                (forkchoice-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (devnet-cli-engine-forkchoice-v2-request
                    62 child-hash
                    :safe (block-hash parent-block)
                    :finalized (block-hash parent-block))
                   first-context))
                (new-payload-status
                  (fixture-object-field
                   (fixture-object-field new-payload-response "result")
                   "status"))
                (forkchoice-status
                  (fixture-object-field
                   (fixture-object-field forkchoice-response "result")
                   "payloadStatus")))
           (is (string= (hash32-to-hex
                         (transaction-hash included-transaction))
                        (fixture-object-field send-response "result")))
           (is database-seeded-p)
           (is (= 1
                  (length
                   (kv-chain-record-entries
                    (make-file-key-value-database journal-path)
                    :txpool))))
           (is (string= +payload-status-valid+ new-payload-status))
           (is (string= +payload-status-valid+
                        (fixture-object-field forkchoice-status "status")))
           (is (probe-file database-path))
           ;; The FCU commit updates the authoritative chain database, but an
           ;; abrupt stop may leave the independent journal one generation
           ;; behind.  Recovery must ignore its now-canonical transaction.
           (is (= 1
                  (length
                   (kv-chain-record-entries
                    (make-file-key-value-database journal-path)
                    :txpool))))
           ;; Constructing the second node directly simulates restart without
           ;; invoking DEVNET-NODE-EXPORT-DATABASE for the first node.
           (let* ((second-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-json genesis-json
                     :database-path (namestring database-path)
                     :txpool-journal-path (namestring journal-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store second-node))
                  (restored-public-context
                    (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                     (ethereum-lisp.cli:devnet-node-public-service second-node)))
                  (txpool-status
                    (fixture-object-field
                     (ethereum-lisp.rpc:rpc-handle-request
                      (list (cons "jsonrpc" "2.0")
                            (cons "id" 63)
                            (cons "method" "txpool_status")
                            (cons "params" #()))
                      restored-public-context)
                     "result")))
             (is (bytes= (hash32-bytes child-hash)
                          (hash32-bytes
                           (block-hash
                            (chain-store-head-block restored-store)))))
             (is (bytes= (hash32-bytes child-hash)
                          (hash32-bytes
                           (chain-store-canonical-hash
                            restored-store
                            (block-header-number (block-header child-block))))))
             (is (bytes= (hash32-bytes (block-hash parent-block))
                          (hash32-bytes
                           (block-hash
                            (chain-store-safe-block restored-store)))))
             (is (bytes= (hash32-bytes (block-hash parent-block))
                          (hash32-bytes
                           (block-hash
                            (chain-store-finalized-block restored-store)))))
             (is (engine-payload-store-state-available-p
                  restored-store child-hash))
             (is (string= "0x0"
                          (fixture-object-field txpool-status "pending")))
             (is (= (hex-to-quantity
                     (fixture-object-field expect "recipientBalance"))
                    (chain-store-account-balance
                     restored-store child-hash recipient)))
             (is (= (hex-to-quantity
                     (fixture-object-field payload-case "number"))
                    (block-header-number
                     (block-header
                      (chain-store-head-block restored-store)))))))
      (dolist (path (list database-path journal-path))
        (when (probe-file path)
          (delete-file path))))))

(deftest devnet-live-persistence-restores-new-payload-candidate-before-forkchoice
  (let ((database-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-live-new-payload" "sexp")))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-one-transfer-with-withdrawal"))
                (genesis-json
                  (json-encode
                   (devnet-cli-engine-fixture-parent-genesis-object case)))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (parent-hash (block-hash parent-block))
                (parent-number
                  (block-header-number (block-header parent-block)))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (child-hash (block-hash child-block))
                (child-number
                  (block-header-number (block-header child-block)))
                (transaction (first (block-transactions child-block)))
                (transaction-hash (transaction-hash transaction))
                (expect (fixture-object-field case "expect"))
                (recipient (fixture-address-field expect "recipient"))
                (expected-recipient-balance
                  (hex-to-quantity
                   (fixture-object-field expect "recipientBalance")))
                (database-fresh-p (not (probe-file database-path)))
                (first-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-json genesis-json
                   :database-path (namestring database-path)))
                (first-store
                  (ethereum-lisp.cli:devnet-node-store first-node))
                (first-safe-block (chain-store-safe-block first-store))
                (first-finalized-block
                  (chain-store-finalized-block first-store))
                (first-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-service first-node)))
                (new-payload-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (engine-fixture-payload-request
                    64
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data child-block)))
                   first-context))
                (new-payload-status
                  (fixture-object-field
                   (fixture-object-field new-payload-response "result")
                   "status")))
           (labels ((same-optional-block-hash-p (left right)
                      (if left
                          (and right
                               (bytes=
                                (hash32-bytes (block-hash left))
                                (hash32-bytes (block-hash right))))
                          (null right))))
             (is database-fresh-p)
             (is (string= +payload-status-valid+ new-payload-status))
             (is (probe-file database-path))
             (is (bytes=
                  (hash32-bytes parent-hash)
                  (hash32-bytes
                   (chain-store-canonical-hash first-store parent-number))))
             (is (not (chain-store-canonical-hash first-store child-number)))
             (is (not (chain-store-transaction-location
                       first-store transaction-hash)))
             ;; A VALID candidate persists only hash-addressed block data and
             ;; state. It must not publish canonical indexes or transaction
             ;; locations before consensus selects it.
             (let ((database
                     (make-file-key-value-database database-path)))
               (dolist (kind '(:block :header :receipt :state))
                 (multiple-value-bind (value present-p)
                     (kv-get-chain-record
                      database kind (hash32-bytes parent-hash))
                   (declare (ignore value))
                   (is present-p))
                 (multiple-value-bind (value present-p)
                     (kv-get-chain-record
                      database kind (hash32-bytes child-hash))
                   (declare (ignore value))
                   (is present-p)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-canonical-hash database parent-number)
                 (is present-p)
                 (is (bytes= (hash32-bytes parent-hash) value)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-canonical-hash
                    database child-number :missing)
                 (is (eq :missing value))
                 (is (not present-p)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database
                    :transaction-location
                    (hash32-bytes transaction-hash)
                    :missing)
                 (is (eq :missing value))
                 (is (not present-p))))
             ;; Constructing another node directly from the same database
             ;; simulates an abrupt restart without any lifecycle export.
             (let* ((second-node
                      (ethereum-lisp.cli:make-devnet-node
                       :genesis-json genesis-json
                       :database-path (namestring database-path)))
                    (restored-store
                      (ethereum-lisp.cli:devnet-node-store second-node))
                    (restored-context
                      (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                       (ethereum-lisp.cli:devnet-node-service second-node)))
                    (restored-public-context
                      (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                       (ethereum-lisp.cli:devnet-node-public-service
                        second-node)))
                    (block-number-before
                      (ethereum-lisp.rpc:rpc-handle-request
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 65)
                             (cons "method" "eth_blockNumber")
                             (cons "params" #()))
                       restored-public-context))
                    (block-by-hash-before
                      (ethereum-lisp.rpc:rpc-handle-request
                       (engine-fixture-block-by-hash-request
                        66 child-hash nil)
                       restored-public-context))
                    (receipt-before
                      (ethereum-lisp.rpc:rpc-handle-request
                       (engine-fixture-receipt-request
                        67 transaction-hash)
                       restored-public-context))
                    (balance-before
                      (ethereum-lisp.rpc:rpc-handle-request
                       (engine-fixture-balance-request 68 recipient)
                       restored-public-context)))
               (is (= parent-number (chain-store-head-number restored-store)))
               (is (bytes=
                    (hash32-bytes parent-hash)
                    (hash32-bytes
                     (block-hash (chain-store-latest-block restored-store)))))
               (is (bytes=
                    (hash32-bytes parent-hash)
                    (hash32-bytes
                     (chain-store-canonical-hash
                      restored-store parent-number))))
               (is (not (chain-store-canonical-hash
                         restored-store child-number)))
               (is (bytes=
                    (hash32-bytes child-hash)
                    (hash32-bytes
                     (block-hash
                      (chain-store-known-block restored-store child-hash)))))
               (is (engine-payload-store-state-available-p
                    restored-store child-hash))
               (is (= expected-recipient-balance
                      (chain-store-account-balance
                       restored-store child-hash recipient)))
               (is (same-optional-block-hash-p
                    first-safe-block
                    (chain-store-safe-block restored-store)))
               (is (same-optional-block-hash-p
                    first-finalized-block
                    (chain-store-finalized-block restored-store)))
               (is (not (chain-store-transaction-location
                         restored-store transaction-hash)))
               (is (string= (quantity-to-hex parent-number)
                            (fixture-object-field
                             block-number-before "result")))
               (is (string=
                    (hash32-to-hex child-hash)
                    (fixture-object-field
                     (fixture-object-field block-by-hash-before "result")
                     "hash")))
               (is (null (fixture-object-field receipt-before "result")))
               (is (string= "0x0"
                            (fixture-object-field balance-before "result")))
               (let* ((forkchoice-response
                        (ethereum-lisp.rpc:rpc-handle-request
                         (devnet-cli-engine-forkchoice-v2-request
                          69 child-hash
                          :safe parent-hash
                          :finalized parent-hash)
                         restored-context))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field
                          forkchoice-response "result")
                         "payloadStatus"))
                      (block-number-after
                        (ethereum-lisp.rpc:rpc-handle-request
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 70)
                               (cons "method" "eth_blockNumber")
                               (cons "params" #()))
                         restored-public-context))
                      (receipt-after
                        (ethereum-lisp.rpc:rpc-handle-request
                         (engine-fixture-receipt-request
                          71 transaction-hash)
                         restored-public-context))
                      (balance-after
                        (ethereum-lisp.rpc:rpc-handle-request
                         (engine-fixture-balance-request 72 recipient)
                         restored-public-context)))
                 (is (string= +payload-status-valid+
                              (fixture-object-field
                               forkchoice-status "status")))
                 (is (= child-number
                        (chain-store-head-number restored-store)))
                 (is (bytes=
                      (hash32-bytes child-hash)
                      (hash32-bytes
                       (chain-store-canonical-hash
                        restored-store child-number))))
                 (is (typep
                      (chain-store-transaction-location
                       restored-store transaction-hash)
                      'engine-transaction-location))
                 (is (string= (quantity-to-hex child-number)
                              (fixture-object-field
                               block-number-after "result")))
                 (is (string=
                      (hash32-to-hex transaction-hash)
                      (fixture-object-field
                       (fixture-object-field receipt-after "result")
                       "transactionHash")))
                 (is (string= (quantity-to-hex expected-recipient-balance)
                              (fixture-object-field
                               balance-after "result")))
                 (let ((database
                         (make-file-key-value-database database-path)))
                   (multiple-value-bind (value present-p)
                       (kv-get-chain-canonical-hash database child-number)
                     (is present-p)
                     (is (bytes= (hash32-bytes child-hash) value)))
                   (multiple-value-bind (value present-p)
                       (kv-get-chain-record
                        database
                        :transaction-location
                        (hash32-bytes transaction-hash))
                     (declare (ignore value))
                     (is present-p)))))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-live-persistence-same-head-forkchoice-flushes-local-canonical-block
  (let ((database-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-live-local-canonical" "sexp")))
    (unwind-protect
         (let* ((genesis-json (devnet-cli-funded-txpool-genesis-json))
                (node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-json genesis-json
                   :database-path (namestring database-path)
                   :dev-mode-p t
                   :dev-period-seconds 1))
                (store (ethereum-lisp.cli:devnet-node-store node))
                (config (ethereum-lisp.cli:devnet-node-config node))
                (genesis (ethereum-lisp.cli:devnet-node-genesis-block node))
                (genesis-hash (block-hash genesis))
                (transaction
                  (devnet-cli-txpool-transaction
                   config 0 +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash (transaction-hash transaction))
                (transaction-id (hash32-bytes transaction-hash))
                (raw-transaction (devnet-cli-transaction-raw transaction))
                (public-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-public-service node)))
                (engine-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-service node)))
                (send-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 79)
                         (cons "method" "eth_sendRawTransaction")
                         (cons "params" (list raw-transaction)))
                   public-context))
                ;; This is deliberately a local canonical publication, not a
                ;; newPayload candidate or a forkchoice transition.
                (sealed-block
                  (ethereum-lisp.cli::devnet-node-seal-pending-block node))
                (sealed-hash (block-hash sealed-block))
                (sealed-number
                  (block-header-number (block-header sealed-block)))
                (forkchoice-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (devnet-cli-engine-forkchoice-v2-request
                    80 sealed-hash
                    :safe genesis-hash
                    :finalized genesis-hash)
                   engine-context))
                (forkchoice-status
                  (fixture-object-field
                   (fixture-object-field forkchoice-response "result")
                   "payloadStatus")))
           (is (string= (hash32-to-hex transaction-hash)
                        (fixture-object-field send-response "result")))
           (is (typep sealed-block 'ethereum-block))
           (is (bytes=
                (hash32-bytes sealed-hash)
                (hash32-bytes
                 (chain-store-canonical-hash store sealed-number))))
           (is (engine-payload-store-state-available-p store sealed-hash))
           (is (typep
                (chain-store-transaction-location store transaction-hash)
                'engine-transaction-location))
           (is (string= +payload-status-valid+
                        (fixture-object-field forkchoice-status "status")))
           ;; No lifecycle full export is invoked. A same-head FCU must flush
           ;; the local canonical delta that was published before the request.
           (let ((database (make-file-key-value-database database-path))
                 (sealed-id (hash32-bytes sealed-hash)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database sealed-number)
               (is present-p)
               (is (bytes= sealed-id value)))
             (dolist (kind '(:block :header :receipt :state))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record database kind sealed-id)
                 (declare (ignore value))
                 (is present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-checkpoint database :head)
               (is present-p)
               (is (bytes= sealed-id value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record
                  database :transaction-location transaction-id)
               (declare (ignore value))
               (is present-p)))
           (let* ((restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-json genesis-json
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (restored-public-context
                    (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                     (ethereum-lisp.cli:devnet-node-public-service
                      restored-node)))
                  (restored-state
                    (chain-store-state-db restored-store sealed-hash))
                  (restored-location
                    (chain-store-transaction-location
                     restored-store transaction-hash))
                  (receipt-response
                    (ethereum-lisp.rpc:rpc-handle-request
                     (engine-fixture-receipt-request
                      81 transaction-hash)
                     restored-public-context))
                  (receipt
                    (fixture-object-field receipt-response "result")))
             (is (= sealed-number
                    (chain-store-head-number restored-store)))
             (is (bytes=
                  (hash32-bytes sealed-hash)
                  (hash32-bytes
                   (block-hash (chain-store-head-block restored-store)))))
             (is (bytes=
                  (hash32-bytes sealed-hash)
                  (hash32-bytes
                   (chain-store-canonical-hash
                    restored-store sealed-number))))
             (is (engine-payload-store-state-available-p
                  restored-store sealed-hash))
             (is restored-state)
             (is (bytes=
                  (hash32-bytes (state-db-root restored-state))
                  (hash32-bytes
                   (block-header-state-root (block-header sealed-block)))))
             (is (typep restored-location 'engine-transaction-location))
             (is (bytes=
                  (hash32-bytes sealed-hash)
                  (hash32-bytes
                   (block-hash
                    (engine-transaction-location-block
                     restored-location)))))
             (is (string= (hash32-to-hex transaction-hash)
                          (fixture-object-field receipt
                                                "transactionHash")))
             (is (= 0
                    (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                     restored-store)))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-live-persistence-restores-same-height-reorg-before-lifecycle-export
  (let ((database-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-live-reorg" "sexp")))
    (unwind-protect
         (let* ((case
                  (select-engine-newpayload-v2-fixture-case
                   +engine-newpayload-v2-fixture-path+
                   "shanghai-log-contract-call-with-withdrawal"))
                (genesis-json
                  (json-encode
                   (devnet-cli-engine-fixture-parent-genesis-object case)))
                (parent-block (devnet-cli-engine-fixture-parent-block case))
                (parent-hash (block-hash parent-block))
                (child-block (devnet-cli-engine-fixture-child-block case))
                (child-hash (block-hash child-block))
                (child-number
                  (block-header-number (block-header child-block)))
                (side-block
                  (devnet-cli-engine-fixture-side-sibling-block
                   case parent-block))
                (side-hash (block-hash side-block))
                (transaction (first (block-transactions child-block)))
                (transaction-hash (transaction-hash transaction))
                (transaction-id (hash32-bytes transaction-hash))
                (first-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-json genesis-json
                   :database-path (namestring database-path)))
                (first-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-service first-node)))
                (child-new-payload-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (engine-fixture-payload-request
                    73
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data child-block)))
                   first-context))
                (child-forkchoice-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (devnet-cli-engine-forkchoice-v2-request
                    74 child-hash
                    :safe parent-hash
                    :finalized parent-hash)
                   first-context))
                (side-new-payload-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (engine-fixture-payload-request
                    75
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data side-block)))
                   first-context))
                (side-forkchoice-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (devnet-cli-engine-forkchoice-v2-request
                    76 side-hash
                    :safe parent-hash
                    :finalized parent-hash)
                   first-context)))
           (labels ((response-status (response &optional payload-status-p)
                      (let ((result
                              (fixture-object-field response "result")))
                        (fixture-object-field
                         (if payload-status-p
                             (fixture-object-field result "payloadStatus")
                             result)
                         "status"))))
             (is (string= +payload-status-valid+
                          (response-status child-new-payload-response)))
             (is (string= +payload-status-valid+
                          (response-status child-forkchoice-response t)))
             (is (string= +payload-status-valid+
                          (response-status side-new-payload-response)))
             (is (string= +payload-status-valid+
                          (response-status side-forkchoice-response t))))
           ;; No DEVNET-NODE-EXPORT-DATABASE call occurs after either FCU.
           ;; These records must therefore be the synchronous candidate and
           ;; forkchoice commits, not a lifecycle snapshot.
           (let ((database (make-file-key-value-database database-path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database child-number)
               (is present-p)
               (is (bytes= (hash32-bytes side-hash) value)))
             (dolist (kind '(:block :header :receipt :state))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database kind (hash32-bytes child-hash))
                 (declare (ignore value))
                 (is present-p))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database kind (hash32-bytes side-hash))
                 (declare (ignore value))
                 (is present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record
                  database :transaction-location transaction-id :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :txpool transaction-id)
               (is present-p)
               (is (plusp (length value)))))
           ;; Constructing a second node directly simulates restart before
           ;; shutdown/lifecycle export can run on the first node.
           (let* ((second-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-json genesis-json
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store second-node))
                  (restored-public-context
                    (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                     (ethereum-lisp.cli:devnet-node-public-service
                      second-node)))
                  (restored-state
                    (chain-store-state-db restored-store side-hash))
                  (receipt-response
                    (ethereum-lisp.rpc:rpc-handle-request
                     (engine-fixture-receipt-request
                      77 transaction-hash)
                     restored-public-context))
                  (txpool-response
                    (ethereum-lisp.rpc:rpc-handle-request
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 78)
                           (cons "method" "txpool_status")
                           (cons "params" #()))
                     restored-public-context))
                  (txpool-status
                    (fixture-object-field txpool-response "result"))
                  (restored-transaction
                    (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                     restored-store transaction-hash)))
             (is (= child-number
                    (chain-store-head-number restored-store)))
             (is (bytes=
                  (hash32-bytes side-hash)
                  (hash32-bytes
                   (block-hash (chain-store-head-block restored-store)))))
             (is (bytes=
                  (hash32-bytes side-hash)
                  (hash32-bytes
                   (chain-store-canonical-hash
                    restored-store child-number))))
             (is (bytes=
                  (hash32-bytes parent-hash)
                  (hash32-bytes
                   (block-hash (chain-store-safe-block restored-store)))))
             (is (bytes=
                  (hash32-bytes parent-hash)
                  (hash32-bytes
                   (block-hash
                    (chain-store-finalized-block restored-store)))))
             (is (bytes=
                  (hash32-bytes child-hash)
                  (hash32-bytes
                   (block-hash
                    (chain-store-known-block restored-store child-hash)))))
             (is (not (bytes=
                       (hash32-bytes child-hash)
                       (hash32-bytes
                        (chain-store-canonical-hash
                         restored-store child-number)))))
             (is (engine-payload-store-state-available-p
                  restored-store side-hash))
             (is restored-state)
             (is (bytes=
                  (hash32-bytes (state-db-root restored-state))
                  (hash32-bytes
                   (block-header-state-root (block-header side-block)))))
             (is (not (chain-store-transaction-location
                       restored-store transaction-hash)))
             (is (null (fixture-object-field receipt-response "result")))
             (is (= 1
                    (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                     restored-store)))
             (is restored-transaction)
             (is (bytes= (transaction-encoding transaction)
                         (transaction-encoding restored-transaction)))
             (is (string= "0x1"
                          (fixture-object-field txpool-status "pending")))
             (is (string= "0x0"
                          (fixture-object-field txpool-status "queued")))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-live-persistence-guard-hides-failed-publication-from-public-rpc
  #-sbcl
  (skip-test "Devnet store guard concurrency test requires SBCL threads")
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path +devnet-cli-genesis-fixture+))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (config (ethereum-lisp.cli:devnet-node-config node))
         (parent (ethereum-lisp.cli:devnet-node-genesis-block node))
         (parent-hash (block-hash parent))
         (child-state
           (state-db-copy (chain-store-state-db store parent-hash)))
         (child
           (make-block
            :header
            (make-block-header
             :parent-hash parent-hash
             :beneficiary (zero-address)
             :state-root (state-db-root child-state)
             :mix-hash (zero-hash32)
             :number 1
             :gas-limit (block-header-gas-limit (block-header parent))
             :timestamp (1+ (block-header-timestamp (block-header parent)))
             :base-fee-per-gas
             (expected-base-fee-per-gas (block-header parent)))
            :withdrawals '()))
         (child-hash (block-hash child))
         (engine-context
           (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
            (ethereum-lisp.cli:devnet-node-service node)))
         (public-context
           (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
            (ethereum-lisp.cli:devnet-node-public-service node)))
         (persistence-entered (sb-thread:make-semaphore :count 0))
         (release-persistence (sb-thread:make-semaphore :count 0))
         (public-started (sb-thread:make-semaphore :count 0))
         engine-response
         public-response
         engine-thread
         public-thread)
    (engine-payload-store-put-block
     store child :state-available-p t :canonicalize-p nil)
    (commit-state-db-to-chain-store store child-hash child-state)
    (ethereum-lisp.rpc:rpc-handle-request
     (devnet-cli-engine-forkchoice-v2-request
      81 parent-hash :safe parent-hash :finalized parent-hash)
     engine-context)
    (setf (ethereum-lisp.rpc::rpc-context-forkchoice-persistence-function
           engine-context)
          (lambda (current-store transition)
            (declare (ignore current-store transition))
            (sb-thread:signal-semaphore persistence-entered)
            (sb-thread:wait-on-semaphore release-persistence)
            (error "simulated database failure")))
    (unwind-protect
         (progn
           (setf engine-thread
                 (sb-thread:make-thread
                  (lambda ()
                    (setf engine-response
                          (ethereum-lisp.rpc:rpc-handle-request
                           (devnet-cli-engine-forkchoice-v2-request
                            82 child-hash
                            :safe parent-hash
                            :finalized parent-hash)
                           engine-context)))
                  :name "ethereum-lisp-test-forkchoice"))
           (sb-thread:wait-on-semaphore persistence-entered)
           (setf public-thread
                 (sb-thread:make-thread
                  (lambda ()
                    (sb-thread:signal-semaphore public-started)
                    (setf public-response
                          (ethereum-lisp.rpc:rpc-handle-request
                           (list (cons "jsonrpc" "2.0")
                                 (cons "id" 83)
                                 (cons "method" "eth_blockNumber")
                                 (cons "params" #()))
                           public-context)))
                  :name "ethereum-lisp-test-public-rpc"))
           (sb-thread:wait-on-semaphore public-started)
           (is (eq :timeout
                   (sb-thread:join-thread
                    public-thread :timeout 0.2 :default :timeout)))
           (sb-thread:signal-semaphore release-persistence)
           (sb-thread:join-thread engine-thread)
           (sb-thread:join-thread public-thread)
           (let ((rpc-error (fixture-object-field engine-response "error")))
             (is (= -32603 (fixture-object-field rpc-error "code"))))
           (is (string= "0x0"
                        (fixture-object-field public-response "result")))
           (is (not (chain-store-canonical-hash store 1)))
           (is (bytes= (hash32-bytes parent-hash)
                       (hash32-bytes
                        (block-hash (chain-store-head-block store))))))
      (sb-thread:signal-semaphore release-persistence)
      (when (and engine-thread (sb-thread:thread-alive-p engine-thread))
        (sb-thread:join-thread engine-thread))
      (when (and public-thread (sb-thread:thread-alive-p public-thread))
        (sb-thread:join-thread public-thread)))))
