(in-package #:ethereum-lisp.evm.internal)

(defun storage-refund-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

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
