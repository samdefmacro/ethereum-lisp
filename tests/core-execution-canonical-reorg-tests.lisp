(in-package #:ethereum-lisp.test)

(deftest canonical-chain-package-boundary
  (let ((canonical (find-package '#:ethereum-lisp.canonical-chain))
        (chain-store (find-package '#:ethereum-lisp.chain-store))
        (txpool (find-package '#:ethereum-lisp.txpool))
        (persistence
          (find-package '#:ethereum-lisp.node-store.persistence))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list canonical))))
    (is (member chain-store (package-use-list canonical)))
    (is (member txpool (package-use-list canonical)))
    (is (not (member persistence (package-use-list canonical))))
    (multiple-value-bind (canonical-symbol canonical-status)
        (find-symbol "CHAIN-STORE-SET-CANONICAL-HEAD" canonical)
      (multiple-value-bind (core-symbol core-status)
          (find-symbol "CHAIN-STORE-SET-CANONICAL-HEAD" core)
        (is (eq :external canonical-status))
        (is (eq :external core-status))
        (is (eq canonical-symbol core-symbol))))
    (multiple-value-bind (symbol status)
        (find-symbol "CANONICAL-CHAIN-SET-HEAD" canonical)
      (is symbol)
      (is (eq :internal status)))))

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
    (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
     store
     transaction)
    (chain-store-put-block store sidechain-child)
    (is (= 1
           (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
            store)))
    (is (eq transaction
            (ethereum-lisp.txpool:engine-payload-store-pending-transaction
             store
             transaction-hash)))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (chain-store-set-canonical-head store (block-hash sidechain-child))
    (is (= 0
           (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
            store)))
    (is (null
         (ethereum-lisp.txpool:engine-payload-store-pending-transaction
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
           (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
            store)))
    (chain-store-set-canonical-head store (block-hash new-canonical-child))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (is (= 1
           (ethereum-lisp.txpool:engine-payload-store-pending-transaction-count
            store)))
    (is (bytes= (transaction-encoding transaction)
                (transaction-encoding
                 (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                  store
                  transaction-hash))))))
