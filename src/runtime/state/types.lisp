(in-package #:ethereum-lisp.state)

(defconstant +wei-per-gwei+ 1000000000)

(defstruct state-object
  account
  (code (make-byte-vector 0) :type byte-vector)
  (storage (make-hash-table :test #'equal)))

(defstruct (state-db (:constructor make-state-db ()))
  (objects (make-hash-table :test #'equal)))

(defstruct (state-storage-proof
            (:constructor make-state-storage-proof
                (&key slot value proof)))
  slot
  value
  proof)

(defstruct (state-proof-result
            (:constructor make-state-proof-result
                (&key address balance nonce code-hash storage-root
                 account-proof storage-proofs)))
  address
  balance
  nonce
  code-hash
  storage-root
  account-proof
  (storage-proofs '() :type list))

(defstruct (state-account-range-entry
            (:constructor make-state-account-range-entry
                (&key proof-key address account code storage-entries)))
  proof-key
  address
  account
  code
  storage-entries)

(defstruct (state-storage-range-entry
            (:constructor make-state-storage-range-entry
                (&key proof-key slot value)))
  proof-key
  slot
  value)

(defun address-key (address)
  (bytes-to-hex (address-bytes address) :prefix nil))

(defun storage-key (slot)
  (bytes-to-hex (hash32-bytes slot) :prefix nil))

(defun ensure-state-uint256 (value label)
  (unless (uint256-p value)
    (error "~A must be a uint256, got ~S" label value))
  value)
