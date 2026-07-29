(in-package #:ethereum-lisp.test)

(deftest engine-new-payload-memory-status-caches-invalid-ancestors
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
         (invalid-child-header (make-block-header
                                :parent-hash (block-hash parent-block)
                                :beneficiary address
                                :state-root +empty-trie-hash+
                                :mix-hash (zero-hash32)
                                :number 42
                                :gas-limit 50000
                                :gas-used 0
                                :timestamp 98
                                :base-fee-per-gas 100))
         (invalid-child-block (make-block :header invalid-child-header))
         (grandchild-header (make-block-header
                             :parent-hash (block-hash invalid-child-block)
                             :beneficiary address
                             :state-root +empty-trie-hash+
                             :mix-hash (zero-hash32)
                             :number 43
                             :gas-limit 50000
                             :gas-used 0
                             :timestamp 100
                             :base-fee-per-gas 100))
         (grandchild-block (make-block :header grandchild-header))
         (invalid-child-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data invalid-child-block)))
         (grandchild-payload
           (execution-payload-envelope-execution-payload
            (block-to-executable-data grandchild-block)))
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block store parent-block :state-available-p t)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 invalid-child-payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (not block))
      (is (engine-payload-store-invalid-block
           store
           (block-hash invalid-child-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 grandchild-payload config)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (string= "links to previously rejected block"
                   (payload-status-validation-error status)))
      (is (not block))
      (let ((cached-head
              (engine-payload-store-invalid-block
               store
               (block-hash grandchild-block))))
        (is cached-head)
        (is (string= (hash32-to-hex (block-hash invalid-child-block))
                     (hash32-to-hex (block-hash cached-head))))))))

(deftest engine-invalid-ancestor-cache-recovers-after-hit-threshold
  (let* ((store (make-engine-payload-memory-store))
         (invalid-block
           (make-block :header (make-block-header :number 2 :timestamp 2)))
         (invalid-hash (block-hash invalid-block)))
    (engine-payload-store-mark-invalid store invalid-block)
    (loop repeat 126
          do (is (engine-payload-store-invalid-ancestor-status
                  store invalid-hash invalid-hash)))
    (is (not (engine-payload-store-invalid-ancestor-status
              store invalid-hash invalid-hash)))
    (is (not (engine-payload-store-invalid-block store invalid-hash)))))

(deftest engine-invalid-ancestor-zeroes-pre-merge-last-valid-hash
  (let* ((store (make-engine-payload-memory-store))
         (pow-parent
           (make-block
            :header (make-block-header :number 1
                                       :timestamp 1
                                       :difficulty 1)))
         (invalid-block
           (make-block
            :header (make-block-header :parent-hash (block-hash pow-parent)
                                       :number 2
                                       :timestamp 2)))
         (invalid-hash (block-hash invalid-block)))
    (engine-payload-store-put-block store pow-parent :state-available-p t)
    (engine-payload-store-mark-invalid store invalid-block)
    (let ((status
            (engine-payload-store-invalid-ancestor-status
             store invalid-hash invalid-hash)))
      (is status)
      (is (string= (hash32-to-hex (zero-hash32))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status)))))))

