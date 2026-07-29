(in-package #:ethereum-lisp.state)

(defun state-db-get-object (state address)
  (let ((key (address-key address)))
    (unless (gethash key (state-db-loaded-accounts state))
      (setf (gethash key (state-db-loaded-accounts state)) t)
      (let ((loader (state-db-account-loader state)))
        (when loader
          (multiple-value-bind (account code present-p storage-entries)
              (funcall loader address)
            (when present-p
              (let ((storage (make-hash-table :test #'equal)))
                (dolist (entry storage-entries)
                  (setf (gethash (storage-key (car entry)) storage) (cdr entry)))
                (setf (gethash key (state-db-objects state))
                      (make-state-object :account account :code code
                                         :storage storage))))))))
    (gethash key (state-db-objects state))))

(defun state-db-account-loaded-p (state address)
  (not (null (gethash (address-key address)
                      (state-db-loaded-accounts state)))))

(defun state-db-materialize (state)
  "Load the complete backing state only for operations that require iteration."
  (let ((materializer (state-db-materializer state)))
    (when materializer
      (setf (state-db-materializer state) nil)
      (funcall materializer state)))
  state)

(defun make-lazy-state-db (account-loader storage-loader materializer)
  "Create a state whose historical backing is resolved on first access."
  (let ((state (make-state-db)))
    (setf (state-db-account-loader state) account-loader
          (state-db-storage-loader state) storage-loader
          (state-db-materializer state) materializer)
    state))

(declaim (ftype (function (t) t) clone-state-object))

(defun state-db-record-change (state key)
  (unless (state-db-reverting-p state)
    (let ((object (gethash key (state-db-objects state))))
      (vector-push-extend
       (make-state-journal-entry
        :key key
        :previous-object (and object (clone-state-object object)))
       (state-db-journal state))))
  state)

(defun state-db-snapshot (state)
  "Return an O(1) mark for reverting subsequent state mutations."
  (fill-pointer (state-db-journal state)))

(defun state-db-touch-account (state address)
  "Journal an EIP-161 touch without otherwise mutating the account."
  (state-db-record-change state (address-key address)))

(defun state-db-revert-to-snapshot (state snapshot)
  "Replay journal entries backwards to SNAPSHOT and discard them."
  (let ((journal (state-db-journal state)))
    (unless (and (integerp snapshot)
                 (<= 0 snapshot (fill-pointer journal)))
      (error "State snapshot mark is invalid: ~S" snapshot))
    (let ((previous-reverting-p (state-db-reverting-p state)))
      (unwind-protect
           (progn
             (setf (state-db-reverting-p state) t)
             (loop while (> (fill-pointer journal) snapshot)
                   for entry = (vector-pop journal)
                   for key = (state-journal-entry-key entry)
                   for previous = (state-journal-entry-previous-object entry)
                   do (if previous
                          (setf (gethash key (state-db-objects state)) previous)
                          (remhash key (state-db-objects state)))
                      (mark-account-dirty state key)))
        (setf (state-db-reverting-p state) previous-reverting-p))))
  state)

(defun state-db-get-account (state address)
  (let ((object (state-db-get-object state address)))
    (and object
         (state-object-account object)
         (account-with-storage-root object))))

(defun empty-state-account-p (account)
  (and account
       (zerop (state-account-nonce account))
       (zerop (state-account-balance account))
       (bytes= (hash32-bytes (state-account-storage-root account))
               (hash32-bytes +empty-trie-hash+))
       (bytes= (hash32-bytes (state-account-code-hash account))
               (hash32-bytes +empty-code-hash+))))

(defun mark-account-dirty (state key)
  "Record that the account at address KEY changed, so the next STATE-DB-ROOT
recomputes. See the STATE-DB DIRTY/CACHED-ROOT invariant."
  (setf (gethash key (state-db-dirty state)) t)
  state)

(defun empty-state-object-p (object)
  (and object
       (empty-state-account-p (state-object-account object))
       (zerop (length (state-object-code object)))
       (zerop (hash-table-count (state-object-storage object)))))

(defun state-db-finalize-transaction (state snapshot delete-empty-objects-p)
  "Finalize accounts touched since SNAPSHOT.

When DELETE-EMPTY-OBJECTS-P is false (pre-EIP-158), touched empty accounts are
retained. The journal remains intact so an enclosing block snapshot can still
revert the transaction."
  (when delete-empty-objects-p
    (let ((journal (state-db-journal state))
          (keys (make-hash-table :test #'equal)))
      (loop for index from snapshot below (fill-pointer journal)
            for entry = (aref journal index)
            do (setf (gethash (state-journal-entry-key entry) keys) t))
      (maphash
       (lambda (key ignored)
         (declare (ignore ignored))
         (let ((object (gethash key (state-db-objects state))))
           (when (empty-state-object-p object)
             (state-db-record-change state key)
             (remhash key (state-db-objects state))
             (mark-account-dirty state key))))
       keys)))
  state)

(defun prune-empty-state-object (state key object)
  (when (empty-state-object-p object)
    (remhash key (state-db-objects state))
    (mark-account-dirty state key))
  state)

(defun state-object-code-hash (object account)
  (if (plusp (length (state-object-code object)))
      (keccak-256-hash (state-object-code object))
      (state-account-code-hash account)))

(defun state-account-with-object-commitments (object account)
  (make-state-account
   :nonce (state-account-nonce account)
   :balance (state-account-balance account)
   :storage-root (storage-root object)
   :code-hash (state-object-code-hash object account)))

(defun state-db-set-account (state address account)
  (let ((key (address-key address)))
    (state-db-get-object state address)
    (state-db-record-change state key)
    (let ((object (or (gethash key (state-db-objects state))
                      (setf (gethash key (state-db-objects state))
                            (make-state-object)))))
      (setf (state-object-account object)
            (state-account-with-object-commitments object account))
      (mark-account-dirty state key)
      state)))

(defun state-db-account-or-empty (state address)
  (or (state-db-get-account state address)
      (make-state-account)))

(defun state-db-put-account-values (state address nonce balance code-hash)
  (state-db-set-account
   state
   address
   (make-state-account :nonce nonce
                       :balance balance
                       :code-hash code-hash)))

(defun state-db-transfer-value (state sender recipient value)
  (unless (bytes= (address-bytes sender) (address-bytes recipient))
    (when (plusp value)
      (let ((sender-account (state-db-account-or-empty state sender))
            (recipient-account (state-db-account-or-empty state recipient)))
        (state-db-put-account-values
         state sender
         (state-account-nonce sender-account)
         (- (state-account-balance sender-account) value)
         (state-account-code-hash sender-account))
        (state-db-put-account-values
         state recipient
         (state-account-nonce recipient-account)
         (+ (state-account-balance recipient-account) value)
         (state-account-code-hash recipient-account)))))
  state)

(defun state-db-add-balance (state address amount)
  (let ((amount (ensure-state-uint256 amount "Balance amount")))
    (unless (zerop amount)
      (let ((account (state-db-account-or-empty state address)))
        (state-db-put-account-values
         state
         address
         (state-account-nonce account)
         (+ (state-account-balance account) amount)
         (state-account-code-hash account)))))
  state)

(defun state-db-clear-account (state address)
  (let ((key (address-key address)))
    (state-db-get-object state address)
    (state-db-record-change state key)
    (remhash key (state-db-objects state))
    (mark-account-dirty state key))
  state)

(defun state-db-set-code (state address code)
  (let* ((key (address-key address))
         (code (ensure-byte-vector code)))
    (state-db-get-object state address)
    (when (or (gethash key (state-db-objects state))
              (plusp (length code)))
      (state-db-record-change state key))
    (let ((object (or (gethash key (state-db-objects state))
                      (and (plusp (length code))
                           (setf (gethash key (state-db-objects state))
                                 (make-state-object))))))
    (when object
      (setf (state-object-code object) code)
      (let ((account (or (state-object-account object) (make-state-account))))
        (setf (state-object-account object)
              (make-state-account
               :nonce (state-account-nonce account)
               :balance (state-account-balance account)
               :storage-root (state-account-storage-root account)
               :code-hash (keccak-256-hash code))))
      (mark-account-dirty state key))
      state)))

(defun state-db-get-code (state address)
  (let ((object (state-db-get-object state address)))
    (if object
        (state-object-code object)
        (make-byte-vector 0))))

(defun state-db-get-code-hash (state address)
  (let ((account (state-db-get-account state address)))
    (if account
        (state-account-code-hash account)
        +empty-code-hash+)))

(defun copy-state-account (account)
  (and account
       (make-state-account
        :nonce (state-account-nonce account)
        :balance (state-account-balance account)
        :storage-root (state-account-storage-root account)
        :code-hash (state-account-code-hash account))))

(defun copy-hash-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun clone-state-object (object)
  (make-state-object
   :account (copy-state-account (state-object-account object))
   :code (subseq (state-object-code object) 0)
   :storage (copy-hash-table (state-object-storage object))
   ;; The clone's storage is EQUAL to the original's, so a root already proved
   ;; for those contents is equally true here. Carrying it matters: snapshots
   ;; are taken per call frame, and dropping it would re-hash the world after
   ;; every one.
   :cached-storage-root (state-object-cached-storage-root object)))

(defun state-db-copy (state)
  (let ((copy (make-state-db)))
    (maphash (lambda (address object)
               (setf (gethash address (state-db-objects copy))
                     (clone-state-object object)))
             (state-db-objects state))
    ;; Carry the account-root memo state so the invariant holds in the copy:
    ;; if DIRTY was empty, CACHED-ROOT stays valid for the cloned OBJECTS.
    (setf (state-db-dirty copy) (copy-hash-table (state-db-dirty state))
          (state-db-cached-root copy) (state-db-cached-root state)
          (state-db-account-loader copy) (state-db-account-loader state)
          (state-db-storage-loader copy) (state-db-storage-loader state)
          (state-db-materializer copy) (state-db-materializer state)
          (state-db-loaded-accounts copy)
          (copy-hash-table (state-db-loaded-accounts state))
          (state-db-loaded-storage copy)
          (copy-hash-table (state-db-loaded-storage state)))
    ;; The copy gets NO trie. Sharing one would let a frame that is later
    ;; reverted leave its mutations in the parent's trie, which is a wrong state
    ;; root and so a consensus divergence; copying one on every CALL frame would
    ;; cost more than the rebuild it saves. The copy rebuilds if it ever flushes.
    (setf (state-db-trie copy) nil)
    copy))

(defun state-db-restore (state snapshot)
  (clrhash (state-db-objects state))
  (maphash (lambda (address object)
             (setf (gethash address (state-db-objects state))
                   (clone-state-object object)))
           (state-db-objects snapshot))
  ;; Wholesale-reset the memo to the snapshot's: OBJECTS now equals the
  ;; snapshot's, so its DIRTY/CACHED-ROOT are exactly right for the restored
  ;; state. (A fold that ran inside the snapshot bracket is undone here.)
  ;; The trie is dropped rather than reconciled: whatever it holds now describes
  ;; the objects we just discarded.
  (setf (state-db-dirty state) (copy-hash-table (state-db-dirty snapshot))
        (state-db-cached-root state) (state-db-cached-root snapshot)
        (state-db-account-loader state) (state-db-account-loader snapshot)
        (state-db-storage-loader state) (state-db-storage-loader snapshot)
        (state-db-materializer state) (state-db-materializer snapshot)
        (state-db-loaded-accounts state)
        (copy-hash-table (state-db-loaded-accounts snapshot))
        (state-db-loaded-storage state)
        (copy-hash-table (state-db-loaded-storage snapshot))
        (state-db-trie state) nil)
  state)

(defun state-db-set-storage (state address slot value)
  (let* ((key (address-key address))
         (value (ensure-state-uint256 value "Storage value")))
    (state-db-get-object state address)
    ;; Preserve a lazily-backed slot's before-image before mutating it.
    (state-db-get-storage state address slot)
    (when (or (gethash key (state-db-objects state))
              (not (zerop value)))
      (state-db-record-change state key))
    (let* ((object (or (gethash key (state-db-objects state))
                       (and (not (zerop value))
                            (setf (gethash key (state-db-objects state))
                                  (make-state-object
                                   :account (make-state-account))))))
           (storage-key (storage-key slot))
           (storage (and object (state-object-storage object))))
    ;; The one place STORAGE changes: drop the object's memoized storage root
    ;; AND mark the account dirty -- the account leaf embeds the storage root
    ;; (state-account-with-object-commitments), so a storage-only write changes
    ;; the ACCOUNT trie even when nonce/balance/code are untouched. Marking the
    ;; storage root alone (wave 3a) is not enough for the account root.
    (when object
      (setf (state-object-cached-storage-root object) nil)
      (mark-account-dirty state key))
    (cond
      ((zerop value)
       (when object
         (remhash storage-key storage)))
      (t
       (setf (gethash storage-key storage) value)))
      state)))

(defun state-db-get-storage (state address slot)
  (let ((object (state-db-get-object state address)))
    (if object
        (let* ((key (address-key address))
               (slot-key (storage-key slot))
               (loaded-key (format nil "~A:~A" key slot-key))
               (storage (state-object-storage object)))
          (unless (or (nth-value 1 (gethash slot-key storage))
                      (gethash loaded-key (state-db-loaded-storage state)))
            (setf (gethash loaded-key (state-db-loaded-storage state)) t)
            (let ((loader (state-db-storage-loader state)))
              (when loader
                (let ((value (funcall loader address slot)))
                  (unless (zerop value)
                    (setf (gethash slot-key storage) value))))))
          (gethash slot-key storage 0))
        0)))

(defun uint256-to-32-byte-hash (value)
  (let ((out (make-byte-vector 32))
        (bytes (integer-to-minimal-bytes (ensure-state-uint256 value "Storage slot"))))
    (replace out bytes :start1 (- 32 (length bytes)))
    (make-hash32 out)))

(defun state-db-storage-proof-key (slot)
  (keccak-256 (hash32-bytes slot)))

(defun state-object-storage-trie (object)
  (let ((trie (make-mpt)))
    (when object
      (maphash (lambda (slot value)
                 (mpt-put trie
                          (state-db-storage-proof-key (hash32-from-hex slot))
                          (rlp-encode value)))
               (state-object-storage object)))
    trie))

(defun storage-root (object)
  (or (and object (state-object-cached-storage-root object))
      (let ((root (make-hash32 (mpt-root-hash (state-object-storage-trie object)))))
        (when object
          (setf (state-object-cached-storage-root object) root))
        root)))

(defun state-db-get-storage-root (state address)
  (storage-root (state-db-get-object state address)))

(defun state-db-get-storage-proof (state address slot)
  (mpt-get-proof (state-object-storage-trie (state-db-get-object state address))
                 (state-db-storage-proof-key slot)))

(defun state-db-verify-storage-proof (storage-root slot proof)
  (mpt-verify-proof storage-root (state-db-storage-proof-key slot) proof))

(defun account-with-storage-root (object)
  (let ((account (or (state-object-account object) (make-state-account))))
    (state-account-with-object-commitments object account)))
