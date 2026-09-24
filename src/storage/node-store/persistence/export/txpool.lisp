(in-package #:ethereum-lisp.node-store.persistence)

(declaim
 (ftype (function (t t t t &key (:require-all-p t)) t)
        node-store-populate-blob-sidecars-for-transactions-batch))

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
    (subpool transaction &optional admitted-at)
  "The durable txpool record: [subpool, encoding] or, when ADMITTED-AT (the
Unix admission time) is known, [subpool, encoding, admitted-at]. The time is
kept so a restart does not reset the age that --txpool.lifetime and the blob
transaction lifetime measure."
  (rlp-encode
   (apply #'make-rlp-list
          (ascii-to-bytes (chain-store-txpool-subpool-identifier subpool))
          (transaction-encoding transaction)
          (when admitted-at (list admitted-at)))))

(defun node-store-txpool-transaction-record-rlp (store subpool transaction)
  "TRANSACTION's durable txpool record, with its admission time from STORE."
  (chain-store-txpool-transaction-record-rlp
   subpool transaction
   (engine-pending-txpool-admission-time
    (engine-payload-store-txpool store) transaction)))

(defun chain-store-export-txpool-transaction-to-kv
    (store batch subpool transaction)
  (kv-batch-put-chain-record
   batch
   :txpool
   (hash32-bytes (transaction-hash transaction))
   (node-store-txpool-transaction-record-rlp store subpool transaction)))

(defun chain-store-populate-txpool-record-export-batch
    (store database batch)
  (let ((current-transaction-keys (make-hash-table :test 'equalp)))
    (flet ((export-subpool (subpool transactions)
             (dolist (transaction transactions)
               (let ((key (hash32-to-hex (transaction-hash transaction))))
                 (setf (gethash key current-transaction-keys) t)
                 (chain-store-export-txpool-transaction-to-kv
                  store batch subpool transaction)))))
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

(defun node-store-current-txpool-transactions (store)
  (append
   (engine-payload-store-pending-transactions store)
   (engine-payload-store-queued-transactions store)
   (engine-payload-store-basefee-transactions store)
   (engine-payload-store-blob-transactions store)))

(defun node-store-export-txpool-records-to-kv
    (store database &key persistence-metadata)
  (chain-store-apply-export-batch
   store database "txpool"
   (lambda (source target batch)
     (chain-store-populate-txpool-record-export-batch source target batch)
     (node-store-populate-blob-sidecars-for-transactions-batch
      source target batch
      (node-store-current-txpool-transactions source)
      :require-all-p t)
     (node-store-populate-persistence-metadata-batch
      batch persistence-metadata))
   :persistence-metadata persistence-metadata))
