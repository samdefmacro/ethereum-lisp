(in-package #:ethereum-lisp.core)

(defstruct (block-header (:constructor make-block-header
                            (&key parent-hash
                                  ommers-hash
                                  beneficiary
                                  state-root
                                  transactions-root
                                  receipts-root
                                  logs-bloom
                                  (difficulty 0)
                                  (number 0)
                                  (gas-limit 0)
                                  (gas-used 0)
                                  (timestamp 0)
                                  (extra-data #())
                                  mix-hash
                                  nonce
                                  base-fee-per-gas
                                  withdrawals-root
                                  blob-gas-used
                                  excess-blob-gas
                                  parent-beacon-root
                                  requests-hash
                                  block-access-list-hash
                                  slot-number)))
  parent-hash
  ommers-hash
  beneficiary
  state-root
  transactions-root
  receipts-root
  logs-bloom
  (difficulty 0 :type (integer 0 *))
  (number 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  (gas-used 0 :type (integer 0 *))
  (timestamp 0 :type (integer 0 *))
  (extra-data (make-byte-vector 0))
  mix-hash
  nonce
  base-fee-per-gas
  withdrawals-root
  blob-gas-used
  excess-blob-gas
  parent-beacon-root
  requests-hash
  block-access-list-hash
  slot-number)

(defun hash-or-zero (hash)
  (hash32-bytes (or hash (zero-hash32))))

(defun address-or-zero (address)
  (address-bytes (or address (zero-address))))

(defun header-fields (header)
  (let ((fields
          (list
           (hash-or-zero (block-header-parent-hash header))
           (hash32-bytes (or (block-header-ommers-hash header) +empty-ommers-hash+))
           (address-or-zero (block-header-beneficiary header))
           (hash32-bytes (or (block-header-state-root header) +empty-trie-hash+))
           (hash32-bytes (or (block-header-transactions-root header) +empty-trie-hash+))
           (hash32-bytes (or (block-header-receipts-root header) +empty-trie-hash+))
           (optional-bytes (or (block-header-logs-bloom header) (make-byte-vector 256))
                           256 "Logs bloom")
           (ensure-uint256 (block-header-difficulty header) "Header difficulty")
           (ensure-uint256 (block-header-number header) "Header number")
           (ensure-uint256 (block-header-gas-limit header) "Header gas limit")
           (ensure-uint256 (block-header-gas-used header) "Header gas used")
           (ensure-uint256 (block-header-timestamp header) "Header timestamp")
           (ensure-byte-vector (block-header-extra-data header))
           (hash-or-zero (block-header-mix-hash header))
           (optional-bytes (or (block-header-nonce header) (make-byte-vector 8))
                           8 "Header nonce"))))
    (when (block-header-base-fee-per-gas header)
      (setf fields (append fields
                           (list (ensure-uint256
                                  (block-header-base-fee-per-gas header)
                                  "Header base fee")))))
    (when (block-header-withdrawals-root header)
      (setf fields (append fields
                           (list (hash32-bytes
                                  (block-header-withdrawals-root header))))))
    (when (block-header-blob-gas-used header)
      (setf fields (append fields
                           (list (ensure-uint256
                                  (block-header-blob-gas-used header)
                                  "Header blob gas used")
                                 (ensure-uint256
                                  (or (block-header-excess-blob-gas header) 0)
                                  "Header excess blob gas")))))
    (when (block-header-parent-beacon-root header)
      (setf fields (append fields
                           (list (hash32-bytes
                                  (block-header-parent-beacon-root header))))))
    (when (block-header-requests-hash header)
      (setf fields (append fields
                           (list (hash32-bytes
                                  (block-header-requests-hash header))))))
    (when (or (block-header-block-access-list-hash header)
              (block-header-slot-number header))
      (setf fields (append fields
                           (list (if (block-header-block-access-list-hash
                                      header)
                                     (hash32-bytes
                                      (block-header-block-access-list-hash
                                       header))
                                     (make-byte-vector 0))))))
    (when (block-header-slot-number header)
      (setf fields (append fields
                           (list (ensure-uint256
                                  (block-header-slot-number header)
                                  "Header slot number")))))
    fields))

(defun block-header-rlp-object (header)
  (apply #'make-rlp-list (header-fields header)))

(defun block-header-rlp (header)
  (rlp-encode (block-header-rlp-object header)))

(defun block-header-hash (header)
  (keccak-256-hash (block-header-rlp header)))

(defun ommers-hash (ommers)
  (keccak-256-hash
   (rlp-encode
    (mapcar #'block-header-rlp-object ommers))))

(defun receipts-logs-bloom (receipts)
  (receipt-bloom
   (loop for receipt in receipts
         append (receipt-logs receipt))))

(defstruct (ethereum-block (:constructor %make-block
                             (&key header
                                   (transactions '())
                                   (receipts '())
                                   (ommers '())
                                   withdrawals
                                   withdrawals-present-p
                                   requests
                                   requests-present-p
                                   block-access-list
                                   block-access-list-present-p
                                   encoded-block-access-list))
                           (:conc-name block-))
  header
  (transactions '() :type list)
  (receipts '() :type list)
  (ommers '() :type list)
  withdrawals
  withdrawals-present-p
  requests
  requests-present-p
  block-access-list
  block-access-list-present-p
  encoded-block-access-list)

(defun make-block (&key (header (make-block-header))
                        (transactions '())
                        (receipts '())
                        (ommers '())
                        (withdrawals nil withdrawals-supplied-p)
                        (requests nil requests-supplied-p)
                        (block-access-list nil block-access-list-supplied-p)
                        (block-access-list-rlp nil
                         block-access-list-rlp-supplied-p))
  (let ((encoded-block-access-list nil))
    (when (and block-access-list-supplied-p
               block-access-list-rlp-supplied-p)
      (block-validation-fail
       "Block access list cannot be supplied as both typed data and RLP"))
    (when block-access-list-rlp-supplied-p
      (setf encoded-block-access-list
            (block-access-list-rlp-input-bytes block-access-list-rlp)
            block-access-list
            (block-access-list-from-rlp encoded-block-access-list)
            block-access-list-supplied-p t))
    (setf (block-header-transactions-root header)
          (transaction-list-root transactions)
          (block-header-receipts-root header)
          (if (= (length transactions) (length receipts))
              (transaction-receipt-list-root transactions receipts)
              (receipt-list-root receipts))
          (block-header-logs-bloom header)
          (bloom-bytes (receipts-logs-bloom receipts))
          (block-header-ommers-hash header)
          (ommers-hash ommers))
    (when withdrawals-supplied-p
      (setf (block-header-withdrawals-root header)
            (withdrawal-list-root withdrawals)))
    (when requests-supplied-p
      (setf (block-header-requests-hash header)
            (execution-requests-hash requests)))
    (when block-access-list-supplied-p
      (unless encoded-block-access-list
        (validate-block-access-list-fields block-access-list)
        (setf encoded-block-access-list
              (block-access-list-rlp block-access-list)))
      (setf (block-header-block-access-list-hash header)
            (keccak-256-hash encoded-block-access-list)))
    (%make-block :header header
                 :transactions transactions
                 :receipts receipts
                 :ommers ommers
                 :withdrawals withdrawals
                 :withdrawals-present-p withdrawals-supplied-p
                 :requests requests
                 :requests-present-p requests-supplied-p
                 :block-access-list block-access-list
                 :block-access-list-present-p block-access-list-supplied-p
                 :encoded-block-access-list encoded-block-access-list)))

(defun block-hash (block)
  (block-header-hash (block-header block)))

(defun rlp-list-field (value label)
  (unless (rlp-list-p value)
    (block-validation-fail "~A must be an RLP list" label))
  (rlp-list-items value))

(defun rlp-sized-bytes-field (value size label)
  (let ((bytes (rlp-bytes-field value label)))
    (unless (= (length bytes) size)
      (block-validation-fail "~A must be exactly ~D bytes" label size))
    bytes))

(defun rlp-hash32-field (value label)
  (make-hash32 (rlp-sized-bytes-field value 32 label)))

(defun rlp-address-field (value label)
  (make-address (rlp-sized-bytes-field value 20 label)))

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
      (%make-block
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
