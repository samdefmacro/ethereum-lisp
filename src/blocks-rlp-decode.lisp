(in-package #:ethereum-lisp.blocks)

(defun block-header-from-rlp-object (value)
  (let ((fields (rlp-list-field value "Block header")))
    (unless (member (length fields) '(15 16 17 20 21 22 23))
      (block-validation-fail
       "Block header RLP must contain a supported fork field count"))
    (make-block-header
     :parent-hash (rlp-hash32-field (first fields) "Header parent hash")
     :ommers-hash (rlp-hash32-field (second fields) "Header ommers hash")
     :beneficiary (rlp-address-field (third fields) "Header beneficiary")
     :state-root (rlp-hash32-field (fourth fields) "Header state root")
     :transactions-root (rlp-hash32-field
                         (fifth fields)
                         "Header transactions root")
     :receipts-root (rlp-hash32-field (sixth fields) "Header receipts root")
     :logs-bloom (rlp-sized-bytes-field
                  (seventh fields)
                  256
                  "Header logs bloom")
     :difficulty (rlp-uint-field (eighth fields) "Header difficulty")
     :number (rlp-uint-field (nth 8 fields) "Header number")
     :gas-limit (rlp-uint-field (nth 9 fields) "Header gas limit")
     :gas-used (rlp-uint-field (nth 10 fields) "Header gas used")
     :timestamp (rlp-uint-field (nth 11 fields) "Header timestamp")
     :extra-data (rlp-bytes-field (nth 12 fields) "Header extra data")
     :mix-hash (rlp-hash32-field (nth 13 fields) "Header mix hash")
     :nonce (rlp-sized-bytes-field (nth 14 fields) 8 "Header nonce")
     :base-fee-per-gas
     (when (> (length fields) 15)
       (rlp-uint-field (nth 15 fields) "Header base fee per gas"))
     :withdrawals-root
     (when (> (length fields) 16)
       (rlp-hash32-field (nth 16 fields) "Header withdrawals root"))
     :blob-gas-used
     (when (> (length fields) 17)
       (rlp-uint-field (nth 17 fields) "Header blob gas used"))
     :excess-blob-gas
     (when (> (length fields) 18)
       (rlp-uint-field (nth 18 fields) "Header excess blob gas"))
     :parent-beacon-root
     (when (> (length fields) 19)
       (rlp-hash32-field (nth 19 fields) "Header parent beacon root"))
     :requests-hash
     (when (> (length fields) 20)
       (rlp-hash32-field (nth 20 fields) "Header requests hash"))
     :block-access-list-hash
     (when (> (length fields) 21)
       (let ((bytes (rlp-bytes-field (nth 21 fields)
                                     "Header block access list hash")))
         (unless (or (zerop (length bytes)) (= 32 (length bytes)))
           (block-validation-fail
            "Header block access list hash must be empty or 32 bytes"))
         (when (= 32 (length bytes))
           (make-hash32 bytes))))
     :slot-number
     (when (> (length fields) 22)
       (rlp-uint-field (nth 22 fields) "Header slot number")))))

(defun block-header-from-rlp (bytes)
  (block-header-from-rlp-object (rlp-decode-one bytes)))

(defun withdrawal-from-rlp-object (value)
  (let ((fields (rlp-list-field value "Withdrawal")))
    (unless (= (length fields) 4)
      (block-validation-fail "Withdrawal RLP must contain 4 fields"))
    (make-withdrawal
     :index (rlp-uint-field (first fields) "Withdrawal index")
     :validator-index
     (rlp-uint-field (second fields) "Withdrawal validator index")
     :address (rlp-address-field (third fields) "Withdrawal address")
     :amount (rlp-uint-field (fourth fields) "Withdrawal amount"))))

(defun block-transactions-from-rlp-object (value)
  (mapcar
   (lambda (transaction)
     (transaction-from-encoding
      (if (rlp-list-p transaction)
          (rlp-encode transaction)
          (rlp-bytes-field transaction "Block transaction"))))
   (rlp-list-field value "Block transactions")))

(defun block-ommers-from-rlp-object (value)
  (mapcar #'block-header-from-rlp-object
          (rlp-list-field value "Block ommers")))

(defun block-withdrawals-from-rlp-object (value)
  (mapcar #'withdrawal-from-rlp-object
          (rlp-list-field value "Block withdrawals")))

(defun block-requests-from-rlp-object (value)
  (mapcar #'rlp-encode (rlp-list-field value "Block requests")))

(defun block-from-rlp (bytes)
  (let* ((decoded (rlp-decode-one bytes))
         (items (rlp-list-field decoded "Block")))
    (unless (member (length items) '(3 4 5 6))
      (block-validation-fail "Block RLP must contain 3 to 6 fields"))
    (let ((withdrawals-present-p (> (length items) 3))
          (requests-present-p (> (length items) 4))
          (block-access-list-present-p (> (length items) 5)))
      (make-block-from-parts
       :header (block-header-from-rlp-object (first items))
       :transactions (block-transactions-from-rlp-object (second items))
       :ommers (block-ommers-from-rlp-object (third items))
       :withdrawals (when withdrawals-present-p
                      (block-withdrawals-from-rlp-object (fourth items)))
       :withdrawals-present-p withdrawals-present-p
       :requests (when requests-present-p
                   (block-requests-from-rlp-object (nth 4 items)))
       :requests-present-p requests-present-p
       :block-access-list (when block-access-list-present-p
                            (block-access-list-from-rlp
                             (rlp-encode (nth 5 items))))
       :block-access-list-present-p block-access-list-present-p
       :encoded-block-access-list (when block-access-list-present-p
                                    (rlp-encode (nth 5 items)))))))
