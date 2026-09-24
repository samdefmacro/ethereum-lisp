(in-package #:ethereum-lisp.txpool.index)

;;;; Derived lookups over the pooled transactions: EIP-7702 authorities and
;;;; blob versioned hashes.
;;;;
;;;; Both answer a question admission asks about the WHOLE pool -- "is this
;;;; address named by a pending authorization?", "does a pooled transaction
;;;; still reference this blob?" -- in one table read instead of a scan.
;;;; Authorities are recovered once, when a transaction enters a subpool
;;;; table, and remembered per transaction so its removal does not recover
;;;; them again (go-ethereum v1.17 legacypool keeps the same index in its
;;;; txLookup, and validateAuth reads it). The blob owner counts are what pin
;;;; a pooled transaction's sidecar in the chain store's bounded blob cache.
;;;;
;;;; NOTE and FORGET are called at every site that puts a transaction into, or
;;;; takes one out of, a subpool table (txpool/index/insert.lisp and
;;;; ENGINE-PENDING-TXPOOL-REMOVE-INDEXED-TRANSACTION). Every write goes
;;;; through the journaled table helpers, so a rolled-back admission restores
;;;; these lookups with the tables they derive from.

(defun engine-pending-txpool-lookup-transaction-key (transaction)
  (hash32-to-hex (transaction-hash transaction)))

(defun engine-pending-txpool-blob-hash-key (versioned-hash)
  "The chain-store blob cache key of VERSIONED-HASH (a hash32 or 32 bytes)."
  (hash32-to-hex (make-hash32 (blob-versioned-hash-bytes versioned-hash))))

(defun engine-pending-txpool-recover-authority-keys (transaction)
  "Distinct authority address keys of TRANSACTION's recoverable EIP-7702
authorizations; NIL for every other transaction type. An authorization whose
signature does not recover names no authority, as in execution."
  (let ((keys '()))
    (dolist (authorization (transaction-authorization-list transaction))
      (let ((authority (set-code-authorization-authority authorization)))
        (when authority
          (pushnew (address-to-hex authority) keys :test #'string=))))
    (nreverse keys)))

(defun engine-pending-txpool-note-transaction-lookups (txpool transaction)
  "Record TRANSACTION, which has just entered a subpool table, in the derived
authority and blob-owner lookups."
  (let ((key (engine-pending-txpool-lookup-transaction-key transaction)))
    (when (typep transaction 'set-code-transaction)
      (let ((authorities
              (engine-pending-txpool-recover-authority-keys transaction))
            (by-authority
              (engine-pending-txpool-authority-transactions txpool)))
        (engine-pending-txpool-journal-puthash
         (engine-pending-txpool-transaction-authorities txpool)
         key authorities)
        (dolist (authority authorities)
          (let ((holders
                  (or (gethash authority by-authority)
                      (engine-pending-txpool-journal-puthash
                       by-authority authority
                       (make-hash-table :test 'equal)))))
            (engine-pending-txpool-journal-puthash holders key t)))))
    (let ((owners (engine-pending-txpool-blob-hash-owners txpool)))
      (loop for versioned-hash across
              (transaction-blob-versioned-hashes transaction)
            for blob-key = (engine-pending-txpool-blob-hash-key versioned-hash)
            do (engine-pending-txpool-journal-puthash
                owners blob-key (1+ (gethash blob-key owners 0))))))
  transaction)

(defun engine-pending-txpool-forget-transaction-lookups (txpool transaction)
  "Remove TRANSACTION, which has just left a subpool table, from the derived
authority and blob-owner lookups."
  (let* ((key (engine-pending-txpool-lookup-transaction-key transaction))
         (by-transaction
           (engine-pending-txpool-transaction-authorities txpool))
         (by-authority (engine-pending-txpool-authority-transactions txpool)))
    (multiple-value-bind (authorities present-p) (gethash key by-transaction)
      (when present-p
        (dolist (authority authorities)
          (let ((holders (gethash authority by-authority)))
            (when holders
              (engine-pending-txpool-journal-remhash holders key)
              (when (zerop (hash-table-count holders))
                (engine-pending-txpool-journal-remhash
                 by-authority authority)))))
        (engine-pending-txpool-journal-remhash by-transaction key)))
    (let ((owners (engine-pending-txpool-blob-hash-owners txpool)))
      (loop for versioned-hash across
              (transaction-blob-versioned-hashes transaction)
            for blob-key = (engine-pending-txpool-blob-hash-key versioned-hash)
            for count = (gethash blob-key owners 0)
            do (if (<= count 1)
                   (engine-pending-txpool-journal-remhash owners blob-key)
                   (engine-pending-txpool-journal-puthash
                    owners blob-key (1- count))))))
  transaction)

(defun engine-pending-txpool-authority-reserved-p (txpool address)
  "Whether a pooled set-code transaction names ADDRESS as an authority."
  (let ((holders (gethash (address-to-hex address)
                          (engine-pending-txpool-authority-transactions
                           txpool))))
    (and holders (plusp (hash-table-count holders)))))

(defun engine-pending-txpool-blob-hash-owned-p (txpool blob-key)
  "Whether a pooled transaction references the blob cache key BLOB-KEY."
  (plusp (gethash blob-key (engine-pending-txpool-blob-hash-owners txpool) 0)))

(defun engine-pending-txpool-owned-blob-count (txpool)
  "How many distinct blobs the pooled transactions reference."
  (hash-table-count (engine-pending-txpool-blob-hash-owners txpool)))
