(in-package #:ethereum-lisp.test)

;;;; Wave-3b account-trie dirty tracking + memoized state root.
;;;;
;;;; STATE-DB now keeps a DIRTY set and a memoized CACHED-ROOT; STATE-DB-ROOT
;;;; recomputes only when DIRTY is non-empty. Every account-mutating function
;;;; marks the address dirty. A missed mark is a wrong state root -- a consensus
;;;; divergence -- so these tests bind *VERIFY-INCREMENTAL-ROOT* true, which
;;;; makes every root flush cross-check the memo against a full rebuild. They
;;;; assert equality against the retained full-rebuild oracle rather than fixed
;;;; hashes, so a missed invalidation surfaces no matter which mutation caused
;;;; it. The dense memo-hit path (a root after a single mutation) is where a
;;;; stale memo bites, so these tests root frequently.

(defun account-trie-full-root (state)
  "The account root computed by a full rebuild -- the reference oracle."
  (make-hash32 (mpt-root-hash (ethereum-lisp.state::state-db-state-trie state))))

(defun account-trie-root= (a b)
  (and (ethereum-lisp.types:hash32= a b) t))

(defun account-trie-address (index)
  (address-from-hex (format nil "0x~40,'0X" (1+ index))))

(defun account-trie-slot (index)
  (hash32-from-hex (format nil "0x~64,'0X" index)))

(defun account-trie-code-hash (index)
  (hash32-from-hex (format nil "0x~64,'0X" (+ 1000 index))))

(defmacro with-verified-account-root (&body body)
  `(let ((ethereum-lisp.state::*verify-incremental-root* t))
     ,@body))

(defun account-trie-random-mutation (state random-state address-count)
  "Apply one random state mutation. A domain rejection (e.g. an overdraw) is a
no-op, never a hook bug, so it is swallowed -- the root cross-check runs in
STATE-DB-ROOT regardless."
  (let ((address (account-trie-address (random address-count random-state))))
    (ignore-errors
     (ecase (random 7 random-state)
       (0 (ethereum-lisp.state::state-db-put-account-values
           state address (random 5 random-state) (random 1000 random-state)
           (account-trie-code-hash (random address-count random-state))))
       (1 (ethereum-lisp.state::state-db-add-balance
           state address (random 500 random-state)))
       (2 (ethereum-lisp.state::state-db-transfer-value
           state address (account-trie-address (random address-count random-state))
           (random 100 random-state)))
       (3 (ethereum-lisp.state::state-db-set-code
           state address
           (make-byte-vector (random 40 random-state)
                             :initial-element (random 256 random-state))))
       (4 (state-db-set-storage state address
                                (account-trie-slot (random 6 random-state))
                                (random 1000 random-state)))
       (5 (state-db-set-storage state address
                                (account-trie-slot (random 6 random-state)) 0))
       (6 (ethereum-lisp.state::state-db-clear-account state address))))))

(deftest account-trie-memo-matches-full-rebuild-under-churn
  ;; A long random mutation sequence, interleaved with snapshot/mutate/restore,
  ;; must keep the memoized root equal to a full rebuild at every root call.
  (with-verified-account-root
    (let ((state (make-state-db))
          (random-state (sb-ext:seed-random-state 20260724))
          (address-count 8)
          (checks 0))
      (dotimes (step 6000)
        (account-trie-random-mutation state random-state address-count)
        (when (zerop (mod step 3))
          (state-db-root state)            ; self-verifies via the oracle
          (incf checks))
        ;; The #1 snapshot trap: a root FOLDED inside a snapshot bracket must be
        ;; undone by restore back to the pre-mutation root.
        (when (zerop (mod step 11))
          (let ((snapshot (state-db-copy state))
                (before (state-db-root state)))
            (dotimes (extra (1+ (random 4 random-state)))
              (account-trie-random-mutation state random-state address-count))
            (state-db-root state)          ; fold inside the bracket
            (state-db-restore state snapshot)
            (is (eq t (account-trie-root= before (state-db-root state))))
            (incf checks))))
      (is (< 2000 checks))
      (is (eq t (account-trie-root= (state-db-root state) (account-trie-full-root state)))))))

(deftest account-trie-memo-handles-deletion-and-resurrection
  (with-verified-account-root
    (let ((state (make-state-db))
          (a (account-trie-address 0))
          (b (account-trie-address 1)))
      ;; empty-but-present account (zeroed values, never pruned) keeps a leaf
      (ethereum-lisp.state::state-db-put-account-values
       state a 0 0 (account-trie-code-hash 0))
      (state-db-root state)
      ;; a storage-only write changes the ACCOUNT root (leaf embeds storage root)
      (state-db-set-storage state b (account-trie-slot 1) 7)
      (let ((with-storage (state-db-root state)))
        ;; selfdestruct deletes the leaf
        (ethereum-lisp.state::state-db-clear-account state b)
        (is (not (account-trie-root= with-storage (state-db-root state)))))
      ;; resurrect: a fresh object with fresh storage
      (ethereum-lisp.state::state-db-put-account-values
       state b 1 5 (account-trie-code-hash 1))
      (state-db-set-storage state b (account-trie-slot 2) 9)
      (state-db-root state)
      ;; prune-to-empty by zeroing the only slot on an otherwise-empty account
      (state-db-set-storage state b (account-trie-slot 2) 0)
      (is (eq t (account-trie-root= (state-db-root state)
                         (account-trie-full-root state)))))))

(deftest account-trie-root-is-memoized-when-clean
  ;; After a root, the dirty set is empty and a repeated root is a memo hit
  ;; (same value, no divergence); a write re-dirties.
  (let ((state (make-state-db)))
    (ethereum-lisp.state::state-db-put-account-values
     state (account-trie-address 0) 1 100 (account-trie-code-hash 0))
    (is (plusp (hash-table-count (ethereum-lisp.state::state-db-dirty state))))
    (let ((root (state-db-root state)))
      (is (zerop (hash-table-count (ethereum-lisp.state::state-db-dirty state))))
      (is (ethereum-lisp.state::state-db-cached-root state))
      (is (eq t (account-trie-root= root (state-db-root state))))     ; memo hit, same value
      (state-db-set-storage state (account-trie-address 0) (account-trie-slot 1) 5)
      (is (plusp (hash-table-count (ethereum-lisp.state::state-db-dirty state))))
      (is (not (account-trie-root= root (state-db-root state)))))))
