(in-package #:ethereum-lisp.database)

(defun kv-put-chain-record (database kind identifier value)
  (kv-put database (kv-chain-record-key kind identifier) value))

(defun kv-get-chain-record (database kind identifier &optional default)
  (kv-get database (kv-chain-record-key kind identifier) default))

(defun kv-get-chain-records (database kind identifiers &optional default)
  "Return ordered value and presence vectors for IDENTIFIERS of KIND."
  (kv-get-many
   database
   (map 'vector
        (lambda (identifier)
          (kv-chain-record-key kind identifier))
        identifiers)
   default))

(defun kv-delete-chain-record (database kind identifier)
  (kv-delete database (kv-chain-record-key kind identifier)))

(defun kv-batch-put-chain-record (batch kind identifier value)
  (kv-batch-put batch (kv-chain-record-key kind identifier) value))

(defun kv-batch-delete-chain-record (batch kind identifier)
  (kv-batch-delete batch (kv-chain-record-key kind identifier)))

(defun kv-chain-records (database kind)
  ;; The closer is required even though the loop below runs to exhaustion and a
  ;; self-closing iterator would release itself: any non-local exit from the
  ;; loop -- a heap exhaustion inside the copy-out, or a caller unwinding
  ;; through this frame -- would otherwise leave a native RocksDB iterator
  ;; pinning its superversion, memtables and SST readers for the life of the
  ;; process. The closer is documented idempotent (KV-ITERATOR in types.lisp),
  ;; so calling it after exhaustion is a no-op.
  (multiple-value-bind (iterator close-iterator)
      (kv-iterator database
                   :start (kv-chain-record-kind-start-key kind)
                   :end (kv-chain-record-kind-end-key kind))
    (unwind-protect
         (loop with records = nil
               do (multiple-value-bind (key value present-p)
                      (funcall iterator)
                    (unless present-p
                      (return (nreverse records)))
                    (push (cons key value) records)))
      (when close-iterator (funcall close-iterator)))))

(defun kv-chain-record-entries (database kind)
  (mapcar
   (lambda (record)
     (cons (kv-chain-record-key-identifier kind (car record))
           (cdr record)))
   (kv-chain-records database kind)))

(defun kv-put-chain-canonical-hash (database number hash)
  (kv-put-chain-record database :canonical-hash number hash))

(defun kv-get-chain-canonical-hash (database number &optional default)
  (kv-get-chain-record database :canonical-hash number default))

(defun kv-delete-chain-canonical-hash (database number)
  (kv-delete-chain-record database :canonical-hash number))

(defun kv-batch-put-chain-canonical-hash (batch number hash)
  (kv-batch-put-chain-record batch :canonical-hash number hash))

(defun kv-batch-delete-chain-canonical-hash (batch number)
  (kv-batch-delete-chain-record batch :canonical-hash number))

(defun kv-chain-canonical-hashes (database)
  (mapcar
   (lambda (entry)
     (cons (kv-chain-record-uint64-identifier (car entry))
           (cdr entry)))
   (kv-chain-record-entries database :canonical-hash)))

(defun kv-put-chain-checkpoint (database label hash)
  (kv-put-chain-record
   database :checkpoint (kv-chain-checkpoint-identifier label) hash))

(defun kv-get-chain-checkpoint (database label &optional default)
  (kv-get-chain-record
   database :checkpoint (kv-chain-checkpoint-identifier label) default))

(defun kv-delete-chain-checkpoint (database label)
  (kv-delete-chain-record
   database :checkpoint (kv-chain-checkpoint-identifier label)))

(defun kv-batch-put-chain-checkpoint (batch label hash)
  (kv-batch-put-chain-record
   batch :checkpoint (kv-chain-checkpoint-identifier label) hash))

(defun kv-batch-delete-chain-checkpoint (batch label)
  (kv-batch-delete-chain-record
   batch :checkpoint (kv-chain-checkpoint-identifier label)))

(defun kv-chain-checkpoints (database)
  (mapcar
   (lambda (entry)
     (cons (kv-chain-checkpoint-label (car entry))
           (cdr entry)))
   (kv-chain-record-entries database :checkpoint)))

(defun kv-put-chain-schema-version
    (database &optional (version +kv-chain-schema-version+))
  (kv-put-chain-record
   database :schema-version +kv-chain-schema-version-identifier+
   (kv-chain-record-uint64-bytes version)))

(defun kv-batch-put-chain-schema-version
    (batch &optional (version +kv-chain-schema-version+))
  (kv-batch-put-chain-record
   batch :schema-version +kv-chain-schema-version-identifier+
   (kv-chain-record-uint64-bytes version)))

(defun kv-get-chain-schema-version (database)
  "Return the persisted on-disk chain schema version and a presence flag.
Absence means a database written before the versioned schema marker existed."
  (multiple-value-bind (value present-p)
      (kv-get-chain-record
       database :schema-version +kv-chain-schema-version-identifier+)
    (if present-p
        (values (kv-chain-record-uint64-identifier value) t)
        (values nil nil))))
