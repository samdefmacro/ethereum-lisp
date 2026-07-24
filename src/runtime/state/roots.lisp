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

(defun flush-account-trie (state)
  "Return the account state root, rebuilding only when the dirty set is
non-empty (the cached root is trustworthy iff dirty is empty; see STATE-DB)."
  (when (or (null (state-db-cached-root state))
            (plusp (hash-table-count (state-db-dirty state))))
    (setf (state-db-cached-root state)
          (make-hash32 (mpt-root-hash (state-db-state-trie state))))
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
