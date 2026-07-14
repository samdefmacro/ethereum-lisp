(in-package #:ethereum-lisp.cli)

;;;; Devnet persisted chain and txpool import helpers.

(defun devnet-cli-call-with-retryable-file-write (label thunk)
  "Call THUNK and classify only file-write failures as retryable storage errors."
  (handler-case
      (funcall thunk)
    (storage-error (condition)
      (error condition))
    (file-error (condition)
      (storage-fail "~A file write failed: ~A" label condition))
    (stream-error (condition)
      (storage-fail "~A stream write failed: ~A" label condition))))

(defun devnet-cli-new-persistence-authority-id ()
  (make-hash32 (devnet-cli-random-bytes 32)))

(defun devnet-cli-persistence-metadata-for-generation
    (state role generation &key base-chain-generation)
  (unless (typep state 'devnet-persistence-state)
    (block-validation-fail
     "Devnet persistence metadata requires persistence state"))
  (make-node-store-persistence-metadata
   :role role
   :generation generation
   :base-chain-generation
   (or base-chain-generation
       (if (eq role :database)
           generation
           (devnet-persistence-state-chain-generation state)))
   :chain-id (devnet-persistence-state-chain-id state)
   :genesis-hash (devnet-persistence-state-genesis-hash state)
   :authority-id (devnet-persistence-state-authority-id state)))

(defun devnet-cli-next-persistence-generation (state)
  (let ((generation
          (1+ (devnet-persistence-state-current-generation state))))
    (unless (ethereum-lisp.validation:uint64-value-p generation)
      (block-validation-fail
       "Devnet persistence generation exhausted uint64 space"))
    generation))

(defun devnet-cli-call-with-next-persistence-generation
    (state role thunk)
  (unless (functionp thunk)
    (block-validation-fail
     "Devnet persistence generation writer must be a function"))
  (let* ((generation (devnet-cli-next-persistence-generation state))
         (metadata
           (devnet-cli-persistence-metadata-for-generation
            state role generation))
         (result (funcall thunk metadata)))
    ;; Confirm only after the artifact batch has completed successfully.
    (setf (devnet-persistence-state-current-generation state) generation)
    (when (eq role :database)
      (setf (devnet-persistence-state-chain-generation state) generation))
    (values result generation)))

(defun devnet-cli-confirm-database-generation (state generation)
  (setf (devnet-persistence-state-chain-generation state) generation
        (devnet-persistence-state-current-generation state)
        (max generation
             (devnet-persistence-state-current-generation state)))
  generation)

(defun devnet-cli-new-payload-persistence-function (database-path)
  (when database-path
    (lambda (store candidate)
      ;; Construct/load first so malformed persisted data remains a permanent
      ;; startup/runtime invariant failure rather than a retry loop.
      (let ((database
              (devnet-cli-make-output-kv-database database-path)))
        (devnet-cli-call-with-retryable-file-write
         "New payload persistence"
         (lambda ()
           (node-store-export-payload-candidate-to-kv
            store candidate database)))))))

(defun devnet-cli-forkchoice-persistence-function
    (database-path persistence-state)
  (when database-path
    (lambda (store transition)
      ;; Export validation and database-corruption conditions pass through and
      ;; fail-stop.  Only an actual write/open/rename stream failure becomes a
      ;; STORAGE-ERROR eligible for dev-period retry.
      (let ((database
              (devnet-cli-make-output-kv-database database-path)))
        (devnet-cli-call-with-next-persistence-generation
         persistence-state
         :database
         (lambda (metadata)
           (devnet-cli-call-with-retryable-file-write
            "Forkchoice persistence"
            (lambda ()
              (node-store-export-forkchoice-to-kv
               store
               transition
               database
               :persistence-metadata metadata)))))))))

(defun devnet-cli-existing-persistence-database (path)
  (when path
    (let ((existing-path (probe-file path)))
      (when (and existing-path
                 (not (devnet-cli-empty-file-p existing-path)))
        (ethereum-lisp.database:make-file-key-value-database
         existing-path)))))

(defun devnet-cli-validated-persistence-metadata
    (database expected-role persistence-state path)
  (when database
    (multiple-value-bind (metadata present-p)
        (node-store-read-persistence-metadata database)
      (when present-p
        (unless (eq expected-role
                    (node-store-persistence-metadata-role metadata))
          (block-validation-fail
           "Persistence artifact has the wrong authority role: ~A" path))
        (unless (= (devnet-persistence-state-chain-id persistence-state)
                   (node-store-persistence-metadata-chain-id metadata))
          (block-validation-fail
           "Persistence artifact chain id is incompatible: ~A" path))
        (unless (hash32=
                 (devnet-persistence-state-genesis-hash persistence-state)
                 (node-store-persistence-metadata-genesis-hash metadata))
          (block-validation-fail
           "Persistence artifact genesis hash is incompatible: ~A" path))
        metadata))))

(defun devnet-cli-import-chain-database
    (store database database-path config genesis-block &key import-txpool-p)
  (when database
    (node-store-import-from-kv
     store
     database
     :expected-chain-id (chain-config-chain-id config)
     :chain-config config
     :track-txpool-database-changes-p t
     :import-txpool-p import-txpool-p)
    (devnet-cli-validate-imported-genesis
     store genesis-block database-path)))

(defun devnet-cli-import-txpool-journal (store journal config)
  ;; A selected journal is a complete snapshot, including the valid empty
  ;; snapshot represented by metadata with no :TXPOOL records.
  (when journal
    (node-store-import-txpool-records-from-kv
     store
     journal
     :expected-chain-id (chain-config-chain-id config)
     :chain-config config
     :skip-indexed-transactions-p t)
    (node-store-restore-txpool-consistency
     store
     :expected-chain-id (chain-config-chain-id config)
     :chain-config config)))

(defun devnet-cli-journal-authoritative-p
    (database-chain-p database-txpool-p database-metadata
     journal-snapshot-p journal-metadata)
  (cond
    ((not journal-snapshot-p) nil)
    ((not database-chain-p)
     (when (and journal-metadata
                (plusp
                 (node-store-persistence-metadata-base-chain-generation
                  journal-metadata)))
       (block-validation-fail
        "Journal without a chain database has a nonzero base generation"))
     t)
    ((and database-metadata journal-metadata)
     (let ((database-generation
             (node-store-persistence-metadata-generation database-metadata))
           (journal-generation
             (node-store-persistence-metadata-generation journal-metadata))
           (journal-base
             (node-store-persistence-metadata-base-chain-generation
              journal-metadata)))
       (cond
         ((> journal-base database-generation)
          (block-validation-fail
           "Journal base generation is newer than the chain database"))
         ((< journal-base database-generation) nil)
         (t (> journal-generation database-generation)))))
    ((and (null database-metadata) journal-metadata)
     (block-validation-fail
      "Versioned journal is incompatible with a legacy chain database"))
    (database-metadata
     ;; Once the database is versioned, an unversioned journal has no proof of
     ;; freshness and must not override it.
     nil)
    (t
     ;; One-time legacy migration preserves the old safe tie-break.
     (not database-txpool-p))))

(defun devnet-cli-install-persistence-authority
    (state database-chain-p database-metadata journal-metadata)
  (when (and database-metadata (not database-chain-p))
    (block-validation-fail
     "Versioned chain database has no chain baseline"))
  (when (and database-metadata journal-metadata
             (not (hash32=
                   (node-store-persistence-metadata-authority-id
                    database-metadata)
                   (node-store-persistence-metadata-authority-id
                    journal-metadata))))
    (block-validation-fail
     "Chain database and journal authority ids do not match"))
  (cond
    (database-metadata
     (setf (devnet-persistence-state-authority-id state)
           (node-store-persistence-metadata-authority-id database-metadata)
           (devnet-persistence-state-chain-generation state)
           (node-store-persistence-metadata-generation database-metadata)
           (devnet-persistence-state-current-generation state)
           (max
            (node-store-persistence-metadata-generation database-metadata)
            (if journal-metadata
                (node-store-persistence-metadata-generation journal-metadata)
                0))))
    ((and journal-metadata (not database-chain-p))
     (setf (devnet-persistence-state-authority-id state)
           (node-store-persistence-metadata-authority-id journal-metadata)
           (devnet-persistence-state-chain-generation state) 0
           (devnet-persistence-state-current-generation state)
           (node-store-persistence-metadata-generation journal-metadata)))
    (t
     (setf (devnet-persistence-state-chain-generation state) 0
           (devnet-persistence-state-current-generation state) 0)))
  state)

(defun devnet-cli-ensure-imported-head-checkpoint
    (store database-path database-head-present-p)
  (unless database-head-present-p
    (let ((head-block
            (chain-store-block-by-number
             store (chain-store-head-number store))))
      (unless head-block
        (error
         "Devnet database has no canonical head block: ~A"
         database-path))
      (chain-store-update-forkchoice-checkpoints
       store
       (make-forkchoice-state
        :head-block-hash (block-hash head-block)
        :safe-block-hash (zero-hash32)
        :finalized-block-hash (zero-hash32))))))

(defun devnet-cli-export-database-at-generation
    (store database-path persistence-state generation)
  (let ((database (devnet-cli-make-output-kv-database database-path)))
    (node-store-export-to-kv
     store
     database
     :persistence-metadata
     (devnet-cli-persistence-metadata-for-generation
      persistence-state :database generation))
    (unless (nth-value 1 (kv-get-chain-checkpoint database :head))
      (error
       "Devnet database has no restartable head checkpoint: ~A"
       database-path)))
  (engine-payload-store-clear-txpool-database-dirty-transaction-hashes store)
  (devnet-cli-confirm-database-generation persistence-state generation))

(defun devnet-cli-export-journal-at-chain-generation
    (store journal-path persistence-state)
  (let ((generation
          (devnet-persistence-state-chain-generation persistence-state)))
    (node-store-export-txpool-records-to-kv
     store
     (devnet-cli-make-output-kv-database journal-path)
     :persistence-metadata
     (devnet-cli-persistence-metadata-for-generation
      persistence-state
      :journal
      generation
      :base-chain-generation generation))))

(defun devnet-cli-import-persistent-state
    (store database-path txpool-journal-path config genesis-block
     persistence-state)
  (let* ((database
           (devnet-cli-existing-persistence-database database-path))
         (journal
           (devnet-cli-existing-persistence-database txpool-journal-path))
         (database-chain-p
           (and database (devnet-cli-kv-chain-records-present-p database)))
         (database-txpool-p
           (and database (devnet-cli-kv-txpool-records-present-p database)))
         (database-head-present-p
           (and database-chain-p
                (nth-value 1 (kv-get-chain-checkpoint database :head))))
         (database-metadata
           (devnet-cli-validated-persistence-metadata
            database :database persistence-state database-path))
         (journal-metadata
           (devnet-cli-validated-persistence-metadata
            journal :journal persistence-state txpool-journal-path))
         (journal-snapshot-p
           (and journal
                (or journal-metadata
                    (devnet-cli-kv-txpool-records-present-p journal)))))
    (when (and database
               (not database-chain-p)
               (devnet-cli-kv-records-present-p database))
      (error
       "Devnet database contains records without a chain baseline: ~A"
       database-path))
    (when (and journal
               (not journal-snapshot-p)
               (devnet-cli-kv-records-present-p journal))
      (error
       "Devnet journal contains records without a txpool snapshot: ~A"
       txpool-journal-path))
    (devnet-cli-install-persistence-authority
     persistence-state
     database-chain-p
     database-metadata
     journal-metadata)
    (let* ((journal-authoritative-p
             (devnet-cli-journal-authoritative-p
              database-chain-p
              database-txpool-p
              database-metadata
              journal-snapshot-p
              journal-metadata))
           (database-rewrite-p
             (and database-path
                  (or (not database-chain-p)
                      (null database-metadata)
                      (not database-head-present-p)
                      journal-authoritative-p))))
      (when database-chain-p
        (devnet-cli-import-chain-database
         store
         database
         database-path
         config
         genesis-block
         :import-txpool-p (not journal-authoritative-p)))
      ;; Tracking must begin before a selected journal is imported so its
      ;; normalized full replacement can be caught up to the chain database.
      (when (and database-path
                 (not
                  (engine-payload-store-txpool-database-change-tracking-enabled-p
                   store)))
        (engine-payload-store-enable-txpool-database-change-tracking store))
      (when journal-authoritative-p
        (devnet-cli-import-txpool-journal store journal config))
      (when (and database-chain-p (not database-head-present-p))
        (devnet-cli-ensure-imported-head-checkpoint
         store database-path database-head-present-p))
      (when database-rewrite-p
        (if (and journal-authoritative-p journal-metadata)
            ;; Copy the already-published journal snapshot to the database at
            ;; the same generation.  This is acknowledgement, not a new
            ;; txpool publication.
            (devnet-cli-export-database-at-generation
             store
             database-path
             persistence-state
             (node-store-persistence-metadata-generation journal-metadata))
            (multiple-value-bind (result generation)
                (devnet-cli-call-with-next-persistence-generation
                 persistence-state
                 :database
                 (lambda (metadata)
                   (node-store-export-to-kv
                    store
                    (devnet-cli-make-output-kv-database database-path)
                    :persistence-metadata metadata)))
              (declare (ignore result))
              (unless
                  (nth-value
                   1
                   (kv-get-chain-checkpoint
                    (devnet-cli-make-output-kv-database database-path)
                    :head))
                (error
                 "Devnet database has no restartable head checkpoint: ~A"
                 database-path))
              (engine-payload-store-clear-txpool-database-dirty-transaction-hashes
               store)
              (devnet-cli-confirm-database-generation
               persistence-state generation))))
      ;; Rewrite an existing legacy or selected journal after DB catch-up so
      ;; both artifacts have an explicit, equal authority baseline.  Do not
      ;; create a journal merely because its path was configured.
      (when (and database-path
                 journal
                 (or (null journal-metadata) database-rewrite-p))
        (devnet-cli-export-journal-at-chain-generation
         store txpool-journal-path persistence-state))
      ;; Journal-only legacy mode has no chain generation to copy.  Publish its
      ;; imported snapshot as generation one with base generation zero.
      (when (and (null database-path)
                 journal-snapshot-p
                 (null journal-metadata))
        (devnet-cli-call-with-next-persistence-generation
         persistence-state
         :journal
         (lambda (metadata)
           (node-store-export-txpool-records-to-kv
            store
            (devnet-cli-make-output-kv-database txpool-journal-path)
            :persistence-metadata metadata))))))
  store)
