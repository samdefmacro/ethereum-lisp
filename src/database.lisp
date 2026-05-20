(in-package #:ethereum-lisp.database)

(defclass key-value-database () ())

(defclass memory-key-value-database (key-value-database)
  ((entries :initform (make-hash-table :test 'equal)
            :accessor memory-key-value-database-entries)))

(defstruct kv-memory-entry
  key
  value)

(defstruct (kv-write-batch (:constructor %make-kv-write-batch))
  operations)

(defgeneric kv-get (database key &optional default))
(defgeneric kv-put (database key value))
(defgeneric kv-delete (database key))
(defgeneric kv-apply-batch (database batch))
(defgeneric kv-iterator (database &key start end reverse-p))

(defun make-memory-key-value-database ()
  (make-instance 'memory-key-value-database))

(defun make-kv-write-batch ()
  (%make-kv-write-batch :operations nil))

(defun kv-copy-bytes (bytes)
  (copy-seq (ensure-byte-vector bytes)))

(defun kv-key-string (key)
  (bytes-to-hex (ensure-byte-vector key)))

(defun kv-entry< (left right)
  (string< (kv-key-string (kv-memory-entry-key left))
           (kv-key-string (kv-memory-entry-key right))))

(defun kv-entry-in-range-p (entry start end)
  (let ((key (kv-key-string (kv-memory-entry-key entry)))
        (start-key (and start (kv-key-string start)))
        (end-key (and end (kv-key-string end))))
    (and (or (null start-key)
             (not (string< key start-key)))
         (or (null end-key)
             (string< key end-key)))))

(defmethod kv-get ((database memory-key-value-database) key &optional default)
  (let ((entry (gethash (kv-key-string key)
                        (memory-key-value-database-entries database))))
    (if entry
        (values (kv-copy-bytes (kv-memory-entry-value entry)) t)
        (values default nil))))

(defmethod kv-put ((database memory-key-value-database) key value)
  (let ((entry (make-kv-memory-entry :key (kv-copy-bytes key)
                                     :value (kv-copy-bytes value))))
    (setf (gethash (kv-key-string key)
                   (memory-key-value-database-entries database))
          entry))
  database)

(defmethod kv-delete ((database memory-key-value-database) key)
  (remhash (kv-key-string key)
           (memory-key-value-database-entries database)))

(defun kv-batch-put (batch key value)
  (push (list :put (kv-copy-bytes key) (kv-copy-bytes value))
        (kv-write-batch-operations batch))
  batch)

(defun kv-batch-delete (batch key)
  (push (list :delete (kv-copy-bytes key))
        (kv-write-batch-operations batch))
  batch)

(defmethod kv-apply-batch ((database memory-key-value-database)
                           (batch kv-write-batch))
  (dolist (operation (reverse (kv-write-batch-operations batch)) database)
    (ecase (first operation)
      (:put (kv-put database (second operation) (third operation)))
      (:delete (kv-delete database (second operation))))))

(defmethod kv-iterator ((database memory-key-value-database)
                        &key start end reverse-p)
  (let* ((entries
           (loop for entry being the hash-values of
                   (memory-key-value-database-entries database)
                 when (kv-entry-in-range-p entry start end)
                   collect entry))
         (sorted
           (sort entries (if reverse-p
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
