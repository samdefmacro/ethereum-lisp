(in-package #:ethereum-lisp.test)

(deftest engine-newpayload-v2-fixture-executes-and-becomes-canonical
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (dolist (case-name +engine-newpayload-v2-smoke-case-names+)
      (let* ((case
               (select-engine-newpayload-v2-fixture-case
                +engine-newpayload-v2-fixture-path+
                case-name))
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
             (sender (fixture-address-field expect "sender"))
             (recipient
               (when (fixture-field-present-p expect "recipient")
                 (fixture-address-field expect "recipient")))
             (contract-address
               (when (fixture-field-present-p expect "contractAddress")
                 (fixture-address-field expect "contractAddress")))
             (value-address (or recipient contract-address))
             (value-balance-field
               (if recipient "recipientBalance" "contractBalance"))
             (withdrawal-recipient
               (fixture-address-field expect "withdrawalRecipient"))
             (code-address (fixture-address-field expect "codeAddress"))
             (storage-address (fixture-address-field expect "storageAddress"))
             (storage-key
               (hash32-from-hex (fixture-object-field expect "storageKey"))))
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
             (expected-state (state-db-copy parent-state))
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
                expected-state
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
                 "0x0100000000000000000000000000000000000000000000000000000000000000")
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
                (block-to-executable-data side-block)))
             (transaction-count (length transactions))
             (transaction-hashes (mapcar #'transaction-hash transactions))
             (transaction-hash (first transaction-hashes)))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((response
                 (engine-rpc-handle-request
                  (engine-fixture-payload-request 101 payload)
                  store config
                  :import-function #'execute-and-commit-engine-payload))
               (result (field response "result")))
          (is (string= (fixture-object-field expect "status")
                       (field result "status")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field result "latestValidHash")))
          (is (engine-payload-store-known-block
               store (block-hash child-block)))
          (is (chain-store-state-available-p
               store (block-hash child-block)))
          (is (= (hex-to-quantity (fixture-object-field expect "senderNonce"))
                 (chain-store-account-nonce
                  store (block-hash child-block) sender)))
          (is (= (hex-to-quantity
                  (fixture-object-field expect "senderBalance"))
                 (chain-store-account-balance
                  store (block-hash child-block) sender)))
          (is (= (hex-to-quantity
                  (fixture-object-field expect value-balance-field))
                 (chain-store-account-balance
                  store (block-hash child-block) value-address)))
          (is (= (hex-to-quantity
                  (fixture-object-field expect "withdrawalBalance"))
                 (chain-store-account-balance
                  store (block-hash child-block)
                  withdrawal-recipient))))
        (let* ((side-response
                 (engine-rpc-handle-request
                  (engine-fixture-payload-request 116 side-payload)
                  store config
                  :import-function #'execute-and-commit-engine-payload))
               (side-result (field side-response "result")))
          (is (string= (fixture-object-field expect "status")
                       (field side-result "status")))
          (is (string= (hash32-to-hex (block-hash side-block))
                       (field side-result "latestValidHash")))
          (is (engine-payload-store-known-block
               store (block-hash side-block)))
          (is (chain-store-state-available-p
               store (block-hash side-block))))
        (let* ((forkchoice-response
                 (engine-rpc-handle-request
                  (engine-fixture-forkchoice-request
                   102 (block-hash child-block)
                   :safe (block-hash parent-block)
                   :finalized (block-hash parent-block))
                  store config))
               (forkchoice-result
                 (field forkchoice-response "result"))
               (payload-status
                 (field forkchoice-result "payloadStatus"))
               (receipt-response
                 (engine-rpc-handle-request
                  (engine-fixture-receipt-request 103 transaction-hash)
                  store config))
               (receipt (field receipt-response "result"))
               (recipient-balance-response
                 (engine-rpc-handle-request
                  (engine-fixture-balance-request 104 value-address)
                  store config))
               (withdrawal-balance-response
                 (engine-rpc-handle-request
                  (engine-fixture-balance-request 105 withdrawal-recipient)
                  store config))
               (code-response
                 (engine-rpc-handle-request
                  (engine-fixture-code-request 106 code-address)
                  store config))
               (storage-response
                 (engine-rpc-handle-request
                  (engine-fixture-storage-request
                   107 storage-address storage-key)
                  store config))
               (proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request 133 value-address)
                  store config))
               (proof
                 (field proof-response "result"))
               (expected-proof
                 (state-db-get-proof expected-state value-address nil))
               (decoded-proof
                 (state-proof-result-from-rpc-object proof))
               (latest-sender-proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request 137 sender)
                  store config))
               (latest-sender-proof
                 (field latest-sender-proof-response "result"))
               (expected-sender-proof
                 (state-db-get-proof expected-state sender nil))
               (latest-sender-decoded-proof
                 (state-proof-result-from-rpc-object latest-sender-proof))
               (safe-sender-proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request
                   138 sender :block-selector "safe")
                  store config))
               (safe-sender-proof
                 (field safe-sender-proof-response "result"))
               (parent-sender-proof
                 (state-db-get-proof parent-state sender nil))
               (safe-sender-decoded-proof
                 (state-proof-result-from-rpc-object safe-sender-proof))
               (finalized-sender-proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request
                   139 sender :block-selector "finalized")
                  store config))
               (finalized-sender-proof
                 (field finalized-sender-proof-response "result"))
               (finalized-sender-decoded-proof
                 (state-proof-result-from-rpc-object finalized-sender-proof))
               (storage-proof-response
                 (engine-rpc-handle-request
                  (engine-fixture-proof-request
                   136 storage-address :storage-keys (list storage-key))
                  store config))
               (storage-proof
                 (field storage-proof-response "result"))
               (storage-proof-entry
                 (first (field storage-proof "storageProof")))
               (expected-storage-proof
                 (state-db-get-proof expected-state storage-address
                                     (list storage-key)))
               (expected-storage-entry
                 (first (state-proof-result-storage-proofs
                         expected-storage-proof)))
               (decoded-storage-proof
                 (state-proof-result-from-rpc-object storage-proof))
               (block-by-number-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 108 "latest" nil)
                  store config))
               (block-by-number
                 (field block-by-number-response "result"))
               (safe-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 130 "safe" nil)
                  store config))
               (safe-block
                 (field safe-block-response "result"))
               (finalized-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 131 "finalized" nil)
                  store config))
               (finalized-block
                 (field finalized-block-response "result"))
               (full-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-number-request 109 "latest" t)
                  store config))
               (full-block
                 (field full-block-response "result"))
               (full-block-transaction
                 (first (field full-block "transactions")))
               (block-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-hash-request
                   110 (block-hash child-block) nil)
                  store config))
               (block-by-hash
                 (field block-by-hash-response "result"))
               (side-block-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-block-by-hash-request
                   117 (block-hash side-block) nil)
                  store config))
               (side-block-by-hash
                 (field side-block-by-hash-response "result"))
               (transaction-count-by-number-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-count-by-number-request
                   111 "latest")
                  store config))
               (transaction-count-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-count-by-hash-request
                   112 (block-hash child-block))
                  store config))
               (side-transaction-count-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-count-by-hash-request
                   118 (block-hash side-block))
                  store config))
               (raw-transaction-response
                 (engine-rpc-handle-request
                  (engine-fixture-raw-transaction-by-block-number-request
                   113 "latest" 0)
                  store config))
               (transaction-by-block-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-by-block-hash-request
                   114 (block-hash child-block) 0)
                  store config))
               (transaction-by-block
                 (field transaction-by-block-response "result"))
               (transaction-by-hash-response
                 (engine-rpc-handle-request
                  (engine-fixture-transaction-by-hash-request
                   115 transaction-hash)
                  store config))
               (transaction-by-hash
                 (field transaction-by-hash-response "result"))
               (receipts
                 (chain-store-block-receipts
                  store (block-hash child-block)))
               (receipts-root
                 (block-header-receipts-root (block-header child-block))))
          (is (string= +payload-status-valid+
                       (field payload-status "status")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (hash32-to-hex
                        (chain-store-canonical-hash
                         store
                         (block-header-number
                          (block-header child-block))))))
          (is (= transaction-count (length receipts)))
          (if (zerop (transaction-type (first transactions)))
              (is (string= (hash32-to-hex (receipt-list-root receipts))
                           (hash32-to-hex receipts-root)))
              (is (not
                   (string= (hash32-to-hex (receipt-list-root receipts))
                            (hash32-to-hex receipts-root)))))
          (is (string= (hash32-to-hex
                        (transaction-receipt-list-root
                         transactions
                         receipts))
                       (hash32-to-hex receipts-root)))
          (is (string= (fixture-object-field expect "receiptType")
                       (field receipt "type")))
          (is (string= (fixture-object-field expect "receiptStatus")
                       (field receipt "status")))
          (when (fixture-field-present-p expect "logAddress")
            (let* ((logs (field receipt "logs"))
                   (log (first logs)))
              (is (= (hex-to-quantity (fixture-object-field expect "logCount"))
                     (length logs)))
              (is (string= (fixture-object-field expect "logAddress")
                           (field log "address")))
              (is (string= (fixture-object-field expect "logData")
                           (field log "data")))
              (is (equal (list (fixture-object-field expect "logTopic"))
                         (field log "topics")))
              (is (string= (hash32-to-hex transaction-hash)
                           (field log "transactionHash")))
              (is (string= (hash32-to-hex (block-hash child-block))
                           (field log "blockHash")))
              (is (string= (fixture-object-field payload-case "number")
                           (field log "blockNumber")))
              (is (string= "0x0" (field log "transactionIndex")))
              (is (string= "0x0" (field log "logIndex")))))
          (if recipient
              (progn
                (is (null (field receipt "contractAddress")))
                (is (string= (address-to-hex recipient)
                             (field receipt "to"))))
              (progn
                (is (string= (address-to-hex contract-address)
                             (field receipt "contractAddress")))
                (is (null (field receipt "to")))))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect value-balance-field)))
                       (field recipient-balance-response "result")))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect "withdrawalBalance")))
                       (field withdrawal-balance-response "result")))
          (is (string= (fixture-object-field expect "code")
                       (field code-response "result")))
          (is (string= (fixture-object-field expect "storageValue")
                       (field storage-response "result")))
          (is (string= (address-to-hex value-address)
                       (field proof "address")))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect value-balance-field)))
                       (field proof "balance")))
          (is (string= (quantity-to-hex
                        (state-proof-result-nonce expected-proof))
                       (field proof "nonce")))
          (is (listp (field proof "accountProof")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-proof-result-account-proof expected-proof))
                     (field proof "accountProof")))
          (is (null (field proof "storageProof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header child-block))
               decoded-proof))
          (is (string= (address-to-hex sender)
                       (field latest-sender-proof "address")))
          (is (string= (quantity-to-hex
                        (state-proof-result-balance expected-sender-proof))
                       (field latest-sender-proof "balance")))
          (is (string= (quantity-to-hex
                        (state-proof-result-nonce expected-sender-proof))
                       (field latest-sender-proof "nonce")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-proof-result-account-proof
                              expected-sender-proof))
                     (field latest-sender-proof "accountProof")))
          (is (null (field latest-sender-proof "storageProof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header child-block))
               latest-sender-decoded-proof))
          (is (string= (address-to-hex sender)
                       (field safe-sender-proof "address")))
          (is (string= (quantity-to-hex
                        (state-proof-result-balance parent-sender-proof))
                       (field safe-sender-proof "balance")))
          (is (string= (quantity-to-hex
                        (state-proof-result-nonce parent-sender-proof))
                       (field safe-sender-proof "nonce")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-proof-result-account-proof
                              parent-sender-proof))
                     (field safe-sender-proof "accountProof")))
          (is (null (field safe-sender-proof "storageProof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header parent-block))
               safe-sender-decoded-proof))
          (is (string= (address-to-hex sender)
                       (field finalized-sender-proof "address")))
          (is (string= (field safe-sender-proof "balance")
                       (field finalized-sender-proof "balance")))
          (is (string= (field safe-sender-proof "nonce")
                       (field finalized-sender-proof "nonce")))
          (is (equal (field safe-sender-proof "accountProof")
                     (field finalized-sender-proof "accountProof")))
          (is (null (field finalized-sender-proof "storageProof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header parent-block))
               finalized-sender-decoded-proof))
          (is (not (string= (field latest-sender-proof "nonce")
                            (field safe-sender-proof "nonce"))))
          (is (string= (address-to-hex storage-address)
                       (field storage-proof "address")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-proof-result-account-proof
                              expected-storage-proof))
                     (field storage-proof "accountProof")))
          (is (= 1 (length (field storage-proof "storageProof"))))
          (is (string= (hash32-to-hex storage-key)
                       (field storage-proof-entry "key")))
          (is (string= (quantity-to-hex
                        (state-storage-proof-value expected-storage-entry))
                       (field storage-proof-entry "value")))
          (is (equal (mapcar #'bytes-to-hex
                             (state-storage-proof-proof
                              expected-storage-entry))
                     (field storage-proof-entry "proof")))
          (is (state-db-verify-proof
               (block-header-state-root (block-header child-block))
               decoded-storage-proof))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field block-by-number "hash")))
          (is (string= (hash32-to-hex (block-hash parent-block))
                       (field safe-block "hash")))
          (is (string= (hash32-to-hex (block-hash parent-block))
                       (field finalized-block "hash")))
          (is (string= (quantity-to-hex
                        (block-header-number (block-header child-block)))
                       (field block-by-number "number")))
          (is (equal (mapcar #'hash32-to-hex transaction-hashes)
                     (field block-by-number "transactions")))
          (is (string= (field block-by-number "hash")
                       (field block-by-hash "hash")))
          (is (string= (hash32-to-hex (block-hash side-block))
                       (field side-block-by-hash "hash")))
          (is (string= (quantity-to-hex
                        (block-header-number (block-header side-block)))
                       (field side-block-by-hash "number")))
          (is (not (string= (field block-by-number "hash")
                            (field side-block-by-hash "hash"))))
          (is (string= (hash32-to-hex transaction-hash)
                       (field full-block-transaction "hash")))
          (is (string= (field block-by-number "hash")
                       (field full-block-transaction "blockHash")))
          (is (string= (field block-by-number "number")
                       (field full-block-transaction "blockNumber")))
          (is (string= (quantity-to-hex 0)
                       (field full-block-transaction "transactionIndex")))
          (is (string= (address-to-hex sender)
                       (field full-block-transaction "from")))
          (if recipient
              (is (string= (address-to-hex recipient)
                           (field full-block-transaction "to")))
              (is (null (field full-block-transaction "to"))))
          (is (string= (quantity-to-hex transaction-count)
                       (field transaction-count-by-number-response "result")))
          (is (string= (quantity-to-hex transaction-count)
                       (field transaction-count-by-hash-response "result")))
          (is (string= (quantity-to-hex 0)
                       (field side-transaction-count-by-hash-response "result")))
          (is (string= (bytes-to-hex
                        (transaction-encoding (first transactions)))
                       (field raw-transaction-response "result")))
          (is (string= (field block-by-number "hash")
                       (field transaction-by-block "blockHash")))
          (is (string= (hash32-to-hex transaction-hash)
                       (field transaction-by-block "hash")))
          (is (string= (address-to-hex sender)
                       (field transaction-by-block "from")))
          (if recipient
              (is (string= (address-to-hex recipient)
                           (field transaction-by-block "to")))
              (is (null (field transaction-by-block "to"))))
          (is (string= (field transaction-by-block "hash")
                       (field transaction-by-hash "hash")))
          (is (string= (field transaction-by-block "blockHash")
                       (field transaction-by-hash "blockHash")))
          (let* ((side-forkchoice-response
                   (engine-rpc-handle-request
                    (engine-fixture-forkchoice-request
                     119 (block-hash side-block)
                     :safe (block-hash parent-block)
                     :finalized (block-hash parent-block))
                    store config))
                 (side-forkchoice-result
                   (field side-forkchoice-response "result"))
                 (side-payload-status
                   (field side-forkchoice-result "payloadStatus"))
                 (side-latest-response
                   (engine-rpc-handle-request
                    (engine-fixture-block-by-number-request 120 "latest" nil)
                    store config))
                 (side-latest
                   (field side-latest-response "result"))
                 (side-safe-response
                   (engine-rpc-handle-request
                    (engine-fixture-block-by-number-request 132 "safe" nil)
                    store config))
                 (side-safe
                   (field side-safe-response "result"))
                 (side-latest-count-response
                   (engine-rpc-handle-request
                    (engine-fixture-transaction-count-by-number-request
                     121 "latest")
                    store config))
                 (side-latest-raw-response
                   (engine-rpc-handle-request
                    (engine-fixture-raw-transaction-by-block-number-request
                     122 "latest" 0)
                    store config))
                 (side-transaction-by-hash-response
                   (engine-rpc-handle-request
                    (engine-fixture-transaction-by-hash-request
                     123 transaction-hash)
                    store config))
                 (side-receipt-response
                   (engine-rpc-handle-request
                    (engine-fixture-receipt-request 124 transaction-hash)
                    store config))
                 (side-latest-proof-response
                   (engine-rpc-handle-request
                    (engine-fixture-proof-request 134 value-address)
                    store config))
                 (side-latest-proof
                   (field side-latest-proof-response "result"))
                 (side-expected-proof
                   (state-db-get-proof side-state value-address nil))
                 (side-decoded-proof
                   (state-proof-result-from-rpc-object side-latest-proof))
                 (child-proof-by-hash-response
                   (engine-rpc-handle-request
                    (engine-fixture-proof-request
                     135 value-address
                     :block-selector (hash32-to-hex (block-hash child-block)))
                    store config))
                 (child-proof-by-hash
                   (field child-proof-by-hash-response "result"))
                 (child-by-hash-after-side-response
                   (engine-rpc-handle-request
                    (engine-fixture-block-by-hash-request
                     125 (block-hash child-block) nil)
                    store config))
                 (child-by-hash-after-side
                   (field child-by-hash-after-side-response "result")))
            (is (string= +payload-status-valid+
                         (field side-payload-status "status")))
            (is (string= (hash32-to-hex (block-hash side-block))
                         (hash32-to-hex
                          (chain-store-canonical-hash
                           store
                           (block-header-number
                            (block-header side-block))))))
            (is (string= (hash32-to-hex (block-hash side-block))
                         (field side-latest "hash")))
            (is (string= (hash32-to-hex (block-hash parent-block))
                         (field side-safe "hash")))
            (is (string= (quantity-to-hex 0)
                         (field side-latest-count-response "result")))
            (is (null (field side-latest-raw-response "result")))
            (is (string= (hash32-to-hex transaction-hash)
                         (field (field side-transaction-by-hash-response
                                       "result")
                                "hash")))
            (is (null (field (field side-transaction-by-hash-response
                                    "result")
                             "blockHash")))
            (is (null (field side-receipt-response "result")))
            (is (string= (quantity-to-hex
                          (state-proof-result-balance side-expected-proof))
                         (field side-latest-proof "balance")))
            (is (equal (mapcar #'bytes-to-hex
                               (state-proof-result-account-proof
                                side-expected-proof))
                       (field side-latest-proof "accountProof")))
            (is (state-db-verify-proof
                 (block-header-state-root (block-header side-block))
                 side-decoded-proof))
            (is (string= (field proof "balance")
                         (field child-proof-by-hash "balance")))
            (is (equal (field proof "accountProof")
                       (field child-proof-by-hash "accountProof")))
            (is (string= (hash32-to-hex (block-hash child-block))
                         (field child-by-hash-after-side "hash"))))
          (let* ((child-forkchoice-response
                   (engine-rpc-handle-request
                    (engine-fixture-forkchoice-request
                     126 (block-hash child-block)
                     :safe (block-hash parent-block)
                     :finalized (block-hash parent-block))
                    store config))
                 (child-forkchoice-result
                   (field child-forkchoice-response "result"))
                 (child-payload-status
                   (field child-forkchoice-result "payloadStatus"))
                 (child-latest-response
                   (engine-rpc-handle-request
                    (engine-fixture-block-by-number-request 127 "latest" nil)
                    store config))
                 (child-latest
                   (field child-latest-response "result"))
                 (child-transaction-by-hash-response
                   (engine-rpc-handle-request
                    (engine-fixture-transaction-by-hash-request
                     128 transaction-hash)
                    store config))
                 (child-transaction-by-hash
                   (field child-transaction-by-hash-response "result"))
                 (child-receipt-response
                   (engine-rpc-handle-request
                    (engine-fixture-receipt-request 129 transaction-hash)
                    store config))
                 (child-receipt
                   (field child-receipt-response "result")))
            (is (string= +payload-status-valid+
                         (field child-payload-status "status")))
            (is (string= (hash32-to-hex (block-hash child-block))
                         (hash32-to-hex
                          (chain-store-canonical-hash
                           store
                           (block-header-number
                            (block-header child-block))))))
            (is (string= (hash32-to-hex (block-hash child-block))
                         (field child-latest "hash")))
            (is (string= (hash32-to-hex transaction-hash)
                         (field child-transaction-by-hash "hash")))
            (is (string= (field child-latest "hash")
                         (field child-transaction-by-hash "blockHash")))
            (is (string= (fixture-object-field expect "receiptStatus")
                         (field child-receipt "status"))))))))))
