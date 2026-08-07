(in-package #:ethereum-lisp.state)

(defconstant +wei-per-gwei+ 1000000000)

(defstruct state-object
  account
  ;; CODE is content-addressed and immutable: it is only ever REPLACED by
  ;; STATE-DB-SET-CODE, never written through. Every reader
  ;; (STATE-DB-GET-CODE and the EVM code loaders) already relies on that, so
  ;; CLONE-STATE-OBJECT shares the vector instead of copying it -- a clone
  ;; happens per journal entry and per call frame, and contract code is the
  ;; largest thing on the object.
  (code (make-byte-vector 0) :type byte-vector)
  ;; Memoized (KECCAK-256-HASH CODE), or NIL when it must be recomputed.
  ;;
  ;; INVARIANT: this must be NIL whenever CODE could have changed since it was
  ;; filled. STATE-DB-SET-CODE is the only writer of CODE and refills it in the
  ;; same step. A stale entry is a wrong account leaf, i.e. a consensus
  ;; divergence. A clone may carry it because it shares the very same CODE.
  (cached-code-hash nil)
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
  ;; Historical states install on-demand readers instead of materialising every
  ;; account and slot. Loaded sets also cache negative lookups.
  account-loader
  storage-loader
  materializer
  (loaded-accounts (make-hash-table :test #'equal))
  (loaded-storage (make-hash-table :test #'equal))
  ;; Per-mutation before-images make snapshots integer marks rather than
  ;; whole-world copies. Entries are replayed backwards on revert.
  (journal (make-array 16 :adjustable t :fill-pointer 0))
  (reverting-p nil :type boolean)
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
  ;;
  ;; TRIE is the persistent account trie the root is taken over, kept across
  ;; flushes so a flush applies only the DIRTY accounts instead of rebuilding a
  ;; trie over every account. NIL means "no trustworthy trie": the next flush
  ;; rebuilds from OBJECTS and keeps the result. It is set to NIL by both
  ;; STATE-DB-COPY and STATE-DB-RESTORE, so a trie can never be shared between
  ;; two state-dbs or outlive a reverted frame -- correctness by construction
  ;; rather than by an argument about when flushes happen.
  (dirty (make-hash-table :test #'equal))
  (cached-root nil)
  (trie nil)
  ;; TOUCHED is the set of address keys a block actually MUTATED (as opposed to
  ;; merely read or lazily loaded), accumulated across the whole block and never
  ;; cleared by a root flush. It is the commit's changed-account set: the block
  ;; commit diffs only these against the parent instead of iterating the whole
  ;; materialized world (see COMMIT-STATE-DB-TO-CHAIN-STORE). It is a correct
  ;; SUPERSET of what changed -- a reverted write may leave a key in it, which
  ;; only produces an empty per-account diff -- because every account mutator
  ;; funnels through MARK-ACCOUNT-DIRTY, the one place that records it.
  ;;
  ;; INVARIANT: an account whose committed value differs from the parent's must
  ;; be in TOUCHED. This holds only for a lazily-backed state (STATE-DB-LAZY-P),
  ;; where the untouched remainder equals the parent by construction; the commit
  ;; therefore uses the touched set only for such states.
  (touched (make-hash-table :test #'equal))
  ;; True only within STATE-DB-MATERIALIZE, so filling untouched backing state
  ;; through the ordinary mutators does not pollute TOUCHED. Purely additive:
  ;; nothing else observes it, so existing behaviour is unchanged.
  (loading-p nil :type boolean))

(defstruct state-journal-entry
  key
  previous-object)

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
