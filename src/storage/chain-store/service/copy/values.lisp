(in-package #:ethereum-lisp.chain-store)

(defun engine-payload-store-copy-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun engine-payload-store-copy-checkpoint (checkpoint)
  (when checkpoint
    (make-chain-store-checkpoint
     :label (chain-store-checkpoint-label checkpoint)
     :block-hash (chain-store-checkpoint-block-hash checkpoint))))

(defun engine-payload-store-copy-filter (filter)
  (cond
    ((typep filter 'engine-log-filter)
     (make-engine-log-filter
      :criteria (copy-tree (engine-log-filter-criteria filter))
      :last-block-number (engine-log-filter-last-block-number filter)
      :pending-changes
      (copy-list (engine-log-filter-pending-changes filter))
      :block-hash-p
      (engine-log-filter-block-hash-p filter)
      :block-hash-consumed-p
      (engine-log-filter-block-hash-consumed-p filter)
      :deadline (engine-log-filter-deadline filter)))
    ((typep filter 'engine-block-filter)
     (make-engine-block-filter
      :last-block-number (engine-block-filter-last-block-number filter)
      :hashes (copy-list (engine-block-filter-hashes filter))
      :deadline (engine-block-filter-deadline filter)))
    ((typep filter 'engine-pending-transaction-filter)
     (make-engine-pending-transaction-filter
      :hashes (copy-list
               (engine-pending-transaction-filter-hashes filter))
      :deadline (engine-pending-transaction-filter-deadline filter)))
    (t filter)))

(defun engine-payload-store-copy-filter-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-filter value)))
             table)
    copy))

(defun engine-payload-store-copy-blob-and-proofs (blob-and-proofs)
  (cond
    ((typep blob-and-proofs 'engine-blob-and-proofs)
     (make-engine-blob-and-proofs
      :blob (maybe-copy-bytes
             (engine-blob-and-proofs-blob blob-and-proofs))
      :commitment (maybe-copy-bytes
                   (engine-blob-and-proofs-commitment blob-and-proofs))
      :proof (maybe-copy-bytes
              (engine-blob-and-proofs-proof blob-and-proofs))
      :cell-proofs
      (mapcar #'maybe-copy-bytes
              (engine-blob-and-proofs-cell-proofs blob-and-proofs))))
    (t blob-and-proofs)))

(defun engine-payload-store-copy-blob-sidecar-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-blob-and-proofs value)))
             table)
    copy))

(defun engine-payload-store-copy-cache-metadata-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash
     (lambda (key metadata)
       (setf (gethash key copy)
             (make-chain-store-cache-entry-metadata
              :inserted-at
              (chain-store-cache-entry-metadata-inserted-at metadata)
              :encoded-bytes
              (chain-store-cache-entry-metadata-encoded-bytes metadata)
              :block-number
              (chain-store-cache-entry-metadata-block-number metadata))))
     table)
    copy))

(defun maybe-copy-hash32 (hash)
  (when hash
    (make-hash32 (copy-seq (hash32-bytes hash)))))

(defun maybe-copy-address (address)
  (when address
    (make-address (copy-seq (address-bytes address)))))
