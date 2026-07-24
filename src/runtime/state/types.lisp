(in-package #:ethereum-lisp.state)

(defconstant +wei-per-gwei+ 1000000000)

(defstruct state-object
  account
  (code (make-byte-vector 0) :type byte-vector)
  (storage (make-hash-table :test #'equal))
  ;; Memoized STORAGE-ROOT, or NIL when it must be recomputed.
  ;;
  ;; Rebuilding a storage trie is most of the cost of a state root, and the
  ;; root is taken over every account even though a block touches a handful.
  ;;
  ;; INVARIANT: this must be NIL whenever STORAGE could have changed since it
  ;; was filled. STATE-DB-SET-STORAGE is the only writer of STORAGE and is
  ;; responsible for clearing it; deleting an account drops the whole object,
  ;; so no stale entry survives. A missed invalidation is a wrong state root,
  ;; i.e. a consensus divergence -- keep the write path down to that one
  ;; function.
  (cached-storage-root nil))

(defstruct (state-db (:constructor make-state-db ()))
  (objects (make-hash-table :test #'equal))
  ;; Incremental account-root support (wave 3b). DIRTY is the set of address
  ;; keys whose account changed since the last root flush; CACHED-ROOT is the
  ;; memoized account state root.
  ;;
  ;; INVARIANT: CACHED-ROOT is the true root of OBJECTS if and only if DIRTY is
  ;; empty. Otherwise it is stale and STATE-DB-ROOT recomputes. Every function
  ;; that mutates an account -- STATE-DB-SET-ACCOUNT, -CLEAR-ACCOUNT, -SET-CODE,
  ;; -SET-STORAGE (storage changes the account leaf via its storage root), and
  ;; PRUNE-EMPTY-STATE-OBJECT -- marks the address in DIRTY. A missed mark is a
  ;; wrong state root, i.e. a consensus divergence: keep the write path down to
  ;; those functions (verified: nothing outside src/runtime/state mutates
  ;; OBJECTS or a STATE-OBJECT slot). *VERIFY-INCREMENTAL-ROOT* cross-checks
  ;; the memo against a full rebuild.
  (dirty (make-hash-table :test #'equal))
  (cached-root nil))

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
