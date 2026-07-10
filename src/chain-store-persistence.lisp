(in-package #:ethereum-lisp.chain-store.persistence)

(defun chain-store-import-from-kv
    (store database &key expected-chain-id chain-config)
  (chain-store-require-memory-store store)
  (unless (txpool-component store)
    (block-validation-fail "Chain import target requires a txpool component"))
  (unless (typep database 'key-value-database)
    (block-validation-fail "Chain import source must be a key-value database"))
  (let ((staging (make-engine-payload-memory-store)))
    (chain-store-import-block-records-from-kv staging database)
    (chain-store-import-header-records-from-kv staging database)
    (chain-store-import-canonical-indexes-from-kv staging database)
    (chain-store-import-receipt-records-from-kv staging database)
    (chain-store-import-state-records-from-kv staging database)
    (chain-store-import-checkpoints-from-kv staging database)
    (chain-store-import-transaction-locations-from-kv staging database)
    (chain-store-import-txpool-records-from-kv
     staging
     database
     :expected-chain-id expected-chain-id
     :chain-config chain-config)
    (chain-store-import-invalid-tipsets-from-kv staging database)
    (chain-store-import-remote-blocks-from-kv staging database)
    (chain-store-import-blob-sidecars-from-kv staging database)
    (chain-store-import-prepared-payloads-from-kv staging database)
    (chain-store-restore-txpool-consistency
     staging
     :expected-chain-id expected-chain-id
     :chain-config chain-config)
    (chain-store-publish-readable-tables store staging))
  store)
