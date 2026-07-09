(in-package #:ethereum-lisp.test)

(deftest engine-rpc-new-payload-v2-rejects-wrong-chain-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (execution-config (make-chain-config :chain-id 1
                                                :london-block 0
                                                :shanghai-time 0))
           (import-config (make-chain-config :chain-id 2
                                             :london-block 0
                                             :shanghai-time 0))
           (sender
             (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (transaction
             (make-legacy-transaction
              :nonce 9
              :gas-price 20000000000
              :gas-limit 21000
              :to recipient
              :value 1000000000000000000
              :v 37
              :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
              :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 9
                             :balance 2000000000000000000))
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 41
                :gas-limit 50000
                :gas-used 25000
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
                         :gas-limit 50000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 100)
                :chain-config execution-config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 28)
                     (cons "method" "engine_newPayloadV2")
                     (cons "params"
                           (list (engine-rpc-executable-data-object
                                  payload))))))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (let* ((response
                 (engine-rpc-handle-request
                  request store import-config
                  :import-function #'execute-and-commit-engine-payload))
               (result (field response "result")))
          (is (string= +payload-status-invalid+ (field result "status")))
          (is (string= (hash32-to-hex (block-hash parent-block))
                       (field result "latestValidHash")))
          (is (string= "Invalid executable data transaction 0 sender"
                       (field result "validationError")))
          (is (not (chain-store-known-block store (block-hash child-block))))
          (is (not (chain-store-state-available-p
                    store
                    (block-hash child-block))))
          (is (not (chain-store-transaction-location
                    store
                    (transaction-hash transaction))))
          (is (= 9
                 (chain-store-account-nonce
                  store (block-hash parent-block) sender)))
          (is (= 2000000000000000000
                 (chain-store-account-balance
                  store (block-hash parent-block) sender)))
          (is (= 0
                 (chain-store-account-balance
                  store (block-hash parent-block) recipient))))))))

(deftest engine-rpc-new-payload-v2-receipt-contract-address
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
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
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           ;; Store byte 0 in memory, then return it as one byte of runtime code.
           (initcode #(96 0 96 0 83 96 1 96 0 243))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 100
                                       :gas-limit 80000
                                       :to nil
                                       :value 7
                                       :data initcode)
              private-key
              1))
           (contract
             (make-address
              (subseq
               (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes sender) 0)))
               12 32)))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 0
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
                     (cons "id" 29)
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
               (import-result (field import-response "result"))
               (receipt-response
                 (engine-rpc-handle-request
                  (receipt-request 30 (transaction-hash transaction))
                  store config))
               (receipt (field receipt-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
          (is (string= (address-to-hex contract)
                       (field receipt "contractAddress")))
          (is (null (field receipt "to")))
          (is (string= (quantity-to-hex 1) (field receipt "status")))
          (is (string= (quantity-to-hex 0)
                       (field receipt "transactionIndex")))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field receipt "transactionHash")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field receipt "blockHash"))))))))

