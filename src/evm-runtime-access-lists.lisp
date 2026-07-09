(in-package #:ethereum-lisp.evm)

(defun storage-access-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun account-access-key (address)
  (address-bytes address))

(defun copy-accessed-storage (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-accessed-storage context)))
    copy))

(defun restore-accessed-storage (context snapshot)
  (when context
    (let ((accessed-storage (evm-context-accessed-storage context)))
      (clrhash accessed-storage)
      (maphash (lambda (key value)
                 (setf (gethash key accessed-storage) value))
               snapshot))))

(defun copy-accessed-addresses (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-accessed-addresses context)))
    copy))

(defun restore-accessed-addresses (context snapshot)
  (when context
    (let ((accessed-addresses (evm-context-accessed-addresses context)))
      (clrhash accessed-addresses)
      (maphash (lambda (key value)
                 (setf (gethash key accessed-addresses) value))
               snapshot))))

(defun account-cold-access-surcharge (context address)
  (if (gethash (account-access-key address)
               (evm-context-accessed-addresses context))
      0
      (- +cold-account-access-cost-eip2929+
         +warm-storage-read-cost-eip2929+)))

(defun mark-account-accessed (context address)
  (setf (gethash (account-access-key address)
                 (evm-context-accessed-addresses context))
        t))

(defun charge-account-access-gas (context address charge-extra-gas)
  (let ((cost (account-cold-access-surcharge context address)))
    (funcall charge-extra-gas cost)
    (mark-account-accessed context address)))

(defun charge-cold-account-access-gas (context address charge-extra-gas)
  (unless (gethash (account-access-key address)
                   (evm-context-accessed-addresses context))
    (funcall charge-extra-gas +cold-account-access-cost-eip2929+)
    (mark-account-accessed context address)))

(defun storage-access-cost (context address slot)
  (let ((key (storage-access-key address slot)))
    (if (gethash key (evm-context-accessed-storage context))
        +warm-storage-read-cost-eip2929+
        +cold-sload-cost-eip2929+)))

(defun storage-cold-access-surcharge (context address slot)
  (let ((key (storage-access-key address slot)))
    (if (gethash key (evm-context-accessed-storage context))
        0
        +cold-sload-cost-eip2929+)))

(defun mark-storage-accessed (context address slot)
  (setf (gethash (storage-access-key address slot)
                 (evm-context-accessed-storage context))
        t))

(defun charge-storage-read-access-gas (context address slot charge-extra-gas)
  (let ((cost (storage-access-cost context address slot)))
    (funcall charge-extra-gas cost)
    (mark-storage-accessed context address slot)))
