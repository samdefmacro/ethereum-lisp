(in-package #:ethereum-lisp.chain-store.persistence)

(defun log-entry-from-rlp-object (value)
  (let ((fields (rlp-list-field value "Receipt log entry")))
    (unless (= (length fields) 3)
      (block-validation-fail "Receipt log entry must contain 3 fields"))
    (make-log-entry
     :address (rlp-address-field (first fields) "Receipt log address")
     :topics (mapcar (lambda (topic)
                       (rlp-hash32-field topic "Receipt log topic"))
                     (rlp-list-field (second fields) "Receipt log topics"))
     :data (rlp-bytes-field (third fields) "Receipt log data"))))

(defun receipt-status-from-rlp-field (value)
  (let ((bytes (rlp-bytes-field value "Receipt status")))
    (cond
      ((zerop (length bytes))
       (values nil 0))
      ((and (= (length bytes) 1)
            (= (aref bytes 0) 1))
       (values nil 1))
      ((= (length bytes) 32)
       (values bytes 1))
      (t
       (block-validation-fail
        "Receipt status must be empty, 0x01, or 32-byte post-state")))))

(defun receipt-from-rlp-object (value)
  (let ((fields (rlp-list-field value "Receipt")))
    (unless (= (length fields) 4)
      (block-validation-fail "Receipt must contain 4 fields"))
    (multiple-value-bind (post-state status)
        (receipt-status-from-rlp-field (first fields))
      (let* ((logs (mapcar #'log-entry-from-rlp-object
                           (rlp-list-field (fourth fields)
                                           "Receipt logs")))
             (expected-bloom
               (rlp-sized-bytes-field (third fields) 256 "Receipt bloom"))
             (actual-bloom (bloom-bytes (receipt-bloom logs))))
        (unless (bytes= expected-bloom actual-bloom)
          (block-validation-fail
           "Receipt bloom does not match decoded receipt logs"))
        (make-receipt
         :post-state post-state
         :status status
         :cumulative-gas-used
         (rlp-uint-field (second fields) "Receipt cumulative gas used")
         :logs logs)))))

(defun receipt-from-transaction-encoding (transaction encoded)
  (let ((encoded (ensure-byte-vector encoded))
        (type (transaction-type transaction)))
    (if (zerop type)
        (receipt-from-rlp-object (rlp-decode-one encoded))
        (progn
          (when (< (length encoded) 2)
            (block-validation-fail "Typed receipt encoding is too short"))
          (unless (= type (aref encoded 0))
            (block-validation-fail
             "Typed receipt prefix does not match transaction type"))
          (receipt-from-rlp-object (rlp-decode-one (subseq encoded 1)))))))

(defun block-receipts-from-record (block record)
  (handler-case
      (let* ((transactions (block-transactions block))
             (encoded-receipts
               (rlp-list-field (rlp-decode-one record)
                               "Block receipt record")))
        (unless (= (length transactions) (length encoded-receipts))
          (block-validation-fail
           "KV receipt record count does not match block transactions"))
        (let ((receipts
                (loop for transaction in transactions
                      for encoded in encoded-receipts
                      for receipt = (receipt-from-transaction-encoding
                                     transaction encoded)
                      do (unless (bytes= encoded
                                          (transaction-receipt-encoding
                                           transaction receipt))
                           (block-validation-fail
                            "KV receipt record does not round-trip"))
                      collect receipt)))
          (unless (hash32= (block-header-receipts-root (block-header block))
                           (transaction-receipt-list-root transactions
                                                          receipts))
            (block-validation-fail
             "KV receipt record root does not match block header"))
          receipts))
    (rlp-error (condition)
      (block-validation-fail "Invalid KV receipt record RLP: ~A" condition))))

(defun chain-store-import-receipt-record-from-kv
    (store block-identifier receipt-record)
  (let* ((block-hash (make-hash32 block-identifier))
         (block (chain-store-known-block store block-hash)))
    (unless block
      (block-validation-fail "KV receipt record references an unknown block"))
    (setf (block-receipts block)
          (block-receipts-from-record block receipt-record))))

(defun chain-store-import-receipt-records-from-kv (store database)
  (dolist (entry (kv-chain-record-entries database :receipt))
    (chain-store-import-receipt-record-from-kv
     store (car entry) (cdr entry))))
