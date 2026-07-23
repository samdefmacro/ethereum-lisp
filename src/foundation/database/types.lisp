(in-package #:ethereum-lisp.database)

(defclass key-value-database () ())

(defclass memory-key-value-database (key-value-database)
  ((entries :initform (make-hash-table :test 'equalp)
            :accessor memory-key-value-database-entries)))

(defconstant +kv-log-default-compaction-min-bytes+ (* 1024 1024)
  "Do not compact the write log before it reaches this many bytes.")

(defconstant +kv-log-default-compaction-ratio+ 2
  "Compact the write log once it exceeds this multiple of the live data size.")

(defclass file-key-value-database (memory-key-value-database)
  ((path :initarg :path :reader file-key-value-database-path)
   (log-bytes
    :initform 0
    :accessor file-key-value-database-log-bytes
    :documentation "Current size of the on-disk write log in bytes.")
   (live-bytes
    :initform 0
    :accessor file-key-value-database-live-bytes
    :documentation "Encoded size of the live entries, for compaction sizing.")
   (compaction-min-bytes
    :initarg :compaction-min-bytes
    :initform +kv-log-default-compaction-min-bytes+
    :reader file-key-value-database-compaction-min-bytes)
   (compaction-ratio
    :initarg :compaction-ratio
    :initform +kv-log-default-compaction-ratio+
    :reader file-key-value-database-compaction-ratio)
   (needs-migration-p
    :initform nil
    :accessor file-key-value-database-needs-migration-p
    :documentation "True when the file still holds the v1 format; the first
durable write rewrites it as a log. Opens never mutate the file.")
   (pending-truncation
    :initform nil
    :accessor file-key-value-database-pending-truncation
    :documentation "Offset of a torn tail found on open, truncated by the
first durable write. Opens never mutate the file.")
   (write-failed-p
    :initform nil
    :accessor file-key-value-database-write-failed-p
    :documentation "Set when an append fails partway; the handle refuses
further writes because the on-disk tail is no longer trusted. Reopen.")))

(defstruct kv-memory-entry
  key
  value)

(defstruct (kv-write-batch (:constructor %make-kv-write-batch))
  operations)

(defgeneric kv-get (database key &optional default))
(defgeneric kv-put (database key value))
(defgeneric kv-delete (database key))
(defgeneric kv-apply-batch (database batch)
  (:documentation
   "Apply every BATCH operation atomically.
If an error is signaled, no batch operation is visible in this handle's view,
and recovery on reopen drops any partially written record. If the durable
sync itself fails after the bytes reached the operating system, whether the
record survives a crash is filesystem-dependent; the handle refuses further
writes either way and must be reopened."))
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
