(in-package #:ethereum-lisp.blocks)

(defun block-transaction-rlp-object (transaction)
  (let ((encoded (transaction-encoding transaction)))
    (if (> (aref encoded 0) #x7f)
        (rlp-decode-one encoded)
        encoded)))

(defun block-transactions-rlp-object (transactions)
  (apply #'make-rlp-list
         (mapcar #'block-transaction-rlp-object transactions)))

(defun block-ommers-rlp-object (ommers)
  (apply #'make-rlp-list
         (mapcar #'block-header-rlp-object ommers)))

(defun block-withdrawals-rlp-object (withdrawals)
  (apply #'make-rlp-list
         (mapcar #'withdrawal-rlp-object withdrawals)))

(defun block-requests-rlp-object (requests)
  (apply #'make-rlp-list
         (mapcar #'rlp-decode-one requests)))

(defun block-access-list-rlp-object-for-block (block)
  (rlp-decode-one
   (or (block-encoded-block-access-list block)
       (block-access-list-rlp (block-block-access-list block)))))

(defun block-rlp (block)
  (let ((fields
          (list (block-header-rlp-object (block-header block))
                (block-transactions-rlp-object
                 (block-transactions block))
                (block-ommers-rlp-object (block-ommers block)))))
    (when (block-withdrawals-present-p block)
      (setf fields
            (append fields
                    (list (block-withdrawals-rlp-object
                           (block-withdrawals block))))))
    (when (block-requests-present-p block)
      (setf fields
            (append fields
                    (list (block-requests-rlp-object
                           (block-requests block))))))
    (when (block-block-access-list-present-p block)
      (setf fields
            (append fields
                    (list (block-access-list-rlp-object-for-block block)))))
    (rlp-encode (apply #'make-rlp-list fields))))
