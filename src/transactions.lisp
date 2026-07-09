(in-package #:ethereum-lisp.core)

;;; Transaction envelope types, RLP encodings, signing hashes, and sender recovery.

(defstruct (legacy-transaction (:constructor make-legacy-transaction
                                  (&key (nonce 0)
                                        (gas-price 0)
                                        (gas-limit 0)
                                        to
                                        (value 0)
                                        (data #())
                                        (v 0)
                                        (r 0)
                                        (s 0))))
  (nonce 0 :type (integer 0 *))
  (gas-price 0 :type (integer 0 *))
  (gas-limit 0 :type (integer 0 *))
  to
  (value 0 :type (integer 0 *))
  (data (make-byte-vector 0))
  (v 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun transaction-to-bytes (to)
  (etypecase to
    (null (make-byte-vector 0))
    (address (address-bytes to))
    (byte-vector (optional-bytes to 20 "Transaction recipient"))
    (vector (optional-bytes to 20 "Transaction recipient"))))

(defun required-transaction-to-bytes (to label)
  (etypecase to
    (address (address-bytes to))
    (byte-vector (optional-bytes to 20 label))
    (vector (optional-bytes to 20 label))))

(defun legacy-transaction-rlp (transaction)
  (rlp-encode
   (make-rlp-list
    (ensure-uint256 (legacy-transaction-nonce transaction) "Transaction nonce")
    (ensure-uint256 (legacy-transaction-gas-price transaction) "Transaction gas price")
    (ensure-uint256 (legacy-transaction-gas-limit transaction) "Transaction gas limit")
    (transaction-to-bytes (legacy-transaction-to transaction))
    (ensure-uint256 (legacy-transaction-value transaction) "Transaction value")
    (ensure-byte-vector (legacy-transaction-data transaction))
    (ensure-uint256 (legacy-transaction-v transaction) "Transaction v")
    (ensure-uint256 (legacy-transaction-r transaction) "Transaction r")
    (ensure-uint256 (legacy-transaction-s transaction) "Transaction s"))))

(defun legacy-transaction-recipient-from-rlp (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (cond
      ((zerop (length bytes)) nil)
      ((= (length bytes) 20) (make-address bytes))
      (t (block-validation-fail
          "Legacy transaction recipient must be empty or 20 bytes")))))

(defun rlp-uint-field (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "~A must be RLP bytes" label))
  (when (and (plusp (length value))
             (zerop (aref value 0)))
    (block-validation-fail "~A must be canonically encoded" label))
  (bytes-to-integer value))

(defun rlp-bytes-field (value label)
  (unless (byte-vector-p value)
    (block-validation-fail "~A must be RLP bytes" label))
  (copy-seq value))

(defun legacy-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail "Legacy transaction must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 9)
            (block-validation-fail
             "Legacy transaction must contain 9 fields"))
          (make-legacy-transaction
           :nonce (rlp-uint-field (first fields) "Transaction nonce")
           :gas-price (rlp-uint-field (second fields)
                                      "Transaction gas price")
           :gas-limit (rlp-uint-field (third fields)
                                      "Transaction gas limit")
           :to (legacy-transaction-recipient-from-rlp (fourth fields))
           :value (rlp-uint-field (fifth fields) "Transaction value")
           :data (rlp-bytes-field (sixth fields) "Transaction data")
           :v (rlp-uint-field (seventh fields) "Transaction v")
           :r (rlp-uint-field (eighth fields) "Transaction r")
           :s (rlp-uint-field (ninth fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid legacy transaction RLP: ~A"
                             condition))))

(defun legacy-transaction-hash (transaction)
  (keccak-256-hash (legacy-transaction-rlp transaction)))

(defun legacy-transaction-signing-payload
    (transaction &key (chain-id nil chain-id-provided-p))
  (let ((payload
          (list
           (ensure-uint256 (legacy-transaction-nonce transaction)
                           "Transaction nonce")
           (ensure-uint256 (legacy-transaction-gas-price transaction)
                           "Transaction gas price")
           (ensure-uint256 (legacy-transaction-gas-limit transaction)
                           "Transaction gas limit")
           (transaction-to-bytes (legacy-transaction-to transaction))
           (ensure-uint256 (legacy-transaction-value transaction)
                           "Transaction value")
           (ensure-byte-vector (legacy-transaction-data transaction)))))
    (when chain-id-provided-p
      (setf payload (append payload (list (ensure-uint256 chain-id
                                                          "Transaction chain id")
                                          0
                                          0))))
    (apply #'make-rlp-list payload)))

(defun legacy-transaction-signing-hash
    (transaction &key (chain-id nil chain-id-provided-p))
  (keccak-256-hash
   (rlp-encode
    (if chain-id-provided-p
        (legacy-transaction-signing-payload transaction :chain-id chain-id)
        (legacy-transaction-signing-payload transaction)))))

(defun legacy-transaction-protected-p (transaction)
  (>= (legacy-transaction-v transaction) 35))

(defun legacy-transaction-chain-id (transaction)
  (let ((v (legacy-transaction-v transaction)))
    (cond
      ((or (= v 27) (= v 28)) 0)
      ((>= v 35) (floor (- v 35) 2))
      (t nil))))

(defun legacy-transaction-y-parity (transaction)
  (let ((v (legacy-transaction-v transaction)))
    (cond
      ((or (= v 27) (= v 28)) (- v 27))
      ((>= v 35) (mod (- v 35) 2))
      (t nil))))

(defun legacy-transaction-sender
    (transaction &key expected-chain-id (homestead-p t))
  "Recover the sender address from a legacy transaction signature.
Returns NIL when V/R/S are invalid or the expected chain id does not match."
  (let* ((chain-id (legacy-transaction-chain-id transaction))
         (protected-p (legacy-transaction-protected-p transaction))
         (y-parity (legacy-transaction-y-parity transaction))
         (r (legacy-transaction-r transaction))
         (s (legacy-transaction-s transaction)))
    (when (and chain-id
               y-parity
               (or (not expected-chain-id)
                   (not protected-p)
                   (= expected-chain-id chain-id))
               (secp256k1-valid-signature-values-p
                y-parity r s :low-s-p homestead-p))
      (let ((hash (if protected-p
                      (legacy-transaction-signing-hash transaction
                                                       :chain-id chain-id)
                      (legacy-transaction-signing-hash transaction))))
        (secp256k1-recover-address (hash32-bytes hash) y-parity r s)))))

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
   (transaction-to-bytes (access-list-transaction-to transaction))
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
   (transaction-to-bytes (access-list-transaction-to transaction))
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
   (transaction-to-bytes (dynamic-fee-transaction-to transaction))
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
   (transaction-to-bytes (dynamic-fee-transaction-to transaction))
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

(defstruct (set-code-authorization (:constructor make-set-code-authorization
                                     (&key (chain-id 0)
                                           address
                                           (nonce 0)
                                           (y-parity 0)
                                           (r 0)
                                           (s 0))))
  (chain-id 0 :type (integer 0 *))
  address
  (nonce 0 :type (integer 0 *))
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun set-code-authorization-rlp-object (authorization)
  (make-rlp-list
   (ensure-uint256 (set-code-authorization-chain-id authorization)
                   "Authorization chain id")
   (required-transaction-to-bytes (set-code-authorization-address authorization)
                                  "Authorization address")
   (ensure-uint256 (set-code-authorization-nonce authorization)
                   "Authorization nonce")
   (ensure-uint256 (set-code-authorization-y-parity authorization)
                   "Authorization y parity")
   (ensure-uint256 (set-code-authorization-r authorization)
                   "Authorization r")
   (ensure-uint256 (set-code-authorization-s authorization)
                   "Authorization s")))

(defun set-code-authorization-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Set-code authorization must be an RLP list"))
  (let ((fields (rlp-list-items value)))
    (unless (= (length fields) 6)
      (block-validation-fail
       "Set-code authorization must contain 6 fields"))
    (make-set-code-authorization
     :chain-id (rlp-uint-field (first fields) "Authorization chain id")
     :address (required-transaction-recipient-from-rlp
               (second fields)
               "Authorization address")
     :nonce (rlp-uint-field (third fields) "Authorization nonce")
     :y-parity (rlp-uint-field (fourth fields)
                               "Authorization y parity")
     :r (rlp-uint-field (fifth fields) "Authorization r")
     :s (rlp-uint-field (sixth fields) "Authorization s"))))

(defun set-code-authorization-signing-hash (authorization)
  (keccak-256-hash
   (concat-bytes
    #(5)
    (rlp-encode
     (make-rlp-list
      (ensure-uint256 (set-code-authorization-chain-id authorization)
                      "Authorization chain id")
      (required-transaction-to-bytes (set-code-authorization-address authorization)
                                     "Authorization address")
      (ensure-uint256 (set-code-authorization-nonce authorization)
                      "Authorization nonce"))))))

(defun set-code-authorization-authority (authorization)
  "Recover the authority address from an EIP-7702 authorization tuple."
  (let ((y-parity (set-code-authorization-y-parity authorization))
        (r (set-code-authorization-r authorization))
        (s (set-code-authorization-s authorization)))
    (when (secp256k1-valid-signature-values-p y-parity r s :low-s-p t)
      (secp256k1-recover-address
       (hash32-bytes (set-code-authorization-signing-hash authorization))
       y-parity
       r
       s))))

(defparameter +set-code-delegation-prefix+ #(#xef #x01 #x00))

(defun set-code-delegation-code (address)
  (concat-bytes +set-code-delegation-prefix+ (address-bytes address)))

(defun set-code-delegation-target (code)
  (let ((code (ensure-byte-vector code)))
    (when (and (= 23 (length code))
               (loop for i below (length +set-code-delegation-prefix+)
                     always (= (aref code i)
                               (aref +set-code-delegation-prefix+ i))))
      (make-address (subseq code (length +set-code-delegation-prefix+))))))

(defstruct (set-code-transaction (:constructor make-set-code-transaction
                                   (&key (chain-id 0)
                                         (nonce 0)
                                         (max-priority-fee-per-gas 0)
                                         (max-fee-per-gas 0)
                                         (gas-limit 0)
                                         to
                                         (value 0)
                                         (data #())
                                         (access-list '())
                                         (authorization-list '())
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
  (authorization-list '() :type list)
  (y-parity 0 :type (integer 0 *))
  (r 0 :type (integer 0 *))
  (s 0 :type (integer 0 *)))

(defun set-code-authorization-list-rlp-object (authorization-list)
  (mapcar #'set-code-authorization-rlp-object authorization-list))

(defun set-code-authorization-list-from-rlp-object (value)
  (unless (rlp-list-p value)
    (block-validation-fail "Set-code authorization list must be an RLP list"))
  (mapcar #'set-code-authorization-from-rlp-object
          (rlp-list-items value)))

(defun set-code-transaction-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (set-code-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (set-code-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (set-code-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (set-code-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (set-code-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (set-code-transaction-to transaction)
                                  "Set-code transaction recipient")
   (ensure-uint256 (set-code-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (set-code-transaction-data transaction))
   (access-list-rlp-object (set-code-transaction-access-list transaction))
   (set-code-authorization-list-rlp-object
    (set-code-transaction-authorization-list transaction))
   (ensure-uint256 (set-code-transaction-y-parity transaction) "Transaction y parity")
   (ensure-uint256 (set-code-transaction-r transaction) "Transaction r")
   (ensure-uint256 (set-code-transaction-s transaction) "Transaction s")))

(defun set-code-transaction-signing-payload (transaction)
  (make-rlp-list
   (ensure-uint256 (set-code-transaction-chain-id transaction) "Transaction chain id")
   (ensure-uint256 (set-code-transaction-nonce transaction) "Transaction nonce")
   (ensure-uint256 (set-code-transaction-max-priority-fee-per-gas transaction)
                   "Transaction max priority fee")
   (ensure-uint256 (set-code-transaction-max-fee-per-gas transaction)
                   "Transaction max fee")
   (ensure-uint256 (set-code-transaction-gas-limit transaction) "Transaction gas limit")
   (required-transaction-to-bytes (set-code-transaction-to transaction)
                                  "Set-code transaction recipient")
   (ensure-uint256 (set-code-transaction-value transaction) "Transaction value")
   (ensure-byte-vector (set-code-transaction-data transaction))
   (access-list-rlp-object (set-code-transaction-access-list transaction))
   (set-code-authorization-list-rlp-object
    (set-code-transaction-authorization-list transaction))))

(defun set-code-transaction-encoding (transaction)
  (concat-bytes #(4) (rlp-encode (set-code-transaction-payload transaction))))

(defun set-code-transaction-from-rlp (bytes)
  (handler-case
      (let ((value (rlp-decode-one bytes)))
        (unless (rlp-list-p value)
          (block-validation-fail
           "Set-code transaction payload must be an RLP list"))
        (let ((fields (rlp-list-items value)))
          (unless (= (length fields) 13)
            (block-validation-fail
             "Set-code transaction payload must contain 13 fields"))
          (make-set-code-transaction
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
                "Set-code transaction recipient")
           :value (rlp-uint-field (seventh fields) "Transaction value")
           :data (rlp-bytes-field (eighth fields) "Transaction data")
           :access-list (access-list-from-rlp-object (ninth fields))
           :authorization-list
           (set-code-authorization-list-from-rlp-object (nth 9 fields))
           :y-parity (rlp-uint-field (nth 10 fields)
                                     "Transaction y parity")
           :r (rlp-uint-field (nth 11 fields) "Transaction r")
           :s (rlp-uint-field (nth 12 fields) "Transaction s"))))
    (block-validation-error (condition)
      (error condition))
    (rlp-error (condition)
      (block-validation-fail "Invalid set-code transaction RLP: ~A"
                             condition))))

(defun set-code-transaction-signing-hash (transaction)
  (keccak-256-hash
   (concat-bytes
    #(4)
    (rlp-encode (set-code-transaction-signing-payload transaction)))))

(defun set-code-transaction-hash (transaction)
  (keccak-256-hash (set-code-transaction-encoding transaction)))

(defun transaction-nonce (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-nonce transaction))
    (access-list-transaction (access-list-transaction-nonce transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-nonce transaction))
    (blob-transaction (blob-transaction-nonce transaction))
    (set-code-transaction (set-code-transaction-nonce transaction))))

(defun transaction-gas-limit (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-gas-limit transaction))
    (access-list-transaction (access-list-transaction-gas-limit transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-gas-limit transaction))
    (blob-transaction (blob-transaction-gas-limit transaction))
    (set-code-transaction (set-code-transaction-gas-limit transaction))))

(defun transaction-to (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-to transaction))
    (access-list-transaction (access-list-transaction-to transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-to transaction))
    (blob-transaction (blob-transaction-to transaction))
    (set-code-transaction (set-code-transaction-to transaction))))

(defun transaction-value (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-value transaction))
    (access-list-transaction (access-list-transaction-value transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-value transaction))
    (blob-transaction (blob-transaction-value transaction))
    (set-code-transaction (set-code-transaction-value transaction))))

(defun transaction-data (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-data transaction))
    (access-list-transaction (access-list-transaction-data transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-data transaction))
    (blob-transaction (blob-transaction-data transaction))
    (set-code-transaction (set-code-transaction-data transaction))))

(defun transaction-access-list (transaction)
  (etypecase transaction
    (legacy-transaction '())
    (access-list-transaction (access-list-transaction-access-list transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-access-list transaction))
    (blob-transaction (blob-transaction-access-list transaction))
    (set-code-transaction (set-code-transaction-access-list transaction))))

(defun transaction-authorization-list (transaction)
  (etypecase transaction
    ((or legacy-transaction
         access-list-transaction
         dynamic-fee-transaction
         blob-transaction)
     '())
    (set-code-transaction
     (set-code-transaction-authorization-list transaction))))

(defun transaction-type (transaction)
  (etypecase transaction
    (legacy-transaction 0)
    (access-list-transaction 1)
    (dynamic-fee-transaction 2)
    (blob-transaction 3)
    (set-code-transaction 4)))

(defun validate-transaction-type-for-config
    (transaction config block-number timestamp)
  (let* ((rules (chain-config-rules config block-number timestamp))
         (type (transaction-type transaction)))
    (when (chain-rules-transaction-type-supported-p rules transaction)
      (return-from validate-transaction-type-for-config t))
    (cond
      ((= type 1)
       (block-validation-fail "Access-list transaction before Berlin"))
      ((= type 2)
       (block-validation-fail "Dynamic-fee transaction before London"))
      ((= type 3)
       (block-validation-fail "Blob transaction before Cancun"))
      ((= type 4)
       (block-validation-fail "Set-code transaction before Prague"))
      (t
       (block-validation-fail "Unsupported transaction type"))))
  t)

(defun transaction-blob-versioned-hashes (transaction)
  (etypecase transaction
    ((or legacy-transaction
         access-list-transaction
         dynamic-fee-transaction
         set-code-transaction)
     #())
    (blob-transaction
     (coerce (blob-transaction-blob-versioned-hashes transaction) 'vector))))

(defun transaction-blob-gas-used (transaction)
  (* (length (transaction-blob-versioned-hashes transaction))
     +blob-gas-per-blob+))

(defun access-list-storage-key-count (access-list)
  (loop for entry in access-list
        sum (length (access-list-entry-storage-keys entry))))

(defun transaction-max-priority-fee-per-gas (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-gas-price transaction))
    (access-list-transaction (access-list-transaction-gas-price transaction))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-max-priority-fee-per-gas transaction))
    (blob-transaction
     (blob-transaction-max-priority-fee-per-gas transaction))
    (set-code-transaction
     (set-code-transaction-max-priority-fee-per-gas transaction))))

(defun transaction-max-fee-per-gas (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-gas-price transaction))
    (access-list-transaction (access-list-transaction-gas-price transaction))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-max-fee-per-gas transaction))
    (blob-transaction
     (blob-transaction-max-fee-per-gas transaction))
    (set-code-transaction
     (set-code-transaction-max-fee-per-gas transaction))))

(defun validate-1559-transaction-fees (transaction base-fee)
  (let ((max-priority-fee (transaction-max-priority-fee-per-gas transaction))
        (max-fee (transaction-max-fee-per-gas transaction)))
    (unless (uint256-p max-priority-fee)
      (block-validation-fail "Max priority fee must be uint256"))
    (unless (uint256-p max-fee)
      (block-validation-fail "Max fee per gas must be uint256"))
    (when (< max-fee max-priority-fee)
      (block-validation-fail "Max priority fee exceeds max fee"))
    (when (< max-fee base-fee)
      (block-validation-fail "Max fee per gas below base fee"))
    t))

(defun transaction-effective-gas-price
    (transaction &key (base-fee 0) (eip1559-enabled-p t))
  (if (not eip1559-enabled-p)
      (transaction-max-priority-fee-per-gas transaction)
      (progn
        (validate-1559-transaction-fees transaction base-fee)
        (if (or (typep transaction 'legacy-transaction)
                (typep transaction 'access-list-transaction))
            (transaction-max-fee-per-gas transaction)
            (+ base-fee
               (min (transaction-max-priority-fee-per-gas transaction)
                    (- (transaction-max-fee-per-gas transaction)
                       base-fee)))))))

(defun transaction-priority-fee-per-gas
    (transaction &key (base-fee 0) (eip1559-enabled-p t))
  (if (not eip1559-enabled-p)
      (transaction-max-priority-fee-per-gas transaction)
      (max 0 (- (transaction-effective-gas-price transaction
                                                 :base-fee base-fee)
                base-fee))))

(defun transaction-encoding (transaction)
  (etypecase transaction
    (legacy-transaction (legacy-transaction-rlp transaction))
    (access-list-transaction (access-list-transaction-encoding transaction))
    (dynamic-fee-transaction (dynamic-fee-transaction-encoding transaction))
    (blob-transaction (blob-transaction-encoding transaction))
    (set-code-transaction (set-code-transaction-encoding transaction))))

(defun transaction-from-encoding (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (when (zerop (length bytes))
      (block-validation-fail "Transaction encoding is empty"))
    (if (> (aref bytes 0) #x7f)
        (legacy-transaction-from-rlp bytes)
        (case (aref bytes 0)
          (1 (access-list-transaction-from-rlp (subseq bytes 1)))
          (2 (dynamic-fee-transaction-from-rlp (subseq bytes 1)))
          (3 (blob-transaction-from-rlp (subseq bytes 1)))
          (4 (set-code-transaction-from-rlp (subseq bytes 1)))
          (otherwise
           (block-validation-fail
            "Typed transaction decoding is not implemented yet"))))))

(defun transaction-hash (transaction)
  (keccak-256-hash (transaction-encoding transaction)))

(defun typed-transaction-sender
    (chain-id y-parity r s signing-hash &key expected-chain-id)
  (when (and (or (not expected-chain-id)
                 (= expected-chain-id chain-id))
             (secp256k1-valid-signature-values-p y-parity r s :low-s-p t))
    (secp256k1-recover-address (hash32-bytes signing-hash) y-parity r s)))

(defun access-list-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-2930 transaction signature."
  (typed-transaction-sender
   (access-list-transaction-chain-id transaction)
   (access-list-transaction-y-parity transaction)
   (access-list-transaction-r transaction)
   (access-list-transaction-s transaction)
   (access-list-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun dynamic-fee-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-1559 transaction signature."
  (typed-transaction-sender
   (dynamic-fee-transaction-chain-id transaction)
   (dynamic-fee-transaction-y-parity transaction)
   (dynamic-fee-transaction-r transaction)
   (dynamic-fee-transaction-s transaction)
   (dynamic-fee-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun blob-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-4844 transaction signature."
  (typed-transaction-sender
   (blob-transaction-chain-id transaction)
   (blob-transaction-y-parity transaction)
   (blob-transaction-r transaction)
   (blob-transaction-s transaction)
   (blob-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun set-code-transaction-sender (transaction &key expected-chain-id)
  "Recover the sender address from an EIP-7702 set-code transaction signature."
  (typed-transaction-sender
   (set-code-transaction-chain-id transaction)
   (set-code-transaction-y-parity transaction)
   (set-code-transaction-r transaction)
   (set-code-transaction-s transaction)
   (set-code-transaction-signing-hash transaction)
   :expected-chain-id expected-chain-id))

(defun transaction-sender (transaction &key expected-chain-id)
  (etypecase transaction
    (legacy-transaction
     (legacy-transaction-sender transaction
                                :expected-chain-id expected-chain-id))
    (access-list-transaction
     (access-list-transaction-sender transaction
                                     :expected-chain-id expected-chain-id))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-sender transaction
                                     :expected-chain-id expected-chain-id))
    (blob-transaction
     (blob-transaction-sender transaction
                              :expected-chain-id expected-chain-id))
    (set-code-transaction
     (set-code-transaction-sender transaction
                                  :expected-chain-id expected-chain-id))))
