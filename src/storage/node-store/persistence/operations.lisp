(in-package #:ethereum-lisp.node-store.persistence)

;;;; Bounded, resumable database operator workflows.
;;;;
;;;; Backup and restore copy raw key/value records rather than hydrating a
;;;; chain store. Memory use is bounded by BATCH-SIZE, and a private progress
;;;; record advances in the same atomic batch as every copied chunk. Ordinary
;;;; schema reads refuse a destination while that marker exists. Before the
;;;; final batch removes it, a streaming comparison proves that the target is
;;;; byte-for-byte equal to the source while holding only one record from each
;;;; database in memory.
;;;;
;;;; These operations require an offline source. RocksDB's ordinary iterator
;;;; is not a cross-database transaction, so a node writing the source during
;;;; a copy could change it after the equality pass. The progress marker keeps
;;;; an interrupted or detected-mismatch target unusable, but it cannot make a
;;;; concurrently mutating source a stable snapshot.

(defconstant +node-store-database-copy-progress-version+ 1)

(defparameter +node-store-default-database-copy-batch-size+ 1024
  "Maximum key/value records copied by one durable backup or restore batch.")

(defstruct (node-store-database-copy-progress
            (:constructor make-node-store-database-copy-progress
                (&key operation source-schema-version copied-count cursor)))
  operation
  source-schema-version
  copied-count
  cursor)

(defun node-store-database-copy-operation-name (operation)
  (ecase operation
    (:backup "backup")
    (:restore "restore")
    (:rebuild "rebuild")
    (:repair "repair")))

(defun node-store-database-copy-operation-from-name (name)
  (cond
    ((string= name "backup") :backup)
    ((string= name "restore") :restore)
    ((string= name "rebuild") :rebuild)
    ((string= name "repair") :repair)
    (t
     (block-validation-fail
      "Unknown chain database copy operation: ~A" name))))

(defun node-store-database-copy-progress-record (progress)
  (rlp-encode
   (make-rlp-list
    +node-store-database-copy-progress-version+
    (ascii-to-bytes
     (node-store-database-copy-operation-name
      (node-store-database-copy-progress-operation progress)))
    (node-store-database-copy-progress-source-schema-version progress)
    (node-store-database-copy-progress-copied-count progress)
    (node-store-database-copy-progress-cursor progress))))

(defun node-store-database-copy-progress-from-record (record)
  (handler-case
      (let ((fields
              (rlp-list-field
               (rlp-decode-one record) "Chain database copy progress")))
        (unless (= 5 (length fields))
          (block-validation-fail
           "Chain database copy progress must contain 5 fields"))
        (let ((record-version
                (rlp-uint-field
                 (first fields) "Chain database copy progress version"))
              (operation
                (node-store-database-copy-operation-from-name
                 (bytes-to-ascii
                  (rlp-bytes-field
                   (second fields) "Chain database copy operation"))))
              (source-schema-version
                (rlp-uint-field
                 (third fields) "Chain database copy source schema"))
              (copied-count
                (rlp-uint-field
                 (fourth fields) "Chain database copy record count"))
              (cursor
                (rlp-bytes-field
                 (fifth fields) "Chain database copy cursor")))
          (unless (= record-version
                     +node-store-database-copy-progress-version+)
            (block-validation-fail
             "Unsupported chain database copy progress version: ~D"
             record-version))
          (make-node-store-database-copy-progress
           :operation operation
           :source-schema-version source-schema-version
           :copied-count copied-count
           :cursor cursor)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid chain database copy progress RLP: ~A" condition))))

(defun node-store-read-database-copy-progress (database)
  (multiple-value-bind (record present-p)
      (kv-get-chain-record
       database :metadata +node-store-database-copy-progress-identifier+)
    (if present-p
        (values (node-store-database-copy-progress-from-record record) t)
        (values nil nil))))

(defun node-store-put-database-copy-progress (batch progress)
  (kv-batch-put-chain-record
   batch :metadata +node-store-database-copy-progress-identifier+
   (node-store-database-copy-progress-record progress)))

(defun node-store-delete-database-copy-progress (batch)
  (kv-batch-delete-chain-record
   batch :metadata +node-store-database-copy-progress-identifier+))

(defun node-store-database-empty-p (database)
  (multiple-value-bind (iterator close-iterator)
      (kv-iterator database)
    (unwind-protect
         (multiple-value-bind (key value present-p)
             (funcall iterator)
           (declare (ignore key value))
           (not present-p))
      (when close-iterator
        (funcall close-iterator)))))

(defun node-store-database-copy-chunk
    (source cursor batch-size)
  "Return up to BATCH-SIZE raw SOURCE records strictly after CURSOR."
  (let ((start (and (plusp (length cursor)) cursor))
        (records '())
        (record-count 0))
    (multiple-value-bind (iterator close-iterator)
        (kv-iterator source :start start)
      (unwind-protect
           (loop while (< record-count batch-size)
                 do (multiple-value-bind (key value present-p)
                        (funcall iterator)
                      (unless present-p
                        (return))
                      ;; START is inclusive, while the cursor names the last
                      ;; record already committed to the destination.
                      (unless (and start (bytes= key cursor))
                        (push (list key value) records)
                        (incf record-count))))
        (when close-iterator
          (funcall close-iterator))))
    (nreverse records)))

(defun node-store-next-copy-target-record (iterator progress-key)
  "Return the next target record, hiding its private copy marker."
  (loop
    (multiple-value-bind (key value present-p)
        (funcall iterator)
      (unless present-p
        (return (values nil nil nil)))
      (unless (bytes= key progress-key)
        (return (values key value t))))))

(defun node-store-databases-copy-equal-p (source target)
  "Compare SOURCE with TARGET while ignoring TARGET's copy progress marker."
  (let ((progress-key
          (kv-chain-record-key
           :metadata +node-store-database-copy-progress-identifier+)))
    (multiple-value-bind (source-iterator close-source-iterator)
        (kv-iterator source)
      (multiple-value-bind (target-iterator close-target-iterator)
          (kv-iterator target)
        (unwind-protect
             (loop
               (multiple-value-bind
                     (source-key source-value source-present-p)
                   (funcall source-iterator)
                 (multiple-value-bind
                       (target-key target-value target-present-p)
                     (node-store-next-copy-target-record
                      target-iterator progress-key)
                   (unless (and (eql source-present-p target-present-p)
                                (or (not source-present-p)
                                    (and (bytes= source-key target-key)
                                         (bytes= source-value target-value))))
                     (return nil))
                   (unless source-present-p
                     (return t)))))
          (when close-target-iterator
            (funcall close-target-iterator))
          (when close-source-iterator
            (funcall close-source-iterator)))))))

(defun node-store-call-database-copy-batch-hook (hook progress)
  (when hook
    (funcall hook progress)))

(defun node-store-start-database-copy
    (target operation source-schema-version hook)
  (unless (node-store-database-empty-p target)
    (block-validation-fail
     "Chain database ~A target must be empty" operation))
  (let* ((progress
           (make-node-store-database-copy-progress
            :operation operation
            :source-schema-version source-schema-version
            :copied-count 0
            :cursor (make-byte-vector 0)))
         (batch (make-kv-write-batch)))
    (node-store-put-database-copy-progress batch progress)
    (kv-apply-batch target batch)
    (node-store-call-database-copy-batch-hook hook progress)
    progress))

(defun node-store-validate-database-copy-progress
    (progress operation source-schema-version)
  (unless (eq operation
              (node-store-database-copy-progress-operation progress))
    (block-validation-fail
     "Incomplete chain database ~A cannot resume as ~A"
     (node-store-database-copy-progress-operation progress)
     operation))
  (unless (= source-schema-version
             (node-store-database-copy-progress-source-schema-version
              progress))
    (block-validation-fail
     "Chain database copy source schema changed from ~D to ~D"
     (node-store-database-copy-progress-source-schema-version progress)
     source-schema-version))
  progress)

(defun node-store-advance-database-copy
    (source target progress batch-size hook)
  "Apply one durable copy chunk; return new progress or NIL when complete."
  (let* ((cursor (node-store-database-copy-progress-cursor progress))
         (records
           (node-store-database-copy-chunk source cursor batch-size)))
    (if records
        (let* ((batch (make-kv-write-batch))
               (new-progress
                 (make-node-store-database-copy-progress
                  :operation
                  (node-store-database-copy-progress-operation progress)
                  :source-schema-version
                  (node-store-database-copy-progress-source-schema-version
                   progress)
                  :copied-count
                  (+ (node-store-database-copy-progress-copied-count progress)
                     (length records))
                  :cursor (caar (last records)))))
          (dolist (entry records)
            (kv-batch-put batch (first entry) (second entry)))
          ;; A copied record is never durable without the cursor proving it no
          ;; longer needs to be copied after a restart.
          (node-store-put-database-copy-progress batch new-progress)
          (kv-apply-batch target batch)
          (node-store-call-database-copy-batch-hook hook new-progress)
          new-progress)
        (progn
          ;; Compare before deleting the refusal marker. If SOURCE changed or
          ;; TARGET was damaged, the destination stays explicitly incomplete.
          (unless (node-store-databases-copy-equal-p source target)
            (block-validation-fail
             "Chain database copy target does not exactly match its source"))
          (let ((batch (make-kv-write-batch)))
            (node-store-delete-database-copy-progress batch)
            (kv-apply-batch target batch))
          (node-store-call-database-copy-batch-hook hook nil)
          nil))))

(defun node-store-copy-chain-database
    (source target operation
     &key
       (batch-size +node-store-default-database-copy-batch-size+)
       after-batch)
  "Copy SOURCE to an empty TARGET with bounded, resumable atomic batches.

OPERATION is persisted in TARGET so the wrong
workflow cannot resume it accidentally. SOURCE must remain offline for the
duration. Returns the number of copied records and whether work was done."
  (unless (and (typep source 'key-value-database)
               (typep target 'key-value-database))
    (block-validation-fail
     "Chain database copy requires key-value source and target databases"))
  (when (eq source target)
    (block-validation-fail
     "Chain database copy source and target must be different handles"))
  (node-store-database-copy-operation-name operation)
  (unless (and (integerp batch-size) (plusp batch-size))
    (block-validation-fail
     "Chain database copy batch size must be a positive integer"))
  (let ((source-schema-version (node-store-chain-schema-version source)))
    (multiple-value-bind (stored-progress progress-present-p)
        (node-store-read-database-copy-progress target)
      (let ((progress
              (if progress-present-p
                  (node-store-validate-database-copy-progress
                   stored-progress operation source-schema-version)
                  (node-store-start-database-copy
                   target operation source-schema-version after-batch)))
            (copied-count
              (if progress-present-p
                  (node-store-database-copy-progress-copied-count
                   stored-progress)
                  0)))
        (loop while progress
              do (let ((new-progress
                         (node-store-advance-database-copy
                          source target progress batch-size after-batch)))
                   (when new-progress
                     (setf copied-count
                           (node-store-database-copy-progress-copied-count
                            new-progress)))
                   (setf progress new-progress))
              finally
                 (return
                   (values copied-count t)))))))

(defun node-store-rebuild-derived-record-kind-p (kind)
  (member kind
          '(:header :receipt :transaction-location
            :ordered-block :ordered-header :ordered-receipt
            :ordered-state-history)))

(defun node-store-populate-rebuilt-transaction-locations
    (batch block receipts)
  (loop with log-index-start = 0
        for transaction in (block-transactions block)
        for receipt in receipts
        for index from 0
        do (kv-batch-put-chain-record
            batch
            :transaction-location
            (hash32-bytes (transaction-hash transaction))
            (transaction-location-record-rlp
             (make-engine-transaction-location
              :block block
              :index index
              :transaction transaction
              :receipt receipt
              :log-index-start log-index-start)))
           (incf log-index-start (length (receipt-logs receipt)))))

(defun node-store-populate-rebuilt-block-records
    (source batch full-key record)
  (let* ((identifier (kv-chain-record-key-identifier :block full-key))
         (block
           (chain-store-decode-persisted-block-record
            record "Block record during database rebuild"))
         (actual-identifier (hash32-bytes (block-hash block))))
    (unless (bytes= identifier actual-identifier)
      (block-validation-fail
       "Block record key does not match its encoded hash during rebuild"))
    (multiple-value-bind (receipt-record receipt-present-p)
        (kv-get-chain-record source :receipt identifier)
      (unless receipt-present-p
        (block-validation-fail
         "Block ~A has no receipt record to rebuild"
         (bytes-to-hex identifier)))
      (let* ((receipts (block-receipts-from-record block receipt-record))
             (header-record (block-header-rlp (block-header block)))
             (number (block-header-number (block-header block)))
             (ordered-identifier
               (kv-chain-height-hash-identifier number identifier)))
        (kv-batch-put-chain-record batch :block identifier record)
        (kv-batch-put-chain-record
         batch :header identifier header-record)
        (kv-batch-put-chain-record
         batch :receipt identifier receipt-record)
        (kv-batch-put-chain-record
         batch :ordered-block ordered-identifier record)
        (kv-batch-put-chain-record
         batch :ordered-header ordered-identifier header-record)
        (kv-batch-put-chain-record
         batch :ordered-receipt ordered-identifier receipt-record)
        (multiple-value-bind (state-root state-root-present-p)
            (kv-get-chain-record source :state-history identifier)
          (when state-root-present-p
            (kv-batch-put-chain-record
             batch :ordered-state-history ordered-identifier state-root)))
        (multiple-value-bind (canonical-hash canonical-p)
            (kv-get-chain-canonical-hash source number)
          (when (and canonical-p (bytes= canonical-hash identifier))
            (node-store-populate-rebuilt-transaction-locations
             batch block receipts)))))))

(defun node-store-populate-database-rebuild-record
    (source batch full-key record)
  (let ((kind (kv-chain-record-key-kind full-key)))
    (cond
      ((eq kind :block)
       (node-store-populate-rebuilt-block-records
        source batch full-key record))
      ((node-store-rebuild-derived-record-kind-p kind)
       ;; These records are reconstructed from each validated :BLOCK and its
       ;; primary :RECEIPT record. Skipping the source copies also drops stale
       ;; or dangling derived entries.
       nil)
      (t
       (kv-batch-put batch full-key record)))))

(defun node-store-advance-database-rebuild
    (source target progress batch-size hook)
  (let* ((cursor (node-store-database-copy-progress-cursor progress))
         (records (node-store-database-copy-chunk source cursor batch-size)))
    (if records
        (let* ((batch (make-kv-write-batch))
               (new-progress
                 (make-node-store-database-copy-progress
                  :operation
                  (node-store-database-copy-progress-operation progress)
                  :source-schema-version
                  (node-store-database-copy-progress-source-schema-version
                   progress)
                  :copied-count
                  (+ (node-store-database-copy-progress-copied-count progress)
                     (length records))
                  :cursor (caar (last records)))))
          (handler-case
              (dolist (entry records)
                (node-store-populate-database-rebuild-record
                 source batch (first entry) (second entry)))
            (rlp-error (condition)
              (block-validation-fail
               "Invalid record RLP while rebuilding chain database: ~A"
               condition)))
          (node-store-put-database-copy-progress batch new-progress)
          (kv-apply-batch target batch)
          (node-store-call-database-copy-batch-hook hook new-progress)
          new-progress)
        (let ((findings
                (node-store-verify-chain-database
                 target
                 :allow-incomplete-operation
                 +node-store-database-copy-progress-identifier+)))
          (when findings
            (block-validation-fail
             "Rebuilt chain database is not consistent: ~A"
             (node-store-database-finding-description (first findings))))
          (let ((batch (make-kv-write-batch)))
            (node-store-delete-database-copy-progress batch)
            (kv-apply-batch target batch))
          (node-store-call-database-copy-batch-hook hook nil)
          nil))))

(defun node-store-run-database-rebuild
    (source target operation batch-size after-batch)
  (unless (and (typep source 'key-value-database)
               (typep target 'key-value-database))
    (block-validation-fail
     "Chain database rebuild requires key-value source and target databases"))
  (when (eq source target)
    (block-validation-fail
     "Chain database rebuild source and target must be different handles"))
  (node-store-database-copy-operation-name operation)
  (unless (and (integerp batch-size) (plusp batch-size))
    (block-validation-fail
     "Chain database rebuild batch size must be a positive integer"))
  (let ((source-schema-version (node-store-chain-schema-version source)))
    (unless (= source-schema-version +kv-chain-schema-version+)
      (block-validation-fail
       "Chain database rebuild requires current schema ~D, got ~D"
       +kv-chain-schema-version+ source-schema-version))
    (multiple-value-bind (stored-progress progress-present-p)
        (node-store-read-database-copy-progress target)
      (let ((progress
              (if progress-present-p
                  (node-store-validate-database-copy-progress
                   stored-progress operation source-schema-version)
                  (node-store-start-database-copy
                   target operation source-schema-version after-batch)))
            (source-record-count
              (if progress-present-p
                  (node-store-database-copy-progress-copied-count
                   stored-progress)
                  0)))
        (loop while progress
              do (let ((new-progress
                         (node-store-advance-database-rebuild
                          source target progress batch-size after-batch)))
                   (when new-progress
                     (setf source-record-count
                           (node-store-database-copy-progress-copied-count
                            new-progress)))
                   (setf progress new-progress))
              finally (return (values source-record-count t)))))))

(defun node-store-rebuild-chain-database
    (source target
     &key
       (batch-size +node-store-default-database-copy-batch-size+)
       after-batch)
  "Rebuild redundant records from primary block/receipt data in fresh TARGET.

The source is never modified. Header records, ordered mirrors, and canonical
transaction locations are regenerated; stale instances of those derived kinds
are omitted. The target remains unreadable until a full bounded-memory audit
passes."
  (node-store-run-database-rebuild
   source target :rebuild batch-size after-batch))

(defun node-store-repairable-database-finding-p (finding)
  (member (node-store-database-finding-kind finding)
          '(:header :ordered-block :ordered-header :ordered-receipt
            :ordered-state-history :transaction-location)))

(defun node-store-repair-chain-database
    (source target
     &key
       (batch-size +node-store-default-database-copy-batch-size+)
       after-batch)
  "Repair only safely derivable records into a fresh TARGET.

Primary block, receipt, state, code, canonical-index, or checkpoint damage is
never guessed. Any such finding refuses repair and leaves SOURCE untouched."
  (let* ((findings (node-store-verify-chain-database source))
         (unrepairable
           (find-if-not #'node-store-repairable-database-finding-p findings)))
    (when unrepairable
      (block-validation-fail
       "Chain database defect is not safely repairable: ~A"
       (node-store-database-finding-description unrepairable)))
    (node-store-run-database-rebuild
     source target :repair batch-size after-batch)))

(defun node-store-backup-chain-database
    (source backup
     &key
       (batch-size +node-store-default-database-copy-batch-size+)
       after-batch)
  "Create or resume a bounded byte-exact copy of offline SOURCE in BACKUP."
  (node-store-copy-chain-database
   source backup :backup :batch-size batch-size :after-batch after-batch))

(defun node-store-restore-chain-database
    (backup target
     &key
       (batch-size +node-store-default-database-copy-batch-size+)
       after-batch)
  "Create or resume a bounded byte-exact copy of BACKUP in empty TARGET."
  (node-store-copy-chain-database
   backup target :restore :batch-size batch-size :after-batch after-batch))
