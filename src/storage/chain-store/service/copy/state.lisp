(in-package #:ethereum-lisp.chain-store)

(defun copy-memory-chain-store (store)
  (setf store (chain-store-require-memory-store store))
  (make-memory-chain-store
   :blocks
   (engine-payload-store-copy-table
    (memory-chain-store-blocks store))
   :number-blocks
   (engine-payload-store-copy-table
    (memory-chain-store-number-blocks store))
   :canonical-hashes
   (engine-payload-store-copy-table
    (memory-chain-store-canonical-hashes store))
   :transaction-locations
   (engine-payload-store-copy-transaction-location-table
    (memory-chain-store-transaction-locations store))
   :account-balances
   (engine-payload-store-copy-table
    (memory-chain-store-account-balances store))
   :account-nonces
   (engine-payload-store-copy-table
    (memory-chain-store-account-nonces store))
   :account-codes
   (engine-payload-store-copy-table
    (memory-chain-store-account-codes store))
   :account-storage
   (engine-payload-store-copy-table
    (memory-chain-store-account-storage store))
   :head-number (memory-chain-store-head-number store)
   :state-blocks
   (engine-payload-store-copy-table
    (memory-chain-store-state-blocks store))
   ;; Diff structs are immutable once installed, so sharing them across
   ;; copies is safe; only the table itself needs copying.
   :state-diffs
   (engine-payload-store-copy-table
    (memory-chain-store-state-diffs store))
   :state-baseline-interval
   (memory-chain-store-state-baseline-interval store)
   :remote-blocks
   (engine-payload-store-copy-table
    (memory-chain-store-remote-blocks store))
   :invalid-tipsets
   (engine-payload-store-copy-block-table
    (memory-chain-store-invalid-tipsets store))
   :prepared-payloads
   (engine-payload-store-copy-prepared-payload-table
    (memory-chain-store-prepared-payloads store))
   :blob-sidecars
   (engine-payload-store-copy-blob-sidecar-table
    (memory-chain-store-blob-sidecars store))
   :log-filters
   (engine-payload-store-copy-filter-table
    (memory-chain-store-log-filters store))
   :next-log-filter-id
   (memory-chain-store-next-log-filter-id store)
   :head-checkpoint
   (engine-payload-store-copy-checkpoint
    (memory-chain-store-head-checkpoint store))
   :safe-checkpoint
   (engine-payload-store-copy-checkpoint
    (memory-chain-store-safe-checkpoint store))
   :finalized-checkpoint
   (engine-payload-store-copy-checkpoint
    (memory-chain-store-finalized-checkpoint store))))
