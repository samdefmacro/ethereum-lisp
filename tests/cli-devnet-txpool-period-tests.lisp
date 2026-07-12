(in-package #:ethereum-lisp.test)

(deftest devnet-cli-txpool-journal-persists-pending-transactions
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-journal" "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((seed-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path (namestring genesis-path)
                   :port 0
                   :txpool-journal-path (namestring journal-path)))
                (seed-store (ethereum-lisp.cli:devnet-node-store seed-node))
                (transaction
                  (devnet-cli-txpool-transaction
                   (ethereum-lisp.cli:devnet-node-config seed-node)
                   0
                   +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash (transaction-hash transaction)))
           (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
            seed-store
            transaction)
           (ethereum-lisp.cli::devnet-node-export-database seed-node)
           (let ((journal (make-file-key-value-database journal-path)))
             (is (= 1 (length (kv-chain-record-entries journal :txpool)))))
           (let* ((restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :txpool-journal-path (namestring journal-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (summary
                    (ethereum-lisp.cli:devnet-node-summary restored-node))
                  (summary-json
                    (ethereum-lisp.cli::devnet-node-summary-json-object
                     restored-node)))
             (is (string= (namestring journal-path)
                          (getf summary :txpool-journal-path)))
             (is (string= (namestring journal-path)
                          (cdr (assoc "txpoolJournalPath"
                                      summary-json
                                      :test #'string=))))
             (is (bytes= (transaction-encoding transaction)
                         (transaction-encoding
                          (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                           restored-store
                           transaction-hash)))))))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-journal-coexists-with-database-restore
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-database" "sexp"))
        (journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-journal" "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :database-path (namestring database-path)
                     :txpool-journal-path (namestring journal-path)))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config seed-node)
                     0
                     +devnet-cli-txpool-pending-gas-price+))
                  (transaction-hash (transaction-hash transaction)))
             (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
              seed-store
              transaction)
             (ethereum-lisp.cli::devnet-node-export-database seed-node)
             (is (= 1
                    (length
                     (kv-chain-record-entries
                      (make-file-key-value-database database-path)
                      :txpool))))
             (is (= 1
                    (length
                     (kv-chain-record-entries
                      (make-file-key-value-database journal-path)
                      :txpool))))
             (let* ((restored-node
                      (ethereum-lisp.cli:make-devnet-node
                       :genesis-path (namestring genesis-path)
                       :port 0
                       :database-path (namestring database-path)
                       :txpool-journal-path (namestring journal-path)))
                    (restored-store
                      (ethereum-lisp.cli:devnet-node-store restored-node)))
               (is (bytes= (transaction-encoding transaction)
                           (transaction-encoding
                            (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                             restored-store
                             transaction-hash)))))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-rejournal-refreshes-live-journal
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-rejournal"
                                "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json"))
        (now 100))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :txpool-journal-path (namestring journal-path)
                     :txpool-rejournal-seconds 10))
                  (state
                    (ethereum-lisp.cli::make-devnet-rejournal-state
                     node
                     10
                     :now-function (lambda () now)))
                  (transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config node)
                     0
                     +devnet-cli-txpool-pending-gas-price+))
                  (telemetry-fields
                    (ethereum-lisp.cli::devnet-node-telemetry-fields node)))
             (is (string= "10"
                          (cdr (assoc "txpoolRejournalSeconds"
                                      telemetry-fields
                                      :test #'string=))))
             (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
              (ethereum-lisp.cli:devnet-node-store node)
              transaction)
             (setf now 109)
             (is (eq nil
                     (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
             (is (not (probe-file journal-path)))
             (setf now 110)
             (is (eq t
                     (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
             (let ((journal (make-file-key-value-database journal-path)))
               (is (= 1
                      (length
                       (kv-chain-record-entries journal :txpool)))))))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-rejournal-without-journal-is-noop
  (let ((unused-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-unused-rejournal"
                                "sexp"))
        (now 0))
    (unwind-protect
         (let* ((node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :port 0
                   :txpool-rejournal-seconds 1))
                (state
                  (ethereum-lisp.cli::make-devnet-rejournal-state
                   node
                   1
                   :now-function (lambda () now))))
           (setf now 1)
           (is (eq nil
                   (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
           (is (not (probe-file unused-path))))
      (when (probe-file unused-path)
        (delete-file unused-path)))))

(deftest devnet-cli-dev-period-parses-and-reports-duration
  (let* ((options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet"
                  "--dev"
                  "--dev.period=2m"
                  "--no-serve")))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path +devnet-cli-genesis-fixture+
            :port 0
            :dev-mode-p (getf options :dev-mode-p)
            :dev-period-seconds (getf options :dev-period-seconds)))
         (summary
           (ethereum-lisp.cli::devnet-node-summary-json-object node))
         (telemetry-fields
           (ethereum-lisp.cli::devnet-node-telemetry-fields node)))
    (is (= 120 (getf options :dev-period-seconds)))
    (is (= 120 (fixture-object-field summary "devPeriodSeconds")))
    (is (string= "120"
                 (cdr (assoc "devPeriodSeconds"
                             telemetry-fields
                             :test #'string=))))
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--dev.period=-1" "--no-serve")))
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--dev.period=bad" "--no-serve")))))

(deftest devnet-cli-dev-period-tick-seals-public-txpool-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json)
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (raw-transaction (devnet-cli-transaction-raw transaction))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now)))
           (send-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":1,"
               "\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\"" raw-transaction "\"]}")
              node)))
      (is (string= transaction-hash (field send-response "result")))
      (is (eq nil (ethereum-lisp.cli::devnet-dev-period-state-tick state)))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (block-number-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"eth_blockNumber\",\"params\":[]}"
                node))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                node))
             (receipt-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":4,"
                 "\"method\":\"eth_getTransactionReceipt\","
                 "\"params\":[\"" transaction-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (mined-transaction (field lookup-response "result"))
             (receipt (field receipt-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (string= (quantity-to-hex 1)
                     (field block-number-response "result")))
        (is (string= transaction-hash
                     (field mined-transaction "hash")))
        (is (string= sealed-hash
                     (field mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field mined-transaction "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field mined-transaction "transactionIndex")))
        (is (string= transaction-hash
                     (field receipt "transactionHash")))
        (is (string= sealed-hash (field receipt "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field receipt "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field receipt "transactionIndex")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-bounds-transactions-by-gas-limit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json
                             :gas-limit 42000)
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (first-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :gas-limit 21000))
           (second-transaction
             (devnet-cli-txpool-transaction
              config
              1
              +devnet-cli-txpool-pending-gas-price+
              :gas-limit 30000))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex
                         (transaction-hash second-transaction)))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now))))
      (dolist (transaction (list first-transaction second-transaction))
        (request
         (concatenate
          'string
          "{\"jsonrpc\":\"2.0\",\"id\":1,"
          "\"method\":\"eth_sendRawTransaction\","
          "\"params\":[\""
          (devnet-cli-transaction-raw transaction)
          "\"]}")
         node))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (first-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":2,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" first-hash "\"]}")
                node))
             (second-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (mined-transaction (field first-lookup "result"))
             (leftover-transaction (field second-lookup "result"))
             (pending-transactions (field pending-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (= 1 (length (block-transactions sealed-block))))
        (is (string= first-hash
                     (hash32-to-hex
                      (transaction-hash
                       (first (block-transactions sealed-block))))))
        (is (string= first-hash
                     (field mined-transaction "hash")))
        (is (string= sealed-hash
                     (field mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 0)
                     (field mined-transaction "transactionIndex")))
        (is (string= second-hash
                     (field leftover-transaction "hash")))
        (is (null (field leftover-transaction "blockHash")))
        (is (= 1 (length pending-transactions)))
        (is (string= second-hash
                     (field (first pending-transactions) "hash")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-selects-fitting-second-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (first-private-key 2)
           (second-private-key +devnet-cli-txpool-private-key+)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json
                             :gas-limit 42000
                             :private-keys (list first-private-key
                                                 second-private-key))
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (first-sender-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :private-key first-private-key
              :gas-limit 21000))
           (first-sender-non-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              1
              +devnet-cli-txpool-pending-gas-price+
              :private-key first-private-key
              :gas-limit 30000))
           (second-sender-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :private-key second-private-key
              :gas-limit 21000))
           (first-fitting-hash
             (hash32-to-hex
              (transaction-hash first-sender-fitting-transaction)))
           (first-non-fitting-hash
             (hash32-to-hex
              (transaction-hash first-sender-non-fitting-transaction)))
           (second-fitting-hash
             (hash32-to-hex
              (transaction-hash second-sender-fitting-transaction)))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now))))
      (dolist (transaction
               (list first-sender-fitting-transaction
                     first-sender-non-fitting-transaction
                     second-sender-fitting-transaction))
        (request
         (concatenate
          'string
          "{\"jsonrpc\":\"2.0\",\"id\":1,"
          "\"method\":\"eth_sendRawTransaction\","
          "\"params\":[\""
          (devnet-cli-transaction-raw transaction)
          "\"]}")
         node))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (mined-hashes
               (mapcar
                (lambda (transaction)
                  (hash32-to-hex (transaction-hash transaction)))
                (block-transactions sealed-block)))
             (second-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":2,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-fitting-hash "\"]}")
                node))
             (second-receipt
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionReceipt\","
                 "\"params\":[\"" second-fitting-hash "\"]}")
                node))
             (leftover-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":4,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" first-non-fitting-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (second-mined-transaction (field second-lookup "result"))
             (second-mined-receipt (field second-receipt "result"))
             (leftover-transaction (field leftover-lookup "result"))
             (pending-transactions (field pending-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (equal (list first-fitting-hash second-fitting-hash)
                   mined-hashes))
        (is (string= second-fitting-hash
                     (field second-mined-transaction "hash")))
        (is (string= sealed-hash
                     (field second-mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field second-mined-transaction "transactionIndex")))
        (is (string= second-fitting-hash
                     (field second-mined-receipt "transactionHash")))
        (is (string= sealed-hash
                     (field second-mined-receipt "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field second-mined-receipt "transactionIndex")))
        (is (string= first-non-fitting-hash
                     (field leftover-transaction "hash")))
        (is (null (field leftover-transaction "blockHash")))
        (is (= 1 (length pending-transactions)))
        (is (string= first-non-fitting-hash
                     (field (first pending-transactions) "hash")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-carries-active-fork-bodies
  (let* ((now 0)
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json
            (devnet-cli-funded-txpool-genesis-json
             :config-fields
             (list (cons "cancunTime" "0x0")
                   (cons "pragueTime" "0x0")
                   (cons "amsterdamTime" "0x0")))
            :port 0
            :dev-mode-p t
            :dev-period-seconds 1))
         (config (ethereum-lisp.cli:devnet-node-config node))
         (transaction
           (devnet-cli-txpool-transaction
            config
            0
            +devnet-cli-txpool-pending-gas-price+))
         (state
           (ethereum-lisp.cli::make-devnet-dev-period-state
            node
            1
            :now-function (lambda () now))))
    (engine-rpc-handle-request-json
     (concatenate
      'string
      "{\"jsonrpc\":\"2.0\",\"id\":1,"
      "\"method\":\"eth_sendRawTransaction\","
      "\"params\":[\"" (devnet-cli-transaction-raw transaction) "\"]}")
     (ethereum-lisp.cli:devnet-node-store node)
     config)
    (setf now 1)
    (let* ((block
             (ethereum-lisp.cli::devnet-dev-period-state-tick state))
           (header (block-header block)))
      (is (typep block 'ethereum-block))
      (is (= 1 (length (block-transactions block))))
      (is (= 0 (block-header-blob-gas-used header)))
      (is (= 0 (block-header-excess-blob-gas header)))
      (is (string= (hash32-to-hex (zero-hash32))
                   (hash32-to-hex
                    (block-header-parent-beacon-root header))))
      (is (block-requests-present-p block))
      (is (null (block-requests block)))
      (is (string= (hash32-to-hex (execution-requests-hash '()))
                   (hash32-to-hex
                    (block-header-requests-hash header))))
      (is (block-block-access-list-present-p block))
      (is (null (block-block-access-list block)))
      (is (string= (hash32-to-hex (block-access-list-hash '()))
                   (hash32-to-hex
                    (block-header-block-access-list-hash header)))))))

(deftest devnet-cli-txpool-journal-rejects-wrong-chain-transactions
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-bad-chain"
                                "sexp")))
    (unwind-protect
         (let* ((config
                  (chain-config-from-genesis-json-file
                   +devnet-cli-genesis-fixture+))
                (transaction
                  (fixture-sign-legacy-transaction
                   (make-legacy-transaction
                    :nonce 0
                    :gas-price +devnet-cli-txpool-gas-price+
                    :gas-limit +devnet-cli-txpool-gas-limit+
                    :to (address-from-hex +devnet-cli-txpool-recipient+)
                    :value +devnet-cli-txpool-value+)
                   +devnet-cli-txpool-private-key+
                   (1+ (chain-config-chain-id config))))
                (journal (make-file-key-value-database journal-path)))
           (kv-put-chain-record
            journal
            :txpool
            (hash32-bytes (transaction-hash transaction))
            (ethereum-lisp.node-store.persistence::chain-store-txpool-transaction-record-rlp
             :pending
             transaction))
           (signals block-validation-error
             (ethereum-lisp.cli:make-devnet-node
              :genesis-path +devnet-cli-genesis-fixture+
              :port 0
              :txpool-journal-path (namestring journal-path))))
      (when (probe-file journal-path)
        (delete-file journal-path)))))

