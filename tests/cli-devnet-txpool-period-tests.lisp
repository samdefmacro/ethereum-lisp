(in-package #:ethereum-lisp.test)

(defun devnet-cli-test-persistence-metadata (path)
  (multiple-value-bind (metadata present-p)
      (ethereum-lisp.node-store.persistence:node-store-read-persistence-metadata
       (make-file-key-value-database path))
    (unless present-p
      (error "Expected persistence metadata at ~A" path))
    metadata))

(deftest devnet-cli-txpool-journal-persists-pending-transactions
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-journal" "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((seed-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path (namestring genesis-path)
                   :port 0
                   :txpool-journal-path (namestring journal-path)))
                (seed-store (ethereum-lisp.cli:devnet-node-store seed-node))
                (transaction
                  (devnet-cli-txpool-transaction
                   (ethereum-lisp.cli:devnet-node-config seed-node)
                   0
                   +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash (transaction-hash transaction)))
           (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
            seed-store
            transaction)
           (ethereum-lisp.cli::devnet-node-export-database seed-node)
           (let ((journal (make-file-key-value-database journal-path)))
             (is (= 1 (length (kv-chain-record-entries journal :txpool)))))
           (let ((metadata
                   (devnet-cli-test-persistence-metadata journal-path)))
             (is (eq :journal
                     (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-role
                      metadata)))
             (is (= 1
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                     metadata)))
             (is (zerop
                  (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-base-chain-generation
                   metadata))))
           (let* ((restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :txpool-journal-path (namestring journal-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (summary
                    (ethereum-lisp.cli:devnet-node-summary restored-node))
                  (summary-json
                    (ethereum-lisp.cli::devnet-node-summary-json-object
                     restored-node)))
             (is (string= (namestring journal-path)
                          (getf summary :txpool-journal-path)))
             (is (string= (namestring journal-path)
                          (cdr (assoc "txpoolJournalPath"
                                      summary-json
                                      :test #'string=))))
             (is (bytes= (transaction-encoding transaction)
                         (transaction-encoding
                          (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                           restored-store
                           transaction-hash)))))))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-journal-coexists-with-database-restore
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-database" "sexp"))
        (journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-journal" "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json
             :private-keys (list +devnet-cli-txpool-private-key+ 2)))
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :database-path (namestring database-path)
                     :txpool-journal-path (namestring journal-path)))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config seed-node)
                     0
                     +devnet-cli-txpool-pending-gas-price+))
                  (transaction-hash (transaction-hash transaction))
                  (journal-transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config seed-node)
                     0
                     +devnet-cli-txpool-pending-gas-price+
                     :private-key 2))
                  (journal-transaction-hash
                    (transaction-hash journal-transaction)))
             (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
              seed-store
              transaction)
             (ethereum-lisp.cli::devnet-node-export-database seed-node)
             (is (= 1
                    (length
                     (kv-chain-record-entries
                      (make-file-key-value-database database-path)
                      :txpool))))
             (is (= 1
                    (length
                     (kv-chain-record-entries
                      (make-file-key-value-database journal-path)
                      :txpool))))
             (let ((database-metadata
                     (devnet-cli-test-persistence-metadata database-path))
                   (journal-metadata
                     (devnet-cli-test-persistence-metadata journal-path)))
               (is (eq :database
                       (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-role
                        database-metadata)))
               (is (eq :journal
                       (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-role
                        journal-metadata)))
               (is (=
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                     database-metadata)
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                     journal-metadata)))
               (is (=
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                     database-metadata)
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-base-chain-generation
                     journal-metadata)))
               (is (ethereum-lisp.types:hash32=
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-authority-id
                     database-metadata)
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-authority-id
                     journal-metadata)))
               ;; Deliberately diverge the equal-generation journal.  The
               ;; database must win the tie; accepting JOURNAL-TRANSACTION here
               ;; would expose a >= comparison bug.
               (let ((journal-source (make-engine-payload-memory-store)))
                 (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
                  journal-source journal-transaction)
                 (ethereum-lisp.node-store.persistence:node-store-export-txpool-records-to-kv
                  journal-source
                  (make-file-key-value-database journal-path)
                  :persistence-metadata journal-metadata)))
             (let* ((restored-node
                      (ethereum-lisp.cli:make-devnet-node
                       :genesis-path (namestring genesis-path)
                       :port 0
                       :database-path (namestring database-path)
                       :txpool-journal-path (namestring journal-path)))
                    (restored-store
                      (ethereum-lisp.cli:devnet-node-store restored-node)))
               (is (bytes= (transaction-encoding transaction)
                           (transaction-encoding
                            (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                             restored-store
                             transaction-hash))))
               (is (eq nil
                       (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                        restored-store journal-transaction-hash)))
               ;; Advance only the database, leaving the divergent journal one
               ;; generation behind.  This models the DB-first crash window
               ;; with a noncanonical sentinel that canonical filtering cannot
               ;; hide.
               (ethereum-lisp.cli::devnet-cli-call-with-next-persistence-generation
                (ethereum-lisp.cli::devnet-node-persistence-state restored-node)
                :database
                (lambda (metadata)
                  (node-store-export-to-kv
                   restored-store
                   (make-file-key-value-database database-path)
                   :persistence-metadata metadata)))
               (let ((database-metadata
                       (devnet-cli-test-persistence-metadata database-path))
                     (journal-metadata
                       (devnet-cli-test-persistence-metadata journal-path)))
                 (is (>
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                       database-metadata)
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                       journal-metadata))))
               (let* ((stale-restored-node
                        (ethereum-lisp.cli:make-devnet-node
                         :genesis-path (namestring genesis-path)
                         :port 0
                         :database-path (namestring database-path)
                         :txpool-journal-path (namestring journal-path)))
                      (stale-restored-store
                        (ethereum-lisp.cli:devnet-node-store
                         stale-restored-node)))
                 (is (bytes=
                      (transaction-encoding transaction)
                      (transaction-encoding
                       (ethereum-lisp.txpool:engine-payload-store-pending-transaction
                        stale-restored-store transaction-hash))))
                 (is (eq nil
                         (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                          stale-restored-store
                          journal-transaction-hash)))))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-newer-txpool-journal-replaces-database-snapshot
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-newer-journal-db"
                                "sexp"))
        (journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-newer-journal"
                                "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-newer-journal-genesis"
                                "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json
             :private-keys (list 2 +devnet-cli-txpool-private-key+)))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :database-path (namestring database-path)
                     :txpool-journal-path (namestring journal-path)))
                  (store (ethereum-lisp.cli:devnet-node-store node))
                  (config (ethereum-lisp.cli:devnet-node-config node))
                  (database-transaction
                    (devnet-cli-txpool-transaction
                     config 0 +devnet-cli-txpool-pending-gas-price+
                     :private-key 2))
                  (journal-transaction
                    (devnet-cli-txpool-transaction
                     config 0 +devnet-cli-txpool-pending-gas-price+))
                  (database-hash (transaction-hash database-transaction))
                  (journal-hash (transaction-hash journal-transaction)))
             (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
              store database-transaction)
             (ethereum-lisp.cli::devnet-node-export-database node)
             (ethereum-lisp.txpool::engine-payload-store-remove-pending-transaction
              store database-hash)
             (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
              store journal-transaction)
             (is (eq t (ethereum-lisp.cli::devnet-node-rejournal node)))
             (let ((database-metadata
                     (devnet-cli-test-persistence-metadata database-path))
                   (journal-metadata
                     (devnet-cli-test-persistence-metadata journal-path)))
               (is (<
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                     database-metadata)
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                     journal-metadata)))
               (is (=
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                     database-metadata)
                    (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-base-chain-generation
                     journal-metadata))))
             (let* ((restored-node
                      (ethereum-lisp.cli:make-devnet-node
                       :genesis-path (namestring genesis-path)
                       :database-path (namestring database-path)
                       :txpool-journal-path (namestring journal-path)))
                    (restored-store
                      (ethereum-lisp.cli:devnet-node-store restored-node)))
               (is (eq nil
                       (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                        restored-store database-hash)))
               (is (bytes=
                    (transaction-encoding journal-transaction)
                    (transaction-encoding
                     (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                      restored-store journal-hash))))
               (let ((database
                       (make-file-key-value-database database-path))
                     (database-metadata
                       (devnet-cli-test-persistence-metadata database-path))
                     (journal-metadata
                       (devnet-cli-test-persistence-metadata journal-path)))
                 (is (= 1 (length (kv-chain-record-entries database :txpool))))
                 (is (bytes=
                      (hash32-bytes journal-hash)
                      (caar (kv-chain-record-entries database :txpool))))
                 (is (=
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                       database-metadata)
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                       journal-metadata)))
                 (is (=
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                       database-metadata)
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-base-chain-generation
                       journal-metadata)))))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-newer-empty-journal-clears-database-txpool
  (let* ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-empty-journal-db"
                                "sexp"))
        (journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-empty-journal"
                                "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-empty-journal-genesis"
                                "json"))
        (real-directory
          (merge-pathnames
           (make-pathname
            :directory
            (list :relative
                  (format nil "ethereum-lisp-real-~A"
                          (devnet-cli-temp-token))))
           (devnet-cli-temp-root)))
        (link-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-link" nil))
        (symlink-database-path
          (merge-pathnames "database.sexp" real-directory))
        (symlink-journal-path
          (format nil
                  "~A~A/../~A/~A"
                  (namestring (devnet-cli-temp-root))
                  (gensym "MISSING-")
                  (file-namestring link-path)
                  (file-namestring symlink-database-path))))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path (devnet-cli-funded-txpool-genesis-json))
           ;; A lexical cancellation can expose an existing directory
           ;; symlink, so canonicalization must repeat until stable.
           (ensure-directories-exist symlink-database-path)
           (uiop:run-program
            (list "ln" "-s"
                  (namestring real-directory)
                  (namestring link-path))
            :output nil
            :error-output nil)
           (is (not (string= (namestring symlink-database-path)
                             symlink-journal-path)))
           (signals error
             (ethereum-lisp.cli:make-devnet-node
              :genesis-path (namestring genesis-path)
              :database-path (namestring symlink-database-path)
              :txpool-journal-path symlink-journal-path))
           (is (not (probe-file symlink-database-path)))
           ;; Database and journal writes must never target the same artifact.
           (signals error
             (ethereum-lisp.cli:make-devnet-node
              :genesis-path (namestring genesis-path)
              :database-path (namestring database-path)
              :txpool-journal-path
              (enough-namestring
               database-path *default-pathname-defaults*)))
           (signals error
             (ethereum-lisp.cli:make-devnet-node
              :genesis-path (namestring genesis-path)
              :database-path (namestring database-path)
              :txpool-journal-path
              (format nil
                      "~A~A/../~A"
                      (namestring
                       (uiop:pathname-directory-pathname database-path))
                      (gensym "MISSING-")
                      (file-namestring database-path))))
           (is (not (probe-file database-path)))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :database-path (namestring database-path)
                     :txpool-journal-path (namestring journal-path)))
                  (store (ethereum-lisp.cli:devnet-node-store node))
                  (transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config node)
                     0
                     +devnet-cli-txpool-pending-gas-price+))
                  (transaction-hash (transaction-hash transaction)))
             (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
              store transaction)
             (ethereum-lisp.cli::devnet-node-export-database node)
             (ethereum-lisp.txpool::engine-payload-store-remove-pending-transaction
              store transaction-hash)
             (is (eq t (ethereum-lisp.cli::devnet-node-rejournal node)))
             (is (null
                  (kv-chain-record-entries
                   (make-file-key-value-database journal-path) :txpool)))
             (let* ((restored-node
                      (ethereum-lisp.cli:make-devnet-node
                       :genesis-path (namestring genesis-path)
                       :database-path (namestring database-path)
                       :txpool-journal-path (namestring journal-path)))
                    (restored-store
                      (ethereum-lisp.cli:devnet-node-store restored-node)))
               (is (eq nil
                       (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                        restored-store transaction-hash)))
               (is (null
                    (kv-chain-record-entries
                     (make-file-key-value-database database-path) :txpool)))
               (let ((database-metadata
                       (devnet-cli-test-persistence-metadata database-path))
                     (journal-metadata
                       (devnet-cli-test-persistence-metadata journal-path)))
                 (is (=
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                       database-metadata)
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                       journal-metadata)))
                 (is (=
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                       database-metadata)
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-base-chain-generation
                       journal-metadata)))))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path))
      (when (probe-file link-path)
        (delete-file link-path))
      (when (probe-file real-directory)
        (uiop:delete-directory-tree real-directory :validate t)))))

(deftest devnet-cli-rejects-incompatible-journal-metadata
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-incompatible-db"
                                "sexp"))
        (journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-incompatible-journal"
                                "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-incompatible-genesis"
                                "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path (devnet-cli-funded-txpool-genesis-json))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :database-path (namestring database-path)
                     :txpool-journal-path (namestring journal-path)))
                  (store (ethereum-lisp.cli:devnet-node-store node))
                  (config (ethereum-lisp.cli:devnet-node-config node))
                  (transaction
                    (devnet-cli-txpool-transaction
                     config 0 +devnet-cli-txpool-pending-gas-price+))
                  (transaction-hash (transaction-hash transaction)))
             (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
              store transaction)
             (ethereum-lisp.cli::devnet-node-export-database node)
             ;; Leave an unapplied txpool delta so the forkchoice guard must
             ;; preserve both the durable record and its dirty acknowledgement.
             (ethereum-lisp.txpool::engine-payload-store-remove-pending-transaction
              store transaction-hash)
             (let* ((database-metadata
                      (devnet-cli-test-persistence-metadata database-path))
                    (database-generation
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-generation
                       database-metadata))
                    (authority-id
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-authority-id
                       database-metadata))
                    (genesis-hash
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-genesis-hash
                       database-metadata))
                    (chain-id
                      (ethereum-lisp.node-store.persistence:node-store-persistence-metadata-chain-id
                       database-metadata))
                    (dirty-hashes-before
                      (mapcar
                       #'hash32-to-hex
                       (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
                        store)))
                    (txpool-records-before
                      (kv-chain-record-entries
                       (make-file-key-value-database database-path)
                       :txpool)))
               (is (= 1 (length dirty-hashes-before)))
               (is (= 1 (length txpool-records-before)))
               ;; Versioned artifacts cannot change while retaining stale
               ;; authority metadata.
               (signals block-validation-error
                 (ethereum-lisp.node-store.persistence:node-store-export-to-kv
                  store (make-file-key-value-database database-path)))
               (signals block-validation-error
                 (ethereum-lisp.node-store.persistence:chain-store-export-indexes-to-kv
                  store (make-file-key-value-database database-path)))
               (signals block-validation-error
                 (ethereum-lisp.node-store.persistence:node-store-export-forkchoice-to-kv
                  store
                  (ethereum-lisp.canonical-chain::make-canonical-chain-transition
                   :changed-txpool-hashes (list transaction-hash))
                  (make-file-key-value-database database-path)))
               (is (equal dirty-hashes-before
                          (mapcar
                           #'hash32-to-hex
                           (ethereum-lisp.txpool:engine-payload-store-txpool-database-dirty-transaction-hashes
                            store))))
               (is (equalp
                    txpool-records-before
                    (kv-chain-record-entries
                     (make-file-key-value-database database-path)
                     :txpool)))
               ;; A journal cannot claim a snapshot based on a future DB.
               (ethereum-lisp.node-store.persistence:node-store-export-txpool-records-to-kv
                store
                (make-file-key-value-database journal-path)
                :persistence-metadata
                (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
                 :role :journal
                 :generation (+ database-generation 2)
                 :base-chain-generation (1+ database-generation)
                 :chain-id chain-id
                 :genesis-hash genesis-hash
                 :authority-id authority-id))
               (signals block-validation-error
                 (ethereum-lisp.node-store.persistence:node-store-export-txpool-records-to-kv
                  store (make-file-key-value-database journal-path)))
               (signals block-validation-error
                 (ethereum-lisp.cli:make-devnet-node
                  :genesis-path (namestring genesis-path)
                  :database-path (namestring database-path)
                  :txpool-journal-path (namestring journal-path)))
               ;; Matching generations still cannot bridge persistence
               ;; lifecycles with different authority ids.
               (ethereum-lisp.node-store.persistence:node-store-export-txpool-records-to-kv
                store
                (make-file-key-value-database journal-path)
                :persistence-metadata
                (ethereum-lisp.node-store.persistence:make-node-store-persistence-metadata
                 :role :journal
                 :generation (1+ database-generation)
                 :base-chain-generation database-generation
                 :chain-id chain-id
                 :genesis-hash genesis-hash
                 :authority-id (zero-hash32)))
               (signals block-validation-error
                 (ethereum-lisp.cli:make-devnet-node
                  :genesis-path (namestring genesis-path)
                  :database-path (namestring database-path)
                  :txpool-journal-path (namestring journal-path)))
               ;; A present but undecodable metadata record fails closed.
               (kv-put-chain-record
                (make-file-key-value-database journal-path)
                :metadata
                ethereum-lisp.node-store.persistence::+node-store-persistence-metadata-identifier+
                (vector #xff))
               (signals block-validation-error
                 (ethereum-lisp.cli:make-devnet-node
                  :genesis-path (namestring genesis-path)
                  :database-path (namestring database-path)
                  :txpool-journal-path (namestring journal-path))))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-rejournal-refreshes-live-journal
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-rejournal"
                                "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json"))
        (now 100))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :txpool-journal-path (namestring journal-path)
                     :txpool-rejournal-seconds 10))
                  (state
                    (ethereum-lisp.cli::make-devnet-rejournal-state
                     node
                     10
                     :now-function (lambda () now)))
                  (transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config node)
                     0
                     +devnet-cli-txpool-pending-gas-price+))
                  (telemetry-fields
                    (ethereum-lisp.cli::devnet-node-telemetry-fields node)))
             (is (string= "10"
                          (cdr (assoc "txpoolRejournalSeconds"
                                      telemetry-fields
                                      :test #'string=))))
             (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
              (ethereum-lisp.cli:devnet-node-store node)
              transaction)
             (setf now 109)
             (is (eq nil
                     (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
             (is (not (probe-file journal-path)))
             (setf now 110)
             (is (eq t
                     (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
             (let ((journal (make-file-key-value-database journal-path)))
               (is (= 1
                      (length
                       (kv-chain-record-entries journal :txpool)))))))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-rejournal-without-journal-is-noop
  (let ((unused-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-unused-rejournal"
                                "sexp"))
        (now 0))
    (unwind-protect
         (let* ((node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :port 0
                   :txpool-rejournal-seconds 1))
                (state
                  (ethereum-lisp.cli::make-devnet-rejournal-state
                   node
                   1
                   :now-function (lambda () now))))
           (setf now 1)
           (is (eq nil
                   (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
           (is (not (probe-file unused-path))))
      (when (probe-file unused-path)
        (delete-file unused-path)))))

(deftest devnet-cli-dev-period-parses-and-reports-duration
  (let* ((options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet"
                  "--dev"
                  "--dev.period=2m"
                  "--no-serve")))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path +devnet-cli-genesis-fixture+
            :port 0
            :dev-mode-p (getf options :dev-mode-p)
            :dev-period-seconds (getf options :dev-period-seconds)))
         (summary
           (ethereum-lisp.cli::devnet-node-summary-json-object node))
         (telemetry-fields
           (ethereum-lisp.cli::devnet-node-telemetry-fields node)))
    (is (= 120 (getf options :dev-period-seconds)))
    (is (= 120 (fixture-object-field summary "devPeriodSeconds")))
    (is (string= "120"
                 (cdr (assoc "devPeriodSeconds"
                             telemetry-fields
                             :test #'string=))))
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--dev.period=-1" "--no-serve")))
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--dev.period=bad" "--no-serve")))))

(deftest devnet-cli-dev-period-tick-seals-public-txpool-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json)
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (raw-transaction (devnet-cli-transaction-raw transaction))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now)))
           (send-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":1,"
               "\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\"" raw-transaction "\"]}")
              node)))
      (is (string= transaction-hash (field send-response "result")))
      (is (eq nil (ethereum-lisp.cli::devnet-dev-period-state-tick state)))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (block-number-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"eth_blockNumber\",\"params\":[]}"
                node))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                node))
             (receipt-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":4,"
                 "\"method\":\"eth_getTransactionReceipt\","
                 "\"params\":[\"" transaction-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (mined-transaction (field lookup-response "result"))
             (receipt (field receipt-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (string= (quantity-to-hex 1)
                     (field block-number-response "result")))
        (is (string= transaction-hash
                     (field mined-transaction "hash")))
        (is (string= sealed-hash
                     (field mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field mined-transaction "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field mined-transaction "transactionIndex")))
        (is (string= transaction-hash
                     (field receipt "transactionHash")))
        (is (string= sealed-hash (field receipt "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field receipt "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field receipt "transactionIndex")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-bounds-transactions-by-gas-limit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json
                             :gas-limit 42000)
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (first-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :gas-limit 21000))
           (second-transaction
             (devnet-cli-txpool-transaction
              config
              1
              +devnet-cli-txpool-pending-gas-price+
              :gas-limit 30000))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex
                         (transaction-hash second-transaction)))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now))))
      (dolist (transaction (list first-transaction second-transaction))
        (request
         (concatenate
          'string
          "{\"jsonrpc\":\"2.0\",\"id\":1,"
          "\"method\":\"eth_sendRawTransaction\","
          "\"params\":[\""
          (devnet-cli-transaction-raw transaction)
          "\"]}")
         node))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (first-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":2,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" first-hash "\"]}")
                node))
             (second-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (mined-transaction (field first-lookup "result"))
             (leftover-transaction (field second-lookup "result"))
             (pending-transactions (field pending-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (= 1 (length (block-transactions sealed-block))))
        (is (string= first-hash
                     (hash32-to-hex
                      (transaction-hash
                       (first (block-transactions sealed-block))))))
        (is (string= first-hash
                     (field mined-transaction "hash")))
        (is (string= sealed-hash
                     (field mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 0)
                     (field mined-transaction "transactionIndex")))
        (is (string= second-hash
                     (field leftover-transaction "hash")))
        (is (null (field leftover-transaction "blockHash")))
        (is (= 1 (length pending-transactions)))
        (is (string= second-hash
                     (field (first pending-transactions) "hash")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-selects-fitting-second-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (first-private-key 2)
           (second-private-key +devnet-cli-txpool-private-key+)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json
                             :gas-limit 42000
                             :private-keys (list first-private-key
                                                 second-private-key))
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (first-sender-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :private-key first-private-key
              :gas-limit 21000))
           (first-sender-non-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              1
              +devnet-cli-txpool-pending-gas-price+
              :private-key first-private-key
              :gas-limit 30000))
           (second-sender-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :private-key second-private-key
              :gas-limit 21000))
           (first-fitting-hash
             (hash32-to-hex
              (transaction-hash first-sender-fitting-transaction)))
           (first-non-fitting-hash
             (hash32-to-hex
              (transaction-hash first-sender-non-fitting-transaction)))
           (second-fitting-hash
             (hash32-to-hex
              (transaction-hash second-sender-fitting-transaction)))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now))))
      (dolist (transaction
               (list first-sender-fitting-transaction
                     first-sender-non-fitting-transaction
                     second-sender-fitting-transaction))
        (request
         (concatenate
          'string
          "{\"jsonrpc\":\"2.0\",\"id\":1,"
          "\"method\":\"eth_sendRawTransaction\","
          "\"params\":[\""
          (devnet-cli-transaction-raw transaction)
          "\"]}")
         node))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (mined-hashes
               (mapcar
                (lambda (transaction)
                  (hash32-to-hex (transaction-hash transaction)))
                (block-transactions sealed-block)))
             (second-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":2,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-fitting-hash "\"]}")
                node))
             (second-receipt
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionReceipt\","
                 "\"params\":[\"" second-fitting-hash "\"]}")
                node))
             (leftover-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":4,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" first-non-fitting-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (second-mined-transaction (field second-lookup "result"))
             (second-mined-receipt (field second-receipt "result"))
             (leftover-transaction (field leftover-lookup "result"))
             (pending-transactions (field pending-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (equal (list first-fitting-hash second-fitting-hash)
                   mined-hashes))
        (is (string= second-fitting-hash
                     (field second-mined-transaction "hash")))
        (is (string= sealed-hash
                     (field second-mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field second-mined-transaction "transactionIndex")))
        (is (string= second-fitting-hash
                     (field second-mined-receipt "transactionHash")))
        (is (string= sealed-hash
                     (field second-mined-receipt "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field second-mined-receipt "transactionIndex")))
        (is (string= first-non-fitting-hash
                     (field leftover-transaction "hash")))
        (is (null (field leftover-transaction "blockHash")))
        (is (= 1 (length pending-transactions)))
        (is (string= first-non-fitting-hash
                     (field (first pending-transactions) "hash")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-carries-active-fork-bodies
  (let* ((now 0)
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json
            (devnet-cli-funded-txpool-genesis-json
             :config-fields
             (list (cons "cancunTime" "0x0")
                   (cons "pragueTime" "0x0")
                   (cons "amsterdamTime" "0x0"))
             :code-accounts
             (loop for address
                     in '("0x00000961ef480eb55e80d19ad83579a64c007002"
                          "0x0000bbddc7ce488642fb579f8b00f3a590007251")
                   collect
                   (cons address #(#x60 #x00 #x60 #x00 #xf3))))
            :port 0
            :dev-mode-p t
            :dev-period-seconds 1))
         (config (ethereum-lisp.cli:devnet-node-config node))
         (transaction
           (devnet-cli-txpool-transaction
            config
            0
            +devnet-cli-txpool-pending-gas-price+))
         (state
           (ethereum-lisp.cli::make-devnet-dev-period-state
            node
            1
            :now-function (lambda () now))))
    (engine-rpc-handle-request-json
     (concatenate
      'string
      "{\"jsonrpc\":\"2.0\",\"id\":1,"
      "\"method\":\"eth_sendRawTransaction\","
      "\"params\":[\"" (devnet-cli-transaction-raw transaction) "\"]}")
     (ethereum-lisp.cli:devnet-node-store node)
     config)
    (setf now 1)
    (let* ((block
             (ethereum-lisp.cli::devnet-dev-period-state-tick state))
           (header (block-header block)))
      (is (typep block 'ethereum-block))
      (is (= 1 (length (block-transactions block))))
      (is (= 0 (block-header-blob-gas-used header)))
      (is (= 0 (block-header-excess-blob-gas header)))
      (is (string= (hash32-to-hex (zero-hash32))
                   (hash32-to-hex
                    (block-header-parent-beacon-root header))))
      (is (block-requests-present-p block))
      (is (null (block-requests block)))
      (is (string= (hash32-to-hex (execution-requests-hash '()))
                   (hash32-to-hex
                    (block-header-requests-hash header))))
      (is (block-block-access-list-present-p block))
      (is (null (block-block-access-list block)))
      (is (string= (hash32-to-hex (block-access-list-hash '()))
                   (hash32-to-hex
                    (block-header-block-access-list-hash header)))))))

(deftest devnet-cli-txpool-journal-rejects-wrong-chain-transactions
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-bad-chain"
                                "sexp")))
    (unwind-protect
         (let* ((config
                  (chain-config-from-genesis-json-file
                   +devnet-cli-genesis-fixture+))
                (transaction
                  (fixture-sign-legacy-transaction
                   (make-legacy-transaction
                    :nonce 0
                    :gas-price +devnet-cli-txpool-gas-price+
                    :gas-limit +devnet-cli-txpool-gas-limit+
                    :to (address-from-hex +devnet-cli-txpool-recipient+)
                    :value +devnet-cli-txpool-value+)
                   +devnet-cli-txpool-private-key+
                   (1+ (chain-config-chain-id config))))
                (journal (make-file-key-value-database journal-path)))
           (kv-put-chain-record
            journal
            :txpool
            (hash32-bytes (transaction-hash transaction))
            (ethereum-lisp.node-store.persistence::chain-store-txpool-transaction-record-rlp
             :pending
             transaction))
           (signals block-validation-error
             (ethereum-lisp.cli:make-devnet-node
              :genesis-path +devnet-cli-genesis-fixture+
              :port 0
              :txpool-journal-path (namestring journal-path))))
      (when (probe-file journal-path)
        (delete-file journal-path)))))
