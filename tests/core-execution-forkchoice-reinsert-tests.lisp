(in-package #:ethereum-lisp.test)

(deftest chain-store-reinsert-prunes-overgas-conflict-before-reorg-reinsert
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (displaced-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 2
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (overgas-conflict
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 3
             :gas-limit 40000
             :to recipient
             :value 0)
            1
            1))
         (displaced-hash (transaction-hash displaced-transaction))
         (overgas-hash (transaction-hash overgas-conflict))
         (sender (transaction-sender displaced-transaction :expected-chain-id 1))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :gas-limit 50000
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 50000
                               :extra-data #(1))
            :transactions (list displaced-transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000
                               :extra-data #(2)))))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (chain-store-put-account-nonce
     store (block-hash new-canonical-child) sender 0)
    (chain-store-put-account-balance
     store (block-hash new-canonical-child) sender 1000000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store overgas-conflict)
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null
         (ethereum-lisp.core::engine-payload-store-pooled-transaction
          store
          overgas-hash)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (bytes= (transaction-encoding displaced-transaction)
                (transaction-encoding
                 (ethereum-lisp.core::engine-payload-store-pending-transaction
                  store
                  displaced-hash))))))

(deftest engine-rpc-forkchoice-reinsert-enforces-configured-chain-id
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex (zero-hash32)))))
           (forkchoice-request (head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 8174)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list (forkchoice-state-object head))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 2 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (wrong-chain-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 2
               :gas-limit 21000
               :to recipient
               :value 3)
              1
              1))
           (transaction-hash (transaction-hash wrong-chain-transaction))
           (sender (transaction-sender wrong-chain-transaction
                                       :expected-chain-id 1))
           (genesis
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :gas-limit 30000000
                                 :timestamp 0
                                 :extra-data #(0))))
           (old-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(1))
              :transactions (list wrong-chain-transaction)
              :receipts (list (make-receipt :status 1
                                            :cumulative-gas-used 21000))))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(2)))))
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-block store old-canonical-child :state-available-p t)
      (chain-store-put-block store new-canonical-child :state-available-p t)
      (chain-store-put-account-nonce
       store (block-hash new-canonical-child) sender 0)
      (chain-store-put-account-balance
       store (block-hash new-canonical-child) sender 1000000)
      (is (typep (chain-store-transaction-location
                  store transaction-hash)
                 'engine-transaction-location))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request (block-hash new-canonical-child))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus")))
        (is (= 8174 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (null (chain-store-transaction-location
                   store transaction-hash)))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                store)))
        (is (null
             (ethereum-lisp.core::engine-payload-store-pending-transaction
              store
              transaction-hash)))))))

(deftest engine-rpc-forkchoice-reinsert-enforces-blob-fee-cap
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex (zero-hash32)))))
           (forkchoice-request (head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 8175)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list (forkchoice-state-object head))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0))
           (transaction
             (transaction-from-encoding
              (hex-to-bytes
               "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
           (transaction-hash (transaction-hash transaction))
           (sender (transaction-sender transaction :expected-chain-id 1337))
           (genesis
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :gas-limit 30000000
                                 :timestamp 0
                                 :extra-data #(0))))
           (old-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :blob-gas-used 0
                                 :excess-blob-gas 0
                                 :extra-data #(1))
              :transactions (list transaction)
              :receipts (list (make-receipt :status 1
                                            :cumulative-gas-used 21000))))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :blob-gas-used 0
                                 :excess-blob-gas (* 64 1024 1024)
                                 :extra-data #(2)))))
      (is (typep transaction 'blob-transaction))
      (is (> (block-header-blob-base-fee
              (block-header new-canonical-child))
             (blob-transaction-max-fee-per-blob-gas transaction)))
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-block store old-canonical-child :state-available-p t)
      (chain-store-put-block store new-canonical-child :state-available-p t)
      (chain-store-put-account-nonce
       store (block-hash new-canonical-child) sender 0)
      (chain-store-put-account-balance
       store (block-hash new-canonical-child) sender
       10000000000000000000)
      (is (typep (chain-store-transaction-location
                  store transaction-hash)
                 'engine-transaction-location))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request (block-hash new-canonical-child))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus")))
        (is (= 8175 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (null (chain-store-transaction-location
                   store transaction-hash)))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-blob-transaction-count
                store)))
        (is (null
             (ethereum-lisp.core::engine-payload-store-blob-transaction
              store
              transaction-hash)))))))

(deftest engine-rpc-forkchoice-reinsert-notifies-pending-transaction-filters
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex (zero-hash32)))))
           (forkchoice-request (head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 8176)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list (forkchoice-state-object head)))))
           (filter-changes-request (filter-id id)
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
              ",\"method\":\"eth_getFilterChanges\",\"params\":[\""
              filter-id "\"]}")))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 2
               :gas-limit 21000
               :to recipient
               :value 3)
              1
              1))
           (transaction-hash (transaction-hash transaction))
           (transaction-hash-hex (hash32-to-hex transaction-hash))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (genesis
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :gas-limit 30000000
                                 :timestamp 0
                                 :extra-data #(0))))
           (old-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(1))
              :transactions (list transaction)
              :receipts (list (make-receipt :status 1
                                            :cumulative-gas-used 21000))))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(2)))))
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-block store old-canonical-child :state-available-p t)
      (chain-store-put-block store new-canonical-child :state-available-p t)
      (chain-store-put-account-nonce
       store (block-hash new-canonical-child) sender 0)
      (chain-store-put-account-balance
       store (block-hash new-canonical-child) sender 1000000)
      (let* ((pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":8177,\"method\":\"eth_newPendingTransactionFilter\"}"
                 store
                 config)))
             (pending-filter-id (field pending-filter-response "result"))
             (initial-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (filter-changes-request pending-filter-id 8178)
                 store
                 config)))
             (forkchoice-response
               (engine-rpc-handle-request
                (forkchoice-request (block-hash new-canonical-child))
                store
                config))
             (payload-status
               (field (field forkchoice-response "result") "payloadStatus"))
             (changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (filter-changes-request pending-filter-id 8179)
                 store
                 config)))
             (changes (field changes-response "result"))
             (empty-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (filter-changes-request pending-filter-id 8180)
                 store
                 config))))
        (is (= 0 (length (field initial-changes-response "result"))))
        (is (= 8176 (field forkchoice-response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (null (chain-store-transaction-location store transaction-hash)))
        (is (typep
             (ethereum-lisp.core::engine-payload-store-pending-transaction
              store
              transaction-hash)
             'legacy-transaction))
        (is (= 1 (length changes)))
        (is (string= transaction-hash-hex (first changes)))
        (is (= 0 (length (field empty-changes-response "result"))))))))

