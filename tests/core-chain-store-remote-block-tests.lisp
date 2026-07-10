(in-package #:ethereum-lisp.test)

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
           (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
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
                   (ethereum-lisp.chain-store:engine-payload-store-remote-block
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
            (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
             store remote)))
    (is (eq invalid
            (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
             store invalid)))
    (setf (block-header-gas-used (block-header remote)) 77
          (block-header-gas-used (block-header invalid)) 88)
    (let ((cached-remote
            (ethereum-lisp.chain-store:engine-payload-store-remote-block
             store remote-hash))
          (cached-invalid
            (ethereum-lisp.chain-store:engine-payload-store-invalid-block
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
            (ethereum-lisp.chain-store:engine-payload-store-remote-block
             store remote-hash))
          (cached-invalid
            (ethereum-lisp.chain-store:engine-payload-store-invalid-block
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
           (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
            target target-block)
           (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
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
           (is (ethereum-lisp.chain-store:engine-payload-store-remote-block
                target
                (block-hash target-block)))
           (is (not
                (ethereum-lisp.chain-store:engine-payload-store-remote-block
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
           (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
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
                (ethereum-lisp.chain-store:engine-payload-store-remote-block
                 target
                 (block-hash target-remote))))
           (is (chain-store-known-block target (block-hash known-block)))
           (is (not
                (ethereum-lisp.chain-store:engine-payload-store-remote-block
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
           (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
            target target-remote)
           (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
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
                (ethereum-lisp.chain-store:engine-payload-store-remote-block
                 target
                 (block-hash target-remote))))
           (is (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                target
                (block-hash invalid-block)))
           (is (not
                (ethereum-lisp.chain-store:engine-payload-store-remote-block
                 target
                 (block-hash invalid-block)))))
      (when (probe-file path)
        (delete-file path)))))

