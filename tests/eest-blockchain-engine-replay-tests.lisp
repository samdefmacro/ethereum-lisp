(in-package #:ethereum-lisp.test)

(deftest eest-blockchain-engine-newpayload-v2-replay
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let ((root (execution-spec-tests-blockchain-test-root
                 "tests/fixtures/execution-spec-tests-root/")))
      (dolist (source-case (load-phase-a-eest-blockchain-replay-cases root))
        (let* ((case (materialize-eest-blockchain-engine-newpayload-v2-case
                      source-case))
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
                         (fixture-object-field payload-case "withdrawals"))))
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
                 (payload
                   (execution-payload-envelope-execution-payload
                    (block-to-executable-data child-block))))
            (engine-payload-store-put-block
             store parent-block :state-available-p t)
            (commit-state-db-to-chain-store
             store (block-hash parent-block) parent-state)
            (let* ((response
                     (engine-rpc-handle-request
                      (engine-fixture-payload-request 301 payload)
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
              (is (string= (fixture-object-field expect "stateRoot")
                           (hash32-to-hex
                            (block-header-state-root
                             (block-header child-block)))))
              (is (string= (fixture-object-field expect "receiptsRoot")
                           (hash32-to-hex
                            (block-header-receipts-root
                             (block-header child-block)))))
              (is (= (hex-to-quantity (fixture-object-field expect "gasUsed"))
                      (block-header-gas-used
                       (block-header child-block))))
              (assert-eest-blockchain-post-state
               (chain-store-state-db store (block-hash child-block))
               source-case))))))))

(defun assert-eest-blockchain-engine-newpayload-v2-replay
    (case &key source-case)
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
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
                     (fixture-object-field payload-case "withdrawals"))))
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
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((response
                 (engine-rpc-handle-request
                  (engine-fixture-payload-request 301 payload)
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
          (is (string= (fixture-object-field expect "stateRoot")
                       (hash32-to-hex
                        (block-header-state-root
                         (block-header child-block)))))
          (is (string= (fixture-object-field expect "receiptsRoot")
                       (hash32-to-hex
                        (block-header-receipts-root
                         (block-header child-block)))))
          (is (= (hex-to-quantity (fixture-object-field expect "gasUsed"))
                 (block-header-gas-used
                  (block-header child-block))))
          (when source-case
            (assert-eest-blockchain-post-state
             (chain-store-state-db store (block-hash child-block))
             source-case)))))))

(deftest optional-phase-a-eest-blockchain-replay-executes
  (dolist (source-case (load-optional-phase-a-eest-blockchain-replay-cases))
    (assert-eest-blockchain-engine-newpayload-v2-replay
     (materialize-eest-blockchain-engine-newpayload-v2-case source-case)
     :source-case source-case)))

