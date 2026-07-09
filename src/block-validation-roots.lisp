(in-package #:ethereum-lisp.core)

(defun validate-block-body-roots
    (block &key (blob-base-fee-update-fraction
                 +blob-base-fee-update-fraction+)
                (max-blob-gas
                 (* +max-blobs-per-block+ +blob-gas-per-blob+))
                block-access-list-max-code-size)
  (let* ((header (block-header block))
         (ommers (block-ommers block))
         (ommers-root nil)
         (transactions (block-transactions block))
         (transactions-root nil)
         (blob-gas-used nil)
         (base-fee (block-header-base-fee-per-gas header))
         (blob-base-fee (when (block-header-excess-blob-gas header)
                          (block-header-blob-base-fee
                           header
                           :update-fraction
                           blob-base-fee-update-fraction))))
    (validate-block-body-commitment-fields header)
    (validate-block-ommer-list-fields ommers)
    (setf ommers-root (ommers-hash ommers))
    (validate-block-transaction-list-fields transactions)
    (setf blob-gas-used (blob-gas-used transactions))
    (dolist (transaction transactions)
      (validate-transaction-recipient-field transaction)
      (validate-transaction-data-field transaction)
      (validate-transaction-scalar-fields transaction)
      (validate-transaction-signature-fields transaction)
      (validate-access-list-fields transaction)
      (validate-set-code-transaction-fields transaction)
      (when base-fee
        (validate-1559-transaction-fees transaction base-fee))
      (when (typep transaction 'blob-transaction)
        (validate-blob-transaction-fields transaction)
        (when blob-base-fee
          (validate-blob-transaction-fee-cap transaction blob-base-fee))))
    (setf transactions-root (transaction-list-root transactions))
    (when (block-withdrawals-present-p block)
      (validate-withdrawal-list-fields (block-withdrawals block)))
    (when (block-requests-present-p block)
      (validate-execution-request-list-fields (block-requests block)))
    (when (block-block-access-list-present-p block)
      (validated-block-access-list-commitment
       block
       :max-code-size block-access-list-max-code-size
       :max-items (when (plusp (block-header-gas-limit header))
                    (floor (block-header-gas-limit header)
                           +block-access-list-item-gas-cost+))))
    (unless (hash32= ommers-root (block-header-ommers-hash header))
      (block-validation-fail "Ommers root hash mismatch"))
    (when (and (block-header-post-merge-p header)
               ommers)
      (block-validation-fail "Post-Merge blocks cannot contain ommers"))
    (unless (hash32= transactions-root
                     (block-header-transactions-root header))
      (block-validation-fail "Transaction root hash mismatch"))
    (cond
      ((block-header-withdrawals-root header)
       (unless (block-withdrawals-present-p block)
         (block-validation-fail "Missing withdrawals in block body"))
       (unless (hash32= (withdrawal-list-root (block-withdrawals block))
                        (block-header-withdrawals-root header))
         (block-validation-fail "Withdrawals root hash mismatch")))
      ((block-withdrawals-present-p block)
       (block-validation-fail "Withdrawals present before withdrawals root")))
    (cond
      ((block-header-requests-hash header)
       (unless (block-requests-present-p block)
         (block-validation-fail "Missing execution requests in block body"))
       (unless (hash32= (execution-requests-hash (block-requests block))
                        (block-header-requests-hash header))
         (block-validation-fail "Execution requests hash mismatch")))
      ((block-requests-present-p block)
       (block-validation-fail "Execution requests present before requests hash")))
    (cond
      ((block-header-block-access-list-hash header)
       (unless (block-block-access-list-present-p block)
         (block-validation-fail "Missing block access list in block body"))
       (unless (hash32= (validated-block-access-list-commitment
                         block
                         :max-code-size block-access-list-max-code-size
                         :max-items
                         (when (plusp (block-header-gas-limit header))
                           (floor (block-header-gas-limit header)
                                  +block-access-list-item-gas-cost+)))
                        (block-header-block-access-list-hash header))
         (block-validation-fail "Block access list hash mismatch")))
      ((block-block-access-list-present-p block)
       (block-validation-fail
        "Block access list present before block access list hash")))
    (cond
      ((block-header-blob-gas-used header)
       (unless (= blob-gas-used (block-header-blob-gas-used header))
         (block-validation-fail "Blob gas used mismatch")))
      ((plusp blob-gas-used)
       (block-validation-fail "Blob transactions present before blob gas header")))
    (when (> blob-gas-used max-blob-gas)
      (block-validation-fail "Blob gas used exceeds maximum"))
    t))

(defun receipts-gas-used (receipts)
  (if receipts
      (receipt-cumulative-gas-used (car (last receipts)))
      0))

(defun validate-block-execution-commitment-fields (header state-root)
  (unless (uint256-p (block-header-gas-used header))
    (block-validation-fail "Header gas used must be uint256"))
  (validate-sized-byte-vector (block-header-logs-bloom header)
                              256
                              "Header logs bloom")
  (unless (hash32-p (block-header-receipts-root header))
    (block-validation-fail "Header receipts root must be a hash32"))
  (unless (hash32-p (block-header-state-root header))
    (block-validation-fail "Header state root must be a hash32"))
  (unless (hash32-p state-root)
    (block-validation-fail "Computed state root must be a hash32"))
  t)

(defun validate-log-topic-field (topic)
  (handler-case
      (progn
        (topic-bytes topic)
        t)
    (error ()
      (block-validation-fail "Log topic must be a hash32 or 32-byte value"))))

(defun validate-log-entry-fields (log)
  (unless (log-entry-p log)
    (block-validation-fail "Receipt log must be a log entry"))
  (unless (address-p (log-entry-address log))
    (block-validation-fail "Receipt log address must be an address"))
  (unless (listp (log-entry-topics log))
    (block-validation-fail "Receipt log topics must be a list"))
  (dolist (topic (log-entry-topics log))
    (validate-log-topic-field topic))
  (handler-case
      (progn
        (ensure-byte-vector (log-entry-data log))
        t)
    (error ()
      (block-validation-fail "Receipt log data must be a byte sequence"))))

(defun validate-receipt-fields (receipt)
  (unless (receipt-p receipt)
    (block-validation-fail "Block receipt must be a receipt"))
  (if (receipt-post-state receipt)
      (validate-sized-byte-vector (receipt-post-state receipt)
                                  32
                                  "Receipt post-state")
      (unless (member (receipt-status receipt) '(0 1))
        (block-validation-fail "Receipt status must be 0 or 1")))
  (unless (uint64-value-p (receipt-cumulative-gas-used receipt))
    (block-validation-fail "Receipt cumulative gas used must be uint64"))
  (unless (listp (receipt-logs receipt))
    (block-validation-fail "Receipt logs must be a list"))
  (dolist (log (receipt-logs receipt) t)
    (validate-log-entry-fields log)))

(defun validate-receipt-list-fields (receipts)
  (unless (listp receipts)
    (block-validation-fail "Block receipts must be a list"))
  (let ((previous-gas-used nil))
    (dolist (receipt receipts t)
      (validate-receipt-fields receipt)
      (let ((gas-used (receipt-cumulative-gas-used receipt)))
        (when (and previous-gas-used (<= gas-used previous-gas-used))
          (block-validation-fail
           "Receipt cumulative gas used must increase"))
        (setf previous-gas-used gas-used)))))

(defun validate-block-execution-receipt-fork-semantics
    (header chain-config)
  (when chain-config
    (unless (chain-config-byzantium-p chain-config
                                      (block-header-number header))
      (block-validation-fail
       "Pre-Byzantium receipt roots are outside Phase A scope"))))

(defun validate-block-execution-roots
    (block receipts state-root &key
       (transactions nil transactions-supplied-p)
       chain-config)
  (let ((header (block-header block)))
    (validate-block-execution-commitment-fields header state-root)
    (validate-block-execution-receipt-fork-semantics header chain-config)
    (validate-receipt-list-fields receipts)
    (when transactions-supplied-p
      (validate-block-transaction-list-fields transactions))
    (let* ((gas-used (receipts-gas-used receipts))
           (logs-bloom (bloom-bytes (receipts-logs-bloom receipts)))
           (receipts-root (if transactions-supplied-p
                              (transaction-receipt-list-root transactions
                                                             receipts)
                              (receipt-list-root receipts))))
      (unless (= gas-used (block-header-gas-used header))
        (block-validation-fail "Gas used mismatch"))
      (unless (and (block-header-logs-bloom header)
                   (bytes= logs-bloom (block-header-logs-bloom header)))
        (block-validation-fail "Logs bloom mismatch"))
      (unless (hash32= receipts-root (block-header-receipts-root header))
        (block-validation-fail "Receipts root mismatch"))
      (unless (hash32= state-root (block-header-state-root header))
        (block-validation-fail "State root mismatch")))
    t))
