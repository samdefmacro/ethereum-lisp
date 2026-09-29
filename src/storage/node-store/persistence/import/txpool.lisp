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

(defun chain-store-import-txpool-transaction-drop-reason
    (store transaction chain-config)
  "Why a well-formed durable txpool record no longer belongs in the pool at the
current head, or NIL when it still does.

These are the chain-rule questions whose answer moves with the head (or with
the configured fork schedule) while the node is stopped: the head's rules do
not admit the transaction type, or a canonical block already includes the
transaction. go-ethereum v1.17.6 answers them the same way on restart: its
journal load hands every journaled transaction to the pool's add path, and logs
and counts each one refused (core/txpool/locals/journal.go load); its blob pool
deletes the entries it cannot track and keeps starting
(core/txpool/blobpool/blobpool.go Init, parseTransaction). A record that fails
one of them is therefore dropped, not fatal: refusing to start on a datadir
that was healthy at shutdown turns a stale pool entry into a dead node (Hoodi,
2026-09-29; docs/evidence/sec5-txpool-journal-import.txt).

A blob transaction whose max fee per blob gas is below the head's blob base fee
is NOT such a record. The running pool keeps it parked, because the blob base
fee falls again after blocks with little blob gas (see
ENGINE-PAYLOAD-STORE-NEW-HEAD-INVALID-REASON), and go-ethereum's blob pool keeps
it too (it orders by blob-fee jumps and evicts only under pressure). The import
restores it into the blob subpool exactly as the stopped process held it."
  (or (handler-case
          (progn
            (chain-store-import-txpool-transaction-rules
             store transaction chain-config)
            nil)
        (block-validation-error (condition)
          (princ-to-string condition)))
      (when (chain-store-transaction-location
             store (transaction-hash transaction))
        "Transaction is already included in a canonical block")))

(defun chain-store-import-txpool-transaction-from-kv
    (store transaction-identifier record &key expected-chain-id chain-config)
  "Restore one durable txpool RECORD into STORE's pool.

Returns NIL when the record was restored, or a drop plist
(:transaction-hash H :subpool S :reason R :transaction TX) when the record is
well formed but no longer valid at the current head (see
CHAIN-STORE-IMPORT-TXPOOL-TRANSACTION-DROP-REASON). A record this process could
never have written -- bytes that do not decode or round-trip, a key that is not
the transaction's hash, fields no admission accepts, a sender that does not
recover for this chain, a blob transaction outside the blob subpool, or two
records claiming one hash or one sender nonce -- still signals
BLOCK-VALIDATION-ERROR: that is corruption, and the importer publishes nothing."
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
      (let ((drop-reason
              (chain-store-import-txpool-transaction-drop-reason
               store transaction chain-config)))
        (when drop-reason
          (return-from chain-store-import-txpool-transaction-from-kv
            (list :transaction-hash transaction-hash
                  :subpool subpool
                  :reason drop-reason
                  :transaction transaction))))
      (when (engine-payload-store-pooled-transaction store transaction-hash)
        (block-validation-fail
         "KV txpool record duplicates a pooled transaction hash"))
      (when (chain-store-import-txpool-transaction-conflict-p
             txpool transaction)
        (block-validation-fail
         "KV txpool record duplicates a sender nonce"))
      (chain-store-import-txpool-transaction-to-subpool
       txpool subpool transaction admitted-at)
      nil)))

(defun node-store-import-txpool-records-from-kv
    (store database &key expected-chain-id chain-config
                         skip-indexed-transactions-p)
  "Restore DATABASE's durable txpool records into STORE. Returns the records
dropped as no longer valid at the current head, a list of drop plists in key
order (see CHAIN-STORE-IMPORT-TXPOOL-TRANSACTION-FROM-KV), and as a second value
the number of records read.

A dropped record stays in DATABASE until the caller's next txpool delta: once
txpool database change tracking is enabled, hand the drops to
NODE-STORE-NOTE-DROPPED-TXPOOL-RECORDS so that delta deletes them. A full
snapshot export deletes them anyway, since it writes only what the pool holds.
SKIP-INDEXED-TRANSACTIONS-P passes over an already-included transaction
silently instead of reporting it, for a journal known to lag the chain
database. Corruption signals BLOCK-VALIDATION-ERROR."
  (let ((drops '())
        (records 0))
    (dolist (entry (kv-chain-record-entries database :txpool))
      (incf records)
      (let ((transaction-hash (make-hash32 (car entry))))
        (unless (and skip-indexed-transactions-p
                     (chain-store-transaction-location
                      store transaction-hash))
          (let ((drop
                  (chain-store-import-txpool-transaction-from-kv
                   store
                   (hash32-bytes transaction-hash)
                   (cdr entry)
                   :expected-chain-id expected-chain-id
                   :chain-config chain-config)))
            (when drop
              (push drop drops))))))
    (values (nreverse drops) records)))

(defun node-store-note-dropped-txpool-records (store drops)
  "Mark each record in DROPS for STORE's next durable txpool delta, which
deletes it because the pool does not hold it. STORE must already track txpool
database changes: enabling tracking clears the marks."
  (when drops
    (engine-payload-store-mark-txpool-database-dirty-transaction-hashes
     store
     (mapcar (lambda (drop) (getf drop :transaction-hash)) drops)))
  store)

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
