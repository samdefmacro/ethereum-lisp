(in-package #:ethereum-lisp.database)

(defun kv-put-memory-entry (database key value)
  (let ((entry (make-kv-memory-entry :key (kv-copy-bytes key)
                                     :value (kv-copy-bytes value))))
    (setf (gethash (kv-key-string key)
                   (memory-key-value-database-entries database))
          entry))
  database)

(defun kv-delete-memory-entry (database key)
  (remhash (kv-key-string key)
           (memory-key-value-database-entries database)))

(defun kv-copy-memory-database-entries (database)
  (let ((copy (make-hash-table :test 'equalp)))
    (maphash
     (lambda (key entry)
       (setf (gethash key copy)
             (make-kv-memory-entry
              :key (kv-copy-bytes (kv-memory-entry-key entry))
              :value (kv-copy-bytes (kv-memory-entry-value entry)))))
     (memory-key-value-database-entries database))
    copy))

(defun kv-database-sorted-entries (database)
  (sort
   (loop for entry being the hash-values of
           (memory-key-value-database-entries database)
         collect entry)
   #'kv-entry<))

(defmethod kv-get ((database memory-key-value-database) key &optional default)
  (let ((entry (gethash (kv-key-string key)
                        (memory-key-value-database-entries database))))
    (if entry
        (values (kv-copy-bytes (kv-memory-entry-value entry)) t)
        (values default nil))))

(defmethod kv-put ((database memory-key-value-database) key value)
  (kv-put-memory-entry database key value))

(defmethod kv-delete ((database memory-key-value-database) key)
  (kv-delete-memory-entry database key))

(defmethod kv-iterator ((database memory-key-value-database)
                        &key start end reverse-p)
  (let* ((entries
           (loop for entry being the hash-values of
                   (memory-key-value-database-entries database)
                 when (kv-entry-in-range-p entry start end)
                   collect entry))
         (sorted
           (sort entries
                 (if reverse-p
                     (lambda (left right)
                       (kv-entry< right left))
                     #'kv-entry<)))
         (remaining sorted))
    (lambda ()
      (let ((entry (pop remaining)))
        (if entry
            (values (kv-copy-bytes (kv-memory-entry-key entry))
                    (kv-copy-bytes (kv-memory-entry-value entry))
                    t)
            (values nil nil nil))))))
