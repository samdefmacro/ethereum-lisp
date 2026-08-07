(in-package #:ethereum-lisp.node-store.persistence)

;;;; Offline integrity audit of a chain database.
;;;;
;;;; The import path is a fail-stop: it refuses a datadir it cannot
;;;; substantiate, which is the right answer for a node and a useless one for
;;;; the operator holding the datadir. This audit answers the other question --
;;;; WHAT is wrong -- by checking the same record-level invariants and
;;;; collecting every violation instead of signalling the first.
;;;;
;;;; It is read-only. It does not migrate, repair, or open anything, so it is
;;;; safe to point at a database a node has already refused. It is not a
;;;; consensus check: it does not re-execute blocks or recompute state roots,
;;;; and it does not walk diff chains to prove a state resolves. What it does
;;;; establish is that every record decodes, that hash-keyed records are filed
;;;; under the hash they claim, and that every cross-record reference has a
;;;; target.

(defstruct (node-store-database-finding
            (:constructor make-node-store-database-finding
                (kind identifier message)))
  "One defect. KIND is the record kind it was found under (or :SCHEMA-VERSION
for the marker itself), IDENTIFIER the record's key bytes or NIL."
  kind
  identifier
  message)

(defun node-store-database-finding-description (finding)
  (format nil "~(~A~)~@[ ~A~]: ~A"
          (node-store-database-finding-kind finding)
          (let ((identifier (node-store-database-finding-identifier finding)))
            (and identifier (bytes-to-hex identifier)))
          (node-store-database-finding-message finding)))

(defmacro with-node-store-database-finding
    ((findings kind identifier) &body body)
  "Run BODY, turning a validation failure into a finding on FINDINGS.

Every check runs under this: one unreadable record must not end the audit,
because the operator needs the whole picture and the record after it may be
the one that explains the failure."
  (let ((condition (gensym "CONDITION")))
    `(handler-case (progn ,@body)
       (block-validation-error (,condition)
         (push (make-node-store-database-finding
                ,kind ,identifier
                (block-validation-error-message ,condition))
               ,findings)
         nil)
       (rlp-error (,condition)
         (push (make-node-store-database-finding
                ,kind ,identifier
                (format nil "record is not valid RLP: ~A" ,condition))
               ,findings)
         nil))))

(defun node-store-verify-code-records (database findings)
  "Every :CODE record must be filed under the hash of its own body.

This is the whole guarantee content addressing rests on: a reader that trusts
the key would hand out a body the account never had."
  (dolist (entry (kv-chain-record-entries database :code) findings)
    (let ((identifier (car entry)))
      (cond
        ((/= 32 (length identifier))
         (push (make-node-store-database-finding
                :code identifier "code record key is not a 32-byte hash")
               findings))
        ((not (bytes= identifier (node-store-code-reference (cdr entry))))
         (push (make-node-store-database-finding
                :code identifier "code record does not hash to its key")
               findings))))))

(defun node-store-verify-block-records (database findings)
  "Return the known block hashes as a hex set, adding a finding per bad record.

A block record is keyed by its own hash, so a record whose body hashes to
something else is unreachable by every index that points at it."
  (let ((known (make-hash-table :test 'equal)))
    (dolist (entry (kv-chain-record-entries database :block))
      (let ((identifier (car entry)))
        (with-node-store-database-finding (findings :block identifier)
          (let ((block (chain-store-decode-persisted-block-record
                        (cdr entry) "Block record")))
            (if (bytes= identifier (hash32-bytes (block-hash block)))
                (setf (gethash (bytes-to-hex identifier) known) t)
                (push (make-node-store-database-finding
                       :block identifier
                       "block record key does not match its encoded hash")
                      findings))))))
    (values known findings)))

(defun node-store-verify-block-references (database findings known kind)
  "Every record of KIND must name a block the database still holds."
  (dolist (entry (kv-chain-record-entries database kind) findings)
    (unless (gethash (bytes-to-hex (car entry)) known)
      (push (make-node-store-database-finding
             kind (car entry) "record references an unknown block")
            findings))))

(defun node-store-verify-height-ordered-references (database findings known)
  "The height-ordered mirrors are keyed number-then-hash, so the block they
name is the key's tail rather than the whole key."
  (dolist (kind '(:ordered-block :ordered-header :ordered-receipt) findings)
    (dolist (entry (kv-chain-record-entries database kind))
      (with-node-store-database-finding (findings kind (car entry))
        (multiple-value-bind (number hash)
            (kv-chain-height-hash-identifier-values (car entry))
          (unless (gethash (bytes-to-hex hash) known)
            (push (make-node-store-database-finding
                   kind (car entry)
                   (format nil
                           "height ~D record references an unknown block"
                           number))
                  findings)))))))

(defun node-store-verify-canonical-index (database findings known)
  (dolist (entry (kv-chain-canonical-hashes database) findings)
    (unless (gethash (bytes-to-hex (cdr entry)) known)
      (push (make-node-store-database-finding
             :canonical-hash (cdr entry)
             (format nil "canonical height ~D references an unknown block"
                     (car entry)))
            findings))))

(defun node-store-verify-checkpoints (database findings known)
  (dolist (entry (kv-chain-checkpoints database) findings)
    (unless (gethash (bytes-to-hex (cdr entry)) known)
      (push (make-node-store-database-finding
             :checkpoint (cdr entry)
             (format nil "~(~A~) checkpoint references an unknown block"
                     (car entry)))
            findings))))

(defun node-store-verify-state-code-references (database findings resolver)
  "Decode every account record's code field under RESOLVER.

That resolution is the check: it fails when a reference is not 32 bytes, when
no body is stored under it, or when the stored body does not hash back to it."
  (dolist (kind '(:state :staged-state))
    (dolist (entry (kv-chain-record-entries database kind))
      (with-node-store-database-finding (findings kind (car entry))
        (dolist (account (rlp-list-field (rlp-decode-one (cdr entry))
                                         "State snapshot"))
          (state-account-snapshot-from-rlp-object account resolver)))))
  (dolist (entry (kv-chain-record-entries database :state-diff) findings)
    (with-node-store-database-finding (findings :state-diff (car entry))
      (let ((fields (rlp-list-field (rlp-decode-one (cdr entry))
                                    "State diff record")))
        (unless (= (length fields) 2)
          (block-validation-fail "State diff record must contain 2 fields"))
        (dolist (account (rlp-list-field (second fields)
                                         "State diff accounts"))
          (chain-store-import-state-diff-account
           account
           (make-hash-table :test 'equal)
           (make-hash-table :test 'equal)
           (make-hash-table :test 'equal)
           (make-hash-table :test 'equal)
           resolver))))))

(defun node-store-verify-chain-database (database)
  "Audit DATABASE and return its findings, in the order they were found.

An empty list means every record decoded, every hash-keyed record was filed
under its own hash, and every cross-record reference had a target. It does not
mean the chain is valid -- see the header of this file for what is out of
scope. An unreadable schema marker is reported alone, because nothing after it
can be interpreted without knowing the layout."
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Chain database audit requires a key-value database"))
  (let ((findings '()))
    (let ((version
            (with-node-store-database-finding
                (findings :schema-version nil)
              (node-store-chain-schema-version database))))
      (unless version
        (return-from node-store-verify-chain-database (nreverse findings)))
      (setf findings (node-store-verify-code-records database findings))
      (multiple-value-bind (known block-findings)
          (node-store-verify-block-records database findings)
        (setf findings block-findings)
        (dolist (kind '(:header :receipt :state :state-diff :block-access-list))
          (setf findings
                (node-store-verify-block-references
                 database findings known kind)))
        (setf findings
              (node-store-verify-height-ordered-references
               database findings known))
        (setf findings
              (node-store-verify-canonical-index database findings known))
        (setf findings
              (node-store-verify-checkpoints database findings known)))
      (setf findings
            (node-store-verify-state-code-references
             database findings
             (when (node-store-content-addressed-code-p version)
               (node-store-database-code-resolver database)))))
    (nreverse findings)))
