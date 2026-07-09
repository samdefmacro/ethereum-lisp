(in-package #:ethereum-lisp.test)

(deftest engine-new-payload-memory-status-validates-known-parent-before-accepted
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
                        :timestamp 98
                        :base-fee-per-gas 100))
         (child-block (make-block :header child-header))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block store parent-block)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status store 1 payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (search "Timestamp is not greater than parent timestamp"
                  (payload-status-validation-error status)))
      (is (not block))
      (is (not (engine-payload-store-remote-block
                store
                (block-hash child-block)))))))

(deftest engine-new-payload-memory-status-clears-remote-block-on-invalid
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
                        :timestamp 98
                        :base-fee-per-gas 100))
         (child-block (make-block :header child-header))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data child-block)))
         (store (make-engine-payload-memory-store)))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status store 1 payload config)
      (is (string= +payload-status-syncing+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-remote-block
           store
           (block-hash child-block))))
    (engine-payload-store-put-block store parent-block)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status store 1 payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block))
      (is (search "Timestamp is not greater than parent timestamp"
                  (payload-status-validation-error status)))
      (is (engine-payload-store-invalid-block
           store
           (block-hash child-block)))
      (is (null
           (engine-payload-store-remote-block
            store
            (block-hash child-block)))))))

(deftest engine-new-payload-memory-status-clears-remote-block-on-invalid-ancestor
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0))
         (parent-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 41
                         :gas-limit 50000
                         :timestamp 98
                         :base-fee-per-gas 100))
         (parent-block (make-block :header parent-header))
         (invalid-header (make-block-header
                          :parent-hash (block-hash parent-block)
                          :beneficiary address
                          :state-root +empty-trie-hash+
                          :mix-hash (zero-hash32)
                          :number 42
                          :gas-limit 50000
                          :timestamp 98
                          :base-fee-per-gas 100))
         (invalid-block (make-block :header invalid-header))
         (descendant-header (make-block-header
                             :parent-hash (block-hash invalid-block)
                             :beneficiary address
                             :state-root +empty-trie-hash+
                             :mix-hash (zero-hash32)
                             :number 43
                             :gas-limit 50000
                             :timestamp 100
                             :base-fee-per-gas 100))
         (descendant-block (make-block :header descendant-header))
         (invalid-payload (execution-payload-envelope-execution-payload
                           (block-to-executable-data invalid-block)))
         (descendant-payload (execution-payload-envelope-execution-payload
                              (block-to-executable-data descendant-block)))
         (store (make-engine-payload-memory-store)))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status store 1 descendant-payload config)
      (is (string= +payload-status-syncing+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-remote-block
           store
           (block-hash descendant-block))))
    (engine-payload-store-put-block store parent-block)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status store 1 invalid-payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block))
      (is (engine-payload-store-invalid-block
           store
           (block-hash invalid-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status store 1 descendant-payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block))
      (is (engine-payload-store-invalid-block
           store
           (block-hash descendant-block)))
      (is (null
           (engine-payload-store-remote-block
            store
            (block-hash descendant-block)))))))

(deftest engine-new-payload-memory-status-imports-executable-block
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :chain-id 1 :london-block 0))
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
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 payload config
         :import-function #'execute-and-commit-engine-payload)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-known-block store (block-hash child-block)))
      (is (chain-store-state-available-p store (block-hash child-block)))
      (is (typep (chain-store-state-db store (block-hash child-block))
                 'state-db)))))

