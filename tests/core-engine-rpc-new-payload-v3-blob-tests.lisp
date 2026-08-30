(in-package #:ethereum-lisp.test)

(deftest engine-rpc-new-payload-v3-validates-shape-before-fork
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request-code (payload versioned-hashes parent-beacon-root)
             (let* ((response
                      (engine-rpc-handle-request
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 34)
                        (cons "method" "engine_newPayloadV3")
                        (cons "params"
                              (list payload
                                    versioned-hashes
                                    parent-beacon-root)))
                       (make-engine-payload-memory-store)
                       (make-chain-config :london-block 0
                                          :cancun-time 1000)))
                    (error (field response "error")))
               (field error "code"))))
    (let* ((json-null (parse-json "null" :preserve-types t))
           (zero-root (hash32-to-hex (zero-hash32)))
           (base-payload
             (engine-rpc-executable-data-object
              (make-executable-data
               :parent-hash (zero-hash32)
               :fee-recipient
               (address-from-hex
                "0x0000000000000000000000000000000000000001")
               :state-root +empty-trie-hash+
               :receipts-root +empty-trie-hash+
               :logs-bloom (make-byte-vector 256)
               :random (zero-hash32)
               :number 1
               :gas-limit 30000000
               :gas-used 0
               :timestamp 1
               :extra-data (make-byte-vector 0)
               :base-fee-per-gas 1
               :block-hash (zero-hash32)
               :transactions '())))
           (blob-gas-only
             (append base-payload (list (cons "blobGasUsed" "0x0"))))
           (excess-blob-gas-only
             (append base-payload (list (cons "excessBlobGas" "0x0"))))
           (complete-payload
             (append base-payload
                     (list (cons "blobGasUsed" "0x0")
                           (cons "excessBlobGas" "0x0")))))
      (is (= -32602 (request-code base-payload json-null json-null)))
      (is (= -32602 (request-code blob-gas-only json-null json-null)))
      (is (= -32602 (request-code excess-blob-gas-only json-null json-null)))
      (is (= -32602 (request-code base-payload #() json-null)))
      (is (= -32602 (request-code base-payload json-null zero-root)))
      (is (= -38005 (request-code complete-payload #() zero-root))))))

(deftest engine-rpc-new-payload-v3-blob-typed-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (payload-request (id payload versioned-hashes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_newPayloadV3")
                   (cons "params"
                         (list (engine-rpc-executable-data-object payload)
                               (mapcar #'hash32-to-hex versioned-hashes)
                               (hash32-to-hex (zero-hash32))))))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash)))))
           (forkchoice-request (id head checkpoint)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV3")
                   (cons "params"
                         (list
                          (list
                           (cons "headBlockHash" (hash32-to-hex head))
                           (cons "safeBlockHash"
                                 (hash32-to-hex checkpoint))
                           (cons "finalizedBlockHash"
                                 (hash32-to-hex checkpoint))))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :shanghai-time 0
                                      :cancun-time 0))
           (sender
             (address-from-hex "0x0c2c51a0990aee1d73c1228de158688341557508"))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (transaction
             (transaction-from-encoding
              (hex-to-bytes
               "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
           (expected-blob-gas-used
             (transaction-blob-gas-used transaction))
           (withdrawal
             (make-withdrawal :index 0
                              :validator-index 1
                              :address withdrawal-recipient
                              :amount 1))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 0
                             :balance 1000000000000000000000))
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
                :withdrawals-root (withdrawal-list-root '())
                :blob-gas-used 0
                :excess-blob-gas 0))
             (parent-block (make-block :header parent-header
                                       :withdrawals '()))
             (execution-state (state-db-copy parent-state))
             (child-block
               (execute-signed-block
                execution-state
                (list transaction)
                :expected-chain-id 1337
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 99
                         :base-fee-per-gas 100
                         :blob-gas-used expected-blob-gas-used
                         :excess-blob-gas 0
                         :parent-beacon-root (zero-hash32))
                :chain-config config
                :withdrawals (list withdrawal)))
             (versioned-hashes
               (coerce (transaction-blob-versioned-hashes transaction) 'list))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request (payload-request 35 payload versioned-hashes)))
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
                 (receipt-request 36 (transaction-hash transaction))
                 store config)
                "result")))
          (let* ((forkchoice-response
                   (engine-rpc-handle-request
                    (forkchoice-request
                     37
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
                      (receipt-request 38 (transaction-hash transaction))
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
              (is (string= (hash32-to-hex (receipt-list-root receipts))
                           (hash32-to-hex
                            (block-header-receipts-root
                             (block-header child-block)))))
              (is (string= (quantity-to-hex 3) (field receipt "type")))
              (is (string= (quantity-to-hex 1) (field receipt "status")))
              (is (string= (quantity-to-hex
                            (transaction-effective-gas-price
                             transaction
                             :base-fee (block-header-base-fee-per-gas
                                        (block-header child-block))))
                           (field receipt "effectiveGasPrice")))
              (is (string= (hash32-to-hex (transaction-hash transaction))
                           (field receipt "transactionHash")))
              (is (string= (hash32-to-hex (block-hash child-block))
                           (field receipt "blockHash"))))))))))
