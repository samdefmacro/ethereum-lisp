(in-package #:ethereum-lisp.test)

(deftest chain-store-interface-wraps-memory-payload-store
  (let* ((store (make-engine-payload-memory-store))
         (payload-id #(3 2 3 4 5 6 7 8))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (storage-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (transaction
           (make-legacy-transaction
            :nonce 1
            :gas-price 2
            :gas-limit 21000
            :to address
            :value 3
            :v 27
            :r 4
            :s 5))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (header (make-block-header :number 43
                                    :state-root +empty-trie-hash+))
         (block (make-block :header header
                            :transactions (list transaction)
                            :receipts (list receipt)))
         (competing-block
           (make-block
            :header
            (make-block-header :number 43
                               :timestamp 1
                               :extra-data #(99))))
         (block-hash (block-hash block))
         (competing-block-hash (block-hash competing-block))
         (transaction-hash (transaction-hash transaction))
         (forkchoice-state
           (make-forkchoice-state
            :head-block-hash block-hash
            :safe-block-hash block-hash
            :finalized-block-hash block-hash))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 3
            :block block)))
    (is (eq block
            (chain-store-put-block store block :state-available-p t)))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-known-block store block-hash))))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-block-by-number store 43))))
    (is (string= (hash32-to-hex block-hash)
                 (hash32-to-hex (chain-store-canonical-hash store 43))))
    (is (= 43 (chain-store-head-number store)))
    (is (= 43 (chain-store-block-tag-number store "latest")))
    (signals block-validation-error
      (chain-store-block-tag-number store "safe"))
    (signals block-validation-error
      (chain-store-block-tag-number store "finalized"))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-latest-block store))))
    (chain-store-put-block store competing-block)
    (is (bytes= (block-rlp competing-block)
                (block-rlp
                 (chain-store-known-block store competing-block-hash))))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-block-by-number store 43))))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-latest-block store))))
    (is (string= (hash32-to-hex block-hash)
                 (hash32-to-hex (chain-store-canonical-hash store 43))))
    (is (chain-store-state-available-p store block-hash))
    (is (= 99
           (chain-store-put-account-balance
            store block-hash address 99)))
    (is (= 99
           (chain-store-account-balance store block-hash address)))
    (is (= 7
           (chain-store-put-account-nonce store block-hash address 7)))
    (is (= 7
           (chain-store-account-nonce store block-hash address)))
    (is (bytes= #(1 2 3)
                (chain-store-put-account-code
                 store block-hash address #(1 2 3))))
    (is (bytes= #(1 2 3)
                (chain-store-account-code store block-hash address)))
    (is (= 5
           (chain-store-put-account-storage
            store block-hash address storage-slot 5)))
    (is (= 5
           (chain-store-account-storage
            store block-hash address storage-slot)))
    (let ((location
            (chain-store-transaction-location store transaction-hash)))
      (is (typep location 'engine-transaction-location))
      (is (bytes= (block-rlp block)
                  (block-rlp (engine-transaction-location-block location))))
      (is (= 0 (engine-transaction-location-index location)))
      (is (bytes= (transaction-encoding transaction)
                  (transaction-encoding
                   (engine-transaction-location-transaction location))))
      (is (bytes= (receipt-rlp receipt)
                  (receipt-rlp
                   (engine-transaction-location-receipt location)))))
    (let ((receipts (chain-store-block-receipts store block-hash)))
      (is (= 1 (length receipts)))
      (is (bytes= (receipt-rlp receipt)
                  (receipt-rlp (first receipts)))))
    (is (eq store
            (chain-store-update-forkchoice-checkpoints
             store forkchoice-state)))
    (is (typep (chain-store-head-checkpoint store)
               'chain-store-checkpoint))
    (is (eq :head
            (chain-store-checkpoint-label
             (chain-store-head-checkpoint store))))
    (is (string= (hash32-to-hex block-hash)
                 (hash32-to-hex
                  (chain-store-checkpoint-block-hash
                   (chain-store-head-checkpoint store)))))
    (is (typep (chain-store-safe-checkpoint store)
               'chain-store-checkpoint))
    (is (eq :safe
            (chain-store-checkpoint-label
             (chain-store-safe-checkpoint store))))
    (is (typep (chain-store-finalized-checkpoint store)
               'chain-store-checkpoint))
    (is (eq :finalized
            (chain-store-checkpoint-label
             (chain-store-finalized-checkpoint store))))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-head-block store))))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-safe-block store))))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-finalized-block store))))
    (is (= 43 (chain-store-block-tag-number store "safe")))
    (is (= 43 (chain-store-block-tag-number store "finalized")))
    (is (eq prepared-payload
            (chain-store-put-prepared-payload store prepared-payload)))
    (is (chain-store-prepared-payload store payload-id))))

(deftest chain-store-put-block-copies-known-block-record
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (log-data (vector #x01 #x02))
         (transaction
           (make-legacy-transaction :nonce 1
                                    :gas-price 7
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3))
         (receipt
           (make-receipt
            :status 1
            :cumulative-gas-used 21000
            :logs
            (list
             (make-log-entry :address recipient
                             :topics (list (zero-hash32))
                             :data log-data))))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 21000
                               :extra-data #(#x03 #x04))
            :transactions (list transaction)
            :receipts (list receipt)))
         (block-hash (block-hash block))
         (transaction-hash (transaction-hash transaction))
         (expected-block-rlp (block-rlp block))
         (expected-transaction-encoding (transaction-encoding transaction))
         (expected-receipt-rlp (receipt-rlp receipt)))
    (chain-store-put-block store block :state-available-p t)
    (setf (block-header-extra-data (block-header block)) #(#xff)
          (legacy-transaction-gas-price transaction) 99
          (receipt-status receipt) 0
          (aref log-data 0) #xee)
    (is (not (eq block (chain-store-known-block store block-hash))))
    (is (bytes= expected-block-rlp
                (block-rlp (chain-store-known-block store block-hash))))
    (is (bytes= expected-block-rlp
                (block-rlp (chain-store-block-by-number store 9))))
    (let ((location (chain-store-transaction-location store transaction-hash)))
      (is (typep location 'engine-transaction-location))
      (is (bytes= expected-block-rlp
                  (block-rlp (engine-transaction-location-block location))))
      (is (bytes= expected-transaction-encoding
                  (transaction-encoding
                   (engine-transaction-location-transaction location))))
      (is (bytes= expected-receipt-rlp
                  (receipt-rlp
                   (engine-transaction-location-receipt location)))))
    (let ((receipts (chain-store-block-receipts store block-hash)))
      (is (= 1 (length receipts)))
      (is (bytes= expected-receipt-rlp
                  (receipt-rlp (first receipts)))))))

(deftest chain-store-transaction-location-and-receipt-reads-are-copied
  (let* ((store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (transaction
           (make-legacy-transaction :nonce 2
                                    :gas-price 9
                                    :gas-limit 21000
                                    :to recipient
                                    :value 5))
         (receipt
           (make-receipt
            :status 1
            :cumulative-gas-used 21000
            :logs
            (list
             (make-log-entry :address recipient
                             :topics (list (zero-hash32))
                             :data (vector #x0a #x0b)))))
         (block
           (make-block
            :header
            (make-block-header :number 10
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 21000)
            :transactions (list transaction)
            :receipts (list receipt)))
         (block-hash (block-hash block))
         (transaction-hash (transaction-hash transaction))
         (expected-block-rlp (block-rlp block))
         (expected-transaction-encoding (transaction-encoding transaction))
         (expected-receipt-rlp (receipt-rlp receipt)))
    (chain-store-put-block store block :state-available-p t)
    (let* ((location
             (chain-store-transaction-location store transaction-hash))
           (location-block (engine-transaction-location-block location))
           (location-transaction
             (engine-transaction-location-transaction location))
           (location-receipt
             (engine-transaction-location-receipt location))
           (location-log
             (first (receipt-logs location-receipt)))
           (location-log-data (log-entry-data location-log)))
      (is (not (eq block location-block)))
      (is (not (eq transaction location-transaction)))
      (is (not (eq receipt location-receipt)))
      (setf (block-header-extra-data (block-header location-block)) #(#xff)
            (legacy-transaction-gas-price location-transaction) 99
            (receipt-status location-receipt) 0
            (aref location-log-data 0) #xee))
    (let* ((receipts (chain-store-block-receipts store block-hash))
           (receipt-copy (first receipts))
           (receipt-log-data (log-entry-data (first (receipt-logs receipt-copy)))))
      (is (not (eq receipt receipt-copy)))
      (setf (receipt-status receipt-copy) 0
            (aref receipt-log-data 1) #xdd))
    (let ((location
            (chain-store-transaction-location store transaction-hash)))
      (is (bytes= expected-block-rlp
                  (block-rlp (engine-transaction-location-block location))))
      (is (bytes= expected-transaction-encoding
                  (transaction-encoding
                   (engine-transaction-location-transaction location))))
      (is (bytes= expected-receipt-rlp
                  (receipt-rlp
                   (engine-transaction-location-receipt location)))))
    (let ((receipts (chain-store-block-receipts store block-hash)))
      (is (= 1 (length receipts)))
      (is (bytes= expected-receipt-rlp
                  (receipt-rlp (first receipts)))))))

