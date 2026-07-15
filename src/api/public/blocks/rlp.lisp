(in-package #:ethereum-lisp.public-api)

(defun eth-rpc-rlp-length-prefix (offset length)
  (if (<= length 55)
      (ensure-byte-vector (list (+ offset length)))
      (let ((length-bytes (integer-to-minimal-bytes length)))
        (concat-bytes
         (ensure-byte-vector (list (+ offset 55 (length length-bytes))))
         length-bytes))))

(defun eth-rpc-encoded-rlp-list (encoded-items)
  (let ((payload (if encoded-items
                     (apply #'concat-bytes encoded-items)
                     (make-byte-vector 0))))
    (concat-bytes (eth-rpc-rlp-length-prefix #xc0 (length payload))
                  payload)))

(defun eth-rpc-block-rlp (block)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "eth block result must be a block"))
  (let ((items
          (list
           (block-header-rlp (block-header block))
           (eth-rpc-encoded-rlp-list
            (mapcar #'transaction-encoding (block-transactions block)))
           (eth-rpc-encoded-rlp-list
            (mapcar #'block-header-rlp (block-ommers block))))))
    (when (block-withdrawals-present-p block)
      (setf items
            (append items
                    (list (eth-rpc-encoded-rlp-list
                           (mapcar #'withdrawal-rlp
                                   (block-withdrawals block)))))))
    (eth-rpc-encoded-rlp-list items)))
