(in-package #:ethereum-lisp.test)

(deftest engine-newpayload-v2-fixture-multi-transaction-receipts
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((case
             (select-engine-newpayload-v2-fixture-case
              +engine-newpayload-v2-fixture-path+
              "shanghai-two-legacy-transfers-with-withdrawal"))
           (store (make-engine-payload-memory-store))
           (config (engine-fixture-chain-config case))
           (parent (fixture-object-field case "parent"))
           (payload-case (fixture-object-field case "payload"))
           (expect (fixture-object-field case "expect"))
           (parent-state (engine-fixture-parent-state parent))
           (fee-recipient (fixture-address-field parent "feeRecipient"))
           (transactions
             (mapcar (lambda (raw)
                       (transaction-from-encoding (hex-to-bytes raw)))
                     (fixture-object-field payload-case "transactions")))
           (withdrawals
             (mapcar #'engine-fixture-withdrawal
                     (fixture-object-field payload-case "withdrawals")))
           (transaction-hashes (mapcar #'transaction-hash transactions))
           (expected-cumulative-gas
             (fixture-object-field expect "cumulativeGasUsed"))
           (expected-receipt-types
             (fixture-object-field expect "receiptTypes"))
           (expected-receipt-statuses
             (fixture-object-field expect "receiptStatuses")))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number (fixture-quantity-field parent "number")
                :gas-limit (fixture-quantity-field parent "gasLimit")
                :gas-used (fixture-quantity-field parent "gasUsed")
                :timestamp (fixture-quantity-field parent "timestamp")
                :base-fee-per-gas
                (fixture-quantity-field parent "baseFeePerGas")
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
             (side-state (state-db-copy parent-state))
             (side-header
               (make-block-header
                :parent-hash (block-hash parent-block)
                :beneficiary fee-recipient
                :mix-hash
                (hash32-from-hex
                 "0x0200000000000000000000000000000000000000000000000000000000000000")
                :number (fixture-quantity-field payload-case "number")
                :gas-limit (fixture-quantity-field payload-case "gasLimit")
                :gas-used 0
                :timestamp
                (1+ (fixture-quantity-field payload-case "timestamp"))
                :base-fee-per-gas
                (fixture-quantity-field payload-case "baseFeePerGas")))
             (side-block
               (execute-signed-block
                side-state
                '()
                :expected-chain-id (chain-config-chain-id config)
                :header side-header
                :chain-config config
                :withdrawals withdrawals))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (side-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data side-block))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (is (string= +payload-status-valid+
                     (field
                      (field
                       (engine-rpc-handle-request
                        (engine-fixture-payload-request 201 payload)
                        store config
                        :import-function #'execute-and-commit-engine-payload)
                       "result")
                      "status")))
        (is (string= +payload-status-valid+
                     (field
                      (field
                       (engine-rpc-handle-request
                        (engine-fixture-payload-request 202 side-payload)
                        store config
                        :import-function #'execute-and-commit-engine-payload)
                       "result")
                      "status")))
        (engine-rpc-handle-request
         (engine-fixture-forkchoice-request
          203 (block-hash child-block)
          :safe (block-hash parent-block)
          :finalized (block-hash parent-block))
         store config)
        (let* ((block-receipts
                 (field (engine-rpc-handle-request
                         (engine-fixture-block-receipts-request
                          204 "latest")
                         store config)
                        "result"))
               (full-block
                 (field (engine-rpc-handle-request
                         (engine-fixture-block-by-number-request
                          205 "latest" t)
                         store config)
                        "result"))
               (full-transactions (field full-block "transactions")))
          (is (= 2 (length block-receipts)))
          (is (= 2 (length full-transactions)))
          (is (string= (quantity-to-hex 2)
                       (field
                        (engine-rpc-handle-request
                         (engine-fixture-transaction-count-by-number-request
                          206 "latest")
                         store config)
                        "result")))
          (is (string= (quantity-to-hex 2)
                       (field
                        (engine-rpc-handle-request
                         (engine-fixture-transaction-count-by-hash-request
                          207 (block-hash child-block))
                         store config)
                        "result")))
          (loop for tx in transactions
                for tx-hash in transaction-hashes
                for receipt in block-receipts
                for full-transaction in full-transactions
                for receipt-type in expected-receipt-types
                for receipt-status in expected-receipt-statuses
                for cumulative-gas in expected-cumulative-gas
                for index from 0
                do (let* ((receipt-by-hash
                            (field
                             (engine-rpc-handle-request
                              (engine-fixture-receipt-request
                               (+ 210 index) tx-hash)
                              store config)
                             "result"))
                          (raw-transaction
                            (field
                             (engine-rpc-handle-request
                              (engine-fixture-raw-transaction-by-block-number-request
                               (+ 220 index) "latest" index)
                              store config)
                             "result"))
                          (transaction-by-block
                            (field
                             (engine-rpc-handle-request
                              (engine-fixture-transaction-by-block-hash-request
                               (+ 230 index) (block-hash child-block) index)
                              store config)
                             "result"))
                          (transaction-by-hash
                            (field
                             (engine-rpc-handle-request
                              (engine-fixture-transaction-by-hash-request
                               (+ 240 index) tx-hash)
                              store config)
                             "result"))
                          (previous-cumulative
                            (if (zerop index)
                                0
                                (hex-to-quantity
                                 (nth (1- index)
                                      expected-cumulative-gas))))
                          (gas-used
                            (- (hex-to-quantity cumulative-gas)
                               previous-cumulative)))
                     (is (string= (hash32-to-hex tx-hash)
                                  (field receipt "transactionHash")))
                     (is (string= (field receipt "transactionHash")
                                  (field receipt-by-hash "transactionHash")))
                     (is (string= receipt-type (field receipt "type")))
                     (is (string= receipt-status (field receipt "status")))
                     (is (string= cumulative-gas
                                  (field receipt "cumulativeGasUsed")))
                     (is (string= (quantity-to-hex gas-used)
                                  (field receipt "gasUsed")))
                     (is (string= (quantity-to-hex index)
                                  (field receipt "transactionIndex")))
                     (is (string= (hash32-to-hex tx-hash)
                                  (field full-transaction "hash")))
                     (is (string= (quantity-to-hex index)
                                  (field full-transaction "transactionIndex")))
                     (is (string= (bytes-to-hex (transaction-encoding tx))
                                  raw-transaction))
                     (is (string= (field full-transaction "hash")
                                  (field transaction-by-block "hash")))
                     (is (string= (field full-transaction "hash")
                                  (field transaction-by-hash "hash"))))))
        (engine-rpc-handle-request
         (engine-fixture-forkchoice-request
          250 (block-hash side-block)
          :safe (block-hash parent-block)
          :finalized (block-hash parent-block))
         store config)
        (is (null
             (field (engine-rpc-handle-request
                     (engine-fixture-block-receipts-request 251 "latest")
                     store config)
                    "result")))
        (dolist (tx-hash transaction-hashes)
          (let ((transaction-by-hash
                  (field (engine-rpc-handle-request
                          (engine-fixture-transaction-by-hash-request
                           252 tx-hash)
                          store config)
                         "result")))
            (is (string= (hash32-to-hex tx-hash)
                         (field transaction-by-hash "hash")))
            (is (null (field transaction-by-hash "blockHash"))))
          (is (null
               (field (engine-rpc-handle-request
                       (engine-fixture-receipt-request 253 tx-hash)
                       store config)
                      "result"))))))))

