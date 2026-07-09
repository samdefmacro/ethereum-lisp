(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-proof-zero-storage-writes
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
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
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block))))))
           (assert-zero-storage-proof
               (store state block address slot expected-balance
                expected-code-hash)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 118 address slot block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proof (first (field proof "storageProof")))
                    (expected-proof
                      (state-db-get-proof state address (list slot)))
                    (expected-storage-proof
                      (first (state-proof-result-storage-proofs
                              expected-proof)))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= (address-to-hex address)
                            (field proof "address")))
               (is (string= (quantity-to-hex expected-balance)
                            (field proof "balance")))
               (is (string= (hash32-to-hex expected-code-hash)
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (= 1 (length (field proof "storageProof"))))
               (is (string= (hash32-to-hex slot)
                            (field storage-proof "key")))
               (is (string= (quantity-to-hex 0)
                            (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (proof-node-hex-list
                           (state-storage-proof-proof expected-storage-proof))
                          (field storage-proof "proof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (missing-address
             (address-from-hex "0x0000000000000000000000000000000000000402"))
           (funded-address
             (address-from-hex "0x0000000000000000000000000000000000000403"))
           (code-address
             (address-from-hex "0x0000000000000000000000000000000000000404"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000001"))
           (code #(96 1 96 0))
           (missing-state (make-state-db))
           (funded-state (make-state-db))
           (code-state (make-state-db)))
      (state-db-set-storage missing-state missing-address slot 0)
      (state-db-set-account funded-state funded-address
                            (make-state-account :balance 1))
      (state-db-set-storage funded-state funded-address slot 0)
      (state-db-set-code code-state code-address code)
      (state-db-set-storage code-state code-address slot 0)
      (assert-zero-storage-proof
       store
       missing-state
       (commit-state-block store missing-state 38 380)
       missing-address
       slot
       0
       +empty-code-hash+)
      (assert-zero-storage-proof
       store
       funded-state
       (commit-state-block store funded-state 39 390)
       funded-address
       slot
       1
       +empty-code-hash+)
      (assert-zero-storage-proof
       store
       code-state
       (commit-state-block store code-state 40 400)
       code-address
       slot
       0
       (keccak-256-hash code)))))

(deftest eth-rpc-get-proof-code-update
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
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
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block)))))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000109"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000000b"))
           (first-code #(96 1 96 0))
           (final-code #(96 2 96 3 1))
           (state (make-state-db)))
      (state-db-set-account state address (make-state-account :balance 1))
      (state-db-set-code state address first-code)
      (state-db-set-code state address final-code)
      (let* ((block (commit-state-block store state 53 530))
             (response
               (engine-rpc-handle-request
                (proof-request 124 address slot block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proof (first (field proof "storageProof")))
             (expected-proof
               (state-db-get-proof state address (list slot)))
             (expected-storage-proof
               (first (state-proof-result-storage-proofs expected-proof)))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (string= "0xa71076e81cddb7521d7345f5aa21a0b5781991a366f66861e5faca0a336798ad"
                     (state-db-root-hex state)))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 0)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex (keccak-256-hash final-code))
                     (field proof "codeHash")))
        (is (string= (hash32-to-hex +empty-trie-hash+)
                     (field proof "storageHash")))
        (is (= 1 (length (field proof "storageProof"))))
        (is (string= (hash32-to-hex slot)
                     (field storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field storage-proof "value")))
        (is (null (field storage-proof "proof")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof expected-storage-proof))
                   (field storage-proof "proof")))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-code-update-preserves-storage
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
           (proof-request (id address slots block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (mapcar #'hash32-to-hex slots)
                               (hash32-to-hex (block-hash block)))))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x000000000000000000000000000000000000010b"))
           (present-slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000002c"))
           (missing-slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000002d"))
           (first-code #(96 1 96 0))
           (final-code #(96 2 96 3 1))
           (state (make-state-db)))
      (state-db-set-account
       state address (make-state-account :nonce 1 :balance 1000))
      (state-db-set-storage state address present-slot #x2c)
      (state-db-set-code state address first-code)
      (state-db-set-code state address final-code)
      (let* ((block (commit-state-block store state 54 540))
             (slots (list present-slot missing-slot))
             (response
               (engine-rpc-handle-request
                (proof-request 126 address slots block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proofs (field proof "storageProof"))
             (present-storage-proof (first storage-proofs))
             (missing-storage-proof (second storage-proofs))
             (expected-proof (state-db-get-proof state address slots))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (string= "0xc7b8d640084dfe51710f52b73da6975f617c6c4503ec763c1e2a2eeef11b3f01"
                     (state-db-root-hex state)))
        (is (equal (state-proof-result-rpc-object expected-proof)
                   proof))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1000)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 1)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex (keccak-256-hash final-code))
                     (field proof "codeHash")))
        (is (string= "0x39b3b39f4dd43bd60944a54f2478267341aa89516ee9e8b5c9b6272b02cb0f75"
                     (field proof "storageHash")))
        (is (= 2 (length storage-proofs)))
        (is (string= (hash32-to-hex present-slot)
                     (field present-storage-proof "key")))
        (is (string= (quantity-to-hex #x2c)
                     (field present-storage-proof "value")))
        (is (= 1 (length (field present-storage-proof "proof"))))
        (is (string= (hash32-to-hex missing-slot)
                     (field missing-storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field missing-storage-proof "value")))
        (is (= 1 (length (field missing-storage-proof "proof"))))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-code-update-nontrivial-state-tries
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (set-updated-code (state address)
             (let ((target (address-from-hex address)))
               (state-db-set-code state target #(96 1 96 0))
               (state-db-set-code state target #(96 2 96 3 1))))
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
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block))))))
           (assert-code-update-proof
               (store state block target slot expected-root expected-nodes)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 125 target slot block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proof (first (field proof "storageProof")))
                    (expected-proof
                      (state-db-get-proof state target (list slot)))
                    (expected-storage-proof
                      (first (state-proof-result-storage-proofs
                              expected-proof)))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (string= expected-root
                            (state-db-root-hex state)))
               (is (string= (address-to-hex target)
                            (field proof "address")))
               (is (string= (quantity-to-hex 1000)
                            (field proof "balance")))
               (is (string= (quantity-to-hex 1)
                            (field proof "nonce")))
               (is (string= (hash32-to-hex
                             (keccak-256-hash #(96 2 96 3 1)))
                            (field proof "codeHash")))
               (is (string= (hash32-to-hex +empty-trie-hash+)
                            (field proof "storageHash")))
               (is (= expected-nodes
                      (length (field proof "accountProof"))))
               (is (= 1 (length (field proof "storageProof"))))
               (is (string= (hash32-to-hex slot)
                            (field storage-proof "key")))
               (is (string= (quantity-to-hex 0)
                            (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (proof-node-hex-list
                           (state-storage-proof-proof expected-storage-proof))
                          (field storage-proof "proof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (branch-target
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-target
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000000b"))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 1000)
      (set-updated-code branch-state
                        "0x0000000000000000000000000000000000000201")
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-updated-code extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-updated-code branch-extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (assert-code-update-proof
       store
       branch-state
       (commit-state-block store branch-state 54 540)
       branch-target
       slot
       "0x6ab69fa5095659c9578b4dc266ea51d9e5288674f3a60ba0058189667c74786e"
       2)
      (assert-code-update-proof
       store
       extension-state
       (commit-state-block store extension-state 55 550)
       extension-target
       slot
       "0x258d8cdbcaf278008d357941227e1b102cad65026083bde2621e843cb7c00c85"
       3)
      (assert-code-update-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 56 560)
       extension-target
       slot
       "0xa53fa7b005c9d7d484bc1130c751b0e743bb907657e3d646aa31cc456680f193"
       4))))

(deftest eth-rpc-get-proof-code-deletion
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof))
           (add-account (state address nonce balance)
             (state-db-set-account
              state
              (address-from-hex address)
              (make-state-account :nonce nonce :balance balance)))
           (set-deleted-code (state address)
             (let ((target (address-from-hex address)))
               (state-db-set-code state target #(96 1 96 0))
               (state-db-set-code state target #())))
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
           (proof-request (id address slot block)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" id)
                   (cons "method" "eth_getProof")
                   (cons "params"
                         (list (address-to-hex address)
                               (list (hash32-to-hex slot))
                               (hash32-to-hex (block-hash block))))))
           (assert-code-deletion-proof
               (store state block address slot expected-balance
                &optional expected-root expected-nodes (expected-nonce 0))
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 119 address slot block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proof (first (field proof "storageProof")))
                    (expected-proof
                      (state-db-get-proof state address (list slot)))
                    (expected-storage-proof
                      (first (state-proof-result-storage-proofs
                              expected-proof)))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (when expected-root
                 (is (string= expected-root
                              (state-db-root-hex state))))
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
               (when expected-nodes
                 (is (= expected-nodes
                        (length (field proof "accountProof")))))
               (is (= 1 (length (field proof "storageProof"))))
               (is (string= (hash32-to-hex slot)
                            (field storage-proof "key")))
               (is (string= (quantity-to-hex 0)
                            (field storage-proof "value")))
               (is (null (field storage-proof "proof")))
               (is (equal (proof-node-hex-list
                           (state-proof-result-account-proof expected-proof))
                          (field proof "accountProof")))
               (is (equal (proof-node-hex-list
                           (state-storage-proof-proof expected-storage-proof))
                          (field storage-proof "proof")))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (created-address
             (address-from-hex "0x0000000000000000000000000000000000000105"))
           (funded-address
             (address-from-hex "0x0000000000000000000000000000000000000106"))
           (branch-target
             (address-from-hex "0x0000000000000000000000000000000000000201"))
           (extension-target
             (address-from-hex "0x0000000000000000000000000000000000000220"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000000b"))
           (code #(96 1 96 0))
           (created-state (make-state-db))
           (funded-state (make-state-db))
           (branch-state (make-state-db))
           (extension-state (make-state-db))
           (branch-extension-state (make-state-db)))
      (state-db-set-code created-state created-address code)
      (state-db-set-code created-state created-address #())
      (state-db-set-account funded-state funded-address
                            (make-state-account :balance 1))
      (state-db-set-code funded-state funded-address code)
      (state-db-set-code funded-state funded-address #())
      (add-account branch-state
                   "0x0000000000000000000000000000000000000201"
                   1 1000)
      (set-deleted-code branch-state
                        "0x0000000000000000000000000000000000000201")
      (add-account branch-state
                   "0x0000000000000000000000000000000000000211"
                   2 200)
      (add-account extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-deleted-code extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000220"
                   1 1000)
      (set-deleted-code branch-extension-state
                        "0x0000000000000000000000000000000000000220")
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000225"
                   2 200)
      (add-account branch-extension-state
                   "0x0000000000000000000000000000000000000203"
                   3 300)
      (assert-code-deletion-proof
       store
       created-state
       (commit-state-block store created-state 41 410)
       created-address
       slot
       0)
      (assert-code-deletion-proof
       store
       funded-state
       (commit-state-block store funded-state 42 420)
       funded-address
       slot
       1)
      (assert-code-deletion-proof
       store
       branch-state
       (commit-state-block store branch-state 57 570)
       branch-target
       slot
       1000
       "0x582439b37db3e207275bb7dd5391cb2119286e63ac0c7d52f719adbae41e00bb"
       2
       1)
      (assert-code-deletion-proof
       store
       extension-state
       (commit-state-block store extension-state 58 580)
       extension-target
       slot
       1000
       "0x915d94dd285fc0df8a08abcc98035f585db26f42ff322fdbf202b94de5ad2e8e"
       3
       1)
      (assert-code-deletion-proof
       store
       branch-extension-state
       (commit-state-block store branch-extension-state 59 590)
       extension-target
       slot
       1000
       "0x51eb577604090486f0601db492fe0690432903734494bccedfc7d321659b4e7e"
       4
       1))))

