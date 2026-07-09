(in-package #:ethereum-lisp.test)

(deftest engine-payload-store-indexes-pending-transactions-by-sender-nonce
  (let* ((store (make-engine-payload-memory-store))
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
         (sender-key
           (address-to-hex
            (or (transaction-sender transaction)
                (zero-address))))
         (nonce-key (write-to-string (transaction-nonce transaction)
                                     :base 10))
         (hash (transaction-hash transaction))
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 0)
            :transactions (list transaction))))
    (is (typep
         (ethereum-lisp.core::engine-payload-memory-store-txpool store)
         'ethereum-lisp.core::engine-pending-txpool))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-queued-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
            store)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-blob-transaction-count
            store)))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store transaction)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store transaction)
    (let* ((sender-index
             (ethereum-lisp.core::engine-payload-store-pending-transactions-by-sender
              store))
           (sender-transactions (gethash sender-key sender-index)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (= 1 (hash-table-count sender-index)))
      (is (= 1 (hash-table-count sender-transactions)))
      (is (eq transaction (gethash nonce-key sender-transactions)))
      (is (eq transaction
              (ethereum-lisp.core::engine-payload-store-pending-transaction
               store hash))))
    (engine-payload-store-put-block store block)
    (let* ((sender-index
             (ethereum-lisp.core::engine-payload-store-pending-transactions-by-sender
              store))
           (sender-transactions (gethash sender-key sender-index)))
      (is (= 0
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store hash)))
      (is (null sender-transactions))
      (is (zerop (hash-table-count sender-index))))))

(deftest engine-payload-store-removes-pending-sender-nonce-on-block-import
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (private-key 1)
         (pending-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (mined-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender pending-transaction)
                (zero-address))))
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 0)
            :transactions (list mined-transaction))))
    (is (not (string= (hash32-to-hex (transaction-hash pending-transaction))
                      (hash32-to-hex (transaction-hash mined-transaction)))))
    (is (bytes= (address-bytes (transaction-sender pending-transaction))
                (address-bytes (transaction-sender mined-transaction))))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store pending-transaction)
    (engine-payload-store-put-block store block)
    (let* ((sender-index
             (ethereum-lisp.core::engine-payload-store-pending-transactions-by-sender
              store))
           (sender-transactions (gethash sender-key sender-index))
           (location
             (chain-store-transaction-location
              store
              (transaction-hash mined-transaction))))
      (is (= 0
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store
            (transaction-hash pending-transaction))))
      (is (null sender-transactions))
      (is (typep location 'engine-transaction-location))
      (is (bytes= (transaction-encoding mined-transaction)
                  (transaction-encoding
                   (engine-transaction-location-transaction location)))))))

(deftest engine-payload-store-removes-included-transactions-from-subpools
  (labels ((put-queued (store transaction)
             (setf
              (gethash
               (ethereum-lisp.core::engine-pending-txpool-hash-key
                (transaction-hash transaction))
               (ethereum-lisp.core::engine-payload-store-queued-transaction-table
                store))
              transaction)
             (ethereum-lisp.core::engine-payload-store-index-queued-transaction
              store
              transaction)))
    (let* ((store (make-engine-payload-memory-store))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (private-key 1)
           (queued-conflict
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 4
               :gas-price 100
               :gas-limit 21000
               :to recipient)
              private-key
              1))
           (mined-conflict
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 4
               :gas-price 110
               :gas-limit 21000
               :to recipient)
              private-key
              1))
           (basefee-exact
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 6
               :gas-price 90
               :gas-limit 21000
               :to recipient)
              private-key
              1))
           (queued-exact
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 5
               :gas-price 120
               :gas-limit 21000
               :to recipient)
              private-key
              1))
           (blob-exact
             (fixture-sign-blob-transaction
              (make-blob-transaction
               :chain-id 1
               :nonce 7
               :max-priority-fee-per-gas 1
               :max-fee-per-gas 130
               :gas-limit 21000
               :to recipient
               :max-fee-per-blob-gas 1
               :blob-versioned-hashes
               (list (hash32-from-hex
                      "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")))
              private-key))
           (sender-key
             (ethereum-lisp.core::engine-payload-store-pending-sender-key
              queued-conflict))
           (block
             (make-block
              :header
              (make-block-header :number 0
                                 :parent-hash (zero-hash32)
                                 :state-root +empty-trie-hash+
                                 :gas-used 0)
              :transactions
              (list mined-conflict queued-exact basefee-exact blob-exact))))
      (is (not (string=
                (hash32-to-hex (transaction-hash queued-conflict))
                (hash32-to-hex (transaction-hash mined-conflict)))))
      (is (bytes= (address-bytes (transaction-sender queued-conflict))
                  (address-bytes (transaction-sender mined-conflict))))
      (put-queued store queued-conflict)
      (put-queued store queued-exact)
      (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
       store
       basefee-exact)
      (ethereum-lisp.core::engine-payload-store-put-blob-transaction
       store
       blob-exact)
      (is (= 2
             (ethereum-lisp.core::engine-payload-store-queued-transaction-count
              store)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
              store)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-blob-transaction-count
              store)))
      (engine-payload-store-put-block store block)
      (let ((queued-sender-transactions
              (gethash
               sender-key
               (ethereum-lisp.core::engine-payload-store-queued-sender-index
                store))))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-queued-transaction-count
                store)))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
                store)))
        (is (= 0
               (ethereum-lisp.core::engine-payload-store-blob-transaction-count
                store)))
        (is (null queued-sender-transactions))))))

(deftest engine-payload-store-requires-recoverable-included-senders-with-txpool
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (pending-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (polluted-transaction
           (make-dynamic-fee-transaction
            :chain-id 1
            :nonce 4
            :max-priority-fee-per-gas 0
            :max-fee-per-gas #x0fa0
            :gas-limit #x84d0
            :to recipient
            :value 0
            :y-parity 1
            :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
            :s #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1))
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 0)
            :transactions (list polluted-transaction)))
         (block-hash (block-hash block))
         (polluted-hash (transaction-hash polluted-transaction)))
    (is (null (transaction-sender polluted-transaction)))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store pending-transaction)
    (signals block-validation-error
      (engine-payload-store-put-block store block))
    (is (null (chain-store-known-block store block-hash)))
    (is (null (chain-store-transaction-location store polluted-hash)))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (eq pending-transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store
             (transaction-hash pending-transaction))))))

(deftest engine-payload-store-replaces-same-sender-nonce-with-price-bump
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (private-key 1)
         (base-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (underpriced-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 109
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (replacement-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 4
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender base-transaction)
                (zero-address))))
         (nonce-key (write-to-string
                     (transaction-nonce base-transaction)
                     :base 10)))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store base-transaction)
    (signals block-validation-error
      (ethereum-lisp.core::engine-payload-store-put-pending-transaction
       store underpriced-transaction))
    (is (= 1
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (eq base-transaction
            (ethereum-lisp.core::engine-payload-store-pending-transaction
             store (transaction-hash base-transaction))))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store replacement-transaction)
    (let* ((sender-index
             (ethereum-lisp.core::engine-payload-store-pending-transactions-by-sender
              store))
           (sender-transactions (gethash sender-key sender-index)))
      (is (= 1
             (ethereum-lisp.core::engine-payload-store-pending-transaction-count
              store)))
      (is (null
           (ethereum-lisp.core::engine-payload-store-pending-transaction
            store (transaction-hash base-transaction))))
      (is (eq replacement-transaction
              (ethereum-lisp.core::engine-payload-store-pending-transaction
               store (transaction-hash replacement-transaction))))
      (is (eq replacement-transaction
              (gethash nonce-key sender-transactions))))))

(deftest engine-pending-transaction-filter-records-hashes-in-order
  (let ((filter
          (ethereum-lisp.core::make-engine-pending-transaction-filter))
        (first-hash
          (hash32-from-hex
           "0x0101010101010101010101010101010101010101010101010101010101010101"))
        (second-hash
          (hash32-from-hex
           "0x0202020202020202020202020202020202020202020202020202020202020202")))
    (is (eq filter
            (ethereum-lisp.core::engine-pending-transaction-filter-record-hash
             filter
             first-hash)))
    (ethereum-lisp.core::engine-pending-transaction-filter-record-hash
     filter
     second-hash)
    (is (equal
         (list first-hash second-hash)
         (ethereum-lisp.core::engine-pending-transaction-filter-hashes
          filter)))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-transaction-filter-record-hash
       filter
       (make-array 31 :element-type '(unsigned-byte 8) :initial-element 0)))))

(deftest engine-pending-txpool-rejects-unrecoverable-sender
  (let* ((txpool (ethereum-lisp.core::make-engine-pending-txpool))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (make-legacy-transaction
            :nonce 0
            :gas-price 100
            :gas-limit 21000
            :to recipient))
         (zero-sender-key (address-to-hex (zero-address))))
    (is (null (transaction-sender transaction)))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
       txpool
       transaction))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-txpool-put-queued-transaction
       txpool
       transaction))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-txpool-put-basefee-transaction
       txpool
       transaction))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-txpool-put-blob-transaction
       txpool
       transaction))
    (is (= 0
           (ethereum-lisp.core::engine-pending-txpool-pending-count
            txpool)))
    (is (= 0
           (ethereum-lisp.core::engine-pending-txpool-queued-count
            txpool)))
    (is (= 0
           (ethereum-lisp.core::engine-pending-txpool-basefee-count
            txpool)))
    (is (= 0
           (ethereum-lisp.core::engine-pending-txpool-blob-count
            txpool)))
    (is (null
         (gethash
          zero-sender-key
          (ethereum-lisp.core::engine-pending-txpool-transactions-by-sender
           txpool))))
    (is (null
         (gethash
          zero-sender-key
          (ethereum-lisp.core::engine-pending-txpool-queued-transactions-by-sender
           txpool))))
    (is (null
         (gethash
          zero-sender-key
          (ethereum-lisp.core::engine-pending-txpool-basefee-transactions-by-sender
           txpool))))
    (is (null
         (gethash
          zero-sender-key
          (ethereum-lisp.core::engine-pending-txpool-blob-transactions-by-sender
           txpool))))))

(deftest engine-pending-txpool-replaces-same-sender-nonce-directly
  (let* ((txpool (ethereum-lisp.core::make-engine-pending-txpool))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (private-key 1)
         (base-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (underpriced-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 109
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (replacement-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender base-transaction)
                (zero-address))))
         (nonce-key (write-to-string
                     (transaction-nonce base-transaction)
                     :base 10)))
    (multiple-value-bind (stored inserted-p)
        (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
         txpool
         base-transaction)
      (is (eq base-transaction stored))
      (is inserted-p))
    (is (= 1
           (ethereum-lisp.core::engine-pending-txpool-pending-count
            txpool)))
    (is (eq base-transaction
            (ethereum-lisp.core::engine-pending-txpool-pending-transaction
             txpool
             (transaction-hash base-transaction))))
    (is (equal (list base-transaction)
               (ethereum-lisp.core::engine-pending-txpool-pending-transactions
                txpool)))
    (multiple-value-bind (stored inserted-p)
        (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
         txpool
         base-transaction)
      (is (eq base-transaction stored))
      (is (null inserted-p)))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
       txpool
       underpriced-transaction))
    (multiple-value-bind (stored inserted-p)
        (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
         txpool
         replacement-transaction)
      (is (eq replacement-transaction stored))
      (is inserted-p))
    (let* ((sender-index
             (ethereum-lisp.core::engine-pending-txpool-transactions-by-sender
              txpool))
           (sender-transactions (gethash sender-key sender-index)))
      (is (= 1
             (ethereum-lisp.core::engine-pending-txpool-pending-count
              txpool)))
      (is (null
           (ethereum-lisp.core::engine-pending-txpool-pending-transaction
            txpool
            (transaction-hash base-transaction))))
      (is (eq replacement-transaction
              (ethereum-lisp.core::engine-pending-txpool-pending-transaction
               txpool
               (transaction-hash replacement-transaction))))
      (is (eq replacement-transaction
              (gethash nonce-key sender-transactions))))))

(deftest engine-pending-txpool-rejects-zero-fee-same-nonce-replacement
  (let* ((txpool (ethereum-lisp.core::make-engine-pending-txpool))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (alternate-recipient
           (address-from-hex "0x4545454545454545454545454545454545454545"))
         (private-key 1)
         (base-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 7
             :gas-price 0
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (same-price-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 7
             :gas-price 0
             :gas-limit 21000
             :to alternate-recipient)
            private-key
            1))
         (bumped-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 7
             :gas-price 1
             :gas-limit 21000
             :to alternate-recipient)
            private-key
            1)))
    (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
     txpool
     base-transaction)
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
       txpool
       same-price-transaction))
    (is (= 1
           (ethereum-lisp.core::engine-pending-txpool-pending-count
            txpool)))
    (is (eq base-transaction
            (ethereum-lisp.core::engine-pending-txpool-pending-transaction
             txpool
             (transaction-hash base-transaction))))
    (is (null
         (ethereum-lisp.core::engine-pending-txpool-pending-transaction
          txpool
          (transaction-hash same-price-transaction))))
    (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
     txpool
     bumped-transaction)
    (is (= 1
           (ethereum-lisp.core::engine-pending-txpool-pending-count
            txpool)))
    (is (null
         (ethereum-lisp.core::engine-pending-txpool-pending-transaction
          txpool
          (transaction-hash base-transaction))))
    (is (eq bumped-transaction
            (ethereum-lisp.core::engine-pending-txpool-pending-transaction
             txpool
             (transaction-hash bumped-transaction))))))

(deftest engine-pending-txpool-indexes-basefee-and-blob-subpools
  (let* ((txpool (ethereum-lisp.core::make-engine-pending-txpool))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (private-key 1)
         (basefee-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (underpriced-basefee
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 109
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (replacement-basefee
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 6
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (blob-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 7
             :gas-price 120
             :gas-limit 21000
             :to recipient)
            private-key
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender basefee-transaction)
                (zero-address)))))
    (ethereum-lisp.core::engine-pending-txpool-put-basefee-transaction
     txpool
     basefee-transaction)
    (ethereum-lisp.core::engine-pending-txpool-put-blob-transaction
     txpool
     blob-transaction)
    (is (eq basefee-transaction
            (ethereum-lisp.core::engine-pending-txpool-basefee-transaction
             txpool
             (transaction-hash basefee-transaction))))
    (is (eq blob-transaction
            (ethereum-lisp.core::engine-pending-txpool-blob-transaction
             txpool
             (transaction-hash blob-transaction))))
    (let ((basefee-by-nonce
            (gethash
             sender-key
             (ethereum-lisp.core::engine-pending-txpool-basefee-transactions-by-sender
              txpool)))
          (blob-by-nonce
            (gethash
             sender-key
             (ethereum-lisp.core::engine-pending-txpool-blob-transactions-by-sender
              txpool))))
      (is (eq basefee-transaction (gethash "6" basefee-by-nonce)))
      (is (eq blob-transaction (gethash "7" blob-by-nonce))))
    (signals block-validation-error
      (ethereum-lisp.core::engine-pending-txpool-put-basefee-transaction
       txpool
       underpriced-basefee))
    (ethereum-lisp.core::engine-pending-txpool-put-basefee-transaction
     txpool
     replacement-basefee)
    (let ((basefee-by-nonce
            (gethash
             sender-key
             (ethereum-lisp.core::engine-pending-txpool-basefee-transactions-by-sender
              txpool))))
      (is (= 1
             (ethereum-lisp.core::engine-pending-txpool-basefee-count
              txpool)))
      (is (eq replacement-basefee (gethash "6" basefee-by-nonce)))
      (is (null
           (gethash
            (ethereum-lisp.core::engine-pending-txpool-hash-key
             (transaction-hash basefee-transaction))
            (ethereum-lisp.core::engine-pending-txpool-basefee-transactions
             txpool)))))
    (ethereum-lisp.core::engine-pending-txpool-remove-basefee-transaction
     txpool
     (transaction-hash replacement-basefee))
    (ethereum-lisp.core::engine-pending-txpool-remove-blob-transaction
     txpool
     (transaction-hash blob-transaction))
    (is (null
         (ethereum-lisp.core::engine-pending-txpool-basefee-transaction
          txpool
          (transaction-hash replacement-basefee))))
    (is (null
         (ethereum-lisp.core::engine-pending-txpool-blob-transaction
          txpool
          (transaction-hash blob-transaction))))
    (is (= 0
           (ethereum-lisp.core::engine-pending-txpool-basefee-count
            txpool)))
    (is (= 0
           (ethereum-lisp.core::engine-pending-txpool-blob-count
            txpool)))
    (is (null
         (gethash
          sender-key
          (ethereum-lisp.core::engine-pending-txpool-basefee-transactions-by-sender
           txpool))))
    (is (null
         (gethash
          sender-key
          (ethereum-lisp.core::engine-pending-txpool-blob-transactions-by-sender
           txpool))))))

(deftest engine-payload-store-rejects-non-blob-blob-subpool-insertion
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1)))
    (signals block-validation-error
      (ethereum-lisp.core::engine-payload-store-put-blob-transaction
       store
       transaction))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-blob-transaction-count
            store)))
    (is (null
         (ethereum-lisp.core::engine-payload-store-pooled-transaction
          store
          (transaction-hash transaction))))))

(deftest engine-payload-store-rejects-blob-nonblob-subpool-insertion
  (let* ((recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (fixture-sign-blob-transaction
            (make-blob-transaction
             :chain-id 1
             :nonce 0
             :max-priority-fee-per-gas 1
             :max-fee-per-gas 100
             :gas-limit 21000
             :to recipient
             :max-fee-per-blob-gas 1
             :blob-versioned-hashes
             (list (hash32-from-hex
                    "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")))
            1))
         (hash (transaction-hash transaction)))
    (dolist (putter
              (list #'ethereum-lisp.core::engine-payload-store-put-pending-transaction
                    #'ethereum-lisp.core::engine-payload-store-put-queued-transaction
                    #'ethereum-lisp.core::engine-payload-store-put-basefee-transaction))
      (let ((store (make-engine-payload-memory-store)))
        (signals block-validation-error
          (funcall putter store transaction))
        (is (= 0
               (+ (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   store)
                  (ethereum-lisp.core::engine-payload-store-queued-transaction-count
                   store)
                  (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
                   store)
                  (ethereum-lisp.core::engine-payload-store-blob-transaction-count
                   store))))
        (is (null
             (ethereum-lisp.core::engine-payload-store-pooled-transaction
              store
              hash)))))))

(deftest engine-payload-store-uses-sender-index-for-pending-account-view
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (sender-nonce-two
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 2
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-nonce-zero
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 1
             :gas-limit 21000
             :to recipient)
            1
            1))
         (replacement
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 3
             :gas-limit 21000
             :to recipient)
            1
            1))
         (other-sender
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            2
            1))
         (sender (transaction-sender sender-nonce-zero :expected-chain-id 1)))
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     sender-nonce-two)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     other-sender)
    (ethereum-lisp.core::engine-payload-store-put-pending-transaction
     store
     sender-nonce-zero)
    (let ((sender-transactions
            (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
             store
             sender)))
      (is (= 2 (length sender-transactions)))
      (is (eq sender-nonce-zero (first sender-transactions)))
      (is (eq sender-nonce-two (second sender-transactions))))
    (is (=
         (+ (ethereum-lisp.core::engine-payload-store-txpool-upfront-cost
             sender-nonce-two)
            (ethereum-lisp.core::engine-payload-store-txpool-upfront-cost
             replacement))
         (ethereum-lisp.core::engine-payload-store-pending-sender-expenditure
          store
          sender
          replacement)))))

(deftest txpool-rpc-views-use-subpool-sender-indexes
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json store config)
             (parse-json
              (engine-rpc-handle-request-json json store config))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1))
           (recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (pending-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 0
               :gas-price 100
               :gas-limit 21000
               :to recipient)
              1
              1))
           (queued-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 110
               :gas-limit 21000
               :to recipient)
              1
              1))
           (basefee-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 2
               :gas-price 120
               :gas-limit 21000
               :to recipient)
              1
              1))
           (blob-transaction
             (fixture-sign-blob-transaction
              (make-blob-transaction
               :chain-id 1
               :nonce 3
               :max-priority-fee-per-gas 1
               :max-fee-per-gas 130
               :gas-limit 21000
               :to recipient
               :max-fee-per-blob-gas 1
               :blob-versioned-hashes
               (list (hash32-from-hex
                      "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")))
              1))
           (queued-high-nonce-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 10
               :gas-price 150
               :gas-limit 21000
               :to recipient)
              1
              1))
           (other-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 140
               :gas-limit 21000
               :to recipient)
              2
              1))
           (sender
             (transaction-sender pending-transaction :expected-chain-id 1))
           (sender-key (address-to-hex sender))
           (other-sender
             (transaction-sender other-transaction :expected-chain-id 1)))
      (ethereum-lisp.core::engine-payload-store-put-pending-transaction
       store
       pending-transaction)
      (ethereum-lisp.core::engine-payload-store-put-queued-transaction
       store
       queued-transaction)
      (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
       store
       basefee-transaction)
      (ethereum-lisp.core::engine-payload-store-put-blob-transaction
       store
       blob-transaction)
      (ethereum-lisp.core::engine-payload-store-put-queued-transaction
       store
       queued-high-nonce-transaction)
      (ethereum-lisp.core::engine-payload-store-put-queued-transaction
       store
       other-transaction)
      (let* ((response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":88,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 sender-key
                 "\"]}")
                store
                config))
             (content-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":90,\"method\":\"txpool_content\",\"params\":[]}"
                store
                config))
             (inspect-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":91,\"method\":\"txpool_inspect\",\"params\":[]}"
                store
                config))
             (other-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":92,"
                 "\"method\":\"txpool_contentFrom\",\"params\":[\""
                 (address-to-hex other-sender)
                 "\"]}")
                store
                config))
             (result (field response "result"))
             (pending (field result "pending"))
             (queued (field result "queued"))
             (content-queued
               (field (field (field content-response "result") "queued")
                      sender-key))
             (inspect-queued
               (field (field (field inspect-response "result") "queued")
                      sender-key))
             (other-queued (field (field other-response "result")
                                  "queued")))
        (is (string= (hash32-to-hex
                      (transaction-hash pending-transaction))
                     (field (field pending "0") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash queued-transaction))
                     (field (field queued "1") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash basefee-transaction))
                     (field (field queued "2") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash blob-transaction))
                     (field (field queued "3") "hash")))
        (is (null (field queued "4")))
        (is (equal '("1" "2" "3" "10") (mapcar #'car queued)))
        (is (string= (hash32-to-hex
                      (transaction-hash queued-transaction))
                     (field (field content-queued "1") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash basefee-transaction))
                     (field (field content-queued "2") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash blob-transaction))
                     (field (field content-queued "3") "hash")))
        (is (string= (hash32-to-hex
                      (transaction-hash queued-high-nonce-transaction))
                     (field (field content-queued "10") "hash")))
        (is (equal '("1" "2" "3" "10") (mapcar #'car content-queued)))
        (is (search "110 wei" (field inspect-queued "1")))
        (is (search "120 wei" (field inspect-queued "2")))
        (is (search "130 wei" (field inspect-queued "3")))
        (is (search "150 wei" (field inspect-queued "10")))
        (is (equal '("1" "2" "3" "10") (mapcar #'car inspect-queued)))
        (is (string= (hash32-to-hex
                      (transaction-hash other-transaction))
                     (field (field other-queued "1") "hash")))))))

(deftest engine-pending-txpool-copy-isolates-sender-indexes
  (let* ((txpool (ethereum-lisp.core::make-engine-pending-txpool))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 7
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender-key
           (address-to-hex
            (or (transaction-sender transaction)
                (zero-address))))
         (nonce-key (write-to-string
                     (transaction-nonce transaction)
                     :base 10))
         (original-encoding (transaction-encoding transaction)))
    (ethereum-lisp.core::engine-pending-txpool-put-pending-transaction
     txpool
     transaction)
    (let* ((copy (ethereum-lisp.core::engine-pending-txpool-copy txpool))
           (sender-transactions
             (gethash
              sender-key
              (ethereum-lisp.core::engine-pending-txpool-transactions-by-sender
               txpool)))
           (copy-sender-transactions
             (gethash
              sender-key
              (ethereum-lisp.core::engine-pending-txpool-transactions-by-sender
               copy)))
           (copy-indexed-transaction
             (gethash nonce-key copy-sender-transactions))
           (copy-pending-transaction
             (ethereum-lisp.core::engine-pending-txpool-pending-transaction
              copy
              (transaction-hash transaction))))
      (is (not (eq txpool copy)))
      (is (not (eq
                (ethereum-lisp.core::engine-pending-txpool-transactions
                 txpool)
                (ethereum-lisp.core::engine-pending-txpool-transactions
                 copy))))
      (is (not (eq sender-transactions copy-sender-transactions)))
      (ethereum-lisp.core::engine-pending-txpool-remove-pending-transaction
       txpool
       (transaction-hash transaction))
      (is (= 0
             (hash-table-count
              (ethereum-lisp.core::engine-pending-txpool-transactions
               txpool))))
      (is (= 1
             (hash-table-count
              (ethereum-lisp.core::engine-pending-txpool-transactions
               copy))))
      (is (not (eq transaction copy-indexed-transaction)))
      (is (eq copy-pending-transaction copy-indexed-transaction))
      (is (bytes= original-encoding
                  (transaction-encoding copy-indexed-transaction)))
      (setf (legacy-transaction-gas-price transaction) 999)
      (is (bytes= original-encoding
                  (transaction-encoding copy-indexed-transaction)))
      (is (not (bytes= original-encoding
                       (transaction-encoding transaction)))))))

