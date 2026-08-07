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
            (:constructor make-node-store-code-sink (batch)))
  "Collects the contract bodies referenced while one write batch is built.
BODIES is keyed by reference hex so a body shared by many accounts, blocks, or
diffs in the same batch is encoded and written exactly once."
  batch
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
                (kv-batch-put-chain-record
                 (node-store-code-sink-batch sink) :code reference code))))
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

(defun node-store-chain-schema-version (database)
  "DATABASE's effective on-disk chain schema version.

A database with no marker predates it and reads as the oldest supported
version. A marker this client cannot read is refused here, before any record
is interpreted under the wrong layout."
  (multiple-value-bind (version present-p)
      (node-store-require-supported-schema-version database)
    (if present-p version +node-store-minimum-supported-schema-version+)))

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
;;; record can be renormalized on the way through.

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

(defun node-store-populate-chain-schema-migration-batch
    (database batch version)
  (let ((code-sink (make-node-store-code-sink batch)))
    (unless (node-store-content-addressed-code-p version)
      (dolist (kind '(:state :staged-state))
        (dolist (entry (kv-chain-record-entries database kind))
          (kv-batch-put-chain-record
           batch kind (car entry)
           (node-store-migrated-state-record (cdr entry) code-sink))))
      (dolist (entry (kv-chain-record-entries database :state-diff))
        (kv-batch-put-chain-record
         batch :state-diff (car entry)
         (node-store-migrated-state-diff-record (cdr entry) code-sink)))))
  batch)

(defun node-store-migrate-chain-schema (database)
  "Bring DATABASE's on-disk chain schema up to +KV-CHAIN-SCHEMA-VERSION+.

Returns the resulting version and whether anything was rewritten. A database
already at the current version is left untouched, so this is cheap enough to
guard every durable write path; one newer than this client is refused by the
version read rather than rewritten.

The whole rewrite and the new marker are one batch. The batch is the client's
unit of durability, so a crash leaves either every record in the old layout
under the old marker or every record in the new layout under the new one --
never accounts whose code field means something other than what the marker
says. The cost of that guarantee is that the batch is proportional to the
retained state; a resumable chunked migration would need a second marker
naming how far it got, which is future work rather than something this
version needs."
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Chain schema migration requires a key-value database"))
  (let ((version (node-store-chain-schema-version database)))
    (when (>= version +kv-chain-schema-version+)
      (return-from node-store-migrate-chain-schema (values version nil)))
    (let ((batch (make-kv-write-batch)))
      (handler-case
          (node-store-populate-chain-schema-migration-batch
           database batch version)
        (rlp-error (condition)
          (block-validation-fail
           "Invalid record RLP while migrating chain schema ~D to ~D: ~A"
           version +kv-chain-schema-version+ condition)))
      (kv-batch-put-chain-schema-version batch)
      (kv-apply-batch database batch)
      (values +kv-chain-schema-version+ t))))
