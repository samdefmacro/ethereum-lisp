(in-package #:ethereum-lisp.test)

(deftest engine-rpc-forkchoice-updated-v1-reports-memory-status
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (payload-attributes-object ()
             (list (cons "timestamp" "0x1")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))))
           (invalid-payload-attributes-object ()
             (list (cons "timestamp" "0x0")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))))
           (forkchoice-request (id state &optional payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (known-block (make-block))
           (known-hash (block-hash known-block))
           (finalized-block
             (make-block
              :header (make-block-header :number 30
                                         :parent-hash (zero-hash32)
                                         :timestamp 30
                                         :gas-limit 30000000)))
           (safe-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash finalized-block)
                                         :number 31
                                         :timestamp 31
                                         :gas-limit 30000000)))
           (head-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash safe-block)
                                         :number 32
                                         :timestamp 32
                                         :gas-limit 30000000)))
           (non-head-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash finalized-block)
                                         :number 33
                                         :timestamp 33
                                         :gas-limit 30000000)))
           (unprocessed-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash head-block)
                                         :number 34
                                         :timestamp 34
                                         :gas-limit 30000000)))
           (unknown-hash
             (hash32-from-hex
              "0x1111111111111111111111111111111111111111111111111111111111111111")))
      (engine-payload-store-put-block
       store known-block :state-available-p t)
      (engine-payload-store-put-block
       store finalized-block :state-available-p t)
      (engine-payload-store-put-block
       store safe-block :state-available-p t)
      (engine-payload-store-put-block
       store head-block :state-available-p t)
      (engine-payload-store-put-block
       store non-head-block :state-available-p t)
      (engine-payload-store-put-block store unprocessed-block)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 17
                 (forkchoice-state-object known-hash)
                 (payload-attributes-object))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus")))
        (is (= 17 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (string= (hash32-to-hex known-hash)
                     (field payload-status "latestValidHash")))
        (is (stringp (field result "payloadId")))
        (is (= 18 (length (field result "payloadId"))))
        (let* ((get-payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 21)
                        (cons "method" "engine_getPayloadV1")
                        (cons "params" (list (field result "payloadId"))))
                  store
                  config))
               (payload (field get-payload-response "result")))
          (is (= 21 (field get-payload-response "id")))
          (is (string= (hash32-to-hex known-hash)
                       (field payload "parentHash")))
          (is (= 1 (hex-to-quantity (field payload "blockNumber"))))
          (is (string= "0x1" (field payload "timestamp")))
          (is (string= (hash32-to-hex (zero-hash32))
                       (field payload "prevRandao")))
          (is (string= (address-to-hex (zero-address))
                       (field payload "feeRecipient")))
          (is (not (field payload "transactions"))))
        (let* ((get-payload-v2-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 22)
                        (cons "method" "engine_getPayloadV2")
                        (cons "params" (list (field result "payloadId"))))
                  store
                  config))
               (envelope (field get-payload-v2-response "result"))
               (payload (field envelope "executionPayload")))
          (is (= 22 (field get-payload-v2-response "id")))
          (is (string= "0x0" (field envelope "blockValue")))
          (is (string= (hash32-to-hex known-hash)
                       (field payload "parentHash")))
          (is (= 1 (hex-to-quantity (field payload "blockNumber"))))
          (is (not (field payload "transactions"))))
        (let* ((checkpoint-response
                 (engine-rpc-handle-request
                  (forkchoice-request
                   28
                   (forkchoice-state-object
                    (block-hash head-block)
                    :safe (block-hash safe-block)
                    :finalized (block-hash finalized-block)))
                  store
                  config))
               (checkpoint-status
                 (field (field checkpoint-response "result") "payloadStatus"))
               (safe-header-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":29,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"safe\"]}"
                   store
                   config)))
               (finalized-header-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"finalized\"]}"
                   store
                   config)))
               (latest-header-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"latest\"]}"
                   store
                   config)))
               (pending-header-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"eth_getHeaderByNumber\",\"params\":[\"pending\"]}"
                   store
                   config)))
               (block-number-response
                 (parse-json
                  (engine-rpc-handle-request-json
                   "{\"jsonrpc\":\"2.0\",\"id\":33,\"method\":\"eth_blockNumber\",\"params\":[]}"
                   store
                   config))))
          (is (= 28 (field checkpoint-response "id")))
          (is (string= +payload-status-valid+
                       (field checkpoint-status "status")))
          (is (string= (quantity-to-hex 32)
                       (field (field latest-header-response "result")
                              "number")))
          (let ((pending-header (field pending-header-response "result")))
            (is (string= (quantity-to-hex 33)
                         (field pending-header "number")))
            (is (string= (hash32-to-hex (block-hash head-block))
                         (field pending-header "parentHash")))
            (is (null (field pending-header "hash")))
            (is (null (field pending-header "nonce"))))
          (is (string= (quantity-to-hex 32)
                       (field block-number-response "result")))
          (is (string= (hash32-to-hex (block-hash head-block))
                       (hash32-to-hex
                        (chain-store-canonical-hash store 32))))
          (is (not (chain-store-canonical-hash store 33)))
          (is (string= (quantity-to-hex 31)
                       (field (field safe-header-response "result")
                              "number")))
          (is (string= (quantity-to-hex 30)
                       (field (field finalized-header-response "result")
                              "number"))))
      (let* ((get-payload-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 25)
                      (cons "method" "engine_getPayloadV1")
                      (cons "params" (list "0x0200000000000000")))
                store
                config))
             (error (field get-payload-response "error")))
        (is (= 25 (field get-payload-response "id")))
        (is (= -38001 (field error "code")))
        (is (string= "Unknown payload" (field error "message"))))
      (let* ((get-payload-response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 27)
                      (cons "method" "engine_getPayloadV2")
                      (cons "params" (list "0x0200000000000000")))
                store
                config))
             (error (field get-payload-response "error")))
        (is (= 27 (field get-payload-response "id")))
        (is (= -38001 (field error "code")))
        (is (string= "Unknown payload" (field error "message"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 26
                 (forkchoice-state-object known-hash)
                 (invalid-payload-attributes-object))
                store
                config))
             (error (field response "error")))
        (is (= 26 (field response "id")))
        (is (= -38003 (field error "code")))
        (is (string= "Payload attributes timestamp must be greater than parent timestamp"
                     (field error "message"))))
      (engine-rpc-handle-request
       (forkchoice-request
        36
        (forkchoice-state-object
         (block-hash head-block)
         :safe (block-hash safe-block)
         :finalized (block-hash finalized-block)))
       store
       config)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 18
                 (forkchoice-state-object unknown-hash))
                store
                config))
             (payload-status
               (field (field response "result") "payloadStatus")))
        (is (string= +payload-status-syncing+
                     (field payload-status "status")))
        (is (not (field payload-status "latestValidHash"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 42
                 (forkchoice-state-object unknown-hash)
                 (invalid-payload-attributes-object))
                store
                config))
             (payload-status
               (field (field response "result") "payloadStatus")))
        (is (= 42 (field response "id")))
        (is (string= +payload-status-syncing+
                     (field payload-status "status")))
        (is (not (field payload-status "latestValidHash"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 37
                 (forkchoice-state-object (block-hash unprocessed-block)))
                store
                config))
             (payload-status
               (field (field response "result") "payloadStatus")))
        (is (string= +payload-status-syncing+
                     (field payload-status "status")))
        (is (not (field payload-status "latestValidHash")))
        (is (not (chain-store-canonical-hash
                  store
                  (block-header-number
                   (block-header unprocessed-block))))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 19
                 (forkchoice-state-object (zero-hash32)))
                store
                config))
             (payload-status
               (field (field response "result") "payloadStatus")))
        (is (string= +payload-status-invalid+
                     (field payload-status "status")))
        (is (string= "forkchoice head block hash is zero"
                     (field payload-status "validationError"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 22
                 (forkchoice-state-object known-hash :safe unknown-hash))
                store
                config))
             (error (field response "error")))
        (is (= -38002 (field error "code")))
        (is (string= "forkchoice safe block is not available"
                     (field error "message"))))
      (let* ((unavailable-safe-block
               (make-block
                :header
                (make-block-header
                 :parent-hash (block-hash finalized-block)
                 :number 34
                 :timestamp 34
                 :gas-limit 30000000)))
             (head-over-unavailable-safe-block
               (make-block
                :header
                (make-block-header
                 :parent-hash (block-hash unavailable-safe-block)
                 :number 35
                 :timestamp 35
                 :gas-limit 30000000))))
        (engine-payload-store-put-block store unavailable-safe-block)
        (engine-payload-store-put-block
         store head-over-unavailable-safe-block :state-available-p t)
        (let* ((response
                 (engine-rpc-handle-request
                  (forkchoice-request
                   38
                   (forkchoice-state-object
                    (block-hash head-over-unavailable-safe-block)
                    :safe (block-hash unavailable-safe-block)))
                  store
                  config))
               (error (field response "error")))
          (is (= -38002 (field error "code")))
          (is (string= "forkchoice safe block state is not available"
                       (field error "message")))
          (is (bytes= (block-rlp safe-block)
                      (block-rlp (chain-store-safe-block store))))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 34
                 (forkchoice-state-object
                  (block-hash head-block)
                  :safe (block-hash non-head-block)))
                store
                config))
             (error (field response "error")))
        (is (= -38002 (field error "code")))
        (is (string= "forkchoice safe block is not an ancestor of head"
                     (field error "message")))
        (is (bytes= (block-rlp safe-block)
                    (block-rlp (chain-store-safe-block store)))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 23
                 (forkchoice-state-object
                  known-hash :finalized unknown-hash))
                store
                config))
             (error (field response "error")))
        (is (= -38002 (field error "code")))
        (is (string= "forkchoice finalized block is not available"
                     (field error "message"))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 35
                 (forkchoice-state-object
                  (block-hash head-block)
                  :finalized (block-hash non-head-block)))
                store
                config))
             (error (field response "error")))
        (is (= -38002 (field error "code")))
        (is (string= "forkchoice finalized block is not an ancestor of head"
                     (field error "message")))
        (is (bytes= (block-rlp finalized-block)
                    (block-rlp (chain-store-finalized-block store)))))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 43
                 (forkchoice-state-object
                  (block-hash head-block)
                  :safe (block-hash safe-block)
                  :finalized (block-hash head-block)))
                store
                config))
             (error (field response "error")))
        (is (= -38002 (field error "code")))
        (is (string= "forkchoice safe block is older than finalized block"
                     (field error "message")))
        (is (bytes= (block-rlp safe-block)
                    (block-rlp (chain-store-safe-block store))))
        (is (bytes= (block-rlp finalized-block)
                    (block-rlp (chain-store-finalized-block store)))))
      (let* ((bad-state
               (list (cons "headBlockHash" (hash32-to-hex known-hash))))
             (response
               (engine-rpc-handle-request
                (forkchoice-request 24 bad-state)
                store
                config))
             (error (field response "error")))
        (is (= -32602 (field error "code"))))))))

(deftest engine-rpc-forkchoice-updated-v1-selects-pending-txpool-transactions
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request-json (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (send-raw (id raw-transaction store config)
             (request-json
              (format nil
                      "{\"jsonrpc\":\"2.0\",\"id\":~D,\"method\":\"eth_sendRawTransaction\",\"params\":[\"~A\"]}"
                      id
                      raw-transaction)
              store
              config))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash" (hash32-to-hex (zero-hash32)))))
           (payload-attributes-object ()
             (list (cons "timestamp" "0xb")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))))
           (forkchoice-request (id head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list (forkchoice-state-object head)
                               (payload-attributes-object))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key-a 1)
           (private-key-b 2)
           (sender-a (fixture-private-key-address private-key-a))
           (sender-b (fixture-private-key-address private-key-b))
           (transaction-a
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 1000
                                       :gas-limit 21000
                                       :to recipient
                                       :value 1)
              private-key-a
              1))
           (transaction-b
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 1000
                                       :gas-limit 30000
                                       :to recipient
                                       :value 1)
              private-key-b
              1))
           (raw-a (bytes-to-hex (transaction-encoding transaction-a)))
           (raw-b (bytes-to-hex (transaction-encoding transaction-b)))
           (hash-a (hash32-to-hex (transaction-hash transaction-a)))
           (hash-b (hash32-to-hex (transaction-hash transaction-b)))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender-a
                            (make-state-account
                             :nonce 0
                             :balance 1000000000))
      (state-db-set-account parent-state sender-b
                            (make-state-account
                             :nonce 0
                             :balance 1000000000))
      (let* ((parent-block
               (make-block
                :header (make-block-header
                         :number 0
                         :timestamp 10
                         :gas-limit 42000
                         :gas-used 0
                         :base-fee-per-gas 100
                         :state-root (state-db-root parent-state))))
             (parent-hash (block-hash parent-block)))
        (chain-store-put-block store parent-block :state-available-p t)
        (commit-state-db-to-chain-store store parent-hash parent-state)
        (chain-store-set-canonical-head
         store parent-hash
         :expected-chain-id (chain-config-chain-id config)
         :chain-config config)
        (is (string= hash-a
                     (field (send-raw 101 raw-a store config) "result")))
        (is (string= hash-b
                     (field (send-raw 102 raw-b store config) "result")))
        (let* ((prepare-response
                 (engine-rpc-handle-request
                  (forkchoice-request 103 parent-hash)
                  store
                  config))
               (payload-id
                 (field (field prepare-response "result") "payloadId"))
               (payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 104)
                        (cons "method" "engine_getPayloadV1")
                        (cons "params" (list payload-id)))
                  store
                  config))
               (payload (field payload-response "result"))
               (payload-transactions (field payload "transactions"))
               (pending-response
                 (request-json
                  "{\"jsonrpc\":\"2.0\",\"id\":105,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                  store
                  config))
               (pending-transactions (field pending-response "result"))
               (pending-hashes
                 (mapcar (lambda (transaction)
                           (field transaction "hash"))
                         pending-transactions))
               (selected-raw (first payload-transactions))
               (selected-hash
                 (cond
                   ((string= selected-raw raw-a) hash-a)
                   ((string= selected-raw raw-b) hash-b)))
               (non-selected-hash
                 (cond
                   ((string= selected-raw raw-a) hash-b)
                   ((string= selected-raw raw-b) hash-a))))
          (is (= 103 (field prepare-response "id")))
          (is (stringp payload-id))
          (is (= 1 (length payload-transactions)))
          (is (member selected-raw (list raw-a raw-b) :test #'string=))
          (is (= 2 (length pending-transactions)))
          (is (member selected-hash pending-hashes :test #'string=))
          (is (member non-selected-hash pending-hashes :test #'string=)))))))

(deftest engine-rpc-forkchoice-updated-v1-payload-id-tracks-txpool-selection
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request-json (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (send-raw (id raw-transaction store config)
             (request-json
              (format nil
                      "{\"jsonrpc\":\"2.0\",\"id\":~D,\"method\":\"eth_sendRawTransaction\",\"params\":[\"~A\"]}"
                      id
                      raw-transaction)
              store
              config))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash" (hash32-to-hex (zero-hash32)))))
           (payload-attributes-object ()
             (list (cons "timestamp" "0xb")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))))
           (forkchoice-request (id head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list (forkchoice-state-object head)
                               (payload-attributes-object)))))
           (get-payload-transactions (id payload-id store config)
             (field
              (field
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" id)
                      (cons "method" "engine_getPayloadV1")
                      (cons "params" (list payload-id)))
                store
                config)
               "result")
              "transactions")))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0))
           (recipient
             (address-from-hex "0x4545454545454545454545454545454545454545"))
           (private-key 1)
           (sender (fixture-private-key-address private-key))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 1000
                                       :gas-limit 21000
                                       :to recipient
                                       :value 1)
              private-key
              1))
           (raw-transaction (bytes-to-hex (transaction-encoding transaction)))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 0
                             :balance 1000000000))
      (let* ((parent-block
               (make-block
                :header (make-block-header
                         :number 0
                         :timestamp 10
                         :gas-limit 42000
                         :gas-used 0
                         :base-fee-per-gas 100
                         :state-root (state-db-root parent-state))))
             (parent-hash (block-hash parent-block)))
        (chain-store-put-block store parent-block :state-available-p t)
        (commit-state-db-to-chain-store store parent-hash parent-state)
        (chain-store-set-canonical-head
         store parent-hash
         :expected-chain-id (chain-config-chain-id config)
         :chain-config config)
        (let* ((empty-prepare-response
                 (engine-rpc-handle-request
                  (forkchoice-request 201 parent-hash)
                  store
                  config))
               (empty-payload-id
                 (field (field empty-prepare-response "result") "payloadId")))
          (is (stringp empty-payload-id))
          (is (not (get-payload-transactions
                    202 empty-payload-id store config)))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field (send-raw
                               203 raw-transaction store config)
                              "result")))
          (let* ((txpool-prepare-response
                   (engine-rpc-handle-request
                    (forkchoice-request 204 parent-hash)
                    store
                    config))
                 (txpool-payload-id
                   (field (field txpool-prepare-response "result")
                          "payloadId"))
                 (txpool-payload-transactions
                   (get-payload-transactions
                    205 txpool-payload-id store config)))
            (is (stringp txpool-payload-id))
            (is (not (string= empty-payload-id txpool-payload-id)))
            (is (= 1 (length txpool-payload-transactions)))
            (is (string= raw-transaction
                         (first txpool-payload-transactions)))
            (is (not (get-payload-transactions
                      206 empty-payload-id store config)))))))))

(deftest engine-rpc-forkchoice-updated-v1-refreshes-txpool-replacement-payload-id
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request-json (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config)))
           (send-raw (id transaction store config)
             (request-json
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":"
               (write-to-string id)
               ",\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\""
               (bytes-to-hex (transaction-encoding transaction))
               "\"]}")
              store
              config))
           (txpool-content-from (id sender store config)
             (request-json
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":"
               (write-to-string id)
               ",\"method\":\"txpool_contentFrom\","
               "\"params\":[\""
               (address-to-hex sender)
               "\"]}")
              store
              config))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash" (hash32-to-hex (zero-hash32)))))
           (payload-attributes-object ()
             (list (cons "timestamp" "0xb")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))))
           (forkchoice-request (id head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list (forkchoice-state-object head)
                               (payload-attributes-object)))))
           (payload-id-from-response (response)
             (field (field response "result") "payloadId"))
           (get-payload-transactions (id payload-id store config)
             (field
              (field
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" id)
                      (cons "method" "engine_getPayloadV1")
                      (cons "params" (list payload-id)))
                store
                config)
               "result")
              "transactions")))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0))
           (recipient
             (address-from-hex "0x4646464646464646464646464646464646464646"))
           (private-key 1)
           (sender (fixture-private-key-address private-key))
           (base-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 1000
                                       :gas-limit 21000
                                       :to recipient
                                       :value 1)
              private-key
              1))
           (replacement-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 1250
                                       :gas-limit 21000
                                       :to recipient
                                       :value 1)
              private-key
              1))
           (base-raw (bytes-to-hex (transaction-encoding base-transaction)))
           (replacement-raw
             (bytes-to-hex (transaction-encoding replacement-transaction)))
           (base-hash (hash32-to-hex (transaction-hash base-transaction)))
           (replacement-hash
             (hash32-to-hex (transaction-hash replacement-transaction)))
           (parent-state (make-state-db)))
      (state-db-set-account parent-state sender
                            (make-state-account
                             :nonce 0
                             :balance 1000000000))
      (let* ((parent-block
               (make-block
                :header (make-block-header
                         :number 0
                         :timestamp 10
                         :gas-limit 30000000
                         :gas-used 0
                         :base-fee-per-gas 100
                         :state-root (state-db-root parent-state))))
             (parent-hash (block-hash parent-block)))
        (chain-store-put-block store parent-block :state-available-p t)
        (commit-state-db-to-chain-store store parent-hash parent-state)
        (chain-store-set-canonical-head
         store parent-hash
         :expected-chain-id (chain-config-chain-id config)
         :chain-config config)
        (is (string= base-hash
                     (field (send-raw
                             207 base-transaction store config)
                            "result")))
        (let* ((base-prepare-response
                 (engine-rpc-handle-request
                  (forkchoice-request 208 parent-hash)
                  store
                  config))
               (base-payload-id
                 (payload-id-from-response base-prepare-response))
               (base-payload-transactions
                 (get-payload-transactions
                  209 base-payload-id store config)))
          (is (stringp base-payload-id))
          (is (= 1 (length base-payload-transactions)))
          (is (string= base-raw (first base-payload-transactions)))
          (is (string= replacement-hash
                       (field (send-raw
                               210 replacement-transaction store config)
                              "result")))
          (let* ((content-response
                   (txpool-content-from 211 sender store config))
                 (content-result (field content-response "result"))
                 (pending
                   (field (field content-result "pending") "0"))
                 (replacement-prepare-response
                   (engine-rpc-handle-request
                    (forkchoice-request 212 parent-hash)
                    store
                    config))
                 (replacement-payload-id
                   (payload-id-from-response replacement-prepare-response))
                 (replacement-payload-transactions
                   (get-payload-transactions
                    213 replacement-payload-id store config)))
            (is (string= replacement-hash (field pending "hash")))
            (is (not (string= base-hash (field pending "hash"))))
            (is (stringp replacement-payload-id))
            (is (not (string= base-payload-id replacement-payload-id)))
            (is (= 1 (length replacement-payload-transactions)))
            (is (string= replacement-raw
                         (first replacement-payload-transactions)))
            (is (not (member base-raw
                             replacement-payload-transactions
                             :test #'string=)))))))))

(deftest engine-rpc-forkchoice-updated-known-block-precedes-invalid-cache
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (forkchoice-request (id state)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params" (list state)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (genesis
             (make-block
              :header (make-block-header :number 0
                                         :parent-hash (zero-hash32)
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (head
             (make-block
              :header (make-block-header :parent-hash (block-hash genesis)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000))))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (engine-payload-store-put-block store head :state-available-p t)
      (engine-payload-store-mark-invalid store head)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 41
                 (forkchoice-state-object (block-hash head)))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus")))
        (is (= 41 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (string= (hash32-to-hex (block-hash head))
                     (field payload-status "latestValidHash")))
        (is (not (field result "payloadId")))
        (is (string= (hash32-to-hex (block-hash head))
                     (hash32-to-hex
                      (chain-store-canonical-hash store 1))))))))

(deftest engine-rpc-forkchoice-update-rolls-back-checkpoints-on-head-rewrite-error
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (forkchoice-request (id state)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params" (list state)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (genesis
             (make-block
              :header (make-block-header :number 0
                                         :parent-hash (zero-hash32)
                                         :timestamp 0
                                         :gas-limit 30000000)))
           (old-head
             (make-block
              :header (make-block-header :parent-hash (block-hash genesis)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000)))
           (missing-parent-hash
             (hash32-from-hex
              "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
           (orphan-head
             (make-block
              :header (make-block-header :parent-hash missing-parent-hash
                                         :number 2
                                         :timestamp 24
                                         :gas-limit 30000000))))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (engine-payload-store-put-block store old-head :state-available-p t)
      (engine-payload-store-put-block store orphan-head :state-available-p t)
      (engine-rpc-handle-request
       (forkchoice-request
        39
        (forkchoice-state-object
         (block-hash old-head)
         :safe (block-hash genesis)
         :finalized (block-hash genesis)))
       store
       config)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 40
                 (forkchoice-state-object
                  (block-hash orphan-head)))
                store
                config))
             (error (field response "error")))
        (is (= 40 (field response "id")))
        (is (= -32602 (field error "code")))
        (is (string= "Canonical head ancestry must be fully known"
                     (field error "message")))
        (is (bytes= (block-rlp old-head)
                    (block-rlp (chain-store-head-block store))))
        (is (bytes= (block-rlp genesis)
                    (block-rlp (chain-store-safe-block store))))
        (is (bytes= (block-rlp genesis)
                    (block-rlp (chain-store-finalized-block store))))
        (is (string= (hash32-to-hex (block-hash old-head))
                     (hash32-to-hex
                      (chain-store-canonical-hash store 1))))
        (is (not (chain-store-canonical-hash store 2)))))))

(deftest engine-rpc-forkchoice-updated-v2-prepares-withdrawal-payload
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (withdrawal-object ()
             (list (cons "index" "0x1")
                   (cons "validatorIndex" "0x2")
                   (cons "address" (address-to-hex (zero-address)))
                   (cons "amount" "0x3")))
           (payload-attributes-object ()
             (list (cons "timestamp" "0x1")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" (list (withdrawal-object)))))
           (forkchoice-request (id state payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV2")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (known-block (make-block))
           (known-hash (block-hash known-block)))
      (engine-payload-store-put-block
       store known-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 28
                 (forkchoice-state-object known-hash)
                 (payload-attributes-object))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus"))
             (payload-id (field result "payloadId")))
        (is (= 28 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (stringp payload-id))
        (is (string= "02" (subseq payload-id 2 4)))
        (let* ((get-payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 29)
                        (cons "method" "engine_getPayloadV2")
                        (cons "params" (list payload-id)))
                  store
                  config))
               (envelope (field get-payload-response "result"))
               (payload (field envelope "executionPayload"))
               (withdrawals (field payload "withdrawals"))
               (withdrawal (first withdrawals)))
          (is (= 29 (field get-payload-response "id")))
          (is (string= "0x0" (field envelope "blockValue")))
          (is (string= (hash32-to-hex known-hash)
                       (field payload "parentHash")))
          (is (= 1 (hex-to-quantity (field payload "blockNumber"))))
          (is (= 1 (length withdrawals)))
          (is (string= "0x1" (field withdrawal "index")))
          (is (string= "0x2" (field withdrawal "validatorIndex")))
          (is (string= (address-to-hex (zero-address))
                       (field withdrawal "address")))
          (is (string= "0x3" (field withdrawal "amount"))))))))

(deftest engine-rpc-forkchoice-updated-v3-prepares-cancun-payload
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (withdrawal-object ()
             (list (cons "index" "0x4")
                   (cons "validatorIndex" "0x5")
                   (cons "address" (address-to-hex (zero-address)))
                   (cons "amount" "0x6")))
           (payload-attributes-object (parent-beacon-root)
             (list (cons "timestamp" "0x1")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" (list (withdrawal-object)))
                   (cons "parentBeaconBlockRoot"
                         (hash32-to-hex parent-beacon-root))))
           (forkchoice-request (id state payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV3")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (known-block (make-block))
           (known-hash (block-hash known-block))
           (parent-beacon-root
             (hash32-from-hex
              "0x3333333333333333333333333333333333333333333333333333333333333333")))
      (engine-payload-store-put-block
       store known-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 30
                 (forkchoice-state-object known-hash)
                 (payload-attributes-object parent-beacon-root))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus"))
             (payload-id (field result "payloadId"))
             (prepared-payload
               (engine-payload-store-prepared-payload
                store (hex-to-bytes payload-id)))
             (prepared-header
               (block-header
                (engine-prepared-payload-block prepared-payload))))
        (is (= 30 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (stringp payload-id))
        (is (string= "03" (subseq payload-id 2 4)))
        (is (string= (hash32-to-hex parent-beacon-root)
                     (hash32-to-hex
                      (block-header-parent-beacon-root prepared-header))))
        (let* ((get-payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 31)
                        (cons "method" "engine_getPayloadV3")
                        (cons "params" (list payload-id)))
                  store
                  config))
               (envelope (field get-payload-response "result"))
               (payload (field envelope "executionPayload"))
               (bundle (field envelope "blobsBundle"))
               (withdrawals (field payload "withdrawals")))
          (is (= 31 (field get-payload-response "id")))
          (is (eq :false (field envelope "shouldOverrideBuilder")))
          (is (string= "0x0" (field payload "blobGasUsed")))
          (is (string= "0x0" (field payload "excessBlobGas")))
          (is (= 1 (length withdrawals)))
          (is (listp (field bundle "commitments")))
          (is (listp (field bundle "proofs")))
          (is (listp (field bundle "blobs"))))))))

(deftest engine-rpc-forkchoice-updated-v4-prepares-amsterdam-payload
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object
               (head &key
                     (safe (zero-hash32))
                     (finalized (zero-hash32)))
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex safe))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex finalized))))
           (withdrawal-object ()
             (list (cons "index" "0x7")
                   (cons "validatorIndex" "0x8")
                   (cons "address" (address-to-hex (zero-address)))
                   (cons "amount" "0x9")))
           (payload-attributes-object (parent-beacon-root)
             (list (cons "timestamp" "0x1")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" (list (withdrawal-object)))
                   (cons "parentBeaconBlockRoot"
                         (hash32-to-hex parent-beacon-root))
                   (cons "slotNumber" "0x2a")))
           (forkchoice-request (id state payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV4")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (known-block (make-block))
           (known-hash (block-hash known-block))
           (parent-beacon-root
             (hash32-from-hex
              "0x4444444444444444444444444444444444444444444444444444444444444444")))
      (engine-payload-store-put-block
       store known-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request
                 32
                 (forkchoice-state-object known-hash)
                 (payload-attributes-object parent-beacon-root))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus"))
             (payload-id (field result "payloadId"))
             (prepared-payload
               (engine-payload-store-prepared-payload
                store (hex-to-bytes payload-id)))
             (prepared-header
               (block-header
                (engine-prepared-payload-block prepared-payload))))
        (is (= 32 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (string= "04" (subseq payload-id 2 4)))
        (is (= 42 (block-header-slot-number prepared-header)))
        (let* ((get-payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 33)
                        (cons "method" "engine_getPayloadV4")
                        (cons "params" (list payload-id)))
                  store
                  config))
               (envelope (field get-payload-response "result"))
               (payload (field envelope "executionPayload"))
               (bundle (field envelope "blobsBundle"))
               (withdrawals (field payload "withdrawals")))
          (is (= 33 (field get-payload-response "id")))
          (is (eq :false (field envelope "shouldOverrideBuilder")))
          (is (string= (quantity-to-hex 42) (field payload "slotNumber")))
          (is (string= "0x0" (field payload "blobGasUsed")))
          (is (string= "0x0" (field payload "excessBlobGas")))
          (is (= 1 (length withdrawals)))
          (is (listp (field bundle "commitments")))
          (is (listp (field bundle "proofs")))
          (is (listp (field bundle "blobs"))))))))

