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
               (result (field response "result"))
               (expected-status (fixture-object-field expect "status"))
               (actual-status (field result "status")))
          (unless (string= expected-status actual-status)
            (error "EEST blockchain replay ~A expected status ~A, got ~A (validationError: ~S)"
                   (fixture-object-field case "name")
                   expected-status
                   actual-status
                   (field result "validationError")))
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
  ;; Cancun-and-later cases are deliberately NOT run here. This harness rebuilds
  ;; the block and submits it through a hardcoded newPayloadV2, which cannot
  ;; express a V3/V4 call: it dies on the first Cancun vector with "Header is
  ;; missing parent beacon root", and even if it got past that it would be
  ;; submitting a structurally different request from the one the fixture
  ;; describes. Those cases are covered by
  ;; OPTIONAL-PHASE-A-EEST-ENGINE-LATE-PAYLOAD-REPLAY-EXECUTES, which submits the
  ;; fixture's own parameters through the fixture's own method -- so this filter
  ;; is what keeps the two from either double-covering or, if it were simply
  ;; deleted, reddening every late-fork run for a harness limitation.
  (map-optional-phase-a-eest-blockchain-replay-cases
   (lambda (source-case)
     (unless (phase-a-eest-blockchain-late-payload-case-p source-case)
       (assert-eest-blockchain-engine-newpayload-v2-replay
        (materialize-eest-blockchain-engine-newpayload-v2-case source-case)
        :source-case source-case)))))

(deftest eest-blockchain-replay-standard-config-activates-network-fork
  ;; The standard block-RLP materializer must hand each case a config that
  ;; activates its OWN fork, not Shanghai -- otherwise a Cancun/Prague/Osaka
  ;; case executes under the wrong ruleset, which is precisely the mis-execution
  ;; the non-blocking late-fork conformance job exists to surface. Drive
  ;; engine-fixture-chain-config the way the replay path does and assert
  ;; cumulative activation at the block.
  (labels ((rules-at (network)
             (let ((config
                     (engine-fixture-chain-config
                      (list (cons "chainId" "0x1")
                            (cons "config"
                                  (eest-blockchain-replay-network-config
                                   network))))))
               (list (chain-config-shanghai-p config 1 1)
                     (chain-config-cancun-p config 1 1)
                     (chain-config-prague-p config 1 1)
                     (chain-config-osaka-p config 1 1)))))
    ;; (shanghai cancun prague osaka), each T only once its network is reached.
    (is (equal '(t nil nil nil) (rules-at "Shanghai")))
    (is (equal '(t t nil nil) (rules-at "Cancun")))
    (is (equal '(t t t nil) (rules-at "Prague")))
    (is (equal '(t t t t) (rules-at "Osaka")))))

(deftest eest-engine-fixture-config-installs-deposit-contract
  (let* ((case
           (list (cons "chainId" "0x1")
                 (cons "config"
                       (eest-blockchain-replay-network-config "Prague"))))
         (config (engine-fixture-chain-config case)))
    (is (string=
         +eest-deposit-contract-address+
         (address-to-hex (chain-config-deposit-contract-address config))))))
