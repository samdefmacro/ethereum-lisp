(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-proof-state-trie-delete-collapse
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (add-code-storage (state address)
             (state-db-set-storage
              state
              address
              (hash32-from-hex
               "0x000000000000000000000000000000000000000000000000000000000000002a")
              42)
             (state-db-set-code state address #(96 1 96 0)))
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
           (assert-delete-collapse-proof
               (store state block address expected-root expected-nodes
                expected-balance expected-nonce)
             (let* ((response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":123,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex address)
                         "\",[],\"" (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state address nil))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= expected-root (state-db-root-hex state)))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex expected-nonce)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (null (field proof "storageProof")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (branch-survivor
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (branch-deleted
             (address-from-hex "0x0000000000000000000000000000000000000211"))
           (extension-survivor
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (extension-deleted
             (address-from-hex "0x0000000000000000000000000000000000000225"))
           (branch-extension-deleted
             (address-from-hex "0x0000000000000000000000000000000000000203"))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (add-code-storage branch-state branch-deleted)
      (state-db-clear-account branch-state branch-deleted)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-code-storage extension-state extension-deleted)
      (state-db-clear-account extension-state extension-deleted)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (add-code-storage branch-extension-state branch-extension-deleted)
      (state-db-clear-account branch-extension-state branch-extension-deleted)
      (let ((branch-block (commit-state-block store branch-state 50 500))
            (extension-block (commit-state-block store extension-state 51 510))
            (branch-extension-block
              (commit-state-block store branch-extension-state 52 520)))
        (assert-delete-collapse-proof
         store
         branch-state
         branch-block
         branch-survivor
         "0x18742ec02ab527594bc83d163360c5b677ca92e37b5a0d5673920a895645b8a1"
         1
         100
         1)
        (assert-delete-collapse-proof
         store
         branch-state
         branch-block
         branch-deleted
         "0x18742ec02ab527594bc83d163360c5b677ca92e37b5a0d5673920a895645b8a1"
         1
         0
         0)
        (assert-delete-collapse-proof
         store
         extension-state
         extension-block
         extension-survivor
         "0x006c6cf2120be53e089f44cb328653de92ca2a9a4970a6a9137148b829c47509"
         1
         100
         1)
        (assert-delete-collapse-proof
         store
         extension-state
         extension-block
         extension-deleted
         "0x006c6cf2120be53e089f44cb328653de92ca2a9a4970a6a9137148b829c47509"
         1
         0
         0)
        (assert-delete-collapse-proof
         store
         branch-extension-state
         branch-extension-block
         extension-survivor
         "0x107571af3beeb3b5f3d1b49b593066ac344ab7e98f657ee27670315fcbde6509"
         3
         100
         1)
        (assert-delete-collapse-proof
         store
         branch-extension-state
         branch-extension-block
         branch-extension-deleted
         "0x107571af3beeb3b5f3d1b49b593066ac344ab7e98f657ee27670315fcbde6509"
         1
         0
         0)))))

(deftest eth-rpc-get-proof-balance-add-nontrivial-state-tries
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
           (assert-balance-add-proof
             (store state block target expected-balance expected-nodes)
             (let* ((response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":110,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex target)
                         "\",[],\"" (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state target nil))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= (address-to-hex target)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex 1)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (null (field proof "storageProof")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof))))
           (assert-balance-add-zero-missing-proof
             (store state block target expected-nodes)
             (let* ((storage-key
                      "0x0000000000000000000000000000000000000000000000000000000000000001")
                    (response
                      (parse-json
                       (engine-rpc-handle-request-json
                        (concatenate
                         'string
                         "{\"jsonrpc\":\"2.0\",\"id\":111,"
                         "\"method\":\"eth_getProof\","
                         "\"params\":[\"" (address-to-hex target)
                         "\",[\"" storage-key "\"],\""
                         (hash32-to-hex (block-hash block))
                         "\"]}")
                        store
                        (make-chain-config))))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof
                       state
                       target
                       (list (hash32-from-hex storage-key))))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof))
                    (storage-proof
                      (first (field proof "storageProof"))))
               (is (string= (address-to-hex target)
                            (field proof "address")))
               (is (string= "0x0" (field proof "balance")))
               (is (string= "0x0" (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (string= storage-key (field storage-proof "key")))
               (is (string= "0x0" (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (branch-target
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-target
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (missing-target
             (address-from-hex "0x00000000000000000000000000000000000002ff"))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db))
           (branch-existing-zero-state (make-state-db))
           (extension-existing-zero-state (make-state-db))
           (branch-extension-existing-zero-state (make-state-db))
           (branch-zero-state (make-state-db))
           (extension-zero-state (make-state-db))
           (branch-extension-zero-state (make-state-db)))
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (state-db-add-balance branch-state branch-target 300)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-add-balance extension-state extension-target 300)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-add-balance branch-extension-state extension-target 300)
      (add-account branch-existing-zero-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-existing-zero-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (state-db-add-balance branch-existing-zero-state branch-target 0)
      (add-account extension-existing-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-existing-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-add-balance extension-existing-zero-state extension-target 0)
      (add-account branch-extension-existing-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-existing-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-existing-zero-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-add-balance branch-extension-existing-zero-state
                            extension-target
                            0)
      (add-account branch-zero-state
                   "0x0000000000000000000000000000000000000201"
                   1 100)
      (add-account branch-zero-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (state-db-add-balance branch-zero-state missing-target 0)
      (add-account extension-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account extension-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (state-db-add-balance extension-zero-state missing-target 0)
      (add-account branch-extension-zero-state
                   "0x0000000000000000000000000000000000000220"
                   1 100)
      (add-account branch-extension-zero-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-zero-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (state-db-add-balance branch-extension-zero-state missing-target 0)
      (assert-balance-add-proof
       store
       branch-state
       (commit-state-block store branch-state 35 350)
       branch-target
       400
       2)
      (assert-balance-add-proof
       store
       extension-state
       (commit-state-block store extension-state 36 360)
       extension-target
       400
       3)
      (assert-balance-add-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 37 370)
       extension-target
       400
       4)
      (assert-balance-add-proof
       store
       branch-existing-zero-state
       (commit-state-block store branch-existing-zero-state 38 380)
       branch-target
       100
       2)
      (assert-balance-add-proof
       store
       extension-existing-zero-state
       (commit-state-block store extension-existing-zero-state 39 390)
       extension-target
       100
       3)
      (assert-balance-add-proof
       store
       branch-extension-existing-zero-state
       (commit-state-block store branch-extension-existing-zero-state 40 400)
       extension-target
       100
       4)
      (assert-balance-add-zero-missing-proof
       store
       branch-zero-state
       (commit-state-block store branch-zero-state 41 410)
       missing-target
       2)
      (assert-balance-add-zero-missing-proof
       store
       extension-zero-state
       (commit-state-block store extension-zero-state 42 420)
       missing-target
       1)
      (assert-balance-add-zero-missing-proof
       store
       branch-extension-zero-state
       (commit-state-block store branch-extension-zero-state 43 430)
       missing-target
       2))))

(deftest eth-rpc-get-proof-value-transfer
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
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
           (proof-request (id address storage-keys block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex storage-keys)
                               (hash32-to-hex (block-hash block))))))
           (assert-transfer-proof
             (store state block address storage-keys expected-root
              expected-balance expected-nonce expected-storage-proof-count
              &key expected-account-proof-count)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 132 address storage-keys block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (expected-proof
                      (state-db-get-proof state address storage-keys))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= expected-root
                            (state-db-root-hex state)))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (quantity-to-hex expected-nonce)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex +empty-code-hash+)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (when expected-account-proof-count
                 (is (= expected-account-proof-count
                        (length (field proof "accountProof")))))
               (is (= expected-storage-proof-count
                      (length (field proof "storageProof"))))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (sender
             (address-from-hex "0x0000000000000000000000000000000000000301"))
           (recipient
             (address-from-hex "0x0000000000000000000000000000000000000302"))
           (zero-sender
             (address-from-hex "0x0000000000000000000000000000000000000303"))
           (missing-recipient
             (address-from-hex "0x0000000000000000000000000000000000000304"))
           (missing-slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           (branch-sender
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (branch-sibling
             (address-from-hex "0x0000000000000000000000000000000000000211"))
           (branch-recipient
             (address-from-hex "0x0000000000000000000000000000000000000202"))
           (extension-sender
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (extension-recipient
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-sibling
             (address-from-hex "0x0000000000000000000000000000000000000225"))
           (branch-extension-extra
             (address-from-hex "0x0000000000000000000000000000000000000203"))
           (transfer-state (make-state-db))
           (zero-transfer-state (make-state-db))
           (branch-transfer-state (make-state-db))
           (extension-transfer-state (make-state-db))
           (branch-extension-transfer-state (make-state-db)))
      (state-db-set-account
       transfer-state sender (make-state-account :nonce 1 :balance 100))
      (ethereum-lisp.state::state-db-transfer-value
       transfer-state sender recipient 37)
      (state-db-set-account
       zero-transfer-state
       zero-sender
       (make-state-account :nonce 2 :balance 100))
      (ethereum-lisp.state::state-db-transfer-value
       zero-transfer-state zero-sender missing-recipient 0)
      (state-db-set-account
       branch-transfer-state
       branch-sender
       (make-state-account :nonce 1 :balance 100))
      (state-db-set-account
       branch-transfer-state
       branch-sibling
       (make-state-account :nonce 2 :balance 200))
      (ethereum-lisp.state::state-db-transfer-value
       branch-transfer-state branch-sender branch-recipient 37)
      (state-db-set-account
       extension-transfer-state
       extension-sender
       (make-state-account :nonce 1 :balance 100))
      (state-db-set-account
       extension-transfer-state
       extension-sibling
       (make-state-account :nonce 2 :balance 200))
      (ethereum-lisp.state::state-db-transfer-value
       extension-transfer-state extension-sender extension-recipient 37)
      (state-db-set-account
       branch-extension-transfer-state
       extension-sender
       (make-state-account :nonce 1 :balance 100))
      (state-db-set-account
       branch-extension-transfer-state
       extension-sibling
       (make-state-account :nonce 2 :balance 200))
      (state-db-set-account
       branch-extension-transfer-state
       branch-extension-extra
       (make-state-account :nonce 3 :balance 300))
      (ethereum-lisp.state::state-db-transfer-value
       branch-extension-transfer-state
       extension-sender
       extension-recipient
       37)
      (let ((transfer-block
              (commit-state-block store transfer-state 44 440))
            (zero-transfer-block
              (commit-state-block store zero-transfer-state 45 450))
            (branch-transfer-block
              (commit-state-block store branch-transfer-state 46 460))
            (extension-transfer-block
              (commit-state-block store extension-transfer-state 47 470))
            (branch-extension-transfer-block
              (commit-state-block
               store branch-extension-transfer-state 48 480)))
        (assert-transfer-proof
         store
         transfer-state
         transfer-block
         sender
         nil
         "0xeb1be297ad9e87812158dcb9b646fe55dfc2e89526b65cf76bd4fe3b40c68da9"
         63
         1
         0)
        (assert-transfer-proof
         store
         transfer-state
         transfer-block
         recipient
         nil
         "0xeb1be297ad9e87812158dcb9b646fe55dfc2e89526b65cf76bd4fe3b40c68da9"
         37
         0
         0)
        (assert-transfer-proof
         store
         zero-transfer-state
         zero-transfer-block
         missing-recipient
         (list missing-slot)
         "0x600e37f427a9f42ebe6b592ff989ec26a865aa3d89c955bb78dbf53890cbeb41"
         0
         0
         1)
        (assert-transfer-proof
         store
         branch-transfer-state
         branch-transfer-block
         branch-sender
         nil
         "0x4dd8ed5858a2fce6bf433fa35e5cc54821ad964aa7a2dd979ea34336ff8b6544"
         63
         1
         0
         :expected-account-proof-count 3)
        (assert-transfer-proof
         store
         branch-transfer-state
         branch-transfer-block
         branch-recipient
         nil
         "0x4dd8ed5858a2fce6bf433fa35e5cc54821ad964aa7a2dd979ea34336ff8b6544"
         37
         0
         0
         :expected-account-proof-count 3)
        (assert-transfer-proof
         store
         extension-transfer-state
         extension-transfer-block
         extension-sender
         nil
         "0x62d868986c4260fa44341f1c75694a5180bb3caaa21efe07f7bab246f22a2aa2"
         63
         1
         0
         :expected-account-proof-count 4)
        (assert-transfer-proof
         store
         extension-transfer-state
         extension-transfer-block
         extension-recipient
         nil
         "0x62d868986c4260fa44341f1c75694a5180bb3caaa21efe07f7bab246f22a2aa2"
         37
         0
         0
         :expected-account-proof-count 3)
        (assert-transfer-proof
         store
         branch-extension-transfer-state
         branch-extension-transfer-block
         extension-sender
         nil
         "0xc86e674a6e90c03f48bc01ea942843efe0eb52fba078dbff71fa44b8c4651aa5"
         63
         1
         0
         :expected-account-proof-count 4)
        (assert-transfer-proof
         store
         branch-extension-transfer-state
         branch-extension-transfer-block
         extension-recipient
         nil
         "0xc86e674a6e90c03f48bc01ea942843efe0eb52fba078dbff71fa44b8c4651aa5"
         37
         0
         0
         :expected-account-proof-count 3)))))

