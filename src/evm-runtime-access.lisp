(in-package #:ethereum-lisp.evm)

(defun transient-storage-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun storage-refund-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun storage-access-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun account-access-key (address)
  (address-bytes address))

(defun transient-storage-get (context address slot)
  (gethash (transient-storage-key address slot)
           (evm-context-transient-storage context)
           0))

(defun transient-storage-set (context address slot value)
  (let ((key (transient-storage-key address slot)))
    (if (zerop value)
        (remhash key (evm-context-transient-storage context))
        (setf (gethash key (evm-context-transient-storage context))
              (word value)))))

(defun copy-transient-storage (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-transient-storage context)))
    copy))

(defun restore-transient-storage (context snapshot)
  (when context
    (let ((storage (evm-context-transient-storage context)))
      (clrhash storage)
      (maphash (lambda (key value)
                 (setf (gethash key storage) value))
               snapshot))))

(defun copy-storage-clears (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-storage-clears context)))
    copy))

(defun restore-storage-clears (context snapshot)
  (when context
    (let ((clears (evm-context-storage-clears context)))
      (clrhash clears)
      (maphash (lambda (key value)
                 (setf (gethash key clears) value))
               snapshot))))

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

(defun sstore-dynamic-gas (access-cost original-value current-value new-value)
  (cond
    ((= current-value new-value)
     (+ access-cost +warm-storage-read-cost-eip2929+))
    ((= original-value current-value)
     (+ access-cost
        (if (zerop original-value)
            +sstore-set-gas-eip2200+
            (- +sstore-reset-gas-eip2200+
               +cold-sload-cost-eip2929+))))
    (t
     (+ access-cost +warm-storage-read-cost-eip2929+))))
