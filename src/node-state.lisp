(in-package #:ethereum-lisp.node-state)

(defstruct (engine-payload-memory-store
            (:constructor make-engine-payload-memory-store
                (&key (blocks (make-hash-table :test 'equal))
                      (number-blocks (make-hash-table :test 'eql))
                      (canonical-hashes (make-hash-table :test 'eql))
                      (transaction-locations (make-hash-table :test 'equal))
                      (account-balances (make-hash-table :test 'equal))
                      (account-nonces (make-hash-table :test 'equal))
                      (account-codes (make-hash-table :test 'equal))
                      (account-storage (make-hash-table :test 'equal))
                      (head-number 0)
                      (state-blocks (make-hash-table :test 'equal))
                      (remote-blocks (make-hash-table :test 'equal))
                      (invalid-tipsets (make-hash-table :test 'equal))
                      (prepared-payloads (make-hash-table :test 'equal))
                      (blob-sidecars (make-hash-table :test 'equal))
                      (txpool (make-engine-pending-txpool))
                      (log-filters (make-hash-table :test 'eql))
                      (next-log-filter-id 1)
                      (head-checkpoint
                       (make-chain-store-checkpoint :label :head))
                      (safe-checkpoint
                       (make-chain-store-checkpoint :label :safe))
                      (finalized-checkpoint
                       (make-chain-store-checkpoint :label :finalized)))))
  blocks
  number-blocks
  canonical-hashes
  transaction-locations
  account-balances
  account-nonces
  account-codes
  account-storage
  (head-number 0 :type (integer 0 *))
  state-blocks
  remote-blocks
  invalid-tipsets
  prepared-payloads
  blob-sidecars
  txpool
  log-filters
  (next-log-filter-id 1 :type (integer 1 *))
  head-checkpoint
  safe-checkpoint
  finalized-checkpoint)
