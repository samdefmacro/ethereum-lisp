(in-package #:ethereum-lisp.transactions)

(defstruct (blob-transaction (:constructor make-blob-transaction
                               (&key (chain-id 0)
                                     (nonce 0)
                                     (max-priority-fee-per-gas 0)
                                     (max-fee-per-gas 0)
                                     (gas-limit 0)
                                     to
                                     (value 0)
                                     (data #())
                                     (access-list '())
                                     (max-fee-per-blob-gas 0)
                                     (blob-versioned-hashes '())
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
  (max-fee-per-blob-gas 0 :type (integer 0 *))
  (blob-versioned-hashes '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun blob-versioned-hash-bytes (hash)
  (etypecase hash
    (hash32 (hash32-bytes hash))
    (byte-vector (optional-bytes hash 32 "Blob versioned hash"))
    (vector (optional-bytes hash 32 "Blob versioned hash"))))

(defun required-transaction-recipient-from-rlp (value label)
  (let ((recipient (legacy-transaction-recipient-from-rlp value)))
    (unless recipient
      (block-validation-fail "~A must be exactly 20 bytes" label))
    recipient))

(defun blob-versioned-hash-from-rlp (value)
  (let ((bytes (rlp-bytes-field value "Blob versioned hash")))
    (unless (= (length bytes) 32)
      (block-validation-fail "Blob versioned hash must be exactly 32 bytes"))
    (make-hash32 bytes)))

(defun blob-versioned-hashes-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Blob versioned hashes must be an RLP list"))
  (mapcar #'blob-versioned-hash-from-rlp
          (rlp-list-items value)))

(defun blob-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (blob-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (blob-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (blob-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (blob-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (blob-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (blob-transaction-to transaction)
                                  "Blob transaction recipient")
   (ensure-uint256 (blob-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (blob-transaction-data transaction))
   (access-list-rlp-object (blob-transaction-access-list transaction))
   (ensure-uint256 (blob-transaction-max-fee-per-blob-gas transaction)
                   "Transaction max blob fee")
   (mapcar #'blob-versioned-hash-bytes
           (blob-transaction-blob-versioned-hashes transaction))
   (ensure-uint256 (blob-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (blob-transaction-r transaction) "Transaction r")
   (ensure-uint256 (blob-transaction-s transaction) "Transaction s")))

(defun blob-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (blob-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (blob-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (blob-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (blob-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (blob-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (blob-transaction-to transaction)
                                  "Blob transaction recipient")
   (ensure-uint256 (blob-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (blob-transaction-data transaction))
   (access-list-rlp-object (blob-transaction-access-list transaction))
   (ensure-uint256 (blob-transaction-max-fee-per-blob-gas transaction)
                   "Transaction max blob fee")
   (mapcar #'blob-versioned-hash-bytes
           (blob-transaction-blob-versioned-hashes transaction))))

(defun blob-transaction-encoding (transaction)
  (concat-bytes #(3) (rlp-encode (blob-transaction-payload transaction))))

(defun blob-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Blob transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 14)
            (block-validation-fail
             "Blob transaction payload must contain 14 fields"))
          (make-blob-transaction
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
           :to (required-transaction-recipient-from-rlp
                (sixth fields)
                "Blob transaction recipient")
           :value (rlp-uint-field (seventh fields) "Transaction value")
           :data (rlp-bytes-field (eighth fields) "Transaction data")
           :access-list (access-list-from-rlp-object (ninth fields))
           :max-fee-per-blob-gas
           (rlp-uint-field (nth 9 fields) "Transaction max blob fee")
           :blob-versioned-hashes
           (blob-versioned-hashes-from-rlp-object (nth 10 fields))
           :y-parity (rlp-uint-field (nth 11 fields)
                                     "Transaction y parity")
           :r (rlp-uint-field (nth 12 fields) "Transaction r")
           :s (rlp-uint-field (nth 13 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid blob transaction RLP: ~A"
                             condition))))

(defun blob-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes #(3)
                 (rlp-encode
                  (blob-transaction-signing-payload transaction)))))

(defun blob-transaction-hash (transaction)
  (keccak-256-hash (blob-transaction-encoding transaction)))

(defstruct (blob-sidecar (:constructor make-blob-sidecar
                            (&key (blobs '())
                                  (commitments '())
                                  (proofs '()))))
  (blobs '() :type list)
  (commitments '() :type list)
  (proofs '() :type list))

(defun blob-sidecar-versioned-hashes (sidecar)
  (mapcar #'kzg-commitment-to-versioned-hash
          (blob-sidecar-commitments sidecar)))
