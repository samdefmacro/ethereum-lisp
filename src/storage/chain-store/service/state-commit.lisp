(in-package #:ethereum-lisp.chain-store)

;;; Commit policy: diff against the parent when it stays within the
;;; baseline interval, otherwise store a full baseline.

(defun engine-payload-store-commit-baseline (store block-hash iterate-accounts)
  (chain-store-journal-remhash
   (memory-chain-store-state-diffs store)
   (engine-payload-store-key block-hash))
  (funcall
   iterate-accounts
   (lambda (address balance nonce code storage-entries)
     (engine-payload-store-put-account-balance
      store block-hash address balance)
     (engine-payload-store-put-account-nonce
      store block-hash address nonce)
     (engine-payload-store-put-account-code
      store block-hash address code)
     (dolist (entry storage-entries)
       (engine-payload-store-put-account-storage
        store block-hash address (car entry) (cdr entry)))))
  :baseline)

(defun engine-payload-store-commit-diff
    (store block-hash parent-key iterate-accounts)
  "Diff the post-state delivered by ITERATE-ACCOUNTS against the parent's
resolved view and install the result. Returns :DIFF, or NIL when the parent
view is unresolvable."
  (multiple-value-bind (parent-balances parent-nonces parent-codes
                        parent-storage)
      (engine-payload-store-collect-state-view store parent-key)
    (unless parent-balances
      (return-from engine-payload-store-commit-diff nil))
    (let ((balances (make-hash-table :test 'equal))
          (nonces (make-hash-table :test 'equal))
          (codes (make-hash-table :test 'equal))
          (storage (make-hash-table :test 'equal))
          (live-addresses (make-hash-table :test 'equal))
          (parent-slots-by-address (make-hash-table :test 'equal)))
      (maphash (lambda (suffix value)
                 (declare (ignore value))
                 (let ((separator (position #\: suffix)))
                   (when separator
                     (push suffix
                           (gethash (subseq suffix 0 separator)
                                    parent-slots-by-address)))))
               parent-storage)
      (funcall
       iterate-accounts
       (lambda (address balance nonce code storage-entries)
         (let ((address-hex (address-to-hex address))
               (code (ensure-byte-vector code)))
           (setf (gethash address-hex live-addresses) t)
           (multiple-value-bind (parent-value present-p)
               (gethash address-hex parent-balances)
             (unless (and present-p (eql parent-value balance))
               (setf (gethash address-hex balances) balance)))
           (multiple-value-bind (parent-value present-p)
               (gethash address-hex parent-nonces)
             (unless (and present-p (eql parent-value nonce))
               (setf (gethash address-hex nonces) nonce)))
           (multiple-value-bind (parent-value present-p)
               (gethash address-hex parent-codes)
             (unless (and present-p (bytes= parent-value code))
               (setf (gethash address-hex codes) (copy-seq code))))
           (let ((post-slots (make-hash-table :test 'equal)))
             (dolist (entry storage-entries)
               (let ((suffix (format nil "~A:~A"
                                     address-hex
                                     (hash32-to-hex (car entry)))))
                 (setf (gethash suffix post-slots) t)
                 (multiple-value-bind (parent-value present-p)
                     (gethash suffix parent-storage)
                   (unless (and present-p (eql parent-value (cdr entry)))
                     (setf (gethash suffix storage) (cdr entry))))))
             (dolist (suffix (gethash address-hex parent-slots-by-address))
               (unless (gethash suffix post-slots)
                 (setf (gethash suffix storage) 0)))))))
      ;; Tombstone parent accounts that no longer exist.
      (dolist (address-hex (engine-payload-store-state-view-addresses
                            parent-balances parent-nonces parent-codes
                            parent-storage))
        (unless (gethash address-hex live-addresses)
          (setf (gethash address-hex balances) :absent
                (gethash address-hex nonces) :absent
                (gethash address-hex codes) :absent)
          (dolist (suffix (gethash address-hex parent-slots-by-address))
            (setf (gethash suffix storage) 0))))
      (chain-store-put-state-diff
       store block-hash
       (hash32-from-hex parent-key)
       :balances balances
       :nonces nonces
       :codes codes
       :storage storage)
      :diff)))

(defun engine-payload-store-commit-diff-touched
    (store block-hash parent-hash iterate-touched)
  "Diff only the accounts a block touched against the parent, resolving each one
through the diff chain on demand instead of building the whole parent view.

ITERATE-TOUCHED calls its visitor with (ADDRESS PRESENT-P BALANCE NONCE CODE
STORAGE-ENTRIES) for each touched account; PRESENT-P is NIL for one destroyed
during the block. This is the touched-set equivalent of
ENGINE-PAYLOAD-STORE-COMMIT-DIFF and installs the identical diff: a present
account records only the fields and slots that differ from the parent, deleted
parent slots are zeroed, and a destroyed account that existed in the parent is
tombstoned. Returns :DIFF."
  (let ((balances (make-hash-table :test 'equal))
        (nonces (make-hash-table :test 'equal))
        (codes (make-hash-table :test 'equal))
        (storage (make-hash-table :test 'equal)))
    (flet ((parent-code-present (address-hex)
             (engine-payload-store-resolve-state-value
              store parent-hash #'chain-state-diff-codes address-hex
              (memory-chain-store-account-codes store) nil)))
      (funcall
       iterate-touched
       (lambda (address present-p balance nonce code storage-entries)
         (let ((address-hex (address-to-hex address)))
           (if present-p
               (let ((code (ensure-byte-vector code))
                     (post-slots (make-hash-table :test 'equal))
                     (parent-slots (make-hash-table :test 'equal)))
                 (multiple-value-bind (parent-value present)
                     (engine-payload-store-account-balance
                      store parent-hash address)
                   (unless (and present (eql parent-value balance))
                     (setf (gethash address-hex balances) balance)))
                 (multiple-value-bind (parent-value present)
                     (engine-payload-store-account-nonce
                      store parent-hash address)
                   (unless (and present (eql parent-value nonce))
                     (setf (gethash address-hex nonces) nonce)))
                 (multiple-value-bind (parent-value present)
                     (parent-code-present address-hex)
                   (unless (and present (bytes= parent-value code))
                     (setf (gethash address-hex codes) (copy-seq code))))
                 ;; Resolve the parent account's live slots once, then diff.
                 (dolist (entry (chain-store-account-storage-entries
                                 store parent-hash address))
                   (setf (gethash (hash32-to-hex (car entry)) parent-slots)
                         (cdr entry)))
                 (dolist (entry storage-entries)
                   (let ((slot-hex (hash32-to-hex (car entry)))
                         (value (cdr entry)))
                     (setf (gethash slot-hex post-slots) t)
                     (multiple-value-bind (parent-value present)
                         (gethash slot-hex parent-slots)
                       (unless (and present (eql parent-value value))
                         (setf (gethash
                                (format nil "~A:~A" address-hex slot-hex)
                                storage)
                               value)))))
                 (maphash
                  (lambda (slot-hex parent-value)
                    (declare (ignore parent-value))
                    (unless (gethash slot-hex post-slots)
                      (setf (gethash (format nil "~A:~A" address-hex slot-hex)
                                     storage)
                            0)))
                  parent-slots))
               ;; Destroyed: tombstone only when the parent actually held it.
               (let ((parent-slots (chain-store-account-storage-entries
                                    store parent-hash address)))
                 (multiple-value-bind (balance-value balance-present)
                     (engine-payload-store-account-balance
                      store parent-hash address)
                   (declare (ignore balance-value))
                   (multiple-value-bind (nonce-value nonce-present)
                       (engine-payload-store-account-nonce
                        store parent-hash address)
                     (declare (ignore nonce-value))
                     (multiple-value-bind (code-value code-present)
                         (parent-code-present address-hex)
                       (declare (ignore code-value))
                       (when (or balance-present nonce-present
                                 code-present parent-slots)
                         (setf (gethash address-hex balances) :absent
                               (gethash address-hex nonces) :absent
                               (gethash address-hex codes) :absent)
                         (dolist (entry parent-slots)
                           (setf (gethash
                                  (format nil "~A:~A" address-hex
                                          (hash32-to-hex (car entry)))
                                  storage)
                                 0)))))))))))
      (chain-store-put-state-diff
       store block-hash parent-hash
       :balances balances
       :nonces nonces
       :codes codes
       :storage storage)
      :diff)))

(defun chain-store-commit-post-state
    (store block-hash iterate-accounts &key iterate-touched)
  "Commit a block's post-state. ITERATE-ACCOUNTS is called with a visitor
function receiving (ADDRESS BALANCE NONCE CODE STORAGE-ENTRIES) for every
live account. Stores a diff against the parent when the parent state is
resolvable and the diff chain stays under the store's baseline interval;
otherwise stores a full baseline. Returns the kind stored.

ITERATE-TOUCHED, when supplied, drives the diff path from only the accounts the
block touched (see ENGINE-PAYLOAD-STORE-COMMIT-DIFF-TOUCHED), avoiding the
whole-world iteration and parent view of the full diff; the baseline path always
uses ITERATE-ACCOUNTS, which enumerates every account. Callers pass it only for
a lazily-backed post-state, whose untouched remainder equals the parent."
  (let* ((store (chain-store-require-memory-store store))
         (block (engine-payload-store-known-block store block-hash))
         (parent-hash (and block
                           (block-header-parent-hash
                            (block-header block))))
         (parent-key (and parent-hash
                          (engine-payload-store-key parent-hash))))
    (or (and parent-key
             (engine-payload-store-state-kind-for-key store parent-key)
             (let ((distance (engine-payload-store-state-baseline-distance
                              store parent-hash)))
               (and distance
                    (< (1+ distance)
                       (memory-chain-store-state-baseline-interval store))
                    (if iterate-touched
                        (engine-payload-store-commit-diff-touched
                         store block-hash parent-hash iterate-touched)
                        (engine-payload-store-commit-diff
                         store block-hash parent-key iterate-accounts)))))
        (engine-payload-store-commit-baseline
         store block-hash iterate-accounts))))
