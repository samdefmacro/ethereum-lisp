(in-package #:ethereum-lisp.node-store.persistence)

;;;; INVALID verdicts are never written.
;;;;
;;;; A verdict describes the binary that reached it as much as the block: a
;;;; client defect produces one as readily as a bad block does.  go-ethereum
;;;; v1.17 keeps its Engine verdicts in memory only (eth/catalyst/api.go
;;;; invalidTipsets, invalidBlocksHits); the bad blocks it writes to disk
;;;; (rawdb.WriteBadBlock) serve debug_getBadBlocks and are never consulted on
;;;; import.  This file only removes the :INVALID-TIPSET records earlier
;;;; revisions wrote, together with the block-access-list side data they
;;;; alone owned.  Hoodi, 2026-09-24: a persisted verdict refused a canonical
;;;; block after the fixing upgrade (60fb6e91), and the attempt to persist one
;;;; for a block the snap history backfill had made known stopped the node.

(defun chain-store-populate-invalid-tipset-deletion-batch
    (store database batch &key authoritative-p)
  "Delete legacy :INVALID-TIPSET records into BATCH.

AUTHORITATIVE-P deletes every such record (a full export); otherwise only the
keys this process evicted from its verdict cache while tracking durable cache
changes are deleted, which can only name a legacy record.  Returns CHANGED-P
and the deleted identifiers."
  (setf store (chain-store-require-memory-store store))
  (let ((deleted-keys (make-hash-table :test 'equalp))
        (changed-p nil))
    (when authoritative-p
      (dolist (entry (kv-chain-record-entries database :invalid-tipset))
        (setf (gethash (bytes-to-hex (car entry)) deleted-keys) t)))
    (maphash
     (lambda (tipset-key marker)
       (declare (ignore marker))
       (setf (gethash tipset-key deleted-keys) t))
     (memory-chain-store-invalid-tipset-durable-deletions store))
    (let ((deleted-identifiers
            (mapcar #'hex-to-bytes
                    (sort
                     (loop for key being the hash-keys of deleted-keys
                           collect key)
                     #'string<))))
      (dolist (identifier deleted-identifiers)
        (when (nth-value
               1 (kv-get-chain-record database :invalid-tipset identifier))
          (kv-batch-delete-chain-record batch :invalid-tipset identifier)
          (setf changed-p t)))
      (values changed-p deleted-identifiers))))

(defun node-store-populate-evicted-remote-bal-cleanup-batch
    (store database batch identifiers
     &key deleted-remote-identifiers deleted-invalid-identifiers)
  "Delete BAL side data owned only by records removed in this batch.

This incremental cleanup combines the final in-memory owner set with point
reads for non-hydrated durable owners. Records scheduled for deletion in this
same batch are not allowed to masquerade as owners."
  (setf store (chain-store-require-memory-store store))
  (let ((changed-p nil))
    (flet ((scheduled-p (identifier scheduled)
             (find identifier scheduled :test #'bytes=))
           (durable-owner-p (kind identifier)
             (multiple-value-bind (record present-p)
                 (kv-get-chain-record database kind identifier)
               (declare (ignore record))
               present-p)))
      (dolist (identifier identifiers)
        (unless
            (let* ((key (bytes-to-hex identifier))
                   (blocks (memory-chain-store-blocks store))
                   (remotes (memory-chain-store-remote-blocks store)))
              (or
               ;; Same-batch candidate/remote writes are already visible in
               ;; memory even though point reads cannot see them yet.  An
               ;; in-memory INVALID verdict owns nothing durable.
               (gethash key blocks)
               (gethash key remotes)
               (durable-owner-p :block identifier)
               (durable-owner-p :staged-block identifier)
               (and (not (scheduled-p identifier deleted-remote-identifiers))
                    (durable-owner-p :remote-block identifier))
               (and (not (scheduled-p identifier deleted-invalid-identifiers))
                    (durable-owner-p :invalid-tipset identifier))))
          (when (durable-owner-p :block-access-list identifier)
            (kv-batch-delete-chain-record
             batch :block-access-list identifier)
            (setf changed-p t)))))
    changed-p))

(defun chain-store-sweep-invalid-tipsets-from-kv (store database)
  "Delete every legacy :INVALID-TIPSET record and the BAL side data it alone
owned, in one batch."
  (engine-payload-store-enable-durable-cache-change-tracking store)
  (let ((deleted-identifiers nil))
    (chain-store-apply-export-batch
     store database "invalid-tipset"
     (lambda (current-store current-database batch)
       (multiple-value-bind (changed-p deleted)
           (chain-store-populate-invalid-tipset-deletion-batch
            current-store current-database batch :authoritative-p t)
         (setf deleted-identifiers deleted)
         (when (node-store-populate-evicted-remote-bal-cleanup-batch
                current-store current-database batch deleted
                :deleted-invalid-identifiers deleted)
           (setf changed-p t))
         ;; CHAIN-STORE-APPLY-EXPORT-BATCH reserves its second return value for
         ;; pending trie nodes. Do not leak deletion identifiers into it.
         changed-p)))
    (node-store-clear-durable-cache-deletions
     (memory-chain-store-invalid-tipset-durable-deletions
      (chain-store-require-memory-store store))
     deleted-identifiers)
    database))
