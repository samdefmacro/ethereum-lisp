(in-package #:ethereum-lisp.trie)

;;;; Durable trie nodes and resumable traversal.

(defstruct mpt-range-proof
  nodes)

(defun mpt-put-ordered-proven-range (trie entries)
  "Bulk insert ordered, non-empty, proven-absent ENTRIES into TRIE."
  (when entries
    (let ((normalized-entries
            (if (every
                 (lambda (entry)
                   (and (byte-vector-p (car entry))
                        (byte-vector-p (cdr entry))))
                 entries)
                entries
                (mapcar
                 (lambda (entry)
                   (cons (ensure-byte-vector (car entry))
                         (ensure-byte-vector (cdr entry))))
                 entries))))
      (dolist (entry normalized-entries)
        (when (zerop (length (cdr entry)))
          (error "An ordered proven MPT range contains an empty value")))
      (setf (mpt-root trie)
            (trie-merge-disjoint-nodes
             (mpt-root trie)
             (build-node-ordered-byte-entries normalized-entries)))))
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
dependencies are durable too. The secondary value mirrors each result as
`(PREFIX HASH REFERENCES)`, where REFERENCES contains every concrete hash in
that closed subtree without duplicating its encoded node values."
  (let ((start (ensure-byte-vector start))
        (end (ensure-byte-vector end)))
    (unless (and (= 32 (length start)) (= 32 (length end)))
      (error "MPT proved range bounds must contain 32 bytes"))
    (unless (and (integerp minimum-prefix-nibbles)
                 (<= 1 minimum-prefix-nibbles 64))
      (error "MPT proved range prefix depth must be between one and 64"))
    (let ((first (keybytes-to-nibbles start :terminator nil))
          (last (keybytes-to-nibbles end :terminator nil))
          (results '())
          (reference-groups '()))
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
           (dirty-subtree-references (node)
             (let ((references '()))
               (labels ((collect (current)
                          (when (and current
                                     (not (hash-node-p current))
                                     (trie-concrete-node-dirty-p current))
                            (dolist (child (trie-node-children current))
                              (collect child))
                            (push (node-hash current) references))))
                 (collect node))
               (nreverse references)))
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
                     (let ((prefix (copy-seq bucket))
                           (reference (node-hash node)))
                       (push (cons prefix reference) results)
                       ;; The second value lets SNAP preserve geth's hash-store
                       ;; invariant without one metadata record per good node:
                       ;; every hash below this maximal proved root has all
                       ;; descendants locally reconstructed. Callers may still
                       ;; withhold the group when account code/storage is not
                       ;; durable yet.
                       (push
                        (list prefix reference
                              (dirty-subtree-references node))
                        reference-groups))
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
      (values (nreverse results) (nreverse reference-groups)))))

(defun mpt-dirty-leaf-values (trie)
  "Return the value of every newly reconstructed leaf in TRIE.

A caller that must decide whether a reconstructed range is closed over external
references needs the leaf values before it can ask anything about them.  Clean
and unresolved subtrees are skipped, exactly as MPT-DIRTY-NODES skips them."
  (let ((values '())
        (seen (make-hash-table :test #'eq)))
    (labels ((visit (node)
               (when (and node (not (hash-node-p node))
                          (trie-concrete-node-dirty-p node)
                          (not (nth-value 1 (gethash node seen))))
                 (setf (gethash node seen) t)
                 (etypecase node
                   (leaf-node (push (leaf-node-value node) values))
                   (extension-node (visit (extension-node-child node)))
                   (branch-node
                    (let ((value (branch-node-value node)))
                      (when (and value (plusp (length value)))
                        (push value values)))
                    (loop for child across (branch-node-children node)
                          do (visit child)))))))
      (visit (mpt-root-node trie)))
    (nreverse values)))

(defun mpt-proved-range-closed-subtrees (trie start end leaf-closed-p)
  "Return the maximal reconstructed subtrees of TRIE that are closed.

START and END are inclusive secure keys.  A subtree qualifies when its whole
key range lies inside them, every one of its nodes was newly reconstructed by
this range, it is hash-addressed, and LEAF-CLOSED-P answers true for the value
of every leaf beneath it.  Each result is `(DEPTH REFERENCE REFERENCES)`, where
DEPTH is the nibble depth of the subtree's own key prefix and REFERENCES holds
every concrete hash inside it.

Unlike MPT-PROVED-RANGE-SUBTREES this has no minimum depth and does not stop at
a node that fails: it keeps descending and publishes the clean children of a
poisoned parent.  That is what geth's stack trie emits between two exclusions
\(eth/protocols/snap/sync.go:2453-2476 with gentrie.go:88-153 and :247-291 at
38271784c2b31926563806da9a2e023b88f5e7a8), and it is what keeps one account
with undelivered storage from withholding its whole bucket."
  (let ((start (ensure-byte-vector start))
        (end (ensure-byte-vector end)))
    (unless (and (= 32 (length start)) (= 32 (length end)))
      (error "MPT proved range bounds must contain 32 bytes"))
    (unless (functionp leaf-closed-p)
      (error "MPT proved range closure predicate must be a function"))
    (let ((first (keybytes-to-nibbles start :terminator nil))
          (last (keybytes-to-nibbles end :terminator nil))
          (analysis (make-hash-table :test #'eq))
          (results '()))
      (when (plusp (mpt-nibbles-compare first last))
        (error "MPT proved range bounds are reversed"))
      (labels
          ((analyze (node)
             "Return whether NODE's subtree is wholly dirty and wholly closed."
             (if (or (null node) (hash-node-p node)
                     (not (trie-concrete-node-dirty-p node)))
                 (values nil nil)
                 (multiple-value-bind (cached present-p) (gethash node analysis)
                   (if present-p
                       (values (car cached) (cdr cached))
                       (let ((dirty-p t)
                             (closed-p t))
                         (etypecase node
                           (leaf-node
                            (setf closed-p
                                  (and (funcall leaf-closed-p
                                                (leaf-node-value node))
                                       t)))
                           (extension-node
                            (multiple-value-bind (child-dirty-p child-closed-p)
                                (analyze (extension-node-child node))
                              (setf dirty-p child-dirty-p
                                    closed-p child-closed-p)))
                           (branch-node
                            (let ((value (branch-node-value node)))
                              (when (and value (plusp (length value)))
                                (setf closed-p
                                      (and (funcall leaf-closed-p value) t))))
                            (loop for child across (branch-node-children node)
                                  do (when child
                                       (multiple-value-bind
                                             (child-dirty-p child-closed-p)
                                           (analyze child)
                                         (unless child-dirty-p
                                           (setf dirty-p nil))
                                         (unless child-closed-p
                                           (setf closed-p nil)))))))
                         (setf (gethash node analysis) (cons dirty-p closed-p))
                         (values dirty-p closed-p))))))
           (coverage-prefix (node pointer-path)
             ;; A leaf's stored path can carry the hex-prefix terminator, so
             ;; its coverage would read as 65 nibbles and be rejected by the
             ;; bound below. A secure key is exactly 64 nibbles; anything past
             ;; that is the terminator and names no key space.
             (let ((full
                     (etypecase node
                       (leaf-node
                        (concatenate
                         'vector pointer-path (leaf-node-path node)))
                       (extension-node
                        (concatenate
                         'vector pointer-path (extension-node-path node)))
                       (branch-node pointer-path))))
               (if (> (length full) 64)
                   (subseq full 0 64)
                   full)))
           (coverage-inside-range-p (coverage)
             (let ((depth (length coverage)))
               (and
                (<= depth 64)
                (let ((low
                        (concatenate
                         'vector coverage (make-byte-vector (- 64 depth))))
                      (high
                        (concatenate
                         'vector coverage
                         (make-byte-vector (- 64 depth) :initial-element 15))))
                  (and (not (minusp (mpt-nibbles-compare low first)))
                       (not (plusp (mpt-nibbles-compare high last))))))))
           (subtree-references (node)
             (let ((references '()))
               (labels ((collect (current)
                          (when (and current
                                     (not (hash-node-p current))
                                     (trie-concrete-node-dirty-p current))
                            (dolist (child (trie-node-children current))
                              (collect child))
                            (push (node-hash current) references))))
                 (collect node))
               (nreverse references)))
           (visit (node pointer-path)
             (when (and node (not (hash-node-p node)))
               (multiple-value-bind (dirty-p closed-p) (analyze node)
                 (let ((coverage (coverage-prefix node pointer-path)))
                   (if (and dirty-p closed-p
                            (node-reference-hashed-p node)
                            (coverage-inside-range-p coverage))
                       (push (list (length coverage) (node-hash node)
                                   (subtree-references node))
                             results)
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
                                  'vector pointer-path
                                  (vector index))))))))))))))
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

(defun mpt-node-record (node)
  "Return NODE's content-addressed durable record as (HASH . ENCODED).

This is exactly the key and value MPT-POPULATE-DIRTY-BATCH writes for NODE, so
a caller that has applied that batch may keep the pair in a read cache."
  (cons (node-hash node) (encoded-node node)))

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

(defun %mpt-walk-extend (prefix path)
  "PREFIX followed by PATH, without PATH's terminator nibble, as octets."
  (let* ((count (if (has-terminator-p path) (1- (length path)) (length path)))
         (result (make-byte-vector (+ (length prefix) count))))
    (replace result prefix)
    (replace result path :start1 (length prefix) :end2 count)
    result))

(defun %mpt-walk-child-prefix (prefix nibble)
  (let ((result (make-byte-vector (1+ (length prefix)))))
    (replace result prefix)
    (setf (aref result (length prefix)) nibble)
    result))

(defun %mpt-walk-order (path bound depth)
  "Compare PATH, the nibbles below DEPTH, with BOUND from DEPTH on.

Returns :BELOW or :ABOVE at the first nibble that differs, and :PREFIX when
they agree over their common length."
  (let ((count (min (length path) (max 0 (- (length bound) depth)))))
    (dotimes (index count :prefix)
      (let ((a (aref path index))
            (b (aref bound (+ depth index))))
        (cond ((< a b) (return :below))
              ((> a b) (return :above)))))))

(defun mpt-map-entries-from (trie start function)
  "Call FUNCTION with KEY and VALUE for every entry of TRIE whose key is at or
after START, in ascending key order, until FUNCTION returns true.

Returns true when FUNCTION ended the walk. MPT-ENTRY-RANGE enumerates and
sorts the whole trie before it filters; this walk resolves only the nodes on
START's path and those of the entries it visits, so a caller that stops after
N entries pays for N entries whatever the size of TRIE. START is NIL (the first
key) or a key; keys are ordered as byte strings."
  (let ((bound (and start (keybytes-to-nibbles start :terminator nil))))
    (labels ((visit (node prefix bounded-p)
               ;; BOUNDED-P: PREFIX is a proper prefix of BOUND, so keys below
               ;; NODE can still fall on either side of it. Otherwise every
               ;; key below NODE is at or after BOUND.
               (when (hash-node-p node)
                 (setf node (trie-resolve-node node)))
               (etypecase node
                 (null nil)
                 (leaf-node
                  (let* ((path (leaf-node-path node))
                         (full (%mpt-walk-extend prefix path)))
                    (when (or (not bounded-p)
                              (ecase (%mpt-walk-order
                                      (subseq full (length prefix))
                                      bound (length prefix))
                                (:below nil)
                                (:above t)
                                (:prefix (>= (length full) (length bound)))))
                      (funcall function
                               (nibbles-to-keybytes full)
                               (copy-seq (leaf-node-value node))))))
                 (extension-node
                  (let* ((path (extension-node-path node))
                         (next (%mpt-walk-extend prefix path))
                         (child (extension-node-child node)))
                    (if (not bounded-p)
                        (visit child next nil)
                        (ecase (%mpt-walk-order path bound (length prefix))
                          (:below nil)
                          (:above (visit child next nil))
                          (:prefix
                           (visit child next
                                  (< (length next) (length bound))))))))
                 (branch-node
                  (let* ((depth (length prefix))
                         (first-child (if bounded-p (aref bound depth) 0)))
                    (or (and (not bounded-p)
                             (plusp (length (branch-node-value node)))
                             ;; The key PREFIX itself precedes every child.
                             (funcall function
                                      (nibbles-to-keybytes prefix)
                                      (copy-seq (branch-node-value node))))
                        (loop for index from first-child below 16
                              for child = (aref (branch-node-children node)
                                                index)
                              thereis
                              (and child
                                   (visit child
                                          (%mpt-walk-child-prefix prefix index)
                                          (and bounded-p
                                               (= index first-child)
                                               (< (1+ depth)
                                                  (length bound))))))))))))
      (and (visit (mpt-root trie) (make-byte-vector 0)
                  (and bound (plusp (length bound))))
           t))))

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
