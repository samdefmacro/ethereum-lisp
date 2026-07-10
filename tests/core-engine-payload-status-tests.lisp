(in-package #:ethereum-lisp.test)

(deftest engine-service-package-boundary
  (let ((engine (find-package '#:ethereum-lisp.engine))
        (payloads (find-package '#:ethereum-lisp.engine-payloads))
        (chain-store (find-package '#:ethereum-lisp.chain-store))
        (json-rpc (find-package '#:ethereum-lisp.json-rpc))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list engine))))
    (is (member payloads (package-use-list engine)))
    (is (member chain-store (package-use-list engine)))
    (is (not (member json-rpc (package-use-list engine))))
    (dolist (name '("ENGINE-NEW-PAYLOAD-MEMORY-STATUS"
                    "ENGINE-FORKCHOICE-MEMORY-STATUS"))
      (multiple-value-bind (engine-symbol engine-status)
          (find-symbol name engine)
        (multiple-value-bind (core-symbol core-status)
            (find-symbol name core)
          (is (eq :external engine-status))
          (is (eq :external core-status))
          (is (eq engine-symbol core-symbol)))))))

(deftest engine-new-payload-params-status-wraps-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 21000
                                               :to recipient
                                               :value 4
                                               :v 27
                                               :r 6
                                               :s 7))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (header (make-block-header
                  :parent-hash (zero-hash32)
                  :beneficiary address
                  :state-root +empty-trie-hash+
                  :mix-hash (zero-hash32)
                  :number 42
                  :gas-limit 50000
                  :gas-used 21000
                  :timestamp 99
                  :base-fee-per-gas 100))
         (source-block (make-block :header header
                                   :transactions (list transaction)
                                   :receipts (list receipt)))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data source-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-params-status payload)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (not (payload-status-validation-error status)))
      (is (typep block 'ethereum-block))
      (is (string= (hash32-to-hex (block-hash source-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (string= (hash32-to-hex (block-hash source-block))
                   (hash32-to-hex (block-hash block)))))
    (setf (executable-data-block-hash payload)
          (hash32-from-hex
           "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
    (multiple-value-bind (status block)
        (engine-new-payload-params-status payload)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block))
      (is (not (payload-status-latest-valid-hash status)))
      (is (search "block hash mismatch"
                  (payload-status-validation-error status))))))

(deftest engine-new-payload-version-status-enforces-fork-parameters
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (parent-beacon-root
           (hash32-from-hex
            "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 21000
                                               :to recipient
                                               :value 4
                                               :v 27
                                               :r 6
                                               :s 7))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (requests (list #(#x00 #xaa)))
         (london-config (make-chain-config :london-block 0))
         (cancun-config (make-chain-config :london-block 0
                                           :shanghai-time 0
                                           :cancun-time 0))
         (prague-config (make-chain-config :london-block 0
                                           :shanghai-time 0
                                           :cancun-time 0
                                           :prague-time 0))
         (amsterdam-config (make-chain-config :london-block 0
                                              :shanghai-time 0
                                              :cancun-time 0
                                              :prague-time 0
                                              :amsterdam-time 0))
         (legacy-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 50000
                         :gas-used 21000
                         :timestamp 99
                         :base-fee-per-gas 100))
         (cancun-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 50000
                         :gas-used 21000
                         :timestamp 99
                         :base-fee-per-gas 100
                         :withdrawals-root (withdrawal-list-root
                                            (list withdrawal))
                         :blob-gas-used 0
                         :excess-blob-gas 0
                         :parent-beacon-root parent-beacon-root))
         (prague-header (make-block-header
                         :parent-hash (zero-hash32)
                         :beneficiary address
                         :state-root +empty-trie-hash+
                         :mix-hash (zero-hash32)
                         :number 42
                         :gas-limit 50000
                         :gas-used 21000
                         :timestamp 99
                         :base-fee-per-gas 100
                         :withdrawals-root (withdrawal-list-root
                                            (list withdrawal))
                         :blob-gas-used 0
                         :excess-blob-gas 0
                         :parent-beacon-root parent-beacon-root
                         :requests-hash (execution-requests-hash requests)))
         (amsterdam-header (make-block-header
                            :parent-hash (zero-hash32)
                            :beneficiary address
                            :state-root +empty-trie-hash+
                            :mix-hash (zero-hash32)
                            :number 42
                            :gas-limit 50000
                            :gas-used 21000
                            :timestamp 99
                            :base-fee-per-gas 100
                            :withdrawals-root (withdrawal-list-root
                                               (list withdrawal))
                            :blob-gas-used 0
                            :excess-blob-gas 0
                            :parent-beacon-root parent-beacon-root
                            :requests-hash (execution-requests-hash requests)
                            :slot-number 7))
         (amsterdam-header-without-block-access-list
           (make-block-header
            :parent-hash (zero-hash32)
            :beneficiary address
            :state-root +empty-trie-hash+
            :mix-hash (zero-hash32)
            :number 42
            :gas-limit 50000
            :gas-used 21000
            :timestamp 99
            :base-fee-per-gas 100
            :withdrawals-root (withdrawal-list-root (list withdrawal))
            :blob-gas-used 0
            :excess-blob-gas 0
            :parent-beacon-root parent-beacon-root
            :requests-hash (execution-requests-hash requests)
            :slot-number 7))
         (legacy-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header legacy-header
                         :transactions (list transaction)
                         :receipts (list receipt)))))
         (cancun-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header cancun-header
                         :transactions (list transaction)
                         :receipts (list receipt)
                         :withdrawals (list withdrawal)))))
         (prague-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header prague-header
                         :transactions (list transaction)
                         :receipts (list receipt)
                         :withdrawals (list withdrawal)
                         :requests requests))))
         (amsterdam-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header amsterdam-header
                         :transactions (list transaction)
                         :receipts (list receipt)
                         :withdrawals (list withdrawal)
                         :requests requests
                         :block-access-list '()))))
         (amsterdam-payload-without-block-access-list
           (execution-payload-envelope-execution-payload
            (block-to-executable-data
             (make-block :header amsterdam-header-without-block-access-list
                         :transactions (list transaction)
                         :receipts (list receipt)
                         :withdrawals (list withdrawal)
                         :requests requests)))))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status 1 legacy-payload london-config)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status 1 cancun-payload cancun-config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status 2 legacy-payload cancun-config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         (make-engine-payload-memory-store)
         3 cancun-payload cancun-config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= "versionedHashes required after Cancun"
                   (payload-status-validation-error status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         3 cancun-payload cancun-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '())
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         3 cancun-payload cancun-config
         :parent-beacon-root parent-beacon-root)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         4 prague-payload prague-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '()
         :requests requests)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         4 prague-payload prague-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '())
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         5 amsterdam-payload amsterdam-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '()
         :requests requests)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         5 prague-payload prague-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '()
         :requests requests)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (not block)))
    (multiple-value-bind (status block)
        (engine-new-payload-version-status
         5 amsterdam-payload-without-block-access-list amsterdam-config
         :parent-beacon-root parent-beacon-root
         :versioned-hashes '()
         :requests requests)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= "blockAccessList required after Amsterdam"
                   (payload-status-validation-error status)))
      (is (not block)))))
