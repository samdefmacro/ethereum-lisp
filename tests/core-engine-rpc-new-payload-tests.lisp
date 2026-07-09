(in-package #:ethereum-lisp.test)

(deftest engine-new-payload-memory-status-caches-invalid-ancestors
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0))
         (parent-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 41
                         :gas-limit 50000
                         :gas-used 25000
                         :timestamp 98
                         :base-fee-per-gas 100))
         (parent-block (make-block :header parent-header))
         (invalid-child-header (make-block-header
                                :parent-hash (block-hash parent-block)
                                :beneficiary address
                                :state-root +empty-trie-hash+
                                :mix-hash (zero-hash32)
                                :number 42
                                :gas-limit 50000
                                :gas-used 0
                                :timestamp 98
                                :base-fee-per-gas 100))
         (invalid-child-block (make-block :header invalid-child-header))
         (grandchild-header (make-block-header
                             :parent-hash (block-hash invalid-child-block)
                             :beneficiary address
                             :state-root +empty-trie-hash+
                             :mix-hash (zero-hash32)
                             :number 43
                             :gas-limit 50000
                             :gas-used 0
                             :timestamp 100
                             :base-fee-per-gas 100))
         (grandchild-block (make-block :header grandchild-header))
         (invalid-child-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data invalid-child-block)))
         (grandchild-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data grandchild-block)))
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block store parent-block :state-available-p t)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 invalid-child-payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (not block))
      (is (engine-payload-store-invalid-block
           store
           (block-hash invalid-child-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 grandchild-payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (string= "links to previously rejected block"
                   (payload-status-validation-error status)))
      (is (not block))
      (let ((cached-head
              (engine-payload-store-invalid-block
               store
               (block-hash grandchild-block))))
        (is cached-head)
        (is (string= (hash32-to-hex (block-hash invalid-child-block))
                     (hash32-to-hex (block-hash cached-head))))))))

(deftest engine-rpc-handle-request-dispatches-new-payload
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (payload-object (payload)
             (list
              (cons "parentHash"
                    (hash32-to-hex (executable-data-parent-hash payload)))
              (cons "feeRecipient"
                    (address-to-hex (executable-data-fee-recipient payload)))
              (cons "stateRoot"
                    (hash32-to-hex (executable-data-state-root payload)))
              (cons "receiptsRoot"
                    (hash32-to-hex (executable-data-receipts-root payload)))
              (cons "logsBloom"
                    (bytes-to-hex (executable-data-logs-bloom payload)))
              (cons "prevRandao"
                    (hash32-to-hex (executable-data-random payload)))
              (cons "blockNumber"
                    (quantity-to-hex (executable-data-number payload)))
              (cons "gasLimit"
                    (quantity-to-hex (executable-data-gas-limit payload)))
              (cons "gasUsed"
                    (quantity-to-hex (executable-data-gas-used payload)))
              (cons "timestamp"
                    (quantity-to-hex (executable-data-timestamp payload)))
              (cons "extraData"
                    (bytes-to-hex (executable-data-extra-data payload)))
              (cons "baseFeePerGas"
                    (quantity-to-hex
                     (executable-data-base-fee-per-gas payload)))
              (cons "blockHash"
                    (hash32-to-hex (executable-data-block-hash payload)))
              (cons "transactions"
                    (mapcar #'bytes-to-hex
                            (executable-data-transactions payload))))))
    (let* ((address
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (config (make-chain-config :london-block 0))
           (parent-header (make-block-header
                           :parent-hash (zero-hash32)
                           :beneficiary address
                           :state-root +empty-trie-hash+
                           :mix-hash (zero-hash32)
                           :number 1
                           :gas-limit 50000
                           :gas-used 25000
                           :timestamp 10
                           :base-fee-per-gas 100))
           (parent-block (make-block :header parent-header))
           (child-header (make-block-header
                          :parent-hash (block-hash parent-block)
                          :beneficiary address
                          :state-root +empty-trie-hash+
                          :receipts-root +empty-trie-hash+
                          :logs-bloom (make-byte-vector 256)
                          :mix-hash (zero-hash32)
                          :number 2
                          :gas-limit 50000
                          :gas-used 0
                          :timestamp 11
                          :base-fee-per-gas 100))
           (child-block (make-block :header child-header))
           (payload
             (execution-payload-envelope-execution-payload
              (block-to-executable-data child-block)))
           (store (make-engine-payload-memory-store))
           (request
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 7)
                   (cons "method" "engine_newPayloadV1")
                   (cons "params" (list (payload-object payload))))))
      (engine-payload-store-put-block store parent-block :state-available-p t)
      (let* ((response (engine-rpc-handle-request request store config))
             (result (field response "result")))
        (is (string= "2.0" (field response "jsonrpc")))
        (is (= 7 (field response "id")))
        (is (string= +payload-status-valid+ (field result "status")))
        (is (string= (hash32-to-hex (block-hash child-block))
                     (field result "latestValidHash")))
        (is (engine-payload-store-known-block store
                                              (block-hash child-block))))
      (let ((executable-store (make-engine-payload-memory-store)))
        (engine-payload-store-put-block
         executable-store parent-block :state-available-p t)
        (let* ((response
                 (engine-rpc-handle-request
                  request executable-store config
                  :import-function #'execute-and-commit-engine-payload))
               (result (field response "result")))
          (is (string= +payload-status-valid+ (field result "status")))
          (is (engine-payload-store-known-block
               executable-store
               (block-hash child-block)))
          (is (chain-store-state-available-p
               executable-store
               (block-hash child-block)))))
      (let* ((response
               (engine-rpc-handle-request-string
                "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (error (field response "error")))
        (is (= -32601 (field error "code"))))
      (let* ((response-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (response (parse-json response-json))
             (error (field response "error")))
        (is (string= "2.0" (field response "jsonrpc")))
        (is (= 9 (field response "id")))
        (is (= -32601 (field error "code")))
        (is (string= "Method not found" (field error "message"))))
      (let* ((parse-error-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":9,"
                store
                config))
             (parse-error-response (parse-json parse-error-json))
             (parse-error (field parse-error-response "error")))
        (is (not (field parse-error-response "id")))
        (is (= -32700 (field parse-error "code")))
        (is (string= "Parse error" (field parse-error "message"))))
      (let* ((missing-version-json
               (engine-rpc-handle-request-json
                "{\"id\":12,\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (missing-version-response (parse-json missing-version-json))
             (missing-version-error
               (field missing-version-response "error"))
             (bad-version-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"1.0\",\"id\":13,\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (bad-version-response (parse-json bad-version-json))
             (bad-version-error (field bad-version-response "error"))
             (numeric-version-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":2,\"id\":14,\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (numeric-version-response (parse-json numeric-version-json))
             (numeric-version-error (field numeric-version-response "error"))
             (missing-method-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":15,\"params\":[]}"
                store
                config))
             (missing-method-response (parse-json missing-method-json))
             (missing-method-error (field missing-method-response "error"))
             (numeric-method-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":7,\"params\":[]}"
                store
                config))
             (numeric-method-response (parse-json numeric-method-json))
             (numeric-method-error (field numeric-method-response "error"))
             (scalar-params-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":17,\"method\":\"engine_nope\",\"params\":7}"
                store
                config))
             (scalar-params-response (parse-json scalar-params-json))
             (scalar-params-error (field scalar-params-response "error"))
             (empty-string-params-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":18,\"method\":\"engine_nope\",\"params\":\"\"}"
                store
                config))
             (empty-string-params-response
               (parse-json empty-string-params-json))
             (empty-string-params-error
               (field empty-string-params-response "error"))
             (boolean-id-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":true,\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (boolean-id-response (parse-json boolean-id-json))
             (boolean-id-error (field boolean-id-response "error"))
             (object-id-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":{\"bad\":1},\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (object-id-response (parse-json object-id-json))
             (object-id-error (field object-id-response "error"))
             (malformed-no-id-json
               (engine-rpc-handle-request-json
                "{\"method\":\"engine_nope\",\"params\":[]}"
                store
                config))
             (malformed-no-id-response (parse-json malformed-no-id-json))
             (malformed-no-id-error (field malformed-no-id-response "error")))
        (is (= -32600 (field missing-version-error "code")))
        (is (= -32600 (field bad-version-error "code")))
        (is (= -32600 (field numeric-version-error "code")))
        (is (= -32600 (field missing-method-error "code")))
        (is (= -32600 (field numeric-method-error "code")))
        (is (= -32600 (field scalar-params-error "code")))
        (is (= -32600 (field empty-string-params-error "code")))
        (is (= -32600 (field boolean-id-error "code")))
        (is (= -32600 (field object-id-error "code")))
        (is (= -32600 (field malformed-no-id-error "code"))))
      (let* ((batch-json
               (engine-rpc-handle-request-json
                "[{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"engine_nope\",\"params\":[]},7]"
                store
                config))
             (responses (parse-json batch-json))
             (first-error (field (first responses) "error"))
             (second-error (field (second responses) "error")))
        (is (= 2 (length responses)))
        (is (= 10 (field (first responses) "id")))
        (is (= -32601 (field first-error "code")))
        (is (not (field (second responses) "id")))
        (is (= -32600 (field second-error "code"))))
      (let* ((notification-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"method\":\"engine_nope\",\"params\":[]}"
                store
                config)))
        (is (string= "" notification-json)))
      (let* ((mixed-batch-json
               (engine-rpc-handle-request-json
                "[{\"jsonrpc\":\"2.0\",\"method\":\"engine_nope\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"engine_nope\",\"params\":[]}]"
                store
                config))
             (responses (parse-json mixed-batch-json))
             (error (field (first responses) "error")))
        (is (= 1 (length responses)))
        (is (= 11 (field (first responses) "id")))
        (is (= -32601 (field error "code"))))
      (let* ((notifications-json
               (engine-rpc-handle-request-json
                "[{\"jsonrpc\":\"2.0\",\"method\":\"engine_nope\",\"params\":[]},{\"jsonrpc\":\"2.0\",\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}]"
                store
                config)))
        (is (string= "" notifications-json))))))

(deftest engine-rpc-new-payload-v2-imports-one-transaction
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
             (expected-state (state-db-copy parent-state))
             (child-header
               (make-block-header
                :parent-hash (block-hash parent-block)
                :beneficiary fee-recipient
                :mix-hash (zero-hash32)
                :number 42
                :gas-limit 50000
                :gas-used 0
                :timestamp 99
                :base-fee-per-gas 100))
             (child-block
               (execute-signed-block
                expected-state
                (list transaction)
                :expected-chain-id 1
                :header child-header
                :chain-config config
                :withdrawals (list withdrawal)))
             (payload
               (execution-payload-envelope-execution-payload
                (block-to-executable-data child-block)))
             (request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 27)
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
                  request store config
                  :import-function #'execute-and-commit-engine-payload))
               (result (field response "result")))
          (is (string= "2.0" (field response "jsonrpc")))
          (is (= 27 (field response "id")))
          (is (string= +payload-status-valid+ (field result "status")))
          (is (string= (hash32-to-hex (block-hash child-block))
                       (field result "latestValidHash")))
          (is (engine-payload-store-known-block
               store (block-hash child-block)))
          (is (chain-store-state-available-p
               store (block-hash child-block)))
          (is (= 10
                 (chain-store-account-nonce
                  store (block-hash child-block) sender)))
          (is (= 999580000000000000
                 (chain-store-account-balance
                  store (block-hash child-block) sender)))
          (is (= 1000000000000000000
                 (chain-store-account-balance
                  store (block-hash child-block) recipient)))
          (is (= +wei-per-gwei+
                 (chain-store-account-balance
                  store (block-hash child-block) withdrawal-recipient)))
          (is (typep (chain-store-transaction-location
                      store
                      (transaction-hash transaction))
                     'engine-transaction-location))
          (let* ((receipts
                   (chain-store-block-receipts store (block-hash child-block)))
                 (receipt-response
                   (engine-rpc-handle-request
                    (receipt-request 28 (transaction-hash transaction))
                    store config))
                 (receipt (field receipt-response "result"))
                 (receipts-root
                   (block-header-receipts-root (block-header child-block))))
            (is (= 1 (length receipts)))
            (is (string= (hash32-to-hex (receipt-list-root receipts))
                         (hash32-to-hex receipts-root)))
            (is (string= (hash32-to-hex
                          (transaction-receipt-list-root
                           (list transaction)
                           receipts))
                         (hash32-to-hex receipts-root)))
            (is (string= (quantity-to-hex 0) (field receipt "type")))
            (is (string= (quantity-to-hex 1)
                         (field receipt "status")))))))))

(deftest engine-rpc-new-payload-v2-rolls-back-state-projection-on-bad-commitment
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (bad-logs-bloom ()
             (let ((bloom (make-byte-vector 256)))
               (setf (aref bloom 0) 1)
               bloom)))
    (let* ((config (make-chain-config :chain-id 1
                                      :byzantium-block 0
                                      :constantinople-block 0
                                      :petersburg-block 0
                                      :berlin-block 0
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
             (parent-block (make-block :header parent-header)))
        (labels ((child-block ()
                   (execute-signed-block
                    (state-db-copy parent-state)
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
                 (check-case (mutate-header expected-error)
                   (let* ((store (make-engine-payload-memory-store))
                          (bad-block (child-block)))
                     (funcall mutate-header (block-header bad-block))
                     (let* ((bad-block-hash (block-hash bad-block))
                            (payload
                              (execution-payload-envelope-execution-payload
                               (block-to-executable-data bad-block)))
                            (request
                              (list
                               (cons "jsonrpc" "2.0")
                               (cons "id" 29)
                               (cons "method" "engine_newPayloadV2")
                               (cons
                                "params"
                                (list (engine-rpc-executable-data-object
                                       payload))))))
                       (engine-payload-store-put-block
                        store parent-block :state-available-p t)
                       (commit-state-db-to-chain-store
                        store (block-hash parent-block) parent-state)
                       (let* ((response
                                (engine-rpc-handle-request
                                 request store config
                                 :import-function
                                 #'execute-and-commit-engine-payload))
                              (result (field response "result")))
                         (is (string= +payload-status-invalid+
                                      (field result "status")))
                         (is (string= expected-error
                                      (field result "validationError")))
                         (is (not (chain-store-known-block
                                   store bad-block-hash)))
                         (is (not (chain-store-state-available-p
                                   store bad-block-hash)))
                         (is (not (chain-store-transaction-location
                                   store
                                   (transaction-hash transaction))))
                         (is (= 0
                                (chain-store-account-nonce
                                 store bad-block-hash sender)))
                         (is (= 0
                                (chain-store-account-balance
                                 store bad-block-hash recipient)))
                         (is (= 0
                                (chain-store-account-balance
                                 store bad-block-hash withdrawal-recipient)))
                         (is (= 9
                                (chain-store-account-nonce
                                 store (block-hash parent-block) sender)))
                         (is (= 2000000000000000000
                                (chain-store-account-balance
                                 store (block-hash parent-block) sender))))))))
          (check-case
           (lambda (header)
             (setf (block-header-state-root header) (zero-hash32)))
           "State root mismatch")
          (check-case
           (lambda (header)
             (setf (block-header-receipts-root header) (zero-hash32)))
           "Receipts root mismatch")
          (check-case
           (lambda (header)
             (setf (block-header-logs-bloom header) (bad-logs-bloom)))
           "Logs bloom mismatch")
          (check-case
           (lambda (header)
             (setf (block-header-gas-used header) 1))
           "Gas used mismatch"))))))

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

(deftest engine-rpc-new-payload-v2-internal-create2-receipt-has-no-contract-address
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
                 (import-result (field import-response "result"))
                 (receipt-response
                   (engine-rpc-handle-request
                    (receipt-request 32 (transaction-hash transaction))
                    store config))
                 (receipt (field receipt-response "result")))
            (is (string= +payload-status-valid+
                         (field import-result "status")))
            (is (bytes= #(0)
                        (chain-store-account-code
                         store (block-hash child-block) created-contract)))
            (is (null (field receipt "contractAddress")))
            (is (string= (address-to-hex contract)
                         (field receipt "to")))
            (is (string= (quantity-to-hex 1) (field receipt "status")))
            (is (string= (quantity-to-hex 0)
                         (field receipt "transactionIndex")))
            (is (string= (hash32-to-hex (transaction-hash transaction))
                         (field receipt "transactionHash")))
            (is (string= (hash32-to-hex (block-hash child-block))
                         (field receipt "blockHash")))))))))

(deftest engine-rpc-new-payload-v2-dynamic-fee-typed-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
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
               (import-result (field import-response "result"))
               (receipts
                 (chain-store-block-receipts store (block-hash child-block)))
               (receipt-response
                 (engine-rpc-handle-request
                  (receipt-request 32 (transaction-hash transaction))
                  store config))
               (receipt (field receipt-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
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
                       (field receipt "blockHash"))))))))

(deftest engine-rpc-new-payload-v2-access-list-typed-receipt
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (receipt-request (id hash)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getTransactionReceipt")
                   (cons "params" (list (hash32-to-hex hash))))))
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
               (import-result (field import-response "result"))
               (receipts
                 (chain-store-block-receipts store (block-hash child-block)))
               (receipt-response
                 (engine-rpc-handle-request
                  (receipt-request 34 (transaction-hash transaction))
                  store config))
               (receipt (field receipt-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
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
                       (field receipt "blockHash"))))))))

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
                   (cons "params" (list (hash32-to-hex hash))))))
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
               (import-result (field import-response "result"))
               (receipts
                 (chain-store-block-receipts store (block-hash child-block)))
               (receipt-response
                 (engine-rpc-handle-request
                  (receipt-request 36 (transaction-hash transaction))
                  store config))
               (receipt (field receipt-response "result")))
          (is (string= +payload-status-valid+
                       (field import-result "status")))
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
                       (field receipt "blockHash"))))))))

