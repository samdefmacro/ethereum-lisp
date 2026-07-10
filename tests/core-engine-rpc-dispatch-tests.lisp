(in-package #:ethereum-lisp.test)

(deftest json-rpc-protocol-package-boundary
  (let ((protocol (find-package '#:ethereum-lisp.json-rpc))
        (json (find-package '#:ethereum-lisp.json))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list protocol))))
    (is (member json (package-use-list protocol)))
    (dolist (name '("JSON-RPC-RESPONSE"
                    "JSON-RPC-INVALID-REQUEST-RESPONSE"
                    "JSON-RPC-REQUEST-VALID-P"))
      (multiple-value-bind (protocol-symbol protocol-status)
          (find-symbol name protocol)
        (multiple-value-bind (core-symbol core-status)
            (find-symbol name core)
          (is (eq :external protocol-status))
          (is (eq :inherited core-status))
          (is (eq protocol-symbol core-symbol)))))
    (multiple-value-bind (symbol status)
        (find-symbol "ENGINE-RPC-ENGINE-METHOD-P" protocol)
      (is (null symbol))
      (is (null status)))))

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
