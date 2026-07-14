(in-package #:ethereum-lisp.consensus)

;;;; Block body commitment validation against header roots.

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
    ;; Requests and block access lists are side data committed by the header,
    ;; not canonical block-body fields.  Validate them when available without
    ;; making generic body decoding depend on their presence.
    (when (block-requests-present-p block)
      (unless (and (block-header-requests-hash header)
                   (hash32= (execution-requests-hash (block-requests block))
                            (block-header-requests-hash header)))
        (block-validation-fail "Execution requests hash mismatch")))
    (when (block-block-access-list-present-p block)
      (unless (and
               (block-header-block-access-list-hash header)
               (hash32= (validated-block-access-list-commitment
                         block
                         :max-code-size block-access-list-max-code-size
                         :max-items
                         (when (plusp (block-header-gas-limit header))
                           (floor (block-header-gas-limit header)
                                  +block-access-list-item-gas-cost+)))
                        (block-header-block-access-list-hash header)))
        (block-validation-fail "Block access list hash mismatch")))
    (cond
      ((block-header-blob-gas-used header)
       (unless (= blob-gas-used (block-header-blob-gas-used header))
         (block-validation-fail "Blob gas used mismatch")))
      ((plusp blob-gas-used)
       (block-validation-fail "Blob transactions present before blob gas header")))
    (when (> blob-gas-used max-blob-gas)
      (block-validation-fail "Blob gas used exceeds maximum"))
    t))
