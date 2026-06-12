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
         (or (plusp (state-account-nonce account))
             (not (bytes= (hash32-bytes (state-account-code-hash account))
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
    (prewarm-execution-address accessed-addresses coinbase)
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

(defun execution-copy-equalp-table (table)
  (let ((copy (make-hash-table :test 'equalp)))
    (maphash (lambda (key value)
               (setf (gethash key copy) value))
             table)
    copy))

(defun execute-contract-creation-call
    (state sender tx effective-chain-rules
     &key (base-fee 0)
          (blob-base-fee 0)
          (chain-id 0)
          chain-config
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  (let* ((call-state (state-db-copy state))
         (contract (execution-create-address
                    sender
                    (transaction-nonce tx)))
         (gas-limit (transaction-gas-limit tx))
         (gas-price (call-transaction-effective-gas-price
                     tx :base-fee base-fee))
         (context-base-fee
           (call-transaction-context-base-fee gas-price base-fee))
         (intrinsic-gas (execution-transaction-intrinsic-gas
                         tx effective-chain-rules)))
    (if (execution-contract-address-collision-p call-state contract)
        (values :failed
                (make-byte-vector 0)
                gas-limit
                (make-hash-table :test 'equalp)
                (make-hash-table :test 'equalp))
        (handler-case
            (let ((context nil))
              (transfer-call-value-for-simulation
               call-state sender contract (transaction-value tx))
              (let ((contract-account
                      (execution-account-or-empty call-state contract)))
                (put-execution-account-values
                 call-state
                 contract
                 1
                 (state-account-balance contract-account)
                 (state-account-code-hash contract-account)))
              (setf context
                    (make-message-evm-context
                     call-state sender tx contract (make-byte-vector 0)
                     gas-price
                     :base-fee context-base-fee
                     :blob-base-fee blob-base-fee
                     :chain-id chain-id
                     :chain-rules effective-chain-rules
                     :chain-config chain-config
                     :coinbase coinbase
                     :timestamp timestamp
                     :block-number block-number
                     :prev-randao prev-randao
                     :difficulty difficulty
                     :random-p random-p
                     :context-gas-limit context-gas-limit))
              (let* ((result
                       (execute-bytecode
                        (transaction-data tx)
                        :context context
                        :gas-limit (- gas-limit intrinsic-gas)))
                     (return-data (copy-seq (evm-result-return-data result)))
                     (accessed-addresses
                       (execution-copy-equalp-table
                        (evm-context-accessed-addresses context)))
                     (accessed-storage
                       (execution-copy-equalp-table
                        (evm-context-accessed-storage context))))
                (if (eq (evm-result-status result) :reverted)
                    (values :reverted
                            return-data
                            (transaction-evm-gas-used
                             tx result effective-chain-rules)
                            accessed-addresses
                            accessed-storage)
                    (let ((gas-used
                            (+ (transaction-evm-gas-used
                                tx result effective-chain-rules)
                               (contract-code-deposit-gas return-data))))
                      (if (or (invalid-contract-runtime-code-p
                               return-data
                               (evm-context-chain-rules context))
                              (> gas-used gas-limit))
                          (values :failed
                                  (make-byte-vector 0)
                                  gas-limit
                                  accessed-addresses
                                  accessed-storage)
                          (values (evm-result-status result)
                                  return-data
                                  gas-used
                                  accessed-addresses
                                  accessed-storage))))))
          (evm-error ()
            (values :failed
                    (make-byte-vector 0)
                    gas-limit
                    (make-hash-table :test 'equalp)
                    (make-hash-table :test 'equalp)))))))

(defun execute-message-call
    (state sender tx
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
  "Execute a call-style transaction against a copied state DB.

Returns status, return data, gas used, accessed-address table, and
accessed-storage table as multiple values. The caller's state object is never
mutated."
  (let* ((effective-chain-rules
           (execution-chain-rules chain-rules chain-config block-number timestamp))
         (recipient (transaction-to tx)))
    (validate-call-transaction-fields tx effective-chain-rules)
    (unless recipient
      (return-from execute-message-call
        (execute-contract-creation-call
         state sender tx effective-chain-rules
         :base-fee base-fee
         :blob-base-fee blob-base-fee
         :chain-id chain-id
         :chain-config chain-config
         :coinbase coinbase
         :timestamp timestamp
         :block-number block-number
         :prev-randao prev-randao
         :difficulty difficulty
         :random-p random-p
         :context-gas-limit context-gas-limit)))
    (let* ((call-state (state-db-copy state))
           (gas-limit (transaction-gas-limit tx))
           (gas-price (call-transaction-effective-gas-price
                       tx :base-fee base-fee))
           (context-base-fee
             (call-transaction-context-base-fee gas-price base-fee))
           (intrinsic-gas (execution-transaction-intrinsic-gas
                           tx effective-chain-rules))
           (code (execution-resolved-code call-state recipient)))
      (transfer-call-value-for-simulation
       call-state sender recipient (transaction-value tx))
      (if (zerop (length code))
          (values :successful
                  (make-byte-vector 0)
                  intrinsic-gas
                  (make-hash-table :test 'equalp)
                  (make-hash-table :test 'equalp))
          (handler-case
              (let ((context
                      (make-message-evm-context
                       call-state sender tx recipient (transaction-data tx)
                       gas-price
                       :base-fee context-base-fee
                       :blob-base-fee blob-base-fee
                       :chain-id chain-id
                       :chain-rules effective-chain-rules
                       :chain-config chain-config
                       :coinbase coinbase
                       :timestamp timestamp
                       :block-number block-number
                       :prev-randao prev-randao
                       :difficulty difficulty
                       :random-p random-p
                       :context-gas-limit context-gas-limit)))
                (let ((result
                        (execute-bytecode
                         code
                         :context context
                         :gas-limit (- gas-limit intrinsic-gas))))
                (values (evm-result-status result)
                        (copy-seq (evm-result-return-data result))
                        (transaction-evm-gas-used
                         tx result effective-chain-rules)
                        (execution-copy-equalp-table
                         (evm-context-accessed-addresses context))
                        (execution-copy-equalp-table
                         (evm-context-accessed-storage context)))))
            (evm-error ()
              (values :failed
                      (make-byte-vector 0)
                      gas-limit
                      (make-hash-table :test 'equalp)
                      (make-hash-table :test 'equalp))))))))

(defun apply-contract-creation (state sender tx
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
  (let* ((effective-chain-rules
           (execution-chain-rules chain-rules chain-config block-number timestamp))
         (intrinsic-gas (execution-transaction-intrinsic-gas
                         tx effective-chain-rules))
         (sender-account (execution-account-or-empty state sender))
         (contract (execution-create-address
                    sender
                    (state-account-nonce sender-account)))
         (gas-limit (transaction-gas-limit tx))
         (gas-price (transaction-effective-gas-price tx :base-fee base-fee)))
    (validate-contract-initcode-size tx effective-chain-rules)
    (charge-sender-upfront state sender tx
                           :base-fee base-fee
                           :blob-base-fee blob-base-fee
                           :chain-rules effective-chain-rules)
    (let ((snapshot (state-db-copy state)))
      (handler-case
          (if (execution-contract-address-collision-p state contract)
              (finalize-transaction-receipt
               state sender coinbase tx
               (make-receipt :status 0 :cumulative-gas-used gas-limit)
               base-fee)
              (progn
                (transfer-value state sender contract
                                (transaction-value tx))
                (let ((contract-account
                        (execution-account-or-empty state contract)))
                  (put-execution-account-values
                   state
                   contract
                   1
                   (state-account-balance contract-account)
                   (state-account-code-hash contract-account)))
                (let* ((context
                         (make-message-evm-context
                          state sender tx contract (make-byte-vector 0)
                          gas-price
                          :base-fee base-fee
                          :blob-base-fee blob-base-fee
                          :chain-id chain-id
                          :chain-rules effective-chain-rules
                          :chain-config chain-config
                          :coinbase coinbase
                          :timestamp timestamp
                          :block-number block-number
                          :prev-randao prev-randao
                          :difficulty difficulty
                          :random-p random-p
                          :context-gas-limit context-gas-limit))
                       (result
                         (execute-bytecode
                          (transaction-data tx)
	                          :context context
	                          :gas-limit (- gas-limit intrinsic-gas))))
                  (if (eq (evm-result-status result) :reverted)
                      (progn
                        (state-db-restore state snapshot)
                        (finalize-transaction-receipt
                         state sender coinbase tx
                         (make-receipt :status 0
	                                       :cumulative-gas-used
	                                       (transaction-evm-gas-used
                                            tx result effective-chain-rules))
                         base-fee))
                      (progn
                        (let* ((runtime-code (evm-result-return-data result))
	                               (gas-used (+ (transaction-evm-gas-used
                                                  tx result effective-chain-rules)
	                                            (contract-code-deposit-gas
	                                             runtime-code))))
                          (if (or (invalid-contract-runtime-code-p
                                   runtime-code
                                   (evm-context-chain-rules context))
                                  (> gas-used gas-limit))
                              (progn
                                (state-db-restore state snapshot)
                                (finalize-transaction-receipt
                                 state sender coinbase tx
                                 (make-receipt :status 0
                                               :cumulative-gas-used gas-limit)
                                 base-fee))
                              (progn
                                (state-db-set-code state contract runtime-code)
                                (finalize-transaction-receipt
                                 state sender coinbase tx
                                 (make-receipt :status 1
                                               :cumulative-gas-used gas-used
                                               :logs (evm-result-logs result))
                                 base-fee
                                 :refund-counter
                                 (evm-result-refund-counter result))))))))))
	        (evm-error ()
          (state-db-restore state snapshot)
          (finalize-transaction-receipt
           state sender coinbase tx
           (make-receipt :status 0 :cumulative-gas-used gas-limit)
           base-fee))))))

(defun apply-message
    (state sender tx
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
  "Apply a transaction message and execute recipient code when present."
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp)))
  (validate-execution-transaction-fields tx effective-chain-rules blob-base-fee)
  (validate-transaction-sender-code state sender)
  (if (transaction-to tx)
      (let* ((recipient (transaction-to tx))
             (gas-limit (transaction-gas-limit tx))
             (gas-price (transaction-effective-gas-price tx :base-fee base-fee)))
        (charge-sender-upfront state sender tx
                               :base-fee base-fee
                               :blob-base-fee blob-base-fee
                               :chain-rules effective-chain-rules)
        (let* ((refund-counter
                 (apply-set-code-authorizations state tx chain-id))
               (code (execution-resolved-code state recipient)))
        (if (zerop (length code))
            (progn
              (transfer-value state sender recipient
                              (transaction-value tx))
              (finalize-transaction-receipt
               state sender coinbase tx
               (make-receipt :status 1
	                             :cumulative-gas-used
	                             (execution-transaction-intrinsic-gas
                                  tx effective-chain-rules))
               base-fee
               :refund-counter refund-counter))
            (let ((snapshot (state-db-copy state)))
              (transfer-value state sender recipient
                              (transaction-value tx))
              (handler-case
                  (let* ((context
                           (make-message-evm-context
                            state sender tx recipient (transaction-data tx)
                            gas-price
                            :base-fee base-fee
                            :blob-base-fee blob-base-fee
                            :chain-id chain-id
	                            :chain-rules effective-chain-rules
	                            :chain-config chain-config
                            :coinbase coinbase
                            :timestamp timestamp
                            :block-number block-number
                            :prev-randao prev-randao
                            :difficulty difficulty
                            :random-p random-p
                            :context-gas-limit context-gas-limit))
                         (result (execute-bytecode code
                                                   :context context
	                                                   :gas-limit (- gas-limit
	                                                                 (execution-transaction-intrinsic-gas
                                                                      tx effective-chain-rules)))))
                    (if (eq (evm-result-status result) :reverted)
                        (progn
                          (state-db-restore state snapshot)
                          (finalize-transaction-receipt
                           state sender coinbase tx
                           (make-receipt :status 0
	                                         :cumulative-gas-used
	                                         (transaction-evm-gas-used
                                              tx result effective-chain-rules))
                           base-fee
                           :refund-counter refund-counter))
                        (finalize-transaction-receipt
                         state sender coinbase tx
                         (make-receipt :status 1
	                                       :cumulative-gas-used
	                                       (transaction-evm-gas-used
                                            tx result effective-chain-rules)
                                       :logs (evm-result-logs result))
                         base-fee
                         :refund-counter
                         (+ refund-counter
                            (evm-result-refund-counter result)))))
                (evm-error ()
                  (state-db-restore state snapshot)
                  (finalize-transaction-receipt
                   state sender coinbase tx
                   (make-receipt :status 0
                                 :cumulative-gas-used gas-limit)
                   base-fee
                   :refund-counter refund-counter)))))))
      (apply-contract-creation state sender tx
                               :base-fee base-fee
                               :blob-base-fee blob-base-fee
                               :chain-id chain-id
                               :chain-rules effective-chain-rules
                               :chain-config chain-config
                               :coinbase coinbase
                               :timestamp timestamp
                               :block-number block-number
                               :prev-randao prev-randao
                               :difficulty difficulty
                               :random-p random-p
	                               :context-gas-limit context-gas-limit))))

(defun transaction-declared-chain-id (tx)
  (typecase tx
    (legacy-transaction
     (legacy-transaction-chain-id tx))
    (access-list-transaction
     (access-list-transaction-chain-id tx))
    (dynamic-fee-transaction
     (dynamic-fee-transaction-chain-id tx))
    (blob-transaction
     (blob-transaction-chain-id tx))
    (set-code-transaction
     (set-code-transaction-chain-id tx))
    (t 0)))

(defun transaction-context-chain-id (tx expected-chain-id)
  (or expected-chain-id
      (transaction-declared-chain-id tx)
      0))

(defun signed-transaction-sender-or-error (tx expected-chain-id)
  (or (transaction-sender tx :expected-chain-id expected-chain-id)
      (error 'transaction-validation-error
             :message "Invalid transaction signature")))

(defun signed-transaction-senders-or-error (transactions expected-chain-id)
  (mapcar (lambda (tx)
            (signed-transaction-sender-or-error tx expected-chain-id))
          transactions))

(defun apply-signed-message
    (state tx
     &key expected-chain-id
          (base-fee 0)
          (blob-base-fee 0)
          chain-rules
          chain-config
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  "Recover the transaction sender from its signature and apply the message."
  (let ((sender (signed-transaction-sender-or-error tx expected-chain-id))
        (chain-id (transaction-context-chain-id tx expected-chain-id)))
    (apply-message state sender tx
                   :base-fee base-fee
                   :blob-base-fee blob-base-fee
                   :chain-id chain-id
                   :chain-rules chain-rules
                   :chain-config chain-config
                   :coinbase coinbase
                   :timestamp timestamp
                   :block-number block-number
                   :prev-randao prev-randao
                   :difficulty difficulty
                   :random-p random-p
                   :context-gas-limit context-gas-limit)))

(defun apply-legacy-message (state sender tx)
  "Apply a legacy transaction and execute recipient code when present."
  (apply-message state sender tx))

(defun apply-message-list
    (state sender transactions
     &key (base-fee 0)
          (blob-base-fee 0)
          (chain-id 0)
          chain-rules
          chain-config
          block-gas-limit
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp))
        (receipts '())
        (cumulative-gas 0))
    (validate-execution-transaction-list-fields transactions
                                                effective-chain-rules
                                                blob-base-fee)
    (validate-transaction-sender-code state sender)
    (dolist (tx transactions)
      (when (and block-gas-limit
                 (> (+ cumulative-gas (transaction-gas-limit tx))
                    block-gas-limit))
        (error 'block-validation-error :message "Block gas limit exceeded"))
      (let ((receipt (apply-message state sender tx
                                    :base-fee base-fee
                                    :blob-base-fee blob-base-fee
                                    :chain-id chain-id
                                    :chain-rules effective-chain-rules
                                    :chain-config chain-config
                                    :coinbase coinbase
                                    :timestamp timestamp
                                    :block-number block-number
                                    :prev-randao prev-randao
                                    :difficulty difficulty
                                    :random-p random-p
                                    :context-gas-limit context-gas-limit)))
        (incf cumulative-gas (receipt-cumulative-gas-used receipt))
        (push (make-receipt :status (receipt-status receipt)
                            :cumulative-gas-used cumulative-gas
                            :logs (receipt-logs receipt))
              receipts)))
    (values (nreverse receipts) cumulative-gas)))

(defun apply-signed-message-list
    (state transactions
     &key expected-chain-id
          (base-fee 0)
          (blob-base-fee 0)
          chain-rules
          chain-config
          block-gas-limit
          (coinbase (zero-address))
          (timestamp 0)
          (block-number 0)
          (prev-randao (zero-hash32))
          (difficulty 0)
          (random-p t)
          (context-gas-limit 0))
  (let ((effective-chain-rules
          (execution-chain-rules chain-rules chain-config block-number timestamp))
        (receipts '())
        (cumulative-gas 0))
    (validate-execution-transaction-list-fields transactions
                                                effective-chain-rules
                                                blob-base-fee)
    (let ((senders (signed-transaction-senders-or-error transactions
                                                        expected-chain-id)))
      (validate-transaction-senders-code state senders)
      (loop for tx in transactions
            for sender in senders
            do
        (when (and block-gas-limit
                   (> (+ cumulative-gas (transaction-gas-limit tx))
                      block-gas-limit))
          (error 'block-validation-error :message "Block gas limit exceeded"))
        (let ((receipt (apply-message
                        state sender tx
                        :base-fee base-fee
                        :blob-base-fee blob-base-fee
                        :chain-id (transaction-context-chain-id
                                   tx expected-chain-id)
                        :chain-rules effective-chain-rules
                        :chain-config chain-config
                        :coinbase coinbase
                        :timestamp timestamp
                        :block-number block-number
                        :prev-randao prev-randao
                        :difficulty difficulty
                        :random-p random-p
                        :context-gas-limit context-gas-limit)))
          (incf cumulative-gas (receipt-cumulative-gas-used receipt))
          (push (make-receipt :status (receipt-status receipt)
                              :cumulative-gas-used cumulative-gas
                              :logs (receipt-logs receipt))
                receipts))))
    (values (nreverse receipts) cumulative-gas)))

(defun apply-legacy-message-list (state sender transactions)
  (apply-message-list state sender transactions))

(defun execute-legacy-messages (state sender transactions)
  (multiple-value-bind (receipts gas-used)
      (apply-legacy-message-list state sender transactions)
    (declare (ignore gas-used))
    (make-execution-result
     :receipts receipts
     :state-root (state-db-root state)
     :transactions-root (transaction-list-root transactions)
     :receipts-root (transaction-receipt-list-root transactions receipts))))

(defun execute-signed-messages
    (state transactions &key expected-chain-id chain-rules chain-config)
  (multiple-value-bind (receipts gas-used)
      (apply-signed-message-list state transactions
                                 :expected-chain-id expected-chain-id
                                 :chain-rules chain-rules
                                 :chain-config chain-config)
    (declare (ignore gas-used))
    (make-execution-result
     :receipts receipts
     :state-root (state-db-root state)
     :transactions-root (transaction-list-root transactions)
     :receipts-root (transaction-receipt-list-root transactions receipts))))

(defun execution-hash32= (left right)
  (and left
       right
       (bytes= (hash32-bytes left) (hash32-bytes right))))

(defun normalize-execution-block-access-list-input
    (block-access-list block-access-list-supplied-p
     block-access-list-rlp block-access-list-rlp-supplied-p)
  (when (and block-access-list-supplied-p
             block-access-list-rlp-supplied-p)
    (error 'block-validation-error
           :message
           "Block access list cannot be supplied as both typed data and RLP"))
  (if block-access-list-rlp-supplied-p
      (values (block-access-list-from-rlp block-access-list-rlp)
              t
              (ensure-byte-vector block-access-list-rlp))
      (values block-access-list block-access-list-supplied-p nil)))

(defun execution-block-access-list-commitment
    (block-access-list encoded-block-access-list &key max-code-size max-items)
  (validate-block-access-list-fields block-access-list
                                     :max-code-size max-code-size
                                     :max-items max-items)
  (if encoded-block-access-list
      (let ((decoded (block-access-list-from-rlp
                      encoded-block-access-list
                      :max-code-size max-code-size
                      :max-items max-items)))
        (unless (bytes= (block-access-list-rlp decoded)
                        (block-access-list-rlp block-access-list))
          (error 'block-validation-error
                 :message
                 "Encoded block access list does not match block access list body"))
        (keccak-256-hash encoded-block-access-list))
      (block-access-list-hash block-access-list)))

(defun validate-block-fork-body-shape-before-execution
    (header chain-config &key withdrawals-supplied-p requests-supplied-p
                              block-access-list-supplied-p
                              max-blob-gas)
  (when chain-config
    (let* ((number (block-header-number header))
           (timestamp (block-header-timestamp header))
           (london-p (chain-config-london-p chain-config number))
           (shanghai-p (chain-config-shanghai-p chain-config number timestamp))
           (cancun-p (chain-config-cancun-p chain-config number timestamp))
           (prague-p (chain-config-prague-p chain-config number timestamp))
           (amsterdam-p (chain-config-amsterdam-p chain-config number timestamp)))
      (cond
        (london-p
         (unless (block-header-base-fee-per-gas header)
           (error 'block-validation-error
                  :message "Header is missing base fee")))
        ((block-header-base-fee-per-gas header)
         (error 'block-validation-error
                :message "Base fee present before London")))
      (cond
        (shanghai-p
         (unless (or withdrawals-supplied-p
                     (block-header-withdrawals-root header))
           (error 'block-validation-error
                  :message "Header is missing withdrawals root")))
        ((or withdrawals-supplied-p
             (block-header-withdrawals-root header))
         (error 'block-validation-error
                :message "Withdrawals present before Shanghai")))
      (validate-block-cancun-fields header :cancun-enabled-p cancun-p)
      (if cancun-p
          (validate-block-blob-gas-fields header
                                          :blob-gas-enabled-p t
                                          :max-blob-gas max-blob-gas)
          (validate-block-blob-gas-fields header :blob-gas-enabled-p nil))
      (cond
        (prague-p
         (unless (or requests-supplied-p
                     (block-header-requests-hash header))
           (error 'block-validation-error
                  :message "Header is missing requests hash")))
        ((or requests-supplied-p
             (block-header-requests-hash header))
         (error 'block-validation-error
                :message "Execution requests present before Prague")))
      (cond
        (amsterdam-p
         (unless (or block-access-list-supplied-p
                     (block-header-block-access-list-hash header))
           (error 'block-validation-error
                  :message "Header is missing block access list hash")))
        ((or block-access-list-supplied-p
             (block-header-block-access-list-hash header))
         (error 'block-validation-error
                :message "Block access list present before Amsterdam")))))
  t)

(defun validate-block-body-commitments-before-execution
    (transactions header &key (ommers '())
                              withdrawals
                              withdrawals-supplied-p
                              requests
                              requests-supplied-p
                              block-access-list
                              block-access-list-supplied-p
                              encoded-block-access-list
                              max-blob-gas
                              block-access-list-max-code-size)
  (let ((actual-blob-gas-used (blob-gas-used transactions))
        (header-blob-gas-used (block-header-blob-gas-used header)))
    (when (and (block-header-transactions-root header)
               (not (execution-hash32=
                     (block-header-transactions-root header)
                     (transaction-list-root transactions))))
      (error 'block-validation-error :message "Transaction root hash mismatch"))
    (when (and (block-header-ommers-hash header)
               (not (execution-hash32=
                     (block-header-ommers-hash header)
                     (ommers-hash ommers))))
      (error 'block-validation-error :message "Ommers root hash mismatch"))
    (when (block-header-withdrawals-root header)
      (unless withdrawals-supplied-p
        (error 'block-validation-error
               :message "Missing withdrawals in block body"))
      (validate-withdrawal-list-fields withdrawals)
      (unless (execution-hash32= (block-header-withdrawals-root header)
                                 (withdrawal-list-root withdrawals))
        (error 'block-validation-error
               :message "Withdrawals root hash mismatch")))
    (when (and withdrawals-supplied-p
               (not (block-header-withdrawals-root header)))
      (validate-withdrawal-list-fields withdrawals))
    (when (block-header-requests-hash header)
      (unless requests-supplied-p
        (error 'block-validation-error
               :message "Missing execution requests in block body"))
      (validate-execution-request-list-fields requests)
      (unless (execution-hash32= (block-header-requests-hash header)
                                 (execution-requests-hash requests))
        (error 'block-validation-error
               :message "Execution requests hash mismatch")))
    (when (and requests-supplied-p
               (not (block-header-requests-hash header)))
      (validate-execution-request-list-fields requests))
    (when (block-header-block-access-list-hash header)
      (unless block-access-list-supplied-p
        (error 'block-validation-error
               :message "Missing block access list in block body"))
      (unless (execution-hash32= (block-header-block-access-list-hash header)
                                 (execution-block-access-list-commitment
                                  block-access-list
                                  encoded-block-access-list
                                  :max-code-size
                                  block-access-list-max-code-size
                                  :max-items
                                  (when (plusp (block-header-gas-limit header))
                                    (floor (block-header-gas-limit header)
                                           +block-access-list-item-gas-cost+))))
        (error 'block-validation-error
               :message "Block access list hash mismatch")))
    (when (and block-access-list-supplied-p
               (not (block-header-block-access-list-hash header)))
      (execution-block-access-list-commitment
       block-access-list
       encoded-block-access-list
       :max-code-size block-access-list-max-code-size
       :max-items (when (plusp (block-header-gas-limit header))
                    (floor (block-header-gas-limit header)
                           +block-access-list-item-gas-cost+))))
    (when (and header-blob-gas-used
               (/= header-blob-gas-used actual-blob-gas-used))
      (error 'block-validation-error :message "Blob gas used mismatch"))
    (when (and max-blob-gas
               (> actual-blob-gas-used max-blob-gas))
      (error 'block-validation-error :message "Blob gas used exceeds maximum"))
    actual-blob-gas-used))

(defun validate-supplied-block-execution-roots
    (header transactions receipts state-root)
  (let ((receipts-root (transaction-receipt-list-root transactions receipts))
        (gas-used (if receipts
                      (receipt-cumulative-gas-used (car (last receipts)))
                      0))
        (logs-bloom (bloom-bytes
                     (receipt-bloom
                      (loop for receipt in receipts
                            append (receipt-logs receipt))))))
    (when (and (plusp (block-header-gas-used header))
               (/= (block-header-gas-used header) gas-used))
      (error 'block-validation-error :message "Gas used mismatch"))
    (when (and (block-header-state-root header)
               (not (execution-hash32= (block-header-state-root header)
                                       state-root)))
      (error 'block-validation-error :message "State root mismatch"))
    (when (and (block-header-receipts-root header)
               (not (execution-hash32= (block-header-receipts-root header)
                                       receipts-root)))
      (error 'block-validation-error :message "Receipts root mismatch"))
    (when (and (block-header-logs-bloom header)
               (not (bytes= (block-header-logs-bloom header) logs-bloom)))
      (error 'block-validation-error :message "Logs bloom mismatch")))
  t)

(defun copy-block-header-for-execution (header)
  (make-block-header
   :parent-hash (block-header-parent-hash header)
   :ommers-hash (block-header-ommers-hash header)
   :beneficiary (block-header-beneficiary header)
   :state-root (block-header-state-root header)
   :transactions-root (block-header-transactions-root header)
   :receipts-root (block-header-receipts-root header)
   :logs-bloom (block-header-logs-bloom header)
   :difficulty (block-header-difficulty header)
   :number (block-header-number header)
   :gas-limit (block-header-gas-limit header)
   :gas-used (block-header-gas-used header)
   :timestamp (block-header-timestamp header)
   :extra-data (block-header-extra-data header)
   :mix-hash (block-header-mix-hash header)
   :nonce (block-header-nonce header)
   :base-fee-per-gas (block-header-base-fee-per-gas header)
   :withdrawals-root (block-header-withdrawals-root header)
   :blob-gas-used (block-header-blob-gas-used header)
   :excess-blob-gas (block-header-excess-blob-gas header)
   :parent-beacon-root (block-header-parent-beacon-root header)
   :requests-hash (block-header-requests-hash header)
   :block-access-list-hash (block-header-block-access-list-hash header)
   :slot-number (block-header-slot-number header)))

(defun restore-block-header-for-execution (header snapshot)
  (setf (block-header-parent-hash header) (block-header-parent-hash snapshot)
        (block-header-ommers-hash header) (block-header-ommers-hash snapshot)
        (block-header-beneficiary header) (block-header-beneficiary snapshot)
        (block-header-state-root header) (block-header-state-root snapshot)
        (block-header-transactions-root header)
        (block-header-transactions-root snapshot)
        (block-header-receipts-root header) (block-header-receipts-root snapshot)
        (block-header-logs-bloom header) (block-header-logs-bloom snapshot)
        (block-header-difficulty header) (block-header-difficulty snapshot)
        (block-header-number header) (block-header-number snapshot)
        (block-header-gas-limit header) (block-header-gas-limit snapshot)
        (block-header-gas-used header) (block-header-gas-used snapshot)
        (block-header-timestamp header) (block-header-timestamp snapshot)
        (block-header-extra-data header) (block-header-extra-data snapshot)
        (block-header-mix-hash header) (block-header-mix-hash snapshot)
        (block-header-nonce header) (block-header-nonce snapshot)
        (block-header-base-fee-per-gas header)
        (block-header-base-fee-per-gas snapshot)
        (block-header-withdrawals-root header)
        (block-header-withdrawals-root snapshot)
        (block-header-blob-gas-used header)
        (block-header-blob-gas-used snapshot)
        (block-header-excess-blob-gas header)
        (block-header-excess-blob-gas snapshot)
        (block-header-parent-beacon-root header)
        (block-header-parent-beacon-root snapshot)
        (block-header-requests-hash header) (block-header-requests-hash snapshot)
        (block-header-block-access-list-hash header)
        (block-header-block-access-list-hash snapshot)
        (block-header-slot-number header) (block-header-slot-number snapshot))
  header)

(defun execute-legacy-block (state sender transactions
                             &key (header (make-block-header))
                                  chain-rules
                                  chain-config
                                  (apply-block-rewards-p nil)
                                  (ommers '())
                                  (withdrawals nil withdrawals-supplied-p)
                                  (requests nil requests-supplied-p)
                                  (block-access-list nil
                                   block-access-list-supplied-p)
                                  (block-access-list-rlp nil
                                   block-access-list-rlp-supplied-p))
  (multiple-value-bind (block-access-list block-access-list-supplied-p
                        encoded-block-access-list)
      (normalize-execution-block-access-list-input
       block-access-list block-access-list-supplied-p
       block-access-list-rlp block-access-list-rlp-supplied-p)
    (let* ((max-blob-gas
             (execution-max-blob-gas chain-rules
                                     chain-config
                                     (block-header-number header)
                                     (block-header-timestamp header)))
           (block-access-list-max-code-size
             (execution-block-access-list-max-code-size
              chain-rules
              chain-config
              (block-header-number header)
              (block-header-timestamp header)))
           (actual-blob-gas-used
            (validate-block-body-commitments-before-execution
             transactions header
             :ommers ommers
             :withdrawals withdrawals
             :withdrawals-supplied-p withdrawals-supplied-p
             :requests requests
             :requests-supplied-p requests-supplied-p
             :block-access-list block-access-list
             :block-access-list-supplied-p block-access-list-supplied-p
             :encoded-block-access-list encoded-block-access-list
             :max-blob-gas max-blob-gas
             :block-access-list-max-code-size
             block-access-list-max-code-size)))
    (validate-block-fork-body-shape-before-execution
     header chain-config
     :withdrawals-supplied-p withdrawals-supplied-p
     :requests-supplied-p requests-supplied-p
     :block-access-list-supplied-p block-access-list-supplied-p
     :max-blob-gas max-blob-gas)
    (let ((snapshot (state-db-copy state))
          (header-snapshot (copy-block-header-for-execution header)))
      (handler-case
          (multiple-value-bind (receipts gas-used)
              (apply-message-list
               state sender transactions
               :base-fee (or (block-header-base-fee-per-gas header) 0)
               :blob-base-fee
               (execution-block-blob-base-fee header chain-rules chain-config)
               :chain-rules chain-rules
               :chain-config chain-config
               :coinbase (or (block-header-beneficiary header) (zero-address))
               :timestamp (block-header-timestamp header)
               :block-number (block-header-number header)
               :prev-randao (or (block-header-mix-hash header) (zero-hash32))
               :difficulty (block-header-difficulty header)
               :random-p (block-header-post-merge-p header)
               :context-gas-limit (block-header-gas-limit header)
               :block-gas-limit
               (when (plusp (block-header-gas-limit header))
                 (block-header-gas-limit header)))
            (when withdrawals-supplied-p
              (apply-withdrawals state withdrawals))
            (when apply-block-rewards-p
              (let ((rules (execution-chain-rules chain-rules chain-config
                                                  (block-header-number header)
                                                  (block-header-timestamp
                                                   header))))
                (apply-block-rewards-for-header state header ommers rules)))
            (when (or (plusp actual-blob-gas-used)
                      (block-header-blob-gas-used header)
                      (block-header-excess-blob-gas header))
              (setf (block-header-blob-gas-used header) actual-blob-gas-used)
              (unless (block-header-excess-blob-gas header)
                (setf (block-header-excess-blob-gas header) 0)))
            (validate-supplied-block-execution-roots
             header transactions receipts (state-db-root state))
            (setf (block-header-state-root header) (state-db-root state)
                  (block-header-gas-used header) gas-used)
            (values
             (apply #'make-block
                    (append (list :header header
                                  :transactions transactions
                                  :ommers ommers
                                  :receipts receipts)
                            (when withdrawals-supplied-p
                              (list :withdrawals withdrawals))
                            (when requests-supplied-p
                              (list :requests requests))
                            (when block-access-list-supplied-p
                              (if encoded-block-access-list
                                  (list :block-access-list-rlp
                                        encoded-block-access-list)
                                  (list :block-access-list block-access-list)))))
             receipts))
        (error (condition)
          (state-db-restore state snapshot)
          (restore-block-header-for-execution header header-snapshot)
          (error condition)))))))

(defun execute-and-commit-signed-block
    (store state transactions
     &key expected-chain-id
          (header (make-block-header))
          chain-rules
          chain-config
          (apply-block-rewards-p nil)
          (ommers '())
          (withdrawals nil withdrawals-supplied-p)
          (requests nil requests-supplied-p)
          (block-access-list nil block-access-list-supplied-p)
          (block-access-list-rlp nil block-access-list-rlp-supplied-p)
          (state-available-p t))
  (execute-and-commit-block
   store
   state
   (lambda ()
     (apply
      #'execute-signed-block
      state
      transactions
      (append
       (list :expected-chain-id expected-chain-id
             :header header
             :chain-rules chain-rules
             :chain-config chain-config
             :apply-block-rewards-p apply-block-rewards-p
             :ommers ommers)
       (when withdrawals-supplied-p
         (list :withdrawals withdrawals))
       (when requests-supplied-p
         (list :requests requests))
       (when block-access-list-supplied-p
         (list :block-access-list block-access-list))
       (when block-access-list-rlp-supplied-p
         (list :block-access-list-rlp block-access-list-rlp)))))
   :state-available-p state-available-p))

(defun execute-atomic-block-commit (store state thunk)
  (let ((state-snapshot (state-db-copy state)))
    (chain-store-atomic-commit
     store
     (lambda ()
       (handler-case
           (funcall thunk)
         (error (condition)
           (state-db-restore state state-snapshot)
           (error condition)))))))

(defun commit-state-db-to-chain-store (store block-hash state)
  (state-db-for-each-account
   state
   (lambda (address account code storage-entries)
     (chain-store-put-account-balance
      store block-hash address (state-account-balance account))
     (chain-store-put-account-nonce
      store block-hash address (state-account-nonce account))
     (chain-store-put-account-code store block-hash address code)
     (dolist (entry storage-entries)
        (chain-store-put-account-storage
         store block-hash address (car entry) (cdr entry)))))
  store)

(defun chain-store-state-db (store block-hash)
  (when (chain-store-state-available-p store block-hash)
    (let ((state (make-state-db)))
      (chain-store-for-each-account
       store
       block-hash
       (lambda (address balance nonce code storage-entries)
         (state-db-set-account
          state address
          (make-state-account :nonce nonce :balance balance))
         (when (plusp (length code))
           (state-db-set-code state address code))
         (dolist (entry storage-entries)
           (state-db-set-storage state address (car entry) (cdr entry)))))
      state)))

(defun execute-and-commit-engine-payload
    (store block config &key (state-available-p t))
  (let* ((header (block-header block))
         (number (block-header-number header))
         (parent-hash (block-header-parent-hash header))
         (state (if (plusp number)
                    (chain-store-state-db store parent-hash)
                    (make-state-db))))
    (unless state
      (error 'block-validation-error
             :message "Engine payload parent state is unavailable"))
    (apply
     #'execute-and-commit-signed-block
     store
     state
     (block-transactions block)
     (append
      (list :expected-chain-id (chain-config-chain-id config)
            :header header
            :chain-config config
            :ommers (block-ommers block)
            :state-available-p state-available-p)
      (when (block-withdrawals-present-p block)
        (list :withdrawals (block-withdrawals block)))
      (when (block-requests-present-p block)
        (list :requests (block-requests block)))
      (when (block-block-access-list-present-p block)
        (list :block-access-list (block-block-access-list block)))))))

(defun execute-and-commit-block
    (store state executor &key (state-available-p t))
  (execute-atomic-block-commit
   store
   state
   (lambda ()
     (multiple-value-bind (block receipts)
         (funcall executor)
       (chain-store-put-block store block
                              :state-available-p state-available-p)
       (when state-available-p
         (commit-state-db-to-chain-store store (block-hash block) state))
       (values block receipts)))))

(defun execute-signed-block (state transactions
                             &key expected-chain-id
                                  (header (make-block-header))
                                  chain-rules
                                  chain-config
                                  (apply-block-rewards-p nil)
                                  (ommers '())
                                  (withdrawals nil withdrawals-supplied-p)
                                  (requests nil requests-supplied-p)
                                  (block-access-list nil
                                   block-access-list-supplied-p)
                                  (block-access-list-rlp nil
                                   block-access-list-rlp-supplied-p))
  "Execute a block by recovering each transaction sender from its signature."
  (multiple-value-bind (block-access-list block-access-list-supplied-p
                        encoded-block-access-list)
      (normalize-execution-block-access-list-input
       block-access-list block-access-list-supplied-p
       block-access-list-rlp block-access-list-rlp-supplied-p)
    (let* ((max-blob-gas
             (execution-max-blob-gas chain-rules
                                     chain-config
                                     (block-header-number header)
                                     (block-header-timestamp header)))
           (block-access-list-max-code-size
             (execution-block-access-list-max-code-size
              chain-rules
              chain-config
              (block-header-number header)
              (block-header-timestamp header)))
           (actual-blob-gas-used
            (validate-block-body-commitments-before-execution
             transactions header
             :ommers ommers
             :withdrawals withdrawals
             :withdrawals-supplied-p withdrawals-supplied-p
             :requests requests
             :requests-supplied-p requests-supplied-p
             :block-access-list block-access-list
             :block-access-list-supplied-p block-access-list-supplied-p
             :encoded-block-access-list encoded-block-access-list
             :max-blob-gas max-blob-gas
             :block-access-list-max-code-size
             block-access-list-max-code-size)))
    (validate-block-fork-body-shape-before-execution
     header chain-config
     :withdrawals-supplied-p withdrawals-supplied-p
     :requests-supplied-p requests-supplied-p
     :block-access-list-supplied-p block-access-list-supplied-p
     :max-blob-gas max-blob-gas)
    (let ((snapshot (state-db-copy state))
          (header-snapshot (copy-block-header-for-execution header)))
      (handler-case
          (multiple-value-bind (receipts gas-used)
              (apply-signed-message-list
               state transactions
               :expected-chain-id expected-chain-id
               :base-fee (or (block-header-base-fee-per-gas header) 0)
               :blob-base-fee
               (execution-block-blob-base-fee header chain-rules chain-config)
               :chain-rules chain-rules
               :chain-config chain-config
               :coinbase (or (block-header-beneficiary header) (zero-address))
               :timestamp (block-header-timestamp header)
               :block-number (block-header-number header)
               :prev-randao (or (block-header-mix-hash header) (zero-hash32))
               :difficulty (block-header-difficulty header)
               :random-p (block-header-post-merge-p header)
               :context-gas-limit (block-header-gas-limit header)
               :block-gas-limit
               (when (plusp (block-header-gas-limit header))
                 (block-header-gas-limit header)))
            (when withdrawals-supplied-p
              (apply-withdrawals state withdrawals))
            (when apply-block-rewards-p
              (let ((rules (execution-chain-rules chain-rules chain-config
                                                  (block-header-number header)
                                                  (block-header-timestamp
                                                   header))))
                (apply-block-rewards-for-header state header ommers rules)))
            (when (or (plusp actual-blob-gas-used)
                      (block-header-blob-gas-used header)
                      (block-header-excess-blob-gas header))
              (setf (block-header-blob-gas-used header) actual-blob-gas-used)
              (unless (block-header-excess-blob-gas header)
                (setf (block-header-excess-blob-gas header) 0)))
            (validate-supplied-block-execution-roots
             header transactions receipts (state-db-root state))
            (setf (block-header-state-root header) (state-db-root state)
                  (block-header-gas-used header) gas-used)
            (values
             (apply #'make-block
                    (append (list :header header
                                  :transactions transactions
                                  :ommers ommers
                                  :receipts receipts)
                            (when withdrawals-supplied-p
                              (list :withdrawals withdrawals))
                            (when requests-supplied-p
                              (list :requests requests))
                            (when block-access-list-supplied-p
                              (if encoded-block-access-list
                                  (list :block-access-list-rlp
                                        encoded-block-access-list)
                                  (list :block-access-list block-access-list)))))
             receipts))
        (error (condition)
          (state-db-restore state snapshot)
          (restore-block-header-for-execution header header-snapshot)
          (error condition)))))))
