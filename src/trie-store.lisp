(in-package #:ethereum-lisp.trie)

;;;; Mutable in-memory Merkle Patricia Trie entry store.

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

(defun mpt-entry-range (trie &key start end)
  (let ((start-id (and start (trie-key-id start)))
        (end-id (and end (trie-key-id end)))
        entries)
    (maphash (lambda (key-id value)
               (when (and (or (null start-id)
                              (not (string< key-id start-id)))
                          (or (null end-id)
                              (string< key-id end-id)))
                 (push (cons key-id value) entries)))
             (mpt-entries trie))
    (loop for entry in (sort entries #'string< :key #'car)
          collect (cons (hex-to-bytes (car entry))
                        (copy-seq (cdr entry))))))
