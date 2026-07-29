(in-package #:ethereum-lisp.trie)

;;;; Trie node and store data structures.

;; Nodes are immutable after construction. Updates allocate only the changed
;; root-to-leaf path and retain untouched subtrees, so cached encodings and
;; hashes on retained nodes remain valid without an invalidation protocol.
(defstruct leaf-node
  path
  value
  cached-rlp-object
  cached-encoded
  cached-reference
  cached-hash)

(defstruct extension-node
  path
  child
  cached-rlp-object
  cached-encoded
  cached-reference
  cached-hash)

(defstruct branch-node
  children
  value
  cached-rlp-object
  cached-encoded
  cached-reference
  cached-hash)

(defstruct (mpt (:constructor make-mpt ()))
  (entries (make-hash-table :test #'equal))
  root)
