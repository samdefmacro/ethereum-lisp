(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-blob-sidecar-record-rlp (blob-and-proofs)
  (rlp-encode
   (make-rlp-list
    (engine-blob-and-proofs-blob blob-and-proofs)
    (engine-blob-and-proofs-commitment blob-and-proofs)
    (engine-blob-and-proofs-proof blob-and-proofs)
    (apply #'make-rlp-list
           (engine-blob-and-proofs-cell-proofs blob-and-proofs)))))

(defun chain-store-export-blob-sidecar-to-kv
    (batch versioned-hash-key blob-and-proofs)
  (kv-batch-put-chain-record
   batch
   :blob-sidecar
   (hex-to-bytes versioned-hash-key)
   (chain-store-blob-sidecar-record-rlp blob-and-proofs)))

(defun node-store-put-immutable-blob-sidecar
    (database batch identifier blob-and-proofs)
  (let ((record (chain-store-blob-sidecar-record-rlp blob-and-proofs)))
    (multiple-value-bind (existing present-p)
        (kv-get-chain-record database :blob-sidecar identifier)
      (cond
        ((not present-p)
         (kv-batch-put-chain-record batch :blob-sidecar identifier record)
         t)
        ((bytes= existing record) nil)
        (t
         (block-validation-fail
          "Blob sidecar conflicts with its persisted versioned hash"))))))

(defun node-store-populate-blob-sidecars-for-transactions-batch
    (store database batch transactions &key require-all-p)
  "Add TRANSACTIONS' available blob sidecars to BATCH by versioned hash.

REQUIRE-ALL-P is used for a txpool snapshot: a pooled blob transaction without
its sidecar is not restartable and is refused.  Imported blocks legitimately
arrive without blob bodies, so live block batches leave it false.  Sidecars are
immutable shared content: this helper never sweeps the common namespace because
a transaction leaving the pool does not mean its canonical block stopped
referencing the sidecar.  Offline rebuild is the compaction path."
  (let ((identifiers (make-hash-table :test 'equal))
        (changed-p nil))
    (dolist (transaction transactions)
      (loop for versioned-hash across
              (transaction-blob-versioned-hashes transaction)
            for identifier = (hash32-bytes versioned-hash)
            for key = (bytes-to-hex identifier)
            unless (gethash key identifiers)
              do (setf (gethash key identifiers) t)
                 (let ((blob-and-proofs
                         (engine-payload-store-blob-and-proofs-v1
                          store versioned-hash)))
                   (cond
                     (blob-and-proofs
                      (when (node-store-put-immutable-blob-sidecar
                             database batch identifier blob-and-proofs)
                        (setf changed-p t)))
                     (require-all-p
                      (block-validation-fail
                       "Pooled blob transaction is missing sidecar ~A"
                       key))))))
    changed-p))

(defun chain-store-populate-blob-sidecar-export-batch
    (store database batch)
  (setf store (chain-store-require-memory-store store))
  (let ((current-versioned-hash-keys (make-hash-table :test 'equalp)))
    (maphash
     (lambda (versioned-hash-key blob-and-proofs)
       (setf (gethash versioned-hash-key current-versioned-hash-keys) t)
       (chain-store-export-blob-sidecar-to-kv
        batch versioned-hash-key blob-and-proofs))
     (memory-chain-store-blob-sidecars store))
    (dolist (entry (kv-chain-record-entries database :blob-sidecar))
      (unless (gethash (bytes-to-hex (car entry))
                       current-versioned-hash-keys)
        (kv-batch-delete-chain-record
         batch
         :blob-sidecar
         (car entry))))))

(defun chain-store-export-blob-sidecars-to-kv (store database)
  (chain-store-apply-export-batch
   store database "blob-sidecar"
   #'chain-store-populate-blob-sidecar-export-batch))
