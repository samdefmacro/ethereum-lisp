(in-package #:ethereum-lisp.test)

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

