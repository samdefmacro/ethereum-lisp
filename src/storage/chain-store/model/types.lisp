(in-package #:ethereum-lisp.chain-store.model)

(defstruct (chain-store-checkpoint
            (:constructor make-chain-store-checkpoint
                (&key label block-hash)))
  label
  block-hash)

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

(defstruct (chain-store-cache-entry-metadata
            (:constructor make-chain-store-cache-entry-metadata
                (&key inserted-at encoded-bytes block-number)))
  "Deterministic accounting attached to one bounded chain-store cache entry.

INSERTED-AT is a store-observed Unix timestamp rather than an untrusted block
timestamp.  ENCODED-BYTES is the exact number of retained protocol bytes used
by the cache budget.  BLOCK-NUMBER is optional: caches whose value can be tied
to an execution block use it for finality pruning, while content-only entries
leave it NIL until their owner supplies an inclusion height."
  (inserted-at 0 :type (integer 0 *))
  (encoded-bytes 0 :type (integer 0 *))
  (block-number nil :type (or null (integer 0 *))))

(defstruct (engine-log-filter
            (:constructor make-engine-log-filter
                (&key criteria last-block-number block-hash-p
                      block-hash-consumed-p
                      pending-changes deadline)))
  criteria
  last-block-number
  pending-changes
  deadline
  (block-hash-p nil :type boolean)
  (block-hash-consumed-p nil :type boolean))

(defstruct (engine-log-filter-change
            (:constructor make-engine-log-filter-change
                (&key block removed-p)))
  block
  (removed-p nil :type boolean))

(defstruct (engine-block-filter
            (:constructor make-engine-block-filter
                (&key last-block-number hashes deadline)))
  (last-block-number 0 :type (integer 0 *))
  hashes
  deadline)

(defstruct (engine-pending-transaction-filter
            (:constructor make-engine-pending-transaction-filter
                (&key hashes deadline)))
  hashes
  deadline)

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
