(in-package #:ethereum-lisp.state)

(defun state-db-state-trie (state)
  (let ((trie (make-mpt)))
    (maphash (lambda (address object)
               (let* ((address-hash (keccak-256 (address-bytes (address-from-hex address))))
                      (account (account-with-storage-root object)))
                 (mpt-put trie address-hash (state-account-rlp account))))
             (state-db-objects state))
    trie))

(defun state-db-account-proof-key (address)
  (keccak-256 (address-bytes address)))

(defun state-db-get-account-proof (state address)
  (mpt-get-proof (state-db-state-trie state)
                 (state-db-account-proof-key address)))

(defun state-db-verify-account-proof (state-root address proof)
  (mpt-verify-proof state-root (state-db-account-proof-key address) proof))

(defvar *verify-incremental-root* nil
  "When true, every account-root flush also computes the full-rebuild root from
STATE-DB-STATE-TRIE and asserts byte-equality with the memoized result. This
catches a missed dirty-hook (a stale memo returned on the fast path). The test
suite and fixture runs bind it true; production leaves it nil. STATE-DB-STATE-
TRIE is retained forever as the reference oracle.")

(defun state-db-apply-dirty-accounts (state trie)
  "Update TRIE to match STATE for the dirty addresses only, and return it.

This is the point of keeping a trie at all: a block touches a handful of
accounts, so only those leaves need to change. An address whose account is gone
is DELETED rather than skipped -- leaving a stale leaf behind would be a wrong
state root, which is a consensus divergence."
  (maphash (lambda (key ignored)
             (declare (ignore ignored))
             (let* ((address (address-from-hex key))
                    (address-hash (keccak-256 (address-bytes address)))
                    (object (gethash key (state-db-objects state))))
               (if object
                   (mpt-put trie address-hash
                            (state-account-rlp
                             (account-with-storage-root object)))
                   (mpt-delete trie address-hash))))
           (state-db-dirty state))
  trie)

(defun flush-account-trie (state)
  "Return the account state root, recomputing only when something changed.

A flush with a trie already in hand updates the dirty leaves; without one it
builds a trie over every account and keeps it for next time. The cached root is
trustworthy iff DIRTY is empty; see STATE-DB."
  (when (or (null (state-db-cached-root state))
            (null (state-db-trie state))
            (plusp (hash-table-count (state-db-dirty state))))
    (let ((trie (if (state-db-trie state)
                    (state-db-apply-dirty-accounts state (state-db-trie state))
                    (state-db-state-trie state))))
      (setf (state-db-trie state) trie)
      (setf (state-db-cached-root state) (make-hash32 (mpt-root-hash trie))))
    (clrhash (state-db-dirty state)))
  (when *verify-incremental-root*
    (let ((full (make-hash32 (mpt-root-hash (state-db-state-trie state)))))
      (unless (hash32= (state-db-cached-root state) full)
        (error "Account state root ~A diverged from a full rebuild ~A ~
                (a state mutation did not mark its account dirty)"
               (hash32-to-hex (state-db-cached-root state))
               (hash32-to-hex full)))))
  (state-db-cached-root state))

(defun state-db-root (state)
  (flush-account-trie state))

(defun state-db-root-hex (state)
  (hash32-to-hex (state-db-root state)))
