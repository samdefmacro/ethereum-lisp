(in-package #:ethereum-lisp.core)

(defun engine-payload-store-copy-block-header (header)
  (when header
    (make-block-header
     :parent-hash (maybe-copy-hash32 (block-header-parent-hash header))
     :ommers-hash (maybe-copy-hash32 (block-header-ommers-hash header))
     :beneficiary (maybe-copy-address (block-header-beneficiary header))
     :state-root (maybe-copy-hash32 (block-header-state-root header))
     :transactions-root
     (maybe-copy-hash32 (block-header-transactions-root header))
     :receipts-root (maybe-copy-hash32 (block-header-receipts-root header))
     :logs-bloom (maybe-copy-bytes (block-header-logs-bloom header))
     :difficulty (block-header-difficulty header)
     :number (block-header-number header)
     :gas-limit (block-header-gas-limit header)
     :gas-used (block-header-gas-used header)
     :timestamp (block-header-timestamp header)
     :extra-data (maybe-copy-bytes (block-header-extra-data header))
     :mix-hash (maybe-copy-hash32 (block-header-mix-hash header))
     :nonce (maybe-copy-bytes (block-header-nonce header))
     :base-fee-per-gas (block-header-base-fee-per-gas header)
     :withdrawals-root (maybe-copy-hash32 (block-header-withdrawals-root header))
     :blob-gas-used (block-header-blob-gas-used header)
     :excess-blob-gas (block-header-excess-blob-gas header)
     :parent-beacon-root
     (maybe-copy-hash32 (block-header-parent-beacon-root header))
     :requests-hash (maybe-copy-hash32 (block-header-requests-hash header))
     :block-access-list-hash
     (maybe-copy-hash32 (block-header-block-access-list-hash header))
     :slot-number (block-header-slot-number header))))

(defun engine-payload-store-copy-log-entry (log)
  (cond
    ((typep log 'log-entry)
     (make-log-entry
      :address (maybe-copy-address (log-entry-address log))
      :topics (mapcar (lambda (topic)
                        (if (typep topic 'hash32)
                            (maybe-copy-hash32 topic)
                            (maybe-copy-bytes topic)))
                      (log-entry-topics log))
      :data (maybe-copy-bytes (log-entry-data log))))
    (t log)))

(defun engine-payload-store-copy-receipt (receipt)
  (cond
    ((typep receipt 'receipt)
     (make-receipt
      :post-state (maybe-copy-bytes (receipt-post-state receipt))
      :status (receipt-status receipt)
      :cumulative-gas-used (receipt-cumulative-gas-used receipt)
      :logs (mapcar #'engine-payload-store-copy-log-entry
                    (receipt-logs receipt))))
    (t receipt)))

(defun engine-payload-store-copy-block (block)
  (cond
    ((typep block 'ethereum-block)
     (let ((copy (copy-ethereum-block block)))
       (setf (block-header copy)
             (engine-payload-store-copy-block-header (block-header block))
             (block-transactions copy)
             (mapcar (lambda (transaction)
                       (transaction-from-encoding
                        (transaction-encoding transaction)))
                     (block-transactions block))
             (block-receipts copy)
             (mapcar #'engine-payload-store-copy-receipt
                     (block-receipts block))
             (block-ommers copy) (copy-list (block-ommers block))
             (block-withdrawals copy)
             (maybe-copy-withdrawals (block-withdrawals block))
             (block-requests copy) (maybe-copy-requests (block-requests block))
             (block-block-access-list copy)
             (copy-tree (block-block-access-list block))
             (block-encoded-block-access-list copy)
             (maybe-copy-bytes (block-encoded-block-access-list block)))
       copy))
    (t block)))

(defun engine-payload-store-copy-block-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-block value)))
             table)
    copy))

(defun engine-payload-store-copy-prepared-payload (prepared-payload)
  (cond
    ((typep prepared-payload 'engine-prepared-payload)
     (make-engine-prepared-payload
      :payload-id (maybe-copy-bytes
                   (engine-prepared-payload-payload-id prepared-payload))
      :version (engine-prepared-payload-version prepared-payload)
      :block
      (engine-payload-store-copy-block
       (engine-prepared-payload-block prepared-payload))
      :blobs-bundle
      (maybe-copy-blob-sidecar
       (engine-prepared-payload-blobs-bundle prepared-payload))))
    (t prepared-payload)))

(defun engine-payload-store-copy-prepared-payload-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy)
                     (engine-payload-store-copy-prepared-payload value)))
             table)
    copy))

(defun engine-payload-store-copy-transaction (transaction)
  (transaction-from-encoding (transaction-encoding transaction)))
