(in-package #:ethereum-lisp.test)

(deftest state-db-from-genesis-json-applies-alloc
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"nonce\":\"2\","
                "\"code\":\"0x60016000\","
                "\"storage\":{"
                "\"0x0000000000000000000000000000000000000000000000000000000000000007\":\"0x2a\""
                "}}}}"))
         (state (state-db-from-genesis-json-string json))
         (address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000007"))
         (account (state-db-get-account state address)))
    (is account)
    (is (= 16 (state-account-balance account)))
    (is (= 2 (state-account-nonce account)))
    (is (string= "0x60016000" (bytes-to-hex (state-db-get-code state address))))
    (is (= 42 (state-db-get-storage state address slot)))
    (is (string= (state-db-root-hex state) (state-db-root-hex state)))))

(deftest state-db-from-genesis-json-applies-short-storage-hex
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"1\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (state (state-db-from-genesis-json-string json))
         (address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000007")))
    (is (= 42 (state-db-get-storage state address slot)))))

(deftest genesis-state-root-from-json-matches-state-db-root
  (let* ((json (concatenate
                'string
                "{\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"nonce\":\"2\","
                "\"code\":\"0x60016000\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (state (state-db-from-genesis-json-string json)))
    (is (string= (state-db-root-hex state)
                 (hash32-to-hex
                  (genesis-state-root-from-genesis-json-string json))))))

(deftest validate-genesis-json-state-root-compares-expected-root
  (let* ((alloc-json (concatenate
                      'string
                      "\"alloc\":{"
                      "\"0x0000000000000000000000000000000000000001\":{"
                      "\"balance\":\"0x10\","
                      "\"storage\":{\"0x07\":\"0x2a\"}"
                      "}}"))
         (computed-root
           (genesis-state-root-from-genesis-json-string
            (format nil "{~A}" alloc-json)))
         (valid-json
           (format nil "{~A,\"stateRoot\":\"~A\"}"
                   alloc-json (hash32-to-hex computed-root))))
    (is (validate-genesis-json-state-root valid-json))
    (signals block-validation-error
      (validate-genesis-json-state-root
       (format nil "{~A,\"stateRoot\":\"~A\"}"
               alloc-json (hash32-to-hex (zero-hash32)))))))

(deftest genesis-header-from-state-genesis-json-uses-computed-root
  (let* ((json (concatenate
                'string
                "{\"config\":{\"londonBlock\":0},"
                "\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (computed-root (genesis-state-root-from-genesis-json-string json))
         (header (genesis-header-from-state-genesis-json-string json)))
    (is (string= (hash32-to-hex computed-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (= +initial-base-fee+ (block-header-base-fee-per-gas header)))))

(deftest genesis-header-from-state-genesis-json-rejects-root-mismatch
  (signals block-validation-error
    (genesis-header-from-state-genesis-json-string
     (concatenate
      'string
      "{\"stateRoot\":\"0x0000000000000000000000000000000000000000000000000000000000000000\","
      "\"alloc\":{\"0x0000000000000000000000000000000000000001\":"
      "{\"balance\":\"0x10\"}}}"))))

(deftest genesis-block-from-state-genesis-json-uses-computed-root
  (let* ((json (concatenate
                'string
                "{\"config\":{\"londonBlock\":0,\"shanghaiTime\":0},"
                "\"alloc\":{"
                "\"0x0000000000000000000000000000000000000001\":{"
                "\"balance\":\"0x10\","
                "\"storage\":{\"0x07\":\"0x2a\"}"
                "}}}"))
         (computed-root (genesis-state-root-from-genesis-json-string json))
         (block (genesis-block-from-state-genesis-json-string json))
         (header (block-header block)))
    (is (string= (hash32-to-hex computed-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (block-withdrawals-present-p block))
    (is (null (block-withdrawals block)))))

(deftest phase-a-shanghai-genesis-fixture-roots
  (let* ((json (fixture-file-string +phase-a-shanghai-genesis-fixture-path+))
         (fixture (parse-json json))
         (expected-root (genesis-expected-state-root-from-genesis-json-string json))
         (computed-root (genesis-state-root-from-genesis-json-string json))
         (state (state-db-from-genesis-json-string json))
         (block (genesis-block-from-state-genesis-json-string json))
         (header (block-header block))
         (sender (address-from-hex "0x0000000000000000000000000000000000001001"))
         (contract (address-from-hex "0x0000000000000000000000000000000000001002"))
         (slot-0 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000000"))
         (slot-1 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001")))
    (validate-phase-a-shanghai-genesis-fixture-shape fixture)
    (is (validate-genesis-json-state-root json))
    (is (string= (hash32-to-hex expected-root)
                 (hash32-to-hex computed-root)))
    (is (string= (hash32-to-hex computed-root)
                 (state-db-root-hex state)))
    (is (string= (hash32-to-hex computed-root)
                 (hash32-to-hex (block-header-state-root header))))
    (is (block-withdrawals-present-p block))
    (is (null (block-withdrawals block)))
    (is (= 1 (state-account-nonce (state-db-get-account state sender))))
    (is (= 1000000000000000000
           (state-account-balance (state-db-get-account state sender))))
    (is (string= "0x7efcce47028dabcb0d42f3a7eda8820bf6f7f4e618398c2547d52f703cafb073"
                 (hash32-to-hex (state-db-get-code-hash state contract))))
    (is (= 42 (state-db-get-storage state contract slot-0)))
    (is (= 0 (state-db-get-storage state contract slot-1)))
    (is (string= "0x81d1fa699f807735499cf6f7df860797cf66f6a66b565cfcda3fae3521eb6861"
                 (hash32-to-hex
                  (state-db-get-storage-root state contract))))))

