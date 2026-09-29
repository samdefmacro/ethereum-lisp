(in-package #:ethereum-lisp.execution)

(defun apply-withdrawal (state withdrawal)
  (if (zerop (withdrawal-amount withdrawal))
      ;; geth v1.17.6 ProcessWithdrawals credits a zero amount too, which
      ;; loads the account: EIP-7928 lists it with no change.  The state is
      ;; unchanged, so before Amsterdam, where nothing records the access,
      ;; this read is invisible.
      (state-db-get-account state (withdrawal-address withdrawal))
      (state-db-add-balance
       state
       (withdrawal-address withdrawal)
       (* (withdrawal-amount withdrawal) +wei-per-gwei+)))
  state)

(defun apply-withdrawals (state withdrawals)
  (dolist (withdrawal withdrawals state)
    (apply-withdrawal state withdrawal)))

(defun apply-legacy-transaction (state sender transaction)
  "Apply one legacy transaction through the EVM-backed message executor."
  (multiple-value-bind (receipts gas-used)
      (apply-message-list state sender (list transaction))
    (declare (ignore gas-used))
    (first receipts)))

(defstruct execution-result
  (receipts '() :type list)
  state-root
  transactions-root
  receipts-root)

(defun execute-legacy-transactions (state sender transactions)
  (multiple-value-bind (receipts gas-used)
      (apply-message-list state sender transactions)
    (declare (ignore gas-used))
    (make-execution-result
     :receipts receipts
     :state-root (state-db-root state)
     :transactions-root (transaction-list-root transactions)
     :receipts-root (transaction-receipt-list-root transactions receipts))))
