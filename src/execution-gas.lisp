(in-package #:ethereum-lisp.execution)

(defun transaction-blob-fee-cap (tx)
  (if (typep tx 'blob-transaction)
      (blob-transaction-max-fee-per-blob-gas tx)
      0))

(defun call-transaction-effective-gas-price
    (transaction &key (base-fee 0) (eip1559-enabled-p t))
  (cond
    ((not eip1559-enabled-p)
     (transaction-max-priority-fee-per-gas transaction))
    ((or (typep transaction 'legacy-transaction)
         (typep transaction 'access-list-transaction))
     (transaction-max-fee-per-gas transaction))
    (t
     (min (transaction-max-fee-per-gas transaction)
          (+ base-fee
             (transaction-max-priority-fee-per-gas transaction))))))

(defun call-transaction-context-base-fee (gas-price base-fee)
  (if (zerop gas-price) 0 base-fee))

(defun eip3860-initcode-rules-active-p (rules)
  (or (null rules) (chain-rules-shanghai-p rules)))

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

(defun execution-transaction-intrinsic-gas (tx rules)
  (transaction-intrinsic-gas
   tx
   :eip3860-p (eip3860-initcode-rules-active-p rules)))

(defun transaction-evm-gas-used (tx result &optional rules)
  (+ (execution-transaction-intrinsic-gas tx rules)
     (evm-result-gas-used result)))

(defun contract-code-deposit-gas (code)
  (* +create-data-gas+ (length (ensure-byte-vector code))))

(defun eip3541-code-prefix-restricted-p (rules)
  (or (null rules) (chain-rules-london-p rules)))

(defun contract-code-size-limit (rules)
  (if (and rules (chain-rules-amsterdam-p rules))
      +amsterdam-max-contract-code-size+
      +max-contract-code-size+))

(defun contract-initcode-size-limit (rules)
  (* 2 (contract-code-size-limit rules)))

(defun invalid-contract-runtime-code-p (code &optional rules)
  (let ((code (ensure-byte-vector code)))
    (or (> (length code) (contract-code-size-limit rules))
        (and (eip3541-code-prefix-restricted-p rules)
             (plusp (length code))
             (= (aref code 0) #xef)))))

(defun validate-contract-initcode-size (tx &optional rules)
  (when (and (eip3860-initcode-rules-active-p rules)
             (> (length (ensure-byte-vector (transaction-data tx)))
                (contract-initcode-size-limit rules)))
    (error 'transaction-validation-error
           :message "Contract initcode exceeds maximum size"))
  t)
