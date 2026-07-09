(in-package #:ethereum-lisp.core)

;;;; Transaction validation, pricing, encoding, and sender recovery.

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
