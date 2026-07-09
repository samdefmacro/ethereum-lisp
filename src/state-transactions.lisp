(in-package #:ethereum-lisp.state)

(define-condition transaction-validation-error (error)
  ((message :initarg :message :reader transaction-validation-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (transaction-validation-error-message condition)))))

(defun transaction-fail (control &rest args)
  (error 'transaction-validation-error
         :message (apply #'format nil control args)))

(defun state-db-account-or-empty (state address)
  (or (state-db-get-account state address)
      (make-state-account)))

(defun state-db-put-account-values (state address nonce balance code-hash)
  (state-db-set-account
   state address
   (make-state-account :nonce nonce
                       :balance balance
                       :code-hash code-hash)))

(defun state-db-transfer-value (state sender recipient value)
  (unless (bytes= (address-bytes sender) (address-bytes recipient))
    (when (plusp value)
      (let ((sender-account (state-db-account-or-empty state sender))
            (recipient-account (state-db-account-or-empty state recipient)))
        (state-db-put-account-values
         state sender
         (state-account-nonce sender-account)
         (- (state-account-balance sender-account) value)
         (state-account-code-hash sender-account))
        (state-db-put-account-values
         state recipient
         (state-account-nonce recipient-account)
         (+ (state-account-balance recipient-account) value)
         (state-account-code-hash recipient-account))))))

(defun state-db-add-balance (state address amount)
  (let ((amount (ensure-state-uint256 amount "Balance amount")))
    (unless (zerop amount)
      (let ((account (state-db-account-or-empty state address)))
        (state-db-put-account-values
         state address
         (state-account-nonce account)
         (+ (state-account-balance account) amount)
         (state-account-code-hash account)))))
  state)

(defun apply-withdrawal (state withdrawal)
  (state-db-add-balance
   state
   (withdrawal-address withdrawal)
   (* (withdrawal-amount withdrawal) +wei-per-gwei+))
  state)

(defun apply-withdrawals (state withdrawals)
  (dolist (withdrawal withdrawals state)
    (apply-withdrawal state withdrawal)))

(defconstant +set-code-authorization-intrinsic-gas+ 25000)

(defun transaction-intrinsic-gas (transaction &key (eip3860-p t))
  (let ((gas (if (transaction-to transaction)
                 +transaction-gas+
                 +contract-creation-transaction-gas+))
        (access-list (transaction-access-list transaction))
        (authorization-list (transaction-authorization-list transaction)))
    (loop for byte across (ensure-byte-vector (transaction-data transaction))
          do (incf gas (if (zerop byte) 4 16)))
    (when (and eip3860-p (not (transaction-to transaction)))
      (incf gas (* +initcode-word-gas+
                   (ceiling (length (ensure-byte-vector
                                     (transaction-data transaction)))
                            32))))
    (incf gas (* 2400 (length access-list)))
    (incf gas (* 1900 (access-list-storage-key-count access-list)))
    (incf gas (* +set-code-authorization-intrinsic-gas+
                 (length authorization-list)))
    gas))

(defun maybe-apply-legacy-transactions-through-message-executor
    (state sender transactions)
  (when (fboundp 'apply-message-list)
    (multiple-value-bind (receipts gas-used)
        (funcall (symbol-function 'apply-message-list)
                 state
                 sender
                 transactions)
      (declare (ignore gas-used))
      receipts)))

(defun apply-legacy-transaction (state sender transaction)
  "Apply a minimal legacy transfer transaction.

When the full execution module is loaded, delegate through the EVM-backed
message executor. The transfer-only fallback remains for standalone state
loading during early bootstrapping."
  (let ((receipts
          (maybe-apply-legacy-transactions-through-message-executor
           state
           sender
           (list transaction))))
    (when receipts
      (return-from apply-legacy-transaction (first receipts))))
  (unless (legacy-transaction-to transaction)
    (transaction-fail "Contract creation transactions are not implemented yet"))
  (let* ((sender-account (state-db-account-or-empty state sender))
         (recipient (legacy-transaction-to transaction))
         (intrinsic-gas (transaction-intrinsic-gas transaction))
         (gas-limit (legacy-transaction-gas-limit transaction))
         (gas-price (legacy-transaction-gas-price transaction))
         (value (legacy-transaction-value transaction))
         (gas-cost (* gas-limit gas-price))
         (total-cost (+ gas-cost value)))
    (unless (= (legacy-transaction-nonce transaction)
               (state-account-nonce sender-account))
      (transaction-fail "Invalid transaction nonce"))
    (when (< gas-limit intrinsic-gas)
      (transaction-fail "Gas limit ~D below intrinsic gas ~D"
                        gas-limit intrinsic-gas))
    (when (< (state-account-balance sender-account) total-cost)
      (transaction-fail "Insufficient sender balance"))
    (state-db-put-account-values
     state sender
     (1+ (state-account-nonce sender-account))
     (- (state-account-balance sender-account) gas-cost)
     (state-account-code-hash sender-account))
    (state-db-transfer-value state sender recipient value)
    (make-receipt :status 1 :cumulative-gas-used gas-limit)))

(defstruct execution-result
  (receipts '() :type list)
  state-root
  transactions-root
  receipts-root)

(defun execute-legacy-transactions (state sender transactions)
  (let ((receipts
          (maybe-apply-legacy-transactions-through-message-executor
           state
           sender
           transactions)))
    (unless receipts
      (let ((fallback-receipts '())
            (cumulative-gas 0))
        (dolist (transaction transactions)
          (let ((receipt (apply-legacy-transaction state sender transaction)))
            (incf cumulative-gas (receipt-cumulative-gas-used receipt))
            (push (make-receipt :status (receipt-status receipt)
                                :cumulative-gas-used cumulative-gas
                                :logs (receipt-logs receipt))
                  fallback-receipts)))
        (setf receipts (nreverse fallback-receipts))))
    (make-execution-result
     :receipts receipts
     :state-root (state-db-root state)
     :transactions-root (transaction-list-root transactions)
     :receipts-root (transaction-receipt-list-root transactions receipts))))
