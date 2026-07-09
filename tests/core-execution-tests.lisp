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

(deftest chain-store-set-canonical-head-rewrites-number-indexes
  (let* ((store (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :extra-data #(0))))
         (genesis-hash (block-hash genesis)))
    (flet ((child-block (number parent-hash marker)
             (make-block
              :header
              (make-block-header :number number
                                 :parent-hash parent-hash
                                 :extra-data (vector marker)))))
      (let* ((a1 (child-block 1 genesis-hash 1))
             (a2-header (block-header (child-block 2 (block-hash a1) 2)))
             (b1 (child-block 1 genesis-hash 11))
             (b2 (child-block 2 (block-hash b1) 12))
             (a2-transaction
               (make-legacy-transaction
                :nonce 1
                :gas-price 2
                :gas-limit 21000
                :value 3
                :data #(1)
                :v 27
                :r 4
                :s 5))
             (b3-transaction
               (make-legacy-transaction
                :nonce 2
                :gas-price 3
                :gas-limit 21000
                :value 4
                :data #(2)
                :v 27
                :r 6
                :s 7))
             (a2-receipt
               (make-receipt :status 1 :cumulative-gas-used 21000))
             (b3-receipt
               (make-receipt :status 1 :cumulative-gas-used 21000))
             (b3
               (make-block
                :header
                (make-block-header :number 3
                                   :parent-hash (block-hash b2)
                                   :extra-data #(13))
                :transactions (list b3-transaction)
                :receipts (list b3-receipt)))
             (a2
               (make-block
                :header a2-header
                :transactions (list a2-transaction)
                :receipts (list a2-receipt)))
             (a1-hash (block-hash a1))
             (a2-hash (block-hash a2))
             (b1-hash (block-hash b1))
             (b2-hash (block-hash b2))
             (b3-hash (block-hash b3))
             (a2-transaction-hash (transaction-hash a2-transaction))
             (b3-transaction-hash (transaction-hash b3-transaction)))
        (dolist (block (list genesis a1 a2 b1 b2 b3))
          (chain-store-put-block store block))
        (is (bytes= (block-rlp a1)
                    (block-rlp (chain-store-block-by-number store 1))))
        (is (bytes= (block-rlp a2)
                    (block-rlp (chain-store-block-by-number store 2))))
        (is (null (chain-store-canonical-hash store 3)))
        (is (= 2 (chain-store-head-number store)))
        (is (bytes= (block-rlp a2)
                    (block-rlp (chain-store-latest-block store))))
        (is (typep (chain-store-transaction-location
                    store a2-transaction-hash)
                   'engine-transaction-location))
        (is (null (chain-store-transaction-location
                   store b3-transaction-hash)))
        (is (bytes= (block-rlp b3)
                    (block-rlp (chain-store-known-block store b3-hash))))
        (is (bytes= (block-rlp b3)
                    (block-rlp
                     (chain-store-set-canonical-head store b3-hash))))
        (is (bytes= (block-rlp b1)
                    (block-rlp (chain-store-block-by-number store 1))))
        (is (bytes= (block-rlp b2)
                    (block-rlp (chain-store-block-by-number store 2))))
        (is (bytes= (block-rlp b3)
                    (block-rlp (chain-store-block-by-number store 3))))
        (is (string= (hash32-to-hex b1-hash)
                     (hash32-to-hex
                      (chain-store-canonical-hash store 1))))
        (is (string= (hash32-to-hex b2-hash)
                     (hash32-to-hex
                      (chain-store-canonical-hash store 2))))
        (is (string= (hash32-to-hex b3-hash)
                     (hash32-to-hex
                      (chain-store-canonical-hash store 3))))
        (is (bytes= (block-rlp a1)
                    (block-rlp (chain-store-known-block store a1-hash))))
        (is (bytes= (block-rlp a2)
                    (block-rlp (chain-store-known-block store a2-hash))))
        (is (null (chain-store-transaction-location
                   store a2-transaction-hash)))
        (let ((location
                (chain-store-transaction-location
                 store b3-transaction-hash)))
          (is (typep location 'engine-transaction-location))
          (is (bytes= (block-rlp b3)
                      (block-rlp
                       (engine-transaction-location-block location))))
          (is (bytes= (transaction-encoding b3-transaction)
                      (transaction-encoding
                       (engine-transaction-location-transaction location))))
          (is (bytes= (receipt-rlp b3-receipt)
                      (receipt-rlp
                       (engine-transaction-location-receipt location)))))
        (is (bytes= (block-rlp b3)
                    (block-rlp (chain-store-latest-block store))))
        (is (= 3 (chain-store-block-tag-number store "latest")))))))

(deftest chain-store-keeps-canonical-transaction-location-over-sidechain-duplicate
  (let* ((store (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :extra-data #(0))))
         (genesis-hash (block-hash genesis))
         (shared-transaction
           (make-legacy-transaction
            :nonce 7
            :gas-price 2
            :gas-limit 21000
            :value 3
            :data #(7)
            :v 27
            :r 4
            :s 5))
         (shared-hash (transaction-hash shared-transaction)))
    (flet ((child-block (number parent-hash marker &key transactions)
             (make-block
              :header
              (make-block-header :number number
                                 :parent-hash parent-hash
                                 :extra-data (vector marker))
              :transactions transactions
              :receipts
              (loop repeat (length transactions)
                    collect (make-receipt :status 1
                                          :cumulative-gas-used 21000)))))
      (let* ((a1 (child-block 1 genesis-hash 1))
             (a2 (child-block 2 (block-hash a1) 2
                              :transactions (list shared-transaction)))
             (b1 (child-block 1 genesis-hash 11))
             (b2 (child-block 2 (block-hash b1) 12
                              :transactions (list shared-transaction))))
        (dolist (block (list genesis a1 a2))
          (chain-store-put-block store block))
        (let ((location
                (chain-store-transaction-location store shared-hash)))
          (is (typep location 'engine-transaction-location))
          (is (bytes= (block-rlp a2)
                      (block-rlp
                       (engine-transaction-location-block location)))))
        (dolist (block (list b1 b2))
          (chain-store-put-block store block))
        (let ((location
                (chain-store-transaction-location store shared-hash)))
          (is (typep location 'engine-transaction-location))
          (is (bytes= (block-rlp a2)
                      (block-rlp
                       (engine-transaction-location-block location)))))
        (chain-store-set-canonical-head store (block-hash b2))
        (let ((location
                (chain-store-transaction-location store shared-hash)))
          (is (typep location 'engine-transaction-location))
          (is (bytes= (block-rlp b2)
                      (block-rlp
                       (engine-transaction-location-block location))))
          (is (bytes= (transaction-encoding shared-transaction)
                      (transaction-encoding
                       (engine-transaction-location-transaction
                        location)))))))))

(deftest chain-store-keeps-pending-transaction-when-sidechain-block-includes-it
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 2
             :gas-limit 21000
             :to recipient
             :value 3)
            1
            1))
         (transaction-hash (transaction-hash transaction))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :extra-data #(0))))
         (canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :extra-data #(1))))
         (sidechain-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :extra-data #(2))
            :transactions (list transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000)))))
    (chain-store-put-block store genesis)
    (chain-store-put-block store canonical-child)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     transaction)
    (chain-store-put-block store sidechain-child)
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (eq transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store
             transaction-hash)))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (chain-store-set-canonical-head store (block-hash sidechain-child))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (null
         (ethereum-lisp.core::engine-payload-store-pending-transaction
          store
          transaction-hash)))
    (let ((location
            (chain-store-transaction-location store transaction-hash)))
      (is (typep location 'engine-transaction-location))
      (is (bytes= (block-rlp sidechain-child)
                  (block-rlp
                   (engine-transaction-location-block location))))
      (is (bytes= (transaction-encoding transaction)
                  (transaction-encoding
                   (engine-transaction-location-transaction location)))))))

(deftest chain-store-reinserts-displaced-canonical-transactions-after-reorg
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 2
             :gas-limit 21000
             :to recipient
             :value 3)
            1
            1))
         (transaction-hash (transaction-hash transaction))
         (sender (transaction-sender transaction :expected-chain-id 1))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(1))
            :transactions (list transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(2)))))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (chain-store-put-account-nonce
     store (block-hash new-canonical-child) sender 0)
    (chain-store-put-account-balance
     store (block-hash new-canonical-child) sender 1000000)
    (is (typep (chain-store-transaction-location store transaction-hash)
               'engine-transaction-location))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (bytes= (transaction-encoding transaction)
                (transaction-encoding
                 (ethereum-lisp.core::engine-payload-store-pending-transaction
                  store
                  transaction-hash))))))

(deftest chain-store-prunes-displaced-transaction-locations-after-short-reorg
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 2
             :gas-limit 21000
             :to recipient
             :value 3)
            1
            1))
         (transaction-hash (transaction-hash transaction))
         (transaction-key (hash32-to-hex transaction-hash))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :gas-limit 30000000
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(1))))
         (old-canonical-grandchild
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash old-canonical-child)
                               :gas-limit 30000000
                               :extra-data #(2))
            :transactions (list transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(3)))))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store old-canonical-grandchild
                           :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (is (typep (chain-store-transaction-location store transaction-hash)
               'engine-transaction-location))
    (is (typep (gethash
                transaction-key
                (ethereum-lisp.core::engine-payload-memory-store-transaction-locations
                 store))
               'engine-transaction-location))
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (is (null
         (gethash
          transaction-key
          (ethereum-lisp.core::engine-payload-memory-store-transaction-locations
           store))))))

(deftest chain-store-reorg-preserves-shared-transaction-location
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 1
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (transaction-hash (transaction-hash transaction))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :gas-limit 30000000
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(1))
            :transactions (list transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(2))
            :transactions (list transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000)))))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (let ((old-location
            (chain-store-transaction-location store transaction-hash)))
      (is (typep old-location 'engine-transaction-location))
      (is (equalp (hash32-bytes (block-hash old-canonical-child))
                  (hash32-bytes
                   (block-hash
                    (engine-transaction-location-block old-location))))))
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (let ((new-location
            (chain-store-transaction-location store transaction-hash)))
      (is (typep new-location 'engine-transaction-location))
      (is (equalp (hash32-bytes (block-hash new-canonical-child))
                  (hash32-bytes
                   (block-hash
                    (engine-transaction-location-block new-location)))))
      (is (= 0 (engine-transaction-location-index new-location)))
      (is (bytes= (transaction-encoding transaction)
                  (transaction-encoding
                   (engine-transaction-location-transaction new-location)))))
    (is (null
         (ethereum-lisp.core::engine-payload-store-pooled-transaction
          store
          transaction-hash)))))

(deftest chain-store-reinsert-respects-pooled-balance-reservations
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (displaced-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 1
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (queued-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 1
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (displaced-hash (transaction-hash displaced-transaction))
         (queued-hash (transaction-hash queued-transaction))
         (sender (transaction-sender displaced-transaction :expected-chain-id 1))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :gas-limit 30000000
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(1))
            :transactions (list displaced-transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(2)))))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (chain-store-put-account-nonce
     store (block-hash new-canonical-child) sender 0)
    (chain-store-put-account-balance
     store (block-hash new-canonical-child) sender 21000)
    (ethereum-lisp.core::engine-payload-store-put-queued-transaction
     store queued-transaction)
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null (chain-store-transaction-location store displaced-hash)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (null
         (ethereum-lisp.core::engine-payload-store-pooled-transaction
          store
          displaced-hash)))
    (is (bytes= (transaction-encoding queued-transaction)
                (transaction-encoding
                 (ethereum-lisp.core::engine-payload-store-queued-transaction
                  store
                  queued-hash))))))

(deftest chain-store-reinsert-preserves-pooled-same-nonce-conflict
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (displaced-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 2
             :gas-limit 21000
             :to recipient
             :value 3)
            1
            1))
         (local-conflict
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 3
             :gas-limit 21000
             :to recipient
             :value 4)
            1
            1))
         (displaced-hash (transaction-hash displaced-transaction))
         (conflict-hash (transaction-hash local-conflict))
         (sender (transaction-sender displaced-transaction
                                     :expected-chain-id 1))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :gas-limit 30000000
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(1))
            :transactions (list displaced-transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :extra-data #(2)))))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (chain-store-put-account-nonce
     store (block-hash new-canonical-child) sender 0)
    (chain-store-put-account-balance
     store (block-hash new-canonical-child) sender 1000000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store local-conflict)
    (is (typep (chain-store-transaction-location store displaced-hash)
               'engine-transaction-location))
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null (chain-store-transaction-location store displaced-hash)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (null
         (ethereum-lisp.core::engine-payload-store-pooled-transaction
          store
          displaced-hash)))
    (is (bytes= (transaction-encoding local-conflict)
                (transaction-encoding
                 (ethereum-lisp.core::engine-payload-store-pending-transaction
                  store
                  conflict-hash))))))

(deftest chain-store-reinsert-routes-basefee-ineligible-transactions
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (displaced-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (displaced-hash (transaction-hash displaced-transaction))
         (sender (transaction-sender displaced-transaction
                                     :expected-chain-id 1))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :gas-limit 30000000
                               :base-fee-per-gas 1
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :base-fee-per-gas 1
                               :extra-data #(1))
            :transactions (list displaced-transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000000
                               :base-fee-per-gas 5
                               :extra-data #(2)))))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (chain-store-put-account-nonce
     store (block-hash new-canonical-child) sender 0)
    (chain-store-put-account-balance
     store (block-hash new-canonical-child) sender 1000000)
    (is (typep (chain-store-transaction-location store displaced-hash)
               'engine-transaction-location))
    (chain-store-set-canonical-head
     store
     (block-hash new-canonical-child)
     :expected-chain-id 1)
    (is (null (chain-store-transaction-location store displaced-hash)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
            store)))
    (is (bytes= (transaction-encoding displaced-transaction)
                (transaction-encoding
                 (ethereum-lisp.core::engine-payload-store-basefee-transaction
                  store
                  displaced-hash))))))

(deftest chain-store-reinsert-prunes-overgas-conflict-before-reorg-reinsert
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (displaced-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 2
             :gas-limit 21000
             :to recipient
             :value 0)
            1
            1))
         (overgas-conflict
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 3
             :gas-limit 40000
             :to recipient
             :value 0)
            1
            1))
         (displaced-hash (transaction-hash displaced-transaction))
         (overgas-hash (transaction-hash overgas-conflict))
         (sender (transaction-sender displaced-transaction :expected-chain-id 1))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :gas-limit 50000
                               :extra-data #(0))))
         (old-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 50000
                               :extra-data #(1))
            :transactions (list displaced-transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000))))
         (new-canonical-child
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :gas-limit 30000
                               :extra-data #(2)))))
    (chain-store-put-block store genesis :state-available-p t)
    (chain-store-put-block store old-canonical-child :state-available-p t)
    (chain-store-put-block store new-canonical-child :state-available-p t)
    (chain-store-put-account-nonce
     store (block-hash new-canonical-child) sender 0)
    (chain-store-put-account-balance
     store (block-hash new-canonical-child) sender 1000000)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store overgas-conflict)
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null
         (ethereum-lisp.core::engine-payload-store-pooled-transaction
          store
          overgas-hash)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (bytes= (transaction-encoding displaced-transaction)
                (transaction-encoding
                 (ethereum-lisp.core::engine-payload-store-pending-transaction
                  store
                  displaced-hash))))))

(deftest engine-rpc-forkchoice-reinsert-enforces-configured-chain-id
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex (zero-hash32)))))
           (forkchoice-request (head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 8174)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list (forkchoice-state-object head))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 2 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (wrong-chain-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 2
               :gas-limit 21000
               :to recipient
               :value 3)
              1
              1))
           (transaction-hash (transaction-hash wrong-chain-transaction))
           (sender (transaction-sender wrong-chain-transaction
                                       :expected-chain-id 1))
           (genesis
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :gas-limit 30000000
                                 :timestamp 0
                                 :extra-data #(0))))
           (old-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(1))
              :transactions (list wrong-chain-transaction)
              :receipts (list (make-receipt :status 1
                                            :cumulative-gas-used 21000))))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(2)))))
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-block store old-canonical-child :state-available-p t)
      (chain-store-put-block store new-canonical-child :state-available-p t)
      (chain-store-put-account-nonce
       store (block-hash new-canonical-child) sender 0)
      (chain-store-put-account-balance
       store (block-hash new-canonical-child) sender 1000000)
      (is (typep (chain-store-transaction-location
                  store transaction-hash)
                 'engine-transaction-location))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request (block-hash new-canonical-child))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus")))
        (is (= 8174 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (null (chain-store-transaction-location
                   store transaction-hash)))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                store)))
        (is (null
             (ethereum-lisp.core::engine-payload-store-pending-transaction
              store
              transaction-hash)))))))

(deftest engine-rpc-forkchoice-reinsert-enforces-blob-fee-cap
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex (zero-hash32)))))
           (forkchoice-request (head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 8175)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list (forkchoice-state-object head))))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0))
           (transaction
             (transaction-from-encoding
              (hex-to-bytes
               "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
           (transaction-hash (transaction-hash transaction))
           (sender (transaction-sender transaction :expected-chain-id 1337))
           (genesis
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :gas-limit 30000000
                                 :timestamp 0
                                 :extra-data #(0))))
           (old-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :blob-gas-used 0
                                 :excess-blob-gas 0
                                 :extra-data #(1))
              :transactions (list transaction)
              :receipts (list (make-receipt :status 1
                                            :cumulative-gas-used 21000))))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :blob-gas-used 0
                                 :excess-blob-gas (* 64 1024 1024)
                                 :extra-data #(2)))))
      (is (typep transaction 'blob-transaction))
      (is (> (block-header-blob-base-fee
              (block-header new-canonical-child))
             (blob-transaction-max-fee-per-blob-gas transaction)))
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-block store old-canonical-child :state-available-p t)
      (chain-store-put-block store new-canonical-child :state-available-p t)
      (chain-store-put-account-nonce
       store (block-hash new-canonical-child) sender 0)
      (chain-store-put-account-balance
       store (block-hash new-canonical-child) sender
       10000000000000000000)
      (is (typep (chain-store-transaction-location
                  store transaction-hash)
                 'engine-transaction-location))
      (let* ((response
               (engine-rpc-handle-request
                (forkchoice-request (block-hash new-canonical-child))
                store
                config))
             (result (field response "result"))
             (payload-status (field result "payloadStatus")))
        (is (= 8175 (field response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (null (chain-store-transaction-location
                   store transaction-hash)))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-blob-transaction-count
                store)))
        (is (null
             (ethereum-lisp.core::engine-payload-store-blob-transaction
              store
              transaction-hash)))))))

(deftest engine-rpc-forkchoice-reinsert-notifies-pending-transaction-filters
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (forkchoice-state-object (head)
             (list (cons "headBlockHash" (hash32-to-hex head))
                   (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
                   (cons "finalizedBlockHash"
                         (hash32-to-hex (zero-hash32)))))
           (forkchoice-request (head)
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 8176)
                   (cons "method" "engine_forkchoiceUpdatedV1")
                   (cons "params"
                         (list (forkchoice-state-object head)))))
           (filter-changes-request (filter-id id)
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":" (write-to-string id)
              ",\"method\":\"eth_getFilterChanges\",\"params\":[\""
              filter-id "\"]}")))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 2
               :gas-limit 21000
               :to recipient
               :value 3)
              1
              1))
           (transaction-hash (transaction-hash transaction))
           (transaction-hash-hex (hash32-to-hex transaction-hash))
           (sender (transaction-sender transaction :expected-chain-id 1))
           (genesis
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :gas-limit 30000000
                                 :timestamp 0
                                 :extra-data #(0))))
           (old-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(1))
              :transactions (list transaction)
              :receipts (list (make-receipt :status 1
                                            :cumulative-gas-used 21000))))
           (new-canonical-child
             (make-block
              :header
              (make-block-header :number 1
                                 :parent-hash (block-hash genesis)
                                 :gas-limit 30000000
                                 :timestamp 12
                                 :extra-data #(2)))))
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-block store old-canonical-child :state-available-p t)
      (chain-store-put-block store new-canonical-child :state-available-p t)
      (chain-store-put-account-nonce
       store (block-hash new-canonical-child) sender 0)
      (chain-store-put-account-balance
       store (block-hash new-canonical-child) sender 1000000)
      (let* ((pending-filter-response
               (parse-json
                (engine-rpc-handle-request-json
                 "{\"jsonrpc\":\"2.0\",\"id\":8177,\"method\":\"eth_newPendingTransactionFilter\"}"
                 store
                 config)))
             (pending-filter-id (field pending-filter-response "result"))
             (initial-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (filter-changes-request pending-filter-id 8178)
                 store
                 config)))
             (forkchoice-response
               (engine-rpc-handle-request
                (forkchoice-request (block-hash new-canonical-child))
                store
                config))
             (payload-status
               (field (field forkchoice-response "result") "payloadStatus"))
             (changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (filter-changes-request pending-filter-id 8179)
                 store
                 config)))
             (changes (field changes-response "result"))
             (empty-changes-response
               (parse-json
                (engine-rpc-handle-request-json
                 (filter-changes-request pending-filter-id 8180)
                 store
                 config))))
        (is (= 0 (length (field initial-changes-response "result"))))
        (is (= 8176 (field forkchoice-response "id")))
        (is (string= +payload-status-valid+
                     (field payload-status "status")))
        (is (null (chain-store-transaction-location store transaction-hash)))
        (is (typep
             (ethereum-lisp.core::engine-payload-store-pending-transaction
              store
              transaction-hash)
             'legacy-transaction))
        (is (= 1 (length changes)))
        (is (string= transaction-hash-hex (first changes)))
        (is (= 0 (length (field empty-changes-response "result"))))))))

