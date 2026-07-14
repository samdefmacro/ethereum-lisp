(in-package #:ethereum-lisp.cli)

;;;; Devnet persisted chain and txpool import helpers.

(defun devnet-cli-new-payload-persistence-function (database-path)
  (when database-path
    (lambda (store candidate)
      (node-store-export-payload-candidate-to-kv
       store
       candidate
       (devnet-cli-make-output-kv-database database-path)))))

(defun devnet-cli-forkchoice-persistence-function (database-path)
  (when database-path
    (lambda (store transition)
      (node-store-export-forkchoice-to-kv
       store
       transition
       (devnet-cli-make-output-kv-database database-path)))))

(defun devnet-cli-import-chain-database
    (store database-path config genesis-block)
  (when database-path
    (let ((existing-database-path (probe-file database-path)))
      (when (and existing-database-path
                 (not (devnet-cli-empty-file-p existing-database-path)))
        (let ((database
                (ethereum-lisp.database:make-file-key-value-database
                 existing-database-path)))
          (when (devnet-cli-kv-chain-records-present-p database)
            (node-store-import-from-kv
             store
             database
             :expected-chain-id (chain-config-chain-id config)
             :chain-config config
             :track-txpool-database-changes-p t)
            (devnet-cli-validate-imported-genesis
             store genesis-block existing-database-path)))))))

(defun devnet-cli-import-txpool-journal
    (store txpool-journal-path config)
  (when txpool-journal-path
    (let ((existing-journal-path (probe-file txpool-journal-path)))
      (when (and existing-journal-path
                 (not (devnet-cli-empty-file-p existing-journal-path)))
        (let ((journal
                (ethereum-lisp.database:make-file-key-value-database
                 existing-journal-path)))
          (when (devnet-cli-kv-txpool-records-present-p journal)
            (unless (devnet-cli-store-txpool-records-present-p store)
              ;; The chain database is authoritative and may have completed a
              ;; live forkchoice commit just before a crash.  The separately
              ;; persisted journal can lag that commit, so discard records
              ;; whose transactions are already canonical while retaining the
              ;; strict generic KV importer for all other callers.
              (node-store-import-txpool-records-from-kv
               store
               journal
               :expected-chain-id (chain-config-chain-id config)
               :chain-config config
               :skip-indexed-transactions-p t)
              (node-store-restore-txpool-consistency
               store
               :expected-chain-id (chain-config-chain-id config)
               :chain-config config))))))))

(defun devnet-cli-import-persistent-state
    (store database-path txpool-journal-path config genesis-block)
  (devnet-cli-import-chain-database store database-path config genesis-block)
  ;; Seed an empty configured database before the listeners become ready.  A
  ;; later newPayload candidate batch can then remain deliberately
  ;; non-canonical while restart still has the prior canonical baseline.
  (when database-path
    (let ((database (devnet-cli-make-output-kv-database database-path)))
      (if (devnet-cli-kv-chain-records-present-p database)
          (multiple-value-bind (head present-p)
              (kv-get-chain-checkpoint database :head)
            (declare (ignore head))
            (unless present-p
              ;; Migrate a validated legacy snapshot once at startup.  The
              ;; full exporter can see every imported canonical index and
              ;; records an explicit head bound before live direct-key deltas
              ;; are allowed to run.
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
                  :finalized-block-hash (zero-hash32))))
              (node-store-export-to-kv store database)
              (unless (nth-value
                       1 (kv-get-chain-checkpoint database :head))
                (error
                 "Devnet database has no restartable head checkpoint: ~A"
                 database-path))
              (engine-payload-store-clear-txpool-database-dirty-transaction-hashes
               store)))
          (if (devnet-cli-kv-records-present-p database)
              (error
               "Devnet database contains records without a chain baseline: ~A"
               database-path)
              (node-store-export-to-kv store database))))
    ;; A restored store may already track normalization changes relative to
    ;; the database; a freshly seeded store does not.  In either case, ensure
    ;; tracking is active before the optional journal import so the next
    ;; forkchoice commit can persist journal-derived changes without scanning
    ;; the complete txpool.
    (unless
        (engine-payload-store-txpool-database-change-tracking-enabled-p store)
      (engine-payload-store-enable-txpool-database-change-tracking store)))
  (devnet-cli-import-txpool-journal store txpool-journal-path config))
