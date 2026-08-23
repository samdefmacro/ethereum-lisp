(in-package #:ethereum-lisp.trie)

;;;; Canonical trie node construction and node reference encoding.

(defun hash-table-entries (table)
  (let (entries)
    (maphash (lambda (key value)
               (push (cons (keybytes-to-nibbles (hex-to-bytes key)
                                                :terminator nil)
                           value)
                     entries))
             table)
    entries))

(defun strip-prefix (nibbles count)
  (subseq nibbles count))

(defun terminal-entry-p (entry)
  (zerop (length (car entry))))

(defun group-by-first-nibble (entries nibble)
  (loop for entry in entries
        for path = (car entry)
        when (and (> (length path) 0)
                  (= (aref path 0) nibble))
          collect (cons (subseq path 1) (cdr entry))))

(defun entries-common-prefix-length (entries)
  (if (endp entries)
      0
      (let ((prefix (caar entries)))
        (dolist (entry (rest entries) (length prefix))
          (let ((length (common-prefix-length prefix (car entry))))
            (when (< length (length prefix))
              (setf prefix (subseq prefix 0 length))))))))

(defun build-node (entries)
  (cond
    ((endp entries) nil)
    ((and (= (length entries) 1)
          (not (terminal-entry-p (first entries))))
     (let ((entry (first entries)))
       (make-leaf-node :path (concatenate 'vector
                                          (car entry)
                                          (vector +terminator-nibble+))
                       :value (cdr entry))))
    ((and (= (length entries) 1)
          (terminal-entry-p (first entries)))
     (make-leaf-node :path (vector +terminator-nibble+)
                     :value (cdar entries)))
    (t
     (let ((prefix-length (entries-common-prefix-length entries)))
       (if (> prefix-length 0)
           (make-extension-node
            :path (subseq (caar entries) 0 prefix-length)
            :child (build-node
                    (mapcar (lambda (entry)
                              (cons (strip-prefix (car entry) prefix-length)
                                    (cdr entry)))
                            entries)))
           (let ((children (make-array 16 :initial-element nil))
                 (value (make-byte-vector 0)))
             (dolist (entry entries)
               (when (terminal-entry-p entry)
                 (setf value (cdr entry))))
             (dotimes (index 16)
               (let ((group (group-by-first-nibble entries index)))
                 (when group
                   (setf (aref children index) (build-node group)))))
             (make-branch-node :children children :value value)))))))

(defun ordered-entries-common-prefix-length (entries)
  "Return the common prefix of already ordered nibble ENTRIES.

For a lexicographically ordered set the first and last key bound every key in
between, so comparing only those two paths avoids the repeated prefix scans of
BUILD-NODE."
  (if (endp entries)
      0
      (let ((last-entry (first entries)))
        (dolist (entry (rest entries))
          (setf last-entry entry))
        (common-prefix-length (caar entries) (car last-entry)))))

(defun ordered-entries-by-first-nibble (entries)
  "Group non-terminal ordered ENTRIES in one forward pass.

The returned list contains `(NIBBLE . ENTRIES)` groups in ascending nibble
order. Every grouped path has its leading nibble removed."
  (let ((groups '())
        (current-nibble nil)
        (current '()))
    (labels ((flush ()
               (when current
                 (push (cons current-nibble (nreverse current)) groups)
                 (setf current nil))))
      (dolist (entry entries)
        (let ((path (car entry)))
          (unless (zerop (length path))
            (let ((nibble (aref path 0)))
              (unless (eql nibble current-nibble)
                (flush)
                (setf current-nibble nibble))
              (push (cons (subseq path 1) (cdr entry)) current)))))
      (flush)
      (nreverse groups))))

(defun build-node-ordered (entries)
  "Build a canonical node from lexicographically ordered nibble ENTRIES.

Unlike BUILD-NODE this path never scans the same level sixteen times and never
performs copy-on-write insertion for every leaf. It is the flat-range/stack
builder used after SNAP has already proved strict key ordering."
  (cond
    ((endp entries) nil)
    ((endp (rest entries))
     (let ((entry (first entries)))
       (make-leaf-node
        :path (concatenate 'vector (car entry)
                           (vector +terminator-nibble+))
        :value (cdr entry))))
    (t
     (let ((prefix-length
             (ordered-entries-common-prefix-length entries)))
       (if (plusp prefix-length)
           (make-extension-node
            :path (subseq (caar entries) 0 prefix-length)
            :child
            (build-node-ordered
             (mapcar
              (lambda (entry)
                (cons (subseq (car entry) prefix-length) (cdr entry)))
              entries)))
           (let ((children (make-array 16 :initial-element nil))
                 (value (make-byte-vector 0)))
             (dolist (entry entries)
               (when (zerop (length (car entry)))
                 (setf value (cdr entry))))
             (dolist (group (ordered-entries-by-first-nibble entries))
               (setf (aref children (car group))
                     (build-node-ordered (cdr group))))
             (make-branch-node :children children :value value)))))))

(defvar *node-encoding-count* nil
  "When bound to a number, increment it for every trie node encoded on a cache
miss. Tests use this to guard the dirty-path complexity contract.")

(declaim (ftype (function (t) t) node-reference))

(defun trie-resolve-node (node)
  "Resolve one HASH-NODE, validating that its loader returns a concrete node."
  (if (hash-node-p node)
      (or (hash-node-resolved node)
          (let ((resolved (funcall (hash-node-resolver node)
                                   (hash-node-hash node))))
            (unless (or (leaf-node-p resolved)
                        (extension-node-p resolved)
                        (branch-node-p resolved))
              (error "Persisted trie resolver returned an invalid node"))
            (setf (hash-node-resolved node) resolved)))
      node))

(defun node-cache-value (node leaf-reader extension-reader branch-reader)
  (etypecase node
    (leaf-node (funcall leaf-reader node))
    (extension-node (funcall extension-reader node))
    (branch-node (funcall branch-reader node))))

(defun (setf node-cache-value)
    (value node leaf-writer extension-writer branch-writer)
  (etypecase node
    (leaf-node (funcall leaf-writer value node))
    (extension-node (funcall extension-writer value node))
    (branch-node (funcall branch-writer value node)))
  value)

(defun node-rlp-object (node)
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (or (node-cache-value node
                        #'leaf-node-cached-rlp-object
                        #'extension-node-cached-rlp-object
                        #'branch-node-cached-rlp-object)
      (setf (node-cache-value node
                              (lambda (value object)
                                (setf (leaf-node-cached-rlp-object object) value))
                              (lambda (value object)
                                (setf (extension-node-cached-rlp-object object) value))
                              (lambda (value object)
                                (setf (branch-node-cached-rlp-object object) value)))
            (etypecase node
              (leaf-node
               (make-rlp-list (hex-prefix-encode (leaf-node-path node))
                              (leaf-node-value node)))
              (extension-node
               (make-rlp-list (hex-prefix-encode (extension-node-path node))
                              (node-reference (extension-node-child node))))
              (branch-node
               (apply #'make-rlp-list
                      (append
                       (loop for child across (branch-node-children node)
                             collect (if child
                                         (node-reference child)
                                         (make-byte-vector 0)))
                       (list (branch-node-value node)))))))))

(defun encoded-node (node)
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (or (node-cache-value node
                        #'leaf-node-cached-encoded
                        #'extension-node-cached-encoded
                        #'branch-node-cached-encoded)
      (progn
        (when *node-encoding-count*
          (incf *node-encoding-count*))
        (setf (node-cache-value node
                                (lambda (value object)
                                  (setf (leaf-node-cached-encoded object) value))
                                (lambda (value object)
                                  (setf (extension-node-cached-encoded object) value))
                                (lambda (value object)
                                  (setf (branch-node-cached-encoded object) value)))
              (rlp-encode (node-rlp-object node))))))

(defun node-reference (node)
  (if (hash-node-p node)
      (hash-node-hash node)
      (or (node-cache-value node
                            #'leaf-node-cached-reference
                            #'extension-node-cached-reference
                            #'branch-node-cached-reference)
          (let* ((encoded (encoded-node node))
                 (reference (if (< (length encoded) 32)
                                (node-rlp-object node)
                                (keccak-256 encoded))))
            (setf (node-cache-value
                   node
                   (lambda (value object)
                     (setf (leaf-node-cached-reference object) value))
                   (lambda (value object)
                     (setf (extension-node-cached-reference object) value))
                   (lambda (value object)
                     (setf (branch-node-cached-reference object) value)))
                  reference)))))

(defun node-hash (node)
  (if (hash-node-p node)
      (hash-node-hash node)
      (or (node-cache-value node
                            #'leaf-node-cached-hash
                            #'extension-node-cached-hash
                            #'branch-node-cached-hash)
          (setf (node-cache-value
                 node
                 (lambda (value object)
                   (setf (leaf-node-cached-hash object) value))
                 (lambda (value object)
                   (setf (extension-node-cached-hash object) value))
                 (lambda (value object)
                   (setf (branch-node-cached-hash object) value)))
                (keccak-256 (encoded-node node))))))

(defun mpt-root-node (trie)
  (mpt-root trie))

(defun nibbles-prefix-p (prefix nibbles)
  (and (<= (length prefix) (length nibbles))
       (= (common-prefix-length prefix nibbles)
          (length prefix))))

(defun node-reference-hashed-p (node)
  (or (hash-node-p node)
      (>= (length (encoded-node node)) 32)))

(defun mpt-root-hash (trie)
  (let ((root (mpt-root-node trie)))
    (if root
        (node-hash root)
        (hash32-bytes +empty-trie-hash+))))

(defun mpt-root-hex (trie)
  (bytes-to-hex (mpt-root-hash trie)))
