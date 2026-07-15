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
