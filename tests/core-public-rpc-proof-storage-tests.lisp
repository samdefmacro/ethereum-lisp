(in-package #:ethereum-lisp.test)

(deftest eth-rpc-get-proof-storage-overwrite-final-value
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
                               (hash32-to-hex (block-hash block))))))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof)))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x000000000000000000000000000000000000030b"))
           (slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000001c"))
           (missing-slot
             (hash32-from-hex
              "0x000000000000000000000000000000000000000000000000000000000000001d"))
           (state (make-state-db)))
      (state-db-set-account state address (make-state-account :nonce 1
                                                              :balance 5))
      (state-db-set-storage state address slot 28)
      (state-db-set-storage state address slot 43)
      (let* ((block (commit-state-block store state 46 460))
             (response
               (engine-rpc-handle-request
                (proof-request 121 address (list slot missing-slot) block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proofs (field proof "storageProof"))
             (present-storage-proof (first storage-proofs))
             (missing-storage-proof (second storage-proofs))
             (expected-proof
               (state-db-get-proof state address (list slot missing-slot)))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (equal (state-proof-result-rpc-object expected-proof)
                   proof))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 5)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 1)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex +empty-code-hash+)
                     (field proof "codeHash")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (= 2 (length storage-proofs)))
        (is (string= (hash32-to-hex slot)
                     (field present-storage-proof "key")))
        (is (string= (quantity-to-hex 43)
                     (field present-storage-proof "value")))
        (is (= 1 (length (field present-storage-proof "proof"))))
        (is (string= (hash32-to-hex missing-slot)
                     (field missing-storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field missing-storage-proof "value")))
        (is (= 1 (length (field missing-storage-proof "proof"))))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-storage-overwrite-to-zero
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
                               (hash32-to-hex (block-hash block))))))
           (proof-node-hex-list (proof)
             (mapcar #'bytes-to-hex proof)))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000104"))
           (slot
             (hash32-from-hex
              "0x0000000000000000000000000000000000000000000000000000000000000009"))
           (state (make-state-db)))
      (state-db-set-account state address (make-state-account :balance 1))
      (state-db-set-storage state address slot 99)
      (state-db-set-storage state address slot 100)
      (state-db-set-storage state address slot 0)
      (let* ((block (commit-state-block store state 47 470))
             (response
               (engine-rpc-handle-request
                (proof-request 122 address (list slot) block)
                store
                (make-chain-config)))
             (proof (field response "result"))
             (storage-proofs (field proof "storageProof"))
             (storage-proof (first storage-proofs))
             (expected-proof
               (state-db-get-proof state address (list slot)))
             (expected-storage-proof
               (first (state-proof-result-storage-proofs expected-proof)))
             (decoded-proof
               (state-proof-result-from-rpc-object proof)))
        (is (equal (state-proof-result-rpc-object expected-proof)
                   proof))
        (is (string= (address-to-hex address)
                     (field proof "address")))
        (is (string= (quantity-to-hex 1)
                     (field proof "balance")))
        (is (string= (quantity-to-hex 0)
                     (field proof "nonce")))
        (is (string= (hash32-to-hex +empty-code-hash+)
                     (field proof "codeHash")))
        (is (string= (hash32-to-hex +empty-trie-hash+)
                     (field proof "storageHash")))
        (is (equal (proof-node-hex-list
                    (state-proof-result-account-proof expected-proof))
                   (field proof "accountProof")))
        (is (= 1 (length storage-proofs)))
        (is (string= (hash32-to-hex slot)
                     (field storage-proof "key")))
        (is (string= (quantity-to-hex 0)
                     (field storage-proof "value")))
        (is (null (field storage-proof "proof")))
        (is (equal (proof-node-hex-list
                    (state-storage-proof-proof expected-storage-proof))
                   (field storage-proof "proof")))
        (is (state-db-verify-proof (state-db-root state)
                                   decoded-proof))))))

(deftest eth-rpc-get-proof-storage-trie-update-boundaries
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
                               (hash32-to-hex (block-hash block))))))
           (storage-slot (value)
             (hash32-from-hex
              (format nil
                      "0x~64,'0x"
                      value)))
           (make-update-state (address slots values update-slot update-value)
             (let ((state (make-state-db)))
               (state-db-set-account state address
                                     (make-state-account :balance 1))
               (loop for slot in slots
                     for value in values
                     do (state-db-set-storage state address slot value))
               (state-db-set-storage state address update-slot update-value)
               state))
           (assert-proof-roundtrip
               (store state block address slots expected-values
                expected-node-counts)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 121 address slots block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proofs (field proof "storageProof"))
                    (expected-proof
                      (state-db-get-proof state address slots))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (= (length expected-values)
                      (length storage-proofs)))
               (loop for storage-proof in storage-proofs
                     for slot in slots
                     for expected-value in expected-values
                     for expected-node-count in expected-node-counts
                     do (progn
                          (is (string= (hash32-to-hex slot)
                                       (field storage-proof "key")))
                          (is (string= (quantity-to-hex expected-value)
                                       (field storage-proof "value")))
                          (is (= expected-node-count
                                 (length (field storage-proof "proof"))))))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000401"))
           (slot-1 (storage-slot 1))
           (slot-2 (storage-slot 2))
           (slot-3 (storage-slot 3))
           (slot-e (storage-slot 14))
           (slot-f (storage-slot 15))
           (branch-state
             (make-update-state
              address
              (list slot-1 slot-2)
              '(1 2)
              slot-1
              17))
           (extension-state
             (make-update-state
              address
              (list slot-1 slot-e)
              '(1 14)
              slot-1
              17)))
      (assert-proof-roundtrip
       store
       branch-state
       (commit-state-block store branch-state 48 480)
       address
       (list slot-1 slot-2 slot-3)
       '(17 2 0)
       '(2 2 1))
      (assert-proof-roundtrip
       store
       extension-state
       (commit-state-block store extension-state 49 490)
       address
       (list slot-1 slot-e slot-f)
       '(17 14 0)
       '(3 3 1)))))

(deftest eth-rpc-get-proof-storage-delete-boundaries
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
                               (hash32-to-hex (block-hash block))))))
           (storage-slot (value)
             (hash32-from-hex
              (format nil
                      "0x~64,'0x"
                     value)))
           (make-delete-preservation-state (address slots values delete-slot)
             (let ((state (make-state-db)))
               (state-db-set-account state address
                                     (make-state-account :balance 1))
               (loop for slot in slots
                     for value in values
                     do (state-db-set-storage state address slot value))
               (state-db-set-storage state address delete-slot 0)
               state))
           (assert-proof-roundtrip
               (store state block address slots expected-values
                expected-node-counts)
             (let* ((response
                      (engine-rpc-handle-request
                       (proof-request 120 address slots block)
                       store
                       (make-chain-config)))
                    (proof (field response "result"))
                    (storage-proofs (field proof "storageProof"))
                    (expected-proof
                      (state-db-get-proof state address slots))
                    (decoded-proof
                      (state-proof-result-from-rpc-object proof)))
               (is (equal (state-proof-result-rpc-object expected-proof)
                          proof))
               (is (= (length expected-values)
                      (length storage-proofs)))
               (loop for storage-proof in storage-proofs
                     for slot in slots
                     for expected-value in expected-values
                     for expected-node-count in expected-node-counts
                     do (progn
                          (is (string= (hash32-to-hex slot)
                                       (field storage-proof "key")))
                          (is (string= (quantity-to-hex expected-value)
                                       (field storage-proof "value")))
                          (is (= expected-node-count
                                 (length (field storage-proof "proof"))))))
               (is (state-db-verify-proof (state-db-root state)
                                          decoded-proof)))))
    (let* ((store (make-engine-payload-memory-store))
           (address
             (address-from-hex "0x0000000000000000000000000000000000000401"))
           (slot-1 (storage-slot 1))
           (slot-2 (storage-slot 2))
           (slot-3 (storage-slot 3))
           (slot-e (storage-slot 14))
           (slot-f (storage-slot 15))
           (branch-state
             (make-delete-preservation-state
              address
              (list slot-1 slot-2 slot-3)
              '(1 2 3)
              slot-3))
           (extension-state
             (make-delete-preservation-state
              address
              (list slot-1 slot-e slot-f)
              '(1 14 15)
              slot-f))
           (collapse-state
             (make-delete-preservation-state
              address
              (list slot-1 slot-2)
              '(1 2)
              slot-2)))
      (assert-proof-roundtrip
       store
       branch-state
       (commit-state-block store branch-state 43 430)
       address
       (list slot-1 slot-2 slot-3)
       '(1 2 0)
       '(2 2 1))
      (assert-proof-roundtrip
       store
       extension-state
       (commit-state-block store extension-state 44 440)
       address
       (list slot-1 slot-e slot-f)
       '(1 14 0)
       '(3 3 1))
      (assert-proof-roundtrip
       store
       collapse-state
       (commit-state-block store collapse-state 45 450)
       address
       (list slot-1 slot-2)
       '(1 0)
       '(1 1)))))

