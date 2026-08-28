(in-package #:ethereum-lisp.database)

(defun kv-batch-put (batch key value)
  (push (list :put (kv-copy-bytes key) (kv-copy-bytes value))
        (kv-write-batch-operations batch))
  batch)

(defun kv-batch-delete (batch key)
  (push (list :delete (kv-copy-bytes key))
        (kv-write-batch-operations batch))
  batch)

(defun kv-batch-append (destination source)
  "Append SOURCE after DESTINATION in application order, consuming SOURCE.

Both batches already own private key/value copies. Moving their operation
lists preserves the public KV-BATCH-PUT mutation boundary without copying a
prepared page a second time on a central writer thread."
  (check-type destination kv-write-batch)
  (check-type source kv-write-batch)
  (when (eq destination source)
    (error "A KV write batch cannot append itself"))
  ;; Operations are stored in reverse application order. SOURCE must precede
  ;; DESTINATION internally so reversing the combined list applies the old
  ;; destination prefix followed by the source suffix.
  (setf (kv-write-batch-operations destination)
        (nconc (kv-write-batch-operations source)
               (kv-write-batch-operations destination))
        (kv-write-batch-operations source) nil)
  destination)

(defun kv-write-batch-statistics (batch)
  "Return BATCH's operation count and logical key/value byte count.

The byte count excludes WAL and SST framing.  It is an observational baseline
for comparing application writes with backend and device write amplification."
  (check-type batch kv-write-batch)
  (loop for operation in (kv-write-batch-operations batch)
        count 1 into operation-count
        sum (+ (length (second operation))
               (if (eq :put (first operation))
                   (length (third operation))
                   0))
          into byte-count
        finally (return (values operation-count byte-count))))

(defun kv-apply-batch-to-memory-shadow (source shadow batch)
  (setf (memory-key-value-database-entries shadow)
        (kv-copy-memory-database-entries source))
  (dolist (operation (reverse (kv-write-batch-operations batch)) shadow)
    (ecase (first operation)
      (:put
       (kv-put-memory-entry shadow (second operation) (third operation)))
      (:delete
       (kv-delete-memory-entry shadow (second operation))))))

(defmethod kv-apply-batch ((database memory-key-value-database)
                           (batch kv-write-batch))
  (let ((shadow (make-memory-key-value-database)))
    (kv-apply-batch-to-memory-shadow database shadow batch)
    (setf (memory-key-value-database-entries database)
          (memory-key-value-database-entries shadow))
    database))

(defmethod kv-apply-batch ((database file-key-value-database)
                           (batch kv-write-batch))
  ;; The whole batch becomes one CRC-framed log record: encoding validates
  ;; every operation before any disk or table mutation, and the record is
  ;; fsynced before the in-memory table changes, so neither an invalid batch
  ;; nor a crash can expose a partial write set.
  (kv-log-write-durable-set
   database
   (reverse (kv-write-batch-operations batch))))

(defmethod kv-apply-batch-buffered
    ((database key-value-database) (batch kv-write-batch))
  ;; Memory and the fsync-per-record file oracle have no cheaper recoverable
  ;; prefix. Preserve their existing behavior; RocksDB specializes this seam.
  (kv-apply-batch database batch))
