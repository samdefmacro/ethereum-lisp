(in-package #:ethereum-lisp.core)

(defstruct (chain-store-checkpoint
            (:constructor make-chain-store-checkpoint
                (&key label block-hash)))
  label
  block-hash)

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

(defstruct (engine-transaction-location
            (:constructor make-engine-transaction-location
                (&key block index transaction receipt log-index-start)))
  block
  (index 0 :type (integer 0 *))
  transaction
  receipt
  (log-index-start 0 :type (integer 0 *)))

(defstruct (engine-blob-and-proofs
            (:constructor make-engine-blob-and-proofs
                (&key blob commitment proof cell-proofs)))
  blob
  commitment
  proof
  cell-proofs)

(defstruct (engine-log-filter
            (:constructor make-engine-log-filter
                (&key criteria last-block-number block-hash-consumed-p
                      pending-changes)))
  criteria
  last-block-number
  pending-changes
  (block-hash-consumed-p nil :type boolean))

(defstruct (engine-log-filter-change
            (:constructor make-engine-log-filter-change
                (&key block removed-p)))
  block
  (removed-p nil :type boolean))

(defstruct (engine-block-filter
            (:constructor make-engine-block-filter
                (&key last-block-number hashes)))
  (last-block-number 0 :type (integer 0 *))
  hashes)

(defstruct (engine-pending-transaction-filter
            (:constructor make-engine-pending-transaction-filter
                (&key hashes)))
  hashes)

(defun engine-pending-transaction-filter-record-hash (filter hash)
  (unless (typep filter 'engine-pending-transaction-filter)
    (block-validation-fail
     "Pending transaction filter must be a pending transaction filter"))
  (unless (hash32-p hash)
    (block-validation-fail "Pending transaction filter hash must be a hash32"))
  (setf (engine-pending-transaction-filter-hashes filter)
        (append
         (engine-pending-transaction-filter-hashes filter)
         (list hash)))
  filter)

(defun engine-block-filter-record-hash (filter hash)
  (unless (typep filter 'engine-block-filter)
    (block-validation-fail "Block filter must be a block filter"))
  (unless (hash32-p hash)
    (block-validation-fail "Block filter hash must be a hash32"))
  (setf (engine-block-filter-hashes filter)
        (append
         (engine-block-filter-hashes filter)
         (list hash)))
  filter)

(defun engine-payload-store-key (hash)
  (unless (hash32-p hash)
    (block-validation-fail "Engine payload store key must be a hash32"))
  (hash32-to-hex hash))
