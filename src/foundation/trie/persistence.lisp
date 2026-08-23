(in-package #:ethereum-lisp.trie)

;;;; Durable trie nodes and resumable traversal.

(defstruct mpt-range-proof
  nodes)

(defun mpt-put-ordered-proven-range (trie entries)
  "Bulk insert ordered, non-empty, proven-absent ENTRIES into TRIE."
  (when entries
    (let ((nibble-entries
            (mapcar
             (lambda (entry)
               (let ((value (ensure-byte-vector (cdr entry))))
                 (when (zerop (length value))
                   (error "An ordered proven MPT range contains an empty value"))
                 (cons
                  (keybytes-to-nibbles
                   (ensure-byte-vector (car entry)) :terminator nil)
                  value)))
             entries)))
      (setf (mpt-root trie)
            (trie-merge-disjoint-nodes
             (mpt-root trie) (build-node-ordered nibble-entries)))))
  trie)

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
  (let ((seen (make-hash-table :test #'equalp))
        (dirty nil))
    (labels ((visit (node)
               (when (and node (not (hash-node-p node))
                          (trie-concrete-node-dirty-p node))
                 (let ((hash (node-hash node)))
                   ;; EQUALP hashes octet vectors by content. Using the hash
                   ;; bytes directly avoids allocating a 64-character hex
                   ;; string for every generated SNAP trie node.
                   (unless (nth-value 1 (gethash hash seen))
                     (setf (gethash hash seen) t)
                     (dolist (child (trie-node-children node))
                       (visit child))
                     (push node dirty))))))
      (visit (mpt-root-node trie)))
    (nreverse dirty)))

(defun mpt-dirty-node-records (trie)
  "Return the content-addressed records for TRIE's newly allocated nodes.

The result retains encoded bytes rather than the concrete node graph, allowing
a verified range worker to hand a compact immutable result to a separate
durability coordinator. No node is marked clean by this observational call."
  (mapcar (lambda (node)
            (cons (node-hash node) (encoded-node node)))
          (mpt-dirty-nodes trie)))

(defun mpt-proved-range-subtrees (trie start end minimum-prefix-nibbles)
  "Return maximal hashed subtrees wholly reconstructed by a proved range.

START and END are inclusive secure keys.  A result is `(PREFIX . HASH)`, where
PREFIX is the coarse key-space bucket used to establish that the whole subtree
lies inside the verified interval.  Clean or unresolved proof-edge nodes are
never returned: every descendant of a result must be newly reconstructed and
therefore present in `MPT-DIRTY-NODE-RECORDS`.  Callers may durably publish the
hash as a reusable completion proof only after the range's external account
dependencies are durable too."
  (let ((start (ensure-byte-vector start))
        (end (ensure-byte-vector end)))
    (unless (and (= 32 (length start)) (= 32 (length end)))
      (error "MPT proved range bounds must contain 32 bytes"))
    (unless (and (integerp minimum-prefix-nibbles)
                 (<= 1 minimum-prefix-nibbles 64))
      (error "MPT proved range prefix depth must be between one and 64"))
    (let ((first (keybytes-to-nibbles start :terminator nil))
          (last (keybytes-to-nibbles end :terminator nil))
          (results '()))
      (when (plusp (mpt-nibbles-compare first last))
        (error "MPT proved range bounds are reversed"))
      (labels
          ((dirty-subtree-p (node)
             (and node
                  (not (hash-node-p node))
                  (trie-concrete-node-dirty-p node)
                  (etypecase node
                    (leaf-node t)
                    (extension-node
                     (dirty-subtree-p (extension-node-child node)))
                    (branch-node
                     (loop for child across (branch-node-children node)
                           always (or (null child)
                                      (dirty-subtree-p child)))))))
           (coverage-prefix (node pointer-path)
             (etypecase node
               (leaf-node
                (concatenate 'vector pointer-path (leaf-node-path node)))
               (extension-node
                (concatenate 'vector pointer-path (extension-node-path node)))
               (branch-node pointer-path)))
           (bucket-inside-range-p (coverage)
             (when (>= (length coverage) minimum-prefix-nibbles)
               (let* ((bucket
                        (subseq coverage 0 minimum-prefix-nibbles))
                      (low
                        (concatenate
                         'vector bucket
                         (make-byte-vector
                          (- 64 minimum-prefix-nibbles))))
                      (high
                        (concatenate
                         'vector bucket
                         (make-byte-vector
                          (- 64 minimum-prefix-nibbles)
                          :initial-element 15))))
                 (when (and (not (minusp (mpt-nibbles-compare low first)))
                            (not (plusp (mpt-nibbles-compare high last))))
                   bucket))))
           (visit (node pointer-path)
             (when (and node (not (hash-node-p node)))
               (let* ((coverage (coverage-prefix node pointer-path))
                      (bucket (bucket-inside-range-p coverage)))
                 (if (and bucket
                          (>= (length pointer-path) minimum-prefix-nibbles)
                          (node-reference-hashed-p node)
                          (dirty-subtree-p node))
                     (push (cons (copy-seq bucket) (node-hash node)) results)
                     (etypecase node
                       (leaf-node nil)
                       (extension-node
                        (visit
                         (extension-node-child node)
                         (concatenate
                          'vector pointer-path (extension-node-path node))))
                       (branch-node
                        (dotimes (index 16)
                          (let ((child
                                  (aref (branch-node-children node) index)))
                            (when child
                              (visit
                               child
                               (concatenate
                                'vector pointer-path (vector index)))))))))))))
        (visit (mpt-root-node trie) (make-byte-vector 0)))
      (nreverse results))))

(defun mpt-hashed-subtrees-with-prefix-at-depth
    (trie minimum-prefix-nibbles)
  "Resolve only the shallow trie spine and return prefixed subtree roots.

Each result is `(PREFIX . HASH)`.  HASH is the first content-addressed
reference encountered at or below MINIMUM-PREFIX-NIBBLES and PREFIX is its
coarse bucket at exactly that depth.  Descendants are deliberately not
resolved.  This is suitable only when a separate trust proof already
establishes that every descendant and external dependency is durable."
  (unless (and (integerp minimum-prefix-nibbles)
               (<= 1 minimum-prefix-nibbles 64))
    (error "MPT subtree prefix depth must be between one and 64"))
  (let ((results '()))
    (labels
        ((visit (node pointer-path)
           (when node
             (cond
               ((and (>= (length pointer-path) minimum-prefix-nibbles)
                     (or (hash-node-p node)
                         (node-reference-hashed-p node)))
                (push
                 (cons
                  (copy-seq
                   (subseq pointer-path 0 minimum-prefix-nibbles))
                  (node-hash node))
                 results))
               ((hash-node-p node)
                (visit (trie-resolve-node node) pointer-path))
               ((leaf-node-p node) nil)
               ((extension-node-p node)
                (visit
                 (extension-node-child node)
                 (concatenate
                  'vector pointer-path (extension-node-path node))))
               ((branch-node-p node)
                (dotimes (index 16)
                  (let ((child (aref (branch-node-children node) index)))
                    (when child
                      (visit
                       child
                       (concatenate
                        'vector pointer-path (vector index)))))))
               (t (error "MPT contains an invalid node type"))))))
      (visit (mpt-root-node trie) (make-byte-vector 0)))
    (nreverse results)))

(defun mpt-hashed-subtrees-at-prefix-depth (trie minimum-prefix-nibbles)
  "Resolve only the shallow trie spine and return hashed subtree roots.

This compatibility projection omits the coarse prefixes returned by
MPT-HASHED-SUBTREES-WITH-PREFIX-AT-DEPTH."
  (mapcar
   #'cdr
   (mpt-hashed-subtrees-with-prefix-at-depth
    trie minimum-prefix-nibbles)))

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

(defun mpt-node-at-nibbles (node path)
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (cond
    ((null node) (values nil nil))
    ((zerop (length path)) (values (encoded-node node) t))
    ((leaf-node-p node) (values nil nil))
    ((extension-node-p node)
     (let ((prefix (extension-node-path node)))
       (if (nibbles-prefix-p prefix path)
           (mpt-node-at-nibbles
            (extension-node-child node) (subseq path (length prefix)))
           (values nil nil))))
    ((branch-node-p node)
     (mpt-node-at-nibbles
      (aref (branch-node-children node) (aref path 0))
      (subseq path 1)))
    (t (error "MPT contains an invalid node type"))))

(defun mpt-get-node-by-compact-path (trie compact-path)
  "Return the encoded node at snap's compact hexary COMPACT-PATH.

The path uses the same hex-prefix representation as Ethereum trie short nodes,
but must carry the extension (non-leaf) flag.  Returns encoded bytes plus a
presence flag and resolves only hashes on the requested path."
  (let ((compact-path (ensure-byte-vector compact-path)))
    (when (zerop (length compact-path))
      (error "Compact trie path must contain its hex-prefix flag byte"))
    (multiple-value-bind (path leaf-p) (hex-prefix-decode compact-path)
      (when leaf-p
        (error "Compact trie node path must not carry the leaf flag"))
      (mpt-node-at-nibbles (mpt-root-node trie) path))))

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
  "Return a bounded range and its compact Merkle boundary proof.

Only nodes on the requested origin and returned right edge are included.  This
is the snap/1 proof shape: interior leaves are supplied by the range itself and
unrelated subtries remain authenticated by their hash references."
  (let* ((range (mpt-entry-range trie :start start :end end))
         (bounded (if limit (subseq range 0 (min limit (length range))) range))
         (origin (or start (and bounded (caar bounded))))
         (last-key (and bounded (car (car (last bounded)))))
         (seen (make-hash-table :test #'equal))
         (nodes '()))
    (labels ((add-proof (key)
               (when key
                 (dolist (node (mpt-get-proof trie key))
                   (let ((id (bytes-to-hex (keccak-256 node) :prefix nil)))
                     (unless (gethash id seen)
                       (setf (gethash id seen) t)
                       (push node nodes)))))))
      (add-proof origin)
      (unless (and origin last-key (bytes= origin last-key))
        (add-proof last-key)))
    (values bounded
            (make-mpt-range-proof :nodes (nreverse nodes)))))

(defun mpt-nibbles-compare (left right)
  (let ((limit (min (length left) (length right))))
    (dotimes (index limit)
      (let ((a (aref left index)) (b (aref right index)))
        (when (/= a b)
          (return-from mpt-nibbles-compare (if (< a b) -1 1)))))
    (cond ((< (length left) (length right)) -1)
          ((> (length left) (length right)) 1)
          (t 0))))

(defun mpt-range-prefix-relation (prefix first last key-length)
  "Classify PREFIX's fixed-width keyspace as :INSIDE, :OUTSIDE, or :OVERLAP."
  (when (> (length prefix) key-length)
    (error "MPT range proof contains a path longer than its keys"))
  (let* ((missing (- key-length (length prefix)))
         (lower (concatenate 'vector prefix (make-byte-vector missing)))
         (upper (concatenate 'vector prefix
                             (make-byte-vector missing :initial-element 15))))
    (cond
      ((or (minusp (mpt-nibbles-compare upper first))
           (plusp (mpt-nibbles-compare lower last)))
       :outside)
      ((and (not (minusp (mpt-nibbles-compare lower first)))
            (not (plusp (mpt-nibbles-compare upper last))))
       :inside)
      (t :overlap))))

(defun mpt-trim-range-node (node prefix first last key-length)
  "Remove the inclusive FIRST..LAST interval without resolving interior hashes."
  (when (null node)
    (return-from mpt-trim-range-node nil))
  (case (mpt-range-prefix-relation prefix first last key-length)
    (:inside (return-from mpt-trim-range-node nil))
    (:outside (return-from mpt-trim-range-node node)))
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (etypecase node
    (leaf-node
     (let* ((path (leaf-node-path node))
            (terminator-p (and (plusp (length path))
                               (= +terminator-nibble+
                                  (aref path (1- (length path))))))
            (key (concatenate 'vector prefix
                              (if terminator-p
                                  (subseq path 0 (1- (length path)))
                                  path))))
       (unless (and terminator-p (= (length key) key-length))
         (error "MPT range proof contains a malformed leaf path"))
       (if (and (not (minusp (mpt-nibbles-compare key first)))
                (not (plusp (mpt-nibbles-compare key last))))
           nil
           node)))
    (extension-node
     (let* ((path (extension-node-path node))
            (child-prefix (concatenate 'vector prefix path))
            (child
              (mpt-trim-range-node
               (extension-node-child node) child-prefix
               first last key-length)))
       (and child (make-extension-node :path path :child child))))
    (branch-node
     (let ((children (copy-seq (branch-node-children node)))
           (value (branch-node-value node)))
       (when (and (= (length prefix) key-length)
                  (not (minusp (mpt-nibbles-compare prefix first)))
                  (not (plusp (mpt-nibbles-compare prefix last))))
         (setf value (make-byte-vector 0)))
       (dotimes (index 16)
         (setf (aref children index)
               (mpt-trim-range-node
                (aref children index)
                (concatenate 'vector prefix (vector index))
                first last key-length)))
       (make-branch-node :children children :value value)))))

(defun mpt-prefix-half-open-relation (prefix first end key-length)
  (when (> (length prefix) key-length)
    (error "MPT range proof contains a path longer than its keys"))
  (let* ((missing (- key-length (length prefix)))
         (lower (concatenate 'vector prefix (make-byte-vector missing)))
         (upper (concatenate 'vector prefix
                             (make-byte-vector missing :initial-element 15))))
    (cond
      ((or (minusp (mpt-nibbles-compare upper first))
           (and end
                (not (minusp (mpt-nibbles-compare lower end)))))
       :outside)
      ((and (not (minusp (mpt-nibbles-compare lower first)))
            (or (null end)
                (minusp (mpt-nibbles-compare upper end))))
       :inside)
      (t :overlap))))

(defun mpt-node-has-key-in-half-open-range-p
    (node prefix first end key-length)
  "Use an edge proof to decide whether NODE contains a key in [FIRST, END)."
  (when (null node)
    (return-from mpt-node-has-key-in-half-open-range-p nil))
  (case (mpt-prefix-half-open-relation prefix first end key-length)
    (:inside (return-from mpt-node-has-key-in-half-open-range-p t))
    (:outside (return-from mpt-node-has-key-in-half-open-range-p nil)))
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (etypecase node
    (leaf-node
     (let* ((path (leaf-node-path node))
            (terminator-p (and (plusp (length path))
                               (= +terminator-nibble+
                                  (aref path (1- (length path))))))
            (key (concatenate 'vector prefix
                              (if terminator-p
                                  (subseq path 0 (1- (length path)))
                                  path))))
       (unless (and terminator-p (= (length key) key-length))
         (error "MPT range proof contains a malformed leaf path"))
       (and (not (minusp (mpt-nibbles-compare key first)))
            (or (null end) (minusp (mpt-nibbles-compare key end))))))
    (extension-node
     (mpt-node-has-key-in-half-open-range-p
      (extension-node-child node)
      (concatenate 'vector prefix (extension-node-path node))
      first end key-length))
    (branch-node
     (or (and (plusp (length (branch-node-value node)))
              (= (length prefix) key-length)
              (not (minusp (mpt-nibbles-compare prefix first)))
              (or (null end) (minusp (mpt-nibbles-compare prefix end))))
         (loop for index below 16
               thereis
               (mpt-node-has-key-in-half-open-range-p
                (aref (branch-node-children node) index)
                (concatenate 'vector prefix (vector index))
                first end key-length))))))

(defun mpt-range-proof-nodes-list (proof)
  (cond ((mpt-range-proof-p proof) (mpt-range-proof-nodes proof))
        ((listp proof) proof)
        (t (error "MPT range proof has an invalid representation"))))

(defun mpt-range-entries-valid-p (entries start end limit)
  (when (and limit (> (length entries) limit))
    (error "MPT range contains more entries than its requested limit"))
  (let ((previous nil))
    (dolist (entry entries)
      (unless (and (consp entry)
                   (byte-vector-p (car entry))
                   (byte-vector-p (cdr entry))
                   (plusp (length (cdr entry))))
        (error "MPT range contains a malformed or deleted entry"))
      (when (and previous
                 (not
                  (ethereum-lisp.validation:byte-vector-lexicographic<
                   previous (car entry))))
        (error "MPT range is not monotonically increasing"))
      (when (and start
                 (ethereum-lisp.validation:byte-vector-lexicographic<
                  (car entry) start))
        (error "MPT range contains an entry before its requested origin"))
      (when (and end
                 (not
                  (ethereum-lisp.validation:byte-vector-lexicographic<
                   (car entry) end)))
        (error "MPT range contains an entry at or beyond its exclusive limit"))
      (setf previous (car entry))))
  t)

(defun mpt-verify-range-proof
    (root-hash entries proof &key start end limit)
  "Verify an ordered, gap-free chunk against ROOT-HASH and compact edge nodes.

PROOF may be the MPT-RANGE-PROOF returned by MPT-GET-RANGE-PROOF or the raw
snap/1 list of encoded edge nodes. Missing or altered interior leaves rebuild
a different root. A proofless response is accepted only when ENTRIES alone
reconstruct the entire trie. The second return value is the verified
reconstructed trie for a non-empty range, allowing its new nodes to be
persisted without rebuilding the same page."
  (mpt-range-entries-valid-p entries start end limit)
  (let* ((root-hash (if (hash32-p root-hash)
                        (hash32-bytes root-hash)
                        (ensure-byte-vector root-hash)))
         (nodes (mpt-range-proof-nodes-list proof)))
    (unless (= 32 (length root-hash))
      (error "MPT range proof root must contain 32 bytes"))
    (cond
      ((null nodes)
        (let ((trie (make-mpt)))
          (setf (mpt-lazy-p trie) t)
          (mpt-put-ordered-proven-range trie entries)
          (let ((reconstructed-root (mpt-root-hash trie)))
            (unless (bytes= root-hash reconstructed-root)
              (error
               "MPT proofless range of ~D entries reconstructs ~A, not ~A"
               (length entries) (bytes-to-hex reconstructed-root)
               (bytes-to-hex root-hash))))
          (values t trie)))
      ((null entries)
       (unless start
         (error "An empty compact MPT range requires an explicit origin"))
       (let ((proof-index (mpt-proof-node-index nodes)))
         (flet ((resolver (hash)
                  (let ((encoded (mpt-proof-index-node hash proof-index)))
                    (values encoded (not (null encoded))))))
           (let* ((trie (make-persisted-mpt root-hash #'resolver))
                  (first (keybytes-to-nibbles start :terminator nil))
                  (end-nibbles
                    (and end (keybytes-to-nibbles end :terminator nil))))
             (when (mpt-node-has-key-in-half-open-range-p
                    (mpt-root trie) (make-byte-vector 0)
                    first end-nibbles (length first))
               (error "Empty MPT range omits an available entry")))))
       (values t nil))
      (t
       (let* ((first-key (or start (caar entries)))
              (last-key (caar (last entries)))
              (proof-index (mpt-proof-node-index nodes)))
         (unless (= (length first-key) (length last-key))
           (error "MPT range boundary keys have different lengths"))
         (flet ((resolver (hash)
                  (let ((encoded (mpt-proof-index-node hash proof-index)))
                    (values encoded (not (null encoded))))))
           (let* ((trie (make-persisted-mpt root-hash #'resolver))
                  (first (keybytes-to-nibbles first-key :terminator nil))
                  (last (keybytes-to-nibbles last-key :terminator nil)))
             (when (plusp (mpt-nibbles-compare first last))
               (error "MPT range edge keys are reversed"))
             (setf (mpt-root trie)
                   (mpt-trim-range-node
                    (mpt-root trie) (make-byte-vector 0)
                    first last (length first)))
             ;; Trimming removed this verified, gap-free interval. Build its
             ;; flat ordered leaves once and merge the completed graph into
             ;; the exposed edge proof instead of copy-on-write inserting
             ;; every key through the same ancestors.
             (mpt-put-ordered-proven-range trie entries)
             (unless (bytes= root-hash (mpt-root-hash trie))
               (error "MPT compact range proof root hash mismatch"))
             (values t trie))))))))
