(in-package #:ethereum-lisp.core)

(defun chain-store-export-to-kv (store database)
  (let ((store (chain-store-require-memory-store store)))
    (unless (typep database 'key-value-database)
      (block-validation-fail "Chain export target must be a key-value database"))
    (let ((batch (make-kv-write-batch)))
      (chain-store-populate-index-export-batch store database batch)
      (chain-store-populate-block-record-export-batch store batch)
      (chain-store-populate-transaction-location-export-batch
       store database batch)
      (chain-store-populate-state-record-export-batch store database batch)
      (chain-store-populate-txpool-record-export-batch store database batch)
      (chain-store-populate-invalid-tipset-export-batch
       store database batch)
      (chain-store-populate-remote-block-export-batch
       store database batch)
      (chain-store-populate-blob-sidecar-export-batch
       store database batch)
      (chain-store-populate-prepared-payload-export-batch
       store database batch)
      (kv-apply-batch database batch))))
