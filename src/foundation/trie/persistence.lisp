(in-package #:ethereum-lisp.trie)

;;;; Durable trie nodes and resumable traversal.

(defstruct mpt-range-proof
  entries)

(defun trie-node-children (node)
  (etypecase node
    (hash-node nil)
    (leaf-node nil)
    (extension-node (list (extension-node-child node)))
    (branch-node
     (loop for child across (branch-node-children node)
           when child collect child))))

(defun trie-concrete-node-dirty-p (node)
  (etypecase node
    (leaf-node (leaf-node-dirty-p node))
    (extension-node (extension-node-dirty-p node))
    (branch-node (branch-node-dirty-p node))))

(defun (setf trie-concrete-node-dirty-p) (value node)
  (etypecase node
    (leaf-node (setf (leaf-node-dirty-p node) value))
    (extension-node (setf (extension-node-dirty-p node) value))
    (branch-node (setf (branch-node-dirty-p node) value)))
  value)

(defun mpt-dirty-nodes (trie)
  "Return TRIE's newly allocated nodes, children before parents.

Clean decoded nodes and unresolved HASH-NODE subtrees are already durable and
are not traversed. Thus work is proportional to changed paths rather than the
retained trie."
  (let ((seen (make-hash-table :test #'equal))
        (dirty nil))
    (labels ((visit (node)
               (when (and node (not (hash-node-p node))
                          (trie-concrete-node-dirty-p node))
                 (let* ((hash (node-hash node))
                        (key (bytes-to-hex hash :prefix nil)))
                   (unless (gethash key seen)
                     (setf (gethash key seen) t)
                     (dolist (child (trie-node-children node))
                       (visit child))
                     (push node dirty))))))
      (visit (mpt-root-node trie)))
    (nreverse dirty)))

(defun mpt-populate-dirty-batch (batch trie &optional database)
  "Add TRIE's dirty nodes to BATCH and return the exact nodes added.

The caller marks the returned nodes clean only after the encompassing database
batch succeeds, so an injected write failure cannot lose pending paths.  When
DATABASE is supplied, an existing content-addressed record is hash-collision
checked before the batch is allowed to replace it."
  (let ((nodes (mpt-dirty-nodes trie)))
    (dolist (node nodes)
      (let ((hash (node-hash node))
            (encoded (encoded-node node)))
        (when database
          (multiple-value-bind (existing present-p)
              (kv-get-chain-record database :trie-node hash)
            (when (and present-p (not (bytes= existing encoded)))
              (error "Persisted trie node collides with content hash ~A"
                     (bytes-to-hex hash)))))
        (kv-batch-put-chain-record batch :trie-node hash encoded)))
    nodes))

(defun mpt-mark-nodes-persisted (nodes)
  (dolist (node nodes)
    (setf (trie-concrete-node-dirty-p node) nil))
  nodes)

(defun mpt-persist (database trie)
  "Atomically persist newly allocated trie paths and return the root.

For a fresh in-memory trie every node is dirty, preserving the historical
behaviour. For a trie opened from a persisted root, untouched hash subtrees are
never resolved or rewritten."
  (let* ((batch (make-kv-write-batch))
         (nodes (mpt-populate-dirty-batch batch trie database))
         (root (mpt-root-node trie)))
    (kv-apply-batch database batch)
    (mpt-mark-nodes-persisted nodes)
    (if root
        (make-hash32 (node-hash root))
        +empty-trie-hash+)))

(defun trie-node-store-get (database hash)
  "Return an encoded persisted node and a presence flag."
  (kv-get-chain-record
   database :trie-node
   (if (hash32-p hash) (hash32-bytes hash) (ensure-byte-vector hash))))

(declaim (ftype (function (t t) t) persisted-trie-node-from-rlp-object))

(defun persisted-trie-child-node (reference resolver)
  (cond
    ((rlp-list-p reference)
     (persisted-trie-node-from-rlp-object reference resolver))
    ((and (byte-vector-p reference) (zerop (length reference))) nil)
    ((and (byte-vector-p reference) (= 32 (length reference)))
     (make-hash-node :hash (copy-seq reference) :resolver resolver))
    (t
     (error "Persisted trie contains a malformed child reference"))))

(defun persisted-trie-node-from-rlp-object (object resolver)
  (unless (rlp-list-p object)
    (error "Persisted trie node must be an RLP list"))
  (let ((items (rlp-list-items object)))
    (case (length items)
      (17
       (let ((children (make-array 16 :initial-element nil))
             (value (nth 16 items)))
         (unless (byte-vector-p value)
           (error "Persisted branch value must be bytes"))
         (dotimes (index 16)
           (setf (aref children index)
                 (persisted-trie-child-node (nth index items) resolver)))
         (make-branch-node
          :children children :value value :dirty-p nil
          :cached-rlp-object object :cached-encoded (rlp-encode object))))
      (2
       (let ((path-field (first items)))
         (unless (byte-vector-p path-field)
           (error "Persisted compact trie path must be bytes"))
         (multiple-value-bind (path leaf-p) (hex-prefix-decode path-field)
           (if leaf-p
               (let ((value (second items)))
                 (unless (byte-vector-p value)
                   (error "Persisted trie leaf value must be bytes"))
                 (make-leaf-node
                  :path path :value value :dirty-p nil
                  :cached-rlp-object object
                  :cached-encoded (rlp-encode object)))
               (make-extension-node
                :path path
                :child (persisted-trie-child-node (second items) resolver)
                :dirty-p nil
                :cached-rlp-object object
                :cached-encoded (rlp-encode object))))))
      (otherwise
       (error "Persisted trie node has malformed item count: ~D"
              (length items))))))

(defun make-persisted-mpt (root-hash encoded-node-resolver)
  "Open ROOT-HASH without loading a node.

ENCODED-NODE-RESOLVER receives a 32-byte hash and returns encoded bytes plus a
presence flag. Each node is hash-checked when, and only when, its path is first
traversed."
  (unless (functionp encoded-node-resolver)
    (error "Persisted trie node resolver must be a function"))
  (let* ((root-hash
           (if (hash32-p root-hash)
               (hash32-bytes root-hash)
               (ensure-byte-vector root-hash)))
         (trie (make-mpt)))
    (unless (= 32 (length root-hash))
      (error "Persisted trie root must contain 32 bytes"))
    (labels ((resolve (hash)
               (multiple-value-bind (encoded present-p)
                   (funcall encoded-node-resolver hash)
                 (unless present-p
                   (error "Persisted trie node ~A is missing"
                          (bytes-to-hex hash)))
                 (let ((encoded (ensure-byte-vector encoded)))
                   (unless (bytes= hash (keccak-256 encoded))
                     (error "Persisted trie node ~A does not hash to its key"
                            (bytes-to-hex hash)))
                   (persisted-trie-node-from-rlp-object
                    (rlp-decode-one encoded) #'resolve)))))
      (setf (mpt-lazy-p trie) t
            (mpt-root trie)
            (unless (bytes= root-hash (hash32-bytes +empty-trie-hash+))
              (make-hash-node
               :hash (copy-seq root-hash) :resolver #'resolve))))
    trie))

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
