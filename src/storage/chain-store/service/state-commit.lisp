(in-package #:ethereum-lisp.chain-store)

;;; Commit policy: diff against the parent when it stays within the
;;; baseline interval, otherwise store a full baseline.

(defun engine-payload-store-commit-baseline (store block-hash iterate-accounts)
  (remhash (engine-payload-store-key block-hash)
           (memory-chain-store-state-diffs store))
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

(defun chain-store-commit-post-state (store block-hash iterate-accounts)
  "Commit a block's post-state. ITERATE-ACCOUNTS is called with a visitor
function receiving (ADDRESS BALANCE NONCE CODE STORAGE-ENTRIES) for every
live account. Stores a diff against the parent when the parent state is
resolvable and the diff chain stays under the store's baseline interval;
otherwise stores a full baseline. Returns the kind stored."
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
                    (engine-payload-store-commit-diff
                     store block-hash parent-key iterate-accounts))))
        (engine-payload-store-commit-baseline
         store block-hash iterate-accounts))))
