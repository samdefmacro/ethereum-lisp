(in-package #:ethereum-lisp.consensus)

(defun validate-withdrawal-fields (withdrawal)
  (unless (uint256-p (withdrawal-index withdrawal))
    (block-validation-fail "Withdrawal index must be uint256"))
  (unless (uint256-p (withdrawal-validator-index withdrawal))
    (block-validation-fail "Withdrawal validator index must be uint256"))
  (unless (address-p (withdrawal-address withdrawal))
    (block-validation-fail "Withdrawal address must be an address"))
  (unless (uint256-p (withdrawal-amount withdrawal))
    (block-validation-fail "Withdrawal amount must be uint256"))
  t)

(defun validate-withdrawal-list-fields (withdrawals)
  (unless (listp withdrawals)
    (block-validation-fail "Withdrawals must be a list"))
  (dolist (withdrawal withdrawals t)
    (validate-withdrawal-fields withdrawal)))

(defun transaction-object-p (value)
  (typep value
         '(or legacy-transaction
              access-list-transaction
              dynamic-fee-transaction
              blob-transaction
              set-code-transaction)))

(defun validate-block-transaction-list-fields (transactions)
  (unless (listp transactions)
    (block-validation-fail "Block transactions must be a list"))
  (dolist (transaction transactions t)
    (unless (transaction-object-p transaction)
      (block-validation-fail "Block transaction must be a transaction"))))

(defun validate-block-ommer-list-fields (ommers)
  (unless (listp ommers)
    (block-validation-fail "Block ommers must be a list"))
  (dolist (ommer ommers t)
    (unless (block-header-p ommer)
      (block-validation-fail "Block ommer must be a block header"))))

(defun validate-block-body-commitment-fields (header)
  (unless (hash32-p (block-header-ommers-hash header))
    (block-validation-fail "Header ommers hash must be a hash32"))
  (unless (hash32-p (block-header-transactions-root header))
    (block-validation-fail "Header transactions root must be a hash32"))
  (when (block-header-withdrawals-root header)
    (unless (hash32-p (block-header-withdrawals-root header))
      (block-validation-fail "Header withdrawals root must be a hash32")))
  (when (block-header-requests-hash header)
    (unless (hash32-p (block-header-requests-hash header))
      (block-validation-fail "Header requests hash must be a hash32")))
  (when (block-header-block-access-list-hash header)
    (unless (hash32-p (block-header-block-access-list-hash header))
      (block-validation-fail
       "Header block access list hash must be a hash32")))
  t)

(defun transaction-blob-count (transaction)
  (typecase transaction
    (blob-transaction
     (length (blob-transaction-blob-versioned-hashes transaction)))
    (t 0)))

(defun blob-gas-used (transactions)
  (* +blob-gas-per-blob+
     (loop for transaction in transactions
           sum (transaction-blob-count transaction))))

(defun validate-block-transactions-against-config (block config)
  (let* ((header (block-header block))
         (number (block-header-number header))
         (timestamp (block-header-timestamp header))
         (osaka-p (chain-config-osaka-p config number timestamp)))
    (validate-block-transaction-list-fields (block-transactions block))
    (dolist (transaction (block-transactions block) t)
      (validate-transaction-type-for-config
       transaction config number timestamp)
      (when (and osaka-p
                 (> (transaction-gas-limit transaction)
                    +transaction-gas-limit-cap-eip7825+))
        (block-validation-fail
         "Transaction gas limit exceeds the EIP-7825 cap")))))

(defun validate-block-body-against-config (block config)
  (let* ((header (block-header block))
         (number (block-header-number header))
         (timestamp (block-header-timestamp header))
         (block-access-list-max-code-size
           (if (chain-config-amsterdam-p config number timestamp)
               +block-access-list-amsterdam-max-code-size+
               +block-access-list-max-code-size+)))
    (when (and (chain-config-osaka-p config number timestamp)
               (> (length (block-rlp block))
                  +max-rlp-block-size-eip7934+))
      (block-validation-fail "Block RLP size exceeds the EIP-7934 cap"))
    (multiple-value-bind (target-blob-gas max-blob-gas update-fraction)
        (chain-config-blob-schedule config number timestamp)
      (declare (ignore target-blob-gas))
      (validate-block-transactions-against-config block config)
      (validate-block-body-roots block
                                 :blob-base-fee-update-fraction
                                 update-fraction
                                 :max-blob-gas max-blob-gas
                                 :max-blobs-per-transaction
                                 (if (chain-config-osaka-p config number
                                                           timestamp)
                                     +max-blobs-per-transaction-eip7594+
                                     (floor max-blob-gas +blob-gas-per-blob+))
                                 :block-access-list-max-code-size
                                 block-access-list-max-code-size))))

(defun validate-block-against-config (parent-header block config)
  (validate-block-header-against-config parent-header (block-header block)
                                        config)
  (validate-block-body-against-config block config))
