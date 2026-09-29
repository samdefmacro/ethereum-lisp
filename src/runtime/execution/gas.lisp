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

(defun transaction-homestead-active-p (rules)
  "Whether RULES are Homestead or later, a later flag implying it as in
TRANSACTION-EIP2028-ACTIVE-P."
  (or (transaction-eip2028-active-p rules)
      (chain-rules-homestead-p rules)
      (chain-rules-eip150-p rules)
      (chain-rules-eip155-p rules)
      (chain-rules-eip158-p rules)
      (chain-rules-byzantium-p rules)
      (chain-rules-constantinople-p rules)
      (chain-rules-petersburg-p rules)))

(defun transaction-eip158-active-p (rules)
  "Whether RULES are Spurious Dragon (EIP-158/161) or later, a later flag
implying it as in TRANSACTION-EIP2028-ACTIVE-P."
  (or (transaction-eip2028-active-p rules)
      (chain-rules-eip158-p rules)
      (chain-rules-byzantium-p rules)
      (chain-rules-constantinople-p rules)
      (chain-rules-petersburg-p rules)))

(defvar *transaction-sender* nil
  "The sender of the transaction being priced, for EIP-2780.

Amsterdam prices a self-transfer (tx.to is the sender) without the recipient's
access and value charges, so its intrinsic and floor gas depend on the sender.
APPLY-MESSAGE binds the recovered sender.  NIL means unknown and prices a call
as a transfer to another account, the upper bound, which suits pool admission
and RPC estimates.  :SELF-TRANSFER-BOUND prices every call as a self-transfer,
the lower bound: the block-level list pre-check binds it because it runs before
senders are recovered, and APPLY-MESSAGE repeats the check exactly.")

(defun transaction-self-transfer-p (transaction sender)
  (let ((to (transaction-to transaction)))
    (and to
         sender
         (or (eq sender :self-transfer-bound)
             (and (not (keywordp sender))
                  (bytes= (address-bytes to) (address-bytes sender)))))))

(defun transaction-base-gas-eip2780 (transaction sender)
  "EIP-2780 intrinsic base: the sender's resources, then the recipient's.

Mirrors geth v1.17.6 intrinsicBaseGasEIP2780. The recipient touch is charged
at the cold rate whatever its warmth; a self-transfer pays neither the touch
nor the value charges, because the sender's own write already covers them."
  (let ((to (transaction-to transaction))
        (self-p (transaction-self-transfer-p transaction sender))
        (value-p (plusp (transaction-value transaction)))
        (gas +transaction-base-gas-eip2780+))
    (cond (self-p)
          ((null to) (incf gas +create-access-amsterdam+))
          (t (incf gas +cold-account-access-amsterdam+)))
    (cond ((or self-p (not value-p)))
          ((null to) (incf gas +transfer-log-gas-eip2780+))
          (t (incf gas (+ +transfer-log-gas-eip2780+
                          +transaction-value-gas-eip2780+))))
    gas))

(defun transaction-access-list-tokens-eip7981 (access-list)
  "EIP-7981: every access-list address and key byte counts as a nonzero
calldata byte, four floor tokens each."
  (* +standard-token-cost-eip7623+
     (+ (* 20 (length access-list))
        (* 32 (access-list-storage-key-count access-list)))))

(defun transaction-access-list-data-gas-eip7981 (access-list)
  "EIP-7981's intrinsic surcharge: the access list's tokens at the EIP-7976
floor price, on top of the per-entry access charges."
  (* +total-cost-floor-per-token-eip7976+
     (transaction-access-list-tokens-eip7981 access-list)))

(defun transaction-intrinsic-gas-amsterdam (transaction sender eip3860-p)
  "Amsterdam intrinsic gas: geth v1.17.6 IntrinsicGas under IsAmsterdam."
  (let* ((data (ensure-byte-vector (transaction-data transaction)))
         (access-list (transaction-access-list transaction))
         (zero-bytes (count 0 data))
         (gas (+ (transaction-base-gas-eip2780 transaction sender)
                 (* +set-code-authorization-base-gas-amsterdam+
                    (length (transaction-authorization-list transaction)))
                 (* +transaction-data-zero-gas+ zero-bytes)
                 (* +transaction-data-nonzero-gas-eip2028+
                    (- (length data) zero-bytes))
                 (* +access-list-address-gas-amsterdam+
                    (length access-list))
                 (* +access-list-storage-key-gas-amsterdam+
                    (access-list-storage-key-count access-list))
                 (transaction-access-list-data-gas-eip7981 access-list))))
    (when (and eip3860-p (not (transaction-to transaction)))
      (incf gas (* +initcode-word-gas+ (ceiling (length data) 32))))
    gas))

(defun transaction-intrinsic-gas
    (transaction &key (eip3860-p t) chain-rules (sender *transaction-sender*))
  (when (and chain-rules (chain-rules-amsterdam-p chain-rules))
    (return-from transaction-intrinsic-gas
      (transaction-intrinsic-gas-amsterdam transaction sender eip3860-p)))
  ;; A creation pays TxGasContractCreation only from Homestead; a Frontier
  ;; creation costs TxGas (go-ethereum v1.17.6 IntrinsicGas).
  (let ((gas (if (or (transaction-to transaction)
                     (not (transaction-homestead-active-p chain-rules)))
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
    (incf gas (* 2400 (length access-list)))
    (incf gas (* 1900 (access-list-storage-key-count access-list)))
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

(defun transaction-floor-data-gas-eip7976 (transaction sender)
  "Amsterdam floor: geth v1.17.6 FloorDataGas under IsAmsterdam.

EIP-7976 bills every calldata byte, zero or not, as four tokens of 16 gas;
EIP-7981 adds the access list's address and key bytes as tokens too; the floor
is anchored to the EIP-2780 base rather than to 21000."
  (let ((tokens (+ (* +standard-token-cost-eip7623+
                      (length (ensure-byte-vector
                               (transaction-data transaction))))
                   (transaction-access-list-tokens-eip7981
                    (transaction-access-list transaction)))))
    (+ (transaction-base-gas-eip2780 transaction sender)
       (* +total-cost-floor-per-token-eip7976+ tokens))))

(defun transaction-effective-floor-gas
    (tx rules &key (sender *transaction-sender*))
  "The calldata floor when active (EIP-7623 from Prague, EIP-7976 from
Amsterdam); 0 otherwise."
  (cond ((and rules (chain-rules-amsterdam-p rules))
         (transaction-floor-data-gas-eip7976 tx sender))
        ((and rules (chain-rules-prague-p rules))
         (transaction-floor-data-gas tx))
        (t 0)))

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
