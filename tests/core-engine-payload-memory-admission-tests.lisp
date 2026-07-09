(in-package #:ethereum-lisp.test)

(deftest engine-new-payload-memory-status-tracks-parent-availability
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
         (child-header (make-block-header
                        :parent-hash (block-hash parent-block)
                        :beneficiary address
                        :state-root +empty-trie-hash+
                        :mix-hash (zero-hash32)
                        :number 42
                        :gas-limit 50000
                        :gas-used 0
                        :timestamp 99
                        :base-fee-per-gas 100))
         (child-block (make-block :header child-header))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
         (missing-parent-store (make-engine-payload-memory-store))
         (missing-state-store (make-engine-payload-memory-store))
         (ready-store (make-engine-payload-memory-store)))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         missing-parent-store 1 payload config)
      (is (string= +payload-status-syncing+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-remote-block
           missing-parent-store
           (block-hash child-block))))
    (engine-payload-store-put-block missing-state-store parent-block)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         missing-state-store 1 payload config)
      (is (string= +payload-status-accepted+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-remote-block
           missing-state-store
           (block-hash child-block))))
    (engine-payload-store-put-block
     ready-store parent-block :state-available-p t)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status ready-store 1 payload config)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash child-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-known-block ready-store
                                            (block-hash child-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status ready-store 1 payload config)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))))

(deftest engine-new-payload-memory-status-known-block-precedes-invalid-cache
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
         (child-header (make-block-header
                        :parent-hash (block-hash parent-block)
                        :beneficiary address
                        :state-root +empty-trie-hash+
                        :mix-hash (zero-hash32)
                        :number 42
                        :gas-limit 50000
                        :gas-used 0
                        :timestamp 99
                        :base-fee-per-gas 100))
         (child-block (make-block :header child-header))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block
     store parent-block :state-available-p t)
    (engine-payload-store-put-block
     store child-block :state-available-p t)
    (engine-payload-store-mark-invalid store child-block)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status store 1 payload config)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash child-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (bytes= (block-rlp child-block)
                  (block-rlp block))))))

(deftest engine-new-payload-memory-status-rejects-unrecoverable-transaction-sender
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (config (make-chain-config :chain-id 1 :london-block 0))
         (transaction
           (make-dynamic-fee-transaction
            :chain-id 1
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas #x0fa0
            :gas-limit #x84d0
            :to recipient
            :value 0
            :y-parity 1
            :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
            :s #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1))
         (header (make-block-header
                  :parent-hash (zero-hash32)
                  :beneficiary address
                  :state-root +empty-trie-hash+
                  :mix-hash (zero-hash32)
                  :number 0
                  :gas-limit 50000
                  :gas-used 0
                  :timestamp 99
                  :base-fee-per-gas 100))
         (block (make-block :header header :transactions (list transaction)))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data block)))
         (store (make-engine-payload-memory-store)))
    (is (null (transaction-sender transaction :expected-chain-id 1)))
    (multiple-value-bind (status imported-block)
        (engine-new-payload-memory-status store 2 payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not imported-block))
      (is (not (payload-status-latest-valid-hash status)))
      (is (search "transaction 0 sender"
                  (payload-status-validation-error status))))
    (is (null (engine-payload-store-known-block store (block-hash block))))
    (is (null (chain-store-transaction-location
               store
               (transaction-hash transaction))))))

(deftest engine-new-payload-memory-status-delays-sender-check-until-importable
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (config (make-chain-config :chain-id 1 :london-block 0))
         (transaction
           (make-dynamic-fee-transaction
            :chain-id 1
            :nonce 0
            :max-priority-fee-per-gas 0
            :max-fee-per-gas #x0fa0
            :gas-limit #x84d0
            :to recipient
            :value 0
            :y-parity 1
            :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
            :s #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1))
         (parent-header
           (make-block-header
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
         (child-header
           (make-block-header
            :parent-hash (block-hash parent-block)
            :beneficiary address
            :state-root +empty-trie-hash+
            :mix-hash (zero-hash32)
            :number 42
            :gas-limit 50000
            :gas-used 0
            :timestamp 99
            :base-fee-per-gas 100))
         (child-block
           (make-block :header child-header
                       :transactions (list transaction)))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
         (missing-parent-store (make-engine-payload-memory-store))
         (missing-state-store (make-engine-payload-memory-store)))
    (is (null (transaction-sender transaction :expected-chain-id 1)))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         missing-parent-store 2 payload config)
      (is (string= +payload-status-syncing+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (not (payload-status-validation-error status)))
      (is (engine-payload-store-remote-block
           missing-parent-store
           (block-hash child-block)))
      (is (not (engine-payload-store-invalid-block
                missing-parent-store
                (block-hash child-block)))))
    (engine-payload-store-put-block missing-state-store parent-block)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         missing-state-store 2 payload config)
      (is (string= +payload-status-accepted+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (not (payload-status-validation-error status)))
      (is (engine-payload-store-remote-block
           missing-state-store
           (block-hash child-block)))
      (is (not (engine-payload-store-invalid-block
                missing-state-store
                (block-hash child-block)))))))

