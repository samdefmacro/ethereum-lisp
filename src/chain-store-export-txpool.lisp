(in-package #:ethereum-lisp.chain-store.persistence)

(defparameter +chain-store-txpool-subpool-labels+
  '((:pending . "pending")
    (:queued . "queued")
    (:basefee . "basefee")
    (:blob . "blob")))

(defun chain-store-txpool-subpool-identifier (subpool)
  (let ((name (and (symbolp subpool)
                   (cdr (assoc subpool
                               +chain-store-txpool-subpool-labels+)))))
    (unless name
      (block-validation-fail "Unknown txpool subpool: ~S" subpool))
    name))

(defun chain-store-txpool-subpool-label (identifier)
  (let* ((name (bytes-to-ascii (ensure-byte-vector identifier)))
         (entry (rassoc name +chain-store-txpool-subpool-labels+
                        :test #'string=)))
    (unless entry
      (block-validation-fail "Unknown KV txpool subpool: ~S" name))
    (car entry)))

(defun chain-store-txpool-transaction-record-rlp
    (subpool transaction)
  (rlp-encode
   (make-rlp-list
    (ascii-to-bytes (chain-store-txpool-subpool-identifier subpool))
    (transaction-encoding transaction))))

(defun chain-store-export-txpool-transaction-to-kv
    (batch subpool transaction)
  (kv-batch-put-chain-record
   batch
   :txpool
   (hash32-bytes (transaction-hash transaction))
   (chain-store-txpool-transaction-record-rlp subpool transaction)))

(defun chain-store-populate-txpool-record-export-batch
    (store database batch)
  (let ((current-transaction-keys (make-hash-table :test 'equal)))
    (flet ((export-subpool (subpool transactions)
             (dolist (transaction transactions)
               (let ((key (hash32-to-hex (transaction-hash transaction))))
                 (setf (gethash key current-transaction-keys) t)
                 (chain-store-export-txpool-transaction-to-kv
                  batch subpool transaction)))))
      (export-subpool :pending
                      (engine-payload-store-pending-transactions store))
      (export-subpool :queued
                      (engine-payload-store-queued-transactions store))
      (export-subpool :basefee
                      (engine-payload-store-basefee-transactions store))
      (export-subpool :blob
                      (engine-payload-store-blob-transactions store)))
    (dolist (entry (kv-chain-record-entries database :txpool))
      (unless (gethash (bytes-to-hex (car entry)) current-transaction-keys)
        (kv-batch-delete-chain-record batch :txpool (car entry))))))

(defun chain-store-export-txpool-records-to-kv (store database)
  (chain-store-apply-export-batch
   store database "txpool"
   #'chain-store-populate-txpool-record-export-batch))
