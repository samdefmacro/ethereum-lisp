(in-package #:ethereum-lisp.txpool.index)

(defvar *engine-pending-txpool-copy-observer* nil
  "Internal test hook called when the deliberate full txpool copy API runs.")

(defstruct (engine-pending-txpool-rollback-snapshot
            (:constructor make-engine-pending-txpool-rollback-snapshot
                (&key account-slot-limit global-slot-limit
                      local-transaction-predicate
                      database-change-tracking-enabled-p
                      change-sequence change-log)))
  account-slot-limit
  global-slot-limit
  local-transaction-predicate
  database-change-tracking-enabled-p
  change-sequence
  change-log)

(defun engine-pending-txpool-transaction-snapshot (txpool)
  "Capture only constant-size txpool metadata for changed-key rollback.

All transaction, sender-index, admission-time, and database-dirty table writes
participate in the enclosing chain-store journal. CHANGE-LOG is a persistent
list updated by PUSH/SUBSEQ, so retaining its old head is O(1) and exact."
  (make-engine-pending-txpool-rollback-snapshot
   :account-slot-limit
   (engine-pending-txpool-account-slot-limit txpool)
   :global-slot-limit
   (engine-pending-txpool-global-slot-limit txpool)
   :local-transaction-predicate
   (engine-pending-txpool-local-transaction-predicate txpool)
   :database-change-tracking-enabled-p
   (engine-pending-txpool-database-change-tracking-enabled-p txpool)
   :change-sequence
   (engine-pending-txpool-change-sequence txpool)
   :change-log
   (engine-pending-txpool-change-log txpool)))

(defun engine-pending-txpool-restore-transaction-snapshot (txpool snapshot)
  (unless (engine-pending-txpool-rollback-snapshot-p snapshot)
    (error "Txpool transaction snapshot is invalid: ~S" snapshot))
  (setf
   (engine-pending-txpool-account-slot-limit txpool)
   (engine-pending-txpool-rollback-snapshot-account-slot-limit snapshot)
   (engine-pending-txpool-global-slot-limit txpool)
   (engine-pending-txpool-rollback-snapshot-global-slot-limit snapshot)
   (engine-pending-txpool-local-transaction-predicate txpool)
   (engine-pending-txpool-rollback-snapshot-local-transaction-predicate
    snapshot)
   (engine-pending-txpool-database-change-tracking-enabled-p txpool)
   (engine-pending-txpool-rollback-snapshot-database-change-tracking-enabled-p
    snapshot)
   (engine-pending-txpool-change-sequence txpool)
   (engine-pending-txpool-rollback-snapshot-change-sequence snapshot)
   (engine-pending-txpool-change-log txpool)
   (engine-pending-txpool-rollback-snapshot-change-log snapshot))
  txpool)

(defun engine-pending-txpool-copy-transaction (transaction transaction-copies)
  (or (gethash transaction transaction-copies)
      (setf (gethash transaction transaction-copies)
            (transaction-from-encoding (transaction-encoding transaction)))))

(defun engine-pending-txpool-copy-transaction-table
    (table transaction-copies)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key transaction)
               (setf (gethash key copy)
                     (engine-pending-txpool-copy-transaction
                      transaction
                      transaction-copies)))
             table)
    copy))

(defun engine-pending-txpool-copy-metadata-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun engine-pending-txpool-copy-sender-index
    (table transaction-copies)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (sender nonce-table)
               (let ((nonce-copy
                       (make-hash-table :test (hash-table-test nonce-table))))
                 (maphash
                  (lambda (nonce transaction)
                    (setf (gethash nonce nonce-copy)
                          (engine-pending-txpool-copy-transaction
                           transaction
                           transaction-copies)))
                  nonce-table)
                 (setf (gethash sender copy) nonce-copy)))
             table)
    copy))

(defun engine-pending-txpool-copy (txpool)
  (when *engine-pending-txpool-copy-observer*
    (funcall *engine-pending-txpool-copy-observer* txpool))
  (let ((transaction-copies (make-hash-table :test 'eq)))
    (make-engine-pending-txpool
     :transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-transactions txpool)
      transaction-copies)
     :transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-transactions-by-sender txpool)
      transaction-copies)
     :queued-transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-queued-transactions txpool)
      transaction-copies)
     :queued-transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-queued-transactions-by-sender txpool)
      transaction-copies)
     :basefee-transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-basefee-transactions txpool)
      transaction-copies)
     :basefee-transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-basefee-transactions-by-sender txpool)
      transaction-copies)
     :blob-transactions
     (engine-pending-txpool-copy-transaction-table
      (engine-pending-txpool-blob-transactions txpool)
      transaction-copies)
     :blob-transactions-by-sender
     (engine-pending-txpool-copy-sender-index
      (engine-pending-txpool-blob-transactions-by-sender txpool)
      transaction-copies)
     :transaction-admitted-at
     (engine-pending-txpool-copy-metadata-table
      (engine-pending-txpool-transaction-admitted-at txpool))
     :database-change-tracking-enabled-p
     (engine-pending-txpool-database-change-tracking-enabled-p txpool)
     :database-dirty-transaction-keys
     (engine-pending-txpool-copy-metadata-table
      (engine-pending-txpool-database-dirty-transaction-keys txpool))
     :change-sequence
     (engine-pending-txpool-change-sequence txpool)
     :change-log
     (mapcar
      (lambda (entry)
        (cons (car entry) (make-hash32 (hash32-bytes (cdr entry)))))
      (engine-pending-txpool-change-log txpool)))))
