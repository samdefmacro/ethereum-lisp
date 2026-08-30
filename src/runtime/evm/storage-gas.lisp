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

(defun legacy-sstore-gas-and-refund (current-value new-value)
  (cond
    ((and (zerop current-value) (not (zerop new-value)))
     (values +sstore-set-gas-eip2200+ 0))
    ((and (not (zerop current-value)) (zerop new-value))
     (values +sstore-reset-gas-eip2200+ +sstore-clear-refund-legacy+))
    (t
     (values +sstore-reset-gas-eip2200+ 0))))

(defun net-sstore-gas-and-refund
    (original-value current-value new-value
     sload-gas reset-gas clear-refund &optional (access-cost 0))
  "Return EIP-1283/EIP-2200 gas and signed refund delta."
  (cond
    ((= current-value new-value)
     (values (+ access-cost sload-gas) 0))
    ((= original-value current-value)
     (if (zerop original-value)
         (values (+ access-cost +sstore-set-gas-eip2200+) 0)
         (values (+ access-cost reset-gas)
                 (if (zerop new-value) clear-refund 0))))
    (t
     (let ((refund 0))
       (when (not (zerop original-value))
         (when (zerop current-value)
           (decf refund clear-refund))
         (when (zerop new-value)
           (incf refund clear-refund)))
       (when (= original-value new-value)
         (incf refund
               (- (if (zerop original-value)
                      +sstore-set-gas-eip2200+
                      reset-gas)
                  sload-gas)))
       (values (+ access-cost sload-gas) refund)))))

(defun historical-sstore-gas-and-refund
    (context original-value current-value new-value address slot)
  (cond
    ((context-berlin-p context)
     (net-sstore-gas-and-refund
      original-value current-value new-value
      +warm-storage-read-cost-eip2929+
      (- +sstore-reset-gas-eip2200+ +cold-sload-cost-eip2929+)
      (if (context-london-p context)
          +sstore-clears-schedule-refund-eip3529+
          +sstore-clear-refund-legacy+)
      (if (gethash (storage-refund-key address slot)
                   (evm-context-accessed-storage context))
          0
          +cold-sload-cost-eip2929+)))
    ((context-istanbul-p context)
     (net-sstore-gas-and-refund
      original-value current-value new-value
      +sstore-load-gas-istanbul+ +sstore-reset-gas-eip2200+
      +sstore-clear-refund-legacy+))
    ((and (context-constantinople-p context)
          (not (context-petersburg-p context)))
     (net-sstore-gas-and-refund
      original-value current-value new-value
      +sstore-load-gas-eip150+ +sstore-reset-gas-eip2200+
      +sstore-clear-refund-legacy+))
    (t
     (legacy-sstore-gas-and-refund current-value new-value))))

(defun sstore-amsterdam-regular-gas
    (access-cost original-value current-value new-value)
  (if (and (/= current-value new-value)
           (= original-value current-value))
      (+ access-cost +storage-write-amsterdam+)
      access-cost))
