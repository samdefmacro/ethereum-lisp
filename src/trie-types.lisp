(in-package #:ethereum-lisp.trie)

;;;; Trie node and store data structures.

(defstruct leaf-node path value)
(defstruct extension-node path child)
(defstruct branch-node children value)

(defstruct (mpt (:constructor make-mpt ()))
  (entries (make-hash-table :test #'equal)))
