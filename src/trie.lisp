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

(defun mpt-root-hash (trie)
  (let ((root (mpt-root-node trie)))
    (if root
        (keccak-256 (encoded-node root))
        (hash32-bytes +empty-trie-hash+))))

(defun mpt-root-hex (trie)
  (bytes-to-hex (mpt-root-hash trie)))
