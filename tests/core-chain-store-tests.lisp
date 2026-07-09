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

(deftest chain-store-export-indexes-to-kv-syncs-canonical-and-checkpoints
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-index-export-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :timestamp 0
                               :gas-limit 30000000)))
         (branch-a-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 1
                               :gas-limit 30000000)))
         (branch-a-2
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash branch-a-1)
                               :timestamp 2
                               :gas-limit 30000000)))
         (branch-b-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 3
                               :extra-data #(1)
                               :gas-limit 30000000))))
    (unwind-protect
         (progn
           (chain-store-put-block store genesis :state-available-p t)
           (chain-store-put-block store branch-a-1 :state-available-p t)
           (chain-store-put-block store branch-a-2 :state-available-p t)
           (chain-store-update-forkchoice-checkpoints
            store
            (make-forkchoice-state
             :head-block-hash (block-hash branch-a-2)
             :safe-block-hash (block-hash genesis)
             :finalized-block-hash (block-hash genesis)))
           (let ((database (make-file-key-value-database path)))
             (is (eq database
                     (chain-store-export-indexes-to-kv store database))))
           (chain-store-put-block store branch-b-1 :state-available-p t)
           (chain-store-set-canonical-head store (block-hash branch-b-1))
           (chain-store-update-forkchoice-checkpoints
            store
            (make-forkchoice-state
             :head-block-hash (block-hash branch-b-1)
             :safe-block-hash (block-hash genesis)
             :finalized-block-hash (block-hash genesis)))
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-indexes-to-kv store database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database 0)
               (is present-p)
               (is (bytes= (hash32-bytes (block-hash genesis)) value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database 1)
               (is present-p)
               (is (bytes= (hash32-bytes (block-hash branch-b-1)) value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database 2 :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (is (= 2 (length (kv-chain-canonical-hashes database))))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-checkpoint database :head)
               (is present-p)
               (is (bytes= (hash32-bytes (block-hash branch-b-1)) value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-checkpoint database :safe)
               (is present-p)
               (is (bytes= (hash32-bytes (block-hash genesis)) value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-checkpoint database :finalized)
               (is present-p)
               (is (bytes= (hash32-bytes (block-hash genesis)) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-export-block-records-to-kv-persists-known-blocks
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-block-record-export-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction
           (make-legacy-transaction :nonce 1
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3
                                    :v 27
                                    :r 4
                                    :s 5))
         (receipt
           (make-receipt :status 1 :cumulative-gas-used 21000))
         (block
           (make-block
            :header
            (make-block-header :number 7
                               :parent-hash (zero-hash32)
                               :timestamp 7
                               :gas-limit 30000000)
            :transactions (list transaction)
            :receipts (list receipt)))
         (side-block
           (make-block
            :header
            (make-block-header :number 7
                               :parent-hash (zero-hash32)
                               :timestamp 8
                               :extra-data #(1)
                               :gas-limit 30000000)))
         (block-id (hash32-bytes (block-hash block)))
         (side-block-id (hash32-bytes (block-hash side-block)))
         (receipt-record
           (rlp-encode
            (make-rlp-list
             (transaction-receipt-encoding transaction receipt)))))
    (unwind-protect
         (progn
           (chain-store-put-block store block :state-available-p t)
           (chain-store-put-block store side-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (is (eq database
                     (chain-store-export-block-records-to-kv
                      store database))))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :block block-id)
               (is present-p)
               (is (bytes= (block-rlp block) value))
               (is (bytes= (block-rlp (block-from-rlp value)) value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :header block-id)
               (is present-p)
               (is (bytes= (block-header-rlp (block-header block)) value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :receipt block-id)
               (is present-p)
               (is (bytes= receipt-record value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :block side-block-id)
               (is present-p)
               (is (bytes= (block-rlp side-block) value)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-export-transaction-locations-to-kv-syncs-canonical
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-transaction-location-export-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (log-entry
           (make-log-entry :address recipient :data #(9)))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :timestamp 0
                               :gas-limit 30000000)))
         (branch-a-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 1
                               :gas-limit 30000000)))
         (old-prefix-transaction
           (make-legacy-transaction :nonce 1
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3
                                    :data #(1)
                                    :v 27
                                    :r 4
                                    :s 5))
         (old-canonical-transaction
           (make-legacy-transaction :nonce 2
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3
                                    :data #(2)
                                    :v 27
                                    :r 4
                                    :s 5))
         (old-canonical-receipt
           (make-receipt :status 1 :cumulative-gas-used 42000))
         (branch-a-2
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash branch-a-1)
                               :timestamp 2
                               :gas-limit 30000000)
            :transactions
            (list old-prefix-transaction old-canonical-transaction)
            :receipts
            (list (make-receipt :status 1
                                :cumulative-gas-used 21000
                                :logs (list log-entry))
                  old-canonical-receipt)))
         (branch-b-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 3
                               :extra-data #(1)
                               :gas-limit 30000000)))
         (new-canonical-transaction
           (make-legacy-transaction :nonce 3
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 4
                                    :data #(3)
                                    :v 27
                                    :r 4
                                    :s 5))
         (branch-b-2
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash branch-b-1)
                               :timestamp 4
                               :extra-data #(2)
                               :gas-limit 30000000)
            :transactions (list new-canonical-transaction)
            :receipts (list (make-receipt :status 1
                                          :cumulative-gas-used 21000))))
         (old-transaction-id
           (hash32-bytes (transaction-hash old-canonical-transaction)))
         (new-transaction-id
           (hash32-bytes (transaction-hash new-canonical-transaction))))
    (labels ((location-record-values (record)
               (let ((items (rlp-list-items (rlp-decode-one record))))
                 (values (first items)
                         (bytes-to-integer (second items))
                         (bytes-to-integer (third items))))))
      (unwind-protect
           (progn
             (dolist (block (list genesis branch-a-1 branch-a-2
                                  branch-b-1 branch-b-2))
               (chain-store-put-block store block :state-available-p t))
             (let ((database (make-file-key-value-database path)))
               (is (eq database
                       (chain-store-export-transaction-locations-to-kv
                        store database))))
             (let ((database (make-file-key-value-database path)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database :transaction-location old-transaction-id)
                 (is present-p)
                 (multiple-value-bind (block-hash index log-index-start)
                     (location-record-values value)
                   (is (bytes= (hash32-bytes (block-hash branch-a-2))
                               block-hash))
                   (is (= 1 index))
                   (is (= 1 log-index-start))))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database :transaction-location new-transaction-id :missing)
                 (is (eq :missing value))
                 (is (not present-p))))
             (chain-store-set-canonical-head store (block-hash branch-b-2))
             (let ((database (make-file-key-value-database path)))
               (chain-store-export-transaction-locations-to-kv store database))
             (let ((database (make-file-key-value-database path)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database :transaction-location old-transaction-id :missing)
                 (is (eq :missing value))
                 (is (not present-p)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record
                    database :transaction-location new-transaction-id)
                 (is present-p)
                 (multiple-value-bind (block-hash index log-index-start)
                     (location-record-values value)
                   (is (bytes= (hash32-bytes (block-hash branch-b-2))
                               block-hash))
                   (is (= 0 index))
                   (is (= 0 log-index-start))))))
        (when (probe-file path)
          (delete-file path))))))

(deftest chain-store-export-state-records-to-kv-persists-snapshots
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-state-record-export-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (address-a
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (address-b
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (slot-a
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000003"))
         (slot-b
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000004"))
         (block-a
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)))
         (block-b
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash block-a)
                               :timestamp 2
                               :gas-limit 30000000)))
         (block-a-id (hash32-bytes (block-hash block-a)))
         (block-b-id (hash32-bytes (block-hash block-b))))
    (labels ((state-record-accounts (record)
               (rlp-list-items (rlp-decode-one record)))
             (account-fields (account-record)
               (let ((items (rlp-list-items account-record)))
                 (values (first items)
                         (bytes-to-integer (second items))
                         (bytes-to-integer (third items))
                         (fourth items)
                         (rlp-list-items (fifth items)))))
             (storage-entry-fields (entry)
               (let ((items (rlp-list-items entry)))
                 (values (first items)
                         (bytes-to-integer (second items))))))
      (unwind-protect
           (progn
             (chain-store-put-block store block-a :state-available-p t)
             (chain-store-put-block store block-b :state-available-p t)
             (chain-store-put-account-storage store (block-hash block-a)
                                              address-b slot-b 22)
             (chain-store-put-account-balance store (block-hash block-a)
                                              address-a 11)
             (chain-store-put-account-nonce store (block-hash block-a)
                                            address-a 7)
             (chain-store-put-account-code store (block-hash block-a)
                                           address-a #(1 2))
             (chain-store-put-account-storage store (block-hash block-a)
                                              address-a slot-a 33)
             (chain-store-put-account-balance store (block-hash block-b)
                                              address-a 44)
             (let ((database (make-file-key-value-database path)))
               (is (eq database
                       (chain-store-export-state-records-to-kv
                        store database))))
             (let ((database (make-file-key-value-database path)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record database :state block-a-id)
                 (is present-p)
                 (let ((accounts (state-record-accounts value)))
                   (is (= 2 (length accounts)))
                   (multiple-value-bind (address balance nonce code storage)
                       (account-fields (first accounts))
                     (is (bytes= (address-bytes address-a) address))
                     (is (= 11 balance))
                     (is (= 7 nonce))
                     (is (bytes= #(1 2) code))
                     (is (= 1 (length storage)))
                     (multiple-value-bind (slot value)
                         (storage-entry-fields (first storage))
                       (is (bytes= (hash32-bytes slot-a) slot))
                       (is (= 33 value))))
                   (multiple-value-bind (address balance nonce code storage)
                       (account-fields (second accounts))
                     (is (bytes= (address-bytes address-b) address))
                     (is (= 0 balance))
                     (is (= 0 nonce))
                     (is (bytes= #() code))
                     (is (= 1 (length storage)))
                     (multiple-value-bind (slot value)
                         (storage-entry-fields (first storage))
                       (is (bytes= (hash32-bytes slot-b) slot))
                       (is (= 22 value))))))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record database :state block-b-id)
                 (is present-p)
                 (is (= 1 (length (state-record-accounts value))))))
             (chain-store-put-block store block-a)
             (let ((database (make-file-key-value-database path)))
               (chain-store-export-state-records-to-kv store database))
             (let ((database (make-file-key-value-database path)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record database :state block-a-id :missing)
                 (is (eq :missing value))
                 (is (not present-p)))
               (multiple-value-bind (value present-p)
                   (kv-get-chain-record database :state block-b-id)
                 (is present-p)
                 (is (= 1 (length (state-record-accounts value)))))))
        (when (probe-file path)
          (delete-file path))))))

(deftest chain-store-prune-state-before-drops-historical-snapshots
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-state-prune-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (block-a
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)))
         (block-b
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash block-a)
                               :timestamp 2
                               :gas-limit 30000000)))
         (block-a-id (hash32-bytes (block-hash block-a)))
         (block-b-id (hash32-bytes (block-hash block-b))))
    (unwind-protect
         (progn
           (chain-store-put-block store block-a :state-available-p t)
           (chain-store-put-block store block-b :state-available-p t)
           (chain-store-set-canonical-head store (block-hash block-b))
           (chain-store-put-account-balance store (block-hash block-a)
                                            address 11)
           (chain-store-put-account-nonce store (block-hash block-a)
                                          address 7)
           (chain-store-put-account-code store (block-hash block-a)
                                         address #(1 2 3))
           (chain-store-put-account-storage store (block-hash block-a)
                                            address slot 33)
           (chain-store-put-account-balance store (block-hash block-b)
                                            address 44)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-state-records-to-kv store database)
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state block-a-id)
               (declare (ignore value))
               (is present-p)))
           (is (= 1 (chain-store-prune-state-before store 2)))
           (is (not (chain-store-state-available-p store
                                                   (block-hash block-a))))
           (is (chain-store-state-available-p store (block-hash block-b)))
           (is (bytes= (block-rlp block-a)
                       (block-rlp
                        (chain-store-known-block store (block-hash block-a)))))
           (is (bytes= (block-rlp block-a)
                       (block-rlp (chain-store-block-by-number store 1))))
           (is (bytes= (block-rlp block-b)
                       (block-rlp (chain-store-block-by-number store 2))))
           (is (= 0 (chain-store-account-balance
                     store (block-hash block-a) address)))
           (is (= 0 (chain-store-account-nonce
                     store (block-hash block-a) address)))
           (is (bytes= #()
                       (chain-store-account-code
                        store (block-hash block-a) address)))
           (is (= 0 (chain-store-account-storage
                     store (block-hash block-a) address slot)))
           (is (= 44 (chain-store-account-balance
                      store (block-hash block-b) address)))
           (let ((accounts '()))
             (chain-store-for-each-account
              store
              (block-hash block-a)
              (lambda (&rest account)
                (push account accounts)))
             (is (null accounts)))
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-state-records-to-kv store database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state block-a-id :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state block-b-id)
               (declare (ignore value))
               (is present-p)))
           (is (= 0 (chain-store-prune-state-before store 2)))
           (is (= 0 (chain-store-prune-state-before store 3)))
           (is (chain-store-state-available-p store (block-hash block-b)))
           (signals block-validation-error
             (chain-store-prune-state-before store -1)))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-prune-state-before-preserves-implicit-latest-snapshot
  (let* ((store (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (block-a
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)))
         (block-b
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash block-a)
                               :timestamp 2
                               :gas-limit 30000000))))
    (chain-store-put-block store block-a :state-available-p t)
    (chain-store-put-block store block-b :state-available-p t)
    (chain-store-put-account-balance store (block-hash block-a) address 11)
    (chain-store-put-account-balance store (block-hash block-b) address 22)
    (is (= 2 (chain-store-head-number store)))
    (is (null (chain-store-checkpoint-block-hash
               (chain-store-head-checkpoint store))))
    (is (= 1 (chain-store-prune-state-before store 3)))
    (is (not (chain-store-state-available-p store (block-hash block-a))))
    (is (chain-store-state-available-p store (block-hash block-b)))
    (is (= 0 (chain-store-account-balance store (block-hash block-a)
                                          address)))
    (is (= 22 (chain-store-account-balance store (block-hash block-b)
                                           address)))))

(deftest chain-store-prune-state-before-prunes-non-head-checkpoint-state
  (let* ((store (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (finalized
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)))
         (safe
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash finalized)
                               :timestamp 2
                               :gas-limit 30000000)))
         (side
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash finalized)
                               :timestamp 3
                               :gas-limit 30000000)))
         (head
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash safe)
                               :timestamp 4
                               :gas-limit 30000000))))
    (dolist (block (list finalized safe side head))
      (chain-store-put-block store block :state-available-p t))
    (chain-store-update-forkchoice-checkpoints
     store
     (make-forkchoice-state
      :head-block-hash (block-hash head)
      :safe-block-hash (block-hash safe)
      :finalized-block-hash (block-hash finalized)))
    (chain-store-put-account-balance store (block-hash finalized) address 11)
    (chain-store-put-account-balance store (block-hash safe) address 22)
    (chain-store-put-account-balance store (block-hash side) address 33)
    (chain-store-put-account-balance store (block-hash head) address 44)
    (is (= 3 (chain-store-prune-state-before store 2)))
    (is (chain-store-known-block store (block-hash finalized)))
    (is (chain-store-known-block store (block-hash safe)))
    (is (not (chain-store-state-available-p store (block-hash finalized))))
    (is (not (chain-store-state-available-p store (block-hash safe))))
    (is (not (chain-store-state-available-p store (block-hash side))))
    (is (chain-store-state-available-p store (block-hash head)))
    (is (bytes= (hash32-bytes (block-hash safe))
                (hash32-bytes
                 (chain-store-checkpoint-block-hash
                  (chain-store-safe-checkpoint store)))))
    (is (bytes= (hash32-bytes (block-hash finalized))
                (hash32-bytes
                 (chain-store-checkpoint-block-hash
                  (chain-store-finalized-checkpoint store)))))
    (is (= 0 (chain-store-account-balance
              store (block-hash finalized) address)))
    (is (= 0 (chain-store-account-balance store (block-hash safe) address)))
    (is (= 0 (chain-store-account-balance store (block-hash side) address)))
    (is (= 44 (chain-store-account-balance store (block-hash head) address)))))

(deftest chain-store-export-to-kv-syncs-readable-chain-records
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-export-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (transaction
           (make-legacy-transaction :nonce 1
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3
                                    :v 27
                                    :r 4
                                    :s 5))
         (receipt
           (make-receipt :status 1 :cumulative-gas-used 21000))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :timestamp 0
                               :gas-limit 30000000)))
         (branch-a-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 1
                               :gas-limit 30000000)))
         (branch-a-2
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash branch-a-1)
                               :timestamp 2
                               :gas-limit 30000000)
            :transactions (list transaction)
            :receipts (list receipt)))
         (branch-b-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 3
                               :extra-data #(1)
                               :gas-limit 30000000)))
         (branch-a-2-id (hash32-bytes (block-hash branch-a-2)))
         (branch-b-1-id (hash32-bytes (block-hash branch-b-1)))
         (transaction-id (hash32-bytes (transaction-hash transaction))))
    (unwind-protect
         (progn
           (dolist (block (list genesis branch-a-1 branch-a-2))
             (chain-store-put-block store block :state-available-p t))
           (chain-store-put-account-balance
            store (block-hash branch-a-2) recipient 11)
           (chain-store-put-account-storage
            store (block-hash branch-a-2) recipient slot 22)
           (let ((database (make-file-key-value-database path)))
             (is (eq database (chain-store-export-to-kv store database))))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database 2)
               (is present-p)
               (is (bytes= branch-a-2-id value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :block branch-a-2-id)
               (is present-p)
               (is (bytes= (block-rlp branch-a-2) value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :receipt branch-a-2-id)
               (is present-p)
               (is (bytes= (rlp-encode
                            (make-rlp-list
                             (transaction-receipt-encoding
                              transaction receipt)))
                           value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record
                  database :transaction-location transaction-id)
               (is present-p)
               (let ((items (rlp-list-items (rlp-decode-one value))))
                 (is (bytes= branch-a-2-id (first items)))
                 (is (= 0 (bytes-to-integer (second items))))
                 (is (= 0 (bytes-to-integer (third items))))))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state branch-a-2-id)
               (is present-p)
               (is (= 1 (length (rlp-list-items (rlp-decode-one value)))))))
           (chain-store-put-block store branch-b-1 :state-available-p t)
           (chain-store-set-canonical-head store (block-hash branch-b-1))
           (chain-store-put-block store branch-a-2)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv store database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database 1)
               (is present-p)
               (is (bytes= branch-b-1-id value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database 2 :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :block branch-a-2-id)
               (is present-p)
               (is (bytes= (block-rlp branch-a-2) value)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record
                  database :transaction-location transaction-id :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state branch-a-2-id :missing)
               (is (eq :missing value))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-export-to-kv-failure-does-not-partially-apply
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-export-failure-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction
           (make-legacy-transaction :nonce 1
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3
                                    :v 27
                                    :r 4
                                    :s 5))
         (block
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)
            :transactions (list transaction)))
         (block-id (hash32-bytes (block-hash block)))
         (transaction-id (hash32-bytes (transaction-hash transaction))))
    (unwind-protect
         (progn
           (chain-store-put-block store block :state-available-p t)
           (signals block-validation-error
             (chain-store-export-to-kv
              store
              (make-file-key-value-database path)))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-canonical-hash database 1 :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :block block-id :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record
                  database :transaction-location transaction-id :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state block-id :missing)
               (is (eq :missing value))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-restores-readable-chain-data
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (transaction
           (make-legacy-transaction :nonce 1
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3
                                    :v 27
                                    :r 4
                                    :s 5))
         (typed-transaction
           (make-dynamic-fee-transaction
            :chain-id 1
            :nonce 1
            :max-priority-fee-per-gas 0
            :max-fee-per-gas #x0fa0
            :gas-limit #x84d0
            :to recipient
            :value 0
            :data #()
            :y-parity 1
            :r #xb7dfab36232379bb3d1497a4f91c1966b1f932eae3ade107bf5d723b9cb474e0
            :s #x6261c359a10f2132f126d250485b90cf20f30340801244a08ef6142ab33d1904))
         (receipt
           (make-receipt :status 1 :cumulative-gas-used 21000))
         (typed-receipt
           (make-receipt
            :status 1
            :cumulative-gas-used 42000
            :logs (list (make-log-entry :address recipient
                                        :topics (list slot)
                                        :data #(4 5 6)))))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :timestamp 0
                               :gas-limit 30000000)))
         (branch-a-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 1
                               :gas-limit 30000000)))
         (branch-a-2
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash branch-a-1)
                               :timestamp 2
                               :gas-limit 30000000)
            :transactions (list transaction typed-transaction)
            :receipts (list receipt typed-receipt)))
         (branch-b-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 3
                               :extra-data #(1)
                               :gas-limit 30000000)))
         (transaction-hash (transaction-hash transaction))
         (typed-transaction-hash (transaction-hash typed-transaction)))
    (unwind-protect
         (progn
           (let ((state (make-state-db)))
             (state-db-set-account
              state recipient (make-state-account :nonce 7 :balance 11))
             (state-db-set-code state recipient #(1 2 3))
             (state-db-set-storage state recipient slot 22)
             (setf (block-header-state-root (block-header branch-a-2))
                   (state-db-root state)))
           (dolist (block (list genesis branch-a-1 branch-a-2 branch-b-1))
             (chain-store-put-block store block :state-available-p t))
           (chain-store-put-account-balance
            store (block-hash branch-a-2) recipient 11)
           (chain-store-put-account-nonce
            store (block-hash branch-a-2) recipient 7)
           (chain-store-put-account-code
            store (block-hash branch-a-2) recipient #(1 2 3))
           (chain-store-put-account-storage
            store (block-hash branch-a-2) recipient slot 22)
           (chain-store-update-forkchoice-checkpoints
            store
            (make-forkchoice-state
             :head-block-hash (block-hash branch-a-2)
             :safe-block-hash (block-hash branch-a-1)
             :finalized-block-hash (block-hash genesis)))
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv store database))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (is (= 2 (chain-store-head-number restored)))
           (is (bytes= (hash32-bytes (block-hash branch-a-2))
                       (hash32-bytes
                        (chain-store-canonical-hash restored 2))))
           (is (bytes= (block-rlp branch-a-2)
                       (block-rlp
                        (chain-store-block-by-number restored 2))))
           (is (bytes= (block-rlp branch-b-1)
                       (block-rlp
                        (chain-store-known-block
                         restored
                         (block-hash branch-b-1)))))
           (is (bytes= (hash32-bytes (block-hash branch-a-2))
                       (hash32-bytes
                        (chain-store-checkpoint-block-hash
                         (chain-store-head-checkpoint restored)))))
           (is (bytes= (hash32-bytes (block-hash branch-a-1))
                       (hash32-bytes
                        (chain-store-checkpoint-block-hash
                         (chain-store-safe-checkpoint restored)))))
           (is (bytes= (hash32-bytes (block-hash genesis))
                       (hash32-bytes
                        (chain-store-checkpoint-block-hash
                         (chain-store-finalized-checkpoint restored)))))
           (let ((location
                   (chain-store-transaction-location
                    restored transaction-hash)))
             (is (typep location 'engine-transaction-location))
             (is (= 0 (engine-transaction-location-index location)))
             (is (bytes= (transaction-receipt-encoding transaction receipt)
                         (transaction-receipt-encoding
                          transaction
                          (engine-transaction-location-receipt location))))
             (is (bytes= (transaction-encoding transaction)
                         (transaction-encoding
                          (engine-transaction-location-transaction
                           location)))))
           (let ((location
                   (chain-store-transaction-location
                    restored typed-transaction-hash)))
             (is (typep location 'engine-transaction-location))
             (is (= 1 (engine-transaction-location-index location)))
             (is (= 0 (engine-transaction-location-log-index-start location)))
             (is (bytes= (transaction-receipt-encoding
                          typed-transaction typed-receipt)
                         (transaction-receipt-encoding
                          typed-transaction
                          (engine-transaction-location-receipt location)))))
           (let ((receipts
                   (chain-store-block-receipts restored
                                               (block-hash branch-a-2))))
             (is (= 2 (length receipts)))
             (is (bytes= (transaction-receipt-encoding transaction receipt)
                         (transaction-receipt-encoding
                          transaction (first receipts))))
             (is (bytes= (transaction-receipt-encoding
                          typed-transaction typed-receipt)
                         (transaction-receipt-encoding
                          typed-transaction (second receipts)))))
           (is (chain-store-state-available-p
                restored
                (block-hash branch-a-2)))
           (is (= 11 (chain-store-account-balance
                      restored (block-hash branch-a-2) recipient)))
           (is (= 7 (chain-store-account-nonce
                     restored (block-hash branch-a-2) recipient)))
           (is (bytes= #(1 2 3)
                       (chain-store-account-code
                        restored (block-hash branch-a-2) recipient)))
           (is (= 22 (chain-store-account-storage
                      restored (block-hash branch-a-2) recipient slot))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-export-import-kv-restores-txpool-subpools
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (pending
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 110
             :gas-limit 21000
             :to recipient)
            1
            1))
         (basefee
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 120
             :gas-limit 21000
             :to recipient)
            2
            1))
         (blob
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
         (pending-hash (transaction-hash pending))
         (pending-id (hash32-bytes pending-hash))
         (pending-sender
           (transaction-sender pending :expected-chain-id 1)))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction
            source pending)
           (ethereum-lisp.core::engine-payload-store-put-queued-transaction
            source queued)
           (ethereum-lisp.core::engine-payload-store-put-basefee-transaction
            source basefee)
           (ethereum-lisp.core::engine-payload-store-put-blob-transaction
            source blob)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :txpool pending-id)
               (is present-p)
               (let ((fields (rlp-list-items (rlp-decode-one record))))
                 (is (string= "pending" (bytes-to-ascii (first fields))))
                 (is (bytes= (transaction-encoding pending)
                             (second fields))))))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (is (= 1
                  (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   restored)))
           (is (= 1
                  (ethereum-lisp.core::engine-payload-store-queued-transaction-count
                   restored)))
           (is (= 1
                  (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
                   restored)))
           (is (= 1
                  (ethereum-lisp.core::engine-payload-store-blob-transaction-count
                   restored)))
           (is (bytes= (transaction-encoding pending)
                       (transaction-encoding
                        (ethereum-lisp.core::engine-payload-store-pooled-transaction
                         restored
                         pending-hash))))
           (is (eq (ethereum-lisp.core::engine-payload-store-pooled-transaction
                    restored
                    (transaction-hash queued))
                   (ethereum-lisp.core::engine-payload-store-queued-transaction
                    restored
                    (transaction-hash queued))))
           (is (bytes= (transaction-encoding basefee)
                       (transaction-encoding
                        (ethereum-lisp.core::engine-payload-store-pooled-transaction
                         restored
                         (transaction-hash basefee)))))
           (is (typep blob 'blob-transaction))
           (is (bytes= (transaction-encoding blob)
                       (transaction-encoding
                        (ethereum-lisp.core::engine-payload-store-pooled-transaction
                         restored
                         (transaction-hash blob)))))
           (is (eq (ethereum-lisp.core::engine-payload-store-pending-transaction
                    restored
                    pending-hash)
                   (first
                    (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
                     restored
                     pending-sender))))
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv
              (make-engine-payload-memory-store)
              database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :txpool pending-id :missing)
               (is (eq :missing record))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-revalidates-restored-txpool
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-revalidate-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (head-block
           (make-block
            :header
            (make-block-header
             :number 1
             :timestamp 12
             :gas-limit 30000
             :base-fee-per-gas 5)))
         (stale-pending
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (basefee-ready
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-ready
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-over-gas
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 3
             :gas-price 6
             :gas-limit 40000
             :to recipient)
            1
            1))
         (sender (transaction-sender basefee-ready :expected-chain-id 1)))
    (unwind-protect
         (progn
           (let ((state (make-state-db)))
             (state-db-set-account
              state
              sender
              (make-state-account :balance 10000000 :nonce 1))
             (setf (block-header-state-root (block-header head-block))
                   (state-db-root state)))
           (chain-store-put-block source head-block :state-available-p t)
           (chain-store-put-account-nonce
            source (block-hash head-block) sender 1)
           (chain-store-put-account-balance
            source (block-hash head-block) sender 10000000)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash stale-pending))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :pending
               stale-pending))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash basefee-ready))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :basefee
               basefee-ready))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-ready))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :queued
               queued-ready))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-over-gas))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :queued
               queued-over-gas)))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (is (= 2
                  (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-queued-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
                   restored)))
           (is (eq nil
                   (ethereum-lisp.core::engine-payload-store-pooled-transaction
                    restored
                    (transaction-hash stale-pending))))
           (is (eq nil
                   (ethereum-lisp.core::engine-payload-store-pooled-transaction
                    restored
                    (transaction-hash queued-over-gas))))
           (is (bytes= (transaction-encoding basefee-ready)
                       (transaction-encoding
                        (ethereum-lisp.core::engine-payload-store-pending-transaction
                         restored
                         (transaction-hash basefee-ready)))))
           (is (bytes= (transaction-encoding queued-ready)
                       (transaction-encoding
                        (ethereum-lisp.core::engine-payload-store-pending-transaction
                         restored
                         (transaction-hash queued-ready)))))
           (let ((sender-transactions
                   (ethereum-lisp.core::engine-payload-store-pending-sender-transactions
                    restored
                    sender)))
             (is (= 2 (length sender-transactions)))
             (is (= 1 (transaction-nonce (first sender-transactions))))
             (is (= 2 (transaction-nonce (second sender-transactions))))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-prunes-overbudget-parked-txpool
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-budget-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (head-block
           (make-block
            :header
            (make-block-header
             :number 1
             :timestamp 12
             :gas-limit 30000
             :base-fee-per-gas 5)))
         (basefee-parked
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-overbudget
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 1
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender (transaction-sender basefee-parked :expected-chain-id 1)))
    (unwind-protect
         (progn
           (let ((state (make-state-db)))
             (state-db-set-account
              state
              sender
              (make-state-account :balance 100000 :nonce 0))
             (setf (block-header-state-root (block-header head-block))
                   (state-db-root state)))
           (chain-store-put-block source head-block :state-available-p t)
           (chain-store-put-account-nonce
            source (block-hash head-block) sender 0)
           (chain-store-put-account-balance
            source (block-hash head-block) sender 100000)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash basefee-parked))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :basefee
               basefee-parked))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-overbudget))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :queued
               queued-overbudget)))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-queued-transaction-count
                   restored)))
           (is (= 1
                  (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
                   restored)))
           (is (bytes= (transaction-encoding basefee-parked)
                       (transaction-encoding
                        (ethereum-lisp.core::engine-payload-store-basefee-transaction
                         restored
                         (transaction-hash basefee-parked)))))
           (is (null
                (ethereum-lisp.core::engine-payload-store-pooled-transaction
                 restored
                 (transaction-hash queued-overbudget)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-prunes-sender-code-invalid-txpool
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-code-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (sender-code #(1 2 3))
         (head-block
           (make-block
            :header
            (make-block-header
             :number 1
             :timestamp 12
             :gas-limit 30000
             :base-fee-per-gas 5)))
         (pending-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 0
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (queued-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 6
             :gas-limit 21000
             :to recipient)
            1
            1))
         (basefee-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 4
             :gas-limit 21000
             :to recipient)
            1
            1))
         (sender (transaction-sender pending-transaction
                                     :expected-chain-id 1)))
    (unwind-protect
         (progn
           (let ((state (make-state-db)))
             (state-db-set-account
              state
              sender
              (make-state-account :balance 10000000
                                  :nonce 0
                                  :code-hash
                                  (keccak-256-hash sender-code)))
             (setf (block-header-state-root (block-header head-block))
                   (state-db-root state)))
           (chain-store-put-block source head-block :state-available-p t)
           (chain-store-put-account-nonce
            source (block-hash head-block) sender 0)
           (chain-store-put-account-balance
            source (block-hash head-block) sender 10000000)
           (chain-store-put-account-code
            source (block-hash head-block) sender sender-code)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash pending-transaction))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :pending
               pending-transaction))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-transaction))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :queued
               queued-transaction))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash basefee-transaction))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :basefee
               basefee-transaction)))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-queued-transaction-count
                   restored)))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-basefee-transaction-count
                   restored)))
           (dolist (transaction (list pending-transaction
                                      queued-transaction
                                      basefee-transaction))
             (is (null
                  (ethereum-lisp.core::engine-payload-store-pooled-transaction
                   restored
                   (transaction-hash transaction))))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-wrong-chain-txpool-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-chain-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (target-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 9
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (wrong-chain-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            2
            2)))
    (unwind-protect
         (progn
           (is (transaction-sender wrong-chain-transaction
                                   :expected-chain-id nil))
           (is (null (transaction-sender wrong-chain-transaction
                                         :expected-chain-id 1)))
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction
            target target-transaction)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash wrong-chain-transaction))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :pending
               wrong-chain-transaction)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)
              :expected-chain-id 1))
           (is (= 1
                  (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   target)))
           (is (eq target-transaction
                   (ethereum-lisp.core::engine-payload-store-pending-transaction
                    target
                    (transaction-hash target-transaction)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-enforces-txpool-fork-rules
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-fork-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (pre-cancun-config
           (make-chain-config :chain-id 1337
                              :london-block 0
                              :cancun-time 100))
         (cancun-config
           (make-chain-config :chain-id 1337
                              :london-block 0
                              :cancun-time 0))
         (transaction
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675"))))
    (unwind-protect
         (progn
           (is (typep transaction 'blob-transaction))
           (is (transaction-sender transaction :expected-chain-id 1337))
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash transaction))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :blob
               transaction)))
           (signals block-validation-error
             (chain-store-import-from-kv
              (make-engine-payload-memory-store)
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config pre-cancun-config))
           (let ((restored (make-engine-payload-memory-store)))
             (chain-store-import-from-kv
              restored
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config cancun-config)
             (is (= 1
                    (ethereum-lisp.core::engine-payload-store-blob-transaction-count
                     restored)))
             (is (typep
                  (ethereum-lisp.core::engine-payload-store-blob-transaction
                   restored
                   (transaction-hash transaction))
                  'blob-transaction))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-enforces-txpool-blob-fee-cap
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-blob-fee-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (config (make-chain-config :chain-id 1337
                                    :london-block 0
                                    :cancun-time 0))
         (head-block
           (make-block
            :header
            (make-block-header
             :number 1
             :timestamp 12
             :gas-limit 30000000
             :blob-gas-used 0
             :excess-blob-gas (* 64 1024 1024))))
         (transaction
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675"))))
    (unwind-protect
         (progn
           (is (typep transaction 'blob-transaction))
           (is (> (block-header-blob-base-fee (block-header head-block))
                  (blob-transaction-max-fee-per-blob-gas transaction)))
           (is (transaction-sender transaction :expected-chain-id 1337))
           (chain-store-put-block source head-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash transaction))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :blob
               transaction)))
           (signals block-validation-error
             (chain-store-import-from-kv
              (make-engine-payload-memory-store)
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config config)))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-enforces-txpool-static-fields
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-static-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (config
           (make-chain-config :chain-id 1337
                              :london-block 0
                              :cancun-time 0))
         (transaction
           (transaction-from-encoding
            (hex-to-bytes
             "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
         (malformed (ethereum-lisp.core::copy-blob-transaction transaction)))
    (setf (blob-transaction-blob-versioned-hashes malformed) '())
    (unwind-protect
         (progn
           (is (transaction-sender malformed :expected-chain-id 1337))
           (signals block-validation-error
             (validate-blob-transaction-fields malformed))
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash malformed))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :blob
               malformed)))
           (signals block-validation-error
             (chain-store-import-from-kv
              (make-engine-payload-memory-store)
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config config)))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-enforces-set-code-authorization-signatures
  (labels ((first-authorization (transaction)
             (first (set-code-transaction-authorization-list transaction))))
    (let* ((path
             (merge-pathnames
              (make-pathname
               :name (format nil "ethereum-lisp-chain-txpool-auth-~A"
                             (gensym))
               :type "sexp")
              #P"/private/tmp/"))
           (config (make-chain-config :chain-id 1337))
           (transaction
             (transaction-from-encoding
              (hex-to-bytes
               "0x04f90126820539800285012a05f2008307a1209471562b71999873db5b286df957af199ec94617f78080c0f8baf85c82053994000000000000000000000000000000000000aaaa0101a07ed17af7d2d2b9ba7d797a202125bf505b9a0f962a67b3b61b56783d8faf7461a001b73b6e586edc706dce6c074eaec28692fa6359fb3446a2442f36777e1c0669f85a8094000000000000000000000000000000000000bbbb8001a05011890f198f0356a887b0779bde5afa1ed04e6acb1e3f37f8f18c7b6f521b98a056c3fa3456b103f3ef4a0acb4b647b9cab9ec4bc68fbcdf1e10b49fb2bcbcf6101a0167b0ecfc343a497095c22ee4270d3cc3b971cc3599fc73bbff727e0d2ed432da01c003c72306807492bf1150e39b2f79da23b49a4e83eb6e9209ae30d3572368f")))
           (malformed (ethereum-lisp.core::copy-set-code-transaction
                       transaction)))
      (setf (set-code-authorization-s (first-authorization malformed))
            #x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1)
      (unwind-protect
           (progn
             (is (transaction-sender malformed :expected-chain-id 1337))
             (signals block-validation-error
               (ethereum-lisp.core::validate-set-code-authorization-signatures
                malformed))
             (let ((database (make-file-key-value-database path)))
               (kv-put-chain-record
                database
                :txpool
                (hash32-bytes (transaction-hash malformed))
                (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
                 :pending
                 malformed)))
             (signals block-validation-error
               (chain-store-import-from-kv
                (make-engine-payload-memory-store)
                (make-file-key-value-database path)
                :expected-chain-id 1337
                :chain-config config)))
        (when (probe-file path)
          (delete-file path))))))

(deftest chain-store-import-from-kv-rejects-corrupt-txpool-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-corrupt-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (target-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 9
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            2
            1))
         (replacement
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 2
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            3
            1)))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction
            target target-transaction)
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction
            source transaction)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash transaction))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :pending
               replacement)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 1
                  (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   target)))
           (is (eq target-transaction
                   (ethereum-lisp.core::engine-payload-store-pending-transaction
                    target
                    (transaction-hash target-transaction)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-txpool-subpool-type-mismatch
  (labels ((with-database-record (subpool transaction thunk)
             (let ((path
                     (merge-pathnames
                      (make-pathname
                       :name
                       (format nil "ethereum-lisp-chain-txpool-subpool-~A"
                               (gensym))
                       :type "sexp")
                      #P"/private/tmp/")))
               (unwind-protect
                    (progn
                      (let ((database (make-file-key-value-database path)))
                        (kv-put-chain-record
                         database
                         :txpool
                         (hash32-bytes (transaction-hash transaction))
                         (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
                          subpool
                          transaction)))
                      (funcall thunk path))
                 (when (probe-file path)
                   (delete-file path))))))
    (let* ((recipient
             (address-from-hex "0x3535353535353535353535353535353535353535"))
           (legacy-transaction
             (fixture-sign-legacy-transaction
              (make-legacy-transaction
               :nonce 1
               :gas-price 100
               :gas-limit 21000
               :to recipient)
              1
              1))
           (blob-transaction
             (transaction-from-encoding
              (hex-to-bytes
               "0x03f8b1820539806485174876e800825208940c2c51a0990aee1d73c1228de1586883415575088080c083020000f842a00100c9fbdf97f747e85847b4f3fff408f89c26842f77c882858bf2c89923849aa00138e3896f3c27f2389147507f8bcec52028b0efca6ee842ed83c9158873943880a0dbac3f97a532c9b00e6239b29036245a5bfbb96940b9d848634661abee98b945a03eec8525f261c2e79798f7b45a5d6ccaefa24576d53ba5023e919b86841c0675")))
           (config (make-chain-config :chain-id 1337
                                      :london-block 0
                                      :cancun-time 0)))
      (with-database-record
       :blob
       legacy-transaction
       (lambda (path)
         (let ((target (make-engine-payload-memory-store)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-blob-transaction-count
                   target))))))
      (with-database-record
       :pending
       blob-transaction
       (lambda (path)
         (let ((target (make-engine-payload-memory-store)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)
              :expected-chain-id 1337
              :chain-config config))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   target)))))))))

(deftest chain-store-import-from-kv-rejects-conflicting-txpool-records
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-conflict-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (target-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 9
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (pending
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            2
            1))
         (queued-conflict
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 120
             :gas-limit 21000
             :to recipient)
            2
            1)))
    (unwind-protect
         (progn
           (is (not (bytes= (hash32-bytes (transaction-hash pending))
                            (hash32-bytes
                             (transaction-hash queued-conflict)))))
           (is (bytes= (address-bytes
                        (transaction-sender pending :expected-chain-id 1))
                       (address-bytes
                        (transaction-sender queued-conflict
                                            :expected-chain-id 1))))
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction
            target target-transaction)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash pending))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :pending
               pending))
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes (transaction-hash queued-conflict))
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :queued
               queued-conflict)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 1
                  (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   target)))
           (is (= 0
                  (ethereum-lisp.core::engine-payload-store-queued-transaction-count
                   target)))
           (is (eq target-transaction
                   (ethereum-lisp.core::engine-payload-store-pending-transaction
                    target
                    (transaction-hash target-transaction))))
           (is (null
                (ethereum-lisp.core::engine-payload-store-pooled-transaction
                 target
                 (transaction-hash pending))))
           (is (null
                (ethereum-lisp.core::engine-payload-store-pooled-transaction
                 target
                 (transaction-hash queued-conflict)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-export-import-kv-restores-invalid-tipsets
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-invalid-tipset-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (parent
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 1
             :gas-limit 50000
             :timestamp 10)))
         (invalid-child
           (make-block
            :header
            (make-block-header
             :parent-hash (block-hash parent)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 2
             :gas-limit 50000
             :timestamp 11)))
         (propagated-head
           (make-block
            :header
            (make-block-header
             :parent-hash (block-hash invalid-child)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 3
             :gas-limit 50000
             :timestamp 12)))
         (invalid-id (hash32-bytes (block-hash invalid-child)))
         (propagated-id (hash32-bytes (block-hash propagated-head))))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-mark-invalid
            source invalid-child)
           (ethereum-lisp.core::engine-payload-store-mark-invalid
            source invalid-child
            :head-hash (block-hash propagated-head))
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :invalid-tipset invalid-id)
               (is present-p)
               (is (bytes= (block-rlp invalid-child) record)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record
                  database :invalid-tipset propagated-id :missing)
               (is (eq :missing record))
               (is (not present-p))))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (let ((direct
                   (ethereum-lisp.core::engine-payload-store-invalid-block
                    restored
                    (block-hash invalid-child)))
                 (propagated
                   (ethereum-lisp.core::engine-payload-store-invalid-block
                    restored
                    (block-hash propagated-head))))
             (is direct)
             (is (not propagated))
             (is (bytes= (block-rlp invalid-child)
                         (block-rlp direct))))
           (let ((status
                   (ethereum-lisp.core::engine-payload-store-invalid-ancestor-status
                    restored
                    (block-hash invalid-child)
                    (block-hash propagated-head))))
             (is (string= +payload-status-invalid+
                          (payload-status-status status)))
             (is (string= "links to previously rejected block"
                          (payload-status-validation-error status)))
             (is (bytes= (hash32-bytes (block-hash parent))
                         (hash32-bytes
                          (payload-status-latest-valid-hash status))))
             (let ((propagated
                     (ethereum-lisp.core::engine-payload-store-invalid-block
                      restored
                      (block-hash propagated-head))))
               (is propagated)
               (is (bytes= (block-rlp invalid-child)
                           (block-rlp propagated)))))
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv
              (make-engine-payload-memory-store)
              database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record
                  database :invalid-tipset invalid-id :missing)
               (is (eq :missing record))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-export-to-kv-prunes-known-invalid-tipset-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-invalid-known-export-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 1
             :gas-limit 50000
             :timestamp 10)))
         (block-id (hash32-bytes (block-hash block))))
    (unwind-protect
         (progn
           (chain-store-put-block store block)
           (ethereum-lisp.core::engine-payload-store-mark-invalid store block)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :invalid-tipset
              block-id
              (block-rlp block))
             (chain-store-export-to-kv store database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record
                  database :invalid-tipset block-id :missing)
               (is (eq :missing record))
               (is (not present-p)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :block block-id)
               (is present-p)
               (is (bytes= (block-rlp block) record)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-known-invalid-tipset-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-invalid-known-import-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (known-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 1
             :gas-limit 50000
             :timestamp 10)))
         (target-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 2
             :gas-limit 50000
             :timestamp 11)))
         (known-id (hash32-bytes (block-hash known-block))))
    (unwind-protect
         (progn
           (chain-store-put-block source known-block)
           (chain-store-put-block target target-block)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :invalid-tipset
              known-id
              (block-rlp known-block)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (chain-store-known-block target (block-hash target-block)))
           (is (not (chain-store-known-block target (block-hash known-block))))
           (is (not
                (ethereum-lisp.core::engine-payload-store-invalid-block
                 target
                 (block-hash known-block)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-invalid-tipset-key-mismatch
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-invalid-tipset-mismatch-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (target-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 1
             :gas-limit 50000
             :timestamp 10)))
         (invalid-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 2
             :gas-limit 50000
             :timestamp 11)))
         (replacement
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 3
             :gas-limit 50000
             :timestamp 12))))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-mark-invalid
            target target-block)
           (ethereum-lisp.core::engine-payload-store-mark-invalid
            source invalid-block)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :invalid-tipset
              (hash32-bytes (block-hash invalid-block))
              (block-rlp replacement)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (ethereum-lisp.core::engine-payload-store-invalid-block
                target
                (block-hash target-block)))
           (is (not
                (ethereum-lisp.core::engine-payload-store-invalid-block
                 target
                 (block-hash invalid-block))))
           (is (not
                (ethereum-lisp.core::engine-payload-store-invalid-block
                 target
                 (block-hash replacement)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-corrupt-invalid-tipset-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-invalid-tipset-corrupt-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (target-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 1
             :gas-limit 50000
             :timestamp 10)))
         (invalid-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 2
             :gas-limit 50000
             :timestamp 11))))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-mark-invalid
            target target-block)
           (ethereum-lisp.core::engine-payload-store-mark-invalid
            source invalid-block)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :invalid-tipset
              (hash32-bytes (block-hash invalid-block))
              #(1 2 3)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (ethereum-lisp.core::engine-payload-store-invalid-block
                target
                (block-hash target-block)))
           (is (not
                (ethereum-lisp.core::engine-payload-store-invalid-block
                 target
                 (block-hash invalid-block)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-export-import-kv-restores-remote-blocks
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-remote-block-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (remote
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 7
             :gas-limit 50000
             :timestamp 70)))
         (remote-id (hash32-bytes (block-hash remote))))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-put-remote-block
            source remote)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :remote-block remote-id)
               (is present-p)
               (is (bytes= (block-rlp remote) record))))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (let ((restored-remote
                   (ethereum-lisp.core::engine-payload-store-remote-block
                    restored
                    (block-hash remote))))
             (is restored-remote)
             (is (bytes= (block-rlp remote)
                         (block-rlp restored-remote))))
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv
              (make-engine-payload-memory-store)
              database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :remote-block remote-id :missing)
               (is (eq :missing record))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest engine-payload-store-copies-sync-cache-blocks
  (let* ((store (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (remote
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 7
             :gas-limit 50000
             :gas-used 0
             :timestamp 70)))
         (invalid
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 8
             :gas-limit 50000
             :gas-used 0
             :timestamp 80)))
         (remote-hash (block-hash remote))
         (invalid-hash (block-hash invalid)))
    (is (eq remote
            (ethereum-lisp.core::engine-payload-store-put-remote-block
             store remote)))
    (is (eq invalid
            (ethereum-lisp.core::engine-payload-store-mark-invalid
             store invalid)))
    (setf (block-header-gas-used (block-header remote)) 77
          (block-header-gas-used (block-header invalid)) 88)
    (let ((cached-remote
            (ethereum-lisp.core::engine-payload-store-remote-block
             store remote-hash))
          (cached-invalid
            (ethereum-lisp.core::engine-payload-store-invalid-block
             store invalid-hash)))
      (is cached-remote)
      (is cached-invalid)
      (is (not (eq remote cached-remote)))
      (is (not (eq invalid cached-invalid)))
      (is (= 0 (block-header-gas-used (block-header cached-remote))))
      (is (= 0 (block-header-gas-used (block-header cached-invalid))))
      (setf (block-header-gas-used (block-header cached-remote)) 11
            (block-header-gas-used (block-header cached-invalid)) 22))
    (let ((cached-remote
            (ethereum-lisp.core::engine-payload-store-remote-block
             store remote-hash))
          (cached-invalid
            (ethereum-lisp.core::engine-payload-store-invalid-block
             store invalid-hash)))
      (is cached-remote)
      (is cached-invalid)
      (is (= 0 (block-header-gas-used (block-header cached-remote))))
      (is (= 0 (block-header-gas-used (block-header cached-invalid)))))))

(deftest chain-store-import-from-kv-rejects-corrupt-remote-block-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-remote-block-corrupt-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (target-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 7
             :gas-limit 50000
             :timestamp 70)))
         (remote
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 8
             :gas-limit 50000
             :timestamp 80)))
         (replacement
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 9
             :gas-limit 50000
             :timestamp 90))))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-put-remote-block
            target target-block)
           (ethereum-lisp.core::engine-payload-store-put-remote-block
            source remote)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :remote-block
              (hash32-bytes (block-hash remote))
              (block-rlp replacement)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (ethereum-lisp.core::engine-payload-store-remote-block
                target
                (block-hash target-block)))
           (is (not
                (ethereum-lisp.core::engine-payload-store-remote-block
                 target
                 (block-hash remote)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-drops-known-remote-block-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-remote-known-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (target-remote
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 6
             :gas-limit 50000
             :timestamp 60)))
         (known-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 7
             :gas-limit 50000
             :timestamp 70))))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-put-remote-block
            target target-remote)
           (chain-store-put-block source known-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
             database
             :remote-block
             (hash32-bytes (block-hash known-block))
             (block-rlp known-block)))
           (let ((database (make-file-key-value-database path)))
             (is (eq target
                     (chain-store-import-from-kv target database))))
           (is (not
                (ethereum-lisp.core::engine-payload-store-remote-block
                 target
                 (block-hash target-remote))))
           (is (chain-store-known-block target (block-hash known-block)))
           (is (not
                (ethereum-lisp.core::engine-payload-store-remote-block
                 target
                 (block-hash known-block)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-drops-invalid-remote-block-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-remote-invalid-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (target-remote
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 8
             :gas-limit 50000
             :timestamp 80)))
         (invalid-block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :beneficiary address
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :number 9
             :gas-limit 50000
             :timestamp 90))))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-put-remote-block
            target target-remote)
           (ethereum-lisp.core::engine-payload-store-mark-invalid
            source invalid-block)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
             database
             :remote-block
             (hash32-bytes (block-hash invalid-block))
             (block-rlp invalid-block)))
           (let ((database (make-file-key-value-database path)))
             (is (eq target
                     (chain-store-import-from-kv target database))))
           (is (not
                (ethereum-lisp.core::engine-payload-store-remote-block
                 target
                 (block-hash target-remote))))
           (is (ethereum-lisp.core::engine-payload-store-invalid-block
                target
                (block-hash invalid-block)))
           (is (not
                (ethereum-lisp.core::engine-payload-store-remote-block
                 target
                 (block-hash invalid-block)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-export-import-kv-restores-blob-sidecars
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-blob-sidecar-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (restored (make-engine-payload-memory-store))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proofs
           (loop for index below +cell-proofs-per-blob+
                 collect
                 (let ((proof (make-byte-vector +kzg-proof-size+)))
                   (setf (aref proof 0) index)
                   proof)))
         sidecar
         versioned-hash
         versioned-hash-id)
    (setf (aref blob 0) #xaa
          (aref commitment 0) #xbb
          sidecar (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs proofs)
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar))
          versioned-hash-id (hash32-bytes versioned-hash))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-put-blob-sidecar
            source sidecar)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record
                  database :blob-sidecar versioned-hash-id)
               (is present-p)
               (is (bytes= record
                           (ethereum-lisp.core::chain-store-blob-sidecar-record-rlp
                            (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
                             source versioned-hash))))))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (chain-store-import-from-kv restored database))))
           (let ((restored-blob
                   (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v2
                    restored
                    versioned-hash)))
             (is restored-blob)
             (is (bytes= blob
                         (ethereum-lisp.core::engine-blob-and-proofs-blob
                          restored-blob)))
             (is (bytes= commitment
                         (ethereum-lisp.core::engine-blob-and-proofs-commitment
                          restored-blob)))
             (is (bytes= (first proofs)
                         (ethereum-lisp.core::engine-blob-and-proofs-proof
                          restored-blob)))
             (is (= +cell-proofs-per-blob+
                    (length
                     (ethereum-lisp.core::engine-blob-and-proofs-cell-proofs
                      restored-blob))))
             (is (bytes= (car (last proofs))
                         (car
                          (last
                           (ethereum-lisp.core::engine-blob-and-proofs-cell-proofs
                            restored-blob))))))
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv
              (make-engine-payload-memory-store)
              database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record
                  database :blob-sidecar versioned-hash-id :missing)
               (is (eq :missing record))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest engine-payload-store-copies-blob-sidecar-lookups
  (let* ((store (make-engine-payload-memory-store))
         (blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proofs
           (loop for index below +cell-proofs-per-blob+
                 collect
                 (let ((proof (make-byte-vector +kzg-proof-size+)))
                   (setf (aref proof 0) index)
                   proof)))
         (sidecar nil)
         (versioned-hash nil))
    (setf (aref blob 0) #xaa
          (aref commitment 0) #xbb
          sidecar (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs proofs)
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
    (ethereum-lisp.core::engine-payload-store-put-blob-sidecar store sidecar)
    (let ((lookup
            (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v2
             store
             versioned-hash)))
      (setf (aref (ethereum-lisp.core::engine-blob-and-proofs-blob lookup) 0)
            #x11)
      (setf (aref (ethereum-lisp.core::engine-blob-and-proofs-commitment
                   lookup)
                  0)
            #x22)
      (setf (aref (ethereum-lisp.core::engine-blob-and-proofs-proof lookup)
                  0)
            #x33)
      (setf (aref
             (first
              (ethereum-lisp.core::engine-blob-and-proofs-cell-proofs lookup))
             0)
            #x44))
    (let ((lookup
            (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v2
             store
             versioned-hash)))
      (is (= #xaa
             (aref (ethereum-lisp.core::engine-blob-and-proofs-blob lookup)
                   0)))
      (is (= #xbb
             (aref (ethereum-lisp.core::engine-blob-and-proofs-commitment
                    lookup)
                   0)))
      (is (= 0
             (aref (ethereum-lisp.core::engine-blob-and-proofs-proof lookup)
                   0)))
      (is (= 0
             (aref
              (first
               (ethereum-lisp.core::engine-blob-and-proofs-cell-proofs lookup))
              0))))))

(deftest chain-store-import-from-kv-rejects-corrupt-blob-sidecar-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-blob-sidecar-corrupt-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (target-blob (make-byte-vector +blob-byte-size+))
         (target-commitment (make-byte-vector +kzg-commitment-size+))
         (target-proof (make-byte-vector +kzg-proof-size+))
         (source-blob (make-byte-vector +blob-byte-size+))
         (source-commitment (make-byte-vector +kzg-commitment-size+))
         (source-proof (make-byte-vector +kzg-proof-size+))
         target-sidecar
         target-versioned-hash
         source-sidecar
         source-versioned-hash)
    (setf (aref target-blob 0) #x11
          (aref target-commitment 0) #x22
          (aref target-proof 0) #x33
          (aref source-blob 0) #x44
          (aref source-commitment 0) #x55
          (aref source-proof 0) #x66
          target-sidecar (make-blob-sidecar
                          :blobs (list target-blob)
                          :commitments (list target-commitment)
                          :proofs (list target-proof))
          target-versioned-hash
          (first (blob-sidecar-versioned-hashes target-sidecar))
          source-sidecar (make-blob-sidecar
                          :blobs (list source-blob)
                          :commitments (list source-commitment)
                          :proofs (list source-proof))
          source-versioned-hash
          (first (blob-sidecar-versioned-hashes source-sidecar)))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-put-blob-sidecar
            target target-sidecar)
           (ethereum-lisp.core::engine-payload-store-put-blob-sidecar
            source source-sidecar)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :blob-sidecar
              (hash32-bytes source-versioned-hash)
              (rlp-encode
               (make-rlp-list
                (make-byte-vector 3 :initial-element 1)
                source-proof
                (make-rlp-list)))))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
                target
                target-versioned-hash))
           (is (not
                (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
                 target
                 source-versioned-hash))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-blob-sidecar-key-mismatch
  (let* ((database (make-memory-key-value-database))
         (target (make-engine-payload-memory-store))
         (target-blob (make-byte-vector +blob-byte-size+))
         (target-commitment (make-byte-vector +kzg-commitment-size+))
         (target-proof (make-byte-vector +kzg-proof-size+))
         (source-blob (make-byte-vector +blob-byte-size+))
         (source-commitment (make-byte-vector +kzg-commitment-size+))
         (source-proof (make-byte-vector +kzg-proof-size+))
         target-sidecar
         target-versioned-hash
         source-sidecar
         source-versioned-hash)
    (setf (aref target-blob 0) #x11
          (aref target-commitment 0) #x22
          (aref target-proof 0) #x33
          (aref source-blob 0) #x44
          (aref source-commitment 0) #x55
          (aref source-proof 0) #x66
          target-sidecar (make-blob-sidecar
                          :blobs (list target-blob)
                          :commitments (list target-commitment)
                          :proofs (list target-proof))
          target-versioned-hash
          (first (blob-sidecar-versioned-hashes target-sidecar))
          source-sidecar (make-blob-sidecar
                          :blobs (list source-blob)
                          :commitments (list source-commitment)
                          :proofs (list source-proof))
          source-versioned-hash
          (first (blob-sidecar-versioned-hashes source-sidecar)))
    (ethereum-lisp.core::engine-payload-store-put-blob-sidecar
     target target-sidecar)
    (let ((source-cache (make-engine-payload-memory-store)))
      (ethereum-lisp.core::engine-payload-store-put-blob-sidecar
       source-cache source-sidecar)
      (kv-put-chain-record
       database
       :blob-sidecar
       (hash32-bytes target-versioned-hash)
       (ethereum-lisp.core::chain-store-blob-sidecar-record-rlp
        (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
         source-cache source-versioned-hash))))
    (signals block-validation-error
      (chain-store-import-from-kv target database))
    (let ((target-cache
            (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
             target target-versioned-hash)))
      (is target-cache)
      (is (bytes= target-blob
                  (ethereum-lisp.core::engine-blob-and-proofs-blob
                   target-cache)))
      (is (bytes= target-commitment
                  (ethereum-lisp.core::engine-blob-and-proofs-commitment
                   target-cache))))
    (is (not
         (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
          target source-versioned-hash)))))

(deftest chain-store-export-import-kv-restores-prepared-payloads
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((path
             (merge-pathnames
              (make-pathname
               :name (format nil "ethereum-lisp-chain-prepared-payload-~A"
                             (gensym))
               :type "sexp")
              #P"/private/tmp/"))
           (source (make-engine-payload-memory-store))
           (restored (make-engine-payload-memory-store))
           (payload-id #(5 0 0 0 0 0 0 1))
           (block
             (make-block
              :header
              (make-block-header :number 9
                                 :timestamp 14
                                 :withdrawals-root
                                 (withdrawal-list-root '()))
              :withdrawals '()))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x03 #xdd))
              :commitments (list #(#x04 #xee))
              :proofs (list #(#x05 #xff) #(#x06 #x11))))
           (prepared-payload
             (make-engine-prepared-payload
              :payload-id payload-id
              :version 5
              :block block
              :blobs-bundle sidecar))
           (payload-id-bytes (ensure-byte-vector payload-id)))
      (unwind-protect
           (progn
             (chain-store-put-prepared-payload source prepared-payload)
             (let ((database (make-file-key-value-database path)))
               (chain-store-export-to-kv source database))
             (let ((database (make-file-key-value-database path)))
               (multiple-value-bind (record present-p)
                   (kv-get-chain-record
                    database :prepared-payload payload-id-bytes)
                 (is present-p)
                 (is (bytes= record
                             (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
                              prepared-payload)))))
             (let ((database (make-file-key-value-database path)))
               (is (eq restored
                       (chain-store-import-from-kv restored database))))
             (let ((restored-payload
                     (chain-store-prepared-payload restored payload-id)))
               (is restored-payload)
               (is (= 5
                      (ethereum-lisp.core::engine-prepared-payload-version
                       restored-payload)))
               (is (bytes= (block-rlp block)
                           (block-rlp
                            (ethereum-lisp.core::engine-prepared-payload-block
                             restored-payload)))))
             (let* ((response
                      (engine-rpc-handle-request
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 40)
                             (cons "method" "engine_getPayloadV5")
                             (cons "params" (list (bytes-to-hex payload-id))))
                       restored
                       (make-chain-config)))
                    (envelope (field response "result"))
                    (bundle (field envelope "blobsBundle")))
               (is (= 40 (field response "id")))
               (is (string= "0x04ee" (first (field bundle "commitments"))))
               (is (string= "0x05ff" (first (field bundle "proofs"))))
               (is (string= "0x0611" (second (field bundle "proofs"))))
               (is (string= "0x03dd" (first (field bundle "blobs")))))
             (let ((database (make-file-key-value-database path)))
               (chain-store-export-to-kv
                (make-engine-payload-memory-store)
                database))
             (let ((database (make-file-key-value-database path)))
               (multiple-value-bind (record present-p)
                   (kv-get-chain-record
                    database :prepared-payload payload-id-bytes :missing)
                 (is (eq :missing record))
                 (is (not present-p)))))
        (when (probe-file path)
          (delete-file path))))))

(deftest chain-store-put-block-prunes-prepared-payload-cache
  (let* ((store (make-engine-payload-memory-store))
         (payload-id #(2 0 0 0 0 0 0 1))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 2
            :block block)))
    (chain-store-put-prepared-payload store prepared-payload)
    (is (chain-store-prepared-payload store payload-id))
    (chain-store-put-block store block)
    (is (not (chain-store-prepared-payload store payload-id)))))

(deftest engine-payload-store-mark-invalid-prunes-prepared-payload-cache
  (let* ((store (make-engine-payload-memory-store))
         (invalid-payload-id #(2 0 0 0 0 0 0 1))
         (descendant-payload-id #(2 0 0 0 0 0 0 2))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (invalid-block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :beneficiary address
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (descendant-block
           (make-block
            :header
            (make-block-header :number 10
                               :parent-hash (block-hash invalid-block)
                               :timestamp 15
                               :beneficiary address
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (invalid-prepared-payload
           (make-engine-prepared-payload
            :payload-id invalid-payload-id
            :version 2
            :block invalid-block))
         (descendant-prepared-payload
           (make-engine-prepared-payload
            :payload-id descendant-payload-id
            :version 2
            :block descendant-block)))
    (chain-store-put-prepared-payload store invalid-prepared-payload)
    (chain-store-put-prepared-payload store descendant-prepared-payload)
    (is (chain-store-prepared-payload store invalid-payload-id))
    (is (chain-store-prepared-payload store descendant-payload-id))
    (ethereum-lisp.core::engine-payload-store-mark-invalid
     store invalid-block :head-hash (block-hash descendant-block))
    (is (not (chain-store-prepared-payload store invalid-payload-id)))
    (is (not (chain-store-prepared-payload store descendant-payload-id)))))

(deftest chain-store-export-to-kv-prunes-known-prepared-payload-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-known-prepared-export-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (store (make-engine-payload-memory-store))
         (payload-id #(2 0 0 0 0 0 0 1))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 2
            :block block))
         (payload-id-bytes (ensure-byte-vector payload-id))
         (block-id (hash32-bytes (block-hash block))))
    (unwind-protect
         (progn
           (chain-store-put-block store block)
           (chain-store-put-prepared-payload store prepared-payload)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :prepared-payload
              payload-id-bytes
              (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
               prepared-payload))
             (chain-store-export-to-kv store database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record
                  database :prepared-payload payload-id-bytes :missing)
               (is (eq :missing record))
               (is (not present-p)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :block block-id)
               (is present-p)
               (is (bytes= (block-rlp block) record)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-retains-matching-known-prepared-payload-record
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((path
             (merge-pathnames
              (make-pathname
               :name (format nil "ethereum-lisp-known-prepared-import-~A"
                             (gensym))
               :type "sexp")
              #P"/private/tmp/"))
           (target (make-engine-payload-memory-store))
           (payload-id #(6 0 0 0 0 0 0 1))
           (target-payload-id #(2 0 0 0 0 0 0 2))
           (account
             (make-block-access-account
              :address
              (address-from-hex
               "0x0000000000000000000000000000000000000001")))
           (known-block
             (make-block
              :header
              (make-block-header :parent-hash (zero-hash32)
                                 :beneficiary (zero-address)
                                 :state-root +empty-trie-hash+
                                 :mix-hash (zero-hash32)
                                 :number 10
                                 :gas-limit 50000
                                 :gas-used 21000
                                 :timestamp 15
                                 :base-fee-per-gas 100
                                 :blob-gas-used 0
                                 :excess-blob-gas 0
                                 :parent-beacon-root (zero-hash32)
                                 :slot-number 42
                                 :withdrawals-root
                                 (withdrawal-list-root '()))
              :withdrawals '()
              :requests (list #(#x82 #x06 #xaa))
              :block-access-list (list account)))
           (sidecar
             (make-blob-sidecar
              :blobs (list #(#x03 #xdd))
              :commitments (list #(#x04 #xee))
              :proofs (list #(#x05 #xff) #(#x06 #x11))))
           (prepared-payload
             (make-engine-prepared-payload
              :payload-id payload-id
              :version 6
              :block known-block
              :blobs-bundle sidecar))
           (target-block
             (make-block
              :header
              (make-block-header :number 11
                                 :timestamp 16
                                 :withdrawals-root
                                 (withdrawal-list-root '()))
              :withdrawals '()))
           (target-payload
             (make-engine-prepared-payload
              :payload-id target-payload-id
              :version 2
              :block target-block))
           (config (make-chain-config)))
      (unwind-protect
           (progn
             (chain-store-put-prepared-payload target target-payload)
             (let ((database (make-file-key-value-database path)))
               (kv-put-chain-record
                database
                :block
                (hash32-bytes (block-hash known-block))
                (block-rlp known-block))
               (kv-put-chain-record
                database
                :prepared-payload
                (ensure-byte-vector payload-id)
                (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
                 prepared-payload)))
             (let ((database (make-file-key-value-database path)))
               (is (eq target
                       (chain-store-import-from-kv target database))))
             (is (chain-store-known-block target (block-hash known-block)))
             (is (chain-store-prepared-payload target payload-id))
             (is (not
                  (chain-store-prepared-payload target target-payload-id)))
             (let* ((payload-response
                      (engine-rpc-handle-request
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 40)
                             (cons "method" "engine_getPayloadV6")
                             (cons "params" (list (bytes-to-hex payload-id))))
                       target
                       config))
                    (envelope (field payload-response "result"))
                    (payload (field envelope "executionPayload"))
                    (bundle (field envelope "blobsBundle"))
                    (body-response
                      (engine-rpc-handle-request
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 41)
                        (cons "method" "engine_getPayloadBodiesByHashV2")
                        (cons "params"
                              (list
                               (list
                                (hash32-to-hex
                                 (block-hash known-block))))))
                       target
                       config))
                    (body (first (field body-response "result"))))
               (is (= 40 (field payload-response "id")))
               (is (string= (bytes-to-hex
                             (block-encoded-block-access-list known-block))
                            (field payload "blockAccessList")))
               (is (string= "0x8206aa"
                            (first (field envelope "executionRequests"))))
               (is (string= "0x04ee"
                            (first (field bundle "commitments"))))
               (is (= 41 (field body-response "id")))
               (is body)
               (is (listp (field body "transactions")))
               (is (null (field body "transactions")))
               (is (listp (field body "withdrawals")))
               (is (null (field body "withdrawals")))
               (is (string= (bytes-to-hex
                             (block-encoded-block-access-list known-block))
                            (field body "blockAccessList")))))
        (when (probe-file path)
          (delete-file path))))))

(deftest chain-store-import-from-kv-drops-mismatched-known-prepared-payload-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-known-prepared-mismatch-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (target (make-engine-payload-memory-store))
         (payload-id #(2 0 0 0 0 0 0 1))
         (target-payload-id #(2 0 0 0 0 0 0 2))
         (header
           (make-block-header :number 9
                              :timestamp 14
                              :withdrawals-root
                              (withdrawal-list-root '())))
         (transaction
           (make-legacy-transaction :nonce 2
                                    :gas-price 3
                                    :gas-limit 21000
                                    :to (address-from-hex
                                         "0x0000000000000000000000000000000000000004")
                                    :value 5
                                    :v 27
                                    :r 8
                                    :s 9))
         (known-block (make-block :header header :withdrawals '()))
         (prepared-block
           (make-block
            :header header
            :transactions (list transaction)
            :withdrawals '()))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 2
            :block prepared-block))
         (target-block
           (make-block
            :header
            (make-block-header :number 10
                               :timestamp 15
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (target-payload
           (make-engine-prepared-payload
            :payload-id target-payload-id
            :version 2
            :block target-block)))
    (unwind-protect
         (progn
           (chain-store-put-prepared-payload target target-payload)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :block
              (hash32-bytes (block-hash known-block))
              (block-rlp known-block))
             (kv-put-chain-record
              database
              :prepared-payload
              (ensure-byte-vector payload-id)
              (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
               prepared-payload)))
           (let ((database (make-file-key-value-database path)))
             (is (eq target
                     (chain-store-import-from-kv target database))))
           (is (chain-store-known-block target (block-hash known-block)))
           (is (not (chain-store-prepared-payload target payload-id)))
           (is (not
                (chain-store-prepared-payload target target-payload-id))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-drops-invalid-prepared-payload-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-invalid-prepared-import-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (payload-id #(2 0 0 0 0 0 0 1))
         (invalid-block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 2
            :block invalid-block)))
    (unwind-protect
         (progn
           (ethereum-lisp.core::engine-payload-store-mark-invalid
            source invalid-block)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :prepared-payload
              (ensure-byte-vector payload-id)
              (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
               prepared-payload)))
           (let ((database (make-file-key-value-database path)))
             (is (eq target
                     (chain-store-import-from-kv target database))))
           (is (ethereum-lisp.core::engine-payload-store-invalid-block
                target
                (block-hash invalid-block)))
           (is (not (chain-store-prepared-payload target payload-id))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-put-prepared-payload-rejects-version-id-mismatch
  (let* ((store (make-engine-payload-memory-store))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (valid-payload
           (make-engine-prepared-payload
            :payload-id #(3 0 0 0 0 0 0 1)
            :version 3
            :block block))
         (mismatched-payload
           (make-engine-prepared-payload
            :payload-id #(5 0 0 0 0 0 0 2)
            :version 3
            :block block)))
    (is (eq valid-payload
            (chain-store-put-prepared-payload store valid-payload)))
    (signals block-validation-error
      (chain-store-put-prepared-payload store mismatched-payload))
    (is (chain-store-prepared-payload store #(3 0 0 0 0 0 0 1)))
    (is (not (chain-store-prepared-payload store #(5 0 0 0 0 0 0 2))))))

(deftest chain-store-put-prepared-payload-validates-blobs-bundle
  (let* ((store (make-engine-payload-memory-store))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (valid-payload-id #(5 0 0 0 0 0 0 1))
         (non-sidecar-payload-id #(5 0 0 0 0 0 0 2))
         (non-byte-payload-id #(5 0 0 0 0 0 0 3))
         (valid-payload
           (make-engine-prepared-payload
            :payload-id valid-payload-id
            :version 5
            :block block
            :blobs-bundle
            (make-blob-sidecar
             :blobs (list #(#x01 #x02))
             :commitments (list #(#x03))
             :proofs (list #(#x04)))))
         (non-sidecar-payload
           (make-engine-prepared-payload
            :payload-id non-sidecar-payload-id
            :version 5
            :block block
            :blobs-bundle "not-a-sidecar"))
         (non-byte-payload
           (make-engine-prepared-payload
            :payload-id non-byte-payload-id
            :version 5
            :block block
            :blobs-bundle
            (make-blob-sidecar
             :blobs (list (vector :not-a-byte))
             :commitments '()
             :proofs '()))))
    (is (eq valid-payload
            (chain-store-put-prepared-payload store valid-payload)))
    (signals block-validation-error
      (chain-store-put-prepared-payload store non-sidecar-payload))
    (signals block-validation-error
      (chain-store-put-prepared-payload store non-byte-payload))
    (is (chain-store-prepared-payload store valid-payload-id))
    (is (not (chain-store-prepared-payload store non-sidecar-payload-id)))
    (is (not (chain-store-prepared-payload store non-byte-payload-id)))))

(deftest chain-store-put-prepared-payload-copies-cache-entry
  (let* ((store (make-engine-payload-memory-store))
         (payload-id #(5 0 0 0 0 0 0 1))
         (original-extra-data #(#x01 #x02))
         (blob (ensure-byte-vector '(#x03 #x04)))
         (commitment (ensure-byte-vector '(#x05 #x06)))
         (proof (ensure-byte-vector '(#x07 #x08)))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :extra-data original-extra-data
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (sidecar
           (make-blob-sidecar
            :blobs (list blob)
            :commitments (list commitment)
            :proofs (list proof)))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 5
            :block block
            :blobs-bundle sidecar)))
    (chain-store-put-prepared-payload store prepared-payload)
    (setf (block-header-extra-data (block-header block)) #(#xff)
          (aref blob 0) #xaa
          (aref commitment 0) #xbb
          (aref proof 0) #xcc)
    (let* ((stored
             (chain-store-prepared-payload store payload-id))
           (stored-block
             (ethereum-lisp.core::engine-prepared-payload-block stored))
           (stored-bundle
             (ethereum-lisp.core::engine-prepared-payload-blobs-bundle stored)))
      (is stored)
      (is (not (eq prepared-payload stored)))
      (is (not (eq block stored-block)))
      (is (bytes= original-extra-data
                  (block-header-extra-data (block-header stored-block))))
      (is (bytes= #(#x03 #x04)
                  (first (blob-sidecar-blobs stored-bundle))))
      (is (bytes= #(#x05 #x06)
                  (first (blob-sidecar-commitments stored-bundle))))
      (is (bytes= #(#x07 #x08)
                  (first (blob-sidecar-proofs stored-bundle))))
      (setf (block-header-extra-data (block-header stored-block)) #(#xee)
            (aref (first (blob-sidecar-blobs stored-bundle)) 0) #xdd
            (aref (first (blob-sidecar-commitments stored-bundle)) 0) #xee
            (aref (first (blob-sidecar-proofs stored-bundle)) 0) #xff))
    (let* ((stored
             (chain-store-prepared-payload store payload-id))
           (stored-block
             (ethereum-lisp.core::engine-prepared-payload-block stored))
           (stored-bundle
             (ethereum-lisp.core::engine-prepared-payload-blobs-bundle stored)))
      (is stored)
      (is (bytes= original-extra-data
                  (block-header-extra-data (block-header stored-block))))
      (is (bytes= #(#x03 #x04)
                  (first (blob-sidecar-blobs stored-bundle))))
      (is (bytes= #(#x05 #x06)
                  (first (blob-sidecar-commitments stored-bundle))))
      (is (bytes= #(#x07 #x08)
                  (first (blob-sidecar-proofs stored-bundle)))))))

(deftest chain-store-import-from-kv-rejects-corrupt-prepared-payload-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-prepared-payload-corrupt-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (source-payload-id #(5 0 0 0 0 0 0 1))
         (replacement-payload-id #(5 0 0 0 0 0 0 2))
         (target-payload-id #(5 0 0 0 0 0 0 3))
         (source-block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (target-block
           (make-block
            :header
            (make-block-header :number 10
                               :timestamp 15
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (source-payload
           (make-engine-prepared-payload
            :payload-id source-payload-id
            :version 5
            :block source-block))
         (replacement-payload
           (make-engine-prepared-payload
            :payload-id replacement-payload-id
            :version 5
            :block source-block))
         (target-payload
           (make-engine-prepared-payload
            :payload-id target-payload-id
            :version 5
            :block target-block)))
    (unwind-protect
         (progn
           (chain-store-put-prepared-payload target target-payload)
           (chain-store-put-prepared-payload source source-payload)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :prepared-payload
              (ensure-byte-vector source-payload-id)
              (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
               replacement-payload)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (chain-store-prepared-payload target target-payload-id))
           (is (not
                (chain-store-prepared-payload target source-payload-id))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-prepared-payload-version-id-mismatch
  (let* ((database (make-memory-key-value-database))
         (target (make-engine-payload-memory-store))
         (target-payload-id #(5 0 0 0 0 0 0 3))
         (mismatched-payload-id #(5 0 0 0 0 0 0 4))
         (block
           (make-block
            :header
            (make-block-header :number 9
                               :timestamp 14
                               :withdrawals-root
                               (withdrawal-list-root '()))
            :withdrawals '()))
         (target-payload
           (make-engine-prepared-payload
            :payload-id target-payload-id
            :version 5
            :block block))
         (mismatched-payload
           (make-engine-prepared-payload
            :payload-id mismatched-payload-id
            :version 3
            :block block)))
    (chain-store-put-prepared-payload target target-payload)
    (kv-put-chain-record
     database
     :prepared-payload
     (ensure-byte-vector mismatched-payload-id)
     (ethereum-lisp.core::chain-store-prepared-payload-record-rlp
      mismatched-payload))
    (signals block-validation-error
      (chain-store-import-from-kv target database))
    (is (chain-store-prepared-payload target target-payload-id))
    (is (not
         (chain-store-prepared-payload target mismatched-payload-id)))))

(deftest chain-store-import-from-kv-rejects-state-root-mismatch
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-state-root-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (state (make-state-db))
         (target-block
           (make-block
            :header
            (make-block-header :number 9
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         source-block
         source-id)
    (state-db-set-account
     state recipient (make-state-account :nonce 7 :balance 11))
    (state-db-set-code state recipient #(1 2 3))
    (state-db-set-storage state recipient slot 22)
    (setf source-block
          (make-block
           :header
           (make-block-header :number 1
                              :state-root (state-db-root state)
                              :transactions-root +empty-trie-hash+
                              :receipts-root +empty-trie-hash+
                              :gas-limit 30000000))
          source-id (hash32-bytes (block-hash source-block)))
    (unwind-protect
         (progn
           (chain-store-put-block source source-block :state-available-p t)
           (commit-state-db-to-chain-store
            source (block-hash source-block) state)
           (chain-store-put-block target target-block :state-available-p t)
           (chain-store-put-account-balance
            target (block-hash target-block) recipient 55)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :state
              source-id
              (rlp-encode
               (make-rlp-list
                (make-rlp-list
                 (address-bytes recipient)
                 12
                 7
                 (hex-to-bytes "010203")
                 (make-rlp-list
                  (make-rlp-list (hash32-bytes slot) 22)))))))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 9 (chain-store-head-number target)))
           (is (not (chain-store-known-block
                     target
                     (block-hash source-block))))
           (is (chain-store-state-available-p
                target
                (block-hash target-block)))
           (is (= 55 (chain-store-account-balance
                      target (block-hash target-block) recipient))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-header-record-mismatch
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-header-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (source-block
           (make-block
            :header
            (make-block-header :number 1
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         (replacement-header
           (make-block-header :number 1
                              :state-root +empty-trie-hash+
                              :timestamp 99
                              :gas-limit 30000000))
         (target-block
           (make-block
            :header
            (make-block-header :number 9
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000))))
    (unwind-protect
         (progn
           (chain-store-put-block source source-block :state-available-p t)
           (chain-store-set-canonical-head source (block-hash source-block))
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash source-block)
             :safe-block-hash (zero-hash32)
             :finalized-block-hash (zero-hash32)))
           (chain-store-put-block target target-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :header
              (hash32-bytes (block-hash source-block))
              (block-header-rlp replacement-header)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 9 (chain-store-head-number target)))
           (is (not (chain-store-known-block
                     target
                     (block-hash source-block)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-orphan-header-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-orphan-header-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (source-block
           (make-block
            :header
            (make-block-header :number 1
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         (orphan-header
           (make-block-header :number 2
                              :state-root +empty-trie-hash+
                              :timestamp 99
                              :gas-limit 30000000))
         (target-block
           (make-block
            :header
            (make-block-header :number 9
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000))))
    (unwind-protect
         (progn
           (chain-store-put-block source source-block :state-available-p t)
           (chain-store-set-canonical-head source (block-hash source-block))
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash source-block)
             :safe-block-hash (zero-hash32)
             :finalized-block-hash (zero-hash32)))
           (chain-store-put-block target target-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :header
              (hash32-bytes (block-header-hash orphan-header))
              (block-header-rlp orphan-header)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 9 (chain-store-head-number target)))
           (is (not (chain-store-known-block
                     target
                     (block-hash source-block)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-invalid-checkpoints
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-checkpoints-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         (canonical-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 1
                               :gas-limit 30000000)))
         (head
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash canonical-1)
                               :state-root +empty-trie-hash+
                               :timestamp 2
                               :gas-limit 30000000)))
         (side
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 3
                               :extra-data (hex-to-bytes "01")
                               :gas-limit 30000000)))
         (target-block
           (make-block
            :header
            (make-block-header :number 9
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000))))
    (unwind-protect
         (progn
           (dolist (block (list genesis canonical-1 head side))
             (chain-store-put-block source block :state-available-p t))
           (chain-store-set-canonical-head source (block-hash head))
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash head)
             :safe-block-hash (block-hash canonical-1)
             :finalized-block-hash (block-hash genesis)))
           (chain-store-put-block target target-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-checkpoint
              database :safe (hash32-bytes (block-hash side))))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 9 (chain-store-head-number target)))
           (is (bytes= (block-rlp target-block)
                       (block-rlp
                        (chain-store-block-by-number target 9))))
           (is (not (chain-store-known-block target (block-hash head)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-disconnected-canonical-indexes
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-canonical-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         (canonical-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 1
                               :gas-limit 30000000)))
         (head
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash canonical-1)
                               :state-root +empty-trie-hash+
                               :timestamp 2
                               :gas-limit 30000000)))
         (side
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 3
                               :extra-data (hex-to-bytes "01")
                               :gas-limit 30000000)))
         (target-block
           (make-block
            :header
            (make-block-header :number 9
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000))))
    (unwind-protect
         (progn
           (dolist (block (list genesis canonical-1 head side))
             (chain-store-put-block source block :state-available-p t))
           (chain-store-set-canonical-head source (block-hash head))
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash head)
             :safe-block-hash (block-hash canonical-1)
             :finalized-block-hash (block-hash genesis)))
           (chain-store-put-block target target-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-canonical-hash
              database 1 (hash32-bytes (block-hash side))))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 9 (chain-store-head-number target)))
           (is (bytes= (block-rlp target-block)
                       (block-rlp
                        (chain-store-block-by-number target 9))))
           (is (not (chain-store-known-block target (block-hash head)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-head-checkpoint-canonical-mismatch
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-head-index-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         (canonical-1
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 1
                               :gas-limit 30000000)))
         (head
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash canonical-1)
                               :state-root +empty-trie-hash+
                               :timestamp 2
                               :gas-limit 30000000)))
         (side
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 3
                               :extra-data (hex-to-bytes "01")
                               :gas-limit 30000000)))
         (target-block
           (make-block
            :header
            (make-block-header :number 9
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000))))
    (unwind-protect
         (progn
           (dolist (block (list genesis canonical-1 head side))
             (chain-store-put-block source block :state-available-p t))
           (chain-store-set-canonical-head source (block-hash head))
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash head)
             :safe-block-hash (block-hash canonical-1)
             :finalized-block-hash (block-hash genesis)))
           (chain-store-put-block target target-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-checkpoint
              database :head (hash32-bytes (block-hash side)))
             (kv-delete-chain-checkpoint database :safe)
             (kv-delete-chain-checkpoint database :finalized))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 9 (chain-store-head-number target)))
           (is (bytes= (block-rlp target-block)
                       (block-rlp
                        (chain-store-block-by-number target 9))))
           (is (not (chain-store-known-block target (block-hash head)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-indexed-txpool-record
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-txpool-indexed-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x3535353535353535353535353535353535353535"))
         (target-transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 9
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            1
            1))
         (transaction
           (fixture-sign-legacy-transaction
            (make-legacy-transaction
             :nonce 1
             :gas-price 100
             :gas-limit 21000
             :to recipient)
            2
            1))
         (receipt
           (make-receipt :status 1 :cumulative-gas-used 21000))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         (head
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 1
                               :gas-limit 30000000)
            :transactions (list transaction)
            :receipts (list receipt)))
         (transaction-hash (transaction-hash transaction)))
    (unwind-protect
         (progn
           (chain-store-put-block source genesis :state-available-p t)
           (chain-store-put-block source head :state-available-p t)
           (chain-store-set-canonical-head source (block-hash head))
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash head)
             :safe-block-hash (block-hash genesis)
             :finalized-block-hash (block-hash genesis)))
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction
            target target-transaction)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :txpool
              (hash32-bytes transaction-hash)
              (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
               :pending
               transaction)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 1
                  (ethereum-lisp.core::engine-payload-store-pending-transaction-count
                   target)))
           (is (eq target-transaction
                   (ethereum-lisp.core::engine-payload-store-pending-transaction
                    target
                    (transaction-hash target-transaction))))
           (is (null
                (ethereum-lisp.core::engine-payload-store-pooled-transaction
                 target
                 transaction-hash)))
           (is (null (chain-store-transaction-location
                      target
                      transaction-hash))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-noncanonical-transaction-location
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-tx-location-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction
           (make-legacy-transaction :nonce 1
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3
                                    :v 27
                                    :r 4
                                    :s 5))
         (receipt
           (make-receipt :status 1 :cumulative-gas-used 21000))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         (canonical-head
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 1
                               :gas-limit 30000000)
            :transactions (list transaction)
            :receipts (list receipt)))
         (side-block
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 2
                               :extra-data (hex-to-bytes "01")
                               :gas-limit 30000000)
            :transactions (list transaction)
            :receipts (list receipt)))
         (target-block
           (make-block
            :header
            (make-block-header :number 9
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         (transaction-id (hash32-bytes (transaction-hash transaction))))
    (unwind-protect
         (progn
           (dolist (block (list genesis canonical-head side-block))
             (chain-store-put-block source block :state-available-p t))
           (chain-store-set-canonical-head source (block-hash canonical-head))
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash canonical-head)
             :safe-block-hash (block-hash genesis)
             :finalized-block-hash (block-hash genesis)))
           (chain-store-put-block target target-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :transaction-location
              transaction-id
              (rlp-encode
               (make-rlp-list
                (hash32-bytes (block-hash side-block))
                0
                0))))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 9 (chain-store-head-number target)))
           (is (not (chain-store-transaction-location
                     target
                     (transaction-hash transaction)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-rejects-location-without-receipt
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-tx-receipt-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (transaction
           (make-legacy-transaction :nonce 1
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3
                                    :v 27
                                    :r 4
                                    :s 5))
         (receipt
           (make-receipt :status 1 :cumulative-gas-used 21000))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000)))
         (head
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :state-root +empty-trie-hash+
                               :timestamp 1
                               :gas-limit 30000000)
            :transactions (list transaction)
            :receipts (list receipt)))
         (target-block
           (make-block
            :header
            (make-block-header :number 9
                               :state-root +empty-trie-hash+
                               :gas-limit 30000000))))
    (unwind-protect
         (progn
           (dolist (block (list genesis head))
             (chain-store-put-block source block :state-available-p t))
           (chain-store-set-canonical-head source (block-hash head))
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash head)
             :safe-block-hash (block-hash genesis)
             :finalized-block-hash (block-hash genesis)))
           (chain-store-put-block target target-block :state-available-p t)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-delete-chain-record
              database :receipt (hash32-bytes (block-hash head))))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 9 (chain-store-head-number target)))
           (is (not (chain-store-transaction-location
                     target
                     (transaction-hash transaction)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-import-from-kv-failure-keeps-existing-readable-data
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-chain-import-failure-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (target (make-engine-payload-memory-store))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (transaction
           (make-legacy-transaction :nonce 1
                                    :gas-price 2
                                    :gas-limit 21000
                                    :to recipient
                                    :value 3
                                    :v 27
                                    :r 4
                                    :s 5))
         (receipt
           (make-receipt :status 1 :cumulative-gas-used 21000))
         (source-block
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)
            :transactions (list transaction)
            :receipts (list receipt)))
         (target-block
           (make-block
            :header
            (make-block-header :number 9
                               :parent-hash (zero-hash32)
                               :timestamp 9
                               :gas-limit 30000000)))
         (target-hash (block-hash target-block))
         (source-id (hash32-bytes (block-hash source-block))))
    (unwind-protect
         (progn
           (chain-store-put-block source source-block :state-available-p t)
           (chain-store-put-block target target-block :state-available-p t)
           (chain-store-put-account-balance target target-hash recipient 55)
           (chain-store-put-account-storage target target-hash recipient slot 66)
           (let ((database (make-file-key-value-database path)))
             (chain-store-export-to-kv source database)
             (kv-put-chain-record database :receipt source-id #(1 2 3)))
           (signals block-validation-error
             (chain-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (= 9 (chain-store-head-number target)))
           (is (bytes= (block-rlp target-block)
                       (block-rlp
                        (chain-store-block-by-number target 9))))
           (is (not (chain-store-known-block
                     target
                     (block-hash source-block))))
           (is (chain-store-state-available-p target target-hash))
           (is (= 55 (chain-store-account-balance
                      target target-hash recipient)))
           (is (= 66 (chain-store-account-storage
                      target target-hash recipient slot))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-update-forkchoice-checkpoints-rejects-safe-before-finalized
  (let* ((store (make-engine-payload-memory-store))
         (genesis
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :timestamp 0
                               :gas-limit 30000000)))
         (safe
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (block-hash genesis)
                               :timestamp 1
                               :gas-limit 30000000)))
         (finalized
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash safe)
                               :timestamp 2
                               :gas-limit 30000000)))
         (head
           (make-block
            :header
            (make-block-header :number 3
                               :parent-hash (block-hash finalized)
                               :timestamp 3
                               :gas-limit 30000000))))
    (dolist (block (list genesis safe finalized head))
      (engine-payload-store-put-block store block :state-available-p t))
    (signals block-validation-error
      (chain-store-update-forkchoice-checkpoints
       store
       (make-forkchoice-state
        :head-block-hash (block-hash head)
        :safe-block-hash (block-hash safe)
        :finalized-block-hash (block-hash finalized))))
    (is (not (chain-store-head-block store)))
    (is (not (chain-store-safe-block store)))
    (is (not (chain-store-finalized-block store)))))

(deftest chain-store-update-forkchoice-checkpoints-requires-available-state
  (let* ((unknown-store (make-engine-payload-memory-store))
         (missing-state-store (make-engine-payload-memory-store))
         (missing-safe-state-store (make-engine-payload-memory-store))
         (unknown-hash
           (hash32-from-hex
            "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (head
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)))
         (safe
           (make-block
            :header
            (make-block-header :number 1
                               :parent-hash (zero-hash32)
                               :timestamp 1
                               :gas-limit 30000000)))
         (head-over-safe
           (make-block
            :header
            (make-block-header :number 2
                               :parent-hash (block-hash safe)
                               :timestamp 2
                               :gas-limit 30000000))))
    (signals block-validation-error
      (chain-store-update-forkchoice-checkpoints
       unknown-store
       (make-forkchoice-state
        :head-block-hash unknown-hash)))
    (is (not (chain-store-head-block unknown-store)))
    (engine-payload-store-put-block missing-state-store head)
    (signals block-validation-error
      (chain-store-update-forkchoice-checkpoints
       missing-state-store
       (make-forkchoice-state
        :head-block-hash (block-hash head))))
    (is (not (chain-store-head-block missing-state-store)))
    (engine-payload-store-put-block missing-safe-state-store safe)
    (engine-payload-store-put-block
     missing-safe-state-store head-over-safe :state-available-p t)
    (signals block-validation-error
      (chain-store-update-forkchoice-checkpoints
       missing-safe-state-store
       (make-forkchoice-state
        :head-block-hash (block-hash head-over-safe)
        :safe-block-hash (block-hash safe))))
    (is (not (chain-store-head-block missing-safe-state-store)))
    (is (not (chain-store-safe-block missing-safe-state-store)))))

(deftest chain-store-state-db-reconstructs-account-projection
  (let* ((store (make-engine-payload-memory-store))
         (missing-state-store (make-engine-payload-memory-store))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
         (storage-only
           (address-from-hex "0x0000000000000000000000000000000000000002"))
         (storage-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000003"))
         (storage-only-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000004"))
         (block
           (make-block
            :header
            (make-block-header :number 44
                               :state-root +empty-trie-hash+)))
         (block-hash (block-hash block)))
    (chain-store-put-block missing-state-store block)
    (chain-store-put-block store block :state-available-p t)
    (chain-store-put-account-balance store block-hash address 99)
    (chain-store-put-account-nonce store block-hash address 7)
    (chain-store-put-account-code store block-hash address #(96 42 0))
    (chain-store-put-account-storage store block-hash address storage-slot 5)
    (chain-store-put-account-storage
     store block-hash storage-only storage-only-slot 11)
    (is (not (chain-store-state-db missing-state-store block-hash)))
    (let* ((state (chain-store-state-db store block-hash))
           (account (state-db-get-account state address))
           (storage-only-account
             (state-db-get-account state storage-only)))
      (is (typep state 'state-db))
      (is (= 99 (state-account-balance account)))
      (is (= 7 (state-account-nonce account)))
      (is (bytes= #(96 42 0) (state-db-get-code state address)))
      (is (= 5 (state-db-get-storage state address storage-slot)))
      (is (= 0 (state-account-balance storage-only-account)))
      (is (= 0 (state-account-nonce storage-only-account)))
      (is (= 11
             (state-db-get-storage
              state storage-only storage-only-slot))))))

(deftest chain-store-for-each-account-iterates-deterministically
  (let* ((store (make-engine-payload-memory-store))
         (address-a
           (address-from-hex "0x0000000000000000000000000000000000000501"))
         (address-b
           (address-from-hex "0x0000000000000000000000000000000000000502"))
         (address-c
           (address-from-hex "0x0000000000000000000000000000000000000503"))
         (slot-a
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-b
           (hash32-from-hex
            "0x000000000000000000000000000000000000000000000000000000000000000b"))
         (block
           (make-block
            :header
            (make-block-header :number 46
                               :state-root +empty-trie-hash+)))
         (block-hash (block-hash block))
         (addresses '())
         (slots '()))
    (chain-store-put-block store block :state-available-p t)
    (chain-store-put-account-balance store block-hash address-c 3)
    (chain-store-put-account-balance store block-hash address-a 1)
    (chain-store-put-account-balance store block-hash address-b 2)
    (chain-store-put-account-storage store block-hash address-a slot-b 11)
    (chain-store-put-account-storage store block-hash address-a slot-a 1)
    (chain-store-for-each-account
     store
     block-hash
     (lambda (address balance nonce code storage-entries)
       (declare (ignore balance nonce code))
       (push (address-to-hex address) addresses)
       (when (bytes= (address-bytes address)
                     (address-bytes address-a))
         (setf slots (mapcar (lambda (entry)
                               (hash32-to-hex (car entry)))
                             storage-entries)))))
    (is (equal (list (address-to-hex address-a)
                     (address-to-hex address-b)
                     (address-to-hex address-c))
               (nreverse addresses)))
    (is (equal (list (hash32-to-hex slot-a)
                     (hash32-to-hex slot-b))
               slots))))

(deftest state-db-account-range-uses-secure-half-open-bounds
  (let* ((state (make-state-db))
         (addresses
           (list (address-from-hex "0x0000000000000000000000000000000000000601")
                 (address-from-hex "0x0000000000000000000000000000000000000602")
                 (address-from-hex "0x0000000000000000000000000000000000000603")
                 (address-from-hex "0x0000000000000000000000000000000000000604")))
         (slot
           (hash32-from-hex
            "0x000000000000000000000000000000000000000000000000000000000000000a")))
    (loop for address in addresses
          for balance from 10 by 10
          do (state-db-set-account
              state
              address
              (make-state-account :nonce balance :balance balance)))
    (state-db-set-code state (second addresses) #(96 42))
    (state-db-set-storage state (second addresses) slot 7)
    (let* ((all (state-db-account-range state))
           (proof-keys
             (mapcar (lambda (entry)
                       (bytes-to-hex
                        (state-account-range-entry-proof-key entry)))
                     all))
           (start (state-account-range-entry-proof-key (second all)))
           (end (state-account-range-entry-proof-key (fourth all)))
           (middle (state-db-account-range state :start start :end end))
           (prefix (state-db-account-range state :end start))
           (suffix (state-db-account-range state :start end)))
      (is (= 4 (length all)))
      (is (equal (sort (copy-list proof-keys) #'string<)
                 proof-keys))
      (is (equal (subseq proof-keys 1 3)
                 (mapcar (lambda (entry)
                           (bytes-to-hex
                            (state-account-range-entry-proof-key entry)))
                         middle)))
      (is (= 1 (length prefix)))
      (is (= 1 (length suffix)))
      (is (null (state-db-account-range state :start start :end start)))
      (let ((code-entry
              (find (address-to-hex (second addresses))
                    all
                    :key (lambda (entry)
                           (address-to-hex
                            (state-account-range-entry-address entry)))
                    :test #'string=)))
        (is (bytes= #(96 42)
                    (state-account-range-entry-code code-entry)))
        (is (= 1
               (length
                (state-account-range-entry-storage-entries code-entry))))))))

(deftest state-db-storage-range-uses-secure-half-open-bounds
  (let* ((state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000611"))
         (slots
           (list (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000001")
                 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000002")
                 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000003")
                 (hash32-from-hex
                  "0x0000000000000000000000000000000000000000000000000000000000000004"))))
    (loop for slot in slots
          for value from 100 by 100
          do (state-db-set-storage state address slot value))
    (let* ((all (state-db-storage-range state address))
           (proof-keys
             (mapcar (lambda (entry)
                       (bytes-to-hex
                        (state-storage-range-entry-proof-key entry)))
                     all))
           (start (state-storage-range-entry-proof-key (second all)))
           (end (state-storage-range-entry-proof-key (fourth all)))
           (middle (state-db-storage-range state address :start start :end end)))
      (is (= 4 (length all)))
      (is (equal (sort (copy-list proof-keys) #'string<)
                 proof-keys))
      (is (equal (subseq proof-keys 1 3)
                 (mapcar (lambda (entry)
                           (bytes-to-hex
                            (state-storage-range-entry-proof-key entry)))
                         middle)))
      (is (every #'plusp
                 (mapcar #'state-storage-range-entry-value middle)))
      (is (null (state-db-storage-range state address :start start :end start)))
      (is (null (state-db-storage-range
                 state
                 (address-from-hex
                  "0x0000000000000000000000000000000000000612")))))))

(deftest chain-store-state-db-round-trips-nontrivial-state-root
  (let* ((store (make-engine-payload-memory-store))
         (sender
           (address-from-hex "0x0000000000000000000000000000000000000411"))
         (recipient
           (address-from-hex "0x0000000000000000000000000000000000000412"))
         (sender-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000011"))
         (recipient-slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000012"))
         (state (make-state-db))
         (block
           (make-block
            :header
            (make-block-header :number 45
                               :timestamp 450
                               :gas-limit 30000000))))
    (state-db-set-account
     state sender (make-state-account :nonce 7 :balance 1000))
    (state-db-set-code state sender #(96 1 96 0 85))
    (state-db-set-storage state sender sender-slot 42)
    (state-db-set-account
     state recipient (make-state-account :nonce 3 :balance 5))
    (state-db-set-code state recipient #(96 2 96 0 85))
    (state-db-set-storage state recipient recipient-slot 99)
    (ethereum-lisp.state::state-db-transfer-value
     state sender recipient 37)
    (setf (block-header-state-root (block-header block))
          (state-db-root state))
    (chain-store-put-block store block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash block) state)
    (let* ((reconstructed (chain-store-state-db store (block-hash block)))
           (sender-account (state-db-get-account reconstructed sender))
           (recipient-account
             (state-db-get-account reconstructed recipient)))
      (is (typep reconstructed 'state-db))
      (is (string= (state-db-root-hex state)
                   (state-db-root-hex reconstructed)))
      (is (= 963 (state-account-balance sender-account)))
      (is (= 42 (state-db-get-storage reconstructed sender sender-slot)))
      (is (bytes= #(96 1 96 0 85)
                  (state-db-get-code reconstructed sender)))
      (is (bytes= (hash32-bytes (state-account-storage-root
                                  (state-db-get-account state sender)))
                  (hash32-bytes
                   (state-account-storage-root sender-account))))
      (is (= 42 (state-account-balance recipient-account)))
      (is (= 99
             (state-db-get-storage
              reconstructed recipient recipient-slot)))
      (is (bytes= #(96 2 96 0 85)
                  (state-db-get-code reconstructed recipient)))
      (is (bytes= (hash32-bytes (state-account-code-hash
                                  (state-db-get-account state recipient)))
                  (hash32-bytes
                   (state-account-code-hash recipient-account)))))))

(deftest execute-atomic-block-commit-commits-state-and-store-together
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
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
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+)
            :transactions (list transaction)
            :receipts (list receipt)))
         (block-hash (block-hash block))
         (transaction-hash (transaction-hash transaction)))
    (multiple-value-bind (result committed-block)
        (execute-atomic-block-commit
         store state
         (lambda ()
           (chain-store-put-block store block :state-available-p t)
           (chain-store-put-account-balance store block-hash address 99)
           (state-db-set-account state address
                                 (make-state-account :balance 99))
           (values :committed block)))
      (is (eq :committed result))
      (is (eq block committed-block)))
    (is (bytes= (block-rlp block)
                (block-rlp (chain-store-known-block store block-hash))))
    (is (chain-store-state-available-p store block-hash))
    (is (= 99 (chain-store-account-balance store block-hash address)))
    (is (typep (chain-store-transaction-location store transaction-hash)
               'engine-transaction-location))
    (is (= 99
           (state-account-balance
            (state-db-get-account state address))))))

(deftest execute-atomic-block-commit-rolls-back-state-and-store-on-error
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000001"))
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
         (block
           (make-block
            :header
            (make-block-header :number 0
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+)
            :transactions (list transaction)
            :receipts (list receipt)))
         (block-hash (block-hash block))
         (transaction-hash (transaction-hash transaction))
         (payload-id #(3 0 0 0 0 0 0 1))
         (blob #(#xaa #xbb))
         (commitment (make-byte-vector +kzg-commitment-size+
                                       :initial-element 0))
         (proof #(#xcc #xdd))
         (sidecar nil)
         (versioned-hash nil)
         (head-checkpoint
           (chain-store-head-checkpoint store))
         (prepared-payload
           (make-engine-prepared-payload
            :payload-id payload-id
            :version 3
            :block block))
         (invalid-block
           (make-block
            :header
            (make-block-header :number 7
                               :parent-hash (zero-hash32)
                               :state-root +empty-trie-hash+
                               :gas-used 0)))
         (invalid-block-hash (block-hash invalid-block))
         (new-invalid-block
           (make-block
            :header
            (make-block-header :number 8
                               :parent-hash invalid-block-hash
                               :state-root +empty-trie-hash+
                               :gas-used 0)))
         (new-invalid-block-hash (block-hash new-invalid-block))
         (pending-filter-id
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction-filter
            store)))
    (state-db-set-account state address (make-state-account :balance 10))
    (setf (aref commitment 0) #x11
          sidecar (make-blob-sidecar
                   :blobs (list blob)
                   :commitments (list commitment)
                   :proofs (list proof))
          versioned-hash (first (blob-sidecar-versioned-hashes sidecar)))
    (chain-store-put-prepared-payload store prepared-payload)
    (ethereum-lisp.core::engine-payload-store-put-blob-sidecar store sidecar)
    (ethereum-lisp.core::engine-payload-store-mark-invalid store invalid-block)
    (signals error
      (execute-atomic-block-commit
       store state
       (lambda ()
         (chain-store-put-block store block :state-available-p t)
         (chain-store-put-account-balance store block-hash address 99)
         (ethereum-lisp.core::engine-payload-store-put-pending-transaction
          store transaction)
         (setf (ethereum-lisp.core::engine-prepared-payload-version
                (chain-store-prepared-payload store payload-id))
               6)
         (setf (aref
                (ethereum-lisp.core::engine-blob-and-proofs-blob
                 (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
                  store versioned-hash))
                0)
               #xff)
         (setf (ethereum-lisp.core::chain-store-checkpoint-label
                (chain-store-head-checkpoint store))
               :mutated-head)
         (setf (block-header-gas-used
                (block-header
                 (ethereum-lisp.core::engine-payload-store-invalid-block
                  store invalid-block-hash)))
               77)
         (ethereum-lisp.core::engine-payload-store-mark-invalid
          store new-invalid-block)
         (state-db-set-account state address
                               (make-state-account :balance 99))
         (error "Injected atomic commit failure"))))
    (is (null (chain-store-known-block store block-hash)))
    (is (null (chain-store-canonical-hash store 0)))
    (is (null (chain-store-transaction-location store transaction-hash)))
    (is (not (chain-store-state-available-p store block-hash)))
    (is (= 0 (chain-store-account-balance store block-hash address)))
    (is (= 0
           (ethereum-lisp.core::engine-payload-store-pending-transaction-count
            store)))
    (is (null (ethereum-lisp.core::engine-payload-store-pending-transaction
               store transaction-hash)))
    (is (null
         (ethereum-lisp.core::engine-pending-transaction-filter-hashes
          (ethereum-lisp.core::engine-payload-store-log-filter
           store pending-filter-id))))
    (is (= 3
           (ethereum-lisp.core::engine-prepared-payload-version
            (chain-store-prepared-payload store payload-id))))
    (is (= #xaa
           (aref
            (ethereum-lisp.core::engine-blob-and-proofs-blob
             (ethereum-lisp.core::engine-payload-store-blob-and-proofs-v1
              store versioned-hash))
            0)))
    (is (eq :head
            (ethereum-lisp.core::chain-store-checkpoint-label
             (chain-store-head-checkpoint store))))
    (is (not (eq head-checkpoint
                 (chain-store-head-checkpoint store))))
    (let ((cached-invalid
            (ethereum-lisp.core::engine-payload-store-invalid-block
             store invalid-block-hash)))
      (is cached-invalid)
      (is (not (eq invalid-block cached-invalid)))
      (is (= 0
             (block-header-gas-used
              (block-header cached-invalid)))))
    (is (null
         (ethereum-lisp.core::engine-payload-store-invalid-block
          store new-invalid-block-hash)))
    (is (= 10
           (state-account-balance
            (state-db-get-account state address))))))

