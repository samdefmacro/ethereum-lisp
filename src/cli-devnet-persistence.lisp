(in-package #:ethereum-lisp.cli)

;;;; Devnet persisted chain and txpool import helpers.

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
            (chain-store-import-from-kv
             store
             database
             :expected-chain-id (chain-config-chain-id config)
             :chain-config config)
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
              (chain-store-import-txpool-records-from-kv
               store
               journal
               :expected-chain-id (chain-config-chain-id config)
               :chain-config config)
              (chain-store-restore-txpool-consistency
               store
               :expected-chain-id (chain-config-chain-id config)
               :chain-config config))))))))

(defun devnet-cli-import-persistent-state
    (store database-path txpool-journal-path config genesis-block)
  (devnet-cli-import-chain-database store database-path config genesis-block)
  (devnet-cli-import-txpool-journal store txpool-journal-path config))
