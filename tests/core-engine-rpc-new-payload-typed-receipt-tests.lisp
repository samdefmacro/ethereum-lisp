(in-package #:ethereum-lisp.test)

(deftest engine-rpc-new-payload-v2-internal-create2-receipt-has-no-contract-address
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash)))))
           (forkchoice-request (id head checkpoint)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV2")
                   (cons "params"
                         (list
                          (list
                           (cons "headBlockHash" (hash32-to-hex head))
                           (cons "safeBlockHash"
                                 (hash32-to-hex checkpoint))
                           (cons "finalizedBlockHash"
                                 (hash32-to-hex checkpoint))))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0))
           (private-key 1)
           (sender (fixture-private-key-address private-key))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000ce"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           ;; CODECOPY the initcode after this prefix, then CREATE2 with salt 5.
           ;; The initcode returns one zero runtime byte.
           (initcode #(96 0 96 0 83 96 1 96 0 243))
           (create2-code
             (concat-bytes
              #(96 10 96 14 95 57 96 5 96 10 95 95 245 0)
              initcode))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 100
                                       :gas-limit 180000
                                       :to contract)
              private-key
              1))
           (salt-bytes (make-byte-vector 32))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (setf (aref salt-bytes 31) 5)
      (let ((created-contract
              (make-address
               (subseq
                (keccak-256
                 (concat-bytes #(255)
                               (address-bytes contract)
                               salt-bytes
                               (keccak-256 initcode)))
                12 32))))
        (state-db-set-account parent-state sender
                              (make-state-account
                               :nonce 0
                               :balance 1000000000))
        (state-db-set-code parent-state contract create2-code)
        (let* ((parent-header
                 (make-block-header
                  :parent-hash (zero-hash32)
                  :beneficiary fee-recipient
                  :state-root (state-db-root parent-state)
                  :mix-hash (zero-hash32)
                  :number 41
                  :gas-limit 200000
                  :gas-used 100000
                  :timestamp 98
                  :base-fee-per-gas 100
                  :withdrawals-root (withdrawal-list-root '())))
               (parent-block (make-block :header parent-header))
               (execution-state (state-db-copy parent-state))
               (child-block
                 (execute-signed-block
                  execution-state
                  (list transaction)
                  :expected-chain-id 1
                  :header (make-block-header
                           :parent-hash (block-hash parent-block)
                           :beneficiary fee-recipient
                           :mix-hash (zero-hash32)
                           :number 42
                           :gas-limit 200000
                           :gas-used 0
                           :timestamp 99
                           :base-fee-per-gas 100)
                  :chain-config config
                  :withdrawals (list withdrawal)))
               (payload
                 (execution-payload-envelope-execution-payload
                  (block-to-executable-data child-block)))
               (request
                 (list (cons "jsonrpc" "2.0")
                       (cons "id" 31)
                       (cons "method" "engine_newPayloadV2")
                       (cons "params"
                             (list (engine-rpc-executable-data-object
                                    payload))))))
          (engine-payload-store-put-block
           store parent-block :state-available-p t)
          (commit-state-db-to-chain-store
           store (block-hash parent-block) parent-state)
          (let* ((import-response
                   (engine-rpc-handle-request
                    request store config
                    :import-function #'execute-and-commit-engine-payload))
                 (import-result (field import-response "result")))
            (is (string= +payload-status-valid+
                         (field import-result "status")))
            (is (bytes= #(0)
                        (chain-store-account-code
                         store (block-hash child-block) created-contract)))
            (is (null (chain-store-transaction-location
                       store
                       (transaction-hash transaction))))
            (is (null
                 (field
                  (engine-rpc-handle-request
                   (receipt-request 32 (transaction-hash transaction))
                   store config)
                  "result")))
            (let* ((forkchoice-response
                     (engine-rpc-handle-request
                      (forkchoice-request
                       33
                       (block-hash child-block)
                       (block-hash parent-block))
                      store config))
                   (forkchoice-status
                     (field (field forkchoice-response "result")
                            "payloadStatus")))
              (is (string= +payload-status-valid+
                           (field forkchoice-status "status")))
              (let* ((receipt-response
                       (engine-rpc-handle-request
                        (receipt-request 34 (transaction-hash transaction))
                        store config))
                     (receipt (field receipt-response "result")))
                (is (null (field receipt "contractAddress")))
                (is (string= (address-to-hex contract)
                             (field receipt "to")))
                (is (string= (quantity-to-hex 1) (field receipt "status")))
                (is (string= (quantity-to-hex 0)
                             (field receipt "transactionIndex")))
                (is (string= (hash32-to-hex (transaction-hash transaction))
                             (field receipt "transactionHash")))
                (is (string= (hash32-to-hex (block-hash child-block))
                             (field receipt "blockHash")))))))))))

(deftest engine-rpc-new-payload-v2-dynamic-fee-typed-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash)))))
           (forkchoice-request (id head checkpoint)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV2")
                   (cons "params"
                         (list
                          (list
                           (cons "headBlockHash" (hash32-to-hex head))
                           (cons "safeBlockHash"
                                 (hash32-to-hex checkpoint))
                           (cons "finalizedBlockHash"
                                 (hash32-to-hex checkpoint))))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0xd02d72e067e77158444ef2020ff2d325f929b363"))
           (recipient
             (address-from-hex "0x1111111111111111111111111111111111111111"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (transaction
             (make-dynamic-fee-transaction
              :chain-id 1
              :nonce 1
              :max-priority-fee-per-gas 0
              :max-fee-per-gas #x0fa0
              :gas-limit #x84d0
              :to recipient
              :value 0
              :data #()
              :y-parity 1
              :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
              :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 1
                             :balance 1000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 100000
                :gas-used 50000
                :timestamp 98
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (execution-state (state-db-copy parent-state))
             (child-block
               (execute-signed-block
                execution-state
                (list transaction)
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 31)
                     (cons "method" "engine_newPayloadV2")
                     (cons "params"
                           (list (engine-rpc-executable-data-object
                                  payload))))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((import-response
                 (engine-rpc-handle-request
                  request store config
                  :import-function #'execute-and-commit-engine-payload))
               (import-result (field import-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
          (is (null (chain-store-transaction-location
                     store
                     (transaction-hash transaction))))
          (is (null
               (field
                (engine-rpc-handle-request
                 (receipt-request 32 (transaction-hash transaction))
                 store config)
                "result")))
          (let* ((forkchoice-response
                   (engine-rpc-handle-request
                    (forkchoice-request
                     33
                     (block-hash child-block)
                     (block-hash parent-block))
                    store config))
                 (forkchoice-status
                   (field (field forkchoice-response "result")
                          "payloadStatus")))
            (is (string= +payload-status-valid+
                         (field forkchoice-status "status")))
            (let* ((receipts
                     (chain-store-block-receipts store (block-hash child-block)))
                   (receipt-response
                     (engine-rpc-handle-request
                      (receipt-request 34 (transaction-hash transaction))
                      store config))
                   (receipt (field receipt-response "result")))
              (is (= 1 (length receipts)))
              (is (string= (hash32-to-hex
                            (transaction-receipt-list-root
                             (list transaction)
                             receipts))
                           (hash32-to-hex
                            (block-header-receipts-root
                             (block-header child-block)))))
              (is (not
                   (string= (hash32-to-hex (receipt-list-root receipts))
                            (hash32-to-hex
                             (block-header-receipts-root
                              (block-header child-block))))))
              (is (string= (quantity-to-hex 2) (field receipt "type")))
              (is (string= (quantity-to-hex 1) (field receipt "status")))
              (is (string= (quantity-to-hex 100)
                           (field receipt "effectiveGasPrice")))
              (is (string= (hash32-to-hex (transaction-hash transaction))
                           (field receipt "transactionHash")))
              (is (string= (hash32-to-hex (block-hash child-block))
                           (field receipt "blockHash"))))))))))

(deftest engine-rpc-new-payload-v2-access-list-typed-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash)))))
           (forkchoice-request (id head checkpoint)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV2")
                   (cons "params"
                         (list
                          (list
                           (cons "headBlockHash" (hash32-to-hex head))
                           (cons "safeBlockHash"
                                 (hash32-to-hex checkpoint))
                           (cons "finalizedBlockHash"
                                 (hash32-to-hex checkpoint))))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0))
           (sender
             (address-from-hex "0x27cf7d8449c9da59189427619ba59f985cee9c0f"))
           (recipient
             (address-from-hex "0xb94f5374fce5edbc8e2a8697c15331677e6ebf0b"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (transaction
             (make-access-list-transaction
              :chain-id 1
              :nonce 3
              :gas-price 1
              :gas-limit 25000
              :to recipient
              :value 10
              :data (hex-to-bytes "0x5544")
              :y-parity 1
              :r #xc9519f4f2b30335884581971573fadf60c6204f59a911df35ee8a540456b2660
              :s #x32f1e8e2c5dd761f9e4f88f41c8310aeaba26a8bfcdacfedfa12ec3862d37521))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 3
                             :balance 1000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 100000
                :gas-used 50000
                :timestamp 98
                :base-fee-per-gas 1
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (execution-state (state-db-copy parent-state))
             (child-block
               (execute-signed-block
                execution-state
                (list transaction)
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 1)
                :chain-config config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 33)
                     (cons "method" "engine_newPayloadV2")
                     (cons "params"
                           (list (engine-rpc-executable-data-object
                                  payload))))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((import-response
                 (engine-rpc-handle-request
                  request store config
                  :import-function #'execute-and-commit-engine-payload))
               (import-result (field import-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
          (is (null (chain-store-transaction-location
                     store
                     (transaction-hash transaction))))
          (is (null
               (field
                (engine-rpc-handle-request
                 (receipt-request 34 (transaction-hash transaction))
                 store config)
                "result")))
          (let* ((forkchoice-response
                   (engine-rpc-handle-request
                    (forkchoice-request
                     35
                     (block-hash child-block)
                     (block-hash parent-block))
                    store config))
                 (forkchoice-status
                   (field (field forkchoice-response "result")
                          "payloadStatus")))
            (is (string= +payload-status-valid+
                         (field forkchoice-status "status")))
            (let* ((receipts
                     (chain-store-block-receipts store (block-hash child-block)))
                   (receipt-response
                     (engine-rpc-handle-request
                      (receipt-request 36 (transaction-hash transaction))
                      store config))
                   (receipt (field receipt-response "result")))
              (is (= 1 (length receipts)))
              (is (string= (hash32-to-hex
                            (transaction-receipt-list-root
                             (list transaction)
                             receipts))
                           (hash32-to-hex
                            (block-header-receipts-root
                             (block-header child-block)))))
              (is (not
                   (string= (hash32-to-hex (receipt-list-root receipts))
                            (hash32-to-hex
                             (block-header-receipts-root
                              (block-header child-block))))))
              (is (string= (quantity-to-hex 1) (field receipt "type")))
              (is (string= (quantity-to-hex 1) (field receipt "status")))
              (is (string= (quantity-to-hex 1)
                           (field receipt "effectiveGasPrice")))
              (is (string= (hash32-to-hex (transaction-hash transaction))
                           (field receipt "transactionHash")))
              (is (string= (hash32-to-hex (block-hash child-block))
                           (field receipt "blockHash"))))))))))
