(in-package #:ethereum-lisp.execution)

(defun charge-sender-upfront (state sender tx
                              &key (base-fee 0) (blob-base-fee 0)
                                   chain-rules)
  (let* ((sender-account (execution-account-or-empty state sender))
         (nonce (transaction-nonce tx))
         (gas-limit (transaction-gas-limit tx))
         (gas-fee-cap (transaction-max-fee-per-gas tx))
         (value (transaction-value tx)))
    (validate-execution-transaction-scalar-fields tx)
    (unless (= nonce (state-account-nonce sender-account))
      (error 'transaction-validation-error :message "Invalid transaction nonce"))
    (when (= (state-account-nonce sender-account) +max-account-nonce+)
      (error 'transaction-validation-error :message "Sender nonce has maximum value"))
    (when (< gas-limit (execution-transaction-intrinsic-gas tx chain-rules))
      (error 'transaction-validation-error :message "Gas limit below intrinsic gas"))
    (let* ((gas-price (transaction-effective-gas-price tx :base-fee base-fee))
           (execution-gas-cost (* gas-limit gas-price))
           (blob-gas-cost (* (transaction-blob-gas-used tx) blob-base-fee))
           (max-execution-gas-cost (* gas-limit gas-fee-cap))
           (max-blob-gas-cost (* (transaction-blob-gas-used tx)
                                 (transaction-blob-fee-cap tx)))
           (gas-cost (+ execution-gas-cost blob-gas-cost))
           (balance-check-cost (+ max-execution-gas-cost
                                  max-blob-gas-cost
                                  value)))
      (when (< (state-account-balance sender-account) balance-check-cost)
        (error 'transaction-validation-error :message "Insufficient sender balance"))
      (put-execution-account-values
       state sender
       (1+ (state-account-nonce sender-account))
       (- (state-account-balance sender-account) gas-cost)
       (state-account-code-hash sender-account)))))

(defun transfer-call-value-for-simulation (state sender recipient value)
  (let ((sender-account (execution-account-or-empty state sender)))
    (when (< (state-account-balance sender-account) value)
      (error 'transaction-validation-error
             :message "Insufficient sender balance"))
    (transfer-value state sender recipient value)))

(defun pay-priority-fee (state coinbase tx receipt base-fee)
  (let ((fee (* (receipt-cumulative-gas-used receipt)
                (transaction-priority-fee-per-gas tx :base-fee base-fee))))
    (when (plusp fee)
      (state-db-add-balance state coinbase fee)))
  receipt)

(defun refund-unused-gas (state sender tx gas-used base-fee)
  (let* ((gas-limit (transaction-gas-limit tx))
         (unused-gas (- gas-limit gas-used))
         (gas-price (transaction-effective-gas-price tx :base-fee base-fee)))
    (when (plusp unused-gas)
      (state-db-add-balance state sender (* unused-gas gas-price)))))

(defun apply-refund-counter-to-receipt (receipt refund-counter)
  (if (plusp refund-counter)
      (let* ((gas-used (receipt-cumulative-gas-used receipt))
             (refund (min refund-counter
                          (floor gas-used +refund-quotient-eip3529+))))
        (make-receipt :status (receipt-status receipt)
                      :cumulative-gas-used (- gas-used refund)
                      :logs (receipt-logs receipt)))
      receipt))

(defun finalize-transaction-receipt
    (state sender coinbase tx receipt base-fee &key (refund-counter 0))
  (let ((receipt (apply-refund-counter-to-receipt receipt refund-counter)))
    (refund-unused-gas state sender tx
                       (receipt-cumulative-gas-used receipt)
                       base-fee)
    (pay-priority-fee state coinbase tx receipt base-fee)))
