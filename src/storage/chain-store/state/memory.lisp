(in-package #:ethereum-lisp.chain-store.state)

(defstruct (memory-chain-store
            (:constructor make-memory-chain-store
                (&key (blocks (make-hash-table :test 'equalp))
                      (number-blocks (make-hash-table :test 'eql))
                      (canonical-hashes (make-hash-table :test 'eql))
                      (transaction-locations (make-hash-table :test 'equalp))
                      (account-balances (make-hash-table :test 'equalp))
                      (account-nonces (make-hash-table :test 'equalp))
                      (account-codes (make-hash-table :test 'equalp))
                      (account-storage (make-hash-table :test 'equalp))
                      (head-number 0)
                      (state-blocks (make-hash-table :test 'equalp))
                      (remote-blocks (make-hash-table :test 'equalp))
                      (invalid-tipsets (make-hash-table :test 'equalp))
                      (prepared-payloads (make-hash-table :test 'equalp))
                      (blob-sidecars (make-hash-table :test 'equalp))
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
  log-filters
  (next-log-filter-id 1 :type (integer 1 *))
  head-checkpoint
  safe-checkpoint
  finalized-checkpoint)

(defgeneric chain-store-component (store)
  (:documentation
   "Return STORE's mutable chain component, or NIL when none exists."))

(defmethod chain-store-component ((store t))
  nil)

(defmethod chain-store-component ((store memory-chain-store))
  store)

(defun chain-store-require-memory-store (store)
  (or (chain-store-component store)
      (block-validation-fail "Chain store component is not available")))
