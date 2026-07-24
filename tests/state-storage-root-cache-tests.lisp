(in-package #:ethereum-lisp.test)

;;;; Memoized per-account storage roots.
;;;;
;;;; Rebuilding every account's storage trie was most of the cost of a state
;;;; root, and the root is taken over the whole world even though a block
;;;; touches a handful of accounts. STATE-OBJECT now memoizes its storage root
;;;; and STATE-DB-SET-STORAGE drops it.
;;;;
;;;; A stale memo is a wrong state root, i.e. a consensus divergence, so these
;;;; tests compare the memoized answer against a cold recomputation rather than
;;;; asserting fixed hashes: any missed invalidation shows up as a mismatch no
;;;; matter which mutation caused it.

(defun storage-cache-clear (state)
  "Force every account to recompute its storage root."
  (maphash (lambda (key object)
             (declare (ignore key))
             (setf (ethereum-lisp.state::state-object-cached-storage-root object)
                   nil))
           (ethereum-lisp.state::state-db-objects state))
  state)

(defun storage-cache-root-hex (state)
  (hash32-to-hex (ethereum-lisp.state:state-db-root state)))

(defun storage-cache-root-agrees-p (state)
  "True when the memoized root equals a root computed from a cleared cache."
  (let ((memoized (storage-cache-root-hex state)))
    (storage-cache-clear state)
    (string= memoized (storage-cache-root-hex state))))

(defun storage-cache-address (index)
  (address-from-hex (format nil "0x~40,'0X" (1+ index))))

(defun storage-cache-slot (index)
  (hash32-from-hex (format nil "0x~64,'0X" index)))

(defun storage-cache-seed-account (state index)
  (ethereum-lisp.state::state-db-put-account-values
   state
   (storage-cache-address index)
   1
   1000
   (hash32-from-hex (format nil "0x~64,'0X" 0))))

(deftest state-storage-root-memo-is-dropped-on-write
  (let ((state (ethereum-lisp.state:make-state-db))
        (address (storage-cache-address 0)))
    (storage-cache-seed-account state 0)
    (ethereum-lisp.state:state-db-set-storage
     state address (storage-cache-slot 1) 42)
    (let ((before (storage-cache-root-hex state)))
      ;; The memo is populated now; a further write must invalidate it.
      (is (ethereum-lisp.state::state-object-cached-storage-root
           (ethereum-lisp.state::state-db-get-object state address)))
      (ethereum-lisp.state:state-db-set-storage
       state address (storage-cache-slot 1) 43)
      (is (null (ethereum-lisp.state::state-object-cached-storage-root
                 (ethereum-lisp.state::state-db-get-object state address))))
      (let ((after (storage-cache-root-hex state)))
        (is (not (string= before after)))
        (is (storage-cache-root-agrees-p state))))))

(deftest state-storage-root-memo-survives-a-zeroing-delete
  ;; Writing zero deletes the slot and can prune the object entirely; both
  ;; paths have to leave a truthful root.
  (let ((state (ethereum-lisp.state:make-state-db))
        (address (storage-cache-address 0)))
    (storage-cache-seed-account state 0)
    (ethereum-lisp.state:state-db-set-storage
     state address (storage-cache-slot 1) 7)
    (let ((populated (storage-cache-root-hex state)))
      (ethereum-lisp.state:state-db-set-storage
       state address (storage-cache-slot 1) 0)
      (let ((emptied (storage-cache-root-hex state)))
        (is (not (string= populated emptied)))
        (is (storage-cache-root-agrees-p state))))))

(deftest state-storage-root-memo-is-consistent-across-snapshots
  ;; Snapshots are taken per call frame; a clone carries the memo, and a
  ;; restore must not reinstate one that no longer matches the storage.
  (let ((state (ethereum-lisp.state:make-state-db))
        (address (storage-cache-address 0)))
    (storage-cache-seed-account state 0)
    (ethereum-lisp.state:state-db-set-storage
     state address (storage-cache-slot 1) 5)
    (let* ((before (storage-cache-root-hex state))
           (snapshot (ethereum-lisp.state:state-db-copy state)))
      (ethereum-lisp.state:state-db-set-storage
       state address (storage-cache-slot 1) 9)
      (is (not (string= before (storage-cache-root-hex state))))
      (ethereum-lisp.state:state-db-restore state snapshot)
      (is (string= before (storage-cache-root-hex state)))
      (is (storage-cache-root-agrees-p state)))))

(deftest state-storage-root-memo-matches-cold-recomputation-under-churn
  ;; The general guard: a long pseudo-random mutation sequence, mixing writes,
  ;; zeroing deletes and object pruning, must never let the memo drift.
  (let* ((state (ethereum-lisp.state:make-state-db))
         (accounts 8)
         (slots 6)
         (random-state (sb-ext:seed-random-state 20260724))
         (comparisons 0))
    (dotimes (index accounts)
      (storage-cache-seed-account state index))
    (dotimes (step 600)
      (ethereum-lisp.state:state-db-set-storage
       state
       (storage-cache-address (random accounts random-state))
       (storage-cache-slot (random slots random-state))
       (if (zerop (random 3 random-state))
           0
           (1+ (random 1000 random-state))))
      (when (zerop (mod step 20))
        (incf comparisons)
        (is (storage-cache-root-agrees-p state))))
    (is (= 30 comparisons))))
