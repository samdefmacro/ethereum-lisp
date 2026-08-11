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
           (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
            source invalid-child)
           (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
            source invalid-child
            :head-hash (block-hash propagated-head))
           (let ((database (make-file-key-value-database path)))
             (node-store-export-to-kv source database))
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
                     (node-store-import-from-kv restored database))))
           (let ((direct
                   (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                    restored
                    (block-hash invalid-child)))
                 (propagated
                   (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                    restored
                    (block-hash propagated-head))))
             (is direct)
             (is (not propagated))
             (is (bytes= (block-rlp invalid-child)
                         (block-rlp direct))))
           (let ((status
                   (ethereum-lisp.engine:engine-payload-store-invalid-ancestor-status
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
                     (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                      restored
                      (block-hash propagated-head))))
               (is propagated)
               (is (bytes= (block-rlp invalid-child)
                           (block-rlp propagated)))))
           (let ((database (make-file-key-value-database path)))
             (node-store-export-to-kv
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

(deftest direct-restart-restores-bounded-invalid-verdict-without-reexecution
  (:layer :integration :module :persistence)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-direct-invalid-~A" (gensym))
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
         (invalid
           (make-block
            :header
            (make-block-header
             :number 1
             :parent-hash (block-hash genesis)
             :state-root +empty-trie-hash+
             :mix-hash (zero-hash32)
             :timestamp 2
             :gas-limit 30000000)))
         (config (make-chain-config :chain-id 1))
         (executor-calls 0))
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
           (engine-payload-store-mark-invalid source invalid)
           (node-store-export-invalid-candidate-to-kv
            source invalid database)
           (let ((restored
                   (ethereum-lisp.cli::devnet-cli-import-direct-chain-database
                    (make-file-key-value-database path)
                    "direct-invalid-file-test" config genesis
                    :import-txpool-p nil)))
             (is (engine-payload-store-invalid-block
                  restored (block-hash invalid)))
             (is (engine-payload-store-durable-cache-change-tracking-enabled-p
                  restored))
             (multiple-value-bind (status candidate receipts)
                 (ethereum-lisp.block-import:import-p2p-block-candidate
                  restored invalid config
                  :import-function
                  (lambda (&rest arguments)
                    (declare (ignore arguments))
                    (incf executor-calls)
                    (error "cached invalid block must not execute")))
               (declare (ignore candidate receipts))
               (is (string= +payload-status-invalid+
                            (payload-status-status status)))
               (is (zerop executor-calls)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest direct-startup-streams-and-durably-bounds-legacy-invalid-tipsets
  (:layer :integration :module :persistence :estimated-seconds 15)
  (let* ((path
           (merge-pathnames
            (make-pathname
             :name (format nil "ethereum-lisp-bounded-invalid-direct-~A"
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
         (invalid-count
           (1+
            (* 2
               ethereum-lisp.node-store.persistence::+node-store-remote-recovery-cleanup-batch-size+)))
         (finalized-stale
           (chain-store-bal-persistence-test-block 0 0 :bal-p t))
         (invalids
           (loop for number from 1 to invalid-count
                 collect
                 (chain-store-bal-persistence-test-block
                  number (mod number 256) :bal-p t))))
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
           (let* ((ordered
                    (sort
                     (copy-list invalids)
                     #'string<
                     :key (lambda (block)
                            (hash32-to-hex (block-hash block)))))
                  (shared-evicted (first ordered))
                  (shared-id
                    (hash32-bytes (block-hash shared-evicted)))
                  (stale-id
                    (hash32-bytes (block-hash finalized-stale)))
                  (batch (make-kv-write-batch)))
             ;; Seed a pre-bound namespace before restart. One count-evicted
             ;; invalid shares its BAL with an independent staged owner; the
             ;; finalized record has no other owner and must lose its BAL.
             (dolist (invalid (cons finalized-stale invalids))
               (let ((identifier (hash32-bytes (block-hash invalid))))
                 (kv-batch-put-chain-record
                  batch :invalid-tipset identifier
                  (ethereum-lisp.node-store.persistence::chain-store-block-record-rlp
                   invalid))
                 (kv-batch-put-chain-record
                  batch :block-access-list identifier
                  (block-encoded-block-access-list invalid))))
             (kv-batch-put-chain-record
              batch :staged-block shared-id
              (ethereum-lisp.node-store.persistence::chain-store-block-record-rlp
               shared-evicted))
             (kv-apply-batch database batch)
             (let* ((database (make-file-key-value-database path))
                    (restored
                      (ethereum-lisp.cli::devnet-cli-import-direct-chain-database
                       database "bounded-invalid-file-test" config genesis
                       :import-txpool-p nil))
                    (chain
                      (ethereum-lisp.chain-store.state:chain-store-require-memory-store
                       restored))
                    (durable-invalids
                      (kv-chain-record-entries database :invalid-tipset))
                    (durable-side-data
                      (kv-chain-record-entries database :block-access-list)))
               (is (> invalid-count
                      (* 2
                         ethereum-lisp.node-store.persistence::+node-store-remote-recovery-cleanup-batch-size+)))
               (is (= ethereum-lisp.chain-store:+engine-invalid-tipsets-cap+
                      (hash-table-count
                       (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipsets
                        chain))))
               (is (= ethereum-lisp.chain-store:+engine-invalid-tipsets-cap+
                      (length durable-invalids)))
               ;; The staged owner keeps one extra BAL after its invalid body
               ;; is evicted; every retained invalid owns one more.
               (is (= (1+ (length durable-invalids))
                      (length durable-side-data)))
               (dolist (entry durable-invalids)
                 (is (nth-value
                      1
                      (gethash
                       (bytes-to-hex (car entry))
                       (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipsets
                        chain)))))
               (is (not
                    (nth-value
                     1
                     (kv-get-chain-record
                      database :invalid-tipset shared-id))))
               (is (nth-value
                    1
                    (kv-get-chain-record
                     database :block-access-list shared-id)))
               (dolist (kind '(:invalid-tipset :block-access-list))
                 (is (not
                      (nth-value
                       1
                       (kv-get-chain-record database kind stale-id)))))
               (is (zerop
                    (hash-table-count
                     (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
                      chain)))))))
      (when (probe-file path)
        (delete-file path)))))

(deftest chain-store-cache-bounded-direct-recovery-suppresses-tombstones
  (:layer :integration :module :persistence)
  (let* ((database (make-memory-key-value-database))
         (store (make-engine-payload-memory-store))
         (invalid
           (chain-store-bal-persistence-test-block 0 17 :bal-p t))
         (remote
           (chain-store-bal-persistence-test-block 0 18 :bal-p t))
         (invalid-id (hash32-bytes (block-hash invalid)))
         (remote-id (hash32-bytes (block-hash remote)))
         (chain
           (ethereum-lisp.chain-store.state:chain-store-require-memory-store
            store)))
    (engine-payload-store-enable-durable-cache-change-tracking store)
    (flet ((seed (kind block identifier)
             (let ((batch (make-kv-write-batch)))
               (kv-batch-put-chain-record
                batch kind identifier
                (ethereum-lisp.node-store.persistence::chain-store-block-record-rlp
                 block))
               (kv-batch-put-chain-record
                batch :block-access-list identifier
                (block-encoded-block-access-list block))
               (kv-apply-batch database batch))))
      (seed :invalid-tipset invalid invalid-id)
      (node-store-import-bounded-invalid-tipsets-from-kv
       store database :now 10 :finalized-number 0)
      (seed :remote-block remote remote-id)
      (node-store-import-bounded-remote-blocks-from-kv
       store database :now 10 :finalized-number 0))
    (is (engine-payload-store-durable-cache-change-tracking-enabled-p store))
    (dolist (entry (list (cons :invalid-tipset invalid-id)
                         (cons :remote-block remote-id)
                         (cons :block-access-list invalid-id)
                         (cons :block-access-list remote-id)))
      (is (not
           (nth-value
            1 (kv-get-chain-record database (car entry) (cdr entry))))))
    (is (zerop
         (hash-table-count
          (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
           chain))))
    (is (zerop
         (hash-table-count
          (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
           chain))))))

(deftest bounded-remote-block-import-preserves-captured-invalid-snapshot-clock
  (:layer :integration :module :persistence)
  (let* ((database (make-memory-key-value-database))
         (store (make-engine-payload-memory-store))
         (invalid
           (chain-store-bal-persistence-test-block 1 19 :bal-p t))
         (identifier (hash32-bytes (block-hash invalid)))
         (key
           (ethereum-lisp.chain-store::engine-payload-store-key
            (block-hash invalid)))
         (chain
           (ethereum-lisp.chain-store.state:chain-store-require-memory-store
            store))
         (batch (make-kv-write-batch)))
    ;; The same durable body may be present in both legacy namespaces. INVALID
    ;; wins. REMOTE recovery must consult the invalid snapshot without aging it
    ;; from the captured test clock to the ambient wall clock.
    (dolist (kind '(:invalid-tipset :remote-block))
      (kv-batch-put-chain-record
       batch kind identifier
       (ethereum-lisp.node-store.persistence::chain-store-block-record-rlp
        invalid)))
    (kv-batch-put-chain-record
     batch :block-access-list identifier
     (block-encoded-block-access-list invalid))
    (kv-apply-batch database batch)
    (engine-payload-store-enable-durable-cache-change-tracking store)
    (node-store-import-bounded-invalid-tipsets-from-kv
     store database :now 10)
    (node-store-import-bounded-remote-blocks-from-kv
     store database :now 10)
    (is (nth-value
         1
         (gethash
          key
          (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipsets
           chain))))
    (is (not
         (nth-value
          1
          (gethash
           key
           (ethereum-lisp.chain-store.state:memory-chain-store-remote-blocks
            chain)))))
    (is (nth-value
         1
         (kv-get-chain-record database :invalid-tipset identifier)))
    (is (not
         (nth-value
          1
          (kv-get-chain-record database :remote-block identifier))))
    ;; INVALID still owns the shared BAL after REMOTE is rejected.
    (is (nth-value
         1
         (kv-get-chain-record database :block-access-list identifier)))
    (is (zerop
         (hash-table-count
          (ethereum-lisp.chain-store.state:memory-chain-store-invalid-tipset-durable-deletions
           chain))))
    (is (zerop
         (hash-table-count
          (ethereum-lisp.chain-store.state:memory-chain-store-remote-block-durable-deletions
           chain))))))

(deftest node-store-export-to-kv-prunes-known-invalid-tipset-record
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
           (ethereum-lisp.chain-store:engine-payload-store-mark-invalid store block)
           (let ((database (make-file-key-value-database path)))
             (kv-put-chain-record
              database
              :invalid-tipset
              block-id
              (block-rlp block))
             (node-store-export-to-kv store database))
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

(deftest node-store-import-from-kv-rejects-known-invalid-tipset-record
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
             (node-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :invalid-tipset
              known-id
              (block-rlp known-block)))
           (signals block-validation-error
             (node-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (chain-store-known-block target (block-hash target-block)))
           (is (not (chain-store-known-block target (block-hash known-block))))
           (is (not
                (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                 target
                 (block-hash known-block)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest node-store-import-from-kv-rejects-invalid-tipset-key-mismatch
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
           (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
            target target-block)
           (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
            source invalid-block)
           (let ((database (make-file-key-value-database path)))
             (node-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :invalid-tipset
              (hash32-bytes (block-hash invalid-block))
              (block-rlp replacement)))
           (signals block-validation-error
             (node-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                target
                (block-hash target-block)))
           (is (not
                (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                 target
                 (block-hash invalid-block))))
           (is (not
                (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                 target
                 (block-hash replacement)))))
      (when (probe-file path)
        (delete-file path)))))

(deftest node-store-import-from-kv-rejects-corrupt-invalid-tipset-record
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
           (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
            target target-block)
           (ethereum-lisp.chain-store:engine-payload-store-mark-invalid
            source invalid-block)
           (let ((database (make-file-key-value-database path)))
             (node-store-export-to-kv source database)
             (kv-put-chain-record
              database
              :invalid-tipset
              (hash32-bytes (block-hash invalid-block))
              #(1 2 3)))
           (signals block-validation-error
             (node-store-import-from-kv
              target
              (make-file-key-value-database path)))
           (is (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                target
                (block-hash target-block)))
           (is (not
                (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                 target
                 (block-hash invalid-block)))))
      (when (probe-file path)
        (delete-file path)))))
