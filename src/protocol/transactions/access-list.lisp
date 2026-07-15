(in-package #:ethereum-lisp.transactions)

(defstruct (access-list-entry (:constructor make-access-list-entry
                                 (&key address (storage-keys '()))))
  address
  (storage-keys '() :type list))

(defun access-list-entry-rlp-object (entry)
  (make-rlp-list
   (address-bytes (access-list-entry-address entry))
   (mapcar #'hash32-bytes (access-list-entry-storage-keys entry))))

(defun access-list-rlp-object (access-list)
  (mapcar #'access-list-entry-rlp-object access-list))

(defun access-list-address-from-rlp (value label)
  (let ((bytes (rlp-bytes-field value label)))
    (unless (= (length bytes) 20)
      (block-validation-fail "~A must be exactly 20 bytes" label))
    (make-address bytes)))

(defun access-list-storage-key-from-rlp (value label)
  (let ((bytes (rlp-bytes-field value label)))
    (unless (= (length bytes) 32)
      (block-validation-fail "~A must be exactly 32 bytes" label))
    (make-hash32 bytes)))

(defun access-list-entry-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Access list entry must be an RLP list"))
  (let ((fields (rlp-list-items value)))
    (unless (= (length fields) 2)
      (block-validation-fail "Access list entry must contain 2 fields"))
    (unless (rlp-list-p (second fields))
      (block-validation-fail "Access list storage keys must be an RLP list"))
    (make-access-list-entry
     :address (access-list-address-from-rlp
               (first fields)
               "Access list entry address")
     :storage-keys
     (mapcar (lambda (storage-key)
               (access-list-storage-key-from-rlp
                storage-key
                "Access list storage key"))
             (rlp-list-items (second fields))))))

(defun access-list-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Access list must be an RLP list"))
  (mapcar #'access-list-entry-from-rlp-object
          (rlp-list-items value)))

(defstruct (access-list-transaction (:constructor make-access-list-transaction
                                      (&key (chain-id 0)
                                            (nonce 0)
                                            (gas-price 0)
                                            (gas-limit 0)
                                            to
                                            (value 0)
                                            (data #())
                                            (access-list '())
                                            (y-parity 0)
                                            (r 0)
                                            (s 0))))
  (chain-id 0 :type (integer 0 *))
  (nonce 0 :type (integer 0 *))
  (gas-price 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun access-list-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (access-list-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (access-list-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (access-list-transaction-gas-price transaction) "Transaction gas price")
   (ensure-uint256 (access-list-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-recipient-bytes (access-list-transaction-to transaction))
   (ensure-uint256 (access-list-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (access-list-transaction-data transaction))
   (access-list-rlp-object (access-list-transaction-access-list transaction))
   (ensure-uint256 (access-list-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (access-list-transaction-r transaction) "Transaction r")
   (ensure-uint256 (access-list-transaction-s transaction) "Transaction s")))

(defun access-list-transaction-encoding (transaction)
  (concat-bytes #(1) (rlp-encode (access-list-transaction-payload transaction))))

(defun access-list-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Access-list transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 11)
            (block-validation-fail
             "Access-list transaction payload must contain 11 fields"))
          (make-access-list-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :gas-price (rlp-uint-field (third fields)
                                      "Transaction gas price")
           :gas-limit (rlp-uint-field (fourth fields)
                                      "Transaction gas limit")
           :to (legacy-transaction-recipient-from-rlp (fifth fields))
           :value (rlp-uint-field (sixth fields) "Transaction value")
           :data (rlp-bytes-field (seventh fields) "Transaction data")
           :access-list (access-list-from-rlp-object (eighth fields))
           :y-parity (rlp-uint-field (ninth fields) "Transaction y parity")
           :r (rlp-uint-field (tenth fields) "Transaction r")
           :s (rlp-uint-field (nth 10 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid access-list transaction RLP: ~A"
                             condition))))

(defun access-list-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (access-list-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (access-list-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (access-list-transaction-gas-price transaction) "Transaction gas price")
   (ensure-uint256 (access-list-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-recipient-bytes (access-list-transaction-to transaction))
   (ensure-uint256 (access-list-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (access-list-transaction-data transaction))
   (access-list-rlp-object (access-list-transaction-access-list transaction))))

(defun access-list-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes #(1)
                 (rlp-encode
                  (access-list-transaction-signing-payload transaction)))))

(defun access-list-transaction-hash (transaction)
  (keccak-256-hash (access-list-transaction-encoding transaction)))
