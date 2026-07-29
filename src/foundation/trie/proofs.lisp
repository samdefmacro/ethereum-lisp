(in-package #:ethereum-lisp.trie)

;;;; Merkle Patricia Trie proof generation and verification.

(declaim (ftype (function (t t t) list) mpt-proof-for-node))

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

(defun mpt-proof-node-index (proof)
  "Index encoded proof nodes by Keccak hash.

The wire proof is a node set, not a positional path. Indexing makes verification
independent of order and permits unrelated nodes supplied by a peer."
  (let ((index (make-hash-table :test #'equal)))
    (dolist (encoded proof index)
      (let ((encoded (ensure-byte-vector encoded)))
        (setf (gethash (bytes-to-hex (keccak-256 encoded) :prefix nil) index)
              encoded)))))

(defun mpt-proof-index-node (reference proof-index)
  (gethash (bytes-to-hex reference :prefix nil) proof-index))

(defun mpt-proof-consume-referenced-node (reference proof-index)
  (cond
    ((and (byte-vector-p reference) (zerop (length reference)))
     (values nil nil))
    ((rlp-list-p reference)
     (values reference t))
    ((and (byte-vector-p reference) (= 32 (length reference)))
     (let ((encoded (mpt-proof-index-node reference proof-index)))
       (unless encoded
         (error "MPT proof is missing referenced node"))
       (values (rlp-decode-one encoded) t)))
    (t
     (error "MPT proof has malformed node reference"))))

(defun mpt-proof-node-value (node nibbles proof-index)
  (unless (rlp-list-p node)
    (error "MPT proof node must be an RLP list"))
  (let ((items (rlp-list-items node)))
    (case (length items)
      (17
       (if (zerop (length nibbles))
           (let ((value (nth 16 items)))
             (values value (plusp (length value))))
           (multiple-value-bind (child present-p)
               (mpt-proof-consume-referenced-node
                (nth (aref nibbles 0) items)
                proof-index)
             (if present-p
                 (mpt-proof-node-value child (subseq nibbles 1) proof-index)
                 (values nil nil)))))
      (2
       (multiple-value-bind (path leaf-p)
           (hex-prefix-decode (first items))
         (if leaf-p
             (if (bytes= path
                         (concatenate 'vector
                                      nibbles
                                      (vector +terminator-nibble+)))
                 (values (second items) t)
                 (values nil nil))
             (if (nibbles-prefix-p path nibbles)
                 (multiple-value-bind (child present-p)
                     (mpt-proof-consume-referenced-node
                      (second items)
                      proof-index)
                   (if present-p
                       (mpt-proof-node-value
                        child
                        (subseq nibbles (length path))
                        proof-index)
                       (values nil nil)))
                 (values nil nil)))))
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
       (let* ((proof-index (mpt-proof-node-index proof))
              (root-node (mpt-proof-index-node root-hash proof-index)))
         (unless root-node
           (error "MPT proof root hash mismatch"))
         (mpt-proof-node-value
          (rlp-decode-one root-node)
          (keybytes-to-nibbles key :terminator nil)
          proof-index))))))
