(in-package #:ethereum-lisp.node-store.persistence)

;;;; Content-addressed contract code.
;;;;
;;;; From chain schema version 3, a contract body is stored ONCE per Keccak
;;;; hash under the :CODE record kind, and the account records that reference
;;;; it -- :STATE and :STAGED-STATE snapshots, and :STATE-DIFF records --
;;;; carry the 32-byte hash in place of the body. Before version 3 those
;;;; records embedded the body directly, so the same contract was written once
;;;; per account, once per block snapshot, and once per diff that touched it.
;;;;
;;;; The two layouts are indistinguishable by inspection: a pre-v3 body can
;;;; itself be 32 bytes long. Which one a record uses is therefore decided
;;;; solely by the on-disk :SCHEMA-VERSION marker, never guessed from the
;;;; bytes. NODE-STORE-MIGRATE-CHAIN-SCHEMA rewrites a pre-v3 database
;;;; forward, and NODE-STORE-REQUIRE-SUPPORTED-SCHEMA-VERSION refuses one
;;;; written by a newer client.
;;;;
;;;; :CODE records are never deleted. Code is immutable and shared by every
;;;; block that references it, so retention cannot decide locally that a body
;;;; is unreachable; a reference with no record is a hard read failure rather
;;;; than an empty account.

(defconstant +node-store-content-addressed-code-schema-version+ 3
  "The first chain schema version whose account records reference code by
hash instead of embedding it.")

(defconstant +node-store-trie-state-schema-version+ 4
  "The first chain schema version whose retained flat states have matching
hash-addressed account-trie roots and nodes in :STATE-HISTORY/:TRIE-NODE.")

;; The implementation lives with the state record decoder, which loads later
;; in this serial persistence module.  Migration only runs after the whole
;; system is loaded; declaring the call contract keeps compile output clean.
(declaim
 (ftype (function (t t t t) list)
        node-store-populate-trie-history-migration-record))

(defparameter +node-store-chain-schema-migration-progress-identifier+
  "schema-migration")

(defparameter +node-store-database-copy-progress-identifier+
  "database-copy")

(defun node-store-incomplete-database-operation (database &key except)
  "Return the private marker naming an incomplete database operation.

EXCEPT lets the implementation of that operation inspect its own intermediate
layout while every ordinary reader still refuses it."
  (dolist (identifier
            (list +node-store-chain-schema-migration-progress-identifier+
                  +node-store-database-copy-progress-identifier+))
    (unless (and except (string= except identifier))
      (multiple-value-bind (record present-p)
          (kv-get-chain-record database :metadata identifier)
        (declare (ignore record))
        (when present-p
          (return identifier))))))

(defun node-store-content-addressed-code-p (schema-version)
  (>= schema-version +node-store-content-addressed-code-schema-version+))

(defun node-store-code-reference (code)
  "The stored reference for CODE: its 32-byte Keccak hash, or empty bytes when
the account has no code. An empty reference needs no :CODE record."
  (let ((code (ensure-byte-vector code)))
    (if (plusp (length code))
        (hash32-bytes (keccak-256-hash code))
        (make-byte-vector 0))))

;;; Writing.

(defstruct (node-store-code-sink
            (:constructor make-node-store-code-sink (batch &optional database)))
  "Collects the contract bodies referenced while one write batch is built.
BODIES is keyed by reference hex so a body shared by many accounts, blocks, or
diffs in the same batch is encoded and written exactly once."
  batch
  database
  (bodies (make-hash-table :test 'equal)))

(defun node-store-code-sink-put (sink code)
  "Record CODE in SINK and return the reference to store in its place.

Without a SINK the caller wants the pre-v3 layout, so the body is its own
reference. That path exists for the migration's read side and for tests that
must produce records in the shape the migration actually has to read."
  (let ((code (ensure-byte-vector code)))
    (if (null sink)
        code
        (let ((reference (node-store-code-reference code)))
          (when (plusp (length reference))
            (let ((key (bytes-to-hex reference)))
              (unless (gethash key (node-store-code-sink-bodies sink))
                (setf (gethash key (node-store-code-sink-bodies sink)) code)
                (let ((database (node-store-code-sink-database sink)))
                  (if database
                      (multiple-value-bind (existing present-p)
                          (kv-get-chain-record database :code reference)
                        (cond
                          ((not present-p)
                           (kv-batch-put-chain-record
                            (node-store-code-sink-batch sink)
                            :code reference code))
                          ((not (bytes= existing code))
                           (block-validation-fail
                            "Persisted code collides with content hash ~A"
                            (bytes-to-hex reference)))))
                      (kv-batch-put-chain-record
                       (node-store-code-sink-batch sink)
                       :code reference code))))))
          reference))))

(defun node-store-code-sink-resolver (sink database)
  "A resolver seeing SINK's not-yet-applied bodies before DATABASE's records.

A record is validated in the same step that builds it, before its batch is
applied, so the bodies it references exist only in the sink at that point."
  (let ((database-resolver (node-store-database-code-resolver database)))
    (lambda (reference label)
      (let ((body (and (plusp (length reference))
                       (gethash (bytes-to-hex reference)
                                (node-store-code-sink-bodies sink)))))
        (or body (funcall database-resolver reference label))))))

;;; Reading.

(defun node-store-database-code-resolver (database)
  "A resolver reading contract bodies from DATABASE's :CODE records."
  (lambda (reference label)
    (multiple-value-bind (code present-p)
        (kv-get-chain-record database :code reference)
      (unless present-p
        (block-validation-fail
         "~A references contract code ~A that is not stored"
         label (bytes-to-hex reference)))
      code)))

(defun node-store-resolve-code (resolver reference label)
  "Resolve one stored code field.

RESOLVER decides the layout: NIL means the pre-v3 inline body, where the field
IS the code. Otherwise the field is a 32-byte content address, and the body it
names is re-hashed on the way out -- the record and the body are separate keys,
so nothing but the hash ties them together."
  (let ((reference (ensure-byte-vector reference)))
    (cond
      ((null resolver) reference)
      ((zerop (length reference)) (make-byte-vector 0))
      (t
       (unless (= 32 (length reference))
         (block-validation-fail
          "~A code reference must be empty or exactly 32 bytes" label))
       (let ((code (ensure-byte-vector (funcall resolver reference label))))
         (unless (bytes= reference (node-store-code-reference code))
           (block-validation-fail
            "~A code record does not hash to its content address" label))
         code)))))

(defun node-store-uninterrupted-chain-schema-version (database)
  "DATABASE's effective on-disk chain schema version.

A database with no marker predates it and reads as the oldest supported
version. A marker this client cannot read is refused here, before any record
is interpreted under the wrong layout."
  (multiple-value-bind (version present-p)
      (node-store-require-supported-schema-version database)
    (if present-p version +node-store-minimum-supported-schema-version+)))

(defun node-store-chain-schema-version (database)
  "Return DATABASE's schema version, refusing an interrupted operation.

Records rewritten by a chunked migration deliberately remain under the old
schema marker until the last batch. They are safe only while the migration
progress record prevents ordinary readers from interpreting the mixed layout.
The same rule protects a partially copied backup or restore target."
  (let ((operation (node-store-incomplete-database-operation database)))
    (when operation
      (block-validation-fail
       "Chain database operation ~A is incomplete; resume it before reading records"
       operation)))
  (node-store-uninterrupted-chain-schema-version database))

(defun node-store-code-resolver-for-database (database)
  "The resolver matching DATABASE's on-disk layout, or NIL when it predates
content-addressed code."
  (when (node-store-content-addressed-code-p
         (node-store-chain-schema-version database))
    (node-store-database-code-resolver database)))

;;; Forward migration.
;;;
;;; The rewrite is structural: every field but the code field is carried
;;; across as the decoded RLP item it already was, so nothing else in the
;;; record can be renormalized on the way through. Progress advances in the
;;; SAME batch as each chunk. The public schema marker remains at the source
;;; version until the final batch, so ordinary readers refuse the mixed layout
;;; while a restart can resume exactly after the last durable key.

(defconstant +node-store-chain-schema-migration-progress-version+ 1)

(defparameter +node-store-default-schema-migration-batch-size+ 1024
  "Maximum source records rewritten by one durable migration batch.")

(defstruct (node-store-chain-schema-migration-progress
            (:constructor make-node-store-chain-schema-migration-progress
                (&key source-version target-version step-index cursor)))
  source-version
  target-version
  step-index
  cursor)

(defun node-store-chain-schema-migration-progress-record (progress)
  (rlp-encode
   (make-rlp-list
    +node-store-chain-schema-migration-progress-version+
    (node-store-chain-schema-migration-progress-source-version progress)
    (node-store-chain-schema-migration-progress-target-version progress)
    (node-store-chain-schema-migration-progress-step-index progress)
    (node-store-chain-schema-migration-progress-cursor progress))))

(defun node-store-chain-schema-migration-progress-from-record (record)
  (handler-case
      (let ((fields
              (rlp-list-field
               (rlp-decode-one record) "Chain schema migration progress")))
        (unless (= 5 (length fields))
          (block-validation-fail
           "Chain schema migration progress must contain 5 fields"))
        (let ((record-version
                (rlp-uint-field
                 (first fields) "Chain schema migration progress version"))
              (source-version
                (rlp-uint-field
                 (second fields) "Chain schema migration source version"))
              (target-version
                (rlp-uint-field
                 (third fields) "Chain schema migration target version"))
              (step-index
                (rlp-uint-field
                 (fourth fields) "Chain schema migration step index"))
              (cursor
                (rlp-bytes-field
                 (fifth fields) "Chain schema migration cursor")))
          (unless (= record-version
                     +node-store-chain-schema-migration-progress-version+)
            (block-validation-fail
             "Unsupported chain schema migration progress version: ~D"
             record-version))
          (make-node-store-chain-schema-migration-progress
           :source-version source-version
           :target-version target-version
           :step-index step-index
           :cursor cursor)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid chain schema migration progress RLP: ~A" condition))))

(defun node-store-read-chain-schema-migration-progress (database)
  (multiple-value-bind (record present-p)
      (kv-get-chain-record
       database :metadata
       +node-store-chain-schema-migration-progress-identifier+)
    (if present-p
        (values
         (node-store-chain-schema-migration-progress-from-record record)
         t)
        (values nil nil))))

(defun node-store-put-chain-schema-migration-progress (batch progress)
  (kv-batch-put-chain-record
   batch :metadata
   +node-store-chain-schema-migration-progress-identifier+
   (node-store-chain-schema-migration-progress-record progress)))

(defun node-store-delete-chain-schema-migration-progress (batch)
  (kv-batch-delete-chain-record
   batch :metadata
   +node-store-chain-schema-migration-progress-identifier+))

(defun node-store-chain-schema-migration-steps (source-version)
  "The ordered rewrites required to bring SOURCE-VERSION to the current one."
  (append
   (when (< source-version 2) '(:ordered-records))
   (when (< source-version +node-store-content-addressed-code-schema-version+)
     '(:state :staged-state :state-diff))
   ;; Ordered records exist by schema 2.  Processing them in height order lets
   ;; a diff open its already-migrated parent root without reconstructing the
   ;; world or retaining migration state in memory across chunks.
   (when (< source-version +node-store-trie-state-schema-version+)
     '(:trie-history))))

(defun node-store-validate-chain-schema-migration-progress
    (progress marker-version steps)
  (unless (= marker-version
             (node-store-chain-schema-migration-progress-source-version
              progress))
    (block-validation-fail
     "Chain schema migration source ~D does not match marker ~D"
     (node-store-chain-schema-migration-progress-source-version progress)
     marker-version))
  (unless (= +kv-chain-schema-version+
             (node-store-chain-schema-migration-progress-target-version
              progress))
    (block-validation-fail
     "Chain schema migration target ~D is not this client's schema ~D"
     (node-store-chain-schema-migration-progress-target-version progress)
     +kv-chain-schema-version+))
  (unless (<= 0
              (node-store-chain-schema-migration-progress-step-index progress)
              (length steps))
    (block-validation-fail
     "Chain schema migration step index is out of range"))
  progress)

(defun node-store-chain-schema-migration-step-kind (step)
  (case step
    (:ordered-records :block)
    (:trie-history :ordered-block)
    (t step)))

(defun node-store-chain-schema-migration-chunk
    (database step cursor batch-size)
  "Return up to BATCH-SIZE source records after CURSOR for STEP.

Each result is (FULL-KEY VALUE). The iterator is explicitly closed because a
RocksDB scan stopped at a chunk boundary otherwise pins a native iterator and
its database resources until process exit."
  (let* ((kind (node-store-chain-schema-migration-step-kind step))
         (start (if (plusp (length cursor))
                    cursor
                    (kv-chain-record-kind-start-key kind)))
         (end (kv-chain-record-kind-end-key kind))
         (records '())
         (record-count 0))
    (multiple-value-bind (iterator close-iterator)
        (kv-iterator database :start start :end end)
      (unwind-protect
           (loop while (< record-count batch-size)
                 do (multiple-value-bind (key value present-p)
                        (funcall iterator)
                      (unless present-p
                        (return))
                      ;; START is inclusive. The progress cursor names the
                      ;; last durable key, so skip it once on resume.
                      (unless (and (plusp (length cursor))
                                   (bytes= key cursor))
                        (push (list key value) records)
                        (incf record-count))))
        (when close-iterator
          (funcall close-iterator))))
    (nreverse records)))

(defun node-store-populate-ordered-record-migration
    (database batch full-key record)
  (let* ((identifier
           (kv-chain-record-key-identifier :block full-key))
         (block
           (chain-store-decode-persisted-block-record
            record "Block record during schema migration")))
    (unless (bytes= identifier (hash32-bytes (block-hash block)))
      (block-validation-fail
       "Block record key does not match its encoded hash during migration"))
    (let ((ordered-identifier
            (kv-chain-height-hash-identifier
             (block-header-number (block-header block)) identifier)))
      (kv-batch-put-chain-record
       batch :ordered-block ordered-identifier record)
      (multiple-value-bind (header present-p)
          (kv-get-chain-record database :header identifier)
        (when present-p
          (kv-batch-put-chain-record
           batch :ordered-header ordered-identifier header)))
      (multiple-value-bind (receipts present-p)
          (kv-get-chain-record database :receipt identifier)
        (when present-p
          (kv-batch-put-chain-record
           batch :ordered-receipt ordered-identifier receipts))))))

(defun node-store-migrated-state-record (record code-sink)
  "Rewrite a pre-v3 account snapshot so each account references its code."
  (rlp-encode
   (apply #'make-rlp-list
          (mapcar
           (lambda (account)
             (let ((fields
                     (rlp-list-field account "State account snapshot")))
               (unless (= (length fields) 5)
                 (block-validation-fail
                  "State account snapshot must contain 5 fields"))
               (make-rlp-list
                (first fields)
                (second fields)
                (third fields)
                (node-store-code-sink-put
                 code-sink
                 (rlp-bytes-field (fourth fields)
                                  "State account snapshot code"))
                (fifth fields))))
           (rlp-list-field (rlp-decode-one record) "State snapshot")))))

(defun node-store-migrated-state-diff-record (record code-sink)
  "Rewrite a pre-v3 state diff so its code field carries a reference.

The unchanged and tombstone tags carry an empty placeholder, whose reference
is also empty, so the tag itself needs no special case."
  (let ((fields (rlp-list-field (rlp-decode-one record) "State diff record")))
    (unless (= (length fields) 2)
      (block-validation-fail "State diff record must contain 2 fields"))
    (rlp-encode
     (make-rlp-list
      (first fields)
      (apply #'make-rlp-list
             (mapcar
              (lambda (account)
                (let ((account-fields
                        (rlp-list-field account "State diff account")))
                  (unless (= (length account-fields) 8)
                    (block-validation-fail
                     "State diff account must contain 8 fields"))
                  (make-rlp-list
                   (first account-fields)
                   (second account-fields)
                   (third account-fields)
                   (fourth account-fields)
                   (fifth account-fields)
                   (sixth account-fields)
                   (node-store-code-sink-put
                    code-sink
                    (rlp-bytes-field (seventh account-fields)
                                     "State diff code"))
                   (eighth account-fields))))
              (rlp-list-field (second fields) "State diff accounts")))))))

(defun node-store-populate-chain-schema-migration-record
    (database batch step full-key record code-sink)
  (ecase step
    (:ordered-records
     (node-store-populate-ordered-record-migration
      database batch full-key record)
     nil)
    ((:state :staged-state)
     (kv-batch-put-chain-record
      batch step (kv-chain-record-key-identifier step full-key)
      (node-store-migrated-state-record record code-sink))
     nil)
    (:state-diff
     (kv-batch-put-chain-record
      batch :state-diff
      (kv-chain-record-key-identifier :state-diff full-key)
      (node-store-migrated-state-diff-record record code-sink))
     nil)
    (:trie-history
     (node-store-populate-trie-history-migration-record
      database batch full-key record))))

(defun node-store-call-schema-migration-batch-hook (hook progress)
  (when hook
    (funcall hook progress)))

(defun node-store-start-chain-schema-migration
    (database source-version hook)
  (let* ((progress
           (make-node-store-chain-schema-migration-progress
            :source-version source-version
            :target-version +kv-chain-schema-version+
            :step-index 0
            :cursor (make-byte-vector 0)))
         (batch (make-kv-write-batch)))
    (node-store-put-chain-schema-migration-progress batch progress)
    (kv-apply-batch database batch)
    (node-store-call-schema-migration-batch-hook hook progress)
    progress))

(defun node-store-advance-chain-schema-migration
    (database progress steps batch-size hook)
  "Apply one durable migration chunk and return the new progress.

NIL means the final marker batch completed and no progress record remains."
  (let ((step-index
          (node-store-chain-schema-migration-progress-step-index progress)))
    (when (= step-index (length steps))
      (let ((batch (make-kv-write-batch)))
        (kv-batch-put-chain-schema-version batch)
        (node-store-delete-chain-schema-migration-progress batch)
        (kv-apply-batch database batch)
        (node-store-call-schema-migration-batch-hook hook nil)
        (return-from node-store-advance-chain-schema-migration nil)))
    (let* ((step (nth step-index steps))
           (cursor
             (node-store-chain-schema-migration-progress-cursor progress))
           (records
             (node-store-chain-schema-migration-chunk
              database step cursor
              ;; A diff opens its parent's nodes from DATABASE.  Keeping this
              ;; step to one ordered block per durable batch makes the parent
              ;; visible before its child without retaining a cross-batch
              ;; migration cache.  Other structural rewrites still use the
              ;; caller's full chunk size.
              (if (eq step :trie-history) 1 batch-size)))
           (batch (make-kv-write-batch))
           (code-sink (make-node-store-code-sink batch database))
           (pending-trie-nodes nil)
           (new-progress
             (if records
                 (make-node-store-chain-schema-migration-progress
                  :source-version
                  (node-store-chain-schema-migration-progress-source-version
                   progress)
                  :target-version +kv-chain-schema-version+
                  :step-index step-index
                  :cursor (caar (last records)))
                 (make-node-store-chain-schema-migration-progress
                  :source-version
                  (node-store-chain-schema-migration-progress-source-version
                   progress)
                  :target-version +kv-chain-schema-version+
                  :step-index (1+ step-index)
                  :cursor (make-byte-vector 0)))))
      (handler-case
          (dolist (entry records)
            (setf pending-trie-nodes
                  (nconc
                   pending-trie-nodes
                   (node-store-populate-chain-schema-migration-record
                    database batch step (first entry) (second entry)
                    code-sink))))
        (rlp-error (condition)
          (block-validation-fail
           "Invalid record RLP while migrating chain schema ~D to ~D: ~A"
           (node-store-chain-schema-migration-progress-source-version progress)
           +kv-chain-schema-version+
           condition)))
      ;; This is the resumability invariant: a rewritten record is never
      ;; durable without the cursor that proves it no longer needs rewriting.
      (node-store-put-chain-schema-migration-progress batch new-progress)
      (kv-apply-batch database batch)
      (mpt-mark-nodes-persisted pending-trie-nodes)
      (node-store-call-schema-migration-batch-hook hook new-progress)
      new-progress)))

(defun node-store-migrate-chain-schema
    (database &key
                (batch-size +node-store-default-schema-migration-batch-size+)
                after-batch)
  "Bring DATABASE's on-disk chain schema up to +KV-CHAIN-SCHEMA-VERSION+.

Returns the resulting version and whether anything was rewritten. A database
already at the current version is left untouched, so this is cheap enough to
guard every durable write path; one newer than this client is refused by the
version read rather than rewritten.

At most BATCH-SIZE source records are rewritten per durable batch. Each batch
also advances a private progress cursor. The public schema marker remains at
the source version until the final batch atomically publishes the target marker
and deletes that cursor. A crash therefore leaves an explicitly unreadable
mixed layout that this function resumes, never one ordinary readers can mistake
for either complete schema.

AFTER-BATCH, when supplied, is called after every durable batch with the new
progress object, or NIL after completion. It is a crash-injection seam: a test
can signal after an arbitrary batch and prove the next call resumes."
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Chain schema migration requires a key-value database"))
  (let ((operation
          (node-store-incomplete-database-operation
           database
           :except +node-store-chain-schema-migration-progress-identifier+)))
    (when operation
      (block-validation-fail
       "Cannot migrate while chain database operation ~A is incomplete"
       operation)))
  (unless (and (integerp batch-size) (plusp batch-size))
    (block-validation-fail
     "Chain schema migration batch size must be a positive integer"))
  (let ((marker-version
          (node-store-uninterrupted-chain-schema-version database)))
    (multiple-value-bind (stored-progress progress-present-p)
        (node-store-read-chain-schema-migration-progress database)
      (when (and (>= marker-version +kv-chain-schema-version+)
                 (not progress-present-p))
        (return-from node-store-migrate-chain-schema
          (values marker-version nil)))
      (let* ((steps
               (node-store-chain-schema-migration-steps marker-version))
             (progress
               (if progress-present-p
                   (node-store-validate-chain-schema-migration-progress
                    stored-progress marker-version steps)
                   (node-store-start-chain-schema-migration
                    database marker-version after-batch))))
        (loop while progress
              do (setf progress
                       (node-store-advance-chain-schema-migration
                        database progress steps batch-size after-batch)))
        (values +kv-chain-schema-version+ t)))))
