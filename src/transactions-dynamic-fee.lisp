(in-package #:ethereum-lisp.transactions)

(defstruct (dynamic-fee-transaction (:constructor make-dynamic-fee-transaction
                                     (&key (chain-id 0)
                                           (nonce 0)
                                           (max-priority-fee-per-gas 0)
                                           (max-fee-per-gas 0)
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
  (max-priority-fee-per-gas 0 :type (integer 0 *))
  (max-fee-per-gas 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  data
  (access-list '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun dynamic-fee-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (dynamic-fee-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (dynamic-fee-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (dynamic-fee-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (dynamic-fee-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (dynamic-fee-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-recipient-bytes (dynamic-fee-transaction-to transaction))
   (ensure-uint256 (dynamic-fee-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (dynamic-fee-transaction-data transaction))
   (access-list-rlp-object (dynamic-fee-transaction-access-list transaction))
   (ensure-uint256 (dynamic-fee-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (dynamic-fee-transaction-r transaction) "Transaction r")
   (ensure-uint256 (dynamic-fee-transaction-s transaction) "Transaction s")))

(defun dynamic-fee-transaction-encoding (transaction)
  (concat-bytes #(2) (rlp-encode (dynamic-fee-transaction-payload transaction))))

(defun dynamic-fee-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Dynamic-fee transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 12)
            (block-validation-fail
             "Dynamic-fee transaction payload must contain 12 fields"))
          (make-dynamic-fee-transaction
           :chain-id (rlp-uint-field (first fields)
                                     "Transaction chain id")
           :nonce (rlp-uint-field (second fields) "Transaction nonce")
           :max-priority-fee-per-gas
           (rlp-uint-field (third fields)
                           "Transaction max priority fee")
           :max-fee-per-gas
           (rlp-uint-field (fourth fields) "Transaction max fee")
           :gas-limit (rlp-uint-field (fifth fields)
                                      "Transaction gas limit")
           :to (legacy-transaction-recipient-from-rlp (sixth fields))
           :value (rlp-uint-field (seventh fields) "Transaction value")
           :data (rlp-bytes-field (eighth fields) "Transaction data")
           :access-list (access-list-from-rlp-object (ninth fields))
           :y-parity (rlp-uint-field (tenth fields) "Transaction y parity")
           :r (rlp-uint-field (nth 10 fields) "Transaction r")
           :s (rlp-uint-field (nth 11 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid dynamic-fee transaction RLP: ~A"
                             condition))))

(defun dynamic-fee-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (dynamic-fee-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (dynamic-fee-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (dynamic-fee-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (dynamic-fee-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (dynamic-fee-transaction-gas-limit transaction) "Transaction gas limit")
   (transaction-recipient-bytes (dynamic-fee-transaction-to transaction))
   (ensure-uint256 (dynamic-fee-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (dynamic-fee-transaction-data transaction))
   (access-list-rlp-object (dynamic-fee-transaction-access-list transaction))))

(defun dynamic-fee-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes #(2)
                 (rlp-encode
                  (dynamic-fee-transaction-signing-payload transaction)))))

(defun dynamic-fee-transaction-hash (transaction)
  (keccak-256-hash (dynamic-fee-transaction-encoding transaction)))
