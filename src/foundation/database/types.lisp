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

(defconstant +kv-get-many-max-keys+ 4096)
(defconstant +kv-get-many-max-key-bytes+ (* 4 1024 1024))

(defun kv-get-many-keys (keys)
  "Normalize and bound a native multi-get input sequence."
  (let ((count (length keys)))
    (unless (<= count +kv-get-many-max-keys+)
      (error "KV multi-get exceeds ~D keys" +kv-get-many-max-keys+))
    (let ((normalized (map 'vector #'ensure-byte-vector keys)))
      (unless
          (<= (loop for key across normalized sum (length key))
              +kv-get-many-max-key-bytes+)
        (error "KV multi-get key bytes exceed ~D"
               +kv-get-many-max-key-bytes+))
      normalized)))

(defgeneric kv-get (database key &optional default))
(defgeneric kv-get-many (database keys &optional default)
  (:documentation
   "Return VALUES and PRESENT-P vectors for KEYS in the same order.

The generic fallback preserves KV-GET semantics. Native backends may override
it with one bounded multi-key operation; callers retain exact per-key absence
information and never observe partial results when the backend signals."))
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
(defgeneric kv-apply-batch-buffered (database batch)
  (:documentation
   "Apply BATCH atomically without independently establishing a durable seam.

The default delegates to KV-APPLY-BATCH. A production backend may return after
the atomic WAL append but before syncing it only when the caller will publish
no cursor or externally visible completion marker until a later
KV-APPLY-BATCH. That later synchronous batch must make all preceding buffered
writes durable before it returns. A crash before the seam may lose the
unpublished work, which the absent cursor makes safe to retry."))
(defgeneric kv-buffered-batch-supported-p (database)
  (:documentation
   "Return true when KV-APPLY-BATCH-BUFFERED is a real non-syncing WAL path.

The default backends establish a durable seam even through the buffered API;
callers use this capability to report durability and generation changes
accurately while RocksDB group-commits unpublished work."))
(defgeneric kv-iterator (database &key start end reverse-p)
  (:documentation
   "Return an iterator function and, as a second value, an idempotent closer.

The iterator returns KEY, VALUE, PRESENT-P and closes itself at end of range.
Callers that intentionally stop before exhaustion must call the closer so a
native backend can release its iterator and surface any deferred IO error."))

(defmethod kv-get-many ((database key-value-database) keys &optional default)
  (let* ((keys (kv-get-many-keys keys))
         (count (length keys))
         (results (make-array count))
         (present (make-array count :element-type 'bit :initial-element 0)))
    (dotimes (index count)
      (multiple-value-bind (value present-p)
          (kv-get database (elt keys index) default)
        (setf (aref results index) value
              (aref present index) (if present-p 1 0))))
    (values results present)))

(defun make-memory-key-value-database ()
  (make-instance 'memory-key-value-database))

(defun make-kv-write-batch ()
  (%make-kv-write-batch :operations nil))

(defun kv-copy-bytes (bytes)
  (copy-seq (ensure-byte-vector bytes)))

(defun kv-key-string (key)
  (bytes-to-hex (ensure-byte-vector key)))

(defun kv-key< (left right)
  "Return true when LEFT precedes RIGHT in RocksDB's bytewise key order."
  (let ((left (ensure-byte-vector left))
        (right (ensure-byte-vector right)))
    (loop for index below (min (length left) (length right))
          for left-byte = (aref left index)
          for right-byte = (aref right index)
          when (< left-byte right-byte)
            do (return t)
          when (> left-byte right-byte)
            do (return nil)
          finally (return (< (length left) (length right))))))

(defun kv-entry< (left right)
  (kv-key< (kv-memory-entry-key left)
           (kv-memory-entry-key right)))

(defun kv-entry-in-range-p (entry start end)
  (let ((key (kv-memory-entry-key entry)))
    (and (or (null start)
             (not (kv-key< key start)))
         (or (null end)
             (kv-key< key end)))))
