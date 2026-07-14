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

(deftest devnet-live-persistence-dev-period-seal-is-durable-before-return
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
                (genesis-header (block-header genesis))
                (genesis-hash (block-hash genesis))
                (side-state
                  (state-db-copy
                   (chain-store-state-db store genesis-hash)))
                (side-block
                  (execute-signed-block
                   side-state
                   '()
                   :expected-chain-id (chain-config-chain-id config)
                   :header
                   (make-block-header
                    :parent-hash genesis-hash
                    :beneficiary (zero-address)
                    :mix-hash (zero-hash32)
                    :number 1
                    :gas-limit (block-header-gas-limit genesis-header)
                    :timestamp (1+ (block-header-timestamp genesis-header))
                    :base-fee-per-gas
                    (expected-base-fee-per-gas genesis-header))
                   :chain-config config
                   :withdrawals '()))
                (side-hash (block-hash side-block))
                (engine-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-service node)))
                ;; Import an executable candidate at the next height but do
                ;; not select it through forkchoice.  Local mining must still
                ;; build on the consensus-selected genesis head.
                (side-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (engine-fixture-payload-request
                    78
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data side-block)))
                   engine-context))
                (side-status
                  (fixture-object-field side-response "result"))
                (side-unselected-p
                  (and
                   (engine-payload-store-known-block store side-hash)
                   (engine-payload-store-state-available-p store side-hash)
                   (null (chain-store-canonical-hash store 1))
                   (ethereum-lisp.types:hash32=
                    genesis-hash
                    (block-hash (chain-store-latest-block store)))))
                (transaction
                  (devnet-cli-txpool-transaction
                   config 0 +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash (transaction-hash transaction))
                (transaction-id (hash32-bytes transaction-hash))
                (raw-transaction (devnet-cli-transaction-raw transaction))
                (public-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-public-service node)))
                (send-response
                  (ethereum-lisp.rpc:rpc-handle-request
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 79)
                         (cons "method" "eth_sendRawTransaction")
                         (cons "params" (list raw-transaction)))
                   public-context))
                ;; This is deliberately a local canonical publication.  No
                ;; forkchoice request or lifecycle export follows it.
                (sealed-block
                  (ethereum-lisp.cli::devnet-node-seal-pending-block node))
                (sealed-hash (block-hash sealed-block))
                (sealed-number
                  (block-header-number (block-header sealed-block))))
           (is (string= +payload-status-valid+
                        (fixture-object-field side-status "status")))
           (is (engine-payload-store-known-block store side-hash))
           (is (engine-payload-store-state-available-p store side-hash))
           (is side-unselected-p)
           (is (string= (hash32-to-hex transaction-hash)
                        (fixture-object-field send-response "result")))
           (is (typep sealed-block 'ethereum-block))
           (is (not (ethereum-lisp.types:hash32= sealed-hash side-hash)))
           (is (ethereum-lisp.types:hash32=
                genesis-hash
                (block-header-parent-hash (block-header sealed-block))))
           (is (not (chain-store-canonical-block-p store side-block)))
           (is (bytes=
                (hash32-bytes sealed-hash)
                (hash32-bytes
                 (chain-store-canonical-hash store sealed-number))))
           (is (engine-payload-store-state-available-p store sealed-hash))
           (is (typep
                (chain-store-transaction-location store transaction-hash)
                'engine-transaction-location))
           (is (bytes=
                (hash32-bytes sealed-hash)
                (hash32-bytes
                 (block-hash (chain-store-head-block store)))))
           (is (= 0
                  (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
                   store)))
           (is (null
                (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
                 store)))
           ;; The durable delta must already exist when sealing returns.
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
                      80 transaction-hash)
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
             (is (engine-payload-store-known-block
                  restored-store side-hash))
             (is (not
                  (chain-store-canonical-block-p
                   restored-store side-block)))
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

(deftest devnet-live-persistence-dev-period-write-failure-rolls-back-and-retries
  (let ((database-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-period-rollback" "sexp")))
    (unwind-protect
         (let* ((now 0)
                (genesis-json (devnet-cli-funded-txpool-genesis-json))
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
                (genesis-state-root
                  (state-db-root (chain-store-state-db store genesis-hash)))
                (transaction
                  (devnet-cli-txpool-transaction
                   config 0 +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash (transaction-hash transaction))
                (transaction-id (hash32-bytes transaction-hash))
                (public-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-public-service node)))
                (state
                  (ethereum-lisp.cli::make-devnet-dev-period-state
                   node 1 :now-function (lambda () now)))
                (failing-database
                  (make-instance 'forkchoice-delta-failing-test-database))
                (original-persistence-function
                  (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
                   node))
                (tentative-block nil)
                (tentative-installed-count nil)
                (tentative-dirty-hashes nil))
           ;; Give the injected database the same durable genesis baseline as
           ;; the real configured database.  Its next batch application then
           ;; fails inside the production record-scoped exporter.
           (node-store-export-to-kv store failing-database)
           (forkchoice-delta-test-reset-operations failing-database)
           (setf
            (forkchoice-delta-failing-test-database-apply-attempts
             failing-database)
            0)
           (let ((send-response
                   (ethereum-lisp.rpc:rpc-handle-request
                    (list (cons "jsonrpc" "2.0")
                          (cons "id" 81)
                          (cons "method" "eth_sendRawTransaction")
                          (cons "params"
                                (list
                                 (devnet-cli-transaction-raw transaction))))
                    public-context)))
             (is (string= (hash32-to-hex transaction-hash)
                          (fixture-object-field send-response "result"))))
           (let ((before-database
                   (payload-candidate-export-database-snapshot
                    failing-database)))
             (setf
              (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
               node)
              (lambda (current-store transition)
                (setf tentative-block
                      (first
                       (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
                        transition))
                      tentative-installed-count
                      (length
                       (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
                        transition))
                      tentative-dirty-hashes
                      (ethereum-lisp.canonical-chain:canonical-chain-transition-changed-txpool-hashes
                       transition))
                (ethereum-lisp.node-store.persistence:node-store-export-forkchoice-to-kv
                 current-store transition failing-database)))
             (setf
              (forkchoice-delta-failing-test-database-fail-next-apply-p
               failing-database)
              t
              now 1)
             (signals error
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (is (= 0
                    (ethereum-lisp.cli::devnet-dev-period-state-last-run-time
                     state)))
             (is (= 1 tentative-installed-count))
             (is (typep tentative-block 'ethereum-block))
             (is (forkchoice-delta-test-one-hash-p
                  tentative-dirty-hashes transaction-hash))
             (is (= 1
                    (forkchoice-delta-failing-test-database-apply-attempts
                     failing-database)))
             (is (equalp
                  before-database
                  (payload-candidate-export-database-snapshot
                   failing-database)))
             (is (null
                  (forkchoice-delta-test-database-applied-operation-batches
                   failing-database))))
           ;; Every tentative memory mutation is gone, while the pending
           ;; transaction and its database dirty marker are restored.
           (let ((tentative-hash (block-hash tentative-block)))
             (is (= 0 (chain-store-head-number store)))
             (is (bytes= (hash32-bytes genesis-hash)
                         (hash32-bytes
                          (block-hash (chain-store-latest-block store)))))
             (is (not (chain-store-canonical-hash store 1)))
             (is (not (chain-store-known-block store tentative-hash)))
             (is (not (engine-payload-store-state-available-p
                       store tentative-hash)))
             (is (not (chain-store-transaction-location
                       store transaction-hash)))
             (is (bytes=
                  (hash32-bytes genesis-state-root)
                  (hash32-bytes
                   (state-db-root
                    (chain-store-state-db store genesis-hash)))))
             (is (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                  store transaction-hash))
             (is (forkchoice-delta-test-one-hash-p
                  (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
                   store)
                  transaction-hash))
             (let ((database
                     (make-file-key-value-database database-path)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-checkpoint database :head)
                 (is present-p)
                 (is (bytes= (hash32-bytes genesis-hash) value)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-canonical-hash database 1 :missing)
                 (is (eq :missing value))
                 (is (not present-p)))
               (dolist (kind '(:block :header :receipt :state))
                 (multiple-value-bind (value present-p)
                     (kv-get-chain-record
                      database kind (hash32-bytes tentative-hash) :missing)
                   (is (eq :missing value))
                   (is (not present-p)))))
             ;; The failed tick did not advance its clock, so the same instant
             ;; can retry and deterministically produce the same block.
             (setf
              (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
               node)
              original-persistence-function)
             (let* ((sealed-block
                      (ethereum-lisp.cli::devnet-dev-period-state-tick state))
                    (sealed-hash (block-hash sealed-block)))
               (is (= 1
                      (ethereum-lisp.cli::devnet-dev-period-state-last-run-time
                       state)))
               (is (bytes= (hash32-bytes tentative-hash)
                           (hash32-bytes sealed-hash)))
               (is (bytes= (hash32-bytes sealed-hash)
                           (hash32-bytes
                            (chain-store-canonical-hash store 1))))
               (is (not
                    (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                     store transaction-hash)))
               (is (null
                    (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
                     store)))
               (let ((database
                       (make-file-key-value-database database-path)))
                 (multiple-value-bind (value present-p)
                     (kv-get-chain-checkpoint database :head)
                   (is present-p)
                   (is (bytes= (hash32-bytes sealed-hash) value)))
                 (multiple-value-bind (value present-p)
                     (kv-get-chain-canonical-hash database 1)
                   (is present-p)
                   (is (bytes= (hash32-bytes sealed-hash) value)))
                 (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                      database :transaction-location transaction-id)
                   (declare (ignore value))
                   (is present-p))))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-live-persistence-dev-period-worker-retries-storage-error
  #-sbcl
  (skip-test "Dev-period persistence retry worker requires SBCL threads")
  #+sbcl
  (let ((database-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-period-worker-retry" "sexp")))
    (unwind-protect
         (let* ((sink
                  (ethereum-lisp.telemetry:make-memory-telemetry-sink))
                (genesis-json (devnet-cli-funded-txpool-genesis-json))
                (node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-json genesis-json
                   :database-path (namestring database-path)
                   :dev-mode-p t
                   :dev-period-seconds 1
                   :telemetry-sink sink))
                (store (ethereum-lisp.cli:devnet-node-store node))
                (config (ethereum-lisp.cli:devnet-node-config node))
                (transaction
                  (devnet-cli-txpool-transaction
                   config 0 +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash (transaction-hash transaction))
                (transaction-id (hash32-bytes transaction-hash))
                (public-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-public-service node)))
                (original-persistence-function
                  (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
                   node))
                (shutdown-controller
                  (ethereum-lisp.cli:make-devnet-shutdown-controller))
                (durable-retry-completed
                  (sb-thread:make-semaphore :count 0))
                (persistence-attempts 0)
                (terminal-error nil)
                (worker-thread nil))
           (is (functionp original-persistence-function))
           (let ((send-response
                   (ethereum-lisp.rpc:rpc-handle-request
                    (list (cons "jsonrpc" "2.0")
                          (cons "id" 811)
                          (cons "method" "eth_sendRawTransaction")
                          (cons "params"
                                (list
                                 (devnet-cli-transaction-raw transaction))))
                    public-context)))
             (is (string= (hash32-to-hex transaction-hash)
                          (fixture-object-field send-response "result"))))
           (setf
            (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
             node)
            (lambda (current-store transition)
              (incf persistence-attempts)
              (if (= persistence-attempts 1)
                  (ethereum-lisp.cli::devnet-cli-call-with-retryable-file-write
                   "simulated transient dev-period persistence"
                   (lambda ()
                     (error 'file-error :pathname database-path)))
                  (prog1
                      (funcall original-persistence-function
                               current-store transition)
                    (sb-thread:signal-semaphore
                     durable-retry-completed)))))
           (unwind-protect
                (progn
                  (setf worker-thread
                        (ethereum-lisp.cli::devnet-start-dev-period-thread
                         node
                         shutdown-controller
                         (lambda (condition)
                           (setf terminal-error condition))))
                  (is worker-thread)
                  (unless
                      (sb-thread:wait-on-semaphore
                       durable-retry-completed :timeout 8)
                    (error
                     "Timed out waiting for dev-period worker persistence retry"))
                  ;; The callback signals after its durable write but before
                  ;; the enclosing tick releases the node-store guard.  Enter
                  ;; that guard once to establish a completion barrier before
                  ;; inspecting the committed in-memory view.
                  (ethereum-lisp.cli::call-with-devnet-node-store-guard
                   node (lambda () t))
                  (is (= 2 persistence-attempts))
                  (is (null terminal-error))
                  (is (not
                       (ethereum-lisp.cli:devnet-shutdown-requested-p
                        shutdown-controller)))
                  (is (= 1 (chain-store-head-number store)))
                  (is (not
                       (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                        store transaction-hash)))
                  (let ((retry-event
                          (find
                           "devnet.dev_period.persistence_retry"
                           (ethereum-lisp.telemetry:telemetry-events sink)
                           :key
                           #'ethereum-lisp.telemetry:telemetry-event-name
                           :test #'string=)))
                    (is retry-event)
                    (is (eq :log
                            (ethereum-lisp.telemetry:telemetry-event-kind
                             retry-event)))
                    (is (eq :warning
                            (ethereum-lisp.telemetry:telemetry-event-value
                             retry-event)))
                    (is
                     (search
                      "simulated transient dev-period persistence file write failed"
                      (cdr
                       (assoc
                        "error"
                        (ethereum-lisp.telemetry:telemetry-event-fields
                         retry-event)
                        :test #'string=)))))
                  (let ((database
                          (make-file-key-value-database database-path))
                        (head-hash
                          (block-hash (chain-store-head-block store))))
                    (multiple-value-bind (value present-p)
                        (kv-get-chain-checkpoint database :head)
                      (is present-p)
                      (is (bytes= (hash32-bytes head-hash) value)))
                    (multiple-value-bind (value present-p)
                        (kv-get-chain-canonical-hash database 1)
                      (is present-p)
                      (is (bytes= (hash32-bytes head-hash) value)))
                    (multiple-value-bind (value present-p)
                        (kv-get-chain-record
                         database :transaction-location transaction-id)
                      (declare (ignore value))
                      (is present-p))))
             (ethereum-lisp.cli:devnet-shutdown-request
              shutdown-controller)
             (when (and worker-thread
                        (sb-thread:thread-alive-p worker-thread))
               (when
                   (eq :timeout
                       (sb-thread:join-thread
                        worker-thread :timeout 5 :default :timeout))
                 (sb-thread:terminate-thread worker-thread)
                 (sb-thread:join-thread
                  worker-thread :timeout 1 :default :timeout)))
             (setf
              (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
               node)
              original-persistence-function)))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-live-persistence-dev-period-worker-fail-stops-on-invariant
  #-sbcl
  (skip-test "Dev-period persistence fail-stop worker requires SBCL threads")
  #+sbcl
  (let ((database-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-period-worker-fail-stop" "sexp")))
    (unwind-protect
         (let* ((sink
                  (ethereum-lisp.telemetry:make-memory-telemetry-sink))
                (genesis-json (devnet-cli-funded-txpool-genesis-json))
                (node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-json genesis-json
                   :database-path (namestring database-path)
                   :dev-mode-p t
                   :dev-period-seconds 1
                   :telemetry-sink sink))
                (store (ethereum-lisp.cli:devnet-node-store node))
                (genesis-hash
                  (block-hash
                   (ethereum-lisp.cli:devnet-node-genesis-block node)))
                (config (ethereum-lisp.cli:devnet-node-config node))
                (transaction
                  (devnet-cli-txpool-transaction
                   config 0 +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash (transaction-hash transaction))
                (public-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-public-service node)))
                (original-persistence-function
                  (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
                   node))
                (shutdown-controller
                  (ethereum-lisp.cli:make-devnet-shutdown-controller))
                (terminal-error-received
                  (sb-thread:make-semaphore :count 0))
                (persistence-attempts 0)
                (terminal-error nil)
                (worker-thread nil))
           (let ((send-response
                   (ethereum-lisp.rpc:rpc-handle-request
                    (list (cons "jsonrpc" "2.0")
                          (cons "id" 812)
                          (cons "method" "eth_sendRawTransaction")
                          (cons "params"
                                (list
                                 (devnet-cli-transaction-raw transaction))))
                    public-context)))
             (is (string= (hash32-to-hex transaction-hash)
                          (fixture-object-field send-response "result"))))
           (setf
            (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
             node)
            (lambda (current-store transition)
              (declare (ignore current-store transition))
              (incf persistence-attempts)
              (ethereum-lisp.cli::devnet-cli-call-with-retryable-file-write
               "simulated permanent dev-period persistence"
               (lambda ()
                 (ethereum-lisp.validation:block-validation-fail
                  "simulated permanent dev-period persistence invariant")))))
           (unwind-protect
                (progn
                  (setf worker-thread
                        (ethereum-lisp.cli::devnet-start-dev-period-thread
                         node
                         shutdown-controller
                         (lambda (condition)
                           (setf terminal-error condition)
                           (sb-thread:signal-semaphore
                            terminal-error-received))))
                  (is worker-thread)
                  (unless
                      (sb-thread:wait-on-semaphore
                       terminal-error-received :timeout 8)
                    (error
                     "Timed out waiting for dev-period invariant fail-stop"))
                  (is (not
                       (eq :timeout
                           (sb-thread:join-thread
                            worker-thread :timeout 5 :default :timeout))))
                  (is (= 1 persistence-attempts))
                  (is (typep
                       terminal-error
                       'ethereum-lisp.validation:block-validation-error))
                  (is (ethereum-lisp.cli:devnet-shutdown-requested-p
                       shutdown-controller))
                  (is (= 0 (chain-store-head-number store)))
                  (is (null (chain-store-canonical-hash store 1)))
                  (is
                   (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                    store transaction-hash))
                  (is
                   (not
                    (find
                     "devnet.dev_period.persistence_retry"
                     (ethereum-lisp.telemetry:telemetry-events sink)
                     :key #'ethereum-lisp.telemetry:telemetry-event-name
                     :test #'string=)))
                  (let ((database
                          (make-file-key-value-database database-path)))
                    (multiple-value-bind (value present-p)
                        (kv-get-chain-checkpoint database :head)
                      (is present-p)
                      (is (bytes= (hash32-bytes genesis-hash) value)))
                    (multiple-value-bind (value present-p)
                        (kv-get-chain-canonical-hash database 1 :missing)
                      (is (eq :missing value))
                      (is (not present-p)))))
             (ethereum-lisp.cli:devnet-shutdown-request
              shutdown-controller)
             (when (and worker-thread
                        (sb-thread:thread-alive-p worker-thread))
               (when
                   (eq :timeout
                       (sb-thread:join-thread
                        worker-thread :timeout 5 :default :timeout))
                 (sb-thread:terminate-thread worker-thread)
                 (sb-thread:join-thread
                  worker-thread :timeout 1 :default :timeout)))
             (setf
              (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
               node)
              original-persistence-function)))
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

(deftest devnet-live-persistence-dev-period-guard-hides-tentative-publication
  #-sbcl
  (skip-test "Dev-period store guard concurrency test requires SBCL threads")
  #+sbcl
  (let ((database-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-period-guard" "sexp")))
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
                (public-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-public-service node)))
                (engine-context
                  (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                   (ethereum-lisp.cli:devnet-node-service node)))
                (test-store-mutex
                  (sb-thread:make-mutex
                   :name "ethereum-lisp-test-observable-node-store"))
                (test-store-guard
                  (lambda (thunk)
                    (sb-thread:with-mutex (test-store-mutex)
                      (funcall thunk))))
                (original-node-store-guard
                  (ethereum-lisp.cli::devnet-node-store-guard-function node))
                (original-public-guard
                  (ethereum-lisp.rpc::rpc-context-request-guard-function
                   public-context))
                (original-engine-guard
                  (ethereum-lisp.rpc::rpc-context-request-guard-function
                   engine-context))
                (original-persistence-function
                  (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
                   node))
                (persistence-entered (sb-thread:make-semaphore :count 0))
                (release-persistence (sb-thread:make-semaphore :count 0))
                (public-lock-contended
                  (sb-thread:make-semaphore :count 0))
                (tentative-head-hash nil)
                (tentative-installed-count nil)
                (tentative-location-visible-p nil)
                (tentative-pending-visible-p nil)
                (seal-result nil)
                (seal-error nil)
                (public-response nil)
                (seal-thread nil)
                (public-thread nil))
           (let ((send-response
                   (ethereum-lisp.rpc:rpc-handle-request
                    (list (cons "jsonrpc" "2.0")
                          (cons "id" 82)
                          (cons "method" "eth_sendRawTransaction")
                          (cons "params"
                                (list
                                 (devnet-cli-transaction-raw transaction))))
                    public-context)))
             (is (string= (hash32-to-hex transaction-hash)
                          (fixture-object-field send-response "result"))))
           ;; Preserve coverage of the production wiring before replacing the
           ;; guard with a test-visible mutex for deterministic contention.
           (is (eq original-node-store-guard original-public-guard))
           (is (eq original-node-store-guard original-engine-guard))
           (setf
            (ethereum-lisp.cli::devnet-node-store-guard-function node)
            test-store-guard
            (ethereum-lisp.rpc::rpc-context-request-guard-function
             public-context)
            (lambda (thunk)
              ;; First try the exact mutex used by the seal without waiting.
              ;; Signal only after that real acquisition fails, then block on
              ;; the same mutex before dispatching the RPC.  A scheduler pause
              ;; before lock acquisition can therefore no longer look like
              ;; store-guard isolation.
              (let ((acquired-p nil)
                    (values nil))
                (sb-thread:with-mutex (test-store-mutex :wait-p nil)
                  (setf acquired-p t
                        values (multiple-value-list (funcall thunk))))
                (if acquired-p
                    (values-list values)
                    (progn
                      (sb-thread:signal-semaphore public-lock-contended)
                      (sb-thread:with-mutex (test-store-mutex)
                        (funcall thunk))))))
            (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
             node)
            (lambda (current-store transition)
              (setf tentative-head-hash
                    (block-hash (chain-store-head-block current-store))
                    tentative-installed-count
                    (length
                     (ethereum-lisp.canonical-chain:canonical-chain-transition-installed-blocks
                      transition))
                    tentative-location-visible-p
                    (typep
                     (chain-store-transaction-location
                      current-store transaction-hash)
                     'engine-transaction-location)
                    tentative-pending-visible-p
                    (not
                     (null
                       (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                        current-store transaction-hash))))
              (sb-thread:signal-semaphore persistence-entered)
              (unless
                  (sb-thread:wait-on-semaphore
                   release-persistence :timeout 10)
                (error
                 "Timed out waiting to release simulated persistence failure"))
              (error "simulated dev-period database failure")))
           (unwind-protect
                (progn
                  (setf seal-thread
                        (sb-thread:make-thread
                         (lambda ()
                           (handler-case
                               (setf seal-result
                                     (ethereum-lisp.cli::devnet-node-seal-pending-block
                                      node :timestamp 1))
                             (error (condition)
                               (setf seal-error condition))))
                         :name "ethereum-lisp-test-dev-period-seal"))
                  (unless
                      (sb-thread:wait-on-semaphore
                       persistence-entered :timeout 5)
                    (error
                     "Timed out waiting for dev-period persistence callback"))
                  (setf public-thread
                        (sb-thread:make-thread
                         (lambda ()
                           (setf public-response
                                 (ethereum-lisp.rpc:rpc-handle-request
                                  (list (cons "jsonrpc" "2.0")
                                        (cons "id" 83)
                                        (cons "method" "eth_blockNumber")
                                        (cons "params" #()))
                                  public-context)))
                         :name "ethereum-lisp-test-dev-period-public-rpc"))
                  (unless
                      (sb-thread:wait-on-semaphore
                       public-lock-contended :timeout 5)
                    (error
                     "Timed out waiting for observed public RPC lock contention"))
                  (is (eq :timeout
                          (sb-thread:join-thread
                           public-thread :timeout 0.2 :default :timeout)))
                  (sb-thread:signal-semaphore release-persistence)
                  (is (not
                       (eq :timeout
                           (sb-thread:join-thread
                            seal-thread :timeout 5 :default :timeout))))
                  (is (not
                       (eq :timeout
                           (sb-thread:join-thread
                            public-thread :timeout 5 :default :timeout))))
                  (is (null seal-result))
                  (is seal-error)
                  (is (= 1 tentative-installed-count))
                  (is tentative-location-visible-p)
                  (is (not tentative-pending-visible-p))
                  (is (not (ethereum-lisp.types:hash32=
                            tentative-head-hash genesis-hash)))
                  (is (string= "0x0"
                               (fixture-object-field
                                public-response "result")))
                  (is (= 0 (chain-store-head-number store)))
                  (is (bytes= (hash32-bytes genesis-hash)
                              (hash32-bytes
                               (block-hash
                                (chain-store-latest-block store)))))
                  (is (not (chain-store-canonical-hash store 1)))
                  (is (not
                       (chain-store-transaction-location
                        store transaction-hash)))
                  (is
                   (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                    store transaction-hash))
                  (let ((receipt-response
                          (ethereum-lisp.rpc:rpc-handle-request
                           (engine-fixture-receipt-request
                            84 transaction-hash)
                           public-context)))
                    (is (null
                         (fixture-object-field receipt-response "result")))))
             (sb-thread:signal-semaphore release-persistence)
             (when (and seal-thread (sb-thread:thread-alive-p seal-thread))
               (when
                   (eq :timeout
                       (sb-thread:join-thread
                        seal-thread :timeout 5 :default :timeout))
                 (sb-thread:terminate-thread seal-thread)
                 (sb-thread:join-thread
                  seal-thread :timeout 1 :default :timeout)))
             (when (and public-thread (sb-thread:thread-alive-p public-thread))
               (when
                   (eq :timeout
                       (sb-thread:join-thread
                        public-thread :timeout 5 :default :timeout))
                 (sb-thread:terminate-thread public-thread)
                 (sb-thread:join-thread
                  public-thread :timeout 1 :default :timeout)))
             (setf
              (ethereum-lisp.cli::devnet-node-store-guard-function node)
              original-node-store-guard
              (ethereum-lisp.rpc::rpc-context-request-guard-function
               public-context)
              original-public-guard
              (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
               node)
              original-persistence-function)))
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
