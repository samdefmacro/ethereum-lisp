(in-package #:ethereum-lisp.trie)

;;;; Trie node and store data structures.

;; Nodes are immutable after construction. Updates allocate only the changed
;; root-to-leaf path and retain untouched subtrees, so cached encodings and
;; hashes on retained nodes remain valid without an invalidation protocol.
(defstruct leaf-node
  path
  value
  ;; Fresh nodes are dirty. Decoded durable nodes explicitly set this NIL;
  ;; copy-on-write updates allocate a new dirty root-to-leaf path while
  ;; retaining clean subtrees by reference.
  (dirty-p t :type boolean)
  cached-rlp-object
  cached-encoded
  cached-reference
  cached-hash)

(defstruct extension-node
  path
  child
  (dirty-p t :type boolean)
  cached-rlp-object
  cached-encoded
  cached-reference
  cached-hash)

(defstruct branch-node
  children
  value
  (dirty-p t :type boolean)
  cached-rlp-object
  cached-encoded
  cached-reference
  cached-hash)

(defstruct hash-node
  "A lazily resolved content-addressed trie node."
  hash
  resolver
  resolved)

(defstruct (mpt
            (:constructor make-mpt ())
            (:copier nil))
  (entries (make-hash-table :test #'equal))
  root
  ;; A lazy trie does not claim ENTRIES is a complete leaf index. Point reads
  ;; and writes traverse ROOT; full enumeration deliberately walks the tree.
  (lazy-p nil :type boolean))

(defun copy-mpt (trie)
  "Return a shallow copy of TRIE's immutable node graph.

Only the MPT wrapper and its optional leaf cache are copied. Updates replace
the wrapper's root with newly allocated path nodes, so sharing the old graph is
safe across execution snapshots and avoids rebuilding the account/storage
tries on revert."
  (let ((copy (make-mpt)))
    (maphash (lambda (key value)
               (setf (gethash key (mpt-entries copy)) value))
             (mpt-entries trie))
    (setf (mpt-root copy) (mpt-root trie)
          (mpt-lazy-p copy) (mpt-lazy-p trie))
    copy))

(defun copy-mpt-root (trie)
  "Return an O(1) wrapper snapshot of TRIE's immutable root graph.

The optional ENTRIES table is deliberately not copied.  The returned wrapper
is marked lazy so enumeration traverses the authoritative root instead of
mistaking the empty cache for the complete trie.  This is the snapshot form
used by changed-key rollback; COPY-MPT remains the full cache-preserving branch
copy API."
  (let ((copy (make-mpt)))
    (setf (mpt-root copy) (mpt-root trie)
          (mpt-lazy-p copy) t)
    copy))
