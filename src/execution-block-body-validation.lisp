(in-package #:ethereum-lisp.execution)

;;;; Block body commitment and post-execution root checks.

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
    ;; Execution requests are Engine side data derived from execution, not a
    ;; canonical block-body field.  When supplied by newPayload, validate the
    ;; early commitment; canonical block imports may omit them and are checked
    ;; against the derived requests after execution.
    (when requests-supplied-p
      (validate-execution-request-list-fields requests)
      (unless (and (block-header-requests-hash header)
                   (execution-hash32=
                    (block-header-requests-hash header)
                    (execution-requests-hash requests)))
        (error 'block-validation-error
               :message "Execution requests hash mismatch")))
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
