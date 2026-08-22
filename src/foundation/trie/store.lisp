(in-package #:ethereum-lisp.trie)

;;;; Mutable in-memory Merkle Patricia Trie entry store.

(declaim (ftype (function (t) t) trie-resolve-node)
         (ftype (function (t t) t) mpt-get))

(defun trie-key-id (key)
  (bytes-to-hex (ensure-byte-vector key) :prefix nil))

(defun trie-terminal-path-p (path)
  (and (= 1 (length path))
       (= +terminator-nibble+ (aref path 0))))

(defun trie-path-with-terminator (key)
  (concatenate 'vector
               (keybytes-to-nibbles key :terminator nil)
               (vector +terminator-nibble+)))

(defun trie-copy-branch-children (branch)
  (copy-seq (branch-node-children branch)))

(defun trie-branch-with-entry (branch path value)
  (if (trie-terminal-path-p path)
      (make-branch-node :children (trie-copy-branch-children branch)
                        :value value)
      (let* ((children (trie-copy-branch-children branch))
             (index (aref path 0)))
        (setf (aref children index)
              (make-leaf-node :path (subseq path 1) :value value))
        (make-branch-node :children children
                          :value (branch-node-value branch)))))

(defun trie-split-leaf (leaf path value)
  (let* ((old-path (leaf-node-path leaf))
         (prefix-length (common-prefix-length old-path path))
         (branch (make-branch-node
                  :children (make-array 16 :initial-element nil)
                  :value (make-byte-vector 0))))
    (setf branch
          (trie-branch-with-entry branch
                                  (subseq old-path prefix-length)
                                  (leaf-node-value leaf)))
    (setf branch
          (trie-branch-with-entry branch
                                  (subseq path prefix-length)
                                  value))
    (if (plusp prefix-length)
        (make-extension-node :path (subseq path 0 prefix-length)
                             :child branch)
        branch)))

(defun trie-split-extension (extension path value prefix-length)
  (let* ((old-path (extension-node-path extension))
         (old-suffix (subseq old-path prefix-length))
         (children (make-array 16 :initial-element nil))
         (old-index (aref old-suffix 0))
         (old-child (if (= 1 (length old-suffix))
                        (extension-node-child extension)
                        (make-extension-node
                         :path (subseq old-suffix 1)
                         :child (extension-node-child extension))))
         (branch (make-branch-node :children children
                                   :value (make-byte-vector 0))))
    (setf (aref children old-index) old-child)
    (setf branch
          (trie-branch-with-entry branch
                                  (subseq path prefix-length)
                                  value))
    (if (plusp prefix-length)
        (make-extension-node :path (subseq path 0 prefix-length)
                             :child branch)
        branch)))

(defun trie-put-node (node path value)
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (etypecase node
    (null
     (make-leaf-node :path path :value value))
    (leaf-node
     (if (bytes= (leaf-node-path node) path)
         (make-leaf-node :path path :value value)
         (trie-split-leaf node path value)))
    (extension-node
     (let* ((node-path (extension-node-path node))
            (prefix-length (common-prefix-length node-path path)))
       (if (= prefix-length (length node-path))
           (make-extension-node
            :path node-path
            :child (trie-put-node (extension-node-child node)
                                  (subseq path prefix-length)
                                  value))
           (trie-split-extension node path value prefix-length))))
    (branch-node
     (if (trie-terminal-path-p path)
         (make-branch-node :children (trie-copy-branch-children node)
                           :value value)
         (let* ((children (trie-copy-branch-children node))
                (index (aref path 0)))
           (setf (aref children index)
                 (trie-put-node (aref children index)
                                (subseq path 1)
                                value))
           (make-branch-node :children children
                             :value (branch-node-value node)))))))

(defun trie-prepend-path (nibble node)
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (etypecase node
    (leaf-node
     (make-leaf-node
      :path (concatenate 'vector (vector nibble) (leaf-node-path node))
      :value (leaf-node-value node)))
    (extension-node
     (make-extension-node
      :path (concatenate 'vector (vector nibble) (extension-node-path node))
      :child (extension-node-child node)))
    (branch-node
     (make-extension-node :path (vector nibble) :child node))))

(defun trie-normalize-extension (path child)
  (when (hash-node-p child)
    (setf child (trie-resolve-node child)))
  (etypecase child
    (null nil)
    (leaf-node
     (make-leaf-node
      :path (concatenate 'vector path (leaf-node-path child))
      :value (leaf-node-value child)))
    (extension-node
     (make-extension-node
      :path (concatenate 'vector path (extension-node-path child))
      :child (extension-node-child child)))
    (branch-node
     (make-extension-node :path path :child child))))

(defun trie-normalize-branch (children value)
  (let ((child-count 0)
        (only-index nil)
        (value-present-p (plusp (length value))))
    (dotimes (index 16)
      (when (aref children index)
        (incf child-count)
        (setf only-index index)))
    (cond
      ((and value-present-p (zerop child-count))
       (make-leaf-node :path (vector +terminator-nibble+) :value value))
      ((or value-present-p (> child-count 1))
       (make-branch-node :children children :value value))
      ((zerop child-count) nil)
      (t
       (trie-prepend-path only-index (aref children only-index))))))

(defun trie-delete-node (node path)
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (etypecase node
    (null nil)
    (leaf-node
     (if (bytes= (leaf-node-path node) path) nil node))
    (extension-node
     (let ((node-path (extension-node-path node)))
       (if (nibbles-prefix-p node-path path)
           (trie-normalize-extension
            node-path
            (trie-delete-node (extension-node-child node)
                              (subseq path (length node-path))))
           node)))
    (branch-node
     (let ((children (trie-copy-branch-children node))
           (value (branch-node-value node)))
       (if (trie-terminal-path-p path)
           (setf value (make-byte-vector 0))
           (let ((index (aref path 0)))
             (setf (aref children index)
                   (trie-delete-node (aref children index)
                                     (subseq path 1)))))
       (trie-normalize-branch children value)))))

(defun trie-get-node (node path)
  "Return (VALUES VALUE PRESENT-P) for PATH without resolving other branches."
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (etypecase node
    (null (values nil nil))
    (leaf-node
     (if (bytes= (leaf-node-path node) path)
         (values (leaf-node-value node) t)
         (values nil nil)))
    (extension-node
     (let ((node-path (extension-node-path node)))
       (if (nibbles-prefix-p node-path path)
           (trie-get-node
            (extension-node-child node)
            (subseq path (length node-path)))
           (values nil nil))))
    (branch-node
     (if (trie-terminal-path-p path)
         (let ((value (branch-node-value node)))
           (values value (plusp (length value))))
         (trie-get-node
          (aref (branch-node-children node) (aref path 0))
          (subseq path 1))))))

(defun mpt-put (trie key value)
  (let* ((key (ensure-byte-vector key))
         (key-id (trie-key-id key))
         (value (ensure-byte-vector value)))
    (if (zerop (length value))
        (mpt-delete trie key)
        (multiple-value-bind (old-value present-p)
            (mpt-get trie key)
          (unless (and present-p (bytes= old-value value))
            (setf (gethash key-id (mpt-entries trie)) value
                  (mpt-root trie)
                  (trie-put-node (mpt-root trie)
                                 (trie-path-with-terminator key)
                                 value))))))
  trie)

(defun mpt-put-proven-absent (trie key value)
  "Insert a non-empty KEY whose absence is already established by the caller.

Unlike MPT-PUT, this deliberately omits the defensive point lookup.  It is for
verified, gap-free range reconstruction where a monotonic durable cursor proves
that every key in the page is new.  General state transitions must keep using
MPT-PUT so updating an existing leaf retains its ordinary checked semantics."
  (let* ((key (ensure-byte-vector key))
         (key-id (trie-key-id key))
         (value (ensure-byte-vector value)))
    (when (zerop (length value))
      (error "A proven-absent MPT insertion requires a non-empty value"))
    (setf (gethash key-id (mpt-entries trie)) value
          (mpt-root trie)
          (trie-put-node (mpt-root trie)
                         (trie-path-with-terminator key)
                         value)))
  trie)

(defun mpt-delete (trie key)
  (let* ((key (ensure-byte-vector key))
         (key-id (trie-key-id key)))
    (when (nth-value 1 (mpt-get trie key))
      (remhash key-id (mpt-entries trie))
      (setf (mpt-root trie)
            (trie-delete-node (mpt-root trie)
                              (trie-path-with-terminator key)))))
  trie)

(defun mpt-get (trie key)
  (trie-get-node
   (mpt-root trie)
   (trie-path-with-terminator (ensure-byte-vector key))))

(defun trie-collect-entry-pairs (node prefix entries)
  (when (hash-node-p node)
    (setf node (trie-resolve-node node)))
  (etypecase node
    (null entries)
    (leaf-node
     (push (cons
            (nibbles-to-keybytes
             (concatenate 'vector prefix (leaf-node-path node)))
            (copy-seq (leaf-node-value node)))
           entries))
    (extension-node
     (setf entries
           (trie-collect-entry-pairs
            (extension-node-child node)
            (concatenate 'vector prefix (extension-node-path node))
            entries)))
    (branch-node
     (when (plusp (length (branch-node-value node)))
       (push (cons (nibbles-to-keybytes prefix)
                   (copy-seq (branch-node-value node)))
             entries))
     (dotimes (index 16)
       (setf entries
             (trie-collect-entry-pairs
              (aref (branch-node-children node) index)
              (concatenate 'vector prefix (vector index))
              entries)))))
  entries)

(defun mpt-entry-pairs (trie)
  (if (mpt-lazy-p trie)
      (sort
       (trie-collect-entry-pairs
        (mpt-root trie) (make-byte-vector 0) nil)
       #'string<
       :key (lambda (entry)
              (bytes-to-hex (car entry) :prefix nil)))
      (let (entries)
        (maphash (lambda (key-id value)
                   (push (cons key-id value) entries))
                 (mpt-entries trie))
        (loop for entry in (sort entries #'string< :key #'car)
              collect (cons (hex-to-bytes (car entry))
                            (copy-seq (cdr entry)))))))

(defun mpt-entry-range (trie &key start end)
  (let ((start-id (and start (trie-key-id start)))
        (end-id (and end (trie-key-id end))))
    (remove-if-not
     (lambda (entry)
       (let ((key-id (trie-key-id (car entry))))
         (and (or (null start-id)
                  (not (string< key-id start-id)))
              (or (null end-id)
                  (string< key-id end-id)))))
     (mpt-entry-pairs trie))))
