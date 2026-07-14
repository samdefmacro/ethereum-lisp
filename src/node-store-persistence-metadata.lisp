(in-package #:ethereum-lisp.node-store.persistence)

(defconstant +node-store-persistence-metadata-version+ 1)

(defparameter +node-store-persistence-metadata-identifier+
  "txpool-authority")

(defparameter +node-store-persistence-role-names+
  '((:database . "database")
    (:journal . "journal")))

(defstruct (node-store-persistence-metadata
            (:constructor %make-node-store-persistence-metadata
                (&key role generation chain-id genesis-hash authority-id
                      base-chain-generation)))
  role
  generation
  chain-id
  genesis-hash
  authority-id
  base-chain-generation)

(defun make-node-store-persistence-metadata
    (&key role generation chain-id genesis-hash authority-id
          base-chain-generation)
  (unless (assoc role +node-store-persistence-role-names+)
    (block-validation-fail
     "Node persistence metadata role must be :DATABASE or :JOURNAL"))
  (unless (uint64-value-p generation)
    (block-validation-fail
     "Node persistence metadata generation must be a uint64"))
  (unless (uint256-p chain-id)
    (block-validation-fail
     "Node persistence metadata chain id must be a uint256"))
  (unless (hash32-p genesis-hash)
    (block-validation-fail
     "Node persistence metadata genesis hash must be a hash32"))
  (unless (hash32-p authority-id)
    (block-validation-fail
     "Node persistence metadata authority id must be a hash32"))
  (unless (uint64-value-p base-chain-generation)
    (block-validation-fail
     "Node persistence metadata base chain generation must be a uint64"))
  (when (> base-chain-generation generation)
    (block-validation-fail
     "Node persistence metadata base chain generation exceeds generation"))
  (when (and (eq role :database)
             (/= base-chain-generation generation))
    (block-validation-fail
     "Database persistence metadata must be based on its own generation"))
  (%make-node-store-persistence-metadata
   :role role
   :generation generation
   :chain-id chain-id
   :genesis-hash genesis-hash
   :authority-id authority-id
   :base-chain-generation base-chain-generation))

(defun node-store-persistence-role-name (role)
  (or (cdr (assoc role +node-store-persistence-role-names+))
      (block-validation-fail
       "Unknown node persistence metadata role: ~S" role)))

(defun node-store-persistence-role-from-name (name)
  (or (car (rassoc name +node-store-persistence-role-names+
                    :test #'string=))
      (block-validation-fail
       "Unknown node persistence metadata role name: ~S" name)))

(defun node-store-persistence-metadata-record-rlp (metadata)
  (unless (node-store-persistence-metadata-p metadata)
    (block-validation-fail
     "Node persistence metadata export requires metadata"))
  (rlp-encode
   (make-rlp-list
    +node-store-persistence-metadata-version+
    (node-store-persistence-role-name
     (node-store-persistence-metadata-role metadata))
    (node-store-persistence-metadata-chain-id metadata)
    (hash32-bytes
     (node-store-persistence-metadata-genesis-hash metadata))
    (hash32-bytes
     (node-store-persistence-metadata-authority-id metadata))
    (node-store-persistence-metadata-generation metadata)
    (node-store-persistence-metadata-base-chain-generation metadata))))

(defun node-store-persistence-metadata-from-record (record)
  (handler-case
      (let ((fields
              (rlp-list-field
               (rlp-decode-one record)
               "Node persistence metadata record")))
        (unless (= (length fields) 7)
          (block-validation-fail
           "Node persistence metadata record must contain 7 fields"))
        (let ((version
                (rlp-uint-field
                 (first fields) "Node persistence metadata version"))
              (role
                (node-store-persistence-role-from-name
                 (bytes-to-ascii
                  (rlp-bytes-field
                   (second fields) "Node persistence metadata role"))))
              (chain-id
                (rlp-uint-field
                 (third fields) "Node persistence metadata chain id"))
              (genesis-hash
                (make-hash32
                 (rlp-sized-bytes-field
                  (fourth fields)
                  32
                  "Node persistence metadata genesis hash")))
              (authority-id
                (make-hash32
                 (rlp-sized-bytes-field
                  (fifth fields)
                  32
                  "Node persistence metadata authority id")))
              (generation
                (rlp-uint-field
                 (sixth fields) "Node persistence metadata generation"))
              (base-chain-generation
                (rlp-uint-field
                 (seventh fields)
                 "Node persistence metadata base chain generation")))
          (unless (= version +node-store-persistence-metadata-version+)
            (block-validation-fail
             "Unsupported node persistence metadata version: ~D" version))
          (make-node-store-persistence-metadata
           :role role
           :chain-id chain-id
           :genesis-hash genesis-hash
           :authority-id authority-id
           :generation generation
           :base-chain-generation base-chain-generation)))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid node persistence metadata RLP: ~A" condition))))

(defun node-store-read-persistence-metadata (database)
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Node persistence metadata source must be a key-value database"))
  (multiple-value-bind (record present-p)
      (kv-get-chain-record
       database :metadata +node-store-persistence-metadata-identifier+)
    (if present-p
        (values (node-store-persistence-metadata-from-record record) t)
        (values nil nil))))

(defun node-store-require-persistence-metadata-for-versioned-target
    (database metadata record-label)
  (multiple-value-bind (existing-metadata present-p)
      (node-store-read-persistence-metadata database)
    (declare (ignore existing-metadata))
    (when (and present-p (null metadata))
      (block-validation-fail
       "~A export requires persistence metadata for a versioned target"
       record-label)))
  metadata)

(defun node-store-populate-persistence-metadata-batch (batch metadata)
  (when metadata
    (kv-batch-put-chain-record
     batch
     :metadata
     +node-store-persistence-metadata-identifier+
     (node-store-persistence-metadata-record-rlp metadata)))
  batch)
