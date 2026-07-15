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
