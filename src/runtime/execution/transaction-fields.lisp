(in-package #:ethereum-lisp.execution)

;;;; Field-level transaction validation for execution paths.

(defun transaction-gas-limit-uint64-p (gas-limit)
  (and (integerp gas-limit)
       (<= 0 gas-limit +max-transaction-gas-limit+)))

(defun transaction-nonce-uint64-p (nonce)
  (and (integerp nonce)
       (<= 0 nonce +max-account-nonce+)))

(defun validate-execution-transaction-scalar-fields (tx)
  (let ((nonce (transaction-nonce tx))
        (gas-limit (transaction-gas-limit tx))
        (value (transaction-value tx)))
    (unless (transaction-nonce-uint64-p nonce)
      (error 'transaction-validation-error
             :message "Transaction nonce exceeds uint64"))
    (unless (transaction-gas-limit-uint64-p gas-limit)
      (error 'transaction-validation-error
             :message "Transaction gas limit exceeds uint64"))
    (unless (uint256-p value)
      (error 'transaction-validation-error
             :message "Transaction value exceeds uint256")))
  (let ((max-priority-fee (transaction-max-priority-fee-per-gas tx))
        (max-fee (transaction-max-fee-per-gas tx)))
    (unless (uint256-p max-priority-fee)
      (error 'transaction-validation-error
             :message "Max priority fee exceeds uint256"))
    (unless (uint256-p max-fee)
      (error 'transaction-validation-error
             :message "Max fee per gas exceeds uint256"))
    (when (< max-fee max-priority-fee)
      (error 'transaction-validation-error
             :message "Max priority fee exceeds max fee")))
  (when (typep tx 'blob-transaction)
    (unless (uint256-p (blob-transaction-max-fee-per-blob-gas tx))
      (error 'transaction-validation-error
             :message "Max fee per blob gas exceeds uint256")))
  t)

(defun validate-call-transaction-scalar-fields (tx)
  (let ((nonce (transaction-nonce tx))
        (gas-limit (transaction-gas-limit tx))
        (value (transaction-value tx)))
    (unless (transaction-nonce-uint64-p nonce)
      (error 'transaction-validation-error
             :message "Transaction nonce exceeds uint64"))
    (unless (transaction-gas-limit-uint64-p gas-limit)
      (error 'transaction-validation-error
             :message "Transaction gas limit exceeds uint64"))
    (unless (uint256-p value)
      (error 'transaction-validation-error
             :message "Transaction value exceeds uint256")))
  (let ((max-priority-fee (transaction-max-priority-fee-per-gas tx))
        (max-fee (transaction-max-fee-per-gas tx)))
    (unless (uint256-p max-priority-fee)
      (error 'transaction-validation-error
             :message "Max priority fee exceeds uint256"))
    (unless (uint256-p max-fee)
      (error 'transaction-validation-error
             :message "Max fee per gas exceeds uint256")))
  (when (typep tx 'blob-transaction)
    (unless (uint256-p (blob-transaction-max-fee-per-blob-gas tx))
      (error 'transaction-validation-error
             :message "Max fee per blob gas exceeds uint256")))
  t)

(defun validate-transaction-data-field (tx)
  (handler-case
      (progn
        (ensure-byte-vector (transaction-data tx))
        t)
    (error ()
      (error 'transaction-validation-error
             :message "Transaction data must be a byte sequence"))))

(defun validate-transaction-recipient-field (tx)
  (let ((recipient (transaction-to tx)))
    (unless (or (null recipient) (address-p recipient))
      (error 'transaction-validation-error
             :message "Transaction recipient must be an address or nil")))
  t)

(defun validate-set-code-transaction-fields (tx)
  (when (typep tx 'set-code-transaction)
    (unless (transaction-to tx)
      (error 'transaction-validation-error
             :message "Set-code transactions cannot create contracts"))
    (when (null (transaction-authorization-list tx))
      (error 'transaction-validation-error
             :message "Set-code transactions require an authorization list"))
    (dolist (authorization (transaction-authorization-list tx))
      (validate-set-code-authorization-fields authorization)))
  t)

(defun validate-set-code-authorization-fields (authorization)
  (unless (uint256-p (set-code-authorization-chain-id authorization))
    (error 'transaction-validation-error
           :message "Authorization chain id exceeds uint256"))
  (unless (address-p (set-code-authorization-address authorization))
    (error 'transaction-validation-error
           :message "Authorization address must be an address"))
  (unless (transaction-nonce-uint64-p
           (set-code-authorization-nonce authorization))
    (error 'transaction-validation-error
           :message "Authorization nonce exceeds uint64"))
  (unless (uint256-p (set-code-authorization-y-parity authorization))
    (error 'transaction-validation-error
           :message "Authorization y parity exceeds uint256"))
  (unless (uint256-p (set-code-authorization-r authorization))
    (error 'transaction-validation-error
           :message "Authorization r exceeds uint256"))
  (unless (uint256-p (set-code-authorization-s authorization))
    (error 'transaction-validation-error
           :message "Authorization s exceeds uint256"))
  t)

(defun validate-transaction-sender-code (state sender)
  (let ((code (state-db-get-code state sender)))
    (when (and (plusp (length code))
               (not (set-code-delegation-target code)))
      (error 'transaction-validation-error
             :message "Transaction sender has non-delegation code")))
  t)

(defun validate-transaction-senders-code (state senders)
  (dolist (sender senders t)
    (validate-transaction-sender-code state sender)))

(defun validate-access-list-fields (tx)
  (dolist (entry (transaction-access-list tx) t)
    (unless (typep entry 'access-list-entry)
      (error 'transaction-validation-error
             :message "Access list entry must be an access-list entry"))
    (unless (address-p (access-list-entry-address entry))
      (error 'transaction-validation-error
             :message "Access list entry address must be an address"))
    (unless (listp (access-list-entry-storage-keys entry))
      (error 'transaction-validation-error
             :message "Access list storage keys must be a list"))
    (dolist (slot (access-list-entry-storage-keys entry))
      (unless (hash32-p slot)
        (error 'transaction-validation-error
               :message "Access list storage key must be a hash32")))))
