(in-package #:ethereum-lisp.trie)

(defstruct leaf-node path value)
(defstruct extension-node path child)
(defstruct branch-node children value)

(defstruct (mpt (:constructor make-mpt ()))
  (entries (make-hash-table :test #'equal)))

(defun trie-key-id (key)
  (bytes-to-hex (ensure-byte-vector key) :prefix nil))

(defun mpt-put (trie key value)
  (let ((value (ensure-byte-vector value)))
    (if (zerop (length value))
        (remhash (trie-key-id key) (mpt-entries trie))
        (setf (gethash (trie-key-id key) (mpt-entries trie)) value)))
  trie)

(defun mpt-delete (trie key)
  (remhash (trie-key-id key) (mpt-entries trie))
  trie)

(defun mpt-get (trie key)
  (gethash (trie-key-id key) (mpt-entries trie)))

(defun mpt-entry-pairs (trie)
  (let (entries)
    (maphash (lambda (key-id value)
               (push (cons key-id value) entries))
             (mpt-entries trie))
    (loop for entry in (sort entries #'string< :key #'car)
          collect (cons (hex-to-bytes (car entry))
                        (copy-seq (cdr entry))))))

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

(defun node-rlp-object (node)
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
                   collect (if child (node-reference child) (make-byte-vector 0)))
             (list (branch-node-value node)))))))

(defun encoded-node (node)
  (rlp-encode (node-rlp-object node)))

(defun node-reference (node)
  (let ((encoded (encoded-node node)))
    (if (< (length encoded) 32)
        (node-rlp-object node)
        (keccak-256 encoded))))

(defun mpt-root-node (trie)
  (build-node (hash-table-entries (mpt-entries trie))))

(defun nibbles-prefix-p (prefix nibbles)
  (and (<= (length prefix) (length nibbles))
       (= (common-prefix-length prefix nibbles)
          (length prefix))))

(defun node-reference-hashed-p (node)
  (let ((reference (node-reference node)))
    (and (byte-vector-p reference)
         (= 32 (length reference)))))

(defun mpt-proof-for-child (child nibbles)
  (and child
       (mpt-proof-for-node child nibbles (node-reference-hashed-p child))))

(defun mpt-proof-for-node (node nibbles include-current-p)
  (let ((proof (if include-current-p
                   (list (encoded-node node))
                   nil)))
    (append
     proof
     (etypecase node
       (leaf-node nil)
       (extension-node
        (let ((path (extension-node-path node)))
          (when (nibbles-prefix-p path nibbles)
            (mpt-proof-for-child
             (extension-node-child node)
             (subseq nibbles (length path))))))
       (branch-node
        (when (plusp (length nibbles))
          (mpt-proof-for-child
           (aref (branch-node-children node) (aref nibbles 0))
           (subseq nibbles 1))))))))

(defun mpt-get-proof (trie key)
  (let ((root (mpt-root-node trie)))
    (if root
        (mpt-proof-for-node
         root
         (keybytes-to-nibbles key :terminator nil)
         t)
        nil)))

(defun mpt-proof-consume-referenced-node (reference proof)
  (cond
    ((and (byte-vector-p reference) (zerop (length reference)))
     (values nil nil nil))
    ((rlp-list-p reference)
     (values reference proof t))
    ((and (byte-vector-p reference) (= 32 (length reference)))
     (unless proof
       (error "MPT proof is missing referenced node"))
     (let ((encoded (first proof)))
       (unless (bytes= reference (keccak-256 encoded))
         (error "MPT proof referenced node hash mismatch"))
       (values (rlp-decode-one encoded) (rest proof) t)))
    (t
     (error "MPT proof has malformed node reference"))))

(defun mpt-proof-node-value (node nibbles proof)
  (unless (rlp-list-p node)
    (error "MPT proof node must be an RLP list"))
  (let ((items (rlp-list-items node)))
    (case (length items)
      (17
       (if (zerop (length nibbles))
           (let ((value (nth 16 items)))
             (values value (plusp (length value)) proof))
           (multiple-value-bind (child next-proof present-p)
               (mpt-proof-consume-referenced-node
                (nth (aref nibbles 0) items)
                proof)
             (if present-p
                 (mpt-proof-node-value child (subseq nibbles 1) next-proof)
                 (values nil nil next-proof)))))
      (2
       (multiple-value-bind (path leaf-p)
           (hex-prefix-decode (first items))
         (if leaf-p
             (if (bytes= path
                         (concatenate 'vector
                                      nibbles
                                      (vector +terminator-nibble+)))
                 (values (second items) t proof)
                 (values nil nil proof))
             (if (nibbles-prefix-p path nibbles)
                 (multiple-value-bind (child next-proof present-p)
                     (mpt-proof-consume-referenced-node
                      (second items)
                      proof)
                   (if present-p
                       (mpt-proof-node-value
                        child
                        (subseq nibbles (length path))
                        next-proof)
                       (values nil nil next-proof)))
                 (values nil nil proof)))))
      (otherwise
       (error "MPT proof node has malformed item count: ~D" (length items))))))

(defun mpt-verify-proof (root-hash key proof)
  (let ((root-hash (if (hash32-p root-hash)
                       (hash32-bytes root-hash)
                       (ensure-byte-vector root-hash))))
    (cond
      ((and (null proof)
            (bytes= root-hash (hash32-bytes +empty-trie-hash+)))
       (values nil nil))
      ((null proof)
       (error "MPT proof is empty for non-empty root"))
      (t
       (let ((root-node (first proof)))
         (unless (bytes= root-hash (keccak-256 root-node))
           (error "MPT proof root hash mismatch"))
         (multiple-value-bind (value present-p remaining-proof)
             (mpt-proof-node-value
              (rlp-decode-one root-node)
              (keybytes-to-nibbles key :terminator nil)
              (rest proof))
           (when remaining-proof
             (error "MPT proof has unconsumed nodes"))
           (values value present-p)))))))

(defun mpt-root-hash (trie)
  (let ((root (mpt-root-node trie)))
    (if root
        (keccak-256 (encoded-node root))
        (hash32-bytes +empty-trie-hash+))))

(defun mpt-root-hex (trie)
  (bytes-to-hex (mpt-root-hash trie)))
