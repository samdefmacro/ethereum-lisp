(in-package #:ethereum-lisp.test)

(deftest engine-rpc-forkchoice-switches-executed-payload-visibility
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (payload-request (id payload)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_newPayloadV2")
                   (cons "params"
                         (list (engine-rpc-executable-data-object payload)))))
           (forkchoice-request (id head)
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
           (balance-request (id address)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getBalance")
                   (cons "params" (list (address-to-hex address) "latest"))))
           (transaction-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionByHash")
                   (cons "params" (list (hash32-to-hex hash)))))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash)))))
           (block-receipts-request (id)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getBlockReceipts")
                   (cons "params" (list "latest"))))
           (block-number-request (id)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_blockNumber")
                   (cons "params" #())))
           (transaction-count-request (id address)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionCount")
                   (cons "params" (list (address-to-hex address) "latest"))))
           (code-request (id address)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getCode")
                   (cons "params" (list (address-to-hex address) "latest"))))
           (storage-request (id address)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getStorageAt")
                   (cons "params"
                         (list (address-to-hex address)
                               (quantity-to-hex 0)
                               "latest")))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
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
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
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
      (state-db-set-code parent-state contract #(1 2 3))
      (state-db-set-storage parent-state contract (zero-hash32) 42)
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
             (branch-a-state (state-db-copy parent-state))
             (branch-a-block
               (execute-signed-block
                branch-a-state
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
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-a-child-state (state-db-copy branch-a-state))
             (branch-a-child-block
               (execute-signed-block
                branch-a-child-state
                '()
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash branch-a-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 43
                         :gas-limit 50000
                         :gas-used 0
                         :timestamp 101
                         :base-fee-per-gas 98)
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-b-state (state-db-copy parent-state))
             (branch-b-block
               (execute-signed-block
                branch-b-state
                '()
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (hash32-from-hex
                                    "0x0100000000000000000000000000000000000000000000000000000000000000")
                         :number 42
                         :gas-limit 50000
                         :gas-used 0
                         :timestamp 100
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-a-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-a-block)))
             (branch-a-child-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-a-child-block)))
             (branch-b-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-b-block)))
             (transaction-hash (transaction-hash transaction)))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (dolist (request (list (payload-request 37 branch-a-payload)
                               (payload-request 38 branch-a-child-payload)
                               (payload-request 39 branch-b-payload)))
          (let* ((response
                   (engine-rpc-handle-request
                    request store config
                    :import-function #'execute-and-commit-engine-payload))
                 (status
                   (field (field response "result") "status")))
            (is (string= +payload-status-valid+ status))))
        (engine-rpc-handle-request
         (forkchoice-request 40 (block-hash branch-a-block))
         store config)
        (is (string= (hash32-to-hex (block-hash branch-a-block))
                     (hash32-to-hex (chain-store-canonical-hash store 42))))
        (is (field (engine-rpc-handle-request
                    (transaction-request 40 transaction-hash)
                    store config)
                   "result"))
        (is (field (engine-rpc-handle-request
                    (receipt-request 41 transaction-hash)
                    store config)
                   "result"))
        (is (= 1
               (length
                (field (engine-rpc-handle-request
                        (block-receipts-request 42)
                        store config)
                       "result"))))
        (is (string= (quantity-to-hex 1000000000000000000)
                     (field (engine-rpc-handle-request
                             (balance-request 43 recipient)
                             store config)
                            "result")))
        (is (string= (quantity-to-hex 10)
                     (field (engine-rpc-handle-request
                             (transaction-count-request 44 sender)
                             store config)
                            "result")))
        (is (string= "0x010203"
                     (field (engine-rpc-handle-request
                             (code-request 45 contract)
                             store config)
                            "result")))
        (is (string= "0x000000000000000000000000000000000000000000000000000000000000002a"
                     (field (engine-rpc-handle-request
                             (storage-request 46 contract)
                             store config)
                            "result")))
        (engine-rpc-handle-request
         (forkchoice-request 47 (block-hash branch-a-child-block))
         store config)
        (is (string= (hash32-to-hex (block-hash branch-a-child-block))
                     (hash32-to-hex (chain-store-canonical-hash store 43))))
        (is (= 43 (chain-store-block-tag-number store "latest")))
        (is (string= (quantity-to-hex 43)
                     (field (engine-rpc-handle-request
                             (block-number-request 48)
                             store config)
                            "result")))
        (engine-rpc-handle-request
         (forkchoice-request 49 (block-hash branch-b-block))
         store config)
        (is (string= (hash32-to-hex (block-hash branch-b-block))
                     (hash32-to-hex (chain-store-canonical-hash store 42))))
        (is (not (chain-store-canonical-hash store 43)))
        (is (= 42 (chain-store-block-tag-number store "latest")))
        (is (string= (quantity-to-hex 42)
                     (field (engine-rpc-handle-request
                             (block-number-request 50)
                             store config)
                            "result")))
        (let ((transaction-result
                (field (engine-rpc-handle-request
                        (transaction-request 51 transaction-hash)
                        store config)
                       "result")))
          (is (string= (hash32-to-hex transaction-hash)
                       (field transaction-result "hash")))
          (is (null (field transaction-result "blockHash"))))
        (is (not (field (engine-rpc-handle-request
                         (receipt-request 52 transaction-hash)
                         store config)
                        "result")))
        (is (not (field (engine-rpc-handle-request
                         (block-receipts-request 53)
                         store config)
                        "result")))
        (is (string= (quantity-to-hex 0)
                     (field (engine-rpc-handle-request
                             (balance-request 54 recipient)
                             store config)
                            "result")))
        (is (string= (quantity-to-hex 9)
                     (field (engine-rpc-handle-request
                             (transaction-count-request 55 sender)
                             store config)
                            "result")))
        (is (string= "0x010203"
                     (field (engine-rpc-handle-request
                             (code-request 56 contract)
                             store config)
                            "result")))
        (is (string= "0x000000000000000000000000000000000000000000000000000000000000002a"
                     (field (engine-rpc-handle-request
                             (storage-request 57 contract)
                             store config)
                            "result")))))))

(deftest engine-rpc-forkchoice-switches-executed-log-visibility
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (payload-request (id payload)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_newPayloadV2")
                   (cons "params"
                         (list (engine-rpc-executable-data-object payload)))))
           (forkchoice-request (id head)
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
           (logs-request (id)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getLogs")
                   (cons "params"
                         (list
                          (list (cons "fromBlock" "latest")
                                (cons "toBlock" "latest"))))))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash)))))
           (block-receipts-request (id)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getBlockReceipts")
                   (cons "params" (list "latest"))))
           (private-key-address (private-key)
             (let* ((point
                      (ethereum-lisp.crypto::secp256k1-scalar-multiply
                       private-key
                       (ethereum-lisp.crypto::secp256k1-point
                        ethereum-lisp.crypto::+secp256k1-gx+
                        ethereum-lisp.crypto::+secp256k1-gy+)))
                    (public-key
                      (concat-bytes
                       (ethereum-lisp.crypto::integer-to-fixed-bytes
                        (ethereum-lisp.crypto::secp256k1-point-x point)
                        32)
                       (ethereum-lisp.crypto::integer-to-fixed-bytes
                        (ethereum-lisp.crypto::secp256k1-point-y point)
                        32)))
                    (hashed (keccak-256 public-key))
                    (bytes (make-byte-vector 20)))
               (replace bytes hashed :start2 12)
               (make-address bytes)))
           (sign-legacy-transaction (transaction private-key chain-id)
             (let* ((n ethereum-lisp.crypto::+secp256k1-n+)
                    (half-n ethereum-lisp.crypto::+secp256k1-half-n+)
                    (generator
                      (ethereum-lisp.crypto::secp256k1-point
                       ethereum-lisp.crypto::+secp256k1-gx+
                       ethereum-lisp.crypto::+secp256k1-gy+))
                    (hash
                      (legacy-transaction-signing-hash transaction
                                                       :chain-id chain-id))
                    (message (bytes-to-integer (hash32-bytes hash)))
                    (expected-sender (private-key-address private-key)))
               (loop for k from 1 below 256
                     for r-point =
                       (ethereum-lisp.crypto::secp256k1-scalar-multiply
                        k generator)
                     for r =
                       (mod (ethereum-lisp.crypto::secp256k1-point-x r-point)
                            n)
                     for inverse-k =
                       (ethereum-lisp.crypto::modular-inverse k n)
                     when (and (plusp r) inverse-k)
                       do (let* ((raw-s
                                   (mod (* (+ message (* r private-key))
                                           inverse-k)
                                        n))
                                 (s raw-s)
                                 (y-parity
                                   (if (oddp
                                        (ethereum-lisp.crypto::secp256k1-point-y
                                         r-point))
                                       1
                                       0)))
                            (when (plusp raw-s)
                              (when (> s half-n)
                                (setf s (- n s)
                                      y-parity (- 1 y-parity)))
                              (let ((signed
                                      (make-legacy-transaction
                                       :nonce
                                       (legacy-transaction-nonce transaction)
                                       :gas-price
                                       (legacy-transaction-gas-price
                                        transaction)
                                       :gas-limit
                                       (legacy-transaction-gas-limit
                                        transaction)
                                       :to
                                       (legacy-transaction-to transaction)
                                       :value
                                       (legacy-transaction-value transaction)
                                       :data
                                       (legacy-transaction-data transaction)
                                       :v (+ 35 (* 2 chain-id) y-parity)
                                       :r r
                                       :s s)))
                                (when (bytes=
                                       (address-bytes expected-sender)
                                       (address-bytes
                                        (legacy-transaction-sender
                                         signed
                                         :expected-chain-id chain-id)))
                                  (return signed)))))
                     finally
                       (error "Unable to sign legacy transaction fixture")))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :london-block 0
                                      :shanghai-time 0))
           (private-key 1)
           (sender (private-key-address private-key))
           (fee-recipient
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (withdrawal-recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (contract
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           ;; SSTORE slot 1 := 42; MSTORE 0 := 7; LOG1 topic 9, mem[0:32].
           (contract-code #(96 42 96 1 85 96 7 96 0 82
                            96 9 96 32 96 0 161 0))
           (transaction
             (sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 100
                                       :gas-limit 50000
                                       :to contract
                                       :value 5)
              private-key
              1))
           (second-transaction
             (sign-legacy-transaction
              (make-legacy-transaction :nonce 1
                                       :gas-price 100
                                       :gas-limit 50000
                                       :to contract
                                       :value 6)
              private-key
              1))
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
      (state-db-set-code parent-state contract contract-code)
      (let* ((parent-header
               (make-block-header
                :parent-hash (zero-hash32)
                :beneficiary fee-recipient
                :state-root (state-db-root parent-state)
                :mix-hash (zero-hash32)
                :number 50
                :gas-limit 100000
                :gas-used 50000
                :timestamp 200
                :base-fee-per-gas 100
                :withdrawals-root (withdrawal-list-root '())))
             (parent-block (make-block :header parent-header))
             (branch-a-state (state-db-copy parent-state))
             (branch-a-block
               (execute-signed-block
                branch-a-state
                (list transaction second-transaction)
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (zero-hash32)
                         :number 51
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 201
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-b-state (state-db-copy parent-state))
             (branch-b-block
               (execute-signed-block
                branch-b-state
                '()
                :expected-chain-id 1
                :header (make-block-header
                         :parent-hash (block-hash parent-block)
                         :beneficiary fee-recipient
                         :mix-hash (hash32-from-hex
                                    "0x0200000000000000000000000000000000000000000000000000000000000000")
                         :number 51
                         :gas-limit 100000
                         :gas-used 0
                         :timestamp 202
                         :base-fee-per-gas 100)
                :chain-config config
                :withdrawals (list withdrawal)))
             (branch-a-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-a-block)))
             (branch-b-payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data branch-b-block)))
             (expected-topic-hash
               (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000009"))
             (expected-topic (hash32-to-hex expected-topic-hash))
             (expected-data
               "0x0000000000000000000000000000000000000000000000000000000000000007"))
        (engine-payload-store-put-block
         store parent-block :state-available-p t)
        (commit-state-db-to-chain-store
         store (block-hash parent-block) parent-state)
        (dolist (request (list (payload-request 58 branch-a-payload)
                               (payload-request 59 branch-b-payload)))
          (let* ((response
                   (engine-rpc-handle-request
                    request store config
                    :import-function #'execute-and-commit-engine-payload))
                 (status
                   (field (field response "result") "status")))
            (is (string= +payload-status-valid+ status))))
        (engine-rpc-handle-request
         (forkchoice-request 60 (block-hash branch-a-block))
         store config)
        (let* ((logs
                 (field (engine-rpc-handle-request
                         (logs-request 61)
                         store config)
                        "result"))
               (first-log (first logs))
               (second-log (second logs)))
          (is (= 2 (length logs)))
          (dolist (log logs)
            (is (string= (address-to-hex contract) (field log "address")))
            (is (string= expected-data (field log "data")))
            (is (string= expected-topic (first (field log "topics"))))
            (is (string= (hash32-to-hex (block-hash branch-a-block))
                         (field log "blockHash"))))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field first-log "transactionHash")))
          (is (string= (quantity-to-hex 0)
                       (field first-log "transactionIndex")))
          (is (string= (quantity-to-hex 0)
                       (field first-log "logIndex")))
          (is (string= (hash32-to-hex
                        (transaction-hash second-transaction))
                       (field second-log "transactionHash")))
          (is (string= (quantity-to-hex 1)
                       (field second-log "transactionIndex")))
          (is (string= (quantity-to-hex 1)
                       (field second-log "logIndex"))))
        (let* ((receipt
                 (field (engine-rpc-handle-request
                         (receipt-request 64 (transaction-hash transaction))
                         store config)
                        "result"))
               (bloom
                 (make-bloom (hex-to-bytes (field receipt "logsBloom")))))
          (is (bloom-contains-p bloom (address-bytes contract)))
          (is (bloom-contains-p bloom (hash32-bytes expected-topic-hash))))
        (let* ((receipts
                 (field (engine-rpc-handle-request
                         (block-receipts-request 65)
                         store config)
                        "result"))
               (first-receipt (first receipts))
               (second-receipt (second receipts))
               (first-cumulative
                 (hex-to-quantity
                  (field first-receipt "cumulativeGasUsed")))
               (second-cumulative
                 (hex-to-quantity
                  (field second-receipt "cumulativeGasUsed"))))
          (is (= 2 (length receipts)))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field first-receipt "transactionHash")))
          (is (string= (hash32-to-hex
                        (transaction-hash second-transaction))
                       (field second-receipt "transactionHash")))
          (is (< first-cumulative second-cumulative))
          (is (= (block-header-gas-used (block-header branch-a-block))
                 second-cumulative))
          (is (string= (quantity-to-hex first-cumulative)
                       (field first-receipt "gasUsed")))
          (is (string= (quantity-to-hex
                        (- second-cumulative first-cumulative))
                       (field second-receipt "gasUsed")))
          (is (string= (quantity-to-hex 0)
                       (field first-receipt "transactionIndex")))
          (is (string= (quantity-to-hex 1)
                       (field second-receipt "transactionIndex")))
          (is (= 1 (length (field first-receipt "logs"))))
          (is (= 1 (length (field second-receipt "logs"))))
          (is (string= (quantity-to-hex 0)
                       (field (first (field first-receipt "logs"))
                              "logIndex")))
          (is (string= (quantity-to-hex 1)
                       (field (first (field second-receipt "logs"))
                              "logIndex"))))
        (engine-rpc-handle-request
         (forkchoice-request 62 (block-hash branch-b-block))
         store config)
        (is (string= (hash32-to-hex (block-hash branch-b-block))
                     (hash32-to-hex (chain-store-canonical-hash store 51))))
        (is (zerop
             (length
              (field (engine-rpc-handle-request
                      (logs-request 63)
                      store config)
                     "result"))))
        (is (not
             (field (engine-rpc-handle-request
                     (receipt-request 66 (transaction-hash transaction))
                     store config)
                    "result")))
        (is (not
             (field (engine-rpc-handle-request
                     (receipt-request 67 (transaction-hash second-transaction))
                     store config)
                    "result")))
        (is (not
             (field (engine-rpc-handle-request
                     (block-receipts-request 68)
                     store config)
                    "result")))))))

