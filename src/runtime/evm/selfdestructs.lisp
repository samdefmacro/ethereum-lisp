(in-package #:ethereum-lisp.evm.internal)

(defun copy-selfdestructed-addresses (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-selfdestructed-addresses context)))
    copy))

(defun restore-selfdestructed-addresses (context snapshot)
  (when context
    (let ((selfdestructed (evm-context-selfdestructed-addresses context)))
      (clrhash selfdestructed)
      (maphash (lambda (key value)
                 (setf (gethash key selfdestructed) value))
               snapshot))))

(defun mark-selfdestructed-address (context address)
  (setf (gethash (address-to-hex address)
                 (evm-context-selfdestructed-addresses context))
        t))

(defun finalize-evm-selfdestructs (state context)
  (maphash
   (lambda (key selfdestructed-p)
     (when selfdestructed-p
       (state-db-clear-account state (address-from-hex key))))
   (evm-context-selfdestructed-addresses context)))

;;; EIP-6780: accounts created during the current transaction. Tracked to
;;; decide whether SELFDESTRUCT deletes the account (only same-transaction
;;; creations are deleted post-Cancun). The set rolls back with frame and
;;; execution snapshots so a reverted creation is no longer "created".

(defun copy-created-accounts (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when (and context (evm-context-created-accounts context))
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-created-accounts context)))
    copy))

(defun restore-created-accounts (context snapshot)
  (when (and context (evm-context-created-accounts context))
    (let ((created (evm-context-created-accounts context)))
      (clrhash created)
      (maphash (lambda (key value)
                 (setf (gethash key created) value))
               snapshot))))

(defun mark-created-account (context address)
  (when (and context (evm-context-created-accounts context))
    (setf (gethash (address-to-hex address)
                   (evm-context-created-accounts context))
          t)))

(defun account-created-this-transaction-p (context address)
  (and context
       (evm-context-created-accounts context)
       (gethash (address-to-hex address)
                (evm-context-created-accounts context))
       t))
