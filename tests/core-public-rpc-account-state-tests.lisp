(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-balance
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x00000000000000000000000000000000000000aa"))
           (empty-address
             (address-from-hex "0x00000000000000000000000000000000000000bb"))
           (state-block
             (make-block
              :header (make-block-header :number 20
                                         :timestamp 200
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 21
                                         :timestamp 210
                                         :gas-limit 30000000)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-balance
       store (block-hash state-block) address 12345)
      (engine-payload-store-put-block store missing-state-block)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":73,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x14\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":74,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\""
                  state-block-hash-hex "\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":75,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x14\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":76,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x15\"]}")
                 store
                 config)))
             (missing-block-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":77,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x63\"]}")
                 store
                 config)))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":78,\"method\":\"eth_getBalance\",\"params\":[\"0x1234\",\"0x14\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":79,"
                  "\"method\":\"eth_getBalance\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (missing-state-error (field missing-state-response "error"))
             (missing-block-error (field missing-block-response "error"))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 12345)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 12345)
                     (field hash-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getBalance state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field missing-block-error "code")))
        (is (string= "eth_getBalance block is not available"
                     (field missing-block-error "message")))
        (is (= -32602 (field invalid-address-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-transaction-count
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (empty-address
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           (pending-transaction
           (make-legacy-transaction
              :nonce 7
              :gas-price 11
              :gas-limit 21100
              :to empty-address
              :value 13
              :data #(1 2 3)
              :v 27
              :r 1
              :s 2))
           (address
             (or (transaction-sender pending-transaction) (zero-address)))
           (state-block
             (make-block
              :header (make-block-header :number 22
                                         :timestamp 220
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 23
                                         :timestamp 230
                                         :gas-limit 30000000)))
           (raw-pending-transaction
             (bytes-to-hex (transaction-encoding pending-transaction)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-nonce
       store (block-hash state-block) address 7)
      (engine-payload-store-put-account-balance
       store (block-hash state-block) address 1000000)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":80,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x16\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":81,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address) "\",\""
                  state-block-hash-hex "\"]}")
                 store
                 config)))
             (send-pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                 "{\"jsonrpc\":\"2.0\",\"id\":87,"
                  "\"method\":\"eth_sendRawTransaction\","
                  "\"params\":[\"" raw-pending-transaction "\"]}")
                 store
                 config
                 :allow-unprotected-transactions-p t)))
             (pending-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":86,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"pending\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":82,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x16\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (progn
                  (engine-payload-store-put-block store missing-state-block)
                  (engine-rpc-handle-request-json
                   (concatenate
                    'string
                    "{\"jsonrpc\":\"2.0\",\"id\":83,"
                    "\"method\":\"eth_getTransactionCount\","
                    "\"params\":[\"" (address-to-hex address) "\",\"0x17\"]}")
                   store
                   config))))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":84,\"method\":\"eth_getTransactionCount\",\"params\":[\"0x1234\",\"0x16\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":85,"
                  "\"method\":\"eth_getTransactionCount\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (missing-state-error (field missing-state-response "error"))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= (quantity-to-hex 7)
                     (field number-response "result")))
        (is (string= (quantity-to-hex 7)
                     (field hash-response "result")))
        (is (string= (hash32-to-hex (transaction-hash pending-transaction))
                     (field send-pending-response "result")))
        (is (string= (quantity-to-hex 8)
                     (field pending-response "result")))
        (is (string= (quantity-to-hex 0)
                     (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getTransactionCount state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-address-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-code
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x00000000000000000000000000000000000000ee"))
           (empty-address
             (address-from-hex "0x00000000000000000000000000000000000000ff"))
           (state-block
             (make-block
              :header (make-block-header :number 24
                                         :timestamp 240
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 25
                                         :timestamp 250
                                         :gas-limit 30000000)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-code
       store (block-hash state-block) address #(96 1 96 0))
      (engine-payload-store-put-block store missing-state-block)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":86,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x18\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":87,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\",\""
                  state-block-hash-hex "\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":88,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x18\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":89,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\",\"0x19\"]}")
                 store
                 config)))
             (invalid-address-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":90,\"method\":\"eth_getCode\",\"params\":[\"0x1234\",\"0x18\"]}"
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":91,"
                  "\"method\":\"eth_getCode\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (missing-state-error (field missing-state-response "error"))
             (invalid-address-error (field invalid-address-response "error"))
             (invalid-params-error (field invalid-params-response "error")))
        (is (string= "0x60016000"
                     (field number-response "result")))
        (is (string= "0x60016000"
                     (field hash-response "result")))
        (is (string= "0x"
                     (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getCode state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-address-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

(deftest eth-rpc-get-storage-at
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000101"))
           (empty-address
             (address-from-hex "0x0000000000000000000000000000000000000102"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000007"))
           (state-block
             (make-block
              :header (make-block-header :number 26
                                         :timestamp 260
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 27
                                         :timestamp 270
                                         :gas-limit 30000000)))
           (state-block-hash-hex (hash32-to-hex (block-hash state-block)))
           (config (make-chain-config)))
      (engine-payload-store-put-block store state-block)
      (engine-payload-store-put-account-storage
       store (block-hash state-block) address slot #x2a)
      (engine-payload-store-put-block store missing-state-block)
      (let* ((number-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":92,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\",\"0x1a\"]}")
                 store
                 config)))
             (hash-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":93,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"7\",\"" state-block-hash-hex "\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":94,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",\"0x7\",\"0x1a\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":95,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\",\"0x1b\"]}")
                 store
                 config)))
             (invalid-slot-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":96,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x"
                  "111111111111111111111111111111111111111111111111111111111111111111"
                  "\",\"0x1a\"]}")
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":97,"
                  "\"method\":\"eth_getStorageAt\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\"]}")
                 store
                 config)))
             (missing-state-error (field missing-state-response "error"))
             (invalid-slot-error (field invalid-slot-response "error"))
             (invalid-params-error (field invalid-params-response "error"))
             (expected-word
               "0x000000000000000000000000000000000000000000000000000000000000002a")
             (zero-word
               "0x0000000000000000000000000000000000000000000000000000000000000000"))
        (is (string= expected-word (field number-response "result")))
        (is (string= expected-word (field hash-response "result")))
        (is (string= zero-word (field empty-account-response "result")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getStorageAt state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-slot-error "code")))
        (is (= -32602 (field invalid-params-error "code")))))))

