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

(defun ordered-slice-common-prefix-length (entries start end depth)
  "Return the common prefix after DEPTH for one ordered entry slice."
  (let* ((first (car (aref entries start)))
         (last (car (aref entries (1- end))))
         (limit (min (length first) (length last))))
    (loop for index from depth below limit
          while (= (aref first index) (aref last index))
          count 1)))

(defun build-node-ordered-slice (entries start end depth)
  "Build one canonical node from ENTRIES in the half-open slice START..END.

Every entry retains its full nibble key.  Recursion advances DEPTH and passes
index ranges instead of allocating a shortened key and a fresh cons at every
trie level."
  (let ((count (- end start)))
    (cond
      ((zerop count) nil)
      ((= count 1)
       (let ((entry (aref entries start)))
         (make-leaf-node
          :path (concatenate 'vector (subseq (car entry) depth)
                             (vector +terminator-nibble+))
          :value (cdr entry))))
      (t
       (let ((prefix-length
               (ordered-slice-common-prefix-length
                entries start end depth)))
         (if (plusp prefix-length)
             (make-extension-node
              :path (subseq (car (aref entries start))
                            depth (+ depth prefix-length))
              :child
              (build-node-ordered-slice
               entries start end (+ depth prefix-length)))
             (let ((children (make-array 16 :initial-element nil))
                   (value (make-byte-vector 0))
                   (cursor start))
               ;; A key that terminates at this depth precedes every key below
               ;; it in a lexicographically ordered input range.
               (when (= (length (car (aref entries cursor))) depth)
                 (setf value (cdr (aref entries cursor)))
                 (incf cursor))
               (loop while (< cursor end)
                     for nibble = (aref (car (aref entries cursor)) depth)
                     for group-end =
                       (loop for index from (1+ cursor) below end
                             while (let ((path (car (aref entries index))))
                                     (and (> (length path) depth)
                                          (= (aref path depth) nibble)))
                             finally (return index))
                     do (setf (aref children nibble)
                              (build-node-ordered-slice
                               entries cursor group-end (1+ depth))
                              cursor group-end))
               (make-branch-node :children children :value value))))))))

(defun build-node-ordered (entries)
  "Build a canonical node from lexicographically ordered nibble ENTRIES.

Unlike BUILD-NODE this path never scans the same level sixteen times and never
performs copy-on-write insertion for every leaf. It is the flat-range/stack
builder used after SNAP has already proved strict key ordering."
  (let ((entry-vector (coerce entries 'simple-vector)))
    (build-node-ordered-slice
     entry-vector 0 (length entry-vector) 0)))

(declaim (inline ordered-byte-key-nibble))
(defun ordered-byte-key-nibble (key index)
  "Read nibble INDEX directly from byte vector KEY without expanding KEY."
  (let ((byte (aref key (ash index -1))))
    (if (evenp index)
        (ash byte -4)
        (logand byte #x0f))))

(defun ordered-byte-key-nibble-slice (key start end &key terminator)
  "Materialize only KEY's nibble slice START..END and optional terminator."
  (let* ((length (- end start))
         (result (make-byte-vector (+ length (if terminator 1 0)))))
    (loop for index from start below end
          for output from 0
          do (setf (aref result output)
                   (ordered-byte-key-nibble key index)))
    (when terminator
      (setf (aref result length) +terminator-nibble+))
    result))

(defun ordered-byte-slice-common-prefix-length (entries start end depth)
  "Return the common nibble prefix after DEPTH for ordered byte-key ENTRIES."
  (let* ((first (car (aref entries start)))
         (last (car (aref entries (1- end))))
         (limit (* 2 (min (length first) (length last)))))
    (loop for index from depth below limit
          while (= (ordered-byte-key-nibble first index)
                   (ordered-byte-key-nibble last index))
          count 1)))

(defun build-node-ordered-byte-slice (entries start end depth)
  "Build one canonical node from an ordered byte-key slice.

Unlike BUILD-NODE-ORDERED-SLICE, this SNAP hot path never expands every secure
key into a temporary 64-byte nibble vector. Only the path retained by each
resulting leaf or extension is materialized."
  (let ((count (- end start)))
    (cond
      ((zerop count) nil)
      ((= count 1)
       (let* ((entry (aref entries start))
              (key (car entry))
              (key-nibbles (* 2 (length key))))
         (make-leaf-node
          :path (ordered-byte-key-nibble-slice
                 key depth key-nibbles :terminator t)
          :value (cdr entry))))
      (t
       (let ((prefix-length
               (ordered-byte-slice-common-prefix-length
                entries start end depth)))
         (if (plusp prefix-length)
             (let ((key (car (aref entries start))))
               (make-extension-node
                :path (ordered-byte-key-nibble-slice
                       key depth (+ depth prefix-length))
                :child
                (build-node-ordered-byte-slice
                 entries start end (+ depth prefix-length))))
             (let ((children (make-array 16 :initial-element nil))
                   (value (make-byte-vector 0))
                   (cursor start))
               (when (= (* 2 (length (car (aref entries cursor)))) depth)
                 (setf value (cdr (aref entries cursor)))
                 (incf cursor))
               (loop while (< cursor end)
                     for nibble =
                       (ordered-byte-key-nibble
                        (car (aref entries cursor)) depth)
                     for group-end =
                       (loop for index from (1+ cursor) below end
                             while (let* ((key (car (aref entries index)))
                                          (key-nibbles (* 2 (length key))))
                                     (and (> key-nibbles depth)
                                          (= (ordered-byte-key-nibble key depth)
                                             nibble)))
                             finally (return index))
                     do (setf (aref children nibble)
                              (build-node-ordered-byte-slice
                               entries cursor group-end (1+ depth))
                              cursor group-end))
               (make-branch-node :children children :value value))))))))

(defun build-node-ordered-byte-entries (entries)
  "Build a canonical node directly from ordered `(BYTE-KEY . VALUE)` entries."
  (let ((entry-vector (coerce entries 'simple-vector)))
    (build-node-ordered-byte-slice
     entry-vector 0 (length entry-vector) 0)))

(defvar *node-encoding-count* nil
  "When bound to a number, increment it for every trie node encoded on a cache
miss. Tests use this to guard the dirty-path complexity contract.")

(defvar *node-hash-computation-count* nil
  "When bound to a number, increment it for every concrete node hash cache miss.")

(defparameter +empty-trie-child-bytes+ (make-byte-vector 0)
  "Shared immutable encoding input for an absent trie branch child.")

(declaim (ftype (function (t) t) encoded-node node-reference))

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

(defun node-reference-byte-item (node)
  "Return NODE as bytes plus whether those bytes are already one RLP item."
  (cond
    ((null node)
     (values +empty-trie-child-bytes+ nil))
    ((hash-node-p node)
     (values (hash-node-hash node) nil))
    (t
     (let ((encoded (encoded-node node)))
       (if (< (length encoded) 32)
           ;; An inline child is an RLP list inside its parent's list.  Its
           ;; bytes must be copied verbatim instead of string-encoded again.
           (values encoded t)
           (values (node-reference node) nil))))))

(defun encode-node-direct (node)
  "Encode concrete NODE without staging an RLP object graph or child buffers."
  (etypecase node
    (leaf-node
     (let ((items (make-array 2)))
       (setf (aref items 0) (hex-prefix-encode (leaf-node-path node))
             (aref items 1) (leaf-node-value node))
       (ethereum-lisp.rlp::rlp-encode-byte-items items)))
    (extension-node
     (let ((items (make-array 2))
           (preencoded-mask 0))
       (setf (aref items 0) (hex-prefix-encode (extension-node-path node)))
       (multiple-value-bind (child-item preencoded-p)
           (node-reference-byte-item (extension-node-child node))
         (setf (aref items 1) child-item)
         (when preencoded-p
           (setf preencoded-mask (logior preencoded-mask (ash 1 1)))))
       (ethereum-lisp.rlp::rlp-encode-byte-items
        items :preencoded-mask preencoded-mask)))
    (branch-node
     (let ((items (make-array 17))
           (preencoded-mask 0))
       (dotimes (index 16)
         (multiple-value-bind (child-item preencoded-p)
             (node-reference-byte-item
              (aref (branch-node-children node) index))
           (setf (aref items index) child-item)
           (when preencoded-p
             (setf preencoded-mask
                   (logior preencoded-mask (ash 1 index))))))
       (setf (aref items 16) (branch-node-value node))
       (ethereum-lisp.rlp::rlp-encode-byte-items
        items :preencoded-mask preencoded-mask)))))

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
              (encode-node-direct node)))))

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
                                (or
                                 (node-cache-value
                                  node
                                  #'leaf-node-cached-hash
                                  #'extension-node-cached-hash
                                  #'branch-node-cached-hash)
                                 (progn
                                   (when *node-hash-computation-count*
                                     (incf *node-hash-computation-count*))
                                   (keccak-256 encoded))))))
            ;; A hashed child reference is exactly the node's content hash.
            ;; Persisting a freshly reconstructed SNAP page subsequently walks
            ;; every dirty child and asks for NODE-HASH; populate that cache
            ;; here so the walk does not hash the same encoding a second time.
            (when (and (byte-vector-p reference)
                       (= 32 (length reference)))
              (setf (node-cache-value
                     node
                     (lambda (value object)
                       (setf (leaf-node-cached-hash object) value))
                     (lambda (value object)
                       (setf (extension-node-cached-hash object) value))
                     (lambda (value object)
                       (setf (branch-node-cached-hash object) value)))
                    reference))
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
          (progn
            (when *node-hash-computation-count*
              (incf *node-hash-computation-count*))
            (setf (node-cache-value
                   node
                   (lambda (value object)
                     (setf (leaf-node-cached-hash object) value))
                   (lambda (value object)
                     (setf (extension-node-cached-hash object) value))
                   (lambda (value object)
                     (setf (branch-node-cached-hash object) value)))
                  (keccak-256 (encoded-node node)))))))

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
