(in-package #:ethereum-lisp.test)

(deftest execute-and-commit-block-stores-only-after-execution-success
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (contract
           (address-from-hex "0x0000000000000000000000000000000000000003"))
         (storage-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000004"))
         (transaction
           (make-legacy-transaction :nonce 0
                                    :gas-price 1
                                    :gas-limit 21000
                                    :to recipient
                                    :value 10))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account :balance 100000))
    (state-db-set-account state contract
                          (make-state-account :balance 7))
    (state-db-set-code state contract #(1 2 3))
    (state-db-set-storage state contract storage-slot 5)
    (multiple-value-bind (block receipts)
        (execute-and-commit-block
         store state
         (lambda ()
           (execute-legacy-block state sender (list transaction)
                                 :header header)))
      (is (= 1 (length receipts)))
      (is (bytes= (block-rlp block)
                  (block-rlp
                   (chain-store-known-block store (block-hash block)))))
      (is (bytes= (block-rlp block)
                  (block-rlp (chain-store-block-by-number store 0))))
      (is (chain-store-state-available-p store (block-hash block)))
      (is (typep (chain-store-transaction-location
                  store
                  (transaction-hash transaction))
                 'engine-transaction-location))
      (is (= 10
             (state-account-balance
              (state-db-get-account state recipient))))
      (is (= 78990
             (chain-store-account-balance store (block-hash block) sender)))
      (is (= 1
             (chain-store-account-nonce store (block-hash block) sender)))
      (is (= 10
             (chain-store-account-balance store (block-hash block) recipient)))
      (is (= 7
             (chain-store-account-balance store (block-hash block) contract)))
      (is (bytes= #(1 2 3)
                  (chain-store-account-code store (block-hash block)
                                            contract)))
      (is (= 5
             (chain-store-account-storage store (block-hash block)
                                          contract storage-slot))))))

(deftest execute-and-commit-block-rolls-back-bad-execution-commitments
  (let ((sender
          (address-from-hex "0x0000000000000000000000000000000000000001"))
        (recipient
          (address-from-hex "0x0000000000000000000000000000000000000002")))
    (labels ((bad-logs-bloom ()
               (let ((bloom (make-byte-vector 256)))
                 (setf (aref bloom 0) 1)
                 bloom))
             (assert-rejected-header (header)
               (let* ((store (make-engine-payload-memory-store))
                      (state (make-state-db))
                      (transaction
                        (make-legacy-transaction
                         :nonce 0
                         :gas-price 1
                         :gas-limit 21000
                         :to recipient
                         :value 10)))
                 (state-db-set-account state sender
                                       (make-state-account :balance 100000))
                 (signals error
                   (execute-and-commit-block
                    store state
                    (lambda ()
                      (execute-legacy-block state sender (list transaction)
                                            :header header))))
                 (is (null (chain-store-block-by-number store 0)))
                 (is (null (chain-store-canonical-hash store 0)))
                 (is (null (chain-store-transaction-location
                            store
                            (transaction-hash transaction))))
                 (is (= 100000
                        (state-account-balance
                         (state-db-get-account state sender))))
                 (is (null (state-db-get-account state recipient))))))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :state-root (zero-hash32)))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :receipts-root (zero-hash32)))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :logs-bloom (bad-logs-bloom)))
      (assert-rejected-header
       (make-block-header :number 0
                          :parent-hash (zero-hash32)
                          :gas-limit 50000
                          :gas-used 1)))))

(deftest execute-and-commit-block-rolls-back-intra-transaction-error
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (transaction
           (make-legacy-transaction :nonce 0
                                    :gas-price 1
                                    :gas-limit 21000
                                    :to recipient
                                    :value 10))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account :balance 1))
    (signals error
      (execute-and-commit-block
       store state
       (lambda ()
         (execute-legacy-block state sender (list transaction)
                               :header header))))
    (is (null (chain-store-block-by-number store 0)))
    (is (null (chain-store-transaction-location
               store
               (transaction-hash transaction))))
    (is (= 1
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

(deftest execute-and-commit-signed-block-recovers-sender-and-stores-indexes
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (make-legacy-transaction
            :nonce 9
            :gas-price 20000000000
            :gas-limit 21000
            :to recipient
            :value 1000000000000000000
            :v 37
            :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
            :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account
                           :nonce 9
                           :balance 2000000000000000000))
    (multiple-value-bind (block receipts)
        (execute-and-commit-signed-block
         store state (list transaction)
         :expected-chain-id 1
         :header header)
      (is (= 1 (length receipts)))
      (is (bytes= (block-rlp block)
                  (block-rlp (chain-store-block-by-number store 0))))
      (is (typep (chain-store-transaction-location
                  store
                  (transaction-hash transaction))
                 'engine-transaction-location))
      (is (= 10
             (chain-store-account-nonce store (block-hash block) sender)))
      (is (= 999580000000000000
             (chain-store-account-balance store (block-hash block) sender)))
      (is (= 1000000000000000000
             (chain-store-account-balance store (block-hash block)
                                          recipient))))))

(deftest execute-and-commit-signed-block-rejects-wrong-chain-id-atomically
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (sender
           (address-from-hex "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (make-legacy-transaction
            :nonce 9
            :gas-price 20000000000
            :gas-limit 21000
            :to recipient
            :value 1000000000000000000
            :v 37
            :r #x28ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276
            :s #x67cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83))
         (header (make-block-header :number 0
                                    :parent-hash (zero-hash32)
                                    :gas-limit 50000)))
    (state-db-set-account state sender
                          (make-state-account
                           :nonce 9
                           :balance 2000000000000000000))
    (signals transaction-validation-error
      (execute-and-commit-signed-block
       store state (list transaction)
       :expected-chain-id 2
       :header header))
    (is (null (chain-store-block-by-number store 0)))
    (is (null (chain-store-transaction-location
               store
               (transaction-hash transaction))))
    (is (= 9
           (state-account-nonce
            (state-db-get-account state sender))))
    (is (= 2000000000000000000
           (state-account-balance
            (state-db-get-account state sender))))
    (is (null (state-db-get-account state recipient)))))

