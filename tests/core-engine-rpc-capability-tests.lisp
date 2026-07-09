(in-package #:ethereum-lisp.test)

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

