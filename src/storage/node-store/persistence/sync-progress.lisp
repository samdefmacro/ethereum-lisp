(in-package #:ethereum-lisp.node-store.persistence)

;;; Durable peer-download cursors.  A cursor is keyed by the remote devp2p
;;; identity and bound to the database authority and chain identity.  Candidate
;;; export appends it to the same write batch as the block and derived state, so
;;; a durable cursor can never name a candidate omitted by a torn import.

(defconstant +node-store-peer-sync-progress-version+ 1)
(defconstant +node-store-peer-sync-peer-id-size+ 64)

(defstruct (node-store-peer-sync-progress
            (:constructor %make-node-store-peer-sync-progress
                (&key peer-id authority-id chain-id genesis-hash
                      last-number last-hash)))
  (peer-id (make-byte-vector +node-store-peer-sync-peer-id-size+)
           :type byte-vector
           :read-only t)
  (authority-id (zero-hash32) :type hash32 :read-only t)
  (chain-id 0 :type integer :read-only t)
  (genesis-hash (zero-hash32) :type hash32 :read-only t)
  (last-number 0 :type integer :read-only t)
  (last-hash (zero-hash32) :type hash32 :read-only t))

(defun node-store-peer-sync-peer-id-bytes (peer-id)
  (handler-case
      (let ((bytes (ensure-byte-vector peer-id)))
        (unless (= (length bytes) +node-store-peer-sync-peer-id-size+)
          (block-validation-fail
           "Peer sync peer id must contain ~D bytes"
           +node-store-peer-sync-peer-id-size+))
        (copy-seq bytes))
    (block-validation-error (condition)
      (error condition))
    (error ()
      (block-validation-fail
       "Peer sync peer id must be a ~D-byte vector"
       +node-store-peer-sync-peer-id-size+))))

(defun make-node-store-peer-sync-progress
    (&key peer-id authority-id chain-id genesis-hash last-number last-hash)
  (let ((peer-id (node-store-peer-sync-peer-id-bytes peer-id)))
    (unless (hash32-p authority-id)
      (block-validation-fail
       "Peer sync persistence authority id must be a hash32"))
    (unless (uint256-p chain-id)
      (block-validation-fail
       "Peer sync chain id must be a uint256"))
    (unless (hash32-p genesis-hash)
      (block-validation-fail
       "Peer sync genesis hash must be a hash32"))
    (unless (uint64-value-p last-number)
      (block-validation-fail
       "Peer sync last block number must be a uint64"))
    (unless (hash32-p last-hash)
      (block-validation-fail
       "Peer sync last block hash must be a hash32"))
    (%make-node-store-peer-sync-progress
     :peer-id peer-id
     :authority-id authority-id
     :chain-id chain-id
     :genesis-hash genesis-hash
     :last-number last-number
     :last-hash last-hash)))

(defun node-store-peer-sync-progress-record-rlp (progress)
  (unless (node-store-peer-sync-progress-p progress)
    (block-validation-fail
     "Peer sync progress export requires a progress record"))
  (rlp-encode
   (make-rlp-list
    +node-store-peer-sync-progress-version+
    (node-store-peer-sync-progress-peer-id progress)
    (hash32-bytes
     (node-store-peer-sync-progress-authority-id progress))
    (node-store-peer-sync-progress-chain-id progress)
    (hash32-bytes
     (node-store-peer-sync-progress-genesis-hash progress))
    (node-store-peer-sync-progress-last-number progress)
    (hash32-bytes
     (node-store-peer-sync-progress-last-hash progress)))))

(defun node-store-peer-sync-progress-from-record (record)
  (handler-case
      (let ((fields
              (rlp-list-field
               (rlp-decode-one record) "Peer sync progress record")))
        (unless (= (length fields) 7)
          (block-validation-fail
           "Peer sync progress record must contain 7 fields"))
        (let ((version
                (rlp-uint-field
                 (first fields) "Peer sync progress version"))
              (peer-id
                (rlp-sized-bytes-field
                 (second fields)
                 +node-store-peer-sync-peer-id-size+
                 "Peer sync peer id"))
              (authority-id
                (make-hash32
                 (rlp-sized-bytes-field
                  (third fields) 32
                  "Peer sync persistence authority id")))
              (chain-id
                (rlp-uint-field
                 (fourth fields) "Peer sync chain id"))
              (genesis-hash
                (make-hash32
                 (rlp-sized-bytes-field
                  (fifth fields) 32 "Peer sync genesis hash")))
              (last-number
                (rlp-uint-field
                 (sixth fields) "Peer sync last block number"))
              (last-hash
                (make-hash32
                 (rlp-sized-bytes-field
                  (seventh fields) 32 "Peer sync last block hash"))))
          (unless (= version +node-store-peer-sync-progress-version+)
            (block-validation-fail
             "Unsupported peer sync progress version: ~D" version))
          (make-node-store-peer-sync-progress
           :peer-id peer-id
           :authority-id authority-id
           :chain-id chain-id
           :genesis-hash genesis-hash
           :last-number last-number
           :last-hash last-hash)))
    (block-validation-error (condition)
      (error condition))
    (error (condition)
      (block-validation-fail
       "Invalid peer sync progress record: ~A" condition))))

(defun node-store-validate-peer-sync-progress
    (database progress &optional expected-peer-id)
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Peer sync progress source must be a key-value database"))
  (unless (node-store-peer-sync-progress-p progress)
    (block-validation-fail
     "Peer sync progress validation requires a progress record"))
  (let ((peer-id
          (node-store-peer-sync-peer-id-bytes
           (node-store-peer-sync-progress-peer-id progress))))
    (unless (hash32-p
             (node-store-peer-sync-progress-authority-id progress))
      (block-validation-fail
       "Peer sync persistence authority id must be a hash32"))
    (unless (uint256-p (node-store-peer-sync-progress-chain-id progress))
      (block-validation-fail
       "Peer sync chain id must be a uint256"))
    (unless (hash32-p
             (node-store-peer-sync-progress-genesis-hash progress))
      (block-validation-fail
       "Peer sync genesis hash must be a hash32"))
    (unless (uint64-value-p
             (node-store-peer-sync-progress-last-number progress))
      (block-validation-fail
       "Peer sync last block number must be a uint64"))
    (unless (hash32-p (node-store-peer-sync-progress-last-hash progress))
      (block-validation-fail
       "Peer sync last block hash must be a hash32"))
    (when expected-peer-id
      (unless (bytes= peer-id
                      (node-store-peer-sync-peer-id-bytes expected-peer-id))
        (block-validation-fail
         "Peer sync progress record does not match its peer key"))))
  (multiple-value-bind (metadata present-p)
      (node-store-read-persistence-metadata database)
    (unless present-p
      (block-validation-fail
       "Peer sync progress requires versioned database persistence metadata"))
    (unless (eq (node-store-persistence-metadata-role metadata) :database)
      (block-validation-fail
       "Peer sync progress requires database persistence authority"))
    (unless (and
             (hash32=
              (node-store-persistence-metadata-authority-id metadata)
              (node-store-peer-sync-progress-authority-id progress))
             (= (node-store-persistence-metadata-chain-id metadata)
                (node-store-peer-sync-progress-chain-id progress))
             (hash32=
              (node-store-persistence-metadata-genesis-hash metadata)
              (node-store-peer-sync-progress-genesis-hash progress)))
      (block-validation-fail
       "Peer sync progress persistence identity changed")))
  progress)

(defun node-store-read-peer-sync-progress (database peer-id)
  "Point-read and validate the durable progress for PEER-ID."
  (let ((peer-id (node-store-peer-sync-peer-id-bytes peer-id)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Peer sync progress source must be a key-value database"))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record database :peer-sync-progress peer-id)
      (if present-p
          (values
           (node-store-validate-peer-sync-progress
            database
            (node-store-peer-sync-progress-from-record record)
            peer-id)
           t)
          (values nil nil)))))

(defun node-store-delete-peer-sync-progress (database peer-id)
  "Atomically delete PEER-ID's obsolete cursor after validating its identity.

This is used only when Engine forkchoice has moved the canonical anchor onto a
branch that the old peer cursor does not descend from.  The next successfully
executed candidate installs its replacement cursor in that candidate's WAL
batch; a crash between deletion and replacement safely resumes from canonical."
  (let ((peer-id (node-store-peer-sync-peer-id-bytes peer-id)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Peer sync progress target must be a key-value database"))
    (multiple-value-bind (progress present-p)
        (node-store-read-peer-sync-progress database peer-id)
      (declare (ignore progress))
      (when present-p
        (let ((batch (make-kv-write-batch)))
          (kv-batch-delete-chain-record
           batch :peer-sync-progress peer-id)
          (kv-apply-batch database batch)))
      present-p)))

(defun node-store-peer-sync-progress-same-identity-p (left right)
  (and
   (bytes= (node-store-peer-sync-progress-peer-id left)
           (node-store-peer-sync-progress-peer-id right))
   (hash32= (node-store-peer-sync-progress-authority-id left)
            (node-store-peer-sync-progress-authority-id right))
   (= (node-store-peer-sync-progress-chain-id left)
      (node-store-peer-sync-progress-chain-id right))
   (hash32= (node-store-peer-sync-progress-genesis-hash left)
            (node-store-peer-sync-progress-genesis-hash right))))

(defun node-store-populate-peer-sync-progress-batch
    (database batch progress)
  "Append PROGRESS to BATCH, refusing identity changes or cursor regression.

Returns true when BATCH gained an operation."
  (unless (typep batch 'kv-write-batch)
    (block-validation-fail
     "Peer sync progress target must be a KV write batch"))
  (node-store-validate-peer-sync-progress database progress)
  (let* ((peer-id (node-store-peer-sync-progress-peer-id progress))
         (desired-record
           (node-store-peer-sync-progress-record-rlp progress)))
    (multiple-value-bind (existing-record present-p)
        (kv-get-chain-record database :peer-sync-progress peer-id)
      (when present-p
        (let ((existing
                (node-store-validate-peer-sync-progress
                 database
                 (node-store-peer-sync-progress-from-record existing-record)
                 peer-id)))
          (unless (node-store-peer-sync-progress-same-identity-p
                   existing progress)
            (block-validation-fail
             "Peer sync progress identity cannot change"))
          (let ((existing-number
                  (node-store-peer-sync-progress-last-number existing))
                (desired-number
                  (node-store-peer-sync-progress-last-number progress)))
            (when (< desired-number existing-number)
              (block-validation-fail
               "Peer sync progress cannot move backwards"))
            (when (and (= desired-number existing-number)
                       (not
                        (hash32=
                         (node-store-peer-sync-progress-last-hash existing)
                         (node-store-peer-sync-progress-last-hash progress))))
              (block-validation-fail
               "Peer sync progress cannot change hash at the same height"))
            (when (bytes= existing-record desired-record)
              (return-from node-store-populate-peer-sync-progress-batch
                nil))))))
    (kv-batch-put-chain-record
     batch :peer-sync-progress peer-id desired-record)
    t))
