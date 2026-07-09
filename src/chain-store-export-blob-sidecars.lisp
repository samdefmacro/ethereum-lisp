(in-package #:ethereum-lisp.core)

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

(defun chain-store-populate-blob-sidecar-export-batch
    (store database batch)
  (let ((current-versioned-hash-keys (make-hash-table :test 'equal)))
    (maphash
     (lambda (versioned-hash-key blob-and-proofs)
       (setf (gethash versioned-hash-key current-versioned-hash-keys) t)
       (chain-store-export-blob-sidecar-to-kv
        batch versioned-hash-key blob-and-proofs))
     (engine-payload-memory-store-blob-sidecars store))
    (dolist (entry (kv-chain-record-entries database :blob-sidecar))
      (unless (gethash (bytes-to-hex (car entry))
                       current-versioned-hash-keys)
        (kv-batch-delete-chain-record
         batch
         :blob-sidecar
         (car entry))))))

(defun chain-store-export-blob-sidecars-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Chain blob-sidecar export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-blob-sidecar-export-batch store database batch)
      (kv-apply-batch database batch))))
