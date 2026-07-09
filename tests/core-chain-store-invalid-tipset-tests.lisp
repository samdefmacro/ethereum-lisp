(in-package #:ethereum-lisp.test)

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

