(in-package #:ethereum-lisp.test)

(deftest node-store-persistence-package-boundary
  (let ((persistence
          (find-package '#:ethereum-lisp.node-store.persistence))
        (database (find-package '#:ethereum-lisp.database))
        (chain-store (find-package '#:ethereum-lisp.chain-store))
        (canonical-chain (find-package '#:ethereum-lisp.canonical-chain))
        (txpool (find-package '#:ethereum-lisp.txpool))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list persistence))))
    (is (member database (package-use-list persistence)))
    (is (member chain-store (package-use-list persistence)))
    (is (not (member canonical-chain (package-use-list persistence))))
    (is (member txpool (package-use-list persistence)))
    (dolist (name '("CANONICAL-CHAIN-TRANSITION-P"
                    "CANONICAL-CHAIN-TRANSITION-INSTALLED-BLOCKS"
                    "CANONICAL-CHAIN-TRANSITION-DISPLACED-BLOCKS"
                    "CANONICAL-CHAIN-TRANSITION-CHANGED-TXPOOL-HASHES"))
      (multiple-value-bind (persistence-symbol persistence-status)
          (find-symbol name persistence)
        (multiple-value-bind (canonical-symbol canonical-status)
            (find-symbol name canonical-chain)
          (is (eq :internal persistence-status))
          (is (eq :external canonical-status))
          (is (eq persistence-symbol canonical-symbol)))))
    (dolist (name '("NODE-STORE-EXPORT-TO-KV"
                    "NODE-STORE-IMPORT-FROM-KV"))
      (multiple-value-bind (persistence-symbol persistence-status)
          (find-symbol name persistence)
        (multiple-value-bind (core-symbol core-status)
            (find-symbol name core)
          (is (eq :external persistence-status))
          (is (eq :external core-status))
          (is (eq persistence-symbol core-symbol)))))
    (multiple-value-bind (persistence-symbol persistence-status)
        (find-symbol "NODE-STORE-EXPORT-TXPOOL-RECORDS-TO-KV" persistence)
      (multiple-value-bind (core-symbol core-status)
          (find-symbol "NODE-STORE-EXPORT-TXPOOL-RECORDS-TO-KV" core)
        (is persistence-symbol)
        (is (eq :external persistence-status))
        (is (null core-symbol))
        (is (null core-status))))
    (dolist (name '("CHAIN-STORE-EXPORT-TO-KV"
                    "CHAIN-STORE-IMPORT-FROM-KV"))
      (multiple-value-bind (symbol status) (find-symbol name persistence)
        (is (null symbol))
        (is (null status))))
    (multiple-value-bind (symbol status)
        (find-symbol "CHAIN-STORE-SET-CANONICAL-HEAD" persistence)
      (is (null symbol))
      (is (null status)))))

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

(deftest node-store-export-to-kv-syncs-readable-chain-records
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
             (is (eq database (node-store-export-to-kv store database))))
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
             (node-store-export-to-kv store database))
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

(deftest node-store-export-to-kv-failure-does-not-partially-apply
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
             (node-store-export-to-kv
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

(deftest node-store-import-from-kv-restores-readable-chain-data
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
             (node-store-export-to-kv store database))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (node-store-import-from-kv restored database))))
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
