(in-package #:ethereum-lisp.test)

;;;; Offline database operator workflows. The fine-grained interruption tests
;;;; use the memory KV oracle so their byte-exact results are deterministic. A
;;;; production-backend regression below also closes and reopens real RocksDB
;;;; databases around backup and restore.

(defun node-store-operations-test-rocksdb-path (role)
  (merge-pathnames
   (make-pathname
    :directory
    `(:relative
      ,(format nil "ethereum-lisp-node-store-operations-~(~A~)-~A"
               role (gensym))))
   #P"/private/tmp/"))

(defun node-store-operations-test-delete-rocksdb-path (path)
  (when (probe-file path)
    (uiop:delete-directory-tree
     path :validate t :if-does-not-exist :ignore)))

(deftest node-store-backup-is-bounded-and-byte-exact
  (let ((source (verify-test-database))
        (backup (make-memory-key-value-database)))
    (multiple-value-bind (copied-count copied-p)
        (node-store-backup-chain-database source backup :batch-size 1)
      (is copied-p)
      (is (> copied-count 1)))
    (is (code-store-test-databases-equal-p source backup))
    (is (= +kv-chain-schema-version+
           (node-store-chain-schema-version backup)))
    (multiple-value-bind (progress present-p)
        (kv-get-chain-record backup :metadata "database-copy")
      (declare (ignore progress))
      (is (not present-p)))))

(deftest node-store-backup-resumes-after-a-durable-chunk
  (let ((source (verify-test-database))
        (backup (make-memory-key-value-database))
        (batch-count 0))
    (signals error
      (node-store-backup-chain-database
       source backup
       :batch-size 1
       :after-batch
       (lambda (progress)
         (incf batch-count)
         ;; Callback one follows the refusal marker. Callback two proves the
         ;; first source record and its cursor are already durable together.
         (when (and progress (= batch-count 2))
           (error "injected backup interruption")))))
    (is (= 2 batch-count))
    (signals block-validation-error
      (node-store-chain-schema-version backup))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record backup :metadata "database-copy")
      (is present-p)
      (when present-p
        (let ((progress
                (ethereum-lisp.node-store.persistence::node-store-database-copy-progress-from-record
                 record)))
          (is (= 1
                 (node-store-database-copy-progress-copied-count
                  progress))))))
    (multiple-value-bind (copied-count copied-p)
        (node-store-backup-chain-database source backup :batch-size 1)
      (is copied-p)
      (is (> copied-count 1)))
    (is (code-store-test-databases-equal-p source backup))))

(deftest node-store-restore-requires-a-fresh-target-and-round-trips
  (let ((source (verify-test-database))
        (backup (make-memory-key-value-database))
        (target (make-memory-key-value-database))
        (nonempty (make-memory-key-value-database)))
    (node-store-backup-chain-database source backup :batch-size 2)
    (kv-put nonempty #(1) #(2))
    (signals block-validation-error
      (node-store-restore-chain-database backup nonempty :batch-size 2))
    (node-store-restore-chain-database backup target :batch-size 2)
    (is (code-store-test-databases-equal-p source target))))

(deftest node-store-backup-and-restore-round-trip-on-rocksdb
  (:layer :integration :module :persistence)
  (let* ((source-path
           (node-store-operations-test-rocksdb-path :source))
         (backup-path
           (node-store-operations-test-rocksdb-path :backup))
         (restore-path
           (node-store-operations-test-rocksdb-path :restore))
         (source-database nil)
         (backup-database nil)
         (restore-database nil))
    (unwind-protect
         (progn
           ;; Materialize a valid database into the production backend, then
           ;; close it so the actual backup source proves persisted reopen.
           (setf source-database
                 (make-rocksdb-key-value-database source-path))
           (multiple-value-bind (copied-count copied-p)
               (node-store-backup-chain-database
                (verify-test-database) source-database :batch-size 1)
             (is copied-p)
             (is (> copied-count 1)))
           (close-rocksdb-key-value-database source-database)
           (setf source-database nil)

           ;; Exercise a production-to-production backup and close it before
           ;; restore so neither side can pass through in-memory state.
           (setf source-database
                 (make-rocksdb-key-value-database source-path)
                 backup-database
                 (make-rocksdb-key-value-database backup-path))
           (multiple-value-bind (copied-count copied-p)
               (node-store-backup-chain-database
                source-database backup-database :batch-size 1)
             (is copied-p)
             (is (> copied-count 1)))
           (is (code-store-test-databases-equal-p
                source-database backup-database))
           (close-rocksdb-key-value-database backup-database)
           (setf backup-database nil)
           (close-rocksdb-key-value-database source-database)
           (setf source-database nil)

           ;; Reopen both inputs, restore into a fresh RocksDB directory, and
           ;; prove both raw byte equality and logical verifier cleanliness.
           (setf source-database
                 (make-rocksdb-key-value-database source-path)
                 backup-database
                 (make-rocksdb-key-value-database backup-path)
                 restore-database
                 (make-rocksdb-key-value-database restore-path))
           (multiple-value-bind (copied-count restored-p)
               (node-store-restore-chain-database
                backup-database restore-database :batch-size 1)
             (is restored-p)
             (is (> copied-count 1)))
           (is (code-store-test-databases-equal-p
                source-database backup-database))
           (is (code-store-test-databases-equal-p
                source-database restore-database))
           (is (null (node-store-verify-chain-database backup-database)))
           (is (null (node-store-verify-chain-database restore-database))))
      (dolist (database
               (list restore-database backup-database source-database))
        (when database
          (ignore-errors
            (close-rocksdb-key-value-database database))))
      (dolist (path (list restore-path backup-path source-path))
        (node-store-operations-test-delete-rocksdb-path path)))))

(deftest node-store-backup-keeps-a-mismatched-target-unreadable
  (let ((source (verify-test-database))
        (backup (make-memory-key-value-database))
        (source-mutated-p nil))
    (multiple-value-bind (iterator close-iterator)
        (kv-iterator source)
      (unwind-protect
           (multiple-value-bind (first-key first-value present-p)
               (funcall iterator)
             (declare (ignore first-value))
             (is present-p)
             (signals block-validation-error
               (node-store-backup-chain-database
                source backup
                :batch-size 1
                :after-batch
                (lambda (progress)
                  (when (and progress
                             (= 1
                                (node-store-database-copy-progress-copied-count
                                 progress))
                             (not source-mutated-p))
                    ;; SOURCE changed behind the cursor. The streaming final
                    ;; comparison must detect this instead of publishing the
                    ;; stale target as a complete backup.
                    (setf source-mutated-p t)
                    (kv-put source first-key #(#xff)))))))
        (when close-iterator
          (funcall close-iterator))))
    (is source-mutated-p)
    (signals block-validation-error
      (node-store-chain-schema-version backup))
    (multiple-value-bind (progress present-p)
        (kv-get-chain-record backup :metadata "database-copy")
      (declare (ignore progress))
      (is present-p))))

(deftest node-store-rebuild-regenerates-derived-records-and-resumes
  (let ((source (verify-test-database))
        (target (make-memory-key-value-database))
        (interrupted-p nil))
    (signals error
      (node-store-rebuild-chain-database
       source target
       :batch-size 1
       :after-batch
       (lambda (progress)
         (when (and progress
                    (= 1
                       (node-store-database-copy-progress-copied-count
                        progress))
                    (not interrupted-p))
           (setf interrupted-p t)
           (error "injected rebuild interruption")))))
    (is interrupted-p)
    (signals block-validation-error
      (node-store-chain-schema-version target))
    (node-store-rebuild-chain-database source target :batch-size 1)
    (is (null (node-store-verify-chain-database target)))
    ;; A clean database's derived records are canonical, so rebuilding it is
    ;; byte-exact as well as logically equivalent.
    (is (code-store-test-databases-equal-p source target))))

(deftest node-store-repair-writes-a-clean-sibling-and-preserves-source
  (multiple-value-bind (source store head)
      (verify-test-database)
    (declare (ignore store))
    (let* ((target (make-memory-key-value-database))
           (identifier (hash32-bytes (block-hash head)))
           (number (block-header-number (block-header head)))
           (ordered-identifier
             (ethereum-lisp.database:kv-chain-height-hash-identifier
              number identifier))
           (dangling-identifier (make-byte-vector 32 :initial-element #xaa)))
      ;; Header and ordered mirrors are redundant with the validated block
      ;; body. A dangling header is likewise safe to omit from the sibling.
      (kv-put-chain-record source :header identifier #(#xc0))
      (kv-delete-chain-record source :ordered-block ordered-identifier)
      (kv-put-chain-record source :header dangling-identifier #(#xc0))
      (let ((source-findings (node-store-verify-chain-database source)))
        (is (member :header (verify-test-finding-kinds source-findings)))
        (is (member :ordered-block
                    (verify-test-finding-kinds source-findings))))
      (node-store-repair-chain-database source target :batch-size 1)
      (is (null (node-store-verify-chain-database target)))
      ;; Repair never edits the evidence an operator pointed it at.
      (is (not (null (node-store-verify-chain-database source))))
      (multiple-value-bind (dangling present-p)
          (kv-get-chain-record target :header dangling-identifier)
        (declare (ignore dangling))
        (is (not present-p))))))

(deftest node-store-repair-refuses-primary-damage-before-writing
  (multiple-value-bind (source store head)
      (verify-test-database)
    (declare (ignore store))
    (let ((target (make-memory-key-value-database))
          (identifier (hash32-bytes (block-hash head))))
      (kv-put-chain-record source :block identifier #(#xc0))
      (signals block-validation-error
        (node-store-repair-chain-database source target :batch-size 1))
      (multiple-value-bind (iterator close-iterator)
          (kv-iterator target)
        (unwind-protect
             (multiple-value-bind (key value present-p)
                 (funcall iterator)
               (declare (ignore key value))
               (is (not present-p)))
          (when close-iterator
            (funcall close-iterator)))))))
