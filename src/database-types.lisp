(in-package #:ethereum-lisp.database)

(defclass key-value-database () ())

(defclass memory-key-value-database (key-value-database)
  ((entries :initform (make-hash-table :test 'equalp)
            :accessor memory-key-value-database-entries)))

(defclass file-key-value-database (memory-key-value-database)
  ((path :initarg :path :reader file-key-value-database-path)))

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
