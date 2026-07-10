(in-package #:ethereum-lisp.test)

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
                    (ethereum-lisp.chain-store.persistence::chain-store-txpool-transaction-record-values
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
