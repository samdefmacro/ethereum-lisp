(in-package #:ethereum-lisp.transactions)

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

(defun transaction-recipient-bytes (to)
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
    (transaction-recipient-bytes (legacy-transaction-to transaction))
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
           (transaction-recipient-bytes (legacy-transaction-to transaction))
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
