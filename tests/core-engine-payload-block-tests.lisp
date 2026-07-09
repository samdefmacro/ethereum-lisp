(in-package #:ethereum-lisp.test)

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

