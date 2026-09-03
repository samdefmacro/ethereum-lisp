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
    (when (< gas-limit
             (max (execution-transaction-intrinsic-gas tx chain-rules)
                  (transaction-effective-floor-gas tx chain-rules)))
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

(defvar *transaction-chain-rules* nil)

(defun execution-london-or-later-p (rules)
  (or (null rules)
      (chain-rules-london-p rules)
      (chain-rules-shanghai-p rules)
      (chain-rules-cancun-p rules)
      (chain-rules-prague-p rules)
      (chain-rules-osaka-p rules)
      (chain-rules-bpo1-p rules)
      (chain-rules-bpo2-p rules)
      (chain-rules-bpo3-p rules)
      (chain-rules-bpo4-p rules)
      (chain-rules-bpo5-p rules)
      (chain-rules-amsterdam-p rules)
      (chain-rules-ubt-p rules)))

(defun apply-refund-counter-to-receipt
    (receipt refund-counter &optional (chain-rules *transaction-chain-rules*))
  (if (plusp refund-counter)
      (let* ((gas-used (receipt-cumulative-gas-used receipt))
             (refund (min refund-counter
                          (floor gas-used
                                 (if (execution-london-or-later-p chain-rules)
                                     +refund-quotient-eip3529+
                                     +refund-quotient-legacy+)))))
        (make-receipt :type (receipt-type receipt)
                      :status (receipt-status receipt)
                      :cumulative-gas-used (- gas-used refund)
                      :regular-gas-used (receipt-regular-gas-used receipt)
                      :state-gas-used (receipt-state-gas-used receipt)
                      :logs (receipt-logs receipt)))
      receipt))

(defun finalized-transaction-gas-values
    (transaction gas-used refund-counter chain-rules)
  "Return billed and peak gas after the fork refund cap and calldata floor."
  (let* ((floor-gas (transaction-effective-floor-gas transaction chain-rules))
         (receipt
           (make-receipt :status 1 :cumulative-gas-used gas-used))
         (refunded
           (apply-refund-counter-to-receipt
            receipt refund-counter chain-rules))
         (floored
           (apply-floor-gas-to-receipt
            refunded floor-gas)))
    (values (receipt-cumulative-gas-used floored)
            (max gas-used floor-gas))))

;; EIP-7623 calldata floor for the transaction currently being finalized.
;; Bound per transaction by apply-message / apply-contract-creation so the
;; floor is applied after refunds without threading it through every receipt
;; construction site. Zero disables the floor (pre-Prague or unbound paths).
(defvar *transaction-floor-gas* 0)

(defun apply-floor-gas-to-receipt (receipt floor-gas)
  "EIP-7623: after refunds, a transaction is billed at least FLOOR-GAS."
  (if (> floor-gas (receipt-cumulative-gas-used receipt))
      (make-receipt :type (receipt-type receipt)
                    :status (receipt-status receipt)
                    :cumulative-gas-used floor-gas
                    :regular-gas-used
                    (max floor-gas (receipt-regular-gas-used receipt))
                    :state-gas-used (receipt-state-gas-used receipt)
                    :logs (receipt-logs receipt))
      receipt))

(defun finalize-transaction-receipt
    (state sender coinbase tx receipt base-fee &key (refund-counter 0))
  (let* ((receipt (apply-refund-counter-to-receipt receipt refund-counter))
         (receipt (apply-floor-gas-to-receipt
                   receipt *transaction-floor-gas*)))
    (refund-unused-gas state sender tx
                       (receipt-cumulative-gas-used receipt)
                       base-fee)
    (pay-priority-fee state coinbase tx receipt base-fee)))
