(in-package #:ethereum-lisp.trie)

;;;; Durable trie nodes and resumable traversal.

(defstruct mpt-range-proof
  entries)

(defun trie-node-children (node)
  (etypecase node
    (leaf-node nil)
    (extension-node (list (extension-node-child node)))
    (branch-node
     (loop for child across (branch-node-children node)
           when child collect child))))

(defun mpt-persist (database trie)
  "Atomically persist every reachable node by Keccak hash and return the root."
  (let ((batch (make-kv-write-batch))
        (seen (make-hash-table :test #'equal))
        (root (mpt-root-node trie)))
    (labels ((persist-node (node)
               (let* ((hash (node-hash node))
                      (key (bytes-to-hex hash :prefix nil)))
                 (unless (gethash key seen)
                   (setf (gethash key seen) t)
                   (dolist (child (trie-node-children node))
                     (persist-node child))
                   (kv-batch-put-chain-record
                    batch :trie-node hash (encoded-node node))))))
      (when root
        (persist-node root))
      (kv-apply-batch database batch)
      (if root
          (make-hash32 (node-hash root))
          +empty-trie-hash+))))

(defun trie-node-store-get (database hash)
  "Return an encoded persisted node and a presence flag."
  (kv-get-chain-record
   database :trie-node
   (if (hash32-p hash) (hash32-bytes hash) (ensure-byte-vector hash))))

(defun make-mpt-iterator (trie &key after)
  "Return a closure yielding KEY, VALUE, CURSOR, PRESENT-P.

AFTER is a cursor returned by an earlier iterator and is excluded, making a
page boundary resumable without repeating an entry."
  (let* ((entries (mpt-entry-pairs trie))
         (after-id (and after (bytes-to-hex after :prefix nil)))
         (remaining
           (if after-id
               (member-if
                (lambda (entry)
                  (string< after-id
                           (bytes-to-hex (car entry) :prefix nil)))
                entries)
               entries)))
    (lambda ()
      (if remaining
          (let* ((entry (pop remaining))
                 (key (copy-seq (car entry))))
            (values key (copy-seq (cdr entry)) key t))
          (values nil nil nil nil)))))

(defun mpt-get-range-proof (trie &key start end limit)
  "Return a bounded range and a self-contained proof of completeness.

The first implementation deliberately carries the full ordered leaf set. It is
larger than snap's compact boundary proof, but a verifier can reconstruct the
committed root and therefore detect omitted, inserted, or reordered leaves."
  (let* ((range (mpt-entry-range trie :start start :end end))
         (bounded (if limit (subseq range 0 (min limit (length range))) range)))
    (values bounded
            (make-mpt-range-proof :entries (mpt-entry-pairs trie)))))

(defun mpt-entry-pairs-equal-p (left right)
  (and (= (length left) (length right))
       (every (lambda (a b)
                (and (bytes= (car a) (car b))
                     (bytes= (cdr a) (cdr b))))
              left right)))

(defun mpt-verify-range-proof
    (root-hash entries proof &key start end limit)
  "Verify range membership, ordering, and completeness against ROOT-HASH."
  (unless (mpt-range-proof-p proof)
    (error "MPT range proof has an invalid representation"))
  (let ((trie (make-mpt)))
    (dolist (entry (mpt-range-proof-entries proof))
      (mpt-put trie (car entry) (cdr entry)))
    (unless (bytes= (if (hash32-p root-hash)
                        (hash32-bytes root-hash)
                        (ensure-byte-vector root-hash))
                    (mpt-root-hash trie))
      (error "MPT range proof root hash mismatch"))
    (let* ((range (mpt-entry-range trie :start start :end end))
           (expected
             (if limit (subseq range 0 (min limit (length range))) range)))
      (unless (mpt-entry-pairs-equal-p entries expected)
        (error "MPT range proof does not contain the complete requested range"))
      t)))
