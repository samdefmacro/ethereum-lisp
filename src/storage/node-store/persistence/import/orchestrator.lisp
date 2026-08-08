(in-package #:ethereum-lisp.node-store.persistence)

(defun node-store-import-from-kv
    (store database &key expected-chain-id chain-config
                         track-txpool-database-changes-p
                         (import-txpool-p t))
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
  (let ((staging (make-engine-payload-memory-store)))
    (chain-store-import-block-records-from-kv staging database)
    (chain-store-import-header-records-from-kv staging database)
    (chain-store-import-canonical-indexes-from-kv staging database)
    (chain-store-import-receipt-records-from-kv staging database)
    (chain-store-import-state-records-from-kv staging database)
    (chain-store-import-checkpoints-from-kv staging database)
    (chain-store-import-transaction-locations-from-kv staging database)
    (when import-txpool-p
      (node-store-import-txpool-records-from-kv
       staging
       database
       :expected-chain-id expected-chain-id
       :chain-config chain-config))
    ;; Imported records are the baseline.  When requested by a live database
    ;; owner, start tracking immediately before normalization so every
    ;; prune/promotion relative to that baseline is eligible for the next
    ;; record-scoped forkchoice commit.
    (when track-txpool-database-changes-p
      (engine-payload-store-enable-txpool-database-change-tracking staging))
    (chain-store-import-invalid-tipsets-from-kv staging database)
    (chain-store-import-remote-blocks-from-kv staging database)
    (chain-store-import-blob-sidecars-from-kv staging database)
    (chain-store-import-prepared-payloads-from-kv staging database)
    (node-store-restore-txpool-consistency
     staging
     :expected-chain-id expected-chain-id
     :chain-config chain-config)
    (chain-store-publish-readable-tables store staging))
  store)
