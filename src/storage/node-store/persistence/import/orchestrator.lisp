(in-package #:ethereum-lisp.node-store.persistence)

(defun node-store-import-from-kv
    (store database &key expected-chain-id chain-config
                         track-txpool-database-changes-p
                         (import-txpool-p t)
                         (import-invalid-tipsets-p t))
  "Hydrate STORE from DATABASE. IMPORT-INVALID-TIPSETS-P NIL leaves persisted
INVALID verdicts out, so the new process re-executes those blocks (node startup
does this; see NODE-STORE-DISCARD-INVALID-TIPSETS-FROM-KV).

Returns STORE, the txpool records dropped as no longer valid at the restored
head (see NODE-STORE-IMPORT-TXPOOL-RECORDS-FROM-KV) and the number of txpool
records read. With TRACK-TXPOOL-DATABASE-CHANGES-P the dropped records are
already marked for deletion by the next txpool delta."
  (chain-store-require-memory-store store)
  (unless (txpool-component store)
    (block-validation-fail "Node import target requires a txpool component"))
  (unless (typep database 'key-value-database)
    (block-validation-fail "Node import source must be a key-value database"))
  ;; Refuse an on-disk schema newer than this client understands before reading
  ;; any record, rather than misinterpreting a future layout, and bring an older
  ;; one forward. Adopting a datadir is the one point where a node is certainly
  ;; its single writer, so it is where the forward migration belongs: every
  ;; later write path may then assume the current layout. Migration advances in
  ;; bounded, resumable batches; an already-current database needs only the
  ;; marker read and performs no write.
  (node-store-migrate-chain-schema database)
  (let ((staging (make-engine-payload-memory-store))
        (txpool-drops '())
        (txpool-records 0))
    (when (engine-payload-store-durable-cache-change-tracking-enabled-p store)
      (engine-payload-store-enable-durable-cache-change-tracking staging))
    (chain-store-import-block-records-from-kv staging database)
    (chain-store-import-header-records-from-kv staging database)
    (chain-store-import-total-difficulty-records-from-kv staging database)
    (chain-store-import-canonical-indexes-from-kv staging database)
    (chain-store-import-receipt-records-from-kv staging database)
    (chain-store-import-state-records-from-kv staging database)
    (chain-store-import-checkpoints-from-kv staging database)
    (chain-store-import-transaction-locations-from-kv staging database)
    (when import-txpool-p
      (multiple-value-setq (txpool-drops txpool-records)
        (node-store-import-txpool-records-from-kv
         staging
         database
         :expected-chain-id expected-chain-id
         :chain-config chain-config)))
    ;; Imported records are the baseline.  When requested by a live database
    ;; owner, start tracking immediately before normalization so every
    ;; prune/promotion relative to that baseline is eligible for the next
    ;; record-scoped forkchoice commit.  A dropped record is part of that
    ;; normalization: the next delta deletes it.
    (when track-txpool-database-changes-p
      (engine-payload-store-enable-txpool-database-change-tracking staging)
      (node-store-note-dropped-txpool-records staging txpool-drops))
    (when import-invalid-tipsets-p
      (chain-store-import-invalid-tipsets-from-kv staging database))
    (chain-store-import-remote-blocks-from-kv staging database)
    (chain-store-import-blob-sidecars-from-kv staging database)
    (chain-store-import-prepared-payloads-from-kv staging database)
    ;; Legacy records do not carry cache-admission timestamps.  Reconcile
    ;; metadata at this startup boundary, then enforce the same deterministic
    ;; count/byte/age/finality budgets as live admission before any table is
    ;; exposed to readers.
    (let ((finalized (chain-store-finalized-block staging)))
      (engine-payload-store-prune-caches
       staging
       :finalized-number
       (and finalized
            (block-header-number (block-header finalized)))))
    (node-store-restore-txpool-consistency
     staging
     :expected-chain-id expected-chain-id
     :chain-config chain-config)
    (chain-store-publish-readable-tables store staging)
    (values store txpool-drops txpool-records)))
