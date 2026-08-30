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

(defun transaction-eip2028-active-p (rules)
  "Whether RULES price non-zero calldata at the Istanbul-or-later rate.

Production chain rules are cumulative.  Direct test and RPC configurations may
name only their latest active fork, so a later flag also implies EIP-2028."
  (or (null rules)
      (chain-rules-istanbul-p rules)
      (chain-rules-berlin-p rules)
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

(defun transaction-intrinsic-gas
    (transaction &key (eip3860-p t) chain-rules)
  (let ((gas (if (transaction-to transaction)
                 +transaction-gas+
                 +contract-creation-transaction-gas+))
        (access-list (transaction-access-list transaction))
        (authorization-list (transaction-authorization-list transaction))
        (nonzero-data-gas
          ;; EIP-2028 reduced non-zero calldata from 68 to 16 gas at Istanbul.
          ;; NIL rules retain the current-fork default used by RPC helpers.
          (if (transaction-eip2028-active-p chain-rules)
              +transaction-data-nonzero-gas-eip2028+
              +transaction-data-nonzero-gas-frontier+)))
    (loop for byte across (ensure-byte-vector (transaction-data transaction))
          do (incf gas
                   (if (zerop byte)
                       +transaction-data-zero-gas+
                       nonzero-data-gas)))
    (when (and eip3860-p (not (transaction-to transaction)))
      (incf gas (* +initcode-word-gas+
                   (ceiling (length (ensure-byte-vector
                                     (transaction-data transaction)))
                            32))))
    (incf gas
          (* (if (and chain-rules
                      (chain-rules-amsterdam-p chain-rules))
                 +access-list-address-gas-amsterdam+
                 2400)
             (length access-list)))
    (incf gas
          (* (if (and chain-rules
                      (chain-rules-amsterdam-p chain-rules))
                 +access-list-storage-key-gas-amsterdam+
                 1900)
             (access-list-storage-key-count access-list)))
    (incf gas (* +set-code-authorization-intrinsic-gas+
                 (length authorization-list)))
    gas))

(defun execution-transaction-intrinsic-gas (tx rules)
  (transaction-intrinsic-gas
   tx
   :eip3860-p (chain-rules-initcode-metering-p rules)
   :chain-rules rules))

(defun transaction-runtime-gas-budget (tx rules)
  "Split post-intrinsic gas into EIP-8037 regular gas and state reservoir."
  (let* ((intrinsic (execution-transaction-intrinsic-gas tx rules))
         (execution-gas (- (transaction-gas-limit tx) intrinsic))
         (regular-gas
           (if (and rules (chain-rules-amsterdam-p rules))
               (min (- +transaction-gas-limit-cap-eip7825+ intrinsic)
                    execution-gas)
               execution-gas)))
    (make-evm-gas-budget
     :regular regular-gas
     :state (- execution-gas regular-gas))))

(defun transaction-calldata-tokens (transaction)
  "EIP-7623 token count: 1 per zero calldata byte, 4 per nonzero byte."
  (let ((tokens 0))
    (loop for byte across (ensure-byte-vector (transaction-data transaction))
          do (incf tokens (if (zerop byte) 1 +standard-token-cost-eip7623+)))
    tokens))

(defun transaction-floor-data-gas (transaction)
  "EIP-7623 floor: 21000 + 10 gas per calldata token."
  (+ +transaction-gas+
     (* +total-cost-floor-per-token-eip7623+
        (transaction-calldata-tokens transaction))))

(defun transaction-effective-floor-gas (tx rules)
  "The EIP-7623 calldata floor when active (Prague+); 0 otherwise."
  (if (and rules (chain-rules-prague-p rules))
      (transaction-floor-data-gas tx)
      0))

(defun transaction-evm-gas-used (tx result &optional rules)
  ;; Pre-floor execution gas. The EIP-7623 floor is applied after the refund
  ;; in finalize-transaction-receipt, so the refund cap uses this value.
  (+ (execution-transaction-intrinsic-gas tx rules)
     (evm-result-regular-gas-used result)
     (evm-result-state-gas-used result)))

(defun transaction-evm-regular-gas-used (tx result rules)
  (+ (execution-transaction-intrinsic-gas tx rules)
     (evm-result-regular-gas-used result)))

(defun transaction-exceptional-regular-gas-used (tx rules)
  (if (and rules (chain-rules-amsterdam-p rules))
      (min (transaction-gas-limit tx)
           +transaction-gas-limit-cap-eip7825+)
      (transaction-gas-limit tx)))

(defun contract-code-deposit-gas (code)
  (* +create-data-gas+ (length (ensure-byte-vector code))))

(defun invalid-contract-runtime-code-p (code &optional rules)
  (let ((code (ensure-byte-vector code)))
    (or (> (length code) (chain-rules-contract-code-size-limit rules))
        (and (chain-rules-code-prefix-restricted-p rules)
             (plusp (length code))
             (= (aref code 0) #xef)))))

(defun validate-contract-initcode-size (tx &optional rules)
  (when (and (chain-rules-initcode-metering-p rules)
             (> (length (ensure-byte-vector (transaction-data tx)))
                (chain-rules-contract-initcode-size-limit rules)))
    (error 'transaction-validation-error
           :message "Contract initcode exceeds maximum size"))
  t)
