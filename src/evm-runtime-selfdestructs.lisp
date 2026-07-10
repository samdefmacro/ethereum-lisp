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
