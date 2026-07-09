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
                   (cons "params" '())))
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

(deftest engine-rpc-get-payload-v3-returns-cancun-envelope
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(3 0 0 0 0 0 0 1))
           (block
             (make-block
              :header
              (make-block-header :number 7
                                 :timestamp 12
                                 :blob-gas-used 0
                                 :excess-blob-gas 0)))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 3
        :block block))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 37)
                      (cons "method" "engine_getPayloadV3")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (payload (field envelope "executionPayload"))
             (bundle (field envelope "blobsBundle")))
        (is (= 37 (field response "id")))
        (is (string= "0x0" (field envelope "blockValue")))
        (is (eq :false (field envelope "shouldOverrideBuilder")))
        (is (string= "0x0" (field payload "blobGasUsed")))
        (is (string= "0x0" (field payload "excessBlobGas")))
        (is (listp (field bundle "commitments")))
        (is (listp (field bundle "proofs")))
        (is (listp (field bundle "blobs")))
        (is (= 0 (length (field bundle "commitments")))))
      (let* ((response-json
               (engine-rpc-handle-request-json
                "{\"jsonrpc\":\"2.0\",\"id\":38,\"method\":\"engine_getPayloadV3\",\"params\":[\"0x0300000000000001\"]}"
                store
                config)))
        (is (search "\"shouldOverrideBuilder\":false" response-json))))))

(deftest engine-rpc-get-payload-v4-returns-prague-execution-requests
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(4 0 0 0 0 0 0 1))
           (requests (list #(#x00 #xaa) #(#x01 #xbb)))
           (block
             (make-block
              :header
              (make-block-header :number 8
                                 :timestamp 13
                                 :blob-gas-used 0
                                 :excess-blob-gas 0)
              :requests requests))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 4
        :block block))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 39)
                      (cons "method" "engine_getPayloadV4")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (payload (field envelope "executionPayload"))
             (bundle (field envelope "blobsBundle"))
             (encoded-requests (field envelope "executionRequests")))
        (is (= 39 (field response "id")))
        (is (eq :false (field envelope "shouldOverrideBuilder")))
        (is (string= "0x0" (field payload "blobGasUsed")))
        (is (string= "0x0" (field payload "excessBlobGas")))
        (is (= 0 (length (field bundle "blobs"))))
        (is (= 2 (length encoded-requests)))
        (is (string= "0x00aa" (first encoded-requests)))
        (is (string= "0x01bb" (second encoded-requests)))))))

(deftest engine-rpc-get-payload-v5-returns-osaka-blobs-bundle
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(5 0 0 0 0 0 0 1))
           (requests (list #(#x02 #xcc)))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x03 #xdd))
              :commitments (list #(#x04 #xee))
              :proofs (list #(#x05 #xff) #(#x06 #x11))))
           (block
             (make-block
              :header
              (make-block-header :number 9
                                 :timestamp 14
                                 :blob-gas-used 0
                                 :excess-blob-gas 0)
              :requests requests))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 5
        :block block
        :blobs-bundle sidecar))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 40)
                      (cons "method" "engine_getPayloadV5")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (bundle (field envelope "blobsBundle")))
        (is (= 40 (field response "id")))
        (is (eq :false (field envelope "shouldOverrideBuilder")))
        (is (string= "0x02cc"
                     (first (field envelope "executionRequests"))))
        (is (string= "0x04ee" (first (field bundle "commitments"))))
        (is (string= "0x05ff" (first (field bundle "proofs"))))
        (is (string= "0x0611" (second (field bundle "proofs"))))
        (is (string= "0x03dd" (first (field bundle "blobs"))))))))

(deftest engine-rpc-get-payload-v6-returns-amsterdam-fields
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((payload-id #(6 0 0 0 0 0 0 1))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x07 #xaa))
              :commitments (list #(#x08 #xbb))
              :proofs (list #(#x09 #xcc))))
           (block
             (make-block
              :header
              (make-block-header :number 10
                                 :timestamp 15
                                 :blob-gas-used 0
                                 :excess-blob-gas 0
                                 :slot-number 42)
              :requests (list #(#x03 #xdd))
              :block-access-list '()))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-prepared-payload
       store
       (make-engine-prepared-payload
        :payload-id payload-id
        :version 6
        :block block
        :blobs-bundle sidecar))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 41)
                      (cons "method" "engine_getPayloadV6")
                      (cons "params" (list (bytes-to-hex payload-id))))
                store
                config))
             (envelope (field response "result"))
             (payload (field envelope "executionPayload"))
             (bundle (field envelope "blobsBundle")))
        (is (= 41 (field response "id")))
        (is (string= (quantity-to-hex 42) (field payload "slotNumber")))
        (is (string= (bytes-to-hex (block-encoded-block-access-list block))
                     (field payload "blockAccessList")))
        (is (string= "0x03dd"
                     (first (field envelope "executionRequests"))))
        (is (string= "0x08bb" (first (field bundle "commitments"))))
        (is (string= "0x09cc" (first (field bundle "proofs"))))
        (is (string= "0x07aa" (first (field bundle "blobs"))))))))

(deftest engine-rpc-get-blobs-v1-returns-blobs-and-proofs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((blob (make-byte-vector +blob-byte-size+))
           (commitment (make-byte-vector +kzg-commitment-size+))
           (proof (make-byte-vector +kzg-proof-size+))
           (unknown-hash
             (make-hash32 (make-byte-vector 32 :initial-element #x11)))
           (sidecar nil)
           (versioned-hash nil)
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (setf (aref blob 0) #xaa
            (aref commitment 0) #xbb
            (aref proof 0) #xcc
            sidecar (make-blob-sidecar
                     :blobs (list blob)
                     :commitments (list commitment)
                     :proofs (list proof))
            versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
      (engine-payload-store-put-blob-sidecar store sidecar)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 42)
                      (cons "method" "engine_getBlobsV1")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)
                                        (hash32-to-hex unknown-hash)))))
                store
                config))
             (result (field response "result"))
             (first-blob (first result)))
        (is (= 42 (field response "id")))
        (is (= 2 (length result)))
        (is (string= (bytes-to-hex blob) (field first-blob "blob")))
        (is (string= (bytes-to-hex proof) (field first-blob "proof")))
        (is (null (second result))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 43)
                      (cons "method" "engine_getBlobsV1")
                      (cons "params"
                            (list
                             (loop repeat 129
                                   collect (hash32-to-hex unknown-hash)))))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested blobs must not exceed 128"
                     (field error "message")))))))

(deftest engine-rpc-get-blobs-v2-v3-return-cell-proofs
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((blob (make-byte-vector +blob-byte-size+))
           (commitment (make-byte-vector +kzg-commitment-size+))
           (proofs
             (loop for i below +cell-proofs-per-blob+
                   collect
                   (let ((proof (make-byte-vector +kzg-proof-size+)))
                     (setf (aref proof 0) i)
                     proof)))
           (unknown-hash
             (make-hash32 (make-byte-vector 32 :initial-element #x22)))
           (sidecar nil)
           (versioned-hash nil)
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (setf (aref blob 0) #xaa
            (aref commitment 0) #xbb
            sidecar (make-blob-sidecar
                     :blobs (list blob)
                     :commitments (list commitment)
                     :proofs proofs)
            versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
      (engine-payload-store-put-blob-sidecar store sidecar)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 44)
                      (cons "method" "engine_getBlobsV2")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)))))
                store
                config))
             (result (field response "result"))
             (first-blob (first result))
             (encoded-proofs (field first-blob "proofs")))
        (is (= 44 (field response "id")))
        (is (= 1 (length result)))
        (is (string= (bytes-to-hex blob) (field first-blob "blob")))
        (is (= +cell-proofs-per-blob+ (length encoded-proofs)))
        (is (string= (bytes-to-hex (first proofs)) (first encoded-proofs)))
        (is (string= (bytes-to-hex (car (last proofs)))
                     (car (last encoded-proofs)))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 45)
                      (cons "method" "engine_getBlobsV2")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)
                                        (hash32-to-hex unknown-hash)))))
                store
                config)))
        (is (= 45 (field response "id")))
        (is (null (field response "result"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 46)
                      (cons "method" "engine_getBlobsV3")
                      (cons "params"
                            (list (list (hash32-to-hex versioned-hash)
                                        (hash32-to-hex unknown-hash)))))
                store
                config))
             (result (field response "result"))
             (first-blob (first result)))
        (is (= 46 (field response "id")))
        (is (= 2 (length result)))
        (is (string= (bytes-to-hex blob) (field first-blob "blob")))
        (is (string= (bytes-to-hex (first proofs))
                     (first (field first-blob "proofs"))))
        (is (null (second result)))))))

(deftest engine-rpc-get-payload-bodies-by-hash-v1-returns-bodies
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((recipient
             (address-from-hex "0x0000000000000000000000000000000000000002"))
           (withdrawal-address
             (address-from-hex "0x0000000000000000000000000000000000000003"))
           (transaction
             (make-legacy-transaction :nonce 1
                                      :gas-price 2
                                      :gas-limit 21000
                                      :to recipient
                                      :value 4
                                      :v 27
                                      :r 6
                                      :s 7))
           (withdrawal
             (make-withdrawal :index 1
                              :validator-index 2
                              :address withdrawal-address
                              :amount 3))
           (block (make-block :transactions (list transaction)
                              :withdrawals (list withdrawal)))
           (empty-withdrawals-block (make-block :withdrawals '()))
           (unknown-hash
             (hash32-from-hex
              "0x2222222222222222222222222222222222222222222222222222222222222222"))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block :state-available-p t)
      (engine-payload-store-put-block
       store empty-withdrawals-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 28)
                      (cons "method" "engine_getPayloadBodiesByHashV1")
                      (cons "params"
                            (list
                             (list (hash32-to-hex (block-hash block))
                                   (hash32-to-hex unknown-hash)
                                   (hash32-to-hex
                                    (block-hash empty-withdrawals-block))))))
                store
                config))
             (bodies (field response "result"))
             (first-body (first bodies))
             (third-body (third bodies)))
        (is (= 28 (field response "id")))
        (is (= 3 (length bodies)))
        (is (string= (bytes-to-hex (transaction-encoding transaction))
                     (first (field first-body "transactions"))))
        (is (= 1 (length (field first-body "withdrawals"))))
        (is (not (second bodies)))
        (is (not (field third-body "transactions")))
        (is (listp (field third-body "withdrawals")))
        (is (= 0 (length (field third-body "withdrawals")))))
      (let* ((too-many-hashes
               (loop repeat 1025 collect (hash32-to-hex (block-hash block))))
             (response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 29)
                      (cons "method" "engine_getPayloadBodiesByHashV1")
                      (cons "params" (list too-many-hashes)))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested bodies must not exceed 1024"
                     (field error "message")))))))

(deftest engine-rpc-get-payload-bodies-by-hash-v2-returns-block-access-list
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((plain-block (make-block))
           (bal-block (make-block :block-access-list '()))
           (unknown-hash
             (hash32-from-hex
              "0x3333333333333333333333333333333333333333333333333333333333333333"))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store plain-block :state-available-p t)
      (engine-payload-store-put-block store bal-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 33)
                      (cons "method" "engine_getPayloadBodiesByHashV2")
                      (cons "params"
                            (list
                             (list (hash32-to-hex (block-hash plain-block))
                                   (hash32-to-hex (block-hash bal-block))
                                   (hash32-to-hex unknown-hash)))))
                store
                config))
             (bodies (field response "result"))
             (plain-body (first bodies))
             (bal-body (second bodies)))
        (is (= 33 (field response "id")))
        (is (= 3 (length bodies)))
        (is (not (field plain-body "blockAccessList")))
        (is (string= (bytes-to-hex (block-encoded-block-access-list bal-block))
                     (field bal-body "blockAccessList")))
        (is (not (third bodies)))))
    (let* ((too-many-hashes
             (loop repeat 1025 collect (hash32-to-hex (zero-hash32))))
           (response
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 34)
                    (cons "method" "engine_getPayloadBodiesByHashV2")
                    (cons "params" (list too-many-hashes)))
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (error (field response "error")))
      (is (= -38004 (field error "code")))
      (is (string= "The number of requested bodies must not exceed 1024"
                   (field error "message"))))))

(deftest engine-rpc-get-payload-bodies-by-range-v1-returns-bodies
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (numbered-block (number &key transactions withdrawals)
             (make-block
              :header (make-block-header :number number
                                         :timestamp number)
              :transactions transactions
              :withdrawals withdrawals)))
    (let* ((recipient
             (address-from-hex "0x0000000000000000000000000000000000000004"))
           (transaction
             (make-legacy-transaction :nonce 2
                                      :gas-price 3
                                      :gas-limit 21000
                                      :to recipient
                                      :value 5
                                      :v 27
                                      :r 8
                                      :s 9))
           (block-1 (numbered-block 1 :transactions (list transaction)))
           (block-2 (numbered-block 2 :withdrawals '()))
           (block-4 (numbered-block 4 :transactions '()))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store block-1 :state-available-p t)
      (engine-payload-store-put-block store block-2 :state-available-p t)
      (engine-payload-store-put-block store block-4 :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 30)
                      (cons "method" "engine_getPayloadBodiesByRangeV1")
                      (cons "params" (list "0x1" "0x4")))
                store
                config))
             (bodies (field response "result"))
             (first-body (first bodies))
             (second-body (second bodies))
             (fourth-body (fourth bodies)))
        (is (= 30 (field response "id")))
        (is (= 4 (length bodies)))
        (is (string= (bytes-to-hex (transaction-encoding transaction))
                     (first (field first-body "transactions"))))
        (is (not (field first-body "withdrawals")))
        (is (not (field second-body "transactions")))
        (is (listp (field second-body "withdrawals")))
        (is (not (third bodies)))
        (is (not (field fourth-body "transactions"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 31)
                      (cons "method" "engine_getPayloadBodiesByRangeV1")
                      (cons "params" (list "0x0" "0x1")))
                store
                config))
             (error (field response "error")))
        (is (= -32602 (field error "code"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 32)
                      (cons "method" "engine_getPayloadBodiesByRangeV1")
                      (cons "params" (list 1 1025)))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested bodies must not exceed 1024"
                     (field error "message")))))))

(deftest engine-rpc-get-payload-bodies-by-range-v2-returns-block-access-list
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (numbered-block
               (number &key (block-access-list nil block-access-list-p))
             (let ((header (make-block-header :number number
                                              :timestamp number)))
               (if block-access-list-p
                   (make-block :header header
                               :block-access-list block-access-list)
                   (make-block :header header)))))
    (let* ((plain-block (numbered-block 1))
           (bal-block (numbered-block 2 :block-access-list '()))
           (tail-block (numbered-block 4 :block-access-list '()))
           (store (make-engine-payload-memory-store))
           (config (make-chain-config)))
      (engine-payload-store-put-block store plain-block :state-available-p t)
      (engine-payload-store-put-block store bal-block :state-available-p t)
      (engine-payload-store-put-block store tail-block :state-available-p t)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 35)
                      (cons "method" "engine_getPayloadBodiesByRangeV2")
                      (cons "params" (list "0x1" "0x4")))
                store
                config))
             (bodies (field response "result"))
             (plain-body (first bodies))
             (bal-body (second bodies))
             (tail-body (fourth bodies)))
        (is (= 35 (field response "id")))
        (is (= 4 (length bodies)))
        (is (not (field plain-body "blockAccessList")))
        (is (string= (bytes-to-hex (block-encoded-block-access-list bal-block))
                     (field bal-body "blockAccessList")))
        (is (not (third bodies)))
        (is (string= (bytes-to-hex (block-encoded-block-access-list tail-block))
                     (field tail-body "blockAccessList"))))
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 36)
                      (cons "method" "engine_getPayloadBodiesByRangeV2")
                      (cons "params" (list "0x1" "0x401")))
                store
                config))
             (error (field response "error")))
        (is (= -38004 (field error "code")))
        (is (string= "The number of requested bodies must not exceed 1024"
                     (field error "message")))))))

(deftest engine-rpc-exchange-capabilities-advertises-supported-methods
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (request-json
             "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"engine_exchangeCapabilities\",\"params\":[[\"engine_newPayloadV1\",\"engine_forkchoiceUpdatedV1\"]]}")
           (response (parse-json
                      (engine-rpc-handle-request-json
                       request-json store config)))
           (capabilities (field response "result")))
      (is (= 11 (field response "id")))
      (is (member "engine_newPayloadV1" capabilities :test #'string=))
      (is (member "engine_newPayloadV2" capabilities :test #'string=))
      (is (not (member "engine_newPayloadV3" capabilities :test #'string=)))
      (is (not (member "engine_newPayloadV5" capabilities :test #'string=)))
      (is (member "engine_forkchoiceUpdatedV1"
                  capabilities
                  :test #'string=))
      (is (member "engine_forkchoiceUpdatedV2"
                  capabilities
                  :test #'string=))
      (is (not (member "engine_forkchoiceUpdatedV3"
                       capabilities
                       :test #'string=)))
      (is (not (member "engine_forkchoiceUpdatedV4"
                       capabilities
                       :test #'string=)))
      (is (member "engine_getPayloadV1" capabilities :test #'string=))
      (is (member "engine_getPayloadV2" capabilities :test #'string=))
      (is (not (member "engine_getPayloadV3"
                       capabilities
                       :test #'string=)))
      (is (not (member "engine_getPayloadV4"
                       capabilities
                       :test #'string=)))
      (is (not (member "engine_getPayloadV5"
                       capabilities
                       :test #'string=)))
      (is (not (member "engine_getPayloadV6"
                       capabilities
                       :test #'string=)))
      (is (member "engine_getPayloadBodiesByHashV1"
                  capabilities
                  :test #'string=))
      (is (not (member "engine_getPayloadBodiesByHashV2"
                       capabilities
                       :test #'string=)))
      (is (member "engine_getPayloadBodiesByRangeV1"
                  capabilities
                  :test #'string=))
      (is (not (member "engine_getPayloadBodiesByRangeV2"
                       capabilities
                       :test #'string=)))
      (is (not (member "engine_getBlobsV1" capabilities :test #'string=)))
      (is (not (member "engine_getBlobsV2" capabilities :test #'string=)))
      (is (not (member "engine_getBlobsV3" capabilities :test #'string=)))
      (is (member "engine_getClientVersionV1" capabilities :test #'string=))
      (is (member "engine_exchangeTransitionConfigurationV1"
                  capabilities
                  :test #'string=))
      (is (not (member "engine_exchangeCapabilities"
                       capabilities
                       :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (response (parse-json
                      (engine-rpc-handle-request-json
                       "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}"
                       store
                       config)))
           (capabilities (field response "result")))
      (is (= 14 (field response "id")))
      (is (not (field response "error")))
      (is (member "engine_newPayloadV1" capabilities :test #'string=))
      (is (member "engine_forkchoiceUpdatedV1" capabilities :test #'string=)))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (response (parse-json
                      (engine-rpc-handle-request-json
                       "{\"jsonrpc\":\"2.0\",\"id\":15,\"method\":\"engine_getPayloadBodiesByRangeV2\",\"params\":[\"0x1\",\"0x1\"]}"
                       store
                       config
                       :allowed-method-p #'engine-rpc-engine-method-p)))
           (error (field response "error")))
      (is (= 15 (field response "id")))
      (is error)
      (is (= -32601 (field error "code")))
      (is (string= "Method not found" (field error "message")))
      (is (not (field response "result"))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (response (parse-json
                      (engine-rpc-handle-request-json
                       "{\"jsonrpc\":\"2.0\",\"id\":17,\"method\":\"engine_getBlobsV1\",\"params\":[[\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"]]}"
                       store
                       config
                       :allowed-method-p #'engine-rpc-engine-method-p)))
           (error (field response "error")))
      (is (= 17 (field response "id")))
      (is error)
      (is (= -32601 (field error "code")))
      (is (string= "Method not found" (field error "message")))
      (is (not (field response "result"))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (response (parse-json
                      (engine-rpc-handle-request-json
                       "{\"jsonrpc\":\"2.0\",\"id\":18,\"method\":\"engine_getBlobsV2\",\"params\":[[\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"]]}"
                       store
                       config
                       :allowed-method-p #'engine-rpc-engine-method-p)))
           (error (field response "error")))
      (is (= 18 (field response "id")))
      (is error)
      (is (= -32601 (field error "code")))
      (is (string= "Method not found" (field error "message")))
      (is (not (field response "result"))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (response (parse-json
                      (engine-rpc-handle-request-json
                       "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"engine_getPayloadBodiesByHashV2\",\"params\":[[\"0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"]]}"
                       store
                       config
                       :allowed-method-p #'engine-rpc-engine-method-p)))
           (error (field response "error")))
      (is (= 16 (field response "id")))
      (is error)
      (is (= -32601 (field error "code")))
      (is (string= "Method not found" (field error "message")))
      (is (not (field response "result"))))
    (let ((old-point-verifier ethereum-lisp.core:*kzg-point-proof-verifier*)
          (old-blob-verifier ethereum-lisp.core:*kzg-blob-proof-verifier*))
      (unwind-protect
           (progn
             (setf ethereum-lisp.core:*kzg-point-proof-verifier*
                   (lambda (commitment z y proof)
                     (declare (ignore commitment z y proof))
                     t)
                   ethereum-lisp.core:*kzg-blob-proof-verifier*
                   (lambda (blob commitment proof)
                     (declare (ignore blob commitment proof))
                     t))
             (let* ((store (make-engine-payload-memory-store))
                    (config (make-chain-config))
                    (request-json
                      "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"engine_exchangeCapabilities\",\"params\":[[\"engine_newPayloadV1\"]]}")
                    (response
                      (parse-json
                       (engine-rpc-handle-request-json
                        request-json store config)))
                    (capabilities (field response "result")))
               (is (member "engine_newPayloadV3" capabilities :test #'string=))
               (is (member "engine_newPayloadV5" capabilities :test #'string=))
               (is (member "engine_forkchoiceUpdatedV4"
                           capabilities
                           :test #'string=))
               (is (member "engine_getPayloadV6" capabilities :test #'string=))
               (is (member "engine_getPayloadBodiesByHashV2"
                           capabilities
                           :test #'string=))
               (is (member "engine_getPayloadBodiesByRangeV2"
                           capabilities
                           :test #'string=))
               (is (member "engine_getBlobsV1" capabilities :test #'string=))
               (is (member "engine_getBlobsV2" capabilities :test #'string=))
               (is (member "engine_getBlobsV3" capabilities :test #'string=))))
        (setf ethereum-lisp.core:*kzg-point-proof-verifier* old-point-verifier
              ethereum-lisp.core:*kzg-blob-proof-verifier* old-blob-verifier)))
    (let* ((response (parse-json
                      (engine-rpc-handle-request-json
                       "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"engine_exchangeCapabilities\",\"params\":[7]}"
                       (make-engine-payload-memory-store)
                       (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response (parse-json
                      (engine-rpc-handle-request-json
                       "{\"jsonrpc\":\"2.0\",\"id\":15,\"method\":\"engine_exchangeCapabilities\",\"params\":[[7]]}"
                       (make-engine-payload-memory-store)
                       (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))
    (let* ((response (parse-json
                      (engine-rpc-handle-request-json
                       "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"engine_exchangeCapabilities\",\"params\":[\"\"]}"
                       (make-engine-payload-memory-store)
                       (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))))

(deftest engine-rpc-get-client-version-returns-local-identity
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((request-json
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":13,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (response
             (parse-json
              (engine-rpc-handle-request-json
               request-json
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (versions (field response "result"))
           (local (first versions)))
      (is (= 13 (field response "id")))
      (is (= 1 (length versions)))
      (is (string= "CL" (field local "code")))
      (is (string= "ethereum-lisp" (field local "name")))
      (is (string= "0.1.0" (field local "version")))
      (is (string= "0x00000000" (field local "commit"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"engine_getClientVersionV1\",\"params\":[7]}"
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))))

(deftest engine-rpc-exchange-transition-configuration-returns-local-config
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((terminal-block-hash
             (hash32-from-hex
              "0x1111111111111111111111111111111111111111111111111111111111111111"))
           (config (make-chain-config
                    :terminal-total-difficulty 12345
                    :terminal-block-hash terminal-block-hash
                    :terminal-block-number 66))
           (request-json
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":15,"
              "\"method\":\"engine_exchangeTransitionConfigurationV1\","
              "\"params\":[{\"terminalTotalDifficulty\":\"0x3039\","
              "\"terminalBlockHash\":\"0x1111111111111111111111111111111111111111111111111111111111111111\","
              "\"terminalBlockNumber\":\"0x42\"}]}"))
           (response
             (parse-json
              (engine-rpc-handle-request-json
               request-json
               (make-engine-payload-memory-store)
               config)))
           (result (field response "result")))
      (is (= 15 (field response "id")))
      (is (string= "0x3039" (field result "terminalTotalDifficulty")))
      (is (string= (hash32-to-hex terminal-block-hash)
                   (field result "terminalBlockHash")))
      (is (string= "0x42" (field result "terminalBlockNumber"))))
    (let* ((terminal-block-hash
             (hash32-from-hex
              "0x1111111111111111111111111111111111111111111111111111111111111111"))
           (config (make-chain-config
                    :terminal-total-difficulty 12345
                    :terminal-block-hash terminal-block-hash
                    :terminal-block-number 66))
           (response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":16,"
                "\"method\":\"engine_exchangeTransitionConfigurationV1\","
                "\"params\":[{\"terminalTotalDifficulty\":\"0x3039\","
                "\"terminalBlockHash\":\"0x1111111111111111111111111111111111111111111111111111111111111111\","
                "\"terminalBlockNumber\":\"0x43\"}]}")
               (make-engine-payload-memory-store)
               config)))
           (result (field response "result")))
      (is (= 16 (field response "id")))
      (is (string= "0x3039" (field result "terminalTotalDifficulty")))
      (is (string= (hash32-to-hex terminal-block-hash)
                   (field result "terminalBlockHash")))
      (is (string= "0x42" (field result "terminalBlockNumber"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":17,"
                "\"method\":\"engine_exchangeTransitionConfigurationV1\","
                "\"params\":[{\"terminalTotalDifficulty\":\"0x303a\","
                "\"terminalBlockHash\":\"0x1111111111111111111111111111111111111111111111111111111111111111\","
                "\"terminalBlockNumber\":\"0x42\"}]}")
               (make-engine-payload-memory-store)
               (make-chain-config
                :terminal-total-difficulty 12345
                :terminal-block-hash
                (hash32-from-hex
                 "0x1111111111111111111111111111111111111111111111111111111111111111")
                :terminal-block-number 66))))
           (error (field response "error")))
      (is (= -32602 (field error "code")))
      (is (search "terminalTotalDifficulty mismatch"
                  (field error "message"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":18,"
                "\"method\":\"engine_exchangeTransitionConfigurationV1\","
                "\"params\":[{\"terminalTotalDifficulty\":\"0x3039\","
                "\"terminalBlockHash\":\"0x2222222222222222222222222222222222222222222222222222222222222222\","
                "\"terminalBlockNumber\":\"0x42\"}]}")
               (make-engine-payload-memory-store)
               (make-chain-config
                :terminal-total-difficulty 12345
                :terminal-block-hash
                (hash32-from-hex
                 "0x1111111111111111111111111111111111111111111111111111111111111111")
                :terminal-block-number 66))))
           (error (field response "error")))
      (is (= -32602 (field error "code")))
      (is (search "terminalBlockHash mismatch"
                  (field error "message"))))
    (let* ((response
             (parse-json
              (engine-rpc-handle-request-json
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":19,"
                "\"method\":\"engine_exchangeTransitionConfigurationV1\","
                "\"params\":[{\"terminalTotalDifficulty\":\"bad\"}]}")
               (make-engine-payload-memory-store)
               (make-chain-config))))
           (error (field response "error")))
      (is (= -32602 (field error "code"))))))

