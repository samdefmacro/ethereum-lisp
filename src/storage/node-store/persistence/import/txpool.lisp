(in-package #:ethereum-lisp.node-store.persistence)

(defun chain-store-txpool-transaction-record-values (record)
  "Decode a durable txpool RECORD into its subpool, transaction and admission
time (NIL for a record written before admission times were kept)."
  (handler-case
      (let ((fields (rlp-list-field (rlp-decode-one record)
                                    "Txpool transaction record")))
        (unless (<= 2 (length fields) 3)
          (block-validation-fail
           "Txpool transaction record must contain 2 or 3 fields"))
        (let* ((subpool
                 (chain-store-txpool-subpool-label
                  (rlp-bytes-field (first fields)
                                   "Txpool transaction subpool")))
               (encoded
                 (rlp-bytes-field (second fields)
                                  "Txpool transaction encoding"))
               (transaction (transaction-from-encoding encoded)))
          (unless (bytes= encoded (transaction-encoding transaction))
            (block-validation-fail
             "Txpool transaction record does not round-trip"))
          (values subpool transaction
                  (and (third fields)
                       (rlp-uint-field (third fields)
                                       "Txpool transaction admission time")))))
    (rlp-error (condition)
      (block-validation-fail
       "Invalid KV txpool transaction record RLP: ~A" condition))))

(defun chain-store-import-txpool-transaction-conflict-p
    (txpool transaction)
  (or (engine-pending-txpool-pending-conflict txpool transaction)
      (engine-pending-txpool-queued-conflict txpool transaction)
      (engine-pending-txpool-basefee-conflict txpool transaction)
      (engine-pending-txpool-blob-conflict txpool transaction)))

(defun chain-store-import-txpool-transaction-to-subpool
    (txpool subpool transaction &optional admitted-at)
  (ecase subpool
    (:pending
     (engine-pending-txpool-put-pending-transaction
      txpool transaction :admitted-at admitted-at))
    (:queued
     (engine-pending-txpool-put-queued-transaction
      txpool transaction :admitted-at admitted-at))
    (:basefee
     (engine-pending-txpool-put-basefee-transaction
      txpool transaction :admitted-at admitted-at))
    (:blob
     (engine-pending-txpool-put-blob-transaction
      txpool transaction :admitted-at admitted-at))))

(defun chain-store-import-txpool-transaction-rules
    (store transaction chain-config)
  (when chain-config
    (let* ((head (chain-store-latest-block store))
           (header (and head (block-header head)))
           (number (if header (block-header-number header) 0))
           (timestamp (if header (block-header-timestamp header) 0)))
      (validate-transaction-type-for-config
       transaction chain-config number timestamp))))

(defun chain-store-import-txpool-subpool-compatible-p
    (subpool transaction)
  (cond
    ((eq subpool :blob)
     (unless (typep transaction 'blob-transaction)
       (block-validation-fail
        "KV txpool blob subpool record must contain a blob transaction")))
    ((typep transaction 'blob-transaction)
     (block-validation-fail
      "KV txpool blob transaction must restore to the blob subpool")))
  t)

(defun chain-store-import-txpool-transaction-static-fields (transaction)
  (validate-transaction-data-field transaction)
  (validate-transaction-recipient-field transaction)
  (validate-transaction-scalar-fields transaction)
  (validate-transaction-signature-fields transaction)
  (validate-access-list-fields transaction)
  (validate-set-code-transaction-fields transaction)
  (validate-set-code-authorization-signatures transaction)
  (when (typep transaction 'blob-transaction)
    ;; Restored transactions were already admitted under their fork's blob
    ;; limit; do not re-impose the default per-transaction cap here.
    (validate-blob-transaction-fields transaction :max-blobs nil))
  t)

(defun chain-store-import-txpool-transaction-from-kv
    (store transaction-identifier record &key expected-chain-id chain-config)
  (let ((transaction-hash (make-hash32 transaction-identifier))
        (txpool (engine-payload-store-txpool store)))
    (multiple-value-bind (subpool transaction admitted-at)
        (chain-store-txpool-transaction-record-values record)
      (unless (hash32= transaction-hash (transaction-hash transaction))
        (block-validation-fail
         "KV txpool record key does not match encoded transaction hash"))
      (chain-store-import-txpool-transaction-static-fields transaction)
      (unless (transaction-sender transaction
                                  :expected-chain-id expected-chain-id)
        (block-validation-fail
         "KV txpool record sender recovery failed"))
      (chain-store-import-txpool-subpool-compatible-p subpool transaction)
      (chain-store-import-txpool-transaction-rules
       store transaction chain-config)
      (engine-payload-store-validate-txpool-blob-fee-cap
       store
       transaction
       :chain-config chain-config
       :label "KV txpool record")
      (when (chain-store-transaction-location store transaction-hash)
        (block-validation-fail
         "KV txpool record duplicates an indexed transaction"))
      (when (engine-payload-store-pooled-transaction store transaction-hash)
        (block-validation-fail
         "KV txpool record duplicates a pooled transaction hash"))
      (when (chain-store-import-txpool-transaction-conflict-p
             txpool transaction)
        (block-validation-fail
         "KV txpool record duplicates a sender nonce"))
      (chain-store-import-txpool-transaction-to-subpool
       txpool subpool transaction admitted-at))))

(defun node-store-import-txpool-records-from-kv
    (store database &key expected-chain-id chain-config
                         skip-indexed-transactions-p)
  (dolist (entry (kv-chain-record-entries database :txpool))
    (let ((transaction-hash (make-hash32 (car entry))))
      (unless (and skip-indexed-transactions-p
                   (chain-store-transaction-location
                    store transaction-hash))
        (chain-store-import-txpool-transaction-from-kv
         store
         (hash32-bytes transaction-hash)
         (cdr entry)
         :expected-chain-id expected-chain-id
         :chain-config chain-config)))))

(defun node-store-restore-txpool-consistency
    (store &key expected-chain-id chain-config)
  (let ((head (chain-store-latest-block store)))
    (when head
      (engine-payload-store-remove-new-head-invalid-txpool-transactions
       store
       :expected-chain-id expected-chain-id
       :chain-config chain-config)
      (when (chain-store-state-available-p store (block-hash head))
        (engine-payload-store-revalidate-pending-transactions
         store
         :expected-chain-id expected-chain-id)
        (engine-payload-store-promote-queued-transactions
         store
         :expected-chain-id expected-chain-id)
        (engine-payload-store-promote-basefee-and-queued-transactions
         store
         :expected-chain-id expected-chain-id)
        (engine-payload-store-prune-overbudget-parked-transactions store))))
  store)
