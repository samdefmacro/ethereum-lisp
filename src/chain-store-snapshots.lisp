(in-package #:ethereum-lisp.chain-store)

(defun chain-store-require-memory-store (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Chain store must be an engine payload memory store"))
  store)

(defun engine-payload-store-snapshot (store)
  (make-engine-payload-memory-store
   :blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-blocks store))
   :number-blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-number-blocks store))
   :canonical-hashes
   (engine-payload-store-copy-table
    (engine-payload-memory-store-canonical-hashes store))
   :transaction-locations
   (engine-payload-store-copy-transaction-location-table
    (engine-payload-memory-store-transaction-locations store))
   :account-balances
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-balances store))
   :account-nonces
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-nonces store))
   :account-codes
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-codes store))
   :account-storage
   (engine-payload-store-copy-table
    (engine-payload-memory-store-account-storage store))
   :head-number (engine-payload-memory-store-head-number store)
   :state-blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-state-blocks store))
   :remote-blocks
   (engine-payload-store-copy-table
    (engine-payload-memory-store-remote-blocks store))
   :invalid-tipsets
   (engine-payload-store-copy-block-table
    (engine-payload-memory-store-invalid-tipsets store))
   :prepared-payloads
   (engine-payload-store-copy-prepared-payload-table
    (engine-payload-memory-store-prepared-payloads store))
   :blob-sidecars
   (engine-payload-store-copy-blob-sidecar-table
    (engine-payload-memory-store-blob-sidecars store))
   :txpool
   (engine-pending-txpool-copy
    (engine-payload-memory-store-txpool store))
   :log-filters
   (engine-payload-store-copy-filter-table
    (engine-payload-memory-store-log-filters store))
   :next-log-filter-id
   (engine-payload-memory-store-next-log-filter-id store)
   :head-checkpoint
   (engine-payload-store-copy-checkpoint
    (engine-payload-memory-store-head-checkpoint store))
   :safe-checkpoint
   (engine-payload-store-copy-checkpoint
    (engine-payload-memory-store-safe-checkpoint store))
   :finalized-checkpoint
   (engine-payload-store-copy-checkpoint
    (engine-payload-memory-store-finalized-checkpoint store))))

(defun engine-payload-store-restore (store snapshot)
  (setf (engine-payload-memory-store-blocks store)
        (engine-payload-memory-store-blocks snapshot)
        (engine-payload-memory-store-number-blocks store)
        (engine-payload-memory-store-number-blocks snapshot)
        (engine-payload-memory-store-canonical-hashes store)
        (engine-payload-memory-store-canonical-hashes snapshot)
        (engine-payload-memory-store-transaction-locations store)
        (engine-payload-memory-store-transaction-locations snapshot)
        (engine-payload-memory-store-account-balances store)
        (engine-payload-memory-store-account-balances snapshot)
        (engine-payload-memory-store-account-nonces store)
        (engine-payload-memory-store-account-nonces snapshot)
        (engine-payload-memory-store-account-codes store)
        (engine-payload-memory-store-account-codes snapshot)
        (engine-payload-memory-store-account-storage store)
        (engine-payload-memory-store-account-storage snapshot)
        (engine-payload-memory-store-head-number store)
        (engine-payload-memory-store-head-number snapshot)
        (engine-payload-memory-store-state-blocks store)
        (engine-payload-memory-store-state-blocks snapshot)
        (engine-payload-memory-store-remote-blocks store)
        (engine-payload-memory-store-remote-blocks snapshot)
        (engine-payload-memory-store-invalid-tipsets store)
        (engine-payload-memory-store-invalid-tipsets snapshot)
        (engine-payload-memory-store-prepared-payloads store)
        (engine-payload-memory-store-prepared-payloads snapshot)
        (engine-payload-memory-store-blob-sidecars store)
        (engine-payload-memory-store-blob-sidecars snapshot)
        (engine-payload-memory-store-txpool store)
        (engine-payload-memory-store-txpool snapshot)
        (engine-payload-memory-store-log-filters store)
        (engine-payload-memory-store-log-filters snapshot)
        (engine-payload-memory-store-next-log-filter-id store)
        (engine-payload-memory-store-next-log-filter-id snapshot)
        (engine-payload-memory-store-head-checkpoint store)
        (engine-payload-memory-store-head-checkpoint snapshot)
        (engine-payload-memory-store-safe-checkpoint store)
        (engine-payload-memory-store-safe-checkpoint snapshot)
        (engine-payload-memory-store-finalized-checkpoint store)
        (engine-payload-memory-store-finalized-checkpoint snapshot))
  store)

(defun chain-store-atomic-commit (store thunk)
  (let* ((store (chain-store-require-memory-store store))
         (snapshot (engine-payload-store-snapshot store)))
    (handler-case
        (funcall thunk)
      (error (condition)
        (engine-payload-store-restore store snapshot)
        (error condition)))))
