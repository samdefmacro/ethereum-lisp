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
             (node-store-export-to-kv source database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :remote-block remote-id)
               (is present-p)
               (is (bytes= (block-rlp remote) record))))
           (let ((database (make-file-key-value-database path)))
             (is (eq restored
                     (node-store-import-from-kv restored database))))
           (let ((restored-remote
                   (ethereum-lisp.chain-store:engine-payload-store-remote-block
                    restored
                    (block-hash remote))))
             (is restored-remote)
             (is (bytes= (block-rlp remote)
                         (block-rlp restored-remote))))
           (let ((database (make-file-key-value-database path)))
             (node-store-export-to-kv
              (make-engine-payload-memory-store)
              database))
           (let ((database (make-file-key-value-database path)))
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database :remote-block remote-id :missing)
               (is (eq :missing record))
               (is (not present-p)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest direct-restart-restores-amsterdam-remote-with-derived-bal-absent
  (:layer :integration :module :persistence)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-amsterdam-remote-~A" (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (state (make-state-db))
         (genesis
           (make-block
            :header
            (make-block-header
             :number 0 :parent-hash (zero-hash32)
             :state-root (state-db-root state) :mix-hash (zero-hash32)
             :timestamp 1 :gas-limit 30000000)))
         (remote
           (ethereum-lisp.blocks:make-block-from-parts
            :header
            (make-block-header
             :number 1 :parent-hash (block-hash genesis)
             :state-root +empty-trie-hash+ :mix-hash (zero-hash32)
             :timestamp 2 :gas-limit 30000000
             :block-access-list-hash (block-access-list-hash '()))
            :transactions '() :ommers '()))
         (identifier (hash32-bytes (block-hash remote)))
         (config (make-chain-config :chain-id 1 :amsterdam-time 0)))
    (unwind-protect
         (let ((database (make-file-key-value-database path)))
           (chain-store-put-block source genesis :state-available-p t)
           (commit-state-db-to-chain-store source (block-hash genesis) state)
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash genesis)
             :safe-block-hash (block-hash genesis)
             :finalized-block-hash (block-hash genesis)))
           (node-store-export-to-kv source database)
           (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
            source remote)
           (ethereum-lisp.node-store.persistence:node-store-export-buffered-candidate-to-kv
            source remote database)
           ;; eth BlockBodies does not carry the execution-derived Amsterdam
           ;; BAL. The committed header/body remains a durable sync target; no
           ;; fabricated empty side record is written.
           (is (not (nth-value
                     1
                     (kv-get-chain-record
                      database :block-access-list identifier))))
           (let ((restored
                   (ethereum-lisp.cli::devnet-cli-import-direct-chain-database
                    (make-file-key-value-database path)
                    "amsterdam-remote-file-test" config genesis
                    :import-txpool-p nil)))
             (let ((candidate
                     (engine-payload-store-remote-block
                      restored (block-hash remote))))
               (is candidate)
               (is (hash32= (block-hash remote) (block-hash candidate)))
               (is (not (block-block-access-list-present-p candidate))))))
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

(deftest node-store-import-from-kv-rejects-corrupt-remote-block-record
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
             (node-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :remote-block
              (hash32-bytes (block-hash remote))
              (block-rlp replacement)))
           (signals block-validation-error
             (node-store-import-from-kv
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

(deftest node-store-import-from-kv-drops-known-remote-block-record
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
             (node-store-export-to-kv source database)
             (kv-put-chain-record
             database
             :remote-block
             (hash32-bytes (block-hash known-block))
             (block-rlp known-block)))
           (let ((database (make-file-key-value-database path)))
             (is (eq target
                     (node-store-import-from-kv target database))))
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

(deftest node-store-import-from-kv-drops-invalid-remote-block-record
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
             (node-store-export-to-kv source database)
             (kv-put-chain-record
             database
             :remote-block
             (hash32-bytes (block-hash invalid-block))
             (block-rlp invalid-block)))
           (let ((database (make-file-key-value-database path)))
             (is (eq target
                     (node-store-import-from-kv target database))))
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

(deftest direct-startup-streams-and-durably-bounds-legacy-remote-targets
  (:layer :integration :module :persistence :estimated-seconds 15)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-bounded-remote-direct-~A"
                           (gensym))
             :type "sexp")
            #P"/private/tmp/"))
         (source (make-engine-payload-memory-store))
         (state (make-state-db))
         (genesis
           (make-block
            :header
            (make-block-header
             :number 0
             :parent-hash (zero-hash32)
             :state-root (state-db-root state)
             :mix-hash (zero-hash32)
             :timestamp 1
             :gas-limit 30000000)))
         (config (make-chain-config :chain-id 1))
         (remote-count
           (1+
            (* 2
               ethereum-lisp.node-store.persistence::+node-store-remote-recovery-cleanup-batch-size+)))
         (finalized-stale
           (chain-store-bal-persistence-test-block 0 0 :bal-p t))
         (remotes
           (loop for marker from 1 to remote-count
                 collect
                 (chain-store-bal-persistence-test-block
                  marker (mod marker 256) :bal-p t))))
    (unwind-protect
         (let ((database (make-file-key-value-database path)))
           (chain-store-put-block source genesis :state-available-p t)
           (commit-state-db-to-chain-store source (block-hash genesis) state)
           (chain-store-update-forkchoice-checkpoints
            source
            (make-forkchoice-state
             :head-block-hash (block-hash genesis)
             :safe-block-hash (block-hash genesis)
             :finalized-block-hash (block-hash genesis)))
           (node-store-export-to-kv source database)
           ;; Simulate a pre-bound legacy database. Seed more than two cleanup
           ;; pages in one batch so every record exists before restart instead
           ;; of being pruned by the live cache.
           (let ((batch (make-kv-write-batch)))
             (dolist (remote (cons finalized-stale remotes))
               (let ((identifier (hash32-bytes (block-hash remote))))
                 (kv-batch-put-chain-record
                  batch
                  :remote-block
                  identifier
                  (ethereum-lisp.node-store.persistence::chain-store-block-record-rlp
                   remote))
                 (kv-batch-put-chain-record
                  batch
                  :block-access-list
                  identifier
                  (block-encoded-block-access-list remote))))
             (kv-apply-batch database batch))
           ;; Reopen the durable file before constructing the direct provider.
           (let* ((database (make-file-key-value-database path))
                  (ordered
                    (sort
                     (copy-list remotes)
                     #'string<
                     :key (lambda (block)
                            (hash32-to-hex (block-hash block)))))
                  (evicted (first ordered))
                  (target (car (last ordered)))
                  ;; Exercise the actual direct CLI startup boundary, not
                  ;; merely the lower-level importer. No txpool is needed.
                  (restored
                    (ethereum-lisp.cli::devnet-cli-import-direct-chain-database
                     database "bounded-remote-file-test" config genesis
                     :import-txpool-p nil))
                  (chain
                    (ethereum-lisp.chain-store.state:chain-store-require-memory-store
                     restored))
                  (node
                    (ethereum-lisp.cli::%make-devnet-node
                     :store restored
                     :store-guard-function (lambda (thunk) (funcall thunk))))
                  (targets (ethereum-lisp.cli::devnet-node-sync-targets node))
                  (durable-remotes
                    (kv-chain-record-entries database :remote-block))
                  (durable-side-data
                    (kv-chain-record-entries database :block-access-list)))
             (is (> remote-count
                    (* 2
                       ethereum-lisp.node-store.persistence::+node-store-remote-recovery-cleanup-batch-size+)))
             (is (database-engine-payload-store-p restored))
             (is (= ethereum-lisp.chain-store:+engine-remote-block-cache-count-limit+
                    (hash-table-count
                     (ethereum-lisp.chain-store.state:memory-chain-store-remote-blocks
                      chain))))
             (is (= ethereum-lisp.chain-store:+engine-remote-block-cache-count-limit+
                    (length durable-remotes)))
             (is (= (length durable-remotes) (length durable-side-data)))
             (dolist (entry durable-remotes)
               (is (nth-value
                    1
                    (gethash
                     (bytes-to-hex (car entry))
                     (ethereum-lisp.chain-store.state:memory-chain-store-remote-blocks
                      chain)))))
             ;; The stable same-time tie break retains the lexicographically
             ;; greatest hashes. Every eviction across all cleanup pages loses
             ;; both its remote body and BAL, while every retained pair remains.
             (let ((retained-identifiers (make-hash-table :test 'equalp)))
               (dolist (entry durable-remotes)
                 (setf (gethash (bytes-to-hex (car entry))
                                retained-identifiers)
                       t))
               (dolist (remote remotes)
                 (let* ((identifier (hash32-bytes (block-hash remote)))
                        (retained-p
                          (gethash (bytes-to-hex identifier)
                                   retained-identifiers)))
                   (dolist (kind '(:remote-block :block-access-list))
                     (is (eq (not (null retained-p))
                             (nth-value
                              1
                              (kv-get-chain-record
                               database kind identifier))))))))
             (dolist (kind '(:remote-block :block-access-list))
               (is (not
                    (nth-value
                     1
                     (kv-get-chain-record
                      database kind (hash32-bytes (block-hash evicted)))))))
             ;; Startup finality is authoritative even for legacy records that
             ;; carry no persisted admission metadata.
             (dolist (kind '(:remote-block :block-access-list))
               (is (not
                    (nth-value
                     1
                     (kv-get-chain-record
                      database kind
                      (hash32-bytes (block-hash finalized-stale)))))))
             ;; A missing-parent target survives direct restart and is
             ;; immediately visible to the ordinary gap-fill enumerator.
             (is (ethereum-lisp.chain-store:engine-payload-store-remote-block
                  restored (block-hash target)))
             (is (find (block-hash target) targets
                       :test #'hash32=
                       :key #'block-hash))))
      (when (probe-file path)
        (delete-file path)))))
