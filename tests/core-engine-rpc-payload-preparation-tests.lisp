(in-package #:ethereum-lisp.test)

(deftest engine-rpc-forkchoice-v1-accepts-null-unavailable-fields
  ;; Hive's generic payload-attributes encoder keeps later-version fields in
  ;; the V1 object as JSON null.  Null is an omitted field here, whereas a
  ;; non-null value remains forbidden by the V1 codec.
  (let ((attributes
          (ethereum-lisp.engine-api::engine-rpc-validate-payload-attributes-v1
           (list (cons "timestamp" "0x1")
                 (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                 (cons "suggestedFeeRecipient"
                       (address-to-hex (zero-address)))
                 (cons "withdrawals" ethereum-lisp.json:+json-null+)
                 (cons "parentBeaconBlockRoot"
                       ethereum-lisp.json:+json-null+)))))
    (is (not (ethereum-lisp.engine::payload-attributes-v1-withdrawals-present-p
              attributes)))
    (is (null (ethereum-lisp.engine::payload-attributes-v1-withdrawals
               attributes)))
    (is (not (ethereum-lisp.engine::payload-attributes-v1-parent-beacon-root-present-p
              attributes)))))

(deftest engine-rpc-new-payload-v1-accepts-null-unavailable-withdrawals
  ;; Hive also includes this version-neutral null in executable payload data.
  ;; The decoder must preserve the distinction between an omitted V1 field and
  ;; a real withdrawals array without attempting to parse null as an array.
  (is (null (ethereum-lisp.engine-api::engine-rpc-withdrawals-field
             (list (cons "withdrawals" ethereum-lisp.json:+json-null+))))))

(deftest engine-prepared-payload-amsterdam-derives-bal-instead-of-supplying-empty
  (let* ((config
           (make-chain-config :chain-id 1 :london-block 0
                              :prague-time 0 :amsterdam-time 0))
         (attributes
           (make-payload-attributes-v1
            :timestamp 1
            :prev-randao (zero-hash32)
            :suggested-fee-recipient (zero-address)))
         (arguments
           (ethereum-lisp.engine-api::engine-rpc-prepared-payload-body-arguments
            attributes config 1 1)))
    (is (member :requests arguments))
    (is (not (member :block-access-list arguments)))))

(deftest forkchoice-sync-target-survives-header-until-state-is-available
  (let* ((store (make-engine-payload-memory-store))
         (block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :number 1
             :timestamp 1
             :gas-limit 30000000)))
         (hash (block-hash block)))
    (engine-payload-store-put-forkchoice-sync-target
     store hash :block-number 1)
    ;; Skeleton/newPayload admission makes the block known, but cannot retire
    ;; the CL target before its execution state exists.
    (engine-payload-store-put-block
     store block :state-available-p nil :canonicalize-p nil)
    (let ((targets (engine-payload-store-forkchoice-sync-targets store)))
      (is (= 1 (length targets)))
      (is (hash32= hash (first targets))))
    ;; The stateful execution commit is the lifecycle boundary that retires
    ;; the target from the downloader.
    (engine-payload-store-put-block
     store block :state-available-p t :canonicalize-p nil)
    (is (null (engine-payload-store-forkchoice-sync-targets store)))))

(deftest engine-rpc-invalid-payload-attributes-still-apply-forkchoice
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex (zero-hash32)))))
           (payload-attributes-without-beacon-root ()
             (list (cons "timestamp" "0x3")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" #()))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :london-block 0
                                      :shanghai-time 0
                                      :cancun-time 0))
           (parent
             (make-block
              :header
              (make-block-header
               :number 1
               :timestamp 1
               :state-root +empty-trie-hash+
               :gas-limit 30000000
               :base-fee-per-gas 1
               :withdrawals-root (withdrawal-list-root '())
               :blob-gas-used 0
               :excess-blob-gas 0
               :parent-beacon-root (zero-hash32))
              :withdrawals '()))
           (child
             (make-block
              :header
              (make-block-header
               :parent-hash (block-hash parent)
               :number 2
               :timestamp 2
               :state-root +empty-trie-hash+
               :gas-limit 30000000
               :base-fee-per-gas 1
               :withdrawals-root (withdrawal-list-root '())
               :blob-gas-used 0
               :excess-blob-gas 0
               :parent-beacon-root (zero-hash32))
              :withdrawals '())))
      (engine-payload-store-put-block store parent :state-available-p t)
      (engine-payload-store-put-block
       store child :state-available-p t :canonicalize-p nil)
      (is (null (chain-store-canonical-hash store 2)))
      (let* ((response
               (engine-rpc-handle-request
                (list
                 (cons "jsonrpc" "2.0")
                 (cons "id" 600)
                 (cons "method" "engine_forkchoiceUpdatedV3")
                 (cons "params"
                       (list
                        (forkchoice-state-object (block-hash child))
                        (payload-attributes-without-beacon-root))))
                store config))
             (error (field response "error")))
        (is (= -38003 (field error "code")))
        (is (hash32= (block-hash child)
                     (chain-store-canonical-hash store 2)))))))

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
           (known-block
             (make-block
              :header
              (make-block-header
               :state-root +empty-trie-hash+
               :gas-limit 30000000)))
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
          (is (ethereum-lisp.json:json-empty-array-p
               (field payload "transactions"))))
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
          (is (ethereum-lisp.json:json-empty-array-p
               (field payload "transactions"))))
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
        (is (not (field payload-status "latestValidHash")))
        (let ((targets
                (engine-payload-store-forkchoice-sync-targets store)))
          (is (= 1 (length targets)))
          (is (bytes= (hash32-bytes unknown-hash)
                      (hash32-bytes (first targets))))))
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
        (is (not (field payload-status "latestValidHash")))
        (is (= 1
               (length
                (engine-payload-store-forkchoice-sync-targets store)))))
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
                   (block-header unprocessed-block)))))
        ;; A restarted snap bootstrap can already know the target header from
        ;; its durable skeleton while the pivot state is still absent.  The CL
        ;; target must replace the older unknown target and remain schedulable.
        (let ((targets
                (engine-payload-store-forkchoice-sync-targets store)))
          (is (= 1 (length targets)))
          (is (hash32= (block-hash unprocessed-block) (first targets)))))
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
                                       :gas-price 2000
                                       :gas-limit 30000
                                       :to recipient
                                       :value 1)
              private-key-a
              1))
           (transaction-b
             (fixture-sign-legacy-transaction
              (make-legacy-transaction :nonce 0
                                       :gas-price 1000
                                       :gas-limit 21000
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
               (prepared-payload
                 (engine-payload-store-prepared-payload
                  store (hex-to-bytes payload-id)))
               (prepared-header
                 (block-header
                  (engine-prepared-payload-block prepared-payload)))
               (prepared-hash
                 (block-hash
                  (engine-prepared-payload-block prepared-payload)))
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
               (selected-hashes
                 (mapcar
                  (lambda (raw)
                    (if (string= raw raw-a) hash-a hash-b))
                  payload-transactions)))
          (is (= 103 (field prepare-response "id")))
          (is (stringp payload-id))
          ;; The first transaction declares 30000 gas but uses only 21000.
          ;; Filling from actual cumulative gas leaves enough room for the
          ;; second 21000-gas transfer.
          (is (= 2 (length payload-transactions)))
          (is (= 42000 (block-header-gas-used prepared-header)))
          (is (= 42000 (hex-to-quantity (field payload "gasUsed"))))
          ;; getPayload exposes the private build result, but only newPayload
          ;; may admit it as a known/stateful candidate.
          (is (null (chain-store-known-block store prepared-hash)))
          (is (not (chain-store-state-available-p store prepared-hash)))
          (is (null (chain-store-canonical-hash store 1)))
          (is (member raw-a payload-transactions :test #'string=))
          (is (member raw-b payload-transactions :test #'string=))
          (is (= 2 (length pending-transactions)))
          (is (every (lambda (hash)
                       (member hash pending-hashes :test #'string=))
                     selected-hashes))
          (is (engine-prepared-payload-execution-state prepared-payload))
          (let ((failed-fallback-calls 0)
                (failed-persistence-calls 0))
            (let ((failed-response
                    (engine-rpc-handle-request
                     (list (cons "jsonrpc" "2.0")
                           (cons "id" 1051)
                           (cons "method" "engine_newPayloadV1")
                           (cons "params" (list payload)))
                     store
                     config
                     :import-function
                     (lambda (current-store candidate current-config)
                       (declare
                        (ignore current-store candidate current-config))
                       (incf failed-fallback-calls)
                       (error "Matching prepared payload was re-executed"))
                     :new-payload-persistence-function
                     (lambda (&rest arguments)
                       (declare (ignore arguments))
                       (incf failed-persistence-calls)
                       (storage-fail "Injected prepared payload write failure")))))
              (is (field failed-response "error")))
            (is (= 0 failed-fallback-calls))
            (is (= 1 failed-persistence-calls))
            (is (null (chain-store-known-block store prepared-hash)))
            (is (not (chain-store-state-available-p store prepared-hash)))
            ;; The import transaction restores the borrowed state after a
            ;; failed durable callback, leaving it intact for retry.
            (is (engine-prepared-payload-execution-state
                 (chain-store-prepared-payload
                  store (hex-to-bytes payload-id)))))
          (let* ((fallback-calls 0)
                 (new-payload-response
                   (engine-rpc-handle-request
                    (list (cons "jsonrpc" "2.0")
                          (cons "id" 106)
                          (cons "method" "engine_newPayloadV1")
                          (cons "params" (list payload)))
                    store
                    config
                    :import-function
                    (lambda (current-store candidate current-config)
                      (declare
                       (ignore current-store candidate current-config))
                      (incf fallback-calls)
                      (error "Matching prepared payload was re-executed"))))
                 (new-payload-status
                   (field new-payload-response "result")))
            (is (= 0 fallback-calls))
            (is (string= +payload-status-valid+
                         (field new-payload-status "status")))
            (is (string= (hash32-to-hex prepared-hash)
                         (field new-payload-status "latestValidHash")))
            (is (chain-store-known-block store prepared-hash))
            (is (chain-store-state-available-p store prepared-hash))
            ;; A complete durable import consumes the private shortcut instead
            ;; of retaining a second world-state beside the canonical store.
            (multiple-value-bind (retained-block retained-state)
                (ethereum-lisp.chain-store::engine-payload-store-borrow-prepared-execution-for-block
                 store (engine-prepared-payload-block prepared-payload))
              (is (null retained-block))
              (is (null retained-state)))))))))

(deftest engine-rpc-forkchoice-updated-v1-improves-stable-payload-before-get
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
            (is (string= empty-payload-id txpool-payload-id))
            (is (= 1 (length txpool-payload-transactions)))
            (is (string= raw-transaction
                         (first txpool-payload-transactions)))
            (is (= 1
                   (length
                    (get-payload-transactions
                     206 empty-payload-id store config))))))))))

(deftest engine-rpc-forkchoice-updated-v1-improves-to-txpool-replacement
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
                 (payload-id-from-response base-prepare-response)))
          (is (stringp base-payload-id))
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
            (is (string= base-payload-id replacement-payload-id))
            (is (= 1 (length replacement-payload-transactions)))
            (is (string= replacement-raw
                         (first replacement-payload-transactions)))
            (is (not (member base-raw
                             replacement-payload-transactions
                             :test #'string=)))))))))

(deftest prepared-payload-builds-blob-transaction-and-bundle
  (let* ((store (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1
                                    :byzantium-block 0
                                    :constantinople-block 0
                                    :petersburg-block 0
                                    :berlin-block 0
                                    :london-block 0
                                    :shanghai-time 0
                                    :cancun-time 0))
         (commitment (make-byte-vector 48 :initial-element #x33))
         (versioned-hash (kzg-commitment-to-versioned-hash commitment))
         (transaction
           (fixture-sign-blob-transaction
            (make-blob-transaction
             :chain-id 1
             :nonce 0
             :max-priority-fee-per-gas 2
             :max-fee-per-gas 20
             :gas-limit 21000
             :to (zero-address)
             :max-fee-per-blob-gas 20
             :blob-versioned-hashes (list versioned-hash))
            1))
         (sidecar
           (make-blob-sidecar
            :blobs (list (make-byte-vector +blob-byte-size+))
            :commitments (list commitment)
            :proofs (list (make-byte-vector 48 :initial-element #x44))))
         (sender (transaction-sender transaction :expected-chain-id 1))
         (state (make-state-db)))
    (state-db-set-account
     state sender (make-state-account :nonce 0 :balance 1000000000))
    (let* ((parent
             (make-block
              :header
              (make-block-header
               :number 0
               :timestamp 10
               :gas-limit 30000000
               :base-fee-per-gas 1
               :blob-gas-used 0
               :excess-blob-gas 0
               :state-root (state-db-root state))))
           (parent-hash (block-hash parent))
           (attributes
             (make-payload-attributes-v1
              :timestamp 11
              :prev-randao (zero-hash32)
              :suggested-fee-recipient (zero-address)
              :withdrawals '()
              :withdrawals-present-p t
              :parent-beacon-root (zero-hash32)
              :parent-beacon-root-present-p t)))
      (chain-store-put-block store parent :state-available-p t)
      (commit-state-db-to-chain-store store parent-hash state)
      (let ((*kzg-blob-proof-verifier*
              (lambda (blob verified-commitment proof)
                (declare (ignore blob proof))
                (bytes= commitment verified-commitment))))
        (engine-payload-store-put-blob-sidecar store sidecar))
      (multiple-value-bind (block selected)
          (ethereum-lisp.engine-api::engine-rpc-build-viable-prepared-payload
           store parent attributes config (list transaction))
        (let ((bundle
                (ethereum-lisp.engine-api::engine-rpc-blobs-bundle-for-transactions
                 store selected)))
          (is (= 1 (length (block-transactions block))))
          (is (= +blob-gas-per-blob+
                 (block-header-blob-gas-used (block-header block))))
          (is (= 1 (length (blob-sidecar-blobs bundle))))
          (is (equalp commitment
                      (first (blob-sidecar-commitments bundle)))))))))

(deftest engine-rpc-builds-submitted-blob-wrapper-into-v3-payload
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (method id params store config)
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" id)
                    (cons "method" method)
                    (cons "params" params))
              store config))
           (forkchoice-state (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex (zero-hash32)))))
           (payload-attributes (timestamp)
             (list (cons "timestamp" (quantity-to-hex timestamp))
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))
                   (cons "withdrawals" #())
                   (cons "parentBeaconBlockRoot"
                         (hash32-to-hex (zero-hash32))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
                                      :london-block 0
                                      :shanghai-time 0
                                      :cancun-time 0))
           (commitment (make-byte-vector 48 :initial-element #x55))
           (versioned-hash (kzg-commitment-to-versioned-hash commitment))
           (datahash-contract
             (address-from-hex
              "0x0000000000000000000000000000000000020000"))
           (transaction
             (fixture-sign-blob-transaction
              (make-blob-transaction
               :chain-id 1337
               :nonce 0
               :max-priority-fee-per-gas 2
               :max-fee-per-gas 20
               :gas-limit 100000
               :to datahash-contract
               :max-fee-per-blob-gas 20
               :blob-versioned-hashes (list versioned-hash))
              1))
           (sidecar
             (make-blob-sidecar
              :blobs (list (make-byte-vector +blob-byte-size+))
              :commitments (list commitment)
              :proofs (list (make-byte-vector 48 :initial-element #x66))))
           (sender (transaction-sender transaction :expected-chain-id 1337))
           (state (make-state-db)))
      (state-db-set-account
       state sender (make-state-account :nonce 0 :balance 1000000000))
      ;; Hive's Cancun blob cases call this exact BLOBHASH/SSTORE contract.
      ;; A transfer to an empty account would miss failures in the execution
      ;; path that silently make the payload builder skip an invalid tx.
      (state-db-set-code
       state datahash-contract
       #(#x5f #x80 #x49 #x55
         #x60 #x01 #x80 #x49 #x55
         #x60 #x02 #x80 #x49 #x55
         #x60 #x03 #x80 #x49 #x55))
      (let* ((parent
               (make-block
                :header
                (make-block-header
                 :number 0
                 :timestamp 0
                 :gas-limit 30000000
                 :base-fee-per-gas 1
                 :withdrawals-root (withdrawal-list-root '())
                 :blob-gas-used 0
                 :excess-blob-gas 0
                 :parent-beacon-root (zero-hash32)
                 :state-root (state-db-root state))
                :withdrawals '()))
             (parent-hash (block-hash parent))
             (raw
               (bytes-to-hex
                (blob-pooled-transaction-encoding transaction sidecar))))
        (chain-store-put-block store parent :state-available-p t)
        (commit-state-db-to-chain-store store parent-hash state)
        (let* ((*kzg-blob-proof-verifier*
                 (lambda (blob actual-commitment proof)
                   (declare (ignore blob proof))
                   (bytes= commitment actual-commitment)))
               (send-response
                 (request "eth_sendRawTransaction" 610 (list raw)
                          store config))
               (prepare-response
                 (request
                  "engine_forkchoiceUpdatedV3" 611
                  (list (forkchoice-state parent-hash)
                        (payload-attributes 1))
                  store config))
               (payload-id
                 (field (field prepare-response "result") "payloadId"))
               (get-response
                 (request "engine_getPayloadV3" 612 (list payload-id)
                          store config))
               (envelope (field get-response "result"))
               (payload (field envelope "executionPayload"))
               (bundle (field envelope "blobsBundle")))
          (is (string= (hash32-to-hex (transaction-hash transaction))
                       (field send-response "result")))
          (is (stringp payload-id))
          (is (= 1 (length (field payload "transactions"))))
          (is (= 1 (length (field bundle "blobs"))))
          (is (= 1 (length (field bundle "commitments"))))
          (is (= 1 (length (field bundle "proofs")))))))))

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
           (v1-payload-attributes-object ()
             (list (cons "timestamp" "0x1")
                   (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                   (cons "suggestedFeeRecipient"
                         (address-to-hex (zero-address)))))
           (forkchoice-request (id state payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV2")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :london-block 0
                                      :shanghai-time 0))
           (known-block
             (make-block
              :header
              (make-block-header
               :state-root +empty-trie-hash+
               :gas-limit 30000000
               :base-fee-per-gas 1000000000)))
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
        ;; Hive exercises this after it has sent a valid Shanghai FCU.  It
        ;; must remain an Engine invalid-payload-attributes error, not an
        ;; internal error from canonical publication or payload construction.
        (let* ((invalid-response
                 (engine-rpc-handle-request
                  (forkchoice-request
                   31 (forkchoice-state-object known-hash)
                   (v1-payload-attributes-object))
                  store config))
               (error (field invalid-response "error")))
          (is (= 31 (field invalid-response "id")))
          (is (= -38003 (field error "code"))))
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
           (config (make-chain-config :london-block 0
                                      :shanghai-time 0
                                      :cancun-time 0))
           (known-block
             (make-block
              :header
              (make-block-header
               :state-root +empty-trie-hash+
               :gas-limit 30000000
               :base-fee-per-gas 1000000000
               :blob-gas-used 0
               :excess-blob-gas 0)))
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
          (is (ethereum-lisp.json:json-empty-array-p
               (field bundle "commitments")))
          (is (ethereum-lisp.json:json-empty-array-p
               (field bundle "proofs")))
          (is (ethereum-lisp.json:json-empty-array-p
               (field bundle "blobs"))))))))

(deftest engine-rpc-forkchoice-selects-the-fork-get-payload-version
  (let ((attributes (make-payload-attributes-v1))
        (cancun (make-chain-config :london-block 0 :cancun-time 0))
        (prague (make-chain-config :london-block 0 :cancun-time 0
                                   :prague-time 0))
        (osaka (make-chain-config :london-block 0 :cancun-time 0
                                  :prague-time 0 :osaka-time 0))
        (amsterdam (make-chain-config :london-block 0 :cancun-time 0
                                      :prague-time 0 :osaka-time 0
                                      :amsterdam-time 0)))
    (is (= 3 (ethereum-lisp.engine-api::engine-rpc-prepared-payload-version
              3 attributes cancun 1 1)))
    (is (= 4 (ethereum-lisp.engine-api::engine-rpc-prepared-payload-version
              3 attributes prague 1 1)))
    (is (= 5 (ethereum-lisp.engine-api::engine-rpc-prepared-payload-version
              3 attributes osaka 1 1)))
    (is (= 6 (ethereum-lisp.engine-api::engine-rpc-prepared-payload-version
              4 attributes amsterdam 1 1)))))

(deftest engine-rpc-amsterdam-payload-building-is-capability-gated
  (is (not (ethereum-lisp.engine-api::engine-rpc-engine-method-p
            "engine_forkchoiceUpdatedV4")))
  (when (ethereum-lisp.engine-api::engine-rpc-engine-method-p
         "engine_forkchoiceUpdatedV4")
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
                   (cons "slotNumber" "0x2a")
                   (cons "targetGasLimit" "0x1c9c380")))
           (forkchoice-request (id state payload-attributes)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "engine_forkchoiceUpdatedV4")
                   (cons "params" (list state payload-attributes)))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :london-block 0
                                      :shanghai-time 0
                                      :cancun-time 0
                                      :prague-time 0
                                      :amsterdam-time 0))
           (parent-state (make-state-db))
           (known-block
             (progn
               (dolist (address
                        '("0x00000961ef480eb55e80d19ad83579a64c007002"
                          "0x0000bbddc7ce488642fb579f8b00f3a590007251"))
                 (state-db-set-code
                  parent-state (address-from-hex address)
                  #(#x60 #x00 #x60 #x00 #xf3)))
               (make-block
                :header
                (make-block-header
                 :state-root (state-db-root parent-state)
                 :gas-limit 30000000
                 :base-fee-per-gas 1000000000
                 :blob-gas-used 0
                 :excess-blob-gas 0))))
           (known-hash (block-hash known-block))
           (parent-beacon-root
             (hash32-from-hex
              "0x4444444444444444444444444444444444444444444444444444444444444444")))
      (engine-payload-store-put-block
       store known-block :state-available-p t)
      (commit-state-db-to-chain-store store known-hash parent-state)
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
        (is (string= "06" (subseq payload-id 2 4)))
        (is (= 42 (block-header-slot-number prepared-header)))
        (let* ((get-payload-response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 33)
                        (cons "method" "engine_getPayloadV6")
                        (cons "params" (list payload-id)))
                  store
                  config))
               (envelope (field get-payload-response "result"))
               (payload (field envelope "executionPayload"))
               (bundle (field envelope "blobsBundle"))
               (execution-requests (field envelope "executionRequests"))
               (withdrawals (field payload "withdrawals")))
          (is (= 33 (field get-payload-response "id")))
          (is (eq :false (field envelope "shouldOverrideBuilder")))
          (is (string= (quantity-to-hex 42) (field payload "slotNumber")))
          (is (string=
               (quantity-to-hex
                (ethereum-lisp.engine-payloads:engine-target-gas-limit
                 (block-header-gas-limit (block-header known-block))
                 30000000))
                       (field payload "gasLimit")))
          (is (string= "0x0" (field payload "blobGasUsed")))
          (is (string= "0x0" (field payload "excessBlobGas")))
          (is (= 1 (length withdrawals)))
          (is (ethereum-lisp.json:json-empty-array-p execution-requests))
          (is (ethereum-lisp.json:json-empty-array-p
               (field bundle "commitments")))
          (is (ethereum-lisp.json:json-empty-array-p
               (field bundle "proofs")))
          (is (ethereum-lisp.json:json-empty-array-p
               (field bundle "blobs")))))))))
