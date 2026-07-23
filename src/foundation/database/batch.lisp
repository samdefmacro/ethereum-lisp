(in-package #:ethereum-lisp.database)

(defun kv-batch-put (batch key value)
  (push (list :put (kv-copy-bytes key) (kv-copy-bytes value))
        (kv-write-batch-operations batch))
  batch)

(defun kv-batch-delete (batch key)
  (push (list :delete (kv-copy-bytes key))
        (kv-write-batch-operations batch))
  batch)

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
