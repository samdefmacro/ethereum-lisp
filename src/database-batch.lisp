(in-package #:ethereum-lisp.database)

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

(defmethod kv-apply-batch ((database file-key-value-database)
                           (batch kv-write-batch))
  (dolist (operation (reverse (kv-write-batch-operations batch)) database)
    (ecase (first operation)
      (:put (kv-put-memory-entry
             database (second operation) (third operation)))
      (:delete (kv-delete-memory-entry database (second operation)))))
  (kv-persist-file-database database))
