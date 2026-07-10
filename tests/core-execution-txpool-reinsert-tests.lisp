(in-package #:ethereum-lisp.test)

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
                (ethereum-lisp.node-state:engine-payload-memory-store-transaction-locations
                 store))
               'engine-transaction-location))
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (is (null
         (gethash
          transaction-key
          (ethereum-lisp.node-state:engine-payload-memory-store-transaction-locations
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
         (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
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
    (ethereum-lisp.txpool:engine-payload-store-put-queued-transaction
     store queued-transaction)
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null (chain-store-transaction-location store displaced-hash)))
    (is (= 0
           (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.txpool:engine-payload-store-queued-transaction-count
            store)))
    (is (null
         (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
          store
          displaced-hash)))
    (is (bytes= (transaction-encoding queued-transaction)
                (transaction-encoding
                 (ethereum-lisp.txpool:engine-payload-store-queued-transaction
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
    (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
     store local-conflict)
    (is (typep (chain-store-transaction-location store displaced-hash)
               'engine-transaction-location))
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null (chain-store-transaction-location store displaced-hash)))
    (is (= 1
           (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
            store)))
    (is (null
         (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
          store
          displaced-hash)))
    (is (bytes= (transaction-encoding local-conflict)
                (transaction-encoding
                 (ethereum-lisp.txpool:engine-payload-store-pending-transaction
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
           (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.txpool:engine-payload-store-queued-transaction-count
            store)))
    (is (= 1
           (ethereum-lisp.txpool:engine-payload-store-basefee-transaction-count
            store)))
    (is (bytes= (transaction-encoding displaced-transaction)
                (transaction-encoding
                 (ethereum-lisp.txpool:engine-payload-store-basefee-transaction
                  store
                  displaced-hash))))))
