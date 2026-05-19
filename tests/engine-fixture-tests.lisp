(in-package #:ethereum-lisp.test)

(defparameter +engine-newpayload-v2-fixture-path+
  "tests/fixtures/execution-spec-tests/engine-newpayload-v2.json")

(defun load-engine-newpayload-v2-fixture-cases (path)
  (handwritten-fixture-cases (load-handwritten-fixture-file path)))

(defun fixture-quantity-field (object name)
  (hex-to-quantity (fixture-object-field object name)))

(defun fixture-address-field (object name)
  (address-from-hex (fixture-object-field object name)))

(defun engine-fixture-chain-config (case)
  (let ((config (fixture-object-field case "config")))
    (make-chain-config
     :chain-id (hex-to-quantity (fixture-object-field case "chainId"))
     :london-block (fixture-quantity-field config "londonBlock")
     :shanghai-time (fixture-quantity-field config "shanghaiTime"))))

(defun engine-fixture-parent-state (parent)
  (let ((state (make-state-db)))
    (dolist (account (fixture-object-field parent "accounts"))
      (state-db-set-account
       state
       (fixture-address-field account "address")
       (make-state-account
        :nonce (fixture-quantity-field account "nonce")
        :balance (fixture-quantity-field account "balance"))))
    state))

(defun engine-fixture-withdrawal (object)
  (make-withdrawal
   :index (fixture-quantity-field object "index")
   :validator-index (fixture-quantity-field object "validatorIndex")
   :address (fixture-address-field object "address")
   :amount (fixture-quantity-field object "amount")))

(defun engine-fixture-payload-request (id payload)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "engine_newPayloadV2")
        (cons "params"
              (list (engine-rpc-executable-data-object payload)))))

(defun engine-fixture-forkchoice-request (id head)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "engine_forkchoiceUpdatedV1")
        (cons "params"
              (list
               (list
                (cons "headBlockHash" (hash32-to-hex head))
                (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                (cons "finalizedBlockHash"
                      (hash32-to-hex (zero-hash32))))))))

(defun engine-fixture-balance-request (id address)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getBalance")
        (cons "params" (list (address-to-hex address) "latest"))))

(defun engine-fixture-receipt-request (id hash)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" "eth_getTransactionReceipt")
        (cons "params" (list (hash32-to-hex hash)))))

(deftest engine-newpayload-v2-fixture-executes-and-becomes-canonical
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((case
             (select-handwritten-fixture-case
              (load-handwritten-fixture-file
               +engine-newpayload-v2-fixture-path+)
              "shanghai-one-transfer-with-withdrawal"))
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
           (recipient (fixture-address-field expect "recipient"))
           (withdrawal-recipient
             (fixture-address-field expect "withdrawalRecipient")))
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
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (transaction-hash (transaction-hash (first transactions))))
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
                  (fixture-object-field expect "recipientBalance"))
                 (chain-store-account-balance
                  store (block-hash child-block) recipient)))
          (is (= (hex-to-quantity
                  (fixture-object-field expect "withdrawalBalance"))
                 (chain-store-account-balance
                  store (block-hash child-block)
                  withdrawal-recipient))))
        (let* ((forkchoice-response
                 (engine-rpc-handle-request
                  (engine-fixture-forkchoice-request
                   102 (block-hash child-block))
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
                  (engine-fixture-balance-request 104 recipient)
                  store config))
               (withdrawal-balance-response
                 (engine-rpc-handle-request
                  (engine-fixture-balance-request 105 withdrawal-recipient)
                  store config))
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
          (is (= 1 (length receipts)))
          (is (string= (hash32-to-hex (receipt-list-root receipts))
                       (hash32-to-hex receipts-root)))
          (is (string= (hash32-to-hex
                        (transaction-receipt-list-root
                         transactions
                         receipts))
                       (hash32-to-hex receipts-root)))
          (is (string= (fixture-object-field expect "receiptType")
                       (field receipt "type")))
          (is (string= (fixture-object-field expect "receiptStatus")
                       (field receipt "status")))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect "recipientBalance")))
                       (field recipient-balance-response "result")))
          (is (string= (quantity-to-hex
                        (hex-to-quantity
                         (fixture-object-field expect "withdrawalBalance")))
                       (field withdrawal-balance-response "result"))))))))
