(in-package #:ethereum-lisp.execution)

(defconstant +create-data-gas+ 200)
(defconstant +max-contract-code-size+ 24576)
(defconstant +max-initcode-size+ (* 2 +max-contract-code-size+))
(defconstant +amsterdam-max-contract-code-size+ 32768)
(defconstant +amsterdam-max-initcode-size+
  (* 2 +amsterdam-max-contract-code-size+))
(defconstant +max-account-nonce+ (1- (ash 1 64)))
(defconstant +max-transaction-gas-limit+ (1- (ash 1 64)))
(defconstant +refund-quotient-eip3529+ 5)
(defconstant +set-code-existing-account-refund+ 12500)
(defconstant +frontier-block-reward+ 5000000000000000000)
(defconstant +byzantium-block-reward+ 3000000000000000000)
(defconstant +constantinople-block-reward+ 2000000000000000000)

(defun execution-account-or-empty (state address)
  (or (state-db-get-account state address)
      (make-state-account)))

(defun put-execution-account-values (state address nonce balance code-hash)
  (state-db-set-account
   state address
   (make-state-account :nonce nonce
                       :balance balance
                       :code-hash code-hash)))

(defun transaction-blob-fee-cap (tx)
  (if (typep tx 'blob-transaction)
      (blob-transaction-max-fee-per-blob-gas tx)
      0))

(defun block-reward-for-rules (rules)
  (cond
    ((and rules (chain-rules-constantinople-p rules))
     +constantinople-block-reward+)
    ((and rules (chain-rules-byzantium-p rules))
     +byzantium-block-reward+)
    (t +frontier-block-reward+)))

(defun apply-block-beneficiary-reward (state beneficiary rules
                                       &key (ommer-count 0))
  (let* ((base-reward (block-reward-for-rules rules))
         (reward (+ base-reward
                    (* ommer-count (floor base-reward 32)))))
    (state-db-add-balance state beneficiary reward)
    reward))

(defun ommer-block-reward (base-reward header ommer)
  (floor (* (+ (block-header-number ommer) 8
               (- (block-header-number header)))
            base-reward)
         8))

(defun apply-block-ommer-rewards (state header ommers rules)
  (let ((base-reward (block-reward-for-rules rules)))
    (dolist (ommer ommers)
      (state-db-add-balance state
                            (or (block-header-beneficiary ommer) (zero-address))
                            (ommer-block-reward base-reward header ommer)))))

(defun block-header-post-merge-p (header)
  (and (plusp (block-header-number header))
       (zerop (block-header-difficulty header))))

(defun apply-block-rewards-for-header (state header ommers rules)
  (unless (block-header-post-merge-p header)
    (apply-block-beneficiary-reward
     state
     (or (block-header-beneficiary header) (zero-address))
     rules
     :ommer-count (length ommers))
    (apply-block-ommer-rewards state header ommers rules)))

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

(defun transfer-value (state sender recipient value)
  (unless (bytes= (address-bytes sender) (address-bytes recipient))
    (when (plusp value)
      (let ((sender-account (execution-account-or-empty state sender))
            (recipient-account (execution-account-or-empty state recipient)))
        (put-execution-account-values
         state sender
         (state-account-nonce sender-account)
         (- (state-account-balance sender-account) value)
         (state-account-code-hash sender-account))
        (put-execution-account-values
         state recipient
         (state-account-nonce recipient-account)
         (+ (state-account-balance recipient-account) value)
         (state-account-code-hash recipient-account))))))

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

(defun eip3860-initcode-rules-active-p (rules)
  (or (null rules) (chain-rules-shanghai-p rules)))

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

(defun valid-set-code-authorization-chain-p (authorization chain-id)
  (let ((authorization-chain-id
          (set-code-authorization-chain-id authorization)))
    (or (zerop authorization-chain-id)
        (= authorization-chain-id chain-id))))

(defun set-code-authorization-nonce-incrementable-p (authorization)
  (< (set-code-authorization-nonce authorization) +max-account-nonce+))

(defun set-code-authority-code-valid-p (state authority)
  (let ((code (state-db-get-code state authority)))
    (or (zerop (length code))
        (set-code-delegation-target code))))

(defun apply-set-code-authorization (state authorization chain-id)
  (when (and (valid-set-code-authorization-chain-p authorization chain-id)
             (set-code-authorization-nonce-incrementable-p authorization))
    (let ((authority (set-code-authorization-authority authorization)))
      (when (and authority
                 (set-code-authority-code-valid-p state authority))
        (let* ((existing-account-p (state-db-get-account state authority))
               (account (or existing-account-p (make-state-account)))
               (authorization-nonce
                 (set-code-authorization-nonce authorization)))
          (when (= authorization-nonce (state-account-nonce account))
            (put-execution-account-values
             state
             authority
             (1+ authorization-nonce)
             (state-account-balance account)
             (state-account-code-hash account))
            (state-db-set-code
             state
             authority
             (if (equalp (address-bytes
                          (set-code-authorization-address authorization))
                         (address-bytes (zero-address)))
                 (make-byte-vector 0)
                 (set-code-delegation-code
                  (set-code-authorization-address authorization))))
            (if existing-account-p +set-code-existing-account-refund+ 0)))))))

(defun apply-set-code-authorizations (state tx chain-id)
  (let ((refund-counter 0))
    (when (typep tx 'set-code-transaction)
      (dolist (authorization (transaction-authorization-list tx))
        (incf refund-counter
              (or (apply-set-code-authorization state authorization chain-id)
                  0))))
    refund-counter))

(defun execution-resolved-code (state address)
  (let* ((code (state-db-get-code state address))
         (delegation-target (set-code-delegation-target code)))
    (if delegation-target
        (state-db-get-code state delegation-target)
        code)))

(defun validate-contract-initcode-size (tx &optional rules)
  (when (and (eip3860-initcode-rules-active-p rules)
             (> (length (ensure-byte-vector (transaction-data tx)))
                (contract-initcode-size-limit rules)))
    (error 'transaction-validation-error
           :message "Contract initcode exceeds maximum size"))
  t)

(defun execution-create-address (creator nonce)
  (let* ((hash (keccak-256
                (rlp-encode
                 (make-rlp-list (address-bytes creator) nonce))))
         (out (make-byte-vector 20)))
    (replace out hash :start2 12)
    (make-address out)))

(defun execution-contract-address-collision-p (state address)
  (let ((account (state-db-get-account state address)))
    (and account
         (not (and (zerop (state-account-nonce account))
                   (zerop (state-account-balance account))
                   (bytes= (hash32-bytes (state-account-storage-root account))
                           (hash32-bytes +empty-trie-hash+))
                   (bytes= (hash32-bytes (state-account-code-hash account))
                           (hash32-bytes +empty-code-hash+)))))))

(defun execution-storage-access-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun execution-account-access-key (address)
  (address-bytes address))

(defun prewarm-execution-address (accessed-addresses address)
  (when address
    (setf (gethash (execution-account-access-key address)
                   accessed-addresses)
          t)))

(defun transaction-accessed-addresses-table
    (tx &key sender destination coinbase chain-rules)
  (let ((accessed-addresses (make-hash-table :test 'equalp)))
    (prewarm-precompile-addresses accessed-addresses chain-rules)
    (prewarm-execution-address accessed-addresses sender)
    (prewarm-execution-address accessed-addresses destination)
    (when (or (null chain-rules)
              (chain-rules-shanghai-p chain-rules))
      (prewarm-execution-address accessed-addresses coinbase))
    (dolist (entry (transaction-access-list tx))
      (prewarm-execution-address accessed-addresses
                                 (access-list-entry-address entry)))
    accessed-addresses))

(defun transaction-accessed-storage-table (tx)
  (let ((accessed-storage (make-hash-table :test 'equalp)))
    (dolist (entry (transaction-access-list tx))
      (dolist (slot (access-list-entry-storage-keys entry))
        (setf (gethash (execution-storage-access-key
                        (access-list-entry-address entry)
                        slot)
                       accessed-storage)
              t)))
    accessed-storage))

(defun execution-chain-rules (chain-rules chain-config block-number timestamp)
  (or chain-rules
      (when chain-config
        (chain-config-rules chain-config block-number timestamp))))

(defun execution-blob-base-fee-update-fraction
    (chain-rules chain-config block-number timestamp)
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
    (if effective-chain-rules
        (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
            (chain-rules-blob-schedule effective-chain-rules)
          (declare (ignore target-blob-gas max-blob-gas))
          update-fraction)
        +blob-base-fee-update-fraction+)))

(defun execution-max-blob-gas
    (chain-rules chain-config block-number timestamp)
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
    (if effective-chain-rules
        (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
            (chain-rules-blob-schedule effective-chain-rules)
          (declare (ignore target-blob-gas update-fraction))
          max-blob-gas)
        (* +max-blobs-per-block+ +blob-gas-per-blob+))))

(defun execution-block-access-list-max-code-size
    (chain-rules chain-config block-number timestamp)
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
    (if (and effective-chain-rules
             (chain-rules-amsterdam-p effective-chain-rules))
        +block-access-list-amsterdam-max-code-size+
        +block-access-list-max-code-size+)))

(defun execution-block-blob-base-fee (header chain-rules chain-config)
  (if (block-header-excess-blob-gas header)
      (block-header-blob-base-fee
       header
       :update-fraction
       (execution-blob-base-fee-update-fraction
        chain-rules
        chain-config
        (block-header-number header)
        (block-header-timestamp header)))
      0))

(defun validate-execution-transaction-type (tx rules)
  (when (and rules
             (not (chain-rules-transaction-type-supported-p rules tx)))
    (error 'block-validation-error
           :message "Transaction type is not active at this fork"))
  t)

(defun validate-execution-transaction-types (transactions rules)
  (dolist (tx transactions t)
    (validate-execution-transaction-type tx rules)))

(defun validate-execution-transaction-fields (tx rules blob-base-fee)
  (validate-execution-transaction-type tx rules)
  (validate-execution-transaction-scalar-fields tx)
  (validate-transaction-recipient-field tx)
  (validate-transaction-data-field tx)
  (validate-access-list-fields tx)
  (when (typep tx 'blob-transaction)
    (validate-blob-transaction-fields tx)
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
    (validate-blob-transaction-fields tx))
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
    (validate-execution-transaction-fields tx rules blob-base-fee)))

(defun make-message-evm-context
    (state sender tx address input gas-price
     &key (base-fee 0)
          (blob-base-fee 0)
          (chain-id 0)
          chain-rules
          chain-config
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
    (make-evm-context
     :state state
     :address address
     :caller sender
     :origin sender
     :call-value (transaction-value tx)
     :input input
     :gas-price gas-price
     :coinbase coinbase
     :timestamp timestamp
     :block-number block-number
     :prev-randao prev-randao
     :difficulty difficulty
     :random-p random-p
     :gas-limit context-gas-limit
     :chain-id chain-id
     :chain-rules effective-chain-rules
     :base-fee base-fee
     :blob-hashes (transaction-blob-versioned-hashes tx)
     :blob-base-fee blob-base-fee
     :accessed-storage (transaction-accessed-storage-table tx)
     :accessed-addresses
     (transaction-accessed-addresses-table tx
                                           :sender sender
                                           :destination address
                                           :coinbase coinbase
                                           :chain-rules effective-chain-rules))))
