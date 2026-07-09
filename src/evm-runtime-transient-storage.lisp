(in-package #:ethereum-lisp.evm)

(defun transient-storage-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

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
