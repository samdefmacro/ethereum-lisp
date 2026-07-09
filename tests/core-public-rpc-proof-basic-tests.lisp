(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-proof
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (json-string-list (values)
             (with-output-to-string (stream)
               (write-char #\[ stream)
               (loop for value in values
                     for first-p = t then nil
                     unless first-p do (write-char #\, stream)
                     do (format stream "\"~A\"" value))
               (write-char #\] stream)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof)))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000103"))
           (empty-address
             (address-from-hex "0x0000000000000000000000000000000000000104"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000007"))
           (missing-slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000008"))
           (state (make-state-db))
           (state-block
             (make-block
              :header (make-block-header :number 28
                                         :timestamp 280
                                         :gas-limit 30000000)))
           (missing-state-block
             (make-block
              :header (make-block-header :number 29
                                         :timestamp 290
                                         :gas-limit 30000000)))
           (config (make-chain-config)))
      (state-db-set-account state address
                            (make-state-account :nonce 3 :balance 1000))
      (state-db-set-code state address #(96 1 96 0))
      (state-db-set-storage state address slot #x2a)
      (state-db-set-account state address
                            (make-state-account :nonce 3 :balance 1000))
      (setf (block-header-state-root (block-header state-block))
            (state-db-root state))
      (chain-store-put-block store state-block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash state-block) state)
      (engine-payload-store-put-block store missing-state-block)
      (let* ((proof-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":98,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",[\"0x7\",\""
                  (hash32-to-hex missing-slot)
                  "\",\"7\",\""
                  (subseq (hash32-to-hex slot) 2)
                  "\",\"0X7\"],\"0x1c\"]}")
                 store
                 config)))
             (empty-account-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":99,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex empty-address)
                  "\",[\"0x7\"],\"0x1c\"]}")
                 store
                 config)))
             (missing-state-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":100,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",[\"0x7\"],\"0x1d\"]}")
                 store
                 config)))
             (invalid-storage-keys-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":101,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\",\"0x7\",\"0x1c\"]}")
                 store
                 config)))
             (invalid-params-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":102,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address) "\"]}")
                 store
                 config)))
             (too-many-storage-keys-response
               (parse-json
                (engine-rpc-handle-request-json
                 (concatenate
                  'string
                  "{\"jsonrpc\":\"2.0\",\"id\":103,"
                  "\"method\":\"eth_getProof\","
                  "\"params\":[\"" (address-to-hex address)
                  "\","
                  (json-string-list
                   (loop repeat (1+ ethereum-lisp.core::+eth-get-proof-max-storage-keys+)
                         collect "0x0"))
                  ",\"0x1c\"]}")
                 store
                 config)))
             (proof (field proof-response "result"))
             (storage-proofs (field proof "storageProof"))
             (first-storage (first storage-proofs))
             (second-storage (second storage-proofs))
             (third-storage (third storage-proofs))
             (fourth-storage (fourth storage-proofs))
             (fifth-storage (fifth storage-proofs))
             (empty-proof (field empty-account-response "result"))
             (expected-proof
               (state-db-get-proof
                state
                address
                (list slot missing-slot slot slot slot)))
             (missing-state-error (field missing-state-response "error"))
             (invalid-storage-keys-error
               (field invalid-storage-keys-response "error"))
             (invalid-params-error (field invalid-params-response "error"))
             (too-many-storage-keys-error
               (field too-many-storage-keys-response "error")))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1000)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 3)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex (keccak-256-hash #(96 1 96 0)))
                     (field proof "codeHash")))
        (is (listp (field proof "accountProof")))
        (is (every #'stringp (field proof "accountProof")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (= 5 (length storage-proofs)))
        (is (string= (quantity-to-hex 7) (field first-storage "key")))
        (is (string= "0x2a" (field first-storage "value")))
        (is (every #'stringp (field first-storage "proof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof
                     (first (state-proof-result-storage-proofs expected-proof))))
                   (field first-storage "proof")))
        (is (string= (hash32-to-hex missing-slot)
                     (field second-storage "key")))
        (is (string= (quantity-to-hex 0)
                     (field second-storage "value")))
        (is (every #'stringp (field second-storage "proof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof
                     (second (state-proof-result-storage-proofs expected-proof))))
                   (field second-storage "proof")))
        (is (string= (quantity-to-hex 7) (field third-storage "key")))
        (is (string= "0x2a" (field third-storage "value")))
        (is (string= (hash32-to-hex slot) (field fourth-storage "key")))
        (is (string= "0x2a" (field fourth-storage "value")))
        (is (every #'stringp (field fourth-storage "proof")))
        (is (string= (quantity-to-hex 7) (field fifth-storage "key")))
        (is (string= "0x2a" (field fifth-storage "value")))
        (is (string= (address-to-hex empty-address)
                     (field empty-proof "address")))
        (is (string= (quantity-to-hex 0)
                     (field empty-proof "balance")))
        (is (string= (hash32-to-hex +empty-code-hash+)
                     (field empty-proof "codeHash")))
        (is (= -32602 (field missing-state-error "code")))
        (is (string= "eth_getProof state is not available"
                     (field missing-state-error "message")))
        (is (= -32602 (field invalid-storage-keys-error "code")))
        (is (= -32602 (field invalid-params-error "code")))
        (is (= -32602 (field too-many-storage-keys-error "code")))))))

(deftest eth-rpc-get-proof-geth-secure-account-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (proof-request (address block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 104)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               nil
                               (hash32-to-hex (block-hash block)))))))
    (let* ((store (make-engine-payload-memory-store))
           (state (make-state-db))
           (cases
             '(("0x0194fdc2fa2ffcc041d3ff12045b73c86e4ff95f"
                "0xb79ef856f65f67cf"
                "0x2077ccce0d8fc159")
               ("0xf662a5eee82abdf44a2d0b75fb180daf48a79ee0"
                "0xe242cf3c6a9f4a578bcb9ef2d4a65314768d6d299761ea9e4f"
                "0x64bed6e2edf354c3")
               ("0xb10d394651850fd4a178892ee285ece151145578"
                "0x20efcd6cea84b6925e607be06371"
                "0x1ec678fcc3aea65a"))))
      (add-account state
                   "0x0194fdc2fa2ffcc041d3ff12045b73c86e4ff95f"
                   2339563716805116249
                   13231285807645419471)
      (add-account state
                   "0xf662a5eee82abdf44a2d0b75fb180daf48a79ee0"
                   7259475919510918339
                   1420263156754097894072208833565313120560341020854497370086991)
      (add-account state
                   "0xb10d394651850fd4a178892ee285ece151145578"
                   2217592893536642650
                   668036214256246407260665125299057)
      (let* ((block (commit-state-block store state 30 300))
             (config (make-chain-config)))
        (is (string= "0x65e27b7b7b43826149e6b5674be3ff0f107ff6e988d20c1be165a172eeef399d"
                     (state-db-root-hex state)))
        (dolist (case cases)
          (destructuring-bind (address-hex balance nonce) case
            (let* ((address (address-from-hex address-hex))
                   (response (engine-rpc-handle-request
                              (proof-request address block)
                              store
                              config))
                   (proof (field response "result"))
                   (expected-proof (state-db-get-proof state address nil))
                   (decoded-proof (state-proof-result-from-rpc-object proof)))
              (is (equal (state-proof-result-rpc-object expected-proof)
                         proof))
              (is (string= (address-to-hex address)
                           (field proof "address")))
              (is (string= balance
                           (field proof "balance")))
              (is (string= nonce
                           (field proof "nonce")))
              (is (string= (hash32-to-hex +empty-code-hash+)
                           (field proof "codeHash")))
              (is (string= (hash32-to-hex +empty-trie-hash+)
                           (field proof "storageHash")))
              (is (= 2 (length (field proof "accountProof"))))
              (is (null (field proof "storageProof")))
              (is (state-db-verify-proof (state-db-root state)
                                         decoded-proof)))))))))

(deftest eth-rpc-get-proof-missing-clear-nontrivial-state-tries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (commit-state-block (store state number timestamp)
             (let ((block
                     (make-block
                      :header (make-block-header
                               :number number
                               :timestamp timestamp
                               :gas-limit 30000000
                               :state-root (state-db-root state)))))
               (chain-store-put-block store block :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block))
           (assert-missing-clear-proof (store state block missing)
             (let* ((response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":109,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex missing)
                         "\",[],\"" (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state missing nil)))
               (is (string= (address-to-hex missing)
                            (field proof "address")))
               (is (string= (quantity-to-hex 0)
                            (field proof "balance")))
               (is (string= (quantity-to-hex 0)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (null (field proof "storageProof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof"))))))
    (let* ((store (make-engine-payload-memory-store))
           (missing (address-from-hex
                     "0x00000000000000000000000000000000000002ff"))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-clear-account extension-state missing)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-clear-account branch-extension-state missing)
      (assert-missing-clear-proof
       store
       extension-state
       (commit-state-block store extension-state 33 330)
       missing)
      (assert-missing-clear-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 34 340)
       missing))))

