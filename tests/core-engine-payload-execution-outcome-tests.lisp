(in-package #:ethereum-lisp.test)

(deftest engine-new-payload-memory-status-executes-known-unprocessed-block
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
    (engine-payload-store-put-block store child-block)
    (is (not (chain-store-state-available-p store (block-hash child-block))))
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 payload config
         :import-function #'execute-and-commit-engine-payload)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (chain-store-state-available-p store (block-hash child-block)))
      (is (typep (chain-store-state-db store (block-hash child-block))
                 'state-db)))))

(deftest engine-new-payload-memory-status-clears-remote-block-on-import
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
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status store 1 payload config)
      (is (string= +payload-status-syncing+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (engine-payload-store-remote-block
           store
           (block-hash child-block))))
    (engine-payload-store-put-block
     store parent-block :state-available-p t)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 payload config
         :import-function #'execute-and-commit-engine-payload)
      (is (string= +payload-status-valid+ (payload-status-status status)))
      (is (typep block 'ethereum-block))
      (is (chain-store-known-block store (block-hash child-block)))
      (is (chain-store-state-available-p store (block-hash child-block)))
      (is (null
           (engine-payload-store-remote-block
            store
            (block-hash child-block)))))))

(deftest engine-new-payload-memory-status-maps-execution-failure-invalid
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
         (bad-child-header (make-block-header
                            :parent-hash (block-hash parent-block)
                            :beneficiary address
                            :state-root (zero-hash32)
                            :mix-hash (zero-hash32)
                            :number 42
                            :gas-limit 50000
                            :gas-used 0
                            :timestamp 99
                            :base-fee-per-gas 100))
         (bad-child-block (make-block :header bad-child-header))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data bad-child-block)))
         (store (make-engine-payload-memory-store)))
    (engine-payload-store-put-block
     store parent-block :state-available-p t)
    (multiple-value-bind (status block)
        (engine-new-payload-memory-status
         store 1 payload config
         :import-function #'execute-and-commit-engine-payload)
      (is (string= +payload-status-invalid+ (payload-status-status status)))
      (is (string= "State root mismatch"
                   (payload-status-validation-error status)))
      (is (string= (hash32-to-hex (block-hash parent-block))
                   (hash32-to-hex
                    (payload-status-latest-valid-hash status))))
      (is (not block))
      (is (not (chain-store-known-block store (block-hash bad-child-block))))
      (is (engine-payload-store-invalid-block
           store
           (block-hash bad-child-block))))))

(deftest engine-new-payload-memory-status-maps-post-execution-commitments-invalid
  (labels ((nonempty-bloom ()
             (let ((bloom (make-byte-vector 256)))
               (setf (aref bloom 0) 1)
               bloom))
           (bad-child-block (parent-block beneficiary &rest header-args)
             (let ((header
                     (make-block-header
                      :parent-hash (block-hash parent-block)
                      :beneficiary beneficiary
                      :state-root +empty-trie-hash+
                      :mix-hash (zero-hash32)
                      :number 42
                      :gas-limit 50000
                      :gas-used 0
                      :timestamp 99
                      :base-fee-per-gas 100)))
               (let ((block (make-block :header header)))
                 (loop for (key value) on header-args by #'cddr
                       do (ecase key
                            (:state-root
                             (setf (block-header-state-root header) value))
                            (:receipts-root
                             (setf (block-header-receipts-root header) value))
                            (:logs-bloom
                             (setf (block-header-logs-bloom header) value))
                            (:gas-used
                             (setf (block-header-gas-used header) value))))
                 block)))
           (check-case (name parent-block bad-block expected-error)
             (declare (ignore name))
             (let* ((config (make-chain-config :chain-id 1 :london-block 0))
                    (store (make-engine-payload-memory-store))
                    (payload
                      (execution-payload-envelope-execution-payload
                       (block-to-executable-data bad-block))))
               (engine-payload-store-put-block
                store parent-block :state-available-p t)
               (multiple-value-bind (status block)
                   (engine-new-payload-memory-status
                    store 1 payload config
                    :import-function #'execute-and-commit-engine-payload)
                 (is (string= +payload-status-invalid+
                              (payload-status-status status)))
                 (is (string= expected-error
                              (payload-status-validation-error status)))
                 (is (string= (hash32-to-hex (block-hash parent-block))
                              (hash32-to-hex
                               (payload-status-latest-valid-hash status))))
                 (is (not block))
                 (is (not (chain-store-known-block
                           store (block-hash bad-block))))
                 (is (engine-payload-store-invalid-block
                      store
                      (block-hash bad-block)))))))
    (let* ((beneficiary
             (address-from-hex "0x0000000000000000000000000000000000000001"))
           (parent-block
             (make-block
              :header (make-block-header
                       :parent-hash (zero-hash32)
                       :beneficiary beneficiary
                       :state-root +empty-trie-hash+
                       :mix-hash (zero-hash32)
                       :number 41
                       :gas-limit 50000
                       :gas-used 25000
                       :timestamp 98
                       :base-fee-per-gas 100))))
      (check-case
       "state root"
       parent-block
       (bad-child-block parent-block beneficiary
                        :state-root (zero-hash32))
       "State root mismatch")
      (check-case
       "receipts root"
       parent-block
       (bad-child-block parent-block beneficiary
                        :receipts-root (zero-hash32))
       "Receipts root mismatch")
      (check-case
       "logs bloom"
       parent-block
       (bad-child-block parent-block beneficiary
                        :logs-bloom (nonempty-bloom))
       "Logs bloom mismatch")
      (check-case
       "gas used"
       parent-block
       (bad-child-block parent-block beneficiary
                        :gas-used 1)
       "Gas used mismatch"))))

