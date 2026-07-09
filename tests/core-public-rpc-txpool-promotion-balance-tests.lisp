(in-package #:ethereum-lisp.test)

(deftest txpool-basefee-promotion-waits-for-contiguous-nonce
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (send-raw (transaction id store config)
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
                ",\"method\":\"eth_sendRawTransaction\","
                "\"params\":[\""
                (bytes-to-hex (transaction-encoding transaction))
                "\"]}")
               store
               config)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (gap-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (gap-hash (hash32-to-hex (transaction-hash gap-transaction)))
           (closing-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 4
               :gas-limit 21000
               :to recipient
               :value 0)
              1
              1))
           (closing-hash
             (hash32-to-hex (transaction-hash closing-transaction)))
           (sender (transaction-sender gap-transaction :expected-chain-id 1))
           (parent-block
             (make-block
              :header (make-block-header :number 0
                                         :timestamp 0
                                         :gas-limit 30000000
                                         :base-fee-per-gas 5)))
           (child-block
             (make-block
              :header (make-block-header :parent-hash
                                         (block-hash parent-block)
                                         :number 1
                                         :timestamp 12
                                         :gas-limit 30000000
                                         :base-fee-per-gas 3))))
      (chain-store-put-block store parent-block :state-available-p t)
      (chain-store-put-account-nonce store (block-hash parent-block) sender 0)
      (chain-store-put-account-balance
       store (block-hash parent-block) sender 1000000)
      (let* ((filter-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":189,\"method\":\"eth_newPendingTransactionFilter\"}"
                store
                config))
             (filter-id (field filter-response "result"))
             (gap-response (send-raw gap-transaction 190 store config))
             (queued-status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":191,\"method\":\"txpool_status\",\"params\":[]}"
                store
                config)))
        (is (string= gap-hash (field gap-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field (field queued-status-response "result")
                            "pending")))
        (is (string= (quantity-to-hex 1)
                     (field (field queued-status-response "result")
                            "queued")))
        (chain-store-put-block store child-block :state-available-p t)
        (chain-store-set-canonical-head store (block-hash child-block))
        (let* ((after-drop-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":192,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (after-drop-content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":193,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (after-drop-filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":194,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (after-drop-status (field after-drop-status-response "result"))
               (after-drop-content (field after-drop-content-response "result"))
               (after-drop-queued
                 (field (field after-drop-content "queued")
                        (address-to-hex sender))))
          (is (string= (quantity-to-hex 0)
                       (field after-drop-status "pending")))
          (is (string= (quantity-to-hex 1)
                       (field after-drop-status "queued")))
          (is (null (field after-drop-content "pending")))
          (is (string= gap-hash
                       (field (field after-drop-queued "1") "hash")))
          (is (= 0 (length (field after-drop-filter-changes "result")))))
        (chain-store-put-account-nonce
         store (block-hash child-block) sender 0)
        (chain-store-put-account-balance
         store (block-hash child-block) sender 1000000)
        (let* ((closing-response (send-raw closing-transaction 195 store config))
               (promoted-status-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":196,\"method\":\"txpool_status\",\"params\":[]}"
                  store
                  config))
               (promoted-content-response
                 (request
                  "{\"jsonrpc\":\"2.0\",\"id\":197,\"method\":\"txpool_content\",\"params\":[]}"
                  store
                  config))
               (filter-changes
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":198,"
                   "\"method\":\"eth_getFilterChanges\","
                   "\"params\":[\"" filter-id "\"]}")
                  store
                  config))
               (transaction-count-response
                 (request
                  (concatenate
                   'string
                   "{\"jsonrpc\":\"2.0\",\"id\":199,"
                   "\"method\":\"eth_getTransactionCount\","
                   "\"params\":[\""
                   (address-to-hex sender)
                   "\",\"pending\"]}")
                  store
                  config))
               (promoted-status (field promoted-status-response "result"))
               (promoted-content (field promoted-content-response "result"))
               (pending
                 (field (field promoted-content "pending")
                        (address-to-hex sender)))
               (filter-hashes (field filter-changes "result")))
          (is (string= closing-hash (field closing-response "result")))
          (is (string= (quantity-to-hex 2)
                       (field promoted-status "pending")))
          (is (string= (quantity-to-hex 0)
                       (field promoted-status "queued")))
          (is (string= closing-hash
                       (field (field pending "0") "hash")))
          (is (string= gap-hash
                       (field (field pending "1") "hash")))
          (is (null (field promoted-content "queued")))
          (is (string= (quantity-to-hex 2)
                       (field transaction-count-response "result")))
          (is (= 2 (length filter-hashes)))
          (is (string= closing-hash (first filter-hashes)))
          (is (string= gap-hash (second filter-hashes))))))))

(deftest engine-payload-store-promotes-basefee-transactions-by-sender-index
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (sender-a-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-a-nonce-one
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-a-nonce-three
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 3
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-b-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            2
            1))
         (sender-a
           (transaction-sender sender-a-nonce-zero :expected-chain-id 1))
         (sender-b
           (transaction-sender sender-b-nonce-zero :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000
                                       :base-fee-per-gas 3))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender-a 0)
    (chain-store-put-account-nonce store (block-hash head-block) sender-b 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender-a 1000000)
    (chain-store-put-account-balance
     store (block-hash head-block) sender-b 1000000)
    (dolist (transaction
             (list sender-a-nonce-three
                   sender-b-nonce-zero
                   sender-a-nonce-one
                   sender-a-nonce-zero))
      (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
       store
       transaction))
    (let ((promoted
            (ethereum-lisp.core::engine-payload-store-promote-basefee-transactions
             store))
          (sender-a-pending
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender-a))
          (sender-b-pending
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender-b)))
      (is (= 3 (length promoted)))
      (is (= 3
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
              store)))
      (is (eq sender-a-nonce-zero (first sender-a-pending)))
      (is (eq sender-a-nonce-one (second sender-a-pending)))
      (is (eq sender-b-nonce-zero (first sender-b-pending)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store
            (transaction-hash sender-a-nonce-three))))
      (is (eq sender-a-nonce-three
              (ethereum-lisp.core::engine-payload-store-pooled-transaction
               store
               (transaction-hash sender-a-nonce-three)))))))

(deftest txpool-queued-promotion-rechecks-pending-balance
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (gap-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 1
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (closing-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 1
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (sender (transaction-sender gap-transaction :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender 21000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     closing-transaction)
    (ethereum-lisp.core::engine-payload-store-put-queued-transaction
     store
     gap-transaction)
    (is (null
         (ethereum-lisp.core::engine-payload-store-promote-queued-transactions
          store
          sender)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (eq closing-transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store
             (transaction-hash closing-transaction))))
    (is (eq gap-transaction
            (ethereum-lisp.core::engine-payload-store-queued-transaction
             store
             (transaction-hash gap-transaction))))))

(deftest txpool-basefee-promotion-rechecks-pending-balance
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (gap-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 4
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (closing-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (sender (transaction-sender gap-transaction :expected-chain-id 1))
         (head-block
           (make-block
            :header (make-block-header :number 0
                                       :timestamp 0
                                       :gas-limit 30000000
                                       :base-fee-per-gas 3))))
    (chain-store-put-block store head-block :state-available-p t)
    (chain-store-put-account-nonce store (block-hash head-block) sender 0)
    (chain-store-put-account-balance
     store (block-hash head-block) sender 84000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     closing-transaction)
    (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
     store
     gap-transaction)
    (is (null
         (ethereum-lisp.core::engine-payload-store-promote-basefee-transactions
          store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
            store)))
    (is (eq closing-transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store
             (transaction-hash closing-transaction))))
    (is (eq gap-transaction
            (ethereum-lisp.core::engine-payload-store-basefee-transaction
             store
             (transaction-hash gap-transaction))))))

