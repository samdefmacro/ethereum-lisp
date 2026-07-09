(in-package #:ethereum-lisp.test)

(deftest block-derives-body-roots
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (transaction (make-legacy-transaction :nonce 1
                                               :gas-price 2
                                               :gas-limit 3
                                               :to address
                                               :value 4
                                               :data #(5)
                                               :v 27
                                               :r 6
                                               :s 7))
         (log (make-log-entry :address address :topics (list topic) :data #(9)))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000
                                :logs (list log)))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (block (make-block :transactions (list transaction)
                            :receipts (list receipt)
                            :withdrawals (list withdrawal)
                            :requests (list #(#x00 #xbb) #(#x01 #xaa))
                            :block-access-list '()))
         (header (block-header block)))
    (is (hash32-p (block-hash block)))
    (is (= 1 (length (block-transactions block))))
    (is (= 1 (length (block-withdrawals block))))
    (is (= 2 (length (block-requests block))))
    (is (block-block-access-list-present-p block))
    (is (string= (hash32-to-hex (transaction-list-root (list transaction)))
                 (hash32-to-hex (block-header-transactions-root header))))
    (is (string= (hash32-to-hex (receipt-list-root (list receipt)))
                 (hash32-to-hex (block-header-receipts-root header))))
    (is (string= (hash32-to-hex (withdrawal-list-root (list withdrawal)))
                 (hash32-to-hex (block-header-withdrawals-root header))))
    (is (string= (hash32-to-hex
                  (execution-requests-hash
                   (list #(#x00 #xbb) #(#x01 #xaa))))
                 (hash32-to-hex (block-header-requests-hash header))))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (is (bytes= (bloom-bytes (receipt-bloom (list log)))
                (block-header-logs-bloom header)))))

(deftest block-to-executable-data-maps-engine-payload-fields
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (parent-hash (hash32-from-hex
                       "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (state-root (hash32-from-hex
                      "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (mix-hash (hash32-from-hex
                    "0x0300000000000000000000000000000000000000000000000000000000000000"))
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
         (requests (list #(#x00 #xaa) #(#x01 #xbb)))
         (header (make-block-header :parent-hash parent-hash
                                    :beneficiary address
                                    :state-root state-root
                                    :mix-hash mix-hash
                                    :number 42
                                    :gas-limit 50000
                                    :gas-used 21000
                                    :timestamp 99
                                    :extra-data #(1 2 3)
                                    :base-fee-per-gas 100
                                    :blob-gas-used 0
                                    :excess-blob-gas 7
                                    :slot-number 11))
         (block (make-block :header header
                            :transactions (list transaction)
                            :receipts (list receipt)
                            :withdrawals (list withdrawal)
                            :requests requests))
         (envelope (block-to-executable-data block :block-value 123))
         (payload (execution-payload-envelope-execution-payload envelope)))
    (is (= 123 (execution-payload-envelope-block-value envelope)))
    (is (not (execution-payload-envelope-override-p envelope)))
    (is (hash32-p (executable-data-block-hash payload)))
    (is (string= (hash32-to-hex (block-hash block))
                 (hash32-to-hex (executable-data-block-hash payload))))
    (is (string= (hash32-to-hex parent-hash)
                 (hash32-to-hex (executable-data-parent-hash payload))))
    (is (string= (address-to-hex address)
                 (address-to-hex (executable-data-fee-recipient payload))))
    (is (string= (hash32-to-hex state-root)
                 (hash32-to-hex (executable-data-state-root payload))))
    (is (string= (hash32-to-hex mix-hash)
                 (hash32-to-hex (executable-data-random payload))))
    (is (= 42 (executable-data-number payload)))
    (is (= 50000 (executable-data-gas-limit payload)))
    (is (= 21000 (executable-data-gas-used payload)))
    (is (= 99 (executable-data-timestamp payload)))
    (is (= 100 (executable-data-base-fee-per-gas payload)))
    (is (= 0 (executable-data-blob-gas-used payload)))
    (is (= 7 (executable-data-excess-blob-gas payload)))
    (is (= 11 (executable-data-slot-number payload)))
    (is (bytes= #(1 2 3) (executable-data-extra-data payload)))
    (is (bytes= (transaction-encoding transaction)
                (first (executable-data-transactions payload))))
    (is (= 1 (length (executable-data-withdrawals payload))))
    (is (= 1 (withdrawal-index
              (first (executable-data-withdrawals payload)))))
    (is (= 2 (length (execution-payload-envelope-requests envelope))))
    (is (bytes= (first requests)
                (first (execution-payload-envelope-requests envelope))))))

(deftest executable-data-decodes-transaction-bytes
  (let* ((recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (slot (hash32-from-hex
                "0x0000000000000000000000000000000000000000000000000000000000000003"))
         (access (list (make-access-list-entry :address recipient
                                               :storage-keys (list slot))))
         (blob-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (authorization
           (make-set-code-authorization :chain-id 1
                                        :address recipient
                                        :nonce 11
                                        :y-parity 1
                                        :r 12
                                        :s 13))
         (transactions
           (list
            (make-legacy-transaction :nonce 1
                                     :gas-price 2
                                     :gas-limit 21000
                                     :to recipient
                                     :value 4
                                     :v 27
                                     :r 6
                                     :s 7)
            (make-access-list-transaction :chain-id 1
                                          :nonce 2
                                          :gas-price 3
                                          :gas-limit 4
                                          :to recipient
                                          :value 5
                                          :data #(6)
                                          :access-list access
                                          :y-parity 1
                                          :r 7
                                          :s 8)
            (make-dynamic-fee-transaction :chain-id 1
                                          :nonce 2
                                          :max-priority-fee-per-gas 3
                                          :max-fee-per-gas 4
                                          :gas-limit 5
                                          :to recipient
                                          :value 6
                                          :data #(7)
                                          :access-list access
                                          :y-parity 1
                                          :r 8
                                          :s 9)
            (make-blob-transaction :chain-id 1
                                   :nonce 2
                                   :max-priority-fee-per-gas 3
                                   :max-fee-per-gas 4
                                   :gas-limit 5
                                   :to recipient
                                   :value 6
                                   :data #(7)
                                   :access-list access
                                   :max-fee-per-blob-gas 10
                                   :blob-versioned-hashes (list blob-hash)
                                   :y-parity 1
                                   :r 8
                                   :s 9)
            (make-set-code-transaction :chain-id 1
                                       :nonce 2
                                       :max-priority-fee-per-gas 3
                                       :max-fee-per-gas 4
                                       :gas-limit 5
                                       :to recipient
                                       :value 6
                                       :data #(7)
                                       :access-list access
                                       :authorization-list
                                       (list authorization)
                                       :y-parity 1
                                       :r 8
                                       :s 9)))
         (payload (make-executable-data
                   :transactions (mapcar #'transaction-encoding
                                         transactions)))
         (decoded (executable-data-decoded-transactions payload)))
    (is (= (length transactions) (length decoded)))
    (loop for original in transactions
          for decoded-transaction in decoded
          do (is (typep decoded-transaction (type-of original)))
             (is (bytes= (transaction-encoding original)
                         (transaction-encoding decoded-transaction))))
    (signals block-validation-error
      (executable-data-decoded-transactions
       (make-executable-data
        :transactions (append (mapcar #'transaction-encoding
                                      transactions)
                              (list #())))))
    (signals block-validation-error
      (executable-data-decoded-transactions
       (make-executable-data :transactions (list 5))))))

(deftest block-from-rlp-decodes-shanghai-empty-body
  (let* ((encoded
           (hex-to-bytes
            "0xf90217f90211a0bd0bfa5377fdd562a7700ec0eab46dcd83a4ba67a3448fc990876c4ff23ec4f6a01dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347940000000000000000000000000000000000000001a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421b9010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000802a82c350806380a0000000000000000000000000000000000000000000000000000000000000000088000000000000000064a056e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421c0c0c0"))
         (block (block-from-rlp encoded))
         (header (block-header block)))
    (is (string= "0x9937880e9ca0115d6d631f925a1b1559d539eff54dde8813c393baec0b82e77b"
                 (hash32-to-hex (block-hash block))))
    (is (string= "0xbd0bfa5377fdd562a7700ec0eab46dcd83a4ba67a3448fc990876c4ff23ec4f6"
                 (hash32-to-hex (block-header-parent-hash header))))
    (is (= #x2a (block-header-number header)))
    (is (= #xc350 (block-header-gas-limit header)))
    (is (= 0 (block-header-gas-used header)))
    (is (= #x64 (block-header-base-fee-per-gas header)))
    (is (block-withdrawals-present-p block))
    (is (= 0 (length (block-withdrawals block))))
    (is (= 0 (length (block-transactions block))))
    (is (= 0 (length (block-ommers block))))
    (is (bytes= encoded (block-rlp block)))))

(deftest executable-data-to-block-no-hash-builds-local-block
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (parent-hash (hash32-from-hex
                       "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (state-root (hash32-from-hex
                      "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (mix-hash (hash32-from-hex
                    "0x0300000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-dynamic-fee-transaction
                       :chain-id 1
                       :nonce 2
                       :max-priority-fee-per-gas 3
                       :max-fee-per-gas 4
                       :gas-limit 21000
                       :to recipient
                       :value 5
                       :data #(6)
                       :y-parity 1
                       :r 7
                       :s 8))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (withdrawal (make-withdrawal :index 1
                                      :validator-index 2
                                      :address address
                                      :amount 3))
         (requests (list #(#x00 #xaa) #(#x01 #xbb)))
         (header (make-block-header :parent-hash parent-hash
                                    :beneficiary address
                                    :state-root state-root
                                    :mix-hash mix-hash
                                    :number 42
                                    :gas-limit 50000
                                    :gas-used 21000
                                    :timestamp 99
                                    :extra-data #(1 2 3)
                                    :base-fee-per-gas 100
                                    :blob-gas-used 0
                                    :excess-blob-gas 7
                                    :slot-number 11))
         (source-block (make-block :header header
                                   :transactions (list transaction)
                                   :receipts (list receipt)
                                   :withdrawals (list withdrawal)
                                   :requests requests))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data source-block)))
         (reconstructed
           (executable-data-to-block-no-hash payload :requests requests))
         (reconstructed-header (block-header reconstructed)))
    (is (= 1 (length (block-transactions reconstructed))))
    (is (typep (first (block-transactions reconstructed))
               'dynamic-fee-transaction))
    (is (bytes= (transaction-encoding transaction)
                (transaction-encoding
                 (first (block-transactions reconstructed)))))
    (is (block-withdrawals-present-p reconstructed))
    (is (= 1 (length (block-withdrawals reconstructed))))
    (is (block-requests-present-p reconstructed))
    (is (= 2 (length (block-requests reconstructed))))
    (is (string= (hash32-to-hex (block-header-transactions-root header))
                 (hash32-to-hex
                  (block-header-transactions-root reconstructed-header))))
    (is (string= (hash32-to-hex (block-header-receipts-root header))
                 (hash32-to-hex
                  (block-header-receipts-root reconstructed-header))))
    (is (string= (hash32-to-hex (block-header-withdrawals-root header))
                 (hash32-to-hex
                  (block-header-withdrawals-root reconstructed-header))))
    (is (string= (hash32-to-hex (block-header-requests-hash header))
                 (hash32-to-hex
                  (block-header-requests-hash reconstructed-header))))
    (is (string= (hash32-to-hex (block-hash source-block))
                 (hash32-to-hex (block-hash reconstructed))))
    (is (= 42 (block-header-number reconstructed-header)))
    (is (= 100 (block-header-base-fee-per-gas reconstructed-header)))
    (is (= 7 (block-header-excess-blob-gas reconstructed-header)))
    (is (= 11 (block-header-slot-number reconstructed-header)))
    (let ((bad-extra payload))
      (setf (executable-data-extra-data bad-extra) (make-byte-vector 33))
      (signals block-validation-error
        (executable-data-to-block-no-hash bad-extra)))
    (let ((bad-bloom (block-to-executable-data source-block)))
      (let ((bad-payload
              (execution-payload-envelope-execution-payload bad-bloom)))
        (setf (executable-data-logs-bloom bad-payload) #(1 2))
        (signals block-validation-error
          (executable-data-to-block-no-hash bad-payload))))))

(deftest executable-data-to-block-checks-payload-block-hash
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient (address-from-hex
                     "0x0000000000000000000000000000000000000002"))
         (parent-hash (hash32-from-hex
                       "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (state-root (hash32-from-hex
                      "0x0200000000000000000000000000000000000000000000000000000000000000"))
         (mix-hash (hash32-from-hex
                    "0x0300000000000000000000000000000000000000000000000000000000000000"))
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
         (requests (list #(#x00 #xaa) #(#x01 #xbb)))
         (header (make-block-header :parent-hash parent-hash
                                    :beneficiary address
                                    :state-root state-root
                                    :mix-hash mix-hash
                                    :number 42
                                    :gas-limit 50000
                                    :gas-used 21000
                                    :timestamp 99
                                    :extra-data #(1 2 3)
                                    :base-fee-per-gas 100))
         (source-block (make-block :header header
                                   :transactions (list transaction)
                                   :receipts (list receipt)
                                   :withdrawals (list withdrawal)
                                   :requests requests))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data source-block)))
         (reconstructed (executable-data-to-block payload :requests requests)))
    (is (string= (hash32-to-hex (block-hash source-block))
                 (hash32-to-hex (block-hash reconstructed))))
    (setf (executable-data-block-hash payload)
          (hash32-from-hex
           "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
    (signals block-validation-error
      (executable-data-to-block payload :requests requests))
    (setf (executable-data-block-hash payload) #(1 2))
    (signals block-validation-error
      (executable-data-to-block payload :requests requests))))

(deftest executable-data-to-block-validates-blob-versioned-hashes
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (blob-hash
           (hash32-from-hex
            "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
         (other-blob-hash
           (hash32-from-hex
            "0x0100000000000000000000000000000000000000000000000000000000000000"))
         (transaction (make-blob-transaction
                       :chain-id 1
                       :nonce 2
                       :max-priority-fee-per-gas 3
                       :max-fee-per-gas 4
                       :gas-limit 21000
                       :to address
                       :value 5
                       :max-fee-per-blob-gas 6
                       :blob-versioned-hashes (list blob-hash)
                       :y-parity 1
                       :r 7
                       :s 8))
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
                  :base-fee-per-gas 100
                  :blob-gas-used +blob-gas-per-blob+
                  :excess-blob-gas 0))
         (source-block (make-block :header header
                                   :transactions (list transaction)
                                   :receipts (list receipt)))
         (payload (execution-payload-envelope-execution-payload
                   (block-to-executable-data source-block)))
         (reconstructed
           (executable-data-to-block
            payload
            :versioned-hashes (list blob-hash))))
    (is (string= (hash32-to-hex (block-hash source-block))
                 (hash32-to-hex (block-hash reconstructed))))
    (signals block-validation-error
      (executable-data-to-block payload))
    (signals block-validation-error
      (executable-data-to-block payload :versioned-hashes '()))
    (signals block-validation-error
      (executable-data-to-block
       payload
       :versioned-hashes (list other-blob-hash)))
    (signals block-validation-error
      (executable-data-to-block
       payload
       :versioned-hashes (list blob-hash other-blob-hash)))
    (signals block-validation-error
      (executable-data-to-block
       payload
       :versioned-hashes (list #(1 2))))))

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

