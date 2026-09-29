(in-package #:ethereum-lisp.execution)

;;;; Fork-aware execution transaction validation orchestration.

(defun validate-execution-transaction-type (tx rules)
  (when (and rules
             (not (chain-rules-transaction-type-supported-p rules tx)))
    (error 'block-validation-error
           :message "Transaction type is not active at this fork"))
  t)

(defun validate-execution-transaction-types (transactions rules)
  (dolist (tx transactions t)
    (validate-execution-transaction-type tx rules)))

(defun validate-execution-transaction-gas-cap (tx rules)
  "Enforce the EIP-7825 (Osaka) per-transaction gas-limit cap of 2^24."
  (when (and rules
             (chain-rules-amsterdam-p rules)
             (> (max (execution-transaction-intrinsic-gas tx rules)
                     (transaction-effective-floor-gas tx rules))
                +transaction-gas-limit-cap-eip7825+))
    ;; EEST names this INTRINSIC_GAS_TOO_LOW: the intrinsic (or floor) gas
    ;; is more than any transaction gas limit may put in the regular
    ;; dimension (geth v1.17.6 execute, "intrinsic cost ... floor ...").
    (error 'transaction-validation-error
           :message "Amsterdam intrinsic gas exceeds the 2^24 transaction gas limit cap"))
  (when (and rules
             (chain-rules-osaka-p rules)
             (not (chain-rules-amsterdam-p rules))
             (> (transaction-gas-limit tx)
                +transaction-gas-limit-cap-eip7825+))
    (error 'transaction-validation-error
           :message "Transaction gas limit exceeds the EIP-7825 cap"))
  t)

(defun validate-execution-transaction-fields (tx rules blob-base-fee)
  (validate-execution-transaction-type tx rules)
  (validate-execution-transaction-gas-cap tx rules)
  (validate-execution-transaction-scalar-fields tx)
  (validate-transaction-recipient-field tx)
  (validate-transaction-data-field tx)
  (validate-access-list-fields tx)
  (when (typep tx 'blob-transaction)
    (validate-blob-transaction-fields
     tx :max-blobs (chain-rules-max-blobs-per-transaction rules))
    (validate-blob-transaction-fee-cap tx blob-base-fee))
  (validate-set-code-transaction-fields tx)
  (when (< (transaction-gas-limit tx)
           (execution-transaction-intrinsic-gas tx rules))
    (error 'transaction-validation-error
           :message "Gas limit below intrinsic gas"))
  (unless (transaction-to tx)
    (validate-contract-initcode-size tx rules))
  t)

(defun validate-call-transaction-fields (tx rules)
  (validate-execution-transaction-type tx rules)
  (validate-call-transaction-scalar-fields tx)
  (validate-transaction-recipient-field tx)
  (validate-transaction-data-field tx)
  (validate-access-list-fields tx)
  (when (typep tx 'blob-transaction)
    (validate-blob-transaction-fields
     tx :max-blobs (chain-rules-max-blobs-per-transaction rules)))
  (validate-set-code-transaction-fields tx)
  (when (< (transaction-gas-limit tx)
           (execution-transaction-intrinsic-gas tx rules))
    (error 'transaction-validation-error
           :message "Gas limit below intrinsic gas"))
  (unless (transaction-to tx)
    (validate-contract-initcode-size tx rules))
  t)

(defun validate-execution-transaction-list-fields
    (transactions rules blob-base-fee)
  (unless (listp transactions)
    (error 'transaction-validation-error
           :message "Transactions must be a list"))
  (dolist (tx transactions t)
    (unless (typep tx
                   '(or legacy-transaction
                        access-list-transaction
                        dynamic-fee-transaction
                        blob-transaction
                        set-code-transaction))
      (error 'transaction-validation-error
             :message "Transaction list item must be a transaction"))
    ;; Senders are not recovered yet, so Amsterdam's sender-dependent
    ;; intrinsic gas (EIP-2780) is checked at its self-transfer lower bound
    ;; here; APPLY-MESSAGE checks it again, exactly, with the sender bound.
    (let ((*transaction-sender* (or *transaction-sender*
                                    :self-transfer-bound)))
      (validate-execution-transaction-fields tx rules blob-base-fee))))
