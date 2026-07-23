(in-package #:ethereum-lisp.chain-store)

(defun engine-payload-store-state-available-p
    (store hash)
  (setf store (chain-store-require-memory-store store))
  (not (null
        (gethash (engine-payload-store-key hash)
                 (memory-chain-store-state-blocks store)))))

(defgeneric chain-store-state-available-p (store hash))

(defmethod chain-store-state-available-p ((store t) hash)
  (engine-payload-store-state-available-p
   (chain-store-require-memory-store store)
   hash))

(defun engine-payload-store-string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))
